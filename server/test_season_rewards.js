'use strict';
/**
 * Season payouts follow the console, not the source.
 *
 * The tiers used to be a literal in grantSeasonRewards (1위 1000 / 2위 500 /
 * 3위 200 + a 30-day banner). They now come from tc_season_reward_config, which
 * means two things have to hold: an install that was never configured must pay
 * exactly what it always did, and a season with its own tiers must use those
 * instead — including the parts that could not be expressed before, like a
 * gold-only rank or a banner that lasts longer than 30 days.
 */

const { Client } = require('pg');

const DB_NAME = 'tichu_season_rewards_test';
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

  const raw = new Client({ connectionString: TEST_DB_URL });
  await raw.connect();

  const goldOf = async (nick) => (await raw.query(
    'SELECT gold FROM tc_users WHERE nickname = $1', [nick])).rows[0].gold;
  const seasonItems = async (nick) => (await raw.query(
    `SELECT item_key, expires_at FROM tc_user_items
     WHERE nickname = $1 AND source = 'season' ORDER BY item_key`, [nick])).rows;

  // Three players, ranked 1-2-3 in every mode.
  const ranked = ['일등', '이등', '삼등'];
  async function seedPlayers() {
    for (let i = 0; i < ranked.length; i++) {
      await db.registerUser(`sr_user${i}`, 'test1234!', ranked[i]);
      const rating = 2000 - i * 100;
      await raw.query(
        `UPDATE tc_users SET gold = 0,
           season_games = 10, season_wins = 5, season_rating = $2,
           sk_season_games = 10, sk_season_wins = 5, sk_season_rating = $2,
           mighty_season_games = 10, mighty_season_wins = 5, mighty_season_rating = $2
         WHERE nickname = $1`, [ranked[i], rating]);
    }
  }
  async function openSeason(name) {
    await raw.query(`UPDATE tc_seasons SET status = 'closed' WHERE status = 'active'`);
    await db.createSeason(name, new Date(Date.now() - 86400000), new Date(Date.now() + 86400000));
    return (await raw.query(
      `SELECT id FROM tc_seasons WHERE name = $1 ORDER BY id DESC LIMIT 1`, [name])).rows[0].id;
  }
  const clearPayouts = async () => {
    await raw.query('DELETE FROM tc_season_rewards');
    await raw.query(`DELETE FROM tc_user_items WHERE source = 'season'`);
    await raw.query('UPDATE tc_users SET gold = 0');
  };

  try {
    await seedPlayers();

    // ── an install nobody configured pays what it always paid ────────────
    const defaults = await db.getSeasonRewardConfig(null);
    check(defaults.rows.length === 9, 'the default set seeds 3 ranks × 3 games');
    check(!(await db.getSeasonRewardConfig(12345)).custom,
      'a season with no rows of its own reports as inheriting');

    const s1 = await openSeason('T1');
    check((await db.grantSeasonRewards(s1)).success, 'closing a season pays out');

    // 1000 + 1000 + 1000 across the three modes.
    check(await goldOf('일등') === 3000, '1위 gets the historical 1000 in each mode');
    check(await goldOf('이등') === 1500, '2위 gets 500 in each mode');
    check(await goldOf('삼등') === 600, '3위 gets 200 in each mode');
    const firstItems = await seasonItems('일등');
    check(firstItems.length === 3, '1위 gets one banner per mode');
    check(firstItems.some((i) => i.item_key === 'banner_season_gold')
      && firstItems.some((i) => i.item_key === 'banner_sk_season_gold')
      && firstItems.some((i) => i.item_key === 'banner_mighty_season_gold'),
      'and they are the per-game gold banners');
    check((await raw.query(
      `SELECT COUNT(*)::int n FROM tc_season_rewards WHERE season_id = $1`, [s1])).rows[0].n === 9,
      'nine payout rows recorded');

    // ── a season with its own tiers uses them ────────────────────────────
    await clearPayouts();
    const s2 = await openSeason('T2');
    await db.saveSeasonRewardConfig(s2, [
      // gold-only rank, which the old literal could not express
      { game_type: 'tichu', rank: 1, gold: 5000, banner_key: '', banner_days: 30 },
      // a banner that outlives the old fixed 30 days
      { game_type: 'tichu', rank: 2, gold: 2000, banner_key: 'banner_season_silver', banner_days: 60 },
      // a rank deeper than the old top-3
      { game_type: 'tichu', rank: 3, gold: 100, banner_key: null, banner_days: 30 },
      { game_type: 'skull_king', rank: 1, gold: 777, banner_key: 'banner_sk_season_gold', banner_days: 30 },
    ]);
    check((await db.getSeasonRewardConfig(s2)).custom, 'the season now reports as configured');
    check((await db.grantSeasonRewards(s2)).success, 'closing it pays out');

    check(await goldOf('일등') === 5000 + 777, '1위 gets the configured tichu + SK gold');
    check(await goldOf('이등') === 2000, '2위 gets the configured tichu gold only');
    check(await goldOf('삼등') === 100, '3위 gets the configured tichu gold only');

    const winner = await seasonItems('일등');
    check(winner.length === 1 && winner[0].item_key === 'banner_sk_season_gold',
      'a blank banner key means gold only — no empty item granted');
    const second = await seasonItems('이등');
    check(second.length === 1 && second[0].item_key === 'banner_season_silver',
      '2위 gets the banner that was configured');
    const days = Math.round((new Date(second[0].expires_at) - Date.now()) / 86400000);
    check(days >= 59 && days <= 60, '…for the configured 60 days, not the old fixed 30');

    check((await raw.query(
      `SELECT COUNT(*)::int n FROM tc_season_rewards WHERE season_id = $1`, [s2])).rows[0].n === 4,
      'only the configured tiers are recorded');
    check((await raw.query(
      `SELECT COUNT(*)::int n FROM tc_season_rewards WHERE season_id = $1 AND rank = 1 AND gold_reward = 5000`,
      [s2])).rows[0].n === 1, 'the payout row carries the configured amount');

    // ── clearing a season's rows puts it back on the defaults ────────────
    await clearPayouts();
    await db.clearSeasonRewardConfig(s2);
    check(!(await db.getSeasonRewardConfig(s2)).custom, 'reset drops back to inheriting');
    const s3 = await openSeason('T3');
    await db.grantSeasonRewards(s3);
    check(await goldOf('일등') === 3000, 'and a later season pays the default again');

    // ── editing the defaults changes every unconfigured season ───────────
    await clearPayouts();
    await db.saveSeasonRewardConfig(null, [
      { game_type: 'tichu', rank: 1, gold: 9999, banner_key: 'banner_season_gold', banner_days: 30 },
    ]);
    const s4 = await openSeason('T4');
    await db.grantSeasonRewards(s4);
    check(await goldOf('일등') === 9999, 'the new default applies');
    check(await goldOf('이등') === 0, 'and a rank that no longer exists pays nothing');

    // ── 보상 감사(대시보드) ───────────────────────────────────────────
    // The console's payout view compares three things that live apart —
    // ranking snapshot, configured tier, actual payout — so its rules are
    // worth pinning: what counts as a problem, and what merely looks like one.
    await clearPayouts();
    await db.saveSeasonRewardConfig(null, [
      { game_type: 'tichu', rank: 1, gold: 1000, banner_key: 'banner_season_gold', banner_days: 30 },
      { game_type: 'tichu', rank: 2, gold: 500, banner_key: 'banner_season_silver', banner_days: 30 },
      { game_type: 'tichu', rank: 3, gold: 200, banner_key: 'banner_season_bronze', banner_days: 30 },
    ]);
    const s5 = await openSeason('T5');
    await db.grantSeasonRewards(s5);
    const audit = await db.getSeasonRewardAudit(s5);
    check(!!audit, 'the audit reads back');
    const tichu = audit.games.find((g) => g.gameType === 'tichu');
    check(tichu.rows.length === 3, 'one row per configured tier');
    check(tichu.rows[0].nickname === '일등' && tichu.rows[0].granted?.gold === 1000,
      'the row carries who was paid and how much');
    check(tichu.rows.every((r) => r.issues.length === 0), 'a clean payout flags nothing');
    check(audit.summary.issueCount === 0, 'and the headline count is zero');
    check(audit.unmatched.length === 0, 'every payout row is attributed to a game');

    // A tier nobody qualified for is reported, but is not a problem to fix:
    // a young season has fewer ranked players than configured ranks.
    await clearPayouts();
    await db.saveSeasonRewardConfig(null, [
      { game_type: 'tichu', rank: 1, gold: 1000, banner_key: 'banner_season_gold', banner_days: 30 },
      { game_type: 'tichu', rank: 9, gold: 100, banner_key: null, banner_days: 30 },
    ]);
    const s6 = await openSeason('T6');
    await db.grantSeasonRewards(s6);
    const sparse = await db.getSeasonRewardAudit(s6);
    const empty = sparse.games.find((g) => g.gameType === 'tichu').rows.find((r) => r.rank === 9);
    check(empty.issues.includes('no_recipient'), 'an empty rank is reported');
    check(sparse.summary.issueCount === 0, '…but does not count as something to fix');

    // The one that does need eyes: a payout row that is missing while the
    // winner is still around.
    await raw.query(`DELETE FROM tc_season_rewards WHERE season_id = $1 AND rank = 1`, [s6]);
    const holed = await db.getSeasonRewardAudit(s6);
    const missing = holed.games.find((g) => g.gameType === 'tichu').rows.find((r) => r.rank === 1);
    check(missing.issues.includes('not_granted'), 'a missing payout is flagged');
    check(holed.summary.issueCount === 1, 'and it is counted');

    // ── 같은 달 시즌은 하나뿐 ──────────────────────────────────────────
    // 롤오버는 부팅과 시간별 타이머 양쪽에서 불리고, 배포 교체 순간에는
    // 인스턴스가 둘일 수 있다. 이름이 같은 시즌이 두 번 만들어지면 관리
    // 화면에 "진행 중"이 여러 개 뜬다 — 실제로 2026-08 이 5개가 됐었다.
    const dupA = await db.createSeason('2099-12', new Date(), new Date(Date.now() + 86400000));
    const dupB = await db.createSeason('2099-12', new Date(), new Date(Date.now() + 86400000));
    check(!!dupA && !!dupB && dupA.id === dupB.id,
      '같은 이름으로 다시 만들면 기존 시즌을 돌려준다');
    check((await raw.query(
      `SELECT COUNT(*)::int n FROM tc_seasons WHERE name = '2099-12'`)).rows[0].n === 1,
      '행은 하나만 남는다');

    // ── 설정이 비면 지급하지 않는다 ────────────────────────────────────
    // 마이그레이션이 반쯤 건너뛰어 기본 티어가 없는 상태로 시즌이 닫히면,
    // 아무도 못 받았는데 시즌 성적은 이미 초기화되어 되돌릴 수 없다.
    await clearPayouts();
    const s7 = await openSeason('T7');
    await raw.query('DELETE FROM tc_season_reward_config');
    const noTiers = await db.grantSeasonRewards(s7);
    check(!noTiers.success, '보상 티어가 비어 있으면 지급이 실패로 끝난다');
    check((await raw.query(
      `SELECT status FROM tc_seasons WHERE id = $1`, [s7])).rows[0].status === 'active',
      '시즌도 닫히지 않는다 — 다음 시도에 다시 걸린다');
    check(await goldOf('일등') === 0, '골드도 나가지 않는다');

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
