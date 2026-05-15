// Apple receipt verification via the App Store verifyReceipt endpoint.
//
// The Flutter in_app_purchase plugin hands us the base64 app receipt as
// PurchaseDetails.verificationData.serverVerificationData. We POST it to
// Apple, who returns the decoded receipt. Per Apple's guidance we always hit
// production first and retry against sandbox when production replies 21007 —
// that one status code means "this is a sandbox receipt", which is normal
// during TestFlight / review.
//
// Required env:
//   APPLE_IAP_SHARED_SECRET  App-specific shared secret (App Store Connect)
//   APPLE_BUNDLE_ID          Expected bundle id (e.g. com.jiny.tichuOnline)

const PROD_URL = 'https://buy.itunes.apple.com/verifyReceipt';
const SANDBOX_URL = 'https://sandbox.itunes.apple.com/verifyReceipt';

async function callApple(url, receiptData, secret) {
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      'receipt-data': receiptData,
      password: secret,
      'exclude-old-transactions': true,
    }),
  });
  if (!res.ok) {
    throw new Error(`Apple verifyReceipt HTTP ${res.status}`);
  }
  return res.json();
}

// Returns { valid, transactionId, productId, raw } or { valid:false, reason }.
async function verifyApple(receiptData, expectedProductId) {
  const secret = process.env.APPLE_IAP_SHARED_SECRET;
  const bundleId = process.env.APPLE_BUNDLE_ID;
  if (!secret || !bundleId) {
    return { valid: false, reason: 'apple_iap_not_configured' };
  }
  if (!receiptData || typeof receiptData !== 'string') {
    return { valid: false, reason: 'missing_receipt' };
  }

  let body;
  try {
    body = await callApple(PROD_URL, receiptData, secret);
    if (body.status === 21007) {
      body = await callApple(SANDBOX_URL, receiptData, secret);
    }
  } catch (err) {
    console.error('[AppleVerify] request failed:', err.message);
    return { valid: false, reason: 'apple_request_failed' };
  }

  if (body.status !== 0) {
    return { valid: false, reason: `apple_status_${body.status}` };
  }
  const receipt = body.receipt || {};
  if (receipt.bundle_id && receipt.bundle_id !== bundleId) {
    return { valid: false, reason: 'bundle_mismatch' };
  }

  // Consumables live in in_app / latest_receipt_info. Find the line item that
  // matches the product the client claims it bought.
  const items = []
    .concat(Array.isArray(body.latest_receipt_info) ? body.latest_receipt_info : [])
    .concat(Array.isArray(receipt.in_app) ? receipt.in_app : []);
  const match = items.find((it) => it && it.product_id === expectedProductId);
  if (!match) {
    return { valid: false, reason: 'product_not_in_receipt' };
  }

  // transaction_id is unique per purchase; this is our idempotency key.
  return {
    valid: true,
    transactionId: String(match.transaction_id),
    productId: match.product_id,
    raw: match,
  };
}

module.exports = { verifyApple };
