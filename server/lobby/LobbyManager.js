const GameRoom = require('../game/GameRoom');

let nextRoomId = 1;

class LobbyManager {
  constructor() {
    this.rooms = new Map();
  }

  createRoom(name, hostId, hostNickname) {
    const roomId = `room_${nextRoomId++}`;
    const room = new GameRoom(roomId, name, hostId, hostNickname);
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
      if (!room.game) {
        list.push({
          id: room.id,
          name: room.name,
          playerCount: room.getPlayerCount(),
          maxPlayers: 4,
          hostName: room.hostNickname,
        });
      }
    }
    return list;
  }
}

module.exports = LobbyManager;
