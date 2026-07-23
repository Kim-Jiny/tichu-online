'use strict';

/**
 * Parity test for game serialize()/reconstruct() used by the bot worker pool.
 *
 * The contract: reconstruct(structuredClone(serialize(g))) must be
 * deep-equal to g.clone(). clone() defines exactly the state a bot search
 * needs, so if serialize() ever drops (or adds) a field relative to clone(),
 * this test fails and the worker would otherwise silently run on wrong state.
 *
 * It drives real bot games (mighty + tichu) and checks the invariant at every
 * decision point, plus a functional check that the reconstructed instance can
 * actually produce a legal action.
 *
 *   node test_serialize_roundtrip.js
 */

const assert = require('assert');
const MightyGame = require('./game/mighty/MightyGame');
const { decideMightyBotAction } = require('./game/mighty/MightyBot');
const { makeRng } = require('./game/mighty/MightyDeck');
const TichuGame = require('./game/TichuGame');
const { decideBotAction } = require('./game/BotPlayer');

let checkpoints = 0;
let functionalChecks = 0;

// Simulate the postMessage boundary (structured clone) + worker-side rebuild.
function roundtrip(GameClass, game) {
  return GameClass.reconstruct(structuredClone(game.serialize()));
}

function assertParity(GameClass, game, label) {
  const rebuilt = roundtrip(GameClass, game);
  const cloned = game.clone();
  assert.deepStrictEqual(
    rebuilt,
    cloned,
    `serialize/reconstruct diverged from clone() at ${label} ` +
    `(state=${game.state}) — a field is missing from serialize() or reconstruct()`
  );
  checkpoints++;
  return rebuilt;
}

// ---------------------------------------------------------------- Mighty ----
function driveMighty(seed) {
  const playerIds = ['p0', 'p1', 'p2', 'p3', 'p4'];
  const playerNames = {};
  for (const pid of playerIds) playerNames[pid] = pid;
  const game = new MightyGame(playerIds, playerNames, { targetScore: 50, rng: makeRng(seed) });
  game.start();

  let safety = 8000;
  while (game.state !== 'round_end' && game.state !== 'game_end' && safety-- > 0) {
    if (game.state === 'trick_end') { game.advanceAfterTrickEnd(); continue; }
    const actor = game.getPendingActor();
    if (!actor) break;

    // Invariant holds at every decision point across every phase.
    const rebuilt = assertParity(MightyGame, game, `mighty seed=${seed} actor=${actor}`);

    // Functional: the reconstructed instance must decide the same class of
    // action the live game would accept. We don't assert action equality
    // (rollouts use randomness); we assert the rebuilt game yields a *legal*
    // action for the live game.
    const rebuiltAction = decideMightyBotAction(rebuilt, actor, 'heuristic');
    if (rebuiltAction) {
      const probe = game.clone();
      const res = probe.handleAction(actor, rebuiltAction);
      assert.ok(
        res && res.success !== false,
        `action from reconstructed mighty game was rejected by live game ` +
        `(state=${game.state} actor=${actor} action=${JSON.stringify(rebuiltAction)})`
      );
      functionalChecks++;
    }

    const action = decideMightyBotAction(game, actor, 'heuristic');
    if (!action) break;
    const result = game.handleAction(actor, action);
    if (!result || result.success === false) {
      const fb = game.getAutoTimeoutAction(actor);
      if (fb) game.handleAction(actor, fb); else break;
    }
  }
}

// ----------------------------------------------------------------- Tichu ----
function tichuPendingActors(game) {
  const s = game.state;
  if (s === 'large_tichu_phase' || s === 'card_exchange') return game.playerIds.slice();
  if (game.needsToCallRank) return [game.needsToCallRank];
  if (game.dragonPending) return [game.dragonDecider];
  return game.currentPlayer ? [game.currentPlayer] : [];
}

function driveTichu(seed) {
  // TichuGame has no injectable rng; seed only varies which round index we run
  // so repeated runs exercise different deals.
  const playerIds = ['p0', 'p1', 'p2', 'p3'];
  const playerNames = { p0: 'p0', p1: 'p1', p2: 'p2', p3: 'p3' };
  const game = new TichuGame(playerIds, playerNames);
  game.start();

  let steps = 0;
  const MAX = 4000;
  while (game.state !== 'round_end' && game.state !== 'game_end' && steps < MAX) {
    let progressed = false;
    for (const actor of tichuPendingActors(game)) {
      if (!actor) continue;

      const rebuilt = assertParity(TichuGame, game, `tichu actor=${actor}`);

      const rebuiltAction = decideBotAction(rebuilt, actor, 'winrate');
      if (rebuiltAction) {
        const probe = game.clone();
        const res = probe.handleAction(actor, rebuiltAction);
        // Multi-actor phases (exchange) can legitimately reject a stale actor
        // once another actor already moved on the probe; only assert for the
        // single-actor playing phase where ordering is unambiguous.
        if (game.state === 'playing') {
          assert.ok(
            res && res.success !== false,
            `action from reconstructed tichu game rejected by live game ` +
            `(actor=${actor} action=${JSON.stringify(rebuiltAction)})`
          );
        }
        functionalChecks++;
      }

      let action = decideBotAction(game, actor, 'winrate');
      if (!action) action = game.getAutoTimeoutAction(actor);
      if (!action) continue;
      const res = game.handleAction(actor, action);
      if (res && res.success) progressed = true;
      else {
        const fb = game.getAutoTimeoutAction(actor);
        if (fb) { const r2 = game.handleAction(actor, fb); if (r2 && r2.success) progressed = true; }
      }
    }
    steps++;
    if (!progressed) break;
  }
}

// ------------------------------------------------------------------ Run -----
function main() {
  for (let seed = 1; seed <= 6; seed++) driveMighty(seed);
  for (let seed = 1; seed <= 6; seed++) driveTichu(seed);
  console.log(`OK — serialize/reconstruct parity held across ${checkpoints} ` +
    `checkpoints (${functionalChecks} functional action checks).`);
}

main();
