/**
 * 엔진이 미션 이벤트를 제대로 남기는지 — 규칙에는 영향이 없는지도 함께 본다.
 *   node server/test_mission_events.js
 */
const TichuGame = require('./game/TichuGame');
const MightyGame = require('./game/mighty/MightyGame');
const SkullKingGame = require('./game/skull_king/SkullKingGame');

let failures = 0;
const check = (label, cond, detail = '') => {
  console.log(`${cond ? '  ok  ' : '  FAIL'} ${label}${!cond && detail ? ` — ${detail}` : ''}`);
  if (!cond) failures++;
};
const has = (evs, pid, event, amount) =>
  evs.some((e) => e.playerId === pid && e.event === event && (amount === undefined || e.amount === amount));

// ── 티츄 ──
{
  const ids = ['p0', 'p1', 'p2', 'p3'];
  const names = { p0: 'A', p1: 'B', p2: 'C', p3: 'D' };
  const g = new TichuGame(ids, names, 1000);

  // 스몰/라지 티츄 성공 + 원투.
  g.finishOrder = ['p0', 'p2', 'p1', 'p3'];
  g.smallTichuDeclarations = ['p0'];
  g.largeTichuDeclarations = ['p2'];
  g.collectRoundMissionEvents();
  let ev = g.drainMissionEvents();
  check('스몰티츄 성공(1등 선언자)', has(ev, 'p0', 'tichu.small_success'));
  check('라지티츄는 1등이 아니면 실패', !has(ev, 'p2', 'tichu.large_success'));
  check('원투면 두 명 모두', has(ev, 'p0', 'tichu.one_two') && has(ev, 'p2', 'tichu.one_two'));
  check('비우면 다시 비어 있다', g.drainMissionEvents().length === 0);

  g.finishOrder = ['p2', 'p1', 'p0', 'p3'];
  g.smallTichuDeclarations = [];
  g.largeTichuDeclarations = ['p2'];
  g.collectRoundMissionEvents();
  ev = g.drainMissionEvents();
  check('라지티츄 성공(1등)', has(ev, 'p2', 'tichu.large_success'));
  check('다른 팀이 1·2등이면 원투 아님', !ev.some((e) => e.event === 'tichu.one_two'));

  // 폭탄으로 딴 점수: 5+10+K(10) 가 든 트릭을 폭탄이 이김.
  const g2 = new TichuGame(ids, names, 1000);
  g2.hands = { p0: ['spade_2'], p1: ['spade_2'], p2: ['spade_2'], p3: ['spade_2'] };
  g2.trickPiles = { p0: [], p1: [], p2: [], p3: [] };
  g2.currentTrick = [
    { playerId: 'p1', cards: ['spade_5', 'heart_5'], combo: { type: 'pair' } },
    { playerId: 'p0', cards: ['spade_10', 'heart_10', 'club_10', 'diamond_10'], combo: { type: 'bomb_four' } },
  ];
  g2.lastPlayedBy = 'p0';
  g2.resolveTrick();
  ev = g2.drainMissionEvents();
  check('폭탄이 딴 트릭 점수 = 5+5+10×4 = 50', has(ev, 'p0', 'tichu.bomb_points', 50), JSON.stringify(ev));

  const g3 = new TichuGame(ids, names, 1000);
  g3.hands = { p0: ['spade_2'], p1: ['spade_2'], p2: ['spade_2'], p3: ['spade_2'] };
  g3.trickPiles = { p0: [], p1: [], p2: [], p3: [] };
  g3.currentTrick = [{ playerId: 'p0', cards: ['spade_K'], combo: { type: 'single' } }];
  g3.lastPlayedBy = 'p0';
  g3.resolveTrick();
  check('폭탄이 아니면 이벤트 없음', g3.drainMissionEvents().length === 0);

  // 개로 마무리(1등).
  const g4 = new TichuGame(ids, names, 1000);
  g4.state = 'playing';
  g4.hands = { p0: ['special_dog'], p1: ['spade_2'], p2: ['spade_3'], p3: ['spade_4'] };
  g4.trickPiles = { p0: [], p1: [], p2: [], p3: [] };
  g4.currentPlayer = 'p0';
  g4.currentTrick = [];
  const r = g4.playDog('p0');
  ev = g4.drainMissionEvents();
  check('개로 손패를 털면 1등 → 이벤트', r.success && has(ev, 'p0', 'tichu.dog_finish'), JSON.stringify([r, ev]));

  // 3등으로 털면 인정 안 함.
  const g5 = new TichuGame(ids, names, 1000);
  g5.state = 'playing';
  g5.hands = { p0: ['special_dog'], p1: [], p2: [], p3: ['spade_4'] };
  g5.finishOrder = ['p1', 'p2'];
  g5.trickPiles = { p0: [], p1: [], p2: [], p3: [] };
  g5.currentPlayer = 'p0';
  g5.currentTrick = [];
  g5.playDog('p0');
  check('3등으로 털면 미션 아님', !g5.drainMissionEvents().some((e) => e.event === 'tichu.dog_finish'));
}

// ── 마이티 ──
{
  const ids = ['p0', 'p1', 'p2', 'p3', 'p4'];
  const names = Object.fromEntries(ids.map((i) => [i, i]));
  const mk = () => new MightyGame(ids, names, {});
  const g = mk();
  g.declarer = 'p0'; g.partner = 'p1';
  g.trumpSuit = 'no_trump';
  g.currentBid = { points: 20, suit: 'no_trump', bidder: 'p0' };
  g.pointCards = { p0: new Array(5).fill('x'), p1: new Array(15).fill('x'), p2: [], p3: [], p4: [] };
  g._collectRoundMissionEvents({ success: true, declarerPoints: 20 });
  let ev = g.drainMissionEvents();
  check('비딩 20 성공', has(ev, 'p0', 'mighty.bid20_success'));
  check('노트럼프 성공', has(ev, 'p0', 'mighty.nt_success'));
  check('여당 20장 독식(주공·친구 모두)', has(ev, 'p0', 'mighty.declarer_all20') && has(ev, 'p1', 'mighty.declarer_all20'));
  check('친구가 7점 이상', has(ev, 'p1', 'mighty.friend_points', 7));
  g.currentBid = { points: 15, suit: 'spade', bidder: 'p0' };
  g.trumpSuit = 'spade';
  g.pointCards.p1 = new Array(6).fill('x');
  g._collectRoundMissionEvents({ success: false, declarerPoints: 11 });
  ev = g.drainMissionEvents();
  check('실패하면 아무 이벤트도 없음(친구 6점도 인정 안 함)', ev.length === 0, JSON.stringify(ev));
}

// ── 스컬킹 ──
{
  const ids = ['p0', 'p1', 'p2'];
  const names = { p0: 'A', p1: 'B', p2: 'C' };
  const g = new SkullKingGame(ids, names, {});
  g.state = 'playing';
  g.hands = { p0: ['x'], p1: ['x'], p2: ['x'] };
  g.tricks = { p0: 0, p1: 0, p2: 0 };
  g.bonuses = { p0: 0, p1: 0, p2: 0 };
  g.lootAlliances = [];
  const cards = require('./game/skull_king/SkullKingDeck').createDeck({}).map((c) => c.id || c);
  const find = (re) => cards.find((c) => re.test(c));
  const sk = find(/skull_king/), pirate = cards.filter((c) => /pirate/.test(c) && !/tigress/.test(c)), mermaid = find(/mermaid/);
  console.log('   (덱 예: ', sk, pirate && pirate[0], mermaid, ')');
  g.currentTrick = [
    { playerId: 'p0', cardId: sk },
    { playerId: 'p1', cardId: pirate[0] },
    { playerId: 'p2', cardId: pirate[1] },
  ];
  g.playerCount = 3;
  g.completeTrick();
  let ev = g.drainMissionEvents();
  check('스컬킹이 해적 둘을 잡으면', has(ev, 'p0', 'sk.skullking_two_pirates'), JSON.stringify(ev));
  g.currentTrick = [
    { playerId: 'p0', cardId: sk },
    { playerId: 'p1', cardId: mermaid },
    { playerId: 'p2', cardId: pirate[2] },
  ];
  g.completeTrick();
  ev = g.drainMissionEvents();
  check('인어가 스컬킹을 잡으면(인어 플레이어)', has(ev, 'p1', 'sk.mermaid_takes_skullking'), JSON.stringify(ev));
}

console.log(failures ? `\n실패 ${failures}건` : '\n전부 통과');
process.exit(failures ? 1 : 0);
