/**
 * How evenly do the bots space their moves out?
 *
 *   node dev-host-room.js ws://localhost:8080 fast &   # a table that plays itself
 *   node test_bot_pace.mjs 티츄관전                      # watch it and time it
 *
 * Written because "봇이 다다닥 낸다" is a report about feel, and feel is what
 * nobody can settle by reading scheduling code.
 *
 * It SPECTATES. The first version sat at the table and played its own hand,
 * which was a mistake twice over: its instant replies were the fastest thing at
 * the table and showed up in the burst column as if the bots had made them, and
 * whenever a wish ("Q 카드를 내야 합니다") made its naive pick illegal the hand
 * stalled on its turn and the run came back with four samples. A spectator
 * cannot stall the game and cannot pollute the timings. dev-host-room.js is
 * what keeps the table moving.
 *
 * What it reports, and why each number earns its place:
 *
 *   p50            the intended rhythm.
 *   p90 / p50      the spread. This is the number that matters: a burst is not
 *                  slow moves or fast moves, it is UNEVEN ones. A table with a
 *                  steady 300ms beat reads as thinking; the same average made
 *                  of 90ms and 700ms reads as stalling and then rattling.
 *   over2x         gaps more than twice the median — the "it paused" half of
 *                  the complaint, counted.
 *   short          gaps under BURST_MS — the "then it rattled" half.
 *
 * Local servers only.
 */

const ROOM_NAME = process.argv[2] || '티츄관전';
const SECONDS = Number(process.argv[3] || 60);
const SERVER_URL = process.argv[4] || 'ws://localhost:8080';
const BURST_MS = 120;

const ACCOUNT = { username: 'web_smoke', password: 'websmoke1234!' };

const ws = new WebSocket(SERVER_URL);
const waiters = [];
const send = (m) => ws.send(JSON.stringify(m));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const stamps = [];   // every spectator_game_state that changed something
let lastSig = null;
let raw = 0;

// Only the things a watcher would actually see move. Without this the timings
// count re-sends of an identical board as if a bot had acted.
function sigOf(s) {
  if (!s) return null;
  return JSON.stringify({
    cur: s.currentPlayer,
    trick: (s.currentTrick || []).length,
    top: (s.currentTrick || []).map((t) => (t.cards || t.card || []).toString()).join('|'),
    phase: s.phase,
    hands: (s.players || []).map((p) => p.cardCount ?? p.handCount ?? 0),
  });
}

ws.addEventListener('message', (ev) => {
  const msg = JSON.parse(ev.data);
  if (msg.type === 'spectator_game_state' || msg.type === 'game_state') {
    raw += 1;
    const sig = sigOf(msg.state);
    if (sig !== lastSig) { stamps.push(Date.now()); lastSig = sig; }
  }
  if (msg.type === 'error') console.log('  server error:', msg.message);
  for (let i = waiters.length - 1; i >= 0; i--) {
    if (waiters[i].match(msg)) waiters.splice(i, 1)[0].resolve(msg);
  }
});

function waitFor(type, ms = 15000) {
  const pred = typeof type === 'string' ? (m) => m.type === type : type;
  return new Promise((res, rej) => {
    const w = { match: pred, resolve: res };
    waiters.push(w);
    setTimeout(() => {
      const i = waiters.indexOf(w);
      if (i !== -1) { waiters.splice(i, 1); rej(new Error(`timed out waiting for ${type}`)); }
    }, ms);
  });
}

await new Promise((r) => ws.addEventListener('open', r));
send({ type: 'login', ...ACCOUNT, deviceInfo: { devicePlatform: 'web', appVersion: '2.8.3', locale: 'ko' } });
await waitFor('login_success');
send({ type: 'check_room' });
await waitFor((m) => m.type === 'restore_complete' || m.type === 'room_state').catch(() => {});
send({ type: 'leave_room' });
await sleep(400);

send({ type: 'room_list' });
const list = await waitFor('room_list');
const room = (list.rooms || []).find((r) => r.name === ROOM_NAME);
if (!room) {
  console.log(`no room named "${ROOM_NAME}". Start one first:\n  node dev-host-room.js ws://localhost:8080 fast &`);
  process.exit(1);
}
send({ type: 'spectate_room', roomId: room.id });
await sleep(1500);

console.log(`spectating "${ROOM_NAME}" for ${SECONDS}s...\n`);
stamps.length = 0;                       // drop the join burst
await sleep(SECONDS * 1000);

const gaps = stamps.slice(1).map((t, i) => t - stamps[i]);
if (gaps.length < 30) {
  console.log(`!! SAMPLE TOO SMALL (${gaps.length} gaps) — is the table actually playing?`);
  process.exit(1);
}
const sorted = [...gaps].sort((a, b) => a - b);
const q = (p) => sorted[Math.floor((sorted.length - 1) * p)];
const p50 = q(0.5);
const over2x = gaps.filter((g) => g > p50 * 2).length;
const short = gaps.filter((g) => g < BURST_MS).length;

console.log(`updates: ${raw} raw, ${stamps.length} that changed the board`);
console.log(`gaps:    n=${gaps.length}  p50=${p50}ms  p90=${q(0.9)}ms  max=${sorted.at(-1)}ms`);
console.log(`spread:  p90/p50 = ${(q(0.9) / p50).toFixed(2)}   <-- evenness; lower is smoother`);
console.log(`paused:  ${over2x} gaps over 2x median (${(100 * over2x / gaps.length).toFixed(0)}%)`);
console.log(`rattled: ${short} gaps under ${BURST_MS}ms (${(100 * short / gaps.length).toFixed(0)}%)`);
process.exit(0);
