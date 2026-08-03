'use strict';
/**
 * A-B harness: 봉황 단독 판단 신규 규칙 vs 예전 규칙.
 *
 * 같은 딜을 두 캠프가 나눠 앉아서 치고, 라운드마다 자리를 돌려 좌석 편향을
 * 씻는다. 봇의 다른 판단은 전부 동일하고 봉황 단독 게이트만 다르다
 * (global.__tichuPhoenixLegacy 좌석 게이트).
 *
 *   node sim_tichu_phoenix_ab.js [rounds] [seedBase]
 *
 * 티츄 딜은 Math.random 을 쓰므로, 딜 동안만 시드 PRNG 로 바꿔서 두 캠프가
 * 같은 패를 받게 한다. 딜이 끝나면 원래 Math.random 을 돌려놓는다.
 */
const TichuGame = require('./game/TichuGame');
const { decideBotAction } = require('./game/BotPlayer');

const IDS = ['p0', 'p1', 'p2', 'p3'];
const NAMES = {}; IDS.forEach((p) => (NAMES[p] = p));

/** mulberry32 — 작고 재현 가능한 PRNG. */
function makeRng(seed) {
  let a = seed >>> 0;
  return function rng() {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** 딜하는 동안만 시드 난수를 쓴다. */
function withSeededDeal(seed, fn) {
  const real = Math.random;
  Math.random = makeRng(seed);
  try { return fn(); } finally { Math.random = real; }
}

const rounds = parseInt(process.argv[2] || '400', 10);
const base = parseInt(process.argv[3] || '11', 10);

const camp = { neo: { pts: 0, wins: 0 }, legacy: { pts: 0, wins: 0 } };
let phoenixPlays = { neo: 0, legacy: 0 };
let errors = 0;

// 듀플리케이트: 같은 딜을 캠프만 바꿔 두 번 친다.
//
// 처음엔 딜 하나당 한 번만 치고 라운드마다 캠프를 돌렸는데, 그러면 딜 자체의
// 유불리가 상쇄되지 않는다. 같은 규칙끼리 붙인 A/A 검증에서 시드에 따라
// -5.7 ~ +7.9점/라운드가 나왔다 — 재려는 차이보다 노이즈가 컸다.
for (let pass = 0; pass < rounds * 2; pass++) {
  const r = Math.floor(pass / 2);
  const mirror = pass % 2 === 1;
  const teamOfSeat = (i) => (i % 2 === 0 ? 'A' : 'B');
  const campOfTeam = mirror ? { A: 'legacy', B: 'neo' } : { A: 'neo', B: 'legacy' };
  const campOf = {};
  IDS.forEach((pid, i) => { campOf[pid] = campOfTeam[teamOfSeat(i)]; });
  // NULL=1 이면 두 캠프가 같은 규칙을 쓴다. 하네스 자체의 편향을 재는 A/A 검증용.
  const nullTest = process.env.NULL === '1';
  global.__tichuPhoenixLegacy = (pid) => (nullTest ? false : campOf[pid] === 'legacy');

  const game = new TichuGame(IDS, NAMES);
  try {
    withSeededDeal(base + r, () => game.start());

    let guard = 0;
    while (game.state !== 'round_end' && game.state !== 'game_end' && guard++ < 4000) {
      const s = game.state;
      const actors = (s === 'large_tichu_phase' || s === 'card_exchange')
        ? game.playerIds.slice()
        : game.needsToCallRank ? [game.needsToCallRank]
          : game.dragonPending ? [game.dragonDecider]
            : [game.currentPlayer];
      if (actors.length === 0) break;

      let progressed = false;
      for (const pid of actors) {
        if (!pid) continue;
        const trickBefore = (game.currentTrick || []).length;
        let action = decideBotAction(game, pid, 'heuristic');
        if (!action) action = game.getAutoTimeoutAction(pid);
        if (!action) continue;
        const usedPhoenix = action.type === 'play_cards'
          && (action.cards || []).length === 1
          && (action.cards || [])[0] === 'special_phoenix'
          && trickBefore > 0;
        let res = game.handleAction(pid, action);
        if (!res || !res.success) {
          const fb = game.getAutoTimeoutAction(pid);
          if (fb) res = game.handleAction(pid, fb);
        }
        if (res && res.success) {
          progressed = true;
          if (usedPhoenix) phoenixPlays[campOf[pid]]++;
        }
      }
      if (!progressed) break;
    }

    const scores = game.totalScores || game.scores || {};
    const a = Number(scores.teamA || 0);
    const b = Number(scores.teamB || 0);
    camp[campOfTeam.A].pts += a;
    camp[campOfTeam.B].pts += b;
    if (a > b) camp[campOfTeam.A].wins++;
    else if (b > a) camp[campOfTeam.B].wins++;
  } catch (e) {
    errors++;
    if (errors <= 3) console.error('round error:', e.message);
  }
}

delete global.__tichuPhoenixLegacy;

const line = (name, c) => {
  const p = phoenixPlays[name] || 0;
  console.log(
    `  ${name.padEnd(7)} 총점 ${String(c.pts).padStart(7)}  라운드승 ${String(c.wins).padStart(4)}`
    + `  봉황단독 ${String(p).padStart(4)}회`,
  );
};

console.log(`\n티츄 봉황 A/B — ${rounds}라운드 (seed ${base}~${base + rounds - 1}), 팀 캠프 교대`);
line('neo', camp.neo);
line('legacy', camp.legacy);
const diff = camp.neo.pts - camp.legacy.pts;
console.log(`\n  순점수 차 (neo - legacy): ${diff > 0 ? '+' : ''}${diff}`
  + `  · 라운드당 ${(diff / Math.max(1, rounds)).toFixed(1)}점`);
if (errors) console.log(`  errors: ${errors}`);
