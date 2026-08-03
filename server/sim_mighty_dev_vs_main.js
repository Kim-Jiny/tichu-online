'use strict';
/**
 * dev 봇 vs main(실서버) 봇 정면 대결.
 *
 * 같은 테이블에서 좌석마다 어느 쪽 코드로 판단할지 나눈다. 게임 엔진은 하나를
 * 공유하고(같은 규칙·같은 딜), 판단 함수만 다른 모듈 트리에서 가져온다.
 * 같은 딜을 캠프 뒤집어 두 번 치는 미러로 자리 편향을 씻는다.
 *
 *   MAIN_BOT=<main 트리 경로> node sim_mighty_dev_vs_main.js [deals] [seedBase]
 *   NULL=1 ... ← 두 캠프 다 dev (하네스 노이즈 폭 측정)
 *
 * main 트리는 이렇게 뽑는다:
 *   git archive main server/game/mighty | tar -x -C <dir> --strip-components=3
 */
const MightyGame = require('./game/mighty/MightyGame');
const devBot = require('./game/mighty/MightyBot');
const { makeRng } = require('./game/mighty/MightyDeck');

const MAIN_BOT = process.env.MAIN_BOT;
if (!MAIN_BOT) {
  console.error('MAIN_BOT=<main 트리 경로> 를 지정해야 한다.');
  process.exit(1);
}
const mainBot = require(`${MAIN_BOT}/MightyBot`);

const IDS = ['p0', 'p1', 'p2', 'p3', 'p4'];
const NAMES = {}; IDS.forEach(p => (NAMES[p] = p));

function settle(g) {
  let s = 200;
  while (s-- > 0) {
    if (g.state === 'trick_end') { g.advanceAfterTrickEnd(); continue; }
    break;
  }
}

const rounds = parseInt(process.argv[2] || '2000', 10);
const base = parseInt(process.argv[3] || '7', 10);
const nullTest = process.env.NULL === '1';

const camp = { dev: { dc: 0, ds: 0, rn: 0, sc: 0 }, main: { dc: 0, ds: 0, rn: 0, sc: 0 } };
let passouts = 0, errors = 0;

for (let pass = 0; pass < rounds * 2; pass++) {
  const r = Math.floor(pass / 2);
  const mirror = pass % 2 === 1;
  const seatCamp = {};
  for (let i = 0; i < IDS.length; i++) {
    seatCamp[IDS[i]] = (((i + r) % 2 === 0) !== mirror) ? 'dev' : 'main';
  }

  const g = new MightyGame(IDS, NAMES, { targetScore: 50, rng: makeRng((1000003 * base + r) >>> 0) });
  g.start();
  let steps = 0, err = false;
  while (g.state !== 'round_end' && g.state !== 'game_end' && steps++ < 8000) {
    settle(g);
    if (g.state === 'round_end' || g.state === 'game_end') break;
    const actor = g.getPendingActor();
    if (!actor) break;
    const bot = (!nullTest && seatCamp[actor] === 'main') ? mainBot : devBot;
    const a = bot.decideMightyBotAction(g, actor, 'mixoracle');
    if (!a) { err = true; break; }
    const res = g.handleAction(actor, a);
    if (!res || res.success === false) {
      const fb = g.getAutoTimeoutAction(actor);
      if (fb) g.handleAction(actor, fb); else { err = true; break; }
    }
  }
  if (err) { errors++; continue; }
  settle(g);
  if (!g.declarer || !g.roundResult) { passouts++; continue; }

  const dc = seatCamp[g.declarer];
  camp[dc].dc++;
  if (g.roundResult.success) camp[dc].ds++;
  for (const pid of IDS) {
    const c = seatCamp[pid];
    camp[c].rn++;
    camp[c].sc += (g.scores[pid] || 0);
  }
}

const pct = (a, b) => (b > 0 ? `${(a / b * 100).toFixed(1)}%` : '-');
console.log(`\ndev 봇 vs main 봇 — ${rounds}딜 ×2(미러) (base ${base})${nullTest ? ' · NULL(둘 다 dev)' : ''}`);
console.log(`passouts=${passouts} errors=${errors}\n`);
console.log('camp     주공라운드  주공성공    좌석라운드  평균점수');
for (const c of ['dev', 'main']) {
  const s = camp[c];
  console.log(`${c.padEnd(7)}  ${String(s.dc).padStart(9)}   ${pct(s.ds, s.dc).padStart(7)}`
    + `    ${String(s.rn).padStart(9)}   ${(s.sc / Math.max(1, s.rn)).toFixed(3).padStart(7)}`);
}
const d = (camp.dev.sc / Math.max(1, camp.dev.rn)) - (camp.main.sc / Math.max(1, camp.main.rn));
console.log(`\n  평균점수 차 (dev - main): ${d > 0 ? '+' : ''}${d.toFixed(3)}`);
