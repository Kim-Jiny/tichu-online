/**
 * Love Letter Bot - decision making.
 *
 * Guard guessing uses CARD COUNTING over public information (all discard piles,
 * the bot's own hand, and any face-up set-aside cards). This 16-card variant
 * has no Priest, so nobody ever learns another player's exact card, which makes
 * the remaining-card distribution the optimal guess. The old uniform-random
 * guess ignored this and hit far less often.
 */

const { getCardInfo, CARD_TYPE, CARD_VALUES, GUESSABLE_TYPES } = require('./LoveLetterDeck');

// Full deck composition by type (Guard×5, Spy×2, Baron×2, Handmaid×2,
// Prince×2, King/Countess/Princess×1).
const DECK_COUNTS = {
  [CARD_TYPE.GUARD]: 5,
  [CARD_TYPE.SPY]: 2,
  [CARD_TYPE.BARON]: 2,
  [CARD_TYPE.HANDMAID]: 2,
  [CARD_TYPE.PRINCE]: 2,
  [CARD_TYPE.KING]: 1,
  [CARD_TYPE.COUNTESS]: 1,
  [CARD_TYPE.PRINCESS]: 1,
};

/**
 * Main entry point: decide bot action based on game state.
 * @param {object} [opts] - { randomGuess } forces uniform-random Guard guessing
 *        (used only by the bench to measure the card-counting improvement).
 */
function decideLLBotAction(game, botId, opts = {}) {
  if (!game || !game.playerIds.includes(botId)) return null;

  if (game.state === 'playing' && game.currentPlayer === botId) {
    return decidePlay(game, botId);
  }

  if (game.state === 'effect_resolve' && game.pendingEffect) {
    return decideEffect(game, botId, opts);
  }

  return null;
}

function decidePlay(game, botId) {
  const hand = game.hands[botId] || [];
  if (hand.length === 0) return null;

  const infos = hand.map(id => ({ id, info: getCardInfo(id) }));
  const sorted = infos.sort((a, b) => (a.info?.value || 0) - (b.info?.value || 0));

  // Countess rule: must play Countess if holding King or Prince
  const hasCountess = sorted.some(c => c.info?.type === CARD_TYPE.COUNTESS);
  const hasKingOrPrince = sorted.some(c =>
    c.info && (c.info.type === CARD_TYPE.KING || c.info.type === CARD_TYPE.PRINCE)
  );
  if (hasCountess && hasKingOrPrince) {
    const countess = sorted.find(c => c.info?.type === CARD_TYPE.COUNTESS);
    return { type: 'play_card', cardId: countess.id };
  }

  const hasPrincess = sorted.some(c => c.info?.type === CARD_TYPE.PRINCESS);

  // Don't play Princess if possible. When holding the Princess, also
  // avoid Prince (can force self-discard if all opponents are protected)
  // and King (swap gives the Princess away), unless they're the only
  // playable options.
  let playable = sorted.filter(c => c.info?.type !== CARD_TYPE.PRINCESS);
  if (hasPrincess) {
    const safer = playable.filter(c =>
      c.info?.type !== CARD_TYPE.PRINCE && c.info?.type !== CARD_TYPE.KING
    );
    if (safer.length > 0) playable = safer;
  }
  if (playable.length > 0) {
    // Play lowest among the chosen pool
    return { type: 'play_card', cardId: playable[0].id };
  }

  // Only Princess left
  return { type: 'play_card', cardId: sorted[0].id };
}

// Remaining count of each card TYPE that is still unknown (could be in an
// opponent's hand or the draw pile), from public information only.
function remainingTypeCounts(game, botId) {
  const counts = { ...DECK_COUNTS };
  const sub = (cardId) => {
    const t = getCardInfo(cardId)?.type;
    if (t && counts[t] != null) counts[t] -= 1;
  };
  for (const pid of game.playerIds) {
    for (const cid of (game.discardPiles?.[pid] || [])) sub(cid);
  }
  for (const cid of (game.hands?.[botId] || [])) sub(cid);
  for (const cid of (game.faceUpCards || [])) sub(cid); // public set-aside (2p)
  return counts;
}

// Best Guard guess = the most plentiful remaining guessable type (Guard itself
// can't be guessed). Ties broken toward the higher-value card (knock out a
// bigger threat).
function pickGuess(game, botId) {
  const counts = remainingTypeCounts(game, botId);
  let best = GUESSABLE_TYPES[0];
  let bestN = -Infinity;
  let bestV = -Infinity;
  for (const t of GUESSABLE_TYPES) {
    const n = counts[t] || 0;
    // CARD_VALUES keyed by type — building card ids breaks for the singletons
    // (ll_king / ll_countess / ll_princess have no _1 suffix), which would mis-
    // value them as 0 and defeat the "tie → guess the bigger card" tiebreak.
    const v = CARD_VALUES[t] ?? 0;
    if (n > bestN || (n === bestN && v > bestV)) {
      best = t; bestN = n; bestV = v;
    }
  }
  return best;
}

function decideEffect(game, botId, opts = {}) {
  const eff = game.pendingEffect;
  if (!eff || eff.playerId !== botId) return null;

  if (eff.resolved) {
    return { type: 'effect_ack' };
  }

  if (eff.type === 'guard') {
    const target = pickRandomTarget(eff.validTargets);
    const guess = opts.randomGuess
      ? GUESSABLE_TYPES[Math.floor(Math.random() * GUESSABLE_TYPES.length)]
      : pickGuess(game, botId);
    return { type: 'guard_guess', targetId: target, guess };
  }

  if (eff.needsTarget) {
    // Prince includes self in validTargets. Targeting self discards
    // our own card — catastrophic when holding the Princess. Prefer
    // opponents and only fall back to self if no opponent is valid.
    let targets = eff.validTargets;
    if (eff.type === 'prince') {
      const opponents = targets.filter(t => t !== botId);
      if (opponents.length > 0) targets = opponents;
    }
    const target = pickRandomTarget(targets);
    return { type: 'select_target', targetId: target };
  }

  return null;
}

function pickRandomTarget(targets) {
  if (!targets || targets.length === 0) return null;
  return targets[Math.floor(Math.random() * targets.length)];
}

module.exports = { decideLLBotAction };
