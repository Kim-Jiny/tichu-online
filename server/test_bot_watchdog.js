'use strict';

/**
 * Verifies the stuck-bot fix actually recovers a frozen room — exercising the
 * REAL production code (game/botWatchdog.js + TichuGame.getPendingActor), not a
 * reimplementation. This is the proof that the watchdog does something.
 */

const assert = require('assert');
const { botWatchdogTick } = require('./game/botWatchdog');
const TichuGame = require('./game/TichuGame');

let pass = 0;
function ok(name, cond) {
  assert.ok(cond, name);
  console.log(`  ✓ ${name}`);
  pass++;
}

// Minimal room doubles. isBot(id) => true for ids starting with 'bot'.
function room({ state = 'playing', pendingActor, bots = ['bot1'] }) {
  return {
    gameType: 'tichu',
    getBotIds: () => bots,
    isBot: (id) => typeof id === 'string' && id.startsWith('bot'),
    game: { state, getPendingActor: () => pendingActor },
  };
}
const asMap = (obj) => new Map(Object.entries(obj));

console.log('\n[1] Watchdog: stranded bot room is recovered after threshold ticks');
{
  // Bot is the pending actor, but NO timer is queued = the freeze condition.
  const rooms = asMap({ r1: room({ pendingActor: 'bot1' }) });
  const pendingBotTimers = {}; // nothing scheduled
  const seen = {};

  let out = botWatchdogTick({ rooms, pendingBotTimers, seen });
  ok('tick 1 does NOT recover yet (avoids racing a sub-second gap)', out.length === 0);
  ok('tick 1 records it as seen', seen.r1 === 1);

  out = botWatchdogTick({ rooms, pendingBotTimers, seen });
  ok('tick 2 recovers the room', out.length === 1 && out[0].roomId === 'r1');
  ok('recovery reports the stranded actor', out[0].actor === 'bot1');
  ok('counter reset after recovery', seen.r1 === undefined);
}

console.log('\n[2] Watchdog: healthy room (bot timer queued) is NEVER touched');
{
  const rooms = asMap({ r1: room({ pendingActor: 'bot1' }) });
  const pendingBotTimers = { r1: {} }; // a timer IS scheduled
  const seen = {};
  for (let i = 0; i < 5; i++) {
    const out = botWatchdogTick({ rooms, pendingBotTimers, seen });
    assert.strictEqual(out.length, 0);
  }
  ok('no recovery across 5 ticks while a timer is queued', true);
  ok('counter stays clear', seen.r1 === undefined);
}

console.log("\n[3] Watchdog: human's turn is never force-rescheduled");
{
  const rooms = asMap({ r1: room({ pendingActor: 'human1' }) });
  const seen = {};
  let out;
  for (let i = 0; i < 3; i++) out = botWatchdogTick({ rooms, pendingBotTimers: {}, seen });
  ok('human pending actor → no recovery', out.length === 0 && seen.r1 === undefined);
}

console.log('\n[4] Watchdog: a transient 1-tick gap then resume does NOT recover');
{
  const r = room({ pendingActor: 'bot1' });
  const rooms = asMap({ r1: r });
  const seen = {};
  botWatchdogTick({ rooms, pendingBotTimers: {}, seen });       // tick1: stranded (seen=1)
  const out = botWatchdogTick({ rooms, pendingBotTimers: { r1: {} }, seen }); // tick2: timer appeared
  ok('counter cleared when scheduling resumes', seen.r1 === undefined);
  ok('no false recovery on a transient gap', out.length === 0);
}

console.log('\n[4b] Watchdog: terminal/transitional states are never recovered');
{
  for (const st of ['round_end', 'game_end', 'trick_end', 'dealing', 'waiting']) {
    const rooms = asMap({ r1: room({ state: st, pendingActor: 'bot1' }) });
    const seen = {};
    let out;
    for (let i = 0; i < 3; i++) out = botWatchdogTick({ rooms, pendingBotTimers: {}, seen });
    assert.strictEqual(out.length, 0, `state ${st} must not recover`);
    assert.strictEqual(seen.r1, undefined, `state ${st} must not accrue`);
  }
  ok('round_end/game_end/trick_end/dealing/waiting → no false recovery', true);
}

console.log('\n[5] TichuGame.getPendingActor targets the obligated actor');
{
  const ids = ['p0', 'p1', 'p2', 'p3'];
  const names = { p0: 'p0', p1: 'p1', p2: 'p2', p3: 'p3' };
  const g = new TichuGame(ids, names);
  g.start();

  // Normal play → currentPlayer.
  g.needsToCallRank = null; g.dragonPending = false; g.dragonDecider = null;
  g.currentPlayer = 'p2';
  ok('normal play → currentPlayer', g.getPendingActor() === 'p2');

  // Bird played → the rank-caller owes the action, even though play has moved on.
  g.needsToCallRank = 'p1'; g.currentPlayer = 'p3';
  ok('needsToCallRank wins over currentPlayer', g.getPendingActor() === 'p1');

  // Dragon won → the decider owes the give.
  g.needsToCallRank = null; g.dragonPending = true; g.dragonDecider = 'p0'; g.currentPlayer = 'p3';
  ok('dragonDecider wins over currentPlayer', g.getPendingActor() === 'p0');
}

console.log('\n[6] End-to-end: a frozen Tichu room where it is a BOT\'s dragon-give');
{
  // Reproduce the exact shape that froze in prod: a bot owes the dragon give,
  // currentPlayer is someone else, and nothing is scheduled. Old code: stuck
  // forever (server only looked at currentPlayer). New code: watchdog targets
  // the right bot and recovers.
  const ids = ['bot1', 'p1', 'p2', 'p3'];
  const names = {}; ids.forEach((p) => (names[p] = p));
  const g = new TichuGame(ids, names);
  g.start();
  g.state = 'playing';
  g.dragonPending = true; g.dragonDecider = 'bot1'; g.currentPlayer = 'p3';

  const r = {
    gameType: 'tichu',
    getBotIds: () => ['bot1'],
    isBot: (id) => id === 'bot1',
    game: g,
  };
  const rooms = asMap({ frozen: r });
  const seen = {};
  ok('getPendingActor resolves to the owed bot', g.getPendingActor() === 'bot1');
  botWatchdogTick({ rooms, pendingBotTimers: {}, seen });
  const out = botWatchdogTick({ rooms, pendingBotTimers: {}, seen });
  ok('watchdog flags the frozen room for recovery', out.length === 1 && out[0].roomId === 'frozen');
  ok('and identifies the bot that was stuck', out[0].actor === 'bot1');
  // getAutoTimeoutAction (what scheduleBotActions(force) ultimately applies)
  // must produce a legal dragon give for that bot — i.e. recovery is real.
  const fb = g.getAutoTimeoutAction('bot1');
  ok('engine yields a legal recovery action (dragon_give)', fb && fb.type === 'dragon_give');
}

console.log(`\n✅ ALL ${pass} ASSERTIONS PASSED\n`);
