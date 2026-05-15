// Google Play purchase verification via the Play Developer API.
//
// The Flutter in_app_purchase plugin hands us the purchase token as
// PurchaseDetails.verificationData.serverVerificationData. We mint an OAuth2
// access token from a service account (signed JWT bearer grant) and call
// purchases.products.get to confirm the purchase is real, paid, and not
// refunded. No googleapis dependency — Node's crypto + global fetch only.
//
// Required env:
//   GOOGLE_PLAY_PACKAGE_NAME   e.g. com.jiny.tichuOnline
//   GOOGLE_PLAY_SA_EMAIL       service account client_email
//   GOOGLE_PLAY_SA_PRIVATE_KEY service account private_key (PEM)

const crypto = require('crypto');

const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const SCOPE = 'https://www.googleapis.com/auth/androidpublisher';

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
  const email = process.env.GOOGLE_PLAY_SA_EMAIL;
  // Allow the PEM to be stored with literal "\n" (common in .env files).
  const key = (process.env.GOOGLE_PLAY_SA_PRIVATE_KEY || '').replace(/\\n/g, '\n');
  if (!email || !key) {
    throw new Error('google_play_not_configured');
  }

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
  const assertion = `${header}.${claim}.${signature}`;

  const res = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!res.ok) {
    throw new Error(`google_token_http_${res.status}`);
  }
  const json = await res.json();
  cachedToken = {
    token: json.access_token,
    exp: Date.now() + (json.expires_in || 3600) * 1000,
  };
  return cachedToken.token;
}

// Returns { valid, transactionId, productId, raw } or { valid:false, reason }.
async function verifyGoogle(purchaseToken, expectedProductId) {
  const pkg = process.env.GOOGLE_PLAY_PACKAGE_NAME;
  if (!pkg || !process.env.GOOGLE_PLAY_SA_EMAIL || !process.env.GOOGLE_PLAY_SA_PRIVATE_KEY) {
    return { valid: false, reason: 'google_play_not_configured' };
  }
  if (!purchaseToken || typeof purchaseToken !== 'string') {
    return { valid: false, reason: 'missing_purchase_token' };
  }
  if (!expectedProductId) {
    return { valid: false, reason: 'missing_product_id' };
  }

  let token;
  try {
    token = await getAccessToken();
  } catch (err) {
    console.error('[GoogleVerify] token failed:', err.message);
    return { valid: false, reason: 'google_token_failed' };
  }

  const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${encodeURIComponent(pkg)}/purchases/products/${encodeURIComponent(expectedProductId)}/tokens/${encodeURIComponent(purchaseToken)}`;
  let body;
  try {
    const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
    if (res.status === 404 || res.status === 410) {
      return { valid: false, reason: 'purchase_not_found' };
    }
    if (!res.ok) {
      return { valid: false, reason: `google_api_http_${res.status}` };
    }
    body = await res.json();
  } catch (err) {
    console.error('[GoogleVerify] request failed:', err.message);
    return { valid: false, reason: 'google_request_failed' };
  }

  // purchaseState: 0 = purchased, 1 = canceled, 2 = pending.
  if (body.purchaseState !== 0) {
    return { valid: false, reason: `purchase_state_${body.purchaseState}`, raw: body };
  }

  // purchaseType is ONLY present for non-standard buys: 0=Test (license
  // tester), 1=Promo, 2=Rewarded. A normal paid purchase omits it entirely.
  // Treat 0 as sandbox; everything else (incl. absent) is real money.
  const environment = body.purchaseType === 0 ? 'sandbox' : 'production';

  // orderId is the unique transaction reference — our idempotency key. Fall
  // back to the purchase token if Google omits orderId (rare, e.g. promos).
  const transactionId = body.orderId || `gpa_${purchaseToken.slice(0, 64)}`;
  // One purchaseToken = one purchase (no accumulation like Apple receipts), so
  // a single-element list keeps the caller's grant loop uniform across stores.
  return {
    valid: true,
    environment,
    transactions: [{
      transactionId: String(transactionId),
      productId: expectedProductId,
      raw: body,
    }],
  };
}

module.exports = { verifyGoogle, getAccessToken };
