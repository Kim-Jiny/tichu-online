const { WebSocketServer } = require('ws');
const http = require('http');
const LobbyManager = require('./lobby/LobbyManager');
const GameRoom = require('./game/GameRoom');

const PORT = process.env.PORT || 8080;

// Create HTTP server for health checks (required by Render)
const server = http.createServer((req, res) => {
  if (req.url === '/health') {
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

server.listen(PORT, () => {
  console.log(`Tichu server running on port ${PORT}`);
});

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
        room.removePlayer(ws.playerId);
        if (room.getPlayerCount() === 0) {
          lobby.removeRoom(ws.roomId);
        } else {
          broadcastRoomState(ws.roomId);
        }
      }
      ws.roomId = null;
    }
    broadcastRoomList();
  });

  ws.on('error', (err) => {
    console.error('WebSocket error:', err.message);
  });
});

function handleMessage(ws, data) {
  switch (data.type) {
    case 'login':
      handleLogin(ws, data);
      break;
    case 'room_list':
      sendTo(ws, { type: 'room_list', rooms: lobby.getRoomList() });
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
    case 'start_game':
      handleStartGame(ws);
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
    default:
      sendTo(ws, { type: 'error', message: `Unknown message type: ${data.type}` });
  }
}

function handleLogin(ws, data) {
  if (!data.nickname || data.nickname.trim().length === 0) {
    sendTo(ws, { type: 'error', message: 'Nickname is required' });
    return;
  }
  ws.playerId = `player_${nextPlayerId++}`;
  ws.nickname = data.nickname.trim();
  console.log(`Player logged in: ${ws.nickname} (${ws.playerId})`);
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
  const room = lobby.createRoom(roomName, ws.playerId, ws.nickname);
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
  const result = room.addPlayer(ws.playerId, ws.nickname);
  if (!result.success) {
    sendTo(ws, { type: 'error', message: result.message });
    return;
  }
  ws.roomId = room.id;
  sendTo(ws, { type: 'room_joined', roomId: room.id, roomName: room.name });
  broadcastRoomState(room.id);
  broadcastRoomList();
}

function handleLeaveRoom(ws) {
  if (!ws.roomId) return;
  const room = lobby.getRoom(ws.roomId);
  const roomId = ws.roomId;
  ws.roomId = null;
  if (room) {
    room.removePlayer(ws.playerId);
    if (room.getPlayerCount() === 0) {
      lobby.removeRoom(roomId);
    } else {
      broadcastRoomState(roomId);
    }
  }
  sendTo(ws, { type: 'room_left' });
  broadcastRoomList();
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
}

function sendGameStateToAll(roomId) {
  const room = lobby.getRoom(roomId);
  if (!room || !room.game) return;

  for (const player of room.players) {
    const ws = findWsByPlayerId(player.id);
    if (ws) {
      const state = room.game.getStateForPlayer(player.id);
      console.log(`[DEBUG] Sending game_state to ${player.nickname}: phase=${state.phase}, cards=${state.myCards?.length || 0}`);
      sendTo(ws, { type: 'game_state', state });
    }
  }
}

function broadcastGameEvent(roomId, event) {
  const room = lobby.getRoom(roomId);
  if (!room) return;
  for (const player of room.players) {
    const ws = findWsByPlayerId(player.id);
    if (ws) {
      sendTo(ws, event);
    }
  }
}

function broadcastRoomState(roomId) {
  const room = lobby.getRoom(roomId);
  if (!room) return;
  const roomState = room.getState();
  for (const player of room.players) {
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
