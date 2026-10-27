'use strict';

/**
 * Paired A/B for the Skull King bot: the search bot (strat 'mc') against the
 * rule-based bot, at the same table, seats rotated every game.
 *
 * The baseline is a copy of the rule-based bot kept next to it, untracked:
 *   git show <ref>:server/game/skull_king/SkullKingBot.js > game/skull_king/SkullKingBot_base.js
 *
 * Usage: node sim_skullking_ab.js [games=200] [players=4] [expansions=csv] [key=value ...]
 *   key=value overrides the search tunables (bidSamples, playSamples, deadlineMs, bidSpan, playMargin),
 *   or noise=0.2: the baseline seats play a random legal card / bid +-1 with that probability.
 *   The search bot still ASSUMES rule-based opponents, so noise measures how well it
 *   holds up against people who do not play like the bot.
 *
 * "diff" is (average final score of the search seats) - (average of the baseline
 * seats), per game; the +- is its standard error over games.
 */

const SkullKingGame = require('./game/skull_king/SkullKingGame');
const fresh = require('./game/skull_king/SkullKingBot');
const base = require('./game/skull_king/SkullKingBot_base');

const args = process.argv.slice(2);
const kv = {};
const pos = [];
for (const a of args) {
  const m = a.match(/^(\w+)=(.+)$/);
  if (m) kv[m[1]] = Number(m[2]); else pos.push(a);
}
const noise = kv.noise || 0;
delete kv.noise;
for (const [k, v] of Object.entries(kv)) {
  if (!(k in fresh.MC)) { console.error(`unknown tunable ${k}`); process.exit(2); }
  fresh.MC[k] = v;
}
const games = parseInt(pos[0], 10) || 200;
const playerCount = parseInt(pos[1], 10) || 4;
const expansions = pos[2] ? pos[2].split(',') : [];

const ids = Array.from({ length: playerCount }, (_, i) => `p${i}`);
const half = Math.floor(playerCount / 2); // search seats per table

let decisionMs = 0;
let decisions = 0;
let slowest = 0;

function act(game, pid, isFresh) {
  if (!isFresh) {
    const a = base.decideSKBotAction(game, pid);
    if (noise > 0 && a && Math.random() < noise) {
      if (a.type === 'submit_bid') {
        const b = a.bid + (Math.random() < 0.5 ? -1 : 1);
        return { type: 'submit_bid', bid: Math.min(Math.max(b, 0), game.round) };
      }
      if (a.type === 'play_card') {
        const legal = game.getLegalCards(pid);
        const id = legal[(Math.random() * legal.length) | 0];
        const act = { type: 'play_card', cardId: id };
        if (id === 'sk_tigress' || /tigress/.test(id)) act.tigressChoice = Math.random() < 0.5 ? 'pirate' : 'escape';
        return act;
      }
    }
    return a;
  }
  const t = process.hrtime.bigint();
  const a = fresh.decideSKBotAction(game, pid, 'mc');
  const ms = Number(process.hrtime.bigint() - t) / 1e6;
  decisionMs += ms; decisions++; if (ms > slowest) slowest = ms;
  return a;
}

const diffs = [];
let freshWins = 0, baseWins = 0, hitFresh = 0, hitBase = 0, roundsFresh = 0, roundsBase = 0;
let sumFresh = 0, sumBase = 0, errors = 0;

for (let g = 0; g < games; g++) {
  // Rotate which seats are the search bot so seat/dealer order cannot favour one side.
  const offset = g % playerCount;
  const isFresh = {};
  ids.forEach((pid, i) => { isFresh[pid] = ((i + offset) % playerCount) < half; });

  const game = new SkullKingGame(ids, [], { expansions });
  game.start();
  let guard = 60000;
  while (game.state !== 'game_end' && guard-- > 0) {
    if (game.state === 'bidding') {
      let progressed = false;
      for (const pid of ids) {
        if (game.bids[pid] !== null) continue;
        const a = act(game, pid, isFresh[pid]);
        if (!a) continue;
        const r = game.handleAction(pid, a);
        if (r && r.success) progressed = true;
      }
      if (!progressed) { errors++; break; }
    } else if (game.state === 'playing') {
      const pid = game.currentPlayer;
      const a = act(game, pid, isFresh[pid]);
      const r = a && game.handleAction(pid, a);
      if (!r || !r.success) { errors++; break; }
    } else if (game.state === 'pirate_ability') {
      const pid = game.pendingAbility.playerId;
      const a = act(game, pid, isFresh[pid]) || game._defaultAbilityAction();
      let r = game.handleAction(pid, a);
      if (!r || !r.success) r = game.handleAction(pid, game._defaultAbilityAction());
      if (!r || !r.success) { errors++; break; }
    } else if (game.state === 'trick_end') {
      game.advanceAfterTrickEnd();
    } else if (game.state === 'round_end') {
      for (const pid of ids) {
        const hit = game.bids[pid] === game.tricks[pid];
        if (isFresh[pid]) { roundsFresh++; if (hit) hitFresh++; } else { roundsBase++; if (hit) hitBase++; }
      }
      game.nextRound();
    } else { errors++; break; }
  }
  if (game.state !== 'game_end') continue;

  // the last round never passes through 'round_end'
  for (const pid of ids) {
    const hit = game.bids[pid] === game.tricks[pid];
    if (isFresh[pid]) { roundsFresh++; if (hit) hitFresh++; } else { roundsBase++; if (hit) hitBase++; }
  }
  const f = ids.filter((p) => isFresh[p]).map((p) => game.totalScores[p]);
  const b = ids.filter((p) => !isFresh[p]).map((p) => game.totalScores[p]);
  const mean = (a) => a.reduce((x, y) => x + y, 0) / a.length;
  diffs.push(mean(f) - mean(b));
  sumFresh += mean(f); sumBase += mean(b);
  const top = Math.max(...ids.map((p) => game.totalScores[p]));
  if (f.includes(top)) freshWins++;
  if (b.includes(top)) baseWins++;
}

const n = diffs.length;
const md = diffs.reduce((a, c) => a + c, 0) / n;
const sd = Math.sqrt(diffs.reduce((a, c) => a + (c - md) ** 2, 0) / Math.max(1, n - 1));
console.log(`=== SK A/B: search(mc) vs rule-based, ${playerCount}p, ${n}/${games} games, exp=[${expansions}] errors=${errors}`);
if (Object.keys(kv).length) console.log('tunables', JSON.stringify(kv));
if (noise) console.log('baseline noise', noise);
console.log(`avg final: mc ${(sumFresh / n).toFixed(1)}  base ${(sumBase / n).toFixed(1)}`);
console.log(`diff: ${md.toFixed(1)} +- ${(sd / Math.sqrt(n)).toFixed(1)} per game  (z=${(md / (sd / Math.sqrt(n))).toFixed(2)})`);
console.log(`top score (ties count for both): mc ${freshWins}  base ${baseWins}`);
console.log(`bid hit rate: mc ${(100 * hitFresh / roundsFresh).toFixed(1)}%  base ${(100 * hitBase / roundsBase).toFixed(1)}%`);
console.log(`mc decision time: avg ${(decisionMs / Math.max(1, decisions)).toFixed(2)}ms  slowest ${slowest.toFixed(1)}ms over ${decisions} decisions`);
