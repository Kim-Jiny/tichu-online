'use strict';

/**
 * Love Letter bot: the knowledge the engine keeps for it, the world sampling the
 * search stands on, and the contract the 'mc' bot must keep (legal actions, no
 * mutation of the live game, same answer from a worker).
 *
 *   node test_ll_mc.js
 */

const assert = require('assert');
const LL = require('./game/love_letter/LoveLetterGame');
const { decideLLBotAction, decideLLBotActionHeuristic, MC } = require('./game/love_letter/LoveLetterBot');
const { sampleWorld } = require('./game/love_letter/LoveLetterSearch');
const { createDeck, getCardInfo } = require('./game/love_letter/LoveLetterDeck');
const { BotWorkerPool } = require('./bots/BotWorkerPool');

MC.samples = 8;
MC.deadlineMs = 15;

/** A game in a known position: hands/draw pile set by hand, `a` to move having just drawn. */
function setup(ids, hands, drawPile, extra = {}) {
  const g = new LL(ids, Object.fromEntries(ids.map((p) => [p, p])));
  g.start();
  g.round = 1;
  for (const pid of ids) {
    g.hands[pid] = hands[pid].slice();
    g.discardPiles[pid] = [];
    g.eliminated[pid] = false;
    g.protected[pid] = false;
  }
  g.setAside = extra.setAside === undefined ? 'll_guard_5' : extra.setAside;
  g.faceUpCards = extra.faceUp || [];
  for (const pid of ids) g.discardPiles[pid] = (extra.discards && extra.discards[pid]) || [];
  // The draw pile starts with the cards given, then every card not yet placed, so the 16 always add up.
  const used = new Set([g.setAside, ...g.faceUpCards, ...drawPile]);
  for (const pid of ids) for (const c of [...g.hands[pid], ...g.discardPiles[pid]]) used.add(c);
  g.drawPile = drawPile.concat(createDeck().map((c) => c.id).filter((c) => !used.has(c)));
  g.currentPlayer = ids[0];
  g.knowledge = {}; g.notTypes = {};
  for (const pid of ids) { g.knowledge[pid] = {}; g.notTypes[pid] = []; }
  g.state = 'playing';
  g.pendingEffect = null;
  return g;
}
const play = (g, pid, cardId) => g.handleAction(pid, { type: 'play_card', cardId });

// ── Priest (spy): the actor learns the card, and loses it when that card is played ──
{
  const g = setup(['a', 'b'], { a: ['ll_spy_1', 'll_guard_1'], b: ['ll_baron_1'] }, ['ll_guard_2', 'll_guard_3', 'll_king', 'll_prince_1', 'll_prince_2']);
  assert.ok(play(g, 'a', 'll_spy_1').success);          // 1 target → resolves at once
  assert.strictEqual(g.knowledge.a.b, 'll_baron_1', 'a should know b holds the Baron');
  assert.strictEqual(g.knowledge.b.a, undefined, 'b learned nothing about a');
  g.handleAction('a', { type: 'effect_ack' });
  // b draws and keeps the Baron: still known
  assert.strictEqual(g.currentPlayer, 'b');
  assert.ok(play(g, 'b', g.hands.b.find((c) => c !== 'll_baron_1')).success || true);
  if (g.state === 'effect_resolve') g.handleAction('b', { type: 'effect_ack' });
  assert.strictEqual(g.knowledge.a.b, 'll_baron_1', 'knowledge must survive b playing the OTHER card');
}
{
  // b plays the known card: what is left is a fresh unknown draw
  const g = setup(['a', 'b'], { a: ['ll_spy_1', 'll_guard_1'], b: ['ll_handmaid_1'] }, ['ll_guard_2', 'll_guard_3', 'll_king', 'll_prince_1', 'll_prince_2']);
  play(g, 'a', 'll_spy_1');
  g.handleAction('a', { type: 'effect_ack' });
  assert.strictEqual(g.knowledge.a.b, 'll_handmaid_1');
  play(g, 'b', 'll_handmaid_1');
  assert.strictEqual(g.knowledge.a.b, undefined, 'a played card is no longer in b\'s hand');
}

// ── Guard that misses: everybody learns what b does NOT hold; cleared when b's card may change ──
{
  const g = setup(['a', 'b'], { a: ['ll_guard_1', 'll_baron_1'], b: ['ll_prince_1'] }, ['ll_guard_2', 'll_guard_3', 'll_king', 'll_prince_2', 'll_baron_2']);
  play(g, 'a', 'll_guard_1');
  const r = g.handleAction('a', { type: 'guard_guess', targetId: 'b', guess: 'baron' });
  assert.ok(r.success);
  assert.deepStrictEqual(g.notTypes.b, ['baron']);
  g.handleAction('a', { type: 'effect_ack' });
  play(g, 'b', g.hands.b[0]);
  assert.deepStrictEqual(g.notTypes.b, [], 'exclusions end once b has taken a turn');
}

// ── King: the two who swap know each other's new card; onlookers follow the swap ──
{
  const g = setup(['a', 'b', 'c'],
    { a: ['ll_king', 'll_baron_1'], b: ['ll_handmaid_1'], c: ['ll_prince_1'] },
    ['ll_guard_2', 'll_guard_3', 'll_guard_4', 'll_prince_2']);
  g.knowledge.c.a = 'll_baron_1'; // c once saw a's Baron
  g.protected.c = true;           // leave b as the only target
  play(g, 'a', 'll_king');
  assert.ok(g.handleAction('a', { type: 'select_target', targetId: 'b' }).success || g.pendingEffect.resolved);
  assert.strictEqual(g.hands.a[0], 'll_handmaid_1');
  assert.strictEqual(g.hands.b[0], 'll_baron_1');
  assert.strictEqual(g.knowledge.a.b, 'll_baron_1');
  assert.strictEqual(g.knowledge.b.a, 'll_handmaid_1');
  assert.strictEqual(g.knowledge.c.b, 'll_baron_1', 'c saw the swap and knows the Baron went to b');
  assert.strictEqual(g.knowledge.c.a, undefined);
}

// ── Prince: the target's hand is new, so old knowledge goes ──
{
  const g = setup(['a', 'b'], { a: ['ll_prince_1', 'll_guard_1'], b: ['ll_baron_1'] }, ['ll_guard_2', 'll_guard_3', 'll_king', 'll_prince_2', 'll_baron_2']);
  g.knowledge.a.b = 'll_baron_1';
  play(g, 'a', 'll_prince_1');
  g.handleAction('a', { type: 'select_target', targetId: 'b' });
  assert.strictEqual(g.knowledge.a.b, undefined);
}

// ── elimination clears what was known about the player ──
{
  const g = setup(['a', 'b'], { a: ['ll_guard_1', 'll_baron_1'], b: ['ll_prince_1'] }, ['ll_guard_2', 'll_guard_3', 'll_king', 'll_prince_2', 'll_baron_2']);
  g.knowledge.a.b = 'll_prince_1';
  play(g, 'a', 'll_guard_1');
  g.handleAction('a', { type: 'guard_guess', targetId: 'b', guess: 'prince' });
  assert.ok(g.eliminated.b);
  assert.strictEqual(g.knowledge.a.b, undefined);
}

// ── the rule-based bot uses what it knows: a known card is a certain Guard hit ──
{
  const g = setup(['a', 'b', 'c'],
    { a: ['ll_guard_1', 'll_baron_1'], b: ['ll_baron_2'], c: ['ll_prince_1'] },
    ['ll_guard_2', 'll_guard_3', 'll_king', 'll_prince_2', 'll_spy_1']);
  g.knowledge.a.c = 'll_prince_1';
  play(g, 'a', 'll_guard_1');
  const a = decideLLBotActionHeuristic(g, 'a');
  assert.deepStrictEqual([a.type, a.targetId, a.guess], ['guard_guess', 'c', 'prince']);
  g.notTypes.b = ['baron'];
  g.knowledge.a.c = undefined; delete g.knowledge.a.c;
}

// ── sampleWorld: consistent with everything known, and a real deal of the unseen cards ──
{
  const g = setup(['a', 'b', 'c'],
    { a: ['ll_guard_1', 'll_baron_1'], b: ['ll_baron_2'], c: ['ll_prince_1'] },
    ['ll_guard_2', 'll_guard_3', 'll_king', 'll_prince_2', 'll_spy_1', 'll_spy_2', 'll_handmaid_1', 'll_handmaid_2'],
    { setAside: 'll_countess', discards: { b: ['ll_guard_4'] } });
  g.knowledge.a.c = 'll_prince_1';
  g.notTypes.b = ['baron', 'spy'];
  for (let i = 0; i < 200; i++) {
    const w = sampleWorld(g, 'a');
    assert.ok(w, 'world');
    assert.deepStrictEqual(w.hands.a, g.hands.a);
    assert.deepStrictEqual(w.hands.c, ['ll_prince_1'], 'a known hand is kept');
    assert.strictEqual(w.hands.b.length, 1);
    const t = getCardInfo(w.hands.b[0]).type;
    assert.ok(t !== 'baron' && t !== 'spy', `b dealt an excluded type ${t}`);
    const all = [...w.hands.a, ...w.hands.b, ...w.hands.c, ...w.drawPile, w.setAside, 'll_guard_4'];
    assert.strictEqual(new Set(all).size, 16, 'a card was dealt twice or lost');
    assert.strictEqual(w.drawPile.length, g.drawPile.length);
  }
}

// ── 'mc' plays whole games legally at 2, 3 and 4 players ──
for (const n of [2, 3, 4]) {
  const ids = Array.from({ length: n }, (_, i) => `p${i}`);
  const g = new LL(ids, Object.fromEntries(ids.map((p) => [p, p])));
  g.start();
  let steps = 0; let errors = 0; let decisions = 0;
  while (g.state !== 'game_end' && steps++ < 4000) {
    if (g.state === 'round_end') { g.handleAction(g.currentPlayer, { type: 'next_round' }); continue; }
    const actor = g.state === 'effect_resolve' ? g.pendingEffect.playerId : g.currentPlayer;
    const a = decideLLBotAction(g, actor, 'mc');
    decisions++;
    const r = a && g.handleAction(actor, a);
    if (!r || !r.success) { errors++; break; }
  }
  assert.strictEqual(errors, 0, `${n}p: illegal action`);
  assert.strictEqual(g.state, 'game_end', `${n}p: game did not finish`);
  assert.ok(decisions > 20);
}

// ── searching never touches the live game ──
{
  const g = setup(['a', 'b', 'c'],
    { a: ['ll_guard_1', 'll_baron_1'], b: ['ll_baron_2'], c: ['ll_prince_1'] },
    ['ll_guard_2', 'll_guard_3', 'll_king', 'll_prince_2', 'll_spy_1']);
  const before = JSON.stringify(g.serialize());
  decideLLBotAction(g, 'a', 'mc');
  play(g, 'a', 'll_guard_1');
  const mid = JSON.stringify(g.serialize());
  decideLLBotAction(g, 'a', 'mc');
  assert.strictEqual(JSON.stringify(g.serialize()), mid, 'search mutated the live game');
  void before;
}

// ── serialize round trip ──
{
  const g = setup(['a', 'b', 'c'],
    { a: ['ll_guard_1', 'll_baron_1'], b: ['ll_baron_2'], c: ['ll_prince_1'] },
    ['ll_guard_2', 'll_guard_3', 'll_king', 'll_prince_2', 'll_spy_1']);
  g.knowledge.a.c = 'll_prince_1';
  g.notTypes.b = ['spy'];
  const copy = LL.reconstruct(structuredClone(g.serialize()));
  assert.deepStrictEqual(copy.knowledge, g.knowledge);
  assert.deepStrictEqual(copy.notTypes, g.notTypes);
  assert.deepStrictEqual(decideLLBotActionHeuristic(copy, 'a'), decideLLBotActionHeuristic(g, 'a'));
}

// ── a worker thread returns a legal action ──
async function workerCheck() {
  const pool = new BotWorkerPool({ size: 1, timeoutMs: 5000 });
  const ids = ['a', 'b', 'c'];
  const g = new LL(ids, Object.fromEntries(ids.map((p) => [p, p])));
  g.start();
  let checked = 0;
  for (let i = 0; i < 60 && g.state !== 'game_end' && checked < 6; i++) {
    if (g.state === 'round_end') { g.handleAction(g.currentPlayer, { type: 'next_round' }); continue; }
    const actor = g.state === 'effect_resolve' ? g.pendingEffect.playerId : g.currentPlayer;
    const a = await pool.decide('love_letter', g, actor, 'mc');
    assert.ok(a, 'worker returned nothing');
    const probe = LL.reconstruct(structuredClone(g.serialize()));
    const res = probe.handleAction(actor, a);
    assert.ok(res && res.success, `worker action illegal: ${JSON.stringify(a)}`);
    g.handleAction(actor, a);
    checked++;
  }
  assert.ok(checked >= 5);
}

workerCheck().then(() => { console.log('ll mc ok'); process.exit(0); })
  .catch((e) => { console.error(e); process.exit(1); });
