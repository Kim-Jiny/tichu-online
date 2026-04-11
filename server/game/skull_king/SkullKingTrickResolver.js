/**
 * Skull King Trick Resolver
 *
 * Base hierarchy: Mermaid > Skull King > Pirate > Number (trump=black > lead suit)
 * Special: Mermaid captures SK (+50 bonus), SK captures pirate (+30/pirate)
 * All escape → lead player wins
 * Tigress: played as pirate or escape
 *
 * Expansions:
 * - Kraken: voids the trick entirely. No winner, no bonus, no trick count.
 *   The player who would have won without the Kraken still leads the next trick.
 * - White Whale: nullifies every special card effect in the trick. Only number
 *   cards count, and the highest value wins regardless of suit (trump loses its
 *   privilege). If no numbers were played, the trick is voided.
 * - Loot: does not affect trick resolution — handled in SkullKingGame.completeTrick.
 *
 * Precedence when both Kraken and White Whale are in the same trick: Kraken wins
 * (the trick is voided).
 */

const { CARD_TYPE, getCardInfo } = require('./SkullKingDeck');

/**
 * Resolve a trick and determine winner + bonus
 * @param {Array} trickPlays - [{playerId, cardId, tigressChoice?}] in play order
 * @returns {{ winnerId, bonus, bonusDetail, voided }}
 *   - voided=true: trick is discarded (Kraken, or White Whale with no numbers).
 *     winnerId is still set to the "would-have-won" player so they lead next trick,
 *     but the game engine must NOT increment tricks/bonus for them.
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

  // ── Expansion: Kraken ─────────────────────────────────────────────────────
  // Kraken voids the trick. To determine the next-trick leader, resolve the
  // trick as if the Kraken weren't played.
  const hasKraken = resolved.some(r => r.effectiveType === CARD_TYPE.KRAKEN);
  if (hasKraken) {
    const withoutKraken = trickPlays.filter(p => {
      const info = getCardInfo(p.cardId);
      return info && info.type !== CARD_TYPE.KRAKEN;
    });
    let nextLeaderId;
    if (withoutKraken.length === 0) {
      // Only a Kraken was played (shouldn't really happen with ≥2 players, but safe)
      nextLeaderId = resolved[0].playerId;
    } else {
      const inner = resolveTrick(withoutKraken);
      nextLeaderId = inner ? inner.winnerId : resolved[0].playerId;
    }
    return {
      winnerId: nextLeaderId,
      bonus: 0,
      bonusDetail: [{ type: 'kraken_void' }],
      voided: true,
    };
  }

  // ── Expansion: White Whale ────────────────────────────────────────────────
  // White Whale nullifies all special card effects. Only number cards count,
  // and the highest value wins regardless of suit. If no numbers were played,
  // the trick is voided (the Whale player leads next).
  const hasWhiteWhale = resolved.some(r => r.effectiveType === CARD_TYPE.WHITE_WHALE);
  if (hasWhiteWhale) {
    const numbered = resolved.filter(r => r.effectiveType === CARD_TYPE.NUMBER);
    if (numbered.length === 0) {
      // No numbers to compare — trick voided. Whale player leads next.
      const whalePlay = resolved.find(r => r.effectiveType === CARD_TYPE.WHITE_WHALE);
      return {
        winnerId: whalePlay.playerId,
        bonus: 0,
        bonusDetail: [{ type: 'white_whale_void' }],
        voided: true,
      };
    }
    // Highest value wins; ties broken by play order (earlier wins).
    let winner = numbered[0];
    for (let i = 1; i < numbered.length; i++) {
      if (numbered[i].value > winner.value) winner = numbered[i];
    }
    return {
      winnerId: winner.playerId,
      bonus: 0,
      bonusDetail: [{ type: 'white_whale_nullify' }],
      voided: false,
    };
  }

  // ── Base game resolution ─────────────────────────────────────────────────

  // Determine lead suit (first numbered card's suit)
  let leadSuit = null;
  for (const r of resolved) {
    if (r.effectiveType === CARD_TYPE.NUMBER) {
      leadSuit = r.suit;
      break;
    }
  }

  // Check if all are escapes (loot is not an escape — if only escapes/loot,
  // loot acts as a non-winner and lead player still wins)
  const allEscapeLike = resolved.every(r =>
    r.effectiveType === CARD_TYPE.ESCAPE || r.effectiveType === CARD_TYPE.LOOT
  );
  if (allEscapeLike) {
    return { winnerId: resolved[0].playerId, bonus: 0, bonusDetail: [], voided: false };
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
    // Only numbered cards (and escapes/loot)
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

  return { winnerId, bonus, bonusDetail, voided: false };
}

module.exports = { resolveTrick };
