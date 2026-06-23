'use strict';

/**
 * Exact endgame solver for Mighty.
 *
 * The server bot has full information (all hands are known), so the endgame is
 * a perfect-information, two-team zero-sum game. Once few cards remain we can
 * solve it EXACTLY with alpha-beta minimax instead of relying on the heuristic
 * rollout — which is where most endgame mistakes come from (wasting trumps,
 * burning the joker on a won trick, sacrificing the wrong card, etc.).
 *
 * Correctness over re-implementation: we recurse on real MightyGame clones and
 * the engine's own handleAction, so trick resolution / legality / scoring are
 * exactly the production rules. Value backed up = the deciding bot's round-end
 * score; teammates maximise it, opponents minimise it (team membership is
 * computed once with full info, so an unrevealed friend is still treated as
 * government).
 *
 * Bounded: only activates at <= MAX_SOLVE_CARDS cards per hand, with a node
 * budget. If the budget is blown it returns null and the caller falls back to
 * the normal (oracle) path.
 */

const { SUITS } = require('./MightyDeck');

// Activate only when the largest active hand has at most this many cards.
// 3 keeps the tree tiny (verified node counts well under budget).
const MAX_SOLVE_CARDS = 3;
// Hard backstop so a pathological position can't stall the event loop.
const NODE_BUDGET = 60000;

function _maxHand(game) {
  let m = 0;
  for (const pid of game.playerIds) {
    if (game.excludedPlayers && game.excludedPlayers.has(pid)) continue;
    const n = (game.hands[pid] || []).length;
    if (n > m) m = n;
  }
  return m;
}

/** Is the endgame solver applicable to this position? */
function canSolve(game) {
  if (!game || game.state !== 'playing') return false;
  const m = _maxHand(game);
  return m > 0 && m <= MAX_SOLVE_CARDS;
}

/**
 * Stable team assignment using full information, so a not-yet-revealed friend
 * is still classified as government. Returns a Set of government player ids.
 */
function _govSet(game) {
  const gov = new Set([game.declarer]);
  if (game.partner) { gov.add(game.partner); return gov; }
  const fc = game.friendCard;
  if (fc && fc !== 'no_friend' && fc !== 'first_trick') {
    for (const pid of game.playerIds) {
      if ((game.hands[pid] || []).includes(fc)) { gov.add(pid); break; }
    }
  }
  return gov;
}

/** Advance the clone through any trick_end bookkeeping. */
function _settle(game) {
  let guard = 64;
  while (guard-- > 0 && game.state === 'trick_end') game.advanceAfterTrickEnd();
  return game;
}

/** Candidate actions for the actor at this node (exact: joker-lead enumerates
 *  the declared suit; everything else is a single card play). */
function _moves(game, actor) {
  const legal = game._getLegalCards(actor);
  const out = [];
  const leading = game.currentTrick.length === 0;
  for (const cardId of legal) {
    if (cardId === 'mighty_joker' && leading) {
      for (const suit of SUITS) out.push({ type: 'play_card', cardId, jokerSuit: suit });
    } else if (cardId === 'mighty_joker') {
      out.push({ type: 'play_card', cardId });
    } else {
      // makePlayAction adds the joker-call flag / any needed metadata.
      out.push(makePlayActionRef(cardId, game, actor));
    }
  }
  return out;
}

// Late-bound to avoid a require cycle (MightyBot is the heavy module).
let makePlayActionRef = null;
function _ensureRefs() {
  if (!makePlayActionRef) {
    makePlayActionRef = require('./MightyBot').makePlayAction;
  }
}

/**
 * Alpha-beta over the deciding bot's round-end score.
 * @returns the leaf value (bot's score) for this subtree.
 */
function _search(game, botId, govSet, botIsGov, alpha, beta, ctr) {
  _settle(game);
  if (game.state === 'round_end' || game.state === 'game_end') {
    return (game.scores && game.scores[botId]) || 0;
  }
  if (++ctr.nodes > NODE_BUDGET) throw new Error('budget');

  const actor = game.currentPlayer;
  if (!actor) return (game.scores && game.scores[botId]) || 0;
  const maximizing = govSet.has(actor) === botIsGov;
  const moves = _moves(game, actor);

  let best = maximizing ? -Infinity : Infinity;
  for (const action of moves) {
    const world = game.clone();
    const res = world.handleAction(actor, action);
    if (!res || res.success === false) continue;
    const v = _search(world, botId, govSet, botIsGov, alpha, beta, ctr);
    if (maximizing) {
      if (v > best) best = v;
      if (best > alpha) alpha = best;
    } else {
      if (v < best) best = v;
      if (best < beta) beta = best;
    }
    if (beta <= alpha) break; // prune
  }
  if (best === Infinity || best === -Infinity) {
    // No legal move applied (shouldn't happen) — settle to a score.
    return (game.scores && game.scores[botId]) || 0;
  }
  return best;
}

/**
 * Solve the position for `botId`. Returns the best play action
 * ({ type:'play_card', cardId, jokerSuit? }) or null if not applicable / the
 * node budget was exceeded (caller should fall back to its normal path).
 */
function solve(game, botId) {
  if (!canSolve(game)) return null;
  if (game.currentPlayer !== botId) return null;
  _ensureRefs();

  const govSet = _govSet(game);
  const botIsGov = govSet.has(botId);
  const ctr = { nodes: 0 };

  try {
    const moves = _moves(game, botId);
    if (moves.length === 0) return null;
    if (moves.length === 1) { moves[0].__nodes = 0; return moves[0]; }

    let bestAction = null;
    let bestVal = -Infinity;
    let alpha = -Infinity;
    const beta = Infinity;
    for (const action of moves) {
      const world = game.clone();
      const res = world.handleAction(botId, action);
      if (!res || res.success === false) continue;
      const v = _search(world, botId, govSet, botIsGov, alpha, beta, ctr);
      if (v > bestVal) { bestVal = v; bestAction = action; }
      if (bestVal > alpha) alpha = bestVal;
    }
    if (!bestAction) return null;
    // Debug metadata (ignored by handleAction).
    bestAction.__value = bestVal;
    bestAction.__nodes = ctr.nodes;
    return bestAction;
  } catch (e) {
    return null; // budget blown or unexpected — fall back
  }
}

module.exports = { solve, canSolve, MAX_SOLVE_CARDS };
