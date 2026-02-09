const { WebSocketServer } = require('ws');
const http = require('http');
const LobbyManager = require('./lobby/LobbyManager');
const GameRoom = require('./game/GameRoom');
const {
  initDatabase, registerUser, loginUser, checkNickname, deleteUser,
  blockUser, unblockUser, getBlockedUsers, reportUser, addFriend, getFriends,
  saveMatchResult, updateUserStats, getUserProfile, getRecentMatches,
  submitInquiry,
} = require('./db/database');
const { handleAdminRoute } = require('./admin');

const PORT = process.env.PORT || 8080;

// Create HTTP server for health checks (required by Render) and admin dashboard
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const pathname = url.pathname;

  if (pathname.startsWith('/tc-backstage')) {
    await handleAdminRoute(req, res, url, pathname, req.method, lobby, wss);
    return;
  }

  if (pathname === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('OK');
  } else {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('Tichu WebSocket Server');
  }
});

const wss = new WebSocketServer({ server });
const lobby = new LobbyManager();

let nextPlayerId = 1;

// Track nickname -> roomId for reconnection during games
const playerSessions = new Map(); // nickname -> { roomId, disconnectedAt }

// Clean up old sessions every 5 minutes
setInterval(() => {
  const now = Date.now();
  const maxAge = 30 * 60 * 1000; // 30 minutes
  for (const [nickname, session] of playerSessions) {
    if (now - session.disconnectedAt > maxAge) {
      playerSessions.delete(nickname);
      console.log(`Session expired for ${nickname}`);
    }
  }
}, 5 * 60 * 1000);

// Initialize database and start server
(async () => {
  await initDatabase();

  server.listen(PORT, () => {
    console.log(`Tichu server running on port ${PORT}`);
  });
})();

wss.on('connection', (ws) => {
  ws.playerId = null;
  ws.nickname = null;
  ws.roomId = null;

  console.log('New connection established');

  ws.on('message', (raw) => {
    let data;
    try {
      data = JSON.parse(raw.toString());
    } catch (e) {
      sendTo(ws, { type: 'error', message: 'Invalid JSON' });
      return;
    }

    handleMessage(ws, data);
  });

  ws.on('close', () => {
    console.log(`Player disconnected: ${ws.nickname} (${ws.playerId})`);
    if (ws.roomId) {
      const room = lobby.getRoom(ws.roomId);
      if (room) {
        if (ws.isSpectator) {
          room.removeSpectator(ws.playerId);
        } else if (room.game) {
          // Game in progress - mark as disconnected, don't remove
          room.markPlayerDisconnected(ws.playerId);
          // Store session for reconnection
          if (ws.nickname) {
            playerSessions.set(ws.nickname, {
              roomId: ws.roomId,
              disconnectedAt: Date.now(),
            });
          }
          broadcastRoomState(ws.roomId);
          sendGameStateToAll(ws.roomId);
        } else {
          // No game - just remove player
          room.removePlayer(ws.playerId);
          if (room.getPlayerCount() === 0) {
            lobby.removeRoom(ws.roomId);
          } else {
            broadcastRoomState(ws.roomId);
          }
        }
      }
      ws.roomId = null;
      ws.isSpectator = false;
    }
    broadcastRoomList();
  });

  ws.on('error', (err) => {
    console.error('WebSocket error:', err.message);
  });
});

function handleMessage(ws, data) {
  switch (data.type) {
    case 'register':
      handleRegister(ws, data);
      break;
    case 'login':
      handleLogin(ws, data);
      break;
    case 'check_nickname':
      handleCheckNickname(ws, data);
      break;
    case 'delete_account':
      handleDeleteAccount(ws);
      break;
    case 'room_list':
      sendTo(ws, { type: 'room_list', rooms: lobby.getRoomList() });
      break;
    case 'spectatable_rooms':
      sendTo(ws, { type: 'spectatable_rooms', rooms: lobby.getSpectatableRooms() });
      break;
    case 'create_room':
      handleCreateRoom(ws, data);
      break;
    case 'join_room':
      handleJoinRoom(ws, data);
      break;
    case 'leave_room':
      handleLeaveRoom(ws);
      break;
    case 'leave_game':
      handleLeaveGame(ws);
      break;
    case 'spectate_room':
      handleSpectateRoom(ws, data);
      break;
    case 'start_game':
      handleStartGame(ws);
      break;
    case 'change_team':
      handleChangeTeam(ws, data);
      break;
    case 'kick_player':
      handleKickPlayer(ws, data);
      break;
    case 'get_profile':
      handleGetProfile(ws, data);
      break;
    // Game actions
    case 'declare_large_tichu':
    case 'pass_large_tichu':
    case 'declare_small_tichu':
    case 'exchange_cards':
    case 'play_cards':
    case 'pass':
    case 'next_round':
    case 'dragon_give':
    case 'call_rank':
      handleGameAction(ws, data);
      break;
    // Spectator card view requests
    case 'request_card_view':
      handleRequestCardView(ws, data);
      break;
    case 'respond_card_view':
      handleRespondCardView(ws, data);
      break;
    // Chat
    case 'chat_message':
      handleChatMessage(ws, data);
      break;
    // User actions
    case 'block_user':
      handleBlockUser(ws, data);
      break;
    case 'unblock_user':
      handleUnblockUser(ws, data);
      break;
    case 'get_blocked_users':
      handleGetBlockedUsers(ws);
      break;
    case 'report_user':
      handleReportUser(ws, data);
      break;
    case 'submit_inquiry':
      handleSubmitInquiry(ws, data);
      break;
    case 'add_friend':
      handleAddFriend(ws, data);
      break;
    case 'get_friends':
      handleGetFriends(ws);
      break;
    default:
      sendTo(ws, { type: 'error', message: `Unknown message type: ${data.type}` });
  }
}

async function handleRegister(ws, data) {
  const { username, password, nickname } = data;
  const result = await registerUser(username, password, nickname);
  sendTo(ws, { type: 'register_result', ...result });
}

async function handleCheckNickname(ws, data) {
  const result = await checkNickname(data.nickname);
  sendTo(ws, { type: 'nickname_check_result', ...result });
}

async function handleDeleteAccount(ws) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'error', message: '로그인이 필요합니다' });
    return;
  }
  const result = await deleteUser(ws.nickname);
  if (result.success) {
    ws.nickname = null;
    ws.playerId = null;
  }
  sendTo(ws, { type: 'account_deleted', ...result });
}

async function handleLogin(ws, data) {
  const { username, password } = data;
  const result = await loginUser(username, password);

  if (!result.success) {
    sendTo(ws, { type: 'login_error', message: result.message });
    return;
  }

  ws.playerId = `player_${nextPlayerId++}`;
  ws.nickname = result.nickname;
  ws.userId = result.userId;
  console.log(`Player logged in: ${ws.nickname} (${ws.playerId})`);

  await handleReconnection(ws);
}

async function handleReconnection(ws) {
  // Check for reconnection to a game
  const session = playerSessions.get(ws.nickname);
  if (session) {
    const room = lobby.getRoom(session.roomId);
    if (room && room.game && room.canReconnect(ws.nickname)) {
      // Reconnect to the game
      const result = room.reconnectPlayer(ws.nickname, ws.playerId);
      if (result.success) {
        ws.roomId = room.id;
        playerSessions.delete(ws.nickname);
        console.log(`Player ${ws.nickname} reconnected to room ${room.name}`);

        sendTo(ws, {
          type: 'login_success',
          playerId: ws.playerId,
          nickname: ws.nickname,
        });
        sendTo(ws, {
          type: 'reconnected',
          roomId: room.id,
          roomName: room.name,
        });

        // Send current room and game state
        broadcastRoomState(room.id);
        sendGameStateToAll(room.id);
        broadcastRoomList();
        return;
      }
    }
    // Session expired or invalid - remove it
    playerSessions.delete(ws.nickname);
  }

  sendTo(ws, {
    type: 'login_success',
    playerId: ws.playerId,
    nickname: ws.nickname,
  });
  sendTo(ws, { type: 'room_list', rooms: lobby.getRoomList() });
}

function handleCreateRoom(ws, data) {
  if (!ws.playerId) {
    sendTo(ws, { type: 'error', message: 'Not logged in' });
    return;
  }
  if (ws.roomId) {
    sendTo(ws, { type: 'error', message: 'Already in a room' });
    return;
  }
  const roomName = (data.roomName || `${ws.nickname}'s Room`).trim();
  const isRanked = !!data.isRanked;
  const password = isRanked
    ? ''
    : (typeof data.password === 'string' ? data.password.trim() : '');
  const room = lobby.createRoom(
    roomName,
    ws.playerId,
    ws.nickname,
    password,
    isRanked
  );
  ws.roomId = room.id;
  sendTo(ws, { type: 'room_joined', roomId: room.id, roomName: room.name });
  broadcastRoomState(room.id);
  broadcastRoomList();
}

function handleJoinRoom(ws, data) {
  if (!ws.playerId) {
    sendTo(ws, { type: 'error', message: 'Not logged in' });
    return;
  }
  if (ws.roomId) {
    sendTo(ws, { type: 'error', message: 'Already in a room' });
    return;
  }
  const room = lobby.getRoom(data.roomId);
  if (!room) {
    sendTo(ws, { type: 'error', message: 'Room not found' });
    return;
  }
  const password = typeof data.password === 'string' ? data.password.trim() : '';
  const result = room.addPlayer(ws.playerId, ws.nickname, password);
  if (!result.success) {
    sendTo(ws, { type: 'error', message: result.message });
    return;
  }
  ws.roomId = room.id;
  sendTo(ws, { type: 'room_joined', roomId: room.id, roomName: room.name });
  // 채팅 히스토리 전송
  sendTo(ws, { type: 'chat_history', messages: room.getChatHistory() });
  broadcastRoomState(room.id);
  broadcastRoomList();
}

function handleLeaveRoom(ws) {
  if (!ws.roomId) return;
  const room = lobby.getRoom(ws.roomId);
  const roomId = ws.roomId;
  const wasSpectating = ws.isSpectator;
  ws.roomId = null;
  ws.isSpectator = false;
  if (room) {
    if (wasSpectating) {
      room.removeSpectator(ws.playerId);
    } else {
      room.removePlayer(ws.playerId);
      if (room.getPlayerCount() === 0) {
        lobby.removeRoom(roomId);
      } else {
        broadcastRoomState(roomId);
      }
    }
  }
  sendTo(ws, { type: 'room_left' });
  broadcastRoomList();
}

function handleLeaveGame(ws) {
  if (!ws.roomId) return;
  const room = lobby.getRoom(ws.roomId);
  const roomId = ws.roomId;

  if (!room) {
    ws.roomId = null;
    sendTo(ws, { type: 'room_left' });
    return;
  }

  // Remove from session tracking
  if (ws.nickname) {
    playerSessions.delete(ws.nickname);
  }

  // Remove player from room
  room.removePlayer(ws.playerId);
  ws.roomId = null;

  if (room.getPlayerCount() === 0) {
    lobby.removeRoom(roomId);
  } else {
    broadcastRoomState(roomId);
    if (room.game) {
      sendGameStateToAll(roomId);
    }
  }

  sendTo(ws, { type: 'room_left' });
  broadcastRoomList();
}

function handleSpectateRoom(ws, data) {
  if (!ws.playerId) {
    sendTo(ws, { type: 'error', message: 'Not logged in' });
    return;
  }
  if (ws.roomId) {
    sendTo(ws, { type: 'error', message: 'Already in a room' });
    return;
  }
  const room = lobby.getRoom(data.roomId);
  if (!room) {
    sendTo(ws, { type: 'error', message: 'Room not found' });
    return;
  }
  const result = room.addSpectator(ws.playerId, ws.nickname);
  if (!result.success) {
    sendTo(ws, { type: 'error', message: result.message });
    return;
  }
  ws.roomId = room.id;
  ws.isSpectator = true;
  sendTo(ws, { type: 'spectate_joined', roomId: room.id, roomName: room.name });

  // Send current game state if game is in progress (without card permissions initially)
  if (room.game) {
    const permittedPlayers = room.getPermittedPlayers(ws.playerId);
    const state = room.game.getStateForSpectator(permittedPlayers);
    sendTo(ws, { type: 'spectator_game_state', state });
  }
}

function handleRequestCardView(ws, data) {
  if (!ws.roomId || !ws.isSpectator) {
    sendTo(ws, { type: 'error', message: 'Not spectating' });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room) return;

  const playerId = data.playerId;
  const result = room.requestCardView(ws.playerId, ws.nickname, playerId);
  if (!result.success) {
    sendTo(ws, { type: 'error', message: result.message });
    return;
  }

  // Notify the player about the request
  const playerWs = findWsByPlayerId(playerId);
  if (playerWs) {
    sendTo(playerWs, {
      type: 'card_view_request',
      spectatorId: ws.playerId,
      spectatorNickname: ws.nickname,
    });
  }

  sendTo(ws, { type: 'card_view_requested', playerId });
}

function handleRespondCardView(ws, data) {
  if (!ws.roomId) {
    sendTo(ws, { type: 'error', message: 'Not in a room' });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room) return;

  const spectatorId = data.spectatorId;
  const allow = data.allow === true;

  const result = room.respondCardViewRequest(ws.playerId, spectatorId, allow);
  if (!result.success) {
    sendTo(ws, { type: 'error', message: result.message });
    return;
  }

  // Notify the spectator
  const spectatorWs = findWsByPlayerId(spectatorId);
  if (spectatorWs) {
    sendTo(spectatorWs, {
      type: 'card_view_response',
      playerId: ws.playerId,
      playerNickname: ws.nickname,
      allowed: allow,
    });

    // If allowed, send updated game state with the new permission
    if (allow && room.game) {
      const permittedPlayers = room.getPermittedPlayers(spectatorId);
      const state = room.game.getStateForSpectator(permittedPlayers);
      sendTo(spectatorWs, { type: 'spectator_game_state', state });
    }
  }
}

function handleStartGame(ws) {
  if (!ws.roomId) {
    sendTo(ws, { type: 'error', message: 'Not in a room' });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room) return;
  if (room.hostId !== ws.playerId) {
    sendTo(ws, { type: 'error', message: 'Only the host can start the game' });
    return;
  }
  if (room.getPlayerCount() < 4) {
    sendTo(ws, { type: 'error', message: 'Need 4 players to start' });
    return;
  }
  room.startGame();
  broadcastRoomState(ws.roomId);
  // Send initial cards to each player
  sendGameStateToAll(ws.roomId);
}

function handleChangeTeam(ws, data) {
  if (!ws.roomId) {
    sendTo(ws, { type: 'error', message: 'Not in a room' });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room) return;
  if (room.isRanked) {
    sendTo(ws, { type: 'error', message: '랭크전에서는 팀을 변경할 수 없습니다' });
    return;
  }
  if (room.game) {
    sendTo(ws, { type: 'error', message: '게임 중에는 팀을 변경할 수 없습니다' });
    return;
  }
  const targetSlot = data.targetSlot;
  if (typeof targetSlot !== 'number' || targetSlot < 0 || targetSlot > 3) {
    sendTo(ws, { type: 'error', message: 'Invalid slot' });
    return;
  }
  const result = room.movePlayerToSlot(ws.playerId, targetSlot);
  if (!result.success) {
    sendTo(ws, { type: 'error', message: result.message });
    return;
  }
  broadcastRoomState(ws.roomId);
}

// Kick player handler (host only, not during game)
function handleKickPlayer(ws, data) {
  if (!ws.roomId) {
    sendTo(ws, { type: 'error', message: 'Not in a room' });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room) return;
  if (room.hostId !== ws.playerId) {
    sendTo(ws, { type: 'error', message: '방장만 강퇴할 수 있습니다' });
    return;
  }
  if (room.game) {
    sendTo(ws, { type: 'error', message: '게임 중에는 강퇴할 수 없습니다' });
    return;
  }
  const targetPlayerId = data.playerId;
  if (!targetPlayerId || targetPlayerId === ws.playerId) {
    sendTo(ws, { type: 'error', message: '자신을 강퇴할 수 없습니다' });
    return;
  }
  // Check if target is in the room
  if (!room.players.some(p => p !== null && p.id === targetPlayerId)) {
    sendTo(ws, { type: 'error', message: '플레이어를 찾을 수 없습니다' });
    return;
  }
  // Send kicked message to target before removing
  const targetWs = findWsByPlayerId(targetPlayerId);
  if (targetWs) {
    sendTo(targetWs, { type: 'kicked', message: '방장에 의해 강퇴되었습니다' });
    targetWs.roomId = null;
  }
  room.removePlayer(targetPlayerId);
  broadcastRoomState(ws.roomId);
  broadcastRoomList();
}

// Get user profile handler
async function handleGetProfile(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'error', message: '로그인이 필요합니다' });
    return;
  }
  const targetNickname = data.nickname;
  if (!targetNickname) {
    sendTo(ws, { type: 'error', message: '닉네임이 필요합니다' });
    return;
  }
  const profile = await getUserProfile(targetNickname);
  const recentMatches = await getRecentMatches(targetNickname, 5);
  const isBlocked = (await getBlockedUsers(ws.nickname)).includes(targetNickname);
  sendTo(ws, {
    type: 'profile_result',
    nickname: targetNickname,
    profile,
    recentMatches,
    isBlocked,
  });
}

function handleGameAction(ws, data) {
  if (!ws.roomId) {
    sendTo(ws, { type: 'error', message: 'Not in a room' });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room || !room.game) {
    sendTo(ws, { type: 'error', message: 'No active game' });
    return;
  }

  if (data.type === 'next_round') {
    if (room.hostId !== ws.playerId) {
      sendTo(ws, { type: 'error', message: 'Only the host can start the next round' });
      return;
    }
    const result = room.game.handleAction(ws.playerId, data);
    if (!result.success) {
      sendTo(ws, { type: 'error', message: result.message });
      return;
    }
    sendGameStateToAll(ws.roomId);
    return;
  }

  const result = room.game.handleAction(ws.playerId, data);
  if (!result.success) {
    sendTo(ws, { type: 'error', message: result.message });
    return;
  }

  // Broadcast updated game state
  if (result.broadcast) {
    broadcastGameEvent(ws.roomId, result.broadcast);
  }
  sendGameStateToAll(ws.roomId);

  // Check for game end and save match result
  if (room.game && room.game.state === 'game_end') {
    saveGameResult(room);
  }
}

// Save game result to database
async function saveGameResult(room) {
  if (!room.game) return;
  const game = room.game;
  const totalScores = game.totalScores;
  const winnerTeam = totalScores.teamA >= totalScores.teamB ? 'A' : 'B';

  // Get player nicknames by team
  const playerIds = game.playerIds;
  const playerNames = game.playerNames;
  const teams = game.teams;

  const teamAPlayers = teams.teamA;
  const teamBPlayers = teams.teamB;

  try {
    await saveMatchResult({
      winnerTeam,
      teamAScore: totalScores.teamA,
      teamBScore: totalScores.teamB,
      playerA1: playerNames[teamAPlayers[0]] || '',
      playerA2: playerNames[teamAPlayers[1]] || '',
      playerB1: playerNames[teamBPlayers[0]] || '',
      playerB2: playerNames[teamBPlayers[1]] || '',
      isRanked: room.isRanked,
    });

    // Update stats for each player
    for (const pid of teamAPlayers) {
      const nick = playerNames[pid];
      if (nick) await updateUserStats(nick, winnerTeam === 'A', room.isRanked);
    }
    for (const pid of teamBPlayers) {
      const nick = playerNames[pid];
      if (nick) await updateUserStats(nick, winnerTeam === 'B', room.isRanked);
    }
    console.log(`Match result saved for room ${room.name}`);
  } catch (err) {
    console.error('Error saving match result:', err);
  }
}

function sendGameStateToAll(roomId) {
  const room = lobby.getRoom(roomId);
  if (!room || !room.game) return;

  // Build connection status map (skip null slots)
  const connectionStatus = {};
  for (const player of room.players) {
    if (player === null) continue;
    connectionStatus[player.id] = player.connected !== false;
  }

  // Send to players (skip null slots)
  for (const player of room.players) {
    if (player === null) continue;
    if (player.connected === false) continue; // Skip disconnected players
    const ws = findWsByPlayerId(player.id);
    if (ws) {
      const state = room.game.getStateForPlayer(player.id);
      // Add connection status to each player
      state.players = state.players.map(p => ({
        ...p,
        connected: connectionStatus[p.id] !== false,
      }));
      console.log(`[DEBUG] Sending game_state to ${player.nickname}: phase=${state.phase}, cards=${state.myCards?.length || 0}`);
      sendTo(ws, { type: 'game_state', state });
    }
  }

  // Send to spectators (each with their own permissions)
  for (const spectatorId of room.getSpectatorIds()) {
    const ws = findWsByPlayerId(spectatorId);
    if (ws) {
      const permittedPlayers = room.getPermittedPlayers(spectatorId);
      const spectatorState = room.game.getStateForSpectator(permittedPlayers);
      // Add connection status to each player
      spectatorState.players = spectatorState.players.map(p => ({
        ...p,
        connected: connectionStatus[p.id] !== false,
      }));
      sendTo(ws, { type: 'spectator_game_state', state: spectatorState });
    }
  }
}

function broadcastGameEvent(roomId, event) {
  const room = lobby.getRoom(roomId);
  if (!room) return;
  // Send to players (skip null slots)
  for (const player of room.players) {
    if (player === null) continue;
    const ws = findWsByPlayerId(player.id);
    if (ws) {
      sendTo(ws, event);
    }
  }
  // Send to spectators
  for (const spectatorId of room.getSpectatorIds()) {
    const ws = findWsByPlayerId(spectatorId);
    if (ws) {
      sendTo(ws, event);
    }
  }
}

function broadcastRoomState(roomId) {
  const room = lobby.getRoom(roomId);
  if (!room) return;
  const roomState = room.getState();
  // Send to players (skip null slots)
  for (const player of room.players) {
    if (player === null) continue;
    const ws = findWsByPlayerId(player.id);
    if (ws) {
      sendTo(ws, { type: 'room_state', room: roomState });
    }
  }
}

function broadcastRoomList() {
  const rooms = lobby.getRoomList();
  wss.clients.forEach((ws) => {
    if (ws.playerId && !ws.roomId) {
      sendTo(ws, { type: 'room_list', rooms });
    }
  });
}

// Chat message handler
function handleChatMessage(ws, data) {
  if (!ws.roomId || !ws.nickname) {
    sendTo(ws, { type: 'error', message: 'Not in a room' });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room) return;

  const message = (data.message || '').trim();
  if (!message || message.length > 200) return;

  // 방에 메시지 저장
  room.addChatMessage(ws.nickname, ws.playerId, message);

  const chatData = {
    type: 'chat_message',
    sender: ws.nickname,
    senderId: ws.playerId,
    message: message,
    timestamp: Date.now(),
  };

  // Broadcast to all players in the room
  room.getPlayerIds().forEach(playerId => {
    const playerWs = findWsByPlayerId(playerId);
    if (playerWs) {
      sendTo(playerWs, chatData);
    }
  });

  // Also send to spectators
  room.getSpectatorIds().forEach(specId => {
    const specWs = findWsByPlayerId(specId);
    if (specWs) {
      sendTo(specWs, chatData);
    }
  });
}

// Block user handler
async function handleBlockUser(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'error', message: '로그인이 필요합니다' });
    return;
  }
  const targetNickname = data.nickname;
  if (!targetNickname || targetNickname === ws.nickname) {
    sendTo(ws, { type: 'error', message: '차단할 수 없습니다' });
    return;
  }
  const result = await blockUser(ws.nickname, targetNickname);
  sendTo(ws, { type: 'block_result', success: result.success, nickname: targetNickname, blocked: true });
}

// Unblock user handler
async function handleUnblockUser(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'error', message: '로그인이 필요합니다' });
    return;
  }
  const targetNickname = data.nickname;
  if (!targetNickname) return;
  const result = await unblockUser(ws.nickname, targetNickname);
  sendTo(ws, { type: 'block_result', success: result.success, nickname: targetNickname, blocked: false });
}

// Get blocked users handler
async function handleGetBlockedUsers(ws) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'blocked_users', users: [] });
    return;
  }
  const blockedUsers = await getBlockedUsers(ws.nickname);
  sendTo(ws, { type: 'blocked_users', users: blockedUsers });
}

// Report user handler
async function handleReportUser(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'error', message: '로그인이 필요합니다' });
    return;
  }
  const targetNickname = data.nickname;
  const reason = data.reason || '';
  if (!targetNickname || targetNickname === ws.nickname) {
    sendTo(ws, { type: 'error', message: '신고할 수 없습니다' });
    return;
  }
  // 채팅 컨텍스트 가져오기
  let chatContext = [];
  if (ws.roomId) {
    const room = lobby.getRoom(ws.roomId);
    if (room) {
      chatContext = room.getChatHistory();
    }
  }
  const result = await reportUser(ws.nickname, targetNickname, reason, ws.roomId || '', chatContext);
  sendTo(ws, { type: 'report_result', ...result });
}

// Submit inquiry handler
async function handleSubmitInquiry(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'error', message: '로그인이 필요합니다' });
    return;
  }
  const { category, title, content } = data;
  if (!category || !title || !content) {
    sendTo(ws, { type: 'inquiry_result', success: false, message: '모든 항목을 입력해주세요' });
    return;
  }
  if (!['bug', 'suggestion', 'other'].includes(category)) {
    sendTo(ws, { type: 'inquiry_result', success: false, message: '올바른 카테고리를 선택해주세요' });
    return;
  }
  const result = await submitInquiry(ws.nickname, category, title, content);
  sendTo(ws, { type: 'inquiry_result', ...result });
}

// Add friend handler
async function handleAddFriend(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'error', message: '로그인이 필요합니다' });
    return;
  }
  const targetNickname = data.nickname;
  if (!targetNickname || targetNickname === ws.nickname) {
    sendTo(ws, { type: 'error', message: '친구 추가할 수 없습니다' });
    return;
  }
  const result = await addFriend(ws.nickname, targetNickname);
  sendTo(ws, { type: 'friend_result', ...result });
}

// Get friends handler
async function handleGetFriends(ws) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'friends_list', friends: [] });
    return;
  }
  const friends = await getFriends(ws.nickname);
  sendTo(ws, { type: 'friends_list', friends });
}

function findWsByPlayerId(playerId) {
  for (const ws of wss.clients) {
    if (ws.playerId === playerId) return ws;
  }
  return null;
}

function sendTo(ws, data) {
  if (ws.readyState === ws.OPEN) {
    ws.send(JSON.stringify(data));
  }
}
