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
    // ─── Success ───
    // Base = (bid − minBid + 1) × 2 + surplus(점수 − bid).
    // Multipliers ×2 for perfect / NT / max-bid stack, and apply to BOTH
    // sides — every defender pays one base, the declarer side collects it.
    let baseScore = (bid - minBid + 1) * 2;
    baseScore += (declarerTeamPoints - bid);
    if (isPerfect) baseScore *= 2;
    if (isNoTrump) baseScore *= 2;
    if (isMaxBid) baseScore *= 2;

    // 노프렌드 is NOT a base multiplier: it means there is no friend to take a
    // share, so the declarer alone collects from one extra defender. Doubling
    // the base instead (the old `if (isSolo) baseScore *= 2`) inflated both
    // sides and, combined with a hardcoded ×2 declarer share, left the pot
    // unbalanced — 4 defenders paid 4×base while the declarer took 2×base.
    // The failure branch below already models solo exactly this way
    // (−unit×4 to the declarer, +unit to each of the 4 defenders).
    scores[declarer] = baseScore * (defenders.length - (isSolo ? 0 : 1));
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
