/**
 * Skull King Score Calculator
 *
 * bid = 0 && success: +10 * roundNumber
 * bid = 0 && fail:    -10 * roundNumber
 * bid > 0 && success: +20 * bid + bonus (bonus ONLY on exact match)
 * bid > 0 && fail:    -10 * |tricks - bid| (no bonus)
 */

function calculateRoundScore(bid, actualTricks, roundNumber, bonus = 0) {
  if (bid === 0) {
    if (actualTricks === 0) {
      // bid=0 success: no bonus applies
      return 10 * roundNumber;
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
