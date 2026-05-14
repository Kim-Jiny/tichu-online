/**
 * Love Letter Bot - Simple AI decision making
 */

const { getCardInfo, CARD_TYPE, GUESSABLE_TYPES } = require('./LoveLetterDeck');

/**
 * Main entry point: decide bot action based on game state
 */
function decideLLBotAction(game, botId) {
  if (!game || !game.playerIds.includes(botId)) return null;

  if (game.state === 'playing' && game.currentPlayer === botId) {
    return decidePlay(game, botId);
  }

  if (game.state === 'effect_resolve' && game.pendingEffect) {
    return decideEffect(game, botId);
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

function decideEffect(game, botId) {
  const eff = game.pendingEffect;
  if (!eff || eff.playerId !== botId) return null;

  if (eff.resolved) {
    return { type: 'effect_ack' };
  }

  if (eff.type === 'guard') {
    const target = pickRandomTarget(eff.validTargets);
    const guess = GUESSABLE_TYPES[Math.floor(Math.random() * GUESSABLE_TYPES.length)];
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
