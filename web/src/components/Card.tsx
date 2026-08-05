import { SUIT_COLORS, SUIT_GLYPHS, isSpecial, rankOf, suitOf } from '../protocol/cards';
import type { CardId } from '../protocol/types';

/**
 * A single Tichu card.
 *
 * The 52 ordinary cards have no artwork anywhere in the project — the Flutter
 * app paints them from a suit→colour map plus a rank glyph
 * (flutter_app/lib/widgets/playing_card.dart:166). Reproducing that in CSS keeps
 * the two clients visually identical and costs no bytes. Only the four special
 * cards are images.
 */

const SPECIAL_ART: Record<string, string> = {
  special_bird: 'cards/bird.png',
  special_dog: 'cards/dog.png',
  special_phoenix: 'cards/phoenix.png',
  special_dragon: 'cards/dragon.png',
};

const SPECIAL_LABELS: Record<string, string> = {
  special_bird: '참새',
  special_dog: '개',
  special_phoenix: '봉황',
  special_dragon: '용',
};

export interface CardProps {
  cardId: CardId;
  selected?: boolean;
  disabled?: boolean;
  faceDown?: boolean;
  /** Overlaid bottom-right; used for the Phoenix's effective value in a trick. */
  badge?: string;
  size?: 'sm' | 'md' | 'lg';
  onClick?: () => void;
}

export function Card({
  cardId,
  selected = false,
  disabled = false,
  faceDown = false,
  badge,
  size = 'md',
  onClick,
}: CardProps) {
  const classes = [
    'card',
    `card--${size}`,
    selected ? 'card--selected' : '',
    disabled ? 'card--disabled' : '',
    onClick ? 'card--interactive' : '',
  ]
    .filter(Boolean)
    .join(' ');

  if (faceDown) {
    return <div className={`${classes} card--back`} aria-hidden="true" />;
  }

  const label = isSpecial(cardId)
    ? (SPECIAL_LABELS[cardId] ?? cardId)
    : `${SUIT_GLYPHS[suitOf(cardId)!] ?? ''}${rankOf(cardId) ?? ''}`;

  return (
    <button
      type="button"
      className={classes}
      onClick={disabled ? undefined : onClick}
      disabled={disabled || !onClick}
      aria-label={label}
      aria-pressed={onClick ? selected : undefined}
    >
      {isSpecial(cardId) ? (
        <img className="card__art" src={SPECIAL_ART[cardId]} alt={label} draggable={false} />
      ) : (
        <NormalFace cardId={cardId} />
      )}
      {badge ? <span className="card__badge">{badge}</span> : null}
    </button>
  );
}

function NormalFace({ cardId }: { cardId: CardId }) {
  const suit = suitOf(cardId);
  const rank = rankOf(cardId);
  if (!suit || !rank) return null;
  const color = SUIT_COLORS[suit];
  return (
    <span className="card__face" style={{ color }}>
      <span className="card__suit">{SUIT_GLYPHS[suit]}</span>
      <span className="card__rank">{rank}</span>
    </span>
  );
}
