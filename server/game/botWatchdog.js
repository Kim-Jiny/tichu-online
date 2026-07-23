'use strict';

/**
 * Pure decision step for the stuck-bot watchdog.
 *
 * Lives outside server.js (which boots the whole server on require, so it can't
 * be unit-tested) precisely so this logic CAN be tested. It performs no I/O: it
 * inspects the rooms + the live pendingBotTimers map, updates the per-room
 * "seen stranded" counter, and returns the rooms that have been stranded long
 * enough to force-reschedule. The caller (server.js) does the actual
 * scheduleBotActions() + logging.
 *
 * A room is "stranded" when a bot is the pending actor but no bot timer is
 * queued for it — i.e. nothing will ever move that bot. We require it to persist
 * `threshold` consecutive ticks so a sub-second scheduling gap is never mistaken
 * for a freeze.
 *
 * @returns {Array<{roomId, actor}>} rooms to recover (counter already reset).
 */
// Terminal / transitional states are NOT bot-actionable: round_end & game_end
// keep currentPlayer set (so getPendingActor would still name a bot), and
// trick_end/dealing/waiting are advanced by their own timers, not bot
// scheduling. Recovering in these states would spam force-reschedules during the
// round-end review screen for no benefit. Anything not listed here (playing,
// bidding, kitty_exchange, kill_select, *_phase, card_exchange, effect_resolve,
// or any future state) is treated as actionable, so the watchdog still fails
// safe toward recovering a real freeze.
const NON_ACTIONABLE_STATES = new Set([
  'round_end', 'game_end', 'trick_end', 'dealing', 'waiting',
]);

function botWatchdogTick({
  rooms,
  pendingBotTimers,
  seen,
  inFlight = {},
  effectAckTimers = {},
  threshold = 2,
}) {
  const toRecover = [];
  for (const [roomId, room] of rooms) {
    if (!room || !room.game || room.getBotIds().length === 0) {
      delete seen[roomId];
      continue;
    }
    if (NON_ACTIONABLE_STATES.has(room.game.state)) {
      delete seen[roomId];
      continue;
    }
    const actor = typeof room.game.getPendingActor === 'function'
      ? room.game.getPendingActor()
      : room.game.currentPlayer;
    const botPending = actor && room.isBot(actor);
    // Love Letter resolved effects are advanced by the presentation/auto-ack
    // timer, not by the normal bot decision timer. If that timer is alive, the
    // room is progressing normally and should not be force-rescheduled.
    if (botPending
        && room.gameType === 'love_letter'
        && room.game.state === 'effect_resolve'
        && room.game.pendingEffect
        && room.game.pendingEffect.resolved
        && effectAckTimers[roomId]) {
      delete seen[roomId];
      continue;
    }
    // A queued bot timer — or a decision currently awaiting the worker pool —
    // means the room is progressing normally, not stranded.
    if (!botPending || pendingBotTimers[roomId] || inFlight[roomId]) {
      delete seen[roomId];
      continue;
    }
    seen[roomId] = (seen[roomId] || 0) + 1;
    if (seen[roomId] >= threshold) {
      delete seen[roomId];
      toRecover.push({ roomId, actor });
    }
  }
  return toRecover;
}

module.exports = { botWatchdogTick, NON_ACTIONABLE_STATES };
