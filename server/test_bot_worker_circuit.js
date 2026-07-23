'use strict';

/**
 * Circuit-breaker test: a worker that fails to LOAD (bad require) must not spin
 * in a tight respawn loop. After MAX_LOAD_FAILURES the pool disables itself and
 * decide() rejects immediately so the caller falls back to a cheap inline
 * decision — instead of pegging a core forever. Then it re-probes after cooldown.
 *
 *   node test_bot_worker_circuit.js
 */

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { BotWorkerPool } = require('./bots/BotWorkerPool');

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  // A worker file that throws at load time (simulates a bad build / missing dep
  // in the container). __dirname is stable; no Date.now in the filename needed.
  const badFile = path.join(os.tmpdir(), 'tichu_bad_worker_test.js');
  fs.writeFileSync(badFile, 'throw new Error("simulated load failure");\n');

  const pool = new BotWorkerPool({ size: 1, workerFile: badFile });

  // Give the respawn/backoff loop time to rack up MAX_LOAD_FAILURES (6) and open.
  const t0 = Date.now();
  while (!pool.disabled && Date.now() - t0 < 15000) await sleep(200);
  assert.ok(pool.disabled, `pool did not disable after repeated load failures (stats=${JSON.stringify(pool.stats)})`);
  assert.ok(pool.stats.disables >= 1, 'disable not counted');
  console.log(`  circuit opened after load failures (disables=${pool.stats.disables})`);

  // While disabled, decide() must reject immediately (caller then inlines).
  const fakeGame = { serialize: () => ({}) };
  let rejected = false;
  try { await pool.decide('mighty', fakeGame, 'bot_1', 'mixoracle'); }
  catch (e) { rejected = /disabled/.test(e.message); }
  assert.ok(rejected, 'decide() should reject immediately while pool is disabled');
  console.log('  decide() rejects fast while disabled → caller falls back inline');

  // The pool must NOT be spinning: worker count is 0 while disabled.
  assert.strictEqual(pool._workers.length, 0, 'no workers should be alive while disabled');

  await pool.destroy();
  fs.unlinkSync(badFile);

  // Sanity: a healthy pool (real worker) still works after all this.
  const good = new BotWorkerPool({ size: 1 });
  const MightyGame = require('./game/mighty/MightyGame');
  const { makeRng } = require('./game/mighty/MightyDeck');
  const ids = ['p0', 'p1', 'p2', 'p3', 'p4'];
  const names = {}; for (const p of ids) names[p] = p;
  const g = new MightyGame(ids, names, { targetScore: 50, rng: makeRng(5) });
  g.start();
  const actor = g.getPendingActor();
  const action = await good.decide('mighty', g, actor, 'mixoracle');
  assert.ok(action, 'healthy pool should still produce a decision');
  await good.destroy();
  console.log('  healthy pool unaffected — still decides');

  console.log('OK — circuit breaker opens on load failures, rejects fast, and healthy pools work.');
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
