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
