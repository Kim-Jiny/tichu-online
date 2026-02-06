const TichuGame = require('./TichuGame');

class GameRoom {
  constructor(id, name, hostId, hostNickname, password = '', isRanked = false) {
    this.id = id;
    this.name = name;
    this.hostId = hostId;
    this.hostNickname = hostNickname;
    this.password = password;
    this.isPrivate = !!password;
    this.isRanked = !!isRanked;
    this.players = [{ id: hostId, nickname: hostNickname }];
    this.spectators = []; // { id, nickname }
    this.game = null;
    // Spectator card view permissions: { spectatorId: Set of playerId }
    this.spectatorPermissions = {};
    // Pending requests: { playerId: [{ spectatorId, spectatorNickname }] }
    this.pendingCardRequests = {};
    // Teams: players[0] & players[2] = Team A, players[1] & players[3] = Team B
  }

  addPlayer(playerId, nickname, password = '') {
    if (this.isPrivate && this.password !== password) {
      return { success: false, message: 'Room password is incorrect' };
    }
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
    if (idx === -1) {
      // Maybe a spectator
      this.removeSpectator(playerId);
      return;
    }
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

  addSpectator(odId, nickname) {
    if (this.spectators.find((s) => s.id === odId)) {
      return { success: false, message: 'Already spectating' };
    }
    this.spectators.push({ id: odId, nickname });
    console.log(`${nickname} is now spectating room ${this.name}`);
    return { success: true };
  }

  removeSpectator(odId) {
    const idx = this.spectators.findIndex((s) => s.id === odId);
    if (idx !== -1) {
      const removed = this.spectators.splice(idx, 1)[0];
      console.log(`${removed.nickname} stopped spectating room ${this.name}`);
      this.removeSpectatorPermissions(odId);
    }
  }

  getSpectatorIds() {
    return this.spectators.map((s) => s.id);
  }

  // Request to view a player's cards
  requestCardView(spectatorId, spectatorNickname, playerId) {
    if (!this.spectators.find(s => s.id === spectatorId)) {
      return { success: false, message: 'Not a spectator' };
    }
    if (!this.players.find(p => p.id === playerId)) {
      return { success: false, message: 'Player not found' };
    }
    // Check if already has permission
    if (this.spectatorPermissions[spectatorId]?.has(playerId)) {
      return { success: false, message: 'Already have permission' };
    }
    // Check if already requested
    if (!this.pendingCardRequests[playerId]) {
      this.pendingCardRequests[playerId] = [];
    }
    if (this.pendingCardRequests[playerId].find(r => r.spectatorId === spectatorId)) {
      return { success: false, message: 'Already requested' };
    }
    this.pendingCardRequests[playerId].push({ spectatorId, spectatorNickname });
    return { success: true };
  }

  // Player responds to card view request
  respondCardViewRequest(playerId, spectatorId, allow) {
    if (!this.pendingCardRequests[playerId]) {
      return { success: false, message: 'No pending request' };
    }
    const reqIdx = this.pendingCardRequests[playerId].findIndex(r => r.spectatorId === spectatorId);
    if (reqIdx === -1) {
      return { success: false, message: 'Request not found' };
    }
    // Remove from pending
    this.pendingCardRequests[playerId].splice(reqIdx, 1);

    if (allow) {
      // Grant permission
      if (!this.spectatorPermissions[spectatorId]) {
        this.spectatorPermissions[spectatorId] = new Set();
      }
      this.spectatorPermissions[spectatorId].add(playerId);
    }
    return { success: true, allowed: allow };
  }

  // Get permitted player IDs for a spectator
  getPermittedPlayers(spectatorId) {
    return this.spectatorPermissions[spectatorId] || new Set();
  }

  // Get pending requests for a player
  getPendingRequests(playerId) {
    return this.pendingCardRequests[playerId] || [];
  }

  // Clean up when spectator leaves
  removeSpectatorPermissions(spectatorId) {
    delete this.spectatorPermissions[spectatorId];
    // Remove from all pending requests
    for (const playerId in this.pendingCardRequests) {
      this.pendingCardRequests[playerId] = this.pendingCardRequests[playerId].filter(
        r => r.spectatorId !== spectatorId
      );
    }
  }

  getPlayerCount() {
    return this.players.length;
  }

  startGame() {
    if (this.players.length !== 4) return false;
    const playerIds = this.players.map((p) => p.id);
    if (this.isRanked) {
      // Shuffle seating order for ranked rooms
      for (let i = playerIds.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [playerIds[i], playerIds[j]] = [playerIds[j], playerIds[i]];
      }
    }
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
      isPrivate: this.isPrivate,
      isRanked: this.isRanked,
      hostId: this.hostId,
      players: this.players.map((p) => ({
        id: p.id,
        name: p.nickname,
        isHost: p.id === this.hostId,
      })),
      gameInProgress: !!this.game,
    };
  }
}

module.exports = GameRoom;
