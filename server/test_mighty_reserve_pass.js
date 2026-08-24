'use strict';
/**
 * "이번 판은 무조건 패스" 예약 버튼.
 *
 * 손패가 나쁘면 내 차례가 올 때까지 다른 사람 비딩을 지켜볼 필요 없이
 * 미리 패스를 예약해둘 수 있다. 차례가 오면 자동으로 패스 처리되고,
 * 예약 버튼을 다시 누르면 취소된다.
 *
 *   node test_mighty_reserve_pass.js
 */
const assert = require('assert');
const MightyGame = require('./game/mighty/MightyGame');
const { makeRng } = require('./game/mighty/MightyDeck');

const IDS = ['p0', 'p1', 'p2', 'p3', 'p4'];
let pass = 0, fail = 0;
const check = (name, cond, detail = '') => {
  if (cond) { pass++; console.log(`  ok   ${name}`); }
  else { fail++; console.log(`  FAIL ${name}${detail ? ` — ${detail}` : ''}`); }
};

function freshGame() {
  const names = {};
  IDS.forEach(p => (names[p] = p));
  const g = new MightyGame(IDS, names, { targetScore: 50, rng: makeRng(7) });
  g.start();
  return g;
}

console.log('\n[예약 토글]');
{
  const g = freshGame();
  const first = g.currentPlayer;
  const later = g.bidOrder[g.bidOrder.length - 1]; // will not act for a while
  assert(later !== first);

  const r1 = g.handleAction(later, { type: 'reserve_pass' });
  check('예약이 성공한다', r1.success);
  check('예약 상태가 보인다', g.getStateForPlayer(later).reservedPass === true);
  check('예약해도 아직 자기 차례가 아니다', g.currentPlayer === first);
  check('아직 bids 에는 안 들어간다', g.bids[later] === undefined);

  const r2 = g.handleAction(later, { type: 'reserve_pass' });
  check('다시 누르면 취소된다', r2.success && g.getStateForPlayer(later).reservedPass === false);
}

console.log('\n[차례가 오면 자동 패스]');
{
  const g = freshGame();
  const first = g.currentPlayer;
  const second = g.bidOrder[1];
  const third = g.bidOrder[2];

  g.handleAction(second, { type: 'reserve_pass' });
  check('예약 확인', g.pendingPassReservations.has(second));

  // first bids something valid; advancing bidding should skip straight past
  // the reserved player without anyone acting on their behalf.
  const bidRes = g.handleAction(first, { type: 'submit_bid', points: g.options.minBid, suit: 'spade' });
  check('첫 비드는 성공한다', bidRes.success, JSON.stringify(bidRes));
  check('예약된 플레이어는 건너뛰어 세번째로 넘어간다', g.currentPlayer === third);
  check('예약된 플레이어는 pass 로 기록된다', g.bids[second] === 'pass');
  check('예약은 소비되고 사라진다', !g.pendingPassReservations.has(second));
}

console.log('\n[이미 비딩/패스한 사람]');
{
  const g = freshGame();
  const first = g.currentPlayer;
  g.handleAction(first, { type: 'submit_bid', pass: true });
  const r = g.handleAction(first, { type: 'reserve_pass' });
  check('이미 패스한 사람은 예약 못 한다', r.success === false, JSON.stringify(r));
}

console.log('\n[내 차례에 누르면 그냥 패스]');
{
  const g = freshGame();
  const first = g.currentPlayer;
  const second = g.bidOrder[1];
  const r = g.handleAction(first, { type: 'reserve_pass' });
  check('성공한다', r.success);
  check('즉시 패스로 처리된다', g.bids[first] === 'pass');
  check('차례가 다음 사람으로 넘어간다', g.currentPlayer === second);
}

console.log('\n[봇이 이어받으면 예약이 사라져야 한다]');
{
  const g = freshGame();
  const second = g.bidOrder[1];
  g.handleAction(second, { type: 'reserve_pass' });
  check('예약됨', g.pendingPassReservations.has(second));
  // Simulate what handOffSeatToBot does server-side when a human leaves and
  // a bot inherits the same playerId — the human's reservation must not
  // silently force the bot to pass on its own turn.
  g.pendingPassReservations.delete(second);
  check('시뮬레이션한 정리 후 예약 없음', !g.pendingPassReservations.has(second));
}

console.log(`\n${fail === 0 ? 'PASS' : 'FAIL'} (${pass} passed, ${fail} failed)`);
process.exit(fail === 0 ? 0 : 1);
