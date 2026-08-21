'use strict';
/**
 * 스컬킹에서 자리를 비웠을 때 대신 부르는 입찰.
 *
 * 예전에는 0이었다. 0은 "한 판도 못 먹겠다" 는 선언이라 한 번이라도 먹으면
 * 그대로 감점인데, 손을 놓은 사람은 아무 카드나 내다가 곧잘 먹는다. 1은
 * 맞히면 점수를 받고 틀려도 0을 어겼을 때와 같은 폭으로 깎인다.
 *
 * 기본값이 두 군데 있다는 게 이 테스트의 또 다른 이유다 — 엔진의
 * getAutoTimeoutAction 과 서버의 runSkullKingFallback. 하나만 고치면
 * 어느 경로로 시간이 초과했느냐에 따라 다른 입찰이 들어간다.
 *
 *   node test_sk_auto_bid.js
 */
const SkullKingGame = require('./game/skull_king/SkullKingGame');
const fs = require('fs');

const IDS = ['p0', 'p1', 'p2'];
let pass = 0, fail = 0;
const check = (name, cond, detail = '') => {
  if (cond) { pass++; console.log(`  ok   ${name}`); }
  else { fail++; console.log(`  FAIL ${name}${detail ? ` — ${detail}` : ''}`); }
};

function biddingGame(round) {
  const names = {};
  IDS.forEach(p => (names[p] = p));
  const g = new SkullKingGame(IDS, names, { targetScore: 100 });
  g.state = 'bidding';
  g.round = round;
  g.bids = {};
  IDS.forEach(p => (g.bids[p] = null));
  return g;
}

console.log('시간 초과 입찰');
{
  const g = biddingGame(1);
  const a = g.getAutoTimeoutAction('p0');
  check('1라운드에서 1승을 부른다', a && a.type === 'submit_bid' && a.bid === 1,
    JSON.stringify(a));
  // 1라운드는 카드가 한 장이라 상한도 1이다. 실제로 받아들여져야 한다.
  const r = g.handleAction('p0', a);
  check('1라운드에서도 유효한 입찰이다', r && r.success !== false,
    r && r.messageKey);
}
{
  const g = biddingGame(7);
  const a = g.getAutoTimeoutAction('p0');
  check('라운드가 커져도 1승이다', a && a.bid === 1, JSON.stringify(a));
}
{
  // 딜 직전이라 라운드가 아직 0인 순간. 상한이 0이므로 1은 거절당한다.
  const g = biddingGame(0);
  const a = g.getAutoTimeoutAction('p0');
  check('상한이 0이면 0으로 떨어진다', a && a.bid === 0, JSON.stringify(a));
}

console.log('\n두 경로의 기본값이 같은가');
{
  // 서버 폴백(runSkullKingFallback)은 엔진을 거치지 않고 직접 넣는다.
  // 소스를 읽어 같은 식을 쓰는지 본다 — 값이 갈리면 어느 경로로 시간이
  // 초과했느냐에 따라 다른 입찰이 들어간다.
  const server = fs.readFileSync('./server.js', 'utf8');
  const i = server.indexOf('runSkullKingFallback');
  const chunk = server.slice(i, i + 900);
  check('서버 폴백도 Math.min(1, round) 를 쓴다',
    /submit_bid',\s*bid:\s*Math\.min\(1,\s*room\.game\.round\)/.test(chunk)
      || /bid:\s*Math\.min\(1,\s*room\.game\.round\)/.test(chunk),
    '서버 폴백이 다른 값을 쓴다');
}

console.log(fail === 0 ? '\nPASS' : `\n${fail} FAILURE(S)`);
process.exit(fail === 0 ? 0 : 1);
