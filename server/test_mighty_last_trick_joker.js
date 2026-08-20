'use strict';
/**
 * 막 트릭의 조커.
 *
 * 규칙: 막 트릭에 나온 조커는 무조건 지는 카드다. 그리고 무늬를 부르지
 * 않는다 — 다들 카드가 한 장뿐이라 고를 것도 없고, 리드 무늬는 조커 다음에
 * 나온 카드가 정한다.
 *
 * 예전에는 부른 무늬가 그대로 리드 무늬였다. 그 무늬를 아무도 안 들고
 * 있으면 나머지가 전부 우선순위 0 으로 묶이고, 목록 맨 앞의 조커가 그
 * 트릭을 가져갔다 — 져야 할 카드가 이겼다.
 *
 *   node test_mighty_last_trick_joker.js
 */
const MightyGame = require('./game/mighty/MightyGame');
const { makeRng } = require('./game/mighty/MightyDeck');

const IDS = ['p0', 'p1', 'p2', 'p3', 'p4'];
let pass = 0, fail = 0;
const check = (name, cond, detail = '') => {
  if (cond) { pass++; console.log(`  ok   ${name}`); }
  else { fail++; console.log(`  FAIL ${name}${detail ? ` — ${detail}` : ''}`); }
};

/** 9트릭이 끝나고 각자 한 장씩 남은 자리. p0 이 조커로 리드한다. */
function lastTrick(hands) {
  const names = {};
  IDS.forEach(p => (names[p] = p));
  const g = new MightyGame(IDS, names, { targetScore: 50, rng: makeRng(1) });
  g.state = 'playing';
  g.trumpSuit = 'heart';
  g.declarer = 'p0';
  g.friendCard = 'mighty_diamond_A';
  g.friendRevealed = true;
  g.partner = 'p2';
  g.tricks = new Array(9).fill(0).map(() => ({
    leader: 'p0', leadSuit: 'club', winner: 'p0', cards: [],
  }));
  g.currentPlayer = 'p0';
  g.currentTrick = [];
  g.hands = hands;
  // start() 를 안 거치는 자리라 점수패 통을 직접 열어 둔다.
  g.pointCards = {};
  IDS.forEach(p => (g.pointCards[p] = []));
  return g;
}

function playOut(g, jokerSuit) {
  g.handleAction('p0', { type: 'play_card', cardId: 'mighty_joker', ...(jokerSuit ? { jokerSuit } : {}) });
  for (const p of ['p1', 'p2', 'p3', 'p4']) {
    g.handleAction(p, { type: 'play_card', cardId: g.hands[p][0] });
  }
  return g.tricks[g.tricks.length - 1];
}

const spread = () => ({
  p0: ['mighty_joker'],
  p1: ['mighty_club_5'],
  p2: ['mighty_club_2'],
  p3: ['mighty_diamond_9'],
  p4: ['mighty_diamond_7'],
});

// ── 무늬를 안 불러도 낼 수 있다 ──
{
  const g = lastTrick(spread());
  const res = g.handleAction('p0', { type: 'play_card', cardId: 'mighty_joker' });
  check('막 트릭 조커는 무늬 없이 낼 수 있다', res.success === true,
    res.messageKey || '');
  check('무늬가 기록되지 않는다', g.jokerSuitDeclared === null,
    `jokerSuitDeclared=${g.jokerSuitDeclared}`);
}

// ── 부른 무늬는 무시된다 ──
{
  const t = playOut(lastTrick(spread()), 'spade');
  check('부른 무늬(♠)는 무시되고 다음 카드가 리드 무늬', t.leadSuit === 'club',
    `리드 무늬 ${t.leadSuit}`);
  check('조커가 트릭을 못 먹는다', t.winner !== 'p0', `승자 ${t.winner}`);
  check('두 번째 카드 무늬에서 제일 높은 사람이 먹는다', t.winner === 'p1',
    `승자 ${t.winner}`);
}

// ── 부른 무늬를 든 사람이 있어도 마찬가지 ──
{
  const hands = spread();
  hands.p3 = ['mighty_spade_3'];
  const t = playOut(lastTrick(hands), 'spade');
  check('♠ 를 든 사람이 있어도 리드 무늬는 다음 카드 것', t.leadSuit === 'club',
    `리드 무늬 ${t.leadSuit}`);
  check('그 사람이 먹지 않는다', t.winner === 'p1', `승자 ${t.winner}`);
}

// ── 기루다는 여전히 이긴다 ──
{
  const hands = spread();
  hands.p3 = ['mighty_heart_2'];
  const t = playOut(lastTrick(hands), 'spade');
  check('기루다는 리드 무늬를 넘는다', t.winner === 'p3', `승자 ${t.winner}`);
}

// ── 마이티는 여전히 다 이긴다 ──
{
  const hands = spread();
  hands.p4 = ['mighty_spade_A'];
  const t = playOut(lastTrick(hands), 'spade');
  check('마이티는 그대로 최강', t.winner === 'p4', `승자 ${t.winner}`);
}

// ── 막 트릭이 아니면 예전 그대로 ──
{
  const g = lastTrick(spread());
  g.tricks = new Array(5).fill(0).map(() => ({
    leader: 'p0', leadSuit: 'club', winner: 'p0', cards: [],
  }));
  const res = g.handleAction('p0', { type: 'play_card', cardId: 'mighty_joker' });
  check('중간 트릭 조커는 무늬를 반드시 부른다', res.success === false
    && res.messageKey === 'mighty_joker_suit_required', JSON.stringify(res));
  const g2 = lastTrick(spread());
  g2.tricks = new Array(5).fill(0).map(() => ({
    leader: 'p0', leadSuit: 'club', winner: 'p0', cards: [],
  }));
  g2.handleAction('p0', { type: 'play_card', cardId: 'mighty_joker', jokerSuit: 'spade' });
  check('중간 트릭은 부른 무늬가 리드 무늬', g2.jokerSuitDeclared === 'spade',
    `${g2.jokerSuitDeclared}`);
}

console.log(fail === 0 ? '\nPASS' : `\n${fail} FAILURE(S)`);
process.exit(fail === 0 ? 0 : 1);
