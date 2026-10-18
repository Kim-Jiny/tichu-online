'use strict';
/**
 * 신고를 사람 기준으로 세는 집계.
 *
 * 기존 신고 목록은 (대상, 방) 단위로 묶여 있어서, 같은 사람이 여러 방에서
 * 신고받으면 행이 흩어진다. 한 방에서 세 번 신고받은 사람과 열 방에서 한
 * 번씩 신고받은 사람은 전혀 다른데, 그 목록만 보면 후자가 더 얌전해 보인다.
 *
 * 받은 신고와 한 신고를 나눠 세는 것도 같이 본다. 받은 수만 보면 시비에
 * 휘말린 사람과 상습 신고자를 구분할 수 없다.
 *
 *   node test_report_counts.js
 */
const db = require('./db/database.js');

let ok = true;
const chk = (n, c, d = '') => {
  console.log(c ? '  ok  ' : '  FAIL', n + (!c && d ? ` — ${d}` : ''));
  if (!c) ok = false;
};
const eq = (n, got, want) =>
  chk(n, got === want, `got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);

const run = Date.now().toString(36).slice(-5);
const nick = (s) => `신고${run}_${s}`;
const P = db.pool;

async function user(name) {
  await P.query(
    `INSERT INTO tc_users (username, nickname, gold) VALUES ($1, $2, 0)
     ON CONFLICT (nickname) DO NOTHING`,
    [`rp_${run}_${name}`, nick(name)],
  );
}

async function report(from, to, { reason = '욕설', room = 'r1', status = 'pending', daysAgo = 0 } = {}) {
  await P.query(
    `INSERT INTO tc_reports
       (reporter_nickname, reported_nickname, reason, room_id, status, created_at)
     VALUES ($1, $2, $3, $4, $5, (NOW() AT TIME ZONE 'UTC') - ($6 || ' days')::interval)
     ON CONFLICT DO NOTHING`,
    [nick(from), nick(to), reason, `${run}_${room}`, status, String(daysAgo)],
  );
}

async function cleanup() {
  const like = `신고${run}_%`;
  await P.query(
    `DELETE FROM tc_reports WHERE reporter_nickname LIKE $1 OR reported_nickname LIKE $1`,
    [like]);
  await P.query('DELETE FROM tc_users WHERE nickname LIKE $1', [like]);
}

(async () => {
  await db.initDatabase();
  for (const n of ['악당', '여러방', '신고쟁이', 'a', 'b', 'c']) await user(n);

  // 악당: 한 방에서 3명에게. 여러방: 세 방에서 1명씩 — 둘 다 3건이지만
  // 방 기준 목록에서는 악당만 "3건" 한 줄로 뭉치고 여러방은 1건씩 흩어진다.
  await report('a', '악당', { room: 'r1', reason: '욕설' });
  await report('b', '악당', { room: 'r1', reason: '욕설' });
  await report('c', '악당', { room: 'r1', reason: '고의 패배', status: 'reviewed' });

  await report('a', '여러방', { room: 'r2' });
  await report('a', '여러방', { room: 'r3' });
  await report('a', '여러방', { room: 'r4' });

  // 신고쟁이: 받은 건 없고 한 건만 많다.
  for (const [i, t] of ['a', 'b', 'c'].entries()) {
    await report('신고쟁이', t, { room: `s${i}` });
  }

  console.log('[유저별 요약]');
  const bad = await db.getUserReportSummary(nick('악당'));
  eq('악당이 받은 신고 3건', bad.received, 3);
  eq('신고한 사람은 3명', bad.reporters, 3);
  eq('미처리 2건', bad.status.pending, 2);
  eq('검토 1건', bad.status.reviewed, 1);
  eq('악당이 한 신고는 0건', bad.made, 0);
  eq('사유는 2종', bad.reasons.length, 2);
  eq('가장 많은 사유는 욕설 2건', `${bad.reasons[0].reason}:${bad.reasons[0].n}`, '욕설:2');

  const snitch = await db.getUserReportSummary(nick('신고쟁이'));
  eq('신고쟁이가 받은 신고 0건', snitch.received, 0);
  eq('신고쟁이가 한 신고 3건', snitch.made, 3);
  chk('받은 수만 보면 둘을 구분할 수 없다 — 그래서 둘 다 센다',
    bad.received !== snitch.received && bad.made !== snitch.made);

  console.log('\n[내역]');
  const rows = await db.getUserReportsReceived(nick('악당'), 20);
  eq('3줄', rows.length, 3);
  chk('최근 것이 위', new Date(rows[0].created_at) >= new Date(rows[2].created_at));
  chk('신고자·사유·방·상태가 들어 있다',
    !!rows[0].reporter_nickname && !!rows[0].reason
      && !!rows[0].room_id && !!rows[0].status,
    JSON.stringify(rows[0]));

  console.log('\n[사람 기준 누적 — 방 기준으로는 안 보이던 것]');
  const top = await db.getTopReportedUsers(50);
  const find = (n) => top.find((r) => r.nickname === nick(n));
  const many = find('여러방');
  chk('여러방이 목록에 있다', !!many, top.map((r) => r.nickname).join(','));
  if (many) {
    eq('여러방도 3건으로 뭉친다', many.reports, 3);
    eq('방은 3곳', many.rooms, 3);
    eq('신고한 사람은 1명', many.reporters, 1);
  }
  const b2 = find('악당');
  if (b2) {
    eq('악당은 1곳에서 3건', b2.rooms, 1);
    eq('악당 미처리 2건', b2.pending, 2);
  }

  console.log('\n[기간을 좁히면 오래된 건이 빠진다]');
  await report('b', '여러방', { room: 'old', daysAgo: 90 });
  const all = (await db.getTopReportedUsers(50)).find((r) => r.nickname === nick('여러방'));
  const recent = (await db.getTopReportedUsers(50, 30)).find((r) => r.nickname === nick('여러방'));
  eq('전체로는 4건', all.reports, 4);
  eq('최근 30일로는 3건', recent.reports, 3);

  console.log('\n[유저 목록의 신고 열과 정렬]');
  // getUsers(search, page, limit, options) — 검색어가 첫 인자다.
  const list = await db.getUsers(`신고${run}_`, 1, 200);
  const byNick = new Map(list.rows.map((r) => [r.nickname, r]));
  eq('목록에 신고 수가 실린다', Number(byNick.get(nick('악당'))?.report_count), 3);
  eq('신고쟁이는 받은 게 없으므로 0', Number(byNick.get(nick('신고쟁이'))?.report_count), 0);
  const sorted = await db.getUsers(`신고${run}_`, 1, 200, { sort: 'reports_desc' });
  const order = sorted.rows.map((r) => Number(r.report_count));
  chk('신고순 정렬이 내림차순', order.every((v, i) => i === 0 || order[i - 1] >= v),
    order.join(','));

  await cleanup();
  console.log(ok ? '\n전부 통과' : '\n실패 있음');
  process.exit(ok ? 0 : 1);
})().catch(async (e) => {
  console.error(e);
  try { await cleanup(); } catch { /* 정리 실패가 원인을 덮지 않게 */ }
  process.exit(1);
});
