/**
 * Skull King Deck - 70 cards total
 * 56 numbered (4 suits x 14 ranks) + 5 Escape + 5 Pirate + 2 Mermaid + 1 Skull King + 1 Tigress
 */

const SK_SUITS = ['yellow', 'green', 'purple', 'black']; // black is trump
const SK_RANKS = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14'];

const SK_RANK_VALUES = {
  '1': 1, '2': 2, '3': 3, '4': 4, '5': 5, '6': 6, '7': 7,
  '8': 8, '9': 9, '10': 10, '11': 11, '12': 12, '13': 13, '14': 14,
};

// Card types for trick resolution
const CARD_TYPE = {
  NUMBER: 'number',
  ESCAPE: 'escape',
  PIRATE: 'pirate',
  MERMAID: 'mermaid',
  SKULL_KING: 'skull_king',
  TIGRESS: 'tigress',
};

function createDeck() {
  const deck = [];

  // 56 numbered cards (4 suits x 14 ranks)
  for (const suit of SK_SUITS) {
    for (const rank of SK_RANKS) {
      deck.push({
        id: `sk_${suit}_${rank}`,
        suit,
        rank,
        value: SK_RANK_VALUES[rank],
        type: CARD_TYPE.NUMBER,
      });
    }
  }

  // 5 Escape cards
  for (let i = 1; i <= 5; i++) {
    deck.push({ id: `sk_escape_${i}`, suit: 'special', rank: 'escape', value: 0, type: CARD_TYPE.ESCAPE });
  }

  // 5 Pirate cards
  for (let i = 1; i <= 5; i++) {
    deck.push({ id: `sk_pirate_${i}`, suit: 'special', rank: 'pirate', value: 0, type: CARD_TYPE.PIRATE });
  }

  // 2 Mermaid cards
  for (let i = 1; i <= 2; i++) {
    deck.push({ id: `sk_mermaid_${i}`, suit: 'special', rank: 'mermaid', value: 0, type: CARD_TYPE.MERMAID });
  }

  // 1 Skull King
  deck.push({ id: 'sk_skull_king', suit: 'special', rank: 'skull_king', value: 0, type: CARD_TYPE.SKULL_KING });

  // 1 Tigress (can be played as pirate or escape)
  deck.push({ id: 'sk_tigress', suit: 'special', rank: 'tigress', value: 0, type: CARD_TYPE.TIGRESS });

  return deck;
}

function shuffle(deck) {
  const arr = [...deck];
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}

function deal(deck, playerCount, cardsPerPlayer) {
  const shuffled = shuffle(deck);
  const hands = [];
  for (let i = 0; i < playerCount; i++) {
    hands.push([]);
  }
  for (let c = 0; c < cardsPerPlayer; c++) {
    for (let p = 0; p < playerCount; p++) {
      hands[p].push(shuffled[c * playerCount + p]);
    }
  }
  return hands;
}

function getCardInfo(cardId) {
  if (cardId === 'sk_skull_king') {
    return { type: CARD_TYPE.SKULL_KING, suit: 'special', rank: 'skull_king', value: 0 };
  }
  if (cardId === 'sk_tigress') {
    return { type: CARD_TYPE.TIGRESS, suit: 'special', rank: 'tigress', value: 0 };
  }
  if (cardId.startsWith('sk_escape_')) {
    return { type: CARD_TYPE.ESCAPE, suit: 'special', rank: 'escape', value: 0 };
  }
  if (cardId.startsWith('sk_pirate_')) {
    return { type: CARD_TYPE.PIRATE, suit: 'special', rank: 'pirate', value: 0 };
  }
  if (cardId.startsWith('sk_mermaid_')) {
    return { type: CARD_TYPE.MERMAID, suit: 'special', rank: 'mermaid', value: 0 };
  }
  // Numbered card: sk_{suit}_{rank}
  const parts = cardId.split('_');
  if (parts.length === 3 && parts[0] === 'sk') {
    const suit = parts[1];
    const rank = parts[2];
    return { type: CARD_TYPE.NUMBER, suit, rank, value: SK_RANK_VALUES[rank] || 0 };
  }
  return null;
}

function sortCards(cards) {
  const typeOrder = {
    [CARD_TYPE.ESCAPE]: 0,
    [CARD_TYPE.NUMBER]: 1,
    [CARD_TYPE.PIRATE]: 2,
    [CARD_TYPE.TIGRESS]: 3,
    [CARD_TYPE.MERMAID]: 4,
    [CARD_TYPE.SKULL_KING]: 5,
  };
  const suitOrder = { yellow: 0, green: 1, purple: 2, black: 3 };

  return [...cards].sort((a, b) => {
    const infoA = typeof a === 'string' ? getCardInfo(a) : a;
    const infoB = typeof b === 'string' ? getCardInfo(b) : b;
    if (!infoA || !infoB) return 0;
    const typeA = typeOrder[infoA.type] ?? 1;
    const typeB = typeOrder[infoB.type] ?? 1;
    if (typeA !== typeB) return typeA - typeB;
    if (infoA.type === CARD_TYPE.NUMBER && infoB.type === CARD_TYPE.NUMBER) {
      const suitA = suitOrder[infoA.suit] ?? 0;
      const suitB = suitOrder[infoB.suit] ?? 0;
      if (suitA !== suitB) return suitA - suitB;
      return (infoA.value || 0) - (infoB.value || 0);
    }
    return 0;
  });
}

module.exports = {
  SK_SUITS, SK_RANKS, SK_RANK_VALUES, CARD_TYPE,
  createDeck, shuffle, deal, getCardInfo, sortCards,
};
