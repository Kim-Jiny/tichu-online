'use strict';
/**
 * 푸시 기록이 실패해도 우편 발송은 성공으로 끝나야 한다.
 *
 * 편지는 이미 저장된 뒤에 푸시를 붙인다. 그 뒷단(히스토리 기록·수신자
 * 저장)이 던진 예외가 라우트까지 올라가면 운영자는 "우편 발송 실패" 로
 * 읽고 다시 보낸다 — 편지는 이미 갔으므로 같은 우편이 두 번 간다.
 *
 * DB 를 건드리지 않고 라우트만 본다: insertPushHistory 를 던지게 바꿔
 * 끼우고, 응답이 302 성공 리다이렉트인지 확인한다.
 *
 * Run: node test_mail_push_resilience.js
 */
const http = require('http');
const db = require('./db/database.js');

const RUN = Date.now().toString(36).slice(-5);
const NICK = `푸시복원${RUN}`;
let failures = 0;
const check = (label, cond, detail = '') => {
  console.log(`${cond ? '  ok  ' : '  FAIL'} ${label}${!cond && detail ? ` — ${detail}` : ''}`);
  if (!cond) failures++;
};

// 히스토리 기록만 고장 낸다. admin.js 는 require 시점에 이 함수를 구조분해로
// 잡아가므로, admin 을 불러오기 전에 갈아끼워야 한다.
const boom = new Error('history table down (test)');
db.insertPushHistory = async () => { throw boom; };

const admin = require('./admin.js');

function post(path, form, cookie) {
  return new Promise((resolve, reject) => {
    const payload = new URLSearchParams(form).toString();
    const req = http.request({
      hostname: '127.0.0.1', port: PORT, path, method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Content-Length': Buffer.byteLength(payload),
        ...(cookie ? { Cookie: cookie } : {}),
      },
    }, (res) => {
      let b = ''; res.on('data', (d) => { b += d; });
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: b }));
    });
    req.on('error', reject);
    req.end(payload);
  });
}

let PORT = 0;
(async () => {
  await db.pool.query(
    `INSERT INTO tc_users (username, nickname, fcm_token, push_enabled)
     VALUES ($1, $2, 'fake-token-for-test', true) ON CONFLICT DO NOTHING`,
    [`pushres_${RUN}`, NICK]);

  // 라우트만 띄운다. 푸시 전송은 성공했다고 치고, 기록에서 터지게 한다.
  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url, 'http://localhost');
    const handled = await admin.handleAdminRoute(
      req, res, url, url.pathname, req.method, { getRoom: () => null }, null,
      {
        sendBroadcastPush: async (tokens) => ({
          successCount: tokens.length, failCount: 0, invalidUserIds: [],
          results: tokens.map((t) => ({ userId: t.id, success: true })),
        }),
      });
    if (!handled && !res.headersSent) { res.writeHead(404); res.end(); }
  });
  await new Promise((r) => server.listen(0, r));
  PORT = server.address().port;

  const login = await post('/tc-backstage/login', { username: 'admin', password: 'admin1234' });
  const cookie = (login.headers['set-cookie']?.[0] || '').split(';')[0];
  check('어드민 로그인', !!cookie, `HTTP ${login.status}`);

  const send = await post('/tc-backstage/mail/send', {
    title: `기록실패${RUN}`, body: '푸시 기록이 터져도 편지는 간다',
    target_kind: 'user', nicknames: NICK, send_push: '1',
  }, cookie);

  check('라우트가 500 으로 죽지 않는다', send.status === 302, `HTTP ${send.status}`);
  const loc = decodeURIComponent(send.headers.location || '');
  check('우편 발송은 성공으로 끝난다', loc.includes('r=ok'), loc);
  check('푸시만 실패했다고 알려준다', /푸시/.test(loc), loc);

  const rows = (await db.pool.query(
    `SELECT id FROM tc_mail WHERE title = $1`, [`기록실패${RUN}`])).rows;
  check('편지는 한 통만 저장됐다', rows.length === 1, `${rows.length}통`);

  for (const r of rows) {
    await db.pool.query('DELETE FROM tc_mail_recipients WHERE mail_id = $1', [r.id]);
    await db.pool.query('DELETE FROM tc_mail WHERE id = $1', [r.id]);
  }
  await db.pool.query('DELETE FROM tc_users WHERE nickname = $1', [NICK]);
  server.close();
})().then(() => {
  console.log(failures === 0 ? '\nPASS' : `\n${failures} FAILURE(S)`);
  process.exit(failures === 0 ? 0 : 1);
}).catch((e) => { console.error('\nERROR', e.message); process.exit(1); });
