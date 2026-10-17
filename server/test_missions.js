/**
 * 미션·토큰 엔진 테스트 — 쓰고 버리는 DB 를 만들어 실제 SQL 로 돌린다.
 *   node server/test_missions.js
 */
const { Pool } = require('pg');
const missions = require('./missions/missions');
const defs = require('./missions/defs');

// 날짜 픽스처는 KST 로 넣는다.
//
// 이 테스트는 세션을 UTC 로 고정하고(아래 SET TIME ZONE) 실서버도 UTC 다.
// 그래서 CURRENT_DATE 는 어디서든 UTC 날짜인데, 미션의 하루 경계는 KST 다
// (expireOld / getState / pick 전부 DATE(timezone('Asia/Seoul', NOW()))).
//
// 두 기준이 겹치지 않는 구간 — KST 00~09시(UTC 로는 전날 15~24시) — 에는
// CURRENT_DATE 가 KST 오늘보다 하루 이르다. 그 시간에 돌리면 방금 넣은
// 미션이 expires_day < KST오늘 이 되어 삽입 즉시 'expired' 로 쓸려 나가고,
// getState().active 에서 사라져 테스트가 깨진다. 로컬만의 문제가 아니라
// 매일 그 9시간 동안 어디서 돌려도 깨졌다.
const KST_TODAY = "DATE(timezone('Asia/Seoul', NOW()))";

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
  // 게임마다 후보 하나씩(목표가 커도 이벤트에 amount 를 목표만큼 주면 한 번에 완료된다).
  const easy = defs.GAMES.map((g) => offered(g)[0]).filter(Boolean);
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
  const done = await missions.record(nick, evOf(easy[0].key), easy[0].target);
  check('이벤트로 미션 완료', done.length === 1 && done[0].key === easy[0].key && done[0].tokens === easy[0].tokens, JSON.stringify(done));
  st = await missions.getState(nick);
  check('토큰 지급, 오늘 고른 미션 3개', st.balance === easy[0].tokens && st.picksToday === 3 && st.dailyPicks === 3);
  check('완료한 미션도 오늘은 목록에 보인다', st.active.some((m) => m.key === easy[0].key && m.status === 'done'));
  check('같은 이벤트가 다시 와도 두 번 주지 않음', (await missions.record(nick, evOf(easy[0].key), easy[0].target)).length === 0);
  check('연속 1일째', st.streak === 1 && st.streakDoneToday === true);

  // 하루 토큰 상한은 없다 — 연달아 깨면 깬 만큼 다 받는다.
  await pool.query(`UPDATE tc_token_balance SET balance = 50 WHERE nickname = $1`, [nick]);
  const done2 = await missions.record(nick, evOf(easy[1].key), easy[1].target);
  check('상한 없이 그대로 지급', done2.length === 1 && done2[0].tokens === easy[1].tokens, JSON.stringify(done2));
  check('잔액이 지급만큼 늘었다', (await missions.getBalance(nick)) === 50 + easy[1].tokens);

  // 목표가 큰 미션(폭탄 30점)은 누적.
  await pool.query('DELETE FROM tc_user_missions WHERE nickname = $1', [nick]);
  await pool.query(
    `INSERT INTO tc_user_missions (nickname, mission_key, picked_day, expires_day, target)
     VALUES ($1, 'tichu_bomb50', ${KST_TODAY}, ${KST_TODAY} + 2, 50)`, [nick]);
  await missions.record(nick, 'tichu.bomb_points', 25);
  st = await missions.getState(nick);
  check('누적 진행(25/50)', st.active.find((m) => m.key === 'tichu_bomb50').progress === 25);

  // 기간이 지난 미션은 만료.
  await pool.query(`UPDATE tc_user_missions SET expires_day = ${KST_TODAY} - 1 WHERE nickname = $1`, [nick]);
  await missions.record(nick, 'tichu.bomb_points', 25);
  st = await missions.getState(nick);
  check('기간 지난 미션은 진행되지 않고 사라짐', !st.active.some((m) => m.key === 'tichu_bomb50'));

  // 새로고침.
  const rr1 = await missions.reroll(nick, 'tichu');
  const rr2 = await missions.reroll(nick, 'tichu');
  check('새로고침은 하루 1번', rr1.success && rr2.reason === 'no_rerolls');

  // 연속 7일 보너스.
  const n2 = '연속왕';
  await pool.query(`INSERT INTO tc_mission_streak (nickname, last_day, streak) VALUES ($1, DATE(timezone('Asia/Seoul', NOW())) - 1, 6)`, [n2]);
  await pool.query(
    `INSERT INTO tc_user_missions (nickname, mission_key, picked_day, expires_day, target)
     VALUES ($1, 'tichu_play', ${KST_TODAY}, ${KST_TODAY} + 2, 1)`, [n2]);
  const d = await missions.record(n2, 'tichu.game_end');
  check('7일째 미션 완료 시 보너스 토큰', d[0] && d[0].streakBonus === defs.STREAK_BONUS_TOKENS, JSON.stringify(d));
  st = await missions.getState(n2);
  check('보너스는 5개', defs.STREAK_BONUS_TOKENS === 5);
  check('보너스까지 합쳐 잔액', st.balance === defs.MISSION_BY_KEY.get('tichu_play').tokens + defs.STREAK_BONUS_TOKENS, String(st.balance));
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
  check('보상 조정이 유효 값에 반영', missions.effectiveMission('tichu_play').tokens === 9 && missions.effectiveMission('tichu_play').defaultTokens === defs.MISSION_BY_KEY.get('tichu_play').tokens);
  check('잘못된 보상(음수)은 거절', (await missions.adminSetMission('tichu_play', { enabled: true, tokens: '-1' }, 't')).reason === 'bad_tokens');
  await missions.adminSetProduct('bubble_basic_1', { enabled: true, price: '70' }, 'tester');
  check('가격 조정 반영', missions.effectiveProduct('bubble_basic_1').price === 70);
  await missions.adminSetProduct('bubble_basic_1', { enabled: false, price: '' }, 'tester');
  await pool.query(`UPDATE tc_token_balance SET balance = 300 WHERE nickname = $1`, [n4]);
  check('판매 중지한 상품은 못 산다', (await missions.buy(n4, 'bubble_basic_1')).reason === 'not_for_sale');
  const ov = await missions.adminOverview();
  check('개요가 미션·상품 전부를 낸다', ov.missions.length === defs.MISSIONS.length && ov.products.length === defs.PRODUCTS.length);

  // ── 연속 미션: 지면 0 으로 ──
  const n5 = '연승테스터';
  await pool.query(`INSERT INTO tc_user_missions (nickname, mission_key, picked_day, expires_day, target)
    VALUES ($1, 'tichu_win_streak4', ${KST_TODAY}, ${KST_TODAY}, 4)`, [n5]); // 목표 4 로 직접 넣어 검사한다
  await missions.record(n5, 'tichu.game_win');
  await missions.record(n5, 'tichu.game_win');
  let ss = await missions.getState(n5);
  check('연승 2/4', ss.active.find((m) => m.key === 'tichu_win_streak4').progress === 2);
  await missions.record(n5, 'tichu.game_loss');
  ss = await missions.getState(n5);
  check('지면 0 으로 돌아간다', ss.active.find((m) => m.key === 'tichu_win_streak4').progress === 0);
  for (let i = 0; i < 3; i++) await missions.record(n5, 'tichu.game_win');
  check('3연승까지는 미완료', (await missions.getState(n5)).active.find((m) => m.key === 'tichu_win_streak4').status === 'active');
  const dn = await missions.record(n5, 'tichu.game_win');
  check('목표 연승이면 완료(정의된 보상)', dn.length === 1 && dn[0].tokens === defs.MISSION_BY_KEY.get('tichu_win_streak4').tokens, JSON.stringify(dn));
  check('이미 완료한 연승은 패배로 되돌아가지 않는다', (await missions.record(n5, 'tichu.game_loss')).length === 0 && (await missions.getState(n5)).active.find((m) => m.key === 'tichu_win_streak4').status === 'done');
  // 다른 게임의 패배는 영향 없다.
  await pool.query(`INSERT INTO tc_user_missions (nickname, mission_key, picked_day, expires_day, target)
    VALUES ($1, 'mighty_win_streak4', ${KST_TODAY}, ${KST_TODAY}, 4)`, [n5]);
  await missions.record(n5, 'mighty.game_win');
  await missions.record(n5, 'tichu.game_loss');
  check('다른 게임의 패배는 영향 없음', (await missions.getState(n5)).active.find((m) => m.key === 'mighty_win_streak4').progress === 1);
  // 정의에서 없앤 미션이 DB 에 남아 있어도 상태 조회가 죽지 않는다.
  await pool.query(`INSERT INTO tc_user_missions (nickname, mission_key, picked_day, expires_day, target)
    VALUES ($1, 'removed_old_mission', ${KST_TODAY}, ${KST_TODAY}, 1)`, [n5]);
  const ss2 = await missions.getState(n5);
  check('없앤 미션은 목록에서 빠진다', !ss2.active.some((m) => m.key === 'removed_old_mission'));

  // ── '한 판에' · '한 라운드에' · '연속 원투' 미션은 범위가 끝나면 0 으로 ──
  const n6 = '범위테스터';
  const add = (key, target) => pool.query(`INSERT INTO tc_user_missions (nickname, mission_key, picked_day, expires_day, target)
    VALUES ($1, $2, ${KST_TODAY}, ${KST_TODAY}, $3)`, [n6, key, target]);
  const prog = async (key) => (await missions.getState(n6)).active.find((m) => m.key === key).progress;
  await add('tichu_first_out5', 5); await add('mighty_win5', 5); await add('tichu_onetwo', 2);
  for (let i = 0; i < 3; i++) await missions.record(n6, 'tichu.first_out');
  check('한 판에 1등 3/5', (await prog('tichu_first_out5')) === 3);
  await missions.record(n6, 'tichu.game_end'); // 판이 끝남 → 0
  check('판이 끝나면 한 판 미션은 0 으로', (await prog('tichu_first_out5')) === 0);
  for (let i = 0; i < 4; i++) await missions.record(n6, 'mighty.trick_win');
  check('한 라운드에 트릭 4/5', (await prog('mighty_win5')) === 4);
  await missions.record(n6, 'mighty.round_end');
  check('라운드가 끝나면 0 으로', (await prog('mighty_win5')) === 0);
  await missions.record(n6, 'tichu.one_two');
  check('원투 1/2', (await prog('tichu_onetwo')) === 1);
  await missions.record(n6, 'tichu.round_no_onetwo');
  check('원투를 못 한 라운드가 끼면 처음부터', (await prog('tichu_onetwo')) === 0);
  await missions.record(n6, 'tichu.one_two');
  const two = await missions.record(n6, 'tichu.one_two');
  check('연속 두 번이면 완료', two.length === 1 && two[0].key === 'tichu_onetwo', JSON.stringify(two));

  // 판 시작도 '한 판에' 미션을 0 으로(중간에 끝난 판의 진행이 새지 않게).
  const n7 = '판시작테스터';
  await pool.query(`INSERT INTO tc_user_missions (nickname, mission_key, picked_day, expires_day, target)
    VALUES ($1, 'sk_bid_hit6', ${KST_TODAY}, ${KST_TODAY}, 6), ($1, 'mighty_win5', ${KST_TODAY}, ${KST_TODAY}, 5)`, [n7]);
  await missions.record(n7, 'sk.bid_hit'); await missions.record(n7, 'sk.bid_hit');
  await missions.record(n7, 'mighty.trick_win');
  await missions.record(n7, 'sk.game_start');
  let st7 = await missions.getState(n7);
  check('판 시작이 한 판 미션을 0 으로', st7.active.find((m) => m.key === 'sk_bid_hit6').progress === 0);
  check('다른 게임의 판 시작은 영향 없음', st7.active.find((m) => m.key === 'mighty_win5').progress === 1);
  await missions.record(n7, 'mighty.game_start');
  st7 = await missions.getState(n7);
  check('마이티 판 시작은 한 라운드 미션도 0 으로', st7.active.find((m) => m.key === 'mighty_win5').progress === 0);
  check('resetOn 은 문자열·배열 모두 받는다', defs.MISSIONS.some((m) => typeof m.resetOn === 'string') && defs.MISSIONS.some((m) => Array.isArray(m.resetOn)));

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
