/**
 * 리텐션·활동 집계의 산수.
 *
 * 통제된 데이터를 심고 알려진 답과 맞춰 본다. 통계 화면은 숫자가 틀려도
 * 그럴듯해 보이는 게 문제다 — 표가 깨지면 눈에 띄지만, 20% 가 나와야 할
 * 자리에 14% 가 나오면 아무도 모른 채 그 숫자로 판단한다.
 *
 * 특히 "아직 오지 않은 날짜"를 지킨다. 창(window)이 닫히지 않았는데 비율을
 * 내면 최근 코호트가 실제보다 나쁘게 보이고, 그 방향의 오류는 빈 칸이
 * 아니라 그럴듯한 숫자로 나오므로 틀렸다는 것이 보이지 않는다.
 *
 * Run: node server/test_retention.js
 */
const db = require('./db/database.js');

let failures = 0;
const check = (label, cond, detail = '') => {
  console.log(`${cond ? '  ok  ' : '  FAIL'} ${label}${!cond && detail ? ` — ${detail}` : ''}`);
  if (!cond) failures++;
};
const eq = (label, got, want) => check(label, got === want, `got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);

const run = Date.now().toString(36).slice(-5);
const nick = (s) => `리텐${run}_${s}`;
const P = db.pool;

/// 가입일을 [daysAgo] 일 전으로 둔 계정.
async function makeUser(name, daysAgo) {
  await P.query(
    `INSERT INTO tc_users (username, nickname, gold, created_at)
     VALUES ($1, $2, 0, (NOW() AT TIME ZONE 'UTC') - ($3 || ' days')::interval)
     ON CONFLICT (nickname) DO NOTHING`,
    [`rt_${run}_${name}`, nick(name), String(daysAgo)],
  );
}

/// 가입일 + [offset] 일에 접속한 것으로. hour 는 비트마스크로 켠다.
async function visit(name, offset, hour = 0) {
  await P.query(
    `INSERT INTO tc_daily_active (nickname, kst_day, sessions, hours_mask)
     SELECT $1::varchar,
            DATE(timezone('Asia/Seoul', u.created_at)) + $2::int,
            1, (1 << $3::int)
       FROM tc_users u WHERE u.nickname = $1::varchar
     ON CONFLICT (nickname, kst_day) DO NOTHING`,
    [nick(name), offset, hour],
  );
}

const ago = (d) => new Date(Date.now() - d * 86400000).toISOString();

(async () => {
  await db.initDatabase();

  // ── 성숙한 코호트: 창이 모두 닫혔으므로 전부 숫자여야 한다 ──
  //
  // 45일 전 가입 4명. 복귀를 일부러 어긋나게 심는다:
  //   a: D+1, D+10, D+30   b: D+1   c: D+7   d: 복귀 없음
  console.log('\n[성숙한 코호트 — 창이 닫혔으니 전부 숫자]');
  for (const n of ['a', 'b', 'c', 'd']) await makeUser(n, 45);
  await visit('a', 1); await visit('a', 10); await visit('a', 30);
  await visit('b', 1);
  await visit('c', 7);

  const joinDay = (await P.query(
    `SELECT DATE(timezone('Asia/Seoul', created_at)) AS d FROM tc_users WHERE nickname = $1`,
    [nick('a')])).rows[0].d;
  const cohorts = await db.getRetentionCohorts(ago(50), ago(40));
  const c = cohorts.find((x) => new Date(x.joinDay).getTime() === new Date(joinDay).getTime());

  check('코호트를 찾았다', !!c, JSON.stringify(cohorts.slice(0, 3)));
  if (c) {
    // 이 테스트가 만든 4명. 같은 날 가입한 다른 계정이 섞일 수 있으므로
    // 최소값으로 본다.
    check('코호트 크기에 4명이 들어 있다', c.cohortSize >= 4, String(c.cohortSize));
    eq('D+1 은 a·b 두 명', c.d1, 2);
    eq('D+7 은 c 한 명', c.d7, 1);
    eq('D+30 은 a 한 명', c.d30, 1);
    // w1 = (가입, +7] → a(D+1), b(D+1), c(D+7) = 3
    eq('1주 안 창은 D+7 까지 포함해 3명', c.w1, 3);
    // w2 = (+7, +30] → a(D+10, D+30) = 1. c 의 D+7 은 w1 쪽이다.
    eq('1~4주 창은 a 한 명', c.w2, 1);
    check('복귀 없는 d 는 어디에도 안 세진다', c.d1 + 0 === 2);
  }

  // ── 어린 코호트: 창이 닫히지 않은 칸은 비어 있어야 한다 ──
  //
  // 이게 이 파일의 핵심이다. 2일 된 코호트의 "1주 안 재방문" 은 아직 5일이
  // 남았으므로 비율을 낼 수 없다. 0 이나 부분값을 내면 그럴듯한 숫자가
  // 나오고, 그걸 보고 "최근 유입이 나쁘다"고 판단하게 된다.
  console.log('\n[어린 코호트 — 아직 오지 않은 날짜는 비워둔다]');
  await makeUser('young', 2);
  await visit('young', 1);
  const youngDay = (await P.query(
    `SELECT DATE(timezone('Asia/Seoul', created_at)) AS d FROM tc_users WHERE nickname = $1`,
    [nick('young')])).rows[0].d;
  const yc = (await db.getRetentionCohorts(ago(3), ago(0)))
    .find((x) => new Date(x.joinDay).getTime() === new Date(youngDay).getTime());

  check('어린 코호트를 찾았다', !!yc);
  if (yc) {
    check('D+1 은 이미 지났으므로 숫자', yc.d1 !== null && yc.d1 >= 1, String(yc.d1));
    eq('D+7 은 아직', yc.d7, null);
    eq('D+30 은 아직', yc.d30, null);
    // 여기가 실제로 틀렸던 자리다. 창의 끝이 아니라 시작으로 판정하면
    // 2일 된 코호트가 미완성 창으로 비율을 내보낸다.
    eq('1주 안 창도 아직 — 창이 +7일에 닫힌다', yc.w1, null);
    eq('1~4주 창도 아직 — 창이 +30일에 닫힌다', yc.w2, null);
  }

  // ── 시간대 비트마스크 ──
  console.log('\n[시간대 비트마스크 — 0시와 23시 경계]');
  await makeUser('h0', 1); await makeUser('h23', 1);
  await visit('h0', 0, 0);
  await visit('h23', 0, 23);
  const hours = await db.getHourlyActivity(ago(2), ago(0));
  const at = (h) => hours.filter((r) => Number(r.hour) === h)
    .reduce((a, r) => a + Number(r.users || 0), 0);
  check('0시가 집계된다', at(0) >= 1, String(at(0)));
  check('23시가 집계된다', at(23) >= 1, String(at(23)));
  check('0~23 범위를 벗어나지 않는다',
    hours.every((r) => Number(r.hour) >= 0 && Number(r.hour) <= 23));
  // 같은 날 또 들어오면 세션은 늘고 비트는 하나다 — "몇 명이 있었나"를
  // 세는 표이므로, 한 사람의 새로고침이 인원으로 보이면 안 된다.
  await db.recordDailyActive(nick('h0'));
  await db.recordDailyActive(nick('h0'));
  const inc = (await P.query(
    `SELECT sessions, hours_mask FROM tc_daily_active
      WHERE nickname = $1 AND kst_day = DATE(timezone('Asia/Seoul', NOW()))`,
    [nick('h0')])).rows[0];
  check('두 번 접속하면 세션이 2', inc && inc.sessions === 2, JSON.stringify(inc));
  check('같은 시간대 비트는 하나만 켜진다',
    inc && inc.hours_mask.toString(2).replace(/0/g, '').length === 1,
    inc && inc.hours_mask.toString(2));

  // ── 접속 빈도 분포 ──
  console.log('\n[접속 빈도 — 분포의 합이 유저 수와 같다]');
  const freq = await db.getVisitFrequency(ago(50), ago(0));
  const sum = ['d1', 'd2_3', 'd4_7', 'd8_14', 'd15']
    .reduce((a, k) => a + Number(freq[k] || 0), 0);
  eq('칸의 합 = 활동 유저 수', sum, Number(freq.users || 0));
  check('a 는 3일 접속했으므로 2~3일 칸에 있다', Number(freq.d2_3 || 0) >= 1,
    JSON.stringify(freq));

  // ── 봇과 탈퇴 계정은 빠진다 ──
  //
  // 활동 집합은 tc_users 조인으로 봇을 거른다. 계정이 없는 닉네임이
  // 세어지면 DAU 가 봇 수만큼 부풀고, 그게 가장 알아채기 어려운 오류다.
  console.log('\n[봇과 탈퇴 계정]');
  const before = (await db.getActiveUserSummary(ago(50), ago(0))).activeInRange;
  await P.query(
    `INSERT INTO tc_daily_active (nickname, kst_day, sessions, hours_mask)
     VALUES ($1, DATE(timezone('Asia/Seoul', NOW())), 1, 1)
     ON CONFLICT DO NOTHING`, [`봇${run}_없는계정`]);
  const after = (await db.getActiveUserSummary(ago(50), ago(0))).activeInRange;
  eq('계정 없는 닉네임(봇)은 활동에 안 세진다', after, before);

  await P.query(`UPDATE tc_users SET is_deleted = TRUE WHERE nickname = $1`, [nick('b')]);
  const afterDel = (await db.getActiveUserSummary(ago(50), ago(0))).activeInRange;
  check('탈퇴 계정은 빠진다', afterDel === before - 1,
    `before=${before} afterDelete=${afterDel}`);

  // 정리
  await P.query(`DELETE FROM tc_daily_active WHERE nickname LIKE $1 OR nickname LIKE $2`,
    [`리텐${run}_%`, `봇${run}_%`]);
  await P.query(`DELETE FROM tc_users WHERE nickname LIKE $1`, [`리텐${run}_%`]);

  console.log(failures === 0 ? '\n전부 통과\n' : `\n${failures}건 실패\n`);
  await P.end();
  process.exit(failures === 0 ? 0 : 1);
})().catch((err) => { console.error('\n테스트가 중단됐습니다:', err); process.exit(1); });
