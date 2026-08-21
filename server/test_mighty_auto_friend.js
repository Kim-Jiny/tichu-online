'use strict';
/**
 * 주공이 자리를 비웠을 때 대신 고르는 친구 카드.
 *
 * 리포트: 비딩·친구지목 단계에서 잠수를 타면 노프렌즈가 됐다. 노프렌즈는
 * "혼자 다 감당하겠다" 는 선언이라 목표 점수가 올라간다. 자리를 비웠다는
 * 이유로 그 계약을 떠안으면 그 판은 대체로 진다 — 잠수한 사람만 손해가
 * 아니라 같은 편이 될 사람도, 남은 넷의 한 판도 같이 버려진다.
 *
 * 원인은 시간 초과 기본값이었다.
 *   const friendCard = hand.includes(mighty) ? 'no_friend' : mighty;
 * 마이티를 손에 들고 있으면 그 자리에서 노프렌즈. 강한 손일수록(마이티+조커)
 * 확실히 그렇게 됐다.
 *
 *   node test_mighty_auto_friend.js
 */
const MightyGame = require('./game/mighty/MightyGame');
const { makeRng } = require('./game/mighty/MightyDeck');

const IDS = ['p0', 'p1', 'p2', 'p3', 'p4'];
let pass = 0, fail = 0;
const check = (name, cond, detail = '') => {
  if (cond) { pass++; console.log(`  ok   ${name}`); }
  else { fail++; console.log(`  FAIL ${name}${detail ? ` — ${detail}` : ''}`); }
};

function game({ trumpSuit = 'diamond' } = {}) {
  const names = {};
  IDS.forEach(p => (names[p] = p));
  const g = new MightyGame(IDS, names, { targetScore: 50, rng: makeRng(3) });
  g.declarer = 'p0';
  g.trumpSuit = trumpSuit;
  return g;
}

const MIGHTY = 'mighty_spade_A';   // 기루다가 스페이드가 아닐 때
const JOKER = 'mighty_joker';

console.log('손에 없는 카드 중 강한 것부터 부른다');
{
  const g = game();
  check('마이티가 손에 없으면 마이티',
    g._autoFriendCard(['mighty_club_5', 'mighty_heart_7']) === MIGHTY);
}
{
  const g = game();
  check('마이티를 들고 있으면 조커',
    g._autoFriendCard([MIGHTY, 'mighty_club_5']) === JOKER);
}
{
  const g = game();
  // 리포트 상황: 마이티도 조커도 손에 있다. 예전에는 여기서 노프렌즈였다.
  const got = g._autoFriendCard([MIGHTY, JOKER, 'mighty_club_5']);
  check('마이티·조커를 다 들고 있어도 노프렌즈가 아니다', got !== 'no_friend', `골른 것 ${got}`);
  check('그때는 기루다 A 를 부른다', got === 'mighty_diamond_A', `골른 것 ${got}`);
}
{
  const g = game();
  const got = g._autoFriendCard([MIGHTY, JOKER, 'mighty_diamond_A', 'mighty_diamond_K']);
  check('기루다 위쪽도 들고 있으면 그다음 기루다', got === 'mighty_diamond_Q', `골른 것 ${got}`);
}
{
  const g = game({ trumpSuit: 'no_trump' });
  const got = g._autoFriendCard([MIGHTY, JOKER]);
  check('노기루다면 무늬 A 로 내려간다', got === 'mighty_spade_A' || /_(A|K)$/.test(got),
    `골른 것 ${got}`);
}

console.log('\n부를 수 있는 카드가 없을 때만 노프렌즈');
{
  const g = game();
  // 후보를 전부 손에 들고 있는 (현실에 없는) 손패
  const all = [MIGHTY, JOKER];
  for (const r of ['A', 'K', 'Q', 'J', '10']) all.push(`mighty_diamond_${r}`);
  for (const s of ['spade', 'diamond', 'heart', 'club']) {
    for (const r of ['A', 'K']) all.push(`mighty_${s}_${r}`);
  }
  check('후보가 전부 손에 있으면 노프렌즈', g._autoFriendCard(all) === 'no_friend');
}

console.log('\n실제 시간 초과 경로');
{
  const g = game();
  g.state = 'kitty_exchange';
  g.hands.p0 = [MIGHTY, JOKER, 'mighty_club_5', 'mighty_club_6', 'mighty_club_7',
    'mighty_heart_2', 'mighty_heart_3', 'mighty_heart_4', 'mighty_spade_2',
    'mighty_spade_3', 'mighty_spade_4', 'mighty_spade_5', 'mighty_spade_6'];
  const action = g.getAutoTimeoutAction('p0');
  check('discard_kitty 를 돌려준다', action && action.type === 'discard_kitty');
  check('친구가 설정된다', action && action.friendCard !== 'no_friend',
    `friendCard=${action && action.friendCard}`);
  check('버릴 카드에 친구 카드가 없다',
    action && !action.discards.includes(action.friendCard));
  check('마이티·조커는 안 버린다',
    action && !action.discards.includes(MIGHTY) && !action.discards.includes(JOKER));
}

console.log(fail === 0 ? '\nPASS' : `\n${fail} FAILURE(S)`);
process.exit(fail === 0 ? 0 : 1);
