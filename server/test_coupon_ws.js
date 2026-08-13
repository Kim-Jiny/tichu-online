/**
 * Redeeming a coupon over the socket.
 *
 * The database test covers the rules; this covers the wire — that the reply
 * carries a translated message rather than a key, and that the wallet the
 * client shows is refreshed by the same handler it already trusts. A reward
 * that lands in the database but never reaches the screen reads as a coupon
 * that did nothing.
 *
 * Run (server must be listening): node server/test_coupon_ws.js
 */
const WebSocket = require('ws');
const db = require('./db/database.js');

const SERVER_URL = process.argv[2] || 'ws://localhost:8080';
const run = Date.now().toString(36).slice(-5);
const CODE = `WS${run.toUpperCase()}`;

let failures = 0;
const check = (label, cond, detail = '') => {
  console.log(`${cond ? '  ok  ' : '  FAIL'} ${label}${!cond && detail ? ` — ${detail}` : ''}`);
  if (!cond) failures++;
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function connect() {
  const c = { last: {}, seen: [] };
  c.ready = new Promise((resolve, reject) => {
    c.ws = new WebSocket(SERVER_URL);
    c.ws.on('open', resolve);
    c.ws.on('error', reject);
    c.ws.on('message', (raw) => {
      const d = JSON.parse(raw.toString());
      c.seen.push(d.type);
      c.last[d.type] = d;
    });
  });
  c.send = (m) => c.ws.send(JSON.stringify(m));
  c.forget = (t) => delete c.last[t];
  c.wait = async (t, ms = 8000) => {
    const end = Date.now() + ms;
    while (Date.now() < end) {
      if (c.last[t]) return c.last[t];
      await sleep(100);
    }
    return null;
  };
  return c;
}

(async () => {
  const acct = {
    username: `cw_${run}`,
    password: 'smoke1234!',
    nickname: `쿠폰소켓${run}`,
  };
  const c = connect();
  await c.ready;
  c.send({ type: 'register', ...acct });
  await sleep(900);
  c.send({
    type: 'login',
    username: acct.username,
    password: acct.password,
    deviceInfo: { appVersion: '99.0.0', locale: 'ko' },
  });
  if (!(await c.wait('login_success'))) throw new Error('login failed');

  await db.upsertCoupon({
    code: CODE, rewardType: 'gold', rewardGold: 777, maxRedemptions: 1,
  });

  const before = (await db.pool.query(
    'SELECT gold FROM tc_users WHERE nickname = $1', [acct.nickname])).rows[0].gold;

  console.log('\n[a bad code first]');
  c.send({ type: 'redeem_coupon', code: 'NOSUCHCODE' });
  const bad = await c.wait('coupon_result');
  check('the server answers', bad != null);
  check('it refuses', bad?.success === false);
  check('and says why in the player\'s language, not a key',
    typeof bad?.message === 'string' && /쿠폰|코드/.test(bad.message),
    bad?.message);

  console.log('\n[the real code]');
  c.forget('coupon_result');
  c.forget('wallet_result');
  c.send({ type: 'redeem_coupon', code: CODE.toLowerCase() });
  const ok = await c.wait('coupon_result');
  check('lowercase input is accepted', ok?.success === true, ok?.message);
  check('the reward comes back with the reply',
    ok?.reward?.type === 'gold' && ok?.reward?.gold === 777,
    JSON.stringify(ok?.reward));

  const wallet = await c.wait('wallet_result', 5000);
  check('the wallet is pushed without being asked', wallet != null);
  // getWallet nests it: { success, wallet: { gold, leave_count } }.
  check('and shows the new balance',
    wallet?.wallet?.gold === before + 777,
    `${wallet?.wallet?.gold} vs ${before + 777}`);

  console.log('\n[twice]');
  c.forget('coupon_result');
  c.send({ type: 'redeem_coupon', code: CODE });
  const again = await c.wait('coupon_result');
  check('the second attempt is refused', again?.success === false);
  check('the balance did not move again',
    (await db.pool.query('SELECT gold FROM tc_users WHERE nickname = $1',
      [acct.nickname])).rows[0].gold === before + 777);

  console.log('\n[logged out]');
  const anon = connect();
  await anon.ready;
  anon.send({ type: 'redeem_coupon', code: CODE });
  const err = await anon.wait('error', 5000);
  check('a client with no session is turned away', err != null, 'no error frame');
  anon.ws.close();

  c.ws.close();
  await db.pool.query('DELETE FROM tc_coupon_redemptions WHERE code = $1', [CODE]);
  await db.pool.query('DELETE FROM tc_coupons WHERE code = $1', [CODE]);
  await db.pool.query('DELETE FROM tc_gold_history WHERE nickname = $1', [acct.nickname]);
  await db.pool.query('DELETE FROM tc_users WHERE nickname = $1', [acct.nickname]);
})()
  .then(() => {
    console.log(failures === 0 ? '\nPASS' : `\n${failures} FAILURE(S)`);
    process.exit(failures === 0 ? 0 : 1);
  })
  .catch((e) => {
    console.error('\nERROR', e.message);
    process.exit(1);
  });
