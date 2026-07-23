'use strict';

/**
 * Integration test for BotWorkerPool: real bot decisions computed in worker
 * threads must be legal on the live game, concurrency/queue must work, and a
 * crashed worker must be replaced without losing the pool.
 *
 *   node test_bot_worker_pool.js
 */

const assert = require('assert');
const { BotWorkerPool } = require('./bots/BotWorkerPool');
const MightyGame = require('./game/mighty/MightyGame');
const { decideMightyBotAction } = require('./game/mighty/MightyBot');
const { makeRng } = require('./game/mighty/MightyDeck');
const TichuGame = require('./game/TichuGame');

function legalOnLive(game, actor, action) {
  const probe = game.clone();
  const res = probe.handleAction(actor, action);
  return res && res.success !== false;
}

async function testMighty(pool) {
  const playerIds = ['p0', 'p1', 'p2', 'p3', 'p4'];
  const playerNames = {}; for (const p of playerIds) playerNames[p] = p;
  const game = new MightyGame(playerIds, playerNames, { targetScore: 50, rng: makeRng(7) });
  game.start();
  let checked = 0, safety = 400;
  while (game.state !== 'round_end' && game.state !== 'game_end' && safety-- > 0 && checked < 12) {
    if (game.state === 'trick_end') { game.advanceAfterTrickEnd(); continue; }
    const actor = game.getPendingActor();
    if (!actor) break;
    // Ask the pool with the real (expensive) strategy.
    const action = await pool.decide('mighty', game, actor, 'mixoracle');
    if (action) {
      assert.ok(legalOnLive(game, actor, action),
        `pool mighty action illegal: state=${game.state} actor=${actor} ${JSON.stringify(action)}`);
      checked++;
    }
    // Advance the live game (cheap heuristic keeps the test fast).
    const adv = decideMightyBotAction(game, actor, 'heuristic') || game.getAutoTimeoutAction(actor);
    if (!adv) break;
    const r = game.handleAction(actor, adv);
    if (!r || r.success === false) { const fb = game.getAutoTimeoutAction(actor); if (fb) game.handleAction(actor, fb); else break; }
  }
  assert.ok(checked >= 5, `expected several mighty pool checks, got ${checked}`);
  console.log(`  mighty: ${checked} pool decisions, all legal`);
}

async function testTichu(pool) {
  const playerIds = ['p0', 'p1', 'p2', 'p3'];
  const playerNames = {}; for (const p of playerIds) playerNames[p] = p;
  const game = new TichuGame(playerIds, playerNames);
  game.start();
  // Advance out of the multi-actor setup phases into single-actor playing so
  // legality is unambiguous, using cheap auto actions.
  let safety = 400, checked = 0;
  const { decideBotAction } = require('./game/BotPlayer');
  while (game.state !== 'round_end' && game.state !== 'game_end' && safety-- > 0 && checked < 10) {
    let actor = game.currentPlayer;
    if (game.needsToCallRank) actor = game.needsToCallRank;
    else if (game.dragonPending) actor = game.dragonDecider;
    if (game.state === 'playing' && actor) {
      const action = await pool.decide('tichu', game, actor, 'winrate');
      if (action) {
        assert.ok(legalOnLive(game, actor, action),
          `pool tichu action illegal: actor=${actor} ${JSON.stringify(action)}`);
        checked++;
      }
      const r = game.handleAction(actor, action || game.getAutoTimeoutAction(actor));
      if (!r || r.success === false) { const fb = game.getAutoTimeoutAction(actor); if (fb) game.handleAction(actor, fb); else break; }
    } else {
      // setup phases: drive all pending actors with auto actions
      const actors = (game.state === 'large_tichu_phase' || game.state === 'card_exchange')
        ? game.playerIds.slice() : (actor ? [actor] : []);
      let moved = false;
      for (const a of actors) {
        const act = decideBotAction(game, a, 'heuristic') || game.getAutoTimeoutAction(a);
        if (!act) continue;
        const r = game.handleAction(a, act);
        if (r && r.success) moved = true;
      }
      if (!moved) break;
    }
  }
  assert.ok(checked >= 3, `expected several tichu pool checks, got ${checked}`);
  console.log(`  tichu: ${checked} pool decisions, all legal`);
}

async function testConcurrency(pool) {
  // Fire many decisions from one frozen state at once; the pool must queue
  // beyond its worker count and still resolve every one to a legal action.
  const playerIds = ['p0', 'p1', 'p2', 'p3', 'p4'];
  const playerNames = {}; for (const p of playerIds) playerNames[p] = p;
  const game = new MightyGame(playerIds, playerNames, { targetScore: 50, rng: makeRng(3) });
  game.start();
  // advance to a playing decision point
  let safety = 400, actor = null;
  while (safety-- > 0) {
    if (game.state === 'trick_end') { game.advanceAfterTrickEnd(); continue; }
    actor = game.getPendingActor();
    if (game.state === 'playing' && actor) break;
    if (!actor) break;
    const adv = decideMightyBotAction(game, actor, 'heuristic') || game.getAutoTimeoutAction(actor);
    if (!adv) break;
    game.handleAction(actor, adv);
  }
  assert.ok(actor && game.state === 'playing', 'could not reach a playing state for concurrency test');

  const N = 20;
  const results = await Promise.all(
    Array.from({ length: N }, () => pool.decide('mighty', game, actor, 'mixoracle'))
  );
  for (const action of results) {
    if (action) assert.ok(legalOnLive(game, actor, action), 'concurrent pool action illegal');
  }
  assert.ok(pool.stats.maxQueue > 0, `queue was never exercised (maxQueue=${pool.stats.maxQueue})`);
  assert.strictEqual(pool.inFlight, 0, `inFlight should drain to 0, got ${pool.inFlight}`);
  console.log(`  concurrency: ${N} parallel decisions, maxQueue=${pool.stats.maxQueue}, all legal`);
}

async function testCrashRecovery() {
  // A worker that crashes mid-decision must be respawned; the next decision
  // must succeed. We simulate by rejecting via a tiny timeout then verifying
  // the pool still works.
  const pool = new BotWorkerPool({ size: 1, timeoutMs: 1 });
  const playerIds = ['p0', 'p1', 'p2', 'p3', 'p4'];
  const playerNames = {}; for (const p of playerIds) playerNames[p] = p;
  const game = new MightyGame(playerIds, playerNames, { targetScore: 50, rng: makeRng(9) });
  game.start();
  const actor = game.getPendingActor();
  let rejected = false;
  try { await pool.decide('mighty', game, actor, 'mixoracle', 1); }
  catch (_) { rejected = true; }
  assert.ok(rejected, 'expected a 1ms-timeout decision to reject');
  // After timeout+respawn, a generous decision must still resolve.
  const action = await pool.decide('mighty', game, actor, 'heuristic', 5000);
  assert.ok(action, 'pool did not recover after worker respawn');
  assert.ok(pool.stats.timeouts >= 1, 'timeout not counted');
  await pool.destroy();
  console.log(`  crash-recovery: timeout rejected + respawn recovered (timeouts=${pool.stats.timeouts})`);
}

async function main() {
  const pool = new BotWorkerPool({ size: 2 });
  console.log(`BotWorkerPool size=${pool.size}`);
  await testMighty(pool);
  await testTichu(pool);
  await testConcurrency(pool);
  await pool.destroy();
  await testCrashRecovery();
  console.log('OK — bot worker pool: legality, concurrency, and crash-recovery all passed.');
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
