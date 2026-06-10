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

function _stepOnce(game) {
  if (game.state === 'trick_end') {
    game.advanceAfterTrickEnd();
    return true;
  }
  const actor = game.getPendingActor();
  if (!actor) return false;
  const action = MightyBot.decideMightyBotAction(game, actor, 'heuristic');
  if (!action) return false;
  const r = game.handleAction(actor, action);
  if (!r || !r.success) {
    const fb = game.getAutoTimeoutAction(actor);
    if (fb) {
      const r2 = game.handleAction(actor, fb);
      return !!(r2 && r2.success);
    }
    return false;
  }
  return true;
}

function runRollout(game) {
  let steps = 0;
  while (game.state !== 'round_end' && game.state !== 'game_end' && steps < MAX_STEPS) {
    if (!_stepOnce(game)) break;
    steps++;
  }
  return game;
}

module.exports = { runRollout };
