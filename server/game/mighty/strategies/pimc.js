'use strict';

/**
 * PIMC (Perfect Information Monte Carlo) core for Mighty bots.
 *
 * Given a list of candidate actions, for each candidate sample N worlds
 * (determinizations of opponents' hidden hands), apply the action to each
 * sampled world, run the round to completion via the rollout policy, and
 * score the outcome from `botId`'s perspective. The candidate with the
 * highest mean score wins.
 *
 * Score is the round's score delta for `botId` — positive = good. Tied
 * candidates are broken by the order they were passed in (so the "natural"
 * heuristic preference still acts as a tiebreaker).
 */

const { sampleWorld } = require('./sampler');
const { runRollout } = require('./rollout');

/**
 * Default scorer: round delta for `botId` (post-rollout score - pre-rollout score).
 * Falls back to 0 if game didn't reach round_end.
 */
function _roundDelta(preScores, finalGame, botId) {
  const before = preScores[botId] || 0;
  const after = (finalGame.scores && finalGame.scores[botId]) || 0;
  return after - before;
}

/**
 * Run PIMC over a set of candidate actions.
 *
 * @param {MightyGame} game           Live game (will not be mutated).
 * @param {string}     botId          Player making the decision.
 * @param {Array}      candidates     [{id, apply: (clonedGame) => void}, ...]
 *                                    `id` is what we return; `apply` mutates
 *                                    the cloned/sampled game to enact the
 *                                    candidate (e.g., game.handleAction(...)).
 * @param {Object}     opts
 * @param {number}     opts.samples   Worlds per candidate (default 50).
 * @param {Function}   opts.scoreFn   (preScores, finalGame, botId) => number.
 * @returns {{winner, scores}} winner = candidate.id; scores = id → meanScore.
 */
function runPIMC(game, botId, candidates, opts = {}) {
  const samples = opts.samples || 50;
  const scoreFn = opts.scoreFn || _roundDelta;

  const preScores = { ...game.scores };
  const totals = {};
  const counts = {};
  for (const c of candidates) { totals[c.id] = 0; counts[c.id] = 0; }

  for (let s = 0; s < samples; s++) {
    // Sample one world; reuse it across all candidates for the same `s` so
    // candidates compete on identical hidden info (variance reduction).
    const baseWorld = sampleWorld(game, botId);
    for (const c of candidates) {
      const w = baseWorld.clone();
      try {
        c.apply(w);
      } catch (e) {
        continue; // illegal in this world — skip
      }
      runRollout(w);
      const score = scoreFn(preScores, w, botId);
      totals[c.id] += score;
      counts[c.id]++;
    }
  }

  let bestId = candidates[0]?.id ?? null;
  let bestMean = -Infinity;
  const meanScores = {};
  for (const c of candidates) {
    const mean = counts[c.id] > 0 ? totals[c.id] / counts[c.id] : -Infinity;
    meanScores[c.id] = mean;
    if (mean > bestMean) { bestMean = mean; bestId = c.id; }
  }

  return { winner: bestId, scores: meanScores };
}

module.exports = { runPIMC };
