'use strict';

/**
 * expectimax_smart strategy.
 *
 * Top-tier bot:
 *   - Bidding / kill / kitty: PIMC-based (delegated to pimc_full) so the
 *     bot only declares hands it can actually make and picks the friend
 *     that maximises EV. Selective bidding is the main lever for high
 *     declarer success rate.
 *   - Play: depth-2 expectimax over sampled determinizations using the
 *     heuristic-based smart rollout for opponent simulation.
 */

const { sampleWorld } = require('./sampler');
const { runRollout } = require('./rollout');
const MightyBotInternals = require('../MightyBot');
const pimcFull = require('./pimc_full');
const { filterFriendSafeCandidates } = require('./_shared');

const SAMPLES = 40;
const MAX_CANDIDATES = 8;
const OWN_DEPTH = 2;

function _heuristicAction(game, botId) {
  return MightyBotInternals.decideMightyBotAction(game, botId, 'heuristic');
}

function _advanceToBotTurn(game, botId) {
  let safety = 500;
  while (safety-- > 0) {
    if (game.state === 'round_end' || game.state === 'game_end') return;
    if (game.state === 'trick_end') { game.advanceAfterTrickEnd(); continue; }
    const actor = game.getPendingActor();
    if (!actor) return;
    if (actor === botId) return;
    const action = _heuristicAction(game, actor);
    if (!action) return;
    const r = game.handleAction(actor, action);
    if (!r || !r.success) {
      const fb = game.getAutoTimeoutAction(actor);
      if (fb) game.handleAction(actor, fb); else return;
    }
  }
}

function _legalCandidates(game, botId) {
  let legal = game.getLegalCards(botId);
  if (!legal || legal.length === 0) return [];
  legal = filterFriendSafeCandidates(game, botId, legal);
  if (legal.length <= MAX_CANDIDATES) return legal;
  const h = _heuristicAction(game, botId);
  const top = h && (h.cardId || (h.cards && h.cards[0]));
  const topInLegal = legal.includes(top) ? top : legal[0];
  return [topInLegal, ...legal.filter(c => c !== topInLegal)].slice(0, MAX_CANDIDATES);
}

function _scoreOnce(game, botId, ownDepth) {
  if (ownDepth <= 0 || game.state === 'round_end' || game.state === 'game_end') {
    runRollout(game);
    return (game.scores[botId] || 0);
  }
  const legal = _legalCandidates(game, botId);
  if (legal.length === 0) {
    runRollout(game);
    return (game.scores[botId] || 0);
  }
  let best = -Infinity;
  for (const cardId of legal) {
    const w = game.clone();
    const a = MightyBotInternals.makePlayAction(cardId, w, botId);
    const r = w.handleAction(botId, a);
    if (!r || !r.success) continue;
    _advanceToBotTurn(w, botId);
    const s = _scoreOnce(w, botId, ownDepth - 1);
    if (s > best) best = s;
  }
  if (best === -Infinity) {
    runRollout(game);
    return (game.scores[botId] || 0);
  }
  return best;
}

function _decidePlayExpectimax(game, botId) {
  const legal = _legalCandidates(game, botId);
  if (legal.length === 0) return null;
  if (legal.length === 1) {
    return MightyBotInternals.makePlayAction(legal[0], game, botId);
  }
  const preScore = game.scores[botId] || 0;
  const totals = {};
  for (const c of legal) totals[c] = 0;

  for (let s = 0; s < SAMPLES; s++) {
    const baseWorld = sampleWorld(game, botId);
    for (const cardId of legal) {
      const w = baseWorld.clone();
      const action = MightyBotInternals.makePlayAction(cardId, w, botId);
      const r = w.handleAction(botId, action);
      if (!r || !r.success) continue;
      _advanceToBotTurn(w, botId);
      const score = _scoreOnce(w, botId, OWN_DEPTH - 1);
      totals[cardId] += (score - preScore);
    }
  }

  let best = legal[0];
  let bestMean = -Infinity;
  for (const cardId of legal) {
    const mean = totals[cardId] / SAMPLES;
    if (mean > bestMean) { bestMean = mean; best = cardId; }
  }
  return MightyBotInternals.makePlayAction(best, game, botId);
}

function decide(game, botId) {
  // Pre-play decisions (bid / kill / kitty) → defer to pimc_full's PIMC
  // logic for selective bidding + friend pick.
  if (game.state === 'bidding' && game.currentPlayer === botId) {
    return pimcFull.decide(game, botId);
  }
  if (game.state === 'kill_select' && game.declarer === botId) {
    return pimcFull.decide(game, botId);
  }
  if (game.state === 'kitty_exchange' && game.declarer === botId) {
    return pimcFull.decide(game, botId);
  }
  // Trick play → 2-ply expectimax with smart rollout.
  if (game.state === 'playing' && game.currentPlayer === botId) {
    return _decidePlayExpectimax(game, botId);
  }
  if (game.state === 'round_end') {
    return { type: 'next_round' };
  }
  return null;
}

module.exports = { decide };
