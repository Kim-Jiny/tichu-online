'use strict';
// 봇의 상대 손패 추정: 교환 카드 고정 / 패스 추론 / 티츄 콜 가중 / 자연 티츄 콜.
const assert = require('assert');
const TichuGame = require('./game/TichuGame');
const { determinizeGameForBot, evaluateHand } = require('./game/BotPlayer');

const ids = ['p0', 'p1', 'p2', 'p3'];
function freshPlaying() {
  const g = new TichuGame(ids, { p0: 'a', p1: 'b', p2: 'c', p3: 'd' });
  g.start();
  for (const p of ids) g.handleAction(p, { type: 'pass_large_tichu' });
  for (const p of ids) {
    const h = g.hands[p];
    g.handleAction(p, { type: 'exchange_cards', cards: { left: h[0], partner: h[1], right: h[2] } });
  }
  return g;
}

// 1. 내가 준 카드는 받은 사람 손에 그대로 있다.
{
  const g = freshPlaying();
  const given = g.exchangeCards.p0;
  const idx = { right: 1, partner: 2, left: 3 };
  for (let i = 0; i < 40; i++) {
    const w = determinizeGameForBot(g, 'p0');
    for (const [k, off] of Object.entries(idx)) {
      assert(w.hands[ids[off]].includes(given[k]), `${k} 카드가 고정되지 않음`);
    }
    for (const p of ids) {
      assert.strictEqual(w.hands[p].length, g.hands[p].length);
      assert.strictEqual(new Set(w.hands[p]).size, w.hands[p].length);
    }
  }
}

// 2. 상대 싱글에 패스한 사람은 그보다 높은 카드를 덜 들고 있다.
{
  const g = freshPlaying();
  g.passLog = [{ playerId: 'p1', winner: 'p0', type: 'single', length: 1, value: 5 }];
  let hi = 0, ref = 0;
  const N = 400;
  for (let i = 0; i < N; i++) {
    const w = determinizeGameForBot(g, 'p0');
    hi += w.hands.p1.filter(c => /_(10|J|Q|K|A)$/.test(c) && !g.hands.p0.includes(c)).length;
    ref += w.hands.p3.filter(c => /_(10|J|Q|K|A)$/.test(c)).length;
  }
  assert(hi < ref * 0.8, `패스 추론 효과 없음 (${hi} vs ${ref})`);
}

// 3. 파트너 밑에서 한 패스는 정보가 아니다.
{
  const g = freshPlaying();
  g.passLog = [{ playerId: 'p1', winner: 'p3', type: 'single', length: 1, value: 5 }];
  let a = 0, b = 0;
  for (let i = 0; i < 400; i++) {
    const w = determinizeGameForBot(g, 'p0');
    a += w.hands.p1.filter(c => /_(10|J|Q|K|A)$/.test(c)).length;
    b += w.hands.p3.filter(c => /_(10|J|Q|K|A)$/.test(c)).length;
  }
  assert(Math.abs(a - b) < b * 0.25, `파트너 패스가 편향을 만듦 (${a} vs ${b})`);
}

// 4. 약한 손은 티츄를 부르지 않는다(자연 콜 기준 점수 미달).
{
  const weak = ['spade_2', 'heart_3', 'club_4', 'diamond_6', 'spade_7', 'heart_8', 'club_9', 'diamond_J',
    'spade_Q', 'heart_5', 'club_6', 'diamond_8', 'spade_10', 'heart_J'];
  assert(evaluateHand(weak).score < 100);
}

console.log('PASS');
