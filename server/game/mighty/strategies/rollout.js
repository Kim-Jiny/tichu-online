'use strict';

/**
 * Rollout policy for Mighty PIMC.
 *
 * Drives a determinized game from any state to round_end, using the full
 * heuristic policy for every actor. Heuristic is role-aware
 * (government/friend/opposition) and follows tactical rules (e.g., friend
 * doesn't gamble non-effective-top winners on declarer's drain), so
 * sampled futures actually look like games between competent bots —
 * making PIMC's EV estimates accurate.
 *
 * Avoids recursion by routing through the heuristic branch directly.
 */

const MightyBot = require('../MightyBot');

// A full Mighty round is ~10 tricks (≤60 plays + trick-ends) plus bidding/kitty
// — under ~100 steps even in pathological-but-legal lines. 200 gives safe
// headroom while capping the tail: if a determinized state ever fails to
// progress (illegal→fallback that doesn't advance), we bail at 200 instead of
// burning 2000 heuristic evaluations and spiking a CPU core.
const MAX_STEPS = 200;

// Per-rollout-step timing is DEEP debug on the hottest path — _stepOnce runs
// thousands of times per mighty decision (candidates × samples × ~100 steps).
// So it is gated behind its OWN opt-in flag (OFF by default), NOT the always-on
// DIAG: normal prod pays zero cost (no hrtime, no env reads per step). Set
// DIAG_ROLLOUT_STEP=1 only when deep-profiling a slow rollout. Read once at
// module load (env doesn't change at runtime).
const ROLLOUT_STEP_DIAG = process.env.DIAG_ROLLOUT_STEP === '1';
const SLOW_MS = Number.isFinite(Number(process.env.DIAG_BOT_SLOW_MS))
  ? Number(process.env.DIAG_BOT_SLOW_MS)
  : 100;

function _stepOnce(game) {
  if (game.state === 'trick_end') {
    game.advanceAfterTrickEnd();
    return true;
  }
  const actor = game.getPendingActor();
  if (!actor) return false;
  const t0 = ROLLOUT_STEP_DIAG ? process.hrtime.bigint() : 0n;
  const action = MightyBot.decideMightyBotAction(game, actor, 'heuristic');
  const heurMs = ROLLOUT_STEP_DIAG ? Number(process.hrtime.bigint() - t0) / 1e6 : 0;
  if (!action) return false;
  const a0 = ROLLOUT_STEP_DIAG ? process.hrtime.bigint() : 0n;
  const r = game.handleAction(actor, action);
  let actionMs = ROLLOUT_STEP_DIAG ? Number(process.hrtime.bigint() - a0) / 1e6 : 0;
  if (!r || !r.success) {
    const fb = game.getAutoTimeoutAction(actor);
    if (fb) {
      const f0 = ROLLOUT_STEP_DIAG ? process.hrtime.bigint() : 0n;
      const r2 = game.handleAction(actor, fb);
      if (ROLLOUT_STEP_DIAG) { actionMs += Number(process.hrtime.bigint() - f0) / 1e6; _logSlowStep(game, actor, action, heurMs, actionMs, t0); }
      return !!(r2 && r2.success);
    }
    if (ROLLOUT_STEP_DIAG) _logSlowStep(game, actor, action, heurMs, actionMs, t0);
    return false;
  }
  if (ROLLOUT_STEP_DIAG) _logSlowStep(game, actor, action, heurMs, actionMs, t0);
  return true;
}

function _logSlowStep(game, actor, action, heurMs, actionMs, t0) {
  const totalMs = Number(process.hrtime.bigint() - t0) / 1e6;
  if (totalMs <= SLOW_MS) return;
  const hand = (game.hands && game.hands[actor] && game.hands[actor].length) || 0;
  const trick = (game.currentTrick && game.currentTrick.length) || 0;
  const act = action
    ? `${action.type || '-'}:${action.cardId || action.points || action.suit || action.pass || '-'}`
    : 'null';
  console.log(`[DIAG] mighty-rollout-step ${totalMs.toFixed(0)}ms actor=${actor} state=${game.state} hand=${hand} trick=${trick} heur=${heurMs.toFixed(0)}ms apply=${actionMs.toFixed(0)}ms action=${act}`);
}

function runRollout(game, deadline = 0) {
  let steps = 0;
  while (game.state !== 'round_end' && game.state !== 'game_end' && steps < MAX_STEPS) {
    if (deadline && Date.now() >= deadline) break;
    if (!_stepOnce(game)) break;
    steps++;
  }
  return game;
}

module.exports = { runRollout };
