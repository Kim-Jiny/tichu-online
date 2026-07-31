'use strict';
/**
 * The shop edit form must be able to round-trip every item we ship.
 *
 * The form writes back whatever its selects hold, so an item whose category or
 * effect_type is missing from the dropdown is silently rewritten the moment an
 * admin opens it — which is how the profile-photo and custom-title passes ended
 * up filed under 배너 with no effect_type. That is worse than cosmetic: the
 * client-version gate keys off effect_type, so a blanked one exposes a paid
 * entitlement to clients that cannot use it, and the entitlement check stops
 * matching so the buyer gets nothing.
 *
 * This walks the seeded catalog and asserts both dropdowns cover it.
 */

const { Client } = require('pg');

const DB_NAME = 'tichu_admin_form_test';
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

  const { SHOP_EFFECT_TYPES, SHOP_CATEGORIES } = require('./admin');

  const raw = new Client({ connectionString: TEST_DB_URL });
  await raw.connect();
  try {
    const effects = (await raw.query(
      `SELECT DISTINCT effect_type FROM tc_shop_items WHERE effect_type IS NOT NULL`
    )).rows.map((r) => r.effect_type).sort();
    const categories = (await raw.query(
      `SELECT DISTINCT category FROM tc_shop_items WHERE category IS NOT NULL`
    )).rows.map((r) => r.category).sort();

    check(effects.length > 0, `catalog has effect types (${effects.length})`);
    for (const e of effects) {
      check(SHOP_EFFECT_TYPES.includes(e), `effect_type "${e}" is offered by the form`);
    }
    for (const c of categories) {
      check(SHOP_CATEGORIES.includes(c), `category "${c}" is offered by the form`);
    }

    // ── an everyday edit cannot reshape an item ─────────────────────────
    // The console's edit form leaves the structural fields out unless they are
    // unlocked, and the update must then leave them alone. This is the exact
    // shape of the payload that form sends when locked.
    const before = (await raw.query(
      `SELECT id, category, effect_type, duration_days, is_permanent, is_season
       FROM tc_shop_items WHERE item_key = 'custom_title_7d'`)).rows[0];
    check(!!before, 'custom_title_7d is in the catalog');

    const db2 = require('./db/database');
    const upd = await db2.updateShopItem(before.id, {
      name_ko: '커스텀 칭호 (7일)', name_en: 'Custom title (7d)', name_de: 'Eigener Titel (7T)',
      description_ko: '', description_en: '', description_de: '',
      price: 700, is_purchasable: true, sale_start: null, sale_end: null,
    });
    check(upd.success, 'a locked-form edit saves');

    const after = (await raw.query(
      `SELECT category, effect_type, duration_days, is_permanent, is_season, price
       FROM tc_shop_items WHERE item_key = 'custom_title_7d'`)).rows[0];
    check(after.price === 700, 'the price it did send is written');
    check(after.category === before.category, 'category survives an edit that omits it');
    check(after.effect_type === before.effect_type, 'effect_type survives an edit that omits it');
    check(after.duration_days === before.duration_days, 'duration survives');
    check(after.is_permanent === before.is_permanent, 'permanence survives');
    check(after.is_season === before.is_season, 'season flag survives');

    // …and an unlocked edit still can, on purpose.
    const reshaped = await db2.updateShopItem(before.id, { category: 'utility' });
    check(reshaped.success && reshaped.item.category === 'utility',
      'an unlocked edit still changes it');
    await raw.query(
      `UPDATE tc_shop_items SET category = $1 WHERE id = $2`, [before.category, before.id]);

    console.log(failures ? `\n${failures} FAILED` : '\nALL PASS');
  } catch (e) {
    console.log(`\nFAIL: ${e.message}`);
    failures++;
  } finally {
    await raw.end();
    process.exit(failures ? 1 : 0);
  }
}

main();
