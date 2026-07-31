'use strict';
/**
 * Friend search results carry the person, not just their name.
 *
 * The search list draws the same identity the rest of the app draws — photo,
 * banner, title, level — so the payload has to include them, and it has to be
 * filtered per viewer exactly like a profile is:
 *   - a private account: no level, and the badge instead
 *   - a friend of that account: everything, as usual
 *   - a title this viewer reported: gone from their results too
 *   - a photo hidden by the privacy reach: gone for strangers, there for friends
 */

const { spawn } = require('child_process');
const path = require('path');
const WebSocket = require('ws');
const { Client } = require('pg');

const PORT = process.env.TEST_PORT || 8095;
const URL = `ws://127.0.0.1:${PORT}`;
const DB_NAME = 'tichu_search_test';
const TEST_DB_URL = `postgresql://jiny@localhost:5432/${DB_NAME}`;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let failures = 0;
function check(cond, msg) {
  if (cond) console.log(`  ok   ${msg}`);
  else { failures++; console.log(`  FAIL ${msg}`); }
}

function client(name) {
  const c = { name, ws: new WebSocket(URL), seen: [] };
  c.send = (o) => c.ws.send(JSON.stringify(o));
  c.ws.on('message', (raw) => c.seen.push(JSON.parse(raw.toString())));
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

async function searchFor(viewer, query, nickname) {
  viewer.forget();
  viewer.send({ type: 'search_users', query });
  const res = await viewer.waitFor('search_users_result');
  return (res?.users || []).find((u) => u.nickname === nickname) || null;
}

async function withDb(fn) {
  const c = new Client({ connectionString: process.env.TEST_DATABASE_URL || TEST_DB_URL });
  await c.connect();
  try { return await fn(c); } finally { await c.end(); }
}

async function main() {
  const admin = new Client({ connectionString: 'postgresql://jiny@localhost:5432/postgres' });
  await admin.connect();
  await admin.query(`DROP DATABASE IF EXISTS ${DB_NAME}`);
  await admin.query(`CREATE DATABASE ${DB_NAME}`);
  await admin.end();

  const server = spawn('node', [path.join(__dirname, 'server.js')], {
    env: { ...process.env, PORT: String(PORT), INSTANCE_NAME: 'test-search',
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

    const seeker = await account('seeker', 'srcSeeker');
    await account('plain', 'srcPlain');
    await account('shy', 'srcShy');

    // srcPlain: a photo, a custom title, level 12.
    // srcShy:   the same, plus the privacy pass with the photo included.
    await withDb(async (c) => {
      await c.query(
        `UPDATE tc_users SET profile_photo_key = 'test/plain.jpg',
           profile_photo_status = 'active',
           profile_photo_expires_at = NOW() + INTERVAL '30 days',
           custom_title_text = '별빛', level = 12
         WHERE nickname = 'srcPlain'`);
      await c.query(
        `UPDATE tc_users SET profile_photo_key = 'test/shy.jpg',
           profile_photo_status = 'active',
           profile_photo_expires_at = NOW() + INTERVAL '30 days',
           profile_private_hide_photo = TRUE, level = 7
         WHERE nickname = 'srcShy'`);
      for (const nick of ['srcPlain', 'srcShy']) {
        await c.query(
          `INSERT INTO tc_user_equips (nickname, title_key, banner_key)
           VALUES ($1, 'custom:rose', 'banner_ocean')
           ON CONFLICT (nickname) DO UPDATE
             SET title_key = 'custom:rose', banner_key = 'banner_ocean'`, [nick]);
        await c.query(
          `INSERT INTO tc_user_items (nickname, item_key, expires_at, is_active, source)
           VALUES ($1, 'custom_title_7d', NOW() + INTERVAL '7 days', TRUE, 'test')`, [nick]);
      }
      await c.query(
        `INSERT INTO tc_user_items (nickname, item_key, expires_at, is_active, source)
         VALUES ('srcShy', 'profile_private_7d', NOW() + INTERVAL '7 days', TRUE, 'test')`);
    });
    // Privacy and photos are read at login, so reconnect both.
    const shy = client('shy2');
    await shy.ready;
    shy.send({ type: 'login', username: 'srcShy', password: 'test1234!',
               deviceInfo: { appVersion: '2.8.0' } });
    await shy.waitFor('login_success');
    await sleep(300);

    // ── an ordinary account: everything is there ────────────────────────
    const plain = await searchFor(seeker, 'srcPlain', 'srcPlain');
    check(!!plain, 'the search finds them');
    check(!!plain?.photoUrl, 'result carries the photo');
    check(plain?.level === 12, 'result carries the level');
    check(plain?.bannerKey === 'banner_ocean', 'result carries the banner');
    check(plain?.titleName === '별빛' && plain?.titleKey === 'custom:rose',
      'result carries the custom title');
    check(plain?.isPrivate !== true, 'not marked private');

    // ── a private account, seen by a stranger ───────────────────────────
    const shyRow = await searchFor(seeker, 'srcShy', 'srcShy');
    check(shyRow?.isPrivate === true, 'private account is marked private');
    check(shyRow?.level == null, 'private account sends no level');
    check(!shyRow?.photoUrl, 'private account with photo reach hides the photo');
    check(shyRow?.nickname === 'srcShy', 'the identity still comes through');

    // ── a reported title is gone from the results too ───────────────────
    seeker.forget();
    seeker.send({ type: 'report_user', nickname: 'srcPlain',
                  reason: '부적절한 칭호', reasonCode: 'title' });
    await seeker.waitFor('report_result');
    await sleep(300);
    const afterReport = await searchFor(seeker, 'srcPlain', 'srcPlain');
    check(!afterReport?.titleName, 'reported title is hidden in search results');
    check(!!afterReport?.photoUrl, '…and nothing else about them is');

    // ── once they are friends, the private account opens up ─────────────
    seeker.send({ type: 'add_friend', nickname: 'srcShy' });
    await sleep(400);
    shy.send({ type: 'accept_friend_request', nickname: 'srcSeeker' });
    await sleep(600);
    const asFriend = await searchFor(seeker, 'srcShy', 'srcShy');
    check(asFriend?.isPrivate !== true, 'a friend does not see the private badge');
    check(asFriend?.level === 7, 'a friend sees the level');
    check(!!asFriend?.photoUrl, 'a friend sees the photo');
    check(asFriend?.friendStatus === 'friend', 'friend status still reported');

    for (const c of [seeker, shy]) c.ws.close();
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
