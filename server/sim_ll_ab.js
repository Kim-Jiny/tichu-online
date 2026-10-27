'use strict';

/**
 * Paired A/B for the Love Letter bot: a new variant against the baseline, at the
 * same table, seats rotated every game.
 *
 *   mode=mc    the Monte-Carlo search bot (strat 'mc')       [default]
 *   mode=heur  the knowledge-aware rule-based bot alone
 *
 * The baseline is a copy of the previous rule-based bot kept next to it, untracked:
 *   git show <ref>:server/game/love_letter/LoveLetterBot.js > game/love_letter/LoveLetterBot_base.js
 *
 * Usage: node sim_ll_ab.js [games=1000] [players=2] [mode=mc|heur] [key=value ...]
 *   key=value overrides the search tunables (samples, deadlineMs, margin).
 *
 * A game is won by whoever reaches the token target first; a shared win counts
 * 1/winners. "per seat" divides by the number of seats of that kind, so an even
 * match shows the same number for both kinds (1/players).
 */

const LL = require('./game/love_letter/LoveLetterGame');
const fresh = require('./game/love_letter/LoveLetterBot');
const base = require('./game/love_letter/LoveLetterBot_base');

const args = process.argv.slice(2);
const kv = {};
const pos = [];
for (const a of args) {
  const m = a.match(/^(\w+)=(.+)$/);
  if (m) kv[m[1]] = m[2]; else pos.push(a);
}
const games = parseInt(pos[0], 10) || 1000;
const playerCount = parseInt(pos[1], 10) || 2;
const mode = kv.mode || 'mc';
delete kv.mode;
for (const [k, v] of Object.entries(kv)) {
  if (!(k in fresh.MC)) { console.error(`unknown tunable ${k}`); process.exit(2); }
  fresh.MC[k] = Number(v);
}

const ids = Array.from({ length: playerCount }, (_, i) => `p${i}`);
const names = Object.fromEntries(ids.map((p) => [p, p]));
const freshSeats = Math.max(1, Math.floor(playerCount / 2));

let ms = 0; let decisions = 0; let slowest = 0;
function act(game, pid, isFresh) {
  if (!isFresh) return base.decideLLBotAction(game, pid);
  const t = process.hrtime.bigint();
  const a = fresh.decideLLBotAction(game, pid, mode === 'mc' ? 'mc' : {});
  const d = Number(process.hrtime.bigint() - t) / 1e6;
  if (game.state === 'playing' || (game.pendingEffect && !game.pendingEffect.resolved)) {
    ms += d; decisions++; if (d > slowest) slowest = d;
  }
  return a;
}

let freshWins = 0; let baseWins = 0; let freshRounds = 0; let baseRounds = 0; let rounds = 0; let errors = 0;

for (let g = 0; g < games; g++) {
  const offset = g % playerCount;
  const isFresh = {};
  ids.forEach((pid, i) => { isFresh[pid] = ((i + offset) % playerCount) < freshSeats; });
  const game = new LL(ids, names);
  game.start();
  let guard = 20000;
  while (game.state !== 'game_end' && guard-- > 0) {
    if (game.state === 'round_end') { game.handleAction(game.currentPlayer, { type: 'next_round' }); continue; }
    const actor = game.state === 'effect_resolve' ? game.pendingEffect.playerId : game.currentPlayer;
    let a = act(game, actor, isFresh[actor]);
    if (!a) a = game.getAutoTimeoutAction(actor);
    const r = a && game.handleAction(actor, a);
    if (!r || !r.success) {
      const fb = game.getAutoTimeoutAction(actor);
      const r2 = fb && game.handleAction(actor, fb);
      if (!r2 || !r2.success) { errors++; break; }
    }
  }
  if (game.state !== 'game_end') continue;
  const winners = ids.filter((p) => game.tokens[p] >= game.targetTokens);
  for (const w of winners) { if (isFresh[w]) freshWins += 1 / winners.length; else baseWins += 1 / winners.length; }
  for (const pid of ids) { if (isFresh[pid]) freshRounds += game.tokens[pid]; else baseRounds += game.tokens[pid]; }
  rounds += game.round;
}

const n = freshWins + baseWins;
const fs = freshSeats; const bs = playerCount - freshSeats;
console.log(`=== LL A/B: ${mode} vs base, ${playerCount}p, ${games} games, errors=${errors}`);
if (Object.keys(kv).length) console.log('tunables', JSON.stringify(kv));
console.log(`game wins: ${mode} ${freshWins.toFixed(1)} (${(100 * freshWins / n).toFixed(1)}%)  base ${baseWins.toFixed(1)}`);
console.log(`per seat win rate: ${mode} ${(100 * freshWins / games / fs).toFixed(1)}%  base ${(100 * baseWins / games / bs).toFixed(1)}%  (even = ${(100 / playerCount).toFixed(1)}%)`);
const z = (() => { // binomial z for the share of game wins
  const p = fs / playerCount; const sd = Math.sqrt(games * p * (1 - p));
  return (freshWins - games * p) / sd;
})();
console.log(`z vs even split: ${z.toFixed(2)}`);
console.log(`tokens per round, per seat: ${mode} ${(freshRounds / rounds / fs).toFixed(3)}  base ${(baseRounds / rounds / bs).toFixed(3)}`);
console.log(`decision time: avg ${(ms / Math.max(1, decisions)).toFixed(2)}ms  slowest ${slowest.toFixed(1)}ms over ${decisions}`);
