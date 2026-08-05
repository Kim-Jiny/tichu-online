/**
 * Static hosting for the web client (web/ → built into ./public/play).
 *
 * It is served by this process rather than by nginx because nginx runs in a
 * different container and already proxies every path to the backend — putting
 * the files inside the app image is what keeps a blue/green swap atomic. The
 * files also have to be same-origin with the WebSocket: the server emits no
 * CORS headers anywhere, so a separate host would break the profile-photo
 * upload endpoint.
 *
 * Nothing here is reachable unless the directory exists, so a server image
 * built without the web stage simply 404s /play.
 */

const fs = require('fs');
const fsp = require('fs/promises');
const path = require('path');

const ROOT = path.join(__dirname, 'public', 'play');
const PREFIX = '/play';

const CONTENT_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.map': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.ico': 'image/x-icon',
  '.wav': 'audio/wav',
  '.mp3': 'audio/mpeg',
  '.woff2': 'font/woff2',
  '.txt': 'text/plain; charset=utf-8',
};

/** Whether this image was built with the web client bundled in. */
function isAvailable() {
  return fs.existsSync(path.join(ROOT, 'index.html'));
}

function matches(pathname) {
  return pathname === PREFIX || pathname.startsWith(`${PREFIX}/`);
}

async function sendFile(res, filePath, { immutable = false } = {}) {
  const body = await fsp.readFile(filePath);
  res.writeHead(200, {
    'Content-Type': CONTENT_TYPES[path.extname(filePath).toLowerCase()] || 'application/octet-stream',
    'Content-Length': body.length,
    'Cache-Control': immutable
      ? 'public, max-age=31536000, immutable'
      : 'no-cache',
  });
  res.end(body);
}

/**
 * Serves `/play/*`. Returns false when the request should fall through to the
 * caller's own handling (i.e. the bundle isn't in this image).
 */
async function serve(req, res, pathname) {
  if (!isAvailable()) return false;

  if (pathname === PREFIX) {
    // Without the trailing slash every relative asset URL would resolve one
    // directory too high.
    res.writeHead(301, { Location: `${PREFIX}/` });
    res.end();
    return true;
  }

  const relative = pathname.slice(PREFIX.length + 1);
  const isAsset = relative.length > 0 && path.extname(relative) !== '';

  if (!isAsset) {
    // Client-side route (or the root): hand back the shell.
    await sendFile(res, path.join(ROOT, 'index.html'));
    return true;
  }

  // Resolve first, then confirm the result is still inside ROOT — decoding and
  // normalising separately is how `..` slips through.
  let target;
  try {
    target = path.resolve(ROOT, decodeURIComponent(relative));
  } catch {
    res.writeHead(400, { 'Content-Type': 'text/plain' });
    res.end('bad request');
    return true;
  }
  if (target !== ROOT && !target.startsWith(ROOT + path.sep)) {
    res.writeHead(403, { 'Content-Type': 'text/plain' });
    res.end('forbidden');
    return true;
  }

  try {
    // Vite fingerprints everything under /assets/, so those are safe to pin
    // forever; anything else (public/ passthroughs) revalidates.
    await sendFile(res, target, { immutable: relative.startsWith('assets/') });
  } catch (err) {
    if (err.code === 'ENOENT' || err.code === 'EISDIR') {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('not found');
    } else {
      res.writeHead(500, { 'Content-Type': 'text/plain' });
      res.end('server error');
    }
  }
  return true;
}

module.exports = { serve, matches, isAvailable, PREFIX, ROOT };
