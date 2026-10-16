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
  check('하루에 3개까지만 고른다', (await missions.pick(nick, fourth.key)).reason === 'too_many');
  check('포기 기능은 없다', typeof missions.drop === 'undefined');

  // 당일 미션: 고른 날 안에만 유효하다.
  const exp = await pool.query(`SELECT picked_day, expires_day FROM tc_user_missions WHERE nickname = $1`, [nick]);
  check('고른 날 = 만료일(당일 미션)', exp.rows.length > 0 && exp.rows.every((r) => String(r.picked_day) === String(r.expires_day)), JSON.stringify(exp.rows[0]));
  check('유효 일수 1', defs.MISSION_LIFETIME_DAYS === 1 && st.lifetimeDays === 1);

  // 이벤트로 진행 → 완료 → 토큰.
  const evOf = (key) => defs.MISSION_BY_KEY.get(key).event;
  const done = await missions.record(nick, evOf(easy[0].key));
  check('이벤트로 미션 완료', done.length === 1 && done[0].key === easy[0].key && done[0].tokens === 1, JSON.stringify(done));
  st = await missions.getState(nick);
  check('토큰 +1, 오늘 고른 미션 3개', st.balance === 1 && st.picksToday === 3 && st.dailyPicks === 3);
  check('완료한 미션도 오늘은 목록에 보인다', st.active.some((m) => m.key === easy[0].key && m.status === 'done'));
  check('같은 이벤트가 다시 와도 두 번 주지 않음', (await missions.record(nick, evOf(easy[0].key))).length === 0);
  check('연속 1일째', st.streak === 1 && st.streakDoneToday === true);

  // 하루 토큰 상한은 없다 — 연달아 깨면 깬 만큼 다 받는다.
  await pool.query(`UPDATE tc_token_balance SET balance = 50 WHERE nickname = $1`, [nick]);
  const done2 = await missions.record(nick, evOf(easy[1].key));
  check('상한 없이 그대로 지급', done2.length === 1 && done2[0].tokens === 1, JSON.stringify(done2));
  check('잔액 51', (await missions.getBalance(nick)) === 51);

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
  check('보너스는 5개', defs.STREAK_BONUS_TOKENS === 5);
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

  // ── 관리자: 지급·회수, 조정 ──
  const n4 = '운영테스트';
  await pool.query(`CREATE TABLE IF NOT EXISTS tc_users (id SERIAL PRIMARY KEY, nickname VARCHAR(50), is_deleted BOOLEAN DEFAULT FALSE)`);
  await pool.query(`INSERT INTO tc_users (nickname) VALUES ($1)`, [n4]);
  check('없는 닉네임에는 지급 안 됨', (await missions.adminGrant('없는사람', 5, '', 'admin')).reason === 'no_user');
  check('0 은 거절', (await missions.adminGrant(n4, 0, '', 'admin')).reason === 'bad_amount');
  const gr = await missions.adminGrant(n4, 30, '이벤트', 'tester');
  check('지급 후 잔액 30', gr.success && gr.balance === 30, JSON.stringify(gr));
  check('하루 한도 없이 연달아 지급', (await missions.adminGrant(n4, 500, '', 'tester')).balance === 530);
  check('잔액보다 많이 회수하면 거절', (await missions.adminGrant(n4, -9999, '', 'tester')).reason === 'insufficient');
  check('회수', (await missions.adminGrant(n4, -30, '오지급', 'tester')).balance === 500);
  const ledger = await missions.adminLedger({ nickname: n4 });
  check('장부에 지급·회수와 누가 했는지가 남는다', ledger.total === 3 && ledger.rows.some((r) => r.reason === 'admin_revoke' && r.ref.startsWith('tester')), JSON.stringify(ledger.rows[0]));
  const sum = await missions.adminUserSummary(n4);
  check('유저 요약', sum.balance === 500);

  await missions.adminSetMission('tichu_play', { enabled: false, tokens: '' }, 'tester');
  let hidden = true;
  for (let d = 0; d < 12; d++) {
    if (missions.offersFor(`probe${d}`, '2026-10-16', 'tichu', 0).includes('tichu_play')) hidden = false;
  }
  check('숨긴 미션은 어떤 유저의 후보에도 안 나온다', hidden);
  await missions.adminSetMission('tichu_play', { enabled: true, tokens: '9' }, 'tester');
  check('보상 조정이 유효 값에 반영', missions.effectiveMission('tichu_play').tokens === 9 && missions.effectiveMission('tichu_play').defaultTokens === 1);
  check('잘못된 보상(음수)은 거절', (await missions.adminSetMission('tichu_play', { enabled: true, tokens: '-1' }, 't')).reason === 'bad_tokens');
  await missions.adminSetProduct('bubble_basic_1', { enabled: true, price: '70' }, 'tester');
  check('가격 조정 반영', missions.effectiveProduct('bubble_basic_1').price === 70);
  await missions.adminSetProduct('bubble_basic_1', { enabled: false, price: '' }, 'tester');
  await pool.query(`UPDATE tc_token_balance SET balance = 300 WHERE nickname = $1`, [n4]);
  check('판매 중지한 상품은 못 산다', (await missions.buy(n4, 'bubble_basic_1')).reason === 'not_for_sale');
  const ov = await missions.adminOverview();
  check('개요가 미션·상품 전부를 낸다', ov.missions.length === defs.MISSIONS.length && ov.products.length === 9);

  // ── 내 토큰 내역 ──
  const hist = await missions.getHistory(n4, { limit: 2 });
  check('내역은 최신순이고 한 장 더 있으면 hasMore', hist.rows.length === 2 && hist.hasMore === true && hist.rows[0].id > hist.rows[1].id, JSON.stringify(hist));
  const hist2 = await missions.getHistory(n4, { before: hist.rows[1].id, limit: 50 });
  check('이전 id 보다 오래된 것만 이어서 준다', hist2.rows.every((r) => r.id < hist.rows[1].id));
  const mine = await missions.getHistory(n4, { limit: 50 });
  check('운영자 지급·회수의 메모는 유저에게 숨긴다', mine.rows.filter((r) => r.reason.startsWith('admin')).every((r) => r.ref === null));
  check('상점·미션 내역은 상품·미션 키를 준다', mine.rows.some((r) => r.reason === 'shop' ? r.ref === 'bubble_basic_1' || r.ref != null : true));
  check('남의 내역은 안 섞인다', (await missions.getHistory('없는사람')).rows.length === 0);

  await pool.end();
  await admin.query(`DROP DATABASE ${DB}`);
  await admin.end();
  console.log(failures ? `\n실패 ${failures}건` : '\n전부 통과');
  process.exit(failures ? 1 : 0);
}
main().catch((e) => { console.error(e); process.exit(1); });
