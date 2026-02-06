const SUITS = ['spade', 'heart', 'diamond', 'club'];
const RANKS = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];
const SPECIAL_CARDS = ['special_bird', 'special_dog', 'special_phoenix', 'special_dragon'];

// Rank values for ordering (Bird=1, 2-10, J=11, Q=12, K=13, A=14, Dragon=15)
const RANK_VALUES = {
  '2': 2, '3': 3, '4': 4, '5': 5, '6': 6, '7': 7, '8': 8,
  '9': 9, '10': 10, 'J': 11, 'Q': 12, 'K': 13, 'A': 14,
};

function createDeck() {
  const deck = [];
  for (const suit of SUITS) {
    for (const rank of RANKS) {
      deck.push({
        id: `${suit}_${rank}`,
        suit: suit,
        rank: rank,
        value: RANK_VALUES[rank],
        special: false,
      });
    }
  }
  // Special cards
  deck.push({ id: 'special_bird', suit: 'special', rank: '1', value: 1, special: true });
  deck.push({ id: 'special_dog', suit: 'special', rank: 'dog', value: 0, special: true });
  deck.push({ id: 'special_phoenix', suit: 'special', rank: 'phoenix', value: -1, special: true });
  deck.push({ id: 'special_dragon', suit: 'special', rank: 'dragon', value: 15, special: true });
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

function deal(deck) {
  // Returns { first8: [4 arrays of 8], remaining6: [4 arrays of 6] }
  const shuffled = shuffle(deck);
  const first8 = [[], [], [], []];
  const remaining6 = [[], [], [], []];

  for (let i = 0; i < 32; i++) {
    first8[i % 4].push(shuffled[i]);
  }
  for (let i = 32; i < 56; i++) {
    remaining6[(i - 32) % 4].push(shuffled[i]);
  }

  return { first8, remaining6 };
}

function getCardValue(cardId) {
  if (cardId === 'special_bird') return 1;
  if (cardId === 'special_dog') return 0;
  if (cardId === 'special_phoenix') return -1;
  if (cardId === 'special_dragon') return 15;
  const rank = cardId.split('_')[1];
  return RANK_VALUES[rank] || 0;
}

function getCardRank(cardId) {
  if (cardId === 'special_bird') return '1';
  if (cardId === 'special_dog') return 'dog';
  if (cardId === 'special_phoenix') return 'phoenix';
  if (cardId === 'special_dragon') return 'dragon';
  return cardId.split('_')[1];
}

function sortCards(cards) {
  return [...cards].sort((a, b) => {
    const va = typeof a === 'string' ? getCardValue(a) : a.value;
    const vb = typeof b === 'string' ? getCardValue(b) : b.value;
    return va - vb;
  });
}

module.exports = {
  SUITS, RANKS, SPECIAL_CARDS, RANK_VALUES,
  createDeck, shuffle, deal, getCardValue, getCardRank, sortCards,
};
