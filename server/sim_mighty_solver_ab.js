'use strict';
/**
 * A-B harness: mixoracle + endgame SOLVER seats vs mixoracle ORACLE-only seats,
 * at one table, on identical seeded deals, camps rotating each round so seat
 * bias washes out. Isolates the endgame solver's contribution.
 *
 *   node sim_mighty_solver_ab.js [rounds] [seedBase]
 *
 * Uses the per-seat gate hook (global.__mightySolverGate) so both camps share
 * the same mixoracle path and only differ in whether the exact solver fires.
 */
const MightyGame = require('./game/mighty/MightyGame');
const { decideMightyBotAction } = require('./game/mighty/MightyBot');
const { makeRng } = require('./game/mighty/MightyDeck');

const IDS = ['p0', 'p1', 'p2', 'p3', 'p4'];
const NAMES = {}; IDS.forEach(p => (NAMES[p] = p));

function settle(g) { let s = 200; while (s-- > 0) { if (g.state === 'trick_end') { g.advanceAfterTrickEnd(); continue; } break; } }

const rounds = parseInt(process.argv[2] || '2000', 10);
const base = parseInt(process.argv[3] || '7', 10);
const camp = { solver: { dc: 0, ds: 0, rn: 0, sc: 0 }, oracle: { dc: 0, ds: 0, rn: 0, sc: 0 } };
let passouts = 0, errors = 0;

for (let r = 0; r < rounds; r++) {
  const seatCamp = {};
  for (let i = 0; i < IDS.length; i++) seatCamp[IDS[i]] = ((i + r) % 2 === 0) ? 'solver' : 'oracle';
  global.__mightySolverGate = (pid) => seatCamp[pid] === 'solver';

  const g = new MightyGame(IDS, NAMES, { targetScore: 50, rng: makeRng((1000003 * base + r) >>> 0) });
  g.start();
  let steps = 0, err = false;
  while (g.state !== 'round_end' && g.state !== 'game_end' && steps++ < 8000) {
    settle(g); if (g.state === 'round_end' || g.state === 'game_end') break;
    const actor = g.getPendingActor(); if (!actor) break;
    const a = decideMightyBotAction(g, actor, 'mixoracle');
    if (!a) { err = true; break; }
    const res = g.handleAction(actor, a);
    if (!res || res.success === false) {
      const fb = g.getAutoTimeoutAction(actor);
      if (fb) g.handleAction(actor, fb); else { err = true; break; }
    }
  }
  if (err) { errors++; continue; }
  settle(g);
  if (!g.declarer || !g.roundResult) { passouts++; continue; }
  const dc = seatCamp[g.declarer]; camp[dc].dc++; if (g.roundResult.success) camp[dc].ds++;
  for (const pid of IDS) { const c = seatCamp[pid]; camp[c].rn++; camp[c].sc += (g.scores[pid] || 0); }
}

const pct = (a, b) => b > 0 ? (a / b * 100).toFixed(1) + '%' : '-';
console.log(`\nSOLVER vs ORACLE-only (mixoracle), ${rounds} seeded rounds (base ${base}), camps rotate.`);
console.log(`passouts=${passouts} errors=${errors}\n`);
console.log('camp     declRounds  declSucc    seatRounds  avgScore');
for (const c of ['solver', 'oracle']) {
  const s = camp[c];
  console.log(`${c.padEnd(7)}  ${String(s.dc).padStart(9)}   ${pct(s.ds, s.dc).padStart(7)}    ${String(s.rn).padStart(9)}   ${(s.sc / s.rn).toFixed(3).padStart(7)}`);
}
const d = (camp.solver.sc / camp.solver.rn) - (camp.oracle.sc / camp.oracle.rn);
console.log(`\nSOLVER avgScore advantage per seat-round: ${d >= 0 ? '+' : ''}${d.toFixed(3)}`);
