'use strict';
/**
 * Every game_state a player receives must carry the seat decoration.
 *
 * The engines produce ids, names and cards; who is connected, whose turn
 * timeouts are stacking up, which seats are bots and each player's profile photo
 * are spliced on afterwards. Six places send a player game_state, and five of
 * them used to do that splice by hand with their own subset of the fields — so
 * approving a spectator's card-view request repainted the approver's board from
 * an undecorated state and every avatar on it disappeared.
 *
 * This drives the real path: player creates a room with bots, spectator asks to
 * see the player's cards, player approves. Then EVERY game_state that arrives
 * afterwards has to be decorated — checking only the next one would pass by luck
 * whenever a broadcast happened to overtake the targeted send.
 *
 * `isBot` stands in for the whole decoration: it is set by the same one function
 * as photoUrl, and unlike a photo it needs no upload or database row to observe.
 *
 * Runs its own server on a spare port against a throwaway database. Both matter:
 * the dev stack holds 8080, and signing accounts up in the shared local database
 * is how 169 junk users ended up in it once already.
 */

const { spawn } = require('child_process');
const path = require('path');
const WebSocket = require('ws');

const PORT = process.env.TEST_PORT || 8099;
const URL = `ws://127.0.0.1:${PORT}`;
const DB_NAME = 'tichu_decor_test';
const ADMIN_URL = 'postgresql://jiny@localhost:5432/postgres';
const TEST_DB_URL = `postgresql://jiny@localhost:5432/${DB_NAME}`;

async function resetDatabase() {
  const { Client } = require('pg');
  const c = new Client({ connectionString: process.env.PGADMIN_URL || ADMIN_URL });
  await c.connect();
  // Dropped and recreated so a previous run's accounts can't make this one pass.
  await c.query(`DROP DATABASE IF EXISTS ${DB_NAME}`);
  await c.query(`CREATE DATABASE ${DB_NAME}`);
  await c.end();
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function client(name) {
  const c = {
    name,
    ws: new WebSocket(URL),
    playerId: null,
    seen: [],
    on: {},
  };
  c.send = (o) => c.ws.send(JSON.stringify(o));
  c.ws.on('message', (raw) => {
    const m = JSON.parse(raw.toString());
    c.seen.push(m);
    if (m.type === 'login_success') c.playerId = m.playerId;
    if (c.on[m.type]) c.on[m.type](m);
  });
  c.ready = new Promise((res, rej) => {
    c.ws.on('open', res);
    c.ws.on('error', rej);
  });
  c.waitFor = async (type, timeoutMs = 6000) => {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      const hit = c.seen.find((m) => m.type === type);
      if (hit) return hit;
      await sleep(50);
    }
    throw new Error(`${name}: timed out waiting for ${type}`);
  };
  return c;
}

/** Register then log in. Accounts are the only way in — there is no dev bypass. */
async function account(label, name) {
  const c = client(label);
  await c.ready;
  c.send({ type: 'register', username: name, password: 'test1234!', nickname: name });
  const reg = await c.waitFor('register_result');
  if (!reg.success) throw new Error(`${label}: register failed — ${reg.message}`);
  c.send({ type: 'login', username: name, password: 'test1234!' });
  await c.waitFor('login_success');
  return c;
}

/** Did this payload go through the shared decorator? */
function undecorated(state) {
  const players = state.players || [];
  if (players.length === 0) return 'no players array';
  // Bots are the seats we can identify without a database: three were added.
  const bots = players.filter((p) => p.isBot === true);
  if (bots.length !== 3) {
    return `isBot missing — ${bots.length}/3 bot seats flagged`;
  }
  if (players.some((p) => p.connected === undefined)) return 'connected missing';
  if (players.some((p) => p.timeoutCount === undefined)) {
    return 'timeoutCount missing';
  }
  if (state.spectatorCount === undefined) return 'spectatorCount missing';
  if (state.cardViewers === undefined) return 'cardViewers missing';
  return null;
}

async function main() {
  await resetDatabase();
  const server = spawn('node', [path.join(__dirname, 'server.js')], {
    env: {
      ...process.env,
      PORT: String(PORT),
      INSTANCE_NAME: 'test-decor',
      DATABASE_URL: process.env.TEST_DATABASE_URL || TEST_DB_URL,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let serverLog = '';
  server.stdout.on('data', (d) => { serverLog += d.toString(); });
  server.stderr.on('data', (d) => { serverLog += d.toString(); });

  const stop = () => { try { server.kill('SIGKILL'); } catch { /* gone */ } };

  try {
    for (let i = 0; i < 60; i++) {
      if (serverLog.includes(`running on port ${PORT}`)) break;
      await sleep(200);
    }
    if (!serverLog.includes(`running on port ${PORT}`)) {
      throw new Error(`server did not start:\n${serverLog}`);
    }

    const host = await account('host', 'decor_host');

    host.send({ type: 'create_room', roomName: 'decor', gameType: 'tichu' });
    const joined = await host.waitFor('room_joined');
    const roomId = joined.roomId;

    for (let i = 0; i < 3; i++) {
      host.send({ type: 'add_bot', speed: 'slow' });
      await sleep(200);
    }
    host.send({ type: 'start_game' });
    const first = await host.waitFor('game_state');

    // The broadcast path was always correct; assert it so a failure below points
    // at the targeted send rather than at the decoration itself.
    const broadcastProblem = undecorated(first.state);
    if (broadcastProblem) {
      throw new Error(`broadcast game_state was undecorated: ${broadcastProblem}`);
    }
    console.log('  ok   broadcast game_state is decorated');

    const spec = await account('spectator', 'decor_spec');
    spec.send({ type: 'spectate_room', roomId });
    await spec.waitFor('spectator_game_state');

    // From here on, nothing the host receives may be undecorated.
    host.seen.length = 0;
    let approved = false;
    host.on.card_view_request = (m) => {
      approved = true;
      host.send({ type: 'respond_card_view', spectatorId: m.spectatorId, allow: true });
    };
    spec.send({ type: 'request_card_view', playerId: host.playerId });

    for (let i = 0; i < 60 && !approved; i++) await sleep(100);
    if (!approved) throw new Error('host never got card_view_request');

    // Long enough for both the targeted send and any broadcast to land.
    await sleep(1500);

    const states = host.seen.filter((m) => m.type === 'game_state');
    if (states.length === 0) {
      throw new Error('host received no game_state after approving');
    }
    const bad = states
      .map((m, i) => ({ i, why: undecorated(m.state) }))
      .filter((r) => r.why);
    if (bad.length) {
      throw new Error(
        `${bad.length}/${states.length} game_state(s) after approval were `
        + `undecorated: ${bad.map((b) => `#${b.i} ${b.why}`).join('; ')}`,
      );
    }
    console.log(`  ok   all ${states.length} game_state(s) after approval are decorated`);

    // The spectator's own view goes through the sibling decorator on the same
    // path, and had the identical bug once.
    const specStates = spec.seen.filter((m) => m.type === 'spectator_game_state');
    const specBad = specStates.filter((m) => {
      const players = m.state.players || [];
      return players.filter((p) => p.isBot === true).length !== 3;
    });
    if (specBad.length) {
      throw new Error(`${specBad.length}/${specStates.length} spectator_game_state(s) undecorated`);
    }
    console.log(`  ok   all ${specStates.length} spectator_game_state(s) are decorated`);

    host.ws.close();
    spec.ws.close();
    console.log('\nALL PASS');
    stop();
    process.exit(0);
  } catch (e) {
    console.log(`\nFAIL: ${e.message}`);
    stop();
    process.exit(1);
  }
}

main();
