'use strict';

/**
 * Equivalence test for the optimized TichuGame.canFulfillCallAndBeat.
 *
 * Proves the new pruned/direct implementation returns the EXACT same boolean as
 * the original exhaustive 2^hand brute force, over many randomized
 * (callRank, lastCombo, hand) cases — including bomb- and straight-flush-heavy
 * hands so the (B1)/(B2) direct-detection paths are exercised. Any mismatch is
 * printed and fails the run.
 */

const TichuGame = require('./game/TichuGame');
const { getComboType, canBeat, COMBO } = require('./game/CardValidator');
const { getCardValue } = require('./game/Deck');

const SUITS = ['spade', 'heart', 'diamond', 'club'];
const RANKS = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];
const RANK_VALUE = { '2': 2, '3': 3, '4': 4, '5': 5, '6': 6, '7': 7, '8': 8, '9': 9, '10': 10, J: 11, Q: 12, K: 13, A: 14 };
const VALUE_RANK = Object.fromEntries(Object.entries(RANK_VALUE).map(([r, v]) => [v, r]));

const ALL_NORMAL = [];
for (const s of SUITS) for (const r of RANKS) ALL_NORMAL.push(`${s}_${r}`);
const SPECIALS = ['special_bird', 'special_phoenix', 'special_dragon', 'special_dog'];

// Deterministic RNG so failures are reproducible.
let _seed = 0x12345678;
function rnd() { _seed = (_seed * 1103515245 + 12345) & 0x7fffffff; return _seed / 0x7fffffff; }
function ri(n) { return Math.floor(rnd() * n); }
function pick(arr) { return arr[ri(arr.length)]; }
function shuffle(a) { const b = a.slice(); for (let i = b.length - 1; i > 0; i--) { const j = ri(i + 1); [b[i], b[j]] = [b[j], b[i]]; } return b; }

// ---- Original brute force (the reference oracle) -------------------------
function bruteForce(wishValue, lastCombo, hand, trickActive) {
  let wishMask = 0;
  hand.forEach((c, i) => { if (getCardValue(c) === wishValue) wishMask |= (1 << i); });
  if (wishMask === 0) return false;
  const total = 1 << hand.length;
  for (let mask = 1; mask < total; mask++) {
    if ((mask & wishMask) === 0) continue;
    const subset = [];
    for (let i = 0; i < hand.length; i++) if (mask & (1 << i)) subset.push(hand[i]);
    const combo = getComboType(subset);
    if (combo.type === COMBO.INVALID) continue;
    if (combo.isPhoenix && trickActive) combo.value = lastCombo.value + 0.5;
    if (canBeat(lastCombo, combo)) return true;
  }
  return false;
}

// ---- Random hand (≤14 cards), biased to sometimes contain a 4-of-a-kind or
//      a same-suit run so bomb / straight-flush paths get exercised. --------
function randomHand() {
  const cards = new Set();
  const size = 1 + ri(14);
  // Bias: ~30% inject a 4-of-a-kind, ~30% inject a same-suit run of 5-7.
  if (rnd() < 0.3) {
    const r = pick(RANKS);
    for (const s of SUITS) cards.add(`${s}_${r}`);
  }
  if (rnd() < 0.3) {
    const s = pick(SUITS);
    const startV = 2 + ri(6); // 2..7
    const len = 5 + ri(3);
    for (let v = startV; v < startV + len && v <= 14; v++) cards.add(`${s}_${VALUE_RANK[v]}`);
  }
  if (rnd() < 0.25) cards.add('special_phoenix');
  const pool = shuffle(ALL_NORMAL);
  for (let i = 0; i < pool.length && cards.size < size; i++) cards.add(pool[i]);
  if (rnd() < 0.1) cards.add(pick(SPECIALS));
  return [...cards].slice(0, 14);
}

// ---- Random valid lastCombo spanning all types (incl. bombs / SF). --------
function buildCards(suit, values) { return values.map((v) => `${suit}_${VALUE_RANK[v]}`); }
function randomLastCombo() {
  for (let attempt = 0; attempt < 50; attempt++) {
    const kind = ri(9);
    let cards;
    if (kind === 0) cards = [pick(ALL_NORMAL)]; // single
    else if (kind === 1) { const r = pick(RANKS); cards = [`spade_${r}`, `heart_${r}`]; } // pair
    else if (kind === 2) { const r = pick(RANKS); cards = [`spade_${r}`, `heart_${r}`, `club_${r}`]; } // triple
    else if (kind === 3) { const v = 2 + ri(8); const ss = shuffle(SUITS); cards = [v, v + 1, v + 2, v + 3, v + 4].map((x, i) => `${ss[i % 4]}_${VALUE_RANK[x]}`); } // straight (mixed)
    else if (kind === 4) { const r1 = pick(RANKS), r2 = pick(RANKS.filter((r) => r !== r1)); cards = [`spade_${r1}`, `heart_${r1}`, `club_${r1}`, `spade_${r2}`, `heart_${r2}`]; } // fullhouse
    else if (kind === 5) { const v = 2 + ri(9); cards = [`spade_${VALUE_RANK[v]}`, `heart_${VALUE_RANK[v]}`, `spade_${VALUE_RANK[v + 1]}`, `heart_${VALUE_RANK[v + 1]}`]; } // steps (2 pairs)
    else if (kind === 6) { const r = pick(RANKS); cards = SUITS.map((s) => `${s}_${r}`); } // 4-bomb
    else if (kind === 7) { const s = pick(SUITS); const v = 2 + ri(6); cards = buildCards(s, [v, v + 1, v + 2, v + 3, v + 4]); } // straight flush
    else { const s = pick(SUITS); const v = 2 + ri(4); cards = buildCards(s, [v, v + 1, v + 2, v + 3, v + 4, v + 5]); } // longer SF
    const combo = getComboType(cards);
    if (combo.type !== COMBO.INVALID) return combo;
  }
  return getComboType([pick(ALL_NORMAL)]);
}

// ---- Run ------------------------------------------------------------------
const N = parseInt(process.argv[2] || '300000', 10);
const ids = ['p0', 'p1', 'p2', 'p3'];
const names = { p0: 'p0', p1: 'p1', p2: 'p2', p3: 'p3' };
const game = new TichuGame(ids, names);

let mismatches = 0;
let trueCount = 0;
const samples = { withWish: 0 };
for (let t = 0; t < N; t++) {
  const hand = randomHand();
  const lastCombo = randomLastCombo();
  const callRank = pick(RANKS);
  const wishValue = RANK_VALUE[callRank];

  // Wire the game state the function reads.
  game.callRank = callRank;
  game.currentTrick = [{ combo: lastCombo }];

  const ref = bruteForce(wishValue, lastCombo, hand, true);
  const opt = game._computeCanFulfillCallAndBeat(lastCombo, hand);
  if (ref) trueCount++;
  if (hand.some((c) => getCardValue(c) === wishValue)) samples.withWish++;

  if (ref !== opt) {
    mismatches++;
    if (mismatches <= 10) {
      console.log(`MISMATCH #${mismatches}: ref=${ref} opt=${opt}`);
      console.log(`  callRank=${callRank} (v=${wishValue})`);
      console.log(`  lastCombo=${JSON.stringify({ type: lastCombo.type, length: lastCombo.length, value: lastCombo.value })}`);
      console.log(`  hand=[${hand.join(', ')}]`);
    }
  }
}

console.log(`\nran ${N} cases | hands-with-wish ${samples.withWish} | ref=true ${trueCount}`);
if (mismatches === 0) {
  console.log('✅ EQUIVALENT — optimized matches brute force on all cases');
} else {
  console.log(`❌ ${mismatches} MISMATCHES — optimized is NOT equivalent`);
  process.exit(1);
}
