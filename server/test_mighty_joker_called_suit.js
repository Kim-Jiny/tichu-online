'use strict';
/**
 * 조커 프렌드에서 조커를 리드할 때 부른 무늬를 아는가.
 *
 * 리포트: 조커 프렌드 판에서 프렌드 봇이 조커를 리드할 때, 이길 수 있는
 * 무늬면 그건 맞는데 이길 수 없는 상황에서도 주공이 조커를 불러낸 무늬가
 * 아닌 다른 무늬를 불러버렸다.
 *
 * _pickJokerLeadSuit 은 무늬별로 "이어서 이길 수 있는가"만 채점했고, 주공이
 * 조커를 끌어내려고 리드했던 무늬(부른 무늬)는 아예 몰랐다. 그래서 이어서
 * 이길 수 있는 무늬가 하나도 없으면 상대 보유/장수 같은 부차 기준으로
 * 사실상 아무 무늬나 골랐다.
 *
 *   node test_mighty_joker_called_suit.js
 */
process.env.MIGHTY_SOLVE_CARDS = '0';
process.env.MIGHTY_SOLVE_MS = '1';

const MightyGame = require('./game/mighty/MightyGame');
const { makeRng } = require('./game/mighty/MightyDeck');
const MightyBot = require('./game/mighty/MightyBot');

const IDS = ['p0', 'p1', 'p2', 'p3', 'p4'];
let pass = 0, fail = 0;
const check = (name, cond, detail = '') => {
  if (cond) { pass++; console.log(`  ok   ${name}`); }
  else { fail++; console.log(`  FAIL ${name}${detail ? ` — ${detail}` : ''}`); }
};

/** 트럼프(♠) 판, 조커 프렌드. 주공(p0)이 트릭0을 [calledSuit] 로 깔았고
 *  프렌드(p1)가 조커로 받아 이미 공개된 자리. 트릭1 선을 프렌드가 잡는다. */
function position({ friendHand, calledSuit = 'club' }) {
  const names = {};
  IDS.forEach(p => (names[p] = p));
  const g = new MightyGame(IDS, names, { targetScore: 50, rng: makeRng(7) });
  g.state = 'playing';
  g.trumpSuit = 'spade';
  g.declarer = 'p0';
  g.friendCard = 'mighty_joker';
  g.friendRevealed = true;
  g.partner = 'p1';
  g.currentTrick = [];
  g.currentPlayer = 'p1';
  g.hands = {
    p0: ['mighty_diamond_K', 'mighty_diamond_Q', 'mighty_heart_9', 'mighty_heart_8', 'mighty_club_9'],
    p1: friendHand,
    p2: ['mighty_diamond_7', 'mighty_club_3', 'mighty_heart_3', 'mighty_spade_3', 'mighty_club_7'],
    p3: ['mighty_diamond_8', 'mighty_club_4', 'mighty_heart_4', 'mighty_spade_4', 'mighty_club_8'],
    p4: ['mighty_diamond_9', 'mighty_club_5', 'mighty_heart_5', 'mighty_spade_5', 'mighty_club_J'],
  };
  g.tricks = [{
    leader: 'p0', leadSuit: calledSuit, winner: 'p1',
    cards: [
      { pid: 'p0', cardId: `mighty_${calledSuit}_2` },
      { pid: 'p1', cardId: 'mighty_joker' },
      { pid: 'p2', cardId: `mighty_${calledSuit}_6` },
      { pid: 'p3', cardId: `mighty_${calledSuit}_4` },
      { pid: 'p4', cardId: `mighty_${calledSuit}_A` },
    ],
  }];
  return g;
}

console.log('이길 수 있는 무늬가 없으면 부른 무늬로 돌려준다');
{
  // 클럽(부른 무늬)도, 하트도, 다이아도, 스페이드(기루다)도 전부 이어서
  // 이길 top/second-top 이 없다. 신호로 부른 무늬(클럽)를 불러야 한다.
  const g = position({
    friendHand: ['mighty_joker', 'mighty_club_2', 'mighty_heart_2', 'mighty_diamond_3', 'mighty_spade_2'],
    calledSuit: 'club',
  });
  const action = MightyBot.makePlayAction('mighty_joker', g, 'p1');
  check('이길 수 없을 때 부른 무늬(club)를 부른다', action.jokerSuit === 'club', `불린 무늬 ${action.jokerSuit}`);
}

console.log('\n진짜 이길 수 있는 무늬가 있으면 그게 여전히 우선한다');
{
  // 하트 A/K 를 들고 있어 하트가 확실한 continuation. 부른 무늬(클럽)는
  // 약하다 — 하트를 불러야 한다.
  const g = position({
    friendHand: ['mighty_joker', 'mighty_club_2', 'mighty_heart_A', 'mighty_heart_K', 'mighty_diamond_3'],
    calledSuit: 'club',
  });
  const action = MightyBot.makePlayAction('mighty_joker', g, 'p1');
  check('이길 수 있는 무늬(heart)가 부른 무늬보다 우선한다', action.jokerSuit === 'heart', `불린 무늬 ${action.jokerSuit}`);
}

console.log('\n상대가 하나도 안 든 무늬는 부른 무늬라도 피한다');
{
  // 부른 무늬(다이아)를 상대(p2~p4 중 야당)가 전혀 안 들고 있으면, 그건
  // 그냥 상대에게 공짜 버림패를 주는 꼴이라 여전히 배제돼야 한다.
  const g = position({
    friendHand: ['mighty_joker', 'mighty_diamond_2', 'mighty_heart_2', 'mighty_club_2', 'mighty_spade_2'],
    calledSuit: 'diamond',
  });
  // 야당(p2,p3,p4) 전원의 다이아를 다른 무늬로 바꿔 "다이아는 야당이 하나도
  // 안 든" 상황을 만든다.
  g.hands.p2 = ['mighty_heart_3', 'mighty_club_3', 'mighty_spade_3', 'mighty_club_7'];
  g.hands.p3 = ['mighty_heart_4', 'mighty_club_4', 'mighty_spade_4', 'mighty_club_8'];
  g.hands.p4 = ['mighty_heart_5', 'mighty_club_5', 'mighty_spade_5', 'mighty_club_J'];
  const action = MightyBot.makePlayAction('mighty_joker', g, 'p1');
  check('부른 무늬라도 상대가 안 든 무늬면 안 부른다', action.jokerSuit !== 'diamond', `불린 무늬 ${action.jokerSuit}`);
}

console.log(fail === 0 ? '\nPASS' : `\n${fail} FAILURE(S)`);
process.exit(fail === 0 ? 0 : 1);
