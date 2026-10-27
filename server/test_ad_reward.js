'use strict';
/**
 * Ad rewards: 50 gold, five a day, counted by the server.
 *
 * The app used to count them itself, on the device's date, and bumped the count
 * before the server had answered — so a refused or lost claim still used one up
 * and nothing was paid. Now the server is the only counter (get_ad_reward_status)
 * and a claim carries an id, so the app can safely send it again when it never
 * heard back: the same ad is paid once.
 */

const { Client } = require('pg');

const DB_NAME = 'tichu_ad_reward_test';
const TEST_DB_URL = process.env.TEST_DATABASE_URL
  || `postgresql://jiny@localhost:5432/${DB_NAME}`;

let failures = 0;
function check(cond, msg) {
  if (cond) console.log(`  ok   ${msg}`);
  else { failures++; console.log(`  FAIL ${msg}`); }
}

async function main() {
  const admin = new Client({ connectionString: 'postgresql://jiny@localhost:5432/postgres' });
  await admin.connect();
  await admin.query(`DROP DATABASE IF EXISTS ${DB_NAME}`);
  await admin.query(`CREATE DATABASE ${DB_NAME}`);
  await admin.end();

  process.env.DATABASE_URL = TEST_DB_URL;
  const db = require('./db/database');
  await db.initDatabase();
  const raw = new Client({ connectionString: TEST_DB_URL });
  await raw.connect();
  const goldOf = async (n) => (await raw.query('SELECT gold FROM tc_users WHERE nickname = $1', [n])).rows[0].gold;

  try {
    await db.registerUser('ad_user1', 'test1234!', '광고하나');
    await raw.query(`UPDATE tc_users SET gold = 0 WHERE nickname = '광고하나'`);
    const nick = '광고하나';

    let st = await db.getAdRewardStatus(nick);
    check(st.success && st.used === 0 && st.remaining === 5 && st.max === 5, '새 사용자: 0번 받음, 5번 남음');

    let r = await db.claimAdReward(nick, 'ad-A');
    check(r.success && r.gold === 50 && r.remaining === 4, '첫 지급: 50골드, 4번 남음');
    st = await db.getAdRewardStatus(nick);
    check(st.used === 1 && st.remaining === 4, '서버가 센 횟수가 1');

    // The app never heard back and sends the same claim again.
    r = await db.claimAdReward(nick, 'ad-A');
    check(r.success && r.repeat === true && r.gold === 50, '같은 claimId 를 다시 보내면 성공을 돌려주되');
    check(await goldOf(nick) === 50, '골드를 또 주지 않는다');
    st = await db.getAdRewardStatus(nick);
    check(st.used === 1, '횟수도 또 올리지 않는다');

    for (const id of ['ad-B', 'ad-C', 'ad-D']) await db.claimAdReward(nick, id);
    r = await db.claimAdReward(nick, 'ad-E');
    check(r.success && r.remaining === 0, '다섯 번째까지는 지급된다');
    check(await goldOf(nick) === 250, '골드 250');

    r = await db.claimAdReward(nick, 'ad-F');
    check(!r.success && r.messageKey === 'db_ad_reward_exhausted' && r.remaining === 0, '여섯 번째는 거절(오늘 몫을 다 받음)');
    check(await goldOf(nick) === 250, '거절되면 골드는 그대로');
    st = await db.getAdRewardStatus(nick);
    check(st.used === 5 && st.remaining === 0, '거절돼도 횟수는 5 에서 늘지 않는다');

    // Already paid ad, asked again after the day's quota is gone: still a success, not "exhausted".
    r = await db.claimAdReward(nick, 'ad-E');
    check(r.success && r.repeat === true, '이미 지급한 광고의 재요청은 몫이 찼어도 성공으로 답한다');
    check(await goldOf(nick) === 250, '그래도 골드는 그대로');

    // A new day (server date): everything above moves to yesterday.
    await raw.query(`UPDATE tc_ad_rewards SET claimed_at = claimed_at - INTERVAL '1 day' WHERE nickname = $1`, [nick]);
    st = await db.getAdRewardStatus(nick);
    check(st.used === 0 && st.remaining === 5, '서버 날짜가 바뀌면 다시 5번');
    r = await db.claimAdReward(nick, 'ad-G');
    check(r.success && r.remaining === 4, '새 날 첫 지급');

    // Old apps send no id: still works and still counts.
    r = await db.claimAdReward(nick);
    check(r.success && r.remaining === 3, 'claimId 가 없는(옛 앱) 요청도 지급·집계된다');
    r = await db.claimAdReward(nick);
    check(r.success && r.remaining === 2, '없는 id 끼리는 서로 같은 광고로 보지 않는다');
    // Junk ids are not trusted as ids.
    r = await db.claimAdReward(nick, 'x'.repeat(200));
    check(r.success && r.remaining === 1, '비정상적으로 긴 id 는 id 없는 요청으로 본다');
    r = await db.claimAdReward(nick, "bad id'; --");
    check(r.success && r.remaining === 0, '이상한 문자가 든 id 도 마찬가지');

    // Many claims at once never get past five.
    await db.registerUser('ad_user2', 'test1234!', '광고둘');
    await raw.query(`UPDATE tc_users SET gold = 0 WHERE nickname = '광고둘'`);
    const results = await Promise.all(Array.from({ length: 10 }, (_, i) => db.claimAdReward('광고둘', `par-${i}`)));
    const ok = results.filter((x) => x.success).length;
    check(ok === 5, `동시에 10번 요청해도 5번만 지급된다 (성공 ${ok})`);
    check(await goldOf('광고둘') === 250, '골드 250');
    const same = await Promise.all(Array.from({ length: 6 }, () => db.claimAdReward('광고둘', 'par-0')));
    check(same.every((x) => x.success && x.repeat), '같은 id 를 동시에 여러 번 보내도 모두 같은 성공');
    check(await goldOf('광고둘') === 250, '그래도 골드는 그대로');
  } finally {
    await raw.end();
    await db.pool.end?.().catch?.(() => {});
  }
  console.log(failures ? `\n실패 ${failures}건` : '\n전부 통과');
  process.exit(failures ? 1 : 0);
}
main().catch((e) => { console.error(e); process.exit(1); });
