/**
 * 어드민의 모든 메뉴 화면을 실제로 열어 본다(쓰고 버리는 DB, 8097 포트).
 *   node server/test_admin_pages_smoke.js
 * 테마를 바꿔도 페이지가 깨지지 않았는지(200, 새 뼈대, 정의되지 않은 값이 글자로 새지 않음)만 본다.
 */
const { Pool } = require('pg');
const { spawn } = require('child_process');
const http = require('http');

const ADMIN_URL = process.env.TEST_PG_ADMIN || 'postgresql://jiny@localhost:5432/postgres';
const DB = 'tichu_admin_smoke';
const PORT = 8097;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let failures = 0;
const check = (label, cond, detail = '') => {
  console.log(`${cond ? '  ok  ' : '  FAIL'} ${label}${!cond && detail ? ` — ${detail}` : ''}`);
  if (!cond) failures++;
};

const req = (method, path, body, cookie) => new Promise((resolve, reject) => {
  const data = body ? new URLSearchParams(body).toString() : null;
  const r = http.request({
    host: 'localhost', port: PORT, path, method,
    headers: {
      ...(cookie ? { Cookie: cookie } : {}),
      ...(data ? { 'Content-Type': 'application/x-www-form-urlencoded', 'Content-Length': Buffer.byteLength(data) } : {}),
    },
  }, (res) => {
    const chunks = [];
    res.on('data', (c) => chunks.push(c));
    res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, buf: Buffer.concat(chunks), body: Buffer.concat(chunks).toString('utf8') }));
  });
  r.on('error', reject);
  if (data) r.write(data);
  r.end();
});

async function main() {
  const admin = new Pool({ connectionString: ADMIN_URL });
  await admin.query(`DROP DATABASE IF EXISTS ${DB}`);
  await admin.query(`CREATE DATABASE ${DB}`);
  const dbUrl = ADMIN_URL.replace(/\/postgres$/, `/${DB}`);
  const pool = new Pool({ connectionString: dbUrl });
  const srv = spawn('node', ['server.js'], { cwd: __dirname, env: { ...process.env, PORT: String(PORT), DATABASE_URL: dbUrl }, stdio: ['ignore', 'pipe', 'pipe'] });
  let log = '';
  srv.stdout.on('data', (d) => { log += d; });
  srv.stderr.on('data', (d) => { log += d; });
  for (let i = 0; i < 100 && !/listening|running|8097/i.test(log); i++) await sleep(200);
  await sleep(800);

  try {
    const bcrypt = require(require.resolve('bcrypt', { paths: [__dirname] }));
    await pool.query(
      `INSERT INTO admin_accounts (username, password) VALUES ('smoke_admin', $1) ON CONFLICT (username) DO UPDATE SET password = EXCLUDED.password`,
      [await bcrypt.hash('adminpass1!', 4)],
    );

    // 로그인 전: 로그인 화면과 이미지는 열리고, 나머지는 로그인으로 보낸다
    const lg = await req('GET', '/tc-backstage/login');
    check('로그인 화면(카툰)', lg.status === 200 && lg.body.includes('mascot') && lg.body.includes('Tichu Admin'));
    for (const f of ['dragon_head.webp', 'dragon_full.webp', 'dragon_icon.webp']) {
      const im = await req('GET', `/tc-backstage/_a/${f}`);
      check(`마스코트 이미지 ${f}`, im.status === 200 && /image\/webp/.test(im.headers['content-type']) && im.buf.length > 1000);
    }
    check('이미지 경로 탈출은 막는다', (await req('GET', '/tc-backstage/_a/..%2Fserver.js')).status === 404
      && (await req('GET', '/tc-backstage/_a/nope.webp')).status === 404);
    check('로그인 전에는 로그인으로 보낸다', (await req('GET', '/tc-backstage/users')).status === 302);

    const login = await req('POST', '/tc-backstage/login', { username: 'smoke_admin', password: 'adminpass1!' });
    const cookie = (login.headers['set-cookie'] || [])[0]?.split(';')[0];
    check('로그인', login.status === 302 && !!cookie);

    const { NAV_GROUPS } = require('./admin_theme');
    const items = NAV_GROUPS.flatMap((g) => g.items);
    for (const it of items) {
      const r = await req('GET', it.href, null, cookie);
      const bad = /\bundefined\b|\[object Object\]|NaN/.test(r.body.replace(/<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>/g, ''));
      check(`${it.label} (${it.href})`, r.status === 200 && r.body.includes('class="sidebar"') && r.body.includes('nav-link active') && !bad,
        `status=${r.status} bad=${bad} ${bad ? (r.body.match(/.{40}(undefined|\[object Object\]|NaN).{40}/) || [''])[0] : ''}`);
    }
    // 사이드바 구성
    const home = await req('GET', '/tc-backstage/', null, cookie);
    check('사이드바에 모든 메뉴가 있다', items.every((it) => home.body.includes(`href="${it.href}"`)));
    check('그룹이 접고 펼 수 있게 들어 있다', (home.body.match(/<details class="nav-group"/g) || []).length === NAV_GROUPS.length);
    check('접속 현황 칸', /class="sb-live"/.test(home.body));
    check('페이지 제목에 아이콘', home.body.includes('pt-icon'));
    check('유저 검색 상단 바', home.body.includes('action="/tc-backstage/users"'));

    // 로그아웃 후 다시 막힌다
    const lo = await req('GET', '/tc-backstage/logout', null, cookie);
    check('로그아웃', lo.status === 302);
  } finally {
    srv.kill();
    await sleep(500);
    await pool.end().catch(() => {});
    await admin.query(`DROP DATABASE IF EXISTS ${DB} WITH (FORCE)`).catch(() => {});
    await admin.end();
  }
  console.log(failures ? `\n실패 ${failures}건` : '\n전부 통과');
  if (failures) console.log(log.split('\n').slice(-25).join('\n'));
  process.exit(failures ? 1 : 0);
}
main().catch((e) => { console.error(e); process.exit(1); });
