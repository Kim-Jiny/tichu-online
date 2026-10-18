'use strict';
/**
 * 봇이 봉황 스트레이트의 값을 과대평가하지 않는다.
 *
 * 티츄 스트레이트의 최고는 A 다(TichuGame: `start + L - 1 <= 14`). 봉황은
 * 안쪽 빈틈만 채울 수 있고 A 위로는 못 간다. 그런데 봇은 "빈틈이 없으면
 * 봉황이 위로 붙는다" 고 보아 J-Q-K-A + 봉황을 15 로 셌고, 14 짜리
 * 스트레이트 위에 냈다가 거부당했다(game_combo_cannot_beat).
 *
 * 무작위 대국에서 3만 수에 한 번쯤 나오는 상황이라, 전체 대국을 돌려
 * 잡는 방식으로는 회귀를 막을 수 없다. 그 패를 손으로 심어 고정한다.
 *
 *   node test_bot_phoenix_straight.js
 */
const TichuGame = require('./game/TichuGame');
const { decideBotAction } = require('./game/BotPlayer');

let ok = true;
const chk = (n, c, d = '') => {
  console.log(c ? '  ok  ' : '  FAIL', n + (!c && d ? ` — ${d}` : ''));
  if (!c) ok = false;
};

const ids = ['p0', 'p1', 'p2', 'p3'];
const names = {}; for (const p of ids) names[p] = p;

/// 플레이 단계의 판을 손으로 세운다. [trick] 은 이미 테이블에 깔린 것.
function setup({ hand, trick }) {
  const g = new TichuGame(ids, names);
  g.start();
  g.state = 'playing';
  g.currentPlayer = 'p0';
  g.trickStarter = trick.length ? 'p3' : 'p0';
  g.currentTrick = trick;
  g.hands = {
    p0: hand.slice(),
    p1: ['club_2', 'club_3', 'club_4', 'club_6', 'club_7'],
    p2: ['spade_3', 'spade_6', 'spade_7', 'spade_8', 'spade_9'],
    p3: ['heart_3', 'heart_4', 'heart_8', 'heart_9', 'heart_10'],
  };
  g.passCount = 0;
  return g;
}

const aceHighTrick = [{
  playerId: 'p3',
  cards: ['spade_10', 'spade_J', 'club_Q', 'diamond_K', 'club_A'],
  combo: { type: 'straight', length: 5, value: 14 },
}];

console.log('[A 로 끝나는 스트레이트 위에 봉황을 얹지 않는다]');
for (const style of ['winrate', 'normal', 'hard']) {
  const g = setup({
    // 봇이 J-Q-K-A + 봉황을 5장 스트레이트로 만들 수 있는 손패.
    hand: ['heart_J', 'heart_Q', 'heart_K', 'diamond_A', 'special_phoenix',
           'club_5', 'spade_4'],
    trick: aceHighTrick,
  });
  const act = decideBotAction(g, 'p0', style);
  // 내기로 했다면 그 수는 반드시 합법이어야 한다. 못 이기면 패스가 정답이다.
  let legal = true, why = '';
  if (act && act.type === 'play_cards') {
    const probe = g.clone();
    const res = probe.handleAction('p0', act);
    legal = !!res && res.success !== false;
    why = `${JSON.stringify(act.cards)} → ${res && (res.messageKey || res.message)}`;
  }
  chk(`${style}: 고른 수가 합법이다`, legal, why);
}

console.log('\n[빈틈이 있으면 봉황으로 채워 이긴다 — 과하게 막지 않았는지]');
{
  // 9-10-J-Q-K 를 봉황으로 채워 13 짜리를 만들어 12 짜리 트릭을 이긴다.
  const g = setup({
    hand: ['heart_9', 'heart_10', 'special_phoenix', 'heart_Q', 'heart_K', 'club_2'],
    trick: [{
      playerId: 'p3',
      cards: ['spade_8', 'spade_9', 'club_10', 'diamond_J', 'club_Q'],
      combo: { type: 'straight', length: 5, value: 12 },
    }],
  });
  const act = decideBotAction(g, 'p0', 'winrate');
  const played = act && act.type === 'play_cards';
  let legal = true, why = '';
  if (played) {
    const probe = g.clone();
    const res = probe.handleAction('p0', act);
    legal = !!res && res.success !== false;
    why = `${JSON.stringify(act.cards)} → ${res && (res.messageKey || res.message)}`;
  }
  chk('이길 수 있는 봉황 스트레이트는 합법으로 낸다', legal, why);
  console.log(`        (고른 수: ${played ? act.cards.join(' ') : act && act.type})`);
}

console.log('\n[A 가 없으면 봉황이 위로 붙는 계산은 그대로]');
{
  // 9-10-J-Q + 봉황 → 봉황이 K 자리로 붙어 13 짜리. 12 짜리를 이긴다.
  const g = setup({
    hand: ['heart_9', 'heart_10', 'heart_J', 'heart_Q', 'special_phoenix', 'club_2'],
    trick: [{
      playerId: 'p3',
      cards: ['spade_8', 'spade_9', 'club_10', 'diamond_J', 'club_Q'],
      combo: { type: 'straight', length: 5, value: 12 },
    }],
  });
  const act = decideBotAction(g, 'p0', 'winrate');
  let legal = true, why = '';
  if (act && act.type === 'play_cards') {
    const probe = g.clone();
    const res = probe.handleAction('p0', act);
    legal = !!res && res.success !== false;
    why = `${JSON.stringify(act.cards)} → ${res && (res.messageKey || res.message)}`;
  }
  chk('위로 붙여 이기는 수도 합법이다', legal, why);
  console.log(`        (고른 수: ${act && act.type === 'play_cards' ? act.cards.join(' ') : act && act.type})`);
}

console.log(ok ? '\n전부 통과' : '\n실패 있음');
process.exit(ok ? 0 : 1);
