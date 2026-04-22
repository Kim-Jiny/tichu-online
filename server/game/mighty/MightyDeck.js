'use strict';

const SUITS = ['spade', 'diamond', 'heart', 'club'];
const RANKS = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];
const POINT_RANKS = ['A', 'K', 'Q', 'J', '10'];
const RANK_ORDER = { '2': 2, '3': 3, '4': 4, '5': 5, '6': 6, '7': 7, '8': 8, '9': 9, '10': 10, 'J': 11, 'Q': 12, 'K': 13, 'A': 14 };

function createDeck() {
  const deck = [];
  for (const suit of SUITS) {
    for (const rank of RANKS) {
      deck.push(`mighty_${suit}_${rank}`);
    }
  }
  deck.push('mighty_joker');
  return deck;
}

function shuffle(deck) {
  const arr = deck.slice();
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}

function deal(playerIds) {
  const deck = shuffle(createDeck());
  const hands = {};
  for (const pid of playerIds) {
    hands[pid] = [];
  }
  // Deal 10 cards each to 5 players = 50, remaining 3 = kitty
  for (let i = 0; i < 50; i++) {
    hands[playerIds[i % playerIds.length]].push(deck[i]);
  }
  const kitty = deck.slice(50, 53);
  return { hands, kitty };
}

function getCardInfo(cardId) {
  if (cardId === 'mighty_joker') {
    return { suit: null, rank: null, point: 0, isJoker: true };
  }
  const parts = cardId.replace('mighty_', '').split('_');
  const suit = parts[0];
  const rank = parts[1];
  const point = POINT_RANKS.includes(rank) ? 1 : 0;
  return { suit, rank, point, isJoker: false };
}

function sortCards(cards, trumpSuit) {
  const suitOrder = SUITS;

  return cards.slice().sort((a, b) => {
    if (a === 'mighty_joker') return -1;
    if (b === 'mighty_joker') return 1;

    const infoA = getCardInfo(a);
    const infoB = getCardInfo(b);

    const suitIdxA = suitOrder.indexOf(infoA.suit);
    const suitIdxB = suitOrder.indexOf(infoB.suit);
    if (suitIdxA !== suitIdxB) return suitIdxA - suitIdxB;

    return RANK_ORDER[infoB.rank] - RANK_ORDER[infoA.rank];
  });
}

module.exports = {
  SUITS,
  RANKS,
  POINT_RANKS,
  RANK_ORDER,
  createDeck,
  shuffle,
  deal,
  getCardInfo,
  sortCards,
};
