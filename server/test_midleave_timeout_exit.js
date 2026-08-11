/**
 * Does an app that has never heard of mid-game leaving still get out?
 *
 * When a seat is handed to a bot the server says so with `left_in_progress` —
 * a type only the new client knows. An already-installed app ignores an
 * unknown type silently. On the leave routes a `room_left` follows from the
 * leave handler, so those users get out; the THREE-TIMEOUT route ends inside
 * handleDesertion and used to send nothing else, leaving them on a frozen
 * board with no signal to navigate away.
 *
 * Both routes go through the same handOffSeatToBot, which now sends
 * `room_left` itself, first. That ordering is what this checks, and it is
 * exactly what distinguishes the two: before the fix the leave route emitted
 * left_in_progress and only then the handler's room_left. Driving the timeout
 * route instead would mean playing three real turns of Tichu against the
 * clock while a second human keeps the table alive — the same assertion, an
 * order of magnitude more setup.
 *
 * Run (server must be listening): node server/test_midleave_timeout_exit.js
 */
const WebSocket = require('ws');

const SERVER_URL = process.argv[2] || 'ws://localhost:8080';
const run = Date.now().toString(36).slice(-5);

let failures = 0;
const check = (label, cond, detail = '') => {
  console.log(`${cond ? '  ok  ' : '  FAIL'} ${label}${!cond && detail ? ` — ${detail}` : ''}`);
  if (!cond) failures++;
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

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
  c.wait = async (t, ms = 9000) => {
    const end = Date.now() + ms;
    while (Date.now() < end) {
      if (c.last[t]) return c.last[t];
      await sleep(120);
    }
    return null;
  };
  return c;
}

async function login(c, tag) {
  const acct = {
    username: `to_${tag}_${run}`,
    password: 'smoke1234!',
    nickname: `타임${tag}${run}`,
  };
  c.nickname = acct.nickname;
  c.send({ type: 'register', ...acct });
  await sleep(900);
  c.send({
    type: 'login',
    username: acct.username,
    password: acct.password,
    deviceInfo: { appVersion: '99.0.0', locale: 'ko' },
  });
  if (!(await c.wait('login_success'))) throw new Error(`${tag}: login failed`);
}

(async () => {
  // Two seated humans: replaceWithBot refuses to hand over the last one, and
  // the match would end as a plain desertion instead.
  const host = connect();
  const leaver = connect();
  await Promise.all([host.ready, leaver.ready]);
  await login(host, 'h');
  await login(leaver, 'v');

  console.log('\n[setup] a mid-join room with two humans and two bots');
  host.send({
    type: 'create_room',
    roomName: `중도탈주순서${run}`,
    turnTimeLimit: 300,
    allowSpectators: true,
    allowMidGameJoin: true,
  });
  const roomId = (await host.wait('room_joined'))?.roomId;
  if (!roomId) throw new Error(`create failed: ${host.last['error']?.message}`);

  leaver.send({ type: 'join_room', roomId });
  if (!(await leaver.wait('room_joined'))) {
    throw new Error(`join failed: ${leaver.last['error']?.message}`);
  }
  for (let i = 0; i < 2; i++) {
    host.send({ type: 'add_bot' });
    await sleep(300);
  }
  // A player who joined has to declare themselves ready; the host is ready by
  // virtue of being the host.
  leaver.send({ type: 'toggle_ready' });
  await sleep(600);
  host.send({ type: 'start_game' });
  if (!(await host.wait('game_state', 12000))) throw new Error('game did not start');

  console.log('\n[walk out]');
  leaver.send({ type: 'leave_game' });
  await sleep(1500);

  const roomLeftAt = leaver.seen.indexOf('room_left');
  const inProgressAt = leaver.seen.indexOf('left_in_progress');

  check('the leaver is told to leave the room', roomLeftAt >= 0,
    `saw: ${[...new Set(leaver.seen)].join(',')}`);
  check('and gets the reason, for clients that understand it',
    inProgressAt >= 0,
    leaver.last['left_in_progress']?.message ?? '(none)');
  // The whole point: an app that only knows room_left must see it, and the
  // timeout route has nothing else to fall back on.
  check('room_left comes first, so an old client acts on it',
    roomLeftAt >= 0 && roomLeftAt < inProgressAt,
    `room_left@${roomLeftAt}, left_in_progress@${inProgressAt}`);
  check('the table carries on rather than being torn down',
    !host.last['player_deserted'],
    'the match ended as a desertion instead');
  check('a bot took the seat',
    !!host.last['player_left_in_progress']?.botName,
    JSON.stringify(host.last['player_left_in_progress'] ?? null));

  host.ws.close();
  leaver.ws.close();
})()
  .then(() => {
    console.log(failures === 0 ? '\nPASS' : `\n${failures} FAILURE(S)`);
    process.exit(failures === 0 ? 0 : 1);
  })
  .catch((e) => {
    console.error('\nERROR', e.message);
    process.exit(1);
  });
