'use strict';

/**
 * Demonstrates the whole point of the worker offload: event-loop latency under
 * concurrent bot load. Simulates N rooms each playing a mighty round, one
 * decision per event-loop turn (as the server does), and measures how late a
 * fixed-interval heartbeat fires — that lateness IS the stall every other room
 * (heartbeats, network I/O, human input) would experience.
 *
 *   INLINE: decisions run synchronously on the main thread -> big lag spikes.
 *   POOL:   decisions run in workers -> heartbeat stays on time.
 *
 *   node test_worker_lag.js
 */

const { BotWorkerPool } = require('./bots/BotWorkerPool');
const MightyGame = require('./game/mighty/MightyGame');
const { decideMightyBotAction } = require('./game/mighty/MightyBot');
const { makeRng } = require('./game/mighty/MightyDeck');

const ROOMS = parseInt(process.argv[2] || '8', 10);
const HEARTBEAT_MS = 20;

function newGame(seed) {
  const ids = ['p0', 'p1', 'p2', 'p3', 'p4'];
  const names = {}; for (const p of ids) names[p] = p;
  const g = new MightyGame(ids, names, { targetScore: 50, rng: makeRng(seed) });
  g.start();
  return g;
}

function nextActor(g) {
  if (g.state === 'trick_end') { g.advanceAfterTrickEnd(); }
  if (g.state === 'round_end' || g.state === 'game_end') return null;
  return g.getPendingActor();
}

function apply(g, actor, action) {
  let res = action ? g.handleAction(actor, action) : null;
  if (!res || res.success === false) {
    const fb = g.getAutoTimeoutAction(actor);
    if (fb) g.handleAction(actor, fb);
  }
}

// Measure how late a fixed-interval heartbeat fires. Overshoot beyond the
// interval == event-loop stall visible to every other room.
function startHeartbeat() {
  const stats = { max: 0, sum: 0, n: 0 };
  let last = process.hrtime.bigint();
  const h = setInterval(() => {
    const now = process.hrtime.bigint();
    const lag = Number(now - last) / 1e6 - HEARTBEAT_MS;
    if (lag > stats.max) stats.max = lag;
    if (lag > 0) { stats.sum += lag; stats.n++; }
    last = now;
  }, HEARTBEAT_MS);
  h.unref();
  return { stats, stop: () => clearInterval(h) };
}

// One room: play to round_end, one decision per event-loop turn. `decide`
// returns the action (sync inline, or a Promise for the pool). We always yield
// between decisions (setImmediate) so rooms interleave like the real server.
function runRoom(seed, decide) {
  return new Promise((resolve) => {
    const g = newGame(seed);
    let safety = 2000;
    const step = async () => {
      if (safety-- <= 0) return resolve();
      const actor = nextActor(g);
      if (!actor) return resolve();
      const action = await decide(g, actor);
      apply(g, actor, action);
      setImmediate(step);
    };
    step();
  });
}

async function run(label, decide, pool) {
  const hb = startHeartbeat();
  const t0 = process.hrtime.bigint();
  await Promise.all(Array.from({ length: ROOMS }, (_, i) => runRoom(1000 + i, decide)));
  const wall = Number(process.hrtime.bigint() - t0) / 1e6;
  hb.stop();
  const avg = hb.stats.n ? (hb.stats.sum / hb.stats.n) : 0;
  console.log(`  ${label.padEnd(6)} rooms=${ROOMS}  wall=${wall.toFixed(0)}ms  ` +
    `heartbeat maxLag=${hb.stats.max.toFixed(0)}ms avgLag=${avg.toFixed(1)}ms` +
    (pool ? `  poolMaxQueue=${pool.stats.maxQueue}` : ''));
  return hb.stats.max;
}

async function main() {
  console.log(`Event-loop lag under ${ROOMS} concurrent mighty rooms (mixoracle):`);

  // INLINE: synchronous decisions on the main thread.
  const inlineMax = await run('INLINE', (g, actor) =>
    Promise.resolve(decideMightyBotAction(g, actor, 'mixoracle')));

  // POOL: decisions offloaded to workers.
  const pool = new BotWorkerPool({ size: 4 });
  const poolMax = await run('POOL', (g, actor) =>
    pool.decide('mighty', g, actor, 'mixoracle').catch(() =>
      decideMightyBotAction(g, actor, 'mixoracle')), pool);
  await pool.destroy();

  const improvement = inlineMax > 0 ? (inlineMax / Math.max(poolMax, 0.1)) : 0;
  console.log(`\n  => worker offload cut peak event-loop stall ~${improvement.toFixed(0)}x ` +
    `(${inlineMax.toFixed(0)}ms -> ${poolMax.toFixed(0)}ms)`);
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
