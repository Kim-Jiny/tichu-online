const { WebSocketServer } = require('ws');
const crypto = require('crypto');
const http = require('http');
const serverStartedAt = new Date().toISOString();
const LobbyManager = require('./lobby/LobbyManager');
const GameRoom = require('./game/GameRoom');
const { decideBotAction } = require('./game/BotPlayer');
const { decideSKBotAction } = require('./game/skull_king/SkullKingBot');
const { decideLLBotAction } = require('./game/love_letter/LoveLetterBot');
const { decideMightyBotAction } = require('./game/mighty/MightyBot');
const {
  initDatabase, registerUser, loginUser, checkNickname, deleteUser,
  blockUser, unblockUser, getBlockedUsers, reportUser,
  addFriend, getFriends, getPendingFriendRequests,
  acceptFriendRequest, rejectFriendRequest, removeFriend,
  saveMatchResult, saveMatchResultWithStats, updateUserStats, getUserProfile, getRecentMatches,
  submitInquiry, getUserInquiries, markInquiriesRead, getRankings,
  getWallet, getGoldHistory, getShopItems, getUserItems, buyItem, equipItem, useItem, changeNickname,
  incrementLeaveCount, setRankedBan, getRankedBan, setChatBan, getChatBan, grantSeasonRewards,
  getActiveSeason, createSeason, getSeasons, getConfig, getLocalizedConfig, updateConfig,
  getCurrentSeasonRankings, getSeasonRankings, resetSeasonStats,
  loginSocial, registerSocial,
  linkSocial, unlinkSocial, getLinkedSocial,
  updateDeviceInfo,
  setPushEnabled,
  setPushFriendInvite,
  setUserAdmin,
  setAdminAlertSettings,
  getAdminPushRecipients,
  claimAdReward,
  searchUsers,
  sendDm,
  getDmHistory,
  markDmRead,
  getDmConversations,
  getTotalUnreadDmCount,
  getInquiries,
  getInquiryById,
  resolveInquiry,
  getReports,
  getReportGroup,
  updateReportGroupStatus,
  getUsers,
  getUserDetail,
  isUserAdmin,
  getDetailedAdminStats,
  saveSKMatchResult, saveSKMatchResultWithStats, saveLLMatchResultWithStats, saveMightyMatchResultWithStats,
  updateSKUserStats,
  getSKRankings,
  getCurrentSKSeasonRankings,
  getSKSeasonRankings,
  getMightyRankings,
  getCurrentMightySeasonRankings,
  getMightySeasonRankings,
  getDashboardStats,
  getAdminGoldHistory,
  adminAdjustGold,
  setAdminMemo,
  getSKRecentMatches,
  getPublishedNotices,
  getBroadcastFcmTokens,
  insertPushHistory,
  getPushHistory,
  clearInvalidFcmToken,
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
  // Only allow unsigned decode in development
  if (process.env.NODE_ENV === 'production') {
    throw new Error('Firebase Admin SDK not configured - social login unavailable');
  }
  // Fallback: decode JWT without signature verification (local dev only)
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

// Broadcast push notification to multiple users (batched)
async function sendBroadcastPush(tokenRows, title, body) {
  if (!firebaseAdmin) return { successCount: 0, failCount: tokenRows.length, invalidUserIds: [], results: tokenRows.map(r => ({ userId: r.id, success: false, invalid: false })), error: 'Firebase not configured' };
  const BATCH_SIZE = 500;
  let successCount = 0;
  let failCount = 0;
  const invalidUserIds = [];
  const results = [];

  for (let i = 0; i < tokenRows.length; i += BATCH_SIZE) {
    const batch = tokenRows.slice(i, i + BATCH_SIZE);
    const tokens = batch.map(r => r.fcm_token);
    try {
      const result = await firebaseAdmin.messaging().sendEachForMulticast({
        tokens,
        notification: { title, body },
      });
      result.responses.forEach((resp, idx) => {
        if (resp.success) {
          successCount++;
          results.push({ userId: batch[idx].id, success: true, invalid: false });
        } else {
          failCount++;
          const code = resp.error?.code;
          const isInvalid = code === 'messaging/registration-token-not-registered' || code === 'messaging/invalid-registration-token';
          if (isInvalid) {
            invalidUserIds.push(batch[idx].id);
          }
          results.push({ userId: batch[idx].id, success: false, invalid: isInvalid });
        }
      });
    } catch (err) {
      console.error('Broadcast push batch error:', err.message);
      failCount += batch.length;
      batch.forEach(r => results.push({ userId: r.id, success: false, invalid: false }));
    }
  }
  return { successCount, failCount, invalidUserIds, results };
}

const { handleAdminRoute } = require('./admin');
const { t } = require('./i18n');

async function sendFriendRequestPush(targetNickname, fromNickname) {
  try {
    const { pool } = require('./db/database');
    const res = await pool.query(
      'SELECT fcm_token, push_enabled, push_friend_invite, locale FROM tc_users WHERE nickname = $1',
      [targetNickname]
    );
    if (res.rows.length === 0) return;
    const user = res.rows[0];
    if (!user.fcm_token || user.push_enabled === false || user.push_friend_invite === false) return;
    const body = t(user.locale, 'push_friend_request_body', { nickname: fromNickname });
    await sendPushNotification(user.fcm_token, 'Tichu Online', body);
  } catch (err) {
    console.error('Friend request push error:', err.message);
  }
}

// Translate a handler result's message.
// - messageKey present → locale-aware translation (missing key falls back to
//   the locale's generic_error, never cross-falls to ko for non-ko clients)
// - raw message present → return as-is (legacy Korean strings). Old clients
//   with no locale get Korean either way; new clients see Korean until the
//   legacy path is migrated to messageKey.
// - neither present → locale-aware generic_error
function resultMessage(result, locale) {
  if (result && result.messageKey) {
    return t(locale, result.messageKey, result.messageParams);
  }
  if (result && result.message) {
    return result.message;
  }
  return t(locale, 'generic_error');
}

const PORT = process.env.PORT || 8080;
const INVITE_BASE_URL = process.env.INVITE_BASE_URL || 'https://tichu.jiny.shop';
const ANDROID_PACKAGE_NAME = 'com.jiny.tichuOnline';
const IOS_APP_ID = 'HW9XJ9J5M2.com.jiny.tichuOnline';
const IOS_STORE_URL = 'https://apps.apple.com/app/tichu-online/id6759035151';
const ANDROID_STORE_URL = `https://play.google.com/store/apps/details?id=${ANDROID_PACKAGE_NAME}`;
const DEFAULT_ANDROID_SHA256 = '42:BC:52:D8:BA:95:74:09:27:07:D4:42:7A:7D:93:25:7C:4F:65:99:1E:02:FE:62:6C:80:3B:72:14:B6:C1:44,F4:AF:EF:78:2C:6A:11:A0:DE:C4:C8:7C:FF:27:A8:5B:C9:B1:D7:71:72:9D:8F:CB:64:49:B5:1C:20:EF:96:1F';
const inviteLinkTokens = new Map();

function getAndroidSha256Fingerprints() {
  const raw = process.env.ANDROID_APP_SHA256_FINGERPRINTS || DEFAULT_ANDROID_SHA256;
  return raw.split(',')
    .map((value) => value.trim())
    .filter(Boolean);
}

function createInviteToken(room, inviterNickname) {
  const token = crypto.randomBytes(24).toString('base64url');
  inviteLinkTokens.set(token, {
    roomId: room.id,
    roomName: room.name,
    password: room.password || '',
    inviterNickname,
    createdAt: Date.now(),
  });
  return token;
}

function getInviteTokenPayload(token) {
  const payload = inviteLinkTokens.get(token);
  if (!payload) return null;
  const maxAgeMs = 7 * 24 * 60 * 60 * 1000;
  if (Date.now() - payload.createdAt > maxAgeMs) {
    inviteLinkTokens.delete(token);
    return null;
  }
  return payload;
}

function escapeHtml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function renderMarketingPage({
  title,
  description,
  eyebrow = 'Tichu Online',
  primaryLabel,
  primaryHref,
  secondaryLabel = 'Google Play',
  secondaryHref = ANDROID_STORE_URL,
  tertiaryLabel = 'App Store',
  tertiaryHref = IOS_STORE_URL,
  metaTitle,
  metaDescription,
}) {
  const pageTitle = metaTitle || title;
  const pageDescription = metaDescription || description;
  return `<!doctype html>
<html lang="ko">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${escapeHtml(pageTitle)}</title>
    <meta name="description" content="${escapeHtml(pageDescription)}" />
    <meta property="og:title" content="${escapeHtml(pageTitle)}" />
    <meta property="og:description" content="${escapeHtml(pageDescription)}" />
    <meta property="og:type" content="website" />
    <meta property="og:url" content="${escapeHtml(primaryHref)}" />
    <meta name="twitter:card" content="summary_large_image" />
    <style>
      :root {
        --bg: #dff3ff;
        --bg-deep: #b8e1fb;
        --panel: rgba(255,255,255,0.84);
        --panel-strong: rgba(255,255,255,0.94);
        --text: #143a57;
        --muted: #4d6f88;
        --line: rgba(53, 117, 163, 0.16);
        --accent: #ffb638;
        --accent-dark: #cf8612;
        --chip: rgba(255,255,255,0.76);
        --sky-shadow: rgba(49, 109, 156, 0.18);
      }
      * { box-sizing: border-box; }
      body {
        margin: 0;
        font-family: -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", "Noto Sans KR", sans-serif;
        background:
          radial-gradient(circle at top left, rgba(255,255,255,0.9), transparent 30%),
          radial-gradient(circle at top right, rgba(117, 204, 255, 0.35), transparent 26%),
          radial-gradient(circle at bottom left, rgba(255, 193, 92, 0.20), transparent 24%),
          linear-gradient(180deg, #effaff 0%, var(--bg) 50%, var(--bg-deep) 100%);
        color: var(--text);
      }
      body::before,
      body::after {
        content: "";
        position: fixed;
        width: 280px;
        height: 280px;
        border-radius: 50%;
        background: radial-gradient(circle, rgba(255,255,255,0.55), rgba(255,255,255,0));
        pointer-events: none;
        z-index: 0;
      }
      body::before { top: 70px; left: -40px; }
      body::after { right: -60px; bottom: 20px; }
      main {
        position: relative;
        z-index: 1;
        min-height: 100vh;
        display: grid;
        place-items: center;
        padding: 24px;
      }
      .shell {
        width: min(920px, 100%);
        display: grid;
        gap: 18px;
      }
      .card {
        background: var(--panel);
        border: 1px solid var(--line);
        border-radius: 28px;
        box-shadow: 0 30px 80px var(--sky-shadow);
        overflow: hidden;
        backdrop-filter: blur(10px);
      }
      .hero {
        display: grid;
        grid-template-columns: 1.05fr 0.95fr;
      }
      .hero-copy {
        padding: 36px;
      }
      .eyebrow {
        display: inline-flex;
        align-items: center;
        gap: 8px;
        padding: 8px 12px;
        border-radius: 999px;
        background: var(--chip);
        color: var(--accent-dark);
        font-size: 13px;
        font-weight: 700;
      }
      h1 {
        margin: 18px 0 12px;
        font-size: clamp(30px, 5vw, 48px);
        line-height: 1.02;
        letter-spacing: -0.04em;
      }
      .lead {
        margin: 0;
        font-size: 17px;
        line-height: 1.65;
        color: var(--muted);
      }
      .actions {
        display: flex;
        flex-wrap: wrap;
        gap: 12px;
        margin-top: 28px;
      }
      .button {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        min-height: 52px;
        padding: 0 18px;
        border-radius: 16px;
        text-decoration: none;
        font-weight: 700;
        transition: transform 120ms ease, opacity 120ms ease;
      }
      .button:hover { transform: translateY(-1px); opacity: 0.97; }
      .button-primary { background: var(--accent); color: #fff; }
      .button-secondary { background: rgba(255,255,255,0.92); color: var(--text); border: 1px solid var(--line); }
      .hero-side {
        position: relative;
        padding: 28px 28px 24px;
        background:
          radial-gradient(circle at top center, rgba(255,255,255,0.75), transparent 42%),
          linear-gradient(180deg, rgba(255,255,255,0.4), rgba(204,235,255,0.45)),
          linear-gradient(135deg, #d9f1ff 0%, #bee6fb 52%, #9fd7f5 100%);
        display: grid;
        gap: 14px;
        align-content: center;
      }
      .panel {
        padding: 16px 18px;
        border-radius: 18px;
        background: rgba(255,255,255,0.72);
        border: 1px solid rgba(255,255,255,0.65);
      }
      .panel strong { display: block; font-size: 15px; margin-bottom: 6px; }
      .panel p { margin: 0; color: var(--muted); line-height: 1.5; font-size: 14px; }
      .features {
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        gap: 14px;
        padding: 18px;
      }
      .feature {
        padding: 18px;
        border-radius: 20px;
        background: var(--panel-strong);
        border: 1px solid var(--line);
      }
      .feature h2 {
        margin: 0 0 8px;
        font-size: 16px;
      }
      .feature p {
        margin: 0;
        font-size: 14px;
        line-height: 1.6;
        color: var(--muted);
      }
      @media (max-width: 760px) {
        .hero { grid-template-columns: 1fr; }
        .features { grid-template-columns: 1fr; }
        .hero-copy, .hero-side { padding: 24px; }
      }
    </style>
  </head>
  <body>
    <main>
      <div class="shell">
        <section class="card hero">
          <div class="hero-copy">
            <div class="eyebrow">${escapeHtml(eyebrow)}</div>
            <h1>${escapeHtml(title)}</h1>
            <p class="lead">${escapeHtml(description)}</p>
            <div class="actions">
              ${primaryLabel && primaryHref
                ? `<a class="button button-primary" href="${escapeHtml(primaryHref)}">${escapeHtml(primaryLabel)}</a>`
                : ''}
              <a class="button ${primaryLabel && primaryHref ? 'button-secondary' : 'button-primary'}" href="${escapeHtml(secondaryHref)}">${escapeHtml(secondaryLabel)}</a>
              <a class="button button-secondary" href="${escapeHtml(tertiaryHref)}">${escapeHtml(tertiaryLabel)}</a>
            </div>
          </div>
          <div class="hero-side">
            <div class="panel">
              <strong>빠르게 모여서 한 판</strong>
              <p>카카오톡 공유로 친구를 초대하고, 링크를 누르면 바로 방으로 이어지는 흐름을 준비하고 있어요.</p>
            </div>
            <div class="panel">
              <strong>지원 게임</strong>
              <p>티츄, 스컬킹, 러브레터까지 한 앱에서 가볍게 즐길 수 있어요.</p>
            </div>
            <div class="panel">
              <strong>모바일 중심</strong>
              <p>앱이 설치되어 있으면 바로 실행되고, 없으면 스토어로 자연스럽게 이동할 수 있어요.</p>
            </div>
          </div>
        </section>
        <section class="features">
          <article class="feature">
            <h2>티츄</h2>
            <p>팀플레이와 선언 타이밍이 살아 있는 클래식 카드게임을 모바일에 맞게 담았습니다.</p>
          </article>
          <article class="feature">
            <h2>스컬킹</h2>
            <p>판 읽기와 예측 재미가 강한 라운드형 카드게임을 친구들과 빠르게 즐길 수 있어요.</p>
          </article>
          <article class="feature">
            <h2>러브레터</h2>
            <p>짧지만 심리전이 강한 게임도 바로 시작할 수 있게 함께 지원합니다.</p>
          </article>
        </section>
      </div>
    </main>
  </body>
</html>`;
}

// Skull King version gating
const SK_MIN_VERSION = '2.0.0';
const SK_EXPANSION_MIN_VERSION = '2.1.0';
// Love Letter version gating
const LL_MIN_VERSION = '2.2.0';
// Mighty version gating
const MIGHTY_MIN_VERSION = '2.3.0';
// SK_EXPANSION_UPDATE_MESSAGE removed – now uses t(locale, 'sk_expansion_update_required')

function compareVersions(v1, v2) {
  // Strip build metadata (e.g. "2.0.0+15" → "2.0.0")
  const a = (v1 || '0.0.0').split('+')[0].split('.').map(Number);
  const b = (v2 || '0.0.0').split('+')[0].split('.').map(Number);
  for (let i = 0; i < 3; i++) {
    if ((a[i] || 0) > (b[i] || 0)) return 1;
    if ((a[i] || 0) < (b[i] || 0)) return -1;
  }
  return 0;
}

function clientSupportsSK(ws) {
  return compareVersions(ws.appVersion, SK_MIN_VERSION) >= 0;
}

function clientSupportsSKExpansions(ws) {
  return compareVersions(ws.appVersion, SK_EXPANSION_MIN_VERSION) >= 0;
}

function roomHasSKExpansions(room) {
  return room && room.gameType === 'skull_king'
    && Array.isArray(room.skExpansions)
    && room.skExpansions.length > 0;
}

function clientSupportsLL(ws) {
  return compareVersions(ws.appVersion, LL_MIN_VERSION) >= 0;
}

function clientSupportsMighty(ws) {
  return compareVersions(ws.appVersion, MIGHTY_MIN_VERSION) >= 0;
}

function clientCanAccessRoom(ws, room) {
  if (!room) return true;
  if (room.gameType === 'mighty') return clientSupportsMighty(ws);
  if (room.gameType === 'love_letter') return clientSupportsLL(ws);
  if (room.gameType !== 'skull_king') return true;
  if (!clientSupportsSK(ws)) return false;
  if (roomHasSKExpansions(room) && !clientSupportsSKExpansions(ws)) return false;
  return true;
}

function roomAccessUpdateMessage(locale, room, action = 'join') {
  if (room && room.gameType === 'mighty') return t(locale, 'mighty_update_required');
  if (room && room.gameType === 'love_letter') return t(locale, 'll_update_required');
  if (roomHasSKExpansions(room)) return t(locale, 'sk_expansion_update_required');
  return t(locale, 'sk_update_' + action);
}

function filterRoomsForClient(ws, rooms) {
  return rooms.filter((room) => clientCanAccessRoom(ws, room));
}

// Maintenance config (in-memory)
const defaultMaintenanceConfig = {
  noticeStart: null,    // ISO string
  noticeEnd: null,
  maintenanceStart: null,
  maintenanceEnd: null,
  message_ko: '',
  message_en: '',
  message_de: '',
};

let maintenanceConfig = { ...defaultMaintenanceConfig };

const recentRoomInvites = new Map();

function getMaintenanceConfig() {
  return { ...maintenanceConfig };
}

function setMaintenanceConfig(config) {
  maintenanceConfig = { ...maintenanceConfig, ...config };
  updateConfig('maintenance', JSON.stringify(maintenanceConfig)).catch(e =>
    console.error('[Maintenance] Failed to persist config:', e.message)
  );
  // Broadcast updated maintenance status to all connected clients
  broadcastMaintenanceStatus();
}

function broadcastMaintenanceStatus() {
  for (const client of wss.clients) {
    if (client.readyState === client.OPEN) {
      const status = getMaintenanceStatus(client.locale);
      sendTo(client, { type: 'maintenance_status', ...status });
    }
  }
}

async function loadMaintenanceConfig() {
  try {
    const saved = await getConfig('maintenance');
    if (saved) {
      maintenanceConfig = { ...defaultMaintenanceConfig, ...JSON.parse(saved) };
      console.log('[Maintenance] Loaded config from DB');
    }
  } catch (e) {
    console.error('[Maintenance] Failed to load config from DB:', e.message);
  }
}

function getMaintenanceStatus(locale) {
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

  // Pick localized message with fallback: requested locale → en → ko
  let message = '';
  if (locale === 'de' && maintenanceConfig.message_de) {
    message = maintenanceConfig.message_de;
  } else if (locale === 'en' && maintenanceConfig.message_en) {
    message = maintenanceConfig.message_en;
  } else if (locale === 'ko' && maintenanceConfig.message_ko) {
    message = maintenanceConfig.message_ko;
  }
  if (!message) message = maintenanceConfig.message_en || maintenanceConfig.message_ko || '';

  return {
    notice,
    maintenance,
    message,
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
      await handleAdminRoute(req, res, url, pathname, req.method, lobby, wss, { getMaintenanceConfig, setMaintenanceConfig, getMaintenanceStatus, sendPushNotification, sendBroadcastPush });
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
  } else if (pathname === '/.well-known/assetlinks.json') {
    const body = JSON.stringify([
      {
        relation: [
          'delegate_permission/common.handle_all_urls',
          'delegate_permission/common.get_login_creds',
        ],
        target: {
          namespace: 'android_app',
          package_name: ANDROID_PACKAGE_NAME,
          sha256_cert_fingerprints: getAndroidSha256Fingerprints(),
        },
      },
    ]);
    res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(body);
  } else if (
    pathname === '/apple-app-site-association'
    || pathname === '/.well-known/apple-app-site-association'
  ) {
    const body = JSON.stringify({
      applinks: {
        apps: [],
        details: [
          {
            appIDs: [IOS_APP_ID],
            components: [
              { '/': '/invite' },
              { '/': '/invite/*' },
            ],
          },
        ],
      },
    });
    res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(body);
  } else if (pathname === '/invite') {
    const token = url.searchParams.get('t') || url.searchParams.get('token') || '';
    const payload = token ? getInviteTokenPayload(token) : null;
    const roomName = payload?.roomName || 'Tichu Online Room';
    const inviter = payload?.inviterNickname || 'A friend';
    const deepLinkUrl = `${INVITE_BASE_URL}/invite?t=${encodeURIComponent(token)}`;
    const title = payload
      ? `${inviter} invited you to ${roomName}`
      : 'Tichu Online invite';
    const description = payload
      ? 'Open this invite in Tichu Online to join the room.'
      : 'This room invite is no longer valid.';
    const html = renderMarketingPage({
      eyebrow: payload ? `${inviter}님의 초대` : 'Tichu Online 초대',
      title: payload ? `${roomName} 방에 참여해보세요` : '초대 링크를 확인할 수 없어요',
      description: payload
        ? '앱이 설치되어 있으면 바로 방으로 이동하고, 설치되어 있지 않다면 아래 스토어에서 내려받을 수 있어요.'
        : '초대 링크가 만료되었거나 유효하지 않습니다. 새로운 링크를 다시 받아주세요.',
      primaryLabel: '앱에서 초대 열기',
      primaryHref: deepLinkUrl,
      metaTitle: title,
      metaDescription: description,
    });
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(html);
  } else if (pathname === '/debug-path') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end(`pathname=${req.url} | hasAdmin=${typeof handleAdminRoute}`);
  } else {
    const html = renderMarketingPage({
      title: 'Tichu Online으로 친구들과 카드 한 판',
      description: '티츄, 스컬킹, 러브레터를 모바일에서 빠르게 즐길 수 있는 멀티플레이 카드게임 앱입니다. 친구 초대 링크를 받았다면 아래 스토어에서 설치한 뒤 바로 게임에 참여할 수 있어요.',
      secondaryLabel: 'Google Play에서 설치',
      secondaryHref: ANDROID_STORE_URL,
      tertiaryLabel: 'App Store에서 설치',
      tertiaryHref: IOS_STORE_URL,
      metaTitle: 'Tichu Online',
      metaDescription: '티츄, 스컬킹, 러브레터를 즐길 수 있는 모바일 카드게임 앱 Tichu Online',
    });
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(html);
  }
});

const wss = new WebSocketServer({ server, maxPayload: 64 * 1024 }); // 64KB max message size
const lobby = new LobbyManager();

let nextPlayerId = 1;

// Track nickname -> roomId for reconnection during games
const playerSessions = new Map(); // nickname -> { roomId, disconnectedAt }
const spectatorSessions = new Map(); // nickname -> { roomId, disconnectedAt }

// Turn timer system
const turnTimers = {};    // roomId -> setTimeout handle
const timeoutCounts = {}; // roomId -> { playerId: count }
const roundEndTimers = {}; // roomId -> setTimeout handle for auto next round
const trickEndTimers = {}; // roomId -> setTimeout handle for skull king trick reveal
const turnTimerPhases = {}; // roomId -> phase name (to prevent phase timer reset)
const waitingRoomTimers = {}; // `${roomId}_${playerId}` -> setTimeout handle for waiting room disconnect

function seasonNameFromDate(date) {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  return `${y}-${m}`;
}

let _seasonCycleRunning = false;
async function ensureSeasonCycle() {
  if (_seasonCycleRunning) return;
  _seasonCycleRunning = true;
  try {
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
  } finally {
    _seasonCycleRunning = false;
  }
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
  for (const [nickname, session] of spectatorSessions) {
    if (now - session.disconnectedAt > maxAge) {
      spectatorSessions.delete(nickname);
    }
  }
  for (const [token, payload] of inviteLinkTokens) {
    if (now - payload.createdAt > 7 * 24 * 60 * 60 * 1000) {
      inviteLinkTokens.delete(token);
    }
  }
  // Clean up zombie rooms: no game, and all humans disconnected for >= 30 min
  let zombieRemoved = false;
  for (const [id, room] of lobby.rooms) {
    if (room.game) continue;
    const humans = room.players.filter(p => p !== null && !p.isBot);
    if (humans.length === 0) {
      // No humans at all (shouldn't happen, but clean up)
      console.log(`[Cleanup] Removing zombie room: ${id} (no humans)`);
      removeRoomAndNotifySpectators(id);
      zombieRemoved = true;
      continue;
    }
    // All humans must be disconnected AND their sessions expired (30min+)
    const allHumansGoneLongEnough = humans.every(p => {
      if (p.connected) return false;
      const session = playerSessions.get(p.nickname);
      return !session || (now - session.disconnectedAt > maxAge);
    });
    if (allHumansGoneLongEnough) {
      console.log(`[Cleanup] Removing zombie room: ${id} (all humans disconnected 30min+)`);
      removeRoomAndNotifySpectators(id);
      zombieRemoved = true;
    }
  }
  if (zombieRemoved) broadcastRoomList();
}, 5 * 60 * 1000);

// WebSocket heartbeat: detect zombie connections (network died without proper close).
// Pings every 15s; terminates any client that didn't pong since last ping (max ~30s detection).
// Terminated sockets fire the `close` event, which runs the normal disconnect flow
// (marks player disconnected and starts the 30s waiting-room removal timer).
const HEARTBEAT_INTERVAL_MS = 15000;
const heartbeatInterval = setInterval(() => {
  wss.clients.forEach((ws) => {
    if (ws.isAlive === false) {
      console.log(`[Heartbeat] Terminating zombie connection: ${ws.nickname || '-'} (${ws.playerId || '-'})`);
      try { ws.terminate(); } catch (_) {}
      return;
    }
    ws.isAlive = false;
    try { ws.ping(); } catch (_) {}
  });
}, HEARTBEAT_INTERVAL_MS);
wss.on('close', () => {
  clearInterval(heartbeatInterval);
});

// Safety net for unawaited async errors
process.on('unhandledRejection', (reason, promise) => {
  console.error('[UNHANDLED REJECTION]', reason);
});

// Initialize database and start server
(async () => {
  await initDatabase();
  await loadMaintenanceConfig();
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

  // Heartbeat: mark alive initially, refresh on pong
  ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });

  console.log('New connection established');

  ws._messageQueue = Promise.resolve();
  ws.on('message', (raw) => {
    let data;
    try {
      data = JSON.parse(raw.toString());
    } catch (e) {
      sendTo(ws, { type: 'error', message: t(ws.locale, 'invalid_data') });
      return;
    }

    // Queue messages per-client to prevent async handler interleaving
    ws._messageQueue = ws._messageQueue.then(() => handleMessage(ws, data)).catch(err => {
      console.error('Message handler error:', err);
    });
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
          if (ws.nickname) {
            spectatorSessions.set(ws.nickname, {
              roomId: ws.roomId,
              disconnectedAt: Date.now(),
            });
          }
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

async function handleMessage(ws, data) {
  switch (data.type) {
    case 'register':
      await handleRegister(ws, data);
      break;
    case 'login':
      await handleLogin(ws, data);
      break;
    case 'check_nickname':
      await handleCheckNickname(ws, data);
      break;
    case 'delete_account':
      await handleDeleteAccount(ws);
      break;
    case 'room_list':
      sendTo(ws, {
        type: 'room_list',
        rooms: filterRoomsForClient(ws, lobby.getRoomList()),
      });
      break;
    case 'spectatable_rooms':
      sendTo(ws, {
        type: 'spectatable_rooms',
        rooms: filterRoomsForClient(ws, lobby.getSpectatableRooms()),
      });
      break;
    case 'create_room':
      handleCreateRoom(ws, data);
      break;
    case 'join_room':
      await handleJoinRoom(ws, data);
      break;
    case 'join_room_by_invite':
      await handleJoinRoomByInvite(ws, data);
      break;
    case 'leave_room':
      await handleLeaveRoom(ws);
      break;
    case 'leave_game':
      await handleLeaveGame(ws);
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
    case 'block_slot':
      handleBlockSlot(ws, data);
      break;
    case 'unblock_slot':
      handleUnblockSlot(ws, data);
      break;
    case 'switch_to_spectator':
      handleSwitchToSpectator(ws);
      break;
    case 'switch_to_player':
      handleSwitchToPlayer(ws, data);
      break;
    case 'get_profile':
      await handleGetProfile(ws, data);
      break;
    case 'create_share_invite_link':
      handleCreateShareInviteLink(ws);
      break;
    // Game actions (Tichu)
    case 'declare_large_tichu':
    case 'pass_large_tichu':
    case 'declare_small_tichu':
    case 'exchange_cards':
    case 'play_cards':
    case 'pass':
    case 'next_round':
    case 'dragon_give':
    case 'call_rank':
    // Game actions (Mighty)
    case 'raise_bid':
    case 'change_trump':
    case 'discard_kitty':
    case 'declare_deal_miss':
    // Game actions (Skull King)
    case 'submit_bid':
    case 'play_card':
    // Game actions (Love Letter)
    case 'select_target':
    case 'guard_guess':
    case 'effect_ack':
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
      await handleChatMessage(ws, data);
      break;
    // User actions
    case 'block_user':
      await handleBlockUser(ws, data);
      break;
    case 'unblock_user':
      await handleUnblockUser(ws, data);
      break;
    case 'get_blocked_users':
      await handleGetBlockedUsers(ws);
      break;
    case 'report_user':
      await handleReportUser(ws, data);
      break;
    case 'submit_inquiry':
      await handleSubmitInquiry(ws, data);
      break;
    case 'get_inquiries':
      await handleGetInquiries(ws);
      break;
    case 'mark_inquiries_read':
      await handleMarkInquiriesRead(ws);
      break;
    case 'get_notices':
      await handleGetNotices(ws);
      break;
    case 'add_friend':
      await handleAddFriend(ws, data);
      break;
    case 'get_friends':
      await handleGetFriends(ws);
      break;
    case 'get_pending_friend_requests':
      await handleGetPendingFriendRequests(ws);
      break;
    case 'accept_friend_request':
      await handleAcceptFriendRequest(ws, data);
      break;
    case 'reject_friend_request':
      await handleRejectFriendRequest(ws, data);
      break;
    case 'remove_friend':
      await handleRemoveFriend(ws, data);
      break;
    case 'invite_to_room':
      handleInviteToRoom(ws, data);
      break;
    case 'get_rankings':
      await handleGetRankings(ws, data);
      break;
    case 'get_seasons':
      await handleGetSeasons(ws);
      break;
    case 'get_wallet':
      await handleGetWallet(ws);
      break;
    case 'get_gold_history':
      await handleGetGoldHistory(ws, data);
      break;
    case 'get_shop_items':
      await handleGetShopItems(ws);
      break;
    case 'get_inventory':
      await handleGetInventory(ws);
      break;
    case 'buy_item':
      await handleBuyItem(ws, data);
      break;
    case 'equip_item':
      await handleEquipItem(ws, data);
      break;
    case 'use_item':
      await handleUseItem(ws, data);
      break;
    case 'change_nickname':
      await handleChangeNickname(ws, data);
      break;
    case 'social_login':
      await handleSocialLogin(ws, data);
      break;
    case 'social_register':
      await handleSocialRegister(ws, data);
      break;
    case 'social_link':
      await handleSocialLink(ws, data);
      break;
    case 'social_unlink':
      await handleSocialUnlink(ws);
      break;
    case 'get_linked_social':
      await handleGetLinkedSocial(ws);
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
        if (ws.isAdmin === true && (data.inquiryAlert != null || data.reportAlert != null)) {
          const alertResult = await setAdminAlertSettings(
            ws.nickname,
            data.inquiryAlert != null ? data.inquiryAlert === true : ws.pushAdminInquiry !== false,
            data.reportAlert != null ? data.reportAlert === true : ws.pushAdminReport !== false,
          );
          if (alertResult.success) {
            ws.pushAdminInquiry = alertResult.settings.pushAdminInquiry === true;
            ws.pushAdminReport = alertResult.settings.pushAdminReport === true;
          }
        }
      }
      break;
    case 'get_admin_dashboard':
      await handleGetAdminDashboard(ws);
      break;
    case 'get_admin_stats':
      await handleGetAdminStats(ws, data);
      break;
    case 'get_admin_users':
      await handleGetAdminUsers(ws, data);
      break;
    case 'get_admin_user_detail':
      await handleGetAdminUserDetail(ws, data);
      break;
    case 'set_admin_user':
      await handleSetAdminUser(ws, data);
      break;
    case 'admin_adjust_gold':
      await handleAdminAdjustGold(ws, data);
      break;
    case 'get_admin_inquiries':
      await handleGetAdminInquiries(ws, data);
      break;
    case 'resolve_admin_inquiry':
      await handleResolveAdminInquiry(ws, data);
      break;
    case 'get_admin_reports':
      await handleGetAdminReports(ws, data);
      break;
    case 'get_admin_report_group':
      await handleGetAdminReportGroup(ws, data);
      break;
    case 'update_admin_report_status':
      await handleUpdateAdminReportStatus(ws, data);
      break;
    case 'ad_reward':
      if (ws.nickname) {
        try {
          const adResult = await claimAdReward(ws.nickname);
          sendTo(ws, { type: 'ad_reward_result', ...adResult });
        } catch (err) {
          sendTo(ws, { type: 'ad_reward_result', success: false, message: t(ws.locale, 'reward_failed') });
        }
      }
      break;
    case 'get_maintenance_status':
      sendTo(ws, { type: 'maintenance_status', ...getMaintenanceStatus(ws.locale) });
      break;
    case 'get_app_config':
      await handleGetAppConfig(ws);
      break;
    case 'search_users':
      await handleSearchUsers(ws, data);
      break;
    case 'send_dm':
      await handleSendDm(ws, data);
      break;
    case 'get_dm_history':
      await handleGetDmHistory(ws, data);
      break;
    case 'mark_dm_read':
      await handleMarkDmRead(ws, data);
      break;
    case 'get_dm_conversations':
      await handleGetDmConversations(ws);
      break;
    case 'get_unread_dm_count':
      await handleGetUnreadDmCount(ws);
      break;
    case 'set_locale':
      if (typeof data.locale === 'string' && ['en', 'ko', 'de'].includes(data.locale)) {
        ws.locale = data.locale;
        if (ws.nickname) {
          updateDeviceInfo(ws.nickname, { locale: data.locale });
        }
      }
      break;
    default:
      sendTo(ws, { type: 'error', message: t(ws.locale, 'unknown_message', { type: data.type }) });
  }
}

async function handleGetAppConfig(ws) {
  try {
    const eulaContent = await getLocalizedConfig('eula_content', ws.locale);
    const privacyPolicy = await getLocalizedConfig('privacy_policy', ws.locale);
    const minVersion = await getConfig('min_version');
    const latestVersion = await getConfig('latest_version');
    sendTo(ws, {
      type: 'app_config',
      eulaContent: eulaContent || '',
      privacyPolicy: privacyPolicy || '',
      minVersion: minVersion || '',
      latestVersion: latestVersion || '',
    });
  } catch (err) {
    console.error('get_app_config error:', err);
    sendTo(ws, { type: 'app_config', eulaContent: '', privacyPolicy: '', minVersion: '', latestVersion: '' });
  }
}

async function handleRegister(ws, data) {
  const { username, password, nickname } = data;
  const result = await registerUser(username, password, nickname);
  sendTo(ws, {
    type: 'register_result',
    success: result.success,
    message: resultMessage(result, ws.locale),
  });
}

async function handleCheckNickname(ws, data) {
  const result = await checkNickname(data.nickname);
  sendTo(ws, {
    type: 'nickname_check_result',
    available: result.available,
    message: resultMessage(result, ws.locale),
  });
}

async function handleDeleteAccount(ws) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'login_required') });
    return;
  }
  const nickname = ws.nickname;
  const playerId = ws.playerId;
  const roomId = ws.roomId;
  const wasSpectator = ws.isSpectator === true;

  if (roomId) {
    const room = lobby.getRoom(roomId);
    if (room) {
      if (wasSpectator) {
        spectatorSessions.delete(nickname);
        room.removeSpectator(playerId);
        if (room.game) _broadcastState(roomId, room);
        broadcastRoomState(roomId);
      } else if (room.game && room.game.state !== 'game_end' && !room.game.deserted) {
        await handleDesertion(roomId, playerId, 'leave');
      } else {
        const timerKey = `${roomId}_${playerId}`;
        if (waitingRoomTimers[timerKey]) {
          clearTimeout(waitingRoomTimers[timerKey]);
          delete waitingRoomTimers[timerKey];
        }
        room.removePlayer(playerId);
        if (room.getHumanPlayerCount() === 0) {
          removeRoomAndNotifySpectators(roomId);
        } else {
          broadcastRoomState(roomId);
        }
      }
      broadcastRoomList();
    }
    ws.roomId = null;
    ws.isSpectator = false;
  }

  playerSessions.delete(nickname);
  spectatorSessions.delete(nickname);

  const result = await deleteUser(nickname);
  if (result.success) {
    ws.nickname = null;
    ws.playerId = null;
    ws.userId = null;
  }
  sendTo(ws, {
    type: 'account_deleted',
    success: result.success,
    message: resultMessage(result, ws.locale),
  });
  if (result.success) {
    setTimeout(() => { try { ws.close(); } catch (_) {} }, 500);
  }
}

async function handleLogin(ws, data) {
  const { username, password } = data;
  // Extract locale early so maintenance message is localized
  const earlyLocale = (data.deviceInfo && data.deviceInfo.locale) || ws.locale || null;
  ws.locale = earlyLocale;

  const result = await loginUser(username, password);

  if (!result.success) {
    sendTo(ws, { type: 'login_error', message: resultMessage(result, ws.locale) });
    return;
  }

  // Block login during maintenance
  const mStatus = getMaintenanceStatus(ws.locale);
  if (mStatus.maintenance) {
    sendTo(ws, { type: 'login_error', message: mStatus.message || t(ws.locale, 'maintenance'), reason: 'maintenance' });
    return;
  }

  // S3: Disconnect existing connection with same nickname to prevent duplicate login
  for (const client of wss.clients) {
    if (client !== ws && client.nickname === result.nickname && client.readyState === client.OPEN) {
      // Preemptively store session before close (close handler is async)
      if (client.roomId) {
        const oldRoom = lobby.getRoom(client.roomId);
        if (client.isSpectator && oldRoom) {
          oldRoom.removeSpectator(client.playerId);
          if (oldRoom.game) _broadcastState(client.roomId, oldRoom);
          broadcastRoomState(client.roomId);
          broadcastRoomList();
        } else if (oldRoom && oldRoom.game) {
          oldRoom.markPlayerDisconnected(client.playerId);
          playerSessions.set(client.nickname, {
            roomId: client.roomId,
            disconnectedAt: Date.now(),
          });
        } else if (oldRoom) {
          // Waiting room (no game) - clean up properly
          const timerKey = `${client.roomId}_${client.playerId}`;
          if (waitingRoomTimers[timerKey]) {
            clearTimeout(waitingRoomTimers[timerKey]);
            delete waitingRoomTimers[timerKey];
          }
          oldRoom.removePlayer(client.playerId);
          if (oldRoom.getHumanPlayerCount() === 0) {
            removeRoomAndNotifySpectators(client.roomId);
          } else {
            broadcastRoomState(client.roomId);
          }
          broadcastRoomList();
        }
      }
      sendTo(client, { type: 'kicked', reason: 'duplicate_login', message: t(client.locale, 'duplicate_login') });
      client.roomId = null; // Prevent close handler from double-processing
      client.close();
    }
  }

  ws.playerId = `player_${nextPlayerId++}`;
  ws.nickname = result.nickname;
  ws.userId = result.userId;
  ws.isAdmin = result.isAdmin === true;
  ws.pushEnabled = result.pushEnabled !== false;
  ws.pushFriendInvite = result.pushFriendInvite !== false;
  ws.pushAdminInquiry = result.pushAdminInquiry !== false;
  ws.pushAdminReport = result.pushAdminReport !== false;
  const deviceInfo = data.deviceInfo || {};
  ws.appVersion = deviceInfo.appVersion || null;
  ws.locale = deviceInfo.locale || null;
  console.log(`Player logged in: ${ws.nickname} (${ws.playerId})`);

  // Notify friends of online status
  notifyFriendsOfStatusChange(ws.nickname, true);

  await handleReconnection(ws);

  // Save device info (fire-and-forget)
  deviceInfo.lastIp = ws.clientIp;
  updateDeviceInfo(ws.nickname, deviceInfo);
}

async function handleSocialLogin(ws, data) {
  const { provider, token } = data;
  if (!provider || !token) {
    sendTo(ws, { type: 'login_error', message: t(ws.locale, 'invalid_request') });
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
    const mStatus = getMaintenanceStatus(ws.locale);
    if (mStatus.maintenance) {
      sendTo(ws, { type: 'login_error', message: mStatus.message || t(ws.locale, 'maintenance'), reason: 'maintenance' });
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
            if (client.isSpectator && oldRoom) {
              oldRoom.removeSpectator(client.playerId);
              if (oldRoom.game) _broadcastState(client.roomId, oldRoom);
              broadcastRoomState(client.roomId);
              broadcastRoomList();
            } else if (oldRoom && oldRoom.game) {
              oldRoom.markPlayerDisconnected(client.playerId);
              playerSessions.set(client.nickname, {
                roomId: client.roomId,
                disconnectedAt: Date.now(),
              });
            } else if (oldRoom) {
              // Waiting room (no game) - clean up properly
              const timerKey = `${client.roomId}_${client.playerId}`;
              if (waitingRoomTimers[timerKey]) {
                clearTimeout(waitingRoomTimers[timerKey]);
                delete waitingRoomTimers[timerKey];
              }
              oldRoom.removePlayer(client.playerId);
              if (oldRoom.getHumanPlayerCount() === 0) {
                removeRoomAndNotifySpectators(client.roomId);
              } else {
                broadcastRoomState(client.roomId);
              }
              broadcastRoomList();
            }
          }
          sendTo(client, { type: 'kicked', reason: 'duplicate_login', message: t(client.locale, 'duplicate_login') });
          client.roomId = null;
          client.close();
        }
      }

      ws.playerId = `player_${nextPlayerId++}`;
      ws.nickname = result.nickname;
      ws.userId = result.userId;
      ws.isAdmin = result.isAdmin === true;
      ws.pushEnabled = result.pushEnabled !== false;
      ws.pushFriendInvite = result.pushFriendInvite !== false;
      ws.pushAdminInquiry = result.pushAdminInquiry !== false;
      ws.pushAdminReport = result.pushAdminReport !== false;
      const socialDeviceInfo = data.deviceInfo || {};
      ws.appVersion = socialDeviceInfo.appVersion || null;
      ws.locale = socialDeviceInfo.locale || null;
      console.log(`Player logged in (social/${provider}): ${ws.nickname} (${ws.playerId})`);

      notifyFriendsOfStatusChange(ws.nickname, true);
      await handleReconnection(ws);

      // Save device info (fire-and-forget)
      socialDeviceInfo.lastIp = ws.clientIp;
      updateDeviceInfo(ws.nickname, socialDeviceInfo);
    } else {
      // New user - need nickname
      sendTo(ws, { type: 'need_nickname', provider, providerUid: verified.uid, email: verified.email });
    }
  } catch (err) {
    console.error('Social login error:', err);
    sendTo(ws, { type: 'login_error', message: t(ws.locale, 'social_login_failed') });
  }
}

async function handleSocialRegister(ws, data) {
  const { provider, token, nickname, existingUser } = data;
  if (!provider || !token || !nickname) {
    sendTo(ws, { type: 'login_error', message: t(ws.locale, 'invalid_request') });
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
    const mStatus = getMaintenanceStatus(ws.locale);
    if (mStatus.maintenance) {
      sendTo(ws, { type: 'login_error', message: mStatus.message || t(ws.locale, 'maintenance'), reason: 'maintenance' });
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
          sendTo(ws, { type: 'login_error', message: t(ws.locale, 'nickname_taken') });
          return;
        }
        // Find user by provider + uid
        const userRes = await client.query(
          'SELECT id FROM tc_users WHERE auth_provider = $1 AND provider_uid = $2',
          [provider, verified.uid]
        );
        if (userRes.rows.length === 0) {
          sendTo(ws, { type: 'login_error', message: t(ws.locale, 'user_not_found') });
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
      sendTo(ws, { type: 'login_error', message: resultMessage(result, ws.locale) });
      return;
    }

    // Auto-login after registration (same flow as handleLogin post-auth)
    ws.playerId = `player_${nextPlayerId++}`;
    ws.nickname = result.nickname;
    ws.userId = result.userId;
    ws.isAdmin = false;
    ws.pushAdminInquiry = true;
    ws.pushAdminReport = true;
    const regDeviceInfo = data.deviceInfo || {};
    ws.appVersion = regDeviceInfo.appVersion || null;
    ws.locale = regDeviceInfo.locale || null;
    console.log(`Player registered & logged in (social/${provider}): ${ws.nickname} (${ws.playerId})`);

    notifyFriendsOfStatusChange(ws.nickname, true);
    await handleReconnection(ws);

    // Save device info (fire-and-forget)
    regDeviceInfo.lastIp = ws.clientIp;
    updateDeviceInfo(ws.nickname, regDeviceInfo);
  } catch (err) {
    console.error('Social register error:', err);
    sendTo(ws, { type: 'login_error', message: t(ws.locale, 'social_register_failed') });
  }
}

async function handleSocialLink(ws, data) {
  if (!ws.userId) {
    sendTo(ws, { type: 'social_link_result', success: false, message: t(ws.locale, 'login_required') });
    return;
  }
  const { provider, token } = data;
  if (!provider || !token) {
    sendTo(ws, { type: 'social_link_result', success: false, message: t(ws.locale, 'invalid_request') });
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
    if (result.success && result.provider) {
      ws.authProvider = result.provider;
    }
    sendTo(ws, { type: 'social_link_result', success: result.success, message: resultMessage(result, ws.locale), provider: result.provider });
  } catch (err) {
    console.error('Social link error:', err);
    sendTo(ws, { type: 'social_link_result', success: false, message: t(ws.locale, 'social_link_failed') });
  }
}

async function handleSocialUnlink(ws) {
  if (!ws.userId) {
    sendTo(ws, { type: 'social_unlink_result', success: false, message: t(ws.locale, 'login_required') });
    return;
  }

  try {
    const result = await unlinkSocial(ws.userId);
    if (result.success) {
      ws.authProvider = 'local';
    }
    sendTo(ws, { type: 'social_unlink_result', success: result.success, message: resultMessage(result, ws.locale) });
  } catch (err) {
    console.error('Social unlink error:', err);
    sendTo(ws, { type: 'social_unlink_result', success: false, message: t(ws.locale, 'social_unlink_failed') });
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
  const titleName = profile?.titleName || null;
  const hasTopCardCounter = profile?.hasTopCardCounter || false;
  const hasMightyTrumpCounter = profile?.hasMightyTrumpCounter || false;
  ws.titleKey = titleKey;
  ws.titleName = titleName;

  const socialInfo = await getLinkedSocial(ws.userId);
  const authProvider = socialInfo?.provider || 'local';
  ws.authProvider = authProvider;

  // Check for reconnection to a game
  const session = playerSessions.get(ws.nickname);
  if (session) {
    const room = lobby.getRoom(session.roomId);
    if (room && room.game && room.canReconnect(ws.nickname)) {
      if (!clientCanAccessRoom(ws, room)) {
        playerSessions.delete(ws.nickname);
        sendTo(ws, {
          type: 'login_success',
          playerId: ws.playerId,
          nickname: ws.nickname,
          themeKey,
          titleKey,
          hasTopCardCounter,
          hasMightyTrumpCounter,
          authProvider,
          isAdmin: ws.isAdmin === true,
          pushEnabled: ws.pushEnabled !== false,
          pushFriendInvite: ws.pushFriendInvite !== false,
          pushAdminInquiry: ws.pushAdminInquiry !== false,
          pushAdminReport: ws.pushAdminReport !== false,
          maintenanceStatus: getMaintenanceStatus(ws.locale),
        });
        sendTo(ws, {
          type: 'error',
          message: roomAccessUpdateMessage(ws.locale, room, 'play'),
        });
        sendTo(ws, {
          type: 'room_list',
          rooms: filterRoomsForClient(ws, lobby.getRoomList()),
        });
        return;
      }
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
          hasMightyTrumpCounter,
          authProvider,
          isAdmin: ws.isAdmin === true,
          pushEnabled: ws.pushEnabled !== false,
          pushFriendInvite: ws.pushFriendInvite !== false,
          pushAdminInquiry: ws.pushAdminInquiry !== false,
          pushAdminReport: ws.pushAdminReport !== false,
          maintenanceStatus: getMaintenanceStatus(ws.locale),
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

  const spectatorSession = spectatorSessions.get(ws.nickname);
  if (spectatorSession) {
    const room = lobby.getRoom(spectatorSession.roomId);
    if (room) {
      if (!clientCanAccessRoom(ws, room)) {
        spectatorSessions.delete(ws.nickname);
        sendTo(ws, {
          type: 'login_success',
          playerId: ws.playerId,
          nickname: ws.nickname,
          themeKey,
          titleKey,
          hasTopCardCounter,
          hasMightyTrumpCounter,
          authProvider,
          isAdmin: ws.isAdmin === true,
          pushEnabled: ws.pushEnabled !== false,
          pushFriendInvite: ws.pushFriendInvite !== false,
          pushAdminInquiry: ws.pushAdminInquiry !== false,
          pushAdminReport: ws.pushAdminReport !== false,
          maintenanceStatus: getMaintenanceStatus(ws.locale),
        });
        sendTo(ws, {
          type: 'error',
          message: roomAccessUpdateMessage(ws.locale, room, 'spectate'),
        });
        sendTo(ws, {
          type: 'room_list',
          rooms: filterRoomsForClient(ws, lobby.getRoomList()),
        });
        return;
      }
      const result = room.addSpectator(ws.playerId, ws.nickname, '');
      if (result.success) {
        ws.roomId = room.id;
        ws.isSpectator = true;
        spectatorSessions.delete(ws.nickname);
        console.log(`Spectator ${ws.nickname} reconnected to room ${room.name}`);

        sendTo(ws, {
          type: 'login_success',
          playerId: ws.playerId,
          nickname: ws.nickname,
          themeKey,
          titleKey,
          hasTopCardCounter,
          hasMightyTrumpCounter,
          authProvider,
          isAdmin: ws.isAdmin === true,
          pushEnabled: ws.pushEnabled !== false,
          pushFriendInvite: ws.pushFriendInvite !== false,
          pushAdminInquiry: ws.pushAdminInquiry !== false,
          pushAdminReport: ws.pushAdminReport !== false,
          maintenanceStatus: getMaintenanceStatus(ws.locale),
        });
        sendTo(ws, {
          type: 'spectate_joined',
          roomId: room.id,
          roomName: room.name,
        });
        sendTo(ws, { type: 'chat_history', messages: room.getChatHistory() });
        broadcastRoomState(room.id);
        if (room.game) {
          const permittedPlayers = room.getPermittedPlayers(ws.playerId);
          const state = room.game.getStateForSpectator(permittedPlayers);
          state.turnDeadline = room.turnDeadline;
          state.spectators = room.spectators.map((s) => ({ id: s.id, nickname: s.nickname }));
          state.spectatorCount = room.spectators.length;
          sendTo(ws, { type: 'spectator_game_state', state });
        } else {
          sendTo(ws, { type: 'room_state', room: room.getState() });
        }
        broadcastRoomList();
        return;
      }
    }
    spectatorSessions.delete(ws.nickname);
  }

  // Check if player was in a waiting room (no game, disconnected)
  for (const [roomId, room] of lobby.rooms) {
    if (room && !room.game) {
      const player = room.players.find(p => p !== null && p.nickname === ws.nickname && p.connected === false);
      if (player) {
        if (!clientCanAccessRoom(ws, room)) {
          const timerKey = `${roomId}_${player.id}`;
          if (waitingRoomTimers[timerKey]) {
            clearTimeout(waitingRoomTimers[timerKey]);
            delete waitingRoomTimers[timerKey];
          }
          room.removePlayer(player.id);
          if (room.getHumanPlayerCount() === 0) {
            removeRoomAndNotifySpectators(roomId);
          } else {
            broadcastRoomState(room.id);
          }
          broadcastRoomList();
          sendTo(ws, {
            type: 'login_success',
            playerId: ws.playerId,
            nickname: ws.nickname,
            themeKey,
            titleKey,
            hasTopCardCounter,
            authProvider,
            isAdmin: ws.isAdmin === true,
            pushEnabled: ws.pushEnabled !== false,
            pushFriendInvite: ws.pushFriendInvite !== false,
            pushAdminInquiry: ws.pushAdminInquiry !== false,
            pushAdminReport: ws.pushAdminReport !== false,
            maintenanceStatus: getMaintenanceStatus(ws.locale),
          });
          sendTo(ws, {
            type: 'error',
            message: roomAccessUpdateMessage(ws.locale, room, 'join'),
          });
          sendTo(ws, {
            type: 'room_list',
            rooms: filterRoomsForClient(ws, lobby.getRoomList()),
          });
          return;
        }
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
        if (room.hostId === oldId) {
          room.hostId = ws.playerId;
          room.hostNickname = ws.nickname;
        }
        ws.roomId = room.id;

        sendTo(ws, {
          type: 'login_success',
          playerId: ws.playerId,
          nickname: ws.nickname,
          themeKey,
          titleKey,
          hasTopCardCounter,
          hasMightyTrumpCounter,
          authProvider,
          isAdmin: ws.isAdmin === true,
          pushEnabled: ws.pushEnabled !== false,
          pushFriendInvite: ws.pushFriendInvite !== false,
          pushAdminInquiry: ws.pushAdminInquiry !== false,
          pushAdminReport: ws.pushAdminReport !== false,
          maintenanceStatus: getMaintenanceStatus(ws.locale),
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
    hasMightyTrumpCounter,
    authProvider,
    isAdmin: ws.isAdmin === true,
    pushEnabled: ws.pushEnabled !== false,
    pushFriendInvite: ws.pushFriendInvite !== false,
    pushAdminInquiry: ws.pushAdminInquiry !== false,
    pushAdminReport: ws.pushAdminReport !== false,
    maintenanceStatus: getMaintenanceStatus(ws.locale),
  });
  sendTo(ws, {
    type: 'room_list',
    rooms: filterRoomsForClient(ws, lobby.getRoomList()),
  });
  // Send unread DM count on login
  getTotalUnreadDmCount(ws.nickname).then(count => {
    sendTo(ws, { type: 'unread_dm_count', count });
  });
}

function handleCreateRoom(ws, data) {
  if (!ws.playerId) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'login_required') });
    return;
  }
  if (ws.roomId) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'already_in_room') });
    return;
  }
  const roomName = (data.roomName || `${ws.nickname}'s Room`).trim();
  const isRanked = !!data.isRanked;
  const gameType = data.gameType === 'skull_king' ? 'skull_king'
    : data.gameType === 'love_letter' ? 'love_letter'
    : data.gameType === 'mighty' ? 'mighty' : 'tichu';

  // Version gating
  if (gameType === 'skull_king' && !clientSupportsSK(ws)) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'sk_update_required') });
    return;
  }
  if (gameType === 'love_letter' && !clientSupportsLL(ws)) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'll_update_required') });
    return;
  }
  if (gameType === 'mighty' && !clientSupportsMighty(ws)) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'mighty_update_required') });
    return;
  }

  if (isRanked && ws.authProvider === 'local') {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'ranked_social_required') });
    return;
  }
  const password = isRanked
    ? ''
    : (typeof data.password === 'string' ? data.password.trim() : '');
  const turnTimeLimit = Math.min(Math.max(parseInt(data.turnTimeLimit) || 30, 10), 999);
  const minTarget = gameType === 'mighty' ? 10 : 100;
  const defaultTarget = gameType === 'mighty' ? 50 : 1000;
  const maxTarget = gameType === 'mighty' ? 500 : 20000;
  const targetScore = (isRanked && gameType === 'mighty')
    ? 50
    : Math.min(Math.max(parseInt(data.targetScore) || defaultTarget, minTarget), maxTarget);

  let maxPlayers = 4;
  let skExpansions = [];
  if (gameType === 'mighty') {
    maxPlayers = 6; // Mighty: 6 seats by default, 1 seat blockable for 5-player mode
  } else if (gameType === 'love_letter') {
    maxPlayers = Math.min(Math.max(parseInt(data.maxPlayers) || 4, 2), 4);
  } else if (gameType === 'skull_king') {
    maxPlayers = Math.min(Math.max(parseInt(data.maxPlayers) || 4, 2), 6);
    // Validate skExpansions: accept only known ids, dedupe, cap to 3
    const allowed = new Set(['kraken', 'white_whale', 'loot']);
    if (Array.isArray(data.skExpansions)) {
      const seen = new Set();
      for (const x of data.skExpansions) {
        if (typeof x === 'string' && allowed.has(x) && !seen.has(x)) {
          seen.add(x);
          skExpansions.push(x);
        }
      }
    }
    if (skExpansions.length > 0 && !clientSupportsSKExpansions(ws)) {
      sendTo(ws, { type: 'error', message: t(ws.locale, 'sk_expansion_update_required') });
      return;
    }
  }

  const room = lobby.createRoom(
    roomName,
    ws.playerId,
    ws.nickname,
    password,
    isRanked,
    turnTimeLimit,
    targetScore,
    gameType,
    maxPlayers,
    skExpansions
  );
  ws.roomId = room.id;
  // Set title on host player
  if (ws.titleKey) {
    room.players[0].titleKey = ws.titleKey;
    room.players[0].titleName = ws.titleName;
  }

  sendTo(ws, { type: 'room_joined', roomId: room.id, roomName: room.name });
  broadcastRoomState(room.id);
  broadcastRoomList();
}

async function handleJoinRoom(ws, data) {
  if (!ws.playerId) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'login_required') });
    return;
  }
  if (ws.roomId) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'already_in_room') });
    return;
  }
  const room = lobby.getRoom(data.roomId);
  if (!room) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'room_not_found') });
    return;
  }
  // SK version gating
  if (!clientCanAccessRoom(ws, room)) {
    sendTo(ws, { type: 'error', message: roomAccessUpdateMessage(ws.locale, room, 'play') });
    return;
  }
  if (room.isRanked && ws.authProvider === 'local') {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'ranked_social_required') });
    return;
  }
  // Ranked ban check
  if (room.isRanked && ws.nickname) {
    const banMinutes = await getRankedBan(ws.nickname);
    if (banMinutes) {
      sendTo(ws, { type: 'error', message: t(ws.locale, 'ranked_ban', { minutes: banMinutes }) });
      return;
    }
  }
  const password = typeof data.password === 'string' ? data.password.trim() : '';
  const result = room.addPlayer(ws.playerId, ws.nickname, password);
  if (!result.success) {
    sendTo(ws, { type: 'error', message: resultMessage(result, ws.locale) });
    return;
  }
  ws.roomId = room.id;
  // Set title on joined player
  if (ws.titleKey) {
    const p = room.players.find(p => p !== null && p.id === ws.playerId);
    if (p) {
      p.titleKey = ws.titleKey;
      p.titleName = ws.titleName;
    }
  }
  sendTo(ws, { type: 'room_joined', roomId: room.id, roomName: room.name });
  // 채팅 히스토리 전송
  sendTo(ws, { type: 'chat_history', messages: room.getChatHistory() });
  broadcastRoomState(room.id);
  broadcastRoomList();
}

async function handleJoinRoomByInvite(ws, data) {
  const token = typeof data.token === 'string' ? data.token.trim() : '';
  if (!token) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'room_not_found') });
    return;
  }

  const payload = getInviteTokenPayload(token);
  if (!payload) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'room_not_found') });
    return;
  }

  await handleJoinRoom(ws, {
    roomId: payload.roomId,
    password: payload.password,
  });
}

function handleCreateShareInviteLink(ws) {
  if (!ws.playerId || !ws.roomId) {
    sendTo(ws, {
      type: 'share_invite_link_error',
      message: 'Join a room before sharing an invite link.',
    });
    return;
  }

  const room = lobby.getRoom(ws.roomId);
  if (!room) {
    sendTo(ws, {
      type: 'share_invite_link_error',
      message: t(ws.locale, 'room_not_found'),
    });
    return;
  }
  if (room.game) {
    sendTo(ws, {
      type: 'share_invite_link_error',
      message: 'Room invites can only be shared before the game starts.',
    });
    return;
  }

  const token = createInviteToken(room, ws.nickname || 'A friend');
  sendTo(ws, {
    type: 'share_invite_link',
    url: `${INVITE_BASE_URL}/invite?t=${encodeURIComponent(token)}`,
  });
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
  if (ws.nickname) {
    spectatorSessions.delete(ws.nickname);
  }
  ws.roomId = null;
  ws.isSpectator = false;
  if (room) {
    if (wasSpectating) {
      room.removeSpectator(ws.playerId);
      if (room.game) {
        _broadcastState(roomId, room);
      }
      broadcastRoomState(roomId);
    } else {
      // S6: If game is active and not already deserted, treat as desertion
      if (room.game && room.game.state !== 'game_end' && !room.game.deserted) {
        await handleDesertion(roomId, ws.playerId);
        // handleDesertion already removes player and cleans up
      } else {
        room.removePlayer(ws.playerId);
      }
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
  // Spectators should use leave_room, but handle gracefully
  if (ws.isSpectator) {
    return handleLeaveRoom(ws);
  }
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
    spectatorSessions.delete(ws.nickname);
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
    sendTo(ws, { type: 'error', message: t(ws.locale, 'not_in_room') });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room) {
    ws.roomId = null;
    sendTo(ws, { type: 'room_closed' });
    return;
  }
  // Already in lobby (auto-return or another player already triggered it)
  if (!room.game) return;
  // Only allow when game has ended
  if (room.game.state !== 'game_end') {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'game_still_in_progress') });
    return;
  }
  // Clear the game and reset ready states
  room.game = null;
  room.resetReady();
  clearTurnTimer(ws.roomId);
  broadcastRoomState(ws.roomId);
  broadcastRoomList();
}

// Auto return to room 3 seconds after game_end
const autoReturnTimers = {};
function scheduleAutoReturnToRoom(roomId) {
  if (autoReturnTimers[roomId]) return; // Already scheduled
  autoReturnTimers[roomId] = setTimeout(() => {
    delete autoReturnTimers[roomId];
    const room = lobby.getRoom(roomId);
    if (!room) return;
    if (!room.game || room.game.state !== 'game_end') return;
    room.game = null;
    room.resetReady();
    clearTurnTimer(roomId);

    // If no connected human players remain, remove the zombie room
    const hasConnectedHuman = room.players.some(p => p !== null && !p.isBot && p.connected);
    if (!hasConnectedHuman) {
      removeRoomAndNotifySpectators(roomId);
      broadcastRoomList();
      return;
    }

    broadcastRoomState(roomId);
    broadcastRoomList();
  }, 3000);
}

function handleCheckRoom(ws) {
  if (!ws.roomId) {
    sendTo(ws, { type: 'room_closed' });
    sendTo(ws, { type: 'restore_complete', destination: 'lobby' });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room) {
    ws.roomId = null;
    sendTo(ws, { type: 'room_closed' });
    sendTo(ws, { type: 'restore_complete', destination: 'lobby' });
    return;
  }
  // Room exists - send current state
  sendTo(ws, { type: 'room_state', room: room.getState() });
  // S27: Also send game state if game is active
  if (room.game) {
    const spectatorList = room.spectators.map((s) => ({ id: s.id, nickname: s.nickname }));
    if (ws.isSpectator) {
      const state = room.game.getStateForSpectator(room.getPermittedPlayers(ws.playerId));
      state.turnDeadline = room.turnDeadline;
      state.spectators = spectatorList;
      state.spectatorCount = room.spectators.length;
      sendTo(ws, { type: 'spectator_game_state', state });
    } else {
      const state = room.game.getStateForPlayer(ws.playerId);
      state.turnDeadline = room.turnDeadline;
      state.cardViewers = room.getViewersForPlayer(ws.playerId);
      state.spectators = spectatorList;
      state.spectatorCount = room.spectators.length;
      sendTo(ws, { type: 'game_state', state });
    }
    sendTo(ws, {
      type: 'restore_complete',
      destination: ws.isSpectator ? 'spectator' : 'game',
    });
    return;
  }
  sendTo(ws, {
    type: 'restore_complete',
    destination: ws.isSpectator ? 'spectator' : 'waiting_room',
  });
}

function handleSpectateRoom(ws, data) {
  if (!ws.playerId) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'login_required') });
    return;
  }
  if (ws.roomId) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'already_in_room') });
    return;
  }
  const room = lobby.getRoom(data.roomId);
  if (!room) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'room_not_found') });
    return;
  }
  // SK version gating for spectators
  if (!clientCanAccessRoom(ws, room)) {
    sendTo(ws, { type: 'error', message: roomAccessUpdateMessage(ws.locale, room, 'spectate') });
    return;
  }
  const password = typeof data.password === 'string' ? data.password.trim() : '';
  const result = room.addSpectator(ws.playerId, ws.nickname, password);
  if (!result.success) {
    sendTo(ws, { type: 'error', message: resultMessage(result, ws.locale) });
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
    sendTo(ws, { type: 'error', message: t(ws.locale, 'not_spectating') });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room) return;

  const playerId = data.playerId;
  const result = room.requestCardView(ws.playerId, ws.nickname, playerId);
  if (!result.success) {
    sendTo(ws, { type: 'error', message: resultMessage(result, ws.locale) });
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

  const timerKey = `${playerId}:${ws.playerId}`;
  room.cardRequestTimers[timerKey] = setTimeout(() => {
    const expired = room.expireCardViewRequest(playerId, ws.playerId);
    if (!expired.success) return;
    const spectatorWs = findWsByPlayerId(ws.playerId);
    if (spectatorWs) {
      sendTo(spectatorWs, {
        type: 'card_view_response',
        playerId,
        playerNickname: playerWs?.nickname || '',
        allowed: false,
      });
      sendTo(spectatorWs, {
        type: 'error',
        message: t(ws.locale, 'card_view_timeout'),
      });
    }
  }, 5000);

  sendTo(ws, { type: 'card_view_requested', playerId });
}

function handleRespondCardView(ws, data) {
  if (!ws.roomId) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'not_in_room') });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room) return;

  const spectatorId = data.spectatorId;
  const allow = data.allow === true;

  const result = room.respondCardViewRequest(ws.playerId, spectatorId, allow);
  if (!result.success) {
    sendTo(ws, { type: 'error', message: resultMessage(result, ws.locale) });
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
    sendTo(ws, { type: 'error', message: t(ws.locale, 'not_in_room') });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room) return;

  const spectatorId = data.spectatorId;
  const result = room.revokeCardView(ws.playerId, spectatorId);
  if (!result.success) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'revoke_failed') });
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
    sendTo(ws, { type: 'error', message: t(ws.locale, 'not_in_room') });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room) { sendTo(ws, { type: 'room_closed' }); ws.roomId = null; return; }
  if (room.game) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'game_already_in_progress') });
    return;
  }
  if (room.hostId !== ws.playerId) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'host_only_start') });
    return;
  }
  if (room.gameType === 'skull_king' || room.gameType === 'love_letter') {
    if (room.getPlayerCount() < 2) {
      sendTo(ws, { type: 'error', message: t(ws.locale, 'min_players_required') });
      return;
    }
  } else if (room.gameType === 'mighty') {
    // Mighty needs the effective capacity filled (5 or 6 depending on blocked slots)
    if (room.getPlayerCount() < room.getEffectiveMaxPlayers()) {
      sendTo(ws, { type: 'error', message: t(ws.locale, 'four_players_required') });
      return;
    }
  } else {
    if (room.getPlayerCount() < room.maxPlayers) {
      sendTo(ws, { type: 'error', message: t(ws.locale, 'four_players_required') });
      return;
    }
  }
  if (!room.areAllReady()) {
    broadcastGameEvent(ws.roomId, { type: 'error', message: t(ws.locale, 'all_players_must_ready') });
    return;
  }
  // Cancel waiting room timers and register sessions for disconnected players
  for (const player of room.players) {
    if (player === null || player.isBot) continue;
    const timerKey = `${ws.roomId}_${player.id}`;
    if (waitingRoomTimers[timerKey]) {
      clearTimeout(waitingRoomTimers[timerKey]);
      delete waitingRoomTimers[timerKey];
    }
    if (player.connected === false) {
      playerSessions.set(player.nickname, {
        roomId: ws.roomId,
        disconnectedAt: Date.now(),
      });
    }
  }
  room.startGame();
  broadcastRoomState(ws.roomId);
  broadcastRoomList();
  // Send initial cards to each player
  sendGameStateToAll(ws.roomId);
}

function handleChangeRoomName(ws, data) {
  if (!ws.roomId) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'not_in_room') });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'room_not_found') });
    return;
  }
  if (room.hostId !== ws.playerId) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'host_only_change') });
    return;
  }
  const rawName = typeof data.roomName === 'string' ? data.roomName.trim() : '';
  if (!rawName) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'room_name_required') });
    return;
  }
  const newName = rawName.slice(0, 20);
  room.setName(newName);
  broadcastRoomState(room.id);
  broadcastRoomList();
}

function handleChangeTeam(ws, data) {
  if (!ws.roomId) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'not_in_room') });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room) { sendTo(ws, { type: 'room_closed' }); ws.roomId = null; return; }
  if (room.isRanked) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'no_team_change_ranked') });
    return;
  }
  if (room.game) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'no_team_change_in_game') });
    return;
  }
  const targetSlot = data.targetSlot;
  if (typeof targetSlot !== 'number' || targetSlot < 0 || targetSlot >= room.maxPlayers) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'invalid_slot') });
    return;
  }
  const result = room.movePlayerToSlot(ws.playerId, targetSlot);
  if (!result.success) {
    sendTo(ws, { type: 'error', message: resultMessage(result, ws.locale) });
    return;
  }
  broadcastRoomState(ws.roomId);
}

// Kick player handler (host only, not during game)
function handleKickPlayer(ws, data) {
  if (!ws.roomId) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'not_in_room') });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room) { sendTo(ws, { type: 'room_closed' }); ws.roomId = null; return; }
  if (room.hostId !== ws.playerId) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'host_only_kick') });
    return;
  }
  if (room.game) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'no_kick_in_game') });
    return;
  }
  const targetPlayerId = data.playerId;
  if (!targetPlayerId || targetPlayerId === ws.playerId) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'cannot_kick_self') });
    return;
  }
  // Check if target is in the room
  if (!room.players.some(p => p !== null && p.id === targetPlayerId)) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'player_not_found') });
    return;
  }
  // Send kicked message to target before removing
  const targetWs = findWsByPlayerId(targetPlayerId);
  if (targetWs) {
    sendTo(targetWs, { type: 'kicked', message: t(targetWs.locale, 'kicked_by_host') });
    targetWs.roomId = null;
  }
  room.removePlayer(targetPlayerId);
  broadcastRoomState(ws.roomId);
  broadcastRoomList();
}

// Add bot handler (host only)
function handleAddBot(ws, data) {
  if (!ws.roomId) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'not_in_room') });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room) { sendTo(ws, { type: 'room_closed' }); ws.roomId = null; return; }
  if (room.hostId !== ws.playerId) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'host_only_add_bot') });
    return;
  }
  if (room.isRanked) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'no_bot_in_ranked') });
    return;
  }
  const targetSlot = typeof data.targetSlot === 'number' ? data.targetSlot : undefined;
  const speed = typeof data.speed === 'string' ? data.speed : 'normal';
  const result = room.addBot(targetSlot, ws.locale, speed);
  if (!result.success) {
    sendTo(ws, { type: 'error', message: resultMessage(result, ws.locale) });
    return;
  }
  broadcastRoomState(ws.roomId);
  broadcastRoomList();
}

function handleBlockSlot(ws, data) {
  if (!ws.roomId) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'not_in_room') });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room) { sendTo(ws, { type: 'room_closed' }); ws.roomId = null; return; }
  const slotIndex = typeof data.slotIndex === 'number' ? data.slotIndex : -1;
  const result = room.blockSlot(ws.playerId, slotIndex);
  if (!result.success) {
    sendTo(ws, { type: 'error', message: resultMessage(result, ws.locale) });
    return;
  }
  broadcastRoomState(ws.roomId);
  broadcastRoomList();
}

function handleUnblockSlot(ws, data) {
  if (!ws.roomId) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'not_in_room') });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room) { sendTo(ws, { type: 'room_closed' }); ws.roomId = null; return; }
  const slotIndex = typeof data.slotIndex === 'number' ? data.slotIndex : -1;
  const result = room.unblockSlot(ws.playerId, slotIndex);
  if (!result.success) {
    sendTo(ws, { type: 'error', message: resultMessage(result, ws.locale) });
    return;
  }
  broadcastRoomState(ws.roomId);
  broadcastRoomList();
}

// Switch to spectator handler
function handleSwitchToSpectator(ws) {
  if (!ws.roomId || ws.isSpectator) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'not_player_in_room') });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room) { sendTo(ws, { type: 'room_closed' }); ws.roomId = null; return; }
  const result = room.switchToSpectator(ws.playerId);
  if (!result.success) {
    sendTo(ws, { type: 'error', message: resultMessage(result, ws.locale) });
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
    sendTo(ws, { type: 'error', message: t(ws.locale, 'not_spectating') });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room) { sendTo(ws, { type: 'room_closed' }); ws.roomId = null; return; }
  if (!clientCanAccessRoom(ws, room)) {
    sendTo(ws, { type: 'error', message: roomAccessUpdateMessage(ws.locale, room, 'join') });
    return;
  }
  if (room.isRanked && ws.authProvider === 'local') {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'ranked_social_required') });
    return;
  }
  const targetSlot = data.targetSlot;
  if (typeof targetSlot !== 'number') {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'invalid_slot') });
    return;
  }
  const result = room.switchToPlayer(ws.playerId, ws.nickname, targetSlot);
  if (!result.success) {
    sendTo(ws, { type: 'error', message: resultMessage(result, ws.locale) });
    return;
  }
  ws.isSpectator = false;
  // Set title on player slot
  if (ws.titleKey) {
    const p = room.players[targetSlot];
    if (p) {
      p.titleKey = ws.titleKey;
      p.titleName = ws.titleName;
    }
  }
  sendTo(ws, { type: 'switched_to_player', roomId: room.id, roomName: room.name });
  broadcastRoomState(ws.roomId);
  broadcastRoomList();
}

// Get user profile handler
async function handleGetProfile(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'login_required') });
    return;
  }
  const targetNickname = data.nickname;
  if (!targetNickname) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'nickname_required') });
    return;
  }
  const profile = await getUserProfile(targetNickname);
  const recentMatches = await getRecentMatches(targetNickname, 20);
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
    sendTo(ws, { type: 'error', message: t(ws.locale, 'not_in_room') });
    return;
  }
  if (ws.isSpectator) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'spectator_no_action') });
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
  // SK: submit_bid is a phase action (simultaneous), play_card clears timer
  // Mighty: submit_bid IS turn-based (not simultaneous), so it should clear the timer
  const phaseActions = ['pass_large_tichu', 'declare_large_tichu', 'exchange_cards', 'declare_small_tichu', 'effect_ack', 'select_target', 'guard_guess'];
  if (room.gameType !== 'mighty') phaseActions.push('submit_bid');
  const prevPhase = room.game.state;

  if (data.type === 'next_round') {
    if (room.hostId !== ws.playerId) {
      sendTo(ws, { type: 'error', message: t(ws.locale, 'host_only_next_round') });
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
      sendTo(ws, { type: 'error', message: resultMessage(result, ws.locale) });
      return;
    }
    sendGameStateToAll(ws.roomId);
    return;
  }

  const result = room.game.handleAction(ws.playerId, data);
  if (!result.success) {
    sendTo(ws, { type: 'error', message: resultMessage(result, ws.locale) });
    return;
  }

  // Clear turn timer only after action confirmed valid
  if (!phaseActions.includes(data.type)) {
    clearTurnTimer(ws.roomId);
  }

  // Clear phase timer if phase changed (e.g. bidding → playing)
  if (room.game.state !== prevPhase && turnTimerPhases[ws.roomId]) {
    clearTurnTimer(ws.roomId);
  }

  // Broadcast updated game state
  if (result.broadcast) {
    broadcastGameEvent(ws.roomId, result.broadcast);
  }
  sendGameStateToAll(ws.roomId);

  // Check for game end and save match result
  if (room.game && room.game.state === 'game_end') {
    saveGameResult(room);
    scheduleAutoReturnToRoom(ws.roomId);
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

  if (room.gameType === 'skull_king') {
    return saveSKGameResult(room);
  }

  // Love Letter: no separate DB save for now (uses SK format)
  if (room.gameType === 'love_letter') {
    return saveLLGameResult(room);
  }

  if (room.gameType === 'mighty') {
    return saveMightyGameResult(room);
  }

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
    await saveMatchResultWithStats(
      {
        winnerTeam,
        teamAScore: totalScores.teamA,
        teamBScore: totalScores.teamB,
        playerA1: playerNames[teamAPlayers[0]] || '',
        playerA2: playerNames[teamAPlayers[1]] || '',
        playerB1: playerNames[teamBPlayers[0]] || '',
        playerB2: playerNames[teamBPlayers[1]] || '',
        isRanked: room.isRanked,
        endReason: 'normal',
      },
      [
        ...teamAPlayers.map((pid) => ({
          nickname: playerNames[pid] || '',
          won: winnerTeam === 'A',
          team: 'A',
          isRanked: room.isRanked,
          isBot: pid.startsWith('bot_'),
        })),
        ...teamBPlayers.map((pid) => ({
          nickname: playerNames[pid] || '',
          won: winnerTeam === 'B',
          team: 'B',
          isRanked: room.isRanked,
          isBot: pid.startsWith('bot_'),
        })),
      ],
    );
    console.log(`Match result saved for room ${room.name}`);
  } catch (err) {
    console.error('Error saving match result:', err);
  }
}

async function saveSKGameResult(room) {
  try {
    const game = room.game;
    const rankings = game.getRankings();
    const isRanked = room.isRanked;

    const winCutoff = Math.floor(game.playerCount / 2);
    await saveSKMatchResultWithStats({
      playerCount: game.playerCount,
      isRanked,
      endReason: 'normal',
      deserterNickname: null,
      players: rankings.map(r => ({
        nickname: r.nickname,
        score: r.score,
        rank: r.rank,
        isWinner: r.rank <= winCutoff,
        isBot: r.playerId.startsWith('bot_'),
      })),
    });

    console.log(`SK match result saved for room ${room.name}`);
  } catch (err) {
    console.error('Error saving SK match result:', err);
  }
}

async function saveLLGameResult(room) {
  try {
    const game = room.game;
    const rankings = game.getRankings();

    await saveLLMatchResultWithStats({
      playerCount: game.playerCount,
      isRanked: false,
      endReason: 'normal',
      deserterNickname: null,
      players: rankings.map(r => ({
        nickname: r.nickname,
        score: r.score,
        rank: r.rank,
        isWinner: r.rank === 1,
        isBot: r.playerId.startsWith('bot_'),
      })),
    });

    console.log(`LL match result saved for room ${room.name}`);
  } catch (err) {
    console.error('Error saving LL match result:', err);
  }
}

function buildMightyPlayers(game, deserterId = null) {
  const partnerId = game.partner || null;
  const declarerTeam = new Set([game.declarer, partnerId].filter(Boolean));
  const declarerWon = game.roundResult?.success === true;
  const allPlayers = game.playerIds.map((pid) => ({
    playerId: pid,
    nickname: game.playerNames[pid] || pid,
    score: game.scores[pid] || 0,
    isWinner: declarerTeam.size === 0
      ? false
      : declarerWon
        ? declarerTeam.has(pid)
        : !declarerTeam.has(pid),
    isBot: pid.startsWith('bot_'),
  }));

  if (deserterId) {
    const deserterIdx = allPlayers.findIndex((p) => p.playerId === deserterId);
    if (deserterIdx >= 0) {
      const [deserter] = allPlayers.splice(deserterIdx, 1);
      allPlayers.sort((a, b) => b.score - a.score || a.nickname.localeCompare(b.nickname));
      const rankedPlayers = [];
      let currentRank = 1;
      for (let i = 0; i < allPlayers.length; i++) {
        if (i > 0 && allPlayers[i].score < allPlayers[i - 1].score) {
          currentRank = i + 1;
        }
        rankedPlayers.push({ ...allPlayers[i], rank: currentRank });
      }
      rankedPlayers.push({ ...deserter, rank: game.playerCount, isWinner: false });
      return rankedPlayers;
    }
  }

  allPlayers.sort((a, b) => b.score - a.score || a.nickname.localeCompare(b.nickname));
  let currentRank = 1;
  return allPlayers.map((player, index) => {
    if (index > 0 && player.score < allPlayers[index - 1].score) {
      currentRank = index + 1;
    }
    return { ...player, rank: currentRank };
  });
}

function buildMightyMatchPayload(room, { endReason = 'normal', deserterNickname = null, deserterId = null } = {}) {
  const game = room.game;
  return {
    playerCount: game.playerCount,
    isRanked: room.isRanked,
    endReason,
    deserterNickname,
    declarerNickname: game.declarer ? (game.playerNames[game.declarer] || game.declarer) : null,
    partnerNickname: game.partner ? (game.playerNames[game.partner] || game.partner) : null,
    declarerTeamSuccess: game.roundResult?.success === true,
    declarerTeamPoints: game.roundResult?.declarerPoints || 0,
    bidPoints: game.currentBid?.points || 0,
    trumpSuit: game.trumpSuit || null,
    players: buildMightyPlayers(game, deserterId).map(({ playerId, ...player }) => player),
  };
}

async function saveMightyGameResult(room) {
  try {
    await saveMightyMatchResultWithStats(buildMightyMatchPayload(room));
    console.log(`Mighty match result saved for room ${room.name}`);
  } catch (err) {
    console.error('Error saving Mighty match result:', err);
  }
}

function sendGameStateToAll(roomId) {
  const room = lobby.getRoom(roomId);
  if (!room || !room.game) return;
  if (room.game.state !== 'trick_end' && trickEndTimers[roomId]) {
    clearTimeout(trickEndTimers[roomId]);
    delete trickEndTimers[roomId];
  }

  // Love Letter: auto-advance effect_resolve after resolved effects
  if (room.gameType === 'love_letter' && room.game.state === 'effect_resolve'
      && room.game.pendingEffect && room.game.pendingEffect.resolved) {
    if (trickEndTimers[roomId]) clearTimeout(trickEndTimers[roomId]);
    trickEndTimers[roomId] = setTimeout(() => {
      delete trickEndTimers[roomId];
      const r = lobby.getRoom(roomId);
      if (!r || !r.game || r.game.state !== 'effect_resolve') return;
      if (!r.game.pendingEffect || !r.game.pendingEffect.resolved) return;
      // Clear stale turn timer from the effect_resolve phase before advancing
      clearTurnTimer(roomId);
      // Auto-ack on behalf of the acting player
      const actingPlayer = r.game.pendingEffect.playerId;
      r.game.handleAction(actingPlayer, { type: 'effect_ack' });
      if (r.game.state === 'game_end') {
        saveGameResult(r);
        scheduleAutoReturnToRoom(roomId);
      }
      sendGameStateToAll(roomId);
    }, 2500);
    _broadcastState(roomId, room);
    return;
  }

  if (room.gameType === 'mighty' && room.game.state === 'trick_end') {
    if (trickEndTimers[roomId]) clearTimeout(trickEndTimers[roomId]);
    trickEndTimers[roomId] = setTimeout(() => {
      delete trickEndTimers[roomId];
      const r = lobby.getRoom(roomId);
      if (!r || !r.game || r.game.state !== 'trick_end') return;
      r.game.advanceAfterTrickEnd();
      if (r.game.state === 'game_end') {
        saveGameResult(r);
        scheduleAutoReturnToRoom(roomId);
      }
      sendGameStateToAll(roomId);
    }, 1500);
    _broadcastState(roomId, room);
    return;
  }

  if (room.gameType === 'skull_king' && room.game.state === 'trick_end') {
    if (trickEndTimers[roomId]) clearTimeout(trickEndTimers[roomId]);
    // Voided tricks (Kraken / White Whale) need a longer display window so
    // players can actually read the "트릭 무효" banner and effect reason.
    const trickEndDelay = room.game.lastTrickVoided ? 2500 : 1500;
    trickEndTimers[roomId] = setTimeout(() => {
      delete trickEndTimers[roomId];
      const r = lobby.getRoom(roomId);
      if (!r || !r.game || r.game.state !== 'trick_end') return;
      r.game.advanceAfterTrickEnd();
      if (r.game.state === 'game_end') {
        saveGameResult(r);
        scheduleAutoReturnToRoom(roomId);
      }
      sendGameStateToAll(roomId);
    }, trickEndDelay);
    _broadcastState(roomId, room);
    return;
  }

  // Auto next round after delay
  if (room.game.state === 'round_end') {
    if (roundEndTimers[roomId]) clearTimeout(roundEndTimers[roomId]);
    const roundEndDelay = room.gameType === 'skull_king' ? 5000 : room.gameType === 'love_letter' ? 4000 : room.gameType === 'mighty' ? 5000 : 3000;
    roundEndTimers[roomId] = setTimeout(() => {
      delete roundEndTimers[roomId];
      const r = lobby.getRoom(roomId);
      if (!r || !r.game || r.game.state !== 'round_end') return;
      r.game.nextRound();
      sendGameStateToAll(roomId);
    }, roundEndDelay);
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

function getBotBaseDelay(speed) {
  switch (speed) {
    case 'fast': return 300 + Math.floor(Math.random() * 300);    // 300-600ms (기존 속도)
    case 'slow': return 1200 + Math.floor(Math.random() * 600);   // 1200-1800ms
    default:     return 600 + Math.floor(Math.random() * 400);    // 600-1000ms
  }
}

function getBotExtraDelay(speed) {
  switch (speed) {
    case 'fast': return 200;   // 기존 속도
    case 'slow': return 800;
    default:     return 400;
  }
}

function scheduleBotActions(roomId) {
  const room = lobby.getRoom(roomId);
  if (!room || !room.game) return;
  if (room.getBotIds().length === 0) return;
  if (pendingBotCheck[roomId]) return; // Already scheduled

  pendingBotCheck[roomId] = true;

  // Quick check to find which bot needs to act and get its speed
  const isSK0 = room.gameType === 'skull_king';
  const isLL0 = room.gameType === 'love_letter';
  const isMighty0 = room.gameType === 'mighty';
  const decideFn0 = isMighty0 ? decideMightyBotAction : isLL0 ? decideLLBotAction : isSK0 ? decideSKBotAction : decideBotAction;
  let activeBotSpeed = 'normal';
  for (const botId of room.getBotIds()) {
    if (decideFn0(room.game, botId)) {
      const bot = room.bots.get(botId);
      activeBotSpeed = bot ? bot.speed : 'normal';
      break;
    }
  }

  const baseDelay = getBotBaseDelay(activeBotSpeed);

  setTimeout(() => {
    delete pendingBotCheck[roomId];
    const r = lobby.getRoom(roomId);
    if (!r || !r.game) return;

    // Re-evaluate at execution time
    const isSK = r.gameType === 'skull_king';
    const isLL = r.gameType === 'love_letter';
    const isMighty = r.gameType === 'mighty';
    const decideFn = isMighty ? decideMightyBotAction : isLL ? decideLLBotAction : isSK ? decideSKBotAction : decideBotAction;
    for (const botId of r.getBotIds()) {
      let action = decideFn(r.game, botId);
      if (action) {
        const bot = r.bots.get(botId);
        const botSpeed = bot ? bot.speed : 'normal';
        // Add extra delay for card play actions to feel more natural
        const isCardPlay = action.type === 'play_cards' || action.type === 'pass' || action.type === 'play_card';
        if (isCardPlay) {
          pendingBotCheck[roomId] = true;
          setTimeout(() => {
            delete pendingBotCheck[roomId];
            const r2 = lobby.getRoom(roomId);
            if (!r2 || !r2.game) return;
            // Re-decide in case state changed
            let action2 = decideFn(r2.game, botId);
            if (!action2) {
              // State changed (e.g. bomb interrupt) - re-schedule for other bots
              scheduleBotActions(roomId);
              return;
            }
            console.log(`[BOT] ${botId} action: ${action2.type}`);
            let result2 = r2.game.handleAction(botId, action2);
            if (result2 && !result2.success && r2.game) {
              console.log(`[BOT] ${botId} action failed: ${result2.messageKey || result2.message}, trying fallback`);
              const fallback2 = r2.game.getAutoTimeoutAction(botId);
              if (fallback2) {
                console.log(`[BOT] ${botId} fallback: ${fallback2.type}`);
                result2 = r2.game.handleAction(botId, fallback2);
              }
            }
            if (result2 && result2.success) {
              if (result2.broadcast) broadcastGameEvent(roomId, result2.broadcast);
              if (r2.game && r2.game.state === 'game_end') { saveGameResult(r2); scheduleAutoReturnToRoom(roomId); }
              sendGameStateToAll(roomId);
            }
          }, getBotExtraDelay(botSpeed));
          return;
        }
        console.log(`[BOT] ${botId} action: ${action.type}`);
        let result = r.game.handleAction(botId, action);
        // If bot's action failed (e.g. call obligation), use server's auto-action as fallback
        if (result && !result.success && r.game) {
          console.log(`[BOT] ${botId} action failed: ${result.messageKey || result.message}, trying fallback`);
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
            scheduleAutoReturnToRoom(roomId);
          }
          sendGameStateToAll(roomId); // This will re-trigger scheduleBotActions
          return; // One action at a time
        } else {
          // S11: Don't return on failure - let other bots try
          console.log(`[BOT] ${botId} action failed: ${result?.message}`);
        }
      }
    }
  }, baseDelay);
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

  // SK bidding phase: simultaneous bids with double time
  if (gameState === 'bidding' && room.gameType === 'skull_king') {
    if (turnTimerPhases[roomId] === 'sk_bidding') return;
    clearTurnTimer(roomId);
    const pending = room.game.playerIds.filter(
      pid => room.game.bids[pid] === null && !room.isBot(pid)
    );
    if (pending.length === 0) return;
    const timeLimit = room.turnTimeLimit * 2 * 1000;
    room.turnDeadline = Date.now() + timeLimit;
    turnTimerPhases[roomId] = 'sk_bidding';
    turnTimers[roomId] = setTimeout(() => {
      handlePhaseTimeout(roomId, 'sk_bidding');
    }, timeLimit);
    return;
  }

  // Mighty bidding: sequential turn-based (not simultaneous like SK)
  if (room.gameType === 'mighty' && gameState === 'bidding') {
    clearTurnTimer(roomId);
    const currentPlayer = room.game.currentPlayer;
    if (!currentPlayer || room.isBot(currentPlayer)) return;
    const timeLimit = room.turnTimeLimit * 1000;
    room.turnDeadline = Date.now() + timeLimit;
    turnTimers[roomId] = setTimeout(() => {
      handleTurnTimeout(roomId, currentPlayer);
    }, timeLimit);
    return;
  }

  // Mighty kitty exchange: declarer has double time
  if (room.gameType === 'mighty' && gameState === 'kitty_exchange') {
    clearTurnTimer(roomId);
    const declarer = room.game.declarer;
    if (!declarer || room.isBot(declarer)) return;
    const timeLimit = room.turnTimeLimit * 2 * 1000;
    room.turnDeadline = Date.now() + timeLimit;
    turnTimers[roomId] = setTimeout(() => {
      handleTurnTimeout(roomId, declarer);
    }, timeLimit);
    return;
  }

  // Love Letter: also set timer during effect_resolve (target/guess selection)
  if (room.gameType === 'love_letter' && gameState === 'effect_resolve') {
    if (turnTimers[roomId]) return; // Already has a timer
    const eff = room.game.pendingEffect;
    if (eff && !eff.resolved) {
      const targetPlayer = eff.playerId;
      if (!targetPlayer || room.isBot(targetPlayer)) return;
      const timeLimit = room.turnTimeLimit * 1000;
      room.turnDeadline = Date.now() + timeLimit;
      turnTimers[roomId] = setTimeout(() => {
        handleTurnTimeout(roomId, targetPlayer);
      }, timeLimit);
    }
    return;
  }

  if (gameState !== 'playing') {
    clearTurnTimer(roomId);
    return;
  }

  // If a phase timer was running (e.g. bidding), clear it before setting turn timer
  if (turnTimerPhases[roomId]) {
    clearTurnTimer(roomId);
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

  // SK bidding timeout: auto-submit bid 0
  if (phase === 'sk_bidding' && room.game.state === 'bidding') {
    const pending = room.game.playerIds.filter(
      pid => room.game.bids[pid] === null
    );
    for (const pid of pending) {
      room.game.handleAction(pid, { type: 'submit_bid', bid: 0 });
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
  const runSkullKingFallback = () => {
    if (!room.game || room.gameType !== 'skull_king') return false;
    if (room.game.state === 'bidding' && room.game.bids?.[playerId] === null) {
      const bidResult = room.game.handleAction(playerId, { type: 'submit_bid', bid: 0 });
      if (bidResult?.success) {
        if (bidResult.broadcast) broadcastGameEvent(roomId, bidResult.broadcast);
        sendGameStateToAll(roomId);
        return true;
      }
    }
    if (room.game.state === 'playing' && room.game.currentPlayer === playerId) {
      const legalCards = room.game.getLegalCards(playerId) || [];
      if (legalCards.length > 0) {
        const cardId = legalCards[Math.floor(Math.random() * legalCards.length)];
        const action = cardId === 'sk_tigress'
            ? {
                type: 'play_card',
                cardId,
                tigressChoice: Math.random() < 0.5 ? 'pirate' : 'escape',
              }
            : { type: 'play_card', cardId };
        const playResult = room.game.handleAction(playerId, action);
        if (playResult?.success) {
          if (playResult.broadcast) broadcastGameEvent(roomId, playResult.broadcast);
          if (room.game && room.game.state === 'game_end') {
            saveGameResult(room);
            scheduleAutoReturnToRoom(roomId);
          } else if (room.game) {
            sendGameStateToAll(roomId);
          }
          return true;
        }
      }
    }
    return false;
  };

  try {
    const action = room.game.getAutoTimeoutAction(playerId);
    if (action) {
      const result = room.game.handleAction(playerId, action);
      if (result && result.success) {
        if (result.broadcast) broadcastGameEvent(roomId, result.broadcast);
        if (room.game && room.game.state === 'game_end') {
          sendGameStateToAll(roomId);
          saveGameResult(room);
          scheduleAutoReturnToRoom(roomId);
        } else if (room.game) {
          sendGameStateToAll(roomId);
        }
      } else {
        console.log(`[TIMEOUT] Auto action failed for ${nickname}: ${result?.message}`);
        if (!runSkullKingFallback() && room.gameType === 'tichu') {
          // Force play call cards to prevent game from getting stuck (Tichu only)
          try {
            const forceResult = room.game.forcePlayCallCards(playerId);
            if (forceResult && forceResult.success) {
              if (forceResult.broadcast) broadcastGameEvent(roomId, forceResult.broadcast);
              if (room.game && room.game.state === 'game_end') {
                sendGameStateToAll(roomId);
                saveGameResult(room);
                scheduleAutoReturnToRoom(roomId);
              } else if (room.game) {
                sendGameStateToAll(roomId);
              }
            }
          } catch (e) {
            console.error(`[TIMEOUT] forcePlayCallCards failed for ${nickname}:`, e.message);
          }
        }
      }
    } else {
      console.log(`[TIMEOUT] No auto action for ${nickname} (currentPlayer: ${room.game.currentPlayer})`);
      runSkullKingFallback();
    }
  } catch (err) {
    console.error(`[TIMEOUT] Exception during auto action for ${nickname}:`, err);
    if (!runSkullKingFallback() && room.gameType === 'tichu') {
      // Force play call cards to prevent game from getting stuck (Tichu only)
      try { room.game.forcePlayCallCards(playerId); } catch (_) {}
    }
  }

  // Keep game progression alive after timeout handling.
  if (room.game && room.game.state === 'playing') {
    sendGameStateToAll(roomId);
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

  try {
    if (room.gameType === 'love_letter') {
      const deserterScore = game.tokens?.[playerId] ?? 0;
      const rankings = game.getRankings();
      const remaining = rankings.filter((r) => r.playerId !== playerId);
      const players = [];

      let currentRank = 1;
      for (let i = 0; i < remaining.length; i++) {
        if (i > 0 && remaining[i].score < remaining[i - 1].score) {
          currentRank = i + 1;
        }
        players.push({
          nickname: remaining[i].nickname,
          score: remaining[i].score,
          rank: currentRank,
          isWinner: false,
          isDraw: true,
          isBot: remaining[i].playerId.startsWith('bot_'),
        });
      }

      players.push({
        nickname: deserterNick || playerId,
        score: deserterScore,
        rank: game.playerCount,
        isWinner: false,
        isDraw: false,
        isBot: playerId.startsWith('bot_'),
      });

      await saveLLMatchResultWithStats({
        playerCount: game.playerCount,
        isRanked: false,
        endReason: reason,
        deserterNickname: deserterNick || null,
        players,
      });

      console.log(`LL desertion result saved for room ${room.name} by ${deserterNick}`);
    } else if (room.gameType === 'skull_king') {
      const deserterScore = game.totalScores[playerId] ?? 0;
      const rankings = game.getRankings();
      const remaining = rankings.filter((r) => r.playerId !== playerId);
      const players = [];

      let currentRank = 1;
      for (let i = 0; i < remaining.length; i++) {
        if (i > 0 && remaining[i].score < remaining[i - 1].score) {
          currentRank = i + 1;
        }
        players.push({
          nickname: remaining[i].nickname,
          score: remaining[i].score,
          rank: currentRank,
          isWinner: false,
          isDraw: true,
          isBot: remaining[i].playerId.startsWith('bot_'),
        });
      }

      players.push({
        nickname: deserterNick || playerId,
        score: deserterScore,
        rank: game.playerCount,
        isWinner: false,
        isDraw: false,
        isBot: playerId.startsWith('bot_'),
      });

      await saveSKMatchResultWithStats({
        playerCount: game.playerCount,
        isRanked: room.isRanked,
        endReason: reason,
        deserterNickname: deserterNick || null,
        players,
      });

    } else if (room.gameType === 'mighty') {
      const game = room.game;
      const deserterScore = game.scores[playerId] ?? 0;
      const remaining = game.playerIds.filter(pid => pid !== playerId);
      const players = [];

      // Remaining players get draw (no win/loss), sorted by score
      const sortedRemaining = remaining.map(pid => ({
        playerId: pid,
        nickname: game.playerNames[pid] || pid,
        score: game.scores[pid] || 0,
        isBot: pid.startsWith('bot_'),
      })).sort((a, b) => b.score - a.score || a.nickname.localeCompare(b.nickname));

      let currentRank = 1;
      for (let i = 0; i < sortedRemaining.length; i++) {
        if (i > 0 && sortedRemaining[i].score < sortedRemaining[i - 1].score) {
          currentRank = i + 1;
        }
        players.push({
          nickname: sortedRemaining[i].nickname,
          score: sortedRemaining[i].score,
          rank: currentRank,
          isWinner: false,
          isDraw: true,
          isBot: sortedRemaining[i].isBot,
        });
      }

      // Deserter gets last rank, loss
      players.push({
        nickname: deserterNick || playerId,
        score: deserterScore,
        rank: game.playerCount,
        isWinner: false,
        isDraw: false,
        isBot: playerId.startsWith('bot_'),
      });

      await saveMightyMatchResultWithStats({
        playerCount: game.playerCount,
        isRanked: room.isRanked,
        endReason: reason,
        deserterNickname: deserterNick || null,
        declarerNickname: game.declarer ? (game.playerNames[game.declarer] || game.declarer) : null,
        partnerNickname: game.partner ? (game.playerNames[game.partner] || game.partner) : null,
        declarerTeamSuccess: false,
        declarerTeamPoints: 0,
        bidPoints: game.currentBid?.points || 0,
        trumpSuit: game.trumpSuit || null,
        players,
      });
      console.log(`Mighty desertion result saved for room ${room.name} by ${deserterNick}`);
    } else {
      const totalScores = game.totalScores;
      const teams = game.teams;
      const playerNames = game.playerNames;
      const teamAPlayers = teams.teamA;
      const teamBPlayers = teams.teamB;

      const statsPlayers = [
        ...teamAPlayers.map(pid => ({
          nickname: playerNames[pid] || '',
          won: false,
          isDraw: pid !== playerId,
          team: 'A',
          isRanked: room.isRanked,
          isBot: pid.startsWith('bot_'),
        })),
        ...teamBPlayers.map(pid => ({
          nickname: playerNames[pid] || '',
          won: false,
          isDraw: pid !== playerId,
          team: 'B',
          isRanked: room.isRanked,
          isBot: pid.startsWith('bot_'),
        })),
      ];

      await saveMatchResultWithStats(
        {
          winnerTeam: 'draw',
          teamAScore: totalScores.teamA,
          teamBScore: totalScores.teamB,
          playerA1: playerNames[teamAPlayers[0]] || '',
          playerA2: playerNames[teamAPlayers[1]] || '',
          playerB1: playerNames[teamBPlayers[0]] || '',
          playerB2: playerNames[teamBPlayers[1]] || '',
          isRanked: room.isRanked,
          endReason: reason,
          deserterNickname: deserterNick || null,
        },
        statsPlayers,
      );
    }
  } catch (err) {
    console.error('Error saving desertion result:', err);
  }

  // Force game end
  game.state = 'game_end';
  game.deserted = true;

  sendGameStateToAll(roomId);
  scheduleAutoReturnToRoom(roomId);
  delete timeoutCounts[roomId];

  // Remove deserter from room (including host)
  if (deserterNick) {
    playerSessions.delete(deserterNick);
  }
  const deserterWs = findWsByPlayerId(playerId);
  if (deserterWs) {
    const kickMessage = reason === 'timeout'
      ? t(deserterWs.locale, 'kicked_timeout_3x')
      : t(deserterWs.locale, 'kicked_desertion');
    sendTo(deserterWs, { type: 'kicked', message: kickMessage });
    deserterWs.roomId = null;
  }
  room.removePlayer(playerId);

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

// Notify all connected participants and remove room
function closeRoom(roomId, messageType = 'room_closed') {
  const room = lobby.getRoom(roomId);
  if (room) {
    for (const player of room.players) {
      if (player === null || room.isBot(player.id)) continue;
      const ws = findWsByPlayerId(player.id);
      if (ws) {
        sendTo(ws, { type: messageType });
        ws.roomId = null;
        ws.isSpectator = false;
      }
    }
    for (const spectator of room.spectators) {
      const ws = findWsByPlayerId(spectator.id);
      if (ws) {
        sendTo(ws, { type: messageType });
        ws.roomId = null;
        ws.isSpectator = false;
      }
    }
  }
  if (autoReturnTimers[roomId]) {
    clearTimeout(autoReturnTimers[roomId]);
    delete autoReturnTimers[roomId];
  }
  if (trickEndTimers[roomId]) {
    clearTimeout(trickEndTimers[roomId]);
    delete trickEndTimers[roomId];
  }
  if (turnTimers[roomId]) {
    clearTimeout(turnTimers[roomId]);
    delete turnTimers[roomId];
  }
  if (roundEndTimers[roomId]) {
    clearTimeout(roundEndTimers[roomId]);
    delete roundEndTimers[roomId];
  }
  Object.keys(waitingRoomTimers).forEach((key) => {
    if (!key.startsWith(`${roomId}_`)) return;
    clearTimeout(waitingRoomTimers[key]);
    delete waitingRoomTimers[key];
  });
  delete timeoutCounts[roomId];
  delete turnTimerPhases[roomId];
  lobby.removeRoom(roomId);
}

function removeRoomAndNotifySpectators(roomId) {
  closeRoom(roomId);
}

function broadcastRoomList() {
  const allRooms = lobby.getRoomList();
  wss.clients.forEach((ws) => {
    if (ws.playerId && !ws.roomId) {
      // Filter SK / SK-expansion rooms for old clients.
      const rooms = filterRoomsForClient(ws, allRooms);
      sendTo(ws, { type: 'room_list', rooms });
    }
  });
}

// Chat message handler
async function handleChatMessage(ws, data) {
  if (!ws.roomId || !ws.nickname) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'not_in_room') });
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

  // Get list of users who blocked the sender (to filter them out)
  let blockedBySender = [];
  try {
    const { pool } = require('./db/database');
    const { rows } = await pool.query(
      'SELECT blocker_nickname FROM tc_blocked_users WHERE blocked_nickname = $1',
      [ws.nickname]
    );
    blockedBySender = rows.map(r => r.blocker_nickname);
  } catch (e) { /* ignore - send to all on error */ }

  const blockedSet = new Set(blockedBySender);

  // Broadcast to all players in the room
  room.getPlayerIds().forEach(playerId => {
    const playerWs = findWsByPlayerId(playerId);
    if (playerWs && !blockedSet.has(playerWs.nickname)) {
      sendTo(playerWs, chatData);
    }
  });

  // Also send to spectators
  room.getSpectatorIds().forEach(specId => {
    const specWs = findWsByPlayerId(specId);
    if (specWs && !blockedSet.has(specWs.nickname)) {
      sendTo(specWs, chatData);
    }
  });
}

// Block user handler
async function handleBlockUser(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'login_required') });
    return;
  }
  const targetNickname = data.nickname;
  if (!targetNickname || targetNickname === ws.nickname) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'cannot_block') });
    return;
  }
  const result = await blockUser(ws.nickname, targetNickname);
  sendTo(ws, { type: 'block_result', success: result.success, nickname: targetNickname, blocked: true });
}

// Unblock user handler
async function handleUnblockUser(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'login_required') });
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
    sendTo(ws, { type: 'error', message: t(ws.locale, 'login_required') });
    return;
  }
  const targetNickname = data.nickname;
  const reason = data.reason || '';
  if (!targetNickname || targetNickname === ws.nickname) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'cannot_report') });
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
  sendTo(ws, {
    type: 'report_result',
    success: result.success,
    message: resultMessage(result, ws.locale),
  });
  if (result.success) {
    await notifyAdminUsers(
      'report',
      'New Report',
      `${ws.nickname} reported ${targetNickname}`,
      { reporter: ws.nickname, target: targetNickname, roomId: ws.roomId || '' }
    );
  }
}

// Rankings handler
async function handleGetRankings(ws, data) {
  const gameType = data?.gameType || 'tichu';

  // SK rankings
  if (gameType === 'skull_king') {
    const seasonId = data?.seasonId;
    let result;
    let isSeason = false;
    if (seasonId === 'current') {
      // Explicitly request current season rankings
      result = await getCurrentSKSeasonRankings(50);
      isSeason = true;
    } else if (seasonId) {
      result = await getSKSeasonRankings(seasonId, 50);
      isSeason = true;
    } else {
      // No seasonId: return all-time SK rankings (backward compatible)
      result = await getSKRankings(50);
    }
    // Calculate requester's SK rank
    if (ws.nickname && result.success && !seasonId) {
      const { pool } = require('./db/database');
      try {
        const myRankRes = await pool.query(
          `SELECT COUNT(*) + 1 AS rank FROM tc_users
           WHERE is_deleted IS NOT TRUE AND sk_total_games > 0
             AND ((sk_rating > (SELECT sk_rating FROM tc_users WHERE nickname = $1))
              OR (sk_rating = (SELECT sk_rating FROM tc_users WHERE nickname = $1)
                  AND sk_wins > (SELECT sk_wins FROM tc_users WHERE nickname = $1)))`,
          [ws.nickname]
        );
        const myProfileRes = await pool.query(
          `SELECT u.nickname, u.sk_rating AS rating, u.sk_wins AS wins,
                  u.sk_losses AS losses, u.sk_total_games AS total_games,
                  CASE WHEN u.sk_total_games > 0
                    THEN ROUND((u.sk_wins::FLOAT / u.sk_total_games) * 100)
                    ELSE 0 END AS win_rate,
                  e.banner_key
           FROM tc_users u
           LEFT JOIN tc_user_equips e ON e.nickname = u.nickname
           WHERE u.nickname = $1`,
          [ws.nickname]
        );
        if (myProfileRes.rows.length > 0) {
          result.myRank = parseInt(myRankRes.rows[0].rank);
          result.myRankData = myProfileRes.rows[0];
        }
      } catch (_) {}
    }
    // Calculate requester's SK season rank
    if (ws.nickname && result.success && isSeason && seasonId === 'current') {
      const { pool } = require('./db/database');
      try {
        const myRankRes = await pool.query(
          `SELECT COUNT(*) + 1 AS rank FROM tc_users
           WHERE is_deleted IS NOT TRUE AND sk_season_games > 0
             AND ((sk_season_rating > (SELECT sk_season_rating FROM tc_users WHERE nickname = $1))
              OR (sk_season_rating = (SELECT sk_season_rating FROM tc_users WHERE nickname = $1)
                  AND sk_season_wins > (SELECT sk_season_wins FROM tc_users WHERE nickname = $1)))`,
          [ws.nickname]
        );
        const myProfileRes = await pool.query(
          `SELECT u.nickname, u.sk_season_rating AS rating, u.sk_season_wins AS wins,
                  u.sk_season_losses AS losses, u.sk_season_games AS total_games,
                  CASE WHEN u.sk_season_games > 0
                    THEN ROUND((u.sk_season_wins::FLOAT / u.sk_season_games) * 100)
                    ELSE 0 END AS win_rate,
                  e.banner_key
           FROM tc_users u
           LEFT JOIN tc_user_equips e ON e.nickname = u.nickname
           WHERE u.nickname = $1`,
          [ws.nickname]
        );
        if (myProfileRes.rows.length > 0) {
          result.myRank = parseInt(myRankRes.rows[0].rank);
          result.myRankData = myProfileRes.rows[0];
        }
      } catch (_) {}
    }
    sendTo(ws, { type: 'rankings_result', gameType: 'skull_king', ...result });
    return;
  }

  // Mighty rankings
  if (gameType === 'mighty') {
    const seasonId = data?.seasonId;
    let result;
    let isSeason = false;
    if (seasonId === 'current') {
      result = await getCurrentMightySeasonRankings(50);
      isSeason = true;
    } else if (seasonId) {
      result = await getMightySeasonRankings(seasonId, 50);
      isSeason = true;
    } else {
      result = await getMightyRankings(50);
    }
    // Calculate requester's Mighty rank (all-time)
    if (ws.nickname && result.success && !seasonId) {
      const { pool } = require('./db/database');
      try {
        const myRankRes = await pool.query(
          `SELECT COUNT(*) + 1 AS rank FROM tc_users
           WHERE is_deleted IS NOT TRUE AND mighty_total_games > 0
             AND ((mighty_rating > (SELECT mighty_rating FROM tc_users WHERE nickname = $1))
              OR (mighty_rating = (SELECT mighty_rating FROM tc_users WHERE nickname = $1)
                  AND mighty_wins > (SELECT mighty_wins FROM tc_users WHERE nickname = $1)))`,
          [ws.nickname]
        );
        const myProfileRes = await pool.query(
          `SELECT u.nickname, u.mighty_rating AS rating, u.mighty_wins AS wins,
                  u.mighty_losses AS losses, u.mighty_total_games AS total_games,
                  CASE WHEN u.mighty_total_games > 0
                    THEN ROUND((u.mighty_wins::FLOAT / u.mighty_total_games) * 100)
                    ELSE 0 END AS win_rate,
                  e.banner_key
           FROM tc_users u
           LEFT JOIN tc_user_equips e ON e.nickname = u.nickname
           WHERE u.nickname = $1`,
          [ws.nickname]
        );
        if (myProfileRes.rows.length > 0) {
          result.myRank = parseInt(myRankRes.rows[0].rank);
          result.myRankData = myProfileRes.rows[0];
        }
      } catch (_) {}
    }
    // Calculate requester's Mighty season rank
    if (ws.nickname && result.success && isSeason && seasonId === 'current') {
      const { pool } = require('./db/database');
      try {
        const myRankRes = await pool.query(
          `SELECT COUNT(*) + 1 AS rank FROM tc_users
           WHERE is_deleted IS NOT TRUE AND mighty_season_games > 0
             AND (
               mighty_season_rating > (SELECT mighty_season_rating FROM tc_users WHERE nickname = $1)
               OR (mighty_season_rating = (SELECT mighty_season_rating FROM tc_users WHERE nickname = $1)
                   AND mighty_season_wins > (SELECT mighty_season_wins FROM tc_users WHERE nickname = $1))
               OR (mighty_season_rating = (SELECT mighty_season_rating FROM tc_users WHERE nickname = $1)
                   AND mighty_season_wins = (SELECT mighty_season_wins FROM tc_users WHERE nickname = $1)
                   AND mighty_season_games > (SELECT mighty_season_games FROM tc_users WHERE nickname = $1))
               OR (mighty_season_rating = (SELECT mighty_season_rating FROM tc_users WHERE nickname = $1)
                   AND mighty_season_wins = (SELECT mighty_season_wins FROM tc_users WHERE nickname = $1)
                   AND mighty_season_games = (SELECT mighty_season_games FROM tc_users WHERE nickname = $1)
                   AND nickname < $1)
             )`,
          [ws.nickname]
        );
        const myProfileRes = await pool.query(
          `SELECT u.nickname, u.mighty_season_rating AS rating, u.mighty_season_wins AS wins,
                  u.mighty_season_losses AS losses, u.mighty_season_games AS total_games,
                  CASE WHEN u.mighty_season_games > 0
                    THEN ROUND((u.mighty_season_wins::FLOAT / u.mighty_season_games) * 100)
                    ELSE 0 END AS win_rate,
                  e.banner_key
           FROM tc_users u
           LEFT JOIN tc_user_equips e ON e.nickname = u.nickname
           WHERE u.nickname = $1`,
          [ws.nickname]
        );
        if (myProfileRes.rows.length > 0) {
          result.myRank = parseInt(myRankRes.rows[0].rank);
          result.myRankData = myProfileRes.rows[0];
        }
      } catch (_) {}
    }
    sendTo(ws, { type: 'rankings_result', gameType: 'mighty', ...result });
    return;
  }

  const seasonId = data?.seasonId;
  if (seasonId) {
    const result = await getSeasonRankings(seasonId, 50);
    sendTo(ws, { type: 'rankings_result', ...result });
    return;
  }
  const result = await getCurrentSeasonRankings(50);
  // Calculate requester's rank
  if (ws.nickname && result.success) {
    const { pool } = require('./db/database');
    try {
      const myRankRes = await pool.query(
        `SELECT COUNT(*) + 1 AS rank FROM tc_users
         WHERE is_deleted IS NOT TRUE AND season_games > 0
           AND (season_rating > (SELECT season_rating FROM tc_users WHERE nickname = $1)
            OR (season_rating = (SELECT season_rating FROM tc_users WHERE nickname = $1)
                AND season_wins > (SELECT season_wins FROM tc_users WHERE nickname = $1)))`,
        [ws.nickname]
      );
      const myProfileRes = await pool.query(
        `SELECT u.nickname, u.season_rating AS rating, u.season_wins AS wins,
                u.season_losses AS losses, u.season_games AS total_games,
                CASE WHEN u.season_games > 0
                  THEN ROUND((u.season_wins::FLOAT / u.season_games) * 100)
                  ELSE 0 END AS win_rate,
                e.banner_key
         FROM tc_users u
         LEFT JOIN tc_user_equips e ON e.nickname = u.nickname
         WHERE u.nickname = $1`,
        [ws.nickname]
      );
      if (myProfileRes.rows.length > 0) {
        result.myRank = parseInt(myRankRes.rows[0].rank);
        result.myRankData = myProfileRes.rows[0];
      }
    } catch (_) {}
  }
  sendTo(ws, { type: 'rankings_result', ...result });
}

async function handleGetSeasons(ws) {
  const result = await getSeasons();
  sendTo(ws, { type: 'seasons_result', ...result });
}

// Wallet handler
async function handleGetWallet(ws) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'wallet_result', success: false, message: t(ws.locale, 'login_required') });
    return;
  }
  const result = await getWallet(ws.nickname);
  sendTo(ws, { type: 'wallet_result', ...result });
}

// Translate gold history title keys to localized text
const goldTitleKeys = {
  ko: {
    leave_defeat: '탈주 패배', ranked_win: '랭크 승리', casual_win: '일반 승리',
    draw: '무승부', ranked_loss: '랭크 패배', casual_loss: '일반 패배',
    ad_reward: '광고 보상', season_reward: '시즌 보상',
    sk_leave_defeat: '스컬킹 탈주 패배', sk_ranked_win: '스컬킹 랭크 승리',
    sk_casual_win: '스컬킹 일반 승리', sk_ranked_loss: '스컬킹 랭크 패배',
    sk_casual_loss: '스컬킹 일반 패배',
    ll_leave_defeat: '러브레터 탈주 패배', ll_win: '러브레터 승리', ll_loss: '러브레터 패배',
    admin_grant: '관리자 지급', admin_deduct: '관리자 차감',
  },
  en: {
    leave_defeat: 'Desertion', ranked_win: 'Ranked Win', casual_win: 'Casual Win',
    draw: 'Draw', ranked_loss: 'Ranked Loss', casual_loss: 'Casual Loss',
    ad_reward: 'Ad Reward', season_reward: 'Season Reward',
    sk_leave_defeat: 'SK Desertion', sk_ranked_win: 'SK Ranked Win',
    sk_casual_win: 'SK Casual Win', sk_ranked_loss: 'SK Ranked Loss',
    sk_casual_loss: 'SK Casual Loss',
    ll_leave_defeat: 'LL Desertion', ll_win: 'LL Win', ll_loss: 'LL Loss',
    admin_grant: 'Admin Grant', admin_deduct: 'Admin Deduct',
  },
  de: {
    leave_defeat: 'Verlassen', ranked_win: 'Rang-Sieg', casual_win: 'Sieg',
    draw: 'Unentschieden', ranked_loss: 'Rang-Niederlage', casual_loss: 'Niederlage',
    ad_reward: 'Werbebelohnung', season_reward: 'Saisonbelohnung',
    sk_leave_defeat: 'SK Verlassen', sk_ranked_win: 'SK Rang-Sieg',
    sk_casual_win: 'SK Sieg', sk_ranked_loss: 'SK Rang-Niederlage',
    sk_casual_loss: 'SK Niederlage',
    ll_leave_defeat: 'LL Verlassen', ll_win: 'LL Sieg', ll_loss: 'LL Niederlage',
    admin_grant: 'Admin-Gutschrift', admin_deduct: 'Admin-Abzug',
  },
};

// Description translations for old clients that don't parse raw format
const goldDescKeys = {
  ko: { match: (a, b) => `최종 점수 ${a} : ${b}`, sk_match: (r, s) => `순위 ${r}위 / 점수 ${s}`, ll_match: (r, s) => `순위 ${r}위 / 점수 ${s}`, season_reward: (r) => `시즌 ${r}위 보상`, ad_reward: () => '광고 시청 보상', shop_purchase: () => '상점 구매' },
  en: { match: (a, b) => `Final Score ${a} : ${b}`, sk_match: (r, s) => `Rank #${r} / Score ${s}`, ll_match: (r, s) => `Rank #${r} / Score ${s}`, season_reward: (r) => `Season Rank #${r}`, ad_reward: () => 'Ad Reward', shop_purchase: () => 'Shop Purchase' },
  de: { match: (a, b) => `Endstand ${a} : ${b}`, sk_match: (r, s) => `Platz ${r} / Punkte ${s}`, ll_match: (r, s) => `Platz ${r} / Punkte ${s}`, season_reward: (r) => `Saison Platz ${r}`, ad_reward: () => 'Werbebelohnung', shop_purchase: () => 'Einkauf' },
};

function translateGoldRow(row, locale, legacyDesc) {
  const map = goldTitleKeys[locale] || goldTitleKeys.ko;
  let title = row.title;
  // Shop purchase title: "name_ko|name_en|name_de" → pick by locale
  if (row.source === 'shop_purchase' && title && title.includes('|')) {
    const parts = title.split('|');
    title = locale === 'de' ? (parts[2] || parts[0]) : locale === 'en' ? (parts[1] || parts[0]) : parts[0];
  } else if (map[title]) {
    title = map[title];
  }

  let description = row.description;
  // Translate description for old clients that display raw text
  if (legacyDesc) {
    const dmap = goldDescKeys[locale] || goldDescKeys.ko;
    const src = row.source;
    if ((src === 'match') && description && description.includes(':')) {
      const [a, b] = description.split(':');
      description = dmap.match(a, b);
    } else if ((src === 'sk_match' || src === 'll_match') && description && description.includes(':')) {
      const [r, s] = description.split(':');
      description = dmap.sk_match(r, s);
    } else if (src === 'season_reward' && description) {
      description = dmap.season_reward(description);
    } else if (src === 'ad_reward') {
      description = dmap.ad_reward();
    } else if (src === 'shop_purchase' && description === 'shop_purchase') {
      description = dmap.shop_purchase();
    }
  }

  return { ...row, title, description };
}

async function handleGetGoldHistory(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'gold_history_result', success: false, message: t(ws.locale, 'login_required') });
    return;
  }
  const rawLimit = data?.limit;
  const limit = typeof rawLimit === 'number' && rawLimit > 0
      ? Math.min(rawLimit, 50)
      : 30;
  const result = await getGoldHistory(ws.nickname, limit);
  if (result.success && result.history) {
    const locale = ws.locale || 'ko';
    // Old clients (< 2.2.0) don't parse description client-side
    const legacyDesc = compareVersions(ws.appVersion, LL_MIN_VERSION) < 0;
    result.history = result.history.map(row => translateGoldRow(row, locale, legacyDesc));
  }
  sendTo(ws, { type: 'gold_history_result', ...result });
}

async function ensureAdmin(ws, responseType = 'admin_error') {
  if (ws.nickname) {
    const isAdmin = await isUserAdmin(ws.nickname);
    ws.isAdmin = isAdmin;
    if (isAdmin) return true;
  }
  sendTo(ws, { type: responseType, success: false, message: t(ws.locale, 'admin_required') });
  return false;
}

function getActiveUsersSnapshot() {
  const rows = [];
  for (const client of wss.clients) {
    if (!client.nickname || client.readyState !== client.OPEN) continue;
    let status = 'online';
    let roomName = null;
    let roomId = null;
    if (client.roomId) {
      const room = lobby.getRoom(client.roomId);
      roomId = client.roomId;
      roomName = room?.name || null;
      status = client.isSpectator ? 'spectating' : (room?.game ? 'ingame' : 'waiting');
    }
    rows.push({
      nickname: client.nickname,
      status,
      roomId,
      roomName,
      isAdmin: client.isAdmin === true,
    });
  }
  rows.sort((a, b) => a.nickname.localeCompare(b.nickname, 'ko'));
  return rows;
}

async function notifyAdminUsers(kind, title, body, payload = {}) {
  const recipients = await getAdminPushRecipients(kind);
  for (const user of recipients) {
    if (user.fcm_token) {
      await sendPushNotification(user.fcm_token, title, body);
    }
  }
  for (const client of wss.clients) {
    if (client.readyState !== client.OPEN || client.isAdmin !== true) continue;
    sendTo(client, { type: 'admin_notice', kind, title, body, ...payload });
  }
}

async function handleGetAdminDashboard(ws) {
  if (!await ensureAdmin(ws, 'admin_dashboard_result')) return;
  const stats = await getDashboardStats();
  sendTo(ws, {
    type: 'admin_dashboard_result',
    success: true,
    dashboard: {
      totalUsers: stats.totalUsers || 0,
      pendingInquiries: stats.pendingInquiries || 0,
      pendingReports: stats.pendingReports || 0,
      activeUsers: getActiveUsersSnapshot().length,
      serverStartedAt,
    },
  });
}

async function handleGetAdminStats(ws, data) {
  if (!await ensureAdmin(ws, 'admin_stats_result')) return;
  const result = await getDetailedAdminStats(
    data?.from?.toString(),
    data?.to?.toString(),
    data?.bucket?.toString() === 'hour' ? 'hour' : 'day',
  );
  sendTo(ws, { type: 'admin_stats_result', ...result });
}

async function handleGetAdminUsers(ws, data) {
  if (!await ensureAdmin(ws, 'admin_users_result')) return;
  const search = (data?.search || '').toString();
  const page = typeof data?.page === 'number' ? data.page : 1;
  const limit = typeof data?.limit === 'number' ? Math.min(data.limit, 100) : 50;
  const result = await getUsers(search, page, limit, { sort: data?.sort || 'login_desc' });
  const activeMap = new Map(getActiveUsersSnapshot().map((row) => [row.nickname, row]));
  sendTo(ws, {
    type: 'admin_users_result',
    success: true,
    rows: result.rows.map((row) => ({
      ...row,
      isOnline: activeMap.has(row.nickname),
      onlineStatus: activeMap.get(row.nickname)?.status || 'offline',
      roomName: activeMap.get(row.nickname)?.roomName || null,
    })),
    total: result.total,
    page: result.page,
    limit: result.limit,
  });
}

async function handleGetAdminUserDetail(ws, data) {
  if (!await ensureAdmin(ws, 'admin_user_detail_result')) return;
  const nickname = data?.nickname?.toString();
  if (!nickname) {
    sendTo(ws, { type: 'admin_user_detail_result', success: false, message: t(ws.locale, 'nickname_required') });
    return;
  }
  const user = await getUserDetail(nickname);
  if (!user) {
    sendTo(ws, { type: 'admin_user_detail_result', success: false, message: t(ws.locale, 'admin_user_not_found') });
    return;
  }
  const active = getActiveUsersSnapshot().find((row) => row.nickname === nickname) || null;
  sendTo(ws, {
    type: 'admin_user_detail_result',
    success: true,
    user: {
      ...user,
      isOnline: active != null,
      onlineStatus: active?.status || 'offline',
      roomName: active?.roomName || null,
    },
  });
}

async function handleSetAdminUser(ws, data) {
  if (!await ensureAdmin(ws, 'admin_set_user_result')) return;
  const nickname = data?.nickname?.toString();
  const isAdmin = data?.isAdmin === true;
  if (!nickname) {
    sendTo(ws, { type: 'admin_set_user_result', success: false, message: t(ws.locale, 'nickname_required') });
    return;
  }
  const result = await setUserAdmin(nickname, isAdmin);
  if (result.success) {
    for (const client of wss.clients) {
      if (client.nickname !== nickname) continue;
      client.isAdmin = isAdmin;
      const pushAdminInquiry = result.user?.push_admin_inquiry !== false;
      const pushAdminReport = result.user?.push_admin_report !== false;
      client.pushAdminInquiry = pushAdminInquiry;
      client.pushAdminReport = pushAdminReport;
      sendTo(client, {
        type: 'admin_status_changed',
        isAdmin,
        pushAdminInquiry,
        pushAdminReport,
      });
    }
  }
  sendTo(ws, { type: 'admin_set_user_result', ...result, nickname, isAdmin });
}

async function handleAdminAdjustGold(ws, data) {
  if (!await ensureAdmin(ws, 'admin_adjust_gold_result')) return;
  const nickname = data?.nickname?.toString();
  const amount = parseInt(data?.amount, 10);
  if (!nickname) {
    sendTo(ws, { type: 'admin_adjust_gold_result', success: false, message: t(ws.locale, 'nickname_required') });
    return;
  }
  if (!Number.isFinite(amount) || amount === 0) {
    sendTo(ws, { type: 'admin_adjust_gold_result', success: false, message: t(ws.locale, 'gold_invalid_amount') });
    return;
  }
  const result = await adminAdjustGold(nickname, amount, ws.nickname || 'admin');
  sendTo(ws, { type: 'admin_adjust_gold_result', ...result, nickname, amount });
}

async function handleGetAdminInquiries(ws, data) {
  if (!await ensureAdmin(ws, 'admin_inquiries_result')) return;
  const page = typeof data?.page === 'number' ? data.page : 1;
  const limit = typeof data?.limit === 'number' ? Math.min(data.limit, 100) : 50;
  const result = await getInquiries(page, limit);
  sendTo(ws, { type: 'admin_inquiries_result', success: true, ...result });
}

async function handleResolveAdminInquiry(ws, data) {
  if (!await ensureAdmin(ws, 'admin_inquiry_resolve_result')) return;
  const id = parseInt(data?.id, 10);
  if (!id) {
    sendTo(ws, { type: 'admin_inquiry_resolve_result', success: false, message: t(ws.locale, 'inquiry_id_required') });
    return;
  }
  const result = await resolveInquiry(id, data?.adminNote?.toString() || '');
  if (result && result.success && result.inquiry) {
    const targetNickname = result.inquiry.user_nickname;
    const user = await getUserDetail(targetNickname);
    if (user && user.fcm_token && user.push_enabled !== false) {
      const title = t(user.locale, 'push_inquiry_reply_title');
      const inquiryTitle = result.inquiry.title || '';
      const message = inquiryTitle
        ? t(user.locale, 'push_inquiry_reply_body_with_title', { title: inquiryTitle })
        : t(user.locale, 'push_inquiry_reply_body');
      await sendPushNotification(user.fcm_token, title, message);
    }
  }
  sendTo(ws, { type: 'admin_inquiry_resolve_result', ...result });
}

async function handleGetAdminReports(ws, data) {
  if (!await ensureAdmin(ws, 'admin_reports_result')) return;
  const page = typeof data?.page === 'number' ? data.page : 1;
  const limit = typeof data?.limit === 'number' ? Math.min(data.limit, 100) : 50;
  const result = await getReports(page, limit);
  sendTo(ws, { type: 'admin_reports_result', success: true, ...result });
}

async function handleGetAdminReportGroup(ws, data) {
  if (!await ensureAdmin(ws, 'admin_report_group_result')) return;
  const target = data?.target?.toString();
  const roomId = data?.roomId?.toString() || '';
  if (!target) {
    sendTo(ws, { type: 'admin_report_group_result', success: false, message: t(ws.locale, 'admin_target_required') });
    return;
  }
  const rows = await getReportGroup(target, roomId);
  sendTo(ws, { type: 'admin_report_group_result', success: true, rows, target, roomId });
}

async function handleUpdateAdminReportStatus(ws, data) {
  if (!await ensureAdmin(ws, 'admin_report_status_result')) return;
  const target = data?.target?.toString();
  const roomId = data?.roomId?.toString() || '';
  const status = data?.status?.toString() || 'reviewed';
  if (!target) {
    sendTo(ws, { type: 'admin_report_status_result', success: false, message: t(ws.locale, 'admin_target_required') });
    return;
  }
  const result = await updateReportGroupStatus(target, roomId, status);
  sendTo(ws, { type: 'admin_report_status_result', ...result, target, roomId, status });
}

// Shop items handler
async function handleGetShopItems(ws) {
  const result = await getShopItems();
  sendTo(ws, { type: 'shop_items_result', ...result });
}

// Inventory handler
async function handleGetInventory(ws) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'inventory_result', success: false, message: t(ws.locale, 'login_required') });
    return;
  }
  const result = await getUserItems(ws.nickname);
  sendTo(ws, { type: 'inventory_result', ...result });
}

async function handleBuyItem(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'purchase_result', success: false, message: t(ws.locale, 'login_required') });
    return;
  }
  const itemKey = data.itemKey;
  const result = await buyItem(ws.nickname, itemKey);
  sendTo(ws, { type: 'purchase_result', itemKey, ...result });
}

async function handleEquipItem(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'equip_result', success: false, message: t(ws.locale, 'login_required') });
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
    ws.titleName = result.itemName || null;
    // Update room player data if in a room
    if (ws.roomId) {
      const room = lobby.getRoom(ws.roomId);
      if (room) {
        const p = room.players.find(p => p !== null && p.id === ws.playerId);
        if (p) {
          p.titleKey = itemKey;
          p.titleName = ws.titleName;
        }
        broadcastRoomState(ws.roomId);
      }
    }
  }
  sendTo(ws, { type: 'equip_result', ...result });
}

async function handleUseItem(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'use_item_result', success: false, message: t(ws.locale, 'login_required') });
    return;
  }
  const itemKey = data.itemKey;
  const result = await useItem(ws.nickname, itemKey);
  sendTo(ws, { type: 'use_item_result', ...result });
}

async function handleChangeNickname(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'change_nickname_result', success: false, message: t(ws.locale, 'login_required') });
    return;
  }
  if (ws.roomId) {
    sendTo(ws, { type: 'change_nickname_result', success: false, message: t(ws.locale, 'no_nickname_change_in_game') });
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
    sendTo(ws, { type: 'error', message: t(ws.locale, 'login_required') });
    return;
  }
  const { category, title, content } = data;
  if (!category || !title || !content) {
    sendTo(ws, { type: 'inquiry_result', success: false, message: t(ws.locale, 'inquiry_fill_all') });
    return;
  }
  if (!['bug', 'suggestion', 'other'].includes(category)) {
    sendTo(ws, { type: 'inquiry_result', success: false, message: t(ws.locale, 'inquiry_invalid_category') });
    return;
  }
  const result = await submitInquiry(ws.nickname, category, title, content);
  sendTo(ws, { type: 'inquiry_result', ...result });
  if (result.success) {
    await notifyAdminUsers(
      'inquiry',
      'New Inquiry',
      `Inquiry from ${ws.nickname}`,
      { nickname: ws.nickname, category, title }
    );
  }
}

async function handleGetInquiries(ws) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'inquiries_result', success: false, message: t(ws.locale, 'login_required'), inquiries: [] });
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

async function handleGetNotices(ws) {
  const result = await getPublishedNotices();
  sendTo(ws, { type: 'notices_result', ...result });
}

// Add friend handler
async function handleAddFriend(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'login_required') });
    return;
  }
  const targetNickname = data.nickname;
  if (!targetNickname || targetNickname === ws.nickname) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'cannot_add_friend') });
    return;
  }
  const result = await addFriend(ws.nickname, targetNickname);
  sendTo(ws, {
    type: 'friend_result',
    success: result.success,
    autoAccepted: result.autoAccepted,
    message: resultMessage(result, ws.locale),
  });
  // Real-time notification to target
  if (result.success) {
    const targetWs = findWsByNickname(targetNickname);
    if (targetWs) {
      if (result.autoAccepted) {
        // Auto-accepted (they had sent us a request) — notify both
        sendTo(targetWs, { type: 'friend_request_accepted', nickname: ws.nickname });
      } else {
        sendTo(targetWs, { type: 'friend_request_received', fromNickname: ws.nickname });
      }
    }
    // Push notification only for new requests (skip auto-accept)
    if (!result.autoAccepted) {
      sendFriendRequestPush(targetNickname, ws.nickname);
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
    sendTo(ws, { type: 'error', message: t(ws.locale, 'login_required') });
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
    sendTo(ws, { type: 'error', message: t(ws.locale, 'login_required') });
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
    sendTo(ws, { type: 'error', message: t(ws.locale, 'login_required') });
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

// === DM Handlers ===

async function handleSearchUsers(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'search_users_result', users: [] });
    return;
  }
  const query = (data.query || '').trim();
  if (!query || query.length < 1) {
    sendTo(ws, { type: 'search_users_result', users: [] });
    return;
  }
  const nicknames = await searchUsers(query, ws.nickname);
  const friendsList = await getFriends(ws.nickname);
  const pendingIncoming = await getPendingFriendRequests(ws.nickname);
  // Check outgoing pending: query tc_friends where I sent and status=pending
  const { pool } = require('./db/database');
  let pendingOutgoing = [];
  try {
    const res = await pool.query(
      `SELECT friend_nickname FROM tc_friends WHERE user_nickname = $1 AND status = 'pending'`,
      [ws.nickname]
    );
    pendingOutgoing = res.rows.map(r => r.friend_nickname);
  } catch (_) {}
  const users = nicknames.map(nick => {
    let friendStatus = 'none';
    if (friendsList.includes(nick)) friendStatus = 'friend';
    else if (pendingIncoming.includes(nick)) friendStatus = 'pending_incoming';
    else if (pendingOutgoing.includes(nick)) friendStatus = 'pending_outgoing';
    return { nickname: nick, friendStatus };
  });
  sendTo(ws, { type: 'search_users_result', users });
}

async function handleSendDm(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'dm_error', message: t(ws.locale, 'login_required') });
    return;
  }
  const targetNickname = data.nickname;
  const message = (data.message || '').trim();
  if (!targetNickname || !message) {
    sendTo(ws, { type: 'dm_error', message: t(ws.locale, 'dm_enter_message') });
    return;
  }
  if (message.length > 500) {
    sendTo(ws, { type: 'dm_error', message: t(ws.locale, 'dm_max_length') });
    return;
  }
  // Check friendship
  const friendsList = await getFriends(ws.nickname);
  if (!friendsList.includes(targetNickname)) {
    sendTo(ws, { type: 'dm_error', message: t(ws.locale, 'dm_friends_only') });
    return;
  }
  // Check blocked
  const blockedList = await getBlockedUsers(ws.nickname);
  const blockedByTarget = await getBlockedUsers(targetNickname);
  if (blockedList.includes(targetNickname) || blockedByTarget.includes(ws.nickname)) {
    sendTo(ws, { type: 'dm_error', message: t(ws.locale, 'dm_blocked') });
    return;
  }
  // Check chat ban
  const chatBan = await getChatBan(ws.nickname);
  if (chatBan) {
    sendTo(ws, { type: 'dm_error', message: t(ws.locale, 'chat_banned') });
    return;
  }
  const result = await sendDm(ws.nickname, targetNickname, message);
  if (!result.success) {
    sendTo(ws, { type: 'dm_error', message: resultMessage(result, ws.locale) });
    return;
  }
  const dmMsg = {
    type: 'dm_message',
    id: result.id,
    sender: ws.nickname,
    receiver: targetNickname,
    message,
    createdAt: result.createdAt,
  };
  sendTo(ws, dmMsg);
  // Real-time delivery to target
  const targetWs = findWsByNickname(targetNickname);
  if (targetWs) {
    sendTo(targetWs, dmMsg);
  }
}

async function handleGetDmHistory(ws, data) {
  if (!ws.nickname) return;
  const targetNickname = data.nickname;
  if (!targetNickname) return;
  const beforeId = data.beforeId || null;
  const messages = await getDmHistory(ws.nickname, targetNickname, beforeId);
  sendTo(ws, { type: 'dm_history', nickname: targetNickname, messages });
}

async function handleMarkDmRead(ws, data) {
  if (!ws.nickname) return;
  const targetNickname = data.nickname;
  if (!targetNickname) return;
  await markDmRead(ws.nickname, targetNickname);
  sendTo(ws, { type: 'dm_marked_read', nickname: targetNickname });
}

async function handleGetDmConversations(ws) {
  if (!ws.nickname) return;
  const conversations = await getDmConversations(ws.nickname);
  sendTo(ws, { type: 'dm_conversations', conversations });
}

async function handleGetUnreadDmCount(ws) {
  if (!ws.nickname) return;
  const count = await getTotalUnreadDmCount(ws.nickname);
  sendTo(ws, { type: 'unread_dm_count', count });
}

// Invite to room handler
function handleInviteToRoom(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'invite_result', success: false, message: t(ws.locale, 'login_required') });
    return;
  }
  if (!ws.roomId) {
    sendTo(ws, { type: 'invite_result', success: false, message: t(ws.locale, 'not_in_room_for_invite') });
    return;
  }
  const targetNickname = data.nickname;
  if (!targetNickname) {
    sendTo(ws, { type: 'invite_result', success: false, message: t(ws.locale, 'invite_no_target') });
    return;
  }
  const targetWs = findWsByNickname(targetNickname);
  if (!targetWs) {
    sendTo(ws, { type: 'invite_result', success: false, message: t(ws.locale, 'dm_offline') });
    return;
  }
  if (targetWs.roomId) {
    sendTo(ws, { type: 'invite_result', success: false, message: t(ws.locale, 'invite_target_in_room') });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room) {
    sendTo(ws, { type: 'invite_result', success: false, message: t(ws.locale, 'room_not_found') });
    return;
  }
  if (room.game) {
    sendTo(ws, { type: 'invite_result', success: false, message: t(ws.locale, 'invite_in_game') });
    return;
  }
  const inviteKey = `${ws.nickname}->${targetNickname}`;
  const now = Date.now();
  for (const [key, timestamp] of recentRoomInvites.entries()) {
    if (now - timestamp > 60000) {
      recentRoomInvites.delete(key);
    }
  }
  const lastInviteAt = recentRoomInvites.get(inviteKey) || 0;
  if (now - lastInviteAt < 10000) {
    sendTo(ws, { type: 'invite_result', success: false, message: t(ws.locale, 'invite_cooldown') });
    return;
  }
  recentRoomInvites.set(inviteKey, now);
  sendTo(targetWs, {
    type: 'room_invite',
    fromNickname: ws.nickname,
    roomId: room.id,
    roomName: room.name,
    isRanked: room.isRanked,
    password: room.password || '',
  });
  sendTo(ws, { type: 'invite_result', success: true, message: t(ws.locale, 'invite_sent') });
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
