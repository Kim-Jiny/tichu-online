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
// Pin the solver to a fixed depth + a huge time budget BEFORE loading it, so
// these golden tests are fully deterministic (no deadline-dependent fallback).
process.env.MIGHTY_SOLVE_CARDS = '3';
process.env.MIGHTY_SOLVE_MS = '600000';

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

// ── Fix 5: 마이티를 아끼고 그 무늬 최상위로 받는다 ──
// 유저 리포트 국면: 주공이 첫 트릭에 낮은 카드를 리드했고, (아직 공개 안 된)
// 프렌드 봇이 그 무늬 최상위(♠K)와 마이티(♠A)를 둘 다 들고 있다.
// 뒤에 스페이드가 없는 상대가 기루다를 들고 있어서 "안전한 승리 카드" 검사는
// ♠K 를 떨어뜨리고, 예전엔 그래서 마이티가 강제로 나갔다. 판돈 0점짜리
// 첫 트릭이므로 ♠K 로 받고 마이티는 남겨야 한다.
(() => {
  const c = (s) => s.split(' ').map(x => `mighty_${x}`);
  const build = () => position({
    declarer: 'p0', partner: null, friendRevealed: false,
    friendCard: 'mighty_spade_A', trumpSuit: 'club',
    tricksLen: 0, currentPlayer: 'p1',
    currentTrick: [{ pid: 'p0', cardId: 'mighty_spade_5' }],
    hands: {
      p0: c('spade_6 spade_7 spade_8 club_2 club_3 heart_2 heart_3 diamond_2 diamond_3'),
      p1: c('spade_A spade_K heart_8 heart_9 heart_10 diamond_8 diamond_9 diamond_10 club_9 club_10'),
      // 스페이드가 없고 기루다를 들고 있다 → ♠K 는 잘릴 수 있다.
      // 봇은 모든 손패를 보므로 오라클도 "어차피 러프당한다"를 알고 마이티를
      // 골랐었다. 그래도 판돈 0점짜리 첫 트릭엔 ♠K 로 받는 게 맞다.
      p2: c('club_4 club_5 club_6 club_Q club_K heart_4 heart_5 diamond_4 diamond_5 diamond_7'),
      p3: c('spade_3 spade_4 spade_9 spade_10 heart_6 heart_7 heart_J diamond_6 diamond_J club_7'),
      p4: c('spade_2 spade_J spade_Q heart_Q heart_K heart_A diamond_Q diamond_K diamond_A club_8'),
    },
  });
  for (const strategy of ['heuristic', 'mixoracle']) {
    check(`fix5(${strategy}): 첫 트릭에서 마이티 대신 무늬 최상위`,
      (MightyBot.decideMightyBotAction(build(), 'p1', strategy) || {}).cardId,
      got => got === 'mighty_spade_K');
  }
})();

// ── Fix 6: 상대가 가져갈 트릭에 점수 카드를 얹어 주지 않는다 ──
// 유저 리포트 형태(자가대국에서 뜬 실제 국면). 야당 p1 이 ♠K 로 이기고 있고
// (아직 공개 안 된) 프렌드 p0 이 따라내야 한다. ♠Q 는 ♠K 를 못 넘으면서
// 점수만 넘겨주는 카드고, ♠7 이라는 값싼 대안이 있다.
(() => {
  const c = (s) => s.split(' ').map(x => `mighty_${x}`);
  const build = () => position({
    declarer: 'p2', partner: null, friendRevealed: false,
    friendCard: 'mighty_spade_A', trumpSuit: 'heart',
    tricksLen: 3, currentPlayer: 'p0',
    currentTrick: [
      { pid: 'p1', cardId: 'mighty_spade_K' },
      { pid: 'p2', cardId: 'mighty_diamond_2' },
      { pid: 'p3', cardId: 'mighty_spade_2' },
      { pid: 'p4', cardId: 'mighty_spade_4' },
    ],
    hands: {
      p0: c('diamond_5 spade_Q heart_8 spade_7 club_4 diamond_7 spade_A'),
      p1: c('diamond_K diamond_9 spade_6 spade_8 diamond_3 spade_3'),
      p2: c('heart_Q heart_A diamond_6 heart_K heart_J diamond_8'),
      p3: c('spade_5 heart_4 diamond_4 heart_3 club_8 club_6'),
      p4: c('heart_9 heart_5 heart_2 heart_10 joker club_10'),
    },
  });
  // 이기러 가든(♠A) 값싸게 버리든(♠7) 상관없다. ♠Q 만 아니면 된다.
  for (const strategy of ['heuristic', 'mixoracle']) {
    check(`fix6(${strategy}): 상대 트릭에 점수 카드를 안 준다`,
      (MightyBot.decideMightyBotAction(build(), 'p0', strategy) || {}).cardId,
      got => got !== 'mighty_spade_Q');
  }
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
