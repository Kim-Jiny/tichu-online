'use strict';
/**
 * A recycled nickname starts empty.
 *
 * Deleting an account is a soft delete: the account row is renamed, but match
 * history, the gold ledger and reports stay behind under the ORIGINAL nickname
 * on purpose (other players' games must keep naming who they played against).
 * The nickname itself, though, becomes available again — so whoever registers
 * it next used to open their profile and find a stranger's record in it.
 *
 * This locks down the fix: every nickname-keyed history read is bounded by the
 * account's own created_at.
 */

const { Client } = require('pg');

const DB_NAME = 'tichu_recycle_test';
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

  const NICK = '재활용닉';
  const raw = new Client({ connectionString: TEST_DB_URL });
  await raw.connect();

  try {
    // ── first owner: one match, one gold ledger row, one report ──────────
    const first = await db.registerUser('recycle_a', 'test1234!', NICK);
    check(first.success, 'first owner registers');

    await raw.query(
      `INSERT INTO tc_match_history
         (player_a1, player_a2, player_b1, player_b2, winner_team,
          team_a_score, team_b_score, is_ranked)
       VALUES ($1, 'p2', 'p3', 'p4', 'A', 1000, 400, TRUE)`, [NICK]);
    await raw.query(
      `INSERT INTO tc_gold_history (nickname, gold_delta, source, title, description)
       VALUES ($1, 500, 'admin', 'admin_grant', '')`, [NICK]);
    await raw.query(
      `INSERT INTO tc_reports (reporter_nickname, reported_nickname, reason)
       VALUES ('someone', $1, '욕설/비방')`, [NICK]);

    const beforeMatches = await db.getRecentMatches(NICK, 20);
    const beforeGold = await db.getGoldHistory(NICK, 30);
    const beforeProfile = await db.getUserProfile(NICK);
    check(beforeMatches.length === 1, 'first owner sees their match');
    check(beforeGold.history.length >= 1, 'first owner sees their gold history');
    check(beforeProfile.reportCount === 1, 'first owner carries their report count');

    // ── the account is deleted, and the nickname comes free ──────────────
    const del = await db.deleteUser(NICK);
    check(del.success, 'account deleted');
    const still = await raw.query(
      `SELECT COUNT(*) FROM tc_match_history WHERE player_a1 = $1`, [NICK]);
    check(Number(still.rows[0].count) === 1,
      'the match row itself is kept (other players still name them)');

    // ── second owner takes the same nickname ─────────────────────────────
    // Delay so created_at is strictly later than the old rows; without the
    // fix this is exactly the moment the record leaks over.
    await new Promise((r) => setTimeout(r, 1100));
    const second = await db.registerUser('recycle_b', 'test1234!', NICK);
    check(second.success, 'the nickname is free again');

    const matches = await db.getRecentMatches(NICK, 20);
    const gold = await db.getGoldHistory(NICK, 30);
    const profile = await db.getUserProfile(NICK);
    check(matches.length === 0, 'new owner starts with no match history');
    check(gold.history.length === 0, 'new owner starts with an empty gold ledger');
    check(profile.reportCount === 0, 'new owner starts with no reports');
    check(profile.totalGames === 0, 'new owner starts at zero games');
    check(!profile.customTitleText, 'new owner has no custom title');

    // ── and their own new rows still show up ─────────────────────────────
    await raw.query(
      `INSERT INTO tc_match_history
         (player_a1, player_a2, player_b1, player_b2, winner_team,
          team_a_score, team_b_score, is_ranked)
       VALUES ($1, 'q2', 'q3', 'q4', 'B', 300, 1000, FALSE)`, [NICK]);
    const own = await db.getRecentMatches(NICK, 20);
    check(own.length === 1, 'new owner sees matches played after registering');

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
