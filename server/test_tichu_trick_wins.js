'use strict';
/**
 * 티츄: 가져간 트릭 수를 센다.
 *
 * 점수를 유추하라고 넣은 값이다. 카드를 보여 주지 않으면서 "누가 얼마나
 * 긁어 갔나" 는 알 수 있게 한다.
 *
 * 세는 자리가 다섯 군데(일반 승리 2, 용 넘김 3)라 하나로 모았다.
 * 빠뜨려도 점수는 맞아서(점수는 카드로만 센다) 한참 모르기 때문이다.
 * 그래서 '카드가 쌓였으면 횟수도 올랐다' 를 직접 본다.
 *
 * 용을 넘긴 경우는 받는 쪽이 오른다 — 점수를 쥐는 쪽이 받은 사람이다.
 *
 *   node test_tichu_trick_wins.js
 */
const TichuGame = require('./game/TichuGame.js');

let ok = true;
const chk = (n, c, d = '') => {
  console.log(c ? '  ok  ' : '  FAIL', n + (!c && d ? ` — ${d}` : ''));
  if (!c) ok = false;
};
const eq = (n, got, want) =>
  chk(n, got === want, `got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);

const ids = ['p0', 'p1', 'p2', 'p3'];
const g = new TichuGame(ids, { p0: 'A', p1: 'B', p2: 'C', p3: 'D' });
g.resetRound();

eq('라운드 시작에는 0', g.trickWins.p0, 0);

// _awardTrick 하나로 모았으므로 카드와 횟수가 같이 움직여야 한다.
g._awardTrick('p1', ['heart_5', 'club_5']);
eq('한 번 가져가면 1', g.trickWins.p1, 1);
eq('카드도 같이 쌓인다', g.trickPiles.p1.length, 2);

g._awardTrick('p1', ['spade_K']);
eq('두 번째도 센다', g.trickWins.p1, 2);
eq('카드는 누적', g.trickPiles.p1.length, 3);
eq('다른 사람은 그대로', g.trickWins.p0, 0);

// 라운드가 바뀌면 비운다 — '이번 라운드' 의 수다.
g.resetRound();
eq('라운드가 바뀌면 0', g.trickWins.p1, 0);
eq('카드도 비워진다', g.trickPiles.p1.length, 0);

// 클라로 나가는 상태에 실린다.
g._awardTrick('p2', ['heart_10']);
const st = g.getStateForPlayer('p0');
const p2 = st.players.find((p) => p.id === 'p2');
eq('플레이어 상태에 실린다', p2.trickWins, 1);
const sp = g.getStateForSpectator(new Set());
eq('관전 상태에도 실린다', sp.players.find((p) => p.id === 'p2').trickWins, 1);

// clone()/serialize() 짝 — 둘 다 들고 가야 한다(워커로 넘어간다).
const c = g.clone();
eq('clone 이 들고 간다', c.trickWins.p2, 1);
eq('serialize 가 들고 간다', g.serialize().trickWins.p2, 1);

// 카드가 쌓인 모든 경로가 횟수도 올렸는가 — 소스로 직접 본다.
const src = require('fs').readFileSync(__dirname + '/game/TichuGame.js', 'utf8');
const direct = (src.match(/this\.trickPiles\[[^\]]+\]\.push\(/g) || []).length;
eq('_awardTrick 을 거치지 않는 push 가 없다', direct, 1); // 헬퍼 자신뿐

console.log(ok ? 'PASS' : 'FAIL');
process.exit(ok ? 0 : 1);
