'use strict';
// 문의 사진: 토큰(사용 횟수·만료·1인 1토큰), 일일 상한, 내 키만 첨부, 이미지 변환.
const assert = require('assert');
const sharp = require('sharp');
const ip = require('./inquiryPhotos');

(async () => {
  let t = Date.parse('2026-10-20T10:00:00Z');
  const store = ip.createInquiryPhotoStore({ now: () => t });

  // 한 토큰으로 MAX_PHOTOS 번까지, 그 이후는 막힌다.
  const tok = store.issue(7);
  for (let i = 0; i < ip.MAX_PHOTOS; i++) assert.strictEqual(store.consume(tok), 7, `use ${i}`);
  assert.strictEqual(store.consume(tok), null, '횟수 소진 뒤 거부');

  // 새로 받으면 앞 토큰은 죽는다(1인 1토큰).
  const a = store.issue(7);
  const b = store.issue(7);
  assert.strictEqual(store.consume(a), null);
  assert.strictEqual(store.consume(b), 7);
  // 다른 사람 토큰은 서로 영향 없다.
  const other = store.issue(9);
  assert.strictEqual(store.consume(b), 7);
  assert.strictEqual(store.consume(other), 9);

  // 만료
  const c = store.issue(7);
  t += ip.TOKEN_TTL_MS + 1;
  assert.strictEqual(store.consume(c), null, '만료 뒤 거부');
  assert.strictEqual(store.consume('nope'), null);
  assert.strictEqual(store.consume(''), null);
  assert.strictEqual(store.consume(undefined), null);

  // 일일 상한 + 날짜가 바뀌면 리셋
  for (let i = 0; i < ip.DAILY_PHOTO_CAP; i++) store.noteUpload(7);
  assert.strictEqual(store.uploadsToday(7), ip.DAILY_PHOTO_CAP);
  assert.strictEqual(store.uploadsToday(9), 0);
  t += 24 * 3600 * 1000;
  assert.strictEqual(store.uploadsToday(7), 0, '다음 날 리셋');

  // 내 키만, 중복 제거, 최대 장수
  const hex = (n) => n.toString(16).padStart(32, '0');
  const mine = [1, 2, 3, 4].map((n) => `inquiries/7/1760000000${n}-${hex(n)}.jpg`);
  assert.deepStrictEqual(ip.pickOwnKeys(7, mine), mine.slice(0, ip.MAX_PHOTOS));
  assert.deepStrictEqual(ip.pickOwnKeys(7, [mine[0], mine[0]]), [mine[0]]);
  assert.deepStrictEqual(ip.pickOwnKeys(8, mine), [], '남의 키 거부');
  const bad = [
    '7/17600000001-' + hex(1) + '.jpg',            // 접두사 없음
    'inquiries/7/../8/1-' + hex(1) + '.jpg',       // 경로 탈출
    'inquiries/7/1-' + hex(1) + '.png',            // 확장자
    'inquiries/7/1-abc.jpg',                       // 랜덤부 짧음
    'rejected/7/1.jpg',
    'inquiries/70/1-' + hex(1) + '.jpg',           // 다른 id(접두 일치)
    42, null, {},
  ];
  assert.deepStrictEqual(ip.pickOwnKeys(7, bad), []);
  assert.deepStrictEqual(ip.pickOwnKeys(7, 'not-an-array'), []);

  // 서버가 하는 변환: 긴 변 1600 이하로만 줄이고(비율 유지), 작은 건 키우지 않고, JPEG 로.
  const big = await sharp({ create: { width: 3000, height: 1500, channels: 3, background: '#39f' } }).png().toBuffer();
  const out = await sharp(big).rotate().resize(1600, 1600, { fit: 'inside', withoutEnlargement: true }).jpeg({ quality: 82 }).toBuffer();
  const meta = await sharp(out).metadata();
  assert.strictEqual(meta.format, 'jpeg');
  assert.strictEqual(meta.width, 1600);
  assert.strictEqual(meta.height, 800);
  const small = await sharp({ create: { width: 300, height: 200, channels: 3, background: '#f93' } }).png().toBuffer();
  const sm = await sharp(await sharp(small).rotate().resize(1600, 1600, { fit: 'inside', withoutEnlargement: true }).jpeg().toBuffer()).metadata();
  assert.strictEqual(sm.width, 300);

  console.log('PASS');
})().catch((e) => { console.error(e); process.exit(1); });
