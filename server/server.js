// Install console capture FIRST so the admin live-log viewer also sees
// bootstrap/startup logs (ring buffer + SSE fan-out; stdout is untouched).
require('./logBuffer').installConsoleCapture();

const { WebSocketServer } = require('ws');
const crypto = require('crypto');
const http = require('http');
const serverStartedAt = new Date().toISOString();
const LobbyManager = require('./lobby/LobbyManager');
const { findAbandonedRooms } = require('./lobby/zombieSweep');
const fillerRooms = require('./lobby/fillerRooms');
const { freezeThresholdMs } = require('./game/freezeWatch');
const { playerStillNeedsToAct } = require('./game/turnGuard');
const GameRoom = require('./game/GameRoom');
const { decideBotAction } = require('./game/BotPlayer');
const { decideSKBotAction } = require('./game/skull_king/SkullKingBot');
const { decideLLBotAction } = require('./game/love_letter/LoveLetterBot');
const { decideMightyBotAction } = require('./game/mighty/MightyBot');
const { BotWorkerPool } = require('./bots/BotWorkerPool');
const webApp = require('./webApp');
const {
  initDatabase, registerUser, loginUser, checkNickname, deleteUser,
  blockUser, unblockUser, getBlockedUsers, reportUser, getReportedNicknames,
  addFriend, getFriends, getPendingFriendRequests, setProfilePrivateHidePhoto,
  unequipCategory, setCustomTitle, clearCustomTitle, setFeatureEnabled,
  acceptFriendRequest, rejectFriendRequest, removeFriend,
  saveMatchResult, saveMatchResultWithStats, updateUserStats, getUserProfile, getRecentMatches, updateCardViewPref,
  submitInquiry, getUserInquiries, markInquiriesRead, getRankings,
  getWallet, getGoldHistory, getShopItems, getVisualCatalog, getUserItems, buyItem, equipItem, useItem, changeNickname,
  getActiveGoldProducts, getGoldProductByProductId, grantIapGold, logIapAttempt, autoRefundByTransaction,
  createBankDeposit, countPendingBankDeposits,
  getConsumptionSnapshot, recordConsumptionRequest, listConsumptionRequests,
  getAttendanceState, claimAttendance,
  incrementLeaveCount, logMidGameLeave, setRankedBan, getRankedBan, setChatBan, getChatBan, grantSeasonRewards,
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
  getTodayMatches,
  getTodayPayments,
  getAdminGoldHistory,
  adminAdjustGold,
  setAdminMemo,
  getSKRecentMatches,
  getPublishedNotices,
  getBroadcastFcmTokens,
  insertPushHistory,
  getPushHistory,
  clearInvalidFcmToken,
  loadTitleTranslations,
  adminClearProfilePhoto,
  getReportedPhotoKeys,
  getReportedTitles,
  isPhotoKeyReported,
} = require('./db/database');

const { verifyApple } = require('./iap/AppleVerify');
const { verifyGoogle } = require('./iap/GoogleVerify');
const { parseAppleNotification } = require('./iap/AppleNotifications');
const { sendConsumptionInfo, ascConfigured } = require('./iap/AppleConsumption');
const { bindingUuid } = require('./iap/accountBinding');
const { pollGoogleVoidedPurchases } = require('./iap/GoogleVoided');

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
const { logAdminAccess, logVerboseConnection } = require('./logger');

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
// ⚠️ STILL tichu.jiny.shop, on purpose. Flip to tichu.kr only after the
// tichu.kr build has shipped and taken hold — see docs/DOMAIN_MIGRATION.md 2단계.
//
// Whichever host is minted here has to be one the RECIPIENT's app already
// registers as an app link, and app links live in the installed binary. Every
// build in the wild today knows tichu.jiny.shop; none of them know tichu.kr.
// Minting tichu.kr links now would mean a player with the app installed taps
// an invite and lands in the browser instead of the app.
//
// tichu.jiny.shop is the only host BOTH old and new builds register, so it
// stays the mint until the old ones are gone. A custom scheme (tichu://) does
// not rescue this: it would also only exist in the new binary.
const INVITE_BASE_URL = process.env.INVITE_BASE_URL || 'https://tichu.jiny.shop';

// Blue/green deploy hooks. Set per-container so the surviving instance
// (PEER_URL) can adopt rooms migrated from this one when SIGTERM hits.
// In single-instance setups (legacy), PEER_URL is null and the migration
// path is skipped entirely — server still works, just with the old
// "down + restart loses state" behavior.
const INSTANCE_NAME = process.env.INSTANCE_NAME || 'default';
const PEER_URL = process.env.PEER_URL || null;
const INTERNAL_MIGRATE_TOKEN = process.env.INTERNAL_MIGRATE_TOKEN || null;
let isDraining = false;
const ANDROID_PACKAGE_NAME = 'com.jiny.tichuOnline';
const IOS_APP_ID = 'HW9XJ9J5M2.com.jiny.tichuOnline';
const IOS_STORE_URL = 'https://apps.apple.com/app/tichu-online/id6759035151';
const ANDROID_STORE_URL = `https://play.google.com/store/apps/details?id=${ANDROID_PACKAGE_NAME}`;
// Public support contact shown on /support. Override via env to route to a
// mailbox you actually monitor (a personal address is fine for a solo dev).
const SUPPORT_EMAIL = process.env.SUPPORT_EMAIL || 'kjinyz@naver.com';
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
  // Raw markup injected into <head>. Only used by /invite, to bounce a real
  // browser into the web client while leaving scrapers the preview tags.
  headExtra = '',
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
    ${headExtra}
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
// Tichu random seating UI shipped with the Mighty client.
const RANDOM_SEATING_MIN_VERSION = '2.3.0';
// New banner pack (10 SKUs) shipped with the 2.4.0 client. Pre-2.4.0 apps
// only hardcode a few legacy banner gradients in the lobby renderer, so a
// purchased new banner would silently fall back to the default look — gate
// show/buy on this version to avoid a "bought but invisible" UX.
const NEW_BANNER_MIN_VERSION = '2.4.0';
// Profile photo (UGC) client. Older clients have no upload UI, so the shop
// items are hidden from them. Bump to match the actual release version.
const PROFILE_PHOTO_MIN_VERSION = '2.8.0';
// Profile privacy pass. Ships in the same unreleased build as the photo item
// and needs the same client work (the redacted popup, and the owner's toggle
// for whether the photo is included), so it rides the same minimum.
const PROFILE_PRIVATE_MIN_VERSION = PROFILE_PHOTO_MIN_VERSION;
// Mid-game walk-outs in the match history. These rows are an event, not a
// result: no score, no final roster, and the client has to know to render them
// as one. An older app picks its renderer off gameType alone, so a Skull King
// walk-out came out as "undefined점 #undefined" and a Tichu one leaned on
// back-filled seat fields to look like anything at all. Rather than shim the
// payload into something they misread more quietly, don't send them the rows —
// they are the only history entries whose absence costs an old client nothing.
const MID_LEAVE_HISTORY_MIN_VERSION = '3.0.0';
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

/// Whether this client renders a walk-out row as an event rather than a match.
///
/// A missing version reads as 0.0.0, so an unknown client is treated as old —
/// which is the safe direction: it loses rows it could not have drawn.
function clientSupportsMidLeaveHistory(ws) {
  return compareVersions(ws.appVersion, MID_LEAVE_HISTORY_MIN_VERSION) >= 0;
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

function clientSupportsRandomSeating(ws) {
  return compareVersions(ws.appVersion, RANDOM_SEATING_MIN_VERSION) >= 0;
}

function clientSupportsNewBanners(ws) {
  return compareVersions(ws.appVersion, NEW_BANNER_MIN_VERSION) >= 0;
}

function clientSupportsProfilePhoto(ws) {
  return compareVersions(ws.appVersion, PROFILE_PHOTO_MIN_VERSION) >= 0;
}

function clientSupportsProfilePrivate(ws) {
  return compareVersions(ws.appVersion, PROFILE_PRIVATE_MIN_VERSION) >= 0;
}

// Custom title ships in the same build and needs the same client work (the
// editor, and a TitleChip that knows `custom:` keys draw no icon).
function clientSupportsCustomTitle(ws) {
  return compareVersions(ws.appVersion, PROFILE_PRIVATE_MIN_VERSION) >= 0;
}

function itemRequiresMightyClient(itemKey) {
  return typeof itemKey === 'string' && itemKey.startsWith('mighty_');
}

// Non-mighty-prefixed utility items that were added alongside the Mighty
// release. Legacy (<2.3.0) apps don't have UI handling for these effect
// types (tichu/sk per-game season-stats resets, and the new full leave-
// count reset), so show/buy is gated on the same 2.3.0 version check to
// avoid surfacing half-supported rows in old shops and inventories.
const V230_UTILITY_ITEM_KEYS = new Set([
  'tichu_season_stats_reset',
  'sk_season_stats_reset',
  'leave_reset',
]);

/** True for any shop item a <2.3.0 client shouldn't see. Wraps the mighty_
 *  prefix rule with the extra 2.3.0-era utility keys. */
function itemRequiresV230Client(itemKey) {
  if (itemRequiresMightyClient(itemKey)) return true;
  return typeof itemKey === 'string' && V230_UTILITY_ITEM_KEYS.has(itemKey);
}

// Banner SKUs introduced in 2.4.0. Pre-2.4.0 lobby renders fall back to a
// default gradient for unknown banner keys, so we gate show/buy/use on the
// client version to avoid "bought but invisible".
const NEW_BANNER_ITEM_KEYS = new Set([
  'banner_ocean',
  'banner_forest',
  'banner_lavender',
  'banner_aurora',
  'banner_galaxy',
  'banner_sakura',
  'banner_coral',
  'banner_moonlight',
  'banner_ember',
  'banner_emerald',
]);

function itemRequiresNewBannerClient(itemKey) {
  return typeof itemKey === 'string' && NEW_BANNER_ITEM_KEYS.has(itemKey);
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

/**
 * Photo screening on/off, persisted in tc_config so an operator can flip it
 * from admin. Unset (null) means the VISION_ENABLED env var still decides, so
 * nothing changes for a server that has never touched the switch.
 */
async function loadPhotoScreeningConfig() {
  try {
    const saved = await getConfig('photo_screening');
    if (saved === 'on' || saved === 'off') {
      visionSafeSearch.setEnabled(saved === 'on');
      console.log(`[profile-photo] screening switch from admin: ${saved}`);
    }
  } catch (e) {
    console.error('[profile-photo] failed to load screening config:', e.message);
  }
}

/**
 * Banned-word list for custom titles, from tc_config. Empty/unset leaves the
 * built-in list in force.
 */
async function loadCustomTitleWords() {
  try {
    const saved = await getConfig('custom_title_banned');
    if (saved !== null && saved !== undefined) {
      const words = saved.split(/[\n,]/).map((w) => w.trim()).filter(Boolean);
      customTitleWords.setBannedWords(words.length ? words : null);
      console.log(`[custom-title] banned words from admin: ${words.length}`);
    }
  } catch (e) {
    console.error('[custom-title] failed to load banned words:', e.message);
  }
}

function getCustomTitleWords() {
  return customTitleWords.getBannedWords();
}

async function setCustomTitleWords(text) {
  const words = String(text || '').split(/[\n,]/).map((w) => w.trim()).filter(Boolean);
  customTitleWords.setBannedWords(words.length ? words : null);
  await updateConfig('custom_title_banned', words.join('\n'));
  console.log(`[custom-title] banned words updated from admin: ${words.length}`);
  return getCustomTitleWords();
}

function getPhotoScreening() {
  return {
    enabled: visionSafeSearch.isEnabled(),
    hasCredentials: visionSafeSearch.hasCredentials(),
    envDefault: process.env.VISION_ENABLED === 'true',
  };
}

async function setPhotoScreening(enabled) {
  visionSafeSearch.setEnabled(enabled === true);
  await updateConfig('photo_screening', enabled === true ? 'on' : 'off');
  console.log(`[profile-photo] screening switched ${enabled === true ? 'ON' : 'OFF'} from admin`);
  return getPhotoScreening();
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

// ── Profile photo (UGC) upload ──────────────────────────────────────────────
// See server/deploy/PROFILE_PHOTO_PLAN.md. Reuses hmlove-minio (scoped key).
const sharp = require('sharp');
const minioClient = require('./storage/minioClient');
const visionSafeSearch = require('./moderation/visionSafeSearch');
const customTitleWords = require('./moderation/customTitle');
const { validateCustomTitle } = customTitleWords;

// Short-lived, one-time upload tokens. Issued over the authenticated WS
// (request_upload_token) and consumed by the HTTP POST /upload/profile-photo —
// the HTTP request carries no WS identity, so this bridges auth for all login
// types (regular / social).
const uploadTokens = new Map(); // token -> { userId, expiresAt }
const UPLOAD_TOKEN_TTL_MS = 3 * 60 * 1000;
const UPLOAD_MAX_BYTES = 5 * 1024 * 1024;
const UPLOAD_ALLOWED_MIME = new Set(['image/jpeg', 'image/png', 'image/webp']);

function httpErr(status, message) { const e = new Error(message); e.statusCode = status; return e; }

function issueUploadToken(userId) {
  // Invalidate any prior outstanding token for this user so two concurrent
  // uploads can't each store a fresh object (only the last DB pointer wins,
  // orphaning the other). One live token per user.
  for (const [t, r] of uploadTokens) if (r.userId === userId) uploadTokens.delete(t);
  const token = crypto.randomBytes(24).toString('base64url');
  uploadTokens.set(token, { userId, expiresAt: Date.now() + UPLOAD_TOKEN_TTL_MS });
  return token;
}
function consumeUploadToken(token) {
  const rec = token && uploadTokens.get(token);
  if (rec) uploadTokens.delete(token); // one-time use
  if (!rec || rec.expiresAt < Date.now()) return null;
  return rec.userId;
}
setInterval(() => {
  const now = Date.now();
  for (const [t, r] of uploadTokens) if (r.expiresAt < now) uploadTokens.delete(t);
}, 60000).unref();

// Eligibility: must hold the active (unexpired) profile-photo shop item.
async function profilePhotoRow(userId) {
  const { pool } = require('./db/database');
  const r = await pool.query(
    'SELECT profile_photo_key, profile_photo_status, profile_photo_expires_at FROM tc_users WHERE id = $1',
    [userId],
  );
  return r.rows[0] || null;
}
function isPhotoEligible(row) {
  return !!row
    && row.profile_photo_status === 'active'
    && (!row.profile_photo_expires_at || new Date(row.profile_photo_expires_at) > new Date());
}

// Public avatar URL from a getUserProfile() result, only while the paid photo
// is active + unexpired. Null → client shows the default avatar.
function profilePhotoUrlFrom(profile) {
  if (!profile || profile.profilePhotoStatus !== 'active' || !profile.profilePhotoKey) return null;
  if (profile.profilePhotoExpiresAt && new Date(profile.profilePhotoExpiresAt) <= new Date()) return null;
  return minioClient.publicUrl(profile.profilePhotoKey);
}

// Sweep profile photos whose paid duration has lapsed: delete the object from
// storage and reset the row to 'none' so serialize() stops surfacing it. The
// counter items expire via tc_user_items (cleanupExpiredItems); profile photos
// live on tc_users and need this dedicated pass. Best-effort — a failed minio
// delete leaves an orphan object but still clears the DB pointer on retry.
async function cleanupExpiredProfilePhotos() {
  if (!minioClient.isEnabled()) return;
  try {
    const { pool } = require('./db/database');
    // Select + lock the still-expired rows, clear them, and return their OLD
    // keys — all in ONE statement so a concurrent re-buy+re-upload can't race
    // between the read and the wipe. victims FOR UPDATE blocks an interleaving
    // purchase; anyone who already renewed no longer matches expires_at < NOW()
    // and is neither cleared nor has their fresh object deleted.
    const cleared = await pool.query(
      `WITH victims AS (
         SELECT id, profile_photo_key FROM tc_users
         WHERE profile_photo_status = 'active'
           AND profile_photo_expires_at IS NOT NULL
           AND profile_photo_expires_at < NOW()
         FOR UPDATE
       ), upd AS (
         UPDATE tc_users SET profile_photo_key = NULL, profile_photo_status = 'none'
         FROM victims WHERE tc_users.id = victims.id
       )
       SELECT profile_photo_key FROM victims`,
    );
    for (const u of cleared.rows) {
      if (u.profile_photo_key) await deletePhotoObjectUnlessReported(u.profile_photo_key);
    }
    if (cleared.rows.length) {
      console.log(`[profile-photo] cleaned up ${cleared.rows.length} expired photo(s)`);
    }
  } catch (e) {
    console.error('[profile-photo] cleanup error:', e && e.message);
  }
}

// Parse a single-file multipart upload into a buffer, enforcing size + MIME.
function parseUploadedImage(req) {
  const Busboy = require('busboy');
  return new Promise((resolve, reject) => {
    let bb;
    try { bb = Busboy({ headers: req.headers, limits: { files: 1, fileSize: UPLOAD_MAX_BYTES } }); }
    catch (_) { return reject(httpErr(400, 'bad_request')); }
    let sawFile = false; let mimeType = null; const chunks = []; let settled = false;
    // Drain (resume) after unpiping so a still-uploading client's remaining
    // body doesn't wedge the socket / block keep-alive reuse on rejection.
    const fail = (code, msg) => { if (settled) return; settled = true; try { req.unpipe(bb); req.resume(); } catch (_) {} reject(httpErr(code, msg)); };
    bb.on('file', (_name, stream, info) => {
      sawFile = true; mimeType = info && info.mimeType;
      if (!UPLOAD_ALLOWED_MIME.has(mimeType)) { stream.resume(); return fail(415, 'unsupported_type'); }
      stream.on('data', (d) => chunks.push(d));
      stream.on('limit', () => { stream.resume(); fail(413, 'file_too_large'); });
    });
    bb.on('error', () => fail(400, 'parse_error'));
    bb.on('close', () => {
      if (settled) return;
      if (!sawFile) return fail(400, 'no_file');
      settled = true; resolve({ buffer: Buffer.concat(chunks), mimeType });
    });
    req.pipe(bb);
  });
}

// Owner removes their own photo. Mirrors the admin clear-photo route: only the
// key is dropped — the paid item status stays, so they can upload a different
// photo for the rest of their window. The object is deleted from storage, and
// every live copy of the URL (ws, the room seat) is cleared and repainted, the
// same dance the upload path does in the other direction.
// Delete a photo object from storage — unless some report references it, in
// which case it stays as evidence: "what image was reported" must remain
// answerable in the admin after the owner deletes or replaces the photo.
// The DB pointer is cleared by the callers either way, so a kept object is
// invisible everywhere except the admin's report view.
async function deletePhotoObjectUnlessReported(key) {
  if (!key) return;
  try {
    if (await isPhotoKeyReported(key)) {
      console.log(`[profile-photo] keeping reported object as evidence: ${key}`);
      return;
    }
    await minioClient.deleteProfilePhoto(key);
  } catch (e) {
    console.warn('[profile-photo] object delete failed:', e.message);
  }
}

async function handleDeleteProfilePhoto(ws) {
  if (!ws.userId) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'login_required') });
    return;
  }
  const { oldKey } = await adminClearProfilePhoto(ws.nickname);
  if (oldKey) deletePhotoObjectUnlessReported(oldKey); // best-effort
  ws.photoUrl = null;
  sendTo(ws, { type: 'profile_photo_updated', playerId: ws.playerId, url: null });
  if (ws.roomId) {
    const room = lobby.getRoom(ws.roomId);
    const player = room?.players?.find((p) => p && p.id === ws.playerId);
    if (player) player.photoUrl = null;
    broadcastRoomState(ws.roomId);
    if (room?.game) sendGameStateToAll(ws.roomId);
  }
  console.log(`[profile-photo] self-deleted by ${ws.nickname}`);
}

async function handleRequestUploadToken(ws) {
  if (ws.userId == null) { sendTo(ws, { type: 'upload_token_error', reason: 'not_logged_in' }); return; }
  if (!minioClient.isEnabled()) { sendTo(ws, { type: 'upload_token_error', reason: 'storage_unavailable' }); return; }
  try {
    if (!isPhotoEligible(await profilePhotoRow(ws.userId))) {
      sendTo(ws, { type: 'upload_token_error', reason: 'no_active_item' });
      return;
    }
    sendTo(ws, { type: 'upload_token', token: issueUploadToken(ws.userId), expiresIn: Math.floor(UPLOAD_TOKEN_TTL_MS / 1000) });
  } catch (_) {
    sendTo(ws, { type: 'upload_token_error', reason: 'server_error' });
  }
}

// Create HTTP server for health checks (required by Render) and admin dashboard
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const pathname = url.pathname;

  // Debug: log admin route attempts
  if (pathname.startsWith('/tc-backstage') || pathname.includes('backstage')) {
    logAdminAccess(`[ADMIN] ${req.method} ${pathname}`);
  }

  if (pathname.startsWith('/tc-backstage')) {
    try {
      await handleAdminRoute(req, res, url, pathname, req.method, lobby, wss, { getMaintenanceConfig, setMaintenanceConfig, getMaintenanceStatus, sendPushNotification, sendBroadcastPush, runGoogleVoidedPoll, closeRoom, broadcastRoomList, broadcastRoomState, sendGameStateToAll, getPhotoScreening, setPhotoScreening, getCustomTitleWords, setCustomTitleWords });
    } catch (err) {
      console.error('Admin route error:', err);
      res.writeHead(500, { 'Content-Type': 'text/plain' });
      res.end('Internal Server Error');
    }
    return;
  }

  // Internal-only endpoints. nginx must block /internal/* from the public
  // edge (deny all in tichu.conf). The shared-secret header is a
  // belt-and-suspenders second line of defense, also required for
  // local-only deploy testing where no nginx sits in front.
  if (pathname.startsWith('/internal/')) {
    if (!INTERNAL_MIGRATE_TOKEN) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('not configured');
      return;
    }
    if (req.headers['x-internal-token'] !== INTERNAL_MIGRATE_TOKEN) {
      res.writeHead(403, { 'Content-Type': 'text/plain' });
      res.end('forbidden');
      return;
    }
    if (req.method === 'POST' && pathname === '/internal/pending-rooms') {
      try {
        await handlePendingRoomsRequest(req, res);
      } catch (err) {
        console.error('[pending-rooms] error:', err);
        res.writeHead(500, { 'Content-Type': 'text/plain' });
        res.end('error');
      }
      return;
    }
    if (req.method === 'POST' && pathname === '/internal/adopt-rooms') {
      try {
        await handleAdoptRoomsRequest(req, res);
      } catch (err) {
        console.error('[adopt-rooms] error:', err);
        res.writeHead(500, { 'Content-Type': 'text/plain' });
        res.end('error');
      }
      return;
    }
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('not found');
    return;
  }

  // App Store Server Notifications V2 (public — Apple calls this). Auth is
  // the JWS signature chain verified inside parseAppleNotification, NOT the
  // network, so this must stay reachable through the public edge.
  // Profile photo upload (multipart). Auth = one-time WS-issued Bearer token.
  if (pathname === '/upload/profile-photo' && req.method === 'POST') {
    try {
      const auth = req.headers['authorization'] || '';
      const userId = consumeUploadToken(auth.startsWith('Bearer ') ? auth.slice(7) : '');
      if (userId == null) throw httpErr(401, 'invalid_or_expired_token');
      if (!minioClient.isEnabled()) throw httpErr(503, 'storage_unavailable');
      const row = await profilePhotoRow(userId);
      if (!isPhotoEligible(row)) throw httpErr(403, 'no_active_item');

      const { buffer } = await parseUploadedImage(req);
      // sharp strips metadata (incl. EXIF/GPS) by default; .rotate() honours the
      // EXIF orientation first, then squares to 512 and re-encodes as JPEG.
      // A decode failure here is bad client input (declared image/* but corrupt
      // or non-image bytes), so surface it as 400 — not a 500 server error.
      let processed;
      try {
        processed = await sharp(buffer)
          .rotate()
          .resize(512, 512, { fit: 'cover' })
          .jpeg({ quality: 85 })
          .toBuffer();
      } catch (_) {
        throw httpErr(400, 'invalid_image');
      }

      // Screen before anything is stored. Apple 1.2 wants objectionable
      // material filtered on the way in, not only taken down after a report.
      const scanStart = Date.now();
      const scan = await visionSafeSearch.screen(processed);
      // Log every outcome, including the boring one. Without a line for 'ok'
      // there is no way to tell "screened and clean" from "screening never
      // ran" — which is exactly the question asked the first time a photo went
      // through, and the log could not answer it.
      console.log(
        `[profile-photo] screened user=${userId} verdict=${scan.verdict}`
        + (scan.scores ? ` ${Object.entries(scan.scores).map(([k, v]) => `${k}=${v}`).join(' ')}` : '')
        + (scan.reason ? ` reason=${scan.reason}` : '')
        + ` ${Date.now() - scanStart}ms`,
      );
      if (scan.verdict === 'reject') {
        console.warn(`[profile-photo] rejected user=${userId} worst=${scan.worst}`);
        throw httpErr(422, 'image_rejected');
      }
      if (scan.verdict === 'error') {
        // Fail closed. This is a paid cosmetic, not a path anyone is blocked
        // on; letting an unscreened image through because the screener was
        // down is the worse of the two outcomes.
        console.error(`[profile-photo] screening failed user=${userId} reason=${scan.reason} ${scan.detail || ''}`);
        throw httpErr(503, 'moderation_unavailable');
      }
      if (scan.verdict === 'review') {
        console.warn(`[profile-photo] flagged for review user=${userId} worst=${scan.worst} labels=${(scan.labels || []).join(',')}`);
      }

      const { key, url } = await minioClient.uploadProfilePhoto(userId, processed, 'image/jpeg');
      const { pool } = require('./db/database');
      await pool.query('UPDATE tc_users SET profile_photo_key = $1 WHERE id = $2', [key, userId]);
      if (row.profile_photo_key && row.profile_photo_key !== key) {
        deletePhotoObjectUnlessReported(row.profile_photo_key); // best-effort, don't await
      }
      // Keep ws + the in-room player object in sync so later re-serializations
      // carry it, then repaint. Without the repaint nothing changes on screen
      // until some unrelated state change happens to come along — in a waiting
      // room that can be never, so the uploader sat looking at their old photo.
      const uws = [...wss.clients].find((c) => c.userId === userId);
      if (uws) {
        uws.photoUrl = url;
        // Only the uploader is told the URL directly. Everyone else learns
        // through room/game state, which filters photos per viewer — sending
        // this event to the room would hand the raw URL to people who have
        // blocked or reported them.
        sendTo(uws, { type: 'profile_photo_updated', playerId: uws.playerId, url });
        if (uws.roomId) {
          const room = lobby.getRoom(uws.roomId);
          const player = room?.players?.find((p) => p && p.id === uws.playerId);
          if (player) player.photoUrl = url;
          broadcastRoomState(uws.roomId);
          if (room?.game) sendGameStateToAll(uws.roomId);
        }
      }
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: true, url }));
    } catch (e) {
      const code = e.statusCode || 500;
      if (code >= 500) console.error('[profile-photo] upload error:', e);
      res.writeHead(code, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: e.message || 'upload_failed' }));
    }
    return;
  }

  if (pathname === '/iap/apple/notifications' && req.method === 'POST') {
    let notif;
    try {
      const body = await readJsonBody(req);
      if (!body || !body.signedPayload) {
        res.writeHead(400, { 'Content-Type': 'text/plain' });
        res.end('no signedPayload');
        return;
      }
      notif = parseAppleNotification(body.signedPayload);
    } catch (err) {
      // Forged / malformed / wrong-bundle → reject so it's not silently acked.
      console.warn('[AppleNotif] verify failed:', err.message);
      res.writeHead(400, { 'Content-Type': 'text/plain' });
      res.end('invalid');
      return;
    }
    try {
      const t = notif.transaction || {};
      const type = notif.notificationType;
      // REFUND = consumable refunded; REVOKE = Family Sharing access revoked.
      if (type === 'REFUND' || type === 'REVOKE') {
        const r = await autoRefundByTransaction({
          transactionId: t.transactionId,
          source: 'apple',
          reason: `apple:${type}${notif.subtype ? ':' + notif.subtype : ''}`,
          onRefunded: notifyAdminRefund,
        });
        console.log(`[AppleNotif] ${type} txn=${t.transactionId} env=${notif.environment} ->`, JSON.stringify(r));
        // Only a transient post-processing failure (DB error, etc.) should
        // make Apple retry. success / idempotent / receipt_not_found are
        // terminal (the last is logged as unmatched for ops) → ack with 200.
        if (r && r.success === false && r.reason !== 'receipt_not_found') {
          res.writeHead(503, { 'Content-Type': 'text/plain' });
          res.end('retry');
          return;
        }
      } else if (type === 'CONSUMPTION_REQUEST') {
        // Apple is deciding a consumable refund and wants our consumption
        // data. Always record; respond to Apple only if ASC key configured.
        const txnId = t.transactionId;
        const snap = await getConsumptionSnapshot(txnId);
        let responseStatus = 'received';
        let responseDetail = null;
        if (!snap.found) {
          responseStatus = 'skipped';
          responseDetail = 'no_matching_receipt';
        } else if (!ascConfigured()) {
          responseStatus = 'skipped';
          responseDetail = 'asc_not_configured';
        } else {
          const sent = await sendConsumptionInfo({
            transactionId: txnId,
            environment: notif.environment,
            fields: snap.fields,
            appAccountToken: t.appAccountToken || null,
          });
          responseStatus = sent.ok ? 'responded' : 'failed';
          responseDetail = sent.reason || null;
        }
        await recordConsumptionRequest({
          notificationUUID: notif.notificationUUID,
          transactionId: txnId,
          productId: snap.productId || t.productId || null,
          nickname: snap.nickname || null,
          environment: notif.environment,
          requestReason: notif.consumptionRequestReason,
          snapshot: snap,
          responseStatus,
          responseDetail,
        });
        console.log(`[AppleNotif] CONSUMPTION_REQUEST txn=${txnId} -> ${responseStatus}${responseDetail ? ':' + responseDetail : ''}`);
      } else {
        console.log(`[AppleNotif] ignored type=${type} subtype=${notif.subtype || '-'}`);
      }
    } catch (err) {
      // Verified but processing threw → transient; ask Apple to retry instead
      // of letting a temporary outage become a permanent refund miss.
      console.error('[AppleNotif] handler error:', err);
      res.writeHead(503, { 'Content-Type': 'text/plain' });
      res.end('retry');
      return;
    }
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('OK');
    return;
  }

  if (pathname === '/health') {
    // 503 while draining so the LB stops sending new connections to this
    // instance. Existing WS connections keep working — they're already
    // open and won't re-pass through the LB until they reconnect.
    if (isDraining) {
      res.writeHead(503, { 'Content-Type': 'text/plain' });
      res.end('draining');
    } else {
      res.writeHead(200, { 'Content-Type': 'text/plain' });
      res.end('OK');
    }
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
    // If the app were installed, the universal link would have opened it
    // before the browser ever loaded this URL. Getting here therefore means
    // there is no app to hand off to — so hand off to the web client instead
    // and drop the recipient straight into the room.
    //
    // Still server-rendered rather than just serving the SPA: this page is
    // what KakaoTalk and every other scraper reads to build the share preview
    // ("<inviter>님의 초대 · <room>"), and a Flutter canvas has nothing for
    // them to read. Scrapers do not run scripts, so they keep the preview
    // while a real visitor never sees this page at all.
    //
    // replace(), not assign(): Back should return to wherever the link was
    // tapped, not bounce through this page again.
    const canPlayInBrowser = webApp.isAvailable() && !!payload;
    const redirectScript = canPlayInBrowser
      ? `<script>location.replace(${JSON.stringify(`/?invite=${encodeURIComponent(token)}`)})</script>`
      : '';
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
      headExtra: redirectScript,
    });
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(html);
  } else if (pathname === '/privacy' || pathname === '/terms') {
    // Public, no-auth policy pages. App Store Connect / Google Play require a
    // publicly reachable Privacy Policy URL; the in-app copy is WS-only, so
    // serve the SAME admin-managed config here to keep them in sync.
    // ?lang=ko|en|de (defaults to ko).
    const langParam = url.searchParams.get('lang');
    const lang = ['ko', 'en', 'de'].includes(langParam) ? langParam : 'ko';
    const isPrivacy = pathname === '/privacy';
    const baseKey = isPrivacy ? 'privacy_policy' : 'eula_content';
    let body = '';
    try {
      body = (await getLocalizedConfig(baseKey, lang)) || '';
    } catch (err) {
      console.error('policy page error:', err);
    }
    const T = {
      ko: { privacy: '개인정보처리방침', terms: '이용약관' },
      en: { privacy: 'Privacy Policy', terms: 'Terms of Service' },
      de: { privacy: 'Datenschutzrichtlinie', terms: 'Nutzungsbedingungen' },
    };
    const pageTitle = isPrivacy ? T[lang].privacy : T[lang].terms;
    const otherLabel = isPrivacy ? T[lang].terms : T[lang].privacy;
    const html = `<!DOCTYPE html><html lang="${lang}"><head>`
      + `<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">`
      + `<meta name="robots" content="all"><title>${escapeHtml(pageTitle)} · Tichu Online</title>`
      + `<style>body{margin:0;background:#f6f4ef;color:#2b2b2b;`
      + `font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Noto Sans KR',sans-serif;line-height:1.7}`
      + `.wrap{max-width:760px;margin:0 auto;padding:40px 22px 80px}`
      + `h1{font-size:22px;margin:0 0 6px}.nav{font-size:13px;margin:0 0 24px}`
      + `.nav a{color:#7a6a4f;text-decoration:none;margin-right:14px}`
      + `pre{white-space:pre-wrap;word-break:break-word;font:inherit;margin:0}</style></head>`
      + `<body><div class="wrap"><h1>${escapeHtml(pageTitle)}</h1>`
      + `<div class="nav"><a href="${isPrivacy ? '/privacy' : '/terms'}?lang=ko">한국어</a>`
      + `<a href="${isPrivacy ? '/privacy' : '/terms'}?lang=en">English</a>`
      + `<a href="${isPrivacy ? '/privacy' : '/terms'}?lang=de">Deutsch</a>`
      + ` · <a href="${isPrivacy ? '/terms' : '/privacy'}?lang=${lang}">${escapeHtml(otherLabel)}</a></div>`
      + `<pre>${escapeHtml(body || (lang === 'ko' ? '내용이 준비 중입니다.' : 'Content is being prepared.'))}</pre>`
      + `</div></body></html>`;
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(html);
  } else if (pathname === '/support') {
    // Public, no-auth customer-support page. App Store Connect / Google Play
    // require a reachable Support URL. Self-contained (no DB) so it always
    // renders even before any admin config is set. ?lang=ko|en|de (default ko).
    const langParam = url.searchParams.get('lang');
    const lang = ['ko', 'en', 'de'].includes(langParam) ? langParam : 'ko';
    const SUP = {
      ko: {
        title: '고객지원', heading: 'Tichu Online 고객지원',
        intro: '도움이 필요하신가요? 자주 묻는 질문을 먼저 확인하시고, 해결되지 않으면 아래 이메일이나 앱 내 문의로 연락 주세요. 보통 영업일 기준 1~2일 내에 답변드립니다.',
        contact: '문의 이메일', inApp: '앱 내 문의', inAppDesc: '설정 → 문의하기 에서 직접 문의를 남기실 수 있어요. 답변은 앱 내 문의 내역에서 확인됩니다.',
        faqTitle: '자주 묻는 질문',
        faq: [
          ['게임 규칙은 어디서 보나요?', '게임 화면의 규칙(?) 버튼에서 티츄·마이티·스컬킹·러브레터 각 게임의 규칙을 확인할 수 있습니다.'],
          ['로그인 / 계정 문제', '소셜 로그인(애플·구글·카카오)으로 접속합니다. 로그인이 안 되면 앱을 최신 버전으로 업데이트한 뒤 다시 시도해 주세요.'],
          ['골드 / 결제 문의', '골드는 게임 플레이 또는 인앱 결제로 얻을 수 있습니다. 결제했는데 골드가 지급되지 않았다면 결제 영수증과 함께 이메일로 문의해 주세요.'],
          ['환불은 어떻게 하나요?', '인앱 결제 환불은 구입하신 스토어(App Store / Google Play) 정책에 따라 진행됩니다. 스토어 고객센터를 통해 요청해 주세요.'],
          ['불량 이용자 신고', '게임 중 상대 프로필에서 신고할 수 있습니다. 접수된 신고는 운영팀이 검토합니다.'],
          ['회원탈퇴 / 데이터 삭제', '설정 → 회원탈퇴 에서 계정과 모든 데이터를 삭제할 수 있습니다. 삭제 후에는 복구가 불가능합니다.'],
        ],
        links: '관련 문서', privacy: '개인정보처리방침', terms: '이용약관', store: '스토어에서 보기',
      },
      en: {
        title: 'Support', heading: 'Tichu Online Support',
        intro: 'Need help? Please check the FAQ below first. If that does not resolve your issue, reach us by email or through the in-app inquiry. We usually reply within 1–2 business days.',
        contact: 'Contact email', inApp: 'In-app inquiry', inAppDesc: 'Go to Settings → Submit Inquiry to send us a message directly. Replies appear in your in-app inquiry history.',
        faqTitle: 'Frequently Asked Questions',
        faq: [
          ['Where can I find the rules?', 'Tap the Rules (?) button on the game screen to read the rules for Tichu, Mighty, Skull King and Love Letter.'],
          ['Login / account issues', 'Sign in with a social account (Apple, Google or Kakao). If login fails, update to the latest app version and try again.'],
          ['Gold / purchase questions', 'You can earn gold by playing or buy it via in-app purchase. If a purchase did not credit your gold, email us with your store receipt.'],
          ['How do I get a refund?', 'In-app purchase refunds are handled by the store you bought from (App Store / Google Play). Please request a refund through their support.'],
          ['Report a player', 'You can report an opponent from their profile during a game. Our team reviews every report.'],
          ['Delete account / data', 'Go to Settings → Delete Account to remove your account and all associated data. Deletion is permanent and cannot be undone.'],
        ],
        links: 'Related', privacy: 'Privacy Policy', terms: 'Terms of Service', store: 'View in store',
      },
      de: {
        title: 'Support', heading: 'Tichu Online Support',
        intro: 'Brauchst du Hilfe? Bitte sieh dir zuerst die FAQ unten an. Falls das dein Problem nicht löst, erreichst du uns per E-Mail oder über die In-App-Anfrage. Wir antworten in der Regel innerhalb von 1–2 Werktagen.',
        contact: 'Kontakt-E-Mail', inApp: 'In-App-Anfrage', inAppDesc: 'Gehe zu Einstellungen → Anfrage senden, um uns direkt zu schreiben. Antworten erscheinen in deinem Anfrageverlauf.',
        faqTitle: 'Häufig gestellte Fragen',
        faq: [
          ['Wo finde ich die Regeln?', 'Tippe im Spielbildschirm auf die Regeln-Schaltfläche (?), um die Regeln für Tichu, Mighty, Skull King und Love Letter zu lesen.'],
          ['Login- / Kontoprobleme', 'Melde dich mit einem sozialen Konto an (Apple, Google oder Kakao). Falls der Login fehlschlägt, aktualisiere die App und versuche es erneut.'],
          ['Gold / Kauf-Fragen', 'Gold erhältst du durch Spielen oder per In-App-Kauf. Wurde dein Gold nach einem Kauf nicht gutgeschrieben, schreib uns mit deinem Beleg.'],
          ['Wie erhalte ich eine Rückerstattung?', 'Rückerstattungen für In-App-Käufe werden über den jeweiligen Store (App Store / Google Play) abgewickelt. Bitte fordere sie dort an.'],
          ['Spieler melden', 'Du kannst einen Gegner während des Spiels über sein Profil melden. Unser Team prüft jede Meldung.'],
          ['Konto / Daten löschen', 'Gehe zu Einstellungen → Konto löschen, um dein Konto und alle Daten zu entfernen. Die Löschung ist endgültig.'],
        ],
        links: 'Verwandt', privacy: 'Datenschutzrichtlinie', terms: 'Nutzungsbedingungen', store: 'Im Store ansehen',
      },
    };
    const s = SUP[lang];
    const faqHtml = s.faq.map(
      ([q, a]) => `<details><summary>${escapeHtml(q)}</summary><p>${escapeHtml(a)}</p></details>`
    ).join('');
    const html = `<!DOCTYPE html><html lang="${lang}"><head>`
      + `<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">`
      + `<meta name="robots" content="all"><title>${escapeHtml(s.title)} · Tichu Online</title>`
      + `<style>body{margin:0;background:#f6f4ef;color:#2b2b2b;`
      + `font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Noto Sans KR',sans-serif;line-height:1.7}`
      + `.wrap{max-width:760px;margin:0 auto;padding:40px 22px 80px}`
      + `h1{font-size:22px;margin:0 0 6px}h2{font-size:16px;margin:32px 0 12px}`
      + `.nav{font-size:13px;margin:0 0 22px}.nav a{color:#7a6a4f;text-decoration:none;margin-right:14px}`
      + `.intro{color:#4a4a4a;margin:0 0 8px}`
      + `.card{background:#fff;border:1px solid #e7e1d6;border-radius:12px;padding:14px 16px;margin:10px 0}`
      + `.card a{color:#7a6a4f}`
      + `details{background:#fff;border:1px solid #e7e1d6;border-radius:12px;padding:12px 16px;margin:8px 0}`
      + `summary{cursor:pointer;font-weight:600}details p{margin:10px 0 2px;color:#4a4a4a}`
      + `.foot{font-size:12px;color:#9a917f;margin-top:40px}</style></head>`
      + `<body><div class="wrap"><h1>${escapeHtml(s.heading)}</h1>`
      + `<div class="nav"><a href="/support?lang=ko">한국어</a>`
      + `<a href="/support?lang=en">English</a><a href="/support?lang=de">Deutsch</a></div>`
      + `<p class="intro">${escapeHtml(s.intro)}</p>`
      + `<div class="card"><strong>${escapeHtml(s.contact)}:</strong> `
      + `<a href="mailto:${SUPPORT_EMAIL}">${escapeHtml(SUPPORT_EMAIL)}</a><br>`
      + `<strong>${escapeHtml(s.inApp)}:</strong> ${escapeHtml(s.inAppDesc)}</div>`
      + `<h2>${escapeHtml(s.faqTitle)}</h2>${faqHtml}`
      + `<h2>${escapeHtml(s.links)}</h2><div class="card">`
      + `<a href="/privacy?lang=${lang}">${escapeHtml(s.privacy)}</a> · `
      + `<a href="/terms?lang=${lang}">${escapeHtml(s.terms)}</a><br>`
      + `<a href="${IOS_STORE_URL}">App Store</a> · `
      + `<a href="${ANDROID_STORE_URL}">Google Play</a></div>`
      + `<p class="foot">© Tichu Online</p>`
      + `</div></body></html>`;
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(html);
  } else if (pathname === '/debug-path') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end(`pathname=${req.url} | hasAdmin=${typeof handleAdminRoute}`);
  } else if (await webApp.serve(req, res, pathname)) {
    // The web client IS the site: every branch above this one is a real route,
    // so by the time we get here the path belongs to the app (a bundled file,
    // or a client-side route that gets the shell). Same-origin with the
    // WebSocket, which matters because nothing here emits CORS headers.
    //
    // Returns false only when the image shipped without a web bundle — a
    // server-only hotfix — and then the marketing page answers instead.
  } else {
    // Only reached when the image shipped without a web bundle (server-only
    // hotfix). Normally the web client answers '/' above — this is the
    // stand-in, so it points at the stores and says nothing about playing in
    // a browser, which is exactly what is unavailable right now.
    const html = renderMarketingPage({
      title: 'Tichu Online으로 친구들과 카드 한 판',
      description: '티츄, 마이티, 스컬킹, 러브레터를 즐길 수 있는 멀티플레이 카드게임입니다. 아래 스토어에서 설치한 뒤 바로 게임에 참여할 수 있어요.',
      secondaryLabel: 'Google Play에서 설치',
      secondaryHref: ANDROID_STORE_URL,
      tertiaryLabel: 'App Store에서 설치',
      tertiaryHref: IOS_STORE_URL,
      metaTitle: 'Tichu Online',
      metaDescription: '티츄, 마이티, 스컬킹, 러브레터를 즐길 수 있는 멀티플레이 카드게임 Tichu Online',
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
// Rooms the draining peer told us it still holds. Someone whose socket dropped
// mid-drain reconnects HERE (our /health is the one the LB likes now) while
// their game is still finishing a round over there — this is what lets us tell
// them "your match is coming" instead of dropping them in a bare lobby, where
// the last tester concluded the game was gone and started a new one.
// nickname -> { roomId, roomName, since }
const pendingArrivals = new Map();

// How long after touching a live match you have to wait before dropping into
// another one. Rate-limits both directions of the mid-game seat swap: without
// it, walking out and re-entering is free (dodge a bad hand, come back on the
// next deal) and seat-hopping between rooms costs nothing.
//
// Overridable so a local test can shorten it (MID_GAME_JOIN_COOLDOWN_MS=20000
// node server.js) without editing a constant that then has to be remembered
// and put back before a deploy. Production sets nothing and gets 5 minutes.
// Note the client's warning text says "5분" from its own constant, so a
// shortened window will read wrong in the dialog — expected while testing.
const MID_GAME_JOIN_COOLDOWN_MS = diagNumberEnv(
  'MID_GAME_JOIN_COOLDOWN_MS',
  5 * 60 * 1000,
);
// nickname -> epoch ms at which they may join a match in progress again. Keyed
// by nickname, not playerId: ids are reminted on every reconnect, so a
// playerId key would be a cooldown you clear by pulling the network cable.
// Swept with the other expiring maps below; in memory, so a server restart or
// an instance handoff forgives it — acceptable for an anti-annoyance timer.
const midGameJoinCooldowns = new Map();

/** Milliseconds left on someone's mid-game-join cooldown, 0 when clear. */
function midGameJoinCooldownLeft(nickname) {
  const until = midGameJoinCooldowns.get(nickname);
  if (!until) return 0;
  const left = until - Date.now();
  if (left <= 0) {
    midGameJoinCooldowns.delete(nickname);
    return 0;
  }
  return left;
}

// Turn timer system
const turnTimers = {};    // roomId -> setTimeout handle
const timeoutCounts = {}; // roomId -> { playerId: count }
const roundEndTimers = {}; // roomId -> setTimeout handle for auto next round
// Rooms adopted mid-match (blue/green drain) resume as soon as anyone is
// back — see maybeAutoResumeMatch.
const resumeTimers = {};  // roomId -> setTimeout handle for auto match resume
// Frozen-room detector — see the [FREEZE] block in the watchdog interval.
const roomProgress = {}; // roomId -> { sig, since, warned }
// Consecutive failed peer-adopt attempts per room, for retry log throttling.
const migrateFailures = {}; // roomId -> count
const trickEndTimers = {}; // roomId -> setTimeout handle for skull king trick reveal
// Love Letter: backup auto-ack timer for a resolved effect. The primary
// 2.5s auto-ack lives in trickEndTimers; this fires just after it as a safety
// net so a slipped/never-armed primary (reconnect race) costs a brief blip
// instead of stranding the room. Idempotent — see autoAckResolvedLLEffect.
const llAckBackupTimers = {}; // roomId -> setTimeout handle
const turnTimerPhases = {}; // roomId -> phase name (to prevent phase timer reset)
// roomId -> the playerId a per-turn timer is armed for. Needed to re-arm the
// same timeout after a reconnect without restarting the clock; the id is not
// recoverable from the handle. Only set for per-turn timers, never phase ones.
const turnTimerTargets = {};
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
  // A drain that never delivered (peer SIGKILLed, notice raced a crash) would
  // otherwise promise a match that is never coming. The window can't outlive
  // the grace period, so anything older is stale.
  for (const [nickname, info] of pendingArrivals) {
    if (now - info.since > 20 * 60 * 1000) pendingArrivals.delete(nickname);
  }
  for (const [token, payload] of inviteLinkTokens) {
    if (now - payload.createdAt > 7 * 24 * 60 * 60 * 1000) {
      inviteLinkTokens.delete(token);
    }
  }
  for (const [nickname, until] of midGameJoinCooldowns) {
    if (now >= until) midGameJoinCooldowns.delete(nickname);
  }
  // Clean up abandoned rooms — including ones with a game still in progress,
  // which have no other exit path. See lobby/zombieSweep.js.
  const abandoned = findAbandonedRooms({
    rooms: lobby.rooms,
    playerSessions,
    now,
    maxAge,
  });
  for (const { id, reason, stuckIn } of abandoned) {
    // A room reaped here while still mid-game is evidence of a freeze, and
    // stuckIn names the state it died in.
    console.log(`[Cleanup] Removing zombie room: ${id} (${reason})${stuckIn ? ` (game abandoned in ${stuckIn})` : ''}`);
    removeRoomAndNotifySpectators(id);
  }
  if (abandoned.length > 0) broadcastRoomList();
}, 5 * 60 * 1000);

// WebSocket heartbeat: detect zombie connections (network died without proper close).
// Pings every 15s; terminates any client that didn't pong since last ping (max ~30s detection).
// Terminated sockets fire the `close` event, which runs the normal disconnect flow
// (marks player disconnected and starts the 30s waiting-room removal timer).
const HEARTBEAT_INTERVAL_MS = 15000;
const HEARTBEAT_MISS_THRESHOLD = 2;
const heartbeatInterval = setInterval(() => {
  wss.clients.forEach((ws) => {
    if ((ws.missedHeartbeats || 0) >= HEARTBEAT_MISS_THRESHOLD) {
      logVerboseConnection(`[Heartbeat] Terminating zombie connection: ${ws.nickname || '-'} (${ws.playerId || '-'})`);
      try { ws.terminate(); } catch (_) {}
      return;
    }
    ws.isAlive = false;
    ws.missedHeartbeats = (ws.missedHeartbeats || 0) + 1;
    try { ws.ping(); } catch (_) {}
  });
}, HEARTBEAT_INTERVAL_MS);
wss.on('close', () => {
  clearInterval(heartbeatInterval);
});

// ── DIAGNOSTICS: event-loop lag + slow-path detail ───────────────────────────
// Investigating "bots lag → players get kicked". Node is single-threaded, so any
// synchronous work (bot rollouts/solver, GC) blocks the loop; if the block spans
// the 15s heartbeat the client is terminated as a zombie. A probe fires every
// DIAG_PROBE_MS and the gap *beyond* that interval is how long the loop was
// blocked. This tells us CPU-blocking (lag spikes, flat memory) vs memory
// pressure (lag rises with GC + climbing rss/heap). Set DIAG=0 to silence.
function diagNumberEnv(name, fallback) {
  const n = Number(process.env[name]);
  return Number.isFinite(n) && n >= 0 ? n : fallback;
}

const DIAG_ON = process.env.DIAG !== '0';
const DIAG_SLOW_MS = diagNumberEnv('DIAG_SLOW_MS', 40);
const DIAG_BOT_SLOW_MS = diagNumberEnv('DIAG_BOT_SLOW_MS', 100);
const DIAG_STALL_MS = diagNumberEnv('DIAG_STALL_MS', 200);
const DIAG_SUMMARY_MS = diagNumberEnv('DIAG_SUMMARY_MS', 30000); // baseline summary cadence (lower in tests)

if (DIAG_ON) {
  const DIAG_PROBE_MS = 1000;
  const MB = 1048576;

  // GC observation — the discriminator for "is this lag spike a GC pause?".
  // Bot CPU is structurally capped (~80ms) and gets its own bot-decide timing,
  // so the remaining suspects for a spike are GC, untimed server code, or a
  // host pause. Each probe reports how many ms of GC ran since the previous
  // probe: if a stall's lag ≈ the GC time in its window, it's GC; if lag >> gc,
  // it's non-GC blocking. Major (mark-sweep-compact) is the expensive kind.
  // Note: GC entries are delivered slightly after the pause, so per-probe
  // attribution can be off by one probe — the 30s window's maxProbe GC is the
  // robust signal (compare it against maxLag in the same window).
  const { PerformanceObserver, constants } = require('perf_hooks');
  let gcTotalMs = 0;   // cumulative all-GC time
  let gcMajorMs = 0;   // cumulative major-GC time
  const gcObs = new PerformanceObserver((list) => {
    for (const e of list.getEntries()) {
      const kind = (e.detail && e.detail.kind) != null ? e.detail.kind : e.kind;
      gcTotalMs += e.duration;
      if (kind === constants.NODE_PERFORMANCE_GC_MAJOR) gcMajorMs += e.duration;
    }
  });
  gcObs.observe({ entryTypes: ['gc'] });

  let diagLastProbe = process.hrtime.bigint();
  let diagMaxLag = 0;
  let diagLastReport = Date.now();
  let gcAtLastProbe = 0;      // gcTotalMs snapshot at previous probe
  let gcMajorAtLastProbe = 0;
  let winGcMs = 0;            // GC ms over the current 30s window
  let winGcMajorMs = 0;
  let winMaxGcProbe = 0;     // largest single-probe GC total in the window

  setInterval(() => {
    const now = process.hrtime.bigint();
    const lag = Number(now - diagLastProbe) / 1e6 - DIAG_PROBE_MS; // ms blocked beyond schedule
    diagLastProbe = now;
    if (lag > diagMaxLag) diagMaxLag = lag;

    const gcInProbe = gcTotalMs - gcAtLastProbe;
    const gcMajorInProbe = gcMajorMs - gcMajorAtLastProbe;
    gcAtLastProbe = gcTotalMs;
    gcMajorAtLastProbe = gcMajorMs;
    winGcMs += gcInProbe;
    winGcMajorMs += gcMajorInProbe;
    if (gcInProbe > winMaxGcProbe) winMaxGcProbe = gcInProbe;

    // Immediate warning on a stall (default >200ms is something a player can feel).
    if (lag > DIAG_STALL_MS) {
      const m = process.memoryUsage();
      // gcShare: how much of this stall the GC explains. ~100% → GC pause;
      // low % → non-GC blocking (server code or host). May undercount if the
      // GC entry lands in the next probe — cross-check the 30s maxProbe line.
      const gcShare = lag > 0 ? Math.min(100, Math.round((gcInProbe / lag) * 100)) : 0;
      console.log(`[DIAG] STALL ${Math.round(lag)}ms gc=${gcInProbe.toFixed(0)}ms(major=${gcMajorInProbe.toFixed(0)},${gcShare}%) | rss=${(m.rss / MB).toFixed(0)}MB heapUsed=${(m.heapUsed / MB).toFixed(0)}MB heapTotal=${(m.heapTotal / MB).toFixed(0)}MB rooms=${lobby.rooms.size} clients=${wss.clients.size}`);
    }
    // Baseline summary every 30s even when nothing stalls.
    if (Date.now() - diagLastReport >= DIAG_SUMMARY_MS) {
      const m = process.memoryUsage();
      // Bot/room health: total bots + "ghost" rooms (an in-progress game with
      // ZERO humans present). Ghost should stay 0 — a room whose last human
      // left/AFK'd is torn down, so a rising ghost/bot count means rooms (and
      // their bots) are leaking rather than being cleaned up. Single pass, no
      // per-room array allocation. ~2.4µs for 100 rooms, once per 30s.
      //
      // Counts CONNECTED humans, not occupied seats: a disconnected player
      // keeps their slot for reconnection, so seat-counting reported ghost=0
      // for exactly the leak this metric exists to catch.
      let totalBots = 0;
      let ghostRooms = 0;
      for (const [, rm] of lobby.rooms) {
        if (!rm || !Array.isArray(rm.players)) continue;
        let humans = 0;
        let bots = 0;
        for (const p of rm.players) {
          if (!p) continue;
          if (p.isBot) bots++; else if (p.connected) humans++;
        }
        totalBots += bots;
        if (rm.game && humans === 0) ghostRooms++; // in-game room with nobody present
      }
      const botDiag = botPool
        ? ` bots=q${botPool.queueDepth}/f${botPool.inFlight}/maxq${botPool.stats.maxQueue}/slow${botPool.stats.slow}/stale${botPool.stats.stale}/to${botPool.stats.timeouts}/er${botPool.stats.errors}/mqw${botPool.stats.maxQWaitMs.toFixed(0)}/mc${botPool.stats.maxComputeMs.toFixed(0)}/mt${botPool.stats.maxTotalMs.toFixed(0)}${botPool.disabled ? '/DISABLED' : ''}`
        : '';
      console.log(`[DIAG] 30s | maxLag=${Math.round(diagMaxLag)}ms gc=${winGcMs.toFixed(0)}ms(major=${winGcMajorMs.toFixed(0)},maxProbe=${winMaxGcProbe.toFixed(0)}) rss=${(m.rss / MB).toFixed(0)}MB heapUsed=${(m.heapUsed / MB).toFixed(0)}MB heapTotal=${(m.heapTotal / MB).toFixed(0)}MB rooms=${lobby.rooms.size}(bots${totalBots},ghost${ghostRooms}) clients=${wss.clients.size}${botDiag}`);
      diagMaxLag = 0;
      winGcMs = 0;
      winGcMajorMs = 0;
      winMaxGcProbe = 0;
      if (botPool) botPool.resetWindowStats(); // each line = THIS window's peaks/rates
      diagLastReport = Date.now();
    }
  }, DIAG_PROBE_MS).unref();
}
// ──────────────────────────────────────────────────────────────────────────────

// ── STUCK-BOT WATCHDOG ────────────────────────────────────────────────────────
// Bots get NO turn-timeout (startTurnTimer skips them), so if a bot's turn is
// ever left unscheduled — a lost/cleared pendingBotTimer, a leaked
// pendingBotCheck flag, a scheduling race on (re)connect — the room freezes
// FOREVER. Humans then rack up turn-timeout strikes while waiting for a bot that
// will never move, and get deserted. Self-play can't reproduce this (the engine
// never strands its own actor); it only happens in the live scheduler. This
// watchdog is the catch-all: if a bot is the pending actor but nothing is
// scheduled for the room across a full interval, force a reschedule. It only
// ever fires on a genuine stall, so it's a no-op in healthy rooms.
const { botWatchdogTick, NON_ACTIONABLE_STATES } = require('./game/botWatchdog');
const BOT_WATCHDOG_MS = 4000;
const botStuckSeen = {}; // roomId -> consecutive intervals seen stranded
setInterval(() => {
  const effectAckTimers = {};
  for (const roomId of Object.keys(trickEndTimers)) effectAckTimers[roomId] = true;
  for (const roomId of Object.keys(llAckBackupTimers)) effectAckTimers[roomId] = true;
  const toRecover = botWatchdogTick({
    rooms: lobby.rooms,
    pendingBotTimers,
    seen: botStuckSeen,
    inFlight: botDecisionInFlight,
    effectAckTimers,
  });
  for (const { roomId, actor } of toRecover) {
    const room = lobby.getRoom(roomId);
    const eff = room?.game?.pendingEffect;
    const llEff = room?.gameType === 'love_letter' && eff
      ? ` effect=${eff.type || '-'} resolved=${eff.resolved ? 1 : 0} needsTarget=${eff.needsTarget ? 1 : 0} needsGuess=${eff.needsGuess ? 1 : 0} ackTimer=${effectAckTimers[roomId] ? 1 : 0}`
      : '';
    console.log(`[BOT] WATCHDOG recovering stranded bot turn: room=${roomId} type=${room?.gameType} state=${room?.game?.state} actor=${actor} pendingCheck=${!!pendingBotCheck[roomId]}${llEff}`);
    try { scheduleBotActions(roomId, true); } catch (e) { console.error('[BOT] WATCHDOG reschedule failed', e); }
  }

  // Frozen-room detector. A live game's signature keeps changing while anything
  // is driving it, so a signature that has not moved for longer than the room's
  // own turn limit allows means nothing is ever going to move it: turn timers
  // only cover `playing` and a few named phases, and the stuck-bot watchdog
  // above deliberately skips round_end/trick_end/dealing. The 30-min zombie
  // sweep eventually reaps such a room, but by then the evidence is gone — so
  // dump it here, once per stall, with the timer/actor state needed to find the
  // cause. Threshold is per-room because the turn limit is per-room; see
  // game/freezeWatch.js.
  const freezeNow = Date.now();
  for (const [roomId, room] of lobby.rooms) {
    if (!room || !room.game) { delete roomProgress[roomId]; continue; }
    const g = room.game;
    const sig = `${g.state}|${g.round ?? ''}|${g.currentPlayer ?? ''}|${g.trickNumber ?? ''}`;
    const prev = roomProgress[roomId];
    if (!prev || prev.sig !== sig) {
      roomProgress[roomId] = { sig, since: freezeNow, warned: false };
      continue;
    }
    if (prev.warned || freezeNow - prev.since < freezeThresholdMs(room.turnTimeLimit)) continue;
    prev.warned = true;
    const actor = typeof g.getPendingActor === 'function' ? g.getPendingActor() : g.currentPlayer;
    const humansPresent = room.players.filter(p => p !== null && !p.isBot && p.connected).length;
    console.warn(
      `[FREEZE] room=${roomId} type=${room.gameType} state=${g.state}`
      + ` stuck=${Math.round((freezeNow - prev.since) / 1000)}s`
      + ` actor=${actor || '-'}${actor && room.isBot(actor) ? '(bot)' : ''}`
      + ` humansPresent=${humansPresent}`
      + ` timers=turn${turnTimers[roomId] ? 1 : 0}/round${roundEndTimers[roomId] ? 1 : 0}`
      + `/trick${trickEndTimers[roomId] ? 1 : 0}/bot${pendingBotTimers[roomId] ? 1 : 0}`
      + `/autoReturn${autoReturnTimers[roomId] ? 1 : 0}`
      + ` inFlight=${botDecisionInFlight[roomId] || 0}`,
    );
  }
}, BOT_WATCHDOG_MS).unref();
// ──────────────────────────────────────────────────────────────────────────────

// Safety net for unawaited async errors
process.on('unhandledRejection', (reason, promise) => {
  console.error('[UNHANDLED REJECTION]', reason);
});

// Last-resort guard against a SYNCHRONOUS throw escaping a non-promise code
// path — most dangerously inside a setTimeout/setInterval callback (turn,
// round, trick and bot timers), which Node delivers outside any try/catch and
// would otherwise crash the whole process and drop every connected game. We
// log and keep running; a single bad timer must not take down all rooms.
process.on('uncaughtException', (err) => {
  console.error('[UNCAUGHT EXCEPTION]', err);
});

// Title translations cache. Populated at boot from tc_shop_items so we can
// localize a peer's equipped title per-recipient without hitting the DB on
// every room-state broadcast. Refreshed lazily on cache miss.
let titleTranslations = {};
async function refreshTitleTranslations() {
  try {
    titleTranslations = await loadTitleTranslations();
  } catch (e) {
    console.warn('[titleTranslations] refresh failed:', e?.message || e);
  }
}

/** Pick a title's display name for the given locale, falling back to the
 *  cached titleName (stored at the title-owner's login time) or Korean. */
function localizeTitleName(titleKey, fallbackName, locale) {
  if (!titleKey) return fallbackName || null;
  const entry = titleTranslations[titleKey];
  if (!entry) return fallbackName || null;
  if (locale === 'en') return entry.en || entry.ko || fallbackName || null;
  if (locale === 'de') return entry.de || entry.ko || fallbackName || null;
  return entry.ko || fallbackName || null;
}

// Initialize database and start server
(async () => {
  await initDatabase();
  await refreshTitleTranslations();
  await loadMaintenanceConfig();
  await loadPhotoScreeningConfig();
  await loadCustomTitleWords();
  await ensureSeasonCycle();
  await cleanupExpiredProfilePhotos();
  setInterval(cleanupExpiredProfilePhotos, 60 * 60 * 1000).unref();

  // Say it out loud at boot. Screening silently not running is the one state
  // that contradicts what the privacy policy and the store review notes claim,
  // and 'skipped' looks exactly like 'clean' in the per-upload log line.
  console.log(
    `[profile-photo] SafeSearch screening: ${
      visionSafeSearch.isEnabled() ? 'ENABLED' : 'DISABLED (uploads are NOT screened)'
    }`,
  );
  server.listen(PORT, () => {
    console.log(`Tichu server running on port ${PORT} (instance=${INSTANCE_NAME})`);
  });
})();

// Capture a room's metadata for migration to a peer instance. Only the
// fields the peer needs to recreate the same room layout — volatile
// in-memory state (hands, chat history, spectator perms, timers) is
// intentionally dropped.
//
// A room with a match in progress is migratable only at a round
// boundary: mid-round there are hands, tricks and pending turn timers
// that we deliberately don't try to serialise, but at round_end the
// only state that outlives the round is the cumulative score and the
// seating (see each engine's getMatchProgress). Returns null for rooms
// that aren't safe to migrate.
// Seats with nobody in them, by current index. See the blockedSlots note in
// serializeRoom.
function emptySlots(room) {
  const out = [];
  for (let i = 0; i < room.maxPlayers; i++) {
    if (!room.players[i]) out.push(i);
  }
  return out;
}

function serializeRoom(room) {
  if (!room) return null;
  let matchProgress = null;
  if (room.game) {
    if (room.game.state !== 'round_end') return null;
    if (typeof room.game.getMatchProgress !== 'function') return null;
    matchProgress = room.game.getMatchProgress();
    if (!matchProgress) return null;
  } else if (room.matchProgress) {
    // Adopted mid-match but not resumed yet — still waiting on players, or
    // inside the resume delay. Two deploys in quick succession would
    // otherwise hop this room again and silently drop the standings,
    // restarting the match from zero. Pass them straight through.
    matchProgress = room.matchProgress;
  }
  const payload = {
    matchProgress,
    // Nicknames only: the peer re-adds each spectator under a fresh id when
    // they reconnect (handleReconnection -> addSpectator), so all it needs is
    // a pointer telling it which room they belong to.
    spectators: (room.spectators || []).map((s) => s.nickname).filter(Boolean),
    // Stable across retries, so the peer can tell "this is the room I already
    // took, the sender just never saw my answer" from a genuine id clash.
    // Without it a lost response is unrecoverable: every retry looks like a
    // duplicate and the sender burns the whole drain window failing.
    migrationOrigin: `${INSTANCE_NAME}:${room.id}`,
    id: room.id,
    name: room.name,
    isPrivate: !!room.isPrivate,
    isRanked: !!room.isRanked,
    password: room.password || '',
    gameType: room.gameType,
    maxPlayers: room.maxPlayers,
    hostId: room.hostId,
    hostNickname: room.hostNickname,
    turnTimeLimit: room.turnTimeLimit,
    targetScore: room.targetScore,
    skExpansions: [...(room.skExpansions || [])],
    // startGame compacts room.players for SK/LL/mighty (the pre-game layout
    // is stashed in _preGamePlayers), so mid-match the slot indices we emit
    // above no longer line up with room.blockedSlots, which still describes
    // the pre-game seating. Re-derive from the seats that are actually empty
    // now — otherwise a 5-player mighty room whose blocked seat wasn't the
    // last one fails mighty's "every non-blocked seat must be filled" check
    // on the peer and loses the match. Left as plain blocks rather than
    // auto-blocks: the shift makes the original mapping unrecoverable, and a
    // seat that stays shut is a far safer wrong guess than one that reopens
    // mid-match.
    blockedSlots: matchProgress ? emptySlots(room) : [...(room.blockedSlots || [])],
    autoBlockedSlots: matchProgress ? [] : [...(room.autoBlockedSlots || [])],
    randomSeating: !!room.randomSeating,
    // Host privacy choice. Was missing from the payload, so a room created
    // with spectating off came back from a migration with it ON (the GameRoom
    // constructor defaults to true) — an audience the host had explicitly
    // refused, appearing after a deploy.
    allowSpectators: room.allowSpectators !== false,
    // Carried so a match that migrates mid-round keeps its exits open — a
    // player who joined on the promise of being able to walk out must not
    // find the option gone after a deploy moved the room.
    allowMidGameJoin: !!room.allowMidGameJoin,
    players: room.players.map((p, slot) => {
      if (!p) return null;
      return {
        slot,
        id: p.id,
        nickname: p.nickname,
        isBot: !!p.isBot,
        botSpeed: p.botSpeed || null,
        botStrategy: p.isBot ? room.bots.get(p.id)?.strategy || null : null,
        // Players pulled out of a live match are already committed to it,
        // so land them pre-readied on the peer — it resumes on its own
        // (maybeAutoResumeMatch), and a stale unready flag would only
        // misrepresent the room in the meantime.
        ready: matchProgress ? true : !!p.ready,
        titleKey: p.titleKey || null,
        titleName: p.titleName || null,
        level: p.isBot ? null : (p.level || 1),
        bannerKey: p.isBot ? null : (p.bannerKey || null),
        photoUrl: p.isBot ? null : (p.photoUrl || null),
        seasonRating: p.isBot ? null : (p.seasonRating ?? null),
        skSeasonRating: p.isBot ? null : (p.skSeasonRating ?? null),
        mightySeasonRating: p.isBot ? null : (p.mightySeasonRating ?? null),
      };
    }),
  };

  // Content hash of everything above. The peer treats a re-sent room as an
  // idempotent success (a retry whose response we lost), which is only sound
  // while the snapshot is identical — if this instance kept mutating the room
  // between attempts, "already adopted" would confirm a STALE copy and we'd
  // delete the newer one. Mismatched fingerprints are refused instead.
  payload.migrationFingerprint = crypto
    .createHash('sha1')
    .update(JSON.stringify(payload))
    .digest('hex');
  return payload;
}

// Read up to 1MB of JSON body from an incoming request. Migration
// payloads are small (a few rooms × ~1KB each); the cap is a sanity
// guard against runaway peers, not a real performance setting.
function readJsonBody(req, limitBytes = 1024 * 1024) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let total = 0;
    req.on('data', (chunk) => {
      total += chunk.length;
      if (total > limitBytes) {
        reject(new Error('payload too large'));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => {
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString('utf8')));
      } catch (err) {
        reject(err);
      }
    });
    req.on('error', reject);
  });
}

// /internal/adopt-rooms POST handler. Peer instance sends a list of
// serialized rooms; we reconstruct each one and pre-register the
// expected human players in `playerSessions` so the existing reconnect
// flow drops them straight into the migrated room when their client
// reconnects to us.
// A room can arrive AFTER the people who belong in it. Someone whose socket
// dropped during the drain reconnects through the load balancer, lands here
// while their room is still on the peer finishing its round, and ends up in
// the lobby. The session pointers registered above only help clients that log
// in later — this one is already past that point, and would sit in the lobby
// watching their game fail to exist (observed in a smoke test: the player gave
// up and created a new room).
//
// So pull them in directly. Same effect as the reconnect path, minus the login.
// Someone we promised a match to has committed to a live game instead. The
// promise is off — say so, or the banner comes back the moment they return to
// the lobby, pointing at a match that resumed without them.
function cancelPendingFor(ws) {
  pendingArrivals.delete(ws.nickname);
  sendTo(ws, { type: 'match_cancelled' });
}

// Free the seat someone is holding in a waiting room so they can be moved into
// their migrated match. Mirrors the duplicate-login cleanup: kill the removal
// timer, drop them, and take the room with them if they were the last human.
function vacateWaitingRoom(ws) {
  const other = lobby.getRoom(ws.roomId);
  if (!other) { ws.roomId = null; return; }
  const timerKey = `${ws.roomId}_${ws.playerId}`;
  if (waitingRoomTimers[timerKey]) {
    clearTimeout(waitingRoomTimers[timerKey]);
    delete waitingRoomTimers[timerKey];
  }
  const leftRoomId = ws.roomId;
  if (ws.isSpectator) other.removeSpectator(ws.playerId);
  else other.removePlayer(ws.playerId);
  ws.roomId = null;
  ws.isSpectator = false;
  if (other.getHumanPlayerCount() === 0) {
    removeRoomAndNotifySpectators(leftRoomId); // sends room_closed to them
  } else {
    // Nothing else would tell them the seat is gone, and the room_joined that
    // normally follows can still be skipped if the roster check rejects them.
    sendTo(ws, { type: 'room_left' });
    broadcastRoomState(leftRoomId);
  }
  broadcastRoomList();
}

function attachWaitingMembers(room, data) {
  const players = new Set(
    (data.players || []).filter((p) => p && !p.isBot && p.nickname).map((p) => p.nickname),
  );
  const watchers = new Set((data.spectators || []).filter(Boolean));
  let attached = 0;

  for (const ws of wss.clients) {
    if (ws.readyState !== ws.OPEN || !ws.nickname) continue;
    if (!players.has(ws.nickname) && !watchers.has(ws.nickname)) continue;
    if (ws.roomId === room.id) continue; // already home

    if (ws.roomId) {
      const other = lobby.getRoom(ws.roomId);
      // Mid-game elsewhere: they made a real choice, and yanking them out of a
      // hand in progress would be worse than letting the old seat lapse. It
      // lapses the normal way — this instance isn't draining, so the usual
      // desertion rules apply to the seat they never came back to.
      if (other && other.game) {
        cancelPendingFor(ws);
        (room.migrationNoShows ||= new Set()).add(ws.nickname);
        continue;
      }
      // Just parked in a waiting room, though, is not a choice worth losing a
      // match over. Measured: a player who made a room while waiting was
      // skipped here, so the match resumed without them and then timed their
      // seat out — from a room they couldn't even see. Move them.
      vacateWaitingRoom(ws);
    }

    if (players.has(ws.nickname)) {
      if (!room.reconnectPlayer(ws.nickname, ws.playerId).success) continue;
      pendingArrivals.delete(ws.nickname);
      ws.roomId = room.id;
      ws.isSpectator = false;
      playerSessions.delete(ws.nickname);
      sendTo(ws, { type: 'room_joined', roomId: room.id, roomName: room.name });
      attached++;
    } else if (watchers.has(ws.nickname)) {
      if (!room.addSpectator(ws.playerId, ws.nickname, '').success) continue;
      pendingArrivals.delete(ws.nickname);
      ws.roomId = room.id;
      ws.isSpectator = true;
      spectatorSessions.delete(ws.nickname);
      sendTo(ws, { type: 'spectate_joined', roomId: room.id, roomName: room.name });
      attached++;
    }
  }

  if (attached > 0) {
    console.log(`[adoptRoom] ${room.id}: pulled ${attached} member(s) in from the lobby`);
    broadcastRoomState(room.id);
    broadcastRoomList();
    // They may be all it was waiting for.
    maybeAutoResumeMatch(room.id);
  }
}

// /internal/pending-rooms — the peer entering drain tells us which rooms it
// still holds and who belongs to them, so we can hold a "your match is on its
// way" state for anyone who reconnects here before the room does.
async function handlePendingRoomsRequest(req, res) {
  const body = await readJsonBody(req);
  const rooms = Array.isArray(body?.rooms) ? body.rooms : [];
  // Nicknames that have since left one of those rooms — the promise no longer
  // holds for them and a "you'll rejoin next round" banner would be a lie.
  for (const nickname of body?.released || []) {
    if (!nickname) continue;
    pendingArrivals.delete(nickname);
    // They may already be sitting in our lobby staring at the banner. Dropping
    // the map entry only helps a future login, so say it out loud. Clients too
    // old to know this type ignore it and fall back to the banner's own TTL.
    for (const ws of wss.clients) {
      if (ws.readyState === ws.OPEN && ws.nickname === nickname && !ws.roomId) {
        sendTo(ws, { type: 'match_cancelled' });
      }
    }
  }
  const now = Date.now();
  let noted = 0;
  for (const r of rooms) {
    if (!r || !r.id || !Array.isArray(r.members)) continue;
    for (const nickname of r.members) {
      if (!nickname) continue;
      pendingArrivals.set(nickname, { roomId: r.id, roomName: r.name || '', since: now });
      noted++;
      // Someone may already be sitting in our lobby wondering where their
      // game went — tell them now rather than only on their next login.
      for (const ws of wss.clients) {
        if (ws.readyState === ws.OPEN && ws.nickname === nickname && !ws.roomId) {
          sendTo(ws, { type: 'match_incoming', roomName: r.name || '' });
        }
      }
    }
  }
  if (noted > 0) console.log(`[pending-rooms] peer is still finishing ${rooms.length} room(s); holding ${noted} member(s)`);
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ noted }));
}

async function handleAdoptRoomsRequest(req, res) {
  const body = await readJsonBody(req);
  const rooms = Array.isArray(body?.rooms) ? body.rooms : [];
  let adopted = 0;
  // Rooms we refused because we already own that exact room and players are
  // in it. The sender is holding a copy that has been overtaken — it needs to
  // know the difference between "try again" and "let go", or it sits on those
  // players until SIGKILL while the rest of the room plays on over here.
  const superseded = [];
  for (const data of rooms) {
    const room = lobby.adoptRoom(data);
    if (!room) {
      const existing = data && data.id ? lobby.getRoom(data.id) : null;
      if (existing && data.migrationOrigin && existing.migrationOrigin === data.migrationOrigin) {
        superseded.push(data.id);
      }
      continue;
    }
    adopted++;
    if (Array.isArray(data.players)) {
      const now = Date.now();
      for (const p of data.players) {
        if (!p || p.isBot || !p.nickname) continue;
        // Register reconnect-pointer keyed by nickname. handleReconnection
        // already looks this up on every login and re-attaches the WS
        // to the room; we just need the entry to exist before the
        // client's reconnect lands.
        playerSessions.set(p.nickname, {
          roomId: room.id,
          disconnectedAt: now,
        });
      }
    }
    // Same for anyone who was watching. Without this they land in the lobby
    // and have to find the room again — measured at ~18s of fumbling in a
    // smoke test, against ~0.5s for the players.
    if (Array.isArray(data.spectators)) {
      const now = Date.now();
      for (const nickname of data.spectators) {
        if (!nickname) continue;
        spectatorSessions.set(nickname, { roomId: room.id, disconnectedAt: now });
      }
    }
    // Everyone pointed at this room, not just those still in it — someone who
    // left mid-drain would otherwise keep the promise until it expired.
    for (const [nickname, info] of pendingArrivals) {
      if (info.roomId === room.id) pendingArrivals.delete(nickname);
    }
    attachWaitingMembers(room, data);
  }
  // Anything we couldn't take (a duplicate id, a malformed entry) must read
  // as a failure on the sender's side — it still holds the only copy of that
  // room, and treating a partial adopt as success deletes it. 409 rather than
  // 200 so even a caller that only checks the status code retries.
  const ok = adopted === rooms.length;
  res.writeHead(ok ? 200 : 409, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ adopted, requested: rooms.length, superseded }));
}

// A room adopted mid-match lands here in the waiting state, holding the
// standings it had on the peer. Rather than making the host press start
// again, pick the match back up on our own once the players are here.
// Called whenever someone reconnects into such a room.
function maybeAutoResumeMatch(roomId) {
  const room = lobby.getRoom(roomId);
  if (!room || room.game || !room.matchProgress) return;
  if (isDraining) return; // on our way out — don't deal a round we can't finish

  // As soon as ANYONE is back, deal the next round. We deliberately do not
  // hold for the others: a round in progress doesn't wait on a disconnected
  // player either — it auto-plays their turn and they slot back in when they
  // return. Waiting here would be a different rule for no reason, and it buys
  // the players who DID come back a stretch of staring at what looks like a
  // room waiting for the host to press start (measured at ~14s in a smoke
  // test, with a backgrounded phone as the straggler).
  //
  // Anyone still away gets a playerSessions pointer from startResumedMatch,
  // so they drop straight into the running game.
  const humans = room.players.filter((p) => p !== null && !p.isBot);
  if (!humans.some((p) => p.connected)) return; // nobody back yet
  if (resumeTimers[roomId]) return; // already on its way

  // Next tick rather than synchronously: handleReconnection is still sending
  // this player their room state, and we'd rather not re-enter mid-flight.
  resumeTimers[roomId] = setTimeout(() => {
    delete resumeTimers[roomId];
    startResumedMatch(roomId);
  }, 0);
}

function startResumedMatch(roomId) {
  const room = lobby.getRoom(roomId);
  if (!room || room.game || !room.matchProgress) return;
  if (isDraining) return;

  const humans = room.players.filter((p) => p !== null && !p.isBot);
  if (!humans.some((p) => p.connected)) return; // everyone left again

  // Same bookkeeping handleStartGame does: drop waiting-room kick timers and
  // make sure anyone who hasn't reconnected yet can still find their way in.
  for (const player of humans) {
    const timerKey = `${roomId}_${player.id}`;
    if (waitingRoomTimers[timerKey]) {
      clearTimeout(waitingRoomTimers[timerKey]);
      delete waitingRoomTimers[timerKey];
    }
    if (player.connected === false) {
      playerSessions.set(player.nickname, { roomId, disconnectedAt: Date.now() });
    }
  }

  if (!room.startGame()) {
    // Roster no longer supports a start (someone left for good). Drop the
    // carried standings so the room behaves like any other waiting room.
    console.log(`[${INSTANCE_NAME}] resume ${roomId}: roster no longer startable — dropping carried match`);
    room.matchProgress = null;
    broadcastRoomState(roomId);
    broadcastRoomList();
    return;
  }

  console.log(`[${INSTANCE_NAME}] resumed migrated ${room.gameType} match in ${roomId}`);
  broadcastRoomState(roomId);
  broadcastRoomList();
  sendGameStateToAll(roomId);

  // Someone on the roster is provably not coming back — they were already
  // playing a different game here when their old match arrived. A six-player
  // Mighty cannot quietly carry on as five, which is what happened before
  // this: the seat stayed empty and got timed out of a room its owner could
  // not even see. Resume, then close the match out the honest way. Desertion
  // records it, scores it, and ends it for everyone at once.
  const noShows = room.migrationNoShows;
  room.migrationNoShows = null;
  if (noShows && noShows.size > 0) {
    const absent = room.players.find(
      (p) => p !== null && !p.isBot && noShows.has(p.nickname),
    );
    if (absent) {
      console.log(`[${INSTANCE_NAME}] resume ${roomId}: ${absent.nickname} is playing elsewhere — deserting`);
      // One call ends the match for the whole table, so the first is enough.
      // No leave-count or ranked ban: they were shown a banner promising the
      // match would come to them, killed time in the lobby the way it invited
      // them to, and the deploy is what made the two mutually exclusive.
      // Deserting them is bookkeeping, not a verdict.
      handleDesertion(roomId, absent.id, 'leave', { penalize: false }).catch((e) =>
        console.error(`[${INSTANCE_NAME}] no-show desertion failed:`, e));
    }
  }
}

// Tell the peer someone is no longer part of a room we announced, so it stops
// promising them a match. Fire-and-forget: the worst case is a stale banner
// that the client drops on its own timer anyway.
function releasePeerPending(nickname) {
  if (!isDraining || !PEER_URL || !INTERNAL_MIGRATE_TOKEN || !nickname) return;
  fetch(`${PEER_URL}/internal/pending-rooms`, {
    method: 'POST',
    headers: {
      'X-Internal-Token': INTERNAL_MIGRATE_TOKEN,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ rooms: [], released: [nickname] }),
    signal: AbortSignal.timeout(5000),
  }).catch(() => { /* best effort */ });
}

// Everyone still seated in a room that is disappearing WITHOUT migrating —
// deserted, emptied out, or dropped because we couldn't serialize it. The
// peer announced this room to them at drain start; if we go quiet now, the
// last player standing waits out the banner's whole TTL for a match that no
// longer exists. Found on a real device: one of two players left mid-round,
// the game ended, the room was removed, and the other player's banner stayed.
function releasePeerPendingForRoom(room) {
  if (!isDraining || !PEER_URL || !INTERNAL_MIGRATE_TOKEN || !room) return;
  const nicknames = room.players
    .filter((p) => p !== null && !p.isBot && p.nickname)
    .map((p) => p.nickname);
  if (nicknames.length === 0) return;
  fetch(`${PEER_URL}/internal/pending-rooms`, {
    method: 'POST',
    headers: {
      'X-Internal-Token': INTERNAL_MIGRATE_TOKEN,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ rooms: [], released: nicknames }),
    signal: AbortSignal.timeout(5000),
  }).catch(() => { /* best effort */ });
}

// Hand the peer a list of the rooms still finishing here, so it can hold their
// members instead of showing them an empty lobby. Best-effort: a failure just
// means those players see the lobby, which is what happened before this
// existed.
async function notifyPeerOfPendingRooms() {
  if (!PEER_URL || !INTERNAL_MIGRATE_TOKEN) return;
  const rooms = [];
  for (const [, room] of lobby.rooms) {
    // Players only. The banner promises a seat back at the next round, which
    // is meaningless to someone who was just watching — and a spectator who
    // leaves the room after this notice goes out would keep seeing it, since
    // the peer has no way to hear about that. Spectators are still restored:
    // the adopt payload carries them and attachWaitingMembers puts them back.
    const members = room.players
      .filter((p) => p !== null && !p.isBot && p.nickname)
      .map((p) => p.nickname);
    if (members.length > 0) rooms.push({ id: room.id, name: room.name, members });
  }
  if (rooms.length === 0) return;
  try {
    const r = await fetch(`${PEER_URL}/internal/pending-rooms`, {
      method: 'POST',
      headers: {
        'X-Internal-Token': INTERNAL_MIGRATE_TOKEN,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ rooms }),
      signal: AbortSignal.timeout(5000),
    });
    if (!r.ok) throw new Error(`peer responded ${r.status}`);
    console.log(`[${INSTANCE_NAME}] told peer about ${rooms.length} room(s) still finishing here`);
  } catch (err) {
    console.error(`[${INSTANCE_NAME}] pending-rooms notice failed:`, err.message || err);
  }
}

// Migrate one room to the peer instance. No-op outside of drain mode and
// for rooms mid-round (only a round boundary is migratable — see
// serializeRoom). After a successful peer adopt, we close the human
// players' WebSockets — their clients reconnect through the LB, land on
// the peer (since this instance's /health is now 503), and the peer's
// already-registered playerSessions entry routes them straight into the
// same-id room. Bot-only rooms have no humans to migrate, so they're
// just dropped.
async function maybeMigrateRoom(roomId) {
  if (!isDraining) return;
  const room = lobby.getRoom(roomId);
  if (!room) return;
  if (room.game && room.game.state !== 'round_end') return;

  // Whatever happens below, this room leaves this instance — kill its
  // timers now so a pending auto-next-round can't deal a fresh hand into
  // a room we're in the middle of handing off.
  clearRoomTimers(roomId, room);

  const humans = room.players.filter(p => p && !p.isBot);
  if (humans.length === 0) {
    lobby.removeRoom(roomId);
    return;
  }

  if (!PEER_URL || !INTERNAL_MIGRATE_TOKEN) {
    // Single-instance fallback: no peer to migrate to. Best we can do
    // is close the WS so the client tries to reconnect once we're back.
    for (const p of humans) findWsByPlayerId(p.id)?.close(1001);
    lobby.removeRoom(roomId);
    return;
  }

  const data = serializeRoom(room);
  if (!data) {
    // Shouldn't happen (we only get here at a round boundary, and every
    // engine implements getMatchProgress) — but if it ever does, close the
    // sockets rather than dropping the room out from under them: a client
    // left holding a room that no longer exists just hangs until SIGKILL.
    releasePeerPendingForRoom(room);
    for (const p of humans) findWsByPlayerId(p.id)?.close(1001);
    lobby.removeRoom(roomId);
    return;
  }

  try {
    const r = await fetch(`${PEER_URL}/internal/adopt-rooms`, {
      method: 'POST',
      headers: {
        'X-Internal-Token': INTERNAL_MIGRATE_TOKEN,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ rooms: [data] }),
      // Without this a peer that accepts the connection but never answers
      // hangs here forever. The drain sweep is serialised behind one
      // in-flight attempt, so that one stuck request would freeze the
      // retries for every other room too, right up to SIGKILL.
      signal: AbortSignal.timeout(5000),
    });
    const body = await r.json().catch(() => null);
    // A refusal can still be terminal. If the peer already owns this room and
    // players are in it — someone whose connection dropped reconnected there
    // while we were retrying — then our copy is the overtaken one. Retrying
    // can never win, and holding on would strand the players still here (they
    // can't even leave: see DRAIN_FROZEN_ACTIONS) until SIGKILL. Let go so
    // they follow the room over.
    const overtaken = !!body && Array.isArray(body.superseded) && body.superseded.includes(roomId);
    if (!overtaken) {
      if (!r.ok) throw new Error(`peer responded ${r.status}`);
      // A 200 is not enough: the peer skips rooms it can't take (duplicate id,
      // malformed entry) and used to report that as success, after which we
      // deleted the only remaining copy. Require it to have taken the room.
      if (!body || body.adopted !== 1) {
        throw new Error(`peer adopted ${body ? body.adopted : '?'}/1`);
      }
    }
    delete migrateFailures[roomId];
    console.log(overtaken
      ? `[${INSTANCE_NAME}] ${roomId} superseded on peer — releasing our copy`
      : `[${INSTANCE_NAME}] migrated ${roomId} to peer`);
  } catch (err) {
    // Leave the room exactly as it is — players still connected, game parked
    // at the round boundary with its timers already cleared — and let the
    // drain poll try again. Dropping it here on a transient failure (peer
    // still warming up, a blip, a bad token) would throw away a live match
    // for something that resolves on the next attempt seconds later. If it
    // never resolves, docker's stop_grace_period is the backstop.
    const n = (migrateFailures[roomId] = (migrateFailures[roomId] || 0) + 1);
    // Retries run every 2s; don't paper the log with hundreds of lines.
    if (n === 1 || n % 15 === 0) {
      console.error(`[${INSTANCE_NAME}] migrate ${roomId} failed (attempt ${n}, will retry):`, err.message || err);
    }
    return;
  }

  for (const p of humans) findWsByPlayerId(p.id)?.close(1001);

  // Spectators travel too — the peer registered a spectatorSessions pointer
  // for each of them at adopt time, so closing the socket sends them back to
  // the same room rather than the lobby. Without this close they'd hang on a
  // dead WS until docker SIGKILL.
  for (const spectator of room.spectators || []) {
    findWsByPlayerId(spectator.id)?.close(1001);
  }

  lobby.removeRoom(roomId);
}

// SIGTERM handler — entry point for the blue/green drain flow.
//   1. Flip isDraining so /health flips to 503 (LB stops sending us new
//      connections; existing WS connections are unaffected).
//   2. Migrate every waiting room (no game in progress) to the peer.
//   3. Close every WS that isn't tied to a room — those users go
//      straight to the peer's lobby on reconnect.
//   4. Rooms mid-round keep playing here until the round ends; the
//      round_end handler then migrates them instead of dealing another
//      hand, so the wait is one round rather than a whole match. The
//      container's stop_grace_period (15m) is the cap.
process.on('SIGTERM', async () => {
  if (isDraining) return;
  console.log(`[${INSTANCE_NAME}] SIGTERM received — entering drain mode`);
  isDraining = true;

  // Snapshot first so concurrent room edits during migration don't
  // mutate the iteration target.
  const roomIds = [...lobby.rooms.keys()];
  for (const id of roomIds) {
    const room = lobby.getRoom(id);
    if (!room) continue;
    if (room.game && room.game.state !== 'round_end') continue;
    try { await maybeMigrateRoom(id); } catch (err) {
      console.error(`[${INSTANCE_NAME}] drain migrate ${id}:`, err);
    }
  }

  // Lobby users (no roomId) are easiest — just close, they'll reconnect
  // to the peer fresh.
  for (const ws of wss.clients) {
    if (!ws.roomId) {
      try { ws.close(1001); } catch (_) { /* ignore */ }
    }
  }

  // Re-arm turn timers that are already ticking. startTurnTimer leaves a live
  // timer alone, so a clock started before this moment keeps its full length —
  // and the absent-player fast lane would only kick in from the NEXT turn.
  // Measured cost of not doing this: the first turn after SIGTERM ran the full
  // 40s+ while everyone waited on a player who had already moved to the peer.
  for (const [roomId, room] of lobby.rooms) {
    if (!room || !room.game) continue;
    const actor = typeof room.game.getPendingActor === 'function'
      ? room.game.getPendingActor()
      : room.game.currentPlayer;
    if (!isAbsentDuringDrain(room, actor)) continue;
    clearTurnTimer(roomId);
    startTurnTimer(roomId);
  }

  console.log(`[${INSTANCE_NAME}] drain initial pass complete; waiting for in-game rooms to reach a round boundary`);

  // Tell the peer who belongs to the rooms we couldn't hand over yet. Their
  // players are still connected here right now, but any one of them who drops
  // from this point lands over there — and without this notice the peer has no
  // way to know their match still exists.
  await notifyPeerOfPendingRooms();

  // Poll for full drain — when no rooms remain (every in-game room has
  // hit a round boundary and migrated), exit. Otherwise we'd sit on the
  // empty process until docker's stop_grace_period hits SIGKILL, which
  // makes idle deploys feel slow.
  //
  // The sweep is a backstop: the round_end handler migrates rooms as
  // soon as they get there. This catches rooms that reached a boundary
  // through some other path (a game abandoned, a player leaving).
  let sweeping = false;
  const drainPoll = setInterval(async () => {
    if (!sweeping) {
      sweeping = true;
      try {
        for (const id of [...lobby.rooms.keys()]) {
          const room = lobby.getRoom(id);
          if (!room) continue;
          if (room.game && room.game.state !== 'round_end') continue;
          try { await maybeMigrateRoom(id); } catch (err) {
            console.error(`[${INSTANCE_NAME}] drain sweep ${id}:`, err);
          }
        }
      } finally {
        sweeping = false;
      }
    }
    if (lobby.rooms.size === 0) {
      clearInterval(drainPoll);
      console.log(`[${INSTANCE_NAME}] drain complete — closing server and exiting`);
      try {
        server.close();
        wss.close();
      } catch (_) { /* ignore */ }
      // Force exit shortly after — server.close() can hang on lingering
      // sockets even after we've closed individual WS connections.
      setTimeout(() => process.exit(0), 1000);
    }
  }, 2000);
});

// Season cycle check every hour
setInterval(() => {
  ensureSeasonCycle();
}, 60 * 60 * 1000);

// Google has no consumable-refund webhook without Pub/Sub, so we poll the
// Voided Purchases API every 30 min (idempotent; overlapping windows are
// safe). Apple pushes its refunds to /iap/apple/notifications instead.
// Auto-disables when the Play service account isn't configured.
const GOOGLE_VOIDED_POLL_MS = 30 * 60 * 1000;
const GOOGLE_VOIDED_CURSOR_KEY = 'iap_gvoid_cursor_ms';
// Google's voidedpurchases endpoint can take up to ~24h to surface a refund
// after it actually happens at the user's end. The poll filters by
// voidedTimeMillis >= startTime — so if the cursor's startTime advances past
// the void's voidedTime before Google indexes it, that refund is missed
// forever. A 1h overlap was too tight in practice. 48h gives Google plenty
// of breathing room; reprocessing is free because autoRefundByTransaction
// is idempotent on transaction_id (already-refunded receipts short-circuit).
const GOOGLE_VOIDED_OVERLAP_MS = 48 * 60 * 60 * 1000; // re-scan 48h before cursor
async function runGoogleVoidedPoll() {
  try {
    // Resume from the persisted cursor so a long outage doesn't drop voids
    // that happened while we were down (idempotent, overlap is safe).
    const raw = await getConfig(GOOGLE_VOIDED_CURSOR_KEY);
    const cursor = raw ? parseInt(raw, 10) : NaN;
    const startTimeMs = Number.isFinite(cursor)
      ? cursor - GOOGLE_VOIDED_OVERLAP_MS
      : null;
    const r = await pollGoogleVoidedPurchases(
      (args) => autoRefundByTransaction({ ...args, onRefunded: notifyAdminRefund }),
      { startTimeMs },
    );
    if (r && r.ok) {
      if (r.processed > 0) console.log(`[GoogleVoided] processed ${r.processed} voided purchase(s)`);
      if (r.pollStartedAt) {
        await updateConfig(GOOGLE_VOIDED_CURSOR_KEY, String(r.pollStartedAt));
      }
    } else if (r && r.reason !== 'not_configured') {
      // Do NOT advance the cursor on failure → next run retries the gap.
      console.warn('[GoogleVoided] poll not ok:', r.reason);
    }
  } catch (e) {
    console.error('[GoogleVoided] poll threw:', e);
  }
}
setInterval(runGoogleVoidedPoll, GOOGLE_VOIDED_POLL_MS);
// First run shortly after boot (let env/DB settle).
setTimeout(runGoogleVoidedPoll, 60 * 1000);

/**
 * Failed-login throttle.
 *
 * bcrypt makes a single guess slow, but nothing stopped a client from opening a
 * socket and trying passwords in a loop — the cost of that loop is paid by the
 * server's event loop, not the attacker's. Counted per account AND per IP so
 * neither "one account, many sources" nor "one source, many accounts" walks
 * through.
 *
 * In memory: a restart clears it, which is the same window an attacker gets by
 * waiting, and there is nothing here worth a table.
 */
const LOGIN_WINDOW_MS = 15 * 60 * 1000;
const LOGIN_MAX_FAILS = 10;   // per account within the window
// Per source address. Deliberately loose: Korean carriers put large numbers of
// mobile users behind one public address (CGNAT), so a strict IP limit locks
// out strangers who share a NAT with one person fumbling their password. The
// per-account limit is the one doing the real work here.
const LOGIN_MAX_FAILS_IP = 100;
const loginFails = new Map(); // key -> { count, first, until }

function loginThrottleKey(kind, value) {
  return `${kind}:${String(value || '').toLowerCase()}`;
}

function loginBlockedFor(keys) {
  const now = Date.now();
  for (const key of keys) {
    const rec = loginFails.get(key);
    if (rec && rec.until && rec.until > now) {
      return Math.ceil((rec.until - now) / 1000);
    }
  }
  return 0;
}

function noteLoginFailure(keys, limits) {
  const now = Date.now();
  keys.forEach((key, i) => {
    const rec = loginFails.get(key);
    if (!rec || now - rec.first > LOGIN_WINDOW_MS) {
      loginFails.set(key, { count: 1, first: now, until: 0 });
      return;
    }
    rec.count += 1;
    if (rec.count >= limits[i]) {
      rec.until = now + LOGIN_WINDOW_MS;
      rec.count = 0;
      rec.first = now;
      console.warn(`[login] throttled ${key} for ${LOGIN_WINDOW_MS / 60000}m`);
    }
  });
}

function clearLoginFailures(keys) {
  for (const key of keys) loginFails.delete(key);
}

// Cheap sweep: the map only grows from failures, but a long-lived server with
// a lot of typos would still accumulate.
setInterval(() => {
  const now = Date.now();
  for (const [key, rec] of loginFails) {
    if (now - rec.first > LOGIN_WINDOW_MS && (!rec.until || rec.until < now)) {
      loginFails.delete(key);
    }
  }
}, LOGIN_WINDOW_MS).unref();

/**
 * Per-connection message budget.
 *
 * maxPayload caps how BIG a message is; nothing capped how MANY. A single
 * client looping sends is enough to keep the handler queue busy for everyone,
 * because every message runs through the same per-socket promise chain.
 *
 * The ceiling is far above real play (a hand of cards is a handful of messages
 * a second, and 'ping' never reaches here) — it exists to stop a loop, not to
 * pace a player. Over the burst limit the message is dropped; a client that
 * keeps flooding after that gets closed.
 */
const MSG_WINDOW_MS = 1000;
const MSG_PER_WINDOW = 40;
const MSG_DROPS_BEFORE_CLOSE = 200; // dropped in a row, i.e. still looping

function messageAllowed(ws) {
  const now = Date.now();
  if (!ws._msgWindowStart || now - ws._msgWindowStart >= MSG_WINDOW_MS) {
    // A window that stayed under the limit ends the streak: bursts happen
    // (rejoining a room repaints a lot), sustained flooding does not.
    if ((ws._msgCount || 0) <= MSG_PER_WINDOW) ws._msgDrops = 0;
    ws._msgWindowStart = now;
    ws._msgCount = 0;
  }
  ws._msgCount += 1;
  if (ws._msgCount <= MSG_PER_WINDOW) return true;

  ws._msgDrops = (ws._msgDrops || 0) + 1;
  if (ws._msgDrops === 1) {
    console.warn(
      `[flood] ${ws.nickname || 'anon'} ${ws.clientIp || '?'} over ${MSG_PER_WINDOW}/s`,
    );
  }
  if (ws._msgDrops >= MSG_DROPS_BEFORE_CLOSE) {
    console.warn(`[flood] closing ${ws.nickname || 'anon'} ${ws.clientIp || '?'}`);
    try { ws.close(1008, 'rate limit'); } catch { /* already going */ }
  }
  return false;
}

wss.on('connection', (ws, req) => {
  ws.playerId = null;
  ws.nickname = null;
  ws.roomId = null;
  ws.clientIp = req.headers['x-forwarded-for']?.split(',')[0]?.trim()
    || req.socket.remoteAddress || null;

  // Heartbeat: mark alive initially, refresh on pong
  ws.isAlive = true;
  ws.missedHeartbeats = 0;
  ws.on('pong', () => {
    ws.isAlive = true;
    ws.missedHeartbeats = 0;
  });

  logVerboseConnection('New connection established');

  ws._messageQueue = Promise.resolve();
  ws.on('message', (raw) => {
    let data;
    try {
      data = JSON.parse(raw.toString());
    } catch (e) {
      sendTo(ws, { type: 'error', message: t(ws.locale, 'invalid_data') });
      return;
    }

    if (!messageAllowed(ws)) return;

    // Heartbeat ping: answer immediately, BEFORE the per-client handler queue.
    // A slow in-flight handler (e.g. DB work) must not delay the pong, or the
    // client's ~15s liveness check could falsely declare the socket dead and
    // trigger an unnecessary reconnect. This is also proof-of-life for the
    // server's own zombie sweep.
    if (data && data.type === 'ping') {
      ws.isAlive = true;
      ws.missedHeartbeats = 0;
      sendTo(ws, { type: 'pong' });
      return;
    }

    // Queue messages per-client to prevent async handler interleaving
    ws._messageQueue = ws._messageQueue.then(() => handleMessage(ws, data)).catch(err => {
      console.error('Message handler error:', err);
    });
  });

  ws.on('close', () => {
    logVerboseConnection(`Player disconnected: ${ws.nickname} (${ws.playerId})`);
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
          // Dropping out mid-drain: whatever clock is running for them was
          // sized for a player who could still act. Drop it so the re-arm
          // below picks the absent-player length instead of making the table
          // wait out a full turn for someone now on the peer.
          if (isDraining) clearTurnTimer(ws.roomId);
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
          // ...except in a room waiting to resume a migrated match. Those
          // seats belong to the match, not to the lobby: dropping one makes
          // the carried standings fail their roster check and the match
          // restarts from zero (and with a single human, removePlayer takes
          // the whole room with it). Someone who reconnects and drops again
          // during the resume window must keep their seat. If nobody ever
          // comes back, the 30-minute abandoned-room sweep still collects it.
          if (!isMigratedResumeRoom(room)) {
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

// Actions that change what a room looks like. While draining, this instance's
// rooms are snapshots in flight to the peer — possibly already adopted there,
// with only our response lost. Any mutation after that makes our copy diverge
// from the peer's, and the retry is then refused on fingerprint mismatch,
// leaving the room stuck here until SIGKILL. Freeze them; every one of these
// works normally once the room lands on the peer seconds later.
//
// Deliberately NOT frozen: leave_room / leave_game (never trap someone in a
// room), chat, and the in-round play actions — a round already in progress
// has to be able to finish, since that boundary is what triggers migration.
const DRAIN_FROZEN_ACTIONS = new Set([
  'create_room', 'join_room', 'join_room_by_invite',
  'change_room_name', 'toggle_ready', 'change_team', 'kick_player',
  'add_bot', 'block_slot', 'unblock_slot', 'set_random_seating',
  'switch_to_spectator', 'switch_to_player',
  // Taking a seat here while the room is about to move to the peer would
  // strand the joiner. Leaving is not frozen — leave_room/leave_game already
  // carry the walk-out, and those must never trap someone in a room.
  'set_mid_game_join', 'join_in_progress',
  'start_game', 'next_round',
]);

// Rooms adopted from a draining peer at a round boundary are briefly parked
// in the lobby with matchProgress until auto-resume fires. They look like
// normal waiting rooms, but changing the roster/seats would make the carried
// standings unusable. Freeze only those room-shape edits; start_game is left
// open because it consumes matchProgress and resumes the match immediately.
const MIGRATED_RESUME_FROZEN_ACTIONS = new Set([
  'join_room', 'join_room_by_invite',
  'change_room_name', 'toggle_ready', 'change_team', 'kick_player',
  'add_bot', 'block_slot', 'unblock_slot', 'set_random_seating',
  'switch_to_spectator', 'switch_to_player',
  'set_mid_game_join', 'join_in_progress',
]);

function isMigratedResumeRoom(room) {
  return !!room && !room.game && !!room.matchProgress;
}

async function handleMessage(ws, data) {
  if (isDraining && DRAIN_FROZEN_ACTIONS.has(data.type)) {
    // Breaking into a match gets its own wording. The generic notice reads as
    // "the server is going away", which is the wrong thing to tell someone
    // sitting in a running game — the match is fine and lands on the peer at
    // the next round boundary, so what they need to know is to try again then.
    sendTo(ws, {
      type: 'error',
      message: t(
        ws.locale,
        data.type === 'join_in_progress'
          ? 'midjoin_wait_for_next_round'
          : 'server_restarting',
      ),
    });
    return;
  }
  // Leaving frees the seat (removePlayer), which fails the roster check at
  // resume and restarts the match from zero — so it waits too, but only until
  // the match picks back up (auto-resume fires within 60s of the first player
  // returning). After that it is a normal in-game leave/desertion again.
  // Spectators aren't in the roster, so they're free to go.
  if ((data.type === 'leave_room' || data.type === 'leave_game') && ws.roomId && !ws.isSpectator) {
    const room = lobby.getRoom(ws.roomId);
    if (isMigratedResumeRoom(room)) {
      sendTo(ws, { type: 'error', message: t(ws.locale, 'room_resuming_match') });
      return;
    }
  }
  if (MIGRATED_RESUME_FROZEN_ACTIONS.has(data.type) && ws.roomId) {
    const room = lobby.getRoom(ws.roomId);
    if (isMigratedResumeRoom(room)) {
      // Not "the server is restarting" — that was the OTHER instance, and it
      // is already gone. From here it is just a room about to pick its match
      // back up, which is what the player should be told.
      sendTo(ws, { type: 'error', message: t(ws.locale, 'room_resuming_match') });
      return;
    }
  }
  // Leaving is kept out of the frozen set above so nobody is ever trapped in a
  // room — but not while the room IS the snapshot in flight. Waiting, or
  // parked at a round boundary, is exactly when the peer may already hold a
  // copy: leaving now changes ours after the fact, the retry can't reconcile,
  // and this player can reconnect onto the peer's copy while the others are
  // still here — a split room. Mid-round leaving stays open (that room isn't
  // migratable yet, and desertion has to keep working), and the block lasts
  // only until the room hands off, normally seconds.
  //
  // Only when there is actually a peer to hand off to. Without one there is no
  // second copy to diverge from — maybeMigrateRoom just closes the sockets and
  // drops the room — so blocking would trap people for nothing.
  if (isDraining && PEER_URL && INTERNAL_MIGRATE_TOKEN
      && (data.type === 'leave_room' || data.type === 'leave_game') && ws.roomId && !ws.isSpectator) {
    const room = lobby.getRoom(ws.roomId);
    if (room && (!room.game || room.game.state === 'round_end')) {
      sendTo(ws, { type: 'error', message: t(ws.locale, 'server_restarting') });
      return;
    }
  }
  switch (data.type) {
    // NOTE: 'ping' is handled earlier in ws.on('message'), before this queue,
    // so the pong is never delayed by a slow in-flight handler. It never
    // reaches this switch.
    case 'register':
      await handleRegister(ws, data);
      break;
    case 'login':
      await handleLogin(ws, data);
      break;
    case 'request_upload_token':
      await handleRequestUploadToken(ws);
      break;
    case 'delete_profile_photo':
      await handleDeleteProfilePhoto(ws);
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
    case 'set_random_seating':
      handleSetRandomSeating(ws, data);
      break;
    case 'switch_to_spectator':
      handleSwitchToSpectator(ws);
      break;
    case 'switch_to_player':
      handleSwitchToPlayer(ws, data);
      break;
    case 'set_mid_game_join':
      handleSetMidGameJoin(ws, data);
      break;
    case 'join_in_progress':
      handleJoinInProgress(ws);
      break;
    case 'get_profile':
      await handleGetProfile(ws, data);
      break;
    case 'get_match_history':
      await handleGetMatchHistory(ws, data);
      break;
    case 'set_profile_private_photo':
      await handleSetProfilePrivatePhoto(ws, data);
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
    case 'declare_kill':
    case 'declare_setting':
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
    case 'set_card_view_pref':
      handleSetCardViewPref(ws, data);
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
    case 'get_gold_products':
      await handleGetGoldProducts(ws, data);
      break;
    case 'verify_iap_purchase':
      await handleVerifyIapPurchase(ws, data);
      break;
    case 'get_bank_deposit_info':
      await handleGetBankDepositInfo(ws);
      break;
    case 'request_bank_deposit':
      await handleRequestBankDeposit(ws, data);
      break;
    case 'get_attendance_state':
      await handleGetAttendanceState(ws);
      break;
    case 'claim_attendance':
      await handleClaimAttendance(ws);
      break;
    case 'get_shop_items':
      await handleGetShopItems(ws);
      break;
    case 'get_visual_catalog':
      await handleGetVisualCatalog(ws);
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
    case 'unequip_item':
      await handleUnequipItem(ws, data);
      break;
    case 'set_custom_title':
      await handleSetCustomTitle(ws, data);
      break;
    case 'set_feature_enabled':
      await handleSetFeatureEnabled(ws, data);
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
        if (ws.isAdmin === true && (data.inquiryAlert != null || data.reportAlert != null || data.paymentAlert != null)) {
          const alertResult = await setAdminAlertSettings(
            ws.nickname,
            data.inquiryAlert != null ? data.inquiryAlert === true : ws.pushAdminInquiry !== false,
            data.reportAlert != null ? data.reportAlert === true : ws.pushAdminReport !== false,
            data.paymentAlert != null ? data.paymentAlert === true : ws.pushAdminPayment !== false,
          );
          if (alertResult.success) {
            ws.pushAdminInquiry = alertResult.settings.pushAdminInquiry === true;
            ws.pushAdminReport = alertResult.settings.pushAdminReport === true;
            ws.pushAdminPayment = alertResult.settings.pushAdminPayment === true;
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
    case 'get_admin_today_matches':
      await handleGetAdminTodayMatches(ws, data);
      break;
    case 'get_admin_today_payments':
      await handleGetAdminTodayPayments(ws, data);
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
      await handleGetAppConfig(ws, data);
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

async function handleGetAppConfig(ws, data = {}) {
  try {
    // EULA/privacy are fetched on first launch, BEFORE the client has logged
    // in, so ws.locale isn't set yet. Accept an explicit locale on the
    // request so the device's UI language still picks the right version;
    // ws.locale takes over once it's known (re-fetches from settings).
    const allowed = new Set(['ko', 'en', 'de']);
    const reqLocale = typeof data.locale === 'string' && allowed.has(data.locale)
      ? data.locale : null;
    const effectiveLocale = reqLocale || ws.locale || null;
    const eulaContent = await getLocalizedConfig('eula_content', effectiveLocale);
    const privacyPolicy = await getLocalizedConfig('privacy_policy', effectiveLocale);
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
  // The row is gone, which means the object key is gone with it — delete the
  // image now or it stays in the bucket, publicly readable, after the person
  // asked to be erased. Best effort: a storage hiccup must not fail the
  // deletion the user already asked for and the DB already committed.
  if (result.success && result.photoKey) {
    await deletePhotoObjectUnlessReported(result.photoKey);
  }
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

// Boot any other socket already logged in under this nickname. Extracted
// because the plain-login and social-login flows both need it and had drifted:
// the resume-room guard below was added to one copy and not the other, so a
// social login still freed the seat of a match waiting to resume.
function disconnectDuplicateLogins(ws, nickname) {
  for (const client of wss.clients) {
    if (client === ws || client.nickname !== nickname || client.readyState !== client.OPEN) continue;
    // Preemptively store session before close (close handler is async)
    if (client.roomId) {
      const oldRoom = lobby.getRoom(client.roomId);
      if (client.isSpectator && oldRoom) {
        oldRoom.removeSpectator(client.playerId);
        if (oldRoom.game) _broadcastState(client.roomId, oldRoom);
        broadcastRoomState(client.roomId);
        broadcastRoomList();
      } else if (oldRoom && (oldRoom.game || isMigratedResumeRoom(oldRoom))) {
        // In a game, or in a room whose seats belong to a match waiting to
        // resume: hold the seat and keep the session. Freeing it would fail
        // the roster check at resume and restart the match from zero — and
        // this path runs on an ordinary duplicate login, i.e. someone simply
        // reopening the app.
        oldRoom.markPlayerDisconnected(client.playerId);
        playerSessions.set(client.nickname, {
          roomId: client.roomId,
          disconnectedAt: Date.now(),
        });
        broadcastRoomState(client.roomId);
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

async function handleLogin(ws, data) {
  const { username, password } = data;
  // Extract locale early so maintenance message is localized
  const earlyLocale = (data.deviceInfo && data.deviceInfo.locale) || ws.locale || null;
  ws.locale = earlyLocale;

  const throttleKeys = [
    loginThrottleKey('user', username),
    loginThrottleKey('ip', ws.clientIp),
  ];
  const blockedFor = loginBlockedFor(throttleKeys);
  if (blockedFor > 0) {
    sendTo(ws, {
      type: 'login_error',
      message: t(ws.locale, 'login_throttled'),
      retryAfter: blockedFor,
    });
    return;
  }

  const result = await loginUser(username, password);

  if (!result.success) {
    noteLoginFailure(throttleKeys, [LOGIN_MAX_FAILS, LOGIN_MAX_FAILS_IP]);
    sendTo(ws, { type: 'login_error', message: resultMessage(result, ws.locale) });
    return;
  }
  // A correct password clears the account's counter, so a user who finally
  // remembers their password is not still serving out a lockout.
  clearLoginFailures([throttleKeys[0]]);

  // Block login during maintenance
  const mStatus = getMaintenanceStatus(ws.locale);
  if (mStatus.maintenance) {
    sendTo(ws, { type: 'login_error', message: mStatus.message || t(ws.locale, 'maintenance'), reason: 'maintenance' });
    return;
  }

  // S3: Disconnect existing connection with same nickname to prevent duplicate login
  disconnectDuplicateLogins(ws, result.nickname);

  ws.playerId = `player_${nextPlayerId++}`;
  ws.nickname = result.nickname;
  ws.userId = result.userId;
  ws.isAdmin = result.isAdmin === true;
  ws.pushEnabled = result.pushEnabled !== false;
  ws.pushFriendInvite = result.pushFriendInvite !== false;
  ws.pushAdminInquiry = result.pushAdminInquiry !== false;
  ws.pushAdminReport = result.pushAdminReport !== false;
  ws.pushAdminPayment = result.pushAdminPayment !== false;
  const deviceInfo = data.deviceInfo || {};
  ws.appVersion = deviceInfo.appVersion || null;
  ws.locale = deviceInfo.locale || null;
  // Kept on the socket, not just written to the row: the backstage online list
  // reads live sockets, and the stored column is whatever the account last
  // logged in from — which is the wrong answer when someone is on two devices.
  ws.devicePlatform = deviceInfo.devicePlatform || null;
  logVerboseConnection(`Player logged in: ${ws.nickname} (${ws.playerId})`);

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
      disconnectDuplicateLogins(ws, result.nickname);

      ws.playerId = `player_${nextPlayerId++}`;
      ws.nickname = result.nickname;
      ws.userId = result.userId;
      ws.isAdmin = result.isAdmin === true;
      ws.pushEnabled = result.pushEnabled !== false;
      ws.pushFriendInvite = result.pushFriendInvite !== false;
      ws.pushAdminInquiry = result.pushAdminInquiry !== false;
      ws.pushAdminReport = result.pushAdminReport !== false;
      ws.pushAdminPayment = result.pushAdminPayment !== false;
      const socialDeviceInfo = data.deviceInfo || {};
      ws.appVersion = socialDeviceInfo.appVersion || null;
      ws.locale = socialDeviceInfo.locale || null;
      ws.devicePlatform = socialDeviceInfo.devicePlatform || null;
      logVerboseConnection(`Player logged in (social/${provider}): ${ws.nickname} (${ws.playerId})`);

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
    ws.pushAdminPayment = true;
    const regDeviceInfo = data.deviceInfo || {};
    ws.appVersion = regDeviceInfo.appVersion || null;
    ws.locale = regDeviceInfo.locale || null;
    ws.devicePlatform = regDeviceInfo.devicePlatform || null;
    logVerboseConnection(`Player registered & logged in (social/${provider}): ${ws.nickname} (${ws.playerId})`);

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
  // Fetch user profile to get equipped theme and title (locale-aware so
  // the self-view of the equipped title matches the app language).
  const profile = await getUserProfile(ws.nickname, ws.locale || 'ko');
  const themeKey = profile?.themeKey || null;
  const titleKey = profile?.titleKey || null;
  const titleName = profile?.titleName || null;
  const bannerKey = profile?.bannerKey || null;
  const hasTopCardCounter = profile?.hasTopCardCounter || false;
  const hasMightyTrumpCounter = profile?.hasMightyTrumpCounter || false;
  const hasMightyPrevTrick = profile?.hasMightyPrevTrick || false;
  // Immutable account-binding token: derived from the unchanging tc_users.id
  // (ws.userId), NOT the mutable nickname. The client stamps this onto every
  // IAP so a receipt redeemed on a different account is detectable, and it
  // stays stable across renames and sessions (so P1-1 cross-session
  // reconciliation never false-mismatches). null only if somehow unauthed.
  const bindingToken = ws.userId != null ? bindingUuid(String(ws.userId)) : null;
  ws.titleKey = titleKey;
  ws.titleName = titleName;
  ws.bannerKey = bannerKey;
  // Public avatar URL, only while the paid photo is active + unexpired. Null
  // falls the client back to the default avatar. The object itself is publicly
  // fetchable, so per-viewer block filtering is done client-side (except the
  // profile popup, which the server already filters by isBlocked).
  ws.photoUrl = profilePhotoUrlFrom(profile);
  // Whose photos this viewer must never be shown: anyone they blocked, plus
  // anyone they reported. Held per connection so the room/game broadcasts can
  // filter without a query each time; kept current by the block/report
  // handlers. A report has to take effect the moment it is filed — leaving the
  // image on screen while the report sits in a queue is the whole complaint.
  ws.hiddenPhotos = new Set(
    await getBlockedUsers(ws.nickname).catch(() => []),
  );
  // Reports hide by PHOTO, not by person: the report was about a specific
  // image, so a replacement photo shows again. The keys were snapshotted into
  // the report rows when they were filed.
  ws.reportedPhotoKeys = new Set(
    await getReportedPhotoKeys(ws.nickname).catch(() => []),
  );
  // Same rule for user-written titles: the report was about that text.
  ws.reportedTitles = new Set(
    await getReportedTitles(ws.nickname).catch(() => []),
  );
  // Friends see past a privacy pass, so the check has to be answerable without
  // a query in the broadcast path. Kept current by the friend accept/remove
  // handlers on both sides.
  ws.friends = new Set(await getFriends(ws.nickname).catch(() => []));
  setProfilePrivacyCache(ws.nickname, {
    active: profile?.hasProfilePrivate === true,
    expiresAt: profile?.profilePrivateExpiresAt || null,
    hidePhoto: profile?.profilePrivateHidePhoto === true,
  });
  ws.level = (profile && Number.isFinite(profile.level)) ? profile.level : 1;
  ws.seasonRating = Number.isFinite(profile?.seasonRating) ? profile.seasonRating : null;
  ws.skSeasonRating = Number.isFinite(profile?.skSeasonRating) ? profile.skSeasonRating : null;
  ws.mightySeasonRating = Number.isFinite(profile?.mightySeasonRating) ? profile.mightySeasonRating : null;
  ws.cardViewPref = (profile?.cardViewPref) || 'ask';

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
          bindingToken,
          // The client keeps its own copy of this so a fresh upload shows before
          // the profile payload catches up, and seeds it from here — except this
          // field was never sent, so a player who already had a photo saw the
          // default avatar in their own profile popup while every other screen
          // showed the photo.
          photoUrl: ws.photoUrl || null,
          themeKey,
          titleKey,
          hasTopCardCounter,
          hasMightyTrumpCounter,
          hasMightyPrevTrick,
          authProvider,
          isAdmin: ws.isAdmin === true,
          pushEnabled: ws.pushEnabled !== false,
          pushFriendInvite: ws.pushFriendInvite !== false,
          pushAdminInquiry: ws.pushAdminInquiry !== false,
          pushAdminReport: ws.pushAdminReport !== false,
          pushAdminPayment: ws.pushAdminPayment !== false,
          maintenanceStatus: getMaintenanceStatus(ws.locale),
          cardViewPref: ws.cardViewPref || 'ask',
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
        logVerboseConnection(`Player ${ws.nickname} reconnected to room ${room.name}`);

        sendTo(ws, {
          type: 'login_success',
          playerId: ws.playerId,
          nickname: ws.nickname,
          bindingToken,
          photoUrl: ws.photoUrl || null,
          themeKey,
          titleKey,
          hasTopCardCounter,
          hasMightyTrumpCounter,
          hasMightyPrevTrick,
          authProvider,
          isAdmin: ws.isAdmin === true,
          pushEnabled: ws.pushEnabled !== false,
          pushFriendInvite: ws.pushFriendInvite !== false,
          pushAdminInquiry: ws.pushAdminInquiry !== false,
          pushAdminReport: ws.pushAdminReport !== false,
          pushAdminPayment: ws.pushAdminPayment !== false,
          maintenanceStatus: getMaintenanceStatus(ws.locale),
          cardViewPref: ws.cardViewPref || 'ask',
        });
        sendTo(ws, {
          type: 'reconnected',
          roomId: room.id,
          roomName: room.name,
        });

        // Reconnecting remaps the player's id (updatePlayerId), so a turn timer
        // armed for the OLD id is now stale. startTurnTimer won't replace a live
        // timer (`if (turnTimers[roomId]) return`), so without clearing it here
        // the stale timer keeps firing for the pre-reconnect id — its auto-play
        // no-ops (id != currentPlayer) while the timeout count climbs, deserting
        // the just-returned player. Clear it so sendGameStateToAll re-arms fresh
        // for the remapped current player.
        // Carry the remaining time across the re-arm. Clearing drops the
        // deadline, and startTurnTimer would then hand out a full fresh turn —
        // so backgrounding the app and coming back reset the clock, and doing
        // it repeatedly meant never having to move.
        const carriedDeadline = room.turnDeadline;
        clearTurnTimer(room.id);
        // Re-arm and fix the deadline BEFORE broadcasting. sendGameStateToAll
        // arms the timer itself, so restoring afterwards left the server right
        // and every client wrong — they had already been handed the fresh
        // deadline and nothing sent them another.
        startTurnTimer(room.id);
        restoreTurnDeadline(room.id, carriedDeadline);
        // Send current room and game state
        broadcastRoomState(room.id);
        sendGameStateToAll(room.id);
        broadcastRoomList();
        // If this room came over from a draining peer mid-match, the player
        // who just landed may be the one it was waiting on.
        maybeAutoResumeMatch(room.id);
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
          bindingToken,
          photoUrl: ws.photoUrl || null,
          themeKey,
          titleKey,
          hasTopCardCounter,
          hasMightyTrumpCounter,
          hasMightyPrevTrick,
          authProvider,
          isAdmin: ws.isAdmin === true,
          pushEnabled: ws.pushEnabled !== false,
          pushFriendInvite: ws.pushFriendInvite !== false,
          pushAdminInquiry: ws.pushAdminInquiry !== false,
          pushAdminReport: ws.pushAdminReport !== false,
          pushAdminPayment: ws.pushAdminPayment !== false,
          maintenanceStatus: getMaintenanceStatus(ws.locale),
          cardViewPref: ws.cardViewPref || 'ask',
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
        logVerboseConnection(`Spectator ${ws.nickname} reconnected to room ${room.name}`);

        sendTo(ws, {
          type: 'login_success',
          playerId: ws.playerId,
          nickname: ws.nickname,
          bindingToken,
          photoUrl: ws.photoUrl || null,
          themeKey,
          titleKey,
          hasTopCardCounter,
          hasMightyTrumpCounter,
          hasMightyPrevTrick,
          authProvider,
          isAdmin: ws.isAdmin === true,
          pushEnabled: ws.pushEnabled !== false,
          pushFriendInvite: ws.pushFriendInvite !== false,
          pushAdminInquiry: ws.pushAdminInquiry !== false,
          pushAdminReport: ws.pushAdminReport !== false,
          pushAdminPayment: ws.pushAdminPayment !== false,
          maintenanceStatus: getMaintenanceStatus(ws.locale),
          cardViewPref: ws.cardViewPref || 'ask',
        });
        sendTo(ws, {
          type: 'spectate_joined',
          roomId: room.id,
          roomName: room.name,
        });
        sendTo(ws, { type: 'chat_history', messages: visibleChatHistory(ws, room) });
        broadcastRoomState(room.id);
        if (room.game) {
          const permittedPlayers = room.getPermittedPlayers(ws.playerId);
          const state = room.game.getStateForSpectator(permittedPlayers);
          sendTo(ws, { type: 'spectator_game_state', state: decorateSpectatorState(room, ws, state) });
        } else {
          sendTo(ws, { type: 'room_state', room: personalizeRoomState(room.getState(), ws) });
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
            bindingToken,
            photoUrl: ws.photoUrl || null,
            themeKey,
            titleKey,
            hasTopCardCounter,
            hasMightyTrumpCounter,
            hasMightyPrevTrick,
            authProvider,
            isAdmin: ws.isAdmin === true,
            pushEnabled: ws.pushEnabled !== false,
            pushFriendInvite: ws.pushFriendInvite !== false,
            pushAdminInquiry: ws.pushAdminInquiry !== false,
            pushAdminReport: ws.pushAdminReport !== false,
            pushAdminPayment: ws.pushAdminPayment !== false,
            maintenanceStatus: getMaintenanceStatus(ws.locale),
            cardViewPref: ws.cardViewPref || 'ask',
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
        // Refresh slot metadata from the freshly loaded profile (ws.*)
        // so peer-adopted waiting rooms self-heal level/banner/rating
        // even if the migration snapshot was missing those fields.
        if (ws.titleKey) {
          player.titleKey = ws.titleKey;
          player.titleName = ws.titleName;
        }
        player.level = ws.level || 1;
        player.bannerKey = ws.bannerKey;
        player.photoUrl = ws.photoUrl || null;
        player.seasonRating = ws.seasonRating;
        player.skSeasonRating = ws.skSeasonRating;
        player.mightySeasonRating = ws.mightySeasonRating;
        if (room.hostId === oldId) {
          room.hostId = ws.playerId;
          room.hostNickname = ws.nickname;
        }
        ws.roomId = room.id;

        sendTo(ws, {
          type: 'login_success',
          playerId: ws.playerId,
          nickname: ws.nickname,
          bindingToken,
          photoUrl: ws.photoUrl || null,
          themeKey,
          titleKey,
          hasTopCardCounter,
          hasMightyTrumpCounter,
          hasMightyPrevTrick,
          authProvider,
          isAdmin: ws.isAdmin === true,
          pushEnabled: ws.pushEnabled !== false,
          pushFriendInvite: ws.pushFriendInvite !== false,
          pushAdminInquiry: ws.pushAdminInquiry !== false,
          pushAdminReport: ws.pushAdminReport !== false,
          pushAdminPayment: ws.pushAdminPayment !== false,
          maintenanceStatus: getMaintenanceStatus(ws.locale),
          cardViewPref: ws.cardViewPref || 'ask',
        });
        sendTo(ws, {
          type: 'room_joined',
          roomId: room.id,
          roomName: room.name,
        });
        notifyLegacyRandomSeatingClient(room, ws);
        broadcastRoomState(room.id);
        broadcastRoomList();
        // A room adopted mid-match has no game object, so its players all
        // come back through this waiting-room path — this is where the
        // auto-resume gets its cue.
        maybeAutoResumeMatch(room.id);
        return;
      }
    }
  }

  sendTo(ws, {
    type: 'login_success',
    playerId: ws.playerId,
    nickname: ws.nickname,
    bindingToken,
    themeKey,
    titleKey,
    hasTopCardCounter,
    hasMightyTrumpCounter,
    hasMightyPrevTrick,
    authProvider,
    isAdmin: ws.isAdmin === true,
    pushEnabled: ws.pushEnabled !== false,
    pushFriendInvite: ws.pushFriendInvite !== false,
    pushAdminInquiry: ws.pushAdminInquiry !== false,
    pushAdminReport: ws.pushAdminReport !== false,
    pushAdminPayment: ws.pushAdminPayment !== false,
    maintenanceStatus: getMaintenanceStatus(ws.locale),
    cardViewPref: ws.cardViewPref || 'ask',
    photoUrl: ws.photoUrl || null,
  });
  sendTo(ws, {
    type: 'room_list',
    rooms: filterRoomsForClient(ws, lobby.getRoomList()),
  });
  // Landing in the lobby, but the draining peer says a match of theirs is
  // still finishing a round over there. Say so — otherwise this looks like
  // the game simply vanished, and the last tester responded by starting a
  // new room. They keep the lobby; we pull them in when the room arrives
  // (attachWaitingMembers).
  const incoming = pendingArrivals.get(ws.nickname);
  if (incoming) {
    sendTo(ws, { type: 'match_incoming', roomName: incoming.roomName || '' });
  }
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
  // Cap to 20 chars, matching handleChangeRoomName — an uncapped name (bounded
  // only by maxPayload) would be re-broadcast to every lobby client.
  const roomName = (data.roomName || `${ws.nickname}'s Room`).trim().slice(0, 20);
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
    skExpansions,
    data.allowSpectators !== false,
    // Opt-in, and the GameRoom constructor drops it for ranked rooms.
    data.allowMidGameJoin === true
  );
  ws.roomId = room.id;
  // Set title + level + season-rating on host player
  if (ws.titleKey) {
    room.players[0].titleKey = ws.titleKey;
    room.players[0].titleName = ws.titleName;
  }
  room.players[0].level = ws.level || 1;
  room.players[0].bannerKey = ws.bannerKey;
  room.players[0].photoUrl = ws.photoUrl || null;
  room.players[0].seasonRating = ws.seasonRating;
  room.players[0].skSeasonRating = ws.skSeasonRating;
  room.players[0].mightySeasonRating = ws.mightySeasonRating;

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
  if (isMigratedResumeRoom(room)) {
    // Seats here belong to a match that is mid-flight, not to an open lobby
    // room — see MIGRATED_RESUME_FROZEN_ACTIONS.
    sendTo(ws, { type: 'error', message: t(ws.locale, 'room_resuming_match') });
    return;
  }
  // Filler rooms are spectate-only: every seat is taken by design, and letting a
  // real player sit in one would mean playing a match nobody records.
  if (fillerRooms.isFillerRoom(room.id)) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'room_full') });
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
  // Set title + level + season-rating on joined player
  {
    const p = room.players.find(p => p !== null && p.id === ws.playerId);
    if (p) {
      if (ws.titleKey) {
        p.titleKey = ws.titleKey;
        p.titleName = ws.titleName;
      }
      p.level = ws.level || 1;
      p.bannerKey = ws.bannerKey;
      p.photoUrl = ws.photoUrl || null;
      p.seasonRating = ws.seasonRating;
      p.skSeasonRating = ws.skSeasonRating;
      p.mightySeasonRating = ws.mightySeasonRating;
    }
  }
  sendTo(ws, { type: 'room_joined', roomId: room.id, roomName: room.name });
  // 채팅 히스토리 전송
  sendTo(ws, { type: 'chat_history', messages: visibleChatHistory(ws, room) });
  notifyLegacyRandomSeatingClient(room, ws);
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
        releasePeerPending(ws.nickname);
        room.removePlayer(ws.playerId);
        if (room.getHumanPlayerCount() === 0) {
          removeRoomAndNotifySpectators(roomId);
        } else {
          broadcastRoomState(roomId);
        }
      }
    }
  }
  sendTo(ws, { type: 'room_left' });
  broadcastRoomList();

  // During drain we want anyone returning to the lobby (player who left
  // their seat OR spectator who stopped watching) to land on the peer's
  // lobby instead of this dying instance. Close the WS after the
  // room_left frame is queued; the client's reconnect logic re-opens
  // through the LB → peer.
  if (isDraining) {
    setTimeout(() => {
      try { ws.close(1001); } catch (_) { /* ignore */ }
    }, 50);
  }
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
  releasePeerPending(ws.nickname);
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
  autoReturnTimers[roomId] = setTimeout(async () => {
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

    // Drain hook: a room that's been waiting to migrate (game ended after
    // SIGTERM) finally has its waiting-room state back. Hand it off to the
    // peer now and close the players' WS so they end up in the migrated
    // room on the new instance.
    if (isDraining) {
      try {
        await maybeMigrateRoom(roomId);
      } catch (err) {
        console.error(`[${INSTANCE_NAME}] post-game migrate ${roomId}:`, err);
      }
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
  sendTo(ws, { type: 'room_state', room: personalizeRoomState(room.getState(), ws) });
  // S27: Also send game state if game is active
  if (room.game) {
    if (ws.isSpectator) {
      const state = room.game.getStateForSpectator(room.getPermittedPlayers(ws.playerId));
      sendTo(ws, { type: 'spectator_game_state', state: decorateSpectatorState(room, ws, state) });
    } else {
      const state = room.game.getStateForPlayer(ws.playerId);
      sendTo(ws, { type: 'game_state', state: decoratePlayerState(room, ws, state) });
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
  // Host turned spectating off for this room.
  if (room.allowSpectators === false) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'spectators_not_allowed') });
    return;
  }
  // SK version gating for spectators
  if (!clientCanAccessRoom(ws, room)) {
    sendTo(ws, { type: 'error', message: roomAccessUpdateMessage(ws.locale, room, 'spectate') });
    return;
  }
  const password = typeof data.password === 'string' ? data.password.trim() : '';
  const result = room.addSpectator(ws.playerId, ws.nickname, password, ws.photoUrl);
  if (!result.success) {
    sendTo(ws, { type: 'error', message: resultMessage(result, ws.locale) });
    return;
  }
  ws.roomId = room.id;
  ws.isSpectator = true;
  sendTo(ws, { type: 'spectate_joined', roomId: room.id, roomName: room.name });
  // Send chat history to spectator
  sendTo(ws, { type: 'chat_history', messages: visibleChatHistory(ws, room) });
  // Update room state/list for everyone
  broadcastRoomState(room.id);
  broadcastRoomList();

  if (room.game) {
    // Go through the normal broadcast rather than hand-rolling a payload here.
    // The hand-rolled one carried the raw engine state and none of the
    // decoration sendGameStateToAll adds — photoUrl, connected, timeoutCount —
    // so a spectator joining a game in progress saw no profile photos at all
    // until the next full broadcast happened along, which in a slow game can be
    // minutes. Two paths building the same message is how that drift happened;
    // one path is the fix.
    sendGameStateToAll(room.id);
  } else {
    // Send waiting room state
    sendTo(ws, { type: 'room_state', room: personalizeRoomState(room.getState(), ws) });
  }
}

function handleRequestCardView(ws, data) {
  if (!ws.roomId) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'not_spectating') });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room) return;
  // Spectators can always ask. Killed-mighty players act as pseudo-spectators
  // for the rest of the round so they have something to do.
  const isKilledMighty = !ws.isSpectator && room.gameType === 'mighty'
    && room.game && room.game.excludedPlayers
    && room.game.excludedPlayers.has(ws.playerId);
  if (!ws.isSpectator && !isKilledMighty) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'not_spectating') });
    return;
  }

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
      if (isKilledMighty) {
        // Killed-mighty player still receives the normal player state; refresh
        // just them so the newly granted cards appear on the scoreboard.
        const state = room.game.getStateForPlayer(ws.playerId, permittedPlayers);
        sendTo(ws, { type: 'game_state', state: decoratePlayerState(room, ws, state) });
      } else {
        const state = room.game.getStateForSpectator(permittedPlayers);
        sendTo(ws, { type: 'spectator_game_state', state: decorateSpectatorState(room, ws, state) });
      }
    }
    return;
  }

  // Look up the target player's persistent card-view preference. If they
  // have set 'always_allow' or 'always_deny', resolve the request right
  // away without bothering them with a popup.
  const playerWs = findWsByPlayerId(playerId);
  const targetPref = (playerWs && playerWs.cardViewPref) || 'ask';
  if (targetPref === 'always_allow' || targetPref === 'always_deny') {
    const allow = targetPref === 'always_allow';
    room.respondCardViewRequest(playerId, ws.playerId, allow);
    const playerNickname = playerWs ? (playerWs.nickname || '') : '';
    sendTo(ws, {
      type: 'card_view_response',
      playerId,
      playerNickname,
      allowed: allow,
    });
    if (!allow) {
      // Surface the deny explicitly so the spectator knows their request
      // wasn't silently lost — the target has set always-deny.
      sendTo(ws, {
        type: 'error',
        message: t(ws.locale, 'card_view_denied_pref', { name: playerNickname }),
      });
    }
    if (allow && room.game) {
      const permittedPlayers = room.getPermittedPlayers(ws.playerId);
      if (isKilledMighty) {
        const state = room.game.getStateForPlayer(ws.playerId, permittedPlayers);
        sendTo(ws, { type: 'game_state', state: decoratePlayerState(room, ws, state) });
      } else {
        const state = room.game.getStateForSpectator(permittedPlayers);
        sendTo(ws, { type: 'spectator_game_state', state: decorateSpectatorState(room, ws, state) });
      }
    }
    return;
  }

  // 'ask' (default) — notify the human player about the request.
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

async function handleSetCardViewPref(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'login_required') });
    return;
  }
  const pref = (data && data.pref) || 'ask';
  const result = await updateCardViewPref(ws.nickname, pref);
  if (!result.success) {
    sendTo(ws, { type: 'card_view_pref_result', success: false });
    return;
  }
  ws.cardViewPref = result.pref;
  sendTo(ws, { type: 'card_view_pref_result', success: true, pref: result.pref });
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
      // If the requester is a killed-mighty player (not a real spectator),
      // send player-state with their pseudo-spectator permissions merged in.
      const isKilledRequester = room.gameType === 'mighty'
        && room.game.excludedPlayers && room.game.excludedPlayers.has(spectatorId);
      if (isKilledRequester) {
        const state = room.game.getStateForPlayer(spectatorId, permittedPlayers);
        sendTo(spectatorWs, { type: 'game_state', state: decoratePlayerState(room, spectatorWs, state) });
      } else {
        const state = room.game.getStateForSpectator(permittedPlayers);
        sendTo(spectatorWs, { type: 'spectator_game_state', state: decorateSpectatorState(room, spectatorWs, state) });
      }
    }
  }

  // Send updated game state to the approving player so cardViewers refreshes immediately
  if (allow && room.game) {
    const playerState = room.game.getStateForPlayer(ws.playerId);
    sendTo(ws, { type: 'game_state', state: decoratePlayerState(room, ws, playerState) });
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
    sendTo(spectatorWs, { type: 'spectator_game_state', state: decorateSpectatorState(room, spectatorWs, state) });
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
  // (Draining is handled centrally — see DRAIN_FROZEN_ACTIONS.)
  if (room.hostId !== ws.playerId) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'host_only_start') });
    return;
  }
  let mightyWillAutoBlock = false;
  if (room.gameType === 'skull_king' || room.gameType === 'love_letter') {
    if (room.getPlayerCount() < 2) {
      sendTo(ws, { type: 'error', message: t(ws.locale, 'min_players_required') });
      return;
    }
  } else if (room.gameType === 'mighty') {
    // Mighty needs the effective capacity filled (5 or 6 depending on blocked slots).
    // Special-case: a 6-seat room with exactly 5 players and one empty
    // non-blocked slot means the host filled seats for 5p mode without
    // explicitly blocking the extra seat. We'll silently treat it as 5p —
    // but only APPLY the block later, after the readiness check passes, so
    // a failed start doesn't leave the room mutated.
    const have = room.getPlayerCount();
    const effectiveMax = room.getEffectiveMaxPlayers();
    mightyWillAutoBlock = have === 5 && effectiveMax === 6;
    const targetSeats = mightyWillAutoBlock ? 5 : effectiveMax;
    if (have < targetSeats) {
      sendTo(ws, {
        type: 'error',
        message: t(ws.locale, 'mighty_players_required', { count: targetSeats }),
      });
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
  // Apply the deferred mighty auto-block now that every precondition passed.
  // Tag the slot as auto-blocked so resetReady() can release it when the
  // room returns to the waiting state after the game ends.
  let autoBlockedSlot = -1;
  if (mightyWillAutoBlock) {
    for (let i = 0; i < room.maxPlayers; i++) {
      if (room.players[i] === null && !room.blockedSlots.has(i)) {
        room.blockedSlots.add(i);
        room.autoBlockedSlots.add(i);
        autoBlockedSlot = i;
        break;
      }
    }
  }
  const started = room.startGame();
  if (started === false && autoBlockedSlot !== -1) {
    // Defensive: if startGame rejected despite our checks, roll back the
    // auto-block so the room isn't left in a half-mutated state.
    room.blockedSlots.delete(autoBlockedSlot);
    room.autoBlockedSlots.delete(autoBlockedSlot);
  }
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
  const strategy = typeof data.strategy === 'string' ? data.strategy : 'heuristic';
  const result = room.addBot(targetSlot, ws.locale, speed, strategy);
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

function handleSetRandomSeating(ws, data) {
  if (!ws.roomId) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'not_in_room') });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room) { sendTo(ws, { type: 'room_closed' }); ws.roomId = null; return; }
  const enabled = data.enabled === true;
  const result = room.setRandomSeating(ws.playerId, enabled);
  if (!result.success) {
    sendTo(ws, { type: 'error', message: resultMessage(result, ws.locale) });
    return;
  }
  notifyLegacyRandomSeatingParticipants(room, enabled);
  broadcastRoomState(ws.roomId);
  broadcastRoomList();
}

function notifyLegacyRandomSeatingParticipants(room, enabled) {
  const messageKey = enabled ? 'random_seating_enabled_notice' : 'random_seating_disabled_notice';
  for (const player of room.players) {
    if (player === null || room.isBot(player.id)) continue;
    const client = findWsByPlayerId(player.id);
    if (!client || clientSupportsRandomSeating(client)) continue;
    sendTo(client, { type: 'error', message: t(client.locale, messageKey) });
  }
}

function notifyLegacyRandomSeatingClient(room, client, messageKey = 'random_seating_enabled_notice') {
  if (!room || !client || !room.randomSeating || clientSupportsRandomSeating(client)) return;
  sendTo(client, { type: 'error', message: t(client.locale, messageKey) });
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
  // Set title + level + season-rating on player slot
  {
    const p = room.players[targetSlot];
    if (p) {
      if (ws.titleKey) {
        p.titleKey = ws.titleKey;
        p.titleName = ws.titleName;
      }
      p.level = ws.level || 1;
      p.bannerKey = ws.bannerKey;
      p.photoUrl = ws.photoUrl || null;
      p.seasonRating = ws.seasonRating;
      p.skSeasonRating = ws.skSeasonRating;
      p.mightySeasonRating = ws.mightySeasonRating;
    }
  }
  sendTo(ws, { type: 'switched_to_player', roomId: room.id, roomName: room.name });
  notifyLegacyRandomSeatingClient(room, ws);
  broadcastRoomState(ws.roomId);
  broadcastRoomList();
}

/** Host toggling mid-game join for the room. Waiting room only. */
function handleSetMidGameJoin(ws, data) {
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
    sendTo(ws, { type: 'error', message: t(ws.locale, 'midjoin_ranked_blocked') });
    return;
  }
  if (data.enabled === true && room.allowSpectators === false) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'midjoin_needs_spectators') });
    return;
  }
  // Flipping this mid-match would change the rules under people who already
  // sat down — someone counting on being able to walk out could find the exit
  // gone. Waiting room only.
  if (room.game) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'room_no_switch_in_game') });
    return;
  }
  room.allowMidGameJoin = data.enabled === true;
  broadcastRoomState(ws.roomId);
  broadcastRoomList();
}

/**
 * A spectator drops into a live match by taking over a bot's seat.
 *
 * The seat is picked at random among the bot-held ones rather than chosen:
 * letting people pick would mean scouting the table from the spectator view
 * (whose hand is strong, which team is ahead) and then claiming the good seat.
 */
function handleJoinInProgress(ws) {
  if (!ws.roomId || !ws.isSpectator) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'not_spectating') });
    return;
  }
  const room = lobby.getRoom(ws.roomId);
  if (!room) { sendTo(ws, { type: 'room_closed' }); ws.roomId = null; return; }
  if (!room.allowMidGameJoin) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'midjoin_not_allowed') });
    return;
  }
  if (room.isRanked) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'midjoin_ranked_blocked') });
    return;
  }
  if (!clientCanAccessRoom(ws, room)) {
    sendTo(ws, { type: 'error', message: roomAccessUpdateMessage(ws.locale, room, 'join') });
    return;
  }
  // A game that is over, or one being torn down by a desertion, has no seat
  // worth inheriting — and grabbing one mid-teardown would race the result
  // save that handleDesertion already claimed.
  const game = room.game;
  if (!game || game.state === 'game_end' || game.deserted) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'midjoin_no_game') });
    return;
  }
  const cooldownLeft = midGameJoinCooldownLeft(ws.nickname);
  if (cooldownLeft > 0) {
    sendTo(ws, {
      type: 'error',
      message: t(ws.locale, 'midjoin_cooldown', { minutes: Math.ceil(cooldownLeft / 60000) }),
      retryAfterMs: cooldownLeft,
    });
    return;
  }
  const botSlots = room.getBotSeatSlots();
  if (botSlots.length === 0) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'midjoin_no_bot_seat') });
    return;
  }
  const slot = botSlots[Math.floor(Math.random() * botSlots.length)];
  const botId = room.players[slot].id;
  const result = room.takeOverBotSeat(botId, ws.playerId, ws.nickname);
  if (!result.success) {
    sendTo(ws, { type: 'error', message: resultMessage(result, ws.locale) });
    return;
  }

  ws.isSpectator = false;
  // Drop the spectator reconnect pointer; the disconnect handler writes the
  // player one if and when they actually drop. playerSessions is a record of
  // who is *away*, not who is seated — writing it here would have the 30-min
  // sweeper expiring the session of a player sitting at the table.
  spectatorSessions.delete(ws.nickname);
  // Carry the cosmetics the seat should now display, same as switchToPlayer.
  {
    const p = room.players[slot];
    if (p) {
      if (ws.titleKey) {
        p.titleKey = ws.titleKey;
        p.titleName = ws.titleName;
      }
      p.level = ws.level || 1;
      p.bannerKey = ws.bannerKey;
      p.photoUrl = ws.photoUrl || null;
      p.seasonRating = ws.seasonRating;
      p.skSeasonRating = ws.skSeasonRating;
      p.mightySeasonRating = ws.mightySeasonRating;
    }
  }
  // The bot that held this seat may have burned timeouts; the newcomer must
  // not inherit a count that deserts them on their first slow turn.
  if (timeoutCounts[room.id]) delete timeoutCounts[room.id][ws.nickname];
  midGameJoinCooldowns.set(ws.nickname, Date.now() + MID_GAME_JOIN_COOLDOWN_MS);

  sendTo(ws, {
    type: 'joined_in_progress',
    roomId: room.id,
    roomName: room.name,
    slot,
  });
  broadcastGameEvent(room.id, {
    type: 'player_joined_in_progress',
    player: ws.playerId,
    playerName: ws.nickname,
    slot,
    replacedBot: botId,
  });

  // The seat's identity changed, which is exactly what botStateSig keys on —
  // any bot decision already in flight for the old id lands stale and is
  // discarded. Re-derive the schedule and the turn timer from the new roster:
  // if it is this seat's turn, the timer must now be a human clock, and the
  // bot loop must stop treating the seat as its own.
  clearTurnTimer(room.id);
  scheduleBotActions(room.id, true);
  startTurnTimer(room.id);
  sendGameStateToAll(room.id);
  broadcastRoomState(room.id);
  broadcastRoomList();
}

/**
 * Owner switching a feature pass on or off.
 *
 * The days keep running either way — this decides whether the pass applies.
 * The reply carries the recomputed capability flags because that is what the
 * client gates its UI on, and it must not wait for the next login to find out.
 */
async function handleSetFeatureEnabled(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'login_required') });
    return;
  }
  const effectType = data?.effectType?.toString() || '';
  const enabled = data?.enabled === true;
  const result = await setFeatureEnabled(ws.nickname, effectType, enabled);
  if (!result.success) {
    sendTo(ws, {
      type: 'feature_toggle_result',
      success: false,
      message: t(ws.locale, result.messageKey || 'db_update_failed'),
    });
    return;
  }
  const profile = await refreshProfilePrivacy(ws.nickname);
  sendTo(ws, {
    type: 'feature_toggle_result',
    success: true,
    effectType,
    enabled,
    hasTopCardCounter: profile?.hasTopCardCounter === true,
    hasMightyTrumpCounter: profile?.hasMightyTrumpCounter === true,
    hasMightyPrevTrick: profile?.hasMightyPrevTrick === true,
    hasProfilePrivate: profile?.hasProfilePrivate === true,
  });
  // Turning privacy off puts records (and possibly the photo) back in view for
  // everyone in the room, so the seats have to be redrawn.
  if (effectType === 'profile_private' && ws.roomId) {
    broadcastRoomState(ws.roomId);
    if (lobby.getRoom(ws.roomId)?.game) sendGameStateToAll(ws.roomId);
  }
}

/** Re-read one user's privacy state into the broadcast cache. */
async function refreshProfilePrivacy(nickname) {
  if (!nickname) return null;
  const profile = await getUserProfile(nickname, 'ko').catch(() => null);
  setProfilePrivacyCache(nickname, {
    active: profile?.hasProfilePrivate === true,
    expiresAt: profile?.profilePrivateExpiresAt || null,
    hidePhoto: profile?.profilePrivateHidePhoto === true,
  });
  return profile;
}

/**
 * The pass holder choosing how far it reaches: records only (default), or the
 * profile photo as well.
 *
 * Allowed without an active pass — it is a stored preference, and refusing to
 * remember it would mean the setting silently resets every time a pass lapses.
 * It simply has no effect until a pass is active.
 */
async function handleSetProfilePrivatePhoto(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'login_required') });
    return;
  }
  const hide = data?.hide === true;
  const result = await setProfilePrivateHidePhoto(ws.nickname, hide);
  if (!result.success) {
    sendTo(ws, {
      type: 'profile_private_result',
      success: false,
      message: t(ws.locale, result.messageKey || 'db_update_failed'),
    });
    return;
  }
  await refreshProfilePrivacy(ws.nickname);
  sendTo(ws, { type: 'profile_private_result', success: true, hidePhoto: hide });
  // Seats already on screen are showing the old answer: everyone in the room
  // needs a state with the photo added or dropped for this viewer.
  if (ws.roomId) {
    broadcastRoomState(ws.roomId);
    const room = lobby.getRoom(ws.roomId);
    if (room?.game) sendGameStateToAll(ws.roomId);
  }
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
  // Viewer's locale picks the title display name; the inspected user's own
  // locale preference is irrelevant to what the viewer should see.
  const profile = await getUserProfile(targetNickname, ws.locale || 'ko');
  // The synthetic host of an admin filler room has no account, so the lookup
  // finds nothing and the popup would say "프로필을 찾을 수 없습니다" — which
  // reads as a bug on a seat that is sitting right there playing. Answer the way
  // a private account answers.
  if (!profile && fillerRooms.isFillerNickname(targetNickname)) {
    sendTo(ws, {
      type: 'profile_result',
      nickname: targetNickname,
      profile: { nickname: targetNickname, isPrivate: true },
      recentMatches: [],
      isBlocked: false,
    });
    return;
  }
  // The privacy cache is filled at login, so a pass held by someone who has
  // not connected since the last restart was invisible here and their records
  // came through. The row is already loaded — trust it, and warm the cache for
  // the broadcast paths while we are at it.
  if (profile) {
    setProfilePrivacyCache(targetNickname, {
      active: profile.hasProfilePrivate === true,
      expiresAt: profile.profilePrivateExpiresAt || null,
      hidePhoto: profile.profilePrivateHidePhoto === true,
    });
  }
  const isBlocked = (await getBlockedUsers(ws.nickname)).includes(targetNickname);
  // Privacy pass: strangers get the identity (so they can still report, invite
  // or add as friend) and nothing that counts as a record. Redacted HERE rather
  // than left to the client — the numbers must not travel to someone who is not
  // allowed to see them.
  const hidden = profileHiddenFrom(ws, targetNickname);
  if (profile && hidden) {
    // A reported title stays hidden here too — this branch builds its own
    // payload, so the filter the normal path applies has to be repeated.
    const titleHidden = titleReported(ws, targetNickname, profile.titleName);
    const redacted = {
      nickname: profile.nickname,
      isPrivate: true,
      bannerKey: profile.bannerKey,
      titleKey: titleHidden ? null : profile.titleKey,
      titleName: titleHidden ? null : profile.titleName,
      photoUrl: visiblePhoto(ws, targetNickname, profilePhotoUrlFrom(profile)),
    };
    sendTo(ws, {
      type: 'profile_result',
      nickname: targetNickname,
      profile: redacted,
      recentMatches: [],
      isBlocked,
    });
    return;
  }
  const allMatches = await getRecentMatches(targetNickname, 20);
  const recentMatches = clientSupportsMidLeaveHistory(ws)
    ? allMatches
    : allMatches.filter((m) => m.isMidGameLeave !== true);
  // Attach the resolved avatar URL, unless this viewer blocked or reported the
  // target — an image someone has objected to must not be forced back on them.
  if (profile) {
    profile.photoUrl = visiblePhoto(ws, targetNickname, profilePhotoUrlFrom(profile));
    if (titleReported(ws, targetNickname, profile.titleName)) {
      profile.titleName = null;
      profile.titleKey = null;
    }
    // Own popup shows the pass and its reach; friends need neither.
    if (ws.nickname !== targetNickname) {
      delete profile.profilePrivateHidePhoto;
      delete profile.profilePrivateExpiresAt;
    }
  }
  sendTo(ws, {
    type: 'profile_result',
    nickname: targetNickname,
    profile,
    recentMatches,
    isBlocked,
  });
}

// One page of a profile's full match history, for the "더보기" list.
//
// Separate from handleGetProfile because the popup's own list must keep its
// per-game cap — see getRecentMatches — while this one pages a single tab. The
// privacy checks are the same ones, deliberately repeated rather than shared by
// flag: a history endpoint that forgets them leaks exactly what the pass is for.
const MATCH_HISTORY_PAGE_MAX = 50;

async function handleGetMatchHistory(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'login_required') });
    return;
  }
  const targetNickname = data.nickname;
  if (!targetNickname) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'nickname_required') });
    return;
  }
  const gameType = typeof data.gameType === 'string' ? data.gameType : 'all';
  const offset = Math.max(0, Math.min(1000, Number(data.offset) || 0));
  const limit = Math.max(
    1,
    Math.min(MATCH_HISTORY_PAGE_MAX, Number(data.limit) || 50),
  );
  const empty = () => sendTo(ws, {
    type: 'match_history_page',
    nickname: targetNickname,
    gameType,
    offset,
    matches: [],
    hasMore: false,
  });
  if (fillerRooms.isFillerNickname(targetNickname)) return empty();
  if (profileHiddenFrom(ws, targetNickname)) return empty();

  const { matches, hasMore } = await getRecentMatches(targetNickname, limit, {
    gameType,
    offset,
    // Same rule as the popup's own list — see clientSupportsMidLeaveHistory.
    // Old clients cannot reach this handler at all (the message type is newer
    // than they are), but the two endpoints answering differently is the kind
    // of gap a later refactor walks into.
    includeMidLeave: clientSupportsMidLeaveHistory(ws),
  });
  sendTo(ws, {
    type: 'match_history_page',
    nickname: targetNickname,
    gameType,
    offset,
    matches,
    hasMore,
  });
}

function handleGameAction(ws, data) {
  const __diagActionOn = DIAG_ON
    && ['play_cards', 'pass', 'play_card'].includes(data?.type);
  const __diagActionStart = __diagActionOn ? process.hrtime.bigint() : 0n;
  let __diagHandleMs = 0;
  let __diagEventMs = 0;
  let __diagStateMs = 0;

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

  const __diagHandleStart = __diagActionOn ? process.hrtime.bigint() : 0n;
  const result = room.game.handleAction(ws.playerId, data);
  if (__diagActionOn) __diagHandleMs = Number(process.hrtime.bigint() - __diagHandleStart) / 1e6;
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
    const __diagEventStart = __diagActionOn ? process.hrtime.bigint() : 0n;
    broadcastGameEvent(ws.roomId, result.broadcast);
    if (__diagActionOn) __diagEventMs = Number(process.hrtime.bigint() - __diagEventStart) / 1e6;
  }
  const __diagStateStart = __diagActionOn ? process.hrtime.bigint() : 0n;
  sendGameStateToAll(ws.roomId);
  if (__diagActionOn) {
    __diagStateMs = Number(process.hrtime.bigint() - __diagStateStart) / 1e6;
    const __diagTotalMs = Number(process.hrtime.bigint() - __diagActionStart) / 1e6;
    if (__diagTotalMs > DIAG_SLOW_MS) {
      console.log(`[DIAG] human-action ${__diagTotalMs.toFixed(0)}ms room=${ws.roomId} type=${room.gameType} action=${data.type} handle=${__diagHandleMs.toFixed(0)}ms event=${__diagEventMs.toFixed(0)}ms state=${__diagStateMs.toFixed(0)}ms`);
    }
  }

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
  // Admin-created filler rooms have no real player in them, so a saved match
  // would only add noise to rankings and match history.
  if (fillerRooms.isFillerRoom(room.id)) {
    room.game.resultSaved = true;
    return;
  }
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
  // Winner criteria for ranking/stats (5p and 6p alike):
  //   rank ≤ 2 AND final score > 0 → winner
  //   everyone else → loss
  const isMightyWinner = (rank, score) => rank <= 2 && score > 0;

  const allPlayers = game.playerIds.map((pid) => ({
    playerId: pid,
    nickname: game.playerNames[pid] || pid,
    score: game.scores[pid] || 0,
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
        rankedPlayers.push({
          ...allPlayers[i],
          rank: currentRank,
          isWinner: isMightyWinner(currentRank, allPlayers[i].score),
        });
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
    return {
      ...player,
      rank: currentRank,
      isWinner: isMightyWinner(currentRank, player.score),
    };
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

// Shared executor for the Love Letter resolved-effect auto-ack. Idempotent: it
// no-ops unless the room is still parked on a resolved effect, so the primary
// 2.5s timer and the bot backup timer can both point at it without ever
// double-acking (whichever fires first advances the state; the other no-ops).
function autoAckResolvedLLEffect(roomId) {
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
}

function sendGameStateToAll(roomId) {
  return _sendGameStateToAllImpl(roomId);
}

function _sendGameStateToAllImpl(roomId) {
  const room = lobby.getRoom(roomId);
  if (!room || !room.game) return;
  // Do NOT clear the Love Letter effect_resolve auto-ack timer here. It owns the
  // 2.5s advance; clearing+resetting it on every re-broadcast (e.g. a human's
  // client activity in the room) keeps postponing the ack and strands the
  // (often bot) effect owner until the 8s watchdog — turning each effect into an
  // 8s stall. It is armed exactly once below and cleans up after itself.
  const isLLEffectResolve = room.gameType === 'love_letter' && room.game.state === 'effect_resolve';
  if (room.game.state !== 'trick_end' && !isLLEffectResolve && trickEndTimers[roomId]) {
    clearTimeout(trickEndTimers[roomId]);
    delete trickEndTimers[roomId];
  }

  // Love Letter: auto-advance effect_resolve after resolved effects
  if (isLLEffectResolve && room.game.pendingEffect && room.game.pendingEffect.resolved) {
    // Primary auto-ack: arm ONCE — re-broadcasts must not reset the 2.5s deadline.
    if (!trickEndTimers[roomId]) {
      trickEndTimers[roomId] = setTimeout(() => {
        delete trickEndTimers[roomId];
        autoAckResolvedLLEffect(roomId);
      }, 2500);
    }
    // Backup auto-ack. A resolved effect gets no turn timer (startTurnTimer
    // only arms for unresolved ones), so if the primary above ever slips —
    // never armed because the slot was occupied, or cleared by a reconnect
    // race — nothing else advances the room. This independent timer fires
    // just after the presentation window and self-heals to a brief blip.
    // Idempotent (autoAckResolvedLLEffect no-ops once the primary advanced),
    // so it never double-acks.
    //
    // Armed for human owners too, not just bots: a human who can ack from the
    // UI doesn't need it, but a disconnected one is exactly as stuck as a bot
    // and — unlike a bot — isn't covered by the stuck-bot watchdog either.
    if (!llAckBackupTimers[roomId]) {
      llAckBackupTimers[roomId] = setTimeout(() => {
        delete llAckBackupTimers[roomId];
        autoAckResolvedLLEffect(roomId);
      }, 4000);
    }
    _broadcastState(roomId, room);
    return;
  }

  if (room.gameType === 'mighty' && room.game.state === 'trick_end') {
    // These early-return branches skip startTurnTimer, which is what would
    // normally drop a timer belonging to the state we just left. Drop it here
    // instead — nobody owes a turn action during a trick/round screen, and a
    // survivor fires into a state where the auto-play no-ops while the
    // timeout count climbs toward a bogus desertion. See game/turnGuard.js.
    clearTurnTimer(roomId);
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
    clearTurnTimer(roomId); // see the mighty trick_end branch above
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
    clearTurnTimer(roomId); // see the mighty trick_end branch above
    // Draining: this is the boundary we've been waiting for. Park here
    // instead of dealing another hand and hand the match to the peer —
    // the cumulative score rides along and the room resumes there.
    if (isDraining) {
      _broadcastState(roomId, room);
      maybeMigrateRoom(roomId).catch((err) => {
        console.error(`[${INSTANCE_NAME}] drain migrate ${roomId}:`, err);
      });
      return;
    }
    if (roundEndTimers[roomId]) clearTimeout(roundEndTimers[roomId]);
    const roundEndDelay = room.gameType === 'skull_king' ? 5000 : room.gameType === 'love_letter' ? 4000 : room.gameType === 'mighty' ? 5000 : 3000;
    roundEndTimers[roomId] = setTimeout(() => {
      delete roundEndTimers[roomId];
      const r = lobby.getRoom(roomId);
      if (!r || !r.game || r.game.state !== 'round_end') return;
      // DIAGNOSTICS (temporary): nextRound re-deals 56 cards; time it in case a
      // round transition is a source of untimed event-loop lag.
      const __t0 = process.hrtime.bigint();
      r.game.nextRound();
      const __ms = Number(process.hrtime.bigint() - __t0) / 1e6;
      if (DIAG_ON && __ms > DIAG_SLOW_MS) console.log(`[DIAG] nextRound ${__ms.toFixed(0)}ms room=${roomId} type=${r.gameType}`);
      sendGameStateToAll(roomId);
    }, roundEndDelay);
    // Send state without timer for round_end
    _broadcastState(roomId, room);
    return;
  }

  // Skull King bidding is simultaneous, so a human bid should refresh any
  // pending bot schedule immediately instead of waiting for an older timer.
  const forceBotReschedule = room.gameType === 'skull_king' && room.game.state === 'bidding';
  // Set timer BEFORE sending state so turnDeadline is included
  scheduleBotActions(roomId, forceBotReschedule);
  startTurnTimer(roomId);

  _broadcastState(roomId, room);
}

function _broadcastState(roomId, room) {
  // Slow broadcast detail. `bcast-split` is the main line; per-recipient
  // `send-slow` and state-build/decor lines appear only when that sub-step is
  // itself slow enough to explain the spike.
  const __diagOn = DIAG_ON;
  const __t0 = __diagOn ? process.hrtime.bigint() : 0n;
  let __tState = 0, __tBuild = 0, __tDecor = 0, __tJson = 0, __tWs = 0, __tSend = 0, __nH = 0, __nS = 0, __maxBytes = 0, __maxBufferedBefore = 0, __maxBufferedAfter = 0;
  const __send = (ws, obj, isSpec, recipientId = '-') => {
    if (!__diagOn) { sendTo(ws, obj); return; }
    const __s = process.hrtime.bigint();
    if (ws.readyState === ws.OPEN) {
      const __j = process.hrtime.bigint();
      const str = JSON.stringify(obj);
      const __jsonMs = Number(process.hrtime.bigint() - __j) / 1e6;
      __tJson += __jsonMs;
      if (str.length > __maxBytes) __maxBytes = str.length;
      const __bufBefore = ws.bufferedAmount || 0;
      if (__bufBefore > __maxBufferedBefore) __maxBufferedBefore = __bufBefore;
      const __w = process.hrtime.bigint();
      ws.send(str, { compress: false });
      const __wsMs = Number(process.hrtime.bigint() - __w) / 1e6;
      __tWs += __wsMs;
      const __bufAfter = ws.bufferedAmount || 0;
      if (__bufAfter > __maxBufferedAfter) __maxBufferedAfter = __bufAfter;
      if ((__jsonMs + __wsMs) > DIAG_SLOW_MS) {
        console.log(`[DIAG] send-slow ${(__jsonMs + __wsMs).toFixed(0)}ms room=${roomId} type=${room.gameType} phase=${room.game.state} recipient=${recipientId} kind=${isSpec ? 'spectator' : 'player'} json=${__jsonMs.toFixed(0)}ms ws=${__wsMs.toFixed(0)}ms kb=${(str.length / 1024).toFixed(1)} buf=${Math.round(__bufBefore / 1024)}KB>${Math.round(__bufAfter / 1024)}KB`);
      }
      if (isSpec) __nS++; else __nH++;
    }
    __tSend += Number(process.hrtime.bigint() - __s) / 1e6;
  };

  try {
  // Clear out stale card-view permissions (killed-mighty players from the
  // previous round who are now active again).
  if (typeof room.pruneCardViewPermissions === 'function') {
    room.pruneCardViewPermissions();
  }

  // Connection / timeout / photo / bot facts, gathered once and reused for
  // every recipient below. The per-viewer part (photo filtering) still happens
  // per socket inside the decorators.
  const seats = roomSeatInfo(room);

  const isMighty = room.gameType === 'mighty';
  const gameStateCache = typeof room.game.buildStateBroadcastCache === 'function'
    ? room.game.buildStateBroadcastCache()
    : null;

  // Send to human players (skip null slots and bots)
  for (const player of room.players) {
    if (player === null) continue;
    if (player.connected === false) continue;
    if (room.isBot(player.id)) continue;
    const ws = findWsByPlayerId(player.id);
    if (ws) {
      const __sb = __diagOn ? process.hrtime.bigint() : 0n;
      // Killed-mighty players get their scoreboard filled with peek data for
      // any seat they've been granted viewing rights to.
      const isExcluded = isMighty && room.game.excludedPlayers
        && room.game.excludedPlayers.has(player.id);
      const permitted = isExcluded
        ? room.getPermittedPlayers(player.id)
        : new Set();
      const state = room.game.getStateForPlayer(player.id, permitted, gameStateCache);
      const __stateMs = __diagOn ? Number(process.hrtime.bigint() - __sb) / 1e6 : 0;
      if (__diagOn) __tBuild += __stateMs;
      if (__diagOn && __stateMs > DIAG_SLOW_MS) {
        console.log(`[DIAG] state-build ${__stateMs.toFixed(0)}ms room=${roomId} type=${room.gameType} phase=${room.game.state} recipient=${player.id} cards=${room.game.hands?.[player.id]?.length ?? '-'}`);
      }
      const __db = __diagOn ? process.hrtime.bigint() : 0n;
      decoratePlayerState(room, ws, state, seats);
      if (__diagOn) {
        const __decorMs = Number(process.hrtime.bigint() - __db) / 1e6;
        __tDecor += __decorMs;
        if (__decorMs > DIAG_SLOW_MS) {
          console.log(`[DIAG] state-decor ${__decorMs.toFixed(0)}ms room=${roomId} type=${room.gameType} phase=${room.game.state} recipient=${player.id}`);
        }
      }
      if (__diagOn) __tState += Number(process.hrtime.bigint() - __sb) / 1e6;
      __send(ws, { type: 'game_state', state }, false, player.id);
    }
  }

  // Send to spectators (each with their own permissions)
  for (const spectatorId of room.getSpectatorIds()) {
    const ws = findWsByPlayerId(spectatorId);
    if (ws) {
      const __sb = __diagOn ? process.hrtime.bigint() : 0n;
      const permittedPlayers = room.getPermittedPlayers(spectatorId);
      const spectatorState = room.game.getStateForSpectator(permittedPlayers, gameStateCache);
      const __stateMs = __diagOn ? Number(process.hrtime.bigint() - __sb) / 1e6 : 0;
      if (__diagOn) __tBuild += __stateMs;
      if (__diagOn && __stateMs > DIAG_SLOW_MS) {
        console.log(`[DIAG] state-build ${__stateMs.toFixed(0)}ms room=${roomId} type=${room.gameType} phase=${room.game.state} recipient=${spectatorId} spectator=1`);
      }
      const __db = __diagOn ? process.hrtime.bigint() : 0n;
      decorateSpectatorState(room, ws, spectatorState, seats);
      if (__diagOn) {
        const __decorMs = Number(process.hrtime.bigint() - __db) / 1e6;
        __tDecor += __decorMs;
        if (__decorMs > DIAG_SLOW_MS) {
          console.log(`[DIAG] state-decor ${__decorMs.toFixed(0)}ms room=${roomId} type=${room.gameType} phase=${room.game.state} recipient=${spectatorId} spectator=1`);
        }
      }
      if (__diagOn) __tState += Number(process.hrtime.bigint() - __sb) / 1e6;
      __send(ws, { type: 'spectator_game_state', state: spectatorState }, true, spectatorId);
    }
  }
  } finally {
    if (__diagOn) {
      const __ms = Number(process.hrtime.bigint() - __t0) / 1e6;
      // A big __ms with small tState+tSend ⇒ time stolen mid-broadcast (GC/host),
      // not real broadcast work. Big tState/tSend ⇒ genuine serialization cost.
      if (__ms > DIAG_SLOW_MS) {
        console.log(`[DIAG] bcast-split ${__ms.toFixed(0)}ms room=${roomId} type=${room.gameType} recips=${__nH}h/${__nS}s state=${__tState.toFixed(0)}ms build=${__tBuild.toFixed(0)}ms decor=${__tDecor.toFixed(0)}ms json=${__tJson.toFixed(0)}ms ws=${__tWs.toFixed(0)}ms send=${__tSend.toFixed(0)}ms maxKB=${(__maxBytes / 1024).toFixed(1)} buf=${Math.round(__maxBufferedBefore / 1024)}KB>${Math.round(__maxBufferedAfter / 1024)}KB`);
      }
    }
  }
}

// Bot auto-response: schedule a single delayed bot action check
let pendingBotCheck = {}; // roomId -> true (prevent duplicate scheduling)
let pendingBotTimers = {}; // roomId -> timeout handle
// roomId -> true while a bot decision is awaiting the worker pool. During that
// await pendingBotTimers[roomId] is cleared (the callback already fired), so
// without this flag the stuck-bot watchdog would misread a slow (queued) worker
// decision as a frozen room and force-reschedule it — harmless (the botStateSig
// gap guard rejects the duplicate) but wasteful and log-noisy under load.
let botDecisionInFlight = {};

function getBotBaseDelay(speed) {
  switch (speed) {
    case 'fast': return 100 + Math.floor(Math.random() * 200);    // 100-300ms (was 300-600)
    case 'slow': return 900 + Math.floor(Math.random() * 600);    // 900-1500ms (was 1200-1800)
    default:     return 300 + Math.floor(Math.random() * 400);    // 300-700ms (was 600-1000)
  }
}

function getBotExtraDelay(speed) {
  switch (speed) {
    case 'fast': return 100;   // was 200
    case 'slow': return 700;   // was 800
    default:     return 300;   // was 400
  }
}

// Cheap signature of the state that decides whether a just-computed bot action
// is still valid: phase, who's to act, and trick progress. Lets the post-delay
// timer skip recomputing an expensive (mixoracle) decision when nothing moved.
function botStateSig(game) {
  if (!game) return '';
  const actor = typeof game.getPendingActor === 'function' ? game.getPendingActor() : game.currentPlayer;
  const trickLen = Array.isArray(game.currentTrick) ? game.currentTrick.length : 0;
  const pendingLen = Array.isArray(game.pendingTrickCards) ? game.pendingTrickCards.length : 0;
  return `${game.state}|${actor}|${game.currentPlayer}|${trickLen}|${game.needsToCallRank || ''}|${game.dragonPending ? game.dragonDecider || '' : ''}|${pendingLen}`;
}

// Bot decision worker pool. Expensive searches (mighty mixoracle/oracle/solver,
// tichu winrate) run here off the main event loop; heuristic / LL / SK stay
// inline (sub-ms, offload would only add IPC latency). BOT_WORKERS=0 disables
// the pool entirely (kill switch) — every decision then runs inline as before.
let botPool = null;
try {
  if (process.env.BOT_WORKERS === '0') {
    console.log('[info] Bot worker pool disabled (BOT_WORKERS=0) — decisions run inline');
  } else {
    botPool = new BotWorkerPool();
    console.log(`[info] Bot worker pool started (size=${botPool.size})`);
  }
} catch (e) {
  console.error('[BOT] worker pool init failed — falling back to inline decisions:', e);
  botPool = null;
}

// Which (gameType, strategy) pairs are worth offloading. 'heuristic' is sub-ms;
// love_letter / skull_king bots are pure heuristics. Everything else on a
// supported game type is an expensive search → worker. New expensive mighty
// strategies auto-qualify (anything != heuristic), so this needs no upkeep.
function botStratIsExpensive(gameType, strat) {
  if (gameType !== 'mighty' && gameType !== 'tichu') return false;
  return !!strat && strat !== 'heuristic';
}

function scheduleBotActions(roomId, forceReschedule = false) {
  const room = lobby.getRoom(roomId);
  if (!room || !room.game) return;
  if (room.getBotIds().length === 0) return;
  // Block re-entry while a decision is already scheduled OR a worker decision
  // is mid-flight. The latter matters because the callback drops pendingBotCheck
  // before awaiting the worker; without this an unrelated re-broadcast
  // (small-tichu declare, card-view revoke, reconnect) would arm a second
  // competing timer during that await. The in-flight callback re-checks state
  // on resolve and reschedules if anything moved, so nothing is lost.
  if ((pendingBotCheck[roomId] || botDecisionInFlight[roomId]) && !forceReschedule) return;
  if (forceReschedule && pendingBotTimers[roomId]) {
    clearTimeout(pendingBotTimers[roomId]);
    delete pendingBotTimers[roomId];
    delete pendingBotCheck[roomId];
  }

  pendingBotCheck[roomId] = true;

  let activeBotSpeed = 'normal';
  const pendingActor0 = typeof room.game.getPendingActor === 'function'
    ? room.game.getPendingActor()
    : room.game.currentPlayer;
  if (pendingActor0 && room.isBot(pendingActor0)) {
    const bot = room.bots.get(pendingActor0);
    activeBotSpeed = bot ? bot.speed : 'normal';
  } else if (room.game.state === 'round_end') {
    for (const botId of room.getBotIds()) {
      const bot = room.bots.get(botId);
      if (bot) {
        activeBotSpeed = bot.speed;
        break;
      }
    }
  }

  const baseDelay = getBotBaseDelay(activeBotSpeed);
  let effectiveDelay = baseDelay;
  if (room.gameType === 'mighty') {
    // Hold bots until the reveal grace period (deal-miss / kill) ends so
    // players can read the overlay before the next action fires.
    if (typeof room.game.revealGracePeriodEndAt === 'number') {
      const graceRemaining = room.game.revealGracePeriodEndAt - Date.now();
      if (graceRemaining > effectiveDelay) effectiveDelay = graceRemaining;
    }
    // Kitty exchange and kill selection are information-rich (kitty reveal,
    // trump change, friend selection, kill target) — give players at least 2s
    // to watch the declarer bot work.
    if ((room.game.state === 'kitty_exchange' || room.game.state === 'kill_select')
        && effectiveDelay < 2000) {
      effectiveDelay = 2000;
    }
  }

  if (pendingBotTimers[roomId]) clearTimeout(pendingBotTimers[roomId]); // never leak a prior handle
  pendingBotTimers[roomId] = setTimeout(async () => {
    delete pendingBotTimers[roomId];
    delete pendingBotCheck[roomId];
    // When the bot "started thinking". Deciding can take a worker round trip,
    // and that time is part of the pause the player sees — so the pause that
    // still owes them is measured from here, not from when the decision lands.
    const thinkStart = Date.now();
    const r = lobby.getRoom(roomId);
    if (!r || !r.game) return;

    try {
    // Re-evaluate at execution time (botDecisionInFlight is managed inside
    // decideFn, around the actual worker round-trip).
    const isSK = r.gameType === 'skull_king';
    const isLL = r.gameType === 'love_letter';
    const isMighty = r.gameType === 'mighty';
    const baseDecideFn = isMighty ? decideMightyBotAction : isLL ? decideLLBotAction : isSK ? decideSKBotAction : decideBotAction;
    // Async: expensive strategies are offloaded to the worker pool (the await
    // yields the event loop instead of blocking it). Cheap strategies resolve
    // inline via an already-settled promise (microtask only — no I/O gap). On
    // any worker failure we fall back to an inline decision so a game never
    // hangs on a sick worker.
    const decideFn = async (g, pid, allowOffload = true) => {
      const cur = lobby.getRoom(roomId);
      const strat = cur?.bots.get(pid)?.strategy || 'heuristic';
      // Only offload when this bot actually has a decision to make. When it is
      // someone else's turn (candidateBotIds = all bots, for the bomb / tichu
      // interrupt check), the strategy short-circuits to []/null before any
      // rollout — so running it inline is just as cheap and saves a wasted
      // worker round-trip per non-acting bot on every human turn.
      const offload = allowOffload && !!botPool && botStratIsExpensive(r.gameType, strat);
      let a;
      if (offload) {
        // Refcount an in-flight worker decision for this room. While it's set:
        //  - scheduleBotActions won't arm a second competing timer (guard above)
        //  - the watchdog won't misread the slow decision as a frozen room.
        // A counter (not a boolean) so two concurrent decisions can't clear each
        // other's mark. Cleared in finally so it never sticks (which would both
        // wedge scheduling AND blind the watchdog).
        botDecisionInFlight[roomId] = (botDecisionInFlight[roomId] || 0) + 1;
        try {
          a = await botPool.decide(r.gameType, g, pid, strat);
        } catch (e) {
          // Worker unavailable (timeout / crash / circuit open). Fall back to
          // the CHEAP heuristic inline — never the expensive strat, which would
          // re-block the very event loop the pool exists to protect (and under
          // a pool-wide outage every decision would hit this path at once).
          if (DIAG_ON) console.log(`[DIAG] bot-worker-fallback room=${roomId} bot=${pid} strat=${strat} err=${e && e.message}`);
          a = baseDecideFn(g, pid, 'heuristic');
        } finally {
          botDecisionInFlight[roomId] = (botDecisionInFlight[roomId] || 1) - 1;
          if (botDecisionInFlight[roomId] <= 0) delete botDecisionInFlight[roomId];
        }
      } else {
        a = baseDecideFn(g, pid, strat);
      }
      // No per-decision timing log here: the mixoracle-detail / tichu-winrate-
      // detail breakdown (for tuning) and the 30s pool summary (mc/mqw/slow,
      // for stutter) cover it without 3 overlapping lines per slow decision.
      return a;
    };

    if (isSK && r.game.state === 'bidding') {
      const pendingBidBots = r.getBotIds().filter(pid => r.game?.bids?.[pid] === null);
      let progressed = false;
      for (const botId of pendingBidBots) {
        let action = await decideFn(r.game, botId);
        if (!action) continue;
        let result = r.game.handleAction(botId, action);
        if (result && !result.success && r.game) {
          console.log(`[BOT] ${botId} action failed: ${result.messageKey || result.message}, trying fallback`);
          const fallback = r.game.getAutoTimeoutAction(botId);
          if (fallback) {
            console.log(`[BOT] ${botId} fallback: ${fallback.type}`);
            result = r.game.handleAction(botId, fallback);
          }
        }
        if (result && result.success) {
          if (result.broadcast) broadcastGameEvent(roomId, result.broadcast);
          progressed = true;
        } else if (result) {
          console.log(`[BOT] ${botId} action failed: ${result.message}`);
        }
      }

      if (progressed) {
        if (r.game && r.game.state === 'game_end') {
          saveGameResult(r);
          scheduleAutoReturnToRoom(roomId);
        }
        sendGameStateToAll(roomId);
      }
      return;
    }

    const pendingActor = typeof r.game.getPendingActor === 'function'
      ? r.game.getPendingActor()
      : r.game.currentPlayer;
    const candidateBotIds = (pendingActor && r.isBot(pendingActor))
      ? [pendingActor]
      : r.getBotIds();

    for (const botId of candidateBotIds) {
      // Snapshot decision-relevant state before the (possibly awaited)
      // decision. Offloaded decisions yield the event loop during the worker
      // round-trip, so a human action or other event can move the game. If it
      // moved, discard this now-stale decision and let the fresh state
      // reschedule — applying it risks an out-of-turn move.
      const preSig = botStateSig(r.game);
      // Offload only the actor whose turn it is (or, in simultaneous phases
      // where pendingActor is null, every candidate legitimately decides).
      // Bots checked purely for a bomb/tichu interrupt on someone else's turn
      // short-circuit to []/null, so run those inline and skip the round-trip.
      // Include `currentPlayer` explicitly: the expensive winrate/oracle path
      // runs on isMyTurn (== currentPlayer), which can diverge from pendingActor
      // in the bird/needsToCallRank and dragon windows — offload it so that
      // never blocks the event loop, regardless of client behaviour.
      const allowOffload = !pendingActor || botId === pendingActor || botId === r.game.currentPlayer;
      let action = await decideFn(r.game, botId, allowOffload);
      // The room may have been closed (desertion / AFK / everyone left) during
      // the worker round-trip. closeRoom() removes it from the lobby but does
      // NOT null room.game (by design it relies on callbacks re-fetching), so
      // the captured `r` would still look alive — trust lobby.getRoom instead.
      // Without this we'd handleAction / saveGameResult on a dead room.
      // Also bail if the room is being deserted: handleDesertion claimed the
      // game terminally (deserted/resultSaved) but leaves state='playing' until
      // its DB awaits finish, so botStateSig alone wouldn't catch it. Applying
      // a move here would race the desertion save.
      if (!lobby.getRoom(roomId) || !r.game || r.game.deserted) return;
      const postSig = botStateSig(r.game);
      if (postSig !== preSig) {
        if (botPool) botPool.noteStale(); // counted in the 30s summary (stale)
        scheduleBotActions(roomId);
        return;
      }
      if (action) {
        const bot = r.bots.get(botId);
        const botSpeed = bot ? bot.speed : 'normal';
        // Add extra delay for card play actions to feel more natural
        const isCardPlay = action.type === 'play_cards' || action.type === 'pass' || action.type === 'play_card';
        if (isCardPlay) {
          // #1: cache the (expensive) decision + a cheap state signature.
          // mixoracle is costly and nothing else acts during a bot's own delay
          // window, so re-running decideFn after the delay just doubled CPU for
          // no benefit. Reuse the cached action when the state is unchanged;
          // only re-decide if it actually moved (e.g. a Tichu bomb interrupt —
          // cheap heuristic anyway).
          const decidedSig = botStateSig(r.game);
          const decidedAction = action;
          pendingBotCheck[roomId] = true;
          if (pendingBotTimers[roomId]) clearTimeout(pendingBotTimers[roomId]); // never leak a prior handle
          pendingBotTimers[roomId] = setTimeout(async () => {
            delete pendingBotTimers[roomId];
            delete pendingBotCheck[roomId];
            const r2 = lobby.getRoom(roomId);
            if (!r2 || !r2.game || r2.game.deserted) return;
            try {
            // Reuse the cached decision when nothing changed; else re-decide.
            // The re-decide may be offloaded (awaited): guard the async gap so
            // a state change during the worker round-trip discards the stale
            // result instead of applying an out-of-turn move.
            let action2;
            if (botStateSig(r2.game) === decidedSig) {
              action2 = decidedAction;
            } else {
              const preSig2 = botStateSig(r2.game);
              action2 = await decideFn(r2.game, botId);
              // Same stale-room guard as the outer path: the room may have been
              // closed or entered desertion during the worker round-trip, and
              // closeRoom() leaves the captured r2.game set — so `!r2.game`
              // alone wouldn't catch it, and we'd run handleAction /
              // saveGameResult / sendGameStateToAll on a dead room.
              if (!lobby.getRoom(roomId) || !r2.game || r2.game.deserted) return;
              const postSig2 = botStateSig(r2.game);
              if (postSig2 !== preSig2) {
                if (botPool) botPool.noteStale(); // counted in the 30s summary (stale)
                scheduleBotActions(roomId);
                return;
              }
            }
            // The cached decision was validated against the pre-delay state.
            // botStateSig is coarse (it captures trick *length* but not the
            // trick-top combo), so a rare state change during the delay can
            // leave a reused follow-play unable to beat the current trick
            // (-> game_combo_cannot_beat, then a wasted fallback pass). If a
            // reused Tichu card-play is no longer legal, re-decide — decideFn
            // always filters candidates against the current game.
            if (action2 === decidedAction
                && (action2.type === 'play_cards' || action2.type === 'play_card')
                && typeof r2.game.canPlayCards === 'function'
                && !r2.game.canPlayCards(botId, action2.cards || []).success) {
              const preSig3 = botStateSig(r2.game);
              action2 = await decideFn(r2.game, botId);
              if (!lobby.getRoom(roomId) || !r2.game || r2.game.deserted) return;
              const postSig3 = botStateSig(r2.game);
              if (postSig3 !== preSig3) {
                if (botPool) botPool.noteStale(); // counted in the 30s summary (stale)
                scheduleBotActions(roomId);
                return;
              }
            }
            if (!action2) {
              // State changed (e.g. bomb interrupt) - re-schedule for other bots
              scheduleBotActions(roomId);
              return;
            }
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
            } catch (e) {
              console.error(`[BOT] scheduleBotActions play-delay timer error room=${roomId}:`, e);
            }
          },
          // Spend what is left of the pause, not another full one. The spacing
          // used to be additive — base + however long the decision took +
          // extra — so a worker round trip that spiked to ~250ms (seen in
          // production: mqw0 mc92 mt257) stretched that one move well past its
          // budget while the next came back at the normal 200-400ms. Even
          // spacing is what reads as a bot thinking; uneven spacing is what
          // reads as it stalling and then rattling off a burst.
          //
          // Bounded on purpose: this can only absorb up to extraDelay, since
          // the base wait already happened before the decision started. For
          // 'normal' (300ms) that covers the spikes observed so far; for
          // 'fast' (100ms) it only takes the edge off. Absorbing the whole
          // budget means deciding first and waiting afterwards, which turns
          // this function async and changes its re-entrancy — a bigger change
          // than the symptom has earned yet.
          Math.max(0, getBotExtraDelay(botSpeed) - (Date.now() - thinkStart)));
          return;
        }
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
      } else if (pendingActor && botId === pendingActor && r.isBot(pendingActor) && !NON_ACTIONABLE_STATES.has(r.game.state)) {
        // SAFETY NET: it is genuinely this bot's turn, but its strategy returned
        // no action (decide() falls through to `return null` for some state /
        // hand). Bots get NO turn-timeout (startTurnTimer skips them), so
        // without this the room freezes forever and the HUMAN players time out
        // and get kicked instead — exactly the "bot turn never advances" bug.
        // Force the engine's guaranteed-legal auto-action so the turn always
        // advances, and log the state so the null-decision source can be fixed.
        console.log(`[BOT] STUCK bot=${botId} room=${roomId} type=${r.gameType} state=${r.game.state} — forcing auto-action`);
        const stuckFb = r.game.getAutoTimeoutAction(botId);
        if (stuckFb) {
          const fr = r.game.handleAction(botId, stuckFb);
          if (fr && fr.success) {
            if (fr.broadcast) broadcastGameEvent(roomId, fr.broadcast);
            if (r.game && r.game.state === 'game_end') { saveGameResult(r); scheduleAutoReturnToRoom(roomId); }
            sendGameStateToAll(roomId); // re-triggers scheduleBotActions for the next actor
          } else {
            console.log(`[BOT] STUCK bot=${botId} auto-action FAILED: ${fr?.messageKey || fr?.message} (state=${r.game.state})`);
          }
        } else {
          console.log(`[BOT] STUCK bot=${botId} no auto-action available for state=${r.game.state}`);
        }
        return;
      }
    }
    } catch (e) {
      // Never let an async bot-decision path crash the process. The bot
      // watchdog reschedules a stalled room, so logging + bailing is safe.
      console.error(`[BOT] scheduleBotActions callback error room=${roomId}:`, e);
    }
  }, effectiveDelay);
}

// --- Turn Timer System ---

// How long to give someone before auto-playing their turn.
//
// While draining, a player who has gone quiet is already on the other
// instance — our /health is 503, so the load balancer sends every reconnect
// there and they cannot come back here to play this turn. Burning the full
// timer on them only delays the round boundary the room needs to migrate,
// which is exactly what strands them in the new lobby waiting for it. They
// can't act either way; auto-play for them promptly instead.
//
// Anyone still connected keeps their normal clock — they're playing, and
// rushing them to speed up someone else's handover would be a poor trade.
const DRAIN_ABSENT_TURN_MS = 1000;

function isAbsentDuringDrain(room, playerId) {
  if (!isDraining || !playerId) return false;
  const p = room.players.find((x) => x !== null && x.id === playerId);
  return !!p && !p.isBot && !p.connected;
}

function turnTimeLimitMs(room, playerId, multiplier = 1) {
  if (isAbsentDuringDrain(room, playerId)) return DRAIN_ABSENT_TURN_MS;
  return room.turnTimeLimit * multiplier * 1000;
}

/**
 * Does this seat play itself? Bots do, and so does a filler room's host — its
 * turns come from lobby/fillerRooms.js, not from a person.
 *
 * Used to decide whether to arm a turn clock. Without the filler case a clock
 * was armed for a seat that never needed one, fired after fillerRooms had
 * already moved, and landed in handleTurnTimeout's spurious-timer guard — no
 * harm done, but a warn line every round for every filler room.
 */
function seatIsAutoPlayed(room, playerId) {
  return room.isBot(playerId) || fillerRooms.isFillerHost(playerId);
}
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
      pid => room.game.largeTichuResponses[pid] === undefined && !seatIsAutoPlayed(room, pid)
    );
    if (pending.length === 0) return;
    const timeLimit = pending.every((pid) => isAbsentDuringDrain(room, pid))
      ? DRAIN_ABSENT_TURN_MS
      : room.turnTimeLimit * 2 * 1000;
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
      pid => !room.game.exchangeDone[pid] && !seatIsAutoPlayed(room, pid)
    );
    if (pending.length === 0) return;
    const timeLimit = pending.every((pid) => isAbsentDuringDrain(room, pid))
      ? DRAIN_ABSENT_TURN_MS
      : room.turnTimeLimit * 2 * 1000;
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
      pid => room.game.bids[pid] === null && !seatIsAutoPlayed(room, pid)
    );
    if (pending.length === 0) return;
    const timeLimit = pending.every((pid) => isAbsentDuringDrain(room, pid))
      ? DRAIN_ABSENT_TURN_MS
      : room.turnTimeLimit * 2 * 1000;
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
    if (!currentPlayer || seatIsAutoPlayed(room, currentPlayer)) return;
    const timeLimit = turnTimeLimitMs(room, currentPlayer);
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
    if (!declarer || seatIsAutoPlayed(room, declarer)) return;
    const timeLimit = turnTimeLimitMs(room, declarer, 2);
    room.turnDeadline = Date.now() + timeLimit;
    turnTimers[roomId] = setTimeout(() => {
      handleTurnTimeout(roomId, declarer);
    }, timeLimit);
    return;
  }

  // Mighty kill-select (6p only): declarer picks a kill target. Uses the
  // standard turn time limit; auto-timeout resolves via getAutoTimeoutAction.
  if (room.gameType === 'mighty' && gameState === 'kill_select') {
    clearTurnTimer(roomId);
    const declarer = room.game.declarer;
    if (!declarer || seatIsAutoPlayed(room, declarer)) return;
    const timeLimit = turnTimeLimitMs(room, declarer);
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
      if (!targetPlayer || seatIsAutoPlayed(room, targetPlayer)) return;
      const timeLimit = turnTimeLimitMs(room, targetPlayer);
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
  if (seatIsAutoPlayed(room, targetPlayer)) return; // Bots don't need timers

  const timeLimit = turnTimeLimitMs(room, targetPlayer);
  room.turnDeadline = Date.now() + timeLimit;

  turnTimerTargets[roomId] = targetPlayer;
  turnTimers[roomId] = setTimeout(() => {
    handleTurnTimeout(roomId, targetPlayer);
  }, timeLimit);
}

/**
 * Re-point a just-re-armed timer at the deadline it had before.
 *
 * A reconnect has to clear the running timer — it is armed for a playerId that
 * no longer exists — and let the state broadcast arm a new one. That new one
 * starts from scratch, which turns "background the app" into a free time
 * extension, repeatable for as long as you like. Put the old deadline back and
 * fire on what is left of it.
 *
 * Covers phase timers (grand tichu, exchange, SK bidding) as well as per-turn
 * ones. A phase clock belongs to everyone still to act, so resetting it hands
 * the extension to the whole table rather than just the returning player —
 * the same exploit, wider.
 */
function restoreTurnDeadline(roomId, deadline) {
  if (!deadline) return;
  const room = lobby.getRoom(roomId);
  if (!room || !turnTimers[roomId]) return;
  const remaining = deadline - Date.now();
  // Already past it: let the fresh timer run rather than firing instantly on
  // someone who has only just got their screen back.
  if (remaining <= 0) return;
  // The new timer is already the shorter of the two — leave it be.
  if (room.turnDeadline && room.turnDeadline <= deadline) return;

  const phase = turnTimerPhases[roomId];
  const armedFor = turnTimerTargets[roomId];
  if (!phase && !armedFor) return;

  clearTimeout(turnTimers[roomId]);
  room.turnDeadline = deadline;
  turnTimers[roomId] = setTimeout(() => {
    if (phase) {
      handlePhaseTimeout(roomId, phase);
    } else {
      handleTurnTimeout(roomId, armedFor);
    }
  }, remaining);
}

function clearTurnTimer(roomId) {
  if (turnTimers[roomId]) {
    clearTimeout(turnTimers[roomId]);
    delete turnTimers[roomId];
  }
  delete turnTimerPhases[roomId];
  delete turnTimerTargets[roomId];
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

  // Guard against a SPURIOUS timeout: only penalize (and eventually desert) a
  // player when they genuinely still need to act right now. If the timer fires
  // when it's not actually this player's turn / not the actionable phase (a
  // stale timer, or the turn already advanced), the auto-play below would no-op
  // while the count kept climbing → the player is wrongly deserted after 3 with
  // no card ever played (reported SK bug). In that case just re-sync the timer
  // to the real current actor and bail without counting.
  {
    const g = room.game;
    // Every game type, not just SK: Love Letter carries an unresolved
    // pendingEffect into round_end/game_end, and mighty/tichu have their own
    // states where the armed actor has already moved on. See game/turnGuard.js.
    if (!playerStillNeedsToAct(room.gameType, g, playerId)) {
      console.warn(`[TIMEOUT] spurious timer ignored: room=${roomId} type=${room.gameType} player=${playerId} state=${g.state} current=${g.currentPlayer}`);
      sendGameStateToAll(roomId);
      return;
    }
  }

  // Use nickname as key so timeout count persists across reconnections
  const nickname = room.game.playerNames[playerId] || playerId;

  // While draining, don't hold a missed turn against anyone. A player who has
  // gone quiet here is very likely already on the peer: our /health is 503, so
  // the load balancer sends every reconnect there and they physically cannot
  // come back to this instance. Counting those turns would desert them for a
  // disconnect the deploy caused — and desertion removes the room, so the
  // match dies before it can migrate. Seen exactly that in a smoke test: a
  // backgrounded player was deserted 3 turns into the drain and the room was
  // gone by the time they reappeared on the other side.
  //
  // Auto-play below still runs, so the round keeps moving and reaches the
  // boundary the handover needs.
  // A filler host has no player behind it; its turns are played by
  // lobby/fillerRooms.js. If a tick ever loses a race with the turn timer we
  // must not "desert" it — that would delete the room an admin asked for.
  if (fillerRooms.isFillerHost(playerId)) {
    logVerboseConnection(`[TIMEOUT] filler host ${nickname} — not counted`);
  } else if (!isDraining) {
    if (!timeoutCounts[roomId]) timeoutCounts[roomId] = {};
    if (!timeoutCounts[roomId][nickname]) timeoutCounts[roomId][nickname] = 0;
    timeoutCounts[roomId][nickname]++;

    logVerboseConnection(`[TIMEOUT] ${nickname} (${playerId}) timeout #${timeoutCounts[roomId][nickname]}`);

    // 3 timeouts → desertion (S2: await async handleDesertion)
    if (timeoutCounts[roomId][nickname] >= 3) {
      await handleDesertion(roomId, playerId, 'timeout');
      return;
    }
  } else {
    logVerboseConnection(`[TIMEOUT] ${nickname} (${playerId}) missed a turn while draining — not counted`);
  }

  // Broadcast timeout event
  broadcastGameEvent(roomId, {
    type: 'turn_timeout',
    player: playerId,
    playerName: nickname,
    // Undefined while draining — we skip the counting entirely there, and the
    // room may never have had a timeout to create the bucket.
    count: timeoutCounts[roomId]?.[nickname] ?? 0,
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
        logVerboseConnection(`[TIMEOUT] Auto action failed for ${nickname}: ${result?.message}`);
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
      logVerboseConnection(`[TIMEOUT] No auto action for ${nickname} (currentPlayer: ${room.game.currentPlayer})`);
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
  logVerboseConnection(`[TIMEOUT] ${nickname} reset timeout count`);
  sendTo(ws, { type: 'timeout_reset', count: 0 });
}

// options.penalize=false records the desertion normally — event, result,
// game end — but skips the leave-count bump and ranked ban. For desertions
// this instance decided on someone's behalf rather than ones they chose.
/**
 * Bump the leave count (and ranked ban) for someone who left a live match.
 *
 * Shared by both desertion outcomes — the one that ends the match and the one
 * where a bot takes the seat — so "what counts against you" has a single
 * definition. From the table's side both are the same act; that a bot covered
 * for you doesn't undo it.
 *
 * Skipped for bots, for the solo-vs-bots case (nobody was harmed), and when
 * the caller passes penalize:false for a desertion this instance decided on
 * someone's behalf rather than one they chose.
 *
 * Counts humans EXCLUDING the deserter, so it is correct whether or not they
 * have already been taken out of room.players by the time we get here.
 */
async function recordDesertionAgainst(room, playerId, nickname, options = {}) {
  const otherHumans = room.players.filter(
    (p) => p !== null && !p.isBot && p.id !== playerId,
  ).length;
  if (options.penalize === false
      || !nickname
      || playerId.startsWith('bot_')
      || otherHumans === 0) {
    return;
  }
  // Non-critical side effects. They MUST NOT abort the caller: the seat change
  // (or the terminal desertion claim) has already happened, so throwing out of
  // here would leave the room half-updated — in the desertion case, bricked at
  // state='playing' forever. Swallow and continue.
  try {
    await incrementLeaveCount(nickname);
    if (room.isRanked) {
      await setRankedBan(nickname);
    }
  } catch (e) {
    console.error(`[DESERTION] leave-count/ban update failed for ${nickname}:`, e);
  }
}

/**
 * Put a bot in a leaving player's seat and keep the match running.
 *
 * Returns the handoff details, or null when it can't be done — which today
 * means they were the last human, and the caller must fall back to ending the
 * match. Fully synchronous so callers can test it before claiming a game
 * terminally without opening a race.
 *
 * `reason` is 'leave' or 'timeout'; it only changes what the table and the
 * departing player are told, not what is recorded.
 */
function handOffSeatToBot(room, playerId, reason, options = {}) {
  const roomId = room.id;
  const nickname = room.game.playerNames[playerId];
  // Snapshot the table BEFORE the swap: a moment later this seat holds a bot,
  // and the match keeps running so the roster carries on changing. Everyone
  // but the leaver, in seat order — the same "who you were playing with" the
  // other game types record.
  const tableAtDeparture = room.players
    .filter((p) => p !== null && p.id !== playerId)
    .map((p) => p.nickname)
    .filter(Boolean);
  const leaverWs = findWsByPlayerId(playerId);
  const locale = leaverWs?.locale
    || findWsByPlayerId(room.hostId)?.locale
    || null;

  const result = room.replaceWithBot(playerId, locale);
  if (!result.success) return null;

  releasePeerPending(nickname);
  // No seat to return to — the bot has it. Drop the reconnect pointer so a
  // later reconnect lands in the lobby rather than a room they are no longer
  // part of, and clear the timeout tally so it can't follow a rejoin.
  playerSessions.delete(nickname);
  if (timeoutCounts[roomId]) delete timeoutCounts[roomId][nickname];
  // Same cooldown as a deliberate walk-out. Timing out of one match then
  // immediately dropping into another is exactly what it is there to stop.
  // Skipped for desertions we decided on their behalf (penalize:false).
  if (options.penalize !== false && nickname) {
    midGameJoinCooldowns.set(nickname, Date.now() + MID_GAME_JOIN_COOLDOWN_MS);
  }

  if (leaverWs) {
    // room_left first, and unconditionally.
    //
    // left_in_progress is a type only the new client knows. On the deliberate
    // routes the leave handler sends room_left of its own afterwards, but the
    // timeout route ends here — so an already-installed app timing out of a
    // mid-join room was told nothing it understood, and sat on a frozen board
    // with no way back but the exit button. It is idempotent for both: the new
    // client clears the room, then left_in_progress clears it again and adds
    // the reason; the old client acts on the one message it recognises.
    sendTo(leaverWs, { type: 'room_left' });
    sendTo(leaverWs, {
      type: 'left_in_progress',
      message: t(
        leaverWs.locale,
        reason === 'timeout' ? 'midjoin_left_timeout' : 'midjoin_left_self',
      ),
    });
    if (leaverWs.roomId === roomId) {
      leaverWs.roomId = null;
      leaverWs.isSpectator = false;
    }
  }

  broadcastGameEvent(roomId, {
    type: 'player_left_in_progress',
    player: playerId,
    playerName: nickname,
    slot: result.slot,
    replacedBy: result.botId,
    botName: result.botNickname,
    reason,
  });

  // The seat is a bot's now: if it was their turn, the bot has to be told to
  // move and the human clock has to come down.
  clearTurnTimer(roomId);
  scheduleBotActions(roomId, true);
  startTurnTimer(roomId);
  sendGameStateToAll(roomId);
  broadcastRoomState(roomId);
  broadcastRoomList();

  console.log(`[MIDLEAVE] ${nickname} (${reason}) left room ${room.name}; ${result.botNickname} took the seat`);
  return { nickname, players: tableAtDeparture, ...result };
}

async function handleDesertion(roomId, playerId, reason = 'leave', options = {}) {
  const room = lobby.getRoom(roomId);
  if (!room || !room.game) return;

  const game = room.game;
  // Someone else already claimed this game terminally.
  if (game.deserted) return;

  // Rooms that allow mid-match seat changes don't end the match when one
  // person goes — a bot inherits the seat and everyone else plays on. This
  // sits ahead of the terminal claim below and covers EVERY route into
  // desertion (leave room, leave game, account deletion, 3 timeouts), not
  // just the deliberate walk-out: if plain "leave" still killed the table,
  // it would be the loophole that makes the whole option pointless.
  //
  // Safe to test before claiming the game: handOffSeatToBot's decision is
  // synchronous, so nothing can interleave between here and `deserted = true`
  // on the fall-through path.
  if (room.allowMidGameJoin && game.state !== 'game_end') {
    const handedOff = handOffSeatToBot(room, playerId, reason, options);
    if (handedOff) {
      // Recording is the same as any desertion — see the note there. Awaited
      // after the seat is already a bot's, so a DB blip can't strand the room.
      await recordDesertionAgainst(room, playerId, handedOff.nickname, options);
      // And leave a trace in their history. The match carries on, so no match
      // row will ever mention them: when it finally ends, the roster saved is
      // the one that finished, with a bot in this seat. Without this the
      // departure is invisible in the profile — only the bare leave_count
      // moves, and nothing says which game it came from.
      if (options.penalize !== false && handedOff.nickname) {
        try {
          await logMidGameLeave({
            nickname: handedOff.nickname,
            gameType: room.gameType,
            reason,
            roomName: room.name,
            players: handedOff.players,
          });
        } catch (e) {
          console.error(`[MIDLEAVE] history log failed for ${handedOff.nickname}:`, e);
        }
      }
      return;
    }
    // Fell through: they were the last human. A table of bots playing to an
    // empty room is not a match, so this ends it like a normal desertion.
  }

  // Claim the game terminally BEFORE any await/broadcast. This closes two
  // race windows:
  //  (a) a concurrent leave/timeout that also reaches handleDesertion bails at
  //      the `deserted` check above (its outer guard passed before we ran) —
  //      no double desertion save; and
  //  (b) an offloaded bot decision awaiting a worker can resolve mid-desertion
  //      while state is still 'playing' (we set state='game_end' only at the
  //      end, after the DB awaits). resultSaved claims the shared idempotency
  //      token so the normal saveGameResult can't also save, and the bot
  //      callback's `deserted` check stops it from applying a move at all.
  //      Prevents a single match being written twice (normal result + desertion
  //      draw), which would corrupt ranked stats / bans.
  // Nothing above this point awaits, so the seat-handoff test cannot widen
  // either window.
  game.deserted = true;
  game.resultSaved = true;
  const deserterNick = game.playerNames[playerId];
  releasePeerPending(deserterNick);

  // Broadcast desertion event
  broadcastGameEvent(roomId, {
    type: 'player_deserted',
    player: playerId,
    playerName: deserterNick,
    reason, // 'leave' or 'timeout'
  });

  // Increment leave_count + ranked ban. See recordDesertionAgainst for the
  // exclusions and for why a failure here must not abort the desertion.
  await recordDesertionAgainst(room, playerId, deserterNick, options);

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

/** Rewrite each player's titleName in a room state payload so it reflects
 *  the recipient's locale rather than the title-owner's locale. */
// A photo the viewer is allowed to see, or null. Both room state and game state
// carry the nickname as `name` (see GameRoom.getState) — reading `nickname`
// there silently matches nothing and the filter never fires.
// The key is the tail of every photo URL we build (`<base>/<userId>/<ts>.jpg`),
// so it can be recovered from the URL regardless of which base built it.
function photoKeyFromUrl(url) {
  const parts = String(url).split('/');
  return parts.length >= 2 ? parts.slice(-2).join('/') : null;
}

/**
 * Who currently holds the profile-privacy pass, and how far they set it to
 * reach. nickname -> { until: epoch ms | null, hidePhoto: boolean }.
 *
 * In memory because visiblePhoto runs for every seat of every broadcast — a
 * query there would be a query per player per state change. Written on login,
 * on purchase and on toggle; entries are re-checked against `until` on read, so
 * an expiry needs no sweeper to take effect.
 */
const profilePrivacy = new Map();

function setProfilePrivacyCache(nickname, { active, expiresAt, hidePhoto }) {
  if (!nickname) return;
  if (!active) {
    profilePrivacy.delete(nickname);
    return;
  }
  profilePrivacy.set(nickname, {
    until: expiresAt ? new Date(expiresAt).getTime() : null,
    hidePhoto: hidePhoto === true,
  });
}

function profilePrivacyOf(nickname) {
  const entry = profilePrivacy.get(nickname);
  if (!entry) return null;
  if (entry.until !== null && entry.until <= Date.now()) {
    profilePrivacy.delete(nickname);
    return null;
  }
  return entry;
}

/** Does this viewer get to see past `nickname`'s privacy? Self and friends do. */
function seesPrivateProfile(ws, nickname) {
  if (!ws?.nickname) return false;
  if (ws.nickname === nickname) return true;
  return ws.friends?.has(nickname) === true;
}

/** Records hidden from this viewer? */
function profileHiddenFrom(ws, nickname) {
  return !!profilePrivacyOf(nickname) && !seesPrivateProfile(ws, nickname);
}

/**
 * Titles this viewer reported, as `nickname\u0000title`. Keyed to the text, so
 * writing a different one shows again — same rule as photos.
 */
function titleReported(ws, nickname, titleName) {
  if (!titleName || !ws?.reportedTitles?.size) return false;
  return ws.reportedTitles.has(`${nickname}\u0000${titleName}`);
}

/**
 * Chat muted for this viewer, in this room only.
 *
 * Reporting abuse or spam should stop that person's chat from arriving — but
 * for this room, not forever. Forever is what blocking is for, and a report is
 * not a block.
 */
/** Room chat as this viewer should see it: muted senders dropped. */
function visibleChatHistory(ws, room) {
  let history = room.getChatHistory() || [];
  if (ws?.mutedChat?.get(room.id)?.size) {
    const muted = ws.mutedChat.get(room.id);
    history = history.filter((m) => !muted.has(m.sender ?? m.nickname));
  }
  // Each line carries the sender's avatar; blocked and reported ones drop out
  // for this viewer exactly as they do on a seat.
  return history.map((m) => (m.photoUrl
    ? { ...m, photoUrl: visiblePhoto(ws, m.sender ?? m.nickname, m.photoUrl) }
    : m));
}

function chatMutedFor(ws, roomId, sender) {
  if (!roomId || !ws?.mutedChat) return false;
  return ws.mutedChat.get(roomId)?.has(sender) === true;
}

function muteChatInRoom(ws, roomId, sender) {
  if (!roomId || !sender) return;
  ws.mutedChat ??= new Map();
  if (!ws.mutedChat.has(roomId)) ws.mutedChat.set(roomId, new Set());
  ws.mutedChat.get(roomId).add(sender);
}

function visiblePhoto(ws, nickname, url) {
  if (!url) return null;
  if (ws?.hiddenPhotos?.has(nickname)) return null;
  // Hide only the exact photo that was reported; a new upload shows again.
  if (ws?.reportedPhotoKeys?.size) {
    const key = photoKeyFromUrl(url);
    if (key && ws.reportedPhotoKeys.has(key)) return null;
  }
  // Privacy pass, and this holder chose to include the photo in it.
  const privacy = profilePrivacyOf(nickname);
  if (privacy?.hidePhoto && !seesPrivateProfile(ws, nickname)) return null;
  return url;
}

// The seat facts the game engines do not have. getStateForPlayer /
// getStateForSpectator only know ids and names; who is connected, whose turn
// timeouts are stacking up, which seats are bots, and each player's active
// profile photo all live on the room. Gathered once so a broadcast can reuse it
// for every recipient.
function roomSeatInfo(room) {
  const connected = {};
  const photoByPid = {};
  const isBotById = {};
  for (const p of room.players) {
    if (p === null) continue;
    connected[p.id] = p.connected !== false;
    if (p.photoUrl) photoByPid[p.id] = p.photoUrl;
    if (p.isBot) isBotById[p.id] = true;
  }
  return {
    connected,
    photoByPid,
    isBotById,
    timeouts: timeoutCounts[room.id] || {},
    // Photo included: the in-game spectator list is built from HERE, not from
    // GameRoom.getState(), so dropping it made the same list show faces in the
    // lobby and initials once a game was running. Filtered per viewer below,
    // the same way seats are.
    spectators: room.spectators.map((sp) => ({
      id: sp.id,
      nickname: sp.nickname,
      photoUrl: sp.photoUrl || null,
    })),
  };
}

// The part of the decoration that is identical for players and spectators.
// Photo filtering is per-viewer (blocked/reported users lose their avatar for
// that viewer only), so this runs once per socket, not once per broadcast.
function decorateSeats(ws, state, seats) {
  state.players = (state.players || []).map((p) => {
    const hideTitle = titleReported(ws, p.name, p.titleName);
    return {
      ...p,
      connected: seats.connected[p.id] !== false,
      timeoutCount: seats.timeouts[p.name] || 0,
      photoUrl: visiblePhoto(ws, p.name, seats.photoByPid[p.id]),
      isBot: !!seats.isBotById[p.id],
      ...(hideTitle ? { titleName: null, titleKey: null } : {}),
    };
  });
  state.spectators = seats.spectators.map((sp) => (
    sp.photoUrl
      ? { ...sp, photoUrl: visiblePhoto(ws, sp.nickname, sp.photoUrl) }
      : sp
  ));
  state.spectatorCount = seats.spectators.length;
  return state;
}

// Everything a player's game_state needs on top of the raw engine state.
//
// One implementation because six places send this message (reconnect /
// check-room, the two always-allow card-view shortcuts, card-view respond and
// revoke, and the periodic broadcast) and five of them had grown their own
// subset of the list. The visible result: approving a card-view request wiped
// every avatar off the approver's own board, because that path rebuilt the
// state and spliced back only turnDeadline and cardViewers.
function decoratePlayerState(room, ws, state, seats) {
  decorateSeats(ws, state, seats || roomSeatInfo(room));
  state.turnDeadline = room.turnDeadline;
  state.cardViewers = room.getViewersForPlayer(ws.playerId);
  return state;
}

// Same for a spectator payload. Spectators have no cards of their own, so there
// is no cardViewers list to attach.
//
// Seven places send this one (card-view request/respond/revoke, reconnect,
// check-room, spectate-join, and the broadcast) and six of them had the same
// decoration missing — a spectator's profile photos vanished the moment they
// asked to see someone's cards.
function decorateSpectatorState(room, ws, state, seats) {
  decorateSeats(ws, state, seats || roomSeatInfo(room));
  state.turnDeadline = room.turnDeadline;
  return state;
}

// Room state as this particular viewer should see it: titles in their locale,
// and no profile photo for anyone they blocked or reported. One pass, one
// clone — the broadcast is already per-socket, so this costs nothing extra.
function personalizeRoomState(state, ws) {
  if (!state || !Array.isArray(state.players)) return state;
  const locale = ws?.locale || 'ko';
  return {
    ...state,
    // Watchers get the same treatment as seats: someone you blocked or
    // reported must not have their photo turn up in the spectator list.
    spectators: Array.isArray(state.spectators)
      ? state.spectators.map((sp) => (
          sp && sp.photoUrl
            ? { ...sp, photoUrl: visiblePhoto(ws, sp.nickname, sp.photoUrl) }
            : sp
        ))
      : state.spectators,
    players: state.players.map((p) => {
      if (p === null) return null;
      const retitle = !!p.titleKey;
      // visiblePhoto, not a local blocked-only check: reports and the privacy
      // pass hide photos too, and the waiting room was applying neither — a
      // reported photo stayed on the seat until the game started.
      const photoUrl = p.photoUrl ? visiblePhoto(ws, p.name, p.photoUrl) : p.photoUrl;
      const unphoto = p.photoUrl !== photoUrl;
      const untitle = titleReported(ws, p.name, p.titleName);
      if (!retitle && !unphoto && !untitle) return p;
      const out = { ...p };
      if (retitle) out.titleName = localizeTitleName(p.titleKey, p.titleName, locale);
      if (unphoto) out.photoUrl = photoUrl;
      if (untitle) {
        out.titleName = null;
        out.titleKey = null;
      }
      return out;
    }),
  };
}

function broadcastRoomState(roomId) {
  const room = lobby.getRoom(roomId);
  if (!room) return;
  const roomState = room.getState();
  const sendLocalized = (ws) => {
    sendTo(ws, { type: 'room_state', room: personalizeRoomState(roomState, ws) });
  };
  // Send to players (skip null slots)
  for (const player of room.players) {
    if (player === null) continue;
    const ws = findWsByPlayerId(player.id);
    if (ws) sendLocalized(ws);
  }
  // Send to spectators
  for (const spectator of room.spectators) {
    const ws = findWsByPlayerId(spectator.id);
    if (ws) sendLocalized(ws);
  }
}

// Notify all connected participants and remove room
function closeRoom(roomId, messageType = 'room_closed') {
  const room = lobby.getRoom(roomId);
  releasePeerPendingForRoom(room);
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
  clearRoomTimers(roomId, room);
  lobby.removeRoom(roomId);
}

// Drop every timer keyed to a room. Shared by closeRoom and the drain
// migration path — both make the room disappear from this instance, so
// a surviving timer would fire against a room that no longer exists.
function clearRoomTimers(roomId, room = null) {
  if (autoReturnTimers[roomId]) {
    clearTimeout(autoReturnTimers[roomId]);
    delete autoReturnTimers[roomId];
  }
  if (trickEndTimers[roomId]) {
    clearTimeout(trickEndTimers[roomId]);
    delete trickEndTimers[roomId];
  }
  if (llAckBackupTimers[roomId]) {
    clearTimeout(llAckBackupTimers[roomId]);
    delete llAckBackupTimers[roomId];
  }
  if (turnTimers[roomId]) {
    clearTimeout(turnTimers[roomId]);
    delete turnTimers[roomId];
  }
  if (roundEndTimers[roomId]) {
    clearTimeout(roundEndTimers[roomId]);
    delete roundEndTimers[roomId];
  }
  if (resumeTimers[roomId]) {
    clearTimeout(resumeTimers[roomId]);
    delete resumeTimers[roomId];
  }
  Object.keys(waitingRoomTimers).forEach((key) => {
    if (!key.startsWith(`${roomId}_`)) return;
    clearTimeout(waitingRoomTimers[key]);
    delete waitingRoomTimers[key];
  });
  delete timeoutCounts[roomId];
  delete turnTimerPhases[roomId];
  delete turnTimerTargets[roomId];
  // Bot action timers (scheduleBotActions) live in global maps and were not
  // cleared above — drop them so the handle/entry doesn't leak after the room
  // is gone (the callback null-checks the room, but the entry would persist).
  if (pendingBotTimers[roomId]) {
    clearTimeout(pendingBotTimers[roomId]);
    delete pendingBotTimers[roomId];
  }
  delete pendingBotCheck[roomId];
  delete botDecisionInFlight[roomId];
  delete roomProgress[roomId];
  // Card-view request timers live on the room object; clear them too.
  if (room && room.cardRequestTimers) {
    for (const key of Object.keys(room.cardRequestTimers)) {
      clearTimeout(room.cardRequestTimers[key]);
    }
    room.cardRequestTimers = {};
  }
}

function removeRoomAndNotifySpectators(roomId) {
  closeRoom(roomId);
}

// Wire the filler-room manager to the pieces it needs. Injected rather than
// required the other way round: server.js boots the server on require, so the
// module cannot reach back into it.
fillerRooms.init({
  lobby,
  broadcastRoomState: (id) => broadcastRoomState(id),
  broadcastRoomList: () => broadcastRoomList(),
  sendGameStateToAll: (id) => sendGameStateToAll(id),
  broadcastGameEvent: (id, e) => broadcastGameEvent(id, e),
  playerStillNeedsToAct,
});

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
  room.addChatMessage(ws.nickname, ws.playerId, message, ws.photoUrl || null);

  const chatData = {
    type: 'chat_message',
    sender: ws.nickname,
    senderId: ws.playerId,
    message: message,
    timestamp: Date.now(),
  };

  // Users who blocked the sender (to filter them from the broadcast). This ran
  // a DB query on EVERY chat message; cache it on the socket with a short TTL.
  // Trade-off: a new block takes up to TTL to take effect in live chat.
  let blockedSet;
  const nowTs = Date.now();
  if (ws._blockedByCache && (nowTs - ws._blockedByCache.at) < 30000) {
    blockedSet = ws._blockedByCache.set;
  } else {
    let blockedBySender = [];
    try {
      const { pool } = require('./db/database');
      const { rows } = await pool.query(
        'SELECT blocker_nickname FROM tc_blocked_users WHERE blocked_nickname = $1',
        [ws.nickname]
      );
      blockedBySender = rows.map(r => r.blocker_nickname);
    } catch (e) { /* ignore - send to all on error */ }
    blockedSet = new Set(blockedBySender);
    ws._blockedByCache = { set: blockedSet, at: nowTs };
  }

  // The sender's avatar travels with the line. The client used to look the
  // nickname up in whatever roster was loaded, which works for the people at
  // the table and for nobody else — a spectator's messages, and messages from
  // someone who has since left, drew the default silhouette. Filtered per
  // viewer like every other photo, so a blocked or reported sender still
  // loses theirs.
  const senderPhoto = ws.photoUrl || null;
  const deliver = (target) => {
    if (!target || blockedSet.has(target.nickname)) return;
    // Reported for abuse/spam by this viewer, in this room.
    if (chatMutedFor(target, room.id, ws.nickname)) return;
    sendTo(target, senderPhoto
      ? { ...chatData, photoUrl: visiblePhoto(target, ws.nickname, senderPhoto) }
      : chatData);
  };
  room.getPlayerIds().forEach((playerId) => deliver(findWsByPlayerId(playerId)));
  room.getSpectatorIds().forEach((specId) => deliver(findWsByPlayerId(specId)));
}

// Is there an account behind this nickname?
//
// Names outlive accounts: an old season's ranking, a match row, a chat line all
// keep naming someone who has since deleted their account, and the profile
// popup opens on those names. Friending, blocking or reporting one of them
// writes a row nobody can ever act on — the report queue in particular fills
// with entries about a user the admin cannot find. Filler-room hosts count as
// present: they have no account row, but a player looking at one sees an
// ordinary opponent, so their block has to behave like an ordinary block.
async function accountExists(nickname) {
  if (!nickname) return false;
  if (fillerRooms.isFillerNickname(nickname)) return true;
  const { pool } = require('./db/database');
  const r = await pool.query(
    'SELECT 1 FROM tc_users WHERE nickname = $1 AND is_deleted IS NOT TRUE LIMIT 1',
    [nickname],
  );
  return r.rowCount > 0;
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
  if (!await accountExists(targetNickname)) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'user_not_found') });
    return;
  }
  const result = await blockUser(ws.nickname, targetNickname);
  if (result.success) ws.hiddenPhotos?.add(targetNickname);
  sendTo(ws, { type: 'block_result', success: result.success, nickname: targetNickname, blocked: true });
  // Repaint whatever they are looking at so the avatar goes now, not on the
  // next unrelated state change.
  if (ws.roomId) {
    broadcastRoomState(ws.roomId);
    if (lobby.getRoom(ws.roomId)?.game) sendGameStateToAll(ws.roomId);
  }
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
  if (result.success) {
    // Reports hide by photo key now, so unblocking can simply return the
    // nickname-level hide; any reported photo stays hidden through
    // reportedPhotoKeys regardless.
    ws.hiddenPhotos?.delete(targetNickname);
  }
  sendTo(ws, { type: 'block_result', success: result.success, nickname: targetNickname, blocked: false });
  if (ws.roomId) {
    broadcastRoomState(ws.roomId);
    if (lobby.getRoom(ws.roomId)?.game) sendGameStateToAll(ws.roomId);
  }
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
  // Cap length: reason is part of tc_reports' UNIQUE btree index (reporter,
  // reported, room, reason). A btree entry maxes ~2704 bytes, so an oversized
  // reason makes the INSERT throw and the report silently fail. 500 chars
  // (<=1500 bytes UTF-8) stays well under and matches the DM cap.
  const reason = String(data.reason || '').slice(0, 500);
  if (!targetNickname || targetNickname === ws.nickname) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'cannot_report') });
    return;
  }
  if (!await accountExists(targetNickname)) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'user_not_found') });
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
  // What the reporter picked, as a code — the visible reason is a localized
  // string and matching on it would break the moment someone reports in German.
  const reasonCode = ['photo', 'title', 'abuse', 'spam', 'nickname', 'gameplay', 'other']
    .includes(data.reasonCode) ? data.reasonCode : null;
  const result = await reportUser(
    ws.nickname,
    targetNickname,
    reason,
    ws.roomId || '',
    chatContext,
    reasonCode,
  );
  sendTo(ws, {
    type: 'report_result',
    success: result.success,
    message: resultMessage(result, ws.locale),
  });
  if (result.success) {
    // Hide exactly what was reported, and nothing else. Waiting for an admin to
    // look at the queue means the reporter keeps staring at the thing they just
    // objected to, possibly for hours — but a report about someone's chat is
    // not a reason to take their picture away.
    if (result.photoKey) ws.reportedPhotoKeys?.add(result.photoKey);
    if (result.titleText) {
      ws.reportedTitles?.add(`${targetNickname}\u0000${result.titleText}`);
    }
    // Abuse and spam are about what the person is saying: mute them here, in
    // this room. Muting them everywhere forever is blocking, which is its own
    // button right next to this one.
    if ((reasonCode === 'abuse' || reasonCode === 'spam') && ws.roomId) {
      muteChatInRoom(ws, ws.roomId, targetNickname);
    }
    if (ws.roomId) {
      broadcastRoomState(ws.roomId);
      if (lobby.getRoom(ws.roomId)?.game) sendGameStateToAll(ws.roomId);
    }
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

// Daily attendance state (7-day streak). Pure read; the client uses
// resetAtUtc to render the next-reset clock in device-local time.
async function handleGetAttendanceState(ws) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'attendance_state_result', success: false, message: t(ws.locale, 'login_required') });
    return;
  }
  const state = await getAttendanceState(ws.nickname);
  if (!state) {
    sendTo(ws, { type: 'attendance_state_result', success: false, message: 'state_failed' });
    return;
  }
  sendTo(ws, { type: 'attendance_state_result', success: true, ...state });
}

// Claim today's reward. Client gates this on a rewarded-ad completion;
// double-claim is impossible regardless (DB checks last_claim_date == today).
async function handleClaimAttendance(ws) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'attendance_claim_result', success: false, message: t(ws.locale, 'login_required') });
    return;
  }
  const r = await claimAttendance(ws.nickname);
  if (!r.success) {
    sendTo(ws, { type: 'attendance_claim_result', success: false, reason: r.reason, message: r.message || r.reason });
    return;
  }
  // Echo a refreshed state so the client can update UI in one round-trip.
  const state = await getAttendanceState(ws.nickname);
  sendTo(ws, {
    type: 'attendance_claim_result',
    success: true,
    goldGranted: r.goldGranted,
    newStreak: r.newStreak,
    newGold: r.newGold,
    state: state || null,
  });
}

function normalizePlatform(p) {
  if (p === 'ios' || p === 'android') return p;
  return null;
}

// Active gold products for the client's platform. On iOS/Android the store
// owns the price and the client resolves it at runtime — we only expose which
// product_ids are live and how much gold each grants. price_krw rides along
// for the web client, which has no store to ask (see handleGetBankDepositInfo).
async function handleGetGoldProducts(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'gold_products_result', success: false, message: t(ws.locale, 'login_required') });
    return;
  }
  const platform = normalizePlatform(data?.platform) || 'both';
  const result = await getActiveGoldProducts(platform);
  sendTo(ws, { type: 'gold_products_result', ...result });
}

// ---------------------------------------------------------------------------
// Bank transfer (web only)
//
// There is no PG behind this and no automation: the player transfers won to a
// bank account, taps "deposit sent", and an admin confirms the incoming money
// by eye and grants the gold with the existing admin_adjust_gold tool. This
// handler's whole job is to get the request in front of that admin.
//
// WEB ONLY, and it has to stay that way. Apple and Google both require
// in-app digital goods to go through their own billing; shipping a bank
// account inside the mobile build is a review rejection at best. The client
// gates the UI on kIsWeb, and the account details only ever leave the server
// through this handler.
//
// The account itself lives in tc_config under `bank_deposit` rather than in
// code, so it can be set (and taken down) from backstage without a deploy:
//   {"enabled":true,"bank":"카카오뱅크","account":"3333-01-1234567",
//    "holder":"홍길동","note":"실제 입금하신 분 성함을 정확히 입력해 주세요"}
// ---------------------------------------------------------------------------

async function readBankDepositConfig() {
  try {
    const raw = await getConfig('bank_deposit');
    if (!raw) return null;
    const cfg = JSON.parse(raw);
    if (!cfg || cfg.enabled !== true) return null;
    if (!cfg.bank || !cfg.account) return null;
    // Support channel link. Only https is passed through: this string is
    // handed to the client to open, and a javascript:/data: URL from a
    // mistyped config field should not be openable.
    const rawChannel = String(cfg.channelUrl || '').trim();
    const channelUrl = rawChannel.startsWith('https://')
      ? rawChannel.slice(0, 200)
      : '';
    return {
      bank: String(cfg.bank).slice(0, 40),
      account: String(cfg.account).slice(0, 60),
      holder: String(cfg.holder || '').slice(0, 40),
      note: String(cfg.note || '').slice(0, 300),
      channelUrl,
    };
  } catch (err) {
    // A malformed value must read as "no bank transfer configured", never as
    // a crash on the shop screen.
    console.error('bank_deposit config parse error:', err);
    return null;
  }
}

async function handleGetBankDepositInfo(ws) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'bank_deposit_info', enabled: false });
    return;
  }
  const cfg = await readBankDepositConfig();
  if (!cfg) {
    sendTo(ws, { type: 'bank_deposit_info', enabled: false });
    return;
  }
  sendTo(ws, { type: 'bank_deposit_info', enabled: true, ...cfg });
}

// One pending notification per player at a time. Tapping the button twice
// shouldn't buzz the admin's phone twice, and the admin has to reconcile each
// one against a bank statement by hand.
const bankDepositCooldown = new Map(); // nickname -> timestamp
const BANK_DEPOSIT_COOLDOWN_MS = 60 * 1000;

async function handleRequestBankDeposit(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'bank_deposit_result', success: false, message: t(ws.locale, 'login_required') });
    return;
  }
  const cfg = await readBankDepositConfig();
  if (!cfg) {
    sendTo(ws, { type: 'bank_deposit_result', success: false, message: t(ws.locale, 'bank_deposit_unavailable') });
    return;
  }

  const last = bankDepositCooldown.get(ws.nickname) || 0;
  if (Date.now() - last < BANK_DEPOSIT_COOLDOWN_MS) {
    sendTo(ws, { type: 'bank_deposit_result', success: false, message: t(ws.locale, 'bank_deposit_too_soon') });
    return;
  }

  // The amount comes from the product row, never from the client — the same
  // rule the store path follows. A client that asks for gold5 gets gold5's
  // price on the admin's screen no matter what it claims to have paid.
  const productId = String(data?.productId || '').slice(0, 80);
  const product = await getGoldProductByProductId(productId);
  if (!product || !product.is_active) {
    sendTo(ws, { type: 'bank_deposit_result', success: false, message: t(ws.locale, 'bank_deposit_bad_product') });
    return;
  }
  const depositor = String(data?.depositor || '').trim().slice(0, 40);
  if (!depositor) {
    sendTo(ws, { type: 'bank_deposit_result', success: false, message: t(ws.locale, 'bank_deposit_need_name') });
    return;
  }

  // One open claim at a time. Two pending rows for the same player is an
  // invitation to approve both for a single transfer.
  if (await countPendingBankDeposits(ws.nickname) > 0) {
    sendTo(ws, { type: 'bank_deposit_result', success: false, message: t(ws.locale, 'bank_deposit_pending_exists') });
    return;
  }

  const price = Number(product.price_krw) || 0;
  const gold = (Number(product.gold_amount) || 0) + (Number(product.bonus_gold) || 0);
  bankDepositCooldown.set(ws.nickname, Date.now());

  // Queued in tc_bank_deposits, which backstage renders as an approve/reject
  // list. It used to be filed as an inquiry — readable, but the admin then had
  // to retype the amount into the manual gold tool, and the payout could drift
  // from what was requested.
  const created = await createBankDeposit({
    nickname: ws.nickname,
    productId,
    priceKrw: price,
    goldAmount: gold,
    depositor,
  });
  if (!created.success) {
    sendTo(ws, { type: 'bank_deposit_result', success: false, message: t(ws.locale, 'bank_deposit_unavailable') });
    return;
  }

  await notifyAdminUsers(
    'payment',
    '💰 입금 확인 요청',
    `${ws.nickname} 님 · ₩${price.toLocaleString()} · 입금자 ${depositor}`,
  ).catch((err) => console.error('bank deposit admin notify failed:', err));

  console.log(`[BANK] deposit claim: ${ws.nickname} ${productId} ₩${price} by "${depositor}"`);
  sendTo(ws, { type: 'bank_deposit_result', success: true, message: t(ws.locale, 'bank_deposit_submitted') });
}

// Verify a store purchase and grant gold. The client never tells us the gold
// amount or price — we look the product up server-side and trust only the
// store's verification response. Idempotent on the store transaction id.
async function handleVerifyIapPurchase(ws, data) {
  const platform = normalizePlatform(data?.platform);
  const productId = typeof data?.productId === 'string' ? data.productId : null;
  const verificationData = typeof data?.verificationData === 'string' ? data.verificationData : null;
  // Optional: the specific store transaction the client is currently
  // delivering. When present we grant ONLY that one instead of every
  // accumulated transaction in the (Apple) receipt — this bounds the
  // cross-account "sweep" when one Apple ID is shared by several game
  // nicknames. Absent on older clients → fall back to grant-all.
  const claimedTxnId = typeof data?.transactionId === 'string' && data.transactionId
    ? data.transactionId : null;
  // Echoed back in iap_purchase_result so the client matches THIS request's
  // response (a late post-timeout reply must not resolve another purchase).
  const requestId = typeof data?.requestId === 'string' ? data.requestId : null;

  // A purchase should be "finished" on the store (consumable consumed /
  // transaction removed) ONLY when it's resolved for good — granted, or the
  // store itself says the receipt is invalid. Transient failures (our infra,
  // login timing, product temporarily inactive) must stay UNFINISHED so the
  // plugin re-delivers them on the next launch and we retry — otherwise a
  // consumable bought while the server is down is lost forever (no restore for
  // consumables). These store-says-bad reasons are the only safe "drop it".
  const PERMANENT = (reason) => {
    if (!reason) return false;
    return reason === 'bundle_mismatch'
      || reason === 'product_not_in_receipt'
      || reason === 'purchase_not_found'
      || reason === 'missing_receipt'
      || reason === 'missing_purchase_token'
      || reason === 'missing_product_id'
      // StoreKit 2 terminal verdicts — the server can NEVER turn these into a
      // grant, so the client must finish the transaction or it re-delivers
      // every launch forever. (sk2_jws_* is deliberately NOT here: a JWS that
      // fails our chain check may be our verifier bug — keep it retryable so a
      // server-side fix can still recover the purchase on a later launch.)
      || reason === 'revoked'
      || reason === 'product_mismatch'
      || reason === 'no_transaction_id'
      || /^apple_status_/.test(reason)
      || /^purchase_state_/.test(reason);
  };

  // Every exit path logs an attempt row. logIapAttempt is best-effort and
  // never throws, so this can't break the purchase flow.
  const fail = async (outcome, reason, msgKey, extra = {}) => {
    await logIapAttempt({
      nickname: ws.nickname || null,
      platform,
      productId,
      environment: extra.environment || null,
      outcome,
      reason,
      transactionId: extra.transactionId || null,
      rawPayload: extra.rawPayload || null,
    });
    sendTo(ws, {
      type: 'iap_purchase_result',
      success: false,
      requestId,
      // Tell the client whether to finish the store transaction or keep it
      // pending for retry. Default to "keep" (false) for anything not clearly
      // permanent — never risk silently dropping a paid consumable.
      finish: PERMANENT(reason),
      message: t(ws.locale, msgKey),
    });
  };

  if (!ws.nickname) {
    return fail('rejected', 'login_required', 'login_required');
  }
  if (!platform || !productId || !verificationData) {
    return fail('rejected', 'invalid_request', 'iap_invalid_request');
  }

  // Product must exist and be active, on a platform that matches.
  const product = await getGoldProductByProductId(productId);
  if (!product || product.is_active !== true) {
    return fail('rejected', 'product_unavailable', 'iap_product_unavailable');
  }
  if (product.platform !== 'both' && product.platform !== platform) {
    return fail('rejected', 'product_platform_mismatch', 'iap_product_unavailable');
  }

  const verifier = platform === 'ios' ? verifyApple : verifyGoogle;
  let v;
  try {
    v = await verifier(verificationData, productId);
  } catch (err) {
    console.error('[IAP] verify threw:', err);
    return fail('error', 'verify_threw', 'iap_verify_failed');
  }
  if (!v || !v.valid) {
    console.warn(`[IAP] verify rejected nickname=${ws.nickname} product=${productId} reason=${v && v.reason}`);
    return fail('rejected', (v && v.reason) || 'verify_invalid', 'iap_verify_failed', {
      environment: v && v.environment,
      rawPayload: v && v.raw,
    });
  }

  const environment = v.environment === 'sandbox' ? 'sandbox' : 'production';

  // Account binding (anti receipt-replay): the client stamps the purchase
  // with the server-issued bindingToken = bindingUuid(ws.userId) — the
  // IMMUTABLE tc_users.id, not the mutable nickname — carried as
  // appAccountToken on iOS (StoreKit 2 JWS) and obfuscatedAccountId on
  // Android. Because the key is immutable and stable across renames/sessions,
  // benign mismatches are near-zero, so we REJECT on mismatch: do NOT grant,
  // do NOT record the transaction_id, and tell the client NOT to finish
  // (finish=false via the non-permanent 'binding_mismatch' reason). A thief
  // replaying a victim's receipt onto their own account is denied and earns
  // nothing; the legitimate owner's own device matches and is granted
  // normally on its later verify (the txn was never recorded, so recovery is
  // not blocked). Logged as outcome 'flagged' for fraud review. accountId
  // absent (legacy / older edge) → check skipped, grant proceeds.
  if (v.accountId && ws.userId != null) {
    const expected = bindingUuid(String(ws.userId));
    if (String(v.accountId).toLowerCase() !== String(expected).toLowerCase()) {
      console.warn(`[IAP] account binding mismatch (rejected) nickname=${ws.nickname} product=${productId}`);
      return fail('flagged', 'binding_mismatch', 'iap_verify_failed', {
        environment,
        rawPayload: { expected: 'bindingUuid(userId)', got: v.accountId },
      });
    }
  } else if (!v.accountId) {
    // Unbound purchase (legacy client / receipt carries no appAccountToken).
    // The binding check is the only defense against a stolen receipt being
    // redirected to another account, so an unbound grant can't be vouched for.
    // We still grant (idempotency stops double-credit) to avoid under-crediting
    // real legacy buyers, but flag it so it surfaces in fraud review. HARDEN:
    // once a min app version that always stamps bindingToken is enforced, turn
    // this into a hard reject (return fail('flagged','binding_required',...)).
    console.warn(`[IAP] unbound purchase granted (no accountId) nickname=${ws.nickname} product=${productId} platform=${platform} env=${environment}`);
  }

  const goldTotal = (parseInt(product.gold_amount, 10) || 0) + (parseInt(product.bonus_gold, 10) || 0);
  // "ko|en|de" so the gold-history row shows a localized product name instead
  // of the raw product id (client resolves via localizeGoldTitle, same as
  // shop_purchase). Empty locale slots fall back to ko client-side.
  const historyTitle = [
    product.label_ko, product.label_en, product.label_de,
  ].map((s) => (s || '').trim()).join('|');

  // Grant EVERY transaction in the receipt, not just the latest. Apple receipts
  // accumulate purchases; if an earlier verify failed and the user bought
  // again, both are here and both must be credited. grantIapGold is idempotent
  // on transaction_id, so already-granted (and refunded) ones are no-ops.
  let txns = Array.isArray(v.transactions) ? v.transactions : [];
  if (txns.length === 0) {
    return fail('error', 'no_transactions', 'iap_verify_failed', { environment });
  }
  // If the client named the exact transaction it's settling and that
  // transaction is present in the verified receipt, grant ONLY that one.
  // (If it's not found — id-format edge — keep grant-all so we never
  // under-credit a real purchase.)
  if (claimedTxnId) {
    const only = txns.filter((t) => t.transactionId === claimedTxnId);
    if (only.length > 0) txns = only;
  }

  let totalNewGold = 0;
  let anyNewlyGranted = false;
  let latestGold = null;
  let grantError = null;
  for (const tx of txns) {
    const grant = await grantIapGold({
      nickname: ws.nickname,
      productId,
      platform,
      transactionId: tx.transactionId,
      environment,
      goldTotal,
      rawPayload: tx.raw,
      historyTitle,
    });
    if (!grant.success) {
      grantError = grant;
      await logIapAttempt({
        nickname: ws.nickname, platform, productId, environment,
        outcome: 'error', reason: 'grant_failed',
        transactionId: tx.transactionId, rawPayload: tx.raw,
      });
      continue;
    }
    if (grant.newGold != null) latestGold = grant.newGold;
    if (!grant.alreadyGranted) {
      anyNewlyGranted = true;
      totalNewGold += goldTotal;
    }
    await logIapAttempt({
      nickname: ws.nickname, platform, productId, environment,
      outcome: grant.alreadyGranted ? 'already_granted' : 'granted',
      reason: null, transactionId: tx.transactionId, rawPayload: tx.raw,
    });
  }

  // Every transaction failed to grant (e.g. DB error) — surface as failure so
  // the client can retry; nothing was credited.
  if (grantError && !anyNewlyGranted && latestGold == null) {
    return fail('error', 'grant_failed', 'iap_grant_failed', { environment });
  }

  sendTo(ws, {
    type: 'iap_purchase_result',
    success: true,
    requestId,
    finish: true, // resolved for good — client may finish the store txn
    alreadyGranted: !anyNewlyGranted,
    goldGranted: totalNewGold,
    newGold: latestGold,
    productId,
  });

  // Notify opted-in admins on a genuinely NEW grant (skip idempotent
  // re-verifies so duplicate purchaseStream emissions don't double-alert).
  if (anyNewlyGranted) {
    const label = (product.label_ko && product.label_ko.trim()) || productId;
    const envTag = environment === 'sandbox' ? ' [샌드박스]' : '';
    // Money first — how much came in is the thing you want at a glance; the
    // gold is an implementation detail of what they got for it.
    //
    // Marked 정가 rather than presented as what they actually paid, because we
    // don't know that: the store owns the real price, and a foreign-currency
    // buyer, a store promo or local tax all move it. price_krw is the KRW list
    // price an admin entered. It is also BEFORE the store's cut, so it is not
    // revenue either.
    const priceKrw = Number(product.price_krw) || 0;
    const priceTag = priceKrw > 0
      ? `₩${priceKrw.toLocaleString()} (정가)`
      : '가격 미설정';
    notifyAdminUsers(
      'payment',
      '💰 결제 발생',
      `${ws.nickname} 님 · ${label} · ${priceTag} · +${totalNewGold.toLocaleString()}G (${platform})${envTag}`,
    ).catch(() => {});
  }
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
    iap_purchase: '골드 충전', iap_refund: '결제 환불',
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
    iap_purchase: 'Gold Top-up', iap_refund: 'Purchase Refund',
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
    iap_purchase: 'Gold-Aufladung', iap_refund: 'Kauf-Rückerstattung',
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

// onRefunded callback for autoRefundByTransaction: alerts opted-in admins when
// a store (Apple/Google) refund/cancel is applied to a user's grant. Only
// fires on a NEW refund (idempotent re-detection won't call this).
async function notifyAdminRefund({ nickname, productId, goldGranted, source }) {
  // Same 정가 caveat as the purchase notice: this is the KRW list price an
  // admin entered, not what the buyer was actually charged or refunded — the
  // store owns both numbers. Shown anyway because "how big was this one" is
  // the first thing you want from a refund alert, and the gold figure only
  // answers it if you happen to know the product.
  let priceTag = '';
  try {
    const product = await getGoldProductByProductId(productId);
    const priceKrw = Number(product?.price_krw) || 0;
    if (priceKrw > 0) priceTag = ` · ₩${priceKrw.toLocaleString()} (정가)`;
  } catch {
    // A lookup failure must not swallow the alert — send it without the price.
  }
  return notifyAdminUsers(
    'payment',
    '↩️ 결제 취소/환불',
    `${nickname || '?'} 님 · ${productId}${priceTag}`
      + ` · -${Number(goldGranted || 0).toLocaleString()}G 회수 (${source || 'store'})`,
  ).catch(() => {});
}

async function handleGetAdminDashboard(ws) {
  if (!await ensureAdmin(ws, 'admin_dashboard_result')) return;
  const stats = await getDashboardStats();
  sendTo(ws, {
    type: 'admin_dashboard_result',
    success: true,
    dashboard: {
      totalUsers: stats.totalUsers || 0,
      todayPaidCount: stats.todayPaidCount || 0,
      todayRefundCount: stats.todayRefundCount || 0,
      todayNetRevenue: stats.todayNetRevenue || 0,
      pendingInquiries: stats.pendingInquiries || 0,
      pendingReports: stats.pendingReports || 0,
      totalInquiries: stats.totalInquiries || 0,
      totalReports: stats.totalReports || 0,
      newUsersToday: stats.newUsersToday || 0,
      activeUsers7d: stats.activeUsers7d || 0,
      activeUsers: getActiveUsersSnapshot().length,
      todayGames: stats.todayGames || 0,
      todayRankedGames: stats.rankedMatchesToday || 0,
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
  const result = await getUsers(search, page, limit, { sort: data?.sort || 'login_desc', excludeDeleted: true });
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
      const pushAdminPayment = result.user?.push_admin_payment !== false;
      client.pushAdminInquiry = pushAdminInquiry;
      client.pushAdminReport = pushAdminReport;
      client.pushAdminPayment = pushAdminPayment;
      sendTo(client, {
        type: 'admin_status_changed',
        isAdmin,
        pushAdminInquiry,
        pushAdminReport,
        pushAdminPayment,
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

async function handleGetAdminTodayMatches(ws, data) {
  if (!await ensureAdmin(ws, 'admin_today_matches_result')) return;
  const ranked = data?.ranked === true ? true : data?.ranked === false ? false : null;
  const limit = typeof data?.limit === 'number' ? data.limit : 100;
  const result = await getTodayMatches({ ranked, limit });
  sendTo(ws, {
    type: 'admin_today_matches_result',
    success: true,
    ranked,
    rows: result.rows,
  });
}

async function handleGetAdminTodayPayments(ws, data) {
  if (!await ensureAdmin(ws, 'admin_today_payments_result')) return;
  const limit = typeof data?.limit === 'number' ? data.limit : 100;
  const result = await getTodayPayments({ limit });
  sendTo(ws, {
    type: 'admin_today_payments_result',
    success: true,
    rows: result.rows,
  });
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
  if (result.success && Array.isArray(result.items)) {
    if (!clientSupportsMighty(ws)) {
      result.items = result.items.filter((item) => !itemRequiresV230Client(item.item_key));
    }
    if (!clientSupportsNewBanners(ws)) {
      result.items = result.items.filter((item) => !itemRequiresNewBannerClient(item.item_key));
    }
    if (!clientSupportsProfilePhoto(ws)) {
      // Older clients have no upload UI — hide the profile-photo shop items.
      result.items = result.items.filter((item) => item.effect_type !== 'profile_photo');
    }
    if (!clientSupportsProfilePrivate(ws)) {
      // No redacted popup and no reach toggle on old clients: they would hold a
      // pass they cannot see the state of, or configure.
      result.items = result.items.filter((item) => item.effect_type !== 'profile_private');
    }
    if (!clientSupportsCustomTitle(ws)) {
      // An old client has no editor, so the pass would run its 7 days with no
      // way to write the title it paid for.
      result.items = result.items.filter((item) => item.effect_type !== 'custom_title');
    }
  }
  sendTo(ws, { type: 'shop_items_result', ...result });
}

// Visual catalog: every shop item that carries a metadata.visual config so
// the client can render banners/titles/themes with the admin-edited
// gradient angle + stops (not its own hardcoded copy). Returned regardless
// of category, purchasable, or season flag.
async function handleGetVisualCatalog(ws) {
  const result = await getVisualCatalog();
  sendTo(ws, { type: 'visual_catalog_result', ...result });
}

// Inventory handler
async function handleGetInventory(ws) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'inventory_result', success: false, message: t(ws.locale, 'login_required') });
    return;
  }
  const result = await getUserItems(ws.nickname);
  if (result.success && Array.isArray(result.items)) {
    if (!clientSupportsMighty(ws)) {
      result.items = result.items.filter((item) => !itemRequiresV230Client(item.item_key));
    }
    if (!clientSupportsNewBanners(ws)) {
      result.items = result.items.filter((item) => !itemRequiresNewBannerClient(item.item_key));
    }
  }
  sendTo(ws, { type: 'inventory_result', ...result });
}

async function handleBuyItem(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'purchase_result', success: false, message: t(ws.locale, 'login_required') });
    return;
  }
  const itemKey = data.itemKey;
  if (itemRequiresV230Client(itemKey) && !clientSupportsMighty(ws)) {
    sendTo(ws, {
      type: 'purchase_result',
      success: false,
      itemKey,
      message: t(ws.locale, 'mighty_update_required'),
    });
    return;
  }
  if (itemRequiresNewBannerClient(itemKey) && !clientSupportsNewBanners(ws)) {
    sendTo(ws, {
      type: 'purchase_result',
      success: false,
      itemKey,
      message: t(ws.locale, 'banner_update_required'),
    });
    return;
  }
  // Profile-photo items need the 2.8.0 upload UI; the shop list already hides
  // them from older clients, so this only blocks a stale/tampered client from
  // spending gold on an item it can't use.
  if (typeof itemKey === 'string' && itemKey.startsWith('profile_photo')) {
    if (!clientSupportsProfilePhoto(ws)) {
      sendTo(ws, {
        type: 'purchase_result',
        success: false,
        itemKey,
        message: t(ws.locale, 'banner_update_required'),
      });
      return;
    }
    // Storage down / unconfigured: the entitlement would tick with no way to
    // upload. Refuse rather than take gold for an item that can't be used.
    if (!minioClient.isEnabled()) {
      sendTo(ws, {
        type: 'purchase_result',
        success: false,
        itemKey,
        message: t(ws.locale, 'profile_photo_storage_unavailable'),
      });
      return;
    }
  }
  // Same reason as the shop filter above; this only stops a stale or tampered
  // client from spending gold on a pass it cannot manage.
  if (typeof itemKey === 'string' && itemKey.startsWith('profile_private')
      && !clientSupportsProfilePrivate(ws)) {
    sendTo(ws, {
      type: 'purchase_result',
      success: false,
      itemKey,
      message: t(ws.locale, 'banner_update_required'),
    });
    return;
  }
  if (typeof itemKey === 'string' && itemKey.startsWith('custom_title')
      && !clientSupportsCustomTitle(ws)) {
    sendTo(ws, {
      type: 'purchase_result',
      success: false,
      itemKey,
      message: t(ws.locale, 'banner_update_required'),
    });
    return;
  }
  const result = await buyItem(ws.nickname, itemKey);
  // The visibility cache is what every broadcast reads; refresh it here so the
  // pass takes effect on this purchase, not on the next login.
  if (result?.success && typeof itemKey === 'string'
      && itemKey.startsWith('profile_private')) {
    await refreshProfilePrivacy(ws.nickname);
  }
  sendTo(ws, { type: 'purchase_result', itemKey, ...result });
}

async function handleEquipItem(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'equip_result', success: false, message: t(ws.locale, 'login_required') });
    return;
  }
  const itemKey = data.itemKey;
  const result = await equipItem(ws.nickname, itemKey, ws.locale || 'ko');
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
  if (result.success && result.category === 'banner') {
    result.bannerKey = itemKey;
    ws.bannerKey = itemKey;
    // Reflect the change in any room the user is already sitting in so the
    // waiting-room slot's gradient updates without requiring a re-join.
    if (ws.roomId) {
      const room = lobby.getRoom(ws.roomId);
      if (room) {
        const p = room.players.find(p => p !== null && p.id === ws.playerId);
        if (p) {
          p.bannerKey = itemKey;
        }
        broadcastRoomState(ws.roomId);
      }
    }
  }
  sendTo(ws, { type: 'equip_result', ...result });
}

/**
 * Take off an equipped cosmetic.
 *
 * Mirrors handleEquipItem's after-effects: the socket's copy of the key, the
 * seat the user is already sitting in, and the room broadcast — otherwise the
 * banner stays on the slot until they leave the room.
 */
/**
 * Write (or rewrite) the user's own title.
 *
 * Validation is server-side and final — the client's field limit is a
 * convenience, not a guarantee, and this is the one path that puts unreviewed
 * text next to a nickname on everyone else's screen.
 */
async function handleSetCustomTitle(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'custom_title_result', success: false, message: t(ws.locale, 'login_required') });
    return;
  }
  const check = validateCustomTitle(data?.text, data?.color?.toString() || '');
  if (!check.ok) {
    sendTo(ws, {
      type: 'custom_title_result',
      success: false,
      reason: check.reason,
      message: t(ws.locale, check.reason),
    });
    return;
  }
  const result = await setCustomTitle(ws.nickname, check.text, check.color);
  if (!result.success) {
    sendTo(ws, {
      type: 'custom_title_result',
      success: false,
      message: t(ws.locale, result.messageKey || 'db_update_failed'),
    });
    return;
  }
  // Same after-effects as equipping a catalog title: the socket's copy, the
  // seat the user is already in, and the room broadcast.
  ws.titleKey = result.titleKey;
  ws.titleName = result.titleName;
  if (ws.roomId) {
    const room = lobby.getRoom(ws.roomId);
    if (room) {
      const p = room.players.find((p) => p !== null && p.id === ws.playerId);
      if (p) {
        p.titleKey = result.titleKey;
        p.titleName = result.titleName;
      }
      broadcastRoomState(ws.roomId);
    }
  }
  sendTo(ws, {
    type: 'custom_title_result',
    success: true,
    titleKey: result.titleKey,
    titleName: result.titleName,
    color: result.color,
  });
}

async function handleUnequipItem(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'equip_result', success: false, message: t(ws.locale, 'login_required') });
    return;
  }
  const category = data?.category?.toString() || '';
  const result = await unequipCategory(ws.nickname, category);
  if (result.success) {
    if (category === 'title') {
      ws.titleKey = null;
      ws.titleName = null;
    }
    if (category === 'banner') ws.bannerKey = null;
    if (ws.roomId) {
      const room = lobby.getRoom(ws.roomId);
      if (room) {
        const p = room.players.find((p) => p !== null && p.id === ws.playerId);
        if (p) {
          if (category === 'title') {
            p.titleKey = null;
            p.titleName = null;
          }
          if (category === 'banner') p.bannerKey = null;
        }
        broadcastRoomState(ws.roomId);
      }
    }
  }
  sendTo(ws, {
    type: 'equip_result',
    unequipped: true,
    category,
    ...result,
    message: result.success ? undefined : t(ws.locale, result.messageKey || 'db_equip_error'),
  });
}

async function handleUseItem(ws, data) {
  if (!ws.nickname) {
    sendTo(ws, { type: 'use_item_result', success: false, message: t(ws.locale, 'login_required') });
    return;
  }
  const itemKey = data.itemKey;
  if (itemRequiresV230Client(itemKey) && !clientSupportsMighty(ws)) {
    sendTo(ws, {
      type: 'use_item_result',
      success: false,
      message: t(ws.locale, 'mighty_update_required'),
    });
    return;
  }
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
  const category = data.category;
  // Cap lengths — tc_inquiries.title/content are unbounded TEXT; clamp to keep
  // storage sane and avoid oversized payloads (client frames allow up to 64KB).
  const title = String(data.title || '').slice(0, 120);
  const content = String(data.content || '').slice(0, 4000);
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
  if (!await accountExists(targetNickname)) {
    sendTo(ws, { type: 'error', message: t(ws.locale, 'user_not_found') });
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
/**
 * Repaint both sides' rooms after a friendship changes.
 *
 * Photo visibility depends on the friend relation, and room/game payloads are
 * pushed on change — becoming friends is not a change either room knows about,
 * so without this the new friend's photo stays hidden (default avatar) until
 * something unrelated happens to trigger a broadcast.
 */
function repaintRoomsFor(...sockets) {
  const rooms = new Set();
  for (const sock of sockets) {
    if (sock?.roomId) rooms.add(sock.roomId);
  }
  for (const roomId of rooms) {
    broadcastRoomState(roomId);
    if (lobby.getRoom(roomId)?.game) sendGameStateToAll(roomId);
  }
}

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
    // Both cached friend sets move now, not on next login: a privacy pass must
    // open up the moment the friendship exists, in both directions.
    ws.friends?.add(nickname);
    const requesterWs = findWsByNickname(nickname);
    if (requesterWs) {
      requesterWs.friends?.add(ws.nickname);
      sendTo(requesterWs, { type: 'friend_request_accepted', nickname: ws.nickname });
    }
    repaintRoomsFor(ws, requesterWs);
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
    ws.friends?.delete(nickname);
    const otherWs = findWsByNickname(nickname);
    if (otherWs) {
      otherWs.friends?.delete(ws.nickname);
      sendTo(otherWs, { type: 'friend_removed', nickname: ws.nickname, success: true });
    }
    // Same in reverse: a privacy-pass holder's photo has to go back to hidden.
    repaintRoomsFor(ws, otherWs);
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
  const found = await searchUsers(query, ws.nickname, ws.locale || 'ko');
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
  const users = found.map((u) => {
    const nick = u.nickname;
    let friendStatus = 'none';
    if (friendsList.includes(nick)) friendStatus = 'friend';
    else if (pendingIncoming.includes(nick)) friendStatus = 'pending_incoming';
    else if (pendingOutgoing.includes(nick)) friendStatus = 'pending_outgoing';
    // A search hit is a profile, so it obeys the same rules the profile popup
    // does: a private account shows who they are (you still have to be able to
    // find and add them) but not how they have been doing, and anything this
    // viewer has reported stays gone.
    const hidden = (u.hasProfilePrivate || !!profilePrivacyOf(nick))
      && !seesPrivateProfile(ws, nick);
    const hideTitle = titleReported(ws, nick, u.titleName);
    let photo = visiblePhoto(ws, nick, profilePhotoUrlFrom(u));
    // visiblePhoto only knows the cache, which is blank for anyone who has not
    // logged in since the server started — most search hits.
    if (photo && hidden && u.profilePrivateHidePhoto) photo = null;
    return {
      nickname: nick,
      friendStatus,
      isPrivate: hidden,
      level: hidden ? null : u.level,
      bannerKey: u.bannerKey,
      titleKey: hideTitle ? null : u.titleKey,
      titleName: hideTitle ? null : u.titleName,
      photoUrl: photo,
    };
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
  // Friendship / block / chat-ban lookups are independent — run in parallel,
  // then apply the checks in priority order.
  const [friendsList, blockedList, blockedByTarget, chatBan] = await Promise.all([
    getFriends(ws.nickname),
    getBlockedUsers(ws.nickname),
    getBlockedUsers(targetNickname),
    getChatBan(ws.nickname),
  ]);
  if (!friendsList.includes(targetNickname)) {
    sendTo(ws, { type: 'dm_error', message: t(ws.locale, 'dm_friends_only') });
    return;
  }
  if (blockedList.includes(targetNickname) || blockedByTarget.includes(ws.nickname)) {
    sendTo(ws, { type: 'dm_error', message: t(ws.locale, 'dm_blocked') });
    return;
  }
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
    ws.send(JSON.stringify(data), { compress: false });
  }
}
