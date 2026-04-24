'use strict';

/**
 * Headless Mighty simulator — spins up 5 bot players, runs N rounds, and
 * reports declarer success rate, average scores per seat, and how often
 * each friend-call type is chosen. Used ad-hoc to benchmark bot tuning
 * changes; not part of production.
 *
 * Usage: node sim_mighty.js [rounds]   (default 500)
 */

const MightyGame = require('./game/mighty/MightyGame');
const MightyBot = require('./game/mighty/MightyBot');
const { decideMightyBotAction } = MightyBot;

// Hook pickFriendCard via the simulator-only globalThis.__mightySimHook
// observer exposed from MightyBot.js. Capture when the declarer picks a
// suit-A for a suit they're void in.
const voidPickLog = { count: 0, samples: [] };
globalThis.__mightySimHook = (hand, pick, topCands) => {
  if (typeof pick !== 'string' || !pick.startsWith('mighty_') || !pick.endsWith('_A')) return;
  if (pick === 'mighty_joker') return;
  const suit = pick.split('_')[1];
  const holds = hand.some(cid => {
    if (cid === 'mighty_joker') return false;
    const p = cid.replace('mighty_', '').split('_');
    return p[0] === suit;
  });
  if (!holds) {
    voidPickLog.count++;
    if (voidPickLog.samples.length < 3) {
      voidPickLog.samples.push({ pick, hand: hand.slice(), topCands });
    }
  }
};

function advanceUntilStable(game) {
  // Mighty's trick resolution sets state='trick_end' and requires an
  // external nudge to move on. Run that implicit step automatically.
  let safety = 1000;
  while (safety-- > 0) {
    if (game.state === 'trick_end') {
      game.advanceAfterTrickEnd();
      continue;
    }
    break;
  }
}

function runGame(playerIds) {
  const playerNames = {};
  for (const pid of playerIds) playerNames[pid] = pid;
  const game = new MightyGame(playerIds, playerNames, { targetScore: 50 });
  game.start();

  const safety = { steps: 0, max: 8000 };
  while (game.state !== 'round_end' && game.state !== 'game_end') {
    advanceUntilStable(game);
    if (game.state === 'round_end' || game.state === 'game_end') break;
    // Find the player expected to act.
    const actor = game.currentPlayer
      || (game.state === 'kill_select' || game.state === 'kitty_exchange' ? game.declarer : null);
    if (!actor) {
      // All passed redeal happens within _advanceBidding; loop will continue.
      break;
    }
    const action = decideMightyBotAction(game, actor);
    if (!action) break;
    const result = game.handleAction(actor, action);
    if (!result || result.success === false) {
      // Shouldn't happen; bail to avoid infinite loop.
      return { error: result && result.messageKey, game };
    }
    if (++safety.steps >= safety.max) {
      return { error: 'safety_limit', game };
    }
  }
  advanceUntilStable(game);
  return { game };
}

function main() {
  const rounds = parseInt(process.argv[2] || '500', 10);
  const playerIds = ['p0', 'p1', 'p2', 'p3', 'p4'];

  const stats = {
    rounds: 0,
    passouts: 0,
    declared: 0,
    declSuccess: 0,
    declFail: 0,
    friendCalls: {},
    declarerSeat: { p0: 0, p1: 0, p2: 0, p3: 0, p4: 0 },
    seatSuccess: { p0: { s: 0, f: 0 }, p1: { s: 0, f: 0 }, p2: { s: 0, f: 0 }, p3: { s: 0, f: 0 }, p4: { s: 0, f: 0 } },
    // Success rate conditioned on friend-call type.
    friendCallResult: {},
    totalScore: { p0: 0, p1: 0, p2: 0, p3: 0, p4: 0 },
    errors: 0,
  };

  for (let r = 0; r < rounds; r++) {
    const { game, error } = runGame(playerIds);
    stats.rounds++;
    if (error) {
      stats.errors++;
      continue;
    }
    // Detect passout (no declarer this round)
    if (!game.declarer || !game.roundResult) {
      stats.passouts++;
      continue;
    }
    stats.declared++;
    stats.declarerSeat[game.declarer]++;
    const friendCall = game.friendCard || 'unknown';
    stats.friendCalls[friendCall] = (stats.friendCalls[friendCall] || 0) + 1;
    const success = game.roundResult && game.roundResult.success;
    if (success) {
      stats.declSuccess++;
      stats.seatSuccess[game.declarer].s++;
    } else {
      stats.declFail++;
      stats.seatSuccess[game.declarer].f++;
    }
    // Friend call → result
    if (!stats.friendCallResult[friendCall]) stats.friendCallResult[friendCall] = { s: 0, f: 0 };
    if (success) stats.friendCallResult[friendCall].s++;
    else stats.friendCallResult[friendCall].f++;
    for (const pid of playerIds) {
      stats.totalScore[pid] += (game.scores[pid] || 0);
    }
  }

  console.log('\n=== Mighty bot sim ===');
  console.log(`Rounds: ${stats.rounds} (passouts ${stats.passouts}, declared ${stats.declared}, errors ${stats.errors})`);
  const declRate = stats.declared ? (stats.declSuccess / stats.declared * 100).toFixed(1) : '—';
  console.log(`Declarer success: ${stats.declSuccess}/${stats.declared}  (${declRate}%)`);
  console.log('\nFriend-call breakdown:');
  const fcKeys = Object.keys(stats.friendCallResult).sort();
  for (const k of fcKeys) {
    const r = stats.friendCallResult[k];
    const total = r.s + r.f;
    const pct = total ? (r.s / total * 100).toFixed(1) : '—';
    const share = stats.declared ? ((total / stats.declared) * 100).toFixed(1) : '—';
    console.log(`  ${k.padEnd(22)} picks=${String(total).padStart(4)} (${share.padStart(4)}% of declared)  success=${pct}%`);
  }
  console.log(`Void-suit friend A picks (observed at decision time): ${voidPickLog.count}`);
  for (const s of voidPickLog.samples) {
    console.log(`  pick=${s.pick}  hand=[${s.hand.join(',')}]`);
    console.log(`    top candidates: ${s.topCands.map(c => `${c.cardId}(${c.score})`).join(', ')}`);
  }
  console.log('\nAvg score per seat:');
  for (const pid of playerIds) {
    console.log(`  ${pid}: ${(stats.totalScore[pid] / stats.rounds).toFixed(2)}`);
  }
}

main();
