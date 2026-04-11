/**
 * Skull King Score Calculator
 *
 * bid = 0 && success: +10 * roundNumber + bonus
 * bid = 0 && fail:    -10 * roundNumber (no bonus)
 * bid > 0 && success: +20 * bid + bonus
 * bid > 0 && fail:    -10 * |tricks - bid| (no bonus)
 *
 * Bonus is awarded whenever the bid is met exactly. In the base game the
 * only bonus sources (mermaid captures SK, SK captures pirate) require
 * winning a trick so bid=0 always had bonus=0. With the Loot expansion a
 * player can accrue bonus (+20) without winning a trick — that bonus is
 * realised on bid=0 success too.
 */

function calculateRoundScore(bid, actualTricks, roundNumber, bonus = 0) {
  if (bid === 0) {
    if (actualTricks === 0) {
      // bid=0 success: base +10 * round, plus any bonus (e.g. Loot).
      return 10 * roundNumber + bonus;
    } else {
      return -10 * roundNumber;
    }
  } else {
    if (actualTricks === bid) {
      // Bonus only awarded when bid is met exactly
      return 20 * bid + bonus;
    } else {
      // Failed bid: no bonus, penalty only
      return -10 * Math.abs(actualTricks - bid);
    }
  }
}

/**
 * Calculate scores for all players in a round
 * @param {Object} playerData - { playerId: { bid, tricks, bonus } }
 * @param {number} roundNumber - 1-10
 * @returns {Object} { playerId: roundScore }
 */
function calculateAllScores(playerData, roundNumber) {
  const scores = {};
  for (const [playerId, data] of Object.entries(playerData)) {
    scores[playerId] = calculateRoundScore(data.bid, data.tricks, roundNumber, data.bonus || 0);
  }
  return scores;
}

module.exports = { calculateRoundScore, calculateAllScores };
