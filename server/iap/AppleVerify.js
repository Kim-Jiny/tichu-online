// Apple purchase verification (StoreKit 2 / App Store Server model).
//
// The iOS client (in_app_purchase_storekit, StoreKit 2 default) sends
// PurchaseDetails.verificationData.serverVerificationData as the JWS
// REPRESENTATION of the transaction — a signed JWT we verify OFFLINE against
// Apple's cert chain (see AppleStoreKit2 / AppleNotifications). There is no
// legacy verifyReceipt path: the app never enables StoreKit 1, so a base64
// app receipt is never produced.
//
// Required env: APPLE_BUNDLE_ID

const { verifyAppleTransaction, looksLikeJws } = require('./AppleStoreKit2');

async function verifyApple(verificationData, expectedProductId) {
  if (typeof verificationData !== 'string' || !verificationData) {
    return { valid: false, reason: 'missing_receipt' };
  }
  if (!looksLikeJws(verificationData)) {
    // Not a StoreKit 2 JWS. Nothing else is expected on iOS — reject loudly
    // rather than feed a malformed blob into JWS verification.
    return { valid: false, reason: 'not_jws' };
  }
  return verifyAppleTransaction(verificationData, expectedProductId);
}

module.exports = { verifyApple };
