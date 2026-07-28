'use strict';
/**
 * Zombie-room sweep tests.
 *
 * The case that motivated this: a mighty room whose only human disconnected
 * kept 5 bots alive for 42 minutes because the sweep skipped rooms with a
 * game in progress, and in-game disconnects arm no removal timer. It took an
 * admin force-close to free it.
 */

const { findAbandonedRooms } = require('./lobby/zombieSweep');

const MAX_AGE = 30 * 60 * 1000;
const NOW = 1_000_000_000;

let failures = 0;
function check(label, cond, detail) {
  if (cond) console.log(`  ok   ${label}`);
  else { failures++; console.log(`  FAIL ${label}${detail ? ` — ${detail}` : ''}`); }
}

const human = (nickname, connected) => ({ nickname, isBot: false, connected, id: `p_${nickname}` });
const bot = (n) => ({ nickname: `봇 ${n}`, isBot: true, connected: true, id: `bot_${n}` });

function sweep(room, sessions = {}) {
  const playerSessions = new Map(Object.entries(sessions));
  return findAbandonedRooms({
    rooms: new Map([['room_2', room]]),
    playerSessions,
    now: NOW,
    maxAge: MAX_AGE,
  });
}

const inGame = (players, state = 'round_end') => ({
  players,
  gameType: 'mighty',
  game: { state },
});
const waiting = (players) => ({ players, gameType: 'mighty', game: null });

// ── the production incident ────────────────────────────────────────────────
{
  console.log('\n=== in-game room, lone human gone, session expired ===');
  const room = inGame([human('텐하이', false), bot(1), bot(2), bot(3), bot(4), bot(5)]);
  const out = sweep(room, { 텐하이: { disconnectedAt: NOW - MAX_AGE - 1 } });
  check('reaped', out.length === 1, JSON.stringify(out));
  check('reports the state it froze in', out[0]?.stuckIn === 'mighty/round_end', out[0]?.stuckIn);
}

{
  console.log('\n=== same room, but the session has NOT expired yet ===');
  const room = inGame([human('텐하이', false), bot(1)]);
  const out = sweep(room, { 텐하이: { disconnectedAt: NOW - 60_000 } });
  check('left alone — the player can still come back', out.length === 0, JSON.stringify(out));
}

{
  console.log('\n=== in-game room with someone still connected ===');
  const room = inGame([human('텐하이', true), human('하민', false), bot(1)]);
  const out = sweep(room, { 하민: { disconnectedAt: NOW - MAX_AGE - 1 } });
  check('left alone — a live game is being played', out.length === 0, JSON.stringify(out));
}

{
  console.log('\n=== in-game room, no session entry at all ===');
  // Sessions are pruned earlier in the same sweep tick, so a missing entry
  // means "expired", not "never existed".
  const room = inGame([human('텐하이', false), bot(1)], 'playing');
  const out = sweep(room, {});
  check('reaped', out.length === 1, JSON.stringify(out));
  check('reports mid-play freeze', out[0]?.stuckIn === 'mighty/playing', out[0]?.stuckIn);
}

// ── waiting rooms: unchanged behaviour ─────────────────────────────────────
{
  console.log('\n=== waiting room, everyone gone and expired ===');
  const out = sweep(waiting([human('텐하이', false)]), { 텐하이: { disconnectedAt: NOW - MAX_AGE - 1 } });
  check('reaped', out.length === 1, JSON.stringify(out));
  check('no stuckIn (no game to be stuck in)', out[0]?.stuckIn === null, String(out[0]?.stuckIn));
}

{
  console.log('\n=== waiting room, host connected ===');
  const out = sweep(waiting([human('텐하이', true), null, bot(1)]));
  check('left alone', out.length === 0, JSON.stringify(out));
}

{
  console.log('\n=== bot-only room ===');
  const out = sweep(inGame([bot(1), bot(2)]));
  check('reaped as having no humans', out.length === 1 && out[0].reason === 'no humans', JSON.stringify(out));
}

{
  console.log('\n=== empty / malformed rooms ===');
  const out = findAbandonedRooms({
    rooms: new Map([['a', null], ['b', {}], ['c', { players: [null, null], game: null }]]),
    playerSessions: new Map(),
    now: NOW,
    maxAge: MAX_AGE,
  });
  check('skips null/malformed, reaps the empty one', out.length === 1 && out[0].id === 'c', JSON.stringify(out));
}

console.log(`\n${failures === 0 ? 'ALL PASS' : `${failures} FAILURE(S)`}`);
process.exit(failures === 0 ? 0 : 1);
