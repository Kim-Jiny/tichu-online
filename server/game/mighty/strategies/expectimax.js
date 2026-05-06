'use strict';

/**
 * expectimax strategy.
 *
 * Distinct from PIMC by adding a second-ply lookahead at the bot's *own*
 * turns: after picking a candidate action, sample a world, play through
 * opponents heuristically until the bot's next turn, pick the best next
 * action greedily, then rollout to round end.
 *
 * This is "expectimax with sampled determinizations":
 *   - max nodes = bot's own decisions (we pick the best)
 *   - chance/min nodes = opponent plays + hidden card distribution (averaged
 *     over `samples` determinizations, with opponents acting heuristically)
 *
 * For decisions where 2-ply lookahead doesn't apply (bid, kill, kitty),
 * we fall back to the heuristic — those are single-shot decisions where
 * the leverage of expectimax over PIMC is small.
 */

const { sampleWorld } = require('./sampler');
const { runRollout } = require('./rollout');
const MightyBotInternals = require('../MightyBot');
const { filterFriendSafeCandidates } = require('./_shared');

const SAMPLES = 25;
const MAX_CANDIDATES = 6;
const OWN_DEPTH = 2;

function _heuristicAction(game, botId) {
  return MightyBotInternals.decideMightyBotAction(game, botId, 'heuristic');
}

/** Drive the game until it's `botId`'s turn or round ends. Uses heuristic
 *  for opponents so the "chance" node has a deterministic policy per
 *  sampled world (variance comes from the determinization, not noisy
 *  opponent play). */
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
  if (game.state === 'bidding' && game.currentPlayer === botId) {
    return _heuristicAction(game, botId);
  }
  if (game.state === 'kill_select' && game.declarer === botId) {
    return _heuristicAction(game, botId);
  }
  if (game.state === 'kitty_exchange' && game.declarer === botId) {
    return _heuristicAction(game, botId);
  }
  if (game.state === 'playing' && game.currentPlayer === botId) {
    return _decidePlayExpectimax(game, botId);
  }
  if (game.state === 'round_end') {
    return { type: 'next_round' };
  }
  return null;
}

module.exports = { decide };
