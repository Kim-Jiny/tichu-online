/**
 * Do walk-out rows stay away from apps that cannot draw them?
 *
 * A mid-game walk-out is an event, not a result: no score, no final roster.
 * An already-installed app picks its renderer off gameType alone, so a Skull
 * King walk-out came out as "undefined점 #undefined". Rather than shim the
 * payload into something it misreads more quietly, the server withholds those
 * rows from clients older than MID_LEAVE_HISTORY_MIN_VERSION.
 *
 * Logs in twice as the SAME account — once claiming an old app version, once a
 * new one — and compares the histories. Same person, same data, two answers.
 *
 * Run (server must be listening): node server/test_midleave_version_gate.js
 */
const WebSocket = require('ws');

const SERVER_URL = process.argv[2] || 'ws://localhost:8080';
const OLD_VERSION = '2.8.3+45';
const NEW_VERSION = '3.0.0+46';
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

const HOST = { username: `vg_h_${run}`, password: 'smoke1234!', nickname: `게이트주${run}` };
const LEAVER = { username: `vg_l_${run}`, password: 'smoke1234!', nickname: `게이트탈${run}` };

async function login(c, acct, appVersion) {
  c.send({ type: 'register', ...acct });
  await sleep(900);
  c.send({
    type: 'login',
    username: acct.username,
    password: acct.password,
    deviceInfo: { appVersion, locale: 'ko' },
  });
  if (!(await c.wait('login_success'))) throw new Error(`login failed (${appVersion})`);
}

async function historyFor(viewer, nickname) {
  viewer.forget('profile_result');
  viewer.send({ type: 'get_profile', nickname });
  const res = await viewer.wait('profile_result');
  if (!res) throw new Error('no profile_result');
  return res.recentMatches ?? [];
}

/// The paged list behind "더보기" — a second endpoint over the same history,
/// and the one that would quietly disagree with the popup if only one of them
/// were gated.
async function pagedHistoryFor(viewer, nickname) {
  viewer.forget('match_history_page');
  viewer.send({
    type: 'get_match_history',
    nickname,
    gameType: 'all',
    offset: 0,
    limit: 50,
  });
  const res = await viewer.wait('match_history_page');
  if (!res) throw new Error('no match_history_page');
  return res.matches ?? [];
}

(async () => {
  const host = connect();
  const leaver = connect();
  await Promise.all([host.ready, leaver.ready]);
  await login(host, HOST, NEW_VERSION);
  await login(leaver, LEAVER, NEW_VERSION);

  console.log('\n[setup] produce one real walk-out');
  host.send({
    type: 'create_room',
    roomName: `버전게이트${run}`,
    turnTimeLimit: 300,
    allowSpectators: true,
    allowMidGameJoin: true,
  });
  const roomId = (await host.wait('room_joined'))?.roomId;
  if (!roomId) throw new Error(`create failed: ${host.last['error']?.message}`);
  leaver.send({ type: 'join_room', roomId });
  if (!(await leaver.wait('room_joined'))) throw new Error('join failed');
  for (let i = 0; i < 2; i++) {
    host.send({ type: 'add_bot' });
    await sleep(300);
  }
  leaver.send({ type: 'toggle_ready' });
  await sleep(600);
  host.send({ type: 'start_game' });
  if (!(await host.wait('game_state', 12000))) throw new Error('game did not start');
  leaver.send({ type: 'leave_game' });
  await sleep(1800);
  leaver.ws.close();
  await sleep(600);

  // One account, three version claims — but they are the SAME account, and a
  // second login kicks the first. So each client is asked everything it needs
  // before the next one takes its place.
  console.log('\n[read it back at two versions]');
  const newEyes = await historyFor(host, LEAVER.nickname);
  const newWalkouts = newEyes.filter((m) => m.isMidGameLeave === true);
  check('a current client sees the walk-out', newWalkouts.length >= 1,
    `${newEyes.length} rows, ${newWalkouts.length} walk-outs`);
  const newPaged = await pagedHistoryFor(host, LEAVER.nickname);
  check('and pages through it in the history list',
    newPaged.filter((m) => m.isMidGameLeave === true).length >= 1,
    `${newPaged.length} rows`);
  host.ws.close();
  await sleep(400);

  const oldApp = connect();
  await oldApp.ready;
  oldApp.send({
    type: 'login',
    username: HOST.username,
    password: HOST.password,
    deviceInfo: { appVersion: OLD_VERSION, locale: 'ko' },
  });
  if (!(await oldApp.wait('login_success'))) throw new Error('old-version login failed');
  const oldEyes = await historyFor(oldApp, LEAVER.nickname);
  const oldWalkouts = oldEyes.filter((m) => m.isMidGameLeave === true);
  check('an older app is not sent any', oldWalkouts.length === 0,
    `${oldWalkouts.length} slipped through`);
  check('and still gets everything else',
    oldEyes.length === newEyes.length - newWalkouts.length,
    `old ${oldEyes.length}, new ${newEyes.length} - ${newWalkouts.length}`);
  // The popup and the paged list are two endpoints over the same history; only
  // one of them being gated is the gap a later refactor walks into.
  const oldPaged = await pagedHistoryFor(oldApp, LEAVER.nickname);
  check('the history list agrees with the popup',
    oldPaged.filter((m) => m.isMidGameLeave === true).length === 0,
    `${oldPaged.filter((m) => m.isMidGameLeave === true).length} slipped through`);
  oldApp.ws.close();
  await sleep(400);

  // A client that sends no deviceInfo at all reads as 0.0.0 — the safe side.
  const unknown = connect();
  await unknown.ready;
  unknown.send({
    type: 'login',
    username: HOST.username,
    password: HOST.password,
  });
  if (!(await unknown.wait('login_success'))) throw new Error('versionless login failed');
  const blindEyes = await historyFor(unknown, LEAVER.nickname);
  check('a client that reports no version is treated as old',
    blindEyes.filter((m) => m.isMidGameLeave === true).length === 0);

  unknown.ws.close();
})()
  .then(() => {
    console.log(failures === 0 ? '\nPASS' : `\n${failures} FAILURE(S)`);
    process.exit(failures === 0 ? 0 : 1);
  })
  .catch((e) => {
    console.error('\nERROR', e.message);
    process.exit(1);
  });
