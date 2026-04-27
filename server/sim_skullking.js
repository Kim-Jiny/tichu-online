'use strict';

/**
 * Headless Skull King simulator: spins up N bot players, plays a fixed
 * number of full 10-round games, and reports per-seat avg score, bid
 * accuracy (% of rounds where each seat hit their bid exactly), and
 * average round-end score per round number. Used to benchmark bot
 * tuning; not part of production.
 *
 * Usage: node sim_skullking.js [games] [players]   (default 200 games, 4 players)
 */

const SkullKingGame = require('./game/skull_king/SkullKingGame');
const { decideSKBotAction } = require('./game/skull_king/SkullKingBot');

const games = parseInt(process.argv[2], 10) || 200;
const playerCount = parseInt(process.argv[3], 10) || 4;

const playerIds = Array.from({ length: playerCount }, (_, i) => `p${i}`);
const seatScores = playerIds.map(() => 0);
const seatHits = playerIds.map(() => 0);
const seatRounds = playerIds.map(() => 0);
const bidByRound = Array.from({ length: 10 }, () => ({ hits: 0, total: 0 }));

let totalRoundsPlayed = 0;
let errors = 0;

for (let g = 0; g < games; g++) {
  const game = new SkullKingGame(playerIds, []);
  game.start();

  let safety = 50000;
  while (game.state !== 'game_end' && safety-- > 0) {
    if (game.state === 'bidding') {
      // Have all bots bid simultaneously (server-style allows it).
      let progressed = false;
      for (const pid of playerIds) {
        if (game.bids[pid] === null) {
          const action = decideSKBotAction(game, pid);
          if (!action) continue;
          const r = game.handleAction(pid, action);
          if (r && r.success) progressed = true;
        }
      }
      if (!progressed) { errors++; break; }
    } else if (game.state === 'playing') {
      const pid = game.currentPlayer;
      const action = decideSKBotAction(game, pid);
      if (!action) { errors++; break; }
      const r = game.handleAction(pid, action);
      if (!r || !r.success) { errors++; break; }
    } else if (game.state === 'trick_end') {
      game.advanceAfterTrickEnd();
    } else if (game.state === 'round_end') {
      // Snapshot per-seat round outcomes BEFORE advancing.
      const round = game.round;
      for (let i = 0; i < playerCount; i++) {
        const pid = playerIds[i];
        const bid = game.bids[pid];
        const tricks = game.tricks[pid];
        const hit = bid !== null && bid === tricks;
        seatRounds[i] += 1;
        if (hit) seatHits[i] += 1;
        if (round >= 1 && round <= 10) {
          bidByRound[round - 1].total += 1;
          if (hit) bidByRound[round - 1].hits += 1;
        }
      }
      totalRoundsPlayed += 1;
      game.nextRound();
    } else {
      // Unknown state — bail out.
      errors++;
      break;
    }
  }

  if (game.state === 'game_end') {
    for (let i = 0; i < playerCount; i++) {
      seatScores[i] += game.totalScores[playerIds[i]] || 0;
    }
  }
}

console.log('=== Skull King bot sim ===');
console.log(`Games: ${games}, players: ${playerCount}, errors: ${errors}`);
console.log(`Total rounds played: ${totalRoundsPlayed}`);
console.log();
console.log('Avg final score per seat:');
for (let i = 0; i < playerCount; i++) {
  const avg = seatScores[i] / games;
  console.log(`  p${i}: ${avg.toFixed(1)}`);
}
console.log();
console.log('Bid hit-rate per seat (bid === tricks won):');
for (let i = 0; i < playerCount; i++) {
  const r = seatRounds[i] || 1;
  console.log(`  p${i}: ${seatHits[i]}/${seatRounds[i]} (${((seatHits[i]/r)*100).toFixed(1)}%)`);
}
console.log();
console.log('Hit-rate by round number:');
for (let r = 0; r < 10; r++) {
  const b = bidByRound[r];
  if (b.total === 0) continue;
  console.log(`  R${r + 1}: ${b.hits}/${b.total} (${((b.hits/b.total)*100).toFixed(1)}%)`);
}

// Overall hit rate
const totalHits = seatHits.reduce((s, x) => s + x, 0);
const totalAttempts = seatRounds.reduce((s, x) => s + x, 0);
console.log();
console.log(`Overall hit rate: ${totalHits}/${totalAttempts} (${((totalHits/totalAttempts)*100).toFixed(2)}%)`);
