const { WebSocketServer } = require('ws');
const http = require('http');
const LobbyManager = require('./lobby/LobbyManager');
const GameRoom = require('./game/GameRoom');
const { decideBotAction } = require('./game/BotPlayer');
const {
  initDatabase, registerUser, loginUser, checkNickname, deleteUser,
  blockUser, unblockUser, getBlockedUsers, reportUser,
  addFriend, getFriends, getPendingFriendRequests,
  acceptFriendRequest, rejectFriendRequest, removeFriend,
  saveMatchResult, updateUserStats, getUserProfile, getRecentMatches,
  submitInquiry, getUserInquiries, markInquiriesRead, getRankings,
  getWallet, getShopItems, getUserItems, buyItem, equipItem, useItem, changeNickname,
  incrementLeaveCount, setRankedBan, getRankedBan, setChatBan, getChatBan, grantSeasonRewards,
  getActiveSeason, createSeason, getSeasons,
  getCurrentSeasonRankings, getSeasonRankings, resetSeasonStats,
  loginSocial, registerSocial,
  linkSocial, unlinkSocial, getLinkedSocial,
  updateDeviceInfo,
  setPushEnabled,
  setPushFriendInvite,
} = require('./db/database');

// Firebase Admin SDK initialization (optional - only if FIREBASE_SERVICE_ACCOUNT is set)
let firebaseAdmin = null;
try {
  const admin = require('firebase-admin');
  const serviceAccountJson = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (serviceAccountJson) {
    const serviceAccount = JSON.parse(serviceAccountJson);
    admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
    firebaseAdmin = admin;
    console.log('Firebase Admin SDK initialized');
  } else {
    console.log('FIREBASE_SERVICE_ACCOUNT not set - Firebase social login disabled');
  }
} catch (err) {
  console.log('Firebase Admin SDK not available:', err.message);
}

// Token verification functions
async function verifyFirebaseToken(idToken) {
  if (firebaseAdmin) {
    const decoded = await firebaseAdmin.auth().verifyIdToken(idToken);
    return { uid: decoded.uid, email: decoded.email || null };
  }
  // Fallback: decode JWT without signature verification (local dev)
  try {
    const payload = idToken.split('.')[1];
    const decoded = JSON.parse(Buffer.from(payload, 'base64url').toString());
    console.log('Firebase token decoded (no verification - dev mode)');
    return { uid: decoded.sub || decoded.user_id, email: decoded.email || null };
  } catch (e) {
    throw new Error('Firebase token decode failed: ' + e.message);
  }
}

async function verifyKakaoToken(accessToken) {
  const res = await fetch('https://kapi.kakao.com/v2/user/me', {
    headers: { 'Authorization': `Bearer ${accessToken}` },
  });
  if (!res.ok) throw new Error('Kakao token verification failed');
  const data = await res.json();
  return {
    uid: String(data.id),
    email: data.kakao_account?.email || null,
  };
}
// Push notification helper
async function sendPushNotification(fcmToken, title, body) {
  if (!firebaseAdmin) return { success: false, message: 'Firebase not configured' };
  try {
    await firebaseAdmin.messaging().send({
      token: fcmToken,
      notification: { title, body },
    });
    return { success: true };
  } catch (err) {
    console.error('Push notification error:', err.message);
    return { success: false, message: err.message };
  }
}

const { handleAdminRoute } = require('./admin');

const PORT = process.env.PORT || 8080;

// Maintenance config (in-memory)
let maintenanceConfig = {
  noticeStart: null,    // ISO string
  noticeEnd: null,
  maintenanceStart: null,
  maintenanceEnd: null,
  message: '',
};

function getMaintenanceConfig() {
  return { ...maintenanceConfig };
}

function setMaintenanceConfig(config) {
  maintenanceConfig = { ...maintenanceConfig, ...config };
}

function getMaintenanceStatus() {
  const now = new Date();
  let notice = false;
  let maintenance = false;

  if (maintenanceConfig.noticeStart && maintenanceConfig.noticeEnd) {
    const ns = new Date(maintenanceConfig.noticeStart);
    const ne = new Date(maintenanceConfig.noticeEnd);
    if (now >= ns && now <= ne) notice = true;
  }
  if (maintenanceConfig.maintenanceStart && maintenanceConfig.maintenanceEnd) {
    const ms = new Date(maintenanceConfig.maintenanceStart);
    const me = new Date(maintenanceConfig.maintenanceEnd);
    if (now >= ms && now <= me) maintenance = true;
  }

  return {
    notice,
    maintenance,
    message: maintenanceConfig.message || '',
    maintenanceStart: maintenanceConfig.maintenanceStart,
    maintenanceEnd: maintenanceConfig.maintenanceEnd,
  };
}

// Create HTTP server for health checks (required by Render) and admin dashboard
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const pathname = url.pathname;

  // Debug: log admin route attempts
  if (pathname.startsWith('/tc-backstage') || pathname.includes('backstage')) {
    console.log(`[ADMIN] ${req.method} ${pathname}`);
  }

  if (pathname.startsWith('/tc-backstage')) {
    try {
      await handleAdminRoute(req, res, url, pathname, req.method, lobby, wss, { getMaintenanceConfig, setMaintenanceConfig, getMaintenanceStatus, sendPushNotification });
    } catch (err) {
      console.error('Admin route error:', err);
      res.writeHead(500, { 'Content-Type': 'text/plain' });
      res.end('Internal Server Error');
    }
    return;
  }

  if (pathname === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('OK');
  } else if (pathname === '/debug-path') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end(`pathname=${req.url} | hasAdmin=${typeof handleAdminRoute}`);
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

// Turn timer system
const turnTimers = {};    // roomId -> setTimeout handle
const timeoutCounts = {}; // roomId -> { playerId: count }
const roundEndTimers = {}; // roomId -> setTimeout handle for auto next round
const turnTimerPhases = {}; // roomId -> phase name (to prevent phase timer reset)
const waitingRoomTimers = {}; // `${roomId}_${playerId}` -> setTimeout handle for waiting room disconnect

function seasonNameFromDate(date) {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  return `${y}-${m} 시즌`;
}

async function ensureSeasonCycle() {
  const now = new Date();
  const active = await getActiveSeason();

  if (active) {
    const endAt = new Date(active.end_at);
    if (now >= endAt) {
      await grantSeasonRewards(active.id);
      await resetSeasonStats();
      const startAt = new Date(now.getFullYear(), now.getMonth(), 1, 0, 0, 0);
      const nextEnd = new Date(now.getFullYear(), now.getMonth() + 1, 1, 0, 0, 0);
      await createSeason(seasonNameFromDate(startAt), startAt, nextEnd);
    }
    return;
  }

  const startAt = new Date(now.getFullYear(), now.getMonth(), 1, 0, 0, 0);
  const endAt = new Date(now.getFullYear(), now.getMonth() + 1, 1, 0, 0, 0);
  await createSeason(seasonNameFromDate(startAt), startAt, endAt);
}

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
  await ensureSeasonCycle();

  server.listen(PORT, () => {
    console.log(`Tichu server running on port ${PORT}`);
  });
})();

// Season cycle check every hour
setInterval(() => {
  ensureSeasonCycle();
}, 60 * 60 * 1000);

wss.on('connection', (ws, req) => {
  ws.playerId = null;
  ws.nickname = null;
  ws.roomId = null;
  ws.clientIp = req.headers['x-forwarded-for']?.split(',')[0]?.trim()
    || req.socket.remoteAddress || null;

  console.log('New connection established');

  ws.on('message', (raw) => {
    let data;
    try {
      data = JSON.parse(raw.toString());
    } catch (e) {
      sendTo(ws, { type: 'error', message: '잘못된 데이터 형식입니다' });
      return;
    }

    handleMessage(ws, data);
  });

  ws.on('close', () => {
    console.log(`Player disconnected: ${ws.nickname} (${ws.playerId})`);
    // Notify friends of offline status
    if (ws.nickname) {
      notifyFriendsOfStatusChange(ws.nickname, false);
    }
    if (ws.roomId) {
      const room = lobby.getRoom(ws.roomId);
      if (room) {
        if (ws.isSpectator) {
          room.removeSpectator(ws.playerId);
          if (room.game) _broadcastState(ws.roomId, room);
          broadcastRoomState(ws.roomId);
          broadcastRoomList();
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
          // No game - mark as disconnected and start 30s removal timer
          const disconnectedPlayerId = ws.playerId;
          const disconnectedRoomId = ws.roomId;
          room.markPlayerDisconnected(disconnectedPlayerId);
          broadcastRoomState(disconnectedRoomId);
          const timerKey = `${disconnectedRoomId}_${disconnectedPlayerId}`;
          waitingRoomTimers[timerKey] = setTimeout(() => {
            delete waitingRoomTimers[timerKey];
            const r = lobby.getRoom(disconnectedRoomId);
            if (!r) return;
            r.removePlayer(disconnectedPlayerId);
            if (r.getHumanPlayerCount() === 0) {
              removeRoomAndNotifySpectators(disconnectedRoomId);
            } else {
              broadcastRoomState(disconnectedRoomId);
            }
            broadcastRoomList();
          }, 30000);
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
    case 'change_room_name':
      handleChangeRoomName(ws, data);
      break;
    case 'return_to_room':
      handleReturnToRoom(ws);
      break;
    case 'check_room':
      handleCheckRoom(ws);
      break;
    case 'spectate_room':
      handleSpectateRoom(ws, data);
      break;
    case 'toggle_ready':
      handleToggleReady(ws);
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
    case 'add_bot':
      handleAddBot(ws, data);
      break;
    case 'switch_to_spectator':
      handleSwitchToSpectator(ws);
      break;
    case 'switch_to_player':
      handleSwitchToPlayer(ws, data);
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
    case 'reset_timeout':
      handleResetTimeout(ws);
      break;
    // Spectator card view requests
    case 'request_card_view':
      handleRequestCardView(ws, data);
      break;
    case 'respond_card_view':
      handleRespondCardView(ws, data);
      break;
    case 'revoke_card_view':
      handleRevokeCardView(ws, data);
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
    case 'get_inquiries':
      handleGetInquiries(ws);
      break;
    case 'mark_inquiries_read':
      handleMarkInquiriesRead(ws);
      break;
    case 'add_friend':
      handleAddFriend(ws, data);
      break;
    case 'get_friends':
      handleGetFriends(ws);
      break;
    case 'get_pending_friend_requests':
      handleGetPendingFriendRequests(ws);
      break;
    case 'accept_friend_request':
      handleAcceptFriendRequest(ws, data);
      break;
    case 'reject_friend_request':
      handleRejectFriendRequest(ws, data);
      break;
    case 'remove_friend':
      handleRemoveFriend(ws, data);
      break;
    case 'invite_to_room':
      handleInviteToRoom(ws, data);
      break;
    case 'get_rankings':
      handleGetRankings(ws, data);
      break;
    case 'get_seasons':
      handleGetSeasons(ws);
      break;
    case 'get_wallet':
      handleGetWallet(ws);
      break;
    case 'get_shop_items':
      handleGetShopItems(ws);
      break;
    case 'get_inventory':
      handleGetInventory(ws);
      break;
    case 'buy_item':
      handleBuyItem(ws, data);
      break;
    case 'equip_item':
      handleEquipItem(ws, data);
      break;
    case 'use_item':
      handleUseItem(ws, data);
      break;
    case 'change_nickname':
      handleChangeNickname(ws, data);
      break;
    case 'social_login':
      handleSocialLogin(ws, data);
      break;
    case 'social_register':
      handleSocialRegister(ws, data);
      break;
    case 'social_link':
      handleSocialLink(ws, data);
      break;
    case 'social_unlink':
      handleSocialUnlink(ws);
      break;
    case 'get_linked_social':
      handleGetLinkedSocial(ws);
      break;
    case 'update_fcm_token':
      if (ws.nickname && data.fcmToken) {
        updateDeviceInfo(ws.nickname, { fcmToken: data.fcmToken });
      }
      break;
    case 'update_push_setting':
      if (ws.nickname) {
        if (data.enabled != null) {
          setPushEnabled(ws.nickname, data.enabled === true);
        }
        if (data.friendInvite != null) {
          setPushFriendInvite(ws.nickname, data.friendInvite === true);
        }
      }
      break;
    case 'get_maintenance_status':
      sendTo(ws, { type: 'maintenance_status', ...getMaintenanceStatus() });
      break;
    default:
      sendTo(ws, { type: 'error', message: `알 수 없는 메시지: ${data.type}` });
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

  // Block login during maintenance
  const mStatus = getMaintenanceStatus();
  if (mStatus.maintenance) {
    sendTo(ws, { type: 'login_error', message: mStatus.message || '서버 점검 중입니다' });
    return;
  }

  // S3: Disconnect existing connection with same nickname to prevent duplicate login
  for (const client of wss.clients) {
    if (client !== ws && client.nickname === result.nickname && client.readyState === client.OPEN) {
      // Preemptively store session before close (close handler is async)
      if (client.roomId) {
        const oldRoom = lobby.getRoom(client.roomId);
        if (oldRoom && oldRoom.game) {
          oldRoom.markPlayerDisconnected(client.playerId);
          playerSessions.set(client.nickname, {
            roomId: client.roomId,
            disconnectedAt: Date.now(),
          });
        }
      }
      sendTo(client, { type: 'kicked', message: '다른 기기에서 로그인되었습니다' });
      client.roomId = null; // Prevent close handler from double-processing
      client.close();
    }
  }

  ws.playerId = `player_${nextPlayerId++}`;
  ws.nickname = result.nickname;
  ws.userId = result.userId;
  console.log(`Player logged in: ${ws.nickname} (${ws.playerId})`);

  // Notify friends of online status
  notifyFriendsOfStatusChange(ws.nickname, true);

  await handleReconnection(ws);

  // Save device info (fire-and-forget)
  const deviceInfo = data.deviceInfo || {};
  deviceInfo.lastIp = ws.clientIp;
  updateDeviceInfo(ws.nickname, deviceInfo);
}

async function handleSocialLogin(ws, data) {
  const { provider, token } = data;
  if (!provider || !token) {
    sendTo(ws, { type: 'login_error', message: '잘못된 요청입니다' });
    return;
  }

  try {
    // Verify token
    let verified;
    if (provider === 'kakao') {
      verified = await verifyKakaoToken(token);
    } else {
      // google, apple → Firebase
      verified = await verifyFirebaseToken(token);
    }

    // Block login during maintenance
    const mStatus = getMaintenanceStatus();
    if (mStatus.maintenance) {
      sendTo(ws, { type: 'login_error', message: mStatus.message || '서버 점검 중입니다' });
      return;
    }

    // Check if user exists
    const result = await loginSocial(provider, verified.uid);
    if (result.found) {
      // Check for empty nickname (existing user with blank nickname)
      if (!result.nickname || result.nickname.trim() === '') {
        sendTo(ws, {
          type: 'need_nickname',
          provider,
          providerUid: verified.uid,
          email: verified.email,
          existingUser: true,
          userId: result.userId,
        });
        return;
      }

      // Existing user - proceed with login flow (same as handleLogin post-auth)
      // Disconnect existing connection with same nickname
      for (const client of wss.clients) {
        if (client !== ws && client.nickname === result.nickname && client.readyState === client.OPEN) {
          if (client.roomId) {
            const oldRoom = lobby.getRoom(client.roomId);
            if (oldRoom && oldRoom.game) {
              oldRoom.markPlayerDisconnected(client.playerId);
              playerSessions.set(client.nickname, {
                roomId: client.roomId,
                disconnectedAt: Date.now(),
              });
            }
          }
          sendTo(client, { type: 'kicked', message: '다른 기기에서 로그인되었습니다' });
          client.roomId = null;
          client.close();
        }
      }

      ws.playerId = `player_${nextPlayerId++}`;
      ws.nickname = result.nickname;
      ws.userId = result.userId;
      console.log(`Player logged in (social/${provider}): ${ws.nickname} (${ws.playerId})`);

      notifyFriendsOfStatusChange(ws.nickname, true);
      await handleReconnection(ws);

      // Save device info (fire-and-forget)
      const socialDeviceInfo = data.deviceInfo || {};
      socialDeviceInfo.lastIp = ws.clientIp;
      updateDeviceInfo(ws.nickname, socialDeviceInfo);
    } else {
      // New user - need nickname
      sendTo(ws, { type: 'need_nickname', provider, providerUid: verified.uid, email: verified.email });
    }
  } catch (err) {
    console.error('Social login error:', err);
    sendTo(ws, { type: 'login_error', message: '소셜 로그인에 실패했습니다' });
  }
}

async function handleSocialRegister(ws, data) {
  const { provider, token, nickname, existingUser } = data;
  if (!provider || !token || !nickname) {
    sendTo(ws, { type: 'login_error', message: '잘못된 요청입니다' });
    return;
  }

  try {
    // Re-verify token
    let verified;
    if (provider === 'kakao') {
      verified = await verifyKakaoToken(token);
    } else {
      verified = await verifyFirebaseToken(token);
    }

    // Block during maintenance
    const mStatus = getMaintenanceStatus();
    if (mStatus.maintenance) {
      sendTo(ws, { type: 'login_error', message: mStatus.message || '서버 점검 중입니다' });
      return;
    }

    let result;
    if (existingUser) {
      // Existing user with empty nickname - update nickname directly
      const { pool } = require('./db/database');
      const client = await pool.connect();
      try {
        // Check nickname duplicate
        const dupCheck = await client.query(
          'SELECT id FROM tc_users WHERE nickname = $1',
          [nickname.trim()]
        );
        if (dupCheck.rows.length > 0) {
          sendTo(ws, { type: 'login_error', message: '이미 사용중인 닉네임입니다' });
          return;
        }
        // Find user by provider + uid
        const userRes = await client.query(
          'SELECT id FROM tc_users WHERE auth_provider = $1 AND provider_uid = $2',
          [provider, verified.uid]
        );
        if (userRes.rows.length === 0) {
          sendTo(ws, { type: 'login_error', message: '사용자를 찾을 수 없습니다' });
          return;
        }
        const userId = userRes.rows[0].id;
        await client.query(
          'UPDATE tc_users SET nickname = $1 WHERE id = $2',
          [nickname.trim(), userId]
        );
        result = { success: true, userId, nickname: nickname.trim() };
      } finally {
        client.release();
      }
    } else {
      result = await registerSocial(provider, verified.uid, verified.email, nickname);
    }

    if (!result.success) {
      sendTo(ws, { type: 'login_error', message: result.message });
      return;
    }

    // Auto-login after registration (same flow as handleLogin post-auth)
    ws.playerId = `player_${nextPlayerId++}`;
    ws.nickname = result.nickname;
    ws.userId = result.userId;
    console.log(`Player registered & logged in (social/${provider}): ${ws.nickname} (${ws.playerId})`);

    notifyFriendsOfStatusChange(ws.nickname, true);
    await handleReconnection(ws);

    // Save device info (fire-and-forget)
    const regDeviceInfo = data.deviceInfo || {};
    regDeviceInfo.lastIp = ws.clientIp;
    updateDeviceInfo(ws.nickname, regDeviceInfo);
  } catch (err) {
    console.error('Social register error:', err);
    sendTo(ws, { type: 'login_error', message: '소셜 회원가입에 실패했습니다' });
  }
}

async function handleSocialLink(ws, data) {
  if (!ws.userId) {
    sendTo(ws, { type: 'social_link_result', success: false, message: '로그인이 필요합니다' });
    return;
  }
  const { provider, token } = data;
  if (!provider || !token) {
    sendTo(ws, { type: 'social_link_result', success: false, message: '잘못된 요청입니다' });
    return;
  }

  try {
    let verified;
    if (provider === 'kakao') {
      verified = await verifyKakaoToken(token);
    } else {
      verified = await verifyFirebaseToken(token);
    }

    const result = await linkSocial(ws.userId, provider, verified.uid, verified.email);
    sendTo(ws, { type: 'social_link_result', success: result.success, message: result.message, provider: result.provider });
  } catch (err) {
    console.error('Social link error:', err);
    sendTo(ws, { type: 'social_link_result', success: false, message: '소셜 연동에 실패했습니다' });
  }
}

async function handleSocialUnlink(ws) {
  if (!ws.userId) {
    sendTo(ws, { type: 'social_unlink_result', success: false, message: '로그인이 필요합니다' });
    return;
  }

  try {
    const result = await unlinkSocial(ws.userId);
    sendTo(ws, { type: 'social_unlink_result', success: result.success, message: result.message });
  } catch (err) {
    console.error('Social unlink error:', err);
    sendTo(ws, { type: 'social_unlink_result', success: false, message: '연동 해제에 실패했습니다' });
  }
}

async function handleGetLinkedSocial(ws) {
  if (!ws.userId) {
    sendTo(ws, { type: 'linked_social_info', provider: 'local', email: null });
    return;
  }

  try {
    const result = await getLinkedSocial(ws.userId);
    sendTo(ws, { type: 'linked_social_info', provider: result.provider, email: result.email });
  } catch (err) {
    console.error('Get linked social error:', err);
    sendTo(ws, { type: 'linked_social_info', provider: 'local', email: null });
  }
}

async function handleReconnection(ws) {
  // Fetch user profile to get equipped theme and title
  const profile = await getUserProfile(ws.nickname);
  const themeKey = profile?.themeKey || null;
  const titleKey = profile?.titleKey || null;
  const hasTopCardCounter = profile?.hasTopCardCounter || false;
  ws.titleKey = titleKey;

  const socialInfo = await getLinkedSocial(ws.userId);
  const authProvider = socialInfo?.provider || 'local';

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
          themeKey,
          titleKey,
          hasTopCardCounter,
          authProvider,
          maintenanceStatus: getMaintenanceStatus(),
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

  // Check if player was in a waiting room (no game, disconnected)
  for (const [roomId, room] of lobby.rooms) {
    if (room && !room.game) {
      const player = room.players.find(p => p !== null && p.nickname === ws.nickname && p.connected === false);
      if (player) {
        // Cancel removal timer
        const timerKey = `${roomId}_${player.id}`;
        if (waitingRoomTimers[timerKey]) {
          clearTimeout(waitingRoomTimers[timerKey]);
          delete waitingRoomTimers[timerKey];
        }
        // Reconnect: update player ID and mark connected
        const oldId = player.id;
        player.id = ws.playerId;
        player.connected = true;
        ws.roomId = room.id;

        sendTo(ws, {
          type: 'login_success',
          playerId: ws.playerId,
          nickname: ws.nickname,
          themeKey,
          titleKey,
          hasTopCardCounter,
          authProvider,
          maintenanceStatus: getMaintenanceStatus(),
        });
        sendTo(ws, {
          type: 'room_joined',
          roomId: room.id,
          roomName: room.name,
        });
        broadcastRoomState(room.id);
        broadcastRoomList();
        return;
      }
    }
  }

  sendTo(ws, {
    type: 'login_success',
    playerId: ws.playerId,
    nickname: ws.nickname,
    themeKey,
    titleKey,
    hasTopCardCounter,
    authProvider,
    maintenanceStatus: getMaintenanceStatus(),
  });
  sendTo(ws, { type: 'room_list', rooms: lobby.getRoomList() });
}

function handleCreateRoom(ws, data) {
  if (!ws.playerId) {
    sendTo(ws, { type: 'error', message: '로그인이 필요합니다' });
    return;
  }
  if (ws.roomId) {
    sendTo(ws, { type: 'error', message: '이미 방에 참가 중입니다' });
    return;
  }
  const roomName = (data.roomName || `${ws.nickname}'s Room`).trim();
  const isRanked = !!data.isRanked;
  const password = isRanked
    ? ''
    : (typeof data.password === 'string' ? data.password.trim() : '');
  const turnTimeLimit = Math.min(Math.max(parseInt(data.turnTimeLimit) || 30, 10), 300);
  const room = lobby.createRoom(
    roomName,
    ws.playerId,
    ws.nickname,
    password,
    isRanked,
    turnTimeLimit
  );
  ws.roomId = room.id;
  // Set title on host player
  if (ws.titleKey) {
    room.players[0].titleKey = ws.titleKey;
  }

  sendTo(ws, { type: 'room_joined', roomId: room.id, roomName: room.name });
  broadcastRoomState(room.id);
  broadcastRoomList();
}

async function handleJoinRoom(ws, data) {
  if (!ws.playerId) {
    sendTo(ws, { type: 'error', message: '로그인이 필요합니다' });
    return;
  }
  if (ws.roomId) {
    sendTo(ws, { type: 'error', message: '이미 방에 참가 중입니다' });
    return;
  }
  const room = lobby.getRoom(data.roomId);
  if (!room) {
    sendTo(ws, { type: 'error', message: '방을 찾을 수 없습니다' });
    return;
  }
  // Ranked ban check
  if (room.isRanked && ws.nickname) {
    const banMinutes = await getRankedBan(ws.nickname);
    if (banMinutes) {
      sendTo(ws, { type: 'error', message: `탈주로 인해 ${banMinutes}분 동안 랭킹전이 제한됩니다` });
      return;
    }
  }
  const password = typeof data.password === 'string' ? data.password.trim() : '';
  const result = room.addPlayer(ws.playerId, ws.nickname, password);
  if (!result.success) {
    sendTo(ws, { type: 'error', message: result.message });
    return;
  }
  ws.roomId = room.id;
  // Set title on joined player
  if (ws.titleKey) {
    const p = room.players.find(p => p !== null && p.id === ws.playerId);
    if (p) p.titleKey = ws.titleKey;
  }
  sendTo(ws, { type: 'room_joined', roomId: room.id, roomName: room.name });
  // 채팅 히스토리 전송
  sendTo(ws, { type: 'chat_history', messages: room.getChatHistory() });
  broadcastRoomState(room.id);
  broadcastRoomList();
}

async function handleLeaveRoom(ws) {
  if (!ws.roomId) {
    // Server may have restarted - client thinks it's in a room but server doesn't know
    sendTo(ws, { type: 'room_left' });
    return;
  }
  // S17: Only clear turn timer for players, not spectators
  if (!ws.isSpectator) {
    clearTurnTimer(ws.roomId);
  }
  const room = lobby.getRoom(ws.roomId);
  const roomId = ws.roomId;
  const wasSpectating = ws.isSpectator;
  ws.roomId = null;
  ws.isSpectator = false;
  if (room) {
    if (wasSpectating) {
      room.removeSpectator(ws.playerId);
      if (room.game) _broadcastState(roomId, room);
      broadcastRoomState(roomId);
    } else {
      // S6: If game is active and not already deserted, treat as desertion
      if (room.game && room.game.state !== 'game_end' && !room.game.deserted) {
        await handleDesertion(roomId, ws.playerId);
      }
      room.removePlayer(ws.playerId);
      if (room.getHumanPlayerCount() === 0) {
        removeRoomAndNotifySpectators(roomId);
      } else {
        broadcastRoomState(roomId);
      }
    }
  }
  sendTo(ws, { type: 'room_left' });
  broadcastRoomList();
}

async function handleLeaveGame(ws) {
  if (!ws.roomId) {
    sendTo(ws, { type: 'room_left' });
    return;
  }
  clearTurnTimer(ws.roomId);
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

  // S6: If game is active (not ended) and not already deserted, treat as desertion
  if (room.game && room.game.state !== 'game_end' && !room.game.deserted) {
    await handleDesertion(roomId, ws.playerId);
    // handleDesertion already removes player and cleans up room
    sendTo(ws, { type: 'room_left' });
    return;
  }

  // Remove player from room
  room.removePlayer(ws.playerId);
  ws.roomId = null;

  if (room.getHumanPlayerCount() === 0) {
    removeRoomAndNotifySpectators(roomId);
  } else {
    broadcastRoomState(roomId);
  }

  sendTo(ws, { type: 'room_left' });
  broadcastRoomList();
}

function handleReturnToRoom(ws) {
  if (!ws.roomId) {
    sendTo(ws, { type: 'error', message: '방에 참가하고 있지 않습니다' });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room) {
    ws.roomId = null;
    sendTo(ws, { type: 'room_closed' });
    return;
  }
  // Only host can return to room (S1)
  if (room.hostId !== ws.playerId) {
    sendTo(ws, { type: 'error', message: '방장만 대기실로 돌아갈 수 있습니다' });
    return;
  }
  // Only allow when game has ended
  if (room.game && room.game.state !== 'game_end') {
    sendTo(ws, { type: 'error', message: '게임이 아직 진행 중입니다' });
    return;
  }
  // Clear the game and reset ready states
  room.game = null;
  room.resetReady();
  clearTurnTimer(ws.roomId);
  broadcastRoomState(ws.roomId);
  broadcastRoomList();
}

function handleCheckRoom(ws) {
  if (!ws.roomId) {
    sendTo(ws, { type: 'room_closed' });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room) {
    ws.roomId = null;
    sendTo(ws, { type: 'room_closed' });
    return;
  }
  // Room exists - send current state
  sendTo(ws, { type: 'room_state', room: room.getState() });
  // S27: Also send game state if game is active
  if (room.game) {
    const state = room.game.getStateForPlayer(ws.playerId);
    state.turnDeadline = room.turnDeadline;
    state.cardViewers = room.getViewersForPlayer(ws.playerId);
    state.spectators = room.spectators.map((s) => ({ id: s.id, nickname: s.nickname }));
    state.spectatorCount = room.spectators.length;
    sendTo(ws, { type: 'game_state', state });
  }
}

function handleSpectateRoom(ws, data) {
  if (!ws.playerId) {
    sendTo(ws, { type: 'error', message: '로그인이 필요합니다' });
    return;
  }
  if (ws.roomId) {
    sendTo(ws, { type: 'error', message: '이미 방에 참가 중입니다' });
    return;
  }
  const room = lobby.getRoom(data.roomId);
  if (!room) {
    sendTo(ws, { type: 'error', message: '방을 찾을 수 없습니다' });
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
  // Send chat history to spectator
  sendTo(ws, { type: 'chat_history', messages: room.getChatHistory() });
  // Update room state/list for everyone
  broadcastRoomState(room.id);
  broadcastRoomList();

  if (room.game) {
    // Send current game state if game is in progress (without card permissions initially)
    const permittedPlayers = room.getPermittedPlayers(ws.playerId);
    const state = room.game.getStateForSpectator(permittedPlayers);
    state.spectators = room.spectators.map((s) => ({ id: s.id, nickname: s.nickname }));
    state.spectatorCount = room.spectators.length;
    sendTo(ws, { type: 'spectator_game_state', state });
  } else {
    // Send waiting room state
    sendTo(ws, { type: 'room_state', room: room.getState() });
  }
}

function handleRequestCardView(ws, data) {
  if (!ws.roomId || !ws.isSpectator) {
    sendTo(ws, { type: 'error', message: '관전 중이 아닙니다' });
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

  // If target is a bot, auto-approve immediately
  if (room.isBot(playerId)) {
    room.respondCardViewRequest(playerId, ws.playerId, true);
    const botPlayer = room.players.find(p => p !== null && p.id === playerId);
    sendTo(ws, {
      type: 'card_view_response',
      playerId: playerId,
      playerNickname: botPlayer ? botPlayer.nickname : '',
      allowed: true,
    });
    if (room.game) {
      const permittedPlayers = room.getPermittedPlayers(ws.playerId);
      const state = room.game.getStateForSpectator(permittedPlayers);
      state.spectators = room.spectators.map((s) => ({ id: s.id, nickname: s.nickname }));
      state.spectatorCount = room.spectators.length;
      sendTo(ws, { type: 'spectator_game_state', state });
    }
    return;
  }

  // Notify the human player about the request
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
    sendTo(ws, { type: 'error', message: '방에 참가하고 있지 않습니다' });
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
      state.spectators = room.spectators.map((s) => ({ id: s.id, nickname: s.nickname }));
      state.spectatorCount = room.spectators.length;
      sendTo(spectatorWs, { type: 'spectator_game_state', state });
    }
  }

  // Send updated game state to the approving player so cardViewers refreshes immediately
  if (allow && room.game) {
    const playerState = room.game.getStateForPlayer(ws.playerId);
    playerState.turnDeadline = room.turnDeadline;
    playerState.cardViewers = room.getViewersForPlayer(ws.playerId);
    playerState.spectators = room.spectators.map((s) => ({ id: s.id, nickname: s.nickname }));
    playerState.spectatorCount = room.spectators.length;
    sendTo(ws, { type: 'game_state', state: playerState });
  }
}

function handleRevokeCardView(ws, data) {
  if (!ws.roomId) {
    sendTo(ws, { type: 'error', message: '방에 참가하고 있지 않습니다' });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room) return;

  const spectatorId = data.spectatorId;
  const result = room.revokeCardView(ws.playerId, spectatorId);
  if (!result.success) {
    sendTo(ws, { type: 'error', message: '취소에 실패했습니다' });
    return;
  }

  // Send updated spectator game state (cards no longer visible)
  const spectatorWs = findWsByPlayerId(spectatorId);
  if (spectatorWs && room.game) {
    const permittedPlayers = room.getPermittedPlayers(spectatorId);
    const state = room.game.getStateForSpectator(permittedPlayers);
    state.spectators = room.spectators.map((s) => ({ id: s.id, nickname: s.nickname }));
    state.spectatorCount = room.spectators.length;
    sendTo(spectatorWs, { type: 'spectator_game_state', state });
  }

  // Send updated game state to the player (cardViewers refreshed)
  sendGameStateToAll(ws.roomId);
}

function handleToggleReady(ws) {
  if (!ws.roomId) return;
  const room = lobby.getRoom(ws.roomId);
  if (!room) { sendTo(ws, { type: 'room_closed' }); ws.roomId = null; return; }
  if (room.hostId === ws.playerId) return; // host doesn't ready
  if (room.game) return; // game already started
  room.toggleReady(ws.playerId);
  broadcastRoomState(ws.roomId);
}

function handleStartGame(ws) {
  if (!ws.roomId) {
    sendTo(ws, { type: 'error', message: '방에 참가하고 있지 않습니다' });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room) { sendTo(ws, { type: 'room_closed' }); ws.roomId = null; return; }
  if (room.hostId !== ws.playerId) {
    sendTo(ws, { type: 'error', message: '방장만 게임을 시작할 수 있습니다' });
    return;
  }
  if (room.getPlayerCount() < 4) {
    sendTo(ws, { type: 'error', message: '4명이 모여야 시작할 수 있습니다' });
    return;
  }
  if (!room.areAllReady()) {
    sendTo(ws, { type: 'error', message: '모든 플레이어가 준비해야 합니다' });
    return;
  }
  room.resetReady();
  room.startGame();
  broadcastRoomState(ws.roomId);
  // Send initial cards to each player
  sendGameStateToAll(ws.roomId);
}

function handleChangeRoomName(ws, data) {
  if (!ws.roomId) {
    sendTo(ws, { type: 'error', message: '방에 참가하고 있지 않습니다' });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room) {
    sendTo(ws, { type: 'error', message: '방을 찾을 수 없습니다' });
    return;
  }
  if (room.hostId !== ws.playerId) {
    sendTo(ws, { type: 'error', message: '방장만 변경할 수 있습니다' });
    return;
  }
  const rawName = typeof data.roomName === 'string' ? data.roomName.trim() : '';
  if (!rawName) {
    sendTo(ws, { type: 'error', message: '방 제목을 입력해주세요' });
    return;
  }
  const newName = rawName.slice(0, 20);
  room.setName(newName);
  broadcastRoomState(room.id);
  broadcastRoomList();
}

function handleChangeTeam(ws, data) {
  if (!ws.roomId) {
    sendTo(ws, { type: 'error', message: '방에 참가하고 있지 않습니다' });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room) { sendTo(ws, { type: 'room_closed' }); ws.roomId = null; return; }
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
    sendTo(ws, { type: 'error', message: '잘못된 슬롯입니다' });
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
    sendTo(ws, { type: 'error', message: '방에 참가하고 있지 않습니다' });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room) { sendTo(ws, { type: 'room_closed' }); ws.roomId = null; return; }
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

// Add bot handler (host only)
function handleAddBot(ws, data) {
  if (!ws.roomId) {
    sendTo(ws, { type: 'error', message: '방에 참가하고 있지 않습니다' });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room) { sendTo(ws, { type: 'room_closed' }); ws.roomId = null; return; }
  if (room.hostId !== ws.playerId) {
    sendTo(ws, { type: 'error', message: '방장만 봇을 추가할 수 있습니다' });
    return;
  }
  // TODO: 테스트 후 복구 - 랭크전 봇 제한
  if (room.isRanked) {
    sendTo(ws, { type: 'error', message: '랭크전에서는 봇을 추가할 수 없습니다' });
    return;
  }
  const targetSlot = typeof data.targetSlot === 'number' ? data.targetSlot : undefined;
  const result = room.addBot(targetSlot);
  if (!result.success) {
    sendTo(ws, { type: 'error', message: result.message });
    return;
  }
  broadcastRoomState(ws.roomId);
  broadcastRoomList();
}

// Switch to spectator handler
function handleSwitchToSpectator(ws) {
  if (!ws.roomId || ws.isSpectator) {
    sendTo(ws, { type: 'error', message: '플레이어로 방에 참가하고 있지 않습니다' });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room) { sendTo(ws, { type: 'room_closed' }); ws.roomId = null; return; }
  const result = room.switchToSpectator(ws.playerId);
  if (!result.success) {
    sendTo(ws, { type: 'error', message: result.message });
    return;
  }
  ws.isSpectator = true;
  sendTo(ws, { type: 'switched_to_spectator' });
  broadcastRoomState(ws.roomId);
  broadcastRoomList();
}

// Switch to player handler
function handleSwitchToPlayer(ws, data) {
  if (!ws.roomId || !ws.isSpectator) {
    sendTo(ws, { type: 'error', message: '관전 중이 아닙니다' });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room) { sendTo(ws, { type: 'room_closed' }); ws.roomId = null; return; }
  const targetSlot = data.targetSlot;
  if (typeof targetSlot !== 'number') {
    sendTo(ws, { type: 'error', message: '잘못된 슬롯입니다' });
    return;
  }
  const result = room.switchToPlayer(ws.playerId, ws.nickname, targetSlot);
  if (!result.success) {
    sendTo(ws, { type: 'error', message: result.message });
    return;
  }
  ws.isSpectator = false;
  // Set title on player slot
  if (ws.titleKey) {
    const p = room.players[targetSlot];
    if (p) p.titleKey = ws.titleKey;
  }
  sendTo(ws, { type: 'switched_to_player', roomId: room.id, roomName: room.name });
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
    sendTo(ws, { type: 'error', message: '방에 참가하고 있지 않습니다' });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room || !room.game) {
    sendTo(ws, { type: 'room_closed' });
    ws.roomId = null;
    return;
  }

  // S7: Only clear turn timer for actions that affect turn progression
  // Don't clear for phase-wide actions (large tichu / exchange) or small tichu declaration
  const phaseActions = ['pass_large_tichu', 'declare_large_tichu', 'exchange_cards', 'declare_small_tichu'];
  if (!phaseActions.includes(data.type)) {
    clearTurnTimer(ws.roomId);
  }

  if (data.type === 'next_round') {
    if (room.hostId !== ws.playerId) {
      sendTo(ws, { type: 'error', message: '방장만 다음 라운드를 시작할 수 있습니다' });
      return;
    }
    // Reset timeout counts for new round (keys are nicknames)
    if (timeoutCounts[ws.roomId]) {
      for (const key in timeoutCounts[ws.roomId]) {
        timeoutCounts[ws.roomId][key] = 0;
      }
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
  if (room.game.resultSaved) return;
  room.game.resultSaved = true;
  clearTurnTimer(room.id);
  if (roundEndTimers[room.id]) {
    clearTimeout(roundEndTimers[room.id]);
    delete roundEndTimers[room.id];
  }
  delete timeoutCounts[room.id];
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

    // Update stats for each player (skip bots)
    for (const pid of teamAPlayers) {
      if (pid.startsWith('bot_')) continue;
      const nick = playerNames[pid];
      if (nick) await updateUserStats(nick, winnerTeam === 'A', room.isRanked);
    }
    for (const pid of teamBPlayers) {
      if (pid.startsWith('bot_')) continue;
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

  // Auto next round after 3 seconds
  if (room.game.state === 'round_end') {
    if (roundEndTimers[roomId]) clearTimeout(roundEndTimers[roomId]);
    roundEndTimers[roomId] = setTimeout(() => {
      delete roundEndTimers[roomId];
      const r = lobby.getRoom(roomId);
      if (!r || !r.game || r.game.state !== 'round_end') return;
      r.game.nextRound();
      sendGameStateToAll(roomId);
    }, 3000);
    // Send state without timer for round_end
    _broadcastState(roomId, room);
    return;
  }

  // Set timer BEFORE sending state so turnDeadline is included
  scheduleBotActions(roomId);
  startTurnTimer(roomId);

  _broadcastState(roomId, room);
}

function _broadcastState(roomId, room) {
  // Build connection status map (skip null slots)
  const connectionStatus = {};
  for (const player of room.players) {
    if (player === null) continue;
    connectionStatus[player.id] = player.connected !== false;
  }

  const spectatorList = room.spectators.map((s) => ({ id: s.id, nickname: s.nickname }));

  // Build timeout count map by player name
  const roomTimeouts = timeoutCounts[roomId] || {};

  // Send to human players (skip null slots and bots)
  for (const player of room.players) {
    if (player === null) continue;
    if (player.connected === false) continue;
    if (room.isBot(player.id)) continue;
    const ws = findWsByPlayerId(player.id);
    if (ws) {
      const state = room.game.getStateForPlayer(player.id);
      state.players = state.players.map(p => ({
        ...p,
        connected: connectionStatus[p.id] !== false,
        timeoutCount: roomTimeouts[p.name] || 0,
      }));
      state.turnDeadline = room.turnDeadline;
      state.cardViewers = room.getViewersForPlayer(player.id);
      state.spectators = spectatorList;
      state.spectatorCount = spectatorList.length;
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
      spectatorState.players = spectatorState.players.map(p => ({
        ...p,
        connected: connectionStatus[p.id] !== false,
        timeoutCount: roomTimeouts[p.name] || 0,
      }));
      spectatorState.turnDeadline = room.turnDeadline;
      spectatorState.spectators = spectatorList;
      spectatorState.spectatorCount = spectatorList.length;
      sendTo(ws, { type: 'spectator_game_state', state: spectatorState });
    }
  }
}

// Bot auto-response: schedule a single delayed bot action check
let pendingBotCheck = {}; // roomId -> true (prevent duplicate scheduling)

function scheduleBotActions(roomId) {
  const room = lobby.getRoom(roomId);
  if (!room || !room.game) return;
  if (room.getBotIds().length === 0) return;
  if (pendingBotCheck[roomId]) return; // Already scheduled

  pendingBotCheck[roomId] = true;
  const delay = 300 + Math.floor(Math.random() * 500);

  setTimeout(() => {
    delete pendingBotCheck[roomId];
    const r = lobby.getRoom(roomId);
    if (!r || !r.game) return;

    // Re-evaluate at execution time
    for (const botId of r.getBotIds()) {
      let action = decideBotAction(r.game, botId);
      if (action) {
        console.log(`[BOT] ${botId} action: ${action.type}`);
        let result = r.game.handleAction(botId, action);
        // If bot's action failed (e.g. call obligation), use server's auto-action as fallback
        if (result && !result.success && r.game) {
          console.log(`[BOT] ${botId} action failed: ${result.message}, trying fallback`);
          const fallback = r.game.getAutoTimeoutAction(botId);
          if (fallback) {
            console.log(`[BOT] ${botId} fallback: ${fallback.type}`);
            result = r.game.handleAction(botId, fallback);
          }
        }
        if (result && result.success) {
          if (result.broadcast) {
            broadcastGameEvent(roomId, result.broadcast);
          }
          if (r.game && r.game.state === 'game_end') {
            saveGameResult(r);
          }
          sendGameStateToAll(roomId); // This will re-trigger scheduleBotActions
          return; // One action at a time
        } else {
          // S11: Don't return on failure - let other bots try
          console.log(`[BOT] ${botId} action failed: ${result?.message}`);
        }
      }
    }
  }, delay);
}

// --- Turn Timer System ---

function startTurnTimer(roomId) {
  const room = lobby.getRoom(roomId);
  if (!room || !room.game) return;

  const gameState = room.game.state;

  if (gameState === 'large_tichu_phase') {
    // Skip if phase timer already running for this phase
    if (turnTimerPhases[roomId] === 'large_tichu_phase') return;
    clearTurnTimer(roomId);
    // 라지 티츄 선언: 2배 시간, 응답 안 한 사람 대상
    const pending = room.game.playerIds.filter(
      pid => room.game.largeTichuResponses[pid] === undefined && !room.isBot(pid)
    );
    if (pending.length === 0) return;
    const timeLimit = room.turnTimeLimit * 2 * 1000;
    room.turnDeadline = Date.now() + timeLimit;
    turnTimerPhases[roomId] = 'large_tichu_phase';
    turnTimers[roomId] = setTimeout(() => {
      handlePhaseTimeout(roomId, 'large_tichu_phase');
    }, timeLimit);
    return;
  }

  if (gameState === 'card_exchange') {
    // Skip if phase timer already running for this phase
    if (turnTimerPhases[roomId] === 'card_exchange') return;
    clearTurnTimer(roomId);
    // 카드 교환: 2배 시간, 교환 안 한 사람 대상
    const pending = room.game.playerIds.filter(
      pid => !room.game.exchangeDone[pid] && !room.isBot(pid)
    );
    if (pending.length === 0) return;
    const timeLimit = room.turnTimeLimit * 2 * 1000;
    room.turnDeadline = Date.now() + timeLimit;
    turnTimerPhases[roomId] = 'card_exchange';
    turnTimers[roomId] = setTimeout(() => {
      handlePhaseTimeout(roomId, 'card_exchange');
    }, timeLimit);
    return;
  }

  if (gameState !== 'playing') {
    clearTurnTimer(roomId);
    return;
  }

  // If a turn timer is already running, keep the existing deadline
  if (turnTimers[roomId]) return;

  // Determine who needs to act
  let targetPlayer = room.game.currentPlayer;
  if (room.game.needsToCallRank) {
    targetPlayer = room.game.needsToCallRank;
  } else if (room.game.dragonPending) {
    targetPlayer = room.game.dragonDecider;
  }
  if (!targetPlayer) return;
  if (room.isBot(targetPlayer)) return; // Bots don't need timers

  const timeLimit = room.turnTimeLimit * 1000;
  room.turnDeadline = Date.now() + timeLimit;

  turnTimers[roomId] = setTimeout(() => {
    handleTurnTimeout(roomId, targetPlayer);
  }, timeLimit);
}

function clearTurnTimer(roomId) {
  if (turnTimers[roomId]) {
    clearTimeout(turnTimers[roomId]);
    delete turnTimers[roomId];
  }
  delete turnTimerPhases[roomId];
  const room = lobby.getRoom(roomId);
  if (room) room.turnDeadline = null;
}

function handlePhaseTimeout(roomId, phase) {
  clearTurnTimer(roomId);
  const room = lobby.getRoom(roomId);
  if (!room || !room.game) return;

  if (phase === 'large_tichu_phase' && room.game.state === 'large_tichu_phase') {
    // 응답 안 한 플레이어 전부 자동 패스
    const pending = room.game.playerIds.filter(
      pid => room.game.largeTichuResponses[pid] === undefined
    );
    for (const pid of pending) {
      const result = room.game.handleAction(pid, { type: 'pass_large_tichu' });
      if (result && result.broadcast) {
        broadcastGameEvent(roomId, result.broadcast);
      }
    }
    sendGameStateToAll(roomId);
    return;
  }

  if (phase === 'card_exchange' && room.game.state === 'card_exchange') {
    // 교환 안 한 플레이어: 손패에서 처음 3장 자동 교환
    const pending = room.game.playerIds.filter(
      pid => !room.game.exchangeDone[pid]
    );
    for (const pid of pending) {
      const hand = room.game.hands[pid];
      const cards = { left: hand[0], partner: hand[1], right: hand[2] };
      room.game.handleAction(pid, { type: 'exchange_cards', cards });
    }
    sendGameStateToAll(roomId);
    return;
  }
}

async function handleTurnTimeout(roomId, playerId) {
  clearTurnTimer(roomId);
  const room = lobby.getRoom(roomId);
  if (!room || !room.game) return;

  // Use nickname as key so timeout count persists across reconnections
  const nickname = room.game.playerNames[playerId] || playerId;

  // Increment timeout count
  if (!timeoutCounts[roomId]) timeoutCounts[roomId] = {};
  if (!timeoutCounts[roomId][nickname]) timeoutCounts[roomId][nickname] = 0;
  timeoutCounts[roomId][nickname]++;

  console.log(`[TIMEOUT] ${nickname} (${playerId}) timeout #${timeoutCounts[roomId][nickname]}`);

  // 3 timeouts → desertion (S2: await async handleDesertion)
  if (timeoutCounts[roomId][nickname] >= 3) {
    await handleDesertion(roomId, playerId, 'timeout');
    return;
  }

  // Broadcast timeout event
  broadcastGameEvent(roomId, {
    type: 'turn_timeout',
    player: playerId,
    playerName: nickname,
    count: timeoutCounts[roomId][nickname],
  });

  // Auto action
  const action = room.game.getAutoTimeoutAction(playerId);
  if (action) {
    const result = room.game.handleAction(playerId, action);
    if (result && result.success) {
      if (result.broadcast) broadcastGameEvent(roomId, result.broadcast);
      if (room.game && room.game.state === 'game_end') saveGameResult(room);
      sendGameStateToAll(roomId);
    }
  }
}

function handleResetTimeout(ws) {
  if (!ws.roomId || !ws.nickname) return;
  const roomId = ws.roomId;
  if (!timeoutCounts[roomId]) return;
  const nickname = ws.nickname;
  if (!timeoutCounts[roomId][nickname] || timeoutCounts[roomId][nickname] === 0) return;
  timeoutCounts[roomId][nickname] = 0;
  console.log(`[TIMEOUT] ${nickname} reset timeout count`);
  sendTo(ws, { type: 'timeout_reset', count: 0 });
}

async function handleDesertion(roomId, playerId, reason = 'leave') {
  const room = lobby.getRoom(roomId);
  if (!room || !room.game) return;

  const game = room.game;
  const deserterNick = game.playerNames[playerId];

  // Broadcast desertion event
  broadcastGameEvent(roomId, {
    type: 'player_deserted',
    player: playerId,
    playerName: deserterNick,
    reason, // 'leave' or 'timeout'
  });

  // Increment leave_count + ranked ban (skip bots)
  if (deserterNick && !playerId.startsWith('bot_')) {
    await incrementLeaveCount(deserterNick);
    if (room.isRanked) {
      await setRankedBan(deserterNick);
    }
  }

  const totalScores = game.totalScores;
  const teams = game.teams;
  const playerNames = game.playerNames;
  const teamAPlayers = teams.teamA;
  const teamBPlayers = teams.teamB;

  // Desertion = draw for remaining players, loss for deserter
  const winnerTeam = 'draw';

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

    // Deserter: forced loss (ranked = -20 penalty)
    if (deserterNick && !playerId.startsWith('bot_')) {
      await updateUserStats(deserterNick, false, room.isRanked);
    }

    // Remaining players: no stat change (draw)

  } catch (err) {
    console.error('Error saving desertion result:', err);
  }

  // Force game end
  game.state = 'game_end';
  game.deserted = true;

  sendGameStateToAll(roomId);
  delete timeoutCounts[roomId];

  // Remove deserter from room (including host)
  if (deserterNick) {
    playerSessions.delete(deserterNick);
  }
  const deserterWs = findWsByPlayerId(playerId);
  if (deserterWs) {
    sendTo(deserterWs, { type: 'kicked', message: '시간 초과 3회로 퇴장되었습니다' });
    deserterWs.roomId = null;
  }
  room.removePlayer(playerId);

  // Clean up game so room shows as not in game
  room.game = null;
  room.resetReady();
  clearTurnTimer(roomId);

  if (room.getHumanPlayerCount() === 0) {
    removeRoomAndNotifySpectators(roomId);
  } else {
    broadcastRoomState(roomId);
  }
  broadcastRoomList();
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
  // Send to spectators
  for (const spectator of room.spectators) {
    const ws = findWsByPlayerId(spectator.id);
    if (ws) {
      sendTo(ws, { type: 'room_state', room: roomState });
    }
  }
}

// Notify all spectators and remove room
function removeRoomAndNotifySpectators(roomId) {
  const room = lobby.getRoom(roomId);
  if (room) {
    for (const spectator of room.spectators) {
      const ws = findWsByPlayerId(spectator.id);
      if (ws) {
        sendTo(ws, { type: 'room_closed' });
        ws.roomId = null;
        ws.isSpectator = false;
      }
    }
  }
  lobby.removeRoom(roomId);
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
async function handleChatMessage(ws, data) {
  if (!ws.roomId || !ws.nickname) {
    sendTo(ws, { type: 'error', message: '방에 참가하고 있지 않습니다' });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room) return;

  const message = (data.message || '').trim();
  if (!message || message.length > 200) return;

  // Check chat ban
  const chatBanMinutes = await getChatBan(ws.nickname);
  if (chatBanMinutes) {
    sendTo(ws, { type: 'chat_banned', remainingMinutes: chatBanMinutes });
    return;
  }

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

// Rankings handler
async function handleGetRankings(ws, data) {
  const seasonId = data?.seasonId;
  if (seasonId) {
    const result = await getSeasonRankings(seasonId, 50);
    sendTo(ws, { type: 'rankings_result', ...result });
    return;
  }
  const result = await getCurrentSeasonRankings(50);
  sendTo(ws, { type: 'rankings_result', ...result });
}

async function handleGetSeasons(ws) {
  const result = await getSeasons();
  sendTo(ws, { type: 'seasons_result', ...result });
}

// Wallet handler
async function handleGetWallet(ws) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'wallet_result', success: false, message: '로그인이 필요합니다' });
    return;
  }
  const result = await getWallet(ws.nickname);
  sendTo(ws, { type: 'wallet_result', ...result });
}

// Shop items handler
async function handleGetShopItems(ws) {
  const result = await getShopItems();
  sendTo(ws, { type: 'shop_items_result', ...result });
}

// Inventory handler
async function handleGetInventory(ws) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'inventory_result', success: false, message: '로그인이 필요합니다' });
    return;
  }
  const result = await getUserItems(ws.nickname);
  sendTo(ws, { type: 'inventory_result', ...result });
}

async function handleBuyItem(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'purchase_result', success: false, message: '로그인이 필요합니다' });
    return;
  }
  const itemKey = data.itemKey;
  const result = await buyItem(ws.nickname, itemKey);
  sendTo(ws, { type: 'purchase_result', itemKey, ...result });
}

async function handleEquipItem(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'equip_result', success: false, message: '로그인이 필요합니다' });
    return;
  }
  const itemKey = data.itemKey;
  const result = await equipItem(ws.nickname, itemKey);
  if (result.success && result.category === 'theme') {
    result.themeKey = itemKey;
  }
  if (result.success && result.category === 'title') {
    result.titleKey = itemKey;
    ws.titleKey = itemKey;
    // Update room player data if in a room
    if (ws.roomId) {
      const room = lobby.getRoom(ws.roomId);
      if (room) {
        const p = room.players.find(p => p !== null && p.id === ws.playerId);
        if (p) p.titleKey = itemKey;
        broadcastRoomState(ws.roomId);
      }
    }
  }
  sendTo(ws, { type: 'equip_result', ...result });
}

async function handleUseItem(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'use_item_result', success: false, message: '로그인이 필요합니다' });
    return;
  }
  const itemKey = data.itemKey;
  const result = await useItem(ws.nickname, itemKey);
  sendTo(ws, { type: 'use_item_result', ...result });
}

async function handleChangeNickname(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'change_nickname_result', success: false, message: '로그인이 필요합니다' });
    return;
  }
  if (ws.roomId) {
    sendTo(ws, { type: 'change_nickname_result', success: false, message: '게임 중에는 닉네임을 변경할 수 없습니다' });
    return;
  }
  const result = await changeNickname(ws.nickname, data.newNickname);
  if (result.success) {
    ws.nickname = result.newNickname;
  }
  sendTo(ws, { type: 'change_nickname_result', ...result });
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

async function handleGetInquiries(ws) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'inquiries_result', success: false, message: '로그인이 필요합니다', inquiries: [] });
    return;
  }
  const result = await getUserInquiries(ws.nickname);
  sendTo(ws, { type: 'inquiries_result', ...result });
}

async function handleMarkInquiriesRead(ws) {
  if (!ws.nickname) return;
  await markInquiriesRead(ws.nickname);
  const result = await getUserInquiries(ws.nickname);
  sendTo(ws, { type: 'inquiries_result', ...result });
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
  // Real-time notification to target
  if (result.success) {
    const targetWs = findWsByNickname(targetNickname);
    if (targetWs) {
      if (result.message === '친구가 되었습니다') {
        // Auto-accepted (they had sent us a request) — notify both
        sendTo(targetWs, { type: 'friend_request_accepted', nickname: ws.nickname });
      } else {
        sendTo(targetWs, { type: 'friend_request_received', fromNickname: ws.nickname });
      }
    }
  }
}

// Get friends handler
async function handleGetFriends(ws) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'friends_list', friends: [] });
    return;
  }
  const friendNicknames = await getFriends(ws.nickname);
  const friends = friendNicknames.map(nick => {
    const friendWs = findWsByNickname(nick);
    const isOnline = !!friendWs;
    let roomId = null;
    let roomName = null;
    if (friendWs && friendWs.roomId) {
      const room = lobby.getRoom(friendWs.roomId);
      if (room) {
        roomId = room.id;
        roomName = room.name;
      }
    }
    let roomPlayerCount = 0;
    let roomInGame = false;
    let roomPassword = '';
    if (friendWs && friendWs.roomId) {
      const r = lobby.getRoom(friendWs.roomId);
      if (r) {
        roomPlayerCount = r.players ? r.players.filter(p => p !== null).length : 0;
        roomInGame = !!(r.game && r.game.state && r.game.state !== 'waiting' && r.game.state !== 'game_end');
        roomPassword = r.password || '';
      }
    }
    return { nickname: nick, isOnline, roomId, roomName, roomPlayerCount, roomInGame, roomPassword };
  });
  sendTo(ws, { type: 'friends_list', friends });
}

// Get pending friend requests handler
async function handleGetPendingFriendRequests(ws) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'pending_friend_requests', requests: [] });
    return;
  }
  const requests = await getPendingFriendRequests(ws.nickname);
  sendTo(ws, { type: 'pending_friend_requests', requests });
}

// Accept friend request handler
async function handleAcceptFriendRequest(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'error', message: '로그인이 필요합니다' });
    return;
  }
  const nickname = data.nickname;
  if (!nickname) return;
  const result = await acceptFriendRequest(ws.nickname, nickname);
  sendTo(ws, { type: 'friend_request_result', action: 'accept', nickname, success: result.success });
  // Notify the requester that their request was accepted
  if (result.success) {
    const requesterWs = findWsByNickname(nickname);
    if (requesterWs) {
      sendTo(requesterWs, { type: 'friend_request_accepted', nickname: ws.nickname });
    }
  }
}

// Reject friend request handler
async function handleRejectFriendRequest(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'error', message: '로그인이 필요합니다' });
    return;
  }
  const nickname = data.nickname;
  if (!nickname) return;
  const result = await rejectFriendRequest(ws.nickname, nickname);
  sendTo(ws, { type: 'friend_request_result', action: 'reject', nickname, success: result.success });
}

// Remove friend handler
async function handleRemoveFriend(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'error', message: '로그인이 필요합니다' });
    return;
  }
  const nickname = data.nickname;
  if (!nickname) return;
  const result = await removeFriend(ws.nickname, nickname);
  sendTo(ws, { type: 'friend_removed', nickname, success: result.success });
  // Notify the other user
  if (result.success) {
    const otherWs = findWsByNickname(nickname);
    if (otherWs) {
      sendTo(otherWs, { type: 'friend_removed', nickname: ws.nickname, success: true });
    }
  }
}

// Invite to room handler
function handleInviteToRoom(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'invite_result', success: false, message: '로그인이 필요합니다' });
    return;
  }
  if (!ws.roomId) {
    sendTo(ws, { type: 'invite_result', success: false, message: '방에 입장한 상태가 아닙니다' });
    return;
  }
  const targetNickname = data.nickname;
  if (!targetNickname) {
    sendTo(ws, { type: 'invite_result', success: false, message: '초대할 대상이 없습니다' });
    return;
  }
  const targetWs = findWsByNickname(targetNickname);
  if (!targetWs) {
    sendTo(ws, { type: 'invite_result', success: false, message: '상대방이 오프라인입니다' });
    return;
  }
  if (targetWs.roomId) {
    sendTo(ws, { type: 'invite_result', success: false, message: '상대방이 이미 방에 있습니다' });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room) {
    sendTo(ws, { type: 'invite_result', success: false, message: '방을 찾을 수 없습니다' });
    return;
  }
  sendTo(targetWs, {
    type: 'room_invite',
    fromNickname: ws.nickname,
    roomId: room.id,
    roomName: room.name,
    isRanked: room.isRanked,
    password: room.password || '',
  });
  sendTo(ws, { type: 'invite_result', success: true, message: '초대를 보냈습니다' });
}

function findWsByPlayerId(playerId) {
  for (const ws of wss.clients) {
    if (ws.playerId === playerId) return ws;
  }
  return null;
}

function findWsByNickname(nickname) {
  for (const ws of wss.clients) {
    if (ws.nickname === nickname && ws.readyState === ws.OPEN) return ws;
  }
  return null;
}

async function notifyFriendsOfStatusChange(nickname, isOnline) {
  const friends = await getFriends(nickname);
  for (const friendNick of friends) {
    const friendWs = findWsByNickname(friendNick);
    if (friendWs) {
      sendTo(friendWs, {
        type: 'friend_status_changed',
        nickname,
        isOnline,
      });
    }
  }
}

function sendTo(ws, data) {
  if (ws.readyState === ws.OPEN) {
    ws.send(JSON.stringify(data));
  }
}
