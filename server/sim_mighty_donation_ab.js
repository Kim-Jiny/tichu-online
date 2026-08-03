'use strict';
/**
 * A-B harness: 점수 헌납을 막는 좌석(hold) vs 예전 좌석(legacy).
 * 한 테이블에서 같은 시드 딜을 두 번(캠프를 뒤집어) 쳐서 자리 편향을 씻는다.
 * 두 캠프 모두 mixoracle 이고 차이는 좌석 게이트(__mightyDonateLegacy) 하나뿐이다.
 *
 *   node sim_mighty_hold_mighty_ab.js [deals] [seedBase]   ← 실제 대국 수는 ×2
 *   NULL=1 node sim_mighty_hold_mighty_ab.js ...   ← 두 캠프 같은 규칙(A/A 검증)
 *
 * 마이티 쪽 수정과 달리 이 국면은 라운드당 0.15회쯤으로 자주 나와서, 집계
 * 점수로도 차이가 잡힐 여지가 있다. 그래도 NULL=1 로 하네스 노이즈 폭을 먼저
 * 재고 그 폭과 비교해서 읽는다. 헌납 자체가 줄었는지는
 * sim_mighty_point_donation.js 로 따로 본다.
 */
const MightyGame = require('./game/mighty/MightyGame');
const { decideMightyBotAction } = require('./game/mighty/MightyBot');
const { makeRng } = require('./game/mighty/MightyDeck');

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

const camp = { hold: { dc: 0, ds: 0, rn: 0, sc: 0 }, legacy: { dc: 0, ds: 0, rn: 0, sc: 0 } };
let passouts = 0, errors = 0;

// 듀플리케이트: 같은 딜을 캠프만 뒤집어 두 번 친다.
//
// 처음엔 딜 하나당 한 번만 쳤는데, 그러면 좌석 편향이 안 씻긴다. 같은 규칙끼리
// 붙인 A/A 검증에서 4000라운드에 +0.264점이 나왔다 — 재려는 차이보다 컸다.
// 5인 게임이라 캠프가 3석/2석으로 갈리고, 어느 쪽이 3석이냐가 정부/야당 구성과
// 얽히면서 라벨만 바꿔도 점수가 기울었다. 미러 패스를 같이 돌리면 상쇄된다.
for (let pass = 0; pass < rounds * 2; pass++) {
  const r = Math.floor(pass / 2);
  const mirror = pass % 2 === 1;
  const seatCamp = {};
  for (let i = 0; i < IDS.length; i++) {
    const hold = ((i + r) % 2 === 0) !== mirror;
    seatCamp[IDS[i]] = hold ? 'hold' : 'legacy';
  }
  // NULL=1 이면 아무도 legacy 로 안 돈다 = 같은 규칙끼리 붙는 A/A.
  global.__mightyDonateLegacy = (pid) => (!nullTest && seatCamp[pid] === 'legacy');

  const g = new MightyGame(IDS, NAMES, { targetScore: 50, rng: makeRng((1000003 * base + r) >>> 0) });
  g.start();
  let steps = 0, err = false;
  while (g.state !== 'round_end' && g.state !== 'game_end' && steps++ < 8000) {
    settle(g);
    if (g.state === 'round_end' || g.state === 'game_end') break;
    const actor = g.getPendingActor();
    if (!actor) break;
    const a = decideMightyBotAction(g, actor, 'mixoracle');
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

delete global.__mightyDonateLegacy;

const pct = (a, b) => (b > 0 ? `${(a / b * 100).toFixed(1)}%` : '-');
console.log(`\n점수 헌납 방지 A/B — ${rounds}딜 ×2(미러) (base ${base})${nullTest ? ' · NULL(A/A) 검증' : ''}`);
console.log(`passouts=${passouts} errors=${errors}\n`);
console.log('camp     주공라운드  주공성공    좌석라운드  평균점수');
for (const c of ['hold', 'legacy']) {
  const s = camp[c];
  console.log(`${c.padEnd(7)}  ${String(s.dc).padStart(9)}   ${pct(s.ds, s.dc).padStart(7)}`
    + `    ${String(s.rn).padStart(9)}   ${(s.sc / Math.max(1, s.rn)).toFixed(3).padStart(7)}`);
}
const d = (camp.hold.sc / Math.max(1, camp.hold.rn)) - (camp.legacy.sc / Math.max(1, camp.legacy.rn));
console.log(`\n  평균점수 차 (hold - legacy): ${d > 0 ? '+' : ''}${d.toFixed(3)}`);
