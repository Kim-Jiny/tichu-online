// webApp.serve: the SPA shell is 200 only at '/', unknown extension-less paths
// get the same shell with 404 (no soft-404 for crawlers), missing assets 404.
const assert = require('assert');
const http = require('http');
const webApp = require('./webApp');

if (!webApp.isAvailable()) {
  console.log('web app status skipped (no public/play build)');
  process.exit(0);
}

const srv = http.createServer(async (req, res) => {
  const pathname = new URL(req.url, 'http://x').pathname;
  if (!(await webApp.serve(req, res, pathname))) { res.writeHead(500); res.end(); }
});

function get(port, p) {
  return new Promise((resolve, reject) => {
    http.get({ port, path: p }, (r) => { r.resume(); resolve(r.statusCode); }).on('error', reject);
  });
}

srv.listen(0, async () => {
  const port = srv.address().port;
  try {
    assert.strictEqual(await get(port, '/'), 200);
    assert.strictEqual(await get(port, '/foo'), 404);
    assert.strictEqual(await get(port, '/a/b/c'), 404);
    assert.strictEqual(await get(port, '/missing.js'), 404);
    assert.strictEqual(await get(port, '/play/foo'), 301);
    console.log('web app status ok');
  } finally {
    srv.close();
  }
});
