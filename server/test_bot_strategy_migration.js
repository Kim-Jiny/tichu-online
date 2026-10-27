'use strict';

/**
 * Skull King / Love Letter bots run the search strategy ('mc') everywhere a bot is
 * seated — new room, mid-game walkout, and a room handed over by a peer server —
 * while apps are only ever told 'heuristic' (an unknown strategy makes the client
 * draw a chip next to the bot). Other games keep the strategy they were given.
 *
 *   node test_bot_strategy_migration.js
 */

const assert = require('assert');
const LobbyManager = require('./lobby/LobbyManager');
const GameRoom = require('./game/GameRoom');
const { publicBotStrategy, BotPlayer } = require('./game/BotPlayer');

// 'mc' is a valid strategy, and unknown ones still fall back (an old server given 'mc' must not break).
assert.strictEqual(new BotPlayer('b', 'b', 'fast', 'mc').strategy, 'mc');
assert.strictEqual(new BotPlayer('b', 'b', 'fast', 'nonsense').strategy, 'heuristic');
assert.strictEqual(publicBotStrategy('mc'), 'heuristic');
assert.strictEqual(publicBotStrategy('mixoracle'), 'mixoracle');
assert.strictEqual(publicBotStrategy(undefined), null);

function bots(room) { return [...room.bots.values()]; }

// A new room: whatever the client asks for, SK/LL bots get 'mc'; tichu/mighty are unchanged.
for (const [gameType, max, ask, want] of [
  ['skull_king', 4, 'heuristic', 'mc'],
  ['love_letter', 3, 'heuristic', 'mc'],
  ['mighty', 5, 'heuristic', 'mixoracle'],
  ['tichu', 4, 'winrate', 'winrate'],
]) {
  const room = new GameRoom(`r-${gameType}`, 'room', 'host', 'host', '', false, 30, 100, gameType, max, []);
  room.addBot(undefined, 'ko', 'fast', ask);
  assert.strictEqual(bots(room)[0].strategy, want, `${gameType}: seated with ${bots(room)[0].strategy}`);
  const shown = room.getState().players.find((p) => p && p.isBot);
  assert.notStrictEqual(shown.botStrategy, 'mc', `${gameType}: 'mc' reached the app`);
}

// A room handed over by a peer: the peer may only know 'heuristic' (older server) or 'mc'.
function payload(gameType, max, strategy) {
  return {
    id: `mig-${gameType}-${strategy}`, name: 'migrated', hostId: null, hostNickname: null,
    gameType, maxPlayers: max,
    players: [
      { slot: 0, id: 'old_bot_1', nickname: '봇 1', isBot: true, botSpeed: 'fast', botStrategy: strategy },
      { slot: 1, id: 'old_bot_2', nickname: '봇 2', isBot: true, botSpeed: 'fast', botStrategy: strategy },
    ],
  };
}
const lobby = new LobbyManager();
for (const [gameType, max, sent, want] of [
  ['skull_king', 4, 'heuristic', 'mc'],   // from an older server
  ['skull_king', 4, 'mc', 'mc'],          // from this version
  ['love_letter', 3, 'heuristic', 'mc'],
  ['love_letter', 3, 'mc', 'mc'],
  ['mighty', 5, 'mixoracle', 'mixoracle'],
  ['tichu', 4, 'winrate', 'winrate'],
]) {
  const adopted = lobby.adoptRoom(payload(gameType, max, sent));
  assert.ok(adopted, `${gameType}/${sent}: room not adopted`);
  const room = lobby.getRoom(`mig-${gameType}-${sent}`);
  assert.ok(room, `${gameType}/${sent}: room missing`);
  for (const b of bots(room)) assert.strictEqual(b.strategy, want, `${gameType} sent=${sent}: seated as ${b.strategy}`);
}

console.log('bot strategy migration ok');
