const TichuGame = require('./TichuGame');

class GameRoom {
  constructor(id, name, hostId, hostNickname) {
    this.id = id;
    this.name = name;
    this.hostId = hostId;
    this.hostNickname = hostNickname;
    this.players = [{ id: hostId, nickname: hostNickname }];
    this.game = null;
    // Teams: players[0] & players[2] = Team A, players[1] & players[3] = Team B
  }

  addPlayer(playerId, nickname) {
    if (this.players.length >= 4) {
      return { success: false, message: 'Room is full' };
    }
    if (this.game) {
      return { success: false, message: 'Game already in progress' };
    }
    if (this.players.find((p) => p.id === playerId)) {
      return { success: false, message: 'Already in this room' };
    }
    this.players.push({ id: playerId, nickname: nickname });
    console.log(`${nickname} joined room ${this.name}`);
    return { success: true };
  }

  removePlayer(playerId) {
    const idx = this.players.findIndex((p) => p.id === playerId);
    if (idx === -1) return;
    const removed = this.players.splice(idx, 1)[0];
    console.log(`${removed.nickname} left room ${this.name}`);
    // If host left, assign new host
    if (this.hostId === playerId && this.players.length > 0) {
      this.hostId = this.players[0].id;
      this.hostNickname = this.players[0].nickname;
    }
    // If game was running and not enough players, end game
    if (this.game && this.players.length < 4) {
      this.game = null;
    }
  }

  getPlayerCount() {
    return this.players.length;
  }

  startGame() {
    if (this.players.length !== 4) return false;
    const playerIds = this.players.map((p) => p.id);
    const playerNames = {};
    this.players.forEach((p) => (playerNames[p.id] = p.nickname));
    this.game = new TichuGame(playerIds, playerNames);
    this.game.start();
    console.log(`Game started in room ${this.name}`);
    return true;
  }

  getState() {
    return {
      id: this.id,
      name: this.name,
      hostId: this.hostId,
      players: this.players.map((p) => ({
        id: p.id,
        nickname: p.nickname,
        isHost: p.id === this.hostId,
      })),
      gameInProgress: !!this.game,
    };
  }
}

module.exports = GameRoom;
