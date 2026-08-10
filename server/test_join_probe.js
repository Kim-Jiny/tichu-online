/**
 * Why did "게임 참여하기" do nothing?
 *
 * Spectates a running room of the given game type and asks to break in,
 * printing whatever the server says back. The smoke test only ever exercised
 * Tichu; this one takes the game type as an argument so a refusal that only
 * happens in Skull King / Mighty / Love Letter has somewhere to show up.
 *
 * Run: node server/test_join_probe.js [skull_king|tichu|mighty|love_letter]
 */
const WebSocket = require('ws');

const GAME = process.argv[2] || 'skull_king';
const SEATS = { tichu: 4, skull_king: 6, love_letter: 4, mighty: 5 };
const SERVER_URL = 'ws://localhost:8080';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const run = Date.now().toString(36).slice(-5);

function client(name) {
  const c = { name, last: {}, seen: [] };
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
  c.waitFor = async (t, ms = 8000) => {
    const end = Date.now() + ms;
    while (Date.now() < end) {
      if (c.last[t]) return c.last[t];
      await sleep(100);
    }
    return null;
  };
  return c;
}

async function login(c, tag) {
  const acct = {
    username: `probe_${tag}_${run}`,
    password: 'smoke1234!',
    nickname: `프로브${tag}${run}`,
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
  if (!(await c.waitFor('login_success'))) throw new Error(`${c.name}: login failed`);
}

(async () => {
  const host = client('host');
  const watcher = client('watcher');
  await Promise.all([host.ready, watcher.ready]);
  await login(host, 'h');
  await login(watcher, 'w');

  console.log(`\n[${GAME}] building a running room`);
  const msg = {
    type: 'create_room',
    roomName: `참여프로브${run}`,
    turnTimeLimit: 30,
    allowSpectators: true,
    allowMidGameJoin: true,
  };
  if (GAME !== 'tichu') {
    msg.gameType = GAME;
    msg.maxPlayers = SEATS[GAME];
    if (GAME === 'skull_king') msg.skExpansions = ['kraken', 'white_whale', 'loot'];
  }
  host.send(msg);
  const joined = await host.waitFor('room_joined');
  if (!joined) throw new Error(`create failed: ${host.last['error']?.message}`);
  const roomId = joined.roomId;

  for (let i = 0; i < SEATS[GAME] - 1; i++) {
    host.send({ type: 'add_bot' });
    await sleep(250);
  }
  await sleep(400);
  host.send({ type: 'start_game' });
  const started = await host.waitFor('game_state', 10000);
  console.log('  game started:', !!started,
    started ? `phase=${started.state?.phase ?? '?'}` : host.last['error']?.message);

  const roomState = await host.waitFor('room_state');
  console.log('  botSeatCount =', roomState?.room?.botSeatCount,
    '| allowMidGameJoin =', roomState?.room?.allowMidGameJoin,
    '| gameInProgress =', roomState?.room?.gameInProgress);

  console.log('\n[break in]');
  watcher.send({ type: 'spectate_room', roomId });
  const spec = await watcher.waitFor('spectate_joined');
  console.log('  spectating:', !!spec, spec ? '' : watcher.last['error']?.message);

  watcher.forget('error');
  watcher.send({ type: 'join_in_progress' });
  await sleep(1200);
  const ok = watcher.last['joined_in_progress'];
  console.log('  joined:', !!ok);
  if (!ok) console.log('  server refused with:', watcher.last['error']?.message ?? '(no reply at all)');
  console.log('  watcher saw:', watcher.seen.join(','));

  host.ws.close();
  watcher.ws.close();
  process.exit(ok ? 0 : 1);
})().catch((e) => {
  console.error('ERROR', e.message);
  process.exit(1);
});
