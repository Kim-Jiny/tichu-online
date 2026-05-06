'use strict';

/**
 * World sampler for Mighty PIMC.
 *
 * Given the live game state from `botId`'s perspective, return a clone of the
 * game where opponents' hidden hands have been re-dealt to a plausible
 * distribution consistent with what the bot can observe:
 *
 *   - bot's own hand stays exact
 *   - each other player keeps the *number* of cards they currently hold
 *   - cards already played, discarded, or revealed (e.g., declarer's kitty
 *     after exchange) are not re-dealt
 *   - known voids (a player failed to follow suit on a previous trick) are
 *     respected — those cards are forbidden in that player's hand
 *
 * Friend-card constraint: if `game.friendRevealed` is true, the friend
 * (`game.partner`) must hold the friend card if it's still unplayed; we
 * enforce this by pre-placing it before random allocation. If friend is
 * unrevealed, the friend card is treated like any other unseen card (some
 * opponent holds it; rollout will reveal them when they play it).
 *
 * Returns the cloned game (caller may mutate freely). On failure to satisfy
 * void constraints (rare), falls back to ignoring voids for the offending
 * card so the rollout can still proceed.
 */

const { getCardInfo, createDeck, shuffle } = require('../MightyDeck');
const { getKnownVoids } = require('../MightyBot');

const ALL_CARDS = createDeck();

/** All cards already accounted for (in someone's hand or already revealed). */
function _accountedCards(game, botId) {
  const seen = new Set();
  // Bot's own hand
  for (const c of (game.hands[botId] || [])) seen.add(c);
  // Played in past tricks
  for (const trick of (game.tricks || [])) {
    for (const play of trick.cards) seen.add(play.cardId);
  }
  // Played in current trick
  for (const play of (game.currentTrick || [])) seen.add(play.cardId);
  // Discarded (kitty leftovers known after exchange)
  for (const c of (game.discarded || [])) seen.add(c);
  // Kitty cards still in the kitty pile — not in any player's hand, so we
  // exclude them from the redeal pool (clone() keeps them in game.kitty).
  for (const c of (game.kitty || [])) seen.add(c);
  return seen;
}

/**
 * Distribute `pool` cards to other players to refill their hands to the
 * known sizes, respecting per-player void sets and per-card forbids.
 * For each card in shuffled order, pick a random eligible player. Falls
 * back to placing anyway if no player is eligible (constraint violation
 * acceptable).
 *
 * `cardForbidden`: optional `{pid: Set<cardId>}` map. When present, the
 * allocator avoids placing those cards in those players' hands. Used to
 * encode signal-based inferences (e.g., "this player didn't use joker
 * on a joker-required trick → they almost certainly don't hold it").
 */
function _allocate(pool, sizes, voids, rng, cardForbidden = {}) {
  const result = {};
  for (const pid of Object.keys(sizes)) result[pid] = [];
  const remaining = { ...sizes };
  const cards = shuffle(pool, rng);

  for (const cardId of cards) {
    let info = null;
    if (cardId !== 'mighty_joker') info = getCardInfo(cardId);
    // Build eligible list
    const eligible = [];
    for (const pid of Object.keys(remaining)) {
      if (remaining[pid] <= 0) continue;
      if (info && voids[pid] && voids[pid].has(info.suit)) continue;
      if (cardForbidden[pid] && cardForbidden[pid].has(cardId)) continue;
      eligible.push(pid);
    }
    let pid;
    if (eligible.length > 0) {
      pid = eligible[Math.floor(rng() * eligible.length)];
    } else {
      // Fallback: pick any remaining player even if it violates void
      const fallback = Object.keys(remaining).filter(p => remaining[p] > 0);
      if (fallback.length === 0) {
        // Pool larger than expected — drop the extra (shouldn't happen
        // when sizes match the pool length).
        continue;
      }
      pid = fallback[Math.floor(rng() * fallback.length)];
    }
    result[pid].push(cardId);
    remaining[pid]--;
  }
  return result;
}

/**
 * Infer who almost certainly does NOT hold the joker, based on past
 * "joker-required" tricks they could have played joker on but didn't.
 *
 * Per the joker-signal rule (user spec):
 *   - Joker absence is only meaningful when joker was the ONLY way to
 *     win the trick. The canonical case is declarer leading trump A
 *     (in trump mode) — beats every non-mighty/non-joker card, so a
 *     follower who could have taken it could only do so via joker.
 *   - "Didn't play joker on a trick where they should have" → that
 *     player almost certainly doesn't hold it.
 *
 * Returns a Set of playerIds who are jokerless candidates.
 */
function _jokerlessFromSignals(game) {
  const set = new Set();
  if (!game.trumpSuit || game.trumpSuit === 'no_trump') return set;
  const trumpAce = `mighty_${game.trumpSuit}_A`;
  const tricks = game.tricks || [];
  for (const trick of tricks) {
    if (!trick.cards || trick.cards.length === 0) continue;
    const lead = trick.cards[0];
    if (lead.cardId !== trumpAce) continue;
    if (lead.pid !== game.declarer) continue;
    // Joker was a viable winner against trump A (in any trick where it
    // had power — i.e., trick index > 0 by default, < lastTrick by
    // default). Skip the no-power-trick case to be safe.
    const trickIdx = tricks.indexOf(trick);
    const totalTricks = Math.floor(50 / (game.activePlayerCount || game.playerCount));
    const isFirst = trickIdx === 0;
    const isLast = trickIdx === totalTricks - 1;
    const jokerWasPowered =
      (!isFirst || game.options.firstTrickJokerPower)
      && (!isLast || game.options.lastTrickJokerPower);
    if (!jokerWasPowered) continue;
    for (let i = 1; i < trick.cards.length; i++) {
      const play = trick.cards[i];
      if (play.cardId === 'mighty_joker') continue;
      set.add(play.pid);
    }
  }
  return set;
}

/**
 * Sample a determinized world for `botId`. Returns a clone of `game` with
 * other players' hands replaced by a sampled distribution. Bot's own hand
 * is preserved exactly.
 */
function sampleWorld(game, botId, rng = Math.random) {
  const clone = game.clone();
  const accounted = _accountedCards(clone, botId);
  const pool = ALL_CARDS.filter(c => !accounted.has(c));

  // Hand sizes for non-bot, non-excluded players
  const sizes = {};
  for (const pid of clone.playerIds) {
    if (pid === botId) continue;
    if (clone.excludedPlayers && clone.excludedPlayers.has(pid)) continue;
    sizes[pid] = (clone.hands[pid] || []).length;
  }

  const voids = getKnownVoids(clone);

  // Friend constraint: if revealed and partner known, ensure partner holds
  // friend card if still unplayed. Pre-place it so allocator doesn't fight.
  if (clone.friendRevealed && clone.partner && clone.friendCard
      && pool.includes(clone.friendCard)
      && clone.partner !== botId
      && sizes[clone.partner] > 0) {
    const idx = pool.indexOf(clone.friendCard);
    pool.splice(idx, 1);
    clone.hands[clone.partner] = [clone.friendCard];
    sizes[clone.partner]--;
  } else {
    // Reset hands for re-deal
    for (const pid of Object.keys(sizes)) clone.hands[pid] = [];
  }
  // Ensure bot's hand untouched (clone() already preserves it)

  const totalNeeded = Object.values(sizes).reduce((a, b) => a + b, 0);
  if (totalNeeded > pool.length) {
    // Underflow — shouldn't happen, but guard against ruining state.
    // Just give back the clone as-is so caller can still rollout.
    return clone;
  }

  // Signal-based joker inference: if a non-bot player passed up a
  // joker-required trick, exclude them from getting joker.
  const cardForbidden = {};
  if (pool.includes('mighty_joker')) {
    const jokerless = _jokerlessFromSignals(clone);
    for (const pid of jokerless) {
      if (pid === botId) continue;
      if (!sizes[pid]) continue;
      if (!cardForbidden[pid]) cardForbidden[pid] = new Set();
      cardForbidden[pid].add('mighty_joker');
    }
  }

  const allocated = _allocate(pool, sizes, voids, rng, cardForbidden);
  for (const pid of Object.keys(allocated)) {
    if (clone.hands[pid] && clone.hands[pid].length > 0) {
      // Pre-placed friend card — append rest
      clone.hands[pid] = clone.hands[pid].concat(allocated[pid]);
    } else {
      clone.hands[pid] = allocated[pid];
    }
  }

  return clone;
}

module.exports = { sampleWorld, ALL_CARDS };
