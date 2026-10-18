'use strict';
/**
 * 미션 통계는 만료를 집계 시점에 판정한다.
 *
 * 만료 처리(expireOld)는 그 사용자가 미션을 조회할 때만 돌아간다. 그래서
 * 돌아오지 않는 사람의 못 깬 미션은 기한이 지나도 'active' 로 남는다.
 * 통계는 'active' 를 완료율에서 빼므로, 그 사람의 실패가 사라지고 완료율이
 * 실제보다 높게 나온다 — 깬 사람만 세는 셈이다.
 *
 * 완료 1건 + 기한이 지난 미완료 1건을 심으면 완료율은 50% 여야 한다.
 * 고치기 전에는 100% 였고, 그 사용자가 미션을 한 번 조회하면 그때서야
 * 50% 로 바뀌었다 — 숫자가 "누가 다시 왔는지" 에 따라 달라졌다.
 *
 *   node test_mission_stats_expiry.js
 */
const db = require('./db/database.js');
const missions = require('./missions/missions.js');

let ok = true;
const chk = (n, c, d = '') => {
  console.log(c ? '  ok  ' : '  FAIL', n + (!c && d ? ` — ${d}` : ''));
  if (!c) ok = false;
};
const eq = (n, got, want) => chk(n, got === want, `got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);

const run = Date.now().toString(36).slice(-5);
const NICK = `만료${run}`;
// 실제 미션 키를 써야 한다. adminStats 는 정의(defs.MISSIONS)를 돌면서
// 집계 행을 붙이므로, 정의에 없는 키는 결과에서 사라진다.
const KEY = require('./missions/defs.js').MISSIONS[0].key;
const P = db.pool;

/// picked_day/expires_day 를 손으로 박은 미션 한 건.
///
/// [minutes] 를 주면 고른 때부터 깬 때까지 그만큼 걸린 것으로 심는다.
/// null 을 주면 picked_at 이 없는 '예전 행' 이 된다(컬럼을 추가하기 전에
/// 쌓인 행들).
async function seed({ status, daysAgo, done = false, minutes = 0 }) {
  await P.query(
    `INSERT INTO tc_user_missions
       (nickname, mission_key, picked_day, expires_day, progress, target,
        status, tokens_awarded, picked_at, done_at)
     VALUES ($1, $2,
             DATE(timezone('Asia/Seoul', NOW())) - $3::int,
             DATE(timezone('Asia/Seoul', NOW())) - ($3::int - 1),
             $4, 10, $5, 0,
             CASE WHEN $6::int IS NULL THEN NULL
                  ELSE (NOW() AT TIME ZONE 'UTC') - ($6 || ' minutes')::interval END,
             $7)`,
    [NICK, KEY, String(daysAgo), done ? 10 : 3, status,
     minutes === null ? null : String(minutes),
     done ? new Date().toISOString() : null],
  );
}

async function statsRow() {
  const from = new Date(Date.now() - 30 * 86400000).toISOString();
  const to = new Date(Date.now() + 86400000).toISOString();
  const s = await missions.adminStats(from, to);
  return (s.missions || s.perMission || []).find((m) => m.key === KEY) || null;
}

/// 실제 키를 쓰므로 이 DB 의 기존 행이 섞인다. 절대값이 아니라 증분을
/// 본다 — 그게 이 테스트가 심은 것의 효과다.
function delta(before, after, field) {
  return Number(after[field] || 0) - Number(before[field] || 0);
}

(async () => {
  await db.initDatabase();
  await P.query(
    `INSERT INTO tc_users (username, nickname, gold) VALUES ($1, $2, 0)
     ON CONFLICT (nickname) DO NOTHING`, [`mx_${run}`, NICK]);

  const base = (await statsRow()) || {};

  // 완료 1건, 그리고 기한이 어제 지났는데도 'active' 로 남아 있는 1건.
  // 후자가 "돌아오지 않은 사람" 이다.
  await seed({ status: 'done', daysAgo: 3, done: true });
  await seed({ status: 'active', daysAgo: 3 });

  console.log('[돌아오지 않은 사람의 실패도 센다]');
  const r = await statsRow();
  chk('그 미션이 통계에 있다', !!r, JSON.stringify(r));
  if (r) {
    eq('완료 +1', delta(base, r, 'done'), 1);
    eq('만료 +1 — 저장값은 active 지만 기한이 지났다', delta(base, r, 'expired'), 1);
    eq('진행 중 +0', delta(base, r, 'active'), 0);
  }

  console.log('\n[아직 기한이 남은 건은 진행 중으로 둔다]');
  // 오늘 고른 건은 실패가 아니다. 섞으면 오늘 발행된 미션 때문에 모든
  // 미션의 완료율이 내려간다.
  await seed({ status: 'active', daysAgo: 0 });
  const r2 = await statsRow();
  if (r2) {
    eq('진행 중 +1', delta(base, r2, 'active'), 1);
    eq('만료는 그대로 +1', delta(base, r2, 'expired'), 1);
  }

  console.log('\n[소요 시간은 고른 시각부터 센다]');
  {
    // 자정부터 재던 때는 이 숫자가 "그날 몇 시에 깼나" 였다 — 하루 안에
    // 깬 건은 전부 0~1440분에 들어와서, 미션이 쉬운지 어려운지 알 수
    // 없었다. 이제 picked_at 부터 센다.
    const b = (await statsRow()) || {};
    await seed({ status: 'done', daysAgo: 0, done: true, minutes: 90 });
    const r3 = await statsRow();
    chk('표본이 1건 늘었다', delta(b, r3, 'avgMinutesN') === 1,
      `${b.avgMinutesN} -> ${r3 && r3.avgMinutesN}`);
    chk('90분쯤으로 나온다', Math.abs(Number(r3.avgMinutes) - 90) <= 2,
      `avgMinutes=${r3 && r3.avgMinutes}`);
    chk('음수가 아니다', Number(r3.avgMinutes) > 0, `${r3 && r3.avgMinutes}`);

    // picked_at 이 없는 예전 행은 평균을 끌어당기지 않는다. 모르는 것을
    // picked_day 자정으로 메우면 그게 바로 고치려던 그 숫자가 된다.
    const b2 = await statsRow();
    await seed({ status: 'done', daysAgo: 3, done: true, minutes: null });
    const r4 = await statsRow();
    eq('예전 행은 표본에 안 들어간다', delta(b2, r4, 'avgMinutesN'), 0);
    eq('평균도 그대로', Number(r4.avgMinutes), Number(b2.avgMinutes));
    eq('완료 집계에는 그대로 들어간다', delta(b2, r4, 'done'), 1);
  }

  console.log('\n[저장값을 바꾸지 않는다]');
  // 통계를 보는 것이 사용자 데이터를 쓰는 일이 되어서는 안 된다.
  const stored = await P.query(
    `SELECT COUNT(*)::int AS n FROM tc_user_missions
      WHERE nickname = $1 AND status = 'active'`, [NICK]);
  eq("DB 의 active 행은 2개 그대로", stored.rows[0].n, 2);

  await P.query('DELETE FROM tc_user_missions WHERE nickname = $1', [NICK]);
  await P.query('DELETE FROM tc_users WHERE nickname = $1', [NICK]);
  console.log(ok ? '\n전부 통과' : '\n실패 있음');
  process.exit(ok ? 0 : 1);
})().catch(async (e) => {
  console.error(e);
  try {
    await P.query('DELETE FROM tc_user_missions WHERE nickname = $1', [NICK]);
    await P.query('DELETE FROM tc_users WHERE nickname = $1', [NICK]);
  } catch { /* 정리 실패가 원인을 덮지 않게 */ }
  process.exit(1);
});
