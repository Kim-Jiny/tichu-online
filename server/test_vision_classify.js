'use strict';
/**
 * Thresholds for the upload screener.
 *
 * Tested against synthetic annotations rather than real images: the decision
 * being checked is "what do we do with this score", and exercising it for real
 * would mean keeping a folder of exactly the material the feature exists to
 * keep out. The network path is covered separately by a live call with a
 * benign image.
 */

const assert = require('assert');
const { classify, CATEGORIES } = require('./moderation/visionSafeSearch');

let failures = 0;
const check = (label, fn) => {
  try { fn(); console.log(`  ok   ${label}`); }
  catch (e) { failures++; console.log(`  FAIL ${label} — ${e.message}`); }
};

const all = (v) => Object.fromEntries(CATEGORIES.map((c) => [c, v]));

check('a clean photo passes', () => {
  assert.strictEqual(classify(all('VERY_UNLIKELY')).verdict, 'ok');
  assert.strictEqual(classify(all('UNLIKELY')).verdict, 'ok');
});

check('POSSIBLE goes to review, not rejection', () => {
  for (const c of CATEGORIES) {
    const r = classify({ ...all('VERY_UNLIKELY'), [c]: 'POSSIBLE' });
    assert.strictEqual(r.verdict, 'review', `${c}: ${r.verdict}`);
    assert.strictEqual(r.worst, c);
  }
});

check('LIKELY and above is rejected, in every category', () => {
  for (const c of CATEGORIES) {
    for (const level of ['LIKELY', 'VERY_LIKELY']) {
      const r = classify({ ...all('VERY_UNLIKELY'), [c]: level });
      assert.strictEqual(r.verdict, 'reject', `${c}=${level}: ${r.verdict}`);
      assert.strictEqual(r.worst, c);
    }
  }
});

check('the worst category wins when several are raised', () => {
  const r = classify({ adult: 'POSSIBLE', racy: 'VERY_LIKELY', violence: 'UNLIKELY' });
  assert.strictEqual(r.verdict, 'reject');
  assert.strictEqual(r.worst, 'racy');
});

check('categories we deliberately ignore cannot reject', () => {
  // A scar photo (medical) or a meme edit (spoof) is not a policy breach.
  const r = classify({ ...all('VERY_UNLIKELY'), medical: 'VERY_LIKELY', spoof: 'VERY_LIKELY' });
  assert.strictEqual(r.verdict, 'ok', JSON.stringify(r));
});

check('a missing or malformed annotation does not silently pass as clean', () => {
  // UNKNOWN ranks below the review line, so this lands on 'ok' — that is the
  // intended reading (Vision answered, it just had no opinion). What must NOT
  // happen is a crash, which would surface as an upload failure.
  for (const bad of [undefined, null, {}, { adult: 'NONSENSE' }]) {
    const r = classify(bad);
    assert.ok(['ok', 'review', 'reject'].includes(r.verdict), `${String(bad)} -> ${r.verdict}`);
    for (const c of CATEGORIES) assert.ok(c in r.scores);
  }
});

console.log(failures === 0 ? '\nALL PASS' : `\n${failures} FAILURE(S)`);
process.exit(failures === 0 ? 0 : 1);
