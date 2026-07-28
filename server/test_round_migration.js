'use strict';
/**
 * Round-boundary migration test.
 *
 * Simulates the blue/green drain path for all four game types:
 *   blue: start match -> play a round -> land at round_end with scores
 *         -> serializeRoom() (the matchProgress half of it)
 *   green: adoptRoom(payload) -> players reconnect under NEW playerIds
 *          -> startGame() resumes the match
 *
 * Asserts the cumulative score, the round counter and the seating all
 * survive, and that Tichu's teams (which are seat-derived) don't rotate.
 */


const LobbyManager = require('./lobby/LobbyManager');

let failures = 0;
function check(label, cond, detail) {
  if (cond) {
    console.log(`  ok   ${label}`);
  } else {
    failures++;
    console.log(`  FAIL ${label}${detail ? ` — ${detail}` : ''}`);
  }
}

function emptySlots(room) {
  const out = [];
  for (let i = 0; i < room.maxPlayers; i++) if (!room.players[i]) out.push(i);
  return out;
}

// Mirrors server.js serializeRoom() for the fields this test cares about.
function serializeRoom(room) {
  if (!room) return null;
  let matchProgress = null;
  if (room.game) {
    if (room.game.state !== 'round_end') return null;
    if (typeof room.game.getMatchProgress !== 'function') return null;
    matchProgress = room.game.getMatchProgress();
    if (!matchProgress) return null;
  }
  return {
    id: room.id,
    name: room.name,
    gameType: room.gameType,
    maxPlayers: room.maxPlayers,
    hostId: room.hostId,
    hostNickname: room.hostNickname,
    targetScore: room.targetScore,
    turnTimeLimit: room.turnTimeLimit,
    isRanked: !!room.isRanked,
    skExpansions: [...(room.skExpansions || [])],
    // Mirrors server.js: mid-match the players array is compacted, so the
    // pre-game blockedSlots indices no longer apply.
    blockedSlots: matchProgress ? emptySlots(room) : [...(room.blockedSlots || [])],
    autoBlockedSlots: matchProgress ? [] : [...(room.autoBlockedSlots || [])],
    randomSeating: !!room.randomSeating,
    matchProgress,
    players: room.players.map((p, slot) => {
      if (!p) return null;
      return {
        slot,
        id: p.id,
        nickname: p.nickname,
        isBot: !!p.isBot,
        ready: matchProgress ? true : !!p.ready,
      };
    }),
  };
}

function seatPlayers(room, nicknames) {
  room.players = Array.from({ length: room.maxPlayers }, () => null);
  nicknames.forEach((nickname, i) => {
    room.players[i] = {
      id: `blue-${nickname}`,
      nickname,
      connected: true,
      ready: true,
      isBot: false,
    };
  });
  room.hostId = room.players[0].id;
  room.hostNickname = room.players[0].nickname;
}

function cumulativeFieldFor(gameType) {
  if (gameType === 'tichu') return 'totalScores';
  if (gameType === 'skull_king') return 'totalScores';
  if (gameType === 'mighty') return 'scores';
  return 'tokens'; // love_letter
}

const CASES = [
  { gameType: 'tichu', nicknames: ['앨리스', '밥', '캐럴', '데이브'] },
  { gameType: 'skull_king', nicknames: ['앨리스', '밥', '캐럴', '데이브'] },
  { gameType: 'mighty', nicknames: ['앨리스', '밥', '캐럴', '데이브', '이브'] },
  { gameType: 'love_letter', nicknames: ['앨리스', '밥', '캐럴', '데이브'] },
];

for (const { gameType, nicknames } of CASES) {
  console.log(`\n=== ${gameType} ===`);

  // ---------- blue: match in progress, parked at a round boundary ----------
  const blue = new LobbyManager();
  const blueRoom = blue.createRoom('방', 'blue-host', nicknames[0], '', false, 30, 1000, gameType, nicknames.length);
  seatPlayers(blueRoom, nicknames);
  if (!blueRoom.startGame()) {
    console.log('  FAIL could not start game on blue');
    failures++;
    continue;
  }

  const field = cumulativeFieldFor(gameType);
  const game = blueRoom.game;

  // Fabricate a mid-match standing: 3 rounds played, distinct scores so a
  // mis-mapped nickname would be obvious.
  game.round = 3;
  const expected = {};
  if (gameType === 'tichu') {
    game.totalScores = { teamA: 320, teamB: 180 };
  } else {
    game.playerIds.forEach((pid, i) => {
      game[field][pid] = (i + 1) * 7;
      expected[game.playerNames[pid]] = (i + 1) * 7;
    });
  }
  // Rotation state that belongs to the match, not the round — it must
  // survive the hop rather than being re-rolled on the peer.
  let rotation = null;
  if (gameType === 'skull_king') {
    game.initialDealerIndex = 2;
    rotation = { dealer: 2 };
  } else if (gameType === 'mighty') {
    game.dealerIndex = 3;
    rotation = { dealer: (3 + 1) % game.playerCount }; // startNewRound advances one seat
  } else if (gameType === 'love_letter') {
    game.currentPlayer = game.playerIds[2];
    rotation = { leader: game.playerNames[game.playerIds[2]] };
  }

  const blueSeatOrder = game.playerIds.map((id) => game.playerNames[id]);
  const blueTeams = gameType === 'tichu'
    ? { teamA: game.teams.teamA.map((id) => game.playerNames[id]), teamB: game.teams.teamB.map((id) => game.playerNames[id]) }
    : null;
  game.state = 'round_end';

  const payload = serializeRoom(blueRoom);
  check('round_end room serialises', payload !== null);
  check('payload carries matchProgress', !!payload?.matchProgress);
  check('players land pre-readied', payload.players.filter(Boolean).every((p) => p.ready === true));

  // A mid-round room must NOT be migratable.
  game.state = 'playing';
  check('mid-round room refuses to serialise', serializeRoom(blueRoom) === null);
  game.state = 'round_end';

  // ---------- green: adopt, reconnect with new ids, resume ----------
  const green = new LobbyManager();
  const greenRoom = green.adoptRoom(JSON.parse(JSON.stringify(payload)));
  check('adopted on peer', !!greenRoom);
  check('matchProgress stored on room', !!greenRoom.matchProgress);
  check('no game object yet (waiting state)', greenRoom.game === null);

  // Every human reconnects: the LB hands out fresh playerIds. This is the
  // step that would break an id-keyed payload.
  for (const p of greenRoom.players) {
    if (!p) continue;
    const res = greenRoom.reconnectPlayer(p.nickname, `green-${p.nickname}`);
    if (!res.success) { failures++; console.log(`  FAIL reconnect ${p.nickname}`); }
  }
  check('all ids changed on reconnect', greenRoom.players.filter(Boolean).every((p) => p.id.startsWith('green-')));

  check('startGame resumes', greenRoom.startGame() === true);
  const resumed = greenRoom.game;
  check('matchProgress consumed', greenRoom.matchProgress === null);

  const resumedSeatOrder = resumed.playerIds.map((id) => resumed.playerNames[id]);
  check('seating preserved', JSON.stringify(resumedSeatOrder) === JSON.stringify(blueSeatOrder),
    `${JSON.stringify(resumedSeatOrder)} vs ${JSON.stringify(blueSeatOrder)}`);
  check('round counter advanced to 4', resumed.round === 4, `got ${resumed.round}`);

  if (gameType === 'tichu') {
    check('team totals carried', resumed.totalScores.teamA === 320 && resumed.totalScores.teamB === 180,
      JSON.stringify(resumed.totalScores));
    const resumedTeams = {
      teamA: resumed.teams.teamA.map((id) => resumed.playerNames[id]),
      teamB: resumed.teams.teamB.map((id) => resumed.playerNames[id]),
    };
    check('teams unchanged', JSON.stringify(resumedTeams) === JSON.stringify(blueTeams),
      `${JSON.stringify(resumedTeams)} vs ${JSON.stringify(blueTeams)}`);
  } else {
    const got = {};
    for (const pid of resumed.playerIds) got[resumed.playerNames[pid]] = resumed[field][pid];
    check('per-player totals carried under new ids', JSON.stringify(got) === JSON.stringify(expected),
      `${JSON.stringify(got)} vs ${JSON.stringify(expected)}`);
  }

  if (gameType === 'skull_king') {
    // SK deals `round` cards — resuming at round 4 must deal 4, not 1.
    const handSizes = resumed.playerIds.map((pid) => resumed.hands[pid].length);
    check('SK dealt round-4 hands (4 cards)', handSizes.every((n) => n === 4), `hand sizes ${handSizes}`);
    check('SK dealer rotation continues', resumed.initialDealerIndex === rotation.dealer,
      `got ${resumed.initialDealerIndex}, expected ${rotation.dealer}`);
  }
  if (gameType === 'mighty') {
    check('mighty dealer advanced exactly one seat', resumed.dealerIndex === rotation.dealer,
      `got ${resumed.dealerIndex}, expected ${rotation.dealer}`);
  }
  if (gameType === 'love_letter') {
    check('LL leader carried (last round winner leads)',
      resumed.playerNames[resumed.currentPlayer] === rotation.leader,
      `got ${resumed.playerNames[resumed.currentPlayer]}, expected ${rotation.leader}`);
  }

  // ---------- roster drift must invalidate the carried state ----------
  const drift = new LobbyManager();
  const driftRoom = drift.adoptRoom(JSON.parse(JSON.stringify(payload)));
  const victim = driftRoom.players.find((p) => p !== null && p.nickname !== driftRoom.hostNickname);
  victim.nickname = '다른사람';   // someone never came back, a different player took the seat
  driftRoom.startGame();
  const driftField = driftRoom.game[cumulativeFieldFor(gameType)];
  const driftTotal = gameType === 'tichu'
    ? driftField.teamA + driftField.teamB
    : Object.values(driftField).reduce((a, b) => a + b, 0);
  check('roster drift discards stale progress', driftTotal === 0 && driftRoom.game.round === 1,
    `total=${driftTotal} round=${driftRoom.game.round}`);
}

// ── 5-player mighty in a 6-seat room ───────────────────────────────────────
// startGame compacts room.players, so a blocked seat that isn't the last one
// ends up describing a seat that is now occupied. Serialising the pre-game
// blockedSlots verbatim made mighty's "every non-blocked seat must be filled"
// check reject the migrated roster on the peer, losing the whole match.
console.log('\n=== mighty 5p in a 6-seat room, blocked seat in the middle ===');
{
  const blue = new LobbyManager();
  const room = blue.createRoom('방', 'blue-host', '앨리스', '', false, 30, 50, 'mighty', 6);
  room.players = [
    { id: 'blue-앨리스', nickname: '앨리스', connected: true, isBot: false },
    { id: 'blue-밥', nickname: '밥', connected: true, isBot: false },
    null, // host blocked this middle seat for 5-player mode
    { id: 'blue-캐럴', nickname: '캐럴', connected: true, isBot: false },
    { id: 'blue-데이브', nickname: '데이브', connected: true, isBot: false },
    { id: 'blue-이브', nickname: '이브', connected: true, isBot: false },
  ];
  room.blockedSlots = new Set([2]);
  room.hostId = 'blue-앨리스';
  room.hostNickname = '앨리스';

  check('starts on blue', room.startGame() === true);
  room.game.round = 3;
  room.game.playerIds.forEach((pid, i) => { room.game.scores[pid] = (i + 1) * 7; });
  const expected = {};
  room.game.playerIds.forEach((pid) => { expected[room.game.playerNames[pid]] = room.game.scores[pid]; });
  room.game.state = 'round_end';

  const payload = serializeRoom(room);
  check('blocked seat re-derived to the empty one', JSON.stringify(payload.blockedSlots) === '[5]',
    JSON.stringify(payload.blockedSlots));

  const green = new LobbyManager();
  const greenRoom = green.adoptRoom(JSON.parse(JSON.stringify(payload)));
  for (const p of greenRoom.players) {
    if (p) greenRoom.reconnectPlayer(p.nickname, `green-${p.nickname}`);
  }
  check('resumes on the peer', greenRoom.startGame() === true);
  if (greenRoom.game) {
    const got = {};
    for (const pid of greenRoom.game.playerIds) got[greenRoom.game.playerNames[pid]] = greenRoom.game.scores[pid];
    check('standings survived', JSON.stringify(got) === JSON.stringify(expected),
      `${JSON.stringify(got)} vs ${JSON.stringify(expected)}`);
    check('round advanced to 4', greenRoom.game.round === 4, `got ${greenRoom.game.round}`);
    check('still a 5-player game', greenRoom.game.playerIds.length === 5,
      `got ${greenRoom.game.playerIds.length}`);
  }
}

console.log(`\n${failures === 0 ? 'ALL PASS' : `${failures} FAILURE(S)`}`);
process.exit(failures === 0 ? 0 : 1);
