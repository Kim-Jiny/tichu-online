/**
 * Static hosting for the web client — flutter_app built for the web, staged
 * by deploy.sh and copied into ./public/play by the Dockerfile.
 *
 * Mounted at the SITE ROOT: tichu.jiny.shop is the game. This runs as the last
 * branch of the request chain in server.js, so every real route (/health,
 * /invite, /terms, /tc-backstage, /media, /upload, /.well-known, …) is matched
 * before it and can never be swallowed by the SPA fallback. /play/* — the old
 * mount point — 301s to the same path at the root.
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

// Directory name is historical; deploy.sh and the Dockerfile stage here.
const ROOT = path.join(__dirname, 'public', 'play');
// Where the client used to be mounted. Kept as a redirect so links and
// bookmarks from the /play era keep working.
const LEGACY_PREFIX = '/play';

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
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  // CanvasKit ships as wasm and the browser only stream-compiles it when the
  // type is exact; anything else falls back to a slower path or fails outright.
  '.wasm': 'application/wasm',
  '.txt': 'text/plain; charset=utf-8',
  '.symbols': 'text/plain; charset=utf-8',
};

/** Whether this image was built with the web client bundled in. */
function isAvailable() {
  return fs.existsSync(path.join(ROOT, 'index.html'));
}

function isLegacyPath(pathname) {
  return pathname === LEGACY_PREFIX || pathname.startsWith(`${LEGACY_PREFIX}/`);
}

// Nothing here is content-hashed: a Flutter build writes main.dart.js,
// assets/… and canvaskit/… under fixed names and rewrites them in place on the
// next release. Fingerprint-style immutable caching would pin players to the
// build they first loaded, so nothing gets a long life here.
//
// But blanket `no-cache` was too far the other way: it forces a conditional
// request for EVERY file on EVERY load. A card game opens dozens of images, so
// a revisit spent dozens of round trips just to be told "304, unchanged" —
// latency that no amount of shrinking the files removes.
//
// So: the entry point still never caches (it decides which build you are on),
// code revalidates (a wrong main.dart.js is a broken app), and the heavy,
// slow-changing media gets a short freshness window. Ten minutes is long
// enough to cover a play session end to end, and short enough that replaced
// art is live before anyone files a bug about it.
const MEDIA_MAX_AGE_SEC = 600;
const MEDIA_RE = /^\/(assets|canvaskit|fonts|icons)\//;

function cacheControlFor(pathname, noStore) {
  if (noStore) return 'no-store';
  return MEDIA_RE.test(pathname)
    ? `public, max-age=${MEDIA_MAX_AGE_SEC}`
    : 'no-cache';
}

async function sendFile(req, res, filePath, pathname) {
  const stat = await fsp.stat(filePath);
  const ext = path.extname(filePath).toLowerCase();
  // `no-cache` means "revalidate before reusing", and revalidating needs
  // something to compare — without an ETag the browser has no way to ask "is
  // mine still current?" and what it does instead is its own business. That
  // ambiguity is why a rebuild could look like it had not deployed. Size and
  // mtime are enough here: every file is written fresh by the build.
  const etag = `W/"${stat.size.toString(16)}-${stat.mtimeMs.toString(16)}"`;
  const noStore = /(?:index\.html|flutter_bootstrap\.js|flutter_service_worker\.js)$/
    .test(filePath);

  const cacheControl = cacheControlFor(pathname || '', noStore);

  if (!noStore && req.headers['if-none-match'] === etag) {
    res.writeHead(304, { ETag: etag, 'Cache-Control': cacheControl });
    res.end();
    return;
  }

  const body = await fsp.readFile(filePath);
  res.writeHead(200, {
    'Content-Type': CONTENT_TYPES[ext] || 'application/octet-stream',
    'Content-Length': body.length,
    // The entry point and the bootstrap decide which build everything else
    // belongs to, so those must never be served from cache at all.
    'Cache-Control': cacheControl,
    ...(noStore ? {} : { ETag: etag }),
  });
  res.end(body);
}

/**
 * Serves the web client from the root. Returns false when the request should
 * fall through to the caller's own handling (i.e. the bundle isn't in this
 * image, and the marketing page should answer instead).
 *
 * Call this LAST: it answers every path it is given, either with a file or
 * with the SPA shell.
 */
async function serve(req, res, pathname) {
  if (!isAvailable()) return false;

  if (isLegacyPath(pathname)) {
    // '/play' -> '/', '/play/foo' -> '/foo'.
    const moved = pathname.slice(LEGACY_PREFIX.length) || '/';
    res.writeHead(301, { Location: moved });
    res.end();
    return true;
  }

  const relative = pathname.replace(/^\/+/, '');
  const isAsset = relative.length > 0 && path.extname(relative) !== '';

  if (!isAsset) {
    // Client-side route (or the root): hand back the shell.
    await sendFile(req, res, path.join(ROOT, 'index.html'), pathname);
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
    await sendFile(req, res, target, pathname);
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

module.exports = { serve, isAvailable, LEGACY_PREFIX, ROOT };
