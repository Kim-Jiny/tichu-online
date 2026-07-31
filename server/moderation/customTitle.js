'use strict';

/**
 * Validation for the user-written custom title.
 *
 * Four characters shown next to a nickname is a small surface with a large
 * abuse area, so this is deliberately an allow-list: Hangul syllables, Latin
 * letters and digits, nothing else. Everything the rule shuts out is something
 * that actually breaks the UI or lies to other players:
 *
 *   - emoji: renders differently per device and drops to a tofu box on older
 *     Android; also blows the 4-character budget (one ZWJ sequence is many code
 *     points and draws wider than four Hangul syllables)
 *   - combining marks (zalgo): stack above and below the chip and paint over
 *     the rows next to it
 *   - bidi overrides / invisible characters: flip or blank the whole line
 *   - staff-looking words: "운영자" and "admin" both fit in four characters
 *   - homoglyphs: Cyrillic а/е/о read as Latin and walk around a word list
 *
 * The colour is a preset id rather than free RGB: free colour lets someone pick
 * the background colour (an invisible title) or copy the season-reward colours.
 */

/** Palette ids the client offers; anything else is rejected. */
const TITLE_COLORS = {
  rose: '#D64550',
  amber: '#C97A0B',
  green: '#2E7D32',
  teal: '#00796B',
  blue: '#1565C0',
  violet: '#6A3FB5',
  pink: '#C2185B',
  slate: '#455A64',
};

const MAX_GRAPHEMES = 4;

// Latin letters, digits, Hangul syllables and compatibility jamo. No space: a
// title made of spaces is an invisible title. The jamo range stops at ㅣ
// (U+3163) on purpose — U+3164 is HANGUL FILLER, which passes for a letter in
// every check and draws nothing.
const ALLOWED = /^[0-9A-Za-z가-힣ㄱ-ㅣ]+$/;

// Anything that draws outside its own cell, or that cannot be seen at all.
const COMBINING = /[̀-ͯ᪰-᫿᷀-᷿⃐-⃿︠-︯]/;
const INVISIBLE = /[\u0000-\u001f\u00ad\u061c\u115f\u1160\u180e\u200b-\u200f\u202a-\u202e\u2060-\u2064\u2066-\u206f\u3164\ufeff\uffa0\ufff9-\ufffb]/;

/**
 * Words that would make the wearer look like staff, or that no one should have
 * to sit across from. Matched case-insensitively against the whole title after
 * normalisation, so "ADMIN" and "admin" both fail.
 *
 * Deliberately short: this is a floor, not a moderation system — reports and an
 * admin who can clear a title are what actually handle the rest.
 */
const BANNED = [
  // staff impersonation
  '운영자', '운영진', '관리자', '어드민', '스탭', '스태프', '시스템', '개발자', '지피엠',
  'admin', 'gm', 'staff', 'system', 'mod', 'owner', 'dev', 'support', 'root',
  // slurs / harassment, Korean shorthand included
  '시발', '씨발', 'ㅅㅂ', '병신', 'ㅂㅅ', '지랄', '좆', '섹스', '보지', '자지', '창녀', '느금',
  '한남', '한녀', '틀딱', '급식충', '장애인', '찐따', '죽어라', '자살',
  'fuck', 'fck', 'shit', 'bitch', 'cunt', 'nigg', 'rape', 'sex', 'porn', 'kys',
];

/**
 * @param {string} rawText
 * @param {string} colorId
 * @returns {{ok: true, text: string, color: string} | {ok: false, reason: string}}
 *   `reason` is a message KEY, translated by the caller.
 */
function validateCustomTitle(rawText, colorId) {
  if (typeof rawText !== 'string') {
    return { ok: false, reason: 'custom_title_empty' };
  }
  // NFC first: the same word can arrive decomposed, and both the length count
  // and the word list must see one canonical form.
  const text = rawText.normalize('NFC').trim();
  if (text.length === 0) return { ok: false, reason: 'custom_title_empty' };
  if (INVISIBLE.test(text) || COMBINING.test(text)) {
    return { ok: false, reason: 'custom_title_charset' };
  }
  if (!ALLOWED.test(text)) {
    return { ok: false, reason: 'custom_title_charset' };
  }
  if (graphemeLength(text) > MAX_GRAPHEMES) {
    return { ok: false, reason: 'custom_title_too_long' };
  }
  const flat = text.toLowerCase();
  if (BANNED.some((w) => flat.includes(w))) {
    return { ok: false, reason: 'custom_title_banned' };
  }
  if (!Object.prototype.hasOwnProperty.call(TITLE_COLORS, colorId)) {
    return { ok: false, reason: 'custom_title_color' };
  }
  return { ok: true, text, color: colorId };
}

/**
 * Count what a reader would call characters. "4자" has to mean four visible
 * things; code-unit length would let a surrogate pair count as two and a
 * decomposed syllable as three.
 */
function graphemeLength(text) {
  if (typeof Intl !== 'undefined' && Intl.Segmenter) {
    const seg = new Intl.Segmenter('ko', { granularity: 'grapheme' });
    let n = 0;
    for (const _ of seg.segment(text)) n++;
    return n;
  }
  return [...text].length;
}

module.exports = { validateCustomTitle, TITLE_COLORS, MAX_GRAPHEMES };
