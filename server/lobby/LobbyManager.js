const GameRoom = require('../game/GameRoom');
const { BotPlayer } = require('../game/BotPlayer');

// Room ids must be unique across INSTANCES, not just within one process.
// A deploy points nginx at the incoming slot before draining the outgoing one
// (see server/deploy/deploy.sh), so for the whole drain window — up to
// stop_grace_period — both are live and handing out ids. With a bare
// per-process counter they both start at room_1, and every colliding id makes
// the peer refuse the migration as a duplicate, killing the match it carried.
// A per-boot token keeps them disjoint; it also survives blue→green→blue
// redeploys, where a plain INSTANCE_NAME prefix would repeat.
const BOOT_TOKEN = require('crypto').randomBytes(3).toString('hex');
// Ids for seats arriving from a peer. Player ids are minted per process
// (`player_7`, `bot_3`) starting from 1, so a migrated room's ids collide
// head-on with ids this process has already handed to unrelated people —
// and with ids a previous boot of this same process handed out, if the room
// migrates back. Observed: an adopted seat kept the peer's `player_1` while a
// local client also held `player_1`; the reconnect wrote one seat's id over
// the other's, leaving a nameless seat and a player with an empty hand. This
// boot's token cannot be produced by any other process or boot.
let nextAdoptedId = 1;
let nextRoomId = 1;

class LobbyManager {
  constructor() {
    this.rooms = new Map();
  }

  createRoom(name, hostId, hostNickname, password = '', isRanked = false, turnTimeLimit = 30, targetScore = 1000, gameType = 'tichu', maxPlayers = 4, skExpansions = [], allowSpectators = true, allowMidGameJoin = false) {
    const roomId = `room_${BOOT_TOKEN}_${nextRoomId++}`;
    const room = new GameRoom(roomId, name, hostId, hostNickname, password, isRanked, turnTimeLimit, targetScore, gameType, maxPlayers, skExpansions, allowSpectators, allowMidGameJoin);
    this.rooms.set(roomId, room);
    console.log(`Room created: ${name} (${roomId}) by ${hostNickname}`);
    return room;
  }

  getRoom(roomId) {
    return this.rooms.get(roomId) || null;
  }

  removeRoom(roomId) {
    if (!this.rooms.has(roomId)) return false;
    this.rooms.delete(roomId);
    console.log(`Room removed: ${roomId}`);
    return true;
  }

  getRoomList() {
    const list = [];
    for (const [id, room] of this.rooms) {
      list.push({
        id: room.id,
        name: room.name,
        playerCount: room.getPlayerCount(),
        maxPlayers: room.maxPlayers,
        effectiveMaxPlayers: room.getEffectiveMaxPlayers ? room.getEffectiveMaxPlayers() : room.maxPlayers,
        gameType: room.gameType,
        hostName: room.hostNickname,
        isPrivate: room.isPrivate,
        isRanked: room.isRanked,
        allowSpectators: room.allowSpectators !== false,
        // The lobby needs this to badge rooms a spectator can still break into.
        allowMidGameJoin: room.allowMidGameJoin === true,
        // A mid-game-join room is only actually enterable while a bot holds a
        // seat, so surface the count rather than making the client infer it
        // from a player list the lobby view doesn't carry.
        botSeatCount: room.getBotSeatCount(),
        gameInProgress: !!room.game,
        spectatorCount: room.spectators.length,
        turnTimeLimit: room.turnTimeLimit,
        targetScore: room.targetScore,
        skExpansions: [...(room.skExpansions || [])],
        randomSeating: !!room.randomSeating,
      });
    }
    return list;
  }

  // Reconstruct a room migrated from a peer instance during a blue/green
  // drain. Reuses the original roomId so existing share/invite links and
  // playerSessions reconnect-pointers stay valid. Bots are recreated as
  // fresh BotPlayer instances; humans are placed in their slots with
  // connected=false until they reconnect (handleReconnection will flip
  // them back to connected on login). Refuses to overwrite an existing
  // room — the caller (peer) should validate before sending.
  adoptRoom(data) {
    if (!data || !data.id) return null;

    const existing = this.rooms.get(data.id);
    if (existing) {
      // A retry after a response the sender never saw. Ids carry a per-boot
      // token so this should only ever be the same room arriving twice, but
      // require the origin stamp to match before saying yes — reporting a
      // stranger's room as adopted would make the sender delete the only
      // copy of it.
      const sameOrigin = !!existing.migrationOrigin
        && existing.migrationOrigin === data.migrationOrigin;

      // Identical re-send: the answer we sent was lost. Say yes again.
      if (sameOrigin
          && existing.migrationFingerprint
          && existing.migrationFingerprint === data.migrationFingerprint) {
        console.log(`[adoptRoom] ${data.id} already adopted from ${data.migrationOrigin} — treating as success`);
        return existing;
      }

      // Same room, newer content: the sender kept mutating it after the
      // attempt we took. Confirming our stale copy would make it delete the
      // newer one, but simply refusing strands the room on a dying instance
      // until SIGKILL. Take the newer snapshot instead — safe precisely while
      // nobody has arrived here yet, which is the case for as long as the
      // sender still holds the sockets (i.e. the whole lost-response window).
      const occupied = existing.game
        || existing.players.some((p) => p !== null && !p.isBot && p.connected);
      if (sameOrigin && !occupied) {
        console.warn(`[adoptRoom] ${data.id} re-sent from ${data.migrationOrigin} with newer content — replacing our unoccupied copy`);
        this.rooms.delete(data.id);
      } else {
        if (sameOrigin) {
          console.warn(`[adoptRoom] ${data.id} re-sent from ${data.migrationOrigin} with different content but players are already here — refusing`);
        }
        return null;
      }
    }

    const room = new GameRoom(
      data.id,
      data.name || 'Migrated Room',
      data.hostId || null,
      data.hostNickname || null,
      data.password || '',
      !!data.isRanked,
      data.turnTimeLimit ?? 30,
      data.targetScore ?? 1000,
      data.gameType || 'tichu',
      data.maxPlayers || 4,
      Array.isArray(data.skExpansions) ? data.skExpansions : [],
    );

    // Constructor seeds slot 0 with the host. Wipe + repopulate from the
    // serialized slot list so we honour the original layout exactly.
    room.players = Array.from({ length: room.maxPlayers }, () => null);
    room.bots = new Map();
    room.blockedSlots = new Set(Array.isArray(data.blockedSlots) ? data.blockedSlots : []);
    room.autoBlockedSlots = new Set(Array.isArray(data.autoBlockedSlots) ? data.autoBlockedSlots : []);
    room.randomSeating = !!data.randomSeating;
    // Assigned after construction: the constructor gates this on isRanked and
    // allowSpectators, and the adopt path passes neither in a form it can see.
    room.allowMidGameJoin = !data.isRanked && !!data.allowMidGameJoin;
    // Mid-match migration: the peer was at a round boundary and handed us
    // the cumulative score + seating. startGame consumes this to resume
    // the match rather than start a new one.
    room.matchProgress = data.matchProgress || null;
    // Identifies the room this was migrated from, so a retried adopt can be
    // recognised as idempotent rather than a collision.
    room.migrationOrigin = data.migrationOrigin || null;
    room.migrationFingerprint = data.migrationFingerprint || null;

    // Old id -> the one this instance will use, so hostId follows the seats.
    // Nothing else needs translating: matchProgress is nickname-keyed, and
    // spectators arrive with their own live ids on reconnect.
    const idMap = new Map();
    const mintId = (oldId, isBot) => {
      const fresh = `${isBot ? 'bot' : 'player'}_${BOOT_TOKEN}_${nextAdoptedId++}`;
      if (oldId) idMap.set(oldId, fresh);
      return fresh;
    };

    if (Array.isArray(data.players)) {
      for (const p of data.players) {
        if (!p || typeof p.slot !== 'number') continue;
        if (p.slot < 0 || p.slot >= room.maxPlayers) continue;
        const freshId = mintId(p.id, !!p.isBot);
        if (p.isBot) {
          // Recreate a fresh bot — game-state learning is empty, but
          // migration only happens between rounds so it doesn't matter.
          const speed = ['fast', 'normal', 'slow'].includes(p.botSpeed) ? p.botSpeed : 'normal';
          // BotPlayer normalises strategy itself; pass through and let it
          // fall back to 'heuristic' on garbage input.
          const bot = new BotPlayer(freshId, p.nickname, speed, p.botStrategy);
          room.bots.set(freshId, bot);
          room.players[p.slot] = {
            id: freshId,
            nickname: p.nickname,
            connected: true,
            isBot: true,
            ready: true,
            botSpeed: speed,
          };
        } else {
          // Human player — placeholder; the real WS arrives on reconnect
          // and handleReconnection rebinds it to this slot via nickname.
          // Carry over the lobby-rendering fields (level/banner/seasonRating)
          // so peer adoption doesn't blank out the slot until the user
          // re-joins from scratch.
          room.players[p.slot] = {
            id: freshId,
            nickname: p.nickname,
            connected: false,
            ready: !!p.ready,
            titleKey: p.titleKey || null,
            titleName: p.titleName || null,
            level: typeof p.level === 'number' ? p.level : null,
            bannerKey: p.bannerKey || null,
            photoUrl: p.photoUrl || null,
            seasonRating: typeof p.seasonRating === 'number' ? p.seasonRating : null,
            skSeasonRating: typeof p.skSeasonRating === 'number' ? p.skSeasonRating : null,
            mightySeasonRating: typeof p.mightySeasonRating === 'number' ? p.mightySeasonRating : null,
          };
        }
      }
    }

    if (room.hostId && idMap.has(room.hostId)) room.hostId = idMap.get(room.hostId);

    this.rooms.set(room.id, room);
    console.log(
      `[adoptRoom] adopted ${room.id} (${room.name}) from peer`
      + (room.matchProgress ? ` — resuming ${room.gameType} match at round ${room.matchProgress.round}` : ''),
    );
    return room;
  }

  getSpectatableRooms() {
    const list = [];
    for (const [id, room] of this.rooms) {
      if (room.game && room.getHumanPlayerCount() >= 2) {
        list.push({
          id: room.id,
          name: room.name,
          playerCount: room.getPlayerCount(),
          maxPlayers: room.maxPlayers,
          spectatorCount: room.spectators.length,
          hostName: room.hostNickname,
          isRanked: room.isRanked,
          gameType: room.gameType,
          gameInProgress: true,
          skExpansions: [...(room.skExpansions || [])],
        });
      }
    }
    return list;
  }
}

module.exports = LobbyManager;
