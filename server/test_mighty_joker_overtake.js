'use strict';
/**
 * 주공이 조커를 미리 터는 룰은 프렌드가 사람일 때만이다.
 *
 * 실제로 나온 판: 봇 프렌드가 기루다 A 로 첫구를 냈는데 주공(봇)이 조커로
 * 덮었다. 트릭은 어차피 우리 것이었으니 늘어난 트릭은 0이고, 조커는 나중에
 * "우리가 질 트릭" 하나를 가져올 수 있었던 카드다.
 *
 * 원인은 declarerSpendJokerBeforeFriendLead 룰이다. "프렌즈가 조커콜 카드를
 * 들고 있으면 선을 넘기기 전에 조커를 털어라" — 지키려는 사고는 "같은 편
 * 조커가 어디 있는지 모르는 **사람**이 야당을 노려 조커콜을 쏜다" 인데,
 * 프렌드가 봇일 때도 걸렸다. 봇은 손패를 다 보므로 그런 수를 두지 않는다.
 * 지킬 사고가 없는 자리에 보험료만 낸 셈이다.
 *
 * 이 테스트가 지키는 것:
 *   - 프렌드가 봇이다          → 안 낸다 (리포트 상황)
 *   - 프렌드가 사람이다        → 낸다 (룰의 원래 목적, fix13 과 같은 뜻)
 *   - 조커를 내도 마이티에 잡힌다 → 안 낸다
 *
 *   node test_mighty_joker_overtake.js
 */
process.env.MIGHTY_SOLVE_CARDS = '3';
process.env.MIGHTY_SOLVE_MS = '600000';

const MightyGame = require('./game/mighty/MightyGame');
const { makeRng } = require('./game/mighty/MightyDeck');
const mixoracle = require('./game/mighty/strategies/mixoracle');

// p2 가 프렌드다. 그 자리만 봇/사람으로 갈아 끼운다 — 봇 좌석 id 는
// `bot_N` 이고, 엔진은 그 규칙으로 봇을 판별한다.
const FRIEND_HUMAN = 'p2';
const FRIEND_BOT = 'bot_2';
let pass = 0, fail = 0;
const check = (name, cond, detail = '') => {
  if (cond) { pass++; console.log(`  ok   ${name}`); }
  else { fail++; console.log(`  FAIL ${name}${detail ? ` — ${detail}` : ''}`); }
};

const JOKER = 'mighty_joker';
const MIGHTY = 'mighty_spade_A';      // 기루다가 스페이드가 아닐 때의 마이티
const JOKER_CALL = 'mighty_club_3';   // 기루다가 클로버가 아니면 ♣3

/**
 * 기루다 다이아. 프렌드(p2)가 ♦A 로 첫구를 냈고 주공(p0)이 따라낼 차례.
 *
 * 프렌즈가 조커콜 카드를 들고 있어야 룰이 걸리므로 p2 손에 ♣3 을 쥐어 준다.
 * [mightyHolder] 로 마이티를 누구에게 줄지 정한다 — 야당이 들고 있으면
 * 프렌드의 ♦A 가 안전하지 않다.
 */
function position({ mightyHolder, friendIsBot = false }) {
  const FRIEND = friendIsBot ? FRIEND_BOT : FRIEND_HUMAN;
  const IDS = ['p0', 'p1', FRIEND, 'p3', 'p4'];
  const names = {};
  IDS.forEach(p => (names[p] = p));
  const g = new MightyGame(IDS, names, { targetScore: 50, rng: makeRng(7) });
  g.state = 'playing';
  g.trumpSuit = 'diamond';
  g.declarer = 'p0';
  g.friendCard = 'mighty_heart_A';
  g.friendRevealed = true;
  g.partner = FRIEND;
  g.jokerCallActive = true;

  const hands = {
    // 주공: 조커 + 잡패. 조커 말고는 ♦A 를 넘을 카드가 없다.
    p0: [JOKER, 'mighty_diamond_5', 'mighty_club_6', 'mighty_heart_6'],
    p1: ['mighty_club_7', 'mighty_club_8', 'mighty_heart_7', 'mighty_spade_7'],
    // 프렌드: 조커콜 카드를 들고 있다 (룰이 걸리는 조건)
    [FRIEND]: [JOKER_CALL, 'mighty_club_9', 'mighty_heart_9'],
    p3: ['mighty_club_T', 'mighty_heart_T', 'mighty_spade_T', 'mighty_club_2'],
    p4: ['mighty_club_J', 'mighty_heart_J', 'mighty_spade_J', 'mighty_club_4'],
  };
  const mightySeat = mightyHolder === 'friend' ? FRIEND : mightyHolder;
  hands[mightySeat] = [MIGHTY, ...hands[mightySeat]].slice(0, 4);
  g.hands = hands;

  // 프렌드가 기루다 A 로 첫구
  g.currentTrick = [{ pid: FRIEND, cardId: 'mighty_diamond_A' }];
  g.leadSuit = 'diamond';
  g.currentPlayer = 'p0';
  // 1트릭이 아니어야 한다. 첫 트릭의 조커는 힘이 없어서
  // (_currentTrickJokerHasPower) 룰이 아예 걸리지 않고, 그러면 이 테스트는
  // 조커를 안 냈다는 사실만 보고 통과해 버린다 — 아무것도 안 지키는 채로.
  g.tricks = [{
    leader: 'p1', leadSuit: 'spade', winner: 'p4',
    cards: [
      { pid: 'p1', cardId: 'mighty_spade_2' },
      { pid: FRIEND, cardId: 'mighty_spade_5' },
      { pid: 'p3', cardId: 'mighty_spade_6' },
      { pid: 'p4', cardId: 'mighty_spade_K' },
      { pid: 'p0', cardId: 'mighty_spade_4' },
    ],
  }];
  return g;
}

console.log('봇 프렌드가 기루다 A 로 첫구를 냈을 때 (리포트 상황)');
{
  const g = position({ mightyHolder: 'friend', friendIsBot: true });
  const card = mixoracle.decide(g, 'p0')?.cardId;
  check('봇 프렌드에게는 조커를 미리 털지 않는다', card !== JOKER, `낸 카드 ${card}`);
}

console.log('\n사람 프렌드일 때는 룰이 그대로 산다');
{
  const g = position({ mightyHolder: 'friend', friendIsBot: false });
  const card = mixoracle.decide(g, 'p0')?.cardId;
  check('사람 프렌드에게는 조커를 미리 턴다', card === JOKER, `낸 카드 ${card}`);
}
{
  // 야당(p3)이 마이티를 들고 있다 → 조커를 내도 잡힌다.
  // 트릭도 못 지키고 조커만 없어지는 수는 두지 않아야 한다.
  const g = position({ mightyHolder: 'p3', friendIsBot: false });
  const card = mixoracle.decide(g, 'p0')?.cardId;
  check('뒤에 마이티가 있으면 조커를 버리지 않는다', card !== JOKER, `낸 카드 ${card}`);
}

console.log(fail === 0 ? '\nPASS' : `\n${fail} FAILURE(S)`);
process.exit(fail === 0 ? 0 : 1);
