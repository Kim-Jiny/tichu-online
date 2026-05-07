'use strict';

/**
 * oracle strategy.
 *
 * Lightweight perfect-information evaluator for Mighty.
 *
 * The server bot already has the full live game state, so instead of
 * sampling many hidden worlds we score a small action set directly on the
 * actual world:
 *
 *   1. clone the current game
 *   2. apply a candidate action
 *   3. finish the round with the cheap heuristic rollout
 *   4. pick the candidate with the best score delta
 *
 * This keeps decision-making deterministic and far cheaper than the old
 * PIMC / sampled-expectimax stack.
 */

const { runRollout } = require('./rollout');
const MightyBotInternals = require('../MightyBot');
const { buildKittyDiscardAction, filterFriendSafeCandidates } = require('./_shared');
const { SUITS } = require('../MightyDeck');

const MAX_BID_CANDIDATES = 5;
const MAX_PLAY_CANDIDATES = 8;

function _heuristicAction(game, botId) {
  return MightyBotInternals.decideMightyBotAction(game, botId, 'heuristic');
}

function _roundDelta(preScores, finalGame, botId) {
  const before = preScores[botId] || 0;
  const after = (finalGame.scores && finalGame.scores[botId]) || 0;
  return after - before;
}

function _evaluateCandidates(game, botId, candidates, scoreFn = _roundDelta) {
  const preScores = { ...game.scores };
  let bestId = candidates[0]?.id ?? null;
  let bestScore = -Infinity;

  for (const candidate of candidates) {
    const world = game.clone();
    try {
      candidate.apply(world);
    } catch (_) {
      continue;
    }

    runRollout(world);
    const score = scoreFn(preScores, world, botId);
    if (score > bestScore) {
      bestScore = score;
      bestId = candidate.id;
    }
  }

  return bestId;
}

function _bidCandidates(game, botId) {
  const heuristic = _heuristicAction(game, botId);
  const set = new Map();
  const add = (action) => {
    if (!action) return;
    const key = action.pass ? 'pass' : `${action.points}_${action.suit}`;
    if (!set.has(key)) set.set(key, action);
  };

  add(heuristic);
  add({ type: 'submit_bid', pass: true });

  if (heuristic && !heuristic.pass && Number.isInteger(heuristic.points)) {
    const minBid = game.options.minBid;
    const lower = heuristic.points - 1;
    if (lower >= minBid && lower > game.currentBid.points) {
      add({ type: 'submit_bid', points: lower, suit: heuristic.suit });
    }
    const higher = heuristic.points + 1;
    if (higher <= 20) {
      add({ type: 'submit_bid', points: higher, suit: heuristic.suit });
    }
  }

  return [...set.values()].slice(0, MAX_BID_CANDIDATES);
}

function _killCandidates(game, botId) {
  const hand = new Set(game.hands[botId] || []);
  const cards = [];
  for (const rank of ['A', 'K']) {
    for (const suit of SUITS) {
      const cardId = `mighty_${suit}_${rank}`;
      if (!hand.has(cardId) && !cards.includes(cardId)) cards.push(cardId);
      if (cards.length >= 4) break;
    }
    if (cards.length >= 4) break;
  }
  if (cards.length === 0) cards.push('mighty_spade_A');
  return cards;
}

function _friendCandidates(game, botId) {
  const hand = game.hands[botId] || [];
  const mightyCard = game.getMightyCard();
  if (!hand.includes(mightyCard)) return [mightyCard];

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
    set.add(ace);
    if (set.size >= 4) break;
  }

  set.add('no_friend');
  return [...set];
}

function _playCandidateCards(game, botId) {
  let legal = game.getLegalCards(botId);
  if (!legal || legal.length === 0) return [];
  legal = filterFriendSafeCandidates(game, botId, legal);
  if (legal.length <= MAX_PLAY_CANDIDATES) return legal;

  const heuristic = _heuristicAction(game, botId);
  const heuristicCard = heuristic && (heuristic.cardId || (heuristic.cards && heuristic.cards[0]));
  const first = legal.includes(heuristicCard) ? heuristicCard : legal[0];
  return [first, ...legal.filter(c => c !== first)].slice(0, MAX_PLAY_CANDIDATES);
}

function _decideBid(game, botId) {
  const candidates = _bidCandidates(game, botId);
  if (candidates.length <= 1) return candidates[0] || _heuristicAction(game, botId);

  const wrapped = candidates.map((action, i) => ({
    id: `bid_${i}`,
    action,
    apply: (world) => {
      const result = world.handleAction(botId, action);
      if (!result || !result.success) throw new Error('illegal bid');
    },
  }));

  const winner = _evaluateCandidates(game, botId, wrapped);
  return wrapped.find(c => c.id === winner)?.action || candidates[0];
}

function _decideKill(game, botId) {
  const candidates = _killCandidates(game, botId).map(cardId => ({
    id: cardId,
    apply: (world) => {
      const result = world.handleAction(botId, { type: 'declare_kill', cardId });
      if (!result || !result.success) throw new Error('illegal kill');
    },
  }));

  if (candidates.length <= 1) {
    return { type: 'declare_kill', cardId: candidates[0]?.id || 'mighty_spade_A' };
  }

  return { type: 'declare_kill', cardId: _evaluateCandidates(game, botId, candidates) };
}

function _decideKitty(game, botId) {
  const trumpChange = MightyBotInternals.considerTrumpChange(game, botId);
  const candidates = [];

  if (trumpChange) {
    candidates.push({
      id: 'change',
      apply: (world) => {
        const result = world.handleAction(botId, trumpChange);
        if (!result || !result.success) throw new Error('illegal trump change');
      },
    });
  }

  for (const friendCard of _friendCandidates(game, botId)) {
    candidates.push({
      id: `friend:${friendCard}`,
      friendCard,
      apply: (world) => {
        const action = buildKittyDiscardAction(world, botId, friendCard);
        const result = world.handleAction(botId, action);
        if (!result || !result.success) throw new Error('illegal discard');
      },
    });
  }

  if (candidates.length === 0) return _heuristicAction(game, botId);
  if (candidates.length === 1) {
    const only = candidates[0];
    return only.id === 'change'
      ? trumpChange
      : buildKittyDiscardAction(game, botId, only.friendCard);
  }

  const winner = _evaluateCandidates(game, botId, candidates);
  if (winner === 'change') return trumpChange;

  const picked = candidates.find(c => c.id === winner);
  return buildKittyDiscardAction(game, botId, picked?.friendCard || 'no_friend');
}

function _decidePlay(game, botId) {
  const candidateCards = _playCandidateCards(game, botId);
  if (candidateCards.length === 0) return null;
  if (candidateCards.length === 1) {
    return MightyBotInternals.makePlayAction(candidateCards[0], game, botId);
  }

  const candidates = candidateCards.map(cardId => ({
    id: cardId,
    apply: (world) => {
      const action = MightyBotInternals.makePlayAction(cardId, world, botId);
      const result = world.handleAction(botId, action);
      if (!result || !result.success) throw new Error('illegal play');
    },
  }));

  const winner = _evaluateCandidates(game, botId, candidates);
  return MightyBotInternals.makePlayAction(winner, game, botId);
}

function decide(game, botId) {
  if (game.state === 'bidding' && game.currentPlayer === botId) {
    return _decideBid(game, botId);
  }
  if (game.state === 'kill_select' && game.declarer === botId) {
    return _decideKill(game, botId);
  }
  if (game.state === 'kitty_exchange' && game.declarer === botId) {
    return _decideKitty(game, botId);
  }
  if (game.state === 'playing' && game.currentPlayer === botId) {
    return _decidePlay(game, botId);
  }
  if (game.state === 'round_end') {
    return { type: 'next_round' };
  }
  return null;
}

module.exports = { decide };
