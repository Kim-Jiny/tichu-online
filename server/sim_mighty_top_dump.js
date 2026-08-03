'use strict';
/**
 * 우리 팀이 이긴 트릭에 "자기 무늬 최상위" 카드를 실어 버리는 순간을 잡는다.
 *
 * 점수 1점을 얹으려고 나중에 트릭을 가져올 A/K 를 버리는 건 손해다.
 * (예: 기루다 하트, 손에 ♣6 과 ♣A → ♣A 를 버린다)
 *
 * 잡는 조건:
 *   - 낸 카드가 마이티/조커가 아니고 기루다도 아니면서 그 무늬 실질 최상위
 *   - 그 카드로 트릭을 이기려는 게 아니다 (현재 승자를 못 넘는다 = 버리는 수)
 *   - 봇이 아는 한 이 트릭은 우리 팀 것이다
 *   - 최상위가 아닌 값싼 대안이 손에 있었다
 *
 *   node sim_mighty_top_dump.js [rounds] [seedBase] [strategy]
 */
const MightyGame = require('./game/mighty/MightyGame');
const MB = require('./game/mighty/MightyBot');
const { decideMightyBotAction } = MB;
const { getCardInfo } = require('./game/mighty/MightyDeck');

const IDS = ['p0', 'p1', 'p2', 'p3', 'p4'];
const NAMES = {}; IDS.forEach((p) => (NAMES[p] = p));

const rounds = parseInt(process.argv[2] || '300', 10);
const base = parseInt(process.argv[3] || '5', 10);
const strategy = process.argv[4] || 'mixoracle';

let dumps = 0, wasted = 0, errors = 0;
const samples = [];
const byRole = {};
const bySource = {};
let lastPath = null, lastRule = null;
global.__mightyPathTrace = (p) => { lastPath = p; if (p !== 'rules') lastRule = null; };
global.__mightyRuleTrace = (n) => { lastRule = n; };

for (let r = 0; r < rounds; r++) {
  const game = new MightyGame(IDS, NAMES, { seed: base + r });
  try {
    game.start();
    let guard = 0;
    while (game.state !== 'game_end' && guard++ < 4000) {
      if (game.state === 'round_end') break;
      if (game.state === 'trick_end') { game.advanceAfterTrickEnd(); continue; }
      const actor = game.currentPlayer;
      if (!actor) break;
      const legal = game._getLegalCards(actor) || [];
      const action = decideMightyBotAction(game, actor, strategy);
      if (!action) break;

      const cardId = action.type === 'play_card' ? action.cardId : null;
      const trump = game.trumpSuit;
      const isTop = (c) => c !== game.getMightyCard() && c !== 'mighty_joker'
        && getCardInfo(c).suit !== trump && MB.isEffectiveTopOfSuit(c, game);

      if (cardId && game.currentTrick.length > 0 && isTop(cardId)
          && !MB.canBeatCurrentWinner(game, cardId)) {
        dumps++;
        const winner = MB.getCurrentTrickWinner(game);
        const gov = MB.isGovernmentSelf(game, actor);
        const believesAlly = gov
          ? MB.isGovernmentSelf(game, winner)
          : (game.friendRevealed ? !MB.isGovernment(game, winner) : winner !== game.declarer);
        const alt = legal.filter((c) => c !== cardId && c !== 'mighty_joker'
          && c !== game.getMightyCard() && !isTop(c));
        if (believesAlly && alt.length > 0) {
          wasted++;
          const role = actor === game.declarer ? '주공'
            : MB.isFriend(game, actor) ? '프렌드' : '야당';
          byRole[role] = (byRole[role] || 0) + 1;
          const src = lastPath === 'rules' ? `rules:${lastRule}` : String(lastPath);
          bySource[src] = (bySource[src] || 0) + 1;
          if (samples.length < 5 && (!process.env.ROLE || role === process.env.ROLE)) {
            samples.push({
              round: r, trick: game.tricks.length + 1, trump, role,
              revealed: game.friendRevealed,
              cur: game.currentTrick.map(p => `${p.pid}:${p.cardId.replace('mighty_', '')}`).join(' '),
              played: cardId.replace('mighty_', ''),
              alt: alt.map(x => x.replace('mighty_', '')).join(' '),
              hand: (game.hands[actor] || []).map(x => x.replace('mighty_', '')).join(' '),
            });
          }
        }
      }

      const res = game.handleAction(actor, action);
      if (!res || !res.success) break;
    }
  } catch (e) {
    errors++;
    if (errors <= 2) console.error('round error:', e.message);
  }
}

console.log(`\n최상위 카드 헌납 스캔 — ${rounds}라운드, ${strategy}`);
console.log(`  최상위 카드를 버리는 수로 낸 횟수: ${dumps}`);
console.log(`  그중 우리 팀 트릭에 실으면서 값싼 대안이 있었던 경우: ${wasted}`
  + (dumps ? ` (${((wasted / dumps) * 100).toFixed(0)}%)` : ''));
if (errors) console.log(`  errors: ${errors}`);
for (const [label, tally] of [['역할별', byRole], ['결정 경로', bySource]]) {
  const e = Object.entries(tally).sort((a, b) => b[1] - a[1]);
  if (!e.length) continue;
  console.log(`\n  ${label}:`);
  for (const [k, v] of e) console.log(`    ${String(v).padStart(3)}회  ${k}`);
}
for (const s of samples) {
  console.log(`\n  [R${s.round} 트릭${s.trick}] ${s.role}${s.revealed ? '' : '(미공개)'} · 기루다 ${s.trump}`);
  console.log(`    트릭: ${s.cur}  → 낸 카드 ${s.played}  (대안: ${s.alt})`);
  console.log(`    손패: ${s.hand}`);
}
