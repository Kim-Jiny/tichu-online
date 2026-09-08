'use strict';
/**
 * Smoke test for SkullBiddingGame's core loop: placing → bidding →
 * revealing → round_end, plus the failure/discard path and win conditions.
 * Not exhaustive — just enough to catch a broken state machine before
 * building bots/UI on top of it.
 *
 *   node test_skull_bidding_basic.js
 */
const SkullBiddingGame = require('./game/skull_bidding/SkullBiddingGame');
const { DISC } = require('./game/skull_bidding/SkullBiddingDeck');

const IDS = ['p0', 'p1', 'p2'];
let pass = 0, fail = 0;
const check = (name, cond, detail = '') => {
  if (cond) { pass++; console.log(`  ok   ${name}`); }
  else { fail++; console.log(`  FAIL ${name}${detail ? ` — ${detail}` : ''}`); }
};

function freshGame() {
  const names = {};
  IDS.forEach((p) => (names[p] = p));
  const g = new SkullBiddingGame(IDS, names);
  g.currentPlayer = 'p0'; // deterministic leader instead of start()'s random pick
  g._startNextRound();
  return g;
}

console.log('배치→비딩→공개→성공, 정상 흐름');
{
  const g = freshGame();
  check('첫 페이즈는 placing', g.state === 'placing');
  check('손패 없이는 입찰 불가', !g.handleStartBid('p0', 1).success);

  g.handlePlaceDisc('p0', DISC.ROSE);
  check('배치 후 다음 사람 턴', g.currentPlayer === 'p1');
  g.handlePlaceDisc('p1', DISC.ROSE);
  g.handlePlaceDisc('p2', DISC.ROSE);
  check('한 바퀴 후 다시 p0', g.currentPlayer === 'p0');

  const bidRes = g.handleStartBid('p0', 2);
  check('입찰 시작 성공', bidRes.success, JSON.stringify(bidRes));
  check('placing 종료, bidding 진입', g.state === 'bidding');
  check('입찰자 다음 사람부터 응답 큐', g.currentPlayer === 'p1');

  check('p1 패스', g.handlePass('p1').success);
  check('p2 패스 → 유일 생존자 p0로 자동 낙찰', g.handlePass('p2').success);
  check('revealing 로 전이', g.state === 'revealing');
  check('도전자는 p0', g.challengerId === 'p0');
  // 전원 rose 만 깔았으니 스컬 없음 — 자기 스택 자동 공개로 바로 성공까지 가야 함
  check('2장 요구, 자기 스택 1장뿐이라 상대 지목 대기', g.state === 'revealing' && !g.pendingDiscard && g.flippedCount === 1);

  const revealRes = g.handleRevealTarget('p0', 'p1');
  check('상대 지목 성공', revealRes.success, JSON.stringify(revealRes));
  check('2장 채워 라운드 성공', g.state === 'round_end');
  check('p0 성공 카운트 1', g.successCount.p0 === 1);
}

console.log('\n해골 공개 → 실패 → 코스터 영구 폐기');
{
  const g = freshGame();
  g.handlePlaceDisc('p0', DISC.SKULL);
  g.handlePlaceDisc('p1', DISC.ROSE);
  g.handlePlaceDisc('p2', DISC.ROSE);
  g.handleStartBid('p0', 1); // 자기 스택(스컬) 1장만 공개하면 됨
  check('bidding 진입', g.state === 'bidding');
  g.handlePass('p1');
  g.handlePass('p2');
  check('실패로 인해 폐기 대기', g.state === 'revealing' && !!g.pendingDiscard);
  check('폐기 대상은 도전자', g.pendingDiscard.playerId === 'p0');

  const before = g.pool.p0.roses;
  const discardRes = g.handleDiscardDisc('p0', DISC.ROSE);
  check('폐기 처리 성공', discardRes.success);
  check('장미 하나 영구 소실', g.pool.p0.roses === before - 1);
  check('라운드 종료로 전이', g.state === 'round_end');
  check('다음 라운드 리더는 실패한 도전자', g.pendingNextLeader === 'p0');
}

console.log('\n테이블 전체 베팅 성공 시 즉승');
{
  const g = freshGame();
  g.handlePlaceDisc('p0', DISC.ROSE);
  g.handlePlaceDisc('p1', DISC.ROSE);
  g.handlePlaceDisc('p2', DISC.ROSE);
  // 테이블 총량 3 그대로 입찰 — 아무도 못 올리니 즉시 낙찰
  const bidRes = g.handleStartBid('p0', 3);
  check('테이블 전체 입찰 시 자동 낙찰', g.state === 'revealing' && g.challengerId === 'p0', JSON.stringify(bidRes));
  check('자기 스택(1장) 공개 후 상대 지목 대기', g.flippedCount === 1 && !g.pendingDiscard);
  g.handleRevealTarget('p0', 'p1');
  g.handleRevealTarget('p0', 'p2');
  check('즉승으로 게임 종료', g.state === 'game_end' && g.gameWinner === 'p0', `state=${g.state} flipped=${g.flippedCount}`);
}

console.log('\n2회 성공 승리 조건');
{
  const g = freshGame();
  g.successCount.p0 = 1; // 이미 1승 상태에서 시작
  g.handlePlaceDisc('p0', DISC.ROSE);
  g.handlePlaceDisc('p1', DISC.ROSE);
  g.handlePlaceDisc('p2', DISC.ROSE);
  g.handleStartBid('p0', 1); // 테이블 총량(3) 미만이라 즉승 조건은 아님
  g.handlePass('p1');
  g.handlePass('p2');
  check('2승 달성으로 게임 종료', g.state === 'game_end' && g.gameWinner === 'p0');
}

console.log('\n0장 된 플레이어는 다음 라운드 턴 순서에서 제외');
{
  const g = freshGame();
  g.pool.p1 = { roses: 0, hasSkull: false };
  g.eliminated.p1 = true;
  g.currentPlayer = 'p0';
  g._startNextRound();
  check('p1 은 hand/stack 미초기화(비활성)', g.hand.p1 === undefined);
  g.handlePlaceDisc('p0', DISC.ROSE);
  check('p1 건너뛰고 p2 로 턴 이동', g.currentPlayer === 'p2');
}

console.log('\n4인 경매: 레이즈가 큐를 다시 세워서 이미 응답한 사람도 재소환');
{
  const ids4 = ['p0', 'p1', 'p2', 'p3'];
  const names4 = {};
  ids4.forEach((p) => (names4[p] = p));
  const g = new SkullBiddingGame(ids4, names4);
  g.currentPlayer = 'p0';
  g._startNextRound();
  for (const pid of ids4) g.handlePlaceDisc(pid, DISC.ROSE); // 테이블 총량 4

  g.handleStartBid('p0', 1);
  check('p1이 응답 큐 맨 앞', g.currentPlayer === 'p1');
  g.handleRaiseBid('p1', 2);
  check('p1 레이즈 후 p2 차례', g.currentPlayer === 'p2');
  g.handlePass('p2');
  check('p2 패스 후 p3 차례', g.currentPlayer === 'p3');
  g.handleRaiseBid('p3', 3);
  // 큐 재구성: p3 다음부터 활성+미패스만 — p0(아직 안 물러남), p1(안 물러남). p2는 패스했으니 제외.
  check('p3 레이즈 후 p0 재소환(아직 응답 안 한 상태였음)', g.currentPlayer === 'p0');
  g.handlePass('p0');
  check('p0 패스 후 p1 재소환', g.currentPlayer === 'p1');
  g.handlePass('p1');
  check('전원 응답 완료, p3 낙찰', g.state === 'revealing' && g.challengerId === 'p3');
  check('낙찰가는 마지막 레이즈값 3', g.targetFlips === 3);
}

console.log('\n잘못된 액션 거부');
{
  const g = freshGame();
  check('내 턴 아닌데 배치 시도 거부', !g.handlePlaceDisc('p1', DISC.ROSE).success);
  g.handlePlaceDisc('p0', DISC.ROSE);
  check('배치 페이즈에 raise_bid 거부', !g.handleRaiseBid('p0', 1).success);
  g.handlePlaceDisc('p1', DISC.ROSE);
  g.handlePlaceDisc('p2', DISC.ROSE);
  g.handleStartBid('p0', 1);
  check('직전 입찰과 같은 금액 재입찰 거부', !g.handleRaiseBid('p1', 1).success);
  check('테이블 총량 초과 입찰 거부', !g.handleRaiseBid('p1', 99).success);
}

console.log(fail === 0 ? '\nPASS' : `\n${fail} FAILURE(S)`);
process.exit(fail === 0 ? 0 : 1);
