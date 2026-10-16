/**
 * 실제 서버를 띄워 미션·토큰 메시지를 끝까지 태운다(쓰고 버리는 DB, 8099 포트).
 *   node server/test_missions_e2e.js
 */
const { Pool } = require('pg');
const { spawn } = require('child_process');
const WebSocket = require('ws');

const ADMIN_URL = process.env.TEST_PG_ADMIN || 'postgresql://jiny@localhost:5432/postgres';
const DB = 'tichu_missions_e2e';
const PORT = 8099;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let failures = 0;
const check = (label, cond, detail = '') => {
  console.log(`${cond ? '  ok  ' : '  FAIL'} ${label}${!cond && detail ? ` — ${detail}` : ''}`);
  if (!cond) failures++;
};

function client(name) {
  const c = { name, last: {}, all: [] };
  c.ready = new Promise((res, rej) => {
    c.ws = new WebSocket(`ws://localhost:${PORT}`);
    c.ws.on('open', res);
    c.ws.on('error', rej);
    c.ws.on('message', (raw) => { const d = JSON.parse(raw); c.last[d.type] = d; c.all.push(d); });
  });
  c.send = (m) => c.ws.send(JSON.stringify(m));
  c.forget = (t) => delete c.last[t];
  c.waitFor = async (t, ms = 6000) => {
    const end = Date.now() + ms;
    while (Date.now() < end) { if (c.last[t]) return c.last[t]; await sleep(60); }
    return null;
  };
  return c;
}

async function login(c, tag) {
  const acct = { username: `m_${tag}`, password: 'smoke1234!', nickname: `미션${tag}` };
  c.nickname = acct.nickname;
  c.send({ type: 'register', ...acct });
  await sleep(1000);
  c.send({ type: 'login', username: acct.username, password: acct.password, deviceInfo: { appVersion: '99.0.0', locale: 'ko' } });
  if (!(await c.waitFor('login_success'))) throw new Error('login failed ' + JSON.stringify(c.last.login_error || c.all.slice(-3)));
}

async function main() {
  const admin = new Pool({ connectionString: ADMIN_URL });
  await admin.query(`DROP DATABASE IF EXISTS ${DB}`);
  await admin.query(`CREATE DATABASE ${DB}`);
  const dbUrl = ADMIN_URL.replace(/\/postgres$/, `/${DB}`);
  const pool = new Pool({ connectionString: dbUrl });

  const srv = spawn('node', ['server.js'], {
    cwd: __dirname,
    env: { ...process.env, PORT: String(PORT), DATABASE_URL: dbUrl },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let log = '';
  srv.stdout.on('data', (d) => { log += d; });
  srv.stderr.on('data', (d) => { log += d; });
  for (let i = 0; i < 100 && !/listening|running|8099/i.test(log); i++) await sleep(200);
  await sleep(800);

  try {
    const a = client('a'); const b = client('b');
    await Promise.all([a.ready, b.ready]);
    await login(a, 'a'); await login(b, 'b');

    a.send({ type: 'get_missions' });
    const st = await a.waitFor('missions_state');
    check('미션 상태를 받는다', st && st.success && st.offers && st.offers.tichu.missions.length >= 2, JSON.stringify(st).slice(0, 200));
    const first = st.offers.tichu.missions[0];
    a.send({ type: 'pick_mission', key: first.key });
    const pk = await a.waitFor('mission_action_result');
    check('미션 선택', pk.success && pk.state.active.some((m) => m.key === first.key), JSON.stringify(pk).slice(0, 200));
    a.forget('mission_action_result');
    a.send({ type: 'pick_mission', key: first.key });
    const pk2 = await a.waitFor('mission_action_result');
    check('중복 선택은 거절', !pk2.success && pk2.reason === 'already_picked');

    a.send({ type: 'get_token_shop' });
    const shop = await a.waitFor('token_shop');
    check('토큰 상점 상품 9개', shop.success && shop.products.length === 9, String(shop.products && shop.products.length));
    a.send({ type: 'buy_token_item', key: 'room_highlight_1' });
    const nb = await a.waitFor('token_buy_result');
    check('토큰이 없으면 못 산다', !nb.success && nb.reason === 'not_enough');

    await pool.query(`INSERT INTO tc_token_balance (nickname, balance) VALUES ($1, 200)
                      ON CONFLICT (nickname) DO UPDATE SET balance = 200`, [a.nickname]);
    a.forget('token_buy_result');
    a.send({ type: 'buy_token_item', key: 'room_highlight_2' });
    const ok1 = await a.waitFor('token_buy_result');
    check('방 목록 강조 구매 → 잔액 150', ok1.success && ok1.shop.balance === 150, JSON.stringify(ok1).slice(0, 200));
    a.forget('token_buy_result');
    a.send({ type: 'buy_token_item', key: 'bubble_basic_3' });
    const ok2 = await a.waitFor('token_buy_result');
    check('말풍선 구매 → 잔액 90', ok2.success && ok2.shop.balance === 90);

    // 방을 만들면 다른 사람의 방 목록에 강조 키가 실려 간다.
    b.forget('room_list');
    a.send({ type: 'create_room', roomName: '강조방', turnTimeLimit: 30, allowSpectators: true });
    await a.waitFor('room_joined');
    await sleep(500);
    b.send({ type: 'room_list' });
    await sleep(600);
    const rl = b.last.room_list;
    const mine = rl && rl.rooms.find((r) => r.name === '강조방');
    check('방 목록에 highlight 키', mine && mine.highlight === 'room_highlight_2', JSON.stringify(mine));

    // 채팅에 말풍선 키.
    a.send({ type: 'chat_message', message: '안녕' });
    await sleep(600);
    const chat = a.last.chat_message;
    check('채팅 메시지에 bubble 키', chat && chat.bubble === 'bubble_basic_3', JSON.stringify(chat));

    // 장착 해제 → 방 목록에서 사라짐.
    a.send({ type: 'equip_token_item', slot: 'room_highlight', key: null });
    const eq = await a.waitFor('token_equip_result');
    check('장착 해제', eq.success && !eq.shop.products.find((p) => p.key === 'room_highlight_2').equipped);
    b.forget('room_list');
    b.send({ type: 'room_list' });
    await sleep(600);
    const mine2 = b.last.room_list && b.last.room_list.rooms.find((r) => r.name === '강조방');
    check('해제하면 highlight 없음', mine2 && !mine2.highlight, JSON.stringify(mine2));
  } finally {
    srv.kill();
    await sleep(400);
    await pool.end();
    await admin.query(`DROP DATABASE IF EXISTS ${DB} WITH (FORCE)`);
    await admin.end();
  }
  console.log(failures ? `\n실패 ${failures}건` : '\n전부 통과');
  if (failures) console.log(log.split('\n').slice(-15).join('\n'));
  process.exit(failures ? 1 : 0);
}
main().catch((e) => { console.error(e); process.exit(1); });
