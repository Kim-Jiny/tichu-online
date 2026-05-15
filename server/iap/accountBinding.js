// Deterministic account-binding token shared by client and server.
//
// StoreKit 2's appAccountToken MUST be a UUID, so we can't use a raw sha256
// hex string. We derive a stable, RFC-4122-shaped UUID from sha256(nickname):
// first 16 bytes of the digest with the version/variant nibbles forced. The
// client stamps this onto the purchase (appAccountToken / obfuscatedAccountId)
// and the server recomputes it from the authenticated nickname to detect a
// receipt redeemed on a different account.
//
// The Dart side (IapService) MUST produce the byte-for-byte same string.

const crypto = require('crypto');

function bindingUuid(name) {
  if (!name) return null;
  const h = crypto.createHash('sha256').update(String(name), 'utf8').digest();
  const b = Buffer.from(h.subarray(0, 16));
  b[6] = (b[6] & 0x0f) | 0x40; // version 4 shape
  b[8] = (b[8] & 0x3f) | 0x80; // RFC-4122 variant
  const x = b.toString('hex');
  return `${x.slice(0, 8)}-${x.slice(8, 12)}-${x.slice(12, 16)}-${x.slice(16, 20)}-${x.slice(20, 32)}`;
}

module.exports = { bindingUuid };
