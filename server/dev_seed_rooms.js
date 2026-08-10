/**
 * Park two rooms in the lobby so the room-list card can be looked at in both
 * states at once: one waiting, one with a match actually running.
 *
 * The clients stay connected until you Ctrl-C — closing them would drop the
 * rooms. Purely a dev fixture; nothing here is used by the app.
 *
 * Run: node server/dev_seed_rooms.js
 */
const WebSocket = require('ws');

const SERVER_URL = process.argv[2] || 'ws://localhost:8080';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function connect(account) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(SERVER_URL);
    const client = { ws, last: {}, send: (m) => ws.send(JSON.stringify(m)) };
    ws.on('open', () => resolve(client));
    ws.on('error', reject);
    ws.on('message', (raw) => {
      const d = JSON.parse(raw.toString());
      client.last[d.type] = d;
    });
    client.account = account;
  });
}

async function waitFor(client, type, ms = 8000) {
  const deadline = Date.now() + ms;
  while (Date.now() < deadline) {
    if (client.last[type]) return client.last[type];
    await sleep(100);
  }
  throw new Error(`no ${type}`);
}

async function makeRoom(client, account, { name, gameType, maxPlayers, bots, start, isRanked, password }) {
  client.send({ type: 'register', ...account });
  await sleep(900);
  client.send({
    type: 'login',
    username: account.username,
    password: account.password,
    deviceInfo: { appVersion: '99.0.0', locale: 'ko' },
  });
  await waitFor(client, 'login_success');
  // A previous run of this script leaves a reconnect pointer behind, so the
  // server pulls the account straight back into its old room on login and
  // create_room then has nowhere to go. Step out first; harmless when there
  // is no room to leave.
  client.send({ type: 'leave_room' });
  await sleep(600);
  delete client.last['room_joined'];

  const msg = {
    type: 'create_room',
    roomName: name,
    turnTimeLimit: 30,
    allowSpectators: true,
    // Ranked rooms can't hold bots, so the option is meaningless there.
    allowMidGameJoin: !isRanked,
    isRanked: !!isRanked,
    password: password || '',
  };
  if (gameType !== 'tichu') {
    msg.gameType = gameType;
    msg.maxPlayers = maxPlayers;
    if (gameType === 'skull_king') {
      msg.skExpansions = ['kraken', 'white_whale', 'loot'];
    }
  }
  client.send(msg);
  await waitFor(client, 'room_joined');

  for (let i = 0; i < bots; i++) {
    client.send({ type: 'add_bot' });
    await sleep(250);
  }
  if (start) {
    await sleep(400);
    client.send({ type: 'start_game' });
    await sleep(1500);
  }
  console.log(`  seeded: ${name} (${gameType}, ${start ? 'playing' : 'waiting'})`);
}

(async () => {
  const a = await connect();
  const b = await connect();
  console.log('seeding lobby…');
  await makeRoom(a, { username: 'seed_a', password: 'smoke1234!', nickname: '시드호스트A' }, {
    name: '무시무시한 해전', gameType: 'skull_king', maxPlayers: 6, bots: 5, start: true,
  });
  await makeRoom(b, { username: 'seed_b', password: 'smoke1234!', nickname: '시드호스트B' }, {
    name: '행운의 카드판', gameType: 'tichu', maxPlayers: 4, bots: 2, start: false,
  });
  // No ranked room here: creating one needs a social account
  // (server.js rejects isRanked from authProvider 'local'), and these are
  // local test logins. Make a ranked room from a signed-in device instead.
  const c = await connect();
  await makeRoom(c, { username: 'seed_c', password: 'smoke1234!', nickname: '시드호스트C' }, {
    name: '비밀의 카드방', gameType: 'tichu', maxPlayers: 4, bots: 2, start: false,
    password: 'pw',
  });
  console.log('\nrooms are up — Ctrl-C to tear them down');
})().catch((e) => {
  console.error('ERROR', e.message);
  process.exit(1);
});
