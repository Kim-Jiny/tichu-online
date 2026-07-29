'use strict';

/**
 * How long a room may sit on one game-state signature before the watchdog
 * calls it frozen.
 *
 * This has to track the room's own turn limit, which players choose when they
 * create the room and which the server accepts anywhere in 10..999 seconds.
 * A flat five minutes was wrong for any room above ~300s: a single absent
 * player's turn legitimately outlasts it, so the detector reported a healthy
 * room as frozen every five minutes. Seen in production on a mighty room whose
 * only human had left — three [FREEZE] warnings for a room that was in fact
 * advancing, just slowly. A detector that cries wolf is worse than none,
 * because the real freezes stop standing out.
 *
 * Several phases give double time (Tichu's large-tichu call and card exchange,
 * Skull King's bidding, Mighty's kitty exchange), so the allowance is two turn
 * limits plus a minute of slack for the round/trick display windows.
 *
 * Lives outside server.js so it can be unit-tested — same reason as
 * game/turnGuard.js and lobby/zombieSweep.js.
 */

const FREEZE_FLOOR_MS = 5 * 60 * 1000;
const FREEZE_SLACK_MS = 60 * 1000;
const DEFAULT_TURN_LIMIT_SEC = 30;

function freezeThresholdMs(turnTimeLimitSec) {
  const limit = Number.isFinite(turnTimeLimitSec) && turnTimeLimitSec > 0
    ? turnTimeLimitSec
    : DEFAULT_TURN_LIMIT_SEC;
  return Math.max(FREEZE_FLOOR_MS, limit * 2 * 1000 + FREEZE_SLACK_MS);
}

module.exports = { freezeThresholdMs, FREEZE_FLOOR_MS };
