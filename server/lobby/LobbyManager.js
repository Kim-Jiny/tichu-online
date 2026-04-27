const GameRoom = require('../game/GameRoom');
const { BotPlayer } = require('../game/BotPlayer');

let nextRoomId = 1;

class LobbyManager {
  constructor() {
    this.rooms = new Map();
  }

  createRoom(name, hostId, hostNickname, password = '', isRanked = false, turnTimeLimit = 30, targetScore = 1000, gameType = 'tichu', maxPlayers = 4, skExpansions = []) {
    const roomId = `room_${nextRoomId++}`;
    const room = new GameRoom(roomId, name, hostId, hostNickname, password, isRanked, turnTimeLimit, targetScore, gameType, maxPlayers, skExpansions);
    this.rooms.set(roomId, room);
    console.log(`Room created: ${name} (${roomId}) by ${hostNickname}`);
    return room;
  }

  getRoom(roomId) {
    return this.rooms.get(roomId) || null;
  }

  removeRoom(roomId) {
    this.rooms.delete(roomId);
    console.log(`Room removed: ${roomId}`);
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
    if (this.rooms.has(data.id)) return null;

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

    if (Array.isArray(data.players)) {
      for (const p of data.players) {
        if (!p || typeof p.slot !== 'number') continue;
        if (p.slot < 0 || p.slot >= room.maxPlayers) continue;
        if (p.isBot) {
          // Recreate a fresh bot — game-state learning is empty, but
          // migration only happens between rounds so it doesn't matter.
          const speed = ['fast', 'normal', 'slow'].includes(p.botSpeed) ? p.botSpeed : 'normal';
          const bot = new BotPlayer(p.id, p.nickname, speed);
          room.bots.set(p.id, bot);
          room.players[p.slot] = {
            id: p.id,
            nickname: p.nickname,
            connected: true,
            isBot: true,
            ready: true,
            botSpeed: speed,
          };
        } else {
          // Human player — placeholder; the real WS arrives on reconnect
          // and handleReconnection rebinds it to this slot via nickname.
          room.players[p.slot] = {
            id: p.id || null,
            nickname: p.nickname,
            connected: false,
            ready: !!p.ready,
            titleKey: p.titleKey || null,
            titleName: p.titleName || null,
          };
        }
      }
    }

    this.rooms.set(room.id, room);
    console.log(`[adoptRoom] adopted ${room.id} (${room.name}) from peer`);
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
