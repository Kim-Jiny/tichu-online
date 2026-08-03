'use strict';
/**
 * 친구 지목이 뜬금없는지 본다.
 *
 * 지목할 때마다 상황을 기록하고, 사람이 봤을 때 이상한 유형을 분류한다:
 *   selfHeld     - 자기가 이미 들고 있는 카드를 지목 (사실상 노프렌드)
 *   voidSuit     - 그 무늬가 자기 손에 하나도 없음 → 친구가 드러날 계기가 없다
 *   kingNoAce    - 그 무늬 A 를 자기가 안 들고 있는데 K 를 지목 → A 가진 쪽이
 *                  그냥 먹으면 친구는 안 나온다
 *   lowCard      - K 미만 카드를 지목
 *   trumpSuit    - 기루다 무늬를 지목 (기루다는 자기가 관리하는 게 보통)
 *
 *   node sim_mighty_friendpick.js [rounds] [seedBase] [strategy]
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

const picks = {};
const flags = {};
const samples = [];
let total = 0, errors = 0;
const short = (c) => String(c).replace('mighty_', '');

for (let r = 0; r < rounds; r++) {
  const game = new MightyGame(IDS, NAMES, { seed: base + r });
  try {
    game.start();
    let guard = 0;
    while (game.state !== 'game_end' && guard++ < 4000) {
      if (game.state === 'round_end') break;
      if (game.state === 'trick_end') { game.advanceAfterTrickEnd(); continue; }
      const actor = game.getPendingActor();
      if (!actor) break;
      const action = decideMightyBotAction(game, actor, strategy);
      if (!action) break;

      if (action.type === 'declare_friend' || action.friendCard !== undefined) {
        const card = action.friendCard || action.cardId;
        const hand = game.hands[actor] || [];
        const trump = game.trumpSuit;
        const mighty = game.getMightyCard();
        total++;
        const label = card === 'no_friend' ? '노프렌드'
          : card === mighty ? '마이티'
            : card === 'mighty_joker' ? '조커'
              : card === 'first_trick' ? '초구프렌드'
                : getCardInfo(card).rank === 'A' ? '사이드 A'
                  : getCardInfo(card).rank === 'K' ? '사이드 K'
                    : `기타(${short(card)})`;
        picks[label] = (picks[label] || 0) + 1;

        const bad = [];
        // 마이티는 무늬 보유와 무관하게 정상적인 지목이다. 기루다가 스페이드면
        // 마이티가 ♦A 로 바뀌는 것까지 포함해서 제외한다.
        if (card !== 'no_friend' && card !== 'first_trick'
            && card !== 'mighty_joker' && card !== mighty) {
          const info = getCardInfo(card);
          const mine = hand.filter(c => c !== 'mighty_joker' && getCardInfo(c).suit === info.suit);
          if (hand.includes(card)) bad.push('selfHeld');
          if (mine.length === 0) bad.push('voidSuit');
          if (info.rank === 'K' && !hand.includes(`mighty_${info.suit}_A`)
              && `mighty_${info.suit}_A` !== mighty) bad.push('kingNoAce');
          if (info.rank !== 'A' && info.rank !== 'K' && card !== mighty) bad.push('lowCard');
          if (trump && trump !== 'no_trump' && info.suit === trump && card !== mighty) bad.push('trumpSuit');
        }
        for (const b of bad) flags[b] = (flags[b] || 0) + 1;
        if (bad.length && samples.length < 8 && (!process.env.ONLY || bad.includes(process.env.ONLY))) {
          samples.push({
            round: r, bad: bad.join(','), card: short(card), trump,
            bid: game.currentBid && game.currentBid.points,
            hand: hand.map(short).join(' '),
          });
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

console.log(`\n친구 지목 스캔 — ${rounds}라운드, ${strategy} · 지목 ${total}건${errors ? ` (errors ${errors})` : ''}`);
console.log('\n  지목 분포:');
for (const [k, v] of Object.entries(picks).sort((a, b) => b[1] - a[1])) {
  console.log(`    ${String(v).padStart(4)}회 (${(v / Math.max(1, total) * 100).toFixed(0)}%)  ${k}`);
}
const f = Object.entries(flags).sort((a, b) => b[1] - a[1]);
console.log(f.length ? '\n  이상 유형:' : '\n  이상 유형 없음');
for (const [k, v] of f) console.log(`    ${String(v).padStart(4)}회  ${k}`);
for (const s of samples) {
  console.log(`\n  [R${s.round}] ${s.bad} · 지목 ${s.card} · 기루다 ${s.trump} · 공약 ${s.bid}`);
  console.log(`    손패: ${s.hand}`);
}
