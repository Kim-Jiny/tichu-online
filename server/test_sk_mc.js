'use strict';

/**
 * Skull King search bot ('mc'): the pieces it stands on and the contract it
 * must keep — every action legal, nothing about hidden cards leaks in, and a
 * worker computes the same kind of answer as the main thread.
 *
 *   node test_sk_mc.js
 */

const assert = require('assert');
const SkullKingGame = require('./game/skull_king/SkullKingGame');
const { decideSKBotAction, decideSKBotActionHeuristic, MC } = require('./game/skull_king/SkullKingBot');
const { unseenPool, inferVoids, sampleDeal } = require('./game/skull_king/SkullKingSearch');
const { getCardInfo, CARD_TYPE } = require('./game/skull_king/SkullKingDeck');
const { BotWorkerPool } = require('./bots/BotWorkerPool');

// Small budgets: this checks behaviour, not strength (that is sim_skullking_ab.js).
MC.bidSamples = 6;
MC.playSamples = 6;
MC.deadlineMs = 15;

const ids4 = ['a', 'b', 'c', 'd'];

function newGame(ids, expansions = []) {
  const g = new SkullKingGame(ids, ids.map((i) => i.toUpperCase()), { expansions });
  g.start();
  return g;
}

/** Drive a whole game; every bot in `strat` mode. Returns {game, errors, decisions}. */
function playGame(ids, expansions, strat, maxRounds = 10) {
  const game = newGame(ids, expansions);
  let errors = 0, decisions = 0, guard = 50000;
  while (game.state !== 'game_end' && game.round <= maxRounds && guard-- > 0) {
    if (game.state === 'bidding') {
      for (const pid of ids) {
        if (game.bids[pid] !== null) continue;
        const r = game.handleAction(pid, decideSKBotAction(game, pid, strat));
        decisions++;
        if (!r || !r.success) errors++;
      }
    } else if (game.state === 'playing') {
      const pid = game.currentPlayer;
      const r = game.handleAction(pid, decideSKBotAction(game, pid, strat));
      decisions++;
      if (!r || !r.success) { errors++; break; }
    } else if (game.state === 'pirate_ability') {
      const pid = game.pendingAbility.playerId;
      const r = game.handleAction(pid, decideSKBotAction(game, pid, strat) || game._defaultAbilityAction());
      decisions++;
      if (!r || !r.success) { errors++; break; }
    } else if (game.state === 'trick_end') {
      game.advanceAfterTrickEnd();
    } else if (game.state === 'round_end') {
      if (game.round >= maxRounds) break;
      game.nextRound();
    } else { errors++; break; }
  }
  return { game, errors, decisions };
}

// ── roundPlays: every card played this round, in order, cleared each round ──
{
  const game = newGame(ids4);
  const hands = ids4.map((p) => game.hands[p][0]);
  for (const p of ids4) game.handleAction(p, { type: 'submit_bid', bid: 0 });
  assert.deepStrictEqual(game.roundPlays, []);
  const first = game.currentPlayer;
  const card = game.hands[first][0];
  const info = getCardInfo(card);
  game.handleAction(first, info.type === CARD_TYPE.TIGRESS
    ? { type: 'play_card', cardId: card, tigressChoice: 'escape' }
    : { type: 'play_card', cardId: card });
  assert.strictEqual(game.roundPlays.length, 1);
  assert.strictEqual(game.roundPlays[0].cardId, card);
  assert.strictEqual(game.roundPlays[0].playerId, first);
  void hands;
}

// ── unseenPool: deck minus my hand and everything already played ───────────
{
  const game = newGame(ids4);
  game.round = 3; // pretend: only the sets matter below
  const me = 'a';
  const pool = unseenPool(game, me);
  for (const c of game.hands[me]) assert.ok(!pool.includes(c), 'my own card is in the pool');
  assert.strictEqual(pool.length, 66 - game.hands[me].length);
  game.roundPlays = [{ playerId: 'b', cardId: pool[0] }];
  assert.ok(!unseenPool(game, me).includes(pool[0]), 'a played card is still in the pool');
}

// ── inferVoids: not following suit proves the player has none of it ─────────
{
  const game = newGame(ids4);
  game.roundPlays = [
    { playerId: 'a', cardId: 'sk_yellow_5' },
    { playerId: 'b', cardId: 'sk_green_9' },   // had to follow yellow, did not → no yellow
    { playerId: 'c', cardId: 'sk_yellow_2' },
    { playerId: 'd', cardId: 'sk_pirate_1' },  // a special says nothing
  ];
  const v = inferVoids(game);
  assert.ok(v.b.has('yellow'), 'b should be void in yellow');
  assert.ok(!v.c.has('yellow') && !v.d.has('yellow') && !v.a.has('yellow'));
}

// ── a player's id changes mid-round (reconnect): the round's plays follow, and the search still works ──
{
  const game = newGame(ids4);
  for (const p of ids4) game.handleAction(p, { type: 'submit_bid', bid: 0 });
  // b is void in the lead suit: play it out so roundPlays holds a "did not follow" record for b
  game.hands.a = ['sk_yellow_5', 'sk_yellow_6', 'sk_yellow_7'];
  game.hands.b = ['sk_green_9', 'sk_green_2', 'sk_green_3'];
  game.hands.c = ['sk_yellow_2', 'sk_yellow_3', 'sk_yellow_4'];
  game.hands.d = ['sk_purple_1', 'sk_purple_2', 'sk_purple_3'];
  game.currentPlayer = 'a'; game.trickStarter = 'a'; game.trickNumber = 1; game.state = 'playing';
  game.roundPlays = []; game.currentTrick = [];
  for (const [p, c] of [['a', 'sk_yellow_5'], ['b', 'sk_green_9'], ['c', 'sk_yellow_2'], ['d', 'sk_purple_1']]) {
    assert.ok(game.handleAction(p, { type: 'play_card', cardId: c }).success, `${p} plays ${c}`);
  }
  assert.ok(inferVoids(game).b.has('yellow'));
  game.advanceAfterTrickEnd(); // next trick, led by the winner
  assert.strictEqual(game.state, 'playing');
  game.updatePlayerId('b', 'b2');
  assert.ok(game.roundPlays.every((p) => p.playerId !== 'b'), 'roundPlays still names the old id');
  assert.ok(inferVoids(game).b2.has('yellow'), 'what b2 showed must follow the new id');
  // even a stale id left in the records must not throw
  game.roundPlays[1].playerId = 'ghost';
  assert.doesNotThrow(() => inferVoids(game));
  // and the search, which used to throw here and silently fall back, runs
  game.roundPlays[1].playerId = 'b2';
  const { searchPlay } = require('./game/skull_king/SkullKingSearch');
  assert.ok(searchPlay(game, game.currentPlayer, null, { samples: 6, deadlineMs: 15 }),
    'search returned nothing after the id change');
}

// ── sampleDeal: right sizes, no card twice, voids respected ────────────────
{
  const pool = ['sk_yellow_1', 'sk_yellow_2', 'sk_yellow_3', 'sk_green_1', 'sk_green_2', 'sk_green_3', 'sk_purple_4', 'sk_black_5'];
  const voids = { b: new Set(['yellow']), c: new Set(), d: new Set() };
  for (let i = 0; i < 300; i++) {
    const { hands, undealt } = sampleDeal(pool, { b: 2, c: 2, d: 2 }, voids);
    const all = [...hands.b, ...hands.c, ...hands.d, ...undealt];
    assert.strictEqual(new Set(all).size, pool.length, 'a card was dealt twice or lost');
    assert.strictEqual(hands.b.length, 2); assert.strictEqual(hands.c.length, 2); assert.strictEqual(hands.d.length, 2);
    assert.ok(!hands.b.some((c) => c.includes('yellow')), 'void suit dealt to b');
  }
}

// ── the search bot plays whole games legally (base, and with every expansion) ─
for (const [label, ids, exp] of [
  ['4p base', ids4, []],
  ['3p base', ['a', 'b', 'c'], []],
  ['5p kraken/whale/loot', ['a', 'b', 'c', 'd', 'e'], ['kraken', 'white_whale', 'loot']],
  ['4p pirate abilities', ids4, ['pirate_abilities']],
]) {
  const { game, errors, decisions } = playGame(ids, exp, 'mc', label.startsWith('5p') ? 6 : 10);
  assert.strictEqual(errors, 0, `${label}: ${errors} illegal actions`);
  assert.ok(decisions > 20, `${label}: only ${decisions} decisions`);
  void game;
}

// ── searching never touches the live game ──────────────────────────────────
{
  const game = newGame(ids4);
  for (const p of ids4) game.handleAction(p, decideSKBotAction(game, p, 'mc'));
  const before = JSON.stringify(game.serialize());
  decideSKBotAction(game, game.currentPlayer, 'mc');
  assert.strictEqual(JSON.stringify(game.serialize()), before, 'search mutated the live game');
}

// ── serialize round trip: a worker's copy decides like the original ─────────
{
  const game = newGame(ids4, ['pirate_abilities']);
  for (const p of ids4) game.handleAction(p, decideSKBotActionHeuristic(game, p));
  for (let i = 0; i < 6 && game.state === 'playing'; i++) {
    const pid = game.currentPlayer;
    const copy = SkullKingGame.reconstruct(structuredClone(game.serialize()));
    assert.deepStrictEqual(decideSKBotActionHeuristic(copy, pid), decideSKBotActionHeuristic(game, pid),
      'reconstructed game decides differently');
    assert.deepStrictEqual(copy.getLegalCards(pid), game.getLegalCards(pid));
    game.handleAction(pid, decideSKBotActionHeuristic(game, pid));
    if (game.state === 'trick_end') game.advanceAfterTrickEnd();
  }
}

// ── a worker thread returns a legal action for a real state ────────────────
async function workerCheck() {
  const pool = new BotWorkerPool({ size: 1, timeoutMs: 5000 });
  try {
    const game = newGame(ids4);
    const bid = await pool.decide('skull_king', game, 'a', 'mc');
    assert.ok(bid && bid.type === 'submit_bid', `worker bid: ${JSON.stringify(bid)}`);
    for (const p of ids4) game.handleAction(p, decideSKBotActionHeuristic(game, p));
    let checked = 0;
    while (game.state === 'playing' && checked < 4) {
      const pid = game.currentPlayer;
      const a = await pool.decide('skull_king', game, pid, 'mc');
      assert.ok(a && game.getLegalCards(pid).includes(a.cardId), `worker play illegal: ${JSON.stringify(a)}`);
      game.handleAction(pid, a);
      checked++;
      if (game.state === 'trick_end') game.advanceAfterTrickEnd();
    }
    assert.ok(checked >= 3);
  } finally {
    await pool.close?.();
  }
}

workerCheck().then(() => {
  console.log('sk mc ok');
  process.exit(0);
}).catch((e) => { console.error(e); process.exit(1); });
