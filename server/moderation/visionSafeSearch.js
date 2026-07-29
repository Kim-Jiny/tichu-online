'use strict';

/**
 * Automated screening of uploaded profile photos (Cloud Vision SafeSearch).
 *
 * Apple 1.2 requires a UGC app to filter objectionable material before it is
 * posted, not only to take it down after a report. Reporting, blocking, and
 * a 24-hour takedown commitment were already in place; this is the missing
 * piece.
 *
 * SafeSearch is billed per image, but it is FREE at every tier when requested
 * alongside Label Detection — so both features go in one call and the labels
 * come along for nothing. They are handed back for the moderation queue: when
 * a photo lands in review it helps to see what Vision thought was in it.
 *
 * Auth reuses the Play service account already on the server, with the same
 * signed-JWT dance as iap/GoogleVerify.js — no googleapis dependency, just
 * crypto and fetch. Only the scope differs.
 *
 * Config:
 *   VISION_ENABLED=true                      required — see below
 *   VISION_SA_EMAIL / VISION_SA_PRIVATE_KEY  (falls back to GOOGLE_PLAY_SA_*)
 *
 * Opt-in rather than "on as soon as credentials exist", because the
 * credentials already exist on this server for Play billing. Screening failures
 * are fail-closed, so auto-enabling would have turned a merge into an outage:
 * every upload refused, because the GCP project has not had the Vision API
 * switched on. An un-enabled API answers 403 to a perfectly valid token —
 * exactly the trap the Play Developer API set on this project once already.
 * Enable the API in the console first, then set VISION_ENABLED=true.
 */

const crypto = require('crypto');

const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const SCOPE = 'https://www.googleapis.com/auth/cloud-platform';
const ANNOTATE_URL = 'https://vision.googleapis.com/v1/images:annotate';
const TIMEOUT_MS = 8000;

// Vision's five-step likelihood scale.
const RANK = {
  UNKNOWN: 0,
  VERY_UNLIKELY: 1,
  UNLIKELY: 2,
  POSSIBLE: 3,
  LIKELY: 4,
  VERY_LIKELY: 5,
};
const REJECT_AT = RANK.LIKELY;   // refuse the upload outright
const REVIEW_AT = RANK.POSSIBLE; // let it through, but flag it

// Categories that disqualify a profile photo. `medical` and `spoof` are
// deliberately absent: a photo of a scar or a meme edit is not a policy breach
// and flagging them would only bury the real reports.
const CATEGORIES = ['adult', 'racy', 'violence'];

function credentials() {
  const email = process.env.VISION_SA_EMAIL || process.env.GOOGLE_PLAY_SA_EMAIL;
  // Allow the PEM to be stored with literal "\n" (common in .env files).
  const raw = process.env.VISION_SA_PRIVATE_KEY
    || process.env.GOOGLE_PLAY_SA_PRIVATE_KEY
    || '';
  return { email, key: raw.replace(/\\n/g, '\n') };
}

function isEnabled() {
  if (process.env.VISION_ENABLED !== 'true') return false;
  const { email, key } = credentials();
  return !!(email && key);
}

function base64url(input) {
  return Buffer.from(input)
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

let cachedToken = null; // { token, exp }

async function getAccessToken() {
  if (cachedToken && cachedToken.exp > Date.now() + 60_000) {
    return cachedToken.token;
  }
  const { email, key } = credentials();
  if (!email || !key) throw new Error('vision_not_configured');

  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claim = base64url(JSON.stringify({
    iss: email,
    scope: SCOPE,
    aud: TOKEN_URL,
    iat: now,
    exp: now + 3600,
  }));
  const signer = crypto.createSign('RSA-SHA256');
  signer.update(`${header}.${claim}`);
  const signature = signer.sign(key)
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');

  const res = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${header}.${claim}.${signature}`,
    }),
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!res.ok) throw new Error(`vision_token_http_${res.status}`);
  const json = await res.json();
  cachedToken = {
    token: json.access_token,
    exp: Date.now() + (json.expires_in || 3600) * 1000,
  };
  return cachedToken.token;
}

/**
 * Turn one safeSearchAnnotation into a verdict.
 *
 * Split out so the thresholds can be tested without sending anything to
 * Google — and without needing the very material this exists to keep out.
 */
function classify(safe) {
  const scores = {};
  let worstRank = 0;
  let worst = null;
  for (const c of CATEGORIES) {
    const value = (safe && safe[c]) || 'UNKNOWN';
    scores[c] = value;
    const rank = RANK[value] ?? 0;
    if (rank > worstRank) { worstRank = rank; worst = c; }
  }
  if (worstRank >= REJECT_AT) return { verdict: 'reject', worst, scores };
  if (worstRank >= REVIEW_AT) return { verdict: 'review', worst, scores };
  return { verdict: 'ok', worst, scores };
}

/**
 * Screen one image.
 *
 * @returns {Promise<{verdict:'ok'|'review'|'reject'|'skipped', worst?:string,
 *                    scores?:Object, labels?:string[], reason?:string}>}
 *
 * Never throws — a transport failure comes back as verdict:"error" so the
 * caller decides what an unscreenable image means.
 */
async function screen(buffer) {
  if (!isEnabled()) return { verdict: 'skipped', reason: 'not_configured' };
  try {
    const token = await getAccessToken();
    const res = await fetch(ANNOTATE_URL, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        requests: [{
          image: { content: buffer.toString('base64') },
          features: [
            { type: 'SAFE_SEARCH_DETECTION' },
            // Free-rides SafeSearch onto the Label tier; also gives the
            // moderation queue something human-readable.
            { type: 'LABEL_DETECTION', maxResults: 5 },
          ],
        }],
      }),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    if (!res.ok) {
      const body = await res.text().catch(() => '');
      return {
        verdict: 'error',
        reason: `http_${res.status}`,
        detail: body.slice(0, 200),
      };
    }
    const json = await res.json();
    const r = json.responses?.[0];
    if (r?.error) return { verdict: 'error', reason: r.error.message || 'api_error' };

    const labels = (r?.labelAnnotations || []).map((l) => l.description);
    return { ...classify(r?.safeSearchAnnotation), labels };
  } catch (e) {
    return { verdict: 'error', reason: e.message || 'unknown' };
  }
}

module.exports = { screen, classify, isEnabled, CATEGORIES, RANK, REJECT_AT, REVIEW_AT };
