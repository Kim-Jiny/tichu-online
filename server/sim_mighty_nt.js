'use strict';
/**
 * 노기루다(NT) 전용 자가대국.
 *
 * 봇은 자연 상태에서 NT 를 아예 안 부른다(1500라운드에 0판). 그래서 NT 쪽
 * 로직은 자가대국으로 검증이 안 된다. 여기서는 입찰만 가로채 NT 를 강제하고
 * 나머지(키티·프렌드 지목·플레이)는 전부 봇 판단에 맡긴다.
 *
 *   node sim_mighty_nt.js [rounds] [seedBase]
 *   NULL=1 ...   ← 두 캠프 같은 규칙 (하네스 노이즈 폭)
 *
 * 캠프는 좌석으로 나누고 같은 딜을 뒤집어 두 번 친다(미러).
 * 게이트: __mightyCalledSuitLegacy — 마이티/조커 프렌드일 때 부른 문양을
 * 포기하던 예전 동작.
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

const rounds = parseInt(process.argv[2] || '1000', 10);
const base = parseInt(process.argv[3] || '7', 10);
const nullTest = process.env.NULL === '1';

const camp = { neo: { dc: 0, ds: 0, rn: 0, sc: 0 }, legacy: { dc: 0, ds: 0, rn: 0, sc: 0 } };
let passouts = 0, errors = 0, ntRounds = 0;
// 새 분기(마이티/조커 프렌드의 부른 문양 복귀)가 실제로 몇 번 걸리는지 센다.
const fired = { neo: 0, legacy: 0 };
let curCamp = 'neo';
global.__mightyCalledSuitHook = () => { fired[curCamp]++; };

for (let pass = 0; pass < rounds * 2; pass++) {
  const r = Math.floor(pass / 2);
  const mirror = pass % 2 === 1;
  const seatCamp = {};
  for (let i = 0; i < IDS.length; i++) {
    seatCamp[IDS[i]] = (((i + r) % 2 === 0) !== mirror) ? 'neo' : 'legacy';
  }
  // 부른 문양 규칙은 좌석이 아니라 전역이라(프렌드 한 명만 쓰는 규칙),
  // 캠프 단위로 라운드를 통째로 나눈다: 짝수 pass = neo, 홀수 = legacy 가
  // 아니라, 미러 짝 안에서 좌석 배치만 뒤집고 규칙은 라운드마다 번갈아 쓴다.
  // 라벨은 항상 미러 짝으로 나눈다(같은 딜을 두 캠프가 한 번씩). NULL 이면
  // 규칙만 양쪽 동일하게 두고 라벨은 그대로 둬야 하네스 노이즈가 측정된다.
  const legacyRound = mirror;
  global.__mightyCalledSuitLegacy = () => (!nullTest && legacyRound);

  // 입찰 가로채기: NT 를 부를 만한 손패(A/K 가 많은 쪽)를 주공으로 세운다.
  // 자리 돌려가며 아무나 부르게 하면 주공 성공률이 26% 로 떨어져서, 실제로
  // 사람이 NT 를 부르는 국면과 너무 달라진다. 딜만 보고 정하므로 두 패스
  // (neo/legacy)에서 같은 좌석이 주공이 된다 — 짝 비교가 유지된다.
  const bidder = null;
  curCamp = legacyRound ? 'legacy' : 'neo';

  const g = new MightyGame(IDS, NAMES, { targetScore: 50, rng: makeRng((1000003 * base + r) >>> 0) });
  g.start();

  let ntBidder = IDS[0];
  let bestStrength = -1;
  for (const pid of IDS) {
    let strength = 0;
    for (const cardId of (g.hands[pid] || [])) {
      if (cardId === 'mighty_joker') { strength += 2; continue; }
      const rank = cardId.split('_').pop();
      if (rank === 'A') strength += 3;
      else if (rank === 'K') strength += 2;
      else if (rank === 'Q') strength += 1;
    }
    if (strength > bestStrength) { bestStrength = strength; ntBidder = pid; }
  }
  let steps = 0, err = false;
  while (g.state !== 'round_end' && g.state !== 'game_end' && steps++ < 8000) {
    settle(g);
    if (g.state === 'round_end' || g.state === 'game_end') break;
    const actor = g.getPendingActor();
    if (!actor) break;

    let a;
    if (g.state === 'bidding') {
      a = actor === ntBidder
        ? { type: 'submit_bid', points: 14, suit: 'no_trump' }
        : { type: 'submit_bid', pass: true };
    } else {
      a = decideMightyBotAction(g, actor, 'mixoracle');
    }
    if (!a) { err = true; break; }
    let res = g.handleAction(actor, a);
    if (!res || res.success === false) {
      const fb = g.getAutoTimeoutAction(actor);
      if (fb) res = g.handleAction(actor, fb); else { err = true; break; }
    }
  }
  if (err) { errors++; continue; }
  settle(g);
  if (!g.declarer || !g.roundResult) { passouts++; continue; }
  if (g.trumpSuit === 'no_trump') ntRounds++;

  const c = legacyRound ? 'legacy' : 'neo';
  camp[c].dc++;
  if (g.roundResult.success) camp[c].ds++;
  // NT 라운드의 정부팀 점수만 본다 — 규칙이 프렌드 리드에만 걸리기 때문.
  for (const pid of IDS) {
    camp[c].rn++;
    camp[c].sc += (g.scores[pid] || 0);
  }
}

delete global.__mightyCalledSuitLegacy;

const pct = (a, b) => (b > 0 ? `${(a / b * 100).toFixed(1)}%` : '-');
console.log(`\nNT 강제 자가대국 — ${rounds}딜 ×2 (base ${base})${nullTest ? ' · NULL(A/A)' : ''}`);
console.log(`NT 라운드 ${ntRounds} · passouts=${passouts} errors=${errors}`);
console.log(`부른문양 복귀 발동: neo ${fired.neo}회 · legacy ${fired.legacy}회\n`);
console.log('camp     라운드   주공성공    좌석합계   평균점수');
for (const c of ['neo', 'legacy']) {
  const s = camp[c];
  console.log(`${c.padEnd(7)}  ${String(s.dc).padStart(6)}   ${pct(s.ds, s.dc).padStart(7)}`
    + `    ${String(s.rn).padStart(8)}   ${(s.sc / Math.max(1, s.rn)).toFixed(3).padStart(7)}`);
}
const d = (camp.neo.ds / Math.max(1, camp.neo.dc)) - (camp.legacy.ds / Math.max(1, camp.legacy.dc));
console.log(`\n  주공성공률 차 (neo - legacy): ${d > 0 ? '+' : ''}${(d * 100).toFixed(2)}%p`);
