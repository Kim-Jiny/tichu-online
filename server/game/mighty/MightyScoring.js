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
function calculateRoundScores({ declarer, partner, playerIds, pointCards, bid, options }) {
  const { minBid = 13, scoreMultiplier = 1, soloBonus = 2, perfectBonus = 2 } = options;

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
  const baseScore = (bid - minBid + 1) * scoreMultiplier;

  let declarerScore;
  if (success) {
    declarerScore = baseScore;
    if (isPerfect) declarerScore *= perfectBonus;
    if (isSolo) declarerScore *= soloBonus;
  } else {
    declarerScore = -baseScore;
    if (isSolo) declarerScore *= soloBonus;
  }

  const scores = {};
  const defenderCount = isSolo ? playerIds.length - 1 : playerIds.length - 2;

  // Declarer score
  scores[declarer] = declarerScore;

  // Partner score (half of declarer, rounded toward zero)
  const partnerScore = (!isSolo && partner) ? Math.trunc(declarerScore / 2) : 0;
  if (!isSolo && partner) {
    scores[partner] = partnerScore;
  }

  // Defenders share opposite; distribute remainder to ensure zero-sum
  const declarerTeamTotal = declarerScore + partnerScore;
  const defenderTotal = -declarerTeamTotal; // must sum to this
  const defenders = playerIds.filter(pid => pid !== declarer && (isSolo || pid !== partner));
  const baseShare = Math.trunc(defenderTotal / defenderCount);
  let remainder = defenderTotal - baseShare * defenderCount;
  for (const pid of defenders) {
    scores[pid] = baseShare;
    if (remainder > 0) { scores[pid]++; remainder--; }
    else if (remainder < 0) { scores[pid]--; remainder++; }
  }

  return { scores, declarerPoints: declarerTeamPoints, success };
}

module.exports = {
  countPoints,
  calculateRoundScores,
};
