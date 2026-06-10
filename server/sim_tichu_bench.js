'use strict';

/**
 * Headless Tichu self-play bench.
 *
 * Drives full Tichu rounds with per-seat strategies, measuring per-strategy
 * decision-time distribution (avg/p95/max + over-budget count) and team
 * strength (rounds won / avg margin). Used to check that lowering the winrate
 * search time budget cuts the worst-case event-loop stall without tanking
 * bot strength.
 *
 * Usage: node sim_tichu_bench.js [rounds] [--seats s0,s1,s2,s3]
 *   seats: per-player strategy (teamA = seats 0,2; teamB = seats 1,3)
 *   default: all winrate.
 */

const { performance } = require('perf_hooks');
const TichuGame = require('./game/TichuGame');
const { decideBotAction } = require('./game/BotPlayer');

function parseArgs() {
  const args = process.argv.slice(2);
  let rounds = 40;
  let warmup = 0;
  let seats = ['winrate', 'winrate', 'winrate', 'winrate'];
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--seats') {
      seats = (args[++i] || '').split(',').map((s) => s.trim());
      if (seats.length !== 4) { console.error('--seats needs 4'); process.exit(1); }
    } else if (args[i] === '--warmup') {
      warmup = Number(args[++i]) || 0;
    } else if (!Number.isNaN(Number(args[i]))) {
      rounds = Number(args[i]);
    }
  }
  return { rounds, seats, warmup };
}

function pendingActors(game) {
  const s = game.state;
  if (s === 'large_tichu_phase' || s === 'card_exchange') return game.playerIds.slice();
  if (game.needsToCallRank) return [game.needsToCallRank];
  if (game.dragonPending) return [game.dragonDecider];
  return [game.currentPlayer ? [game.currentPlayer] : []].flat();
}

function pct(sortedArr, p) {
  if (sortedArr.length === 0) return 0;
  const idx = Math.min(sortedArr.length - 1, Math.floor((p / 100) * sortedArr.length));
  return sortedArr[idx];
}

function main() {
  const { rounds, seats, warmup } = parseArgs();
  const playerIds = ['p0', 'p1', 'p2', 'p3'];
  const playerNames = { p0: 'p0', p1: 'p1', p2: 'p2', p3: 'p3' };
  const stratOf = {};
  playerIds.forEach((pid, i) => { stratOf[pid] = seats[i]; });

  console.log(`\nTichu bench: ${rounds} rounds. Seats: ${seats.join(',')}`);

  // Decision timing per strategy.
  const times = {};
  for (const s of new Set(seats)) times[s] = [];
  let teamAwins = 0, teamBwins = 0, marginSum = 0, completed = 0, stuck = 0;

  for (let r = 0; r < rounds; r++) {
    const game = new TichuGame(playerIds, playerNames);
    game.start();
    let steps = 0;
    const MAX = 4000;
    while (game.state !== 'round_end' && game.state !== 'game_end' && steps < MAX) {
      let progressed = false;
      for (const actor of pendingActors(game)) {
        if (!actor) continue;
        const t0 = performance.now();
        let action = decideBotAction(game, actor, stratOf[actor]);
        const dt = performance.now() - t0;
        // Skip warmup rounds from timing so JIT-cold outliers (absent in a
        // long-running server) don't masquerade as steady-state spikes.
        if (r >= warmup && stratOf[actor] && times[stratOf[actor]]) times[stratOf[actor]].push(dt);
        if (!action) action = game.getAutoTimeoutAction(actor);
        if (!action) continue;
        const res = game.handleAction(actor, action);
        if (res && res.success) { progressed = true; }
        else {
          const fb = game.getAutoTimeoutAction(actor);
          if (fb) { const r2 = game.handleAction(actor, fb); if (r2 && r2.success) progressed = true; }
        }
      }
      steps++;
      if (!progressed) { stuck++; break; }
    }
    if (game.state === 'round_end' || game.state === 'game_end') {
      completed++;
      const a = game.totalScores.teamA || 0;
      const b = game.totalScores.teamB || 0;
      if (a > b) teamAwins++; else if (b > a) teamBwins++;
      marginSum += (a - b);
    }
  }

  console.log(`\nCompleted ${completed}/${rounds} rounds (${stuck} stuck).`);
  console.log('\n=== Decision time per strategy ===');
  console.log('strategy      decisions    avg ms    p95 ms    max ms   >50ms   >100ms');
  for (const s of Object.keys(times)) {
    const arr = times[s].slice().sort((x, y) => x - y);
    const n = arr.length;
    const avg = n ? (arr.reduce((x, y) => x + y, 0) / n) : 0;
    const over50 = arr.filter((x) => x > 50).length;
    const over100 = arr.filter((x) => x > 100).length;
    console.log(`${s.padEnd(12)} ${String(n).padStart(9)} ${avg.toFixed(2).padStart(9)} ${pct(arr, 95).toFixed(2).padStart(9)} ${(arr[n - 1] || 0).toFixed(2).padStart(9)} ${String(over50).padStart(7)} ${String(over100).padStart(8)}`);
  }
  console.log('\n=== Team strength (teamA = seats 0,2 / teamB = seats 1,3) ===');
  console.log(`teamA wins: ${teamAwins}  teamB wins: ${teamBwins}  avg margin (A-B): ${(marginSum / Math.max(completed, 1)).toFixed(1)}`);
}

main();
