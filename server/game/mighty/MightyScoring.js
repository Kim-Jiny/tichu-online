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

  const scores = {};
  const defenders = playerIds.filter(pid => pid !== declarer && (isSolo || pid !== partner));

  if (success) {
    // ─── Success: existing formula (unchanged) ───
    // Base = (bid − minBid + 1) × 2 + surplus(점수 − bid).
    // Multipliers ×2 for perfect / solo / NT / max-bid stack.
    let baseScore = (bid - minBid + 1) * 2;
    baseScore += (declarerTeamPoints - bid);
    if (isPerfect) baseScore *= 2;
    if (isSolo) baseScore *= 2;
    if (isNoTrump) baseScore *= 2;
    if (isMaxBid) baseScore *= 2;

    scores[declarer] = baseScore * 2;
    if (!isSolo && partner) {
      scores[partner] = baseScore;
    }
    for (const pid of defenders) {
      scores[pid] = -baseScore;
    }
  } else {
    // ─── Failure: deficit-based with backrun ×2 ───
    // Per-player unit = (bid − declarer team points) × backrunMult.
    //   - 백런: declarer team got ≤ 10 (opp got ≥ 10) → ×2 to all sides
    // Distribution:
    //   - 주공:  −unit × 2  (×2 again if solo / 노프렌즈)
    //   - 친구:  −unit
    //   - 야당:  +unit each
    // Solo (노프렌즈) doubles only the declarer side; each defender still
    // gets +unit, math balances because there's one extra defender.
    const deficit = bid - declarerTeamPoints;
    const backrunMult = declarerTeamPoints <= 10 ? 2 : 1;
    const unit = deficit * backrunMult;

    if (isSolo) {
      scores[declarer] = -unit * 4;
    } else {
      scores[declarer] = -unit * 2;
      if (partner) scores[partner] = -unit;
    }
    for (const pid of defenders) {
      scores[pid] = unit;
    }
  }

  return { scores, declarerPoints: declarerTeamPoints, success };
}

module.exports = {
  countPoints,
  calculateRoundScores,
};
