'use strict';

/**
 * Live-server smoke for the bot worker offload. Boots the REAL server, opens a
 * WebSocket, creates a tichu room, adds 3 server-side `winrate` bots (an
 * offloaded strategy), starts the game, and plays the human seat with simple
 * legal moves. Then it inspects the server's own stdout to assert:
 *
 *   1. the game actually started and progressed,
 *   2. bot decisions ran in a WORKER (via=worker DIAG lines), and
 *   3. no async-glue error / crash / unhandled rejection occurred.
 *
 * This is the end-to-end gate that the unit/pool tests can't cover: the real
 * server.js scheduleBotActions async wiring under a live game.
 *
 *   node test_worker_live_smoke.js
 */

const { spawn } = require('child_process');
const path = require('path');
const WebSocket = require('ws');

const PORT = 8123; // avoid clashing with a dev server on 8080
const URL = `ws://localhost:${PORT}`;
const TIME_BUDGET_MS = 75000;

let logbuf = '';
function serverSaw(re) { return re.test(logbuf); }

function bootServer() {
  return new Promise((resolve, reject) => {
    const child = spawn('node', ['server.js'], {
      cwd: __dirname,
      env: { ...process.env, PORT: String(PORT), DIAG: '1', DIAG_BOT_SLOW_MS: '0' },
    });
    const onData = (d) => {
      logbuf += d.toString();
      if (/Tichu server running on port/.test(logbuf)) { cleanup(); resolve(child); }
    };
    const onErr = (d) => { logbuf += d.toString(); };
    const to = setTimeout(() => { cleanup(); reject(new Error('server boot timeout')); }, 20000);
    function cleanup() { clearTimeout(to); child.stdout.off('data', onData); }
    child.stdout.on('data', onData);
    child.stderr.on('data', onErr);
    // keep capturing after boot
    child.stdout.on('data', (d) => { logbuf += d.toString(); });
    child.on('exit', (code) => { logbuf += `\n[server exited code=${code}]\n`; });
  });
}

// ---- minimal tichu human client (legal-ish auto play for its own seat) ----
class Host {
  constructor() {
    this.ws = null; this.playerId = null; this.myCards = []; this.botsAdded = false;
    this.started = false; this.rounds = 0; this.done = false;
    const uniq = Date.now().toString(36);
    this.username = `smoke_${uniq}`;
    this.password = 'smoke_pw_123';
    this.nickname = `스모크${uniq.slice(-4)}`;
  }
  connect() {
    return new Promise((res, rej) => {
      this.ws = new WebSocket(URL);
      this.ws.on('open', res);
      this.ws.on('error', rej);
      this.ws.on('message', (raw) => this.onMsg(JSON.parse(raw.toString())));
    });
  }
  send(o) { if (this.ws && this.ws.readyState === WebSocket.OPEN) this.ws.send(JSON.stringify(o)); }
  onMsg(data) {
    switch (data.type) {
      case 'register_result':
        // Whether it succeeded or the user already existed, proceed to login.
        this.send({ type: 'login', username: this.username, password: this.password });
        break;
      case 'login_error':
        console.error(`  login_error: ${data.message}`);
        break;
      case 'login_success':
        this.playerId = data.playerId;
        this.send({ type: 'create_room', roomName: '워커스모크', gameType: 'tichu', targetScore: 100, turnTimeLimit: 10 });
        break;
      case 'room_joined':
        if (!this.botsAdded) {
          this.botsAdded = true;
          // 3 server-side winrate bots (offloaded strategy) fill the room.
          let n = 0;
          const addOne = () => {
            if (n++ >= 3) { setTimeout(() => this.send({ type: 'start_game' }), 800); return; }
            this.send({ type: 'add_bot', strategy: 'winrate', speed: 'fast' });
            setTimeout(addOne, 350);
          };
          addOne();
        }
        break;
      case 'game_state':
        this.onState(data.state);
        break;
    }
  }
  onState(s) {
    if (!s) return;
    this.myCards = s.myCards || [];
    const phase = s.phase;
    if (phase === 'large_tichu_phase') {
      if (!s.largeTichuResponded) this.send({ type: 'pass_large_tichu' });
    } else if (phase === 'card_exchange') {
      if (!s.exchangeDone && this.myCards.length >= 3) {
        const normal = this.myCards.filter((c) => !c.startsWith('special_'));
        const low = [...normal].sort((a, b) => this.val(a) - this.val(b));
        const high = [...normal].sort((a, b) => this.val(b) - this.val(a));
        this.send({ type: 'exchange_cards', cards: { left: low[0] || this.myCards[0], partner: high[0] || this.myCards[1], right: low[1] || this.myCards[2] } });
      }
    } else if (phase === 'playing') {
      if (s.dragonPending && s.dragonDecider === this.playerId) { this.send({ type: 'dragon_give', target: 'left' }); return; }
      if (s.isMyTurn) setTimeout(() => this.play(s), 120);
    } else if (phase === 'round_end') {
      this.rounds++;
      setTimeout(() => this.send({ type: 'next_round' }), 1200);
    } else if (phase === 'game_end') {
      this.done = true;
    }
  }
  play(s) {
    const trick = s.currentTrick || [];
    const cards = this.myCards;
    if (!cards.length) return this.send({ type: 'pass' });
    const normal = cards.filter((c) => !c.startsWith('special_'));
    if (trick.length === 0) {
      if (cards.includes('special_dog')) return this.send({ type: 'play_cards', cards: ['special_dog'] });
      if (cards.includes('special_bird')) return this.send({ type: 'play_cards', cards: ['special_bird'], callRank: 'A' });
      if (normal.length) return this.send({ type: 'play_cards', cards: [normal.sort((a, b) => this.val(a) - this.val(b))[0]] });
      return this.send({ type: 'play_cards', cards: [cards[0]] });
    }
    const last = trick[trick.length - 1];
    const lastVal = last.comboValue || 0;
    if (last.combo === 'single') {
      const beat = normal.sort((a, b) => this.val(a) - this.val(b)).find((c) => this.val(c) > lastVal);
      if (beat) return this.send({ type: 'play_cards', cards: [beat] });
      if (cards.includes('special_dragon') && lastVal < 15) return this.send({ type: 'play_cards', cards: ['special_dragon'] });
    }
    this.send({ type: 'pass' });
  }
  val(c) {
    if (c === 'special_bird') return 1; if (c === 'special_dog') return 0;
    if (c === 'special_phoenix') return 14.5; if (c === 'special_dragon') return 15;
    const m = { '2':2,'3':3,'4':4,'5':5,'6':6,'7':7,'8':8,'9':9,'10':10,'J':11,'Q':12,'K':13,'A':14 };
    return m[c.split('_')[1]] || 0;
  }
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  console.log(`Booting real server on :${PORT} (DIAG_BOT_SLOW_MS=0)...`);
  const server = await bootServer();
  const boughtWorker = serverSaw(/Bot worker pool started/);
  console.log(`  server up. worker pool: ${boughtWorker ? 'ON' : 'OFF(!)'}`);

  const host = new Host();
  await host.connect();
  host.send({ type: 'register', username: host.username, password: host.password, nickname: host.nickname });

  const t0 = Date.now();
  while (!host.done && Date.now() - t0 < TIME_BUDGET_MS && host.rounds < 3) await sleep(500);
  await sleep(500);

  // ---- assertions from the server's own log ----
  const errors = [];
  const check = (cond, msg) => { if (!cond) errors.push(msg); };

  check(boughtWorker, 'server did not start the worker pool');
  check(serverSaw(/tichu game started/), 'game never started');
  check(serverSaw(/via=worker/), 'no bot decision ran in a worker (via=worker missing) — offload not exercised');
  check(host.rounds >= 1 || host.done, `game did not complete a round (rounds=${host.rounds}, done=${host.done})`);

  // Hard failures: async-glue crashes / unhandled rejections / worker breakage.
  const badPatterns = [
    /scheduleBotActions callback error/,
    /play-delay timer error/,
    /UnhandledPromiseRejection|Unhandled promise rejection/i,
    /worker pool init failed/,
    /serialize failed/,
    /\bTypeError\b|\bReferenceError\b/,
    /\[server exited code=[^0]/,
  ];
  for (const p of badPatterns) check(!serverSaw(p), `server log contains failure marker: ${p}`);

  // Informational counts.
  const workerDecisions = (logbuf.match(/via=worker/g) || []).length;
  const botFallbacks = (logbuf.match(/bot-worker-fallback/g) || []).length;
  const actionFailed = (logbuf.match(/\[BOT\].*action failed/g) || []).length;
  const matchSaved = serverSaw(/Match result saved/);
  console.log(`  rounds=${host.rounds} gameEnd=${host.done} matchSaved=${matchSaved}`);
  console.log(`  worker decisions=${workerDecisions}  worker-fallbacks=${botFallbacks}  bot action-failed=${actionFailed}`);
  const diagBots = (logbuf.match(/bots=q\S+/g) || []).slice(-1)[0];
  if (diagBots) console.log(`  last DIAG pool stats: ${diagBots}`);

  // Diagnostic: key server-log lines (room lifecycle / errors).
  const keyLines = logbuf.split('\n').filter((l) =>
    /Room created|Bot .* added|game started|Match result|error|ERROR|host_only|required|ready|login/i.test(l)
    && !/DIAG] 30s/.test(l)).slice(0, 25);
  if (keyLines.length) { console.log('  --- server log (key lines) ---'); for (const l of keyLines) console.log('   ' + l.trim()); }

  try { server.kill('SIGKILL'); } catch (_) {}

  if (errors.length) {
    console.error('\nFAIL:');
    for (const e of errors) console.error('  - ' + e);
    process.exit(1);
  }
  console.log('\nOK — live server ran a tichu game with 3 offloaded winrate bots: ' +
    'decisions ran in workers, no async-glue errors, game progressed.');
  process.exit(0);
}

main().catch((e) => { console.error(e); process.exit(1); });
