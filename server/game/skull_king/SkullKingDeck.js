/**
 * Skull King Deck - 65 cards base (expansions add more)
 * Base: 52 numbered (4 suits x 13 ranks) + 5 Escape + 4 Pirate + 2 Mermaid + 1 Skull King + 1 Tigress
 * Expansions (optional):
 *   - 'kraken': +1 Kraken (voids trick)
 *   - 'white_whale': +1 White Whale (nullifies special card effects)
 *   - 'loot': +2 Loot (bonus points for trick winner + loot player)
 */

const SK_SUITS = ['yellow', 'green', 'purple', 'black']; // black is trump
const SK_RANKS = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13'];

const SK_RANK_VALUES = {
  '1': 1, '2': 2, '3': 3, '4': 4, '5': 5, '6': 6, '7': 7,
  '8': 8, '9': 9, '10': 10, '11': 11, '12': 12, '13': 13,
};

// Card types for trick resolution
const CARD_TYPE = {
  NUMBER: 'number',
  ESCAPE: 'escape',
  PIRATE: 'pirate',
  MERMAID: 'mermaid',
  SKULL_KING: 'skull_king',
  TIGRESS: 'tigress',
  KRAKEN: 'kraken',
  WHITE_WHALE: 'white_whale',
  LOOT: 'loot',
};

// Known expansion ids
const SK_EXPANSIONS = ['kraken', 'white_whale', 'loot', 'pirate_abilities'];

// 해적 5명의 이름(카드 id 의 번호 → 이름). 능력은 'pirate_abilities' 모드를 켰을 때만
// 쓸 수 있고, 모드가 꺼져 있어도 카드는 그대로 쓴다(능력만 없다).
const PIRATE_NAMES = { 1: 'rascal', 2: 'rosie', 3: 'bendt', 4: 'harry', 5: 'juanita' };

/** `sk_pirate_3` → 'bendt'. 해적 카드가 아니거나 번호가 없으면 null. */
function pirateNameOf(cardId) {
  const m = /^sk_pirate_(\d+)$/.exec(cardId || '');
  return m ? (PIRATE_NAMES[Number(m[1])] || null) : null;
}

function createDeck(expansions = []) {
  const deck = [];
  const expansionSet = new Set(Array.isArray(expansions) ? expansions : []);

  // 52 numbered cards (4 suits x 13 ranks)
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

  // Pirate cards (Rascal / Rosie / Bendt / Harry / Juanita)
  //
  // 기본 4장, 해적 능력 모드에서 5장(후아니타 추가).
  //
  // 원래는 모드와 상관없이 5장이었다. 그런데 5번째 해적의 그림
  // (sk_pirate5.webp)은 3.3.0 번들에서 처음 들어갔고, 버전 게이트
  // (clientCanAccessRoom → roomHasSKPirateAbilities)는 능력 모드를 켠 방만
  // 막는다. 그래서 3.2.0 앱이 일반 스컬킹 방에 들어와 이 카드를 받으면
  // 없는 에셋을 찾다 errorBuilder 로 떨어져, 카드 자리에 색칠된 사각형이
  // 뜬다 — 기존 유저 전체에게.
  //
  // 5번째 해적을 모드에 묶으면 그 게이트가 그대로 보호막이 된다. 능력이
  // 있을 때만 다섯 번째 해적이 있다는 건 이름표(PIRATE_NAMES)의 구성과도
  // 맞는다.
  //
  // min_version 을 3.3.0 이상으로 올려 3.2.0 이 접속하지 못하게 되면,
  // 이 조건을 지우고 항상 5장으로 되돌려도 된다(공식 룰은 해적 5장이다).
  const pirateCount = expansionSet.has('pirate_abilities') ? 5 : 4;
  for (let i = 1; i <= pirateCount; i++) {
    deck.push({ id: `sk_pirate_${i}`, suit: 'special', rank: 'pirate', value: 0, type: CARD_TYPE.PIRATE });
  }

  // 2 Mermaid cards
  for (let i = 1; i <= 2; i++) {
    deck.push({ id: `sk_mermaid_${i}`, suit: 'special', rank: 'mermaid', value: 0, type: CARD_TYPE.MERMAID });
  }

  // 1 Skull King
  deck.push({ id: 'sk_skull_king', suit: 'special', rank: 'skull_king', value: 0, type: CARD_TYPE.SKULL_KING });

  // 1 Tigress (can be played as pirate or escape)
  deck.push({ id: 'sk_tigress_1', suit: 'special', rank: 'tigress', value: 0, type: CARD_TYPE.TIGRESS });

  // --- Expansions ---

  // Kraken expansion: 1 Kraken (voids the trick)
  if (expansionSet.has('kraken')) {
    deck.push({ id: 'sk_kraken', suit: 'special', rank: 'kraken', value: 0, type: CARD_TYPE.KRAKEN });
  }

  // White Whale expansion: 1 White Whale (nullifies special card effects)
  if (expansionSet.has('white_whale')) {
    deck.push({ id: 'sk_white_whale', suit: 'special', rank: 'white_whale', value: 0, type: CARD_TYPE.WHITE_WHALE });
  }

  // Loot expansion: 2 Loot (bonus points when trick is won)
  if (expansionSet.has('loot')) {
    for (let i = 1; i <= 2; i++) {
      deck.push({ id: `sk_loot_${i}`, suit: 'special', rank: 'loot', value: 0, type: CARD_TYPE.LOOT });
    }
  }

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
  return dealWithRest(deck, playerCount, cardsPerPlayer).hands;
}

/** deal 과 같지만 나눠 주고 남은 카드(Bendt 가 뽑고 Juanita 가 보는 더미)도 돌려준다. */
function dealWithRest(deck, playerCount, cardsPerPlayer) {
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
  return { hands, rest: shuffled.slice(cardsPerPlayer * playerCount) };
}

function getCardInfo(cardId) {
  if (cardId === 'sk_skull_king') {
    return { type: CARD_TYPE.SKULL_KING, suit: 'special', rank: 'skull_king', value: 0 };
  }
  if (cardId === 'sk_kraken') {
    return { type: CARD_TYPE.KRAKEN, suit: 'special', rank: 'kraken', value: 0 };
  }
  if (cardId === 'sk_white_whale') {
    return { type: CARD_TYPE.WHITE_WHALE, suit: 'special', rank: 'white_whale', value: 0 };
  }
  if (cardId.startsWith('sk_tigress')) {
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
  if (cardId.startsWith('sk_loot_')) {
    return { type: CARD_TYPE.LOOT, suit: 'special', rank: 'loot', value: 0 };
  }
  // Numbered card: sk_{suit}_{rank} — strictly validated against known suits
  // and ranks. This also prevents mis-parsing of 3-part expansion ids like
  // `sk_white_whale` if the explicit checks above are ever reordered.
  const parts = cardId.split('_');
  if (parts.length === 3 && parts[0] === 'sk'
      && SK_SUITS.includes(parts[1])
      && SK_RANK_VALUES[parts[2]] !== undefined) {
    const suit = parts[1];
    const rank = parts[2];
    return { type: CARD_TYPE.NUMBER, suit, rank, value: SK_RANK_VALUES[rank] };
  }
  return null;
}

function sortCards(cards) {
  const typeOrder = {
    [CARD_TYPE.ESCAPE]: 0,
    [CARD_TYPE.LOOT]: 0.5,
    [CARD_TYPE.NUMBER]: 1,
    [CARD_TYPE.PIRATE]: 2,
    [CARD_TYPE.TIGRESS]: 3,
    [CARD_TYPE.MERMAID]: 4,
    [CARD_TYPE.SKULL_KING]: 5,
    [CARD_TYPE.WHITE_WHALE]: 6,
    [CARD_TYPE.KRAKEN]: 7,
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
  SK_SUITS, SK_RANKS, SK_RANK_VALUES, CARD_TYPE, SK_EXPANSIONS,
  PIRATE_NAMES, pirateNameOf,
  createDeck, shuffle, deal, dealWithRest, getCardInfo, sortCards,
};
