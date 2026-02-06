const GameRoom = require('../game/GameRoom');

let nextRoomId = 1;

class LobbyManager {
  constructor() {
    this.rooms = new Map();
  }

  createRoom(name, hostId, hostNickname, password = '', isRanked = false) {
    const roomId = `room_${nextRoomId++}`;
    const room = new GameRoom(roomId, name, hostId, hostNickname, password, isRanked);
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
        maxPlayers: 4,
        hostName: room.hostNickname,
        isPrivate: room.isPrivate,
        isRanked: room.isRanked,
        gameInProgress: !!room.game,
        spectatorCount: room.game ? room.spectators.length : 0,
      });
    }
    return list;
  }

  getSpectatableRooms() {
    const list = [];
    for (const [id, room] of this.rooms) {
      if (room.game) {
        list.push({
          id: room.id,
          name: room.name,
          playerCount: room.getPlayerCount(),
          spectatorCount: room.spectators.length,
          hostName: room.hostNickname,
          isRanked: room.isRanked,
          gameInProgress: true,
        });
      }
    }
    return list;
  }
}

module.exports = LobbyManager;
