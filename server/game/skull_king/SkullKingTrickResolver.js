/**
 * Skull King Trick Resolver
 *
 * Hierarchy: Mermaid > Skull King > Pirate > Number (trump=black > lead suit)
 * Special: Mermaid captures SK (+50 bonus), SK captures pirate (+30/pirate)
 * All escape → lead player wins
 * Tigress: played as pirate or escape
 */

const { CARD_TYPE, getCardInfo } = require('./SkullKingDeck');

/**
 * Resolve a trick and determine winner + bonus
 * @param {Array} trickPlays - [{playerId, cardId, tigressChoice?}] in play order
 * @returns {{ winnerId, bonus, bonusDetail }}
 */
function resolveTrick(trickPlays) {
  if (!trickPlays || trickPlays.length === 0) return null;

  // Build resolved cards (apply tigress choice)
  const resolved = trickPlays.map(play => {
    const info = getCardInfo(play.cardId);
    let effectiveType = info.type;
    if (info.type === CARD_TYPE.TIGRESS) {
      effectiveType = play.tigressChoice === 'pirate' ? CARD_TYPE.PIRATE : CARD_TYPE.ESCAPE;
    }
    return {
      ...play,
      info,
      effectiveType,
      suit: info.suit,
      value: info.value || 0,
    };
  });

  // Determine lead suit (first numbered card's suit)
  let leadSuit = null;
  for (const r of resolved) {
    if (r.effectiveType === CARD_TYPE.NUMBER) {
      leadSuit = r.suit;
      break;
    }
  }

  // Check if all are escapes
  const allEscape = resolved.every(r => r.effectiveType === CARD_TYPE.ESCAPE);
  if (allEscape) {
    return { winnerId: resolved[0].playerId, bonus: 0, bonusDetail: [] };
  }

  // Check for special card interactions
  const hasSK = resolved.some(r => r.effectiveType === CARD_TYPE.SKULL_KING);
  const hasMermaid = resolved.some(r => r.effectiveType === CARD_TYPE.MERMAID);
  const hasPirate = resolved.some(r => r.effectiveType === CARD_TYPE.PIRATE);

  let winnerId = null;
  let bonus = 0;
  const bonusDetail = [];

  if (hasSK && hasMermaid) {
    // Mermaid captures Skull King → first mermaid player wins, +50 bonus
    const mermaidPlay = resolved.find(r => r.effectiveType === CARD_TYPE.MERMAID);
    winnerId = mermaidPlay.playerId;
    bonus += 50;
    bonusDetail.push({ type: 'mermaid_captures_sk', points: 50 });
  } else if (hasSK) {
    // Skull King wins, +30 per pirate captured
    const skPlay = resolved.find(r => r.effectiveType === CARD_TYPE.SKULL_KING);
    winnerId = skPlay.playerId;
    const pirateCount = resolved.filter(r => r.effectiveType === CARD_TYPE.PIRATE).length;
    if (pirateCount > 0) {
      bonus += 30 * pirateCount;
      bonusDetail.push({ type: 'sk_captures_pirates', count: pirateCount, points: 30 * pirateCount });
    }
  } else if (hasPirate) {
    // First pirate wins (pirates beat all numbered)
    const piratePlay = resolved.find(r => r.effectiveType === CARD_TYPE.PIRATE);
    winnerId = piratePlay.playerId;
  } else if (hasMermaid) {
    // Mermaid wins over numbers (no SK or pirate present)
    const mermaidPlay = resolved.find(r => r.effectiveType === CARD_TYPE.MERMAID);
    winnerId = mermaidPlay.playerId;
  } else {
    // Only numbered cards (and escapes)
    // Highest trump (black) wins, else highest of lead suit
    const numbered = resolved.filter(r => r.effectiveType === CARD_TYPE.NUMBER);
    const trumpCards = numbered.filter(r => r.suit === 'black');
    const leadCards = numbered.filter(r => r.suit === leadSuit);

    if (trumpCards.length > 0) {
      trumpCards.sort((a, b) => b.value - a.value);
      winnerId = trumpCards[0].playerId;
    } else if (leadCards.length > 0) {
      leadCards.sort((a, b) => b.value - a.value);
      winnerId = leadCards[0].playerId;
    } else {
      // Edge case: no trump, no lead-suit cards (all off-suit numbers)
      // First numbered card player wins
      winnerId = numbered[0].playerId;
    }
  }

  return { winnerId, bonus, bonusDetail };
}

module.exports = { resolveTrick };
