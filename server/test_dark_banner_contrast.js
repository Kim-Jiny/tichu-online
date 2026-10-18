'use strict';
/**
 * 어두운 배너 위의 글자가 실제로 읽히는지.
 *
 * 배너는 어드민에서 색만 넣으면 끝이라, 만들 때 "예뻐 보이는가" 는 봐도
 * "그 위의 글자가 읽히는가" 는 잘 안 본다. 실제로 먹금 배너를 처음 만들
 * 때 금색이 너무 밝아 크림색 글자가 대비 2.80 으로 묻혔다 — 눈으로는
 * 괜찮아 보였다.
 *
 * 그라데이션 '전 구간' 중 가장 나쁜 곳을 본다. 글자는 배너를 가로지르고
 * 닉네임 길이에 따라 어디에 닿을지 모른다.
 *
 * 기존 배너는 검사하지 않는다. 42종 중 13종이 이 기준 아래인데, 그중
 * 다수는 글자가 닿지 않는 끝이 밝은 경우라 실제로 문제가 아닐 수 있다 —
 * 그걸 가리려면 눈으로 봐야 한다. 여기서는 새로 만든 어두운 배너만
 * 보증한다.
 *
 *   node test_dark_banner_contrast.js
 */
const db = require('./db/database.js');

let ok = true;
const chk = (n, c, d = '') => {
  console.log(c ? '  ok  ' : '  FAIL', n + (!c && d ? ` — ${d}` : ''));
  if (!c) ok = false;
};

/// WCAG 상대 휘도.
function luminance(hex) {
  const n = parseInt(hex.slice(1), 16);
  const f = (v) => {
    v /= 255;
    return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
  };
  return 0.2126 * f((n >> 16) & 255) + 0.7152 * f((n >> 8) & 255) + 0.0722 * f(n & 255);
}

function contrast(a, b) {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}

/// 앱이 쓰는 판정과 같은 기준(banner_ink.dart 의 isDarkBanner).
const DARK_THRESHOLD = 0.45;

(async () => {
  await db.initDatabase();
  const rows = (await db.pool.query(
    `SELECT item_key, metadata FROM tc_shop_items
      WHERE category = 'banner' AND item_key LIKE 'banner_dark%'
      ORDER BY item_key`
  )).rows;

  chk('어두운 배너 세 종이 있다', rows.length === 3, `${rows.length}종`);

  for (const row of rows) {
    const v = row.metadata && row.metadata.visual;
    console.log(`\n[${row.item_key}]`);
    chk('비주얼이 들어 있다', !!v);
    if (!v) continue;

    const stops = v.preview && v.preview.background && v.preview.background.stops;
    chk('미리보기 그라데이션이 있다', Array.isArray(stops) && stops.length >= 2);
    if (!stops) continue;

    const mean = stops.reduce((a, s) => a + luminance(s.color), 0) / stops.length;
    chk(`실제로 어둡다 (휘도 ${mean.toFixed(3)})`, mean <= DARK_THRESHOLD,
      '앱이 밝은 배너로 보고 글자를 어둡게 쓴다');

    // text.color 를 채워 둔다. 비워도 앱이 밝기로 판단하지만, 한쪽만
    // 어두운 그라데이션은 평균으로 한 가지 답밖에 못 낸다.
    const ink = v.text && v.text.color;
    chk('글자색이 지정돼 있다', !!ink);
    if (!ink) continue;

    const worst = stops
      .map((s) => ({ color: s.color, ratio: contrast(ink, s.color) }))
      .sort((a, b) => a.ratio - b.ratio)[0];
    chk(`가장 나쁜 구간에서도 읽힌다 (${worst.color} 대비 ${worst.ratio.toFixed(2)})`,
      worst.ratio >= 4.5, '글자가 묻힌다');

    // 섬네일 테두리·아이콘도 배너 바탕 위에 놓인다.
    const th = v.thumbnail;
    chk('섬네일이 있다', !!(th && th.icon && th.background));
  }

  console.log(ok ? '\n전부 통과' : '\n실패 있음');
  process.exit(ok ? 0 : 1);
})().catch((e) => { console.error(e); process.exit(1); });
