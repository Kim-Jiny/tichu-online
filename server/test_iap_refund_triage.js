'use strict';
/**
 * A store refund we cannot claw back has to land in the triage queue.
 *
 * The auto path never takes a balance negative: if the player already spent
 * the gold, the receipt is parked as 'refund_failed' for an admin to decide.
 * That status is 13 characters and the column was VARCHAR(12), so the write
 * threw 22001 and rolled the whole transaction back — in production, every 30
 * minutes, forever, because the Voided Purchases poll re-lists the same
 * purchase and nothing ever recorded that it had been handled. The money was
 * refunded by Google and nobody on our side ever saw it.
 *
 * Nothing caught it because the happy path fits: 'refunded' is 8 characters.
 * So this test drives the branch that does not fit, on a real database.
 *
 * Run: node server/test_iap_refund_triage.js
 */
const { Client } = require('pg');

const DB_NAME = 'tichu_iap_refund_test';
const TEST_DB_URL = process.env.TEST_DATABASE_URL
  || `postgresql://jiny@localhost:5432/${DB_NAME}`;

let failures = 0;
function check(cond, msg, detail = '') {
  if (cond) console.log(`  ok   ${msg}`);
  else { failures++; console.log(`  FAIL ${msg}${detail ? ` — ${detail}` : ''}`); }
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

  const receipt = async (nickname, txn, gold) => {
    await raw.query(
      `INSERT INTO tc_iap_receipts
         (nickname, product_id, platform, transaction_id, gold_granted, environment, status)
       VALUES ($1, 'gold_1000', 'android', $2, $3, 'production', 'granted')`,
      [nickname, txn, gold],
    );
  };
  const statusOf = async (txn) => (await raw.query(
    `SELECT status, refund_source, refund_reason, refund_detected_at
       FROM tc_iap_receipts WHERE transaction_id = $1`, [txn])).rows[0];
  const goldOf = async (nick) => Number((await raw.query(
    `SELECT gold FROM tc_users WHERE nickname = $1`, [nick])).rows[0].gold);

  try {
    // ── the player still has the gold: a plain clawback ──────────────────
    console.log('\n[돈이 남아 있으면 그냥 회수한다]');
    await db.registerUser('iap_rich', 'test1234!', '부자');
    await raw.query(`UPDATE tc_users SET gold = 5000 WHERE nickname = '부자'`);
    await receipt('부자', 'GPA.RICH-0001', 1000);
    const okRefund = await db.autoRefundByTransaction({
      transactionId: 'GPA.RICH-0001', source: 'google', reason: 'voided:1',
    });
    check(okRefund.success === true, '환불이 성공한다', JSON.stringify(okRefund));
    check((await statusOf('GPA.RICH-0001')).status === 'refunded', '영수증이 refunded 가 된다');
    check(await goldOf('부자') === 4000, '골드가 정확히 회수된다', `gold=${await goldOf('부자')}`);

    // ── the player spent it: park, do not go negative ────────────────────
    console.log('\n[이미 써버렸으면 잔액을 건드리지 않고 대기열로]');
    await db.registerUser('iap_broke', 'test1234!', '탕진');
    await raw.query(`UPDATE tc_users SET gold = 10 WHERE nickname = '탕진'`);
    await receipt('탕진', 'GPA.BROKE-0001', 1000);
    const parked = await db.autoRefundByTransaction({
      transactionId: 'GPA.BROKE-0001', source: 'google', reason: 'voided:1',
    });
    check(parked.success === true, '호출이 예외 없이 끝난다', JSON.stringify(parked));
    check(parked.marked === 'refund_failed', 'refund_failed 로 표시했다고 답한다', JSON.stringify(parked));
    const row = await statusOf('GPA.BROKE-0001');
    check(row.status === 'refund_failed', '영수증이 실제로 대기열에 들어간다', `status=${row.status}`);
    check(row.refund_detected_at != null, '언제 감지했는지 남는다');
    check(row.refund_source === 'google', '어디서 온 환불인지 남는다', `${row.refund_source}`);
    check(await goldOf('탕진') === 10, '잔액은 마이너스로 가지 않는다', `gold=${await goldOf('탕진')}`);

    // ── and the poll must not keep re-doing it every 30 minutes ──────────
    console.log('\n[같은 환불을 다시 봐도 조용해야 한다]');
    const again = await db.autoRefundByTransaction({
      transactionId: 'GPA.BROKE-0001', source: 'google', reason: 'voided:1',
    });
    check(again.idempotent === true || again.success === true,
      '두 번째 폴링은 멱등하게 지나간다', JSON.stringify(again));
    check(await goldOf('탕진') === 10, '두 번째에도 잔액은 그대로');

    // ── every status the code writes must fit the column ─────────────────
    console.log('\n[컬럼 폭]');
    const width = (await raw.query(
      `SELECT character_maximum_length AS n FROM information_schema.columns
        WHERE table_name = 'tc_iap_receipts' AND column_name = 'status'`)).rows[0].n;
    for (const s of ['granted', 'refunded', 'refund_failed']) {
      check(s.length <= width, `'${s}' (${s.length}자) 가 status(${width}) 에 들어간다`);
    }
    const srcWidth = (await raw.query(
      `SELECT character_maximum_length AS n FROM information_schema.columns
        WHERE table_name = 'tc_iap_receipts' AND column_name = 'refund_source'`)).rows[0].n;
    for (const s of ['google', 'apple', 'manual', 'admin_google']) {
      check(s.length <= srcWidth, `'${s}' (${s.length}자) 가 refund_source(${srcWidth}) 에 들어간다`);
    }

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
