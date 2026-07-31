'use strict';
/**
 * A report hides exactly what it named — and nothing else.
 *
 * The rule this locks down:
 *   photo report  → that photo goes away for the reporter (and stays away)
 *   title report  → that title goes away for the reporter (and stays away)
 *   abuse/spam    → that person's chat stops arriving, IN THAT ROOM only
 *   anything else → nothing is hidden
 *
 * Before, every report hid the reported user's photo, whatever it was about.
 * The "and nothing else" half is the point, so each case checks the things that
 * must stay visible as well as the one that must not.
 */

const { spawn } = require('child_process');
const path = require('path');
const WebSocket = require('ws');
const { Client } = require('pg');

const PORT = process.env.TEST_PORT || 8096;
const URL = `ws://127.0.0.1:${PORT}`;
const DB_NAME = 'tichu_report_scope_test';
const TEST_DB_URL = `postgresql://jiny@localhost:5432/${DB_NAME}`;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let failures = 0;
function check(cond, msg) {
  if (cond) console.log(`  ok   ${msg}`);
  else { failures++; console.log(`  FAIL ${msg}`); }
}

function client(name) {
  const c = { name, ws: new WebSocket(URL), playerId: null, seen: [] };
  c.send = (o) => c.ws.send(JSON.stringify(o));
  c.ws.on('message', (raw) => {
    const m = JSON.parse(raw.toString());
    c.seen.push(m);
    if (m.type === 'login_success') c.playerId = m.playerId;
  });
  c.ready = new Promise((res, rej) => { c.ws.on('open', res); c.ws.on('error', rej); });
  c.waitFor = async (type, ms = 6000) => {
    const end = Date.now() + ms;
    while (Date.now() < end) {
      const hit = c.seen.find((m) => m.type === type);
      if (hit) return hit;
      await sleep(50);
    }
    return null;
  };
  c.forget = () => { c.seen.length = 0; };
  return c;
}

async function account(label, name) {
  const c = client(label);
  await c.ready;
  c.send({ type: 'register', username: name, password: 'test1234!', nickname: name,
           deviceInfo: { appVersion: '2.8.0' } });
  const reg = await c.waitFor('register_result');
  if (!reg?.success) throw new Error(`${label}: register failed — ${reg && reg.message}`);
  c.send({ type: 'login', username: name, password: 'test1234!',
           deviceInfo: { appVersion: '2.8.0' } });
  if (!await c.waitFor('login_success')) throw new Error(`${label}: login failed`);
  return c;
}

async function withDb(fn) {
  const c = new Client({ connectionString: process.env.TEST_DATABASE_URL || TEST_DB_URL });
  await c.connect();
  try { return await fn(c); } finally { await c.end(); }
}

/**
 * The reporter's view of a target's seat in the room they share.
 *
 * Room state is pushed on change, not on request, so this nudges a change the
 * target is allowed to make (ready toggle) and reads the state that follows.
 */
async function seatOf(viewer, target, targetName) {
  viewer.forget();
  target.send({ type: 'toggle_ready' });
  const state = await viewer.waitFor('room_state', 4000);
  target.send({ type: 'toggle_ready' });
  await sleep(150);
  return (state?.room?.players || []).find((p) => p && p.name === targetName) || null;
}

async function main() {
  const admin = new Client({ connectionString: 'postgresql://jiny@localhost:5432/postgres' });
  await admin.connect();
  await admin.query(`DROP DATABASE IF EXISTS ${DB_NAME}`);
  await admin.query(`CREATE DATABASE ${DB_NAME}`);
  await admin.end();

  const server = spawn('node', [path.join(__dirname, 'server.js')], {
    env: { ...process.env, PORT: String(PORT), INSTANCE_NAME: 'test-report',
           DATABASE_URL: process.env.TEST_DATABASE_URL || TEST_DB_URL },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let log = '';
  server.stdout.on('data', (d) => { log += d; });
  server.stderr.on('data', (d) => { log += d; });
  const stop = () => { try { server.kill('SIGKILL'); } catch { /* gone */ } };

  try {
    for (let i = 0; i < 80 && !log.includes(`running on port ${PORT}`); i++) await sleep(200);
    if (!log.includes(`running on port ${PORT}`)) throw new Error(`server did not start:\n${log}`);

    const host = await account('host', 'repHost');
    const rude = await account('rude', 'repRude');

    // Give the target a photo and a custom title to report.
    await withDb(async (c) => {
      await c.query(
        `UPDATE tc_users SET profile_photo_key = 'test/repRude.jpg',
           profile_photo_status = 'active',
           profile_photo_expires_at = NOW() + INTERVAL '30 days',
           custom_title_text = '왕'
         WHERE nickname = 'repRude'`);
      await c.query(
        `INSERT INTO tc_user_equips (nickname, title_key) VALUES ('repRude', 'custom:rose')
         ON CONFLICT (nickname) DO UPDATE SET title_key = 'custom:rose'`);
      await c.query(
        `INSERT INTO tc_user_items (nickname, item_key, expires_at, is_active, source)
         VALUES ('repRude', 'custom_title_7d', NOW() + INTERVAL '7 days', TRUE, 'test')`);
    });
    // Re-login so the socket picks up photo/title (both are cached at login).
    rude.ws.close();
    const rude2 = client('rude2');
    await rude2.ready;
    rude2.send({ type: 'login', username: 'repRude', password: 'test1234!',
                 deviceInfo: { appVersion: '2.8.0' } });
    await rude2.waitFor('login_success');

    host.send({ type: 'create_room', roomName: 'rep', gameType: 'tichu' });
    const joined = await host.waitFor('room_joined');
    rude2.send({ type: 'join_room', roomId: joined.roomId });
    await sleep(600);

    const before = await seatOf(host, rude2, 'repRude');
    check(!!before?.photoUrl, 'before any report: photo visible');
    check(before?.titleName === '왕', 'before any report: title visible');

    // ── behaviour report: nothing about the person's looks is hidden ──────
    host.forget();
    host.send({ type: 'report_user', nickname: 'repRude', reason: '욕설/비방',
                reasonCode: 'abuse' });
    await host.waitFor('report_result');
    await sleep(400);
    const afterAbuse = await seatOf(host, rude2, 'repRude');
    check(!!afterAbuse?.photoUrl, 'abuse report leaves the photo alone');
    check(afterAbuse?.titleName === '왕', 'abuse report leaves the title alone');

    // …but their chat stops arriving in this room.
    host.forget();
    rude2.send({ type: 'chat_message', message: '이건 안 보여야 함' });
    await sleep(700);
    const chat = host.seen.find((m) => m.type === 'chat_message' && m.sender === 'repRude');
    check(!chat, 'abuse report mutes that player\'s chat in this room');

    // ── title report: the title goes, the photo stays ────────────────────
    host.forget();
    host.send({ type: 'report_user', nickname: 'repRude', reason: '부적절한 칭호',
                reasonCode: 'title' });
    await host.waitFor('report_result');
    await sleep(400);
    const afterTitle = await seatOf(host, rude2, 'repRude');
    check(!afterTitle?.titleName, 'title report hides that title');
    check(!!afterTitle?.photoUrl, 'title report still leaves the photo alone');

    // ── photo report: now the photo goes too ────────────────────────────
    host.forget();
    host.send({ type: 'report_user', nickname: 'repRude', reason: '부적절한 프로필 사진',
                reasonCode: 'photo' });
    await host.waitFor('report_result');
    await sleep(400);
    const afterPhoto = await seatOf(host, rude2, 'repRude');
    check(!afterPhoto?.photoUrl, 'photo report hides that photo');

    // ── the mute is per-room, not forever ───────────────────────────────
    // A different room means a different mute set: the report was about what
    // was said in that room, and blocking is the permanent option.
    host.forget();
    host.send({ type: 'leave_room' });
    await sleep(400);
    host.send({ type: 'create_room', roomName: 'rep2', gameType: 'tichu' });
    const joined2 = await host.waitFor('room_joined');
    rude2.send({ type: 'leave_room' });
    await sleep(300);
    rude2.send({ type: 'join_room', roomId: joined2.roomId });
    await sleep(600);
    host.forget();
    rude2.send({ type: 'chat_message', message: '새 방에서는 보여야 함' });
    await sleep(700);
    const chat2 = host.seen.find((m) => m.type === 'chat_message' && m.sender === 'repRude');
    check(!!chat2, 'the chat mute does not follow them into another room');

    // ── a name with no account behind it takes no action at all ────────
    // Old rankings and match rows keep naming deleted accounts, and the popup
    // opens on those names; reporting one used to file a ticket about a user
    // the admin cannot look up.
    for (const [type, extra] of [
      ['report_user', { reason: '기타', reasonCode: 'other' }],
      ['block_user', {}],
      ['add_friend', {}],
    ]) {
      host.forget();
      host.send({ type, nickname: '없는사람', ...extra });
      const err = await host.waitFor('error', 2000);
      check(!!err, `${type} on a deleted name is refused`);
    }
    const ghosts = await withDb((c) => c.query(
      `SELECT (SELECT COUNT(*) FROM tc_reports WHERE reported_nickname = '없는사람') AS r,
              (SELECT COUNT(*) FROM tc_blocked_users WHERE blocked_nickname = '없는사람') AS b,
              (SELECT COUNT(*) FROM tc_friends WHERE friend_nickname = '없는사람') AS f`));
    const g = ghosts.rows[0];
    check(Number(g.r) + Number(g.b) + Number(g.f) === 0,
      'and writes no rows against that name');

    for (const c of [host, rude2]) c.ws.close();
    console.log(failures ? `\n${failures} FAILED` : '\nALL PASS');
    stop();
    process.exit(failures ? 1 : 0);
  } catch (e) {
    console.log(`\nFAIL: ${e.message}`);
    stop();
    process.exit(1);
  }
}

main();
