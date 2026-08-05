/**
 * Protocol smoke test for the web client.
 *
 * Speaks exactly the message sequence src/state/store.ts sends — same field
 * names, same `deviceInfo`, same ordering — and asserts the server's replies.
 * The point is to catch a wrong field name or a missed gate (e.g. appVersion)
 * without opening a browser; the UI is a pure function of these payloads, so a
 * green run here means the client is talking correctly.
 *
 *   node scripts/smoke.mjs [ws://localhost:8080]
 *
 * Local servers only — it registers an account and plays a full round.
 */

const SERVER_URL = process.argv[2] || 'ws://localhost:8080';
const ACCOUNT = {
  username: 'web_smoke',
  password: 'websmoke1234!',
  nickname: '웹스모크',
};
const APP_VERSION = '2.8.0';

const checks = [];
function check(name, ok, detail = '') {
  checks.push({ name, ok, detail });
  console.log(`${ok ? '\x1b[32m  ok\x1b[0m' : '\x1b[31mFAIL\x1b[0m'}  ${name}${detail ? ` — ${detail}` : ''}`);
}

const ws = new WebSocket(SERVER_URL);
const waiters = [];
let lastGameState = null;
let roomState = null;

ws.addEventListener('message', (event) => {
  const msg = JSON.parse(event.data);
  if (msg.type === 'game_state') lastGameState = msg.state;
  if (msg.type === 'room_state') roomState = msg.room;
  if (msg.type === 'error') console.log(`\x1b[33m       server error: ${msg.message}\x1b[0m`);
  for (let i = waiters.length - 1; i >= 0; i -= 1) {
    if (waiters[i].match(msg)) {
      const [waiter] = waiters.splice(i, 1);
      waiter.resolve(msg);
    }
  }
});

function send(msg) {
  ws.send(JSON.stringify(msg));
}

function waitFor(match, { timeout = 15000, label = 'message' } = {}) {
  const predicate = typeof match === 'string' ? (m) => m.type === match : match;
  return new Promise((resolve, reject) => {
    const waiter = { match: predicate, resolve };
    waiters.push(waiter);
    setTimeout(() => {
      const index = waiters.indexOf(waiter);
      if (index !== -1) {
        waiters.splice(index, 1);
        reject(new Error(`timed out waiting for ${label}`));
      }
    }, timeout);
  });
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const RANK_VALUES = { 2: 2, 3: 3, 4: 4, 5: 5, 6: 6, 7: 7, 8: 8, 9: 9, 10: 10, J: 11, Q: 12, K: 13, A: 14 };
function cardValue(id) {
  if (id === 'special_bird') return 1;
  if (id === 'special_dog') return 0;
  if (id === 'special_phoenix') return 14.5;
  if (id === 'special_dragon') return 15;
  return RANK_VALUES[id.split('_')[1]] ?? 0;
}

async function main() {
  await new Promise((resolve, reject) => {
    ws.addEventListener('open', resolve, { once: true });
    ws.addEventListener('error', reject, { once: true });
  });
  check('WebSocket connects', true, SERVER_URL);

  // ping/pong, the client heartbeat.
  send({ type: 'ping' });
  await waitFor('pong', { label: 'pong' });
  check('ping → pong', true);

  // Register is a no-op after the first run.
  send({ type: 'register', ...ACCOUNT });
  await waitFor('register_result', { label: 'register_result' }).catch(() => null);

  send({
    type: 'login',
    username: ACCOUNT.username,
    password: ACCOUNT.password,
    deviceInfo: { devicePlatform: 'web', appVersion: APP_VERSION, locale: 'ko' },
  });
  const login = await waitFor(
    (m) => m.type === 'login_success' || m.type === 'login_error',
    { label: 'login result' },
  );
  if (login.type === 'login_error') {
    check('login', false, login.message);
    return finish();
  }
  check('login_success', true, `playerId=${login.playerId} provider=${login.authProvider}`);
  check(
    'login_success carries the fields the store reads',
    typeof login.nickname === 'string' && typeof login.isAdmin === 'boolean' && 'maintenanceStatus' in login,
    `nickname=${login.nickname}`,
  );

  // The store always probes check_room after login.
  send({ type: 'check_room' });
  const restore = await waitFor('restore_complete', { label: 'restore_complete' });
  check('check_room → restore_complete', true, `destination=${restore.destination}`);

  if (restore.destination !== 'lobby') {
    send({ type: 'leave_room' });
    await waitFor((m) => m.type === 'room_left' || m.type === 'room_closed', {
      label: 'leaving the restored room',
    }).catch(() => null);
    await sleep(300);
  }

  send({ type: 'room_list' });
  const rooms = await waitFor('room_list', { label: 'room_list' });
  check('room_list', Array.isArray(rooms.rooms), `${rooms.rooms?.length ?? 0} rooms`);

  send({
    type: 'create_room',
    gameType: 'tichu',
    roomName: '웹스모크',
    password: '',
    turnTimeLimit: 30,
    targetScore: 400,
    allowSpectators: true,
    isRanked: false,
  });
  const joined = await waitFor('room_joined', { label: 'room_joined' });
  check('create_room → room_joined', true, joined.roomName);

  await waitFor('room_state', { label: 'room_state' });
  check(
    'room_state seat array shape',
    Array.isArray(roomState?.players) && roomState.players.length === roomState.maxPlayers,
    `players=${roomState?.players?.length} maxPlayers=${roomState?.maxPlayers}`,
  );

  for (const slot of [1, 2, 3]) {
    send({ type: 'add_bot', speed: 'fast', targetSlot: slot });
    await sleep(350);
  }
  const botCount = (roomState?.players ?? []).filter((p) => p && p.isBot).length;
  check('add_bot fills three seats', botCount === 3, `bots=${botCount}`);

  send({ type: 'toggle_ready' });
  await sleep(300);

  send({ type: 'start_game' });
  await waitFor('game_state', { label: 'game_state after start_game' });
  check('start_game → game_state', true, `phase=${lastGameState.phase}`);
  check(
    'Tichu state omits gameType (client defaults to tichu)',
    lastGameState.gameType === undefined,
    `gameType=${String(lastGameState.gameType)}`,
  );
  check(
    'state carries the decorated fields the UI reads',
    'turnDeadline' in lastGameState && Array.isArray(lastGameState.players),
    `players=${lastGameState.players?.length}`,
  );
  check(
    'seat positions are self/right/partner/left',
    new Set(lastGameState.players.map((p) => p.position)).size === 4,
    lastGameState.players.map((p) => p.position).join(','),
  );

  await playThroughRound();

  finish();
}

/** Drives the host's own hand with the crudest legal play until the round ends. */
async function playThroughRound() {
  const roundEnd = waitFor(
    (m) => m.type === 'game_state' && (m.state.phase === 'round_end' || m.state.phase === 'game_end'),
    { timeout: 180000, label: 'round_end' },
  );

  let sawExchange = false;
  let sawPlaying = false;
  let lastActedSignature = '';

  const loop = setInterval(() => {
    const state = lastGameState;
    if (!state) return;

    // Act at most once per distinct situation; the server echoes a fresh
    // snapshot after every action and re-acting would double-play.
    const signature = `${state.phase}|${state.myCards.length}|${state.isMyTurn}|${state.currentTrick.length}|${state.needsToCallRank}|${state.dragonPending}|${state.exchangeDone}|${state.largeTichuResponded}`;
    if (signature === lastActedSignature) return;
    lastActedSignature = signature;

    if (state.needsToCallRank) {
      send({ type: 'call_rank', rank: null });
      return;
    }
    if (state.dragonPending) {
      send({ type: 'dragon_give', target: 'left' });
      return;
    }

    switch (state.phase) {
      case 'large_tichu_phase':
        if (!state.largeTichuResponded) send({ type: 'pass_large_tichu' });
        break;

      case 'card_exchange': {
        sawExchange = true;
        if (state.exchangeDone || state.myCards.length < 3) break;
        const sorted = [...state.myCards].sort((a, b) => cardValue(a) - cardValue(b));
        send({
          type: 'exchange_cards',
          cards: { left: sorted[0], partner: sorted[sorted.length - 1], right: sorted[1] },
        });
        break;
      }

      case 'playing': {
        sawPlaying = true;
        if (!state.isMyTurn) break;
        if (state.currentTrick.length === 0) {
          const lead = state.myCards.find((c) => c !== 'special_dog') ?? state.myCards[0];
          if (lead) send({ type: 'play_cards', cards: [lead] });
          break;
        }
        const top = state.currentTrick[state.currentTrick.length - 1];
        if (top.combo === 'single') {
          const beat = state.myCards.find(
            (c) => !c.startsWith('special_') && cardValue(c) > (top.comboValue || 0),
          );
          if (beat) {
            send({ type: 'play_cards', cards: [beat] });
            break;
          }
        }
        send({ type: 'pass' });
        break;
      }

      default:
        break;
    }
  }, 250);

  try {
    const end = await roundEnd;
    clearInterval(loop);
    check('played a full round to round_end', true, `phase=${end.state.phase}`);
    check('card_exchange phase was exercised', sawExchange);
    check('playing phase was exercised', sawPlaying);
    check(
      'round scores arrived',
      end.state.lastRoundScores !== null && typeof end.state.totalScores?.teamA === 'number',
      `A=${end.state.totalScores?.teamA} B=${end.state.totalScores?.teamB}`,
    );
    check(
      'scoreHistory populated',
      Array.isArray(end.state.scoreHistory) && end.state.scoreHistory.length > 0,
      `${end.state.scoreHistory?.length} entries`,
    );
  } catch (error) {
    clearInterval(loop);
    check('played a full round to round_end', false, error.message);
  }
}

function finish() {
  send({ type: 'leave_game' });
  setTimeout(() => {
    const failed = checks.filter((c) => !c.ok);
    console.log(`\n${checks.length - failed.length}/${checks.length} checks passed`);
    ws.close();
    process.exit(failed.length === 0 ? 0 : 1);
  }, 500);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
