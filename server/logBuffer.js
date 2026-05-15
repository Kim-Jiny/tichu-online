// In-memory log ring buffer + live fan-out for the admin log viewer.
//
// The server logs only to stdout (console.*), captured by Docker/Render. To
// show a live tail in the admin panel we wrap console.* so each call ALSO
// lands in a bounded ring buffer and is pushed to any connected SSE clients —
// while still calling the original method so stdout/`docker logs` is unchanged.
//
// Scope/limits (surface these in the UI): in-memory only (lost on restart),
// just the most recent MAX_LINES, and per-instance — under blue/green you see
// only the instance nginx currently routes to. For full history use the
// platform log (Render dashboard / `docker logs`).

const util = require('util');

const MAX_LINES = 1500;
const MAX_LINE_CHARS = 4000; // truncate pathological lines (raw payload dumps)

const ring = []; // [{ seq, ts, level, line }]
let seq = 0;
const subscribers = new Set(); // Set<(entry) => void>
let installed = false;
// Guard against re-entrancy: if a subscriber callback (or util.format) itself
// logs, we must not recurse into capture.
let inCapture = false;

function record(level, args) {
  let line;
  try {
    line = util.format(...args);
  } catch (_) {
    line = '[logBuffer: unformattable log args]';
  }
  if (line.length > MAX_LINE_CHARS) {
    line = line.slice(0, MAX_LINE_CHARS) + ` …(+${line.length - MAX_LINE_CHARS} chars truncated)`;
  }
  const entry = { seq: ++seq, ts: Date.now(), level, line };
  ring.push(entry);
  if (ring.length > MAX_LINES) ring.shift();
  for (const fn of subscribers) {
    try {
      fn(entry);
    } catch (_) {
      // A broken subscriber must never break logging.
    }
  }
}

// Replace console.* once. Returns silently if already installed so repeated
// requires (or hot reload) don't stack wrappers.
function installConsoleCapture() {
  if (installed) return;
  installed = true;
  const levels = {
    log: 'info',
    info: 'info',
    warn: 'warn',
    error: 'error',
    debug: 'debug',
  };
  for (const [method, level] of Object.entries(levels)) {
    const original = console[method].bind(console);
    console[method] = (...args) => {
      original(...args);
      if (inCapture) return;
      inCapture = true;
      try {
        record(level, args);
      } finally {
        inCapture = false;
      }
    };
  }
}

// Snapshot of the current buffer, optionally only entries after `afterSeq`
// (used by the SSE client to resume without dupes after a reconnect).
function snapshot(afterSeq = 0) {
  return afterSeq > 0 ? ring.filter((e) => e.seq > afterSeq) : ring.slice();
}

function subscribe(fn) {
  subscribers.add(fn);
  return () => subscribers.delete(fn);
}

module.exports = { installConsoleCapture, snapshot, subscribe, MAX_LINES };
