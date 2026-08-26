/**
 * Coupons: the cap, the one-per-account rule, and what actually gets paid.
 *
 * The two rules worth testing are the two that only break under load. A cap of
 * N is read and written by every redemption at once, and "one per account" is
 * what a double-tap attacks. Both are checked here by firing the redemptions
 * concurrently rather than in a loop — a sequential test passes with no
 * locking at all and tells you nothing.
 *
 * Talks to the database directly; no server needed.
 *
 * Run: node server/test_coupon.js
 */
const db = require('./db/database.js');

let failures = 0;
const check = (label, cond, detail = '') => {
  console.log(`${cond ? '  ok  ' : '  FAIL'} ${label}${!cond && detail ? ` — ${detail}` : ''}`);
  if (!cond) failures++;
};

const run = Date.now().toString(36).slice(-5);
const nick = (i) => `쿠폰${run}_${i}`;

async function makeUsers(n) {
  for (let i = 0; i < n; i++) {
    await db.pool.query(
      `INSERT INTO tc_users (username, nickname, gold)
       VALUES ($1, $2, 0) ON CONFLICT (nickname) DO NOTHING`,
      [`cp_${run}_${i}`, nick(i)],
    );
  }
}

async function cleanup(codes, n) {
  for (const c of codes) {
    await db.pool.query('DELETE FROM tc_coupon_redemptions WHERE code = $1', [c]);
    await db.pool.query('DELETE FROM tc_coupons WHERE code = $1', [c]);
  }
  for (let i = 0; i < n; i++) {
    await db.pool.query('DELETE FROM tc_user_items WHERE nickname = $1', [nick(i)]);
    await db.pool.query('DELETE FROM tc_gold_history WHERE nickname = $1', [nick(i)]);
    await db.pool.query('DELETE FROM tc_users WHERE nickname = $1', [nick(i)]);
  }
}

(async () => {
  // Migrations run on server boot; this talks to the database directly, so it
  // has to create its own tables first. Doubles as a check that the coupon DDL
  // is safe to run against a database that already has data.
  await db.initDatabase();

  const USERS = 12;
  const CAP = 5;
  // Already uppercase: the server normalizes codes on the way in, so a
  // mixed-case constant here would store one string and query another.
  const suffix = run.toUpperCase();
  const codes = [`CAP${suffix}`, `ONCE${suffix}`, `GONE${suffix}`,
    `ITEM${suffix}`, `OFF${suffix}`, `SOON${suffix}`];
  await makeUsers(USERS);

  console.log('\n[a cap of 5, rushed by 12 people at once]');
  await db.upsertCoupon({
    code: codes[0], rewardType: 'gold', rewardGold: 100, maxRedemptions: CAP,
  });
  const rush = await Promise.all(
    Array.from({ length: USERS }, (_, i) => db.redeemCoupon(nick(i), codes[0])),
  );
  const won = rush.filter((r) => r.success).length;
  check(`exactly ${CAP} succeed`, won === CAP, `${won} did`);
  check('the rest are told it ran out',
    rush.filter((r) => r.messageKey === 'coupon_exhausted').length === USERS - CAP,
    rush.filter((r) => !r.success).map((r) => r.messageKey).join(','));
  const row = (await db.pool.query(
    'SELECT redeemed_count FROM tc_coupons WHERE code = $1', [codes[0]])).rows[0];
  const logged = (await db.pool.query(
    'SELECT COUNT(*)::int c FROM tc_coupon_redemptions WHERE code = $1', [codes[0]])).rows[0].c;
  check('the counter matches the rows it stands for',
    row.redeemed_count === CAP && logged === CAP,
    `counter=${row.redeemed_count}, rows=${logged}`);
  const paid = (await db.pool.query(
    `SELECT COUNT(*)::int c FROM tc_gold_history WHERE source = 'coupon' AND description = $1`,
    [codes[0]])).rows[0].c;
  check('nobody was paid who did not win a seat', paid === CAP, `${paid} payments`);

  console.log('\n[one account, eight simultaneous taps]');
  // This account also won a seat in the rush above, so the test reads the
  // delta rather than the balance.
  const before = (await db.pool.query(
    'SELECT gold FROM tc_users WHERE nickname = $1', [nick(0)])).rows[0].gold;
  await db.upsertCoupon({ code: codes[1], rewardType: 'gold', rewardGold: 500 });
  const taps = await Promise.all(
    Array.from({ length: 8 }, () => db.redeemCoupon(nick(0), codes[1])),
  );
  check('only one tap pays', taps.filter((r) => r.success).length === 1,
    `${taps.filter((r) => r.success).length} paid`);
  check('the others say it is already used',
    taps.filter((r) => r.messageKey === 'coupon_already_used').length === 7);
  const after = (await db.pool.query(
    'SELECT gold FROM tc_users WHERE nickname = $1', [nick(0)])).rows[0].gold;
  check('the account is 500 richer, not 4000', after - before === 500,
    `+${after - before}`);

  console.log('\n[the refusals]');
  await db.upsertCoupon({
    code: codes[2], rewardType: 'gold', rewardGold: 10,
    expiresAt: new Date(Date.now() - 60000),
  });
  check('an expired coupon is refused',
    (await db.redeemCoupon(nick(1), codes[2])).messageKey === 'coupon_expired');
  await db.upsertCoupon({
    code: codes[4], rewardType: 'gold', rewardGold: 10, isActive: false,
  });
  await db.upsertCoupon({
    code: `SOON${suffix}`, rewardType: 'gold', rewardGold: 10,
    expiresAt: new Date(Date.now() + 60 * 60 * 1000),
  });
  check('a coupon expiring in an hour still works',
    (await db.redeemCoupon(nick(1), `SOON${suffix}`)).success === true,
    'an off-by-timezone fix can make everything look expired');
  check('a switched-off coupon is refused',
    (await db.redeemCoupon(nick(1), codes[4])).messageKey === 'coupon_inactive');
  check('an unknown code is refused',
    (await db.redeemCoupon(nick(1), `NOPE${suffix}`)).messageKey === 'coupon_not_found');
  check('an unknown account is refused',
    (await db.redeemCoupon(`없는사람${run}`, codes[1])).messageKey === 'db_user_not_found');

  console.log('\n[typing it off a blog post]');
  const messy = await db.redeemCoupon(nick(2), `  ${codes[1].toLowerCase()} `);
  check('lowercase and stray spaces still match', messy.success === true,
    messy.messageKey || '');

  console.log('\n[an item coupon]');
  const shopItem = (await db.pool.query(
    `SELECT item_key FROM tc_shop_items WHERE is_permanent = FALSE
       AND duration_days IS NOT NULL LIMIT 1`)).rows[0];
  if (!shopItem) {
    console.log('  skip  no time-limited shop item in this database');
  } else {
    await db.upsertCoupon({
      code: codes[3], rewardType: 'item',
      rewardItemKey: shopItem.item_key, rewardDays: 3,
    });
    const got = await db.redeemCoupon(nick(3), codes[3]);
    check('the item is granted', got.success === true, got.messageKey || '');
    const owned = (await db.pool.query(
      `SELECT expires_at, source FROM tc_user_items
        WHERE nickname = $1 AND item_key = $2`,
      [nick(3), shopItem.item_key])).rows[0];
    check('it is recorded as coming from a coupon', owned?.source === 'coupon',
      owned?.source);
    const days = owned?.expires_at
      ? Math.round((new Date(owned.expires_at) - Date.now()) / 86400000)
      : null;
    check('reward_days overrides the shop duration', days === 3, `${days} days`);
    // The rounded day count above passes whether or not the timezone is right
    // — three days minus nine hours still rounds to three. Compare in SQL,
    // where the column's UTC value meets a UTC now, and give it minutes of
    // slack rather than hours. Run under TZ=Asia/Seoul this is what fails if
    // the expiry is ever built from a JS Date again.
    const drift = (await db.pool.query(
      `SELECT EXTRACT(EPOCH FROM (
                expires_at - ((NOW() AT TIME ZONE 'UTC') + INTERVAL '3 days')
              )) / 60 AS minutes
       FROM tc_user_items WHERE nickname = $1 AND item_key = $2`,
      [nick(3), shopItem.item_key])).rows[0]?.minutes;
    check('and lands exactly three days out in UTC, whatever the host timezone',
      Math.abs(Number(drift)) < 2, `${Number(drift).toFixed(1)} minutes off`);
  }

  console.log('\n[이미 가진 것을 또 받았을 때]');
  // A gift cannot refuse the way the shop does — the coupon is already spent.
  // What it must not do is stack a second row: a permanent item cannot be
  // owned twice, and duplicates inflate the backstage inventory and the
  // "쓰는 중" holder counts.
  const permItem = (await db.pool.query(
    `SELECT item_key FROM tc_shop_items
      WHERE is_permanent = TRUE AND category <> 'utility' LIMIT 1`)).rows[0];
  if (permItem) {
    const rows = async () => (await db.pool.query(
      'SELECT COUNT(*)::int n FROM tc_user_items WHERE nickname = $1 AND item_key = $2',
      [nick(6), permItem.item_key])).rows[0].n;
    for (const suffix of ['A', 'B']) {
      const code = `PERM${suffix}${run.toUpperCase()}`;
      codes.push(code);
      await db.upsertCoupon({
        code, rewardType: 'item', rewardItemKey: permItem.item_key });
      const got = await db.redeemCoupon(nick(6), code);
      check(`영구 아이템 지급 (${suffix})`, got.success === true, got.messageKey || '');
    }
    check('두 번 받아도 행은 하나', (await rows()) === 1, `${await rows()} rows`);
  }

  const utilityItem = (await db.pool.query(
    `SELECT item_key FROM tc_shop_items
      WHERE is_permanent = TRUE AND category = 'utility' LIMIT 1`)).rows[0];
  if (utilityItem) {
    const rows = async () => (await db.pool.query(
      'SELECT COUNT(*)::int n FROM tc_user_items WHERE nickname = $1 AND item_key = $2',
      [nick(8), utilityItem.item_key])).rows[0].n;
    for (const suffix of ['A', 'B']) {
      const code = `UTIL${suffix}${run.toUpperCase()}`;
      codes.push(code);
      await db.upsertCoupon({
        code, rewardType: 'item', rewardItemKey: utilityItem.item_key });
      const got = await db.redeemCoupon(nick(8), code);
      check(`영구 소모품 지급 (${suffix})`, got.success === true, got.messageKey || '');
    }
    check('영구 소모품은 두 장 보유할 수 있다', (await rows()) === 2, `${await rows()} rows`);
  }

  const dupTemp = (await db.pool.query(
    `SELECT item_key, duration_days FROM tc_shop_items
     WHERE is_permanent = FALSE AND duration_days IS NOT NULL LIMIT 1`)).rows[0];
  if (dupTemp) {
    const hours = async () => Number((await db.pool.query(
      `SELECT EXTRACT(EPOCH FROM (expires_at - (NOW() AT TIME ZONE 'UTC')))/3600 h
       FROM tc_user_items WHERE nickname = $1 AND item_key = $2`,
      [nick(7), dupTemp.item_key])).rows[0]?.h);
    for (const suffix of ['A', 'B']) {
      const code = `TEMP${suffix}${run.toUpperCase()}`;
      codes.push(code);
      await db.upsertCoupon({
        code, rewardType: 'item', rewardItemKey: dupTemp.item_key, rewardDays: 5 });
      await db.redeemCoupon(nick(7), code);
    }
    const n = (await db.pool.query(
      'SELECT COUNT(*)::int n FROM tc_user_items WHERE nickname = $1 AND item_key = $2',
      [nick(7), dupTemp.item_key])).rows[0].n;
    check('기간제도 행은 하나', n === 1, `${n} rows`);
    check('대신 기간이 합쳐진다 (5+5=10일)',
      Math.abs((await hours()) - 240) < 1, `${(await hours()).toFixed(1)}h`);
  }

  await cleanup(codes, USERS);
})()
  .then(() => {
    console.log(failures === 0 ? '\nPASS' : `\n${failures} FAILURE(S)`);
    process.exit(failures === 0 ? 0 : 1);
  })
  .catch(async (e) => {
    console.error('\nERROR', e.message);
    process.exit(1);
  });
