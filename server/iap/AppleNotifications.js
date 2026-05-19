// App Store Server Notifications V2 verification.
//
// Apple POSTs { signedPayload: "<JWS>" } to our public endpoint when a
// purchase is refunded/revoked (notificationType REFUND for consumables).
// The JWS is ES256-signed; its header carries an x5c cert chain that MUST
// chain up to Apple Root CA - G3. We verify the chain + signature ourselves
// (no third-party dep) before trusting a single byte — an unverified endpoint
// would let anyone forge refunds.
//
// Required env: APPLE_BUNDLE_ID (reject notifications for other apps).

const crypto = require('crypto');

// Apple Root CA - G3 (https://www.apple.com/certificateauthority/). The whole
// chain is anchored here; we pin by SHA-256 fingerprint.
const APPLE_ROOT_G3_FP =
  '63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79';

function b64urlToBuf(s) {
  s = String(s).replace(/-/g, '+').replace(/_/g, '/');
  while (s.length % 4) s += '=';
  return Buffer.from(s, 'base64');
}

function b64urlToJson(s) {
  return JSON.parse(b64urlToBuf(s).toString('utf8'));
}

// Verify a single compact JWS against Apple's chain and return its decoded
// JSON payload. Throws on any verification failure.
function verifyJws(jws) {
  if (typeof jws !== 'string' || jws.split('.').length !== 3) {
    throw new Error('jws_malformed');
  }
  const [h, p, sig] = jws.split('.');
  const header = b64urlToJson(h);
  if (header.alg !== 'ES256') throw new Error(`jws_alg_${header.alg}`);
  if (!Array.isArray(header.x5c) || header.x5c.length < 2) {
    throw new Error('jws_no_x5c');
  }

  const certs = header.x5c.map((der) => new crypto.X509Certificate(Buffer.from(der, 'base64')));
  const now = new Date();
  for (const c of certs) {
    if (new Date(c.validFrom) > now || new Date(c.validTo) < now) {
      throw new Error('cert_expired');
    }
  }
  // Each cert must be signed by the next; the last must be Apple Root G3.
  for (let i = 0; i < certs.length - 1; i++) {
    if (!certs[i].verify(certs[i + 1].publicKey)) {
      throw new Error(`cert_chain_broken_${i}`);
    }
  }
  const root = certs[certs.length - 1];
  if (root.fingerprint256 !== APPLE_ROOT_G3_FP) {
    throw new Error('cert_root_not_apple');
  }
  if (!root.verify(root.publicKey)) {
    throw new Error('cert_root_not_selfsigned');
  }

  // ES256 JWS signature is raw R||S (ieee-p1363), not DER.
  const ok = crypto.verify(
    'sha256',
    Buffer.from(`${h}.${p}`),
    { key: certs[0].publicKey, dsaEncoding: 'ieee-p1363' },
    b64urlToBuf(sig)
  );
  if (!ok) throw new Error('jws_bad_signature');

  return b64urlToJson(p);
}

// Returns { notificationType, subtype, environment, transaction } where
// transaction is the decoded JWSTransaction (transactionId, productId,
// revocationDate, ...). Throws if verification or the bundle check fails.
function parseAppleNotification(signedPayload) {
  const payload = verifyJws(signedPayload);
  const data = payload.data || {};
  const expectedBundle = process.env.APPLE_BUNDLE_ID;
  if (expectedBundle && data.bundleId && data.bundleId !== expectedBundle) {
    throw new Error('bundle_mismatch');
  }
  let transaction = null;
  if (data.signedTransactionInfo) {
    transaction = verifyJws(data.signedTransactionInfo);
  }
  return {
    notificationType: payload.notificationType,
    subtype: payload.subtype || null,
    notificationUUID: payload.notificationUUID || null,
    environment: data.environment || transaction?.environment || null,
    // Present on CONSUMPTION_REQUEST: why Apple is asking (e.g. 'UNINTENDED_PURCHASE').
    consumptionRequestReason: data.consumptionRequestReason || null,
    transaction,
  };
}

module.exports = { parseAppleNotification, verifyJws };
