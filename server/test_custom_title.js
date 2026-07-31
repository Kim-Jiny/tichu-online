'use strict';
/**
 * What the custom title accepts and refuses.
 *
 * Pure function, so no server or database — the point is that every rule has a
 * case that fails without it, including the ones that are easy to think are
 * covered "because it's only four characters".
 */

const { validateCustomTitle } = require('./moderation/customTitle');

let failures = 0;

function accepts(text, color, note) {
  const r = validateCustomTitle(text, color);
  if (r.ok) {
    console.log(`  ok   accepts ${JSON.stringify(text)} — ${note}`);
  } else {
    failures++;
    console.log(`  FAIL rejected ${JSON.stringify(text)} (${r.reason}) — ${note}`);
  }
}

function rejects(text, color, expected, note) {
  const r = validateCustomTitle(text, color);
  if (!r.ok && r.reason === expected) {
    console.log(`  ok   rejects ${JSON.stringify(text)} (${expected}) — ${note}`);
  } else {
    failures++;
    console.log(
      `  FAIL ${JSON.stringify(text)} gave ${r.ok ? 'ACCEPTED' : r.reason},`
      + ` expected ${expected} — ${note}`,
    );
  }
}

accepts('용사', 'rose', '한글 2자');
accepts('네글자야', 'blue', '한글 4자 (상한)');
accepts('GOAT', 'slate', '영문 4자');
accepts('7777', 'amber', '숫자 4자');
accepts('킹A1', 'teal', '혼합');

rejects('다섯글자야', 'rose', 'custom_title_too_long', '5자');
rejects('', 'rose', 'custom_title_empty', '빈 문자열');
rejects('   ', 'rose', 'custom_title_empty', '공백만');
rejects('용 사', 'rose', 'custom_title_charset', '가운데 공백');
rejects('🐉왕', 'rose', 'custom_title_charset', '이모지 — 기기별로 깨짐');
rejects('👨‍👩‍👧', 'rose', 'custom_title_charset', 'ZWJ 조합 이모지');
rejects('ㅋ̸̢̛̥', 'rose', 'custom_title_charset', '결합 문자(zalgo) — 칩 밖으로 번짐');
rejects('‮abc', 'rose', 'custom_title_charset', 'RTL 오버라이드 — 줄이 뒤집힘');
rejects('a​b', 'rose', 'custom_title_charset', '제로폭 공백');
rejects('ㅤㅤ', 'rose', 'custom_title_charset', '한글 채움 문자(빈 칭호)');
rejects('운영자', 'rose', 'custom_title_banned', '스태프 사칭');
rejects('GM', 'rose', 'custom_title_banned', '대소문자 무시 사칭');
rejects('ADMIN', 'rose', 'custom_title_too_long', '5자 — 길이에서 먼저 걸림');
rejects('시발', 'rose', 'custom_title_banned', '욕설');
rejects('용사', 'rainbow', 'custom_title_color', '팔레트 밖 색상');
rejects('용사', '#000000', 'custom_title_color', '자유 RGB 입력');

// Decomposed Hangul: same four syllables, arrived as jamo. NFC must fold it
// before counting, or "네글자야" written this way reads as 8 and is refused.
accepts('네글자야'.normalize('NFD'), 'blue', 'NFD로 들어온 한글 4자');

if (failures) {
  console.log(`\n${failures} FAILED`);
  process.exit(1);
}
console.log('\nALL PASS');
