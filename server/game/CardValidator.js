const { getCardValue, getCardRank, RANK_VALUES } = require('./Deck');

// Combo types
const COMBO = {
  SINGLE: 'single',
  PAIR: 'pair',
  TRIPLE: 'triple',
  STRAIGHT: 'straight',         // 5+ consecutive cards
  FULL_HOUSE: 'full_house',     // triple + pair
  STEPS: 'steps',               // consecutive pairs (2+ pairs)
  BOMB_FOUR: 'bomb_four',       // 4 of same rank
  BOMB_STRAIGHT_FLUSH: 'bomb_straight_flush', // 5+ same suit consecutive
  DOG: 'dog',
  INVALID: 'invalid',
};

function getComboType(cardIds) {
  if (!cardIds || cardIds.length === 0) return { type: COMBO.INVALID };

  // Check for Dog (can only be played alone)
  if (cardIds.length === 1 && cardIds[0] === 'special_dog') {
    return { type: COMBO.DOG, length: 1, value: 0 };
  }

  // Dog cannot be in any combo
  if (cardIds.includes('special_dog')) return { type: COMBO.INVALID };

  // Resolve Phoenix in combos
  const hasPhoenix = cardIds.includes('special_phoenix');
  const normalCards = cardIds.filter((c) => c !== 'special_phoenix');

  // Get values/ranks for normal cards
  const values = normalCards.map((c) => getCardValue(c));
  const ranks = normalCards.map((c) => getCardRank(c));

  if (cardIds.length === 1) {
    return handleSingle(cardIds[0]);
  }

  if (cardIds.length === 2) {
    return handlePair(normalCards, hasPhoenix);
  }

  if (cardIds.length === 3) {
    return handleTriple(normalCards, hasPhoenix);
  }

  // 4 cards
  if (cardIds.length === 4) {
    return handleFourCards(normalCards, hasPhoenix, cardIds);
  }

  // 5+ cards
  return handleFivePlus(normalCards, hasPhoenix, cardIds);
}

function handleSingle(cardId) {
  if (cardId === 'special_dragon') {
    return { type: COMBO.SINGLE, length: 1, value: 15 };
  }
  if (cardId === 'special_phoenix') {
    // Phoenix single: value determined when played (current top + 0.5)
    return { type: COMBO.SINGLE, length: 1, value: -1, isPhoenix: true };
  }
  if (cardId === 'special_bird') {
    return { type: COMBO.SINGLE, length: 1, value: 1 };
  }
  return { type: COMBO.SINGLE, length: 1, value: getCardValue(cardId) };
}

function handlePair(normalCards, hasPhoenix) {
  if (hasPhoenix) {
    // Phoenix + any card = pair of that card's rank
    if (normalCards.length === 1) {
      const v = getCardValue(normalCards[0]);
      if (normalCards[0] === 'special_bird' || normalCards[0] === 'special_dragon') {
        return { type: COMBO.INVALID };
      }
      return { type: COMBO.PAIR, length: 2, value: v, phoenixAs: v };
    }
  }
  if (normalCards.length === 2) {
    const v1 = getCardValue(normalCards[0]);
    const v2 = getCardValue(normalCards[1]);
    if (v1 === v2 && !normalCards.includes('special_bird') && !normalCards.includes('special_dragon')) {
      return { type: COMBO.PAIR, length: 2, value: v1 };
    }
  }
  return { type: COMBO.INVALID };
}

function handleTriple(normalCards, hasPhoenix) {
  const valueCounts = getValueCounts(normalCards);
  const entries = Object.entries(valueCounts);

  if (hasPhoenix) {
    // Phoenix can fill in for a missing card
    if (normalCards.length === 2) {
      const v1 = getCardValue(normalCards[0]);
      const v2 = getCardValue(normalCards[1]);
      if (v1 === v2 && isNormalRank(normalCards[0]) && isNormalRank(normalCards[1])) {
        return { type: COMBO.TRIPLE, length: 3, value: v1, phoenixAs: v1 };
      }
    }
  } else {
    if (normalCards.length === 3) {
      const vals = normalCards.map((c) => getCardValue(c));
      if (vals[0] === vals[1] && vals[1] === vals[2] && isNormalRank(normalCards[0])) {
        return { type: COMBO.TRIPLE, length: 3, value: vals[0] };
      }
    }
  }
  return { type: COMBO.INVALID };
}

function handleFourCards(normalCards, hasPhoenix, allCards) {
  const valueCounts = getValueCounts(normalCards);
  const entries = Object.entries(valueCounts);

  // Check for 4-of-a-kind bomb (no Phoenix allowed in bombs)
  if (!hasPhoenix && normalCards.length === 4) {
    const vals = normalCards.map((c) => getCardValue(c));
    if (vals.every((v) => v === vals[0]) && isNormalRank(normalCards[0])) {
      return { type: COMBO.BOMB_FOUR, length: 4, value: vals[0] };
    }
  }

  // Steps (2 consecutive pairs)
  const stepsResult = checkSteps(normalCards, hasPhoenix, allCards.length);
  if (stepsResult) return stepsResult;

  // Full house not possible with 4 cards
  return { type: COMBO.INVALID };
}

function handleFivePlus(normalCards, hasPhoenix, allCards) {
  const n = allCards.length;

  // Check for straight flush bomb (no Phoenix)
  if (!hasPhoenix) {
    const sfResult = checkStraightFlushBomb(normalCards);
    if (sfResult) return sfResult;
  }

  // Full house (5 cards: triple + pair)
  if (n === 5) {
    const fhResult = checkFullHouse(normalCards, hasPhoenix);
    if (fhResult) return fhResult;
  }

  // Straight (5+ consecutive, Phoenix can fill one gap)
  const straightResult = checkStraight(normalCards, hasPhoenix, n);
  if (straightResult) return straightResult;

  // Steps (consecutive pairs)
  const stepsResult = checkSteps(normalCards, hasPhoenix, n);
  if (stepsResult) return stepsResult;

  return { type: COMBO.INVALID };
}

function checkStraightFlushBomb(cards) {
  if (cards.length < 5) return null;
  // All same suit
  const suits = cards.map((c) => c.split('_')[0]);
  if (!suits.every((s) => s === suits[0])) return null;
  // Check special cards
  if (cards.some((c) => c.startsWith('special_') && c !== 'special_bird')) return null;

  const values = cards.map((c) => getCardValue(c)).sort((a, b) => a - b);
  for (let i = 1; i < values.length; i++) {
    if (values[i] !== values[i - 1] + 1) return null;
  }
  return {
    type: COMBO.BOMB_STRAIGHT_FLUSH,
    length: cards.length,
    value: values[values.length - 1],
    suit: suits[0],
  };
}

function checkFullHouse(normalCards, hasPhoenix) {
  const valueCounts = getValueCounts(normalCards);
  const entries = Object.entries(valueCounts);

  if (hasPhoenix) {
    // Phoenix can be the missing card in triple or pair
    if (entries.length === 2) {
      const [c1, c2] = entries.map(([v, cnt]) => cnt);
      const [v1, v2] = entries.map(([v]) => parseInt(v));
      // 3+1 → Phoenix makes it 3+2 (Phoenix completes the pair)
      if (c1 === 3 && c2 === 1) return { type: COMBO.FULL_HOUSE, length: 5, value: v1, phoenixAs: v2 };
      if (c1 === 1 && c2 === 3) return { type: COMBO.FULL_HOUSE, length: 5, value: v2, phoenixAs: v1 };
      // 2+2 → Phoenix makes higher pair into triple
      if (c1 === 2 && c2 === 2) {
        const tripleVal = Math.max(v1, v2);
        return { type: COMBO.FULL_HOUSE, length: 5, value: tripleVal, phoenixAs: tripleVal };
      }
    }
  } else {
    if (entries.length === 2) {
      const [c1, c2] = entries.map(([v, cnt]) => cnt);
      const [v1, v2] = entries.map(([v]) => parseInt(v));
      if ((c1 === 3 && c2 === 2) || (c1 === 2 && c2 === 3)) {
        const tripleVal = c1 === 3 ? v1 : v2;
        return { type: COMBO.FULL_HOUSE, length: 5, value: tripleVal };
      }
    }
  }
  return null;
}

function checkStraight(normalCards, hasPhoenix, totalLength) {
  if (totalLength < 5) return null;

  let values = normalCards.map((c) => getCardValue(c));
  // Dragon/Dog cannot be in straights
  if (normalCards.includes('special_dragon') || normalCards.includes('special_dog')) return null;
  // Filter valid values for straights (1-14, Bird=1 counts)
  values.sort((a, b) => a - b);

  // Check for duplicates (straights don't have duplicates, except Phoenix fills gaps)
  if (!hasPhoenix) {
    const unique = [...new Set(values)];
    if (unique.length !== values.length) return null;
    if (unique.length !== totalLength) return null;
    // Check consecutive
    for (let i = 1; i < unique.length; i++) {
      if (unique[i] !== unique[i - 1] + 1) return null;
    }
    return { type: COMBO.STRAIGHT, length: totalLength, value: unique[unique.length - 1] };
  } else {
    // With Phoenix: can fill one gap
    const unique = [...new Set(values)].sort((a, b) => a - b);
    if (unique.length !== normalCards.length) return null; // Duplicates not allowed in straight
    if (unique.length + 1 !== totalLength) return null;

    // Try to fill a gap
    let gaps = 0;
    let gapValue = null;
    let highValue = unique[unique.length - 1];
    for (let i = 1; i < unique.length; i++) {
      const diff = unique[i] - unique[i - 1];
      if (diff === 1) continue;
      if (diff === 2) { gaps++; gapValue = unique[i - 1] + 1; }
      else return null;
    }

    if (gaps <= 1) {
      let phoenixAs;
      if (gaps === 0) {
        // Phoenix extends the straight at top (or bottom if top exceeds Ace)
        phoenixAs = unique[unique.length - 1] + 1;
        highValue = phoenixAs;
        if (highValue > 14) {
          highValue = unique[unique.length - 1];
          phoenixAs = unique[0] - 1; // extend at bottom
        }
      } else {
        // Phoenix fills the gap
        phoenixAs = gapValue;
      }
      return { type: COMBO.STRAIGHT, length: totalLength, value: highValue, phoenixAs };
    }
    return null;
  }
}

function checkSteps(normalCards, hasPhoenix, totalLength) {
  // Steps = consecutive pairs (4, 6, 8, 10... cards)
  if (totalLength % 2 !== 0 || totalLength < 4) return null;
  const numPairs = totalLength / 2;

  const valueCounts = getValueCounts(normalCards);
  const entries = Object.entries(valueCounts)
    .map(([v, c]) => ({ value: parseInt(v), count: c }))
    .sort((a, b) => a.value - b.value);

  if (hasPhoenix) {
    // Phoenix can fill one missing card to complete a pair
    let phoenixUsed = false;
    let phoenixAs = null;
    const pairs = [];

    for (const e of entries) {
      if (e.count === 2) {
        pairs.push(e.value);
      } else if (e.count === 1 && !phoenixUsed) {
        pairs.push(e.value);
        phoenixAs = e.value;
        phoenixUsed = true;
      } else if (e.count === 3 && !phoenixUsed) {
        return null;
      } else {
        return null;
      }
    }

    if (pairs.length !== numPairs) return null;
    pairs.sort((a, b) => a - b);
    for (let i = 1; i < pairs.length; i++) {
      if (pairs[i] !== pairs[i - 1] + 1) return null;
    }
    return { type: COMBO.STEPS, length: totalLength, value: pairs[pairs.length - 1], numPairs, phoenixAs };
  } else {
    // All entries must be pairs
    if (entries.length !== numPairs) return null;
    if (!entries.every((e) => e.count === 2)) return null;
    // Check consecutive
    for (let i = 1; i < entries.length; i++) {
      if (entries[i].value !== entries[i - 1].value + 1) return null;
    }
    return { type: COMBO.STEPS, length: totalLength, value: entries[entries.length - 1].value, numPairs };
  }
}

function canBeat(currentCombo, newCombo) {
  if (!currentCombo) return true; // First play of trick

  // Bombs beat anything
  if (isBomb(newCombo)) {
    if (isBomb(currentCombo)) {
      return compareBombs(currentCombo, newCombo);
    }
    return true;
  }

  // Non-bomb can't beat bomb
  if (isBomb(currentCombo)) return false;

  // Same type and same length required
  if (currentCombo.type !== newCombo.type) return false;
  if (currentCombo.length !== newCombo.length) return false;

  // Steps must have same number of pairs
  if (currentCombo.type === COMBO.STEPS && currentCombo.numPairs !== newCombo.numPairs) return false;

  // Higher value wins
  return newCombo.value > currentCombo.value;
}

function isBomb(combo) {
  return combo.type === COMBO.BOMB_FOUR || combo.type === COMBO.BOMB_STRAIGHT_FLUSH;
}

function compareBombs(current, next) {
  // Straight flush bomb beats 4-of-a-kind bomb
  if (current.type === COMBO.BOMB_FOUR && next.type === COMBO.BOMB_STRAIGHT_FLUSH) return true;
  if (current.type === COMBO.BOMB_STRAIGHT_FLUSH && next.type === COMBO.BOMB_FOUR) return false;

  // Both same bomb type
  if (current.type === COMBO.BOMB_STRAIGHT_FLUSH && next.type === COMBO.BOMB_STRAIGHT_FLUSH) {
    // Longer straight flush wins; if same length, higher value wins
    if (next.length > current.length) return true;
    if (next.length < current.length) return false;
    return next.value > current.value;
  }

  // Both 4-of-a-kind
  return next.value > current.value;
}

function getValueCounts(cardIds) {
  const counts = {};
  for (const id of cardIds) {
    const v = getCardValue(id);
    counts[v] = (counts[v] || 0) + 1;
  }
  return counts;
}

function isNormalRank(cardId) {
  return !cardId.startsWith('special_');
}

// Reorder cards for display: straights low→high, full house pair→triple, steps low→high
function arrangeCardsWithPhoenix(cardIds, combo) {
  const hasPhoenix = cardIds.includes('special_phoenix');
  const normalCards = cardIds.filter((c) => c !== 'special_phoenix');

  // Sort normal cards by value (low to high)
  normalCards.sort((a, b) => getCardValue(a) - getCardValue(b));

  // Full house: pair first, then triple
  if (combo.type === COMBO.FULL_HOUSE) {
    const tripleVal = combo.value;
    const pairCards = [];
    const tripleCards = [];
    for (const c of normalCards) {
      if (getCardValue(c) === tripleVal && tripleCards.length < 3) {
        tripleCards.push(c);
      } else {
        pairCards.push(c);
      }
    }
    // Phoenix in full house: insert into whichever group needs it
    if (hasPhoenix && combo.phoenixAs !== undefined) {
      if (tripleCards.length < 3 && combo.phoenixAs === tripleVal) {
        tripleCards.push('special_phoenix');
      } else {
        pairCards.push('special_phoenix');
      }
    }
    return [...pairCards, ...tripleCards];
  }

  // For other combos: just insert phoenix at its logical position
  if (hasPhoenix && combo.phoenixAs !== undefined) {
    const phoenixVal = combo.phoenixAs;
    const result = [];
    let inserted = false;
    for (let i = 0; i < normalCards.length; i++) {
      if (!inserted && getCardValue(normalCards[i]) > phoenixVal) {
        result.push('special_phoenix');
        inserted = true;
      }
      result.push(normalCards[i]);
    }
    if (!inserted) result.push('special_phoenix');
    return result;
  }

  return normalCards;
}

module.exports = { getComboType, canBeat, isBomb, arrangeCardsWithPhoenix, COMBO };
