'use strict';

/**
 * Support-inquiry photo attachments: upload tokens, the per-user daily cap and
 * the check that a key a client submits is one of its own uploads.
 *
 * Kept out of server.js so it can be tested without a socket, a DB or MinIO.
 * The tokens are deliberately a separate store from the profile-photo tokens:
 * that one keeps a single live token per user and kills the previous, so
 * sharing it would let opening an inquiry cancel a pending avatar upload.
 */

const crypto = require('crypto');

const MAX_PHOTOS = 3;
const TOKEN_TTL_MS = 10 * 60 * 1000;
const DAILY_PHOTO_CAP = 12; // per user — abuse guard on storage

function createInquiryPhotoStore({ now = () => Date.now() } = {}) {
  const tokens = new Map(); // token -> { userId, uses, expiresAt }
  const daily = new Map();  // userId -> { day, n }

  const dayKey = () => new Date(now()).toISOString().slice(0, 10);

  function uploadsToday(userId) {
    const r = daily.get(userId);
    return r && r.day === dayKey() ? r.n : 0;
  }
  function noteUpload(userId) {
    daily.set(userId, { day: dayKey(), n: uploadsToday(userId) + 1 });
  }

  // One live token per user; one token covers up to MAX_PHOTOS uploads inside
  // its window so attaching three pictures is one WS round trip, not three.
  function issue(userId) {
    for (const [t, r] of tokens) if (r.userId === userId) tokens.delete(t);
    const token = crypto.randomBytes(24).toString('base64url');
    tokens.set(token, { userId, uses: MAX_PHOTOS, expiresAt: now() + TOKEN_TTL_MS });
    return token;
  }

  // Takes one use. Returns the userId, or null if unknown / expired / spent.
  function consume(token) {
    const rec = token && tokens.get(token);
    if (!rec) return null;
    if (rec.expiresAt < now() || rec.uses <= 0) { tokens.delete(token); return null; }
    rec.uses -= 1;
    return rec.userId;
  }

  function sweep() {
    const t = now();
    for (const [k, r] of tokens) if (r.expiresAt < t) tokens.delete(k);
  }

  return { issue, consume, uploadsToday, noteUpload, sweep };
}

// A client may only attach objects its own uploads produced — never a path it
// guessed or one belonging to somebody else.
function ownKeyPattern(userId) {
  return new RegExp(`^inquiries/${Number(userId)}/[0-9]+-[0-9a-f]{32}\\.jpg$`);
}

function pickOwnKeys(userId, raw) {
  const re = ownKeyPattern(userId);
  return (Array.isArray(raw) ? raw : [])
    .filter((k) => typeof k === 'string' && re.test(k))
    .filter((k, i, a) => a.indexOf(k) === i)
    .slice(0, MAX_PHOTOS);
}

module.exports = {
  MAX_PHOTOS, TOKEN_TTL_MS, DAILY_PHOTO_CAP,
  createInquiryPhotoStore, ownKeyPattern, pickOwnKeys,
};
