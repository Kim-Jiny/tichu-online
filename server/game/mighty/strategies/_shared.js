'use strict';

const MightyBot = require('../MightyBot');

/** Build a discard_kitty action with a forced friend choice (heuristic discards). */
function buildKittyDiscardAction(game, botId, friendCard) {
  const hand = game.hands[botId];
  const mightyCard = game.getMightyCard();
  const protectedCards = new Set([mightyCard, 'mighty_joker']);
  const suitGroups = MightyBot.groupMightyCardsBySuit(hand, protectedCards);
  const eligible = hand.filter(c => !protectedCards.has(c) && c !== friendCard);
  const discards = MightyBot.chooseKittyDiscards(eligible, game, suitGroups);
  return { type: 'discard_kitty', discards, friendCard: friendCard || 'no_friend' };
}

/**
 * When the bot is the unrevealed/revealed friend reinforcing declarer's
 * lead, prune candidates: a "winning" card (one that beats current top)
 * is only allowed if it's safe per `isSafeFriendWinner` — i.e., it'll
 * survive opp behind. Non-winning cards (safe discards) are always
 * allowed. Applies to BOTH trump and non-trump leads, since trump leads
 * can also be over-cut by higher trumps held by opp behind.
 *
 * Returns the filtered list, or the original list if filter would empty
 * it (defensive — should not happen since safe discards are always kept).
 */
function filterFriendSafeCandidates(game, botId, legal) {
  if (!legal || legal.length === 0) return legal;
  if (game.currentTrick.length === 0) return legal; // bot is leading
  if (!MightyBot.isFriend(game, botId)) return legal;
  const declarerLed = game.currentTrick[0].pid === game.declarer;
  if (!declarerLed) return legal;

  const filtered = legal.filter(cardId => {
    if (!MightyBot.canBeatCurrentWinner(game, cardId)) return true; // safe discard
    return MightyBot.isSafeFriendWinner(cardId, game, botId);
  });
  return filtered.length > 0 ? filtered : legal;
}

module.exports = { buildKittyDiscardAction, filterFriendSafeCandidates };
