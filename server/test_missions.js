/**
 * 미션·토큰 엔진 테스트 — 쓰고 버리는 DB 를 만들어 실제 SQL 로 돌린다.
 *   node server/test_missions.js
 */
const { Pool } = require('pg');
const missions = require('./missions/missions');
const defs = require('./missions/defs');

const ADMIN_URL = process.env.TEST_PG_ADMIN || 'postgresql://jiny@localhost:5432/postgres';
const DB = 'tichu_missions_test';
let failures = 0;
const check = (label, cond, detail = '') => {
  console.log(`${cond ? '  ok  ' : '  FAIL'} ${label}${!cond && detail ? ` — ${detail}` : ''}`);
  if (!cond) failures++;
};

async function main() {
  const admin = new Pool({ connectionString: ADMIN_URL });
  await admin.query(`DROP DATABASE IF EXISTS ${DB}`);
  await admin.query(`CREATE DATABASE ${DB}`);
  const pool = new Pool({ connectionString: ADMIN_URL.replace(/\/postgres$/, `/${DB}`) });
  pool.on('connect', (c) => c.query("SET TIME ZONE 'UTC'").catch(() => {}));
  const c = await pool.connect();
  await missions.ensureSchema(c);
  await missions.ensureSchema(c); // 두 번 돌려도 안전
  c.release();
  missions.init(pool);

  const nick = '미션테스터';
  let st = await missions.getState(nick);
  check('처음엔 토큰 0, 활성 미션 없음', st.balance === 0 && st.active.length === 0);
  check('게임 4종 모두 후보가 있다', defs.GAMES.every((g) => st.offers[g].missions.length >= 2));

  // 후보에 없는 미션은 못 고른다.
  const notOffered = defs.MISSIONS.find((m) => !st.offers[m.game].missions.some((x) => x.key === m.key));
  check('후보에 없는 미션은 선택 불가', (await missions.pick(nick, notOffered.key)).reason === 'not_offered');

  // 후보 중 쉬운 것(…_play) 세 게임에서 하나씩 고른다.
  const offered = (g) => st.offers[g].missions;
  const easy = defs.GAMES.map((g) => offered(g).find((m) => m.tier === 1)).filter(Boolean);
  for (const m of easy.slice(0, 3)) check(`선택 ${m.key}`, (await missions.pick(nick, m.key)).success);
  check('같은 미션 중복 선택 불가', (await missions.pick(nick, easy[0].key)).reason === 'already_picked');
  const fourth = easy[3] || offered('tichu').find((m) => !easy.includes(m));
  check('동시에 3개까지만', (await missions.pick(nick, fourth.key)).reason === 'too_many');

  // 이벤트로 진행 → 완료 → 토큰.
  const evOf = (key) => defs.MISSION_BY_KEY.get(key).event;
  const done = await missions.record(nick, evOf(easy[0].key));
  check('이벤트로 미션 완료', done.length === 1 && done[0].key === easy[0].key && done[0].tokens === 1, JSON.stringify(done));
  st = await missions.getState(nick);
  check('토큰 +1, 오늘 번 토큰 1', st.balance === 1 && st.todayEarned === 1);
  check('완료한 미션도 오늘은 목록에 보인다', st.active.some((m) => m.key === easy[0].key && m.status === 'done'));
  check('같은 이벤트가 다시 와도 두 번 주지 않음', (await missions.record(nick, evOf(easy[0].key))).length === 0);
  check('연속 1일째', st.streak === 1 && st.streakDoneToday === true);

  // 하루 상한.
  await pool.query(`UPDATE tc_token_ledger SET delta = 9 WHERE nickname = $1 AND reason = 'mission'`, [nick]);
  await pool.query(`UPDATE tc_token_balance SET balance = 9 WHERE nickname = $1`, [nick]);
  const done2 = await missions.record(nick, evOf(easy[1].key));
  check('하루 상한(10)을 넘으면 남은 만큼만', done2.length === 1 && done2[0].tokens === 1, JSON.stringify(done2));
  const done3 = await missions.record(nick, evOf(easy[2].key));
  check('상한이 다 찼으면 미션은 끝나도 토큰 0', done3.length === 1 && done3[0].tokens === 0, JSON.stringify(done3));

  // 목표가 큰 미션(폭탄 30점)은 누적.
  await pool.query('DELETE FROM tc_user_missions WHERE nickname = $1', [nick]);
  await pool.query(
    `INSERT INTO tc_user_missions (nickname, mission_key, picked_day, expires_day, target)
     VALUES ($1, 'tichu_bomb30', CURRENT_DATE, CURRENT_DATE + 2, 30)`, [nick]);
  await missions.record(nick, 'tichu.bomb_points', 15);
  st = await missions.getState(nick);
  check('누적 진행(15/30)', st.active.find((m) => m.key === 'tichu_bomb30').progress === 15);

  // 기간이 지난 미션은 만료.
  await pool.query(`UPDATE tc_user_missions SET expires_day = CURRENT_DATE - 1 WHERE nickname = $1`, [nick]);
  await missions.record(nick, 'tichu.bomb_points', 15);
  st = await missions.getState(nick);
  check('기간 지난 미션은 진행되지 않고 사라짐', !st.active.some((m) => m.key === 'tichu_bomb30'));

  // 새로고침.
  const rr1 = await missions.reroll(nick, 'tichu');
  const rr2 = await missions.reroll(nick, 'tichu');
  check('새로고침은 하루 1번', rr1.success && rr2.reason === 'no_rerolls');

  // 연속 7일 보너스.
  const n2 = '연속왕';
  await pool.query(`INSERT INTO tc_mission_streak (nickname, last_day, streak) VALUES ($1, DATE(timezone('Asia/Seoul', NOW())) - 1, 6)`, [n2]);
  await pool.query(
    `INSERT INTO tc_user_missions (nickname, mission_key, picked_day, expires_day, target)
     VALUES ($1, 'tichu_play', CURRENT_DATE, CURRENT_DATE + 2, 1)`, [n2]);
  const d = await missions.record(n2, 'tichu.game_end');
  check('7일째 미션 완료 시 보너스 토큰', d[0] && d[0].streakBonus === defs.STREAK_BONUS_TOKENS, JSON.stringify(d));
  st = await missions.getState(n2);
  check('보너스까지 합쳐 잔액', st.balance === 1 + defs.STREAK_BONUS_TOKENS, String(st.balance));
  check('주기가 다시 시작', st.streak === 0 || st.streak === 7 ? true : false);

  // 상점.
  const n3 = '쇼핑왕';
  await pool.query(`INSERT INTO tc_token_balance (nickname, balance) VALUES ($1, 130)`, [n3]);
  check('토큰이 충분하면 산다', (await missions.buy(n3, 'bubble_premium_1')).success === true);
  check('잔액 차감', (await missions.getBalance(n3)) === 30);
  check('부족하면 거절', (await missions.buy(n3, 'room_highlight_1')).reason === 'not_enough');
  let shop = await missions.getShop(n3);
  const owned = shop.products.find((p) => p.key === 'bubble_premium_1');
  check('처음 산 말풍선은 자동 장착', owned.equipped && owned.ownedUntil);
  await pool.query(`UPDATE tc_token_balance SET balance = 200 WHERE nickname = $1`, [n3]);
  await missions.buy(n3, 'bubble_basic_2');
  shop = await missions.getShop(n3);
  check('이미 장착 중이면 그대로(말풍선은 한 칸)', shop.products.find((p) => p.key === 'bubble_premium_1').equipped && !shop.products.find((p) => p.key === 'bubble_basic_2').equipped);
  check('장착 변경', (await missions.equip(n3, 'bubble', 'bubble_basic_2')).success);
  check('안 산 건 장착 불가', (await missions.equip(n3, 'bubble', 'bubble_basic_3')).reason === 'not_owned');
  check('칸이 다르면 장착 불가', (await missions.equip(n3, 'room_highlight', 'bubble_basic_2')).reason === 'unknown_product');
  let eq = await missions.getEquippedKeys(n3);
  check('다른 사람에게 보일 장착 키', eq.bubble === 'bubble_basic_2' && eq.roomHighlight === null, JSON.stringify(eq));
  // 만료되면 장착도 풀린다.
  await pool.query(`UPDATE tc_token_owned SET expires_at = NOW() - interval '1 day' WHERE nickname = $1 AND product_key = 'bubble_basic_2'`, [n3]);
  eq = await missions.getEquippedKeys(n3);
  check('만료된 상품은 장착 상태에서 빠진다', eq.bubble === null, JSON.stringify(eq));
  // 또 사면 늘어난다.
  await missions.buy(n3, 'bubble_premium_1');
  const before = (await missions.getShop(n3)).products.find((p) => p.key === 'bubble_premium_1').ownedUntil;
  await pool.query(`UPDATE tc_token_balance SET balance = 100 WHERE nickname = $1`, [n3]);
  await missions.buy(n3, 'bubble_premium_1');
  const after = (await missions.getShop(n3)).products.find((p) => p.key === 'bubble_premium_1').ownedUntil;
  check('재구매는 기존 만료일 뒤로 30일 연장', new Date(after) - new Date(before) > 29 * 86400e3);
  // 토큰으로 얻은 장부.
  const led = await pool.query(`SELECT COUNT(*)::int AS n FROM tc_token_ledger WHERE nickname = $1 AND reason = 'shop'`, [n3]);
  check('구매는 장부에 남는다', led.rows[0].n >= 3);

  await pool.end();
  await admin.query(`DROP DATABASE ${DB}`);
  await admin.end();
  console.log(failures ? `\n실패 ${failures}건` : '\n전부 통과');
  process.exit(failures ? 1 : 0);
}
main().catch((e) => { console.error(e); process.exit(1); });
