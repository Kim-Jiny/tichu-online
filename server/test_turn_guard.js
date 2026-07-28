'use strict';
/**
 * Spurious-turn-timeout guard tests.
 *
 * The guard decides whether a firing turn timer represents a real timeout or
 * a stale one left over from a state the game already left. Getting a "yes"
 * wrong costs a player three bogus timeouts and a desertion; getting a "no"
 * wrong stalls a game waiting on someone who never acts. Both directions are
 * covered below.
 *
 * Originally reported for Skull King; Love Letter hits it via a pendingEffect
 * that survives into round_end / game_end.
 */

const { playerStillNeedsToAct } = require('./game/turnGuard');

let failures = 0;
function check(label, actual, expected) {
  if (actual === expected) console.log(`  ok   ${label}`);
  else { failures++; console.log(`  FAIL ${label} — got ${actual}, expected ${expected}`); }
}

const ME = 'player_1';
const OTHER = 'player_2';

// ── Love Letter — the case seen in testing ─────────────────────────────────
console.log('\n=== love_letter ===');
{
  const ll = (state, pendingEffect, currentPlayer = ME) => ({ state, pendingEffect, currentPlayer });

  check('my turn to play', playerStillNeedsToAct('love_letter', ll('playing', null), ME), true);
  check("someone else's turn", playerStillNeedsToAct('love_letter', ll('playing', null, OTHER), ME), false);

  const myEffect = { playerId: ME, resolved: false, needsTarget: true, type: 'prince' };
  check('my unresolved effect', playerStillNeedsToAct('love_letter', ll('effect_resolve', myEffect), ME), true);
  check("another player's effect",
    playerStillNeedsToAct('love_letter', ll('effect_resolve', { ...myEffect, playerId: OTHER }), ME), false);
  check('resolved effect (ack timers own it)',
    playerStillNeedsToAct('love_letter', ll('effect_resolve', { ...myEffect, resolved: true }), ME), false);

  // The observed payload: game over, effect never resolved, timer still armed.
  check('game_end carrying an unresolved effect',
    playerStillNeedsToAct('love_letter', ll('game_end', myEffect), ME), false);
  check('round_end carrying an unresolved effect',
    playerStillNeedsToAct('love_letter', ll('round_end', myEffect), ME), false);
}

// ── Skull King — must keep the original fix's behaviour ────────────────────
console.log('\n=== skull_king (regression: original reported bug) ===');
{
  const sk = (state, extra = {}) => ({ state, currentPlayer: ME, bids: { [ME]: null, [OTHER]: 3 }, ...extra });

  check('my turn to play', playerStillNeedsToAct('skull_king', sk('playing'), ME), true);
  check("someone else's turn", playerStillNeedsToAct('skull_king', sk('playing', { currentPlayer: OTHER }), ME), false);
  check('bidding, my bid still missing', playerStillNeedsToAct('skull_king', sk('bidding'), ME), true);
  check('bidding, already bid',
    playerStillNeedsToAct('skull_king', sk('bidding', { bids: { [ME]: 2 } }), ME), false);
  check('trick_end', playerStillNeedsToAct('skull_king', sk('trick_end'), ME), false);
  check('round_end', playerStillNeedsToAct('skull_king', sk('round_end'), ME), false);
}

// ── Mighty ─────────────────────────────────────────────────────────────────
console.log('\n=== mighty ===');
{
  const mg = (state, extra = {}) => ({ state, currentPlayer: ME, declarer: ME, ...extra });

  check('my turn to play', playerStillNeedsToAct('mighty', mg('playing'), ME), true);
  check('my turn to bid', playerStillNeedsToAct('mighty', mg('bidding'), ME), true);
  check("someone else bidding", playerStillNeedsToAct('mighty', mg('bidding', { currentPlayer: OTHER }), ME), false);
  check('kitty exchange as declarer', playerStillNeedsToAct('mighty', mg('kitty_exchange'), ME), true);
  check('kitty exchange, not declarer',
    playerStillNeedsToAct('mighty', mg('kitty_exchange', { declarer: OTHER }), ME), false);
  check('kill_select as declarer', playerStillNeedsToAct('mighty', mg('kill_select'), ME), true);
  check('trick_end', playerStillNeedsToAct('mighty', mg('trick_end'), ME), false);
  check('round_end', playerStillNeedsToAct('mighty', mg('round_end'), ME), false);
  check('game_end', playerStillNeedsToAct('mighty', mg('game_end'), ME), false);
}

// ── Tichu — the turn can be owed by someone other than currentPlayer ───────
console.log('\n=== tichu ===');
{
  const tc = (state, extra = {}) => ({ state, currentPlayer: ME, ...extra });

  check('my turn to play', playerStillNeedsToAct('tichu', tc('playing'), ME), true);
  check("someone else's turn", playerStillNeedsToAct('tichu', tc('playing', { currentPlayer: OTHER }), ME), false);
  check('mahjong wish is mine',
    playerStillNeedsToAct('tichu', tc('playing', { currentPlayer: OTHER, needsToCallRank: ME }), ME), true);
  check("mahjong wish is someone else's",
    playerStillNeedsToAct('tichu', tc('playing', { needsToCallRank: OTHER }), ME), false);
  check('dragon decision is mine',
    playerStillNeedsToAct('tichu', tc('playing', { currentPlayer: OTHER, dragonPending: true, dragonDecider: ME }), ME), true);
  check("dragon decision is someone else's",
    playerStillNeedsToAct('tichu', tc('playing', { dragonPending: true, dragonDecider: OTHER }), ME), false);
  // Phase timeouts (large tichu / exchange) go through handlePhaseTimeout.
  check('large_tichu_phase is not a turn timeout',
    playerStillNeedsToAct('tichu', tc('large_tichu_phase'), ME), false);
  check('card_exchange is not a turn timeout',
    playerStillNeedsToAct('tichu', tc('card_exchange'), ME), false);
  check('round_end', playerStillNeedsToAct('tichu', tc('round_end'), ME), false);
}

// ── defensive ──────────────────────────────────────────────────────────────
console.log('\n=== malformed input ===');
check('no game', playerStillNeedsToAct('tichu', null, ME), false);
check('no player', playerStillNeedsToAct('tichu', { state: 'playing', currentPlayer: ME }, null), false);
check('effect_resolve with no effect',
  playerStillNeedsToAct('love_letter', { state: 'effect_resolve', pendingEffect: null }, ME), false);

console.log(`\n${failures === 0 ? 'ALL PASS' : `${failures} FAILURE(S)`}`);
process.exit(failures === 0 ? 0 : 1);
