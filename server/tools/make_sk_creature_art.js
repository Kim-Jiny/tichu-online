'use strict';
/**
 * 크라켄·흰고래의 '배경 없는 캐릭터' 그림을 뽑는다.
 *
 * 트릭 보드의 효과 연출은 카드가 아니라 캐릭터만 띄운다(둥근 빛 번짐 위에
 * 얹히므로, 카드 틀과 그 안의 배경이 들어 있으면 배경이 두 겹으로 보인다).
 * 그 그림을 원본 PNG 에서 만들어 낸다.
 *
 * 쓰는 곳: sk_game_screen.dart 의 _skCreatureArt.
 *
 *   cd server && node tools/make_sk_creature_art.js
 *
 * 원본(art/cards/*.png)을 새로 그렸으면 이걸 다시 돌린다. 카드용 webp 는
 * art/cards/README.md 의 스크립트로 따로 만든다 — 그쪽은 배경이 있어야 한다.
 */
const sharp = require('sharp');
const fs = require('fs');

/// 가장자리에서 번져 들어가며 배경을 지운다.
///
/// 단색 배경이 아니라 그라데이션이므로, 씨앗 색 하나와 비교하면 아래쪽에서
/// 끊긴다. 대신 "직전 픽셀과 비슷한가"를 보며 번지면 그라데이션을 따라가고,
/// 굵은 검은 외곽선에서 자연히 멈춘다.
async function cutout(src, out, { tol = 14, feather = 0.6 } = {}) {
  const img = sharp(src);
  const { width: w, height: h, channels: ch } =
    await img.metadata().then((m) => ({ ...m, channels: m.channels }));
  const { data } = await img.raw().toBuffer({ resolveWithObject: true });

  const idx = (x, y) => (y * w + x) * ch;
  const bg = new Uint8Array(w * h);       // 1 = 배경
  const stack = [];
  const push = (x, y, fr, fg, fb) => {
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    const p = y * w + x;
    if (bg[p]) return;
    const i = idx(x, y);
    if (Math.abs(data[i] - fr) > tol
      || Math.abs(data[i + 1] - fg) > tol
      || Math.abs(data[i + 2] - fb) > tol) return;
    bg[p] = 1;
    stack.push(x, y);
  };
  // 테두리 전체를 씨앗으로
  for (let x = 0; x < w; x++) {
    push(x, 0, data[idx(x, 0)], data[idx(x, 0) + 1], data[idx(x, 0) + 2]);
    push(x, h - 1, data[idx(x, h - 1)], data[idx(x, h - 1) + 1], data[idx(x, h - 1) + 2]);
  }
  for (let y = 0; y < h; y++) {
    push(0, y, data[idx(0, y)], data[idx(0, y) + 1], data[idx(0, y) + 2]);
    push(w - 1, y, data[idx(w - 1, y)], data[idx(w - 1, y) + 1], data[idx(w - 1, y) + 2]);
  }
  while (stack.length) {
    const y = stack.pop(), x = stack.pop();
    const i = idx(x, y);
    const r = data[i], g = data[i + 1], b = data[i + 2];
    push(x + 1, y, r, g, b); push(x - 1, y, r, g, b);
    push(x, y + 1, r, g, b); push(x, y - 1, r, g, b);
  }

  // 알파 채널로. 경계를 살짝 깎아 배경색 테두리가 남지 않게 한다.
  const rgba = Buffer.alloc(w * h * 4);
  let minX = w, minY = h, maxX = -1, maxY = -1, kept = 0;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const p = y * w + x, i = idx(x, y), o = p * 4;
      rgba[o] = data[i]; rgba[o + 1] = data[i + 1]; rgba[o + 2] = data[i + 2];
      if (bg[p]) { rgba[o + 3] = 0; continue; }
      // 배경과 맞닿은 픽셀은 반투명으로 — 계단이 덜 보인다.
      const edge = (x > 0 && bg[p - 1]) || (x < w - 1 && bg[p + 1])
        || (y > 0 && bg[p - w]) || (y < h - 1 && bg[p + w]);
      rgba[o + 3] = edge ? Math.round(255 * feather) : 255;
      kept++;
      if (x < minX) minX = x; if (x > maxX) maxX = x;
      if (y < minY) minY = y; if (y > maxY) maxY = y;
    }
  }
  const pct = ((kept / (w * h)) * 100).toFixed(1);
  // 남은 영역만 잘라낸다 — 투명 여백을 들고 다닐 이유가 없다.
  const pad = 6;
  const left = Math.max(0, minX - pad), top = Math.max(0, minY - pad);
  const cw = Math.min(w - left, maxX - minX + 1 + pad * 2);
  const chh = Math.min(h - top, maxY - minY + 1 + pad * 2);
  const buf = await sharp(rgba, { raw: { width: w, height: h, channels: 4 } })
    .extract({ left, top, width: cw, height: chh })
    .resize({ height: 420, fit: 'inside', kernel: 'lanczos3' })
    .webp({ quality: 92, effort: 6, alphaQuality: 100 })
    .toBuffer();
  fs.writeFileSync(out, buf);
  const m = await sharp(buf).metadata();
  console.log(`  ${out.split('/').pop().padEnd(24)} ${m.width}x${m.height}  ${(buf.length/1024).toFixed(1)} KB  (남은 픽셀 ${pct}%)`);
}

(async () => {
  const S = '../flutter_app/art/cards/', A = '../flutter_app/assets/cards/';
  await cutout(S + 'kraken.png', A + 'sk_kraken_art.webp');
  await cutout(S + 'white_whale.png', A + 'sk_white_whale_art.webp');
})();
