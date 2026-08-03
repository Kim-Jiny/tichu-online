'use strict';
/**
 * 야당이 이미 가져간 트릭에 점수 카드를 갖다 바치는 순간을 잡는다.
 *
 * 잡는 조건:
 *   - 봇이 낸 카드가 점수 카드(10/J/Q/K/A)이고 마이티/조커가 아니다
 *   - 그 카드로는 현재 트릭 승자를 못 넘는다 (= 이기려는 수가 아니라 버리는 수)
 *   - 낼 때 이미 트릭 승자가 상대 팀이었다
 *   - 점수 0짜리 합법 카드가 손에 있었다
 *   - 그리고 실제로 그 트릭을 상대 팀이 가져갔다 (뒤에서 우리 팀이 뒤집었으면 제외)
 *
 *   node sim_mighty_point_donation.js [rounds] [seedBase] [strategy]
 */
const MightyGame = require('./game/mighty/MightyGame');
const MB = require('./game/mighty/MightyBot');
const { decideMightyBotAction } = MB;
const { getCardInfo } = require('./game/mighty/MightyDeck');

const IDS = ['p0', 'p1', 'p2', 'p3', 'p4'];
const NAMES = {}; IDS.forEach((p) => (NAMES[p] = p));

const rounds = parseInt(process.argv[2] || '200', 10);
const base = parseInt(process.argv[3] || '5', 10);
const strategy = process.argv[4] || 'mixoracle';

const isPoint = (cardId) => {
  if (!cardId || cardId === 'mighty_joker') return false;
  const info = getCardInfo(cardId);
  return !!(info && info.point);
};

let dumps = 0, donations = 0, errors = 0;
const samples = [];
const bySource = {};
const byRole = {};
let lastPath = null, lastRule = null;
global.__mightyPathTrace = (p) => { lastPath = p; if (p !== 'rules') lastRule = null; };
global.__mightyRuleTrace = (n) => { lastRule = n; };

for (let r = 0; r < rounds; r++) {
  const game = new MightyGame(IDS, NAMES, { seed: base + r });
  let pending = [];
  const resolve = () => {
    if (pending.length === 0) return;
    const trick = game.tricks[game.tricks.length - 1];
    for (const ev of pending) {
      const winner = trick && trick.winner;
      // 상대 팀이 실제로 가져갔을 때만 "갖다 바침"으로 센다.
      if (winner && MB.isGovernmentSelf(game, winner) !== ev.gov) {
        donations++;
        bySource[ev.src] = (bySource[ev.src] || 0) + 1;
        byRole[ev.role] = (byRole[ev.role] || 0) + 1;
        if (samples.length < 6 && (!process.env.ROLE || ev.role === process.env.ROLE)) samples.push(ev);
      }
    }
    pending = [];
  };

  try {
    game.start();
    let guard = 0;
    while (game.state !== 'game_end' && guard++ < 4000) {
      if (game.state === 'round_end') break;
      if (game.state === 'trick_end') { resolve(); game.advanceAfterTrickEnd(); continue; }
      const actor = game.currentPlayer;
      if (!actor) break;
      const legal = game._getLegalCards(actor) || [];
      const action = decideMightyBotAction(game, actor, strategy);
      if (!action) break;

      if (action.type === 'play_card' && game.currentTrick.length > 0
          && isPoint(action.cardId) && action.cardId !== game.getMightyCard()
          && !MB.canBeatCurrentWinner(game, action.cardId)) {
        dumps++;
        const winnerNow = MB.getCurrentTrickWinner(game);
        const gov = MB.isGovernmentSelf(game, actor);
        // 봇 자신이 "적이 가져간다"고 믿는 자리만 센다. 프렌드 공개 전 야당은
        // 규칙상 주공 말고는 전부 우리편으로 보므로(정보 게이트), 거기에
        // 점수를 미는 건 실수가 아니다 — 그건 빼야 진짜 실수만 남는다.
        const winnerIsGov = MB.isGovernment(game, winnerNow);
        const believesAlly = gov
          ? MB.isGovernmentSelf(game, winnerNow)
          : (game.friendRevealed ? !winnerIsGov : winnerNow !== game.declarer);
        const cheap = legal.filter((cd) => !isPoint(cd) && cd !== 'mighty_joker');
        if (!believesAlly && cheap.length > 0) {
          pending.push({
            // 결정적으로 다시 세울 수 있게 국면을 통째로 떠 둔다 (DUMP=파일).
            snapshot: {
              actor,
              trumpSuit: game.trumpSuit,
              declarer: game.declarer,
              partner: game.partner,
              friendCard: game.friendCard,
              friendRevealed: game.friendRevealed,
              currentBid: game.currentBid,
              hands: JSON.parse(JSON.stringify(game.hands)),
              currentTrick: JSON.parse(JSON.stringify(game.currentTrick)),
              tricks: JSON.parse(JSON.stringify(game.tricks)),
              played: action.cardId,
            },
            gov,
            src: lastPath === 'rules' ? `rules:${lastRule}` : String(lastPath),
            round: r,
            trick: game.tricks.length + 1,
            trump: game.trumpSuit,
            role: actor === game.declarer ? '주공'
              : MB.isFriend(game, actor) ? '프렌드' : '야당',
            revealed: game.friendRevealed,
            cur: game.currentTrick.map(p => `${p.pid}:${p.cardId.replace('mighty_', '')}`).join(' '),
            played: action.cardId.replace('mighty_', ''),
            cheap: cheap.map(x => x.replace('mighty_', '')).join(' '),
            hand: (game.hands[actor] || []).map(x => x.replace('mighty_', '')).join(' '),
          });
        }
      }

      const res = game.handleAction(actor, action);
      if (!res || !res.success) break;
    }
    resolve();
  } catch (e) {
    errors++;
    if (errors <= 2) console.error('round error:', e.message);
  }
}

console.log(`\n점수 갖다바침 스캔 — ${rounds}라운드, ${strategy}`);
console.log(`  못 이기는 자리에 점수 카드를 낸 횟수: ${dumps}`);
console.log(`  그중 상대가 가져갈 트릭인데 값싼 대안이 있었던 경우: ${donations}`
  + (dumps ? ` (${((donations / dumps) * 100).toFixed(0)}%)` : ''));
if (errors) console.log(`  errors: ${errors}`);
const roles = Object.entries(byRole).sort((a, b) => b[1] - a[1]);
if (roles.length) {
  console.log('\n  역할별:');
  for (const [k, v] of roles) console.log(`    ${String(v).padStart(3)}회  ${k}`);
}
const srcs = Object.entries(bySource).sort((a, b) => b[1] - a[1]);
if (srcs.length) {
  console.log('\n  결정 경로:');
  for (const [k, v] of srcs) console.log(`    ${String(v).padStart(3)}회  ${k}`);
}
for (const s of samples) {
  console.log(`\n  [R${s.round} 트릭${s.trick}] ${s.role}${s.revealed ? '' : '(미공개)'} · 기루다 ${s.trump}`);
  console.log(`    트릭: ${s.cur}  → 낸 카드 ${s.played}  (값싼 대안: ${s.cheap})`);
  console.log(`    손패: ${s.hand}`);
}
if (process.env.DUMP) {
  require('fs').writeFileSync(process.env.DUMP,
    JSON.stringify(samples.map(s => s.snapshot), null, 2));
  console.log(`\n  국면 스냅샷 ${samples.length}건 → ${process.env.DUMP}`);
}
