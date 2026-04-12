const GameRoom = require('../game/GameRoom');

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
        gameType: room.gameType,
        hostName: room.hostNickname,
        isPrivate: room.isPrivate,
        isRanked: room.isRanked,
        gameInProgress: !!room.game,
        spectatorCount: room.spectators.length,
        turnTimeLimit: room.turnTimeLimit,
        targetScore: room.targetScore,
        skExpansions: [...(room.skExpansions || [])],
      });
    }
    return list;
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
