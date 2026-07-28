'use strict';

/**
 * Is this player genuinely on the hook for an action right now?
 *
 * handleTurnTimeout uses this to tell a real timeout from a stale one. A turn
 * timer armed for one state can still fire after the game has moved on —
 * sendGameStateToAll returns early for round_end/trick_end without going
 * through startTurnTimer, so the previous state's timer survives into a state
 * where nobody owes an action. When that happens the auto-play no-ops (every
 * engine's getAutoTimeoutAction returns null unless the player is the pending
 * actor) while the timeout count still climbs — so a player who did nothing
 * wrong gets deserted after three of them.
 *
 * This mirrors, per game type, exactly the actors startTurnTimer arms a
 * handleTurnTimeout for. Keep the two in sync: anything this says yes to but
 * startTurnTimer never arms is harmless, but the reverse re-opens the bug.
 *
 * Note the phases that do NOT belong here: Tichu's large_tichu_phase and
 * card_exchange, and Skull King's simultaneous bidding, run through
 * handlePhaseTimeout instead, which times out a whole phase rather than one
 * player. (SK bidding still appears below — the timer there can fire through
 * either path, and that allowance is the original reported-bug fix.)
 *
 * Lives outside server.js so it can be unit-tested — same reason as
 * game/botWatchdog.js and lobby/zombieSweep.js.
 */
function playerStillNeedsToAct(gameType, game, playerId) {
  if (!game || !playerId) return false;
  const state = game.state;

  if (gameType === 'skull_king') {
    return (state === 'playing' && game.currentPlayer === playerId)
      || (state === 'bidding' && !!game.bids && game.bids[playerId] === null);
  }

  if (gameType === 'love_letter') {
    if (state === 'playing') return game.currentPlayer === playerId;
    if (state === 'effect_resolve') {
      const eff = game.pendingEffect;
      // A resolved effect is advanced by the ack timers, not by this one.
      return !!eff && !eff.resolved && eff.playerId === playerId;
    }
    return false;
  }

  if (gameType === 'mighty') {
    if (state === 'playing' || state === 'bidding') return game.currentPlayer === playerId;
    if (state === 'kitty_exchange' || state === 'kill_select') return game.declarer === playerId;
    return false;
  }

  // Tichu: the turn can be owed by someone other than currentPlayer.
  if (state !== 'playing') return false;
  let target = game.currentPlayer;
  if (game.needsToCallRank) target = game.needsToCallRank;
  else if (game.dragonPending) target = game.dragonDecider;
  return target === playerId;
}

module.exports = { playerStillNeedsToAct };
