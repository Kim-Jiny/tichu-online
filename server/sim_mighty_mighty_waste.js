'use strict';
/**
 * 마이티(최강 카드)를 굳이 안 써도 되는 자리에서 쓰는 순간을 잡는다.
 *
 * 잡는 조건: 봇이 마이티를 냈는데, 같은 트릭에서 마이티 말고도
 * "그 무늬의 실질 최상위 카드"를 낼 수 있었던 경우. 리드 무늬의 최상위는
 * 조커가 아니면 못 넘으므로, 그걸 두고 마이티를 쓰는 건 대개 낭비다.
 *
 *   node sim_mighty_mighty_waste.js [rounds] [seedBase] [strategy]
 */
const MightyGame = require('./game/mighty/MightyGame');
const { decideMightyBotAction } = require('./game/mighty/MightyBot');
const { getCardInfo } = require('./game/mighty/MightyDeck');
const MightyBotInternals = require('./game/mighty/MightyBot');

const IDS = ['p0', 'p1', 'p2', 'p3', 'p4'];
const NAMES = {}; IDS.forEach((p) => (NAMES[p] = p));

const rounds = parseInt(process.argv[2] || '200', 10);
const base = parseInt(process.argv[3] || '5', 10);
const strategy = process.argv[4] || 'mixoracle';

const RANK_ORDER = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];
const rankIdx = (r) => RANK_ORDER.indexOf(r);

/**
 * 이 카드가 자기 무늬 최상위인가 — 봇이 실제로 쓰는 판정을 그대로 쓴다.
 * 예전엔 "내 손패 + 나온 카드"만 보고 따졌는데, 그러면 상대가 들고 있는
 * 에이스를 못 보고 K 를 최상위로 세어 낭비가 아닌 수까지 낭비로 셌다.
 */
function isTopOfSuit(game, botId, cardId) {
  if (cardId === 'mighty_joker') return false;
  return MightyBotInternals.isEffectiveTopOfSuit(cardId, game);
}

let plays = 0, waste = 0, errors = 0;
const samples = [];
// 어느 결정 경로/룰이 그 수를 냈는지 받아 둔다 (mixoracle 이 노출하는 훅).
let lastPath = null;
let lastRule = null;
const bySource = {};
global.__mightyPathTrace = (path) => { lastPath = path; if (path !== 'rules') lastRule = null; };
global.__mightyRuleTrace = (name) => { lastRule = name; };

for (let r = 0; r < rounds; r++) {
  const game = new MightyGame(IDS, NAMES, { seed: base + r });
  try {
    game.start();
    let guard = 0;
    while (game.state !== 'game_end' && guard++ < 4000) {
      if (game.state === 'round_end') { game.advanceAfterTrickEnd?.(); break; }
      const actor = game.currentPlayer;
      if (!actor) break;
      const mightyCard = game.getMightyCard();
      const legal = typeof game._getLegalCards === 'function' ? game._getLegalCards(actor) : [];
      const action = decideMightyBotAction(game, actor, strategy);
      if (!action) break;

      if (action.type === 'play_card' && action.cardId === mightyCard && game.currentTrick.length > 0) {
        plays++;
        // 낭비의 정의: 지금 이긴 카드를 넘을 수 있으면서 그 무늬 최상위인 카드가
        // 손에 있는데도 마이티를 쓴 경우. "이길 수 있는"까지 봐야 한다 —
        // 앞사람이 이미 기루다로 잘라간 트릭에서는 무늬 최상위를 들고 있어도
        // 그걸론 못 이기고, 그때 마이티는 낭비가 아니다.
        const alt = legal.filter((c) => c !== mightyCard && c !== 'mighty_joker'
          && MightyBotInternals.canBeatCurrentWinner(game, c)
          && isTopOfSuit(game, actor, c));
        if (alt.length > 0) {
          waste++;
          const src = lastPath === 'rules' ? `rules:${lastRule}` : String(lastPath);
          bySource[src] = (bySource[src] || 0) + 1;
          if (samples.length < 5) {
            samples.push({
              round: r,
              trick: game.tricks.length + 1,
              trump: game.trumpSuit,
              lead: game.currentTrick[0].cardId,
              role: actor === game.declarer ? '주공'
                : actor === game.partner ? '프렌드' : '야당',
              revealed: game.friendRevealed,
              friendCard: game.friendCard,
              mightyIsFriendCard: game.friendCard === mightyCard,
              hand: (game.hands[actor] || []).join(' '),
              // 대안 헬퍼가 그 자리에서 뭘 고르는지 — 카드가 나오는데도 마이티를
              // 냈다면, 그 수는 다른 판단 경로에서 나온 것이다.
              helper: MightyBotInternals.topOfSuitInsteadOfMighty(
                game, actor, legal.filter(c => MightyBotInternals.canBeatCurrentWinner(game, c)),
              ),
              alt: alt.join(' '),
              players: game.playerCount,
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

console.log(`\n마이티 낭비 스캔 — ${rounds}라운드, ${strategy}`);
console.log(`  마이티를 따라내기로 쓴 횟수: ${plays}`);
console.log(`  그중 그 무늬 최상위로도 이길 수 있었던 경우: ${waste}`
  + (plays ? ` (${((waste / plays) * 100).toFixed(0)}%)` : ''));
if (errors) console.log(`  errors: ${errors}`);
const srcs = Object.entries(bySource).sort((a, b) => b[1] - a[1]);
if (srcs.length) {
  console.log('\n  낭비를 낸 결정 경로:');
  for (const [k, v] of srcs) console.log(`    ${String(v).padStart(3)}회  ${k}`);
}
for (const s of samples) {
  console.log(`\n  [R${s.round} 트릭${s.trick}] ${s.role}${s.revealed ? '' : '(미공개)'} · 기루다 ${s.trump} · 리드 ${s.lead}`
    + ` · 프렌드카드 ${s.friendCard}${s.mightyIsFriendCard ? ' (=마이티)' : ''}`);
  console.log(`    손패: ${s.hand}`);
  console.log(`    마이티 대신 낼 수 있었던 최상위: ${s.alt} · 헬퍼 선택: ${s.helper}`);
}
