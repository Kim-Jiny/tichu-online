'use strict';

/**
 * Skull bot — pure heuristic, no lookahead (matches love_letter/skull_king's
 * first-cut bots). There's no way to estimate opponents' hidden discs beyond
 * "somewhere between reckless and hoping for the best", so this plays a
 * simple safety-floor strategy: only claim what it already knows is safe
 * from its own placed roses, plus a one-disc leap of faith.
 */

const { DISC, poolSize } = require('./SkullBiddingDeck');

function decideSkullBiddingBotAction(game, botId) {
  if (!game || !game.playerIds.includes(botId)) return null;
  if (game.currentPlayer !== botId) return null;

  switch (game.state) {
    case 'placing':
      return decidePlacing(game, botId);
    case 'bidding':
      return decideBidding(game, botId);
    case 'revealing':
      return decideRevealing(game, botId);
    case 'round_end':
      return { type: 'next_round' };
    default:
      return null;
  }
}

// Discs this bot could flip from its OWN stack with zero risk — the roses
// it has placed there. A floor, not the true safe count: real safety also
// depends on whether opponents kept their skull off the table, which is
// unknowable.
function _ownSafeCount(game, botId) {
  const stack = game.stack[botId] || [];
  return stack.filter((d) => d === DISC.ROSE).length;
}

function decidePlacing(game, botId) {
  const hand = game.hand[botId];
  if (!hand || poolSize(hand) === 0) {
    return { type: 'start_bid', amount: Math.max(1, _ownSafeCount(game, botId)) };
  }

  // Never opens on the very first placement of the round — the rule
  // requires having placed at least one disc, and there's nothing to base
  // a bid on yet anyway.
  if (game.placedThisRound.has(botId) && Math.random() < 0.35) {
    const amount = Math.max(1, _ownSafeCount(game, botId));
    return { type: 'start_bid', amount };
  }
  if (hand.roses > 0) return { type: 'place_disc', discType: DISC.ROSE };
  return { type: 'place_disc', discType: DISC.SKULL };
}

function decideBidding(game, botId) {
  const safe = _ownSafeCount(game, botId);
  // Willing to go exactly one past its own known-safe floor — betting that
  // at least one opponent is also still sitting on their skull unplaced.
  if (game.highestBid < safe + 1 && game.highestBid < game.tableTotal) {
    return { type: 'raise_bid', amount: game.highestBid + 1 };
  }
  return { type: 'pass' };
}

function decideRevealing(game, botId) {
  if (game.pendingDiscard && game.pendingDiscard.playerId === botId) {
    const pool = game.pool[botId];
    // Give up a rose while one remains — losing the skull instead would
    // remove all future risk from its own stack, which costs more
    // strategically than one fewer rose.
    return { type: 'discard_disc', discardType: pool.roses > 0 ? DISC.ROSE : DISC.SKULL };
  }
  const target = game.playerIds.find(
    (pid) => pid !== botId && !game.eliminated[pid] && (game.stack[pid] || []).length > 0
  );
  if (target) return { type: 'reveal_target', targetId: target };
  return null;
}

module.exports = { decideSkullBiddingBotAction };
