import type { CardId, Rank, Suit } from './types';

/**
 * Card identity helpers.
 *
 * Card ids are `{suit}_{rank}` or `special_{name}` (server/game/Deck.js:11).
 * The server sorts `myCards` before sending, so nothing here re-sorts a hand —
 * these are for rendering and for the one piece of rule logic the client needs.
 */

export const SUITS: Suit[] = ['spade', 'heart', 'diamond', 'club'];

export const RANKS: Rank[] = [
  '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A',
];

/** Matches PlayingCard.suitColors in flutter_app/lib/widgets/playing_card.dart:31. */
export const SUIT_COLORS: Record<Suit, string> = {
  spade: '#2B2B2B',
  heart: '#D24B4B',
  diamond: '#6FB6E5',
  club: '#4BAA6A',
};

export const SUIT_GLYPHS: Record<Suit, string> = {
  spade: '♠',
  heart: '♥',
  diamond: '♦',
  club: '♣',
};

export const SPECIAL_CARDS = [
  'special_bird',
  'special_dog',
  'special_phoenix',
  'special_dragon',
] as const;

export type SpecialCardId = (typeof SPECIAL_CARDS)[number];

const RANK_VALUES: Record<string, number> = {
  '2': 2, '3': 3, '4': 4, '5': 5, '6': 6, '7': 7, '8': 8,
  '9': 9, '10': 10, J: 11, Q: 12, K: 13, A: 14,
};

export function isSpecial(cardId: CardId): boolean {
  return cardId.startsWith('special_');
}

export function suitOf(cardId: CardId): Suit | null {
  if (isSpecial(cardId)) return null;
  const suit = cardId.split('_')[0] as Suit;
  return SUITS.includes(suit) ? suit : null;
}

export function rankOf(cardId: CardId): Rank | null {
  if (isSpecial(cardId)) return null;
  const rank = cardId.split('_')[1] as Rank;
  return RANKS.includes(rank) ? rank : null;
}

/**
 * Effective rank, matching the server's ordering. The Phoenix sits at 14.5 as a
 * placeholder — its real value depends on what it is beating, which only the
 * server knows (it comes back as `comboValue` on the played trick).
 */
export function cardValue(cardId: CardId): number {
  switch (cardId) {
    case 'special_bird':
      return 1;
    case 'special_dog':
      return 0;
    case 'special_phoenix':
      return 14.5;
    case 'special_dragon':
      return 15;
    default:
      return RANK_VALUES[cardId.split('_')[1]] ?? 0;
  }
}

/** Tichu scoring value of a single card, for the "points on the table" readout. */
export function cardPoints(cardId: CardId): number {
  if (cardId === 'special_dragon') return 25;
  if (cardId === 'special_phoenix') return -25;
  const rank = rankOf(cardId);
  if (rank === '5') return 5;
  if (rank === '10' || rank === 'K') return 10;
  return 0;
}

export function trickPoints(cards: CardId[]): number {
  return cards.reduce((sum, c) => sum + cardPoints(c), 0);
}

/**
 * Whether a selection is a bomb — the only rule the client evaluates itself.
 *
 * Ported from flutter_app/lib/screens/game_screen.dart:206. It exists purely to
 * decide whether to enable the out-of-turn play button; the server re-validates
 * every play in CardValidator.js, so a false positive here just earns an error
 * toast rather than an illegal move.
 */
export function isBombCombo(cards: CardId[]): boolean {
  if (cards.some(isSpecial)) return false;

  // Four of a kind.
  if (cards.length === 4) {
    const ranks = new Set(cards.map(rankOf));
    return ranks.size === 1;
  }

  // Straight flush: 5+ consecutive cards of one suit.
  if (cards.length >= 5) {
    const suits = new Set(cards.map(suitOf));
    if (suits.size !== 1) return false;
    const values = cards.map(cardValue).sort((a, b) => a - b);
    for (let i = 1; i < values.length; i += 1) {
      if (values[i] !== values[i - 1] + 1) return false;
    }
    return true;
  }

  return false;
}

/** Ranks a Bird wish may name. */
export const WISHABLE_RANKS: Rank[] = RANKS;
