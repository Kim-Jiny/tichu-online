/**
 * Live smoke test for the mid-game-join room option.
 *
 * The unit test covers the seat handoff itself; this covers the wiring the
 * unit test can't reach — the desertion branch in server.js, the turn timer,
 * and the spectator break-in — by driving a real server over WebSocket.
 *
 * Two humans sit down with two bots. What should happen, in order:
 *
 *   1. A spectator breaks into one of the bot seats, and the cooldown then
 *      refuses a second break-in.
 *   2. Both seated humans go silent. Whoever hits 3 turn timeouts first loses
 *      their seat to a bot, and the match KEEPS RUNNING for the other human.
 *      (The thing that was broken.)
 *   3. When the last remaining human times out too, there is nobody left to
 *      play for, so it falls back to ending the match.
 *
 * The spectator step comes FIRST on purpose. Run the other way round, both
 * humans time out within a turn of each other, the second one ends the match,
 * and the spectator arrives at a room that no longer exists.
 *
 * Nobody plays a card — every move comes from a timeout or a bot, which is
 * what makes the script short and the timing predictable.
 *
 * Run (server must already be listening):
 *   node server/test_midjoin_smoke.js [ws://localhost:8080]
 */
const WebSocket = require('ws');

const SERVER_URL = process.argv[2] || 'ws://localhost:8080';
// Grand-tichu and exchange run on phase timers at 2x, and both auto-fill
// without counting against anyone; only playing turns count toward the 3.
const TURN_LIMIT_SEC = 10;
const OVERALL_TIMEOUT_MS = 240_000;

let failures = 0;
function check(label, cond, detail = '') {
  console.log(`${cond ? '  ok  ' : '  FAIL'} ${label}${!cond && detail ? ` — ${detail}` : ''}`);
  if (!cond) failures++;
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

class Client {
  constructor(name) {
    this.name = name;
    this.playerId = null;
    this.roomId = null;
    this.seen = [];          // every message type, in order
    this.last = {};          // type -> most recent payload
    this.gameStates = 0;
  }

  connect() {
    return new Promise((resolve, reject) => {
      this.ws = new WebSocket(SERVER_URL);
      this.ws.on('open', resolve);
      this.ws.on('error', reject);
      this.ws.on('message', (raw) => {
        const data = JSON.parse(raw.toString());
        this.seen.push(data.type);
        this.last[data.type] = data;
        if (data.type === 'login_success') this.playerId = data.playerId;
        if (data.type === 'room_joined') this.roomId = data.roomId;
        if (data.type === 'game_state') this.gameStates++;
      });
    });
  }

  send(msg) { this.ws.send(JSON.stringify(msg)); }
  saw(type) { return this.seen.includes(type); }
  /** Drop a remembered message so waitFor/last see only what comes next. */
  forget(type) { delete this.last[type]; }
  close() { try { this.ws.close(); } catch { /* already gone */ } }

  /** Resolve once `type` arrives, or reject on timeout. */
  waitFor(type, ms) {
    if (this.last[type]) return Promise.resolve(this.last[type]);
    return new Promise((resolve, reject) => {
      const deadline = setTimeout(
        () => reject(new Error(`${this.name}: timed out waiting for ${type}`)),
        ms,
      );
      const poll = setInterval(() => {
        if (this.last[type]) {
          clearTimeout(deadline);
          clearInterval(poll);
          resolve(this.last[type]);
        }
      }, 100);
    });
  }
}

async function main() {
  const alice = new Client('alice');
  const bob = new Client('bob');
  const carol = new Client('carol');
  await Promise.all([alice.connect(), bob.connect(), carol.connect()]);

  // Local accounts, not guest sessions — the server has no nickname-only
  // login. Registration is idempotent enough for a repeat run: a duplicate
  // username just fails and the login that follows still works.
  const accounts = [
    [alice, { username: 'smoke_alice', password: 'smoke1234!', nickname: '스모크앨리스' }],
    [bob, { username: 'smoke_bob', password: 'smoke1234!', nickname: '스모크밥' }],
    [carol, { username: 'smoke_carol', password: 'smoke1234!', nickname: '스모크캐롤' }],
  ];
  for (const [client, acct] of accounts) {
    client.nickname = acct.nickname;
    client.send({ type: 'register', ...acct });
  }
  await sleep(1200);
  for (const [client, acct] of accounts) {
    client.send({
      type: 'login',
      username: acct.username,
      password: acct.password,
      deviceInfo: { appVersion: '99.0.0', locale: 'ko' },
    });
  }
  await Promise.all(accounts.map(([c]) => c.waitFor('login_success', 8000)));

  console.log('\n[setup]');
  alice.send({
    type: 'create_room',
    roomName: '중도참여 스모크',
    turnTimeLimit: TURN_LIMIT_SEC,
    allowSpectators: true,
    allowMidGameJoin: true,
  });
  const created = await alice.waitFor('room_joined', 5000);
  const roomId = created.roomId;

  const roomState = await alice.waitFor('room_state', 5000);
  check('room reports the option on', roomState.room.allowMidGameJoin === true);

  bob.send({ type: 'join_room', roomId });
  await bob.waitFor('room_joined', 5000);
  alice.send({ type: 'add_bot' });
  await sleep(300);
  alice.send({ type: 'add_bot' });
  await sleep(500);

  // Bots are seated ready; the non-host human is not, and start_game refuses
  // until everyone is (areAllReady).
  bob.send({ type: 'toggle_ready' });
  await sleep(500);

  alice.send({ type: 'start_game' });
  await Promise.all([
    alice.waitFor('game_state', 8000),
    bob.waitFor('game_state', 8000),
  ]);
  console.log('  ..  game started, both humans going silent');

  // ── 1. a spectator breaks into a bot seat ─────────────────────────────
  console.log('\n[spectator breaks in]');
  carol.send({ type: 'spectate_room', roomId });
  // spectate_joined is the ack; the board state follows on its own and is not
  // a precondition for breaking in.
  const watching = await carol.waitFor('spectate_joined', 8000).catch(() => null);
  check('spectator got into the room', !!watching, carol.last['error']?.message);
  carol.send({ type: 'join_in_progress' });
  const joined = await carol.waitFor('joined_in_progress', 8000).catch(() => null);
  check('spectator took a bot seat', !!joined, JSON.stringify(carol.last['error']));
  check('joiner was dealt into the live hand',
    (await carol.waitFor('game_state', 8000).catch(() => null)) != null);
  check('table was told someone joined',
    alice.last['player_joined_in_progress']?.playerName === carol.nickname,
    alice.last['player_joined_in_progress']?.playerName);

  // Walk straight back out, then try to break in again. Seat-hopping has to
  // cost something; without a cooldown, leaving a bad hand and re-entering on
  // the next deal is free.
  //
  // The re-spectate matters: having taken a seat, carol is a PLAYER, and a
  // second join_in_progress would be refused for not spectating — which says
  // nothing about the cooldown. Only a spectator reaches that check.
  carol.send({ type: 'leave_room' });
  await carol.waitFor('room_left', 8000).catch(() => null);
  await sleep(800);
  carol.forget('error');
  carol.forget('spectate_joined');
  carol.send({ type: 'spectate_room', roomId });
  await carol.waitFor('spectate_joined', 8000).catch(() => null);
  carol.send({ type: 'join_in_progress' });
  await sleep(600);
  check('an immediate re-entry is refused, and says how long',
    /\d/.test(carol.last['error']?.message || ''),
    carol.last['error']?.message);

  // ── 2. first human to burn 3 timeouts loses the seat, match continues ──
  console.log('\n[timeout → bot takes the seat]');
  const handoff = await Promise.race([
    alice.waitFor('left_in_progress', OVERALL_TIMEOUT_MS),
    bob.waitFor('left_in_progress', OVERALL_TIMEOUT_MS),
  ]);
  const [gone, stayed] = alice.saw('left_in_progress')
    ? [alice, bob]
    : [bob, alice];
  check('timed-out player was told the seat went to a bot',
    typeof handoff.message === 'string' && handoff.message.length > 0,
    JSON.stringify(handoff.message));
  check('they were NOT kicked as a deserter', !gone.saw('kicked'));

  const notice = stayed.last['player_left_in_progress'];
  check('table was told a bot took over', !!notice);
  check('notice names the timeout as the reason', notice?.reason === 'timeout',
    notice?.reason);
  check('notice names the replacing bot', !!notice?.botName, notice?.botName);

  // The point of the whole feature: the other human's game is still alive.
  check('match did not end for the remaining human',
    !stayed.saw('game_ended')
      && stayed.last['game_state']?.state?.phase != 'game_end',
    stayed.last['game_state']?.state?.phase);
  const before = stayed.gameStates;
  await sleep(TURN_LIMIT_SEC * 1000 + 4000);
  check('match is still progressing', stayed.gameStates > before,
    `states ${before} -> ${stayed.gameStates}`);

  // ── 3. last human out ends the match ──────────────────────────────────
  console.log('\n[last human out ends it]');
  const ended = await stayed
    .waitFor('kicked', OVERALL_TIMEOUT_MS)
    .then(() => 'kicked')
    .catch((e) => e.message);
  check('the final departure ends the match as a desertion',
    ended === 'kicked', String(ended));

  for (const c of [alice, bob, carol]) c.close();
}

const guard = setTimeout(() => {
  console.log('\nFAIL overall timeout');
  process.exit(1);
}, OVERALL_TIMEOUT_MS + 60_000);

main()
  .then(() => {
    clearTimeout(guard);
    console.log(failures === 0 ? '\nPASS' : `\n${failures} FAILURE(S)`);
    process.exit(failures === 0 ? 0 : 1);
  })
  .catch((e) => {
    clearTimeout(guard);
    console.error('\nERROR', e.message);
    process.exit(1);
  });
