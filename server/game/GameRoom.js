const TichuGame = require('./TichuGame');
const { BotPlayer } = require('./BotPlayer');

let nextBotNum = 1;

const TITLE_NAMES = {
  'title_sweet': '달콤한 플레이어',
  'title_steady': '꾸준한 승부사',
  'title_flash_30d': '스피드 러너',
};

class GameRoom {
  constructor(id, name, hostId, hostNickname, password = '', isRanked = false, turnTimeLimit = 30) {
    this.id = id;
    this.name = name;
    this.hostId = hostId;
    this.hostNickname = hostNickname;
    this.password = password;
    this.isPrivate = !!password;
    this.isRanked = !!isRanked;
    this.turnTimeLimit = turnTimeLimit; // seconds
    this.turnDeadline = null; // epoch ms when active
    // Fixed 4-slot system: host goes to slot 0, rest are null
    this.players = [
      { id: hostId, nickname: hostNickname, connected: true, ready: false },
      null,
      null,
      null,
    ];
    this.spectators = []; // { id, nickname }
    this.game = null;
    // Bot tracking
    this.bots = new Map(); // botId -> BotPlayer
    // Spectator card view permissions: { spectatorId: Set of playerId }
    this.spectatorPermissions = {};
    // Pending requests: { playerId: [{ spectatorId, spectatorNickname }] }
    this.pendingCardRequests = {};
    // Teams: players[0] & players[2] = Team A, players[1] & players[3] = Team B
    // Chat history (최근 100개)
    this.chatHistory = [];
  }

  addChatMessage(sender, senderId, message) {
    const msg = {
      sender,
      senderId,
      message,
      timestamp: Date.now(),
    };
    this.chatHistory.push(msg);
    // 최근 100개만 유지
    if (this.chatHistory.length > 100) {
      this.chatHistory.shift();
    }
    return msg;
  }

  getChatHistory() {
    return this.chatHistory;
  }

  addPlayer(playerId, nickname, password = '') {
    if (this.isPrivate && this.password !== password) {
      return { success: false, message: 'Room password is incorrect' };
    }
    if (this.getPlayerCount() >= 4) {
      return { success: false, message: 'Room is full' };
    }
    if (this.game) {
      return { success: false, message: 'Game already in progress' };
    }
    if (this.players.some((p) => p !== null && p.id === playerId)) {
      return { success: false, message: 'Already in this room' };
    }
    // Find first null slot
    const emptySlot = this.players.indexOf(null);
    if (emptySlot === -1) {
      return { success: false, message: 'Room is full' };
    }
    this.players[emptySlot] = { id: playerId, nickname: nickname, connected: true, ready: false };
    console.log(`${nickname} joined room ${this.name} (slot ${emptySlot})`);
    return { success: true };
  }

  removePlayer(playerId) {
    const idx = this.players.findIndex((p) => p !== null && p.id === playerId);
    if (idx === -1) {
      // Maybe a spectator
      this.removeSpectator(playerId);
      return;
    }
    const removed = this.players[idx];
    this.players[idx] = null; // Set slot to null instead of splice
    this.bots.delete(playerId); // Clean up bot tracking if applicable
    console.log(`${removed.nickname} left room ${this.name}`);
    // If host left, assign new host (first non-null human player, skip bots)
    if (this.hostId === playerId) {
      const nextHost = this.players.find((p) => p !== null && !p.isBot);
      if (nextHost) {
        this.hostId = nextHost.id;
        this.hostNickname = nextHost.nickname;
      }
    }
    // If game was running and not enough players, end game
    // But preserve game if already ended (so remaining players can see results)
    if (this.game && this.getPlayerCount() < 4 && this.game.state !== 'game_end') {
      this.game = null;
    }
  }

  // Mark player as disconnected (during game, don't remove)
  markPlayerDisconnected(playerId) {
    const player = this.players.find((p) => p !== null && p.id === playerId);
    if (player) {
      player.connected = false;
      console.log(`${player.nickname} disconnected in room ${this.name}`);
      return true;
    }
    return false;
  }

  // Reconnect player with new playerId
  reconnectPlayer(nickname, newPlayerId) {
    const player = this.players.find((p) => p !== null && p.nickname === nickname && !p.connected);
    if (player) {
      const oldPlayerId = player.id;
      player.id = newPlayerId;
      player.connected = true;
      // Update game's player ID if game is running
      if (this.game) {
        this.game.updatePlayerId(oldPlayerId, newPlayerId);
      }
      // Update host if needed
      if (this.hostId === oldPlayerId) {
        this.hostId = newPlayerId;
      }
      console.log(`${nickname} reconnected in room ${this.name}`);
      return { success: true, oldPlayerId };
    }
    return { success: false };
  }

  // Get disconnected player nicknames
  getDisconnectedPlayers() {
    return this.players.filter(p => p !== null && !p.connected).map(p => p.nickname);
  }

  // Check if a nickname can reconnect to this room
  canReconnect(nickname) {
    return this.players.some(p => p !== null && p.nickname === nickname && !p.connected);
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

  getPlayerIds() {
    return this.players.filter((p) => p !== null).map((p) => p.id);
  }

  // Request to view a player's cards
  requestCardView(spectatorId, spectatorNickname, playerId) {
    if (!this.spectators.find(s => s.id === spectatorId)) {
      return { success: false, message: 'Not a spectator' };
    }
    if (!this.players.some(p => p !== null && p.id === playerId)) {
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

  // Get list of spectators currently viewing a player's cards
  getViewersForPlayer(playerId) {
    const viewers = [];
    for (const [spectatorId, permittedSet] of Object.entries(this.spectatorPermissions)) {
      if (permittedSet.has(playerId)) {
        const spec = this.spectators.find(s => s.id === spectatorId);
        if (spec) {
          viewers.push({ id: spectatorId, nickname: spec.nickname });
        }
      }
    }
    return viewers;
  }

  // Revoke a spectator's permission to view a player's cards
  revokeCardView(playerId, spectatorId) {
    if (!this.spectatorPermissions[spectatorId]) return { success: false };
    this.spectatorPermissions[spectatorId].delete(playerId);
    return { success: true };
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

  // --- Bot management ---

  addBot(targetSlot) {
    if (this.getPlayerCount() >= 4) {
      return { success: false, message: '방이 가득 찼습니다' };
    }
    if (this.game) {
      return { success: false, message: '게임 중에는 봇을 추가할 수 없습니다' };
    }
    let slot;
    if (typeof targetSlot === 'number' && targetSlot >= 0 && targetSlot <= 3) {
      if (this.players[targetSlot] !== null) {
        return { success: false, message: '이미 다른 플레이어가 있는 자리입니다' };
      }
      slot = targetSlot;
    } else {
      slot = this.players.indexOf(null);
    }
    if (slot === -1) {
      return { success: false, message: '빈 자리가 없습니다' };
    }
    const botId = `bot_${nextBotNum++}`;
    const botNickname = `봇 ${this.bots.size + 1}`;
    const bot = new BotPlayer(botId, botNickname);
    this.bots.set(botId, bot);
    this.players[slot] = { id: botId, nickname: botNickname, connected: true, isBot: true, ready: true };
    console.log(`Bot ${botNickname} added to room ${this.name} (slot ${slot})`);
    return { success: true, botId };
  }

  removeBots() {
    for (const [botId] of this.bots) {
      const idx = this.players.findIndex(p => p !== null && p.id === botId);
      if (idx !== -1) {
        this.players[idx] = null;
      }
    }
    this.bots.clear();
  }

  isBot(playerId) {
    return this.bots.has(playerId);
  }

  getBotIds() {
    return [...this.bots.keys()];
  }

  getPlayerCount() {
    return this.players.filter((p) => p !== null).length;
  }

  getHumanPlayerCount() {
    return this.players.filter((p) => p !== null && !p.isBot).length;
  }

  // Switch a player to spectator mode
  switchToSpectator(playerId) {
    if (this.game) {
      return { success: false, message: '게임 중에는 전환할 수 없습니다' };
    }
    const idx = this.players.findIndex(p => p !== null && p.id === playerId);
    if (idx === -1) {
      return { success: false, message: '플레이어를 찾을 수 없습니다' };
    }
    const player = this.players[idx];
    const nickname = player.nickname;

    // Remove from player slot
    this.players[idx] = null;

    // Add to spectators
    this.spectators.push({ id: playerId, nickname });

    // If host left, assign new host
    if (this.hostId === playerId) {
      const nextHost = this.players.find(p => p !== null && !p.isBot);
      if (nextHost) {
        this.hostId = nextHost.id;
        this.hostNickname = nextHost.nickname;
      }
    }

    console.log(`${nickname} switched to spectator in room ${this.name}`);
    return { success: true };
  }

  // Switch a spectator to player mode
  switchToPlayer(spectatorId, nickname, targetSlot) {
    if (this.game) {
      return { success: false, message: '게임 중에는 전환할 수 없습니다' };
    }
    if (this.getPlayerCount() >= 4) {
      return { success: false, message: '방이 가득 찼습니다' };
    }
    const specIdx = this.spectators.findIndex(s => s.id === spectatorId);
    if (specIdx === -1) {
      return { success: false, message: '관전자를 찾을 수 없습니다' };
    }
    if (typeof targetSlot !== 'number' || targetSlot < 0 || targetSlot > 3) {
      return { success: false, message: '잘못된 슬롯입니다' };
    }
    if (this.players[targetSlot] !== null) {
      return { success: false, message: '이미 다른 플레이어가 있는 자리입니다' };
    }

    // Remove from spectators
    this.spectators.splice(specIdx, 1);
    this.removeSpectatorPermissions(spectatorId);

    // Add to player slot
    this.players[targetSlot] = { id: spectatorId, nickname, connected: true, ready: false };

    // If no host (empty room edge case), assign this player
    if (!this.players.some(p => p !== null && p.id === this.hostId)) {
      this.hostId = spectatorId;
      this.hostNickname = nickname;
    }

    console.log(`${nickname} switched to player in room ${this.name} (slot ${targetSlot})`);
    return { success: true };
  }

  // Move a player to a specific slot (only if target slot is empty)
  movePlayerToSlot(playerId, targetSlot) {
    const currentIndex = this.players.findIndex((p) => p !== null && p.id === playerId);
    if (currentIndex === -1) {
      return { success: false, message: '플레이어를 찾을 수 없습니다' };
    }
    if (currentIndex === targetSlot) {
      return { success: true }; // Already in this slot
    }
    if (targetSlot < 0 || targetSlot > 3) {
      return { success: false, message: '잘못된 슬롯입니다' };
    }
    // Only allow move to empty (null) slot - no swapping
    if (this.players[targetSlot] !== null) {
      return { success: false, message: '이미 다른 플레이어가 있는 자리입니다' };
    }
    // Move player to target slot
    this.players[targetSlot] = this.players[currentIndex];
    this.players[currentIndex] = null;
    console.log(`Player ${playerId} moved to slot ${targetSlot}`);
    return { success: true };
  }

  startGame() {
    // All 4 slots must be non-null
    if (this.players.some((p) => p === null)) return false;
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

  toggleReady(playerId) {
    const player = this.players.find(p => p !== null && p.id === playerId);
    if (!player) return false;
    player.ready = !player.ready;
    return true;
  }

  areAllReady() {
    // All non-null human players (except host) must be ready. Bots are always ready.
    for (const p of this.players) {
      if (p === null) return false; // need 4 players
      if (p.isBot) continue;
      if (p.id === this.hostId) continue; // host doesn't need to ready
      if (!p.ready) return false;
    }
    return true;
  }

  resetReady() {
    for (const p of this.players) {
      if (p !== null) p.ready = false;
    }
  }

  getState() {
    return {
      id: this.id,
      name: this.name,
      isPrivate: this.isPrivate,
      isRanked: this.isRanked,
      hostId: this.hostId,
      spectators: this.spectators.map((s) => ({
        id: s.id,
        nickname: s.nickname,
      })),
      spectatorCount: this.spectators.length,
      // Send all 4 slots including nulls
      players: this.players.map((p) => {
        if (p === null) return null;
        return {
          id: p.id,
          name: p.nickname,
          isHost: p.id === this.hostId,
          connected: p.connected !== false,
          isBot: !!p.isBot,
          isReady: !!p.isBot || !!p.ready,
          titleKey: p.titleKey || null,
          titleName: TITLE_NAMES[p.titleKey] || null,
        };
      }),
      gameInProgress: !!this.game,
      turnTimeLimit: this.turnTimeLimit,
    };
  }
}

module.exports = GameRoom;
