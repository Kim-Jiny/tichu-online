/**
 * Does a player's connection blip revoke what they already allowed?
 *
 * Card-view permission is stored as spectator -> set of player ids, and a
 * reconnect mints the player a new id. If nothing carries the permission over,
 * everyone watching that hand loses it the moment the player reconnects — and
 * neither side is told, so it reads as the viewer being kicked out.
 *
 * Grants a spectator card view, drops the player, brings them back, and checks
 * the spectator can still see the hand.
 *
 * Run (server must be listening): node server/test_card_view_reconnect.js
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
  c.forget = (t) => delete c.last[t];
  c.wait = async (t, ms = 8000) => {
    const end = Date.now() + ms;
    while (Date.now() < end) {
      if (c.last[t]) return c.last[t];
      await sleep(80);
    }
    return null;
  };
  return c;
}

const HOST = {
  username: `cvhost_${run}`,
  password: 'smoke1234!',
  nickname: `주인${run}`,
};
const WATCHER = {
  username: `cvwatch_${run}`,
  password: 'smoke1234!',
  nickname: `구경꾼${run}`,
};

async function register(c, acct) {
  c.send({ type: 'register', ...acct });
  await sleep(900);
  c.send({
    type: 'login',
    username: acct.username,
    password: acct.password,
    deviceInfo: { appVersion: '99.0.0', locale: 'ko' },
  });
  return c.wait('login_success');
}

/** Can the watcher see the host's hand in the state it last received? */
function seesHostCards(watcher, hostNickname) {
  // Spectators get their own message — the seats a spectator may see cards for
  // are decided per viewer, so their state is built separately from a player's.
  const players = watcher.last['spectator_game_state']?.state?.players ?? [];
  const host = players.find((p) => p.name === hostNickname);
  return !!host && Array.isArray(host.cards) && host.cards.length > 0;
}

function watcherSeats(watcher) {
  return JSON.stringify(
    (watcher.last['spectator_game_state']?.state?.players ?? []).map((p) => ({
      n: p.name,
      c: (p.cards ?? []).length,
    })),
  );
}

(async () => {
  const host = connect();
  const watcher = connect();
  await Promise.all([host.ready, watcher.ready]);
  if (!(await register(host, HOST))) throw new Error('host login failed');
  if (!(await register(watcher, WATCHER))) throw new Error('watcher login failed');

  console.log('\n[setup] a table with three bots and one onlooker');
  host.send({
    type: 'create_room',
    roomName: `패권한${run}`,
    turnTimeLimit: 60,
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

  watcher.send({ type: 'spectate_room', roomId });
  if (!(await watcher.wait('spectate_joined'))) {
    throw new Error(`spectate failed: ${watcher.last['error']?.message}`);
  }

  console.log('\n[grant]');
  const hostPlayerId = host.last['login_success']?.playerId;
  watcher.send({ type: 'request_card_view', playerId: hostPlayerId });
  const asked = await host.wait('card_view_request', 6000);
  check('the player is asked', asked != null,
    host.last['error']?.message ?? '(no prompt)');
  host.send({
    type: 'respond_card_view',
    spectatorId: asked?.spectatorId,
    allow: true,
  });
  await sleep(900);
  check('the onlooker can see the hand', seesHostCards(watcher, HOST.nickname),
    watcherSeats(watcher));

  console.log('\n[the player blips]');
  host.ws.close();
  await sleep(1500);
  const back = connect();
  await back.ready;
  back.send({
    type: 'login',
    username: HOST.username,
    password: HOST.password,
    deviceInfo: { appVersion: '99.0.0', locale: 'ko' },
  });
  if (!(await back.wait('login_success'))) throw new Error('re-login failed');
  await back.wait('game_state', 8000);
  await sleep(1200);

  check('the onlooker still sees the hand after the reconnect',
    seesHostCards(watcher, HOST.nickname),
    watcherSeats(watcher));
  check('and the player is not asked all over again',
    !back.last['card_view_request']);

  watcher.ws.close();
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
