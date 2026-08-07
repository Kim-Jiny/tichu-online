/**
 * How far apart do the bots' moves actually land?
 *
 *   node test_bot_pace.mjs [fast|normal|slow] [ws://localhost:8080]
 *
 * Written because "봇이 다다닥 낸다" is a report about feel, and feel is what
 * nobody can settle by reading scheduling code. This sits a player at a table
 * with three bots, plays the minimum needed to keep the hand moving, and times
 * every game_state that arrives.
 *
 * What it prints, and why each number earns its place:
 *
 *   p50 / p90     the normal rhythm. If these look right, the burst is not the
 *                 delay constants and raising them will only make the game slow
 *                 without making it smooth.
 *   redundant     game_state messages that changed nothing observable. Each is
 *                 a repaint the client did for no reason.
 *   short gaps    every pair under BURST_MS, CLASSIFIED. A second card played
 *                 is a scheduling bug; a trick collected 30ms after the winning
 *                 card is a pacing bug; a turn advancing with no card and no
 *                 hand change is a third thing again. Lumping them together is
 *                 how you end up fixing the wrong one — which is exactly what
 *                 the first read of this did.
 *
 * Local servers only: it creates a room and plays a real hand.
 */
const SPEED = process.argv[2] || 'fast';
const GAME = process.argv[3] || 'tichu';
const SERVER_URL = process.argv[4] || 'ws://localhost:8080';
const SEATS = GAME === 'skull_king' ? 6 : GAME === 'mighty' ? 6 : 4;
const BURST_MS = 120; // below this two moves read as simultaneous

const ACCOUNT = { username: 'web_smoke', password: 'websmoke1234!' };
const APP_VERSION = '2.8.3';

const ws = new WebSocket(SERVER_URL);
const waiters = [];
let state = null;
let myMovePending = false;
let myBidPending = false;
let rejected = false;
let myId = null;
const send = (m) => ws.send(JSON.stringify(m));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Every observed state, stamped. A bot "acted" whenever the set of cards on
// the table or the current player changed without us doing anything.
const events = [];
const raw = [];   // every game_state, changed or not
let lastSig = null;

function sigOf(s) {
  if (!s) return null;
  return JSON.stringify({
    cur: s.currentPlayer,
    // Bids are the other thing that can arrive in a burst — in Skull King
    // every seat bids before anyone plays.
    bids: (s.players || []).map((p) => (p.hasBid ? 1 : 0)).join(''),
    trick: (s.currentTrick || []).length,
    top: (s.currentTrick || []).map((t) => (t.cards || []).join(',')).join('|'),
    phase: s.phase,
    hands: (s.players || []).map((p) => p.cardCount ?? p.handCount ?? 0),
  });
}

ws.addEventListener('message', (ev) => {
  const msg = JSON.parse(ev.data);
  if (msg.type === 'error') {
    // A wish ("Q 카드를 내야 합니다") makes our naive pick illegal. Passing is
    // always legal mid-trick, and keeping the hand moving is the whole point —
    // without this the sample dies on the first Bird of the game.
    rejected = true;
    if (state?.phase === 'playing' && (state.currentTrick || []).length > 0) send({ type: 'pass' });
  }
  if (msg.type === 'game_state') {
    raw.push(Date.now());
    state = msg.state;
    if (!myId) myId = (msg.state.players || []).find((p) => !p.isBot)?.id ?? null;
    const sig = sigOf(state);
    if (sig !== lastSig) {
      events.push({
        t: Date.now(),
        phase: state.phase,
        cur: state.currentPlayer,
        trick: (state.currentTrick || []).length,
        bidsIn: state.phase === 'bidding' || (state.players || []).some((p) => p.hasBid)
          ? (state.players || []).filter((p) => p.hasBid).length
          : null,
        // Whose card just landed, if any — the last entry in the trick.
        by: (state.currentTrick || []).at(-1)?.playerId
            ?? (state.currentTrick || []).at(-1)?.player ?? null,
        handList: (state.players || []).map((x) => x.cardCount ?? x.handCount ?? 0),
        ids: (state.players || []).map((x) => x.id ?? x.playerId ?? null),
        hands: (state.players || []).map((x) => x.cardCount ?? x.handCount ?? 0).join('/'),
      });
      lastSig = sig;
    }
  }
  for (let i = waiters.length - 1; i >= 0; i--) {
    if (waiters[i].match(msg)) waiters.splice(i, 1)[0].resolve(msg);
  }
});

function waitFor(type, ms = 20000) {
  const pred = typeof type === 'string' ? (m) => m.type === type : type;
  return new Promise((res, rej) => {
    const w = { match: pred, resolve: res };
    waiters.push(w);
    setTimeout(() => {
      const i = waiters.indexOf(w);
      if (i !== -1) { waiters.splice(i, 1); rej(new Error(`timeout ${type}`)); }
    }, ms);
  });
}

await new Promise((r) => ws.addEventListener('open', r));
send({ type: 'login', ...ACCOUNT, deviceInfo: { devicePlatform: 'web', appVersion: APP_VERSION, locale: 'ko' } });
await waitFor('login_success');
send({ type: 'check_room' });
await waitFor((m) => m.type === 'restore_complete' || m.type === 'room_state').catch(() => {});
send({ type: 'leave_room' });
await sleep(500);
send({ type: 'create_room', gameType: GAME, roomName: 'pace', password: '',
       turnTimeLimit: 60, targetScore: 3000, maxPlayers: SEATS,
       allowSpectators: true, isRanked: false });
await waitFor('room_joined');
for (const slot of Array.from({ length: SEATS - 1 }, (_, i) => i + 1)) { send({ type: 'add_bot', speed: SPEED, targetSlot: slot }); await sleep(300); }
send({ type: 'toggle_ready' });
await sleep(300);
send({ type: 'start_game' });
await waitFor('game_state');

// Decline everything we are asked for, and never play: we only want to watch
// the bots. The turn timer will auto-pass for us if it comes round.
// Field names lifted from test_web_protocol.mjs, which is known to drive a
// real round to completion.
const decline = () => {
  if (!state) return;
  if (state.phase === 'large_tichu_phase' && !state.largeTichuResponded) {
    send({ type: 'pass_large_tichu' });
  }
  if (state.phase === 'card_exchange' && !state.exchangeDone && (state.myCards || []).length >= 3) {
    const c = state.myCards;
    send({ type: 'exchange_cards', cards: { left: c[0], partner: c[1], right: c[2] } });
  }
  // Play as soon as it is our turn, so the table keeps moving and we can see
  // how the bots space themselves out between our turns.
  // Skull King: bid the minimum, then follow suit with whatever is legal.
  if (state.phase === 'bidding' && !(state.players || []).some((p) => p.id === myId && p.hasBid)) {
    // Bid on a human-ish delay too, for the same reason we play on one.
    if (!myBidPending) {
      myBidPending = true;
      setTimeout(() => { send({ type: 'submit_bid', bid: 0 }); myBidPending = false; }, 900);
    }
  }
  // Our own turn is answered on a human-ish delay. Playing instantly made the
  // probe itself the fastest actor at the table, and its own moves then showed
  // up in the burst column — the first read of Skull King was entirely this.
  if (GAME === 'skull_king' && state.phase === 'playing' && state.isMyTurn && !myMovePending) {
    const card = (state.myCards || [])[0];
    if (card) {
      myMovePending = true;
      setTimeout(() => { send({ type: 'play_card', cardId: card.id ?? card }); myMovePending = false; }, 900);
    }
  }
  if (GAME === 'tichu' && state.phase === 'playing' && state.isMyTurn) {
    if ((state.currentTrick || []).length === 0) {
      const lead = (state.myCards || []).find((x) => x !== 'special_dog');
      if (lead) send({ type: 'play_cards', cards: [lead] });
    } else {
      send({ type: 'pass' });
    }
  }
};
const declineTimer = setInterval(decline, 400);

console.log(`watching a ${SPEED}-bot ${GAME} table (${SEATS} seats) for 40s...\n`);
await sleep(40000);
clearInterval(declineTimer);

const gaps = [];
for (let i = 1; i < events.length; i++) gaps.push(events[i].t - events[i - 1].t);
const bursts = gaps.filter((g) => g < BURST_MS);
const sorted = [...gaps].sort((a, b) => a - b);
const pct = (p) => sorted.length ? sorted[Math.floor((sorted.length - 1) * p)] : 0;

const mySeat = (events.at(-1)?.ids || []).indexOf(myId);
const rawGaps = raw.slice(1).map((t, i) => t - raw[i]);
console.log(`game_state messages: ${raw.length}   (of which changed something: ${events.length})`);
console.log(`redundant broadcasts: ${raw.length - events.length}`);
console.log(`raw gaps <120ms: ${rawGaps.filter((g) => g < 120).length} / ${rawGaps.length}`);
// A burst does not have to be two updates close together. Skull King bids all
// arrive inside ONE broadcast, which has no gap to measure at all — so count
// how many bids each update carries. Anything above 1 is several seats acting
// at the same instant, which is the same complaint wearing a different shape.
const bidJumps = [];
for (let i = 1; i < events.length; i++) {
  const a = events[i - 1], b = events[i];
  if (a.bidsIn == null || b.bidsIn == null) continue;
  if (b.bidsIn > a.bidsIn) bidJumps.push({ n: b.bidsIn - a.bidsIn, from: a.bidsIn, to: b.bidsIn, gap: b.t - a.t });
}
if (bidJumps.length) {
  console.log('\nbids per update (>1 means several seats bid at the same instant):');
  for (const j of bidJumps) {
    console.log(`  +${j.n} bids in one update (${j.from}->${j.to}) after ${j.gap}ms${j.n > 1 ? '   <-- BURST' : ''}`);
  }
}
console.log(`\nshort gaps (<${BURST_MS}ms) — what actually changed:`);
for (let i = 1; i < events.length; i++) {
  const g = events[i].t - events[i - 1].t;
  if (g >= BURST_MS) continue;
  const a = events[i - 1], b = events[i];
  const shrank = (a.handList || []).map((h, k) => (b.handList?.[k] ?? h) < h ? k : -1).filter((k) => k >= 0);
  const who = shrank.length ? ` by seat ${shrank.join(',')}${shrank.includes(mySeat) ? ' (US)' : ' (bot)'}` : '';
  const kind = (a.bidsIn !== null && b.bidsIn > a.bidsIn) ? `BIDS LANDED ${a.bidsIn}->${b.bidsIn}`
             : b.trick > a.trick ? 'ANOTHER CARD PLAYED' + who
             : b.trick < a.trick ? 'trick collected'
             : b.hands !== a.hands ? 'hand counts moved'
             : 'turn/phase only';
  console.log(`  ${String(g).padStart(4)}ms  ${kind.padEnd(20)} trick ${a.trick}->${b.trick}  hands ${a.hands} -> ${b.hands}  phase ${a.phase}->${b.phase}`);
}
if (gaps.length < 30) console.log(`\n!! SAMPLE TOO SMALL (${gaps.length} gaps) — the hand stalled; do not compare this run`);
console.log(`\nmin=${sorted[0]} p50=${pct(0.5)} p90=${pct(0.9)} max=${sorted[sorted.length - 1]}`);
console.log(`bursts (<${BURST_MS}ms apart): ${bursts.length} / ${gaps.length}`);
process.exit(0);
