/**
 * The App Review kill switch.
 *
 * Whether coupons are visible in the iOS app is decided by the server, not the
 * binary, so that a reviewer's objection costs a config change instead of a
 * release. The two ways to get it wrong are both silent: hiding the notices
 * from everyone (the coupon campaign quietly stops working), or hiding them
 * from nobody (the switch is flipped during review and does nothing). So this
 * asserts both sides on every platform that matters.
 *
 * Note that iPhone Safari reports devicePlatform 'web' — it must keep seeing
 * coupons even with the switch on, since that is where iOS players are meant
 * to redeem.
 *
 * Run (server must be listening): node server/test_coupon_notice_gate.js
 */
const WebSocket = require('ws');
const db = require('./db/database.js');

const SERVER_URL = process.argv[2] || 'ws://localhost:8080';
const run = Date.now().toString(36).slice(-5);
const CODE = `GATE${run.toUpperCase()}`;

let failures = 0;
const check = (label, cond, detail = '') => {
  console.log(`${cond ? '  ok  ' : '  FAIL'} ${label}${!cond && detail ? ` — ${detail}` : ''}`);
  if (!cond) failures++;
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function connect() {
  const c = { last: {} };
  c.ready = new Promise((resolve, reject) => {
    c.ws = new WebSocket(SERVER_URL);
    c.ws.on('open', resolve);
    c.ws.on('error', reject);
    c.ws.on('message', (raw) => {
      const d = JSON.parse(raw.toString());
      c.last[d.type] = d;
    });
  });
  c.send = (m) => c.ws.send(JSON.stringify(m));
  c.wait = async (t, ms = 8000) => {
    const end = Date.now() + ms;
    while (Date.now() < end) {
      if (c.last[t]) return c.last[t];
      await sleep(80);
    }
    return null;
  };
  return c;
}

/// Logs in a throwaway account claiming to be on `platform`, asks for the
/// notices, and answers the only question that matters: did the coupon notice
/// come down this socket?
async function seesCoupon(platform, idx) {
  const acct = {
    username: `gate_${run}_${idx}`,
    password: 'smoke1234!',
    nickname: `게이트${run}_${idx}`,
  };
  const c = connect();
  await c.ready;
  c.send({ type: 'register', ...acct });
  await sleep(700);
  c.send({
    type: 'login',
    username: acct.username,
    password: acct.password,
    deviceInfo: { appVersion: '99.0.0', locale: 'ko', devicePlatform: platform },
  });
  if (!(await c.wait('login_success'))) throw new Error(`login failed (${platform})`);

  c.send({ type: 'get_notices' });
  const res = await c.wait('notices_result');
  c.ws.close();
  if (!res) throw new Error(`no notices_result (${platform})`);
  const notices = res.notices || [];
  return {
    coupon: notices.some((n) => n.coupon_code === CODE),
    total: notices.length,
    withCoupon: notices.filter((n) => n.coupon_code).length,
    nickname: acct.nickname,
  };
}

(async () => {
  await db.updateConfig('coupon_hide_ios', 'off');
  await db.upsertCoupon({
    code: CODE, rewardType: 'gold', rewardGold: 10, maxRedemptions: 1,
  });
  const notice = await db.createNotice(
    'event', `게이트 테스트 ${run}`, '쿠폰이 붙은 공지', false, 'published', CODE,
  );
  const noticeId = notice?.id;
  if (!noticeId) throw new Error('could not create the test notice');

  const nicknames = [];
  const probe = async (platform, i) => {
    const r = await seesCoupon(platform, i);
    nicknames.push(r.nickname);
    return r;
  };

  console.log('\n[switch off — everyone sees it]');
  const offIos = await probe('ios', 1);
  const offWeb = await probe('web', 2);
  const offDroid = await probe('android', 3);
  check('the iOS app sees the coupon notice', offIos.coupon);
  check('the web sees it', offWeb.coupon);
  check('Android sees it', offDroid.coupon);

  console.log('\n[switch on — the iOS app only]');
  await db.updateConfig('coupon_hide_ios', 'on');
  const onIos = await probe('ios', 4);
  const onWeb = await probe('web', 5);
  const onDroid = await probe('android', 6);
  const onLegacy = await probe(null, 7);
  check('the iOS app no longer sees it', !onIos.coupon);
  // Every coupon notice goes, not just this test's one — but nothing else may.
  check('every coupon notice goes and no other does',
    onIos.total === offIos.total - offIos.withCoupon && onIos.withCoupon === 0,
    `${onIos.total} left of ${offIos.total}, ${offIos.withCoupon} carried coupons`);
  check('the web still sees it — iPhone Safari reports web', onWeb.coupon);
  check('Android still sees it', onDroid.coupon);
  check('a client that sends no platform still sees it', onLegacy.coupon,
    'only the iOS app is gated; unknown must not be treated as iOS');

  console.log('\n[and back]');
  await db.updateConfig('coupon_hide_ios', 'off');
  const backIos = await probe('ios', 8);
  check('flipping it back restores the notice with no deploy', backIos.coupon);

  if (noticeId) await db.pool.query('DELETE FROM tc_notices WHERE id = $1', [noticeId]);
  await db.pool.query('DELETE FROM tc_coupons WHERE code = $1', [CODE]);
  for (const n of nicknames) {
    await db.pool.query('DELETE FROM tc_users WHERE nickname = $1', [n]);
  }
})()
  .then(() => {
    console.log(failures === 0 ? '\nPASS' : `\n${failures} FAILURE(S)`);
    process.exit(failures === 0 ? 0 : 1);
  })
  .catch((e) => {
    console.error('\nERROR', e.message);
    process.exit(1);
  });
