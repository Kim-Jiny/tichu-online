'use strict';

const { getCardInfo } = require('./MightyDeck');

/**
 * Count point cards collected by each player/team.
 * Point cards: A, K, Q, J, 10 = 1 point each (total 20 in deck)
 */
function countPoints(collectedCards) {
  let points = 0;
  for (const cardId of collectedCards) {
    const info = getCardInfo(cardId);
    points += info.point;
  }
  return points;
}

/**
 * Calculate round scores.
 * @param {object} params
 * @param {string} params.declarer - declarer pid
 * @param {string|null} params.partner - partner pid (null if solo/no friend)
 * @param {string[]} params.playerIds - all player ids
 * @param {object} params.pointCards - pid → [collected point card ids]
 * @param {number} params.bid - declared bid amount
 * @param {object} params.options - game options
 * @returns {{ scores: object, declarerPoints: number, success: boolean }}
 */
function calculateRoundScores({ declarer, partner, playerIds, pointCards, bid, trumpSuit, options }) {
  const { minBid = 13 } = options;

  // Count points for declarer team
  const isSolo = !partner || partner === declarer;
  let declarerTeamPoints = 0;

  for (const pid of playerIds) {
    const pts = countPoints(pointCards[pid] || []);
    if (pid === declarer || pid === partner) {
      declarerTeamPoints += pts;
    }
  }

  const success = declarerTeamPoints >= bid;
  const isPerfect = declarerTeamPoints === 20;
  const isNoTrump = trumpSuit === 'no_trump';
  const isMaxBid = bid >= 20;

  // Base score = (bid - minBid + 1) * baseMultiplier + distance from the bid.
  // Success doubles the bid-distance baseline; failure uses ×1 so a missed
  // declarer isn't crushed before the deficit penalty is even applied.
  const baseMultiplier = success ? 2 : 1;
  let baseScore = (bid - minBid + 1) * baseMultiplier;
  if (success) {
    baseScore += (declarerTeamPoints - bid);
  } else {
    baseScore += (bid - declarerTeamPoints);
  }

  // Multipliers (run ×2, solo ×2, NT ×2, 20bid ×2) apply on both success
  // and failure — a failed solo / NT / 20-bid is still a bigger swing.
  if (isPerfect) baseScore *= 2;
  if (isSolo) baseScore *= 2;
  if (isNoTrump) baseScore *= 2;
  if (isMaxBid) baseScore *= 2;

  // Declarer: ±base × 2, Partner: ±base, Defenders: each ∓base
  const scores = {};
  const defenders = playerIds.filter(pid => pid !== declarer && (isSolo || pid !== partner));

  if (success) {
    scores[declarer] = baseScore * 2;
    if (!isSolo && partner) {
      scores[partner] = baseScore;
    }
    for (const pid of defenders) {
      scores[pid] = -baseScore;
    }
  } else {
    scores[declarer] = -baseScore * 2;
    if (!isSolo && partner) {
      scores[partner] = -baseScore;
    }
    for (const pid of defenders) {
      scores[pid] = baseScore;
    }
  }

  return { scores, declarerPoints: declarerTeamPoints, success };
}

module.exports = {
  countPoints,
  calculateRoundScores,
};
