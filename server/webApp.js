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
  // robots.txt and sitemap.xml. Without these two a crawler is handed the
  // fallback type and may not treat the sitemap as a sitemap at all.
  '.txt': 'text/plain; charset=utf-8',
  '.xml': 'application/xml; charset=utf-8',
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

/**
 * 미리 압축해 둔 형제 파일(`<파일>.br`)을 쓸 수 있으면 그걸 고른다.
 *
 * nginx 는 gzip 까지만 한다(brotli 모듈이 기본 빌드에 없다). 부팅 경로에서
 * 제일 큰 main.dart.js 가 gzip 1.46MB · brotli 1.10MB 라 25% 차이고, 이건
 * 느린 회선에서 그대로 체감된다. 압축은 빌드 때 precompress_web.js 가
 * 끝내 두고, 여기서는 파일이 있는지만 본다.
 *
 * 이미 Content-Encoding 이 붙은 응답은 nginx 가 다시 gzip 하지 않으므로
 * 이중 압축 걱정은 없다. .br 이 없으면 원본을 그대로 내주고 gzip 이 받는다.
 */
async function pickBrotli(req, filePath) {
  const accepted = String(req.headers['accept-encoding'] || '');
  if (!/(^|[\s,])br($|[\s,;])/.test(accepted)) return null;
  try {
    const brPath = `${filePath}.br`;
    return { path: brPath, stat: await fsp.stat(brPath) };
  } catch {
    return null;
  }
}

async function sendFile(req, res, filePath, pathname) {
  // Content-Type 은 언제나 원본 확장자로 정한다 — 내보내는 바이트가 brotli 라도
  // 그건 인코딩이지 타입이 아니다. .wasm 이 application/wasm 이 아니면
  // 브라우저가 스트리밍 컴파일을 포기한다.
  const ext = path.extname(filePath).toLowerCase();
  const brotli = await pickBrotli(req, filePath);
  const stat = brotli ? brotli.stat : await fsp.stat(filePath);
  const bodyPath = brotli ? brotli.path : filePath;
  // `no-cache` means "revalidate before reusing", and revalidating needs
  // something to compare — without an ETag the browser has no way to ask "is
  // mine still current?" and what it does instead is its own business. That
  // ambiguity is why a rebuild could look like it had not deployed. Size and
  // mtime are enough here: every file is written fresh by the build.
  //
  // brotli 로 내줄 때는 그 파일의 크기·시각으로 만든다. 인코딩이 다르면 태그도
  // 달라야, 같은 URL 을 두 형태로 캐시해도 서로 304 로 오인하지 않는다.
  const etag = `W/"${stat.size.toString(16)}-${stat.mtimeMs.toString(16)}"`;
  const noStore = /(?:index\.html|flutter_bootstrap\.js|flutter_service_worker\.js)$/
    .test(filePath);

  const cacheControl = cacheControlFor(pathname || '', noStore);

  if (!noStore && req.headers['if-none-match'] === etag) {
    res.writeHead(304, {
      ETag: etag,
      'Cache-Control': cacheControl,
      Vary: 'Accept-Encoding',
    });
    res.end();
    return;
  }

  const body = await fsp.readFile(bodyPath);
  res.writeHead(200, {
    'Content-Type': CONTENT_TYPES[ext] || 'application/octet-stream',
    'Content-Length': body.length,
    // The entry point and the bootstrap decide which build everything else
    // belongs to, so those must never be served from cache at all.
    'Cache-Control': cacheControl,
    // 같은 URL 이 인코딩에 따라 다른 바이트를 낸다. 이게 없으면 중간 캐시가
    // br 응답을 br 을 못 받는 클라이언트에게 물려 줄 수 있다.
    Vary: 'Accept-Encoding',
    ...(brotli ? { 'Content-Encoding': 'br' } : {}),
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
