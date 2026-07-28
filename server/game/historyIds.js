'use strict';

/**
 * Translating playerIds inside per-round history entries.
 *
 * Every engine's score/round history is keyed by playerId, which is fine while
 * a match stays on one instance: reconnects rewrite the ids in place via
 * updatePlayerId. A migrated match can't rely on that — it arrives on the peer
 * as plain data, and by the time a game object exists every player has already
 * been issued a fresh id. So the history travels nickname-keyed and is
 * translated back on arrival.
 *
 * Which fields carry ids is not guesswork: it is exactly what each engine's
 * updatePlayerId rewrites. Keep the two in sync — a field added there needs
 * translating here, or it survives migration pointing at an id that no longer
 * exists.
 *
 * Unresolvable names are dropped rather than kept as dangling references. The
 * roster is validated before any of this runs (GameRoom._takeMatchProgress),
 * so it should never happen; if it does, a missing scoreboard row beats a row
 * attributed to nobody.
 */

/** Remap an object's keys (playerId -> nickname, or back). */
function mapKeys(obj, translate) {
  if (!obj || typeof obj !== 'object') return obj;
  const out = {};
  for (const [key, value] of Object.entries(obj)) {
    const mapped = translate(key);
    if (mapped !== undefined && mapped !== null) out[mapped] = value;
  }
  return out;
}

/** Remap a single id field, preserving an intentional null/undefined. */
function mapId(id, translate) {
  if (id === null || id === undefined) return id;
  const mapped = translate(id);
  return mapped === undefined ? null : mapped;
}

/** Remap an array of ids, dropping any that don't resolve. */
function mapIds(list, translate) {
  if (!Array.isArray(list)) return list;
  return list
    .map((id) => (id === null || id === undefined ? id : translate(id)))
    .filter((id) => id !== undefined && id !== null);
}

module.exports = { mapKeys, mapId, mapIds };
