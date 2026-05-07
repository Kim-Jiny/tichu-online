'use strict';

/**
 * Headless Mighty simulator with per-seat strategies.
 *
 * Spins up 5 bot players, runs N rounds, and reports per-strategy
 * declarer success rate, average per-round score, and avg decision time.
 * Used to benchmark bot tuning and compare strategy variants
 * (heuristic vs oracle vs mixoracle).
 *
 * Usage:
 *   node sim_mighty.js [rounds] [--strategies <list>]
 *
 *   --strategies takes 5 comma-separated strategy names, one per seat:
 *     node sim_mighty.js 200 --strategies heuristic,pimc_play,heuristic,heuristic,heuristic
 *
 *   With --rotate, strategies cycle around seats round-by-round so seat
 *   bias washes out.
 *
 * Default: all seats use heuristic.
 */

const MightyGame = require('./game/mighty/MightyGame');
const { decideMightyBotAction } = require('./game/mighty/MightyBot');
const { VALID_BOT_STRATEGIES: VALID_STRATEGIES } = require('./game/BotPlayer');

function parseArgs() {
  const args = process.argv.slice(2);
  let rounds = 200;
  let strategies = ['heuristic', 'heuristic', 'heuristic', 'heuristic', 'heuristic'];
  let rotate = false;
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--strategies') {
      const list = (args[++i] || '').split(',').map(s => s.trim());
      if (list.length !== 5) {
        console.error('--strategies needs exactly 5 comma-separated names');
        process.exit(1);
      }
      for (const s of list) {
        if (!VALID_STRATEGIES.includes(s)) {
          console.error(`unknown strategy: ${s}. Valid: ${VALID_STRATEGIES.join(', ')}`);
          process.exit(1);
        }
      }
      strategies = list;
    } else if (a === '--rotate') {
      rotate = true;
    } else if (/^\d+$/.test(a)) {
      rounds = parseInt(a, 10);
    }
  }
  return { rounds, strategies, rotate };
}

function advanceUntilStable(game) {
  let safety = 1000;
  while (safety-- > 0) {
    if (game.state === 'trick_end') {
      game.advanceAfterTrickEnd();
      continue;
    }
    break;
  }
}

function runGame(playerIds, seatStrategy, decisionStats) {
  const playerNames = {};
  for (const pid of playerIds) playerNames[pid] = pid;
  const game = new MightyGame(playerIds, playerNames, { targetScore: 50 });
  game.start();

  const safety = { steps: 0, max: 8000 };
  while (game.state !== 'round_end' && game.state !== 'game_end') {
    advanceUntilStable(game);
    if (game.state === 'round_end' || game.state === 'game_end') break;
    const actor = game.getPendingActor();
    if (!actor) break;
    const strategy = seatStrategy[actor];
    const t0 = Date.now();
    const action = decideMightyBotAction(game, actor, strategy);
    const dt = Date.now() - t0;
    if (decisionStats) {
      decisionStats[strategy].count++;
      decisionStats[strategy].totalMs += dt;
    }
    if (!action) break;
    const result = game.handleAction(actor, action);
    if (!result || result.success === false) {
      const fb = game.getAutoTimeoutAction(actor);
      if (fb) game.handleAction(actor, fb);
      else return { error: result && result.messageKey, game };
    }
    if (++safety.steps >= safety.max) {
      return { error: 'safety_limit', game };
    }
  }
  advanceUntilStable(game);
  return { game };
}

function main() {
  const { rounds, strategies, rotate } = parseArgs();
  const playerIds = ['p0', 'p1', 'p2', 'p3', 'p4'];

  console.log(`\nSimulating ${rounds} rounds. Seats: ${strategies.join(',')}${rotate ? '  (rotating)' : ''}`);

  const decisionStats = {};
  for (const s of VALID_STRATEGIES) decisionStats[s] = { count: 0, totalMs: 0 };

  // Per-strategy outcome buckets — declarer success / avg score per round
  // played at any seat with that strategy.
  const stratStats = {};
  for (const s of VALID_STRATEGIES) {
    stratStats[s] = {
      declarerCount: 0,
      declarerSuccess: 0,
      roundsPlayed: 0,
      totalScore: 0,
    };
  }
  const passouts = { count: 0 };

  for (let r = 0; r < rounds; r++) {
    // Build seat → strategy mapping (rotate if requested)
    const seatStrategy = {};
    for (let i = 0; i < playerIds.length; i++) {
      const stratIdx = rotate ? (i + r) % strategies.length : i;
      seatStrategy[playerIds[i]] = strategies[stratIdx];
    }

    const { game, error } = runGame(playerIds, seatStrategy, decisionStats);
    if (error) continue;

    if (!game.declarer || !game.roundResult) {
      passouts.count++;
      continue;
    }

    const declarerStrat = seatStrategy[game.declarer];
    stratStats[declarerStrat].declarerCount++;
    if (game.roundResult.success) stratStats[declarerStrat].declarerSuccess++;

    for (const pid of playerIds) {
      const s = seatStrategy[pid];
      stratStats[s].roundsPlayed++;
      stratStats[s].totalScore += (game.scores[pid] || 0);
    }
  }

  // Report
  console.log('\n=== Per-strategy results ===');
  console.log('Strategy          decl rounds  decl success    rounds played   avg score / round    avg ms / decision');
  for (const s of VALID_STRATEGIES) {
    const st = stratStats[s];
    if (st.declarerCount === 0 && st.roundsPlayed === 0) continue;
    const declRate = st.declarerCount > 0
      ? `${st.declarerSuccess}/${st.declarerCount}  (${(st.declarerSuccess / st.declarerCount * 100).toFixed(1)}%)`
      : '—';
    const avgScore = st.roundsPlayed > 0 ? (st.totalScore / st.roundsPlayed).toFixed(2) : '—';
    const ds = decisionStats[s];
    const avgMs = ds.count > 0 ? (ds.totalMs / ds.count).toFixed(1) : '—';
    console.log(
      `  ${s.padEnd(14)}  ${String(st.declarerCount).padStart(8)}     ${declRate.padStart(14)}    ${String(st.roundsPlayed).padStart(11)}    ${avgScore.padStart(15)}     ${avgMs.padStart(15)}`
    );
  }
  console.log(`\nPassouts: ${passouts.count} / ${rounds} (${(passouts.count / rounds * 100).toFixed(1)}%)`);
}

main();
