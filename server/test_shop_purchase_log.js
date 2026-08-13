/**
 * The backstage's "who bought what, when" log.
 *
 * The thing worth testing is that a RENEWAL shows up. buyItem inserts a
 * tc_user_items row the first time someone buys a pass, but a repeat purchase
 * updates that row's expiry and writes a tc_gold_history row instead. A log
 * built on tc_user_items alone therefore reports one sale for a player who has
 * paid five times — and reports nothing at all for an item whose entire
 * revenue is renewals. Nothing errors; the numbers are just quietly low.
 *
 * The page's summary is a separate aggregate from its rows, so it also has to
 * agree with them under the same filters.
 *
 * Talks to the database directly; no server needed.
 *
 * Run: node server/test_shop_purchase_log.js
 */
const db = require('./db/database.js');

let failures = 0;
const check = (label, cond, detail = '') => {
  console.log(`${cond ? '  ok  ' : '  FAIL'} ${label}${!cond && detail ? ` — ${detail}` : ''}`);
  if (!cond) failures++;
};

const run = Date.now().toString(36).slice(-5);
const NICK = `구매${run}`;

(async () => {
  await db.initDatabase();
  await db.pool.query(
    `INSERT INTO tc_users (username, nickname, gold) VALUES ($1, $2, 100000)
     ON CONFLICT (nickname) DO NOTHING`,
    [`buy_${run}`, NICK],
  );

  const item = (await db.pool.query(
    `SELECT item_key, name_ko, name_en, name_de, price FROM tc_shop_items
     WHERE is_permanent = FALSE AND duration_days IS NOT NULL LIMIT 1`)).rows[0];
  if (!item) throw new Error('no time-limited shop item in this database');

  const base = await db.getShopPurchaseLogSummary({ nickname: NICK });
  check('a new account has bought nothing', base.purchases === 0, `${base.purchases}`);

  // A first purchase: the row in tc_user_items is the record.
  await db.pool.query(
    `INSERT INTO tc_user_items (nickname, item_key, expires_at, source)
     VALUES ($1, $2, (NOW() AT TIME ZONE 'UTC') + INTERVAL '30 days', 'shop')`,
    [NICK, item.item_key],
  );
  // Two renewals: exactly what buyItem writes on an extend — the expiry moves
  // on the existing row and the ledger gets the entry.
  for (let i = 0; i < 2; i++) {
    await db.pool.query(
      `INSERT INTO tc_gold_history (nickname, gold_delta, source, title, description)
       VALUES ($1, $2, 'shop_purchase', $3, 'shop_purchase')`,
      [NICK, -item.price, `${item.name_ko}|${item.name_en}|${item.name_de}`],
    );
  }

  console.log('\n[one purchase and two renewals]');
  const log = await db.getShopPurchaseLog({ nickname: NICK, limit: 50 });
  check('all three are listed, not just the one row in tc_user_items',
    log.rows.length === 3, `${log.rows.length} rows`);
  check('one is marked as new',
    log.rows.filter((r) => r.kind === 'new').length === 1);
  check('two are marked as renewals',
    log.rows.filter((r) => r.kind === 'extend').length === 2);
  check('the renewals carry the item key, which the ledger does not store',
    log.rows.filter((r) => r.kind === 'extend').every((r) => r.itemKey === item.item_key),
    log.rows.filter((r) => r.kind === 'extend').map((r) => r.itemKey).join(','));
  check('and its category, so the page can badge them',
    log.rows.every((r) => r.category != null));
  check('every row is charged the price', log.rows.every((r) => r.price === item.price),
    log.rows.map((r) => r.price).join(','));

  console.log('\n[the summary must agree with the rows it sits above]');
  const sum = await db.getShopPurchaseLogSummary({ nickname: NICK });
  check('same count', sum.purchases === 3, `${sum.purchases}`);
  check('renewals counted separately', sum.extends === 2, `${sum.extends}`);
  check('gold adds up', sum.spent === item.price * 3, `${sum.spent}`);
  check('one buyer', sum.buyers === 1, `${sum.buyers}`);

  console.log('\n[newest first]');
  const times = log.rows.map((r) => new Date(r.at).getTime());
  check('rows come back in descending time order',
    times.every((t, i) => i === 0 || times[i - 1] >= t), times.join(','));

  console.log('\n[filters]');
  const byItem = await db.getShopPurchaseLog({
    nickname: NICK, itemKey: item.item_key, limit: 50 });
  check('filtering by item keeps all three', byItem.rows.length === 3);
  const byOther = await db.getShopPurchaseLog({
    nickname: NICK, itemKey: 'definitely_not_real', limit: 50 });
  check('filtering by another item keeps none', byOther.rows.length === 0);
  const partial = await db.getShopPurchaseLog({ nickname: run, limit: 50 });
  check('the nickname filter matches on a fragment', partial.rows.length >= 3,
    `${partial.rows.length}`);

  console.log('\n[paging]');
  const p1 = await db.getShopPurchaseLog({ nickname: NICK, limit: 2, offset: 0 });
  const p2 = await db.getShopPurchaseLog({ nickname: NICK, limit: 2, offset: 2 });
  check('a full first page reports more behind it',
    p1.rows.length === 2 && p1.hasMore === true);
  check('the last page does not', p2.rows.length === 1 && p2.hasMore === false,
    `${p2.rows.length} rows, hasMore=${p2.hasMore}`);

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
