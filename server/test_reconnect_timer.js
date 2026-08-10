/**
 * Does backgrounding the app buy you a fresh turn?
 *
 * A reconnect has to throw away the turn timer — it is armed for a playerId
 * that no longer exists — and let the state broadcast arm a new one. That new
 * one used to start a whole turn from scratch, so dropping the connection was
 * a free time extension, repeatable for as long as you liked.
 *
 * Waits out part of a turn, reconnects, and reads the deadline the server
 * reports back. It should be roughly where it was, not pushed out to a full
 * turn again.
 *
 * Run (server must be listening): node server/test_reconnect_timer.js
 */
const WebSocket = require('ws');

const SERVER_URL = process.argv[2] || 'ws://localhost:8080';
const TURN_LIMIT_SEC = 30;
const WAIT_BEFORE_DROP_SEC = 8;

let failures = 0;
const check = (label, cond, detail = '') => {
  console.log(`${cond ? '  ok  ' : '  FAIL'} ${label}${!cond && detail ? ` — ${detail}` : ''}`);
  if (!cond) failures++;
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const run = Date.now().toString(36).slice(-5);

function connect() {
  const c = { last: {}, seen: [] };
  c.ready = new Promise((resolve, reject) => {
    c.ws = new WebSocket(SERVER_URL);
    c.ws.on('open', resolve);
    c.ws.on('error', reject);
    c.ws.on('message', (raw) => {
      const d = JSON.parse(raw.toString());
      c.seen.push(d.type);
      c.last[d.type] = d;
    });
  });
  c.send = (m) => c.ws.send(JSON.stringify(m));
  c.forget = (t) => delete c.last[t];
  c.wait = async (t, ms = 8000) => {
    const end = Date.now() + ms;
    while (Date.now() < end) {
      if (c.last[t]) return c.last[t];
      await sleep(100);
    }
    return null;
  };
  return c;
}

const ACCOUNT = {
  username: `rt_${run}`,
  password: 'smoke1234!',
  nickname: `타이머${run}`,
};

async function login(c) {
  c.send({ type: 'login', ...ACCOUNT, deviceInfo: { appVersion: '99.0.0', locale: 'ko' } });
  return c.wait('login_success');
}

/** Seconds left on the turn clock, as the client would compute it. */
function secondsLeft(gameState) {
  const dl = gameState?.state?.turnDeadline;
  return dl ? (dl - Date.now()) / 1000 : null;
}

(async () => {
  const host = connect();
  await host.ready;
  host.send({ type: 'register', ...ACCOUNT });
  await sleep(900);
  if (!(await login(host))) throw new Error('login failed');

  console.log('\n[setup] a table of bots, so the clock is ours alone');
  host.send({
    type: 'create_room',
    roomName: `타이머${run}`,
    turnTimeLimit: TURN_LIMIT_SEC,
    allowSpectators: true,
  });
  const roomId = (await host.wait('room_joined'))?.roomId;
  if (!roomId) throw new Error(`create failed: ${host.last['error']?.message}`);
  for (let i = 0; i < 3; i++) {
    host.send({ type: 'add_bot' });
    await sleep(250);
  }
  await sleep(400);
  host.send({ type: 'start_game' });
  if (!(await host.wait('game_state', 10000))) throw new Error('game did not start');

  // Wait for a state that actually carries a deadline for us.
  let before = null;
  for (let i = 0; i < 40 && before == null; i++) {
    before = secondsLeft(host.last['game_state']);
    if (before == null) await sleep(500);
  }
  check('the turn clock is running', before != null, String(before));
  console.log(`  ..  ${before?.toFixed(1)}s left; waiting ${WAIT_BEFORE_DROP_SEC}s then dropping`);

  await sleep(WAIT_BEFORE_DROP_SEC * 1000);
  const atDrop = secondsLeft(host.last['game_state']);

  // Background the app: the socket goes away and comes back as a new one.
  host.ws.close();
  await sleep(1500);
  const back = connect();
  await back.ready;
  if (!(await login(back))) throw new Error('re-login failed');
  const state = await back.wait('game_state', 10000);
  const after = secondsLeft(state);

  console.log(`  ..  ${atDrop?.toFixed(1)}s at drop -> ${after?.toFixed(1)}s after reconnect`);
  check('reconnecting does not hand out a fresh turn',
    after != null && after <= (atDrop ?? TURN_LIMIT_SEC) + 2,
    `${after?.toFixed(1)}s left, was ${atDrop?.toFixed(1)}s`);
  check('the clock is still ticking, not expired',
    after != null && after > 0, String(after));

  back.ws.close();
})()
  .then(() => {
    console.log(failures === 0 ? '\nPASS' : `\n${failures} FAILURE(S)`);
    process.exit(failures === 0 ? 0 : 1);
  })
  .catch((e) => {
    console.error('\nERROR', e.message);
    process.exit(1);
  });
