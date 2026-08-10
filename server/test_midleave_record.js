/**
 * Does a voluntary mid-game walk-out actually land on the leaver's record?
 *
 * Reads leave_count straight from the database before and after, because the
 * question is whether the row moved — not whether some screen drew it. Also
 * walks out twice from the SAME match (rejoining in between) to check the
 * count accumulates per departure rather than per match.
 *
 * Needs the server running with a short cooldown, e.g.
 *   MID_GAME_JOIN_COOLDOWN_MS=5000 node server.js
 *
 * Run: node server/test_midleave_record.js
 */
const WebSocket = require('ws');
const { pool } = require('./db/database');

const SERVER_URL = process.argv[2] || 'ws://localhost:8080';
let failures = 0;
const check = (label, cond, detail = '') => {
  console.log(`${cond ? '  ok  ' : '  FAIL'} ${label}${!cond && detail ? ` — ${detail}` : ''}`);
  if (!cond) failures++;
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function leaveCountOf(nickname) {
  const r = await pool.query(
    'SELECT leave_count FROM tc_users WHERE nickname = $1', [nickname],
  );
  return r.rows[0]?.leave_count ?? null;
}

class Client {
  constructor(name) { this.name = name; this.last = {}; this.seen = []; }
  connect() {
    return new Promise((resolve, reject) => {
      this.ws = new WebSocket(SERVER_URL);
      this.ws.on('open', resolve);
      this.ws.on('error', reject);
      this.ws.on('message', (raw) => {
        const d = JSON.parse(raw.toString());
        this.seen.push(d.type);
        this.last[d.type] = d;
      });
    });
  }
  send(m) { this.ws.send(JSON.stringify(m)); }
  forget(type) { delete this.last[type]; }
  close() { try { this.ws.close(); } catch { /* gone */ } }
  waitFor(type, ms) {
    if (this.last[type]) return Promise.resolve(this.last[type]);
    return new Promise((resolve, reject) => {
      const t = setTimeout(() => reject(new Error(`${this.name}: no ${type}`)), ms);
      const p = setInterval(() => {
        if (this.last[type]) { clearTimeout(t); clearInterval(p); resolve(this.last[type]); }
      }, 100);
    });
  }
}

async function main() {
  const host = new Client('host');
  const mover = new Client('mover');
  await Promise.all([host.connect(), mover.connect()]);

  const accounts = [
    [host, { username: 'rec_host', password: 'smoke1234!', nickname: '기록호스트' }],
    [mover, { username: 'rec_mover', password: 'smoke1234!', nickname: '기록탈주자' }],
  ];
  for (const [c, a] of accounts) { c.nickname = a.nickname; c.send({ type: 'register', ...a }); }
  await sleep(1200);
  for (const [c, a] of accounts) {
    c.send({
      type: 'login', username: a.username, password: a.password,
      deviceInfo: { appVersion: '99.0.0', locale: 'ko' },
    });
  }
  await Promise.all(accounts.map(([c]) => c.waitFor('login_success', 8000)));

  const before = await leaveCountOf(mover.nickname);
  console.log(`\nleave_count before: ${before}`);

  host.send({
    type: 'create_room', roomName: '기록 테스트', turnTimeLimit: 10,
    allowSpectators: true, allowMidGameJoin: true,
  });
  const roomId = (await host.waitFor('room_joined', 5000)).roomId;
  mover.send({ type: 'join_room', roomId });
  await mover.waitFor('room_joined', 5000);
  host.send({ type: 'add_bot' });
  await sleep(300);
  host.send({ type: 'add_bot' });
  await sleep(400);
  mover.send({ type: 'toggle_ready' });
  await sleep(400);
  host.send({ type: 'start_game' });
  await Promise.all([
    host.waitFor('game_state', 8000),
    mover.waitFor('game_state', 8000),
  ]);

  // ── walk out #1 ────────────────────────────────────────────────────────
  mover.send({ type: 'leave_room' });
  await mover.waitFor('room_left', 8000);
  await sleep(1200);
  const after1 = await leaveCountOf(mover.nickname);
  check('a voluntary walk-out counts immediately, mid-match',
    after1 === before + 1, `${before} -> ${after1}`);
  check('the match did not end for the host',
    host.last['game_state']?.state?.phase !== 'game_end',
    host.last['game_state']?.state?.phase);

  // ── rejoin the SAME match, then walk out again ────────────────────────
  mover.forget('joined_in_progress');
  mover.forget('error');
  mover.send({ type: 'spectate_room', roomId });
  await mover.waitFor('spectate_joined', 8000);
  // Ride out whatever cooldown the server was started with.
  let joined = null;
  for (let attempt = 0; attempt < 12 && !joined; attempt++) {
    mover.send({ type: 'join_in_progress' });
    joined = await mover.waitFor('joined_in_progress', 2500).catch(() => null);
    if (!joined) await sleep(2500);
  }
  check('could rejoin the same match after the cooldown', !!joined,
    mover.last['error']?.message);

  if (joined) {
    mover.forget('room_left');
    mover.send({ type: 'leave_room' });
    await mover.waitFor('room_left', 8000);
    await sleep(1200);
    const after2 = await leaveCountOf(mover.nickname);
    check('a second walk-out from the same match counts again',
      after2 === before + 2, `${before} -> ${after2}`);
  }

  host.close();
  mover.close();
}

main()
  .then(async () => {
    console.log(failures === 0 ? '\nPASS' : `\n${failures} FAILURE(S)`);
    await pool.end();
    process.exit(failures === 0 ? 0 : 1);
  })
  .catch(async (e) => {
    console.error('\nERROR', e.message);
    await pool.end().catch(() => {});
    process.exit(1);
  });
