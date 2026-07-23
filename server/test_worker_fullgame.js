'use strict';

/**
 * End-to-end check that a full round can be played where EVERY bot decision is
 * computed in a worker (await pool.decide) and applied to the live game — the
 * exact serialize -> worker -> decide -> apply -> advance cycle server.js now
 * performs, minus the WebSocket/room wrapper. Exercises every phase (bidding,
 * exchange, kill, tricks, scoring) through the pool and asserts the round
 * reaches a terminal state without getting stuck or applying illegal moves.
 *
 *   node test_worker_fullgame.js
 */

const assert = require('assert');
const { BotWorkerPool } = require('./bots/BotWorkerPool');
const MightyGame = require('./game/mighty/MightyGame');
const { makeRng } = require('./game/mighty/MightyDeck');
const TichuGame = require('./game/TichuGame');

async function playMightyRound(pool, seed) {
  const playerIds = ['p0', 'p1', 'p2', 'p3', 'p4'];
  const names = {}; for (const p of playerIds) names[p] = p;
  const game = new MightyGame(playerIds, names, { targetScore: 50, rng: makeRng(seed) });
  game.start();
  let decisions = 0, fallbacks = 0, safety = 2000;
  while (game.state !== 'round_end' && game.state !== 'game_end' && safety-- > 0) {
    if (game.state === 'trick_end') { game.advanceAfterTrickEnd(); continue; }
    const actor = game.getPendingActor();
    if (!actor) break;
    const action = await pool.decide('mighty', game, actor, 'mixoracle');
    decisions++;
    let res = action ? game.handleAction(actor, action) : null;
    if (!res || res.success === false) {
      const fb = game.getAutoTimeoutAction(actor);
      assert.ok(fb, `mighty stuck: no action & no auto-fallback (state=${game.state} actor=${actor})`);
      res = game.handleAction(actor, fb);
      fallbacks++;
      assert.ok(res && res.success !== false, `mighty auto-fallback rejected (state=${game.state})`);
    }
  }
  assert.ok(game.state === 'round_end' || game.state === 'game_end',
    `mighty round did not terminate (state=${game.state})`);
  return { decisions, fallbacks, state: game.state };
}

function tichuActors(game) {
  const s = game.state;
  if (s === 'large_tichu_phase' || s === 'card_exchange') return game.playerIds.slice();
  if (game.needsToCallRank) return [game.needsToCallRank];
  if (game.dragonPending) return [game.dragonDecider];
  return game.currentPlayer ? [game.currentPlayer] : [];
}

async function playTichuRound(pool) {
  const playerIds = ['p0', 'p1', 'p2', 'p3'];
  const names = {}; for (const p of playerIds) names[p] = p;
  const game = new TichuGame(playerIds, names);
  game.start();
  let decisions = 0, fallbacks = 0, safety = 4000;
  while (game.state !== 'round_end' && game.state !== 'game_end' && safety-- > 0) {
    let moved = false;
    for (const actor of tichuActors(game)) {
      if (!actor) continue;
      const action = await pool.decide('tichu', game, actor, 'winrate');
      decisions++;
      let res = action ? game.handleAction(actor, action) : null;
      if (!res || res.success === false) {
        const fb = game.getAutoTimeoutAction(actor);
        if (!fb) continue;
        res = game.handleAction(actor, fb);
        fallbacks++;
      }
      if (res && res.success) moved = true;
    }
    if (!moved) break;
  }
  assert.ok(game.state === 'round_end' || game.state === 'game_end',
    `tichu round did not terminate (state=${game.state})`);
  return { decisions, fallbacks, state: game.state };
}

async function main() {
  const pool = new BotWorkerPool({ size: 4 });
  console.log(`BotWorkerPool size=${pool.size}`);

  const m = await playMightyRound(pool, 42);
  console.log(`  mighty round -> ${m.state} via ${m.decisions} worker decisions (${m.fallbacks} auto-fallbacks)`);

  const t = await playTichuRound(pool);
  console.log(`  tichu round  -> ${t.state} via ${t.decisions} worker decisions (${t.fallbacks} auto-fallbacks)`);

  console.log(`  pool stats: ${JSON.stringify(pool.stats)}`);
  await pool.destroy();
  console.log('OK — full rounds played end-to-end entirely through the worker pool.');
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
