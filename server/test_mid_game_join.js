/**
 * Mid-game seat handoff: does a seat survive changing hands?
 *
 * The whole feature rests on one bet — that a seat is nothing but a playerId
 * to the engine, so rewriting the id moves the hand, the score, the turn and
 * the declarations with it. This checks that bet directly on every game type,
 * because the id-bearing field list differs per engine and a field missed in
 * one of them silently eats a player's cards.
 *
 * Run: node server/test_mid_game_join.js
 */
const GameRoom = require('./game/GameRoom');

let failures = 0;
function check(label, cond, detail = '') {
  if (cond) {
    console.log(`  ok   ${label}`);
  } else {
    failures++;
    console.log(`  FAIL ${label}${detail ? ` — ${detail}` : ''}`);
  }
}

/**
 * Snapshot the per-seat state that must survive a handoff.
 *
 * `cards` counts as well as fingerprints: an empty hand would make the
 * before/after comparison pass by matching nothing, so the caller asserts the
 * count is non-zero and the check has something to fail on.
 */
function seatSnapshot(game, playerId) {
  const hand = game.hands?.[playerId] || [];
  return {
    // Engines store hands as card-id strings in some games and card objects in
    // others — normalise so this works across all four.
    hand: hand.map((c) => (typeof c === 'string' ? c : c && c.id)).sort().join(','),
    cards: hand.length,
    isCurrent: game.currentPlayer === playerId,
    inPlayerIds: game.playerIds.includes(playerId),
  };
}

function makeRoom(gameType, maxPlayers, botCount) {
  const room = new GameRoom(
    `room_test_${gameType}`, `${gameType} room`, 'player_host', '호스트',
    '', false, 30, 1000, gameType, maxPlayers, [], true, true,
  );
  for (let i = 0; i < botCount; i++) {
    const r = room.addBot(undefined, 'ko', 'fast', undefined);
    if (!r.success) throw new Error(`addBot failed for ${gameType}: ${r.messageKey}`);
  }
  return room;
}

function runCase(gameType, maxPlayers, seats) {
  console.log(`\n[${gameType}]`);
  // One human (the host) + bots filling the rest.
  const room = makeRoom(gameType, maxPlayers, seats - 1);
  room.startGame();
  const game = room.game;
  if (!game) { failures++; console.log('  FAIL game did not start'); return; }

  check('option on', room.allowMidGameJoin === true);
  check('bot seats present', room.getBotSeatCount() === seats - 1,
    `got ${room.getBotSeatCount()}, want ${seats - 1}`);

  // ── bot → human ────────────────────────────────────────────────────────
  const botSlot = room.getBotSeatSlots()[0];
  const botId = room.players[botSlot].id;
  const before = seatSnapshot(game, botId);
  const joined = room.takeOverBotSeat(botId, 'player_joiner', '난입');
  check('takeOverBotSeat succeeded', joined.success, joined.messageKey);
  const after = seatSnapshot(game, 'player_joiner');

  check('bot actually held cards', before.cards > 0, `cards=${before.cards}`);
  check('hand carried over', before.hand === after.hand && after.cards === before.cards,
    `before=${before.hand.slice(0, 40)} after=${after.hand.slice(0, 40)}`);
  check('turn ownership carried', before.isCurrent === after.isCurrent);
  check('seat in playerIds', after.inPlayerIds);
  check('old bot id fully gone',
    !game.playerIds.includes(botId) && game.hands?.[botId] === undefined);
  check('display name is the joiner', game.playerNames['player_joiner'] === '난입');
  check('room roster shows a human', room.players[botSlot].isBot === false);
  check('bot deregistered', room.isBot(botId) === false);
  check('seat count unchanged',
    game.playerIds.length === seats, `got ${game.playerIds.length}, want ${seats}`);

  // ── human → bot ────────────────────────────────────────────────────────
  const leaveBefore = seatSnapshot(game, 'player_joiner');
  const left = room.replaceWithBot('player_joiner', 'ko');
  check('replaceWithBot succeeded', left.success, left.messageKey);
  const leaveAfter = seatSnapshot(game, left.botId);
  check('hand carried back',
    leaveBefore.hand === leaveAfter.hand && leaveAfter.cards === leaveBefore.cards);
  check('turn ownership carried back', leaveBefore.isCurrent === leaveAfter.isCurrent);
  check('replacement is a registered bot', room.isBot(left.botId) === true);
  check('seat count still right', game.playerIds.length === seats);

  // ── last human may not walk ────────────────────────────────────────────
  // Only the host is human now; walking would leave bots playing to nobody.
  const lastOut = room.replaceWithBot('player_host', 'ko');
  check('last human refused', lastOut.success === false
    && lastOut.messageKey === 'midjoin_last_human', lastOut.messageKey);
}

console.log('mid-game seat handoff');
runCase('tichu', 4, 4);
runCase('skull_king', 4, 4);
runCase('mighty', 5, 5);
runCase('love_letter', 4, 4);

// Ranked rooms hold no bots, so the option must never latch on.
console.log('\n[ranked guard]');
const ranked = new GameRoom(
  'room_test_ranked', 'ranked', 'player_host', '호스트',
  '', true, 30, 1000, 'tichu', 4, [], true, true,
);
check('ranked room forces the option off', ranked.allowMidGameJoin === false);

// Spectating off means nobody is ever positioned to break in.
const noSpec = new GameRoom(
  'room_test_nospec', 'no spectators', 'player_host', '호스트',
  '', false, 30, 1000, 'tichu', 4, [], false, true,
);
check('spectator-less room forces the option off', noSpec.allowMidGameJoin === false);

// A room that migrates between instances during a deploy must land with the
// same rules it left with. Both flags used to be dropped by adoptRoom, so a
// spectator-free room came back with an audience.
console.log('\n[migration round-trip]');
{
  const LobbyManager = require('./lobby/LobbyManager');
  const lobby = new LobbyManager();
  const base = (extra) => ({
    id: `room_adopt_${Math.floor(failures + Object.keys(extra).length + 1)}_${extra.tag}`,
    name: 'migrated', hostId: 'player_h', hostNickname: '호스트',
    gameType: 'tichu', maxPlayers: 4, players: [], ...extra,
  });

  const kept = lobby.adoptRoom(base({
    tag: 'a', allowSpectators: true, allowMidGameJoin: true,
  }));
  check('option survives migration', kept?.allowMidGameJoin === true);
  check('spectating survives migration', kept?.allowSpectators === true);

  const noSpec = lobby.adoptRoom(base({
    tag: 'b', allowSpectators: false, allowMidGameJoin: true,
  }));
  check('spectators-off survives migration', noSpec?.allowSpectators === false);
  check('option dropped when spectating is off',
    noSpec?.allowMidGameJoin === false);

  // A peer old enough not to send the field predates it being carried, and
  // its rooms allowed spectating — absent must read as true, not false.
  const legacy = lobby.adoptRoom(base({ tag: 'c' }));
  check('missing allowSpectators defaults to on', legacy?.allowSpectators === true);
  check('missing allowMidGameJoin defaults to off',
    legacy?.allowMidGameJoin === false);

  const ranked = lobby.adoptRoom(base({
    tag: 'd', isRanked: true, allowSpectators: true, allowMidGameJoin: true,
  }));
  check('ranked migration still forces the option off',
    ranked?.allowMidGameJoin === false);
}

console.log(failures === 0 ? '\nPASS' : `\n${failures} FAILURE(S)`);
process.exit(failures === 0 ? 0 : 1);
