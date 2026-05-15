// Google Play refund detection via the Voided Purchases API.
//
// Apple pushes refunds to us; Google has no consumable refund webhook that's
// free of Pub/Sub infra, but it exposes purchases.voidedpurchases.list which
// we can POLL with the SAME service account already used for verification —
// no extra credential, no public endpoint. We ask for vouchers voided in a
// trailing window and hand each one to autoRefundByTransaction (idempotent,
// so overlapping windows are safe).
//
// Required env: GOOGLE_PLAY_PACKAGE_NAME + the GOOGLE_PLAY_SA_* used by
// GoogleVerify. Disabled automatically when those are absent.

const { getAccessToken } = require('./GoogleVerify');

// voidedSource: 0=User, 1=Developer, 2=Google. voidedReason: 0=Other,
// 1=Remorse, 2=Not_received, 3=Defective, 4=Accidental_purchase, 5=Fraud,
// 6=Friendly_fraud, 7=Chargeback.
function reasonText(v) {
  const src = { 0: 'user', 1: 'developer', 2: 'google' }[v.voidedSource] || 'unknown';
  return `google_void:src=${src}:reason=${v.voidedReason}`;
}

// Lists purchases voided in the last `windowMs` and refunds each via the
// supplied autoRefund fn. Returns a small stats object; never throws.
// startTimeMs (optional): explicit lower bound, used to resume from a
// persisted cursor so a long outage doesn't drop voids that happened in the
// gap. Clamped to Google's ~30-day max lookback. Falls back to now-windowMs.
async function pollGoogleVoidedPurchases(autoRefund, { windowMs = 36 * 60 * 60 * 1000, startTimeMs = null } = {}) {
  const pkg = process.env.GOOGLE_PLAY_PACKAGE_NAME;
  if (!pkg || !process.env.GOOGLE_PLAY_SA_EMAIL || !process.env.GOOGLE_PLAY_SA_PRIVATE_KEY) {
    return { ok: false, reason: 'not_configured' };
  }

  let token;
  try {
    token = await getAccessToken();
  } catch (err) {
    console.error('[GoogleVoided] token failed:', err.message);
    return { ok: false, reason: 'token_failed' };
  }

  const nowMs = Date.now();
  const MAX_LOOKBACK = 29 * 24 * 60 * 60 * 1000; // Google won't return older
  let startTime = startTimeMs != null ? startTimeMs : nowMs - windowMs;
  startTime = Math.max(startTime, nowMs - MAX_LOOKBACK);
  let processed = 0;
  let nextToken = null;
  try {
    do {
      const params = new URLSearchParams({
        startTime: String(startTime),
        type: '1', // 0 = in-app voids only; 1 = in-app + subscription voids (superset, safe)
        'maxResults': '100',
      });
      if (nextToken) params.set('token', nextToken);
      const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${encodeURIComponent(pkg)}/purchases/voidedpurchases?${params}`;
      const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
      if (!res.ok) {
        console.error('[GoogleVoided] list http', res.status);
        return { ok: false, reason: `http_${res.status}`, processed };
      }
      const body = await res.json();
      const list = Array.isArray(body.voidedPurchases) ? body.voidedPurchases : [];
      for (const v of list) {
        // Our Google transactionId is orderId (see GoogleVerify); fall back to
        // the token-derived id if orderId is absent.
        const txn = v.orderId || (v.purchaseToken ? `gpa_${String(v.purchaseToken).slice(0, 64)}` : null);
        if (!txn) continue;
        const r = await autoRefund({ transactionId: txn, source: 'google', reason: reasonText(v) });
        if (r && (r.success || r.idempotent)) processed++;
      }
      nextToken = body.tokenPagination && body.tokenPagination.nextPageToken;
    } while (nextToken);
  } catch (err) {
    console.error('[GoogleVoided] poll error:', err.message);
    return { ok: false, reason: 'request_failed', processed };
  }
  // pollStartedAt = the moment this poll began. The caller persists it as the
  // next cursor only on ok, so the next run resumes from here (with overlap).
  return { ok: true, processed, pollStartedAt: nowMs };
}

module.exports = { pollGoogleVoidedPurchases };
