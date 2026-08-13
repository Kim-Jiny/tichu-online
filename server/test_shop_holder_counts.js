/**
 * "How many people are using this item right now" on the backstage item list.
 *
 * The number is only useful if it means one thing, and there are three ways to
 * get it wrong quietly:
 *
 *  - counting lapsed holders as live, which makes a dead item look healthy;
 *  - counting the equips table on its own — an equip row is NOT cleared when
 *    the item runs out, so a banner nobody can actually see still reports as
 *    worn;
 *  - reporting zero for the profile-photo pass, which lives on tc_users rather
 *    than tc_user_items and so is invisible to the obvious query.
 *
 * Talks to the database directly; no server needed.
 *
 * Run: node server/test_shop_holder_counts.js
 */
const db = require('./db/database.js');

let failures = 0;
const check = (label, cond, detail = '') => {
  console.log(`${cond ? '  ok  ' : '  FAIL'} ${label}${!cond && detail ? ` — ${detail}` : ''}`);
  if (!cond) failures++;
};

const run = Date.now().toString(36).slice(-5);
const nick = (i) => `보유${run}_${i}`;

async function makeUser(i) {
  await db.pool.query(
    `INSERT INTO tc_users (username, nickname, gold) VALUES ($1, $2, 0)
     ON CONFLICT (nickname) DO NOTHING`,
    [`hold_${run}_${i}`, nick(i)],
  );
}

/// Hand [i] the item with an expiry [days] from now (negative = already gone).
async function give(i, itemKey, days) {
  await db.pool.query(
    `INSERT INTO tc_user_items (nickname, item_key, expires_at, source)
     VALUES ($1, $2, (NOW() AT TIME ZONE 'UTC') + ($3 || ' days')::interval, 'admin')`,
    [nick(i), itemKey, days],
  );
}

async function wearBanner(i, itemKey) {
  await db.pool.query(
    `INSERT INTO tc_user_equips (nickname, banner_key) VALUES ($1, $2)
     ON CONFLICT (nickname) DO UPDATE SET banner_key = EXCLUDED.banner_key`,
    [nick(i), itemKey],
  );
}

(async () => {
  await db.initDatabase();

  const banner = (await db.pool.query(
    `SELECT item_key FROM tc_shop_items WHERE category = 'banner' LIMIT 1`)).rows[0]?.item_key;
  if (!banner) throw new Error('no banner in this database');

  // Whatever the rest of the database already holds; this test asserts on the
  // delta so it can run against a populated dev database.
  const base = await db.getShopItemHolderCounts();
  const b0 = base.byKey[banner] || { active: 0, total: 0, equipped: 0 };
  const photo0 = base.profilePhotoActive;

  // 1 and 2 hold it with time left; 2 also wears it. 3 holds a lapsed copy and
  // is still wearing it — the case that inflates a naive equips count.
  for (const i of [1, 2, 3]) await makeUser(i);
  await give(1, banner, 10);
  await give(2, banner, 10);
  await wearBanner(2, banner);
  await give(3, banner, -10);
  await wearBanner(3, banner);

  const c = await db.getShopItemHolderCounts();
  const b = c.byKey[banner];

  console.log('\n[a banner held by three, one of them lapsed]');
  check('two more live holders', b.active - b0.active === 2,
    `${b0.active} → ${b.active}`);
  check('three more holders in total — the lapsed one still counts there',
    b.total - b0.total === 3, `${b0.total} → ${b.total}`);
  check('only one more counted as worn',
    b.equipped - b0.equipped === 1, `${b0.equipped} → ${b.equipped}`);
  check('the lapsed wearer is not counted, though their equip row still says so',
    b.equipped - b0.equipped !== 2,
    'an equip row outlives the item; counting equips alone reports invisible banners');

  console.log('\n[the profile-photo pass, which is not a tc_user_items row]');
  await db.pool.query(
    `UPDATE tc_users SET profile_photo_status = 'active',
       profile_photo_expires_at = (NOW() AT TIME ZONE 'UTC') + INTERVAL '5 days'
     WHERE nickname = $1`, [nick(1)]);
  await db.pool.query(
    `UPDATE tc_users SET profile_photo_status = 'active',
       profile_photo_expires_at = (NOW() AT TIME ZONE 'UTC') - INTERVAL '5 days'
     WHERE nickname = $1`, [nick(2)]);
  const c2 = await db.getShopItemHolderCounts();
  check('the live pass is counted', c2.profilePhotoActive - photo0 === 1,
    `${photo0} → ${c2.profilePhotoActive}`);
  check('the expired one is not', c2.profilePhotoActive - photo0 !== 2);

  console.log('\n[an item nobody has]');
  check('is absent rather than zero, so the page can draw a dash',
    c2.byKey['definitely_not_a_real_item_key'] === undefined);

  for (const i of [1, 2, 3]) {
    await db.pool.query('DELETE FROM tc_user_items WHERE nickname = $1', [nick(i)]);
    await db.pool.query('DELETE FROM tc_user_equips WHERE nickname = $1', [nick(i)]);
    await db.pool.query('DELETE FROM tc_users WHERE nickname = $1', [nick(i)]);
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
