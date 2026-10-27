/**
 * Love Letter Bot - decision making.
 *
 * Two layers:
 *   - the rule-based bot below, which counts cards (every discard pile, its own
 *     hand, the face-up set-aside cards, and the cards it knows sit in someone
 *     else's hand) and uses what it has learned: a Priest ('spy') shows a hand,
 *     a Baron tie shows both, a King swap shows both, a failed Guard guess tells
 *     everybody what that player does NOT hold (game.knowledge / game.notTypes).
 *   - strat 'mc' (LoveLetterSearch.js): a determinized Monte-Carlo search that
 *     deals the unseen cards at random consistent with all of that, plays the
 *     round out with the rule-based bot, and picks what wins the round most often.
 *
 * Only information a player at this seat could have is read here: never
 * game.drawPile, game.setAside or another player's hand.
 */

const { getCardInfo, CARD_TYPE, CARD_VALUES, GUESSABLE_TYPES } = require('./LoveLetterDeck');

// Full deck composition by type (Guard×5, Priest('spy')×2, Baron×2, Handmaid×2,
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

const ALL_TYPES = Object.keys(DECK_COUNTS);

/**
 * Main entry point: decide bot action based on game state.
 * @param {object|string} [opts] - 'mc' to add the Monte-Carlo search on top of the
 *        rule-based choice; or { randomGuess } to force uniform-random Guard
 *        guessing (used only by the old bench).
 */
function decideLLBotAction(game, botId, opts = {}) {
  if (opts === 'mc') {
    try {
      const a = decideWithSearch(game, botId);
      if (a) return a;
    } catch (e) { /* a broken search must never stall a game — fall through */ }
    return decideLLBotActionHeuristic(game, botId, {});
  }
  return decideLLBotActionHeuristic(game, botId, typeof opts === 'object' && opts ? opts : {});
}

// Tunables, exposed so the A/B harness can sweep them.
const MC = { samples: 40, deadlineMs: 20, margin: 0 };

function decideWithSearch(game, botId) {
  if (!game || !game.playerIds.includes(botId)) return null;
  const { searchPlay, searchEffect } = require('./LoveLetterSearch');
  if (game.state === 'playing' && game.currentPlayer === botId) {
    const base = decidePlay(game, botId);
    return searchPlay(game, botId, base, MC);
  }
  if (game.state === 'effect_resolve' && game.pendingEffect
      && game.pendingEffect.playerId === botId && !game.pendingEffect.resolved) {
    const base = decideEffect(game, botId, {});
    return searchEffect(game, botId, base, MC);
  }
  return null;
}

function decideLLBotActionHeuristic(game, botId, opts = {}) {
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

// ── what the bot knows ────────────────────────────────────────────────────

/** The card viewerId knows holderId is holding, or null. */
function knownCard(game, viewerId, holderId) {
  const k = game.knowledge && game.knowledge[viewerId];
  return (k && k[holderId]) || null;
}

// Remaining count of each card TYPE that could still be an UNKNOWN card (in an
// opponent's hand we know nothing about, or the draw pile), from public info plus
// what this bot has learned. Cards the bot knows sit in a specific hand are not
// candidates for the others.
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
  const k = game.knowledge && game.knowledge[botId];
  if (k) for (const holder of Object.keys(k)) if (holder !== botId && k[holder]) sub(k[holder]);
  return counts;
}

/** Weights of what an unknown card in holderId's hand can be: counts, minus failed guesses. */
function holderWeights(game, counts, holderId) {
  const w = {};
  const banned = (game.notTypes && game.notTypes[holderId]) || [];
  for (const t of ALL_TYPES) w[t] = banned.includes(t) ? 0 : Math.max(0, counts[t] || 0);
  return w;
}

function sumOf(w) {
  let s = 0;
  for (const t of ALL_TYPES) s += w[t];
  return s;
}

// Best Guard guess against one target: its card if known, else the most
// plentiful guessable type left. Returns { guess, p } (p = chance it is right).
function bestGuessFor(game, botId, counts, targetId) {
  const known = knownCard(game, botId, targetId);
  if (known) {
    const t = getCardInfo(known)?.type;
    // A known Guard cannot be named: nothing to gain from this target.
    if (t === CARD_TYPE.GUARD) return { guess: GUESSABLE_TYPES[0], p: 0 };
    return { guess: t, p: 1 };
  }
  const w = holderWeights(game, counts, targetId);
  const total = sumOf(w);
  let best = GUESSABLE_TYPES[0];
  let bestN = -Infinity;
  let bestV = -Infinity;
  for (const t of GUESSABLE_TYPES) {
    const n = w[t];
    // CARD_VALUES keyed by type — building card ids breaks for the singletons
    // (ll_king / ll_countess / ll_princess have no _1 suffix), which would mis-
    // value them as 0 and defeat the "tie → guess the bigger card" tiebreak.
    const v = CARD_VALUES[t] ?? 0;
    if (n > bestN || (n === bestN && v > bestV)) {
      best = t; bestN = n; bestV = v;
    }
  }
  return { guess: best, p: total > 0 ? bestN / total : 0 };
}

function pickBest(items, score) {
  let best = [];
  let bestS = -Infinity;
  for (const it of items) {
    const s = score(it);
    if (s > bestS + 1e-9) { bestS = s; best = [it]; } else if (Math.abs(s - bestS) <= 1e-9) best.push(it);
  }
  return best[Math.floor(Math.random() * best.length)];
}

function expectedValue(w) {
  const total = sumOf(w);
  if (total <= 0) return 0;
  let e = 0;
  for (const t of ALL_TYPES) e += (CARD_VALUES[t] ?? 0) * w[t];
  return e / total;
}

function decideEffect(game, botId, opts = {}) {
  const eff = game.pendingEffect;
  if (!eff || eff.playerId !== botId) return null;

  if (eff.resolved) {
    return { type: 'effect_ack' };
  }

  const counts = remainingTypeCounts(game, botId);

  if (eff.type === 'guard') {
    const targets = eff.targetId && !eff.needsTarget ? [eff.targetId] : eff.validTargets;
    if (opts.randomGuess) {
      return {
        type: 'guard_guess',
        targetId: pickRandomTarget(targets),
        guess: GUESSABLE_TYPES[Math.floor(Math.random() * GUESSABLE_TYPES.length)],
      };
    }
    const choice = pickBest(targets.map(t => ({ t, ...bestGuessFor(game, botId, counts, t) })), c => c.p);
    return { type: 'guard_guess', targetId: choice.t, guess: choice.guess };
  }

  if (eff.needsTarget) {
    return { type: 'select_target', targetId: pickTarget(game, botId, eff, counts) };
  }

  return null;
}

function valueOfKnownOrExpected(game, botId, counts, holderId) {
  const k = knownCard(game, botId, holderId);
  if (k) return getCardInfo(k)?.value ?? 0;
  return expectedValue(holderWeights(game, counts, holderId));
}

function pickTarget(game, botId, eff, counts) {
  const targets = eff.validTargets;
  if (!targets || targets.length === 0) return null;
  const myCard = (game.hands[botId] || [])[0];
  const myV = myCard ? (getCardInfo(myCard)?.value ?? 0) : 0;

  switch (eff.type) {
    case 'baron': {
      // Win the comparison: P(their card is lower) - P(it is higher). A known card is certain.
      return pickBest(targets, (t) => {
        const k = knownCard(game, botId, t);
        if (k) {
          const v = getCardInfo(k)?.value ?? 0;
          return v < myV ? 1 : v > myV ? -1 : 0;
        }
        const w = holderWeights(game, counts, t);
        const total = sumOf(w);
        if (total <= 0) return 0;
        let lo = 0; let hi = 0;
        for (const ty of ALL_TYPES) {
          const v = CARD_VALUES[ty] ?? 0;
          if (v < myV) lo += w[ty]; else if (v > myV) hi += w[ty];
        }
        return (lo - hi) / total;
      });
    }
    case 'king':
      // Swap with whoever probably holds the best card.
      return pickBest(targets, (t) => valueOfKnownOrExpected(game, botId, counts, t) - myV);
    case 'prince': {
      // Prefer opponents. A known Princess is a kill; otherwise hit the strongest hand.
      const opponents = targets.filter(t => t !== botId);
      const pool = opponents.length > 0 ? opponents : targets;
      return pickBest(pool, (t) => {
        const k = knownCard(game, botId, t);
        if (k && getCardInfo(k)?.type === CARD_TYPE.PRINCESS) return 100;
        return valueOfKnownOrExpected(game, botId, counts, t);
      });
    }
    default: {
      // Priest ('spy'): look at someone we know nothing about.
      const unknown = targets.filter(t => !knownCard(game, botId, t));
      return pickRandomTarget(unknown.length ? unknown : targets);
    }
  }
}

function pickRandomTarget(targets) {
  if (!targets || targets.length === 0) return null;
  return targets[Math.floor(Math.random() * targets.length)];
}

module.exports = {
  decideLLBotAction, decideLLBotActionHeuristic, decidePlay, decideEffect, remainingTypeCounts,
  MC, DECK_COUNTS,
};
