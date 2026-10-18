'use strict';
/**
 * 닉네임을 바꾸면 그 사람의 기록이 전부 따라와야 한다.
 *
 * 닉네임이 키인 표가 마흔 개쯤 된다. 바꿀 때 하나씩 손으로 옮기고 있어서
 * 열세 개가 빠져 있었다. 빠지면 기록이 옛 닉네임에 묶인 채 남는데, 통계가
 * 비는 정도가 아니라 몇 가지는 되돌아간다 — 쓴 쿠폰이 '안 쓴 것' 이 되어
 * 같은 쿠폰을 다시 받을 수 있었다.
 *
 * 그래서 두 가지를 본다:
 *   1) 실제로 옮겨지는가 (한 판 돌려 본다)
 *   2) 스키마에 있는 표를 빠짐없이 다루는가 (새 표가 생기면 여기서 걸린다)
 *
 *   node test_nickname_rename.js
 */
const db = require('./db/database.js');
const missions = require('./missions/missions.js');

let ok = true;
const chk = (n, c, d = '') => {
  console.log(c ? '  ok  ' : '  FAIL', n + (!c && d ? ` — ${d}` : ''));
  if (!c) ok = false;
};

const run = Date.now().toString(36).slice(-4);
const A = `닉변${run}`;
const B = `새닉${run}`;
const P = db.pool;

async function cleanup() {
  const names = [A, B];
  const tables = [
    ...db.RENAME_NICKNAME_TABLES,
    'tc_user_items', 'tc_token_balance', 'tc_token_ledger',
    'tc_token_owned', 'tc_token_equips', 'tc_user_missions',
    'tc_mission_rerolls', 'tc_mission_streak',
  ];
  for (const t of tables) {
    await P.query(`DELETE FROM ${t} WHERE nickname = ANY($1)`, [names]).catch(() => {});
  }
  await P.query('DELETE FROM tc_users WHERE nickname = ANY($1)', [names]).catch(() => {});
}

(async () => {
  await db.initDatabase();
  await cleanup();

  console.log('[스키마에 있는 표를 빠짐없이 다루는가]');
  // 닉네임 컬럼이 있는 표 전부를 긁어, 어딘가에서 옮겨지는지 본다.
  const all = (await P.query(
    `SELECT table_name FROM information_schema.columns
      WHERE column_name = 'nickname' AND table_name LIKE 'tc_%'
      GROUP BY table_name ORDER BY table_name`
  )).rows.map((r) => r.table_name);

  // tc_users 는 기준 표라 따로 바뀐다. 미션 쪽은 missions.renameUser 가 맡는다.
  const MISSIONS = [
    'tc_token_balance', 'tc_token_ledger', 'tc_user_missions',
    'tc_mission_rerolls', 'tc_mission_streak', 'tc_token_owned', 'tc_token_equips',
  ];
  const covered = new Set(['tc_users', ...MISSIONS, ...db.RENAME_NICKNAME_TABLES]);
  // changeNickname 안에 직접 적힌 것들(tc_user_items 등)도 센다.
  const src = require('fs').readFileSync(require('path').join(__dirname, 'db/database.js'), 'utf8');
  const fn = src.slice(src.indexOf('async function changeNickname'));
  const body = fn.slice(0, fn.indexOf('\nasync function '));
  for (const m of body.matchAll(/UPDATE (tc_[a-z_]+) SET nickname/g)) covered.add(m[1]);

  const missed = all.filter((t) => !covered.has(t));
  chk('빠진 표가 없다', missed.length === 0,
    `${missed.join(', ')} — RENAME_NICKNAME_TABLES 에 더해야 한다`);

  console.log('\n[실제로 따라오는가]');
  await P.query(
    `INSERT INTO tc_users (username, nickname, gold) VALUES ($1, $2, 0)
     ON CONFLICT (nickname) DO NOTHING`, [`nk_${run}`, A]);
  await P.query(
    `INSERT INTO tc_user_items (nickname, item_key, expires_at, source)
     VALUES ($1, 'nickname_change', NULL, 'admin')`, [A]);

  // 쿠폰 사용 기록 — 빠지면 같은 쿠폰을 다시 받을 수 있다.
  await P.query(
    `INSERT INTO tc_coupon_redemptions (nickname, code) VALUES ($1, $2)
     ON CONFLICT DO NOTHING`, [A, `TEST${run}`]).catch(() => {});
  // 활동 집계 — 빠지면 과거가 사라진다.
  await P.query(
    `INSERT INTO tc_daily_active (nickname, kst_day, sessions, hours_mask)
     VALUES ($1, DATE(timezone('Asia/Seoul', NOW())), 1, 1)
     ON CONFLICT DO NOTHING`, [A]);
  // 미션 토큰 — 이쪽은 원래도 옮겨졌다. 같이 확인해 둔다.
  await missions.adminGrant(A, 500, 'test', 'tester');

  const r = await db.changeNickname(A, B);
  chk('닉네임이 바뀐다', r.success === true, r.messageKey || '');
  if (!r.success) { await cleanup(); process.exit(1); }

  const count = async (t, n) =>
    (await P.query(`SELECT COUNT(*)::int AS c FROM ${t} WHERE nickname = $1`, [n])
      .catch(() => ({ rows: [{ c: -1 }] }))).rows[0].c;

  chk('쿠폰 사용 기록이 따라온다', await count('tc_coupon_redemptions', B) === 1);
  chk('옛 닉네임에 남지 않는다 — 같은 쿠폰을 다시 받을 수 없다',
    await count('tc_coupon_redemptions', A) === 0);
  chk('활동 집계가 따라온다', await count('tc_daily_active', B) === 1);
  chk('활동 집계가 옛 닉네임에 남지 않는다', await count('tc_daily_active', A) === 0);
  chk('미션 토큰이 따라온다', await missions.getBalance(B) === 500);

  await cleanup();
  console.log(ok ? '\n전부 통과' : '\n실패 있음');
  process.exit(ok ? 0 : 1);
})().catch(async (e) => {
  console.error(e);
  try { await cleanup(); } catch { /* 정리 실패가 원인을 덮지 않게 */ }
  process.exit(1);
});
