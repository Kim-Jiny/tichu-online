'use strict';
// 스컬킹 해적 능력 모드: 5명의 능력(Rosie/Bendt/Rascal/Juanita/Harry)과 예외, 봇·타임아웃 기본값.
//   node test_sk_pirate_abilities.js
const SK = require('./game/skull_king/SkullKingGame');
const { decideSKBotAction } = require('./game/skull_king/SkullKingBot');
const { createDeck } = require('./game/skull_king/SkullKingDeck');
const ids = ['a', 'b', 'c'];
const names = { a: 'a', b: 'b', c: 'c' };
let ok = true;
const chk = (n, c) => { console.log(c ? '  ok  ' : '  FAIL', n); if (!c) ok = false; };

// 라운드 3, 각자 손패와 입찰을 직접 심은 판. a 가 먼저 낸다.
function mk(expansions = ['pirate_abilities'], hands, bids) {
  const g = new SK(ids, names, { expansions });
  g.round = 3; g.trickNumber = 1; g.state = 'playing';
  g.hands = hands || { a: ['sk_pirate_2', 'sk_yellow_1', 'sk_green_2'], b: ['sk_yellow_5', 'sk_green_3', 'sk_purple_3'], c: ['sk_yellow_6', 'sk_green_4', 'sk_purple_4'] };
  g.bids = bids || { a: 1, b: 1, c: 1 };
  g.tricks = { a: 0, b: 0, c: 0 }; g.bonuses = { a: 0, b: 0, c: 0 };
  g.totalScores = { a: 0, b: 0, c: 0 };
  g.currentTrick = []; g.trickStarter = 'a'; g.currentPlayer = 'a';
  g.undealt = ['sk_black_1', 'sk_black_2', 'sk_black_3', 'sk_black_4'];
  return g;
}
const play = (g, p, c, t) => g.handleAction(p, { type: 'play_card', cardId: c, tigressChoice: t });
// a 가 pirate 로 시작해 이기게 하고 결과 대기(능력 시작)까지 진행
function aWins(g, pirateId) {
  play(g, 'a', pirateId); play(g, 'b', g.hands.b[0]); play(g, 'c', g.hands.c[0]);
  g.advanceAfterTrickEnd();
}

console.log('덱');
// 5번째 해적(후아니타)의 그림은 3.3.0 번들에서 처음 들어갔다. 일반 방에도
// 넣으면 버전 게이트가 능력 모드만 막으므로, 3.2.0 앱이 일반 스컬킹 방에서
// 없는 에셋을 찾다 카드 자리에 색칠된 사각형을 띄운다 — 기존 유저 전체에게.
// 그래서 5번째는 능력 모드에만 있고, 그 모드는 게이트가 이미 막는다.
chk('기본 덱은 해적 4장',
  createDeck([]).filter((c) => c.type === 'pirate').length === 4);
chk('능력 모드는 해적 5장',
  createDeck(['pirate_abilities']).filter((c) => c.type === 'pirate').length === 5);
chk('5번째 해적은 능력 모드에만 있다',
  !createDeck([]).some((c) => c.id === 'sk_pirate_5')
  && createDeck(['pirate_abilities']).some((c) => c.id === 'sk_pirate_5'));
// 다른 확장팩을 켜도 5번째가 따라 들어오면 안 된다.
chk('다른 확장팩은 해적 수를 바꾸지 않는다',
  createDeck(['kraken', 'white_whale', 'loot'])
    .filter((c) => c.type === 'pirate').length === 4);

console.log('모드 꺼짐/능력 없는 승리');
let g = mk([]); aWins(g, 'sk_pirate_2');
chk('모드가 꺼져 있으면 능력 없이 다음 트릭', g.state === 'playing' && !g.pendingAbility);
g = mk(['pirate_abilities'], { a: ['sk_tigress_1', 'sk_yellow_1', 'sk_green_2'], b: ['sk_yellow_5', 'sk_green_3', 'sk_purple_3'], c: ['sk_yellow_6', 'sk_green_4', 'sk_purple_4'] });
play(g, 'a', 'sk_tigress_1', 'pirate'); play(g, 'b', 'sk_yellow_5'); play(g, 'c', 'sk_yellow_6'); g.advanceAfterTrickEnd();
chk('티그리스로 낸 해적은 능력이 없다', g.state === 'playing' && !g.pendingAbility);
g = mk(['pirate_abilities'], { a: ['sk_pirate_2', 'sk_yellow_1', 'sk_green_2'], b: ['sk_skull_king', 'sk_green_3', 'sk_purple_3'], c: ['sk_yellow_6', 'sk_green_4', 'sk_purple_4'] });
play(g, 'a', 'sk_pirate_2'); play(g, 'b', 'sk_skull_king'); play(g, 'c', 'sk_yellow_6'); g.advanceAfterTrickEnd();
chk('스컬킹이 이기면 해적 능력 없음', g.state === 'playing' && !g.pendingAbility);

console.log('Rosie');
g = mk(); aWins(g, 'sk_pirate_2');
chk('트릭 뒤 pirate_ability 로 넘어간다', g.state === 'pirate_ability' && g.pendingAbility.pirate === 'rosie' && g.getPendingActor() === 'a');
let st = g.getStateForPlayer('a');
chk('내 능력 차례에 카드 낼 차례(isMyTurn)는 아님', st.isMyTurn === false && st.legalCards.length === 0 && st.pendingAbility.pirate === 'rosie');
chk('다른 사람은 해적 능력을 못 쓴다', !g.handleAction('b', { type: 'use_pirate_ability', leaderId: 'b' }).success);
chk('없는 사람을 지목하면 거절', !g.handleAction('a', { type: 'use_pirate_ability', leaderId: 'zzz' }).success);
chk('c 를 지목', g.handleAction('a', { type: 'use_pirate_ability', leaderId: 'c' }).success);
chk('다음 트릭은 c 가 선', g.state === 'playing' && g.currentPlayer === 'c' && g.trickStarter === 'c');
chk('알림 정보가 남는다', g.lastAbility.pirate === 'rosie' && g.lastAbility.targetId === 'c' && g.abilitySeq === 1);
play(g, 'c', 'sk_yellow_6'); play(g, 'a', 'sk_yellow_1'); play(g, 'b', 'sk_yellow_5'); g.advanceAfterTrickEnd();
chk('지목은 한 번만 — 그다음은 이긴 사람', g.trickStarter === 'c' || g.trickStarter === 'b');

console.log('Bendt');
g = mk(['pirate_abilities'], { a: ['sk_pirate_3', 'sk_yellow_1', 'sk_green_2'], b: ['sk_yellow_5', 'sk_green_3', 'sk_purple_3'], c: ['sk_yellow_6', 'sk_green_4', 'sk_purple_4'] });
aWins(g, 'sk_pirate_3');
chk('2장을 뽑아 손이 4장이 된다', g.pendingAbility.pirate === 'bendt' && g.hands.a.length === 4 && g.pendingAbility.drawn.length === 2 && g.undealt.length === 2);
chk('내 상태에만 뽑은 카드가 보인다', g.getStateForPlayer('a').abilityInfo.drawn.every((x) => typeof x === 'string') && g.getStateForPlayer('a').abilityInfo.drawn.length === 2 && g.getStateForPlayer('b').abilityInfo === null);
chk('1장만 버리면 거절', !g.handleAction('a', { type: 'use_pirate_ability', discard: [g.hands.a[0]] }).success);
chk('손에 없는 카드는 거절', !g.handleAction('a', { type: 'use_pirate_ability', discard: ['sk_red_1', 'sk_red_2'] }).success);
const keep = g.hands.a.slice(0, 2);
chk('같은 카드 두 번은 거절', !g.handleAction('a', { type: 'use_pirate_ability', discard: [keep[0], keep[0]] }).success);
chk('2장 버리기', g.handleAction('a', { type: 'use_pirate_ability', discard: g.hands.a.slice(2) }).success && g.hands.a.length === 2 && g.state === 'playing');

console.log('Rascal');
g = mk(['pirate_abilities'], { a: ['sk_pirate_1', 'sk_yellow_1', 'sk_green_2'], b: ['sk_yellow_5', 'sk_green_3', 'sk_purple_3'], c: ['sk_yellow_6', 'sk_green_4', 'sk_purple_4'] });
aWins(g, 'sk_pirate_1');
chk('rascal 차례', g.pendingAbility.pirate === 'rascal');
chk('15점은 거절', !g.handleAction('a', { type: 'use_pirate_ability', wager: 15 }).success);
chk('20점 내기', g.handleAction('a', { type: 'use_pirate_ability', wager: 20 }).success && g.rascalWagers.a === 20);
// 입찰을 맞히면 +20, 못 맞히면 -20 (남은 두 트릭을 정리한 뒤 endRound)
function finish(g, tricksA) {
  g.tricks.a = tricksA; g.hands = { a: [], b: [], c: [] }; g.endRound();
}
let s1 = mk(['pirate_abilities']); s1.rascalWagers = { a: 20 }; s1.bids.a = 1; finish(s1, 1);
chk('맞히면 20*1 + 20', s1.lastRoundScores.a === 40);
let s2 = mk(['pirate_abilities']); s2.rascalWagers = { a: 20 }; s2.bids.a = 1; finish(s2, 2);
chk('틀리면 -10 - 20', s2.lastRoundScores.a === -30);
let s3 = mk(['pirate_abilities']); s3.bids.a = 1; finish(s3, 1);
chk('내기를 안 걸면 변화 없음', s3.lastRoundScores.a === 20);
chk('점수 기록에 내기 금액이 남는다', s1.scoreHistory[0].scores.a.wager === 20);

console.log('Juanita');
g = mk(['pirate_abilities'], { a: ['sk_pirate_5', 'sk_yellow_1', 'sk_green_2'], b: ['sk_yellow_5', 'sk_green_3', 'sk_purple_3'], c: ['sk_yellow_6', 'sk_green_4', 'sk_purple_4'] });
aWins(g, 'sk_pirate_5');
chk('juanita 는 나눠 주지 않은 카드를 본다(본인만)', g.pendingAbility.pirate === 'juanita'
  && g.getStateForPlayer('a').abilityInfo.undealt.length === 4 && g.getStateForPlayer('b').abilityInfo === null
  && g.getStateForSpectator().abilityInfo === undefined);
chk('확인하면 끝', g.handleAction('a', { type: 'use_pirate_ability' }).success && g.state === 'playing');

console.log('Harry');
g = mk(['pirate_abilities'], { a: ['sk_pirate_4'], b: ['sk_yellow_5'], c: ['sk_yellow_6'] }, { a: 2, b: 0, c: 0 });
g.round = 3; g.tricks.a = 2; // 이번 트릭까지 3승이 되어 입찰 2 를 넘긴다(마지막 트릭)
aWins(g, 'sk_pirate_4');
chk('마지막 트릭 뒤에도 harry 는 쓸 수 있다', g.state === 'pirate_ability' && g.pendingAbility.pirate === 'harry');
chk('범위를 벗어난 값은 거절', !g.handleAction('a', { type: 'use_pirate_ability', delta: 2 }).success);
chk('+1 로 입찰을 3 으로', g.handleAction('a', { type: 'use_pirate_ability', delta: 1 }).success && g.bids.a === 3);
chk('쓰고 나면 라운드가 끝나고 입찰 3 이 맞아 점수', g.state === 'round_end' && g.lastRoundScores.a === 60);
g = mk(['pirate_abilities'], { a: ['sk_pirate_4', 'sk_yellow_1', 'sk_green_2'], b: ['sk_yellow_5', 'sk_green_3', 'sk_purple_3'], c: ['sk_yellow_6', 'sk_green_4', 'sk_purple_4'] }, { a: 0, b: 1, c: 1 });
aWins(g, 'sk_pirate_4');
chk('입찰 0 에서 -1 은 거절', !g.handleAction('a', { type: 'use_pirate_ability', delta: -1 }).success);

console.log('마지막 트릭 뒤 다른 해적은 능력 없음');
for (const [n, id] of [['rosie', 'sk_pirate_2'], ['rascal', 'sk_pirate_1'], ['bendt', 'sk_pirate_3'], ['juanita', 'sk_pirate_5']]) {
  g = mk(['pirate_abilities'], { a: [id], b: ['sk_yellow_5'], c: ['sk_yellow_6'] });
  aWins(g, id);
  chk(`${n}: 라운드가 바로 끝난다`, g.state === 'round_end' && !g.pendingAbility);
}

console.log('더미가 모자라면 건너뜀');
g = mk(['pirate_abilities'], { a: ['sk_pirate_3', 'sk_yellow_1', 'sk_green_2'], b: ['sk_yellow_5', 'sk_green_3', 'sk_purple_3'], c: ['sk_yellow_6', 'sk_green_4', 'sk_purple_4'] });
g.undealt = [];
aWins(g, 'sk_pirate_3');
chk('bendt 는 더미가 비면 건너뜀', g.state === 'playing');

console.log('타임아웃 기본값 / 봇');
for (const [n, id] of [['rosie', 'sk_pirate_2'], ['bendt', 'sk_pirate_3'], ['rascal', 'sk_pirate_1'], ['juanita', 'sk_pirate_5'], ['harry', 'sk_pirate_4']]) {
  g = mk(['pirate_abilities'], { a: [id, 'sk_yellow_1', 'sk_green_2'], b: ['sk_yellow_5', 'sk_green_3', 'sk_purple_3'], c: ['sk_yellow_6', 'sk_green_4', 'sk_purple_4'] });
  aWins(g, id);
  const auto = g.getAutoTimeoutAction('a');
  const r = auto && g.handleAction('a', auto);
  chk(`${n}: 시간 초과 기본값이 유효`, !!(r && r.success) && g.state === 'playing');
  g = mk(['pirate_abilities'], { a: [id, 'sk_yellow_1', 'sk_green_2'], b: ['sk_yellow_5', 'sk_green_3', 'sk_purple_3'], c: ['sk_yellow_6', 'sk_green_4', 'sk_purple_4'] });
  aWins(g, id);
  const bot = decideSKBotAction(g, 'a');
  const rb = bot && g.handleAction('a', bot);
  chk(`${n}: 봇 결정이 유효`, !!(rb && rb.success) && g.state === 'playing');
}

console.log('전체 대국(봇 3명, 능력 켬)이 끝까지 돈다');
let finished = 0;
for (let i = 0; i < 40; i++) {
  const gm = new SK(['a', 'b', 'c', 'd'], { a: 'a', b: 'b', c: 'c', d: 'd' }, { expansions: ['kraken', 'white_whale', 'loot', 'pirate_abilities'] });
  gm.start();
  let guard = 0, bad = false;
  while (gm.state !== 'game_end' && guard++ < 5000) {
    if (gm.state === 'bidding') { for (const p of gm.playerIds) if (gm.bids[p] === null) gm.handleAction(p, decideSKBotAction(gm, p)); }
    else if (gm.state === 'playing' || gm.state === 'pirate_ability') {
      const actor = gm.getPendingActor();
      const a = decideSKBotAction(gm, actor);
      const r = gm.handleAction(actor, a);
      if (!r || !r.success) { console.log('  액션 실패', gm.state, a, r); bad = true; break; }
    } else if (gm.state === 'trick_end') gm.advanceAfterTrickEnd();
    else if (gm.state === 'round_end') gm.nextRound();
  }
  if (!bad && gm.state === 'game_end') finished++;
}
chk('40판 모두 정상 종료', finished === 40);

console.log(ok ? '\n전부 통과' : '\n실패 있음');
process.exit(ok ? 0 : 1);
