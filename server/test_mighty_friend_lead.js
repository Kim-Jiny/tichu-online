'use strict';
/**
 * 마이티 프렌드가 선을 잡았을 때 무엇을 돌려주는가.
 *
 * 실제로 나온 판: NT 20공약, 마이티(♠A) 프렌드. 주공이 1트릭에 ♦4 를 깔아
 * 프렌드를 부르고, 프렌드가 막자리 ♦Q 로 선을 잡았다. 2트릭 첫구에서 봇은
 * 다이아를 들고도 마이티를 혼자 던져버렸다.
 *
 * 두 가지를 한꺼번에 버리는 수다: 아무도 위협하지 않는 트릭에 최강 카드를
 * 쓰고, 그러면서 자기가 프렌드라는 걸 알려준다. 주공은 ♦A 를 들고 다이아가
 * 돌아오기를 기다리고 있었다.
 *
 *   node test_mighty_friend_lead.js
 */
process.env.MIGHTY_SOLVE_CARDS = '3';
process.env.MIGHTY_SOLVE_MS = '600000';

const MightyGame = require('./game/mighty/MightyGame');
const { makeRng } = require('./game/mighty/MightyDeck');
const mixoracle = require('./game/mighty/strategies/mixoracle');

const IDS = ['p0', 'p1', 'p2', 'p3', 'p4'];
let pass = 0, fail = 0;
const check = (name, cond, detail = '') => {
  if (cond) { pass++; console.log(`  ok   ${name}`); }
  else { fail++; console.log(`  FAIL ${name}${detail ? ` — ${detail}` : ''}`); }
};

/** 주공이 ♦4 로 부르고 프렌드가 ♦Q 로 선을 잡은 자리. */
function position({ friendHand, revealed = false }) {
  const names = {};
  IDS.forEach(p => (names[p] = p));
  const g = new MightyGame(IDS, names, { targetScore: 50, rng: makeRng(1) });
  g.state = 'playing';
  g.trumpSuit = 'no_trump';
  g.declarer = 'p0';
  g.friendCard = g.getMightyCard();
  g.friendRevealed = revealed;
  g.partner = revealed ? 'p2' : null;
  g.currentTrick = [];
  g.currentPlayer = 'p2';
  g.hands = {
    p0: ['mighty_diamond_A', 'mighty_spade_6', 'mighty_spade_5', 'mighty_spade_4', 'mighty_heart_6'],
    p1: ['mighty_club_3', 'mighty_club_5', 'mighty_heart_3', 'mighty_heart_4', 'mighty_club_7'],
    p2: friendHand,
    p3: ['mighty_club_K', 'mighty_heart_K', 'mighty_diamond_K', 'mighty_club_4', 'mighty_heart_7'],
    p4: ['mighty_club_Q', 'mighty_heart_Q', 'mighty_diamond_2', 'mighty_club_6', 'mighty_heart_8'],
  };
  g.tricks = [{
    leader: 'p0', leadSuit: 'diamond', winner: 'p2',
    cards: [
      { pid: 'p0', cardId: 'mighty_diamond_4' },
      { pid: 'p1', cardId: 'mighty_diamond_3' },
      { pid: 'p2', cardId: 'mighty_diamond_Q' },
      { pid: 'p3', cardId: 'mighty_diamond_6' },
      { pid: 'p4', cardId: 'mighty_diamond_7' },
    ],
  }];
  return g;
}

const MIGHTY = 'mighty_spade_A';

// ── 돌려줄 다이아가 있으면 마이티를 아낀다 ──
{
  const g = position({
    friendHand: [MIGHTY, 'mighty_diamond_9', 'mighty_club_9', 'mighty_heart_9', 'mighty_club_2'],
  });
  const card = mixoracle.decide(g, 'p2')?.cardId;
  check('주공이 깐 무늬를 돌려준다', card === 'mighty_diamond_9', `낸 카드 ${card}`);
  check('마이티를 혼자 던지지 않는다', card !== MIGHTY, `낸 카드 ${card}`);
}

// ── 돌려줄 게 없으면 마이티로라도 선을 잡는다 ──
{
  const g = position({
    friendHand: [MIGHTY, 'mighty_club_9', 'mighty_club_8', 'mighty_heart_9', 'mighty_club_2'],
  });
  const card = mixoracle.decide(g, 'p2')?.cardId;
  check('돌려줄 무늬가 없으면 아끼지 않는다', card === MIGHTY, `낸 카드 ${card}`);
}

// ── 이미 공개된 뒤라면 예전대로 ──
{
  const g = position({
    friendHand: [MIGHTY, 'mighty_diamond_9', 'mighty_club_9', 'mighty_heart_9', 'mighty_club_2'],
    revealed: true,
  });
  const card = mixoracle.decide(g, 'p2')?.cardId;
  check('공개 후에는 동작이 그대로다', card === MIGHTY, `낸 카드 ${card}`);
}

console.log(fail === 0 ? '\nPASS' : `\n${fail} FAILURE(S)`);
process.exit(fail === 0 ? 0 : 1);
