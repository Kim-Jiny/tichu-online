'use strict';
/**
 * Bot-vs-bot smoke sim for SkullBiddingGame — plays out full games with
 * 3-6 bots and checks every one terminates (no stuck phase, no infinite
 * loop) within a sane number of actions. Not a balance/strategy check,
 * just "does the state machine ever get stuck".
 *
 *   node sim_skull_bidding.js [rounds]
 */
const SkullBiddingGame = require('./game/skull_bidding/SkullBiddingGame');
const { decideSkullBiddingBotAction } = require('./game/skull_bidding/SkullBiddingBot');

const GAMES = parseInt(process.argv[2], 10) || 500;
const MAX_ACTIONS_PER_GAME = 2000; // generous — a real game needs a tiny fraction of this

let completed = 0;
let stuck = 0;
const playerCountTally = {};
const winnerByReason = { instant: 0, target: 0, lastStanding: 0 };

for (let g = 0; g < GAMES; g++) {
  const playerCount = 3 + (g % 4); // cycles 3,4,5,6
  const ids = Array.from({ length: playerCount }, (_, i) => `p${i}`);
  const names = {};
  ids.forEach((p) => (names[p] = p));
  const game = new SkullBiddingGame(ids, names);
  game.start();

  let actions = 0;
  let ok = true;
  while (game.state !== 'game_end') {
    actions++;
    if (actions > MAX_ACTIONS_PER_GAME) { ok = false; break; }

    const actor = game.currentPlayer;
    if (!actor) { ok = false; break; }
    const action = decideSkullBiddingBotAction(game, actor);
    if (!action) { ok = false; break; }
    const result = game.handleAction(actor, action);
    if (!result.success) {
      console.error(`게임 ${g} action 실패:`, JSON.stringify(action), result);
      ok = false;
      break;
    }
  }

  if (ok && game.state === 'game_end') {
    completed++;
    playerCountTally[playerCount] = (playerCountTally[playerCount] || 0) + 1;
    const lastHistory = game.roundHistory[game.roundHistory.length - 1];
    const activeLeft = ids.filter((pid) => !game.eliminated[pid]).length;
    if (lastHistory && lastHistory.result === 'success'
        && lastHistory.bid === lastHistory.tableTotal) {
      winnerByReason.instant++;
    } else if (activeLeft <= 1) {
      winnerByReason.lastStanding++;
    } else {
      winnerByReason.target++;
    }
  } else {
    stuck++;
    console.error(`게임 ${g} (인원 ${playerCount}) 미종료 — state=${game.state} actions=${actions}`);
  }
}

console.log(`${GAMES}게임 중 정상 종료 ${completed}, 막힘 ${stuck}`);
console.log('인원별 완료 수:', playerCountTally);
console.log('승리 사유:', winnerByReason);
process.exit(stuck === 0 ? 0 : 1);
