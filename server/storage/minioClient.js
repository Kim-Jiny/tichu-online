'use strict';

/**
 * Profile-photo object storage.
 *
 * Reuses the shared hmlove-minio instance (same VPS / app-network) under a
 * dedicated `tichu-profile-photos` bucket + a bucket-scoped access key — see
 * server/deploy/PROFILE_PHOTO_PLAN.md. Config comes from the server .env:
 *   MINIO_ENDPOINT=hmlove-minio  MINIO_PORT=9000  MINIO_USE_SSL=false
 *   MINIO_BUCKET=tichu-profile-photos
 *   MINIO_ACCESS_KEY / MINIO_SECRET_KEY = the tichu-pp scoped key
 *   MINIO_PUBLIC_BASE = https://<domain>/media/profile-photos (nginx route)
 *
 * If the access key/secret are absent (e.g. a container started before the
 * feature was configured), the module is DISABLED and isEnabled() returns
 * false — callers must surface a clean "not available" instead of crashing.
 */

const Minio = require('minio');

const ENDPOINT = process.env.MINIO_ENDPOINT || 'hmlove-minio';
const PORT = parseInt(process.env.MINIO_PORT, 10) || 9000;
const USE_SSL = process.env.MINIO_USE_SSL === 'true';
const BUCKET = process.env.MINIO_BUCKET || 'tichu-profile-photos';
const PUBLIC_BASE = (process.env.MINIO_PUBLIC_BASE || '').replace(/\/+$/, '');

const enabled = !!(process.env.MINIO_ACCESS_KEY && process.env.MINIO_SECRET_KEY);
let client = null;
if (enabled) {
  client = new Minio.Client({
    endPoint: ENDPOINT,
    port: PORT,
    useSSL: USE_SSL,
    accessKey: process.env.MINIO_ACCESS_KEY,
    secretKey: process.env.MINIO_SECRET_KEY,
  });
}

function isEnabled() { return enabled; }

// Public URL served by nginx (/media/profile-photos/<key> -> bucket object).
// Falls back to the relative path if MINIO_PUBLIC_BASE isn't set.
function publicUrl(key) {
  if (!key) return null;
  return PUBLIC_BASE ? `${PUBLIC_BASE}/${key}` : `/media/profile-photos/${key}`;
}

// key = `${userId}/${timestamp}.${ext}` — changes on every re-upload, so the
// 7-day immutable cache header on nginx never needs manual invalidation.
async function uploadProfilePhoto(userId, buffer, mimeType) {
  if (!client) throw new Error('minio not configured');
  const ext = mimeType === 'image/png' ? 'png'
    : mimeType === 'image/webp' ? 'webp'
    : 'jpg';
  const key = `${userId}/${Date.now()}.${ext}`;
  await client.putObject(BUCKET, key, buffer, buffer.length, { 'Content-Type': mimeType });
  return { key, url: publicUrl(key) };
}

async function deleteProfilePhoto(key) {
  if (!client || !key) return;
  try { await client.removeObject(BUCKET, key); } catch (_) { /* best-effort */ }
}

// A rejected/ prefix in the same bucket keeps publicUrl() and the nginx
// /media/profile-photos/ route working unchanged for the admin review page —
// it's just another key, never linked from anywhere a player can reach.
async function uploadRejectedPhoto(userId, buffer, mimeType) {
  if (!client) throw new Error('minio not configured');
  const ext = mimeType === 'image/png' ? 'png'
    : mimeType === 'image/webp' ? 'webp'
    : 'jpg';
  const key = `rejected/${userId}/${Date.now()}.${ext}`;
  await client.putObject(BUCKET, key, buffer, buffer.length, { 'Content-Type': mimeType });
  return { key, url: publicUrl(key) };
}

module.exports = {
  isEnabled, uploadProfilePhoto, uploadRejectedPhoto, deleteProfilePhoto, publicUrl, BUCKET,
};
