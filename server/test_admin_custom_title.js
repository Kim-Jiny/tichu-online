'use strict';
/**
 * An operator writes a title from the console.
 *
 * The rules that exist to keep players honest do not apply here: an operator
 * title is usually the one thing a player may not write ("운영자"), it is longer
 * than four characters, and the account has never bought the pass. What must
 * still hold is that it actually shows — every display path asks whether a
 * custom-title pass is live, so writing the text alone would leave it visible
 * nowhere.
 */

const { Client } = require('pg');

const DB_NAME = 'tichu_admin_title_test';
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
  const { validateAdminTitle, validateCustomTitle } = require('./moderation/customTitle');

  const raw = new Client({ connectionString: TEST_DB_URL });
  await raw.connect();

  try {
    // ── what the operator form accepts, and what it still refuses ────────
    const staff = validateAdminTitle('운영자', 'rose');
    check(staff.ok, 'accepts a staff word the player validator rejects');
    check(!validateCustomTitle('운영자', 'rose').ok, '…and the player path still refuses it');

    const long = validateAdminTitle('총괄 운영자 김진영', 'blue');
    check(long.ok, 'accepts more than four characters, spaces included');
    check(!validateCustomTitle('총괄 운영자 김진영', 'blue').ok,
      '…which the player path caps at four');

    check(validateAdminTitle('GM★서포트', 'amber').ok, 'accepts symbols outside the allow-list');
    check(!validateAdminTitle('운​영자', 'rose').ok, 'still refuses invisible characters');
    check(!validateAdminTitle('아'.repeat(25), 'rose').ok, 'still refuses past the column width');
    check(!validateAdminTitle('운영자', 'chartreuse').ok, 'still refuses a colour off the palette');
    check(!validateAdminTitle('   ', 'rose').ok, 'still refuses an all-space title');

    // ── writing it onto an account that never bought the pass ────────────
    await db.registerUser('adm_op', 'test1234!', '운영자계정');
    const set = await db.setCustomTitleByAdmin('운영자계정', '운영자', 'rose');
    check(set.success, 'writes onto an account with no entitlement');

    const profile = await db.getUserProfile('운영자계정');
    check(profile.titleName === '운영자', 'the title is what the profile reports');
    check(profile.titleKey === 'custom:rose', 'worn in the title slot');
    check(profile.hasCustomTitle === true, 'the pass it needs was granted alongside');

    const granted = await raw.query(
      `SELECT ui.expires_at, ui.source FROM tc_user_items ui
       JOIN tc_shop_items si ON si.item_key = ui.item_key
       WHERE ui.nickname = '운영자계정' AND si.effect_type = 'custom_title'`);
    check(granted.rowCount === 1, 'exactly one pass granted');
    check(granted.rows[0].expires_at === null, 'and it does not expire');
    check(granted.rows[0].source === 'admin', 'marked as an operator grant, not a purchase');

    // ── a paying player's own expiry is not touched ──────────────────────
    await db.registerUser('adm_payer', 'test1234!', '구매자');
    await raw.query(
      `INSERT INTO tc_user_items (nickname, item_key, expires_at, is_active, source)
       VALUES ('구매자', 'custom_title_7d', NOW() + INTERVAL '3 days', TRUE, 'shop')`);
    const before = (await raw.query(
      `SELECT expires_at FROM tc_user_items WHERE nickname = '구매자'`)).rows[0].expires_at;
    await db.setCustomTitleByAdmin('구매자', '이벤트 우승자', 'violet');
    const after = await raw.query(
      `SELECT expires_at, source FROM tc_user_items WHERE nickname = '구매자'`);
    check(after.rowCount === 1, 'no second pass stacked on a buyer');
    check(after.rows[0].expires_at.getTime() === before.getTime(),
      'the buyer\'s expiry is left exactly as it was');
    check((await db.getUserProfile('구매자')).titleName === '이벤트 우승자',
      'and the operator title shows on them too');

    // ── a switched-off pass would have hidden it ─────────────────────────
    await raw.query(
      `INSERT INTO tc_user_feature_off (nickname, effect_type) VALUES ('구매자', 'custom_title')
       ON CONFLICT DO NOTHING`);
    await db.setCustomTitleByAdmin('구매자', '재지정', 'teal');
    const off = await raw.query(
      `SELECT 1 FROM tc_user_feature_off WHERE nickname = '구매자' AND effect_type = 'custom_title'`);
    check(off.rowCount === 0, 'switching the feature off no longer hides an operator title');

    // ── clearing still works, and leaves the account usable ──────────────
    await db.clearCustomTitle('운영자계정');
    const cleared = await db.getUserProfile('운영자계정');
    check(!cleared.titleName, 'clear removes the title');
    check(cleared.hasCustomTitle === true, '…and leaves the pass, as it does for players');

    check(!(await db.setCustomTitleByAdmin('없는사람', '운영자', 'rose')).success,
      'refuses a nickname with no account');

    console.log(failures ? `\n${failures} FAILED` : '\nALL PASS');
  } catch (e) {
    console.log(`\nFAIL: ${e.message}\n${e.stack}`);
    failures++;
  } finally {
    await raw.end();
    process.exit(failures ? 1 : 0);
  }
}

main();
