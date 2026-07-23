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
    this.defaultTimeoutMs = opts.timeoutMs || 800; // generous safety net; bots self-limit to ~100ms
    this._idc = 0;
    this._pending = new Map();   // id -> job
    this._queue = [];            // jobs waiting for a free worker
    this._workers = [];          // { worker, busy }
    // Lightweight counters for DIAG.
    this.stats = { dispatched: 0, completed: 0, errors: 0, timeouts: 0, maxQueue: 0 };
    for (let i = 0; i < this.size; i++) this._spawn(i);
  }

  _spawn(idx) {
    const worker = new Worker(WORKER_FILE);
    const slot = { worker, busy: false };
    worker.on('message', (msg) => this._onMessage(idx, msg));
    worker.on('error', (err) => this._onWorkerFailure(idx, err));
    worker.on('exit', (code) => { if (code !== 0) this._onWorkerFailure(idx, new Error(`worker exit ${code}`)); });
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

  _onMessage(idx, msg) {
    const job = this._pending.get(msg.id);
    if (!job) return; // already timed out / respawned
    this._pending.delete(msg.id);
    clearTimeout(job.timer);
    const slot = this._workers[idx];
    if (slot) slot.busy = false;
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
    // terminate and respawn so it doesn't wedge the slot forever.
    job.reject(new Error('bot worker timeout'));
    this._respawn(job.workerIdx);
  }

  _onWorkerFailure(idx, err) {
    // Reject whatever this worker was running, then respawn.
    for (const [id, job] of this._pending) {
      if (job.workerIdx === idx) {
        this._pending.delete(id);
        clearTimeout(job.timer);
        this.stats.errors++;
        job.reject(err instanceof Error ? err : new Error(String(err)));
      }
    }
    this._respawn(idx);
  }

  _respawn(idx) {
    const old = this._workers[idx];
    this._workers[idx] = null;
    if (old && old.worker) { try { old.worker.terminate(); } catch (_) {} }
    this._spawn(idx);
    this._drain(idx);
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
    for (const slot of this._workers) {
      if (slot && slot.worker) { try { await slot.worker.terminate(); } catch (_) {} }
    }
    this._workers = [];
  }
}

module.exports = { BotWorkerPool, defaultSize };
