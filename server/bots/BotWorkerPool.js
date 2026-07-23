'use strict';

/**
 * Fixed-size pool of bot-decision worker threads.
 *
 * Why: bot search (mighty mixoracle/oracle/solver, tichu winrate) is a
 * synchronous 40-100ms CPU burst. On the single main thread, N rooms deciding
 * near the same tick serialize into N*~100ms of blocking that freezes every
 * room's heartbeat/input and kicks human players. Moving the search into
 * workers keeps the event loop free.
 *
 * The bounded worker set doubles as the *global bot concurrency limit*: at
 * most `size` decisions run at once; the rest queue. This is the structural
 * cap that a per-room setTimeout scheme never had.
 *
 * decide() resolves with the action (or null). It REJECTS on worker
 * timeout/crash — callers must fall back to a cheap synchronous decision so a
 * game never hangs on a sick worker.
 */

const os = require('os');
const path = require('path');
const { Worker } = require('worker_threads');

const WORKER_FILE = path.join(__dirname, 'botWorker.js');

// Circuit-breaker tuning. A worker that dies within LOAD_FAIL_MS of spawn
// without ever completing a job is treated as a *load* failure (e.g. a
// require() that throws in the container). MAX_LOAD_FAILURES such failures
// WITHIN LOAD_FAIL_WINDOW_MS opens the circuit: the pool disables itself and
// every decide() rejects immediately so callers fall back to a cheap inline
// decision — instead of a tight respawn loop pegging a core while the main
// thread also drowns in expensive inline fallbacks. After REENABLE_MS it
// probes once more. The window (not a consecutive counter) is deliberate: a
// single poisoned worker respawning every ~250ms must trip the breaker even
// while healthy sibling workers keep completing jobs.
const LOAD_FAIL_MS = 4000;
const LOAD_FAIL_WINDOW_MS = 30000;
const MAX_LOAD_FAILURES = 6;
const BASE_BACKOFF_MS = 250;
const MAX_BACKOFF_MS = 10000;
const REENABLE_MS = 60000;

function defaultSize() {
  const env = parseInt(process.env.BOT_WORKERS || '', 10);
  if (Number.isFinite(env) && env > 0) return env;
  // Leave a core for the main loop; cap so a big box doesn't spawn dozens.
  const cores = (os.cpus() || []).length || 2;
  return Math.max(1, Math.min(4, cores - 1));
}

class BotWorkerPool {
  constructor(opts = {}) {
    this.size = opts.size || defaultSize();
    this._workerFile = opts.workerFile || WORKER_FILE; // override for tests
    this.defaultTimeoutMs = opts.timeoutMs || 800; // generous safety net; bots self-limit to ~100ms
    this._idc = 0;
    this._pending = new Map();   // id -> job
    this._queue = [];            // jobs waiting for a free worker
    this._workers = [];          // { worker, busy, gen, spawnedAt, completed }
    this.disabled = false;       // circuit open -> decide() rejects, caller inlines
    this._destroyed = false;
    this._loadFailures = [];     // timestamps of recent load failures (sliding window)
    this._gen = 0;               // monotonic worker id; stale events are ignored
    this._respawnTimers = new Set();
    this._reenableTimer = null;
    // Lightweight counters for DIAG.
    this.stats = { dispatched: 0, completed: 0, errors: 0, timeouts: 0, maxQueue: 0, disables: 0 };
    for (let i = 0; i < this.size; i++) this._spawn(i);
  }

  _spawn(idx) {
    if (this.disabled) return;
    const worker = new Worker(this._workerFile);
    const slot = { worker, busy: false, gen: ++this._gen, spawnedAt: Date.now(), completed: false };
    // Identity-guard every listener: after a terminate()+respawn, the OLD
    // worker's late 'exit'/'error'/'message' must NOT touch the fresh slot now
    // sitting at the same idx (that would spuriously reject the new worker's
    // job and respawn a healthy worker). Compare against the current occupant.
    worker.on('message', (msg) => { if (this._workers[idx] === slot) this._onMessage(idx, slot, msg); });
    worker.on('error', (err) => { if (this._workers[idx] === slot) this._onWorkerFailure(idx, slot, err); });
    // Respawn on ANY exit, not just non-zero: a long-lived message-loop worker
    // should never exit on its own, so even a clean exit(0) means a dead slot.
    // Intentional terminate()s are already filtered by the identity guard (the
    // slot is nulled/replaced before terminate), so this only fires for a
    // worker that died while still the current occupant.
    worker.on('exit', (code) => { if (this._workers[idx] === slot) this._onWorkerFailure(idx, slot, new Error(`worker exit ${code}`)); });
    this._workers[idx] = slot;
  }

  /**
   * @param {string} gameType  'mighty' | 'tichu'
   * @param {object} game      live game instance (must have serialize())
   * @param {string} botId
   * @param {string} strat
   * @param {number} [timeoutMs]
   * @returns {Promise<object|null>} action, or rejects on timeout/crash
   */
  decide(gameType, game, botId, strat, timeoutMs) {
    if (this.disabled) return Promise.reject(new Error('bot pool disabled'));
    let state;
    try {
      state = game.serialize();
    } catch (e) {
      return Promise.reject(new Error(`serialize failed: ${(e && e.message) || e}`));
    }
    return new Promise((resolve, reject) => {
      const job = {
        gameType, botId, strat, state,
        timeoutMs: timeoutMs || this.defaultTimeoutMs,
        resolve, reject,
      };
      const freeIdx = this._workers.findIndex((w) => w && !w.busy);
      if (freeIdx >= 0) this._dispatch(freeIdx, job);
      else {
        this._queue.push(job);
        if (this._queue.length > this.stats.maxQueue) this.stats.maxQueue = this._queue.length;
      }
    });
  }

  _dispatch(idx, job) {
    const slot = this._workers[idx];
    const id = ++this._idc;
    slot.busy = true;
    job.id = id;
    job.workerIdx = idx;
    job.timer = setTimeout(() => this._onTimeout(id), job.timeoutMs);
    this._pending.set(id, job);
    this.stats.dispatched++;
    slot.worker.postMessage({
      id, gameType: job.gameType, botId: job.botId, strat: job.strat, state: job.state,
    });
  }

  _onMessage(idx, slot, msg) {
    const job = this._pending.get(msg.id);
    if (!job) return; // already timed out / respawned
    this._pending.delete(msg.id);
    clearTimeout(job.timer);
    slot.busy = false;
    slot.completed = true;            // this worker loaded & ran fine
    // NOTE: do NOT clear _loadFailures here. Successes must not mask a single
    // worker that keeps load-failing — old failures age out of the window on
    // their own (see _onWorkerFailure).
    if (msg.error) { this.stats.errors++; job.reject(new Error(msg.error)); }
    else { this.stats.completed++; job.resolve(msg.action); }
    this._drain(idx);
  }

  _onTimeout(id) {
    const job = this._pending.get(id);
    if (!job) return;
    this._pending.delete(id);
    this.stats.timeouts++;
    // The worker is stuck in a synchronous burst and cannot be interrupted;
    // terminate and respawn (immediately — a timeout is normal under load, not
    // a load failure, so it must not reduce capacity or trip the breaker).
    job.reject(new Error('bot worker timeout'));
    this._respawn(job.workerIdx, 0);
  }

  _onWorkerFailure(idx, slot, err) {
    // Reject whatever this worker was running.
    for (const [id, job] of this._pending) {
      if (job.workerIdx === idx) {
        this._pending.delete(id);
        clearTimeout(job.timer);
        this.stats.errors++;
        job.reject(err instanceof Error ? err : new Error(String(err)));
      }
    }
    // A worker that died young without ever completing a job is almost
    // certainly a load-time failure (bad require / build) that will recur on
    // every respawn — count it in a sliding window and back off.
    const now = Date.now();
    const loadFailure = !slot.completed && (now - slot.spawnedAt) < LOAD_FAIL_MS;
    if (loadFailure) {
      this._loadFailures.push(now);
      const cutoff = now - LOAD_FAIL_WINDOW_MS;
      while (this._loadFailures.length && this._loadFailures[0] < cutoff) this._loadFailures.shift();
      const n = this._loadFailures.length;
      if (n >= MAX_LOAD_FAILURES) { this._disable(err); return; }
      const backoff = Math.min(MAX_BACKOFF_MS, BASE_BACKOFF_MS * 2 ** (n - 1));
      this._respawn(idx, backoff);
    } else {
      this._respawn(idx, 0);
    }
  }

  _respawn(idx, delayMs = 0) {
    const old = this._workers[idx];
    this._workers[idx] = null;
    if (old && old.worker) { try { old.worker.terminate(); } catch (_) {} }
    if (this.disabled) return;
    if (delayMs > 0) {
      const t = setTimeout(() => {
        this._respawnTimers.delete(t);
        if (this.disabled) return;
        this._spawn(idx);
        this._drain(idx);
      }, delayMs);
      if (t.unref) t.unref();
      this._respawnTimers.add(t);
    } else {
      this._spawn(idx);
      this._drain(idx);
    }
  }

  // Circuit open: stop respawning, reject everything in flight/queued so callers
  // fall back to a cheap inline decision, and probe again after a cooldown.
  _disable(err) {
    if (this.disabled) return;
    this.disabled = true;
    this.stats.disables++;
    console.error(`[BOT] worker pool DISABLED after ${this._loadFailures.length} load failures in ${LOAD_FAIL_WINDOW_MS}ms — decisions run inline until re-probe. ${(err && err.message) || err}`);
    for (const [, job] of this._pending) { clearTimeout(job.timer); try { job.reject(new Error('bot pool disabled')); } catch (_) {} }
    this._pending.clear();
    for (const job of this._queue) { try { job.reject(new Error('bot pool disabled')); } catch (_) {} }
    this._queue = [];
    for (const t of this._respawnTimers) clearTimeout(t);
    this._respawnTimers.clear();
    for (const slot of this._workers) { if (slot && slot.worker) { try { slot.worker.terminate(); } catch (_) {} } }
    this._workers = [];
    this._reenableTimer = setTimeout(() => this._reenable(), REENABLE_MS);
    if (this._reenableTimer.unref) this._reenableTimer.unref();
  }

  _reenable() {
    if (this._destroyed || !this.disabled) return; // never resurrect a destroyed pool
    console.log('[BOT] worker pool re-probing after cooldown');
    this.disabled = false;
    this._loadFailures = [];
    this._reenableTimer = null;
    for (let i = 0; i < this.size; i++) this._spawn(i);
  }

  _drain(idx) {
    const slot = this._workers[idx];
    if (slot && !slot.busy && this._queue.length > 0) {
      this._dispatch(idx, this._queue.shift());
    }
  }

  get queueDepth() { return this._queue.length; }
  get inFlight() { return this._pending.size; }

  async destroy() {
    this._destroyed = true;
    this.disabled = true; // stop any pending respawns from re-spawning
    for (const t of this._respawnTimers) clearTimeout(t);
    this._respawnTimers.clear();
    if (this._reenableTimer) { clearTimeout(this._reenableTimer); this._reenableTimer = null; }
    // Drop slot identity BEFORE terminating so the terminate()-triggered exit
    // events are ignored by the listener guard (no failure-path spin).
    const workers = this._workers;
    this._workers = [];
    // Settle every outstanding promise so no caller hangs (mirror _disable);
    // queued jobs have no worker/timer and would otherwise never resolve.
    for (const [, job] of this._pending) { clearTimeout(job.timer); try { job.reject(new Error('bot pool destroyed')); } catch (_) {} }
    this._pending.clear();
    for (const job of this._queue) { try { job.reject(new Error('bot pool destroyed')); } catch (_) {} }
    this._queue = [];
    for (const slot of workers) {
      if (slot && slot.worker) { try { await slot.worker.terminate(); } catch (_) {} }
    }
  }
}

module.exports = { BotWorkerPool, defaultSize };
