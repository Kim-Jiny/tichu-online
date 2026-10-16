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
  check('친구가 7점 이상', has(ev, 'p1', 'mighty.friend_points', 1));
  check('NT 20점 성공', has(ev, 'p0', 'mighty.nt20_success'), JSON.stringify(ev));
  g.currentBid = { points: 15, suit: 'spade', bidder: 'p0' };
  g.trumpSuit = 'spade';
  g.pointCards.p1 = new Array(6).fill('x');
  g._collectRoundMissionEvents({ success: false, declarerPoints: 11 });
  ev = g.drainMissionEvents();
  check('실패하면 주공·친구 성공 이벤트는 없다(친구 6점도 인정 안 함)', !ev.some((e) => (e.playerId === 'p0' || e.playerId === 'p1') && e.event !== 'mighty.round_end'), JSON.stringify(ev));
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


// ── 추가 미션 이벤트 ──
{
  const ids = ['p0', 'p1', 'p2', 'p3'];
  const names = { p0: 'A', p1: 'B', p2: 'C', p3: 'D' };
  const mk = () => {
    const g = new TichuGame(ids, names, 1000);
    g.hands = { p0: ['spade_2'], p1: ['spade_2'], p2: ['spade_2'], p3: ['spade_2'] };
    g.trickPiles = { p0: [], p1: [], p2: [], p3: [] };
    return g;
  };
  const trickWin = (cards, combo) => {
    const g = mk();
    g.currentTrick = [{ playerId: 'p0', cards, combo }];
    g.lastPlayedBy = 'p0';
    g.resolveTrick();
    return g.drainMissionEvents();
  };
  check('스트레이트로 이기면', has(trickWin(['spade_3', 'spade_4', 'heart_5', 'heart_6', 'club_7'], { type: 'straight' }), 'p0', 'tichu.straight_win'));
  check('풀하우스로 이기면', has(trickWin(['spade_3', 'heart_3', 'club_3', 'spade_9', 'heart_9'], { type: 'full_house' }), 'p0', 'tichu.fullhouse_win'));
  check('연속 쌍으로 이기면', has(trickWin(['spade_3', 'heart_3', 'spade_4', 'heart_4'], { type: 'steps' }), 'p0', 'tichu.steps_win'));
  check('봉황이 든 패로 이기면', has(trickWin(['special_phoenix', 'spade_9'], { type: 'pair' }), 'p0', 'tichu.phoenix_win'));
  check('용으로 이기면', has(trickWin(['special_dragon'], { type: 'single' }), 'p0', 'tichu.dragon_win'));
  check('그냥 단독은 아무것도 아님', trickWin(['spade_9'], { type: 'single' }).length === 0);

  // 폭탄을 낼 때마다 한 번.
  const gb = mk();
  gb.state = 'playing';
  gb.hands.p0 = ['spade_9', 'heart_9', 'club_9', 'diamond_9', 'spade_2'];
  gb.currentPlayer = 'p0';
  const rb = gb.handleAction('p0', { type: 'play_cards', cards: ['spade_9', 'heart_9', 'club_9', 'diamond_9'] });
  const evb = gb.drainMissionEvents();
  check('폭탄을 내면 bomb_played', !!(rb && rb.success) && has(evb, 'p0', 'tichu.bomb_played'), JSON.stringify([rb, evb]));

  // 라운드 끝: 1등 / 티츄 저지.
  const gr = mk();
  gr.finishOrder = ['p1', 'p0', 'p2', 'p3'];
  gr.smallTichuDeclarations = ['p0']; // p0(팀A) 선언했지만 2등 → 실패
  gr.collectRoundMissionEvents();
  const evr = gr.drainMissionEvents();
  check('1등 이벤트', has(evr, 'p1', 'tichu.first_out'));
  check('상대 팀(p1,p3)이 티츄를 막았다', has(evr, 'p1', 'tichu.tichu_broken') && has(evr, 'p3', 'tichu.tichu_broken') && !has(evr, 'p0', 'tichu.tichu_broken') && !has(evr, 'p2', 'tichu.tichu_broken'), JSON.stringify(evr));
  const gs = mk();
  gs.finishOrder = ['p0', 'p1', 'p2', 'p3'];
  gs.smallTichuDeclarations = ['p0'];
  gs.collectRoundMissionEvents();
  check('성공한 티츄는 막은 게 아님', !gs.drainMissionEvents().some((e) => e.event === 'tichu.tichu_broken'));
}

{
  // 맞티츄·티츄 원투, 긴 스트레이트, K/A 풀하우스, 스트레이트 플러시, 봉황으로 A 잡기.
  const ids = ['p0', 'p1', 'p2', 'p3'];
  const names = { p0: 'A', p1: 'B', p2: 'C', p3: 'D' };
  const mk = () => {
    const g = new TichuGame(ids, names, 1000);
    g.hands = { p0: ['spade_2'], p1: ['spade_2'], p2: ['spade_2'], p3: ['spade_2'] };
    g.trickPiles = { p0: [], p1: [], p2: [], p3: [] };
    return g;
  };
  const round = (order, small, large) => {
    const g = mk();
    g.finishOrder = order; g.smallTichuDeclarations = small; g.largeTichuDeclarations = large;
    g.collectRoundMissionEvents();
    return g.drainMissionEvents();
  };
  // p0(팀A) 이 1등, 상대 팀(p1) 도 스몰 선언 → 맞스몰.
  let ev = round(['p0', 'p2', 'p1', 'p3'], ['p0', 'p1'], []);
  check('맞스몰 성공', has(ev, 'p0', 'tichu.counter_small') && !has(ev, 'p0', 'tichu.counter_large'), JSON.stringify(ev));
  ev = round(['p0', 'p1', 'p2', 'p3'], ['p0'], []);
  check('상대가 선언하지 않았으면 맞스몰이 아님', !has(ev, 'p0', 'tichu.counter_small'));
  ev = round(['p0', 'p1', 'p2', 'p3'], ['p0'], ['p1']);
  check('상대는 라지, 나는 스몰이면 맞스몰이 아님', !has(ev, 'p0', 'tichu.counter_small') && !has(ev, 'p0', 'tichu.counter_large'));
  ev = round(['p1', 'p0', 'p2', 'p3'], ['p0', 'p1'], []);
  check('상대가 1등이면 내 맞스몰은 실패', !has(ev, 'p0', 'tichu.counter_small') && has(ev, 'p1', 'tichu.counter_small') === true);
  ev = round(['p0', 'p2', 'p1', 'p3'], [], ['p0', 'p3']);
  check('맞라지 성공', has(ev, 'p0', 'tichu.counter_large'), JSON.stringify(ev));
  ev = round(['p0', 'p2', 'p1', 'p3'], ['p0'], []);
  check('티츄 선언 + 우리 팀 원투', has(ev, 'p0', 'tichu.tichu_onetwo'), JSON.stringify(ev));
  ev = round(['p0', 'p1', 'p2', 'p3'], ['p0'], []);
  check('원투가 아니면 티츄 원투 아님', !has(ev, 'p0', 'tichu.tichu_onetwo'));
  ev = round(['p0', 'p2', 'p1', 'p3'], [], []);
  check('선언 없는 원투는 티츄 원투 아님', !has(ev, 'p0', 'tichu.tichu_onetwo'));

  // 긴 스트레이트.
  const longStraight = (n) => {
    const g = mk();
    g.state = 'playing';
    const suits = ['spade', 'heart', 'club', 'diamond'];
    const RK = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];
    const cards = []; for (let i = 0; i < n; i++) cards.push(`${suits[i % 3]}_${RK[i]}`);
    g.hands.p0 = [...cards, 'diamond_A'];
    g.currentPlayer = 'p0';
    const r = g.handleAction('p0', { type: 'play_cards', cards });
    return { r, ev: g.drainMissionEvents() };
  };
  let ls = longStraight(8);
  check('8장 스트레이트', ls.r.success && has(ls.ev, 'p0', 'tichu.straight8') && !has(ls.ev, 'p0', 'tichu.straight10'), JSON.stringify([ls.r.success, ls.ev]));
  ls = longStraight(10);
  check('10장 스트레이트', ls.r.success && has(ls.ev, 'p0', 'tichu.straight10') && has(ls.ev, 'p0', 'tichu.straight8'), JSON.stringify([ls.r.success, ls.ev]));
  ls = longStraight(5);
  check('5장 스트레이트는 해당 없음', ls.r.success && !has(ls.ev, 'p0', 'tichu.straight8'));

  // K / A 풀하우스로 이긴 트릭.
  const fh = (rank) => {
    const g = mk();
    g.currentTrick = [{ playerId: 'p0', cards: [`spade_${rank}`, `heart_${rank}`, `club_${rank}`, 'spade_3', 'heart_3'], combo: { type: 'full_house', length: 5, value: rank === 'K' ? 13 : rank === 'A' ? 14 : 9 } }];
    g.lastPlayedBy = 'p0';
    g.resolveTrick();
    return g.drainMissionEvents();
  };
  ev = fh('K');
  check('K 풀하우스', has(ev, 'p0', 'tichu.fullhouse_k') && !has(ev, 'p0', 'tichu.fullhouse_a'), JSON.stringify(ev));
  ev = fh('A');
  check('A 풀하우스는 K 조건도 만족', has(ev, 'p0', 'tichu.fullhouse_a') && has(ev, 'p0', 'tichu.fullhouse_k'));
  ev = fh('9');
  check('9 풀하우스는 일반 풀하우스만', has(ev, 'p0', 'tichu.fullhouse_win') && !has(ev, 'p0', 'tichu.fullhouse_k'));

  // 스트레이트 플러시 폭탄.
  const gf = mk();
  gf.state = 'playing';
  gf.hands.p0 = ['spade_3', 'spade_4', 'spade_5', 'spade_6', 'spade_7', 'heart_K'];
  gf.currentPlayer = 'p0';
  const rf = gf.handleAction('p0', { type: 'play_cards', cards: ['spade_3', 'spade_4', 'spade_5', 'spade_6', 'spade_7'] });
  const evf = gf.drainMissionEvents();
  check('스트레이트 플러시 폭탄', rf.success && has(evf, 'p0', 'tichu.straight_flush') && has(evf, 'p0', 'tichu.bomb_played'), JSON.stringify([rf.success, evf]));
  const g4k = mk();
  g4k.state = 'playing';
  g4k.hands.p0 = ['spade_9', 'heart_9', 'club_9', 'diamond_9', 'spade_2'];
  g4k.currentPlayer = 'p0';
  g4k.handleAction('p0', { type: 'play_cards', cards: ['spade_9', 'heart_9', 'club_9', 'diamond_9'] });
  check('4장 폭탄은 스트레이트 플러시가 아님', !has(g4k.drainMissionEvents(), 'p0', 'tichu.straight_flush'));

  // 봉황을 단독으로 내서 이긴 트릭.
  const phoenixTrick = (cards, combo) => {
    const g = mk();
    g.currentTrick = [{ playerId: 'p0', cards, combo }];
    g.lastPlayedBy = 'p0';
    g.resolveTrick();
    return g.drainMissionEvents();
  };
  check('봉황 단독으로 이긴 트릭', has(phoenixTrick(['special_phoenix'], { type: 'single', value: 1.5 }), 'p0', 'tichu.phoenix_single_win'));
  check('봉황이 든 조합은 단독이 아님', !has(phoenixTrick(['special_phoenix', 'spade_9'], { type: 'pair' }), 'p0', 'tichu.phoenix_single_win'));

  // A 풀하우스로 이긴 트릭의 점수.
  const aFull = (() => {
    const g = mk();
    g.currentTrick = [
      { playerId: 'p1', cards: ['spade_5', 'heart_5'], combo: { type: 'pair' } },
      { playerId: 'p0', cards: ['spade_A', 'heart_A', 'club_A', 'spade_K', 'heart_K'], combo: { type: 'full_house', length: 5, value: 14 } },
    ];
    g.lastPlayedBy = 'p0';
    g.resolveTrick();
    return g.drainMissionEvents();
  })();
  check('A 풀하우스 트릭의 점수(5+5+K10+K10 = 30)', has(aFull, 'p0', 'tichu.fullhouse_a_points', 30), JSON.stringify(aFull));

  // 원투를 못 한 사람에겐 '원투 아님' 이벤트(연속 미션을 끊는다).
  const nr = round(['p0', 'p1', 'p2', 'p3'], [], []);
  check('원투가 아니면 모두에게 원투 아님 이벤트', ids.every((p) => has(nr, p, 'tichu.round_no_onetwo')) && !nr.some((e) => e.event === 'tichu.one_two'));
  const yr = round(['p0', 'p2', 'p1', 'p3'], [], []);
  check('원투 팀은 one_two, 상대 팀만 원투 아님', has(yr, 'p0', 'tichu.one_two') && has(yr, 'p2', 'tichu.one_two') && has(yr, 'p1', 'tichu.round_no_onetwo') && has(yr, 'p3', 'tichu.round_no_onetwo') && !has(yr, 'p0', 'tichu.round_no_onetwo'), JSON.stringify(yr));
}

{
  const ids = ['p0', 'p1', 'p2', 'p3', 'p4'];
  const names = Object.fromEntries(ids.map((i) => [i, i]));
  const g = new MightyGame(ids, names, {});
  g.trumpSuit = 'spade';
  g.declarer = 'p0'; g.partner = 'p1';
  g.currentBid = { points: 18, suit: 'spade', bidder: 'p0' };
  g.pointCards = { p0: [], p1: [], p2: [], p3: [], p4: [] };
  g._collectRoundMissionEvents({ success: true, declarerPoints: 15 });
  let ev = g.drainMissionEvents();
  check('주공 성공 · 친구 성공 · 18점 비딩', has(ev, 'p0', 'mighty.declarer_success') && has(ev, 'p1', 'mighty.friend_success') && has(ev, 'p0', 'mighty.bid18_success'), JSON.stringify(ev));
  g._collectRoundMissionEvents({ success: false, declarerPoints: 9 });
  ev = g.drainMissionEvents();
  check('실패하면 야당 셋이 막은 걸로', has(ev, 'p2', 'mighty.defend') && has(ev, 'p3', 'mighty.defend') && has(ev, 'p4', 'mighty.defend') && !has(ev, 'p0', 'mighty.defend') && !has(ev, 'p1', 'mighty.defend'), JSON.stringify(ev));
}

{
  // 마이티: 한 '트릭'에서 먹은 점수 카드 수 / 조커콜로 주공 조커 죽이기.
  const ids = ['p0', 'p1', 'p2', 'p3', 'p4'];
  const names = Object.fromEntries(ids.map((i) => [i, i]));
  const mk = () => {
    const g = new MightyGame(ids, names, {});
    g.start();
    g.trumpSuit = 'heart';
    g.declarer = 'p0'; g.partner = 'p1';
    g.currentBid = { points: 15, suit: 'heart', bidder: 'p0' };
    g.pointCards = { p0: [], p1: [], p2: [], p3: [], p4: [] };
    g.tricks = [];
    g.currentTrick = [];
    return g;
  };
  const trick = (plays, setup) => {
    const g = mk();
    if (setup) setup(g);
    g.currentTrick = plays.map(([pid, cardId]) => ({ pid, cardId }));
    g._resolveTrick();
    return g.drainMissionEvents();
  };
  // 점수 카드: A·K·Q·J·10 (같은 문양으로 5장 = 모두 점수 카드).
  let ev = trick([['p0', 'mighty_heart_A'], ['p1', 'mighty_heart_K'], ['p2', 'mighty_heart_Q'], ['p3', 'mighty_heart_J'], ['p4', 'mighty_heart_10']]);
  check('한 트릭에 점수 카드 5장 → 2·4·5장 모두', has(ev, 'p0', 'mighty.point_trick2') && has(ev, 'p0', 'mighty.point_trick4') && has(ev, 'p0', 'mighty.point_trick5'), JSON.stringify(ev));
  ev = trick([['p0', 'mighty_heart_A'], ['p1', 'mighty_heart_K'], ['p2', 'mighty_heart_Q'], ['p3', 'mighty_heart_J'], ['p4', 'mighty_heart_2']]);
  check('점수 카드 4장 → 2·4장, 5장은 아님', has(ev, 'p0', 'mighty.point_trick4') && has(ev, 'p0', 'mighty.point_trick2') && !has(ev, 'p0', 'mighty.point_trick5'), JSON.stringify(ev));
  ev = trick([['p0', 'mighty_heart_A'], ['p1', 'mighty_heart_K'], ['p2', 'mighty_heart_3'], ['p3', 'mighty_heart_4'], ['p4', 'mighty_heart_2']]);
  check('점수 카드 2장 → 2장만', has(ev, 'p0', 'mighty.point_trick2') && !has(ev, 'p0', 'mighty.point_trick4'), JSON.stringify(ev));
  ev = trick([['p0', 'mighty_heart_A'], ['p1', 'mighty_heart_5'], ['p2', 'mighty_heart_3'], ['p3', 'mighty_heart_4'], ['p4', 'mighty_heart_2']]);
  check('점수 카드 1장은 해당 없음', !ev.some((e) => e.event.startsWith('mighty.point_trick')), JSON.stringify(ev));

  // 마이티 카드로 이긴 트릭 + 점수 2장 이상(마이티 자신 포함).
  const g0 = mk();
  const mightyCard = g0.getMightyCard();
  ev = trick([['p0', mightyCard], ['p1', 'mighty_heart_K'], ['p2', 'mighty_heart_3'], ['p3', 'mighty_heart_4'], ['p4', 'mighty_heart_2']]);
  check('마이티로 이긴 트릭 + 점수 2장(마이티 포함)', has(ev, 'p0', 'mighty.mighty_point2') && has(ev, 'p0', 'mighty.mighty_win'), JSON.stringify(ev));
  ev = trick([['p0', mightyCard], ['p1', 'mighty_heart_5'], ['p2', 'mighty_heart_3'], ['p3', 'mighty_heart_4'], ['p4', 'mighty_heart_2']]);
  check('마이티만 점수 카드면 2점 미만', !has(ev, 'p0', 'mighty.mighty_point2') && has(ev, 'p0', 'mighty.mighty_win'), JSON.stringify(ev));
  check('트릭을 이기면 trick_win', has(trick([['p0', 'mighty_heart_A'], ['p1', 'mighty_heart_3'], ['p2', 'mighty_heart_4'], ['p3', 'mighty_heart_5'], ['p4', 'mighty_heart_6']]), 'p0', 'mighty.trick_win'));
  // 라운드가 끝나면 모두에게 round_end 리셋 이벤트.
  const gre = mk();
  gre._collectRoundMissionEvents({ success: true, declarerPoints: 13 });
  const evre = gre.drainMissionEvents();
  check('라운드 끝에 모두에게 mighty.round_end', ids.every((p) => has(evre, p, 'mighty.round_end')), JSON.stringify(evre.map((e) => e.event)));

  // 조커콜: 친구(p1)가 조커콜 카드를 선으로 내고, 주공(p0)이 조커를 냈다.
  const callCard = mk().getJokerCallCard();
  ev = trick([['p1', callCard], ['p0', 'mighty_joker'], ['p2', 'mighty_diamond_3'], ['p3', 'mighty_diamond_4'], ['p4', 'mighty_diamond_5']], (g) => { g.jokerCallActive = true; });
  check('친구가 조커콜로 주공의 조커를 죽임', has(ev, 'p1', 'mighty.joker_kill_friend') && !has(ev, 'p1', 'mighty.joker_kill_defender'), JSON.stringify(ev));
  ev = trick([['p2', callCard], ['p0', 'mighty_joker'], ['p1', 'mighty_diamond_3'], ['p3', 'mighty_diamond_4'], ['p4', 'mighty_diamond_5']], (g) => { g.jokerCallActive = true; });
  check('야당이 조커콜로 주공의 조커를 죽임', has(ev, 'p2', 'mighty.joker_kill_defender') && !has(ev, 'p2', 'mighty.joker_kill_friend'), JSON.stringify(ev));
  ev = trick([['p2', callCard], ['p3', 'mighty_joker'], ['p1', 'mighty_diamond_3'], ['p0', 'mighty_diamond_4'], ['p4', 'mighty_diamond_5']], (g) => { g.jokerCallActive = true; });
  check('주공이 아닌 사람의 조커는 해당 없음', ev.every((e) => !e.event.startsWith('mighty.joker_kill')), JSON.stringify(ev));
  ev = trick([['p2', callCard], ['p0', 'mighty_joker'], ['p1', 'mighty_diamond_3'], ['p3', 'mighty_diamond_4'], ['p4', 'mighty_diamond_5']], (g) => { g.jokerCallActive = false; });
  check('조커콜을 선언하지 않았으면 해당 없음', ev.every((e) => !e.event.startsWith('mighty.joker_kill')), JSON.stringify(ev));
}

{
  const ids = ['p0', 'p1', 'p2'];
  const names = { p0: 'A', p1: 'B', p2: 'C' };
  const g = new SkullKingGame(ids, names, {});
  g.state = 'playing';
  g.hands = { p0: ['x'], p1: ['x'], p2: ['x'] };
  g.tricks = { p0: 0, p1: 0, p2: 0 };
  g.bonuses = { p0: 0, p1: 0, p2: 0 };
  g.lootAlliances = [];
  g.playerCount = 3;
  g.currentTrick = [
    { playerId: 'p0', cardId: 'sk_pirate_1' },
    { playerId: 'p1', cardId: 'sk_escape_1' },
    { playerId: 'p2', cardId: 'sk_escape_2' },
  ];
  g.completeTrick();
  let ev = g.drainMissionEvents();
  check('해적으로 이기면', has(ev, 'p0', 'sk.pirate_win'), JSON.stringify(ev));
  g.currentTrick = [
    { playerId: 'p0', cardId: 'sk_mermaid_1' },
    { playerId: 'p1', cardId: 'sk_escape_1' },
    { playerId: 'p2', cardId: 'sk_escape_2' },
  ];
  g.completeTrick();
  check('인어로 이기면', has(g.drainMissionEvents(), 'p0', 'sk.mermaid_win'));
  g.currentTrick = [
    { playerId: 'p0', cardId: 'sk_skull_king' },
    { playerId: 'p1', cardId: 'sk_escape_1' },
    { playerId: 'p2', cardId: 'sk_escape_2' },
  ];
  g.completeTrick();
  check('스컬킹으로 이기면', has(g.drainMissionEvents(), 'p0', 'sk.skullking_win'));
}

{
  const LL = require('./game/love_letter/LoveLetterGame');
  const ids = ['p0', 'p1', 'p2'];
  const names = { p0: 'A', p1: 'B', p2: 'C' };
  const g = new LL(ids, names, {});
  g.start && g.start();
  // 경비병이 맞췄을 때.
  const setup = (actorCard, targetCard, type, guess) => {
    const gg = new LL(ids, names, {});
    gg.start();
    gg.hands = { p0: [actorCard], p1: [targetCard], p2: ['ll_countess'] };
    gg.eliminated = { p0: false, p1: false, p2: false };
    gg.discardPiles = { p0: [], p1: [], p2: [] };
    gg.pendingEffect = { type, playerId: 'p0', targetId: 'p1', guess, resolved: false };
    gg.state = 'effect_resolve';
    gg._resolveEffect();
    return gg.drainMissionEvents();
  };
  let ev = setup('ll_guard_1', 'll_prince_1', 'guard', 'prince');
  check('경비병 적중 + 탈락', has(ev, 'p0', 'll.guard_hit') && has(ev, 'p0', 'll.knock_out'), JSON.stringify(ev));
  ev = setup('ll_guard_1', 'll_prince_1', 'guard', 'king');
  check('경비병 빗나감은 없음', ev.length === 0, JSON.stringify(ev));
  ev = setup('ll_king', 'll_guard_1', 'baron', null);
  check('남작 대결 승리(내 카드가 높음)', has(ev, 'p0', 'll.baron_win') && has(ev, 'p0', 'll.knock_out'), JSON.stringify(ev));
  ev = setup('ll_guard_1', 'll_king', 'baron', null);
  check('남작 대결에서 지면 이벤트 없음', ev.length === 0, JSON.stringify(ev));
}

console.log(failures ? `\n실패 ${failures}건` : '\n전부 통과');
process.exit(failures ? 1 : 0);
