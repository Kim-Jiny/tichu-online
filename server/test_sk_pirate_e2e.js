/**
 * 실제 서버에 해적 능력 모드로 스컬킹 한 판을 태운다(쓰고 버리는 DB, 8098 포트).
 * 사람 1 + 빠른 봇 2. 사람은 아무 합법 카드나 내고, 능력 차례가 오면 기본 선택을 한다.
 *   node server/test_sk_pirate_e2e.js
 */
const { Pool } = require('pg');
const { spawn } = require('child_process');
const WebSocket = require('ws');

const ADMIN_URL = process.env.TEST_PG_ADMIN || 'postgresql://jiny@localhost:5432/postgres';
const DB = 'tichu_sk_pirate_e2e';
const PORT = 8098;
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
  const acct = { username: `pk_${tag}`, password: 'smoke1234!', nickname: `해적${tag}` };
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
  for (let i = 0; i < 100 && !/listening|running|8098/i.test(log); i++) await sleep(200);
  await sleep(800);

  try {
    // 옛 앱(3.2.0)은 해적 능력 방을 만들 수 없다
    const old = client('3.2.0');
    await old.ready; await login(old, 'old');
    old.send({ type: 'create_room', roomName: '옛앱', gameType: 'skull_king', maxPlayers: 3, skExpansions: ['pirate_abilities'] });
    await sleep(800);
    check('옛 앱은 해적 능력 방을 못 만든다', !old.last.room_joined && !!old.last.error, JSON.stringify(old.last.error || old.last.room_joined));

    const a = client('99.0.0');
    await a.ready; await login(a, 'a');
    a.send({ type: 'create_room', roomName: '해적능력', gameType: 'skull_king', maxPlayers: 3, skExpansions: ['pirate_abilities'] });
    const joined = await a.waitFor('room_joined');
    check('새 앱은 방을 만든다', !!joined, JSON.stringify(a.last.error || ''));
    const rs0 = await a.waitFor('room_state');
    check('방에 확장팩이 실린다', rs0 && rs0.room && (rs0.room.skExpansions || []).includes('pirate_abilities'), JSON.stringify(rs0 && rs0.room && rs0.room.skExpansions));

    // 옛 앱 목록에서는 이 방이 안 보이고, 입장도 못 한다
    old.send({ type: 'get_room_list' });
    await sleep(600);
    const rl = old.last.room_list;
    check('옛 앱의 방 목록에 안 보인다', !rl || !(rl.rooms || []).some((r) => r.name === '해적능력'), JSON.stringify((rl && rl.rooms || []).map((r) => r.name)));

    a.send({ type: 'add_bot', speed: 'fast' });
    await sleep(400);
    a.send({ type: 'add_bot', speed: 'fast' });
    await sleep(600);

    const seen = { pirates: new Set(), abilities: new Set(), maxSeq: 0, phases: new Set(), errors: [] };
    let me = null; let gameEnd = false; let lastAct = 0;
    a.onMsg = (d) => {
      if (d.type === 'error') { seen.errors.push(d.message); return; }
      if (d.type !== 'game_state' || d.state.gameType !== 'skull_king') return;
      const s = d.state;
      seen.phases.add(s.phase);
      if (s.lastAbility) seen.abilities.add(s.lastAbility.pirate);
      if (s.abilitySeq > seen.maxSeq) seen.maxSeq = s.abilitySeq;
      if (s.pendingAbility) seen.pirates.add(s.pendingAbility.pirate);
      if (s.phase === 'game_end') { gameEnd = true; return; }
      const self = s.players.find((p) => p.position === 'self');
      me = self && self.id;
      const act = (m) => { lastAct = Date.now(); setTimeout(() => a.send(m), 30); };
      if (s.phase === 'bidding' && self && self.bid === null) act({ type: 'submit_bid', bid: Math.min(1, s.round) });
      else if (s.phase === 'playing' && s.isMyTurn && s.legalCards.length) {
        const cardId = s.legalCards[Math.floor(Math.random() * s.legalCards.length)];
        act({ type: 'play_card', cardId, tigressChoice: 'pirate' });
      } else if (s.phase === 'pirate_ability' && s.pendingAbility && s.pendingAbility.playerId === me) {
        const info = s.abilityInfo || {};
        const p = s.pendingAbility.pirate;
        if (p === 'rosie') act({ type: 'use_pirate_ability', leaderId: me });
        else if (p === 'bendt') act({ type: 'use_pirate_ability', discard: info.drawn });
        else if (p === 'rascal') act({ type: 'use_pirate_ability', wager: 10 });
        else if (p === 'harry') act({ type: 'use_pirate_ability', delta: 0 });
        else act({ type: 'use_pirate_ability' });
      } else if (s.phase === 'round_end') {
        // 서버가 5초 뒤 자동으로 넘긴다
      }
    };
    a.send({ type: 'start_game' });
    const started = Date.now();
    while (!gameEnd && Date.now() - started < 420000 && Date.now() - Math.max(lastAct, started) < 40000) await sleep(500);

    check('한 판이 끝까지 간다', gameEnd, `phases=${[...seen.phases]} lastAct=${Date.now() - lastAct}ms ago`);
    check('능력 단계(pirate_ability)가 한 번 이상 나온다', seen.phases.has('pirate_ability'), [...seen.phases].join());
    check('사용된 능력이 모두에게 알려진다', seen.maxSeq >= 1 && seen.abilities.size >= 1, `seq=${seen.maxSeq} abilities=${[...seen.abilities]}`);
    check('서버 오류가 없다', seen.errors.length === 0, seen.errors.slice(0, 3).join(' | '));
    console.log('  본 능력:', [...seen.pirates].join(', '), '/ 횟수 seq =', seen.maxSeq);
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
