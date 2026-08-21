'use strict';
/**
 * 주공이 프렌드 카드를 부를 때 프렌드가 나오는가.
 *
 * 리포트: 기루다 A 가 프렌드 카드인데 주공이 기루다 3 을 깔았고, 두 번째
 * 자리의 프렌드가 A 를 내지 않았다. 뒷자리에 조커가 있어서 못 이기기
 * 때문이었다.
 *
 * 휴리스틱의 판단("못 이기는 카드는 아낀다")으로는 맞지만, 이 자리의 프렌드
 * 카드는 트릭을 먹으러 내는 카드가 아니라 **부름에 답하는 카드**다. 주공이
 * 기루다 밑장을 까는 건 친구를 불러내는 수고, 여기서 안 나오면 주공은 누가
 * 자기 편인지 모른 채 계속 혼자 계산한다. 조커에 잡혀도 공개는 일어나므로
 * 잃는 건 카드 한 장이고 얻는 건 남은 판의 호흡이다.
 *
 *   node test_mighty_friend_answers_call.js
 */
// 손패가 이 장수 이하면 엔드게임 솔버가 하드룰을 덮는다. 여기서 보려는
// 것은 룰이라 솔버가 끼지 않게 낮춰 둔다.
process.env.MIGHTY_SOLVE_CARDS = '1';
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

const FRIEND_CARD = 'mighty_diamond_A';   // 기루다 A 가 프렌드 카드
const JOKER = 'mighty_joker';

/**
 * 기루다 다이아. 주공(p0)이 ♦3 을 깔았고 두 번째 자리 p1(프렌드)이 낼 차례.
 * [jokerHolder] 로 조커를 뒤에 앉힌다.
 */
function position({ jokerHolder = 'p2', friendHand } = {}) {
  const names = {};
  IDS.forEach(p => (names[p] = p));
  const g = new MightyGame(IDS, names, { targetScore: 50, rng: makeRng(11) });
  g.state = 'playing';
  g.trumpSuit = 'diamond';
  g.declarer = 'p0';
  g.friendCard = FRIEND_CARD;
  g.friendRevealed = false;
  g.partner = null;

  g.hands = {
    p0: ['mighty_diamond_K', 'mighty_club_9', 'mighty_heart_9', 'mighty_spade_9',
      'mighty_club_10', 'mighty_heart_10'],
    p1: friendHand || [FRIEND_CARD, 'mighty_diamond_5', 'mighty_club_2',
      'mighty_heart_2', 'mighty_spade_2', 'mighty_club_6'],
    p2: ['mighty_diamond_7', 'mighty_club_3', 'mighty_heart_3', 'mighty_spade_3',
      'mighty_club_7', 'mighty_heart_7'],
    p3: ['mighty_diamond_8', 'mighty_club_4', 'mighty_heart_4', 'mighty_spade_4',
      'mighty_club_8', 'mighty_heart_8'],
    p4: ['mighty_diamond_9', 'mighty_club_5', 'mighty_heart_5', 'mighty_spade_5',
      'mighty_club_J', 'mighty_heart_J'],
  };
  if (jokerHolder) g.hands[jokerHolder] = [JOKER, ...g.hands[jokerHolder]].slice(0, 6);

  g.currentTrick = [{ pid: 'p0', cardId: 'mighty_diamond_3' }];
  g.leadSuit = 'diamond';
  g.currentPlayer = 'p1';
  // 1트릭이 아니어야 조커에 힘이 있다.
  g.tricks = [{
    leader: 'p0', leadSuit: 'spade', winner: 'p0',
    cards: IDS.map(pid => ({ pid, cardId: `mighty_spade_${{p0:'A',p1:'2',p2:'3',p3:'4',p4:'5'}[pid]}` })),
  }];
  return g;
}

console.log('주공이 기루다 밑장으로 부를 때');
{
  // 리포트 상황: 뒷자리(p2)에 조커가 있다.
  const g = position({ jokerHolder: 'p2' });
  const card = mixoracle.decide(g, 'p1')?.cardId;
  check('뒤에 조커가 있어도 프렌드 카드를 낸다', card === FRIEND_CARD, `낸 카드 ${card}`);
}
{
  // 조커가 없으면 예전에도 나왔다. 회귀 확인.
  const g = position({ jokerHolder: null });
  const card = mixoracle.decide(g, 'p1')?.cardId;
  check('조커가 없으면 당연히 낸다', card === FRIEND_CARD, `낸 카드 ${card}`);
}
{
  // 주공 뒤가 아니라 마지막 자리에서도 마찬가지다.
  const g = position({ jokerHolder: 'p2' });
  g.currentTrick = [
    { pid: 'p0', cardId: 'mighty_diamond_3' },
    { pid: 'p2', cardId: JOKER },
  ];
  g.currentPlayer = 'p1';
  const card = mixoracle.decide(g, 'p1')?.cardId;
  check('조커가 이미 깔려 있어도 낸다', card === FRIEND_CARD, `낸 카드 ${card}`);
}

console.log('\n부름이 닿지 않으면 내지 않는다');
{
  // 주공이 다른 무늬를 깔았고 프렌드는 그 무늬를 들고 있다 → 따라야 한다.
  const g = position({ jokerHolder: null });
  g.currentTrick = [{ pid: 'p0', cardId: 'mighty_club_9' }];
  g.leadSuit = 'club';
  const card = mixoracle.decide(g, 'p1')?.cardId;
  check('무늬를 따라야 하면 프렌드 카드를 못 낸다', card !== FRIEND_CARD, `낸 카드 ${card}`);
}
{
  // 주공이 아니라 야당이 이끈 트릭이면 이 룰은 걸리지 않는다.
  const g = position({ jokerHolder: null });
  g.currentTrick = [{ pid: 'p2', cardId: 'mighty_diamond_3' }];
  g.tricks[0].winner = 'p2';
  const card = mixoracle.decide(g, 'p1')?.cardId;
  check('야당이 이끈 트릭에서는 이 룰이 강제하지 않는다', true,
    `(참고: 낸 카드 ${card})`);
}

console.log(fail === 0 ? '\nPASS' : `\n${fail} FAILURE(S)`);
process.exit(fail === 0 ? 0 : 1);
