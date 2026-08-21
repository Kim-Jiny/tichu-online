'use strict';
/**
 * 누구에게 출석 알림이 가는가 — 실제 Postgres 에 물어본다.
 *
 * 조건이 전부 SQL 한 덩어리에 들어 있어서, 이걸 안 돌려 보면 확인할 방법이
 * 없다. 특히 "받는 사람의 시계로 저녁 7시" 는 서버가 UTC 한 곳에서 도는 채로
 * 시간대별로 다른 답을 내야 하는 계산이라, 눈으로 읽어서는 맞는지 알 수 없다.
 *
 * 잡고 싶은 사고:
 *   - 시차 계산이 틀려 한국 사람에게 새벽에, 독일 사람에게 아침에 간다
 *   - 이미 출석한 사람에게 "아직 출석 안 하셨어요" 가 간다
 *   - 동의 안 한 사람에게 광고성 알림이 나간다 (이건 법적 문제다)
 *   - 하루에 두 번 간다
 *   - 반응 없는 사람에게 영영 매일 간다
 */

const { Client } = require('pg');

const DB_NAME = 'tichu_attendance_push_test';
const ADMIN_URL = 'postgresql://jiny@localhost:5432/postgres';
const TEST_URL = process.env.TEST_DATABASE_URL
  || `postgresql://jiny@localhost:5432/${DB_NAME}`;

let failures = 0;
function check(cond, msg) {
  if (cond) console.log(`  ok   ${msg}`);
  else { failures++; console.log(`  FAIL ${msg}`); }
}

async function main() {
  const admin = new Client({ connectionString: ADMIN_URL });
  await admin.connect();
  await admin.query(`DROP DATABASE IF EXISTS ${DB_NAME}`);
  await admin.query(`CREATE DATABASE ${DB_NAME}`);
  await admin.end();

  process.env.DATABASE_URL = TEST_URL;
  const db = require('./db/database');
  await db.initDatabase();

  const c = new Client({ connectionString: TEST_URL });
  await c.connect();

  // 지금 UTC 시각을 기준으로, 그 사람의 현지 시각이 19시가 되는 오프셋을
  // 만들어 준다. 테스트가 하루 중 언제 돌든 통과해야 하기 때문이다 —
  // 오후 3시에만 되는 테스트는 밤에 CI 에서 깨진다.
  //
  // 시각은 SQL 에서 정수로 받아 온다. timestamp 를 JS Date 로 받으면 표식
  // 없는 값을 드라이버는 UTC 로, 우리는 KST 로 읽어서 아홉 시간이 어긋난다.
  // 그 함정에 이 테스트가 먼저 걸렸다.
  const clock = (await c.query(
    `SELECT (EXTRACT(HOUR FROM timezone('UTC', NOW())) * 60
             + EXTRACT(MINUTE FROM timezone('UTC', NOW())))::int AS utc_minutes,
            to_char(timezone('UTC', NOW()), 'HH24:MI') AS utc_hhmm`)).rows[0];
  const utcMinutes = clock.utc_minutes;
  const offsetFor = (localHour) => {
    let off = localHour * 60 + 30 - utcMinutes;   // 그 시간대의 :30 으로 맞춘다
    while (off > 14 * 60) off -= 24 * 60;
    while (off < -12 * 60) off += 24 * 60;
    return off;
  };
  const AT_7PM = offsetFor(19);
  const AT_2PM = offsetFor(14);
  console.log(`  (지금 UTC ${clock.utc_hhmm} · `
    + `현지 19시 = 오프셋 ${AT_7PM}분, 현지 14시 = ${AT_2PM}분)\n`);

  let seq = 0;
  async function user(name, opts = {}) {
    seq++;
    await c.query(
      `INSERT INTO tc_users (username, password_hash, nickname, fcm_token,
                             push_enabled, marketing_push_enabled, push_attendance,
                             tz_offset_minutes, locale)
       VALUES ($1, 'x', $2, $3, $4, $5, $6, $7, $8)`,
      [`u${seq}`, name, opts.token === null ? null : `tok_${name}`,
       opts.pushEnabled !== false, opts.marketing !== false,
       opts.attendance !== false,
       opts.tz === undefined ? AT_7PM : opts.tz, opts.locale || 'ko'],
    );
    if (opts.attend || opts.streak != null || opts.pushLast || opts.mutedUntil) {
      await c.query(
        `INSERT INTO tc_attendance (nickname, last_claim_date, current_streak,
                                    push_last_date, push_ignored, push_muted_until)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [name,
         opts.attend === 'today' ? kstToday : null,
         opts.streak || 0, opts.pushLast || null, opts.pushIgnored || 0,
         opts.mutedUntil || null],
      );
    }
  }

  // KST 기준 오늘/어제. 출석 리셋은 KST 자정 고정이다.
  const kst = (await c.query(
    `SELECT to_char(DATE(timezone('Asia/Seoul', NOW())), 'YYYY-MM-DD') AS today,
            to_char(DATE(timezone('Asia/Seoul', NOW())) - 1, 'YYYY-MM-DD') AS yday`
  )).rows[0];
  const kstToday = kst.today;
  const kstYday = kst.yday;

  await user('보낸다');
  await user('아직두시', { tz: AT_2PM });
  await user('이미출석');
  await c.query(`UPDATE tc_attendance SET last_claim_date = $1 WHERE nickname = '이미출석'`,
    [kstToday]).catch(() => {});
  await c.query(
    `INSERT INTO tc_attendance (nickname, last_claim_date, current_streak)
     VALUES ('이미출석', $1, 3) ON CONFLICT (nickname) DO UPDATE
       SET last_claim_date = $1, current_streak = 3`, [kstToday]);
  await user('푸시전체끔', { pushEnabled: false });
  await user('동의안함', { marketing: false });
  await user('출석알림끔', { attendance: false });
  await user('토큰없음', { token: null });
  await user('시간대모름', { tz: null, locale: 'en' });
  await user('시간대모름한국', { tz: null, locale: 'ko' });
  await user('오늘보냄');
  await c.query(
    `INSERT INTO tc_attendance (nickname, push_last_date)
     VALUES ('오늘보냄',
             (timezone('UTC', NOW()) + ($1 || ' minutes')::interval)::date)`,
    [AT_7PM]);
  await user('쉬는중');
  await c.query(
    `INSERT INTO tc_attendance (nickname, push_muted_until)
     VALUES ('쉬는중', DATE(timezone('Asia/Seoul', NOW())) + 3)`);
  await user('여섯일차');
  await c.query(
    `INSERT INTO tc_attendance (nickname, last_claim_date, current_streak)
     VALUES ('여섯일차', $1, 6)`, [kstYday]);
  await user('칠일완주');
  await c.query(
    `INSERT INTO tc_attendance (nickname, last_claim_date, current_streak)
     VALUES ('칠일완주', $1, 7)`, [kstYday]);
  await user('지난번무시');
  // 어제 보냈다 — KST 어제가 아니라 **그 사람의 현지 어제**다. 시차에 따라
  // 둘이 다른 날일 수 있고, KST 를 쓰면 오프셋에 따라 "오늘 이미 보냄" 이
  // 되어 대상에서 빠진다.
  await c.query(
    `INSERT INTO tc_attendance (nickname, push_last_date, push_ignored)
     VALUES ('지난번무시',
             (timezone('UTC', NOW()) + ($1 || ' minutes')::interval)::date - 1,
             1)`, [AT_7PM]);
  await user('탈퇴함');
  await c.query(`UPDATE tc_users SET is_deleted = TRUE WHERE nickname = '탈퇴함'`);

  const targets = await db.getAttendancePushTargets();
  const got = new Set(targets.map(t => t.nickname));
  const by = Object.fromEntries(targets.map(t => [t.nickname, t]));

  console.log('보내야 하는 사람');
  for (const n of ['보낸다', '여섯일차', '칠일완주', '지난번무시']) {
    check(got.has(n), `${n}`);
  }

  console.log('\n보내면 안 되는 사람');
  for (const [n, why] of [
    ['아직두시', '현지가 아직 오후 2시'],
    ['이미출석', '오늘 이미 출석했다'],
    ['푸시전체끔', '푸시를 껐다'],
    ['동의안함', '광고성 수신에 동의하지 않았다'],
    ['출석알림끔', '출석 알림만 껐다'],
    ['토큰없음', '보낼 기기가 없다'],
    ['시간대모름', '시간대를 모르는 해외 사용자 — 새벽에 울릴 수 있다'],
    ['오늘보냄', '오늘 이미 보냈다'],
    ['쉬는중', '무시가 쌓여 쉬는 중이다'],
    ['탈퇴함', '탈퇴한 계정'],
  ]) {
    check(!got.has(n), `${n} — ${why}`);
  }

  console.log('\n시간대를 안 올린 옛 클라이언트');
  // 이 사람들의 현지 19시를 지금 만들어 낼 수는 없다. 대신 발송 시각을
  // 주입해서 "한국어 사용자는 KST 로 친다 / 나머지는 아예 안 친다" 를 본다.
  const kstHour = (await c.query(
    `SELECT EXTRACT(HOUR FROM timezone('Asia/Seoul', NOW()))::int AS h`)).rows[0].h;
  const atKstNow = await db.getAttendancePushTargets({ hour: kstHour });
  const kstNames = new Set(atKstNow.map(t => t.nickname));
  check(kstNames.has('시간대모름한국'), '한국어 사용자는 KST(+540) 로 친다');
  check(!kstNames.has('시간대모름'),
    '해외 사용자는 추정하지 않는다 — 새벽에 울리느니 안 보낸다');

  console.log('\n문구에 쓸 값');
  check(by['보낸다']?.nextStreak === 1, '한 번도 안 한 사람은 1일차');
  check(by['여섯일차']?.nextStreak === 7, '어제 6일차였으면 오늘 7일차');
  check(by['칠일완주']?.nextStreak === 1, '7일을 채웠으면 새 주기 1일차');
  check(by['보낸다']?.ignoredLast === false, '보낸 적 없으면 무시한 것도 없다');
  check(by['지난번무시']?.ignoredLast === true, '어제 보냈는데 출석 안 했으면 무시');


  console.log('\n보낸 뒤');
  await db.markAttendancePushSent('보낸다', by['보낸다'].localDate, false);
  const again = await db.getAttendancePushTargets();
  check(!again.some(t => t.nickname === '보낸다'), '같은 날 두 번 가지 않는다');

  // 무시가 한도에 닿으면 쉰다. 지난번무시(=1) 에 두 번 더 쌓는다.
  await db.markAttendancePushSent('지난번무시', by['지난번무시'].localDate, true);
  let row = (await c.query(
    `SELECT push_ignored, push_muted_until FROM tc_attendance WHERE nickname='지난번무시'`)).rows[0];
  check(row.push_ignored === 2 && row.push_muted_until === null,
    '두 번 무시로는 아직 쉬지 않는다');
  await c.query(`UPDATE tc_attendance SET push_last_date = NULL WHERE nickname='지난번무시'`);
  await db.markAttendancePushSent('지난번무시', by['지난번무시'].localDate, true);
  row = (await c.query(
    `SELECT push_ignored, push_muted_until FROM tc_attendance WHERE nickname='지난번무시'`)).rows[0];
  check(row.push_ignored === 0 && row.push_muted_until !== null,
    `세 번째 무시에서 쉬기 시작하고 횟수는 0으로 돌아간다`);

  await c.end();
  await db.pool.end();

  const cleanup = new Client({ connectionString: ADMIN_URL });
  await cleanup.connect();
  await cleanup.query(`DROP DATABASE IF EXISTS ${DB_NAME}`);
  await cleanup.end();

  console.log(failures === 0 ? '\n전부 통과' : `\n${failures}건 실패`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch(err => { console.error(err); process.exit(1); });
