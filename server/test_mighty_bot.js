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

// ── Fix 5: 안 잘릴 자리면 마이티를 아끼고 그 무늬 최상위로 받는다 ──
// 유저 리포트 국면: 주공이 첫 트릭에 낮은 카드를 리드했고, (아직 공개 안 된)
// 프렌드 봇이 그 무늬 최상위(♠K)와 마이티(♠A)를 둘 다 들고 있다. 뒤에 남은
// 사람이 전부 스페이드를 들고 있어 ♠K 가 그대로 버틴다 — 이럴 때 마이티까지
// 쓰는 건 게임 최강 카드를 0점짜리 첫 트릭에 버리는 것이다.
//
// 처음엔 "뒤에서 잘릴 수 있어도 판돈 0점이면 ♠K" 로 넣었는데, 실제 대국에서
// 그 ♠K 가 기루다로 잘려 트릭을 통째로 넘기는 걸 보고 뒤집었다(Fix 5b).
// 지금 기준은 "잘릴 것 같으면 마이티, 버틸 때만 아낀다" 하나뿐이라,
// 이 케이스는 러프할 사람이 아예 없는 배치로 다시 세웠다.
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
      // 뒤에 남은 셋 다 스페이드를 들었다 → ♠K 를 넘길 사람이 없다.
      p2: c('spade_2 spade_3 club_6 club_Q club_K heart_4 heart_5 diamond_4 diamond_5 diamond_7'),
      p3: c('spade_4 spade_9 spade_10 heart_6 heart_7 heart_J diamond_6 diamond_J club_7 club_4'),
      p4: c('spade_J spade_Q heart_Q heart_K heart_A diamond_Q diamond_K diamond_A club_8 club_5'),
    },
  });
  for (const strategy of ['heuristic', 'mixoracle']) {
    check(`fix5(${strategy}): 안 잘릴 자리면 마이티 대신 무늬 최상위`,
      (MightyBot.decideMightyBotAction(build(), 'p1', strategy) || {}).cardId,
      got => got === 'mighty_spade_K');
  }
})();

// ── Fix 5b: 뒤에서 잘릴 것 같으면 마이티를 낸다 ──
// 유저 리포트: 기루다 하트, 주공이 1트릭 초구로 ♠3. 프렌드 봇은 ♠A(마이티)와
// ♠K 를 들고 있고, 뒤에 스페이드가 없는 야당이 있다. 봇은 마이티도 ♠K 도 안
// 내고 흘려서 트릭을 통째로 내줬다 — 마이티를 아끼려고 손을 뗀 규칙과 점수패를
// 안 넘기려는 규칙이 엇갈려서 셋 중 제일 나쁜 수가 나왔다.
// 야당이 막자리든 중간 자리든 같다. 잘릴 것 같으면 마이티로 확실히 가져온다.
(() => {
  const c = (s) => s.split(' ').map(x => `mighty_${x}`);
  const build = (voidLast) => position({
    declarer: 'p0', partner: null, friendRevealed: false,
    friendCard: 'mighty_spade_A', trumpSuit: 'heart',
    tricksLen: 0, currentPlayer: 'p2',
    currentTrick: [
      { pid: 'p0', cardId: 'mighty_spade_3' },
      { pid: 'p1', cardId: 'mighty_spade_7' },
    ],
    hands: {
      p0: c('spade_4 spade_5 heart_2 heart_3 club_2 club_3 club_4 diamond_2 diamond_3'),
      p1: c('spade_8 heart_4 club_5 club_6 club_7 diamond_4 diamond_5 diamond_6 diamond_7'),
      p2: c('spade_A spade_K heart_5 club_8 club_9 club_10 diamond_8 diamond_9 diamond_10 diamond_J'),
      // 스페이드가 없고 기루다를 잔뜩 든 야당. 막자리/중간 자리 둘 다 본다.
      [voidLast ? 'p3' : 'p4']:
        c('spade_6 spade_9 spade_10 spade_J spade_Q heart_6 club_J club_Q club_K diamond_Q'),
      [voidLast ? 'p4' : 'p3']:
        c('heart_A heart_K heart_Q heart_J heart_10 heart_9 heart_8 club_A diamond_K diamond_A'),
    },
  });
  for (const strategy of ['heuristic', 'mixoracle']) {
    check(`fix5b(${strategy}): 막자리가 잘라 가면 마이티를 낸다`,
      (MightyBot.decideMightyBotAction(build(true), 'p2', strategy) || {}).cardId,
      got => got === 'mighty_spade_A');
    check(`fix5b(${strategy}): 중간 자리가 잘라 가도 마이티를 낸다`,
      (MightyBot.decideMightyBotAction(build(false), 'p2', strategy) || {}).cardId,
      got => got === 'mighty_spade_A');
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

// ── Fix 7: 주공도 버릴 때 자기 무늬 최상위는 남긴다 ──
// 유저 리포트: 기루다 하트, 주공이 ♣6 과 ♣A 를 들고 있는데 프렌드가 이긴
// 트릭에 ♣A 를 실어 버린다. 1점 얹자고 나중에 확실히 가져올 트릭을 버리는 셈.
// 넘길 수 있는 카드였다면 실어 줘도 되지만 A 는 못 넘긴다.
(() => {
  const c = (s) => s.split(' ').map(x => `mighty_${x}`);
  const build = () => position({
    declarer: 'p0', partner: 'p2', friendRevealed: true, trumpSuit: 'heart',
    friendCard: 'mighty_diamond_A', tricksLen: 3, currentPlayer: 'p0',
    currentTrick: [
      { pid: 'p1', cardId: 'mighty_diamond_5' },
      { pid: 'p2', cardId: 'mighty_diamond_A' }, // 프렌드가 그 무늬 최상위로 확보
      { pid: 'p3', cardId: 'mighty_diamond_3' },
      { pid: 'p4', cardId: 'mighty_diamond_4' },
    ],
    hands: {
      p0: c('club_6 club_A spade_4 heart_2'), // 주공 — 다이아 없음
      p1: c('spade_A spade_K club_9 heart_6'),
      p2: c('club_K club_Q spade_9 heart_7'),
      p3: c('club_J club_10 spade_8 heart_8'),
      p4: c('club_8 club_7 spade_7 heart_9'),
    },
  });
  check('fix7(heuristic): 주공이 아군 트릭에 ♣A 를 안 버린다',
    (MightyBot.decideMightyBotAction(build(), 'p0', 'heuristic') || {}).cardId,
    got => got !== 'mighty_club_A');
})();

// ── Fix 7b: 야당도 같은 기준 ──
// 야당 아군(p3)이 ♦A 로 확보한 트릭. 뒤에 정부팀이 안 남았으니 그냥 버리는
// 자리인데, ♣A 를 실어 주면 나중에 자기가 가져올 트릭을 버리는 셈이다.
(() => {
  const c = (s) => s.split(' ').map(x => `mighty_${x}`);
  const build = () => position({
    declarer: 'p0', partner: 'p1', friendRevealed: true, trumpSuit: 'heart',
    friendCard: 'mighty_diamond_A', tricksLen: 3, currentPlayer: 'p2',
    currentTrick: [
      { pid: 'p3', cardId: 'mighty_diamond_A' },
      { pid: 'p4', cardId: 'mighty_diamond_2' },
      { pid: 'p0', cardId: 'mighty_diamond_7' },
      { pid: 'p1', cardId: 'mighty_diamond_8' },
    ],
    hands: {
      p0: c('spade_A spade_K club_9 heart_6'),
      p1: c('club_K club_Q spade_9 heart_7'),
      p2: c('club_6 club_A spade_4 heart_2'), // 야당 — 다이아 없음
      p3: c('club_J club_10 spade_8 heart_8'),
      p4: c('club_8 club_7 spade_7 heart_9'),
    },
  });
  check('fix7b(heuristic): 야당이 아군 트릭에 ♣A 를 안 버린다',
    (MightyBot.decideMightyBotAction(build(), 'p2', 'heuristic') || {}).cardId,
    got => got !== 'mighty_club_A');
})();

// ── Fix 8: 조커콜은 NT 금지 · 우리 편 조커에 쏘지 않기 ──
// 조커콜은 상대 조커를 끌어내려고 쏘는 것이다. 우리 편이 들고 있으면 우리
// 조커를 우리가 태우는 헛발사고, 노기루다(NT)에서는 조커콜 자체가 없다.
(() => {
  const c = (s) => s.split(' ').map(x => `mighty_${x}`);
  const build = (trumpSuit, jokerHolder) => {
    const hands = {
      p0: c('club_3 club_9 heart_5 diamond_6 spade_7'), // 주공 — 조커콜 카드 보유
      p1: c('club_4 heart_6 diamond_7 spade_8 heart_10'),
      p2: c('club_5 heart_7 diamond_8 spade_9 heart_J'), // 프렌드
      p3: c('club_6 heart_8 diamond_9 spade_10 heart_Q'),
      p4: c('club_7 heart_9 diamond_10 spade_J heart_K'),
    };
    hands[jokerHolder] = [...hands[jokerHolder].slice(0, 4), 'mighty_joker'];
    return position({
      declarer: 'p0', partner: 'p2', friendRevealed: true,
      friendCard: 'mighty_spade_A', trumpSuit,
      tricksLen: 1, currentPlayer: 'p0', currentTrick: [], hands,
    });
  };
  for (const strategy of ['heuristic', 'mixoracle']) {
    // p2 = 프렌드(우리 편)
    check(`fix8(${strategy}): 우리 편 조커에 조커콜 안 쏨`,
      (MightyBot.decideMightyBotAction(build('heart', 'p2'), 'p0', strategy) || {}).jokerCall === true,
      got => got === false);
    // NT 에서는 상대가 들고 있어도 콜 자체가 없다
    check(`fix8(${strategy}): NT 에서 조커콜 안 함`,
      (MightyBot.decideMightyBotAction(build('no_trump', 'p4'), 'p0', strategy) || {}).jokerCall === true,
      got => got === false);
    // 상대가 들고 있으면 정상적으로 쏜다 (수정이 과하게 막지 않았는지 확인)
    check(`fix8(${strategy}): 야당 조커에는 정상 발사`,
      (MightyBot.decideMightyBotAction(build('heart', 'p4'), 'p0', strategy) || {}).jokerCall === true,
      got => got === true);
  }
})();

// ── Fix 9: NT 프렌드 리드 — 탑패 먼저, 없으면 부른 문양 복귀 ──
// 유저 스펙: NT 에서 주공이 ♣4 로 프렌드를 끌어내고 프렌드가 마이티(또는 조커)로
// 받아 나온 뒤, 프렌드가 선을 잡으면 ① 자기 탑패를 높은 것부터 내리고
// ② 탑패가 없으면 부른 문양(= 주공이 끌어낸 무늬, 여기선 클로버)을 높은 것부터
// 돌려준다. 클로버가 우선순위인 게 아니라 탑패를 다 쓴 뒤의 복귀처다.
//
// 예전엔 부른 문양을 "프렌드 카드의 무늬"로만 계산해서, 마이티(♠A)·조커처럼
// 무늬 의미가 없는 프렌드 카드면 ②가 통째로 빠지고 오라클로 흘렀다.
(() => {
  const c = (s) => s.split(' ').map(x => `mighty_${x}`);
  const build = (friendCard, withTops) => {
    const g = position({
      declarer: 'p0', partner: 'p2', friendRevealed: true,
      friendCard, trumpSuit: 'no_trump',
      tricksLen: 0, currentPlayer: 'p2', currentTrick: [],
      hands: {
        p0: c('club_2 heart_3 diamond_3 spade_3 club_5'),
        p1: c('club_6 heart_4 diamond_K spade_4 club_7'),
        p2: withTops
          ? c('heart_A heart_K club_K club_9 diamond_5')
          : c('club_K club_9 club_2 diamond_5 spade_6'),
        p3: c('club_A heart_6 diamond_A spade_K club_10'),
        p4: c('club_J heart_7 diamond_Q spade_10 club_Q'),
      },
    });
    // 주공이 ♣4 를 깔고 프렌드가 프렌드 카드로 받아 공개된 트릭.
    g.tricks = [{
      leader: 'p0', leadSuit: 'club', winner: 'p2',
      cards: [
        { pid: 'p0', cardId: 'mighty_club_4' },
        { pid: 'p1', cardId: 'mighty_club_3' },
        { pid: 'p2', cardId: friendCard },
        { pid: 'p3', cardId: 'mighty_diamond_2' },
        { pid: 'p4', cardId: 'mighty_heart_2' },
      ],
    }];
    return g;
  };
  for (const [label, friendCard] of [['마이티', 'mighty_spade_A'], ['조커', 'mighty_joker']]) {
    check(`fix9(${label} 프렌드): 탑패부터 높은 순으로`,
      (MightyBot.decideMightyBotAction(build(friendCard, true), 'p2', 'mixoracle') || {}).cardId,
      got => got === 'mighty_heart_A');
    check(`fix9(${label} 프렌드): 탑패 없으면 부른 문양 높은 순으로`,
      (MightyBot.decideMightyBotAction(build(friendCard, false), 'p2', 'mixoracle') || {}).cardId,
      got => got === 'mighty_club_K');
  }
})();

// ── Fix 10: 주공의 그 무늬가 마이티 한 장뿐이면 그 무늬를 돌리지 않는다 ──
// 유저 스펙: 주공 손패에 스페이드가 ♠A(마이티) 하나뿐인데 프렌드가 스페이드를
// 돌리면, 주공은 팔로우할 카드가 없어 마이티를 버려야 한다. 기루다/NT 무관.
(() => {
  const c = (s) => s.split(' ').map(x => `mighty_${x}`);
  const build = (trumpSuit) => {
    const g = position({
      declarer: 'p0', partner: 'p2', friendRevealed: true,
      friendCard: 'mighty_club_A', trumpSuit,
      tricksLen: 0, currentPlayer: 'p2', currentTrick: [],
      hands: {
        p0: c('spade_A heart_2 heart_3 diamond_2 club_2'), // 스페이드 = 마이티뿐
        p1: c('spade_2 heart_4 diamond_4 club_4 heart_5'),
        p2: c('spade_K spade_9 heart_A heart_K diamond_5'), // 프렌드(선)
        p3: c('spade_3 heart_6 diamond_6 club_6 heart_7'),
        p4: c('spade_4 heart_8 diamond_8 club_8 heart_9'),
      },
    });
    g.tricks = [{
      leader: 'p0', leadSuit: 'club', winner: 'p2',
      cards: [
        { pid: 'p0', cardId: 'mighty_club_3' }, { pid: 'p1', cardId: 'mighty_club_5' },
        { pid: 'p2', cardId: 'mighty_club_A' }, { pid: 'p3', cardId: 'mighty_club_7' },
        { pid: 'p4', cardId: 'mighty_club_9' },
      ],
    }];
    return g;
  };
  for (const trumpSuit of ['heart', 'no_trump']) {
    for (const strategy of ['heuristic', 'mixoracle']) {
      const got = (MightyBot.decideMightyBotAction(build(trumpSuit), 'p2', strategy) || {}).cardId;
      check(`fix10(${trumpSuit}/${strategy}): 마이티 무늬를 안 돌린다`,
        got, x => x === 'mighty_joker' || !String(x).startsWith('mighty_spade_'));
    }
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

// ── Fix 11: 점수 걸린 트릭을 확실히 먹을 수 있으면 먹는다 ──
// 유저 리포트: 기루다 클로버, 주공이 1트릭 초구로 ♥K 를 냈는데 바로 뒷자리
// 야당이 ♥A 를 들고도 안 냈다.
// 아래는 그 리포트를 쫓다가 자가대국 스캔에서 잡은 같은 성질의 국면이다.
// 주공이 ♣K 를 깔고 ♣Q 까지 실려 2점이 걸렸는데, 야당 p2 가 ♣A 를 들고도
// ♣2 로 흘렸다(오라클 롤아웃이 "에이스는 아꼈다가 더 큰 트릭에" 를 고른다).
// 뒤에 남은 사람은 p3 뿐이고 ♣A 를 넘길 카드가 없으니 확실한 승리수다.
(() => {
  const c = (s) => s.split(' ').map(x => x === 'joker' ? 'mighty_joker' : `mighty_${x}`);
  const build = () => position({
    declarer: 'p4', partner: null, friendRevealed: false,
    friendCard: 'mighty_heart_A', trumpSuit: 'club',
    tricksLen: 1, currentPlayer: 'p2',
    currentTrick: [
      { pid: 'p4', cardId: 'mighty_club_K' },
      { pid: 'p0', cardId: 'mighty_club_4' },
      { pid: 'p1', cardId: 'mighty_club_Q' },
    ],
    hands: {
      p0: c('spade_K club_9 heart_2 club_6 heart_A diamond_7 club_7 diamond_K'),
      p1: c('heart_3 spade_J heart_J spade_Q heart_5 spade_8 diamond_9 heart_6'),
      p2: c('club_A heart_10 heart_8 diamond_10 spade_10 club_2 joker spade_6 diamond_4'),
      p3: c('diamond_8 diamond_2 heart_9 club_3 diamond_6 heart_4 diamond_J heart_Q club_J'),
      p4: c('diamond_A diamond_3 heart_7 club_5 club_8 club_10 heart_K diamond_5'),
    },
  });
  // 휴리스틱은 같은 트릭을 조커로 먹는다(트릭은 가져오지만 조커 낭비 판단은
  // 별개 룰 소관). 실서버가 쓰는 건 mixoracle 이라 거기서만 카드를 못박는다.
  let fired = [];
  global.__mightyRuleTrace = (name) => fired.push(name);
  check('fix11: 점수 걸린 트릭을 확실한 승리수로 먹는다',
    (MightyBot.decideMightyBotAction(build(), 'p2', 'mixoracle') || {}).cardId,
    got => got === 'mighty_club_A');
  check('fix11: 그 판단이 하드 룰에서 나온다',
    fired.join(','), got => got.includes('takeSurePointTrick'));

  // 판돈이 0점이면 룰이 안 걸린다 — 에이스를 아끼는 판단은 그대로 둔다.
  const noPot = () => {
    const g = build();
    g.currentTrick = [
      { pid: 'p4', cardId: 'mighty_club_9' },
      { pid: 'p0', cardId: 'mighty_club_4' },
      { pid: 'p1', cardId: 'mighty_club_6' },
    ];
    g.hands.p4 = c('diamond_A diamond_3 heart_7 club_5 club_8 club_K heart_K diamond_5');
    g.hands.p1 = c('heart_3 spade_J heart_J spade_Q heart_5 spade_8 diamond_9 club_Q');
    return g;
  };
  fired = [];
  MightyBot.decideMightyBotAction(noPot(), 'p2', 'mixoracle');
  check('fix11: 판돈 0점이면 룰이 안 걸린다',
    fired.join(','), got => !got.includes('takeSurePointTrick'));
  global.__mightyRuleTrace = null;
})();

// ── Fix 12: 주공이 조커콜을 들었으면 프렌드는 조커를 먼저 쓴다 ──
// 유저 리포트: 주공(사람)이 조커콜 카드를 들고 있는데 프렌드(봇)가 선을
// 먹고도 조커를 안 써서, 나중에 주공이 쏜 총에 프렌드가 맞았다.
// 룰은 있었는데 "프렌드 공개 전" 에만 위협으로 봐서 공개 뒤엔 안 걸렸다.
//
// 부를 무늬도 같이 못박는다 — 기루다가 6장 이상 남았고 야당이 기루다를
// 들고 있으면 기루다(같이 훑는다), 아니면 주공이 물패를 낼 무늬.
(() => {
  const c = (s) => s.split(' ').map(x => x === 'joker' ? 'mighty_joker' : `mighty_${x}`);
  const build = (mut) => {
    const g = position({
      declarer: 'p0', partner: 'p2', friendRevealed: true,
      friendCard: 'mighty_diamond_A', trumpSuit: 'heart',
      tricksLen: 2, currentPlayer: 'p2', currentTrick: [],
      hands: {
        p0: c('club_3 heart_A heart_5 heart_2 spade_9 spade_4 diamond_2'),
        p1: c('spade_A spade_K heart_7 club_9 club_8 diamond_5 diamond_6'),
        p2: c('joker diamond_A heart_9 club_K club_Q spade_7 spade_6'),
        p3: c('heart_K heart_3 club_A club_10 spade_8 diamond_9 diamond_J'),
        p4: c('heart_Q heart_4 club_5 club_6 spade_10 diamond_K diamond_Q'),
      },
    });
    if (mut) mut(g, c);
    return g;
  };

  // 조커콜 카드는 기루다가 클로버가 아니면 ♣3 이다.
  check('fix12: 조커콜 카드가 주공 손에 있다',
    build().getJokerCallCard(), got => got === 'mighty_club_3');

  const a = MightyBot.decideMightyBotAction(build(), 'p2', 'mixoracle') || {};
  check('fix12: 프렌드가 조커를 먼저 쓴다', a.cardId,
    got => got === 'mighty_joker');
  check('fix12: 야당이 기루다를 들었으면 기루다를 부른다', a.jokerSuit,
    got => got === 'heart');

  // 남은 기루다가 전부 우리 편 손에 있으면 훑을 게 없다 → 기루다를 안 부른다.
  const b = MightyBot.decideMightyBotAction(build((g, cc) => {
    g.hands.p0 = cc('club_3 heart_A heart_5 heart_2 heart_K heart_Q spade_4');
    g.hands.p1 = cc('spade_A spade_K club_7 club_9 club_8 diamond_5 diamond_6');
    g.hands.p3 = cc('club_A club_10 club_J spade_8 diamond_9 diamond_J diamond_10');
    g.hands.p4 = cc('club_5 club_6 club_2 spade_10 spade_5 diamond_K diamond_Q');
  }), 'p2', 'mixoracle') || {};
  check('fix12: 야당 기루다가 없으면 기루다를 안 부른다', b.jokerSuit,
    got => got && got !== 'heart');
})();

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
