'use strict';
/**
 * The profile-privacy pass, end to end.
 *
 * What has to hold, from a stranger's side:
 *   - records are gone from the profile payload (not merely hidden by the app —
 *     the numbers must not be sent at all)
 *   - identity stays (nickname, so they can still report / add as friend)
 *   - the photo stays by default, and disappears once the owner turns on the
 *     "hide photo too" reach — in the profile popup AND on the room seat
 * and from a friend's side: nothing is hidden at all.
 *
 * Runs its own server on a spare port against a throwaway database: the dev
 * stack holds 8080, and test accounts in the shared local database are how junk
 * users pile up there.
 */

const { spawn } = require('child_process');
const path = require('path');
const WebSocket = require('ws');

const PORT = process.env.TEST_PORT || 8098;
const URL = `ws://127.0.0.1:${PORT}`;
const DB_NAME = 'tichu_privacy_test';
const ADMIN_URL = 'postgresql://jiny@localhost:5432/postgres';
const TEST_DB_URL = `postgresql://jiny@localhost:5432/${DB_NAME}`;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function resetDatabase() {
  const { Client } = require('pg');
  const c = new Client({ connectionString: process.env.PGADMIN_URL || ADMIN_URL });
  await c.connect();
  await c.query(`DROP DATABASE IF EXISTS ${DB_NAME}`);
  await c.query(`CREATE DATABASE ${DB_NAME}`);
  await c.end();
}

/** Direct DB access for the bits no message can set up (gold, a photo key). */
async function withDb(fn) {
  const { Client } = require('pg');
  const c = new Client({ connectionString: process.env.TEST_DATABASE_URL || TEST_DB_URL });
  await c.connect();
  try {
    return await fn(c);
  } finally {
    await c.end();
  }
}

function client(name) {
  const c = { name, ws: new WebSocket(URL), playerId: null, seen: [], on: {} };
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
  /** Drops everything seen so far, so the next waitFor can't match a stale one. */
  c.forget = () => { c.seen.length = 0; };
  return c;
}

async function account(label, name) {
  const c = client(label);
  await c.ready;
  // appVersion gates the privacy item; anything below the minimum can't buy it.
  c.send({
    type: 'register',
    username: name,
    password: 'test1234!',
    nickname: name,
    deviceInfo: { appVersion: '2.8.0' },
  });
  const reg = await c.waitFor('register_result');
  if (!reg.success) throw new Error(`${label}: register failed — ${reg.message}`);
  c.send({
    type: 'login',
    username: name,
    password: 'test1234!',
    deviceInfo: { appVersion: '2.8.0' },
  });
  await c.waitFor('login_success');
  return c;
}

async function profileOf(viewer, target) {
  viewer.forget();
  viewer.send({ type: 'get_profile', nickname: target });
  const res = await viewer.waitFor('profile_result');
  return res;
}

function check(cond, msg) {
  if (!cond) throw new Error(msg);
  console.log(`  ok   ${msg}`);
}

async function main() {
  await resetDatabase();
  const server = spawn('node', [path.join(__dirname, 'server.js')], {
    env: {
      ...process.env,
      PORT: String(PORT),
      INSTANCE_NAME: 'test-privacy',
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

    const owner = await account('owner', 'privOwner');
    const stranger = await account('stranger', 'privStrgr');
    const friend = await account('friend', 'privFriend');

    // A photo to hide, and gold to buy the pass with. The pass ships
    // is_purchasable = FALSE (see the seed) and is switched on in admin once the
    // client is live, so the test does that switch first — otherwise it would be
    // testing the ship-dark flag rather than the feature.
    await withDb(async (c) => {
      await c.query(
        `UPDATE tc_shop_items SET is_purchasable = TRUE
         WHERE effect_type IN ('profile_private', 'profile_photo')`,
      );
      await c.query(
        `UPDATE tc_users SET gold = 99999,
           profile_photo_key = 'test/privOwner.jpg',
           profile_photo_status = 'active',
           profile_photo_expires_at = NOW() + INTERVAL '30 days'
         WHERE nickname = 'privOwner'`,
      );
    });
    // Re-login so the socket picks up the photo (it is cached at login).
    owner.ws.close();
    const owner2 = await (async () => {
      const c = client('owner2');
      await c.ready;
      c.send({
        type: 'login',
        username: 'privOwner',
        password: 'test1234!',
        deviceInfo: { appVersion: '2.8.0' },
      });
      await c.waitFor('login_success');
      return c;
    })();

    // Friendship, accepted both ways.
    friend.send({ type: 'add_friend', nickname: 'privOwner' });
    await sleep(400);
    owner2.send({ type: 'accept_friend_request', nickname: 'privFriend' });
    await sleep(400);

    // ── before the pass: a stranger sees everything ──────────────────────
    let before = await profileOf(stranger, 'privOwner');
    check(
      before.profile && before.profile.isPrivate !== true
        && before.profile.totalGames !== undefined,
      'without the pass a stranger sees the records',
    );
    check(!!before.profile.photoUrl, 'without the pass a stranger sees the photo');

    // ── buy it ───────────────────────────────────────────────────────────
    owner2.forget();
    owner2.send({ type: 'buy_item', itemKey: 'profile_private_7d' });
    const bought = await owner2.waitFor('purchase_result');
    check(bought.success === true, `pass bought (${bought.message || 'ok'})`);

    // ── stranger: records gone, identity and photo kept ──────────────────
    const hiddenView = await profileOf(stranger, 'privOwner');
    check(hiddenView.profile?.isPrivate === true, 'stranger gets isPrivate');
    check(
      hiddenView.profile.totalGames === undefined
        && hiddenView.profile.level === undefined
        && hiddenView.profile.seasonRating === undefined,
      'no record fields are sent to a stranger',
    );
    check(
      (hiddenView.recentMatches || []).length === 0,
      'recent matches are not sent to a stranger',
    );
    check(hiddenView.profile.nickname === 'privOwner', 'identity is kept');
    check(!!hiddenView.profile.photoUrl, 'photo still shown by default');

    // ── friend: nothing hidden ───────────────────────────────────────────
    const friendView = await profileOf(friend, 'privOwner');
    check(
      friendView.profile?.isPrivate !== true
        && friendView.profile?.totalGames !== undefined,
      'a friend sees the records',
    );

    // ── owner: sees their own, plus the reach setting ────────────────────
    const ownView = await profileOf(owner2, 'privOwner');
    check(
      ownView.profile?.hasProfilePrivate === true
        && ownView.profile?.profilePrivateHidePhoto === false,
      'owner sees the pass state and its reach',
    );

    // ── extend the reach to the photo ────────────────────────────────────
    owner2.forget();
    owner2.send({ type: 'set_profile_private_photo', hide: true });
    const toggled = await owner2.waitFor('profile_private_result');
    check(toggled.success === true && toggled.hidePhoto === true, 'reach toggled to include the photo');

    const hiddenPhotoView = await profileOf(stranger, 'privOwner');
    check(!hiddenPhotoView.profile.photoUrl, 'stranger no longer gets the photo');
    const friendPhotoView = await profileOf(friend, 'privOwner');
    check(!!friendPhotoView.profile.photoUrl, 'friend still gets the photo');

    // ── and on the room seat, not just in the popup ──────────────────────
    owner2.forget();
    owner2.send({ type: 'create_room', roomName: 'priv', gameType: 'tichu' });
    const joined = await owner2.waitFor('room_joined');
    stranger.forget();
    stranger.send({ type: 'join_room', roomId: joined.roomId });
    const strangerRoom = await stranger.waitFor('room_state', 8000);
    const ownerSeat = (strangerRoom.room?.players || [])
      .find((p) => p && p.name === 'privOwner');
    check(!!ownerSeat, 'stranger sees the owner seated');
    check(!ownerSeat.photoUrl, 'stranger gets no photo on the room seat either');

    friend.forget();
    friend.send({ type: 'join_room', roomId: joined.roomId });
    const friendRoom = await friend.waitFor('room_state', 8000);
    const seatForFriend = (friendRoom.room?.players || [])
      .find((p) => p && p.name === 'privOwner');
    check(!!seatForFriend?.photoUrl, 'friend still gets the photo on the room seat');

    for (const c of [owner2, stranger, friend]) c.ws.close();
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
