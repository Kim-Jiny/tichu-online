const TichuGame = require('./TichuGame');
const { BotPlayer } = require('./BotPlayer');
let SkullKingGame; // Lazy-loaded to avoid circular dependency
let LoveLetterGame; // Lazy-loaded

let nextBotNum = 1;


class GameRoom {
  constructor(id, name, hostId, hostNickname, password = '', isRanked = false, turnTimeLimit = 30, targetScore = 1000, gameType = 'tichu', maxPlayers = 4, skExpansions = []) {
    this.id = id;
    this.name = name;
    this.hostId = hostId;
    this.hostNickname = hostNickname;
    this.password = password;
    this.isPrivate = !!password;
    this.isRanked = !!isRanked;
    this.turnTimeLimit = turnTimeLimit; // seconds
    this.targetScore = targetScore;
    this.turnDeadline = null; // epoch ms when active
    this.gameType = gameType; // 'tichu', 'skull_king', or 'love_letter'
    this.maxPlayers = maxPlayers; // 4 for tichu, 2-6 for skull_king, 2-4 for love_letter
    // Enabled Skull King expansions (only meaningful when gameType === 'skull_king').
    // Subset of ['kraken', 'white_whale', 'loot'].
    this.skExpansions = Array.isArray(skExpansions) ? skExpansions.slice() : [];
    // Dynamic slot system: host goes to slot 0, rest are null
    this.players = Array.from({ length: this.maxPlayers }, (_, i) =>
      i === 0 ? { id: hostId, nickname: hostNickname, connected: true, ready: false } : null
    );
    // Slots blocked by host (host can block empty slots to effectively shrink the room).
    // Only meaningful for skull_king and love_letter. Tichu always requires full 4.
    this.blockedSlots = new Set();
    this.spectators = []; // { id, nickname }
    this.game = null;
    // Bot tracking
    this.bots = new Map(); // botId -> BotPlayer
    // Spectator card view permissions: { spectatorId: Set of playerId }
    this.spectatorPermissions = {};
    // Pending requests: { playerId: [{ spectatorId, spectatorNickname }] }
    this.pendingCardRequests = {};
    this.cardRequestTimers = {};
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
    if (this.getPlayerCount() >= this.getEffectiveMaxPlayers()) {
      return { success: false, message: 'Room is full' };
    }
    if (this.game) {
      return { success: false, message: 'Game already in progress' };
    }
    if (this.players.some((p) => p !== null && p.id === playerId)) {
      return { success: false, message: 'Already in this room' };
    }
    // Find first null, non-blocked slot
    let emptySlot = -1;
    for (let i = 0; i < this.players.length; i++) {
      if (this.players[i] === null && !this.blockedSlots.has(i)) {
        emptySlot = i;
        break;
      }
    }
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
    delete this.pendingCardRequests[playerId];
    for (const timerKey of Object.keys(this.cardRequestTimers)) {
      if (timerKey.startsWith(`${playerId}:`)) {
        clearTimeout(this.cardRequestTimers[timerKey]);
        delete this.cardRequestTimers[timerKey];
      }
    }
    console.log(`${removed.nickname} left room ${this.name}`);
    // If host left, assign new host (first non-null human player, skip bots)
    if (this.hostId === playerId) {
      const nextHost = this.players.find((p) => p !== null && !p.isBot);
      if (nextHost) {
        this.hostId = nextHost.id;
        this.hostNickname = nextHost.nickname;
      } else {
        // No human players left - pick any remaining player (including bots)
        const anyPlayer = this.players.find((p) => p !== null);
        if (anyPlayer) {
          this.hostId = anyPlayer.id;
          this.hostNickname = anyPlayer.nickname;
        }
      }
    }
    // If game was running and not enough players, end game
    // But preserve game if already ended (so remaining players can see results)
    const minPlayersForGame = (this.gameType === 'skull_king' || this.gameType === 'love_letter') ? 2 : this.maxPlayers;
    if (this.game && this.getPlayerCount() < minPlayersForGame && this.game.state !== 'game_end') {
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

  addSpectator(odId, nickname, password = '') {
    if (this.isPrivate && this.password !== password) {
      return { success: false, messageKey: 'room_wrong_password' };
    }
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
    for (const requests of Object.values(this.pendingCardRequests)) {
      if (requests.find(r => r.spectatorId === spectatorId)) {
        return { success: false, messageKey: 'room_waiting_other_response' };
      }
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
    if (this.pendingCardRequests[playerId].length === 0) {
      delete this.pendingCardRequests[playerId];
    }
    const timerKey = `${playerId}:${spectatorId}`;
    if (this.cardRequestTimers[timerKey]) {
      clearTimeout(this.cardRequestTimers[timerKey]);
      delete this.cardRequestTimers[timerKey];
    }

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

  expireCardViewRequest(playerId, spectatorId) {
    if (!this.pendingCardRequests[playerId]) return { success: false };
    const reqIdx = this.pendingCardRequests[playerId].findIndex(r => r.spectatorId === spectatorId);
    if (reqIdx === -1) return { success: false };
    this.pendingCardRequests[playerId].splice(reqIdx, 1);
    if (this.pendingCardRequests[playerId].length === 0) {
      delete this.pendingCardRequests[playerId];
    }
    const timerKey = `${playerId}:${spectatorId}`;
    if (this.cardRequestTimers[timerKey]) {
      clearTimeout(this.cardRequestTimers[timerKey]);
      delete this.cardRequestTimers[timerKey];
    }
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
      if (this.pendingCardRequests[playerId].length === 0) {
        delete this.pendingCardRequests[playerId];
      }
    }
    for (const timerKey of Object.keys(this.cardRequestTimers)) {
      if (timerKey.endsWith(`:${spectatorId}`)) {
        clearTimeout(this.cardRequestTimers[timerKey]);
        delete this.cardRequestTimers[timerKey];
      }
    }
  }

  // --- Bot management ---

  addBot(targetSlot, locale) {
    if (this.getPlayerCount() >= this.getEffectiveMaxPlayers()) {
      return { success: false, messageKey: 'room_full' };
    }
    if (this.game) {
      return { success: false, messageKey: 'room_no_bot_in_game' };
    }
    let slot;
    if (typeof targetSlot === 'number' && targetSlot >= 0 && targetSlot < this.maxPlayers) {
      if (this.players[targetSlot] !== null) {
        return { success: false, messageKey: 'room_slot_taken' };
      }
      if (this.blockedSlots.has(targetSlot)) {
        return { success: false, messageKey: 'room_slot_taken' };
      }
      slot = targetSlot;
    } else {
      // Find first null, non-blocked slot
      slot = -1;
      for (let i = 0; i < this.players.length; i++) {
        if (this.players[i] === null && !this.blockedSlots.has(i)) {
          slot = i;
          break;
        }
      }
    }
    if (slot === -1) {
      return { success: false, messageKey: 'room_no_empty_slot' };
    }
    const botId = `bot_${nextBotNum++}`;
    const { t } = require('../i18n');
    const botNickname = t(locale, 'bot_nickname', { number: this.bots.size + 1 });
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
      return { success: false, messageKey: 'room_no_switch_in_game' };
    }
    const idx = this.players.findIndex(p => p !== null && p.id === playerId);
    if (idx === -1) {
      return { success: false, messageKey: 'player_not_found' };
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
      } else {
        const anyPlayer = this.players.find(p => p !== null);
        if (anyPlayer) {
          this.hostId = anyPlayer.id;
          this.hostNickname = anyPlayer.nickname;
        }
      }
    }

    console.log(`${nickname} switched to spectator in room ${this.name}`);
    return { success: true };
  }

  // Switch a spectator to player mode
  switchToPlayer(spectatorId, nickname, targetSlot) {
    if (this.game) {
      return { success: false, messageKey: 'room_no_switch_in_game' };
    }
    if (this.getPlayerCount() >= this.getEffectiveMaxPlayers()) {
      return { success: false, messageKey: 'room_full' };
    }
    const specIdx = this.spectators.findIndex(s => s.id === spectatorId);
    if (specIdx === -1) {
      return { success: false, messageKey: 'room_spectator_not_found' };
    }
    if (typeof targetSlot !== 'number' || targetSlot < 0 || targetSlot >= this.maxPlayers) {
      return { success: false, messageKey: 'invalid_slot' };
    }
    if (this.players[targetSlot] !== null) {
      return { success: false, messageKey: 'room_slot_taken' };
    }
    if (this.blockedSlots.has(targetSlot)) {
      return { success: false, messageKey: 'room_slot_taken' };
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
      return { success: false, messageKey: 'player_not_found' };
    }
    if (currentIndex === targetSlot) {
      return { success: true }; // Already in this slot
    }
    if (targetSlot < 0 || targetSlot >= this.maxPlayers) {
      return { success: false, messageKey: 'invalid_slot' };
    }
    // Only allow move to empty (null) slot - no swapping
    if (this.players[targetSlot] !== null) {
      return { success: false, messageKey: 'room_slot_taken' };
    }
    if (this.blockedSlots.has(targetSlot)) {
      return { success: false, messageKey: 'room_slot_taken' };
    }
    // Move player to target slot
    this.players[targetSlot] = this.players[currentIndex];
    this.players[currentIndex] = null;
    console.log(`Player ${playerId} moved to slot ${targetSlot}`);
    return { success: true };
  }

  // Host blocks an empty slot so no one can join it (effectively shrinking the room)
  blockSlot(playerId, slotIndex) {
    if (playerId !== this.hostId) {
      return { success: false, messageKey: 'host_only' };
    }
    if (this.game) {
      return { success: false, messageKey: 'room_no_switch_in_game' };
    }
    if (this.gameType === 'tichu') {
      return { success: false, messageKey: 'invalid_slot' };
    }
    if (typeof slotIndex !== 'number' || slotIndex < 0 || slotIndex >= this.maxPlayers) {
      return { success: false, messageKey: 'invalid_slot' };
    }
    if (this.players[slotIndex] !== null) {
      return { success: false, messageKey: 'room_slot_taken' };
    }
    // Need at least 2 non-blocked slots left (minimum players for SK/LL)
    const remainingAfterBlock = this.maxPlayers - this.blockedSlots.size - 1;
    if (remainingAfterBlock < 2) {
      return { success: false, messageKey: 'room_full' };
    }
    this.blockedSlots.add(slotIndex);
    return { success: true };
  }

  unblockSlot(playerId, slotIndex) {
    if (playerId !== this.hostId) {
      return { success: false, messageKey: 'host_only' };
    }
    if (this.game) {
      return { success: false, messageKey: 'room_no_switch_in_game' };
    }
    if (typeof slotIndex !== 'number' || slotIndex < 0 || slotIndex >= this.maxPlayers) {
      return { success: false, messageKey: 'invalid_slot' };
    }
    this.blockedSlots.delete(slotIndex);
    return { success: true };
  }

  // Effective room capacity accounting for blocked slots
  getEffectiveMaxPlayers() {
    return this.maxPlayers - this.blockedSlots.size;
  }

  startGame() {
    // Restore pre-game slot structure if a previous game rearranged them
    // (e.g. game was abandoned via player removal without full resetReady)
    if (this._preGamePlayers) {
      const currentPlayerMap = new Map();
      for (const p of this.players) {
        if (p !== null) currentPlayerMap.set(p.id, p);
      }
      this.players = this._preGamePlayers.map(slot => {
        if (slot === null) return null;
        return currentPlayerMap.get(slot.id) || null;
      });
      this._preGamePlayers = null;
    }

    if (this.gameType === 'love_letter') {
      // Love Letter: all non-null players participate
      const activePlayers = this.players.filter(p => p !== null);
      if (activePlayers.length < 2) return false;
      this._preGamePlayers = this.players.slice();
      this.players = activePlayers;
    } else if (this.gameType === 'skull_king') {
      // SK allows fewer than maxPlayers - compact null slots
      const activePlayers = this.players.filter(p => p !== null);
      if (activePlayers.length < 2) return false;
      // Save original slot structure for restoration after game ends
      this._preGamePlayers = this.players.slice();
      this.players = activePlayers;
    } else {
      // Tichu: all slots must be non-null
      if (this.players.some((p) => p === null)) return false;
    }
    const playerIds = this.players.map((p) => p.id);
    if (this.gameType === 'skull_king' || this.gameType === 'love_letter' || this.isRanked) {
      // SK/LL or ranked: fully shuffle all seats
      for (let i = playerIds.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [playerIds[i], playerIds[j]] = [playerIds[j], playerIds[i]];
      }
    } else {
      // Tichu normal: keep teams (0,2 vs 1,3) but randomly swap which team sits where
      if (Math.random() < 0.5) {
        [playerIds[0], playerIds[1]] = [playerIds[1], playerIds[0]];
        [playerIds[2], playerIds[3]] = [playerIds[3], playerIds[2]];
      }
    }
    const playerNames = {};
    this.players.forEach((p) => (playerNames[p.id] = p.nickname));

    if (this.gameType === 'skull_king') {
      if (!SkullKingGame) {
        SkullKingGame = require('./skull_king/SkullKingGame');
      }
      this.game = new SkullKingGame(playerIds, playerNames, { expansions: this.skExpansions });
      this.game.start();
    } else if (this.gameType === 'love_letter') {
      if (!LoveLetterGame) {
        LoveLetterGame = require('./love_letter/LoveLetterGame');
      }
      this.game = new LoveLetterGame(playerIds, playerNames, {});
      this.game.start();
    } else {
      this.game = new TichuGame(playerIds, playerNames);
      this.game.targetScore = this.targetScore;
      this.game.start();
    }
    console.log(`${this.gameType} game started in room ${this.name}`);
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
      if (p === null) {
        if (this.gameType === 'skull_king' || this.gameType === 'love_letter') continue;
        return false; // tichu needs all slots filled
      }
      if (p.isBot) continue;
      if (p.id === this.hostId) continue; // host doesn't need to ready
      if (!p.ready) return false;
    }
    // SK/LL requires at least 2 players
    if ((this.gameType === 'skull_king' || this.gameType === 'love_letter') && this.getPlayerCount() < 2) return false;
    return true;
  }

  resetReady() {
    // Restore original slot structure for SK rooms after game ends
    if (this._preGamePlayers) {
      // Rebuild maxPlayers-sized array with current active players in their original slots
      const currentPlayerMap = new Map();
      for (const p of this.players) {
        if (p !== null) currentPlayerMap.set(p.id, p);
      }
      this.players = this._preGamePlayers.map(slot => {
        if (slot === null) return null;
        // Use current reference if player is still present, otherwise null (they left)
        return currentPlayerMap.get(slot.id) || null;
      });
      this._preGamePlayers = null;
    }
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
      gameType: this.gameType,
      maxPlayers: this.maxPlayers,
      hostId: this.hostId,
      spectators: this.spectators.map((s) => ({
        id: s.id,
        nickname: s.nickname,
      })),
      spectatorCount: this.spectators.length,
      // Send all slots including nulls
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
          titleName: p.titleName || null,
        };
      }),
      gameInProgress: !!this.game,
      turnTimeLimit: this.turnTimeLimit,
      targetScore: this.targetScore,
      skExpansions: [...this.skExpansions],
      blockedSlots: [...this.blockedSlots].sort((a, b) => a - b),
      effectiveMaxPlayers: this.getEffectiveMaxPlayers(),
    };
  }

  setName(newName) {
    this.name = newName;
  }
}

module.exports = GameRoom;
