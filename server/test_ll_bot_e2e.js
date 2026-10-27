/**
 * 실제 서버에 러브레터 한 판을 태운다(쓰고 버리는 DB, 8093 포트).
 * 사람 1 + 빠른 봇 2. 봇은 'mc'(가상 플레이 검색) 전략이라 워커 스레드를 거친다 —
 * 서버·워커·직렬화가 맞물려 한 판이 끝까지 가는지 본다.
 *   node server/test_ll_bot_e2e.js
 */
const { Pool } = require('pg');
const { spawn } = require('child_process');
const WebSocket = require('ws');

const ADMIN_URL = process.env.TEST_PG_ADMIN || 'postgresql://jiny@localhost:5432/postgres';
const DB = 'tichu_ll_bot_e2e';
// 8093. 8092 는 test_sk_pirate_e2e, 8098 은 test_profile_privacy 가 쓴다 — 같은 번호면
// 두 테스트를 나란히 돌릴 수 없고, 뒤에 오는 쪽이 EADDRINUSE 로 죽는다.
const PORT = Number(process.env.TEST_PORT) || 8093;
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
  const acct = { username: `ll_${tag}`, password: 'smoke1234!', nickname: `편지${tag}` };
  c.send({ type: 'register', ...acct });
  await sleep(1000);
  c.send({ type: 'login', username: acct.username, password: acct.password, deviceInfo: { appVersion: c.version, locale: 'ko' } });
  if (!(await c.waitFor('login_success'))) throw new Error('login failed ' + JSON.stringify(c.last.login_error || c.all.slice(-3)));
}

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
    a.send({ type: 'create_room', roomName: '러브레터봇', gameType: 'love_letter', maxPlayers: 3 });
    check('방을 만든다', !!(await a.waitFor('room_joined')), JSON.stringify(a.last.error || ''));
    await a.waitFor('room_state');
    a.send({ type: 'add_bot', speed: 'fast' });
    await sleep(400);
    a.send({ type: 'add_bot', speed: 'fast' });
    await sleep(600);
    const rs = a.last.room_state;
    const bots = ((rs && rs.room && rs.room.players) || []).filter((p) => p && p.isBot);
    check('봇 둘이 앉는다', bots.length === 2, `bots=${bots.length}`);
    // 앱에는 내부 전략 이름('mc')이 나가면 안 된다 — 모르는 전략은 칩으로 뜬다
    check("봇 전략은 앱에 'heuristic' 으로 보인다", bots.every((b) => b.botStrategy === 'heuristic'), JSON.stringify(bots.map((b) => b.botStrategy)));

    const seen = { phases: new Set(), effects: new Set(), errors: [], turns: 0 };
    let me = null; let gameEnd = false; let lastAct = 0;
    const ty = (id) => (id || '').replace(/^ll_/, '').replace(/_\d+$/, '');
    a.onMsg = (d) => {
      if (d.type === 'error') { seen.errors.push(d.message); return; }
      if (d.type !== 'game_state' || d.state.gameType !== 'love_letter') return;
      const s = d.state;
      seen.phases.add(s.phase);
      if (s.pendingEffect) seen.effects.add(s.pendingEffect.type);
      if (s.phase === 'game_end') { gameEnd = true; return; }
      const self = s.players.find((p) => p.position === 'self');
      me = self && self.id;
      const act = (m) => { lastAct = Date.now(); setTimeout(() => a.send(m), 30); };
      const e = s.pendingEffect;
      if (s.phase === 'playing' && s.isMyTurn && s.myCards.length) {
        seen.turns++;
        const types = s.myCards.map(ty);
        // 백작부인 규칙: 왕·왕자와 같이 들면 백작부인을 내야 한다.
        const forced = types.includes('countess') && (types.includes('king') || types.includes('prince'));
        const cardId = forced ? s.myCards[types.indexOf('countess')] : s.myCards[0];
        act({ type: 'play_card', cardId });
      } else if (s.phase === 'effect_resolve' && e && e.playerId === me) {
        if (e.resolved) act({ type: 'effect_ack' });
        else if (e.type === 'guard') act({ type: 'guard_guess', targetId: e.validTargets[0], guess: 'baron' });
        else if (e.needsTarget) act({ type: 'select_target', targetId: e.validTargets[0] });
      }
    };
    a.send({ type: 'start_game' });
    const started = Date.now();
    while (!gameEnd && Date.now() - started < 420000 && Date.now() - Math.max(lastAct, started) < 40000) await sleep(500);

    check('한 판이 끝까지 간다', gameEnd, `phases=${[...seen.phases]} lastAct=${Date.now() - lastAct}ms ago`);
    check('효과 단계가 나온다', seen.phases.has('effect_resolve'), [...seen.phases].join());
    check('서버 오류가 없다', seen.errors.length === 0, seen.errors.slice(0, 3).join(' | '));
    check('워커 오류가 없다', !/bot-worker-error|botWorker: unsupported/i.test(log), (log.match(/.*(bot-worker-error|unsupported).*/i) || [''])[0]);
    console.log('  본 효과:', [...seen.effects].join(', '), '/ 내 차례', seen.turns);
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
