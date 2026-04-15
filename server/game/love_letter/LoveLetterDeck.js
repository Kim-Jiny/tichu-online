/**
 * Love Letter Deck - 16 cards
 * Guard(1) x5, Spy(2) x2, Baron(3) x2, Handmaid(4) x2,
 * Prince(5) x2, King(6) x1, Countess(7) x1, Princess(8) x1
 */

const CARD_TYPE = {
  GUARD: 'guard',
  SPY: 'spy',
  BARON: 'baron',
  HANDMAID: 'handmaid',
  PRINCE: 'prince',
  KING: 'king',
  COUNTESS: 'countess',
  PRINCESS: 'princess',
};

const CARD_VALUES = {
  [CARD_TYPE.GUARD]: 1,
  [CARD_TYPE.SPY]: 2,
  [CARD_TYPE.BARON]: 3,
  [CARD_TYPE.HANDMAID]: 4,
  [CARD_TYPE.PRINCE]: 5,
  [CARD_TYPE.KING]: 6,
  [CARD_TYPE.COUNTESS]: 7,
  [CARD_TYPE.PRINCESS]: 8,
};

// All guessable card types (everything except Guard)
const GUESSABLE_TYPES = [
  CARD_TYPE.SPY, CARD_TYPE.BARON, CARD_TYPE.HANDMAID,
  CARD_TYPE.PRINCE, CARD_TYPE.KING, CARD_TYPE.COUNTESS, CARD_TYPE.PRINCESS,
];

function createDeck() {
  const deck = [];

  // Guard x5
  for (let i = 1; i <= 5; i++) {
    deck.push({ id: `ll_guard_${i}`, type: CARD_TYPE.GUARD, value: 1 });
  }
  // Spy x2
  for (let i = 1; i <= 2; i++) {
    deck.push({ id: `ll_spy_${i}`, type: CARD_TYPE.SPY, value: 2 });
  }
  // Baron x2
  for (let i = 1; i <= 2; i++) {
    deck.push({ id: `ll_baron_${i}`, type: CARD_TYPE.BARON, value: 3 });
  }
  // Handmaid x2
  for (let i = 1; i <= 2; i++) {
    deck.push({ id: `ll_handmaid_${i}`, type: CARD_TYPE.HANDMAID, value: 4 });
  }
  // Prince x2
  for (let i = 1; i <= 2; i++) {
    deck.push({ id: `ll_prince_${i}`, type: CARD_TYPE.PRINCE, value: 5 });
  }
  // King x1
  deck.push({ id: 'll_king', type: CARD_TYPE.KING, value: 6 });
  // Countess x1
  deck.push({ id: 'll_countess', type: CARD_TYPE.COUNTESS, value: 7 });
  // Princess x1
  deck.push({ id: 'll_princess', type: CARD_TYPE.PRINCESS, value: 8 });

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

/**
 * Deal cards for Love Letter.
 * - 1 card set aside face-down
 * - 2-player: 3 additional cards set aside face-up
 * - Each player gets 1 card
 * - Rest goes to draw pile
 * Returns { hands: {playerId: [card]}, drawPile: [card], setAside: card, faceUpCards: [card] }
 */
function deal(playerIds) {
  const deck = shuffle(createDeck());
  const playerCount = playerIds.length;

  // 1 card face-down set aside
  const setAside = deck.shift();

  // 2-player: 3 face-up cards set aside
  const faceUpCards = [];
  if (playerCount === 2) {
    for (let i = 0; i < 3; i++) {
      faceUpCards.push(deck.shift());
    }
  }

  // Deal 1 card to each player
  const hands = {};
  for (const pid of playerIds) {
    hands[pid] = [deck.shift()];
  }

  // Remaining cards form the draw pile
  return { hands, drawPile: deck, setAside, faceUpCards };
}

function getCardInfo(cardId) {
  if (!cardId || typeof cardId !== 'string') return null;
  if (!cardId.startsWith('ll_')) return null;

  const rest = cardId.slice(3); // remove 'll_'

  if (rest.startsWith('guard_')) return { type: CARD_TYPE.GUARD, value: 1 };
  if (rest.startsWith('spy_')) return { type: CARD_TYPE.SPY, value: 2 };
  if (rest.startsWith('baron_')) return { type: CARD_TYPE.BARON, value: 3 };
  if (rest.startsWith('handmaid_')) return { type: CARD_TYPE.HANDMAID, value: 4 };
  if (rest.startsWith('prince_')) return { type: CARD_TYPE.PRINCE, value: 5 };
  if (rest === 'king') return { type: CARD_TYPE.KING, value: 6 };
  if (rest === 'countess') return { type: CARD_TYPE.COUNTESS, value: 7 };
  if (rest === 'princess') return { type: CARD_TYPE.PRINCESS, value: 8 };

  return null;
}

function sortCards(cards) {
  return [...cards].sort((a, b) => {
    const infoA = typeof a === 'string' ? getCardInfo(a) : a;
    const infoB = typeof b === 'string' ? getCardInfo(b) : b;
    if (!infoA || !infoB) return 0;
    return (infoA.value || 0) - (infoB.value || 0);
  });
}

module.exports = {
  CARD_TYPE, CARD_VALUES, GUESSABLE_TYPES,
  createDeck, shuffle, deal, getCardInfo, sortCards,
};
