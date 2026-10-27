'use strict';

/**
 * Skull King bot — determinized Monte-Carlo search.
 *
 * The rule-based bot (SkullKingBot.js) plays every seat of a rollout. For a
 * decision we deal the cards nobody can see to the other players at random
 * (respecting what they have already shown they lack), play the rest of the
 * round out with the rule-based bot, and keep the choice whose average round
 * score is best. All candidates are evaluated on the SAME sampled deals so the
 * comparison is not drowned by dealing luck.
 *
 *   searchBid  — which bid maximises the expected round score
 *   searchPlay — which card (and Tigress side) maximises it
 *
 * Both return null when they cannot beat the budget or have nothing to choose
 * between; the caller then falls back to the rule-based answer.
 */

const SkullKingGame = require('./SkullKingGame');
const { createDeck, getCardInfo, CARD_TYPE } = require('./SkullKingDeck');

// Cheap, pure; required lazily so SkullKingBot <-> SkullKingSearch can reference each other.
function heuristic() {
  return require('./SkullKingBot').decideSKBotActionHeuristic;
}

// ── information the bot is allowed to use ─────────────────────────────────

/** Cards nobody has shown me yet: the deck minus my hand and every card played this round. */
function unseenPool(game, botId) {
  const known = new Set(game.hands[botId] || []);
  for (const p of game.roundPlays || []) known.add(p.cardId);
  for (const p of game.currentTrick) known.add(p.cardId);
  return createDeck(game.expansions).map((c) => c.id).filter((id) => !known.has(id));
}

/** Lead suit of a list of plays — same rule as SkullKingGame.getLeadSuit. */
function leadSuitOf(plays) {
  for (const play of plays) {
    const info = getCardInfo(play.cardId);
    let type = info.type;
    if (type === CARD_TYPE.TIGRESS) {
      type = play.tigressChoice === 'pirate' ? CARD_TYPE.PIRATE : CARD_TYPE.ESCAPE;
    }
    if (type === CARD_TYPE.ESCAPE || type === CARD_TYPE.LOOT) continue;
    return type === CARD_TYPE.NUMBER ? info.suit : null;
  }
  return null;
}

/** playerId -> Set of suits the player has proved they hold none of (they had to follow and did not). */
function inferVoids(game) {
  const voids = {};
  for (const pid of game.playerIds) voids[pid] = new Set();
  const plays = game.roundPlays || [];
  const n = game.playerCount;
  for (let i = 0; i < plays.length; i += n) {
    const trick = plays.slice(i, i + n);
    for (let k = 1; k < trick.length; k++) {
      const lead = leadSuitOf(trick.slice(0, k));
      if (!lead) continue;
      const info = getCardInfo(trick[k].cardId);
      if (info.type === CARD_TYPE.NUMBER && info.suit !== lead) voids[trick[k].playerId].add(lead);
    }
  }
  return voids;
}

/**
 * Deal the unseen cards to the other players: handSizes[pid] cards each, nobody
 * gets a suit they are known to lack. The remainder is the undealt stack.
 */
function sampleDeal(pool, handSizes, voids) {
  const cards = pool.slice();
  for (let i = cards.length - 1; i > 0; i--) {
    const j = (Math.random() * (i + 1)) | 0;
    const t = cards[i]; cards[i] = cards[j]; cards[j] = t;
  }
  const hands = {};
  const room = {};
  const pids = Object.keys(handSizes);
  for (const pid of pids) { hands[pid] = []; room[pid] = handSizes[pid]; }
  const rest = [];
  // Cards of a suit somebody is void in go first: they are the constrained ones.
  const suitOf = (id) => { const i = getCardInfo(id); return i.type === CARD_TYPE.NUMBER ? i.suit : null; };
  const constrained = [];
  const free = [];
  for (const id of cards) {
    const s = suitOf(id);
    (s && pids.some((p) => voids[p] && voids[p].has(s)) ? constrained : free).push(id);
  }
  for (const id of constrained.concat(free)) {
    const s = suitOf(id);
    let total = 0;
    const eligible = [];
    for (const pid of pids) {
      if (room[pid] > 0 && !(s && voids[pid] && voids[pid].has(s))) { eligible.push(pid); total += room[pid]; }
    }
    if (eligible.length === 0) { rest.push(id); continue; }
    let r = Math.random() * total;
    let pick = eligible[eligible.length - 1];
    for (const pid of eligible) { r -= room[pid]; if (r < 0) { pick = pid; break; } }
    hands[pick].push(id);
    room[pick]--;
  }
  // Dead end (a constrained card nobody can take) can leave a hand short: top it up from the rest.
  for (const pid of pids) {
    while (room[pid] > 0 && rest.length) { hands[pid].push(rest.pop()); room[pid]--; }
  }
  return { hands, undealt: rest };
}

// ── rollout machinery ─────────────────────────────────────────────────────

function cloneGame(game) {
  const g = Object.create(SkullKingGame.prototype);
  Object.assign(g, game);
  g.hands = {};
  for (const pid of game.playerIds) g.hands[pid] = game.hands[pid].slice();
  g.bids = { ...game.bids };
  g.tricks = { ...game.tricks };
  g.bonuses = { ...game.bonuses };
  g.totalScores = { ...game.totalScores };
  g.lastRoundScores = { ...game.lastRoundScores };
  g.rascalWagers = { ...game.rascalWagers };
  g.lootAlliances = game.lootAlliances.map((a) => ({ ...a }));
  g.currentTrick = game.currentTrick.map((p) => ({ ...p }));
  g.roundPlays = (game.roundPlays || []).map((p) => ({ ...p }));
  g.undealt = game.undealt.slice();
  g.pendingAbility = game.pendingAbility ? { ...game.pendingAbility } : null;
  g.scoreHistory = [];
  g.missionEvents = [];
  return g;
}

/** A rollout copy of the game in which the other players hold the sampled cards. */
function worldFrom(game, botId, deal) {
  const sim = cloneGame(game);
  for (const pid of game.playerIds) {
    if (pid !== botId) sim.hands[pid] = deal.hands[pid].slice();
  }
  sim.undealt = deal.undealt.slice();
  return sim;
}

/** Play the round to its end with the rule-based bot in every seat. false if it got stuck. */
function playOut(sim) {
  const h = heuristic();
  for (let guard = 0; guard < 600; guard++) {
    const st = sim.state;
    if (st === 'round_end' || st === 'game_end') return true;
    if (st === 'playing') {
      const pid = sim.currentPlayer;
      const a = h(sim, pid);
      if (!a) return false;
      const r = sim.handleAction(pid, a);
      if (!r || !r.success) return false;
    } else if (st === 'trick_end') {
      sim.advanceAfterTrickEnd();
    } else if (st === 'pirate_ability') {
      const pid = sim.pendingAbility.playerId;
      let r = sim.handleAction(pid, h(sim, pid) || sim._defaultAbilityAction());
      if (!r || !r.success) r = sim.handleAction(pid, sim._defaultAbilityAction());
      if (!r || !r.success) return false;
    } else {
      return false;
    }
  }
  return false;
}

/**
 * Hard stop. The soft deadline lets a search finish its minimum number of
 * samples, which is what makes the answer worth having; but a worker that runs
 * past BotWorkerPool's timeout is killed and respawned, so on a loaded box the
 * search gives up (returns null -> rule-based move) well before that.
 */
function hardMs(deadlineMs) { return deadlineMs * 4; }

function handSizesOf(game, botId) {
  const sizes = {};
  for (const pid of game.playerIds) if (pid !== botId) sizes[pid] = game.hands[pid].length;
  return sizes;
}

// ── bidding ───────────────────────────────────────────────────────────────

/**
 * Pick the bid with the best average round score. `candidates` are the bids to
 * compare. Players who have not bid yet are bid by the rule-based bot on their
 * sampled hand, after mine, in seating order.
 */
function searchBid(game, botId, candidates, { samples = 40, deadlineMs = 25 } = {}) {
  if (candidates.length < 2) return null;
  const t0 = Date.now();
  const h = heuristic();
  const pool = unseenPool(game, botId);
  const sizes = handSizesOf(game, botId);
  const noVoids = {};
  const sum = candidates.map(() => 0);
  let done = 0;
  for (let s = 0; s < samples; s++) {
    if (Date.now() - t0 > hardMs(deadlineMs) || (done >= 8 && Date.now() - t0 > deadlineMs)) break;
    const deal = sampleDeal(pool, sizes, noVoids);
    const scores = [];
    let ok = true;
    for (let c = 0; c < candidates.length; c++) {
      const sim = worldFrom(game, botId, deal);
      sim.bids[botId] = candidates[c];
      for (const pid of sim.playerIds) {
        if (sim.bids[pid] === null) {
          const a = h(sim, pid);
          sim.bids[pid] = a ? a.bid : 0;
        }
      }
      sim.startTrick();
      if (!playOut(sim)) { ok = false; break; }
      scores.push(sim.lastRoundScores[botId]);
    }
    if (!ok) continue;
    for (let c = 0; c < candidates.length; c++) sum[c] += scores[c];
    done++;
  }
  if (done < 4) return null;
  let best = 0;
  for (let c = 1; c < candidates.length; c++) if (sum[c] > sum[best]) best = c;
  return { bid: candidates[best], means: sum.map((v) => v / done), samples: done };
}

// ── card play ─────────────────────────────────────────────────────────────

/** Every distinct way to play the legal cards (a Tigress can be played two ways). */
function playOptions(legal) {
  const opts = [];
  for (const id of legal) {
    const info = getCardInfo(id);
    if (info.type === CARD_TYPE.TIGRESS) {
      opts.push({ type: 'play_card', cardId: id, tigressChoice: 'pirate' });
      opts.push({ type: 'play_card', cardId: id, tigressChoice: 'escape' });
    } else {
      opts.push({ type: 'play_card', cardId: id });
    }
  }
  return opts;
}

/**
 * Pick the card with the best average round score, or null to defer to the
 * rule-based choice. `preferred` is that choice: it keeps the pick unless
 * another option is better by more than `margin` points.
 */
function searchPlay(game, botId, preferred, { samples = 30, deadlineMs = 25, margin = 0 } = {}) {
  const legal = game.getLegalCards(botId);
  if (legal.length < 2) return null;
  const options = playOptions(legal);
  const t0 = Date.now();
  const h = heuristic();
  const pool = unseenPool(game, botId);
  const sizes = handSizesOf(game, botId);
  const voids = inferVoids(game);
  const sum = options.map(() => 0);
  let done = 0;
  for (let s = 0; s < samples; s++) {
    if (Date.now() - t0 > hardMs(deadlineMs) || (done >= 6 && Date.now() - t0 > deadlineMs)) break;
    const deal = sampleDeal(pool, sizes, voids);
    const scores = [];
    let ok = true;
    for (let o = 0; o < options.length; o++) {
      const sim = worldFrom(game, botId, deal);
      const r = sim.handleAction(botId, options[o]);
      if (!r || !r.success || !playOut(sim)) { ok = false; break; }
      scores.push(sim.lastRoundScores[botId]);
    }
    if (!ok) continue;
    for (let o = 0; o < options.length; o++) sum[o] += scores[o];
    done++;
  }
  if (done < 4) return null;
  const same = (a, b) => a.cardId === b.cardId && (a.tigressChoice || null) === (b.tigressChoice || null);
  let best = 0;
  for (let o = 1; o < options.length; o++) if (sum[o] > sum[best]) best = o;
  const pref = preferred ? options.findIndex((o) => same(o, preferred)) : -1;
  if (pref >= 0 && sum[best] - sum[pref] <= margin * done) return options[pref];
  return options[best];
}

module.exports = { searchBid, searchPlay, unseenPool, inferVoids, sampleDeal, cloneGame };
