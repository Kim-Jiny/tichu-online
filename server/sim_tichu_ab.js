'use strict';

/**
 * Paired A/B for Tichu bots: BotPlayer.js (new) vs BotPlayer_old.js (baseline).
 *
 * Each deal is played twice with the same seed, swapping which bot sits on
 * which team, so deck luck cancels. Reports mean round-score margin
 * (new minus old) with a standard error.
 *
 * Baseline: git show <ref>:server/game/BotPlayer.js > game/BotPlayer_old.js (untracked).
 *
 * Usage: node sim_tichu_ab.js [deals=40] [--seed N] [--old path]
 * Env flags (BOT_ACE, BOT_SCALE...) apply to the NEW bot only via NEW_ENV,
 * e.g. NEW_ENV="BOT_ACE=0" — they're toggled around each new-bot decision.
 */

const path = require('path');
const TichuGame = require('./game/TichuGame');
const NewBot = require('./game/BotPlayer');

function parse() {
  const a = process.argv.slice(2);
  let deals = 40, seed = 1, old = './game/BotPlayer_old';
  for (let i = 0; i < a.length; i++) {
    if (a[i] === '--seed') seed = Number(a[++i]);
    else if (a[i] === '--old') old = a[++i];
    else if (!Number.isNaN(Number(a[i]))) deals = Number(a[i]);
  }
  return { deals, seed, old };
}

function mulberry(seed) {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6D2B79F5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function pendingActors(game) {
  const s = game.state;
  if (s === 'large_tichu_phase' || s === 'card_exchange') return game.playerIds.slice();
  if (game.needsToCallRank) return [game.needsToCallRank];
  if (game.dragonPending) return [game.dragonDecider];
  return game.currentPlayer ? [game.currentPlayer] : [];
}

function parseEnv(str) {
  const out = {};
  for (const kv of (str || '').split(/\s+/).filter(Boolean)) {
    const [k, v] = kv.split('=');
    out[k] = v;
  }
  return out;
}

function playRound(seed, newSeats, OldBot, newEnv) {
  const rnd = mulberry(seed);
  const realRandom = Math.random;
  Math.random = rnd;
  try {
    const ids = ['p0', 'p1', 'p2', 'p3'];
    const names = { p0: 'p0', p1: 'p1', p2: 'p2', p3: 'p3' };
    const game = new TichuGame(ids, names);
    game.start();
    let steps = 0;
    while (game.state !== 'round_end' && game.state !== 'game_end' && steps < 4000) {
      let progressed = false;
      for (const actor of pendingActors(game)) {
        const isNew = newSeats.has(actor);
        let action;
        if (isNew) {
          const saved = {};
          for (const k of Object.keys(newEnv)) { saved[k] = process.env[k]; process.env[k] = newEnv[k]; }
          try { action = NewBot.decideBotAction(game, actor, 'winrate'); }
          finally { for (const k of Object.keys(saved)) { if (saved[k] === undefined) delete process.env[k]; else process.env[k] = saved[k]; } }
        } else {
          action = OldBot.decideBotAction(game, actor, 'winrate');
        }
        if (!action) action = game.getAutoTimeoutAction(actor);
        if (!action) continue;
        const res = game.handleAction(actor, action);
        if (res && res.success) progressed = true;
        else {
          const fb = game.getAutoTimeoutAction(actor);
          if (fb) { const r2 = game.handleAction(actor, fb); if (r2 && r2.success) progressed = true; }
        }
      }
      steps++;
      if (!progressed) return null;
    }
    if (game.state !== 'round_end' && game.state !== 'game_end') return null;
    return (game.totalScores.teamA || 0) - (game.totalScores.teamB || 0);
  } finally {
    Math.random = realRandom;
  }
}

function main() {
  const { deals, seed, old } = parse();
  const OldBot = require(path.resolve(__dirname, old));
  const newEnv = parseEnv(process.env.NEW_ENV);
  const diffs = [];
  for (let d = 0; d < deals; d++) {
    const s = seed * 100003 + d;
    // new on team A (p0,p2) -> margin = A-B ; new on team B (p1,p3) -> margin = B-A
    const a = playRound(s, new Set(['p0', 'p2']), OldBot, newEnv);
    const b = playRound(s, new Set(['p1', 'p3']), OldBot, newEnv);
    if (a === null || b === null) continue;
    diffs.push((a + -b) / 2);
  }
  const n = diffs.length;
  const mean = diffs.reduce((x, y) => x + y, 0) / Math.max(n, 1);
  const sd = Math.sqrt(diffs.reduce((x, y) => x + (y - mean) ** 2, 0) / Math.max(n - 1, 1));
  const se = sd / Math.sqrt(Math.max(n, 1));
  console.log(`NEW_ENV=${process.env.NEW_ENV || '(none)'} deals=${n} new-old margin/round = ${mean.toFixed(1)} ± ${se.toFixed(1)} (SE)`);
}

main();
