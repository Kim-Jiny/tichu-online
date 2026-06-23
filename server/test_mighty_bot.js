'use strict';
/**
 * Regression tests for Mighty bot decisions.
 *
 * Each test pins a specific endgame/trick situation (a "golden position") and
 * asserts the heuristic bot plays the correct card. These lock in fixes that
 * aggregate win-rate sims are too noise-insensitive to catch (the situations
 * are rare). Positions are built on a REAL MightyGame instance (seeded, so
 * getMightyCard / _getCardPriority / clone / getLegalCards all work) with the
 * target state injected directly.
 *
 *   node test_mighty_bot.js
 */
const assert = require('assert');
const MightyGame = require('./game/mighty/MightyGame');
const MightyBot = require('./game/mighty/MightyBot');
const Solver = require('./game/mighty/MightyEndgameSolver');
const { makeRng, deal } = require('./game/mighty/MightyDeck');

const IDS = ['p0', 'p1', 'p2', 'p3', 'p4'];

/** Build a playing-state position with fields overridden. */
function position(opts) {
  const names = {};
  IDS.forEach(p => (names[p] = p));
  const game = new MightyGame(IDS, names, { targetScore: 50, rng: makeRng(1) });
  game.state = 'playing';
  game.trumpSuit = opts.trumpSuit || 'club';
  game.declarer = opts.declarer || 'p0';
  game.partner = opts.partner || null;
  game.friendRevealed = opts.friendRevealed || false;
  game.friendCard = opts.friendCard || 'first_trick';
  game.hands = opts.hands;
  game.currentTrick = opts.currentTrick || [];
  game.tricks = new Array(opts.tricksLen != null ? opts.tricksLen : 3)
    .fill(0).map(() => ({ cards: [] }));
  game.currentPlayer = opts.currentPlayer;
  Object.assign(game.options, opts.options || {});
  return game;
}

function leadCardOf(game, pid) {
  const a = MightyBot.decideMightyBotAction(game, pid, 'heuristic');
  return a && a.cardId;
}

let pass = 0, fail = 0;
function check(name, got, expectFn) {
  let ok = false, detail = '';
  try { ok = expectFn(got); } catch (e) { detail = e.message; }
  if (ok) { pass++; console.log(`PASS  ${name} (got ${got})`); }
  else { fail++; console.log(`FAIL  ${name}: got ${got} ${detail}`); }
}

// ── Seeded RNG: same seed → identical deal; different seed → different ──
(() => {
  const a = deal(IDS, makeRng(123));
  const b = deal(IDS, makeRng(123));
  const c = deal(IDS, makeRng(124));
  check('seeded deal reproducible', JSON.stringify(a) === JSON.stringify(b), x => x === true);
  check('different seed → different deal', JSON.stringify(a) === JSON.stringify(c), x => x === false);
})();

// ── Fix 1: penultimate-trick joker sacrifice ──
// Declarer holds two trumps (♣3,♣J), only government has trump, an opponent
// holds the joker (dies on the last trick). Lead the LOW trump (♣3), keeping
// ♣J for the final trick. (Not the high ♣J.)
check('fix1: penultimate → lead low trump',
  leadCardOf(position({
    declarer: 'p0', partner: 'p2', friendRevealed: true, trumpSuit: 'club',
    tricksLen: 8, currentPlayer: 'p0', currentTrick: [],
    options: { lastTrickJokerPower: false },
    hands: {
      p0: ['mighty_club_3', 'mighty_club_J'],
      p1: ['mighty_joker', 'mighty_heart_2'],
      p2: ['mighty_diamond_5', 'mighty_diamond_6'],
      p3: ['mighty_heart_7', 'mighty_heart_8'],
      p4: ['mighty_spade_2', 'mighty_spade_4'],
    },
  }), 'p0'),
  got => got === 'mighty_club_3');

// ── Fix 2: opposition keeps a live-ruffer trump, dumps a point card ──
// Opp bot can't beat declarer's ♣Q ruff; its only non-trump cards are points.
// ♣8 is a live ruffer (no opponent holds a higher trump), so keep it and dump
// the lowest point card (♥10), NOT the trump.
check('fix2: opp keeps live-ruffer trump, dumps point',
  leadCardOf(position({
    declarer: 'p0', partner: 'p3', friendRevealed: true, trumpSuit: 'club',
    tricksLen: 3, currentPlayer: 'p1',
    currentTrick: [
      { pid: 'p4', cardId: 'mighty_diamond_9' },
      { pid: 'p0', cardId: 'mighty_club_Q' },
    ],
    hands: {
      p0: ['mighty_heart_3', 'mighty_heart_4'],
      p1: ['mighty_club_8', 'mighty_heart_A', 'mighty_heart_10'],
      p2: ['mighty_heart_6', 'mighty_heart_7'],
      p3: ['mighty_spade_6', 'mighty_spade_7'],
      p4: ['mighty_diamond_2', 'mighty_diamond_3'],
    },
  }), 'p1'),
  got => got === 'mighty_heart_10');

// ── Fix 2b: opposition dumps an OVER-RUFFABLE trump (declarer holds ♣K) ──
check('fix2b: opp dumps over-ruffable trump',
  leadCardOf(position({
    declarer: 'p0', partner: 'p3', friendRevealed: true, trumpSuit: 'club',
    tricksLen: 3, currentPlayer: 'p1',
    currentTrick: [
      { pid: 'p4', cardId: 'mighty_diamond_9' },
      { pid: 'p0', cardId: 'mighty_club_Q' },
    ],
    hands: {
      p0: ['mighty_club_K', 'mighty_heart_3'],
      p1: ['mighty_club_8', 'mighty_heart_A', 'mighty_heart_10'],
      p2: ['mighty_heart_6', 'mighty_heart_7'],
      p3: ['mighty_spade_6', 'mighty_spade_7'],
      p4: ['mighty_diamond_2', 'mighty_diamond_3'],
    },
  }), 'p1'),
  got => got === 'mighty_club_8');

// ── Fix 3: friend preserves joker on a LOCKED trick ──
// Declarer led ♣9 (trump); no opponent can beat it. Friend holds the joker but
// must NOT burn it to reveal/reinforce a trivially-won trick.
check('fix3: friend preserves joker on locked trick',
  leadCardOf(position({
    declarer: 'p0', partner: 'p2', friendRevealed: true, trumpSuit: 'club',
    tricksLen: 3, currentPlayer: 'p2',
    currentTrick: [{ pid: 'p0', cardId: 'mighty_club_9' }],
    hands: {
      p0: ['mighty_diamond_4'],
      p1: ['mighty_heart_2', 'mighty_diamond_3'],
      p2: ['mighty_joker', 'mighty_heart_10', 'mighty_heart_5', 'mighty_spade_8'],
      p3: ['mighty_spade_6', 'mighty_spade_7'],
      p4: ['mighty_diamond_6', 'mighty_diamond_7'],
    },
  }), 'p2'),
  got => got !== 'mighty_joker');

// ── Fix 4: joker lead suit avoids the team's Mighty suit ──
// Declarer leads the joker; partner holds the Mighty (♠A) as their ONLY spade.
// Declaring ♠ would force the partner to burn the Mighty — pick another suit.
(() => {
  const g = position({
    declarer: 'p0', partner: 'p2', friendRevealed: true, trumpSuit: 'club',
    tricksLen: 3, currentPlayer: 'p0', currentTrick: [],
    hands: {
      p0: ['mighty_joker', 'mighty_club_5', 'mighty_heart_6'],
      p1: ['mighty_spade_3', 'mighty_club_9', 'mighty_heart_7'],
      p2: ['mighty_spade_A', 'mighty_club_8', 'mighty_heart_9'],
      p3: ['mighty_diamond_5', 'mighty_diamond_6', 'mighty_club_K'],
      p4: ['mighty_diamond_7', 'mighty_diamond_8', 'mighty_heart_J'],
    },
  });
  const action = MightyBot.makePlayAction('mighty_joker', g, 'p0');
  check('fix4: joker call avoids Mighty suit (spade)',
    action.jokerSuit, s => s && s !== 'spade');
})();

// ── Endgame solver: legal + deterministic on real seeded endgames ──
// Plays seeded games to their first solvable position and checks the solver
// returns a legal, deterministic move. (Broad coverage — 4000+ solves with 0
// illegal moves — is exercised by sim_mighty_solver_ab.js.)
(() => {
  const settle = (g) => { let s = 200; while (s-- > 0) { if (g.state === 'trick_end') { g.advanceAfterTrickEnd(); continue; } break; } };
  let tested = 0, illegal = 0, nondet = 0;
  for (let seed = 1; seed <= 80 && tested < 40; seed++) {
    const names = {}; IDS.forEach(p => (names[p] = p));
    const g = new MightyGame(IDS, names, { targetScore: 50, rng: makeRng(seed) });
    g.start();
    let steps = 0;
    while (g.state !== 'round_end' && g.state !== 'game_end' && steps++ < 8000) {
      settle(g);
      if (g.state === 'round_end' || g.state === 'game_end') break;
      const actor = g.getPendingActor();
      if (!actor) break;
      if (g.state === 'playing' && g.currentPlayer === actor && Solver.canSolve(g) && tested < 40) {
        const m1 = Solver.solve(g, actor);
        const m2 = Solver.solve(g, actor);
        if (m1) {
          tested++;
          if (!g._getLegalCards(actor).includes(m1.cardId)) illegal++;
          if (!m2 || m1.cardId !== m2.cardId || m1.jokerSuit !== m2.jokerSuit) nondet++;
        }
      }
      const a = MightyBot.decideMightyBotAction(g, actor, 'heuristic');
      if (!a) break;
      const res = g.handleAction(actor, a);
      if (!res || res.success === false) {
        const fb = g.getAutoTimeoutAction(actor);
        if (fb) g.handleAction(actor, fb); else break;
      }
    }
  }
  check(`solver legal on ${tested} endgames`, illegal, x => x === 0);
  check('solver deterministic', nondet, x => x === 0);
})();

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
