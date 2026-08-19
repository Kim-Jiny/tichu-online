#!/usr/bin/env node
'use strict';
/**
 * 웹 번들을 미리 brotli 로 압축해 둔다.
 *
 *   node precompress_web.js [디렉터리]      (기본: ./public/play)
 *
 * nginx 가 이미 gzip 을 켜 두었지만, 부팅 경로에서 제일 큰 main.dart.js 가
 * gzip 1.46MB · brotli 1.10MB 다 — 25% 차이고, RTT 300ms 짜리 회선에서는
 * 0.5초쯤 된다. nginx 에 brotli 모듈이 없어서(기본 빌드에 안 들어간다) 앱
 * 컨테이너가 직접 내주는 쪽으로 갔다.
 *
 * 압축은 빌드 때 한 번만 한다. 품질 11 은 5MB 짜리에 10초쯤 걸려서 요청마다
 * 할 만한 일이 아니고, 어차피 파일은 배포 사이에 안 바뀐다. webApp.js 가
 * `<파일>.br` 이 있고 클라이언트가 br 을 받겠다고 하면 그걸 내준다.
 *
 * 원본은 그대로 둔다 — br 을 못 받는 클라이언트도 있고, 그쪽은 nginx 의
 * gzip 이 받는다.
 */

const fs = require('fs/promises');
const path = require('path');
const zlib = require('zlib');
const { promisify } = require('util');

const brotli = promisify(zlib.brotliCompress);

// 압축해서 이득이 나는 것만. woff2 · png · jpg · webp 는 이미 압축된
// 포맷이라 다시 눌러 봐야 CPU 만 쓰고 크기는 그대로거나 늘어난다.
const COMPRESSIBLE = new Set([
  '.js', '.json', '.html', '.css', '.svg', '.txt', '.xml', '.wasm',
  '.bin', '.otf', '.ttf', '.map',
]);

// 브라우저가 받지 않는 것들.
//   .symbols    — 스택트레이스 해독용
//   canvaskit/  — 엔진은 이걸 gstatic CDN 에서 받는다(실측으로 확인).
//                 여기 있는 건 CDN 이 막혔을 때의 보루라 nginx gzip 으로 충분한데,
//                 품질 11 로 28MB 를 누르면 빌드마다 80초가 그냥 나간다.
const SKIP = /\.symbols$|(^|[\\/])canvaskit[\\/]/;

// 1KB 미만은 프레이밍 오버헤드가 이득을 먹는다. nginx 의 gzip_min_length 와
// 같은 기준.
const MIN_BYTES = 1024;

async function* walk(dir) {
  for (const entry of await fs.readdir(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) yield* walk(full);
    else if (entry.isFile()) yield full;
  }
}

async function main() {
  const root = path.resolve(process.argv[2] || path.join(__dirname, 'public', 'play'));
  try {
    await fs.access(root);
  } catch {
    console.error(`no such directory: ${root}`);
    process.exit(1);
  }

  let files = 0, before = 0, after = 0;
  const started = Date.now();

  for await (const file of walk(root)) {
    if (file.endsWith('.br')) continue;
    if (SKIP.test(file)) continue;
    if (!COMPRESSIBLE.has(path.extname(file).toLowerCase())) continue;

    const body = await fs.readFile(file);
    if (body.length < MIN_BYTES) continue;

    const packed = await brotli(body, {
      params: {
        [zlib.constants.BROTLI_PARAM_QUALITY]: 11,
        [zlib.constants.BROTLI_PARAM_SIZE_HINT]: body.length,
      },
    });
    // 안 줄어드는 파일에 .br 을 남기면 서버가 굳이 그걸 골라 내준다.
    if (packed.length >= body.length) continue;

    await fs.writeFile(`${file}.br`, packed);
    files++;
    before += body.length;
    after += packed.length;
  }

  const mb = (n) => (n / 1048576).toFixed(2);
  console.log(
    `brotli: ${files}개 · ${mb(before)}MB → ${mb(after)}MB `
    + `(${Math.round(100 - (after / before || 1) * 100)}% 감소, ${Math.round((Date.now() - started) / 1000)}초)`,
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
