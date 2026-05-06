'use strict';

/**
 * pimc_play strategy.
 *
 * Uses PIMC for the highest-leverage decisions (friend card pick + every
 * play during the trick phase) and defers to the existing heuristic for
 * bidding, kill selection, and the kitty discard set itself.
 *
 * The kitty step is special: the heuristic picks one friend card, but PIMC
 * scores several friend candidates by enumerating the heuristic's top
 * options and re-running the discard pick for each. The discard pattern
 * still comes from the heuristic — only the friend choice gets MC scoring.
 */

const { runPIMC } = require('./pimc');
const MightyBotInternals = require('../MightyBot');
const { buildKittyDiscardAction, filterFriendSafeCandidates } = require('./_shared');
const { SUITS } = require('../MightyDeck');

const PIMC_PLAY_SAMPLES = 40;
const PIMC_FRIEND_SAMPLES = 30;
const MAX_PLAY_CANDIDATES = 8;

function _heuristicAction(game, botId) {
  return MightyBotInternals.decideMightyBotAction(game, botId, 'heuristic');
}

/** Friend candidates: heuristic's pick + joker + 1-3 length non-trump A's + no_friend. */
function _friendCandidates(game, botId) {
  const hand = game.hands[botId];
  const mightyCard = game.getMightyCard();
  if (!hand.includes(mightyCard)) {
    // Forced: not holding mighty means the friend MUST be the mighty card.
    return [mightyCard];
  }
  const trumpSuit = game.trumpSuit;
  const set = new Set();
  const heuristicPick = MightyBotInternals.pickFriendCard(hand, game);
  if (heuristicPick) set.add(heuristicPick);
  if (!hand.includes('mighty_joker')) set.add('mighty_joker');
  for (const suit of SUITS) {
    if (suit === trumpSuit) continue;
    const ace = `mighty_${suit}_A`;
    if (ace === mightyCard) continue;
    if (hand.includes(ace)) continue;
    if (set.has(ace)) continue;
    set.add(ace);
    if (set.size >= 4) break;
  }
  set.add('no_friend');
  return [...set];
}

/** Decide a kitty discard with PIMC scoring over friend choices. */
function _decideKittyPIMC(game, botId) {
  const trumpChange = MightyBotInternals.considerTrumpChange(game, botId);
  if (trumpChange) return trumpChange;

  const friends = _friendCandidates(game, botId);
  if (friends.length <= 1) {
    return buildKittyDiscardAction(game, botId, friends[0] || 'no_friend');
  }

  const candidates = friends.map(f => ({
    id: f,
    apply: (w) => {
      const action = buildKittyDiscardAction(w, botId, f);
      const r = w.handleAction(botId, action);
      if (!r || !r.success) throw new Error('illegal discard');
    },
  }));
  const { winner } = runPIMC(game, botId, candidates, { samples: PIMC_FRIEND_SAMPLES });
  return buildKittyDiscardAction(game, botId, winner);
}

/** Decide a play with PIMC scoring over legal cards. */
function _decidePlayPIMC(game, botId) {
  let legal = game.getLegalCards(botId);
  if (!legal || legal.length === 0) return null;
  legal = filterFriendSafeCandidates(game, botId, legal);
  if (legal.length === 1) {
    return MightyBotInternals.makePlayAction(legal[0], game, botId);
  }

  // Cap candidates: heuristic's top pick first, others appended.
  let candidateCards = legal;
  if (legal.length > MAX_PLAY_CANDIDATES) {
    const heuristic = _heuristicAction(game, botId);
    const heuristicCard = heuristic && (heuristic.cardId || (heuristic.cards && heuristic.cards[0]));
    const heuristicInLegal = legal.includes(heuristicCard) ? heuristicCard : legal[0];
    candidateCards = [heuristicInLegal, ...legal.filter(c => c !== heuristicInLegal)].slice(0, MAX_PLAY_CANDIDATES);
  }

  const candidates = candidateCards.map(cardId => ({
    id: cardId,
    apply: (w) => {
      const a = MightyBotInternals.makePlayAction(cardId, w, botId);
      const r = w.handleAction(botId, a);
      if (!r || !r.success) throw new Error('illegal play');
    },
  }));
  const { winner } = runPIMC(game, botId, candidates, { samples: PIMC_PLAY_SAMPLES });
  return MightyBotInternals.makePlayAction(winner, game, botId);
}

function decide(game, botId) {
  if (game.state === 'bidding' && game.currentPlayer === botId) {
    return _heuristicAction(game, botId);
  }
  if (game.state === 'kill_select' && game.declarer === botId) {
    return _heuristicAction(game, botId);
  }
  if (game.state === 'kitty_exchange' && game.declarer === botId) {
    return _decideKittyPIMC(game, botId);
  }
  if (game.state === 'playing' && game.currentPlayer === botId) {
    return _decidePlayPIMC(game, botId);
  }
  if (game.state === 'round_end') {
    return { type: 'next_round' };
  }
  return null;
}

module.exports = { decide };
