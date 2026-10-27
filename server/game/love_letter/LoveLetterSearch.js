'use strict';

/**
 * Love Letter bot — determinized Monte-Carlo search (strat 'mc').
 *
 * To choose a card or a target/guess we deal the cards nobody has shown to the
 * other players at random — consistent with everything this seat knows (its own
 * hand, every discard, the face-up cards, hands it has seen, and the guesses
 * that failed) — play the round out with the rule-based bot in every seat, and
 * keep the option that wins the round most often. All options are tried on the
 * SAME sampled worlds so the comparison is not drowned by dealing luck.
 *
 * Returns null when it has nothing to choose between or too little budget; the
 * caller then falls back to the rule-based answer.
 */

const LoveLetterGame = require('./LoveLetterGame');
const { createDeck, getCardInfo, GUESSABLE_TYPES } = require('./LoveLetterDeck');

function rules() {
  return require('./LoveLetterBot'); // lazy: LoveLetterBot requires this file lazily too
}

// ── the world this seat can see ───────────────────────────────────────────

/**
 * Deal the hidden cards: every opponent whose hand this seat does not know, the
 * draw pile and the face-down set-aside card. Returns null if the bookkeeping
 * does not add up (then the caller just plays the rule-based move).
 */
function sampleWorld(game, botId) {
  const known = game.knowledge && game.knowledge[botId] || {};
  const visible = new Set(game.hands[botId] || []);
  for (const pid of game.playerIds) for (const c of game.discardPiles[pid] || []) visible.add(c);
  for (const c of game.faceUpCards || []) visible.add(c);

  const fixed = {};
  for (const pid of game.playerIds) {
    if (pid === botId || game.eliminated[pid]) continue;
    if (known[pid] && !visible.has(known[pid])) { fixed[pid] = known[pid]; visible.add(known[pid]); }
  }

  const pool = createDeck().map((c) => c.id).filter((id) => !visible.has(id));
  for (let i = pool.length - 1; i > 0; i--) {
    const j = (Math.random() * (i + 1)) | 0;
    const t = pool[i]; pool[i] = pool[j]; pool[j] = t;
  }

  const hands = {};
  for (const pid of game.playerIds) {
    if (pid === botId) hands[pid] = (game.hands[pid] || []).slice();
    else if (game.eliminated[pid]) hands[pid] = [];
    else if (fixed[pid]) hands[pid] = [fixed[pid]];
    else hands[pid] = null; // to deal
  }
  for (const pid of game.playerIds) {
    if (hands[pid] !== null) continue;
    const need = game.hands[pid].length; // public: how many cards they hold
    const banned = new Set((game.notTypes && game.notTypes[pid]) || []);
    const mine = [];
    for (let n = 0; n < need; n++) {
      let idx = pool.findIndex((c) => !banned.has(getCardInfo(c).type));
      if (idx < 0) idx = 0; // the constraints cannot all hold: ignore them rather than fail
      if (pool.length === 0) return null;
      mine.push(pool.splice(idx, 1)[0]);
    }
    hands[pid] = mine;
  }

  const drawCount = game.drawPile.length;
  const hasSetAside = !!game.setAside;
  if (pool.length !== drawCount + (hasSetAside ? 1 : 0)) return null;
  return {
    hands,
    drawPile: pool.slice(0, drawCount),
    setAside: hasSetAside ? pool[drawCount] : null,
  };
}

/** A copy of the game for a rollout, holding the sampled hidden cards. */
function worldFrom(game, botId, world) {
  const g = Object.create(LoveLetterGame.prototype);
  Object.assign(g, game);
  g.hands = {};
  for (const pid of game.playerIds) g.hands[pid] = world.hands[pid].slice();
  g.drawPile = world.drawPile.slice();
  g.setAside = world.setAside;
  g.originalSetAside = world.setAside;
  g.discardPiles = {};
  for (const pid of game.playerIds) g.discardPiles[pid] = (game.discardPiles[pid] || []).slice();
  g.eliminated = { ...game.eliminated };
  g.protected = { ...game.protected };
  g.tokens = { ...game.tokens };
  g.notTypes = {};
  for (const pid of game.playerIds) g.notTypes[pid] = ((game.notTypes && game.notTypes[pid]) || []).slice();
  // Knowledge: what this seat knows, plus what the others know ABOUT this seat's
  // hand (they were shown it, so this seat knows they know). What the others know
  // about each other is hidden from this seat and must not steer the rollout.
  g.knowledge = {};
  for (const pid of game.playerIds) g.knowledge[pid] = {};
  const mine = game.knowledge && game.knowledge[botId] || {};
  for (const holder of Object.keys(mine)) g.knowledge[botId][holder] = mine[holder];
  for (const pid of game.playerIds) {
    if (pid === botId) continue;
    const k = game.knowledge && game.knowledge[pid];
    if (k && k[botId]) g.knowledge[pid][botId] = k[botId];
  }
  g.pendingEffect = game.pendingEffect
    ? { ...game.pendingEffect, validTargets: (game.pendingEffect.validTargets || []).slice() }
    : null;
  g.roundHistory = [];
  g.missionEvents = [];
  return g;
}

/** Play the round out with the rule-based bot in every seat. Returns the share of the round `botId` wins, or null if stuck. */
function playOut(sim, botId) {
  const r = rules();
  for (let guard = 0; guard < 200; guard++) {
    const st = sim.state;
    if (st === 'round_end' || st === 'game_end') {
      const last = sim.roundHistory[sim.roundHistory.length - 1];
      if (!last || !last.winners || last.winners.length === 0) return 0;
      return last.winners.includes(botId) ? 1 / last.winners.length : 0;
    }
    let actor; let action;
    if (st === 'playing') {
      actor = sim.currentPlayer;
      action = r.decidePlay(sim, actor);
    } else if (st === 'effect_resolve' && sim.pendingEffect) {
      actor = sim.pendingEffect.playerId;
      action = r.decideEffect(sim, actor, {});
    } else {
      return null;
    }
    if (!action) return null;
    const res = sim.handleAction(actor, action);
    if (!res || !res.success) return null;
  }
  return null;
}

// ── choosing ──────────────────────────────────────────────────────────────

function sameAction(a, b) {
  if (!a || !b || a.type !== b.type) return false;
  return a.cardId === b.cardId && a.targetId === b.targetId && a.guess === b.guess;
}

function evaluate(game, botId, options, preferred, { samples = 40, deadlineMs = 20, margin = 0 } = {}) {
  if (options.length < 2) return null;
  const t0 = Date.now();
  const sum = options.map(() => 0);
  let done = 0;
  for (let s = 0; s < samples; s++) {
    if (done >= 8 && Date.now() - t0 > deadlineMs) break;
    const world = sampleWorld(game, botId);
    if (!world) return null;
    const vals = [];
    let ok = true;
    for (const opt of options) {
      const sim = worldFrom(game, botId, world);
      const res = sim.handleAction(botId, opt);
      if (!res || !res.success) { ok = false; break; }
      const v = playOut(sim, botId);
      if (v === null) { ok = false; break; }
      vals.push(v);
    }
    if (!ok) continue;
    for (let i = 0; i < options.length; i++) sum[i] += vals[i];
    done++;
  }
  if (done < 4) return null;
  let best = 0;
  for (let i = 1; i < options.length; i++) if (sum[i] > sum[best]) best = i;
  const pref = preferred ? options.findIndex((o) => sameAction(o, preferred)) : -1;
  if (pref >= 0 && sum[best] - sum[pref] <= margin * done) return options[pref];
  return options[best];
}

/** Which card to play. `preferred` is the rule-based choice. */
function searchPlay(game, botId, preferred, cfg) {
  const hand = game.hands[botId] || [];
  const options = hand.map((cardId) => ({ type: 'play_card', cardId }));
  // The Countess rule leaves one legal card: nothing to search.
  const hasCountess = hand.some((c) => getCardInfo(c)?.type === 'countess');
  const hasKP = hand.some((c) => ['king', 'prince'].includes(getCardInfo(c)?.type));
  if (hand.length < 2 || (hasCountess && hasKP)) return null;
  return evaluate(game, botId, options, preferred, cfg);
}

/** Which target (and Guard guess) to use the pending effect on. */
function searchEffect(game, botId, preferred, cfg) {
  const eff = game.pendingEffect;
  if (!eff || eff.resolved) return null;
  const targets = eff.targetId && !eff.needsTarget ? [eff.targetId] : (eff.validTargets || []);
  let options;
  if (eff.type === 'guard') {
    options = [];
    for (const t of targets) for (const g of GUESSABLE_TYPES) options.push({ type: 'guard_guess', targetId: t, guess: g });
  } else if (eff.needsTarget) {
    options = targets.map((t) => ({ type: 'select_target', targetId: t }));
  } else {
    return null;
  }
  return evaluate(game, botId, options, preferred, cfg);
}

module.exports = { searchPlay, searchEffect, sampleWorld, worldFrom };
