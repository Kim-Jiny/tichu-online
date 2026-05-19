// Apple "Send Consumption Information" — responds to a CONSUMPTION_REQUEST
// App Store Server Notification with the data Apple weighs when deciding a
// consumable refund. Apple still makes the final call; this only informs it
// (and helps curb refund abuse).
//
// Unlike the rest of our IAP path (StoreKit 2 JWS, verified offline, no key),
// the App Store Server API requires an authenticated bearer JWT signed with
// an App Store Connect API in-app-purchase key. Optional by design: if the
// env below is absent we skip the callback and still record the request.
//
// Required env (only for the Apple callback; recording works without it):
//   APPLE_ASC_KEY_ID        App Store Connect API key id (10 chars)
//   APPLE_ASC_ISSUER_ID     issuer id (UUID)
//   APPLE_ASC_PRIVATE_KEY   the .p8 EC private key (PEM; literal \n ok)
//   APPLE_BUNDLE_ID         app bundle id (already used elsewhere)

const crypto = require('crypto');

function ascConfigured() {
  return !!(process.env.APPLE_ASC_KEY_ID
    && process.env.APPLE_ASC_ISSUER_ID
    && process.env.APPLE_ASC_PRIVATE_KEY
    && process.env.APPLE_BUNDLE_ID);
}

function b64url(buf) {
  return Buffer.from(buf).toString('base64')
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

// ES256 JWT for the App Store Server API. exp must be <= 20 min out.
function mintAscToken() {
  const keyId = process.env.APPLE_ASC_KEY_ID;
  const issuer = process.env.APPLE_ASC_ISSUER_ID;
  const bundleId = process.env.APPLE_BUNDLE_ID;
  const pem = (process.env.APPLE_ASC_PRIVATE_KEY || '').replace(/\\n/g, '\n');
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: 'ES256', kid: keyId, typ: 'JWT' }));
  const payload = b64url(JSON.stringify({
    iss: issuer,
    iat: now,
    exp: now + 15 * 60,
    aud: 'appstoreconnect-v1',
    bid: bundleId,
  }));
  const signingInput = `${header}.${payload}`;
  // dsaEncoding ieee-p1363 → raw r||s (JOSE), not DER.
  const sig = crypto.sign('sha256', Buffer.from(signingInput), {
    key: crypto.createPrivateKey(pem),
    dsaEncoding: 'ieee-p1363',
  });
  return `${signingInput}.${b64url(sig)}`;
}

// Sends the consumption body for one transaction. `fields` is the validated
// ConsumptionRequest object; `appAccountToken` is the binding UUID (omit if
// absent — Apple allows it). Returns { ok, reason }.
async function sendConsumptionInfo({ transactionId, environment, fields, appAccountToken }) {
  if (!ascConfigured()) return { ok: false, reason: 'not_configured' };
  if (!transactionId) return { ok: false, reason: 'missing_transaction_id' };

  let token;
  try {
    token = mintAscToken();
  } catch (err) {
    console.error('[AppleConsumption] token mint failed:', err.message);
    return { ok: false, reason: 'token_failed' };
  }

  const host = environment === 'sandbox'
    ? 'https://api.storekit-sandbox.itunes.apple.com'
    : 'https://api.storekit.itunes.apple.com';
  const url = `${host}/inApps/v1/transactions/consumption/${encodeURIComponent(transactionId)}`;

  const body = { ...fields };
  if (appAccountToken) body.appAccountToken = String(appAccountToken);

  try {
    const res = await fetch(url, {
      method: 'PUT',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    });
    // 202 Accepted is the documented success for this endpoint.
    if (res.status === 202) return { ok: true, reason: 'accepted' };
    if (res.status === 404) return { ok: false, reason: 'transaction_not_found' };
    if (res.status === 429) return { ok: false, reason: 'rate_limited' };
    return { ok: false, reason: `http_${res.status}` };
  } catch (err) {
    console.error('[AppleConsumption] request failed:', err.message);
    return { ok: false, reason: 'request_failed' };
  }
}

module.exports = { sendConsumptionInfo, ascConfigured };
