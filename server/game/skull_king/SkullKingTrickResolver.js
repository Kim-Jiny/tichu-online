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
 * 크라켄과 흰고래가 한 트릭에 함께 나오면 — 공식 FAQ —
 *   나중에 나온 쪽의 효과만 적용되고, 먼저 나온 쪽은 도주 카드로 취급한다.
 *   · 크라켄 → 흰고래 : 흰고래가 적용된다(색과 무관하게 가장 높은 숫자가
 *     트릭을 가져가고, 숫자가 없으면 무효). 크라켄은 도주다.
 *   · 흰고래 → 크라켄 : 크라켄이 적용된다(트릭 무효). 흰고래는 도주이고,
 *     다음 트릭은 "두 생물이 없었다면 이겼을 사람"이 시작한다.
 *
 * 리드 무늬(getLeadSuit)는 이 규칙에 영향을 받지 않는다. 그건 카드를 내는
 * 순간순간 정해지는데, 그 시점에는 둘 중 어느 쪽이 나중이 될지 알 수 없다.
 * 소급해서 바꾸면 이미 카드를 낸 사람이 봤던 합법 카드 목록이 달라진다.
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

  // ── 크라켄과 흰고래가 함께 나왔을 때 ──────────────────────────────────
  // 나중에 나온 쪽만 효과를 내고, 먼저 나온 쪽은 도주가 된다(머리말 참고).
  // 덱에 각각 한 장뿐이라 findIndex 로 충분하다.
  const krakenIdx = resolved.findIndex(r => r.effectiveType === CARD_TYPE.KRAKEN);
  const whaleIdx = resolved.findIndex(r => r.effectiveType === CARD_TYPE.WHITE_WHALE);
  // 먼저 나온 쪽을 도주로 바꿔 둔다. 아래 두 분기가 effectiveType 으로
  // 판정하므로, 이 한 줄이 "먼저 나온 쪽은 아무 일도 하지 않는다"를
  // 그대로 만든다 — 흰고래 분기의 숫자 세기에서도 자연히 빠진다.
  let supersededCreature = null;
  if (krakenIdx >= 0 && whaleIdx >= 0) {
    const earlier = krakenIdx < whaleIdx ? krakenIdx : whaleIdx;
    supersededCreature = krakenIdx < whaleIdx ? 'kraken' : 'white_whale';
    resolved[earlier] = { ...resolved[earlier], effectiveType: CARD_TYPE.ESCAPE };
  }

  // ── Expansion: Kraken ─────────────────────────────────────────────────────
  // Kraken voids the trick. To determine the next-trick leader, resolve the
  // trick as if the Kraken weren't played.
  const hasKraken = krakenIdx >= 0
    && resolved[krakenIdx].effectiveType === CARD_TYPE.KRAKEN;
  if (hasKraken) {
    // 두 생물을 모두 뺀 트릭에서 이겼을 사람이 다음을 시작한다. 흰고래가
    // 함께 나왔다면 그건 도주가 됐지만, 다음 선을 정할 때는 "두 생물이
    // 없었다면" 을 묻는 것이므로 둘 다 빼고 센다.
    const withoutCreatures = trickPlays.filter(p => {
      const info = getCardInfo(p.cardId);
      return info
        && info.type !== CARD_TYPE.KRAKEN
        && info.type !== CARD_TYPE.WHITE_WHALE;
    });
    let nextLeaderId;
    if (withoutCreatures.length === 0) {
      // 생물만 나온 트릭(2인 이하에서나 가능). 첫 사람이 선을 잡는다.
      nextLeaderId = resolved[0].playerId;
    } else {
      const inner = resolveTrick(withoutCreatures);
      nextLeaderId = inner ? inner.winnerId : resolved[0].playerId;
    }
    return {
      winnerId: nextLeaderId,
      bonus: 0,
      bonusDetail: [{ type: 'kraken_void', supersededCreature }],
      voided: true,
    };
  }

  // ── Expansion: White Whale ────────────────────────────────────────────────
  // White Whale nullifies all special card effects. Only number cards count,
  // and the highest value wins regardless of suit. If no numbers were played,
  // the trick is voided (the Whale player leads next).
  const hasWhiteWhale = whaleIdx >= 0
    && resolved[whaleIdx].effectiveType === CARD_TYPE.WHITE_WHALE;
  if (hasWhiteWhale) {
    const numbered = resolved.filter(r => r.effectiveType === CARD_TYPE.NUMBER);
    if (numbered.length === 0) {
      // No numbers to compare — trick voided. Whale player leads next.
      const whalePlay = resolved.find(r => r.effectiveType === CARD_TYPE.WHITE_WHALE);
      return {
        winnerId: whalePlay.playerId,
        bonus: 0,
        bonusDetail: [{ type: 'white_whale_void', supersededCreature }],
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
      bonusDetail: [{ type: 'white_whale_nullify', supersededCreature }],
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
