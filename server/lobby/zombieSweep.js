'use strict';

/**
 * Pure decision step for the zombie-room sweep.
 *
 * Lives outside server.js (which boots the whole server on require, so it
 * can't be unit-tested) precisely so this logic CAN be tested — same reason
 * as game/botWatchdog.js. It performs no I/O: it inspects the rooms plus the
 * playerSessions map and returns which rooms the caller should close.
 *
 * A room is abandoned when every human seat is disconnected AND that player's
 * reconnect session has expired — i.e. nobody is coming back to it.
 *
 * Rooms with a game in progress are deliberately INCLUDED. They used to be
 * skipped, which left them with no exit at all: the in-game disconnect path
 * only flags `connected=false` (no removal timer, unlike the waiting-room
 * path), so such a room could only ever be freed by its own game reaching
 * game_end. A game that stops advancing — a lost round/trick timer parks it
 * in a state where neither a turn timer nor the stuck-bot watchdog applies —
 * therefore leaked the room and its bots forever. Observed in production: a
 * mighty room survived 42 minutes with zero clients until an admin killed it.
 *
 * @returns {Array<{id, reason, stuckIn}>} rooms to close. `stuckIn` is
 *          `gameType/state` when the room was still mid-game (evidence of a
 *          freeze), otherwise null.
 */
function findAbandonedRooms({ rooms, playerSessions, now, maxAge }) {
  const abandoned = [];
  for (const [id, room] of rooms) {
    if (!room || !Array.isArray(room.players)) continue;

    const humans = room.players.filter((p) => p !== null && !p.isBot);
    if (humans.length === 0) {
      // No human seats at all (shouldn't happen, but clean up).
      abandoned.push({ id, reason: 'no humans', stuckIn: null });
      continue;
    }

    const allGoneLongEnough = humans.every((p) => {
      if (p.connected) return false;
      const session = playerSessions.get(p.nickname);
      return !session || (now - session.disconnectedAt > maxAge);
    });
    if (!allGoneLongEnough) continue;

    abandoned.push({
      id,
      reason: 'all humans disconnected 30min+',
      stuckIn: room.game ? `${room.gameType}/${room.game.state}` : null,
    });
  }
  return abandoned;
}

module.exports = { findAbandonedRooms };
