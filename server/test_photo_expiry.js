'use strict';
/**
 * 사진권이 끝나면 자리에서도 사진이 내려가는가.
 *
 * ws.photoUrl 은 로그인할 때 한 번 만들어 소켓에 붙여두고, 방의 좌석은 그
 * 사본을 들고 있다. 그래서 DB 만 정리하면 접속 중인 사람의 얼굴은 세션이
 * 끝날 때까지 테이블에 남는다 — 게다가 정리 작업이 저장소 객체까지 지우고
 * 나면, 남아 있는 건 더 이상 열리지 않는 URL 이다.
 *
 * 클라이언트는 photoUrl 이 null 이면 기본 아바타를 그린다(ProfileAvatar).
 * 그러니 서버가 할 일은 "깨진 URL 을 보내지 않는 것" 하나다.
 *
 * Run (server must be listening): node server/test_photo_expiry.js
 */
const WebSocket = require('ws');
const http = require('http');
const db = require('./db/database.js');

const SERVER_URL = process.argv[2] || 'ws://localhost:8080';
const ADMIN_BASE = process.argv[3] || 'http://localhost:8080';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const RUN = Date.now().toString(36).slice(-5);

let failures = 0;
const check = (label, cond, detail = '') => {
  console.log(`${cond ? '  ok  ' : '  FAIL'} ${label}${!cond && detail ? ` — ${detail}` : ''}`);
  if (!cond) failures++;
};

function client(name) {
  const c = { name, last: {}, seen: [] };
  c.ws = new WebSocket(SERVER_URL);
  c.ws.on('message', (raw) => {
    const d = JSON.parse(raw.toString());
    c.seen.push(d.type);
    c.last[d.type] = d;
  });
  c.send = (m) => c.ws.send(JSON.stringify(m));
  c.forget = (t) => delete c.last[t];
  c.wait = (type, ms = 6000) => new Promise((resolve, reject) => {
    if (c.last[type]) return resolve(c.last[type]);
    const deadline = setTimeout(() => reject(new Error(`${name}: no ${type}`)), ms);
    const tick = setInterval(() => {
      if (c.last[type]) { clearTimeout(deadline); clearInterval(tick); resolve(c.last[type]); }
    }, 40);
  });
  return new Promise((resolve, reject) => {
    c.ws.on('open', () => resolve(c));
    c.ws.on('error', reject);
  });
}

/** POST to the backstage as the default admin, following the session cookie. */
function adminPost(path, cookie) {
  return new Promise((resolve, reject) => {
    const url = new URL(ADMIN_BASE + path);
    const req = http.request({
      hostname: url.hostname, port: url.port, path: url.pathname,
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded', ...(cookie ? { Cookie: cookie } : {}) },
    }, (res) => {
      let body = '';
      res.on('data', (d) => { body += d; });
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body }));
    });
    req.on('error', reject);
    req.end('');
  });
}
function adminLogin() {
  return new Promise((resolve, reject) => {
    const url = new URL(ADMIN_BASE + '/tc-backstage/login');
    const payload = 'username=admin&password=admin1234';
    const req = http.request({
      hostname: url.hostname, port: url.port, path: url.pathname, method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'Content-Length': payload.length },
    }, (res) => {
      res.resume();
      const raw = res.headers['set-cookie']?.[0];
      resolve(raw ? raw.split(';')[0] : null);
    });
    req.on('error', reject);
    req.end(payload);
  });
}

(async () => {
  const NICK = `사진WS${RUN}`;
  const acct = { username: `photo_${RUN}`, password: 'phototest1234!', nickname: NICK };
  const a = await client('주인');
  const b = await client('구경꾼');

  a.send({ type: 'register', ...acct });
  const bAcct = { username: `photob_${RUN}`, password: 'phototest1234!', nickname: `옆자리${RUN}` };
  b.send({ type: 'register', ...bAcct });
  await sleep(1100);

  // 사진권을 유효하게 만들어두고 로그인해야 ws.photoUrl 이 잡힌다.
  await db.pool.query(
    `UPDATE tc_users
        SET profile_photo_key = 'profile/${RUN}.webp', profile_photo_status = 'active',
            profile_photo_expires_at = (NOW() AT TIME ZONE 'UTC') + INTERVAL '3 days'
      WHERE nickname = $1`, [NICK]);

  for (const [c, acc] of [[a, acct], [b, bAcct]]) {
    c.send({ type: 'login', username: acc.username, password: acc.password,
      deviceInfo: { appVersion: '99.0.0', locale: 'ko' } });
  }
  await Promise.all([a.wait('login_success'), b.wait('login_success')]);

  console.log('\n[사진권이 살아 있을 때]');
  a.send({ type: 'create_room', roomName: `사진방${RUN}`, gameType: 'tichu' });
  const room = await a.wait('room_joined');
  b.send({ type: 'join_room', roomId: room.roomId });
  await b.wait('room_joined');
  const seatOf = (state, nick) => (state.room.players || []).find((p) => p && p.name === nick);
  const before = seatOf(await b.wait('room_state'), NICK);
  check('옆자리에서 사진이 보인다', !!before?.photoUrl, `${before?.photoUrl}`);

  console.log('\n[사진권이 만료되고 정리가 돌면]');
  await db.pool.query(
    `UPDATE tc_users SET profile_photo_expires_at = (NOW() AT TIME ZONE 'UTC') - INTERVAL '1 hour'
      WHERE nickname = $1`, [NICK]);
  b.forget('room_state');
  a.forget('profile_photo_updated');
  const cookie = await adminLogin();
  const swept = await adminPost('/tc-backstage/profile-photos/sweep', cookie);
  check('어드민에서 정리를 돌릴 수 있다', swept.status === 302, `HTTP ${swept.status}`);

  const told = await a.wait('profile_photo_updated', 5000).catch(() => null);
  check('주인에게 사진이 내려갔다고 알려준다', told != null && told.url === null,
    JSON.stringify(told));
  const after = seatOf(await b.wait('room_state', 5000), NICK);
  check('옆자리에서도 사진이 사라진다 (기본 아바타로)',
    !after?.photoUrl, `${after?.photoUrl}`);

  console.log('\n[DB 상태]');
  const row = (await db.pool.query(
    `SELECT profile_photo_key, profile_photo_status FROM tc_users WHERE nickname = $1`,
    [NICK])).rows[0];
  check('키가 지워졌다', row.profile_photo_key === null, `${row.profile_photo_key}`);
  check('상태가 none 이다', row.profile_photo_status === 'none', row.profile_photo_status);

  console.log('\n[다시 접속해도]');
  a.ws.close();
  const a2 = await client('주인2');
  a2.send({ type: 'login', username: acct.username, password: acct.password,
    deviceInfo: { appVersion: '99.0.0', locale: 'ko' } });
  const relogin = await a2.wait('login_success');
  check('로그인 페이로드에도 사진이 없다',
    !relogin.photoUrl && !relogin.profilePhotoKey,
    `${relogin.photoUrl} / ${relogin.profilePhotoKey}`);
  a2.ws.close();

  b.ws.close();
  for (const n of [NICK, `옆자리${RUN}`]) {
    await db.pool.query('DELETE FROM tc_users WHERE nickname = $1', [n]);
  }
})()
  .then(() => {
    console.log(failures === 0 ? '\nPASS' : `\n${failures} FAILURE(S)`);
    process.exit(failures === 0 ? 0 : 1);
  })
  .catch((e) => { console.error('\nERROR', e.message); process.exit(1); });
