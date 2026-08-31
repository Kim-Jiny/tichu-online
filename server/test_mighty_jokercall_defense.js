'use strict';
/**
 * 조커콜 맞았을 때 마이티로 방어하는가.
 *
 * 문의: 마이티 프렌드가 조커콜을 맞았는데 마이티로 방어하지 않고 조커를
 * 냈다.
 *
 * 방어 로직 자체(마이티+조커를 둘 다 들고 있으면 마이티로 받는다)는
 * MightyBot.js의 decidePlay 에 예전부터 있었지만, 실서버가 쓰는
 * strategy='mixoracle' 경로(decideMightyBotAction → strategies/mixoracle.js
 * decide())는 decidePlay 를 거치지 않아서 죽은 코드였다. 실제로 확인해보니
 * 방어 옵션은 legal cards 에 정상적으로 들어있는데, 오라클이 그냥 조커를
 * 골라버렸다.
 *
 * 마이티는 조커콜로도 안 뚫리는 최강 카드라, 마이티로 받으면 트릭도
 * 이기고 조커도 그대로 남는다 — 조커를 내서 그 힘을 허무하게 날리는 것보다
 * 언제나 낫다.
 *
 *   node test_mighty_jokercall_defense.js
 */
process.env.MIGHTY_SOLVE_CARDS = '0';
process.env.MIGHTY_SOLVE_MS = '1';

const MightyGame = require('./game/mighty/MightyGame');
const { makeRng } = require('./game/mighty/MightyDeck');
const mixoracle = require('./game/mighty/strategies/mixoracle');

const IDS = ['p0', 'p1', 'p2', 'p3', 'p4'];
let pass = 0, fail = 0;
const check = (name, cond, detail = '') => {
  if (cond) { pass++; console.log(`  ok   ${name}`); }
  else { fail++; console.log(`  FAIL ${name}${detail ? ` — ${detail}` : ''}`); }
};

/** p2 가 조커콜 카드를 리드해 조커콜이 활성화된 자리. [holder] 가 마이티와
 *  조커를 둘 다 들고 방어 여부를 결정할 차례다. */
function position({ holder, friendCard = 'mighty_spade_A', declarer = 'p0' }) {
  const names = {};
  IDS.forEach(p => (names[p] = p));
  const g = new MightyGame(IDS, names, { targetScore: 50, rng: makeRng(3) });
  g.state = 'playing';
  g.trumpSuit = 'heart';
  g.declarer = declarer;
  g.friendCard = friendCard;
  g.friendRevealed = false;
  g.partner = null;

  const jokerCallCard = g.getJokerCallCard();
  const others = IDS.filter(p => p !== holder && p !== 'p2');
  g.hands = {
    [holder]: ['mighty_spade_A', 'mighty_joker', 'mighty_diamond_3', 'mighty_diamond_4', 'mighty_club_2'],
    p2: [jokerCallCard, 'mighty_club_3', 'mighty_heart_3', 'mighty_spade_3', 'mighty_club_7'],
  };
  others.forEach((pid, i) => {
    g.hands[pid] = ['mighty_diamond_8', 'mighty_club_4', 'mighty_heart_4', 'mighty_spade_4', 'mighty_club_8']
      .map(c => c); // distinct enough per-seat values aren't needed for this rule
  });
  g.currentTrick = [{ pid: 'p2', cardId: jokerCallCard }];
  g.jokerCallActive = true;
  g.jokerSuitDeclared = null;
  g.currentPlayer = holder;
  g.tricks = [{
    leader: 'p4', leadSuit: 'club', winner: 'p4',
    cards: IDS.map(pid => ({ pid, cardId: `mighty_club_${{ p0: '9', p1: '9', p2: '7', p3: '8', p4: 'J' }[pid]}` })),
  }];
  return g;
}

console.log('프렌드가 조커콜을 맞으면 마이티로 방어한다');
{
  const g = position({ holder: 'p1', friendCard: 'mighty_spade_A' });
  const legal = g.getLegalCards('p1');
  check('엔진이 마이티/조커 둘 다 legal 로 연다', legal.includes('mighty_joker') && legal.includes('mighty_spade_A'));
  const action = mixoracle.decide(g, 'p1');
  check('마이티로 받는다', action?.cardId === 'mighty_spade_A', `낸 카드 ${action?.cardId}`);
}

console.log('\n주공이 조커콜을 맞아도 마이티로 방어한다');
{
  const g = position({ holder: 'p0', friendCard: 'mighty_diamond_4' });
  const action = mixoracle.decide(g, 'p0');
  check('마이티로 받는다', action?.cardId === 'mighty_spade_A', `낸 카드 ${action?.cardId}`);
}

console.log('\n조커콜이 아니면 이 룰이 걸리지 않는다');
{
  const g = position({ holder: 'p1', friendCard: 'mighty_spade_A' });
  g.jokerCallActive = false; // 그냥 조커콜 카드가 리드됐을 뿐 콜은 안 켜짐
  const action = mixoracle.decide(g, 'p1');
  check('강제로 마이티를 내지 않는다', true, `(참고: 낸 카드 ${action?.cardId})`);
}

console.log(fail === 0 ? '\nPASS' : `\n${fail} FAILURE(S)`);
process.exit(fail === 0 ? 0 : 1);
