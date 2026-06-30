'use strict';
// Head-to-head Love Letter bot bench: card-counting Guard guess (smart) vs the
// old uniform-random guess (dumb). Drives 2-player games the way the server
// does (currentPlayer / effect_resolve owner; resolved effects auto-ack), then
// tallies affection tokens (= round wins) per strategy. Seats alternate per game
// so first-player / seat bias washes out.

const LL = require('./game/love_letter/LoveLetterGame');
const { decideLLBotAction } = require('./game/love_letter/LoveLetterBot');

const GAMES = parseInt(process.argv[2] || '4000', 10);
const ids = ['p0', 'p1'];
const names = { p0: 'p0', p1: 'p1' };

// opts per seat: smart = card counting, dumb = random guess
function run(smartSeat) {
  const optsBySeat = {
    p0: { randomGuess: smartSeat !== 0 },
    p1: { randomGuess: smartSeat !== 1 },
  };
  const g = new LL(ids, names);
  g.start();
  let steps = 0;
  while (g.state !== 'game_end' && steps++ < 20000) {
    if (g.state === 'round_end') {
      const r = g.handleAction(g.currentPlayer, { type: 'next_round' });
      if (!r || r.success === false) break;
      continue;
    }
    const actor = g.currentPlayer;
    if (!actor) break;
    let action = decideLLBotAction(g, actor, optsBySeat[actor]);
    if (!action) action = g.getAutoTimeoutAction(actor);
    if (!action) break;
    const res = g.handleAction(actor, action);
    if (!res || res.success === false) {
      const fb = g.getAutoTimeoutAction(actor);
      if (fb) { const r2 = g.handleAction(actor, fb); if (r2 && r2.success) continue; }
      break;
    }
  }
  // Attribute final tokens to strategy.
  let smartTok = 0, dumbTok = 0;
  for (const pid of ids) {
    const seat = pid === 'p0' ? 0 : 1;
    if (seat === smartSeat) smartTok += g.tokens[pid] || 0;
    else dumbTok += g.tokens[pid] || 0;
  }
  return { smartTok, dumbTok, smartWon: smartTok > dumbTok };
}

let smartTokens = 0, dumbTokens = 0, smartGames = 0, dumbGames = 0, ties = 0;
for (let i = 0; i < GAMES; i++) {
  const { smartTok, dumbTok, smartWon } = run(i % 2); // alternate which seat is smart
  smartTokens += smartTok; dumbTokens += dumbTok;
  if (smartTok === dumbTok) ties++;
  else if (smartWon) smartGames++; else dumbGames++;
}

const totalTok = smartTokens + dumbTokens;
console.log(`\nLove Letter bot bench — ${GAMES} games (2p head-to-head)`);
console.log(`tokens (round wins):  smart=${smartTokens}  dumb=${dumbTokens}  smart share=${(100 * smartTokens / totalTok).toFixed(1)}%`);
console.log(`game wins:            smart=${smartGames}  dumb=${dumbGames}  ties=${ties}  smart winrate=${(100 * smartGames / (smartGames + dumbGames)).toFixed(1)}%`);
