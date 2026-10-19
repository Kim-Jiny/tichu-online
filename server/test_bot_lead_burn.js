'use strict';
/**
 * 봇이 A/K 페어를 혼자 먼저 내지 않는다.
 *
 * 승률 탐색(winrate)은 샘플이 서너 개뿐이라, 트릭을 이기는 수(AA)를 곧잘
 * 뽑았다. 그러면 AA 22 5 8 에서 AA 를 내고 나머지 22·5·8 세 번을 전부
 * 지는 선으로 내게 된다. 휴리스틱은 뒤가 이어 나가지 않으면(canChainOut)
 * 높은 조합을 아낀다 — 탐색 후보에서도 같은 기준으로 뺀다.
 *
 *   node test_bot_lead_burn.js
 */
const TichuGame = require('./game/TichuGame');
const { decideBotAction } = require('./game/BotPlayer');
const { createDeck } = require('./game/Deck');

let ok = true;
const chk = (n, c, d = '') => { console.log(c ? '  ok  ' : '  FAIL', n + (!c && d ? ` — ${d}` : '')); if (!c) ok = false; };

const ids = ['p0', 'p1', 'p2', 'p3']; const names = {}; ids.forEach(p => (names[p] = p));
let seed = 7; const rnd = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff; };

function lead(hand, counts) {
  const rest = createDeck().map(c => (typeof c === 'string' ? c : c.id))
    .filter(c => !hand.includes(c) && !c.startsWith('special_')).sort(() => rnd() - 0.5);
  const hs = []; let k = 0;
  for (const c of counts) { hs.push(rest.slice(k, k + c)); k += c; }
  const g = new TichuGame(ids, names); g.start();
  g.state = 'playing'; g.currentPlayer = 'p0'; g.trickStarter = 'p0'; g.currentTrick = [];
  g.hands = { p0: hand.slice(), p1: hs[0], p2: hs[1], p3: hs[2] };
  g.passCount = 0; g.trickPiles = { p0: [], p1: [], p2: [], p3: [] }; g.trickWins = {}; g.lastPlayedBy = null;
  return g;
}

console.log('[AA 22 5 8 — AA 를 먼저 내지 않는다]');
let aa = 0;
for (let i = 0; i < 60; i++) {
  const counts = [1 + Math.floor(rnd() * 9), 1 + Math.floor(rnd() * 9), 1 + Math.floor(rnd() * 9)];
  const g = lead(['spade_A', 'heart_A', 'spade_2', 'heart_2', 'club_5', 'diamond_8'], counts);
  const a = decideBotAction(g, 'p0', 'winrate');
  if (a.cards && a.cards.length === 2 && a.cards.every(c => c.endsWith('_A'))) aa++;
}
chk('60 번 중 AA 선공 0 번', aa === 0, `${aa} 번`);

console.log('[뒤가 이어 나가면 AA 를 먼저 내도 된다 — AA KK 3]');
const g2 = lead(['spade_A', 'heart_A', 'spade_K', 'heart_K', 'club_3'], [5, 5, 5]);
const a2 = decideBotAction(g2, 'p0', 'winrate');
chk('합법적인 수를 낸다', a2 && a2.type === 'play_cards' && a2.cards.length > 0);

console.log(ok ? '\nALL PASS' : '\nFAIL');
process.exit(ok ? 0 : 1);
