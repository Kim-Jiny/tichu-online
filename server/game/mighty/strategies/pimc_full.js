'use strict';

/**
 * pimc_full strategy.
 *
 * Applies PIMC scoring to every decision point: bidding, kill selection,
 * kitty (trump-change + friend + discard), and play. Uses the heuristic to
 * generate a small candidate set for each decision (so we don't enumerate
 * the full action space) and lets MC rollouts pick the best.
 *
 * Candidate generation philosophy: heuristic's top pick + 2-3 sensible
 * perturbations. PIMC is a tiebreaker among nearby plays, not a
 * brute-force search over every legal action.
 */

const { runPIMC } = require('./pimc');
const MightyBotInternals = require('../MightyBot');
const playStrategy = require('./pimc_play');
const { buildKittyDiscardAction } = require('./_shared');
const { SUITS } = require('../MightyDeck');

const PIMC_BID_SAMPLES = 30;
const PIMC_KILL_SAMPLES = 25;
const PIMC_KITTY_SAMPLES = 30;
const MAX_BID_CANDIDATES = 5;

function _heuristicAction(game, botId) {
  return MightyBotInternals.decideMightyBotAction(game, botId, 'heuristic');
}

/** Bid candidates: heuristic's pick + pass + minor perturbations. */
function _bidCandidates(game, botId) {
  const heuristic = _heuristicAction(game, botId);
  const set = new Map();
  const add = (action) => {
    const key = action.pass ? 'pass' : `${action.points}_${action.suit}`;
    if (!set.has(key)) set.set(key, action);
  };

  add(heuristic);
  add({ type: 'submit_bid', pass: true });

  // Perturbations: ±1 from heuristic's bid (if it was a bid), and a NT variant.
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
    // NT perturbation removed: heuristic now gates NT on a strict
    // mighty+joker+missing-A-with-KQ hand pattern, so synthesising an NT
    // candidate when heuristic chose a suit would bypass that gate.
  }
  // Cap candidates to keep MC budget manageable.
  return [...set.values()].slice(0, MAX_BID_CANDIDATES);
}

function _decideBidPIMC(game, botId) {
  const candidates = _bidCandidates(game, botId);
  if (candidates.length <= 1) return candidates[0] || _heuristicAction(game, botId);

  const wrapped = candidates.map((action, i) => ({
    id: `bid_${i}`,
    action,
    apply: (w) => {
      const r = w.handleAction(botId, action);
      if (!r || !r.success) throw new Error('illegal bid');
    },
  }));
  const { winner } = runPIMC(game, botId, wrapped, { samples: PIMC_BID_SAMPLES });
  return wrapped.find(c => c.id === winner)?.action || candidates[0];
}

/** Kill targets: a small candidate set of opponent A's the bot doesn't hold. */
function _killCandidates(game, botId) {
  const hand = new Set(game.hands[botId] || []);
  const cards = [];
  // Highest-leverage targets: side-suit Aces opponents are most likely to hold.
  for (const rank of ['A', 'K']) {
    for (const suit of SUITS) {
      const c = `mighty_${suit}_${rank}`;
      if (!hand.has(c) && !cards.includes(c)) cards.push(c);
      if (cards.length >= 4) break;
    }
    if (cards.length >= 4) break;
  }
  if (cards.length === 0) cards.push('mighty_spade_A');
  return cards;
}

function _decideKillPIMC(game, botId) {
  const candidates = _killCandidates(game, botId).map(cardId => ({
    id: cardId,
    apply: (w) => {
      const r = w.handleAction(botId, { type: 'select_kill_target', cardId });
      if (!r || !r.success) throw new Error('illegal kill');
    },
  }));
  if (candidates.length <= 1) {
    return { type: 'select_kill_target', cardId: candidates[0]?.id || 'mighty_spade_A' };
  }
  const { winner } = runPIMC(game, botId, candidates, { samples: PIMC_KILL_SAMPLES });
  return { type: 'select_kill_target', cardId: winner };
}

/** Kitty: PIMC trump-change-or-not, then friend candidate. */
function _decideKittyPIMC(game, botId) {
  const proposed = MightyBotInternals.considerTrumpChange(game, botId);
  if (proposed) {
    const candidates = [
      {
        id: 'change',
        apply: (w) => {
          const r = w.handleAction(botId, proposed);
          if (!r || !r.success) throw new Error('illegal change');
        },
      },
      {
        id: 'stay',
        apply: (w) => {
          const friend = MightyBotInternals.pickFriendCard(w.hands[botId], w);
          const action = buildKittyDiscardAction(w, botId, friend);
          const r = w.handleAction(botId, action);
          if (!r || !r.success) throw new Error('illegal discard');
        },
      },
    ];
    const { winner } = runPIMC(game, botId, candidates, { samples: PIMC_KITTY_SAMPLES });
    if (winner === 'change') return proposed;
  }

  return playStrategy.decide(game, botId);
}

function decide(game, botId) {
  if (game.state === 'bidding' && game.currentPlayer === botId) {
    return _decideBidPIMC(game, botId);
  }
  if (game.state === 'kill_select' && game.declarer === botId) {
    return _decideKillPIMC(game, botId);
  }
  if (game.state === 'kitty_exchange' && game.declarer === botId) {
    return _decideKittyPIMC(game, botId);
  }
  if (game.state === 'playing' && game.currentPlayer === botId) {
    return playStrategy.decide(game, botId);
  }
  if (game.state === 'round_end') {
    return { type: 'next_round' };
  }
  return null;
}

module.exports = { decide };
