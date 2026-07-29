'use strict';
/**
 * The freeze threshold has to outlast a legal turn, or the detector reports
 * healthy rooms. Turn limits are player-chosen (10..999s, see handleCreateRoom)
 * and several phases double them, so a flat five minutes was wrong for any
 * room above ~150s.
 */

const assert = require('assert');
const { freezeThresholdMs, FREEZE_FLOOR_MS } = require('./game/freezeWatch');

let failures = 0;
function check(label, fn) {
  try { fn(); console.log(`  ok   ${label}`); }
  catch (e) { failures++; console.log(`  FAIL ${label} — ${e.message}`); }
}

// The clamp handleCreateRoom applies.
const MIN_LIMIT = 10;
const MAX_LIMIT = 999;

check('short limits still get the five-minute floor', () => {
  assert.strictEqual(freezeThresholdMs(10), FREEZE_FLOOR_MS);
  assert.strictEqual(freezeThresholdMs(30), FREEZE_FLOOR_MS);
  // 30s doubled + slack is 61s, well under the floor.
  assert.strictEqual(freezeThresholdMs(120), FREEZE_FLOOR_MS);
});

check('a long limit raises the threshold past its own doubled turn', () => {
  // The production case: a room somewhere above 300s warned every 5 minutes.
  assert.ok(freezeThresholdMs(400) > 400 * 2 * 1000,
    `400s room: ${freezeThresholdMs(400)}ms`);
  assert.ok(freezeThresholdMs(MAX_LIMIT) > MAX_LIMIT * 2 * 1000,
    `max room: ${freezeThresholdMs(MAX_LIMIT)}ms`);
});

check('no legal turn limit can trip the detector on its own', () => {
  for (let limit = MIN_LIMIT; limit <= MAX_LIMIT; limit++) {
    // Worst case a room can legitimately sit still: a doubled-time phase.
    const longestLegalWait = limit * 2 * 1000;
    assert.ok(
      freezeThresholdMs(limit) > longestLegalWait,
      `limit=${limit}s: threshold ${freezeThresholdMs(limit)}ms <= legal wait ${longestLegalWait}ms`,
    );
  }
});

check('threshold never decreases as the limit grows', () => {
  let previous = 0;
  for (let limit = MIN_LIMIT; limit <= MAX_LIMIT; limit++) {
    const t = freezeThresholdMs(limit);
    assert.ok(t >= previous, `limit=${limit}s went backwards`);
    previous = t;
  }
});

check('garbage falls back to the default limit, not NaN', () => {
  for (const bad of [undefined, null, NaN, 0, -5, 'abc']) {
    const t = freezeThresholdMs(bad);
    assert.ok(Number.isFinite(t) && t >= FREEZE_FLOOR_MS, `${String(bad)} -> ${t}`);
  }
});

console.log(failures === 0 ? '\nALL PASS' : `\n${failures} FAILURE(S)`);
process.exit(failures === 0 ? 0 : 1);
