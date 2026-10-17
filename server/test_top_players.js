/**
 * 플레이량 Top 10 은 완주한 판만 센다.
 *
 * 탈주로 중단된 판은 누구에게도 한 판이 아니다. 그걸 섞어 세면 중간에
 * 자주 나가는 사람이 위로 올라와서, 이 표가 보려던 것과 반대가 된다.
 *
 * 숫자가 틀려도 표는 멀쩡해 보이는 종류의 버그라 테스트로 묶는다 —
 * 7판 둔 사람이 9판으로 보이는 걸 눈으로는 알 수 없다.
 *
 * 기간은 '오늘'을 쓴다. 이 테스트가 심는 판만 오늘 자로 들어가므로,
 * 다른 데이터가 섞인 DB 에서도 비교 대상이 맞는다.
 *
 * Run: node server/test_top_players.js
 */
const db = require('./db/database.js');

let failures = 0;
const check = (label, cond, detail = '') => {
  console.log(`${cond ? '  ok  ' : '  FAIL'} ${label}${!cond && detail ? ` — ${detail}` : ''}`);
  if (!cond) failures++;
};
const eq = (label, got, want) =>
  check(label, got === want, `got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);

const run = Date.now().toString(36).slice(-5);
const nick = (s) => `탑${run}_${s}`;
const P = db.pool;
const NOW = `(NOW() AT TIME ZONE 'UTC')`;

async function makeUser(name) {
  await P.query(
    `INSERT INTO tc_users (username, nickname, gold) VALUES ($1, $2, 0)
     ON CONFLICT (nickname) DO NOTHING`,
    [`top_${run}_${name}`, nick(name)],
  );
}

/// 티츄 한 판. endReason 'normal' 이면 완주, 'leave'/'timeout' 이면 중단.
async function tichuMatch(players, endReason = 'normal', deserter = null) {
  const [a1, a2, b1, b2] = players.map(nick);
  await P.query(
    `INSERT INTO tc_match_history
       (winner_team, team_a_score, team_b_score, player_a1, player_a2,
        player_b1, player_b2, is_ranked, end_reason, deserter_nickname, created_at)
     VALUES ('A', 1000, 500, $1, $2, $3, $4, FALSE, $5, $6, ${NOW})`,
    [a1, a2, b1, b2, endReason, deserter ? nick(deserter) : null],
  );
}

/// 이 테스트가 심은 스컬킹 판 id. 정리할 때 이것만 지운다.
const skIds = [];

/// 스컬킹 한 판.
async function skMatch(players, endReason = 'normal') {
  const { rows } = await P.query(
    `INSERT INTO tc_sk_match_history (player_count, is_ranked, end_reason, created_at)
     VALUES ($1, FALSE, $2, ${NOW}) RETURNING id`,
    [players.length, endReason],
  );
  const id = rows[0].id;
  skIds.push(id);
  for (let i = 0; i < players.length; i++) {
    await P.query(
      `INSERT INTO tc_sk_match_players (match_id, nickname, score, rank, is_winner, is_bot)
       VALUES ($1, $2, $3, $4, $5, FALSE)`,
      [id, nick(players[i]), 100 - i, i + 1, i === 0],
    );
  }
}

async function cleanup() {
  const like = `탑${run}_%`;
  if (skIds.length) {
    await P.query(`DELETE FROM tc_sk_match_players WHERE match_id = ANY($1::int[])`, [skIds]);
    await P.query(`DELETE FROM tc_sk_match_history WHERE id = ANY($1::int[])`, [skIds]);
  }
  await P.query(
    `DELETE FROM tc_match_history WHERE player_a1 LIKE $1`, [like]);
  await P.query(`DELETE FROM tc_users WHERE nickname LIKE $1`, [like]);
}

(async () => {
  await db.initDatabase();
  const names = ['완주왕', '탈주왕', '동료1', '동료2', '동료3'];
  for (const n of names) await makeUser(n);

  // 완주왕: 티츄 완주 5판. 탈주 판은 하나도 없다.
  // 탈주왕: 티츄 완주 2판 + 탈주로 끝난 판 6판 (본인이 나간 3 + 남이 나간 3).
  //
  // 섞어 세면 탈주왕(8)이 완주왕(5)을 이긴다. 완주만 세면 5 대 2 로
  // 뒤집힌다 — 그 뒤집힘이 이 테스트가 지키는 것이다.
  // 둘을 같은 판에 넣지 않는다. 같은 판에 있으면 둘의 숫자가 같아져서
  // 완주/탈주 구분이 아니라 판 수만 보게 된다.
  for (let i = 0; i < 5; i++) await tichuMatch(['완주왕', '동료1', '동료2', '동료3']);
  for (let i = 0; i < 2; i++) await tichuMatch(['탈주왕', '동료1', '동료2', '동료3']);
  // 본인이 나간 판과 남이 나간 판 모두 뺀다 — 어느 쪽도 끝까지 간 판이
  // 아니다.
  for (let i = 0; i < 3; i++) await tichuMatch(['탈주왕', '동료1', '동료2', '동료3'], 'leave', '탈주왕');
  for (let i = 0; i < 3; i++) await tichuMatch(['탈주왕', '동료1', '동료2', '동료3'], 'leave', '동료1');

  // 시간초과 중단도 탈주와 같이 뺀다. 끝까지 간 판이 아니다.
  await tichuMatch(['탈주왕', '동료1', '동료2', '동료3'], 'timeout', '동료2');

  // 스컬킹: 완주 2 + 중단 4. 게임별 열도 같은 기준인지 본다.
  for (let i = 0; i < 2; i++) await skMatch(['완주왕', '동료1', '동료2']);
  for (let i = 0; i < 2; i++) await skMatch(['탈주왕', '동료1', '동료2']);
  for (let i = 0; i < 4; i++) await skMatch(['탈주왕', '동료1', '동료2'], 'leave');

  // 래퍼는 { rows, period, game } 을 돌려준다.
  const { rows } = await db.getDashboardActivityTopPlayers('today', 'all');
  const find = (n) => rows.find((r) => r.nickname === nick(n));
  const kingA = find('완주왕');
  const kingB = find('탈주왕');

  console.log('\n[완주한 판만 센다]');
  check('심은 계정이 오늘 Top 10 에 있다', !!kingA && !!kingB,
    `오늘 더 많이 플레이한 계정이 10개 넘게 있는 DB 라면 이 테스트는 못 돈다. rows=${rows.map(r => r.nickname).join(',')}`);
  if (!kingA || !kingB) { await cleanup(); process.exit(1); }

  eq('완주왕 티츄 = 5 (완주 5)', Number(kingA.tichu_games), 5);
  eq('탈주왕 티츄 = 2 (완주 2, 탈주 6·시간초과 1 제외)', Number(kingB.tichu_games), 2);
  check('탈주 판이 티츄에 섞이지 않았다', Number(kingB.tichu_games) !== 9,
    '탈주 6판·시간초과 1판이 그대로 더해졌다');

  eq('완주왕 SK = 2 (완주 2, 중단 4 제외)', Number(kingA.sk_games), 2);
  eq('탈주왕 SK = 2 (완주 2, 중단 4 제외)', Number(kingB.sk_games), 2);

  eq('완주왕 전체 = 7 (티츄 5 + SK 2)', Number(kingA.activity_games), 7);
  eq('탈주왕 전체 = 4 (티츄 2 + SK 2)', Number(kingB.activity_games), 4);

  console.log('\n[순위가 뒤집힌다]');
  // 완주만 세면 완주왕(7)이 탈주왕(4)보다 위다. 섞어 세면 탈주왕(15)이
  // 위로 올라온다 — 표가 보려던 것과 반대 방향이다.
  const idxA = rows.findIndex((r) => r.nickname === nick('완주왕'));
  const idxB = rows.findIndex((r) => r.nickname === nick('탈주왕'));
  check('완주왕이 탈주왕보다 위', idxA < idxB, `완주왕 ${idxA}위, 탈주왕 ${idxB}위`);

  console.log('\n[게임별 필터도 같은 기준]');
  const tichuOnly = (await db.getDashboardActivityTopPlayers('today', 'tichu')).rows;
  const tB = tichuOnly.find((r) => r.nickname === nick('탈주왕'));
  eq('티츄 필터에서도 탈주왕 = 2', tB ? Number(tB.tichu_games) : null, 2);

  const skOnly = (await db.getDashboardActivityTopPlayers('today', 'skull_king')).rows;
  const sA = skOnly.find((r) => r.nickname === nick('완주왕'));
  eq('SK 필터에서도 완주왕 = 2', sA ? Number(sA.sk_games) : null, 2);

  await cleanup();
  console.log(failures ? `\n${failures} 건 실패` : '\n모두 통과');
  process.exit(failures ? 1 : 0);
})().catch(async (e) => {
  console.error(e);
  try { await cleanup(); } catch { /* 정리 실패는 원인 오류를 덮지 않게 */ }
  process.exit(1);
});
