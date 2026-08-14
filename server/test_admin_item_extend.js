/**
 * Extending a user's time-limited item from the backstage.
 *
 * The two rules that are easy to get wrong, and silent when you do:
 *
 *  - An EXPIRED pass extends from now, not from its old expiry. "+7 days" on
 *    something that ran out two months ago must give seven usable days, not
 *    move a date that is still in the past. Nothing errors either way; the
 *    player just still cannot use what support told them they got back.
 *  - The arithmetic stays in UTC. These columns are `timestamp without time
 *    zone` holding UTC values, and doing the maths in JS puts the answer back
 *    through node-pg in the process timezone — nine hours out on a KST host.
 *    Run this under both TZ=UTC and TZ=Asia/Seoul; the numbers must match.
 *
 * Talks to the database directly; no server needed.
 *
 * Run: node server/test_admin_item_extend.js
 */
const db = require('./db/database.js');

let failures = 0;
const check = (label, cond, detail = '') => {
  console.log(`${cond ? '  ok  ' : '  FAIL'} ${label}${!cond && detail ? ` — ${detail}` : ''}`);
  if (!cond) failures++;
};

const run = Date.now().toString(36).slice(-5);
const NICK = `연장${run}`;

/// Hours from now until the row's expiry, read back through the same path the
/// admin page renders with.
async function hoursLeft(itemKey) {
  const r = await db.pool.query(
    `SELECT EXTRACT(EPOCH FROM (expires_at - (NOW() AT TIME ZONE 'UTC'))) / 3600 AS h
     FROM tc_user_items WHERE nickname = $1 AND item_key = $2`,
    [NICK, itemKey],
  );
  return r.rows[0] ? Number(r.rows[0].h) : null;
}

/// Put a row in with an expiry N days from now (negative = already lapsed).
async function give(itemKey, daysFromNow) {
  await db.pool.query('DELETE FROM tc_user_items WHERE nickname = $1 AND item_key = $2',
    [NICK, itemKey]);
  await db.pool.query(
    `INSERT INTO tc_user_items (nickname, item_key, expires_at, source)
     VALUES ($1, $2, (NOW() AT TIME ZONE 'UTC') + ($3 || ' days')::interval, 'admin')`,
    [NICK, itemKey, daysFromNow],
  );
}

(async () => {
  await db.initDatabase();
  await db.pool.query(
    `INSERT INTO tc_users (username, nickname, gold) VALUES ($1, $2, 0)
     ON CONFLICT (nickname) DO NOTHING`,
    [`ext_${run}`, NICK],
  );

  const tempItem = (await db.pool.query(
    `SELECT item_key FROM tc_shop_items
     WHERE is_permanent = FALSE AND duration_days IS NOT NULL LIMIT 1`)).rows[0]?.item_key;
  const permItem = (await db.pool.query(
    `SELECT item_key FROM tc_shop_items WHERE is_permanent = TRUE LIMIT 1`)).rows[0]?.item_key;
  if (!tempItem) throw new Error('no time-limited shop item in this database');

  console.log(`\n[a live pass — TZ=${process.env.TZ || '(host default)'}]`);
  await give(tempItem, 3);
  const before = await hoursLeft(tempItem);
  const ext = await db.adminExtendUserItem(NICK, tempItem, 7, 'tester');
  check('the extend succeeds', ext.success === true, ext.message);
  const after = await hoursLeft(tempItem);
  check('seven days are added to what was left',
    Math.abs((after - before) - 168) < 0.2, `${before}h → ${after}h`);
  check('and it is 10 days out, not 7 — the remainder was kept',
    Math.abs(after - 240) < 0.5, `${after}h`);

  console.log('\n[a pass that ran out two months ago]');
  await give(tempItem, -60);
  const ext2 = await db.adminExtendUserItem(NICK, tempItem, 7, 'tester');
  check('the extend succeeds', ext2.success === true, ext2.message);
  const revived = await hoursLeft(tempItem);
  check('it comes back with a full seven days from now',
    Math.abs(revived - 168) < 0.5, `${revived}h`);
  check('not still in the past', revived > 0, `${revived}h`);

  console.log('\n[shortening]');
  await give(tempItem, 30);
  await db.adminExtendUserItem(NICK, tempItem, -25, 'tester');
  const short = await hoursLeft(tempItem);
  check('a negative day count takes time off',
    Math.abs(short - 120) < 0.5, `${short}h`);

  console.log('\n[what it refuses]');
  check('zero days', (await db.adminExtendUserItem(NICK, tempItem, 0)).success === false);
  check('a non-number', (await db.adminExtendUserItem(NICK, tempItem, 'abc')).success === false);
  check('an absurd span', (await db.adminExtendUserItem(NICK, tempItem, 99999)).success === false);
  check('an item they do not own',
    (await db.adminExtendUserItem(NICK, 'no_such_item_key', 7)).success === false);
  if (permItem) {
    await db.pool.query(
      `INSERT INTO tc_user_items (nickname, item_key, expires_at, source)
       VALUES ($1, $2, NULL, 'admin')`, [NICK, permItem]);
    const perm = await db.adminExtendUserItem(NICK, permItem, 7);
    check('a permanent item, rather than pinning an expiry onto it',
      perm.success === false, perm.message);
  } else {
    console.log('  skip  no permanent shop item in this database');
  }

  console.log('\n[the profile-photo pass, which lives on tc_users]');
  await db.pool.query(
    `UPDATE tc_users SET profile_photo_status = 'active',
       profile_photo_expires_at = (NOW() AT TIME ZONE 'UTC') - INTERVAL '5 days'
     WHERE nickname = $1`, [NICK]);
  const photo = await db.adminExtendUserItem(NICK, 'profile_photo', 14, 'tester');
  check('it extends too', photo.success === true, photo.message);
  const photoLeft = (await db.pool.query(
    `SELECT EXTRACT(EPOCH FROM (profile_photo_expires_at - (NOW() AT TIME ZONE 'UTC')))/3600 AS h
     FROM tc_users WHERE nickname = $1`, [NICK])).rows[0].h;
  check('from now, since it had lapsed',
    Math.abs(Number(photoLeft) - 336) < 0.5, `${photoLeft}h`);

  console.log('\n[the inventory the admin page reads]');
  const inv = await db.getAdminUserInventory(NICK);
  check('it lists what they hold', inv.success === true && inv.items.length > 0,
    `${inv.items?.length} rows`);
  check('including the profile-photo pass, which is not a tc_user_items row',
    inv.items.some((i) => i.kind === 'profile_photo'));
  // The player's own getUserItems deletes expired rows on the way past. The
  // admin view must not: an expired pass is the one support gets asked about.
  await give(tempItem, -3);
  const invExpired = await db.getAdminUserInventory(NICK);
  check('and expired rows, which it must not quietly delete',
    invExpired.items.some((i) => i.item_key === tempItem));
  check('the row is still there afterwards',
    (await hoursLeft(tempItem)) < 0);

  // ── 회수 ────────────────────────────────────────────────────────────────
  // The mirror of extending, and the part that is easy to half-do: the row
  // goes but the seat keeps drawing the banner, or a duplicate row survives
  // and the item is still there after support said they took it.
  console.log('\n[회수]');
  await give(tempItem, 30);
  await db.pool.query(
    `INSERT INTO tc_user_equips (nickname, banner_key) VALUES ($1, $2)
     ON CONFLICT (nickname) DO UPDATE SET banner_key = EXCLUDED.banner_key`,
    [NICK, tempItem],
  );
  const rev = await db.adminRevokeUserItem(NICK, tempItem, { adminActor: 'tester' });
  check('회수가 성공한다', rev.success === true, rev.message);
  check('아이템 행이 사라진다', (await hoursLeft(tempItem)) === null);
  const equipAfter = (await db.pool.query(
    'SELECT banner_key FROM tc_user_equips WHERE nickname = $1', [NICK])).rows[0];
  check('착용 중이던 슬롯이 비워진다', equipAfter?.banner_key === null, `${equipAfter?.banner_key}`);
  check('인벤토리에서도 안 보인다',
    !(await db.getAdminUserInventory(NICK)).items.some((i) => i.item_key === tempItem));

  console.log('\n[중복 보유를 회수하면]');
  await give(tempItem, 10);
  await db.pool.query(
    `INSERT INTO tc_user_items (nickname, item_key, expires_at, source)
     VALUES ($1, $2, (NOW() AT TIME ZONE 'UTC') + INTERVAL '5 days', 'coupon')`,
    [NICK, tempItem],
  );
  const dup = await db.adminRevokeUserItem(NICK, tempItem, { adminActor: 'tester' });
  check('한 번에 다 없어진다', dup.success === true && dup.removed === 2, `removed=${dup.removed}`);
  check('정말 하나도 안 남는다', (await hoursLeft(tempItem)) === null);

  console.log('\n[골드 환불을 선택하면]');
  const price = Number((await db.pool.query(
    'SELECT price FROM tc_shop_items WHERE item_key = $1', [tempItem])).rows[0].price);
  await db.pool.query('UPDATE tc_users SET gold = 100 WHERE nickname = $1', [NICK]);
  await give(tempItem, 10);
  const refunded = await db.adminRevokeUserItem(NICK, tempItem, { refundGold: true, adminActor: 'tester' });
  const goldNow = Number((await db.pool.query(
    'SELECT gold FROM tc_users WHERE nickname = $1', [NICK])).rows[0].gold);
  check('구매가만큼 돌려준다', refunded.refunded === price && goldNow === 100 + price,
    `refunded=${refunded.refunded} gold=${goldNow} price=${price}`);
  const ledger = (await db.pool.query(
    `SELECT gold_delta, title FROM tc_gold_history
      WHERE nickname = $1 ORDER BY id DESC LIMIT 1`, [NICK])).rows[0];
  check('골드 내역에 사유가 남는다',
    ledger && Number(ledger.gold_delta) === price && ledger.title === 'item_revoke_refund',
    JSON.stringify(ledger));

  console.log('\n[환불을 선택하지 않으면]');
  await give(tempItem, 10);
  const goldBefore = Number((await db.pool.query(
    'SELECT gold FROM tc_users WHERE nickname = $1', [NICK])).rows[0].gold);
  await db.adminRevokeUserItem(NICK, tempItem, { adminActor: 'tester' });
  const goldAfter = Number((await db.pool.query(
    'SELECT gold FROM tc_users WHERE nickname = $1', [NICK])).rows[0].gold);
  check('골드는 그대로다', goldAfter === goldBefore, `${goldBefore} → ${goldAfter}`);

  console.log('\n[없는 아이템을 회수하려 하면]');
  const missing = await db.adminRevokeUserItem(NICK, tempItem, { adminActor: 'tester' });
  check('가지고 있지 않다고 답한다', missing.success === false, JSON.stringify(missing));

  await db.pool.query('DELETE FROM tc_user_equips WHERE nickname = $1', [NICK]);
  await db.pool.query('DELETE FROM tc_gold_history WHERE nickname = $1', [NICK]);
  await db.pool.query('DELETE FROM tc_user_items WHERE nickname = $1', [NICK]);
  await db.pool.query('DELETE FROM tc_users WHERE nickname = $1', [NICK]);
})()
  .then(() => {
    console.log(failures === 0 ? '\nPASS' : `\n${failures} FAILURE(S)`);
    process.exit(failures === 0 ? 0 : 1);
  })
  .catch((e) => {
    console.error('\nERROR', e.message);
    process.exit(1);
  });
