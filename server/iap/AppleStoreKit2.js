// StoreKit 2 transaction verification (App Store Server API model).
//
// With StoreKit 2 (the default in in_app_purchase_storekit ≥0.4), the iOS
// client no longer sends the legacy base64 app receipt — PurchaseDetails
// .verificationData.serverVerificationData is the JWS REPRESENTATION of the
// transaction (a signed JWT). We verify it OFFLINE using the same Apple cert
// chain logic as App Store Server Notifications v2 (verifyJws), so no
// verifyReceipt round-trip and no .p8 key are needed for the purchase flow.
//
// The decoded JWSTransaction gives us one specific transaction (no receipt
// accumulation), its environment, and the appAccountToken — which finally
// makes account binding enforceable on iOS.
//
// Required env: APPLE_BUNDLE_ID

const { verifyJws } = require('./AppleNotifications');

// A compact JWS is exactly three base64url segments and its header declares
// an alg. The legacy receipt is a single base64 blob (no dots), so this
// cleanly distinguishes the two during the SK1→SK2 transition.
function looksLikeJws(s) {
  if (typeof s !== 'string') return false;
  const parts = s.split('.');
  if (parts.length !== 3) return false;
  try {
    let h = parts[0].replace(/-/g, '+').replace(/_/g, '/');
    while (h.length % 4) h += '=';
    const header = JSON.parse(Buffer.from(h, 'base64').toString('utf8'));
    return typeof header.alg === 'string';
  } catch (_) {
    return false;
  }
}

// Returns the same contract as the other verifiers:
// { valid, environment, accountId, transactions:[{transactionId,productId,raw}] }
// or { valid:false, reason, raw? }.
function verifyAppleTransaction(jws, expectedProductId) {
  let tx;
  try {
    tx = verifyJws(jws);
  } catch (err) {
    return { valid: false, reason: `sk2_jws_${err.message}` };
  }

  const bundleId = process.env.APPLE_BUNDLE_ID;
  if (bundleId && tx.bundleId && tx.bundleId !== bundleId) {
    return { valid: false, reason: 'bundle_mismatch', raw: tx };
  }
  if (expectedProductId && tx.productId !== expectedProductId) {
    return { valid: false, reason: 'product_mismatch', raw: tx };
  }
  // A revoked (refunded / family-removed) transaction must not grant.
  if (tx.revocationDate) {
    return { valid: false, reason: 'revoked', raw: tx };
  }
  if (!tx.transactionId) {
    return { valid: false, reason: 'no_transaction_id', raw: tx };
  }

  const environment = String(tx.environment || '').toLowerCase() === 'sandbox'
    ? 'sandbox'
    : 'production';

  return {
    valid: true,
    environment,
    // appAccountToken is the UUID the client stamped at purchase time.
    accountId: tx.appAccountToken ? String(tx.appAccountToken).toLowerCase() : null,
    transactions: [{
      transactionId: String(tx.transactionId),
      productId: tx.productId,
      raw: tx,
    }],
  };
}

module.exports = { verifyAppleTransaction, looksLikeJws };
