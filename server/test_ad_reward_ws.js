/**
 * 광고 보상 메시지가 실제 서버를 통해 오가는지(쓰고 버리는 DB, 8094 포트).
 *   get_ad_reward_status → ad_reward_status, ad_reward(claimId) → ad_reward_result
 *   같은 claimId 를 다시 보내도 한 번만 지급된다.
 *   node server/test_ad_reward_ws.js
 */
const { Pool } = require('pg');
const { spawn } = require('child_process');
const WebSocket = require('ws');

const ADMIN_URL = process.env.TEST_PG_ADMIN || 'postgresql://jiny@localhost:5432/postgres';
const DB = 'tichu_ad_reward_ws';
// 8094. 8092 는 test_sk_pirate_e2e, 8093 은 test_ll_bot_e2e, 8098 은 test_profile_privacy 가 쓴다 — 같은 번호면
// 두 테스트를 나란히 돌릴 수 없고, 뒤에 오는 쪽이 EADDRINUSE 로 죽는다.
const PORT = Number(process.env.TEST_PORT) || 8094;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let failures = 0;
const check = (label, cond, detail = '') => {
  console.log(`${cond ? '  ok  ' : '  FAIL'} ${label}${!cond && detail ? ` — ${detail}` : ''}`);
  if (!cond) failures++;
};

function client(version) {
  const c = { last: {}, all: [], version };
  c.ready = new Promise((res, rej) => {
    c.ws = new WebSocket(`ws://localhost:${PORT}`);
    c.ws.on('open', res);
    c.ws.on('error', rej);
    c.ws.on('message', (raw) => { const d = JSON.parse(raw); c.last[d.type] = d; c.all.push(d); if (c.onMsg) c.onMsg(d); });
  });
  c.send = (m) => c.ws.send(JSON.stringify(m));
  c.waitFor = async (t, ms = 6000) => {
    const end = Date.now() + ms;
    while (Date.now() < end) { if (c.last[t]) return c.last[t]; await sleep(60); }
    return null;
  };
  return c;
}

async function login(c, tag) {
  const acct = { username: `ad_${tag}`, password: 'smoke1234!', nickname: `광고${tag}` };
  c.send({ type: 'register', ...acct });
  await sleep(1000);
  c.send({ type: 'login', username: acct.username, password: acct.password, deviceInfo: { appVersion: c.version, locale: 'ko' } });
  if (!(await c.waitFor('login_success'))) throw new Error('login failed ' + JSON.stringify(c.last.login_error || c.all.slice(-3)));
}

// 이 파일의 check 는 (설명, 조건) 순서다. 읽기 쉽게 (조건, 설명) 로 쓰는 ok 를 둔다.
const ok = (cond, label, detail) => check(label, !!cond, detail);

async function main() {
  const admin = new Pool({ connectionString: ADMIN_URL });
  await admin.query(`DROP DATABASE IF EXISTS ${DB}`);
  await admin.query(`CREATE DATABASE ${DB}`);
  const dbUrl = ADMIN_URL.replace(/\/postgres$/, `/${DB}`);

  const srv = spawn('node', ['server.js'], {
    cwd: __dirname,
    env: { ...process.env, PORT: String(PORT), DATABASE_URL: dbUrl },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let log = '';
  srv.stdout.on('data', (d) => { log += d; });
  srv.stderr.on('data', (d) => { log += d; });
  for (let i = 0; i < 100 && !new RegExp(`listening|running|${PORT}`, 'i').test(log); i++) await sleep(200);
  await sleep(800);

  try {
    const a = client('99.0.0');
    await a.ready; await login(a, 'a');

    const ask = async (msg, type) => {
      delete a.last[type];
      a.send(msg);
      return a.waitFor(type, 4000);
    };

    let st = await ask({ type: 'get_ad_reward_status' }, 'ad_reward_status');
    ok(st && st.success && st.used === 0 && st.remaining === 5 && st.max === 5, '처음엔 0번 받음', JSON.stringify(st));

    let r = await ask({ type: 'ad_reward', claimId: 'ws-1' }, 'ad_reward_result');
    ok(r && r.success && r.remaining === 4 && typeof r.gold === 'number', '지급된다', JSON.stringify(r));
    ok(r && r.claimId === 'ws-1', '성공 응답은 요청 claimId 를 돌려준다', JSON.stringify(r));
    const gold = r && r.gold;

    r = await ask({ type: 'ad_reward', claimId: 'ws-1' }, 'ad_reward_result');
    ok(r && r.success && r.repeat === true && r.gold === gold, '같은 claimId 를 다시 보내면 골드가 그대로다', JSON.stringify(r));

    ok(r && r.claimId === 'ws-1', '중복 지급 응답도 원래 claimId 를 돌려준다', JSON.stringify(r));

    st = await ask({ type: 'get_ad_reward_status' }, 'ad_reward_status');
    ok(st && st.used === 1 && st.remaining === 4, '서버가 센 횟수는 1', JSON.stringify(st));

    for (let i = 2; i <= 5; i++) await ask({ type: 'ad_reward', claimId: `ws-${i}` }, 'ad_reward_result');
    r = await ask({ type: 'ad_reward', claimId: 'ws-6' }, 'ad_reward_result');
    ok(r && !r.success && r.messageKey === 'db_ad_reward_exhausted', '여섯 번째는 거절 + 거절 사유가 messageKey 로 온다', JSON.stringify(r));
    ok(r && r.claimId === 'ws-6', '거절 응답도 요청 claimId 를 돌려준다', JSON.stringify(r));
    const legacy = await ask({ type: 'ad_reward' }, 'ad_reward_result');
    ok(legacy && !legacy.success && legacy.claimId === null, 'id 없는 구형 앱도 정상 응답을 받는다', JSON.stringify(legacy));
    st = await ask({ type: 'get_ad_reward_status' }, 'ad_reward_status');
    ok(st && st.used === 5 && st.remaining === 0, '거절 뒤에도 횟수는 5', JSON.stringify(st));
    ok(!/Claim ad reward error|Get ad reward status error/.test(log), '서버 오류 로그가 없다');
  } finally {
    srv.kill();
    await sleep(500);
    await admin.query(`DROP DATABASE IF EXISTS ${DB} WITH (FORCE)`).catch(() => {});
    await admin.end();
  }
  console.log(failures ? `\n실패 ${failures}건` : '\n전부 통과');
  if (failures) { console.log(log.split('\n').slice(-30).join('\n')); }
  process.exit(failures ? 1 : 0);
}
main().catch((e) => { console.error(e); process.exit(1); });
