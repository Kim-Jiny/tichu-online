'use strict';

/**
 * "스컬" (Skull) has no shared deck — each player owns a private pool of 4
 * discs (3 rose + 1 skull) that persists across the whole match and only
 * ever shrinks (one disc is permanently discarded per failed challenge).
 * This module just holds the constants both Game and Bot key off of.
 */

const DISC = { ROSE: 'rose', SKULL: 'skull' };

const ROSES_PER_PLAYER = 3;
const MIN_PLAYERS = 3;
const MAX_PLAYERS = 6;
const TARGET_SUCCESSES = 2;

/** A fresh permanent disc pool for a player at match start. */
function freshPool() {
  return { roses: ROSES_PER_PLAYER, hasSkull: true };
}

/** Total discs left in a pool (roses + the skull, if not yet discarded). */
function poolSize(pool) {
  return pool.roses + (pool.hasSkull ? 1 : 0);
}

module.exports = { DISC, ROSES_PER_PLAYER, MIN_PLAYERS, MAX_PLAYERS, TARGET_SUCCESSES, freshPool, poolSize };
