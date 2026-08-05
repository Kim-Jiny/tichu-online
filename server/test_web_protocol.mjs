/**
 * End-to-end protocol test: login → lobby → room → bots → a full Tichu round.
 *
 * Written while the web client was a separate JS app, and kept after that was
 * dropped for Flutter Web, because what it actually exercises is the server:
 * a plain WebSocket speaking the same message sequence any client must, with
 * assertions on the replies. It catches a renamed field or a missed gate (the
 * appVersion one especially) in about two minutes, without a browser.
 *
 *   node test_web_protocol.mjs [ws://localhost:8080]
 *
 * Local servers only — it registers an account and plays real rounds.
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
    // High enough that the game does not end before the Bird has had a few
    // chances to be dealt — the Bird check needs it in hand at least once.
    targetScore: 3000,
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

/**
 * Drives the host's own hand with the crudest legal play, round after round,
 * until the Bird has been exercised (it needs a wish riding along with the
 * play) or the round cap is hit.
 */
async function playThroughRound() {
  const MAX_ROUNDS = 6;
  let roundsFinished = 0;
  let firstRoundEnd = null;
  let resolveDone;
  const done = new Promise((resolve) => {
    resolveDone = resolve;
  });

  let sawExchange = false;
  let sawPlaying = false;
  let lastActedSignature = '';
  // Bird handling: the wish must ship with the play, so we assert the server
  // registered it on the very next snapshot.
  let birdWishSent = null;
  let birdVerified = false;
  let birdTurnAdvancedWithoutWish = false;

  const loop = setInterval(() => {
    const state = lastGameState;
    if (!state) return;

    // A Bird went out with a wish on the previous tick — the wish must already
    // be live, and nobody should still owe a call.
    if (birdWishSent && !birdVerified) {
      if (state.needsToCallRank) birdTurnAdvancedWithoutWish = true;
      if (state.callRank === birdWishSent || state.callRank === null) {
        birdVerified = true;
        check(
          'Bird play carries the wish (callRank rides with play_cards)',
          !birdTurnAdvancedWithoutWish,
          `wish=${birdWishSent} serverCallRank=${String(state.callRank)}`,
        );
      }
    }

    if (state.phase === 'round_end' || state.phase === 'game_end') {
      if (!firstRoundEnd) {
        firstRoundEnd = state;
        roundsFinished += 1;
      }
      if (state.phase === 'game_end' || birdVerified || roundsFinished >= MAX_ROUNDS) {
        clearInterval(loop);
        resolveDone();
        return;
      }
      // Server advances on its own timer; just wait for the next round.
      return;
    }
    if (firstRoundEnd && state.phase !== 'round_end') {
      // New round started.
      if (state.round > roundsFinished) roundsFinished = state.round - 1;
    }

    // Act at most once per distinct situation; the server echoes a fresh
    // snapshot after every action and re-acting would double-play.
    const signature = `${state.round}|${state.phase}|${state.myCards.length}|${state.isMyTurn}|${state.currentTrick.length}|${state.needsToCallRank}|${state.dragonPending}|${state.exchangeDone}|${state.largeTichuResponded}`;
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
          // The Bird can only ever lead, and the wish has to ship with it.
          if (!birdWishSent && state.myCards.includes('special_bird')) {
            birdWishSent = 'A';
            send({ type: 'play_cards', cards: ['special_bird'], callRank: 'A' });
            break;
          }
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

  const timeout = setTimeout(() => {
    clearInterval(loop);
    resolveDone();
  }, 300000);
  await done;
  clearTimeout(timeout);
  clearInterval(loop);

  const end = firstRoundEnd;
  check('played a full round to round_end', Boolean(end), end ? `phase=${end.phase}` : 'never ended');
  check('card_exchange phase was exercised', sawExchange);
  check('playing phase was exercised', sawPlaying);
  if (end) {
    check(
      'round scores arrived',
      end.lastRoundScores !== null && typeof end.totalScores?.teamA === 'number',
      `A=${end.totalScores?.teamA} B=${end.totalScores?.teamB}`,
    );
    check(
      'scoreHistory populated',
      Array.isArray(end.scoreHistory) && end.scoreHistory.length > 0,
      `${end.scoreHistory?.length} entries`,
    );
  }
  if (!birdWishSent) {
    // Not a failure: the Bird simply never landed in this hand within the cap.
    console.log(`\x1b[33m       skipped: Bird never dealt in ${roundsFinished} round(s)\x1b[0m`);
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
