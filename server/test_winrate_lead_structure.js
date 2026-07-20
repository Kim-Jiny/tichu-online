// Regression: winrate bot must NOT break a same-rank group when LEADING.
// Repro of reported bad plays: hand 2 5 5 K led as K then single-5 (breaks 55);
// hand 4 4 5 6 6 8 8 8 K broke 888 into 88. The lead structure-preservation
// guard in buildWinrateCandidates should remove those fragmenting leads.
const assert = require('assert');
const TichuGame = require('./game/TichuGame');
const { decideBotAction } = require('./game/BotPlayer');

let pass = 0;
function ok(name, cond) { if (cond) { pass++; console.log('  ✓ ' + name); } else { console.error('  ✗ ' + name); process.exitCode = 1; } }

const RANK_VALUE = { '2':2,'3':3,'4':4,'5':5,'6':6,'7':7,'8':8,'9':9,'10':10,'J':11,'Q':12,'K':13,'A':14 };
const rankOf = (c) => c.split('_')[1];
const valOf = (c) => RANK_VALUE[rankOf(c)];

// The lowest-value rank the hand holds exactly once (the correct lead single).
function minSingletonValue(hand) {
  const counts = {};
  for (const c of hand) { if (c.startsWith('special_')) continue; const r = rankOf(c); counts[r] = (counts[r] || 0) + 1; }
  let min = Infinity;
  for (const r of Object.keys(counts)) { if (counts[r] === 1 && RANK_VALUE[r] < min) min = RANK_VALUE[r]; }
  return min;
}
// True if the play leads a normal single that is NOT the lowest singleton.
function leadsWrongSingle(hand, play) {
  const cards = (play && play.cards) || [];
  if (cards.length !== 1 || cards[0].startsWith('special_')) return false;
  if (cards.length === hand.length) return false; // finishing
  return valOf(cards[0]) !== minSingletonValue(hand);
}

function breaksGroup(hand, play) {
  const cards = (play && play.cards) || [];
  const normal = cards.filter(c => !c.startsWith('special_'));
  if (normal.length === 0) return false;
  if (cards.length === hand.length) return false; // finishing play is allowed
  const ranks = new Set(normal.map(rankOf));
  if (ranks.size !== 1) return false; // straight/step/full-house — not a same-rank group
  if (normal.length > 3) return false; // quad = bomb, handled elsewhere
  const r = normal[0].split('_')[1];
  const held = hand.filter(c => rankOf(c) === r).length;
  return held > cards.length; // used only part of a larger held group
}

function makeLeadGame(botHand, fillOthers) {
  const ids = ['bot1', 'p1', 'p2', 'p3'];
  const names = {}; ids.forEach(p => names[p] = p);
  const g = new TichuGame(ids, names);
  g.start();
  g.state = 'playing';
  g.currentPlayer = 'bot1';
  g.currentTrick = [];
  g.passCount = 0;
  g.callRank = null;
  g.needsToCallRank = null;
  g.dragonPending = false;
  g.hands.bot1 = botHand.slice();
  g.hands.p1 = fillOthers.slice(0, 6);
  g.hands.p2 = fillOthers.slice(6, 12);
  g.hands.p3 = fillOthers.slice(12, 18);
  return g;
}

// Filler cards for opponents (unused by either test hand).
const filler = [
  'club_2','club_3','club_4','club_6','club_7','club_9',
  'club_10','club_J','club_Q','club_K','club_A','diamond_2',
  'diamond_3','diamond_4','diamond_6','diamond_7','diamond_9','diamond_J',
];

console.log('[1] hand 2 5 5 K — lead must not play single 5 (breaks 55)');
{
  const hand = ['spade_2', 'spade_5', 'heart_5', 'spade_K'];
  let bad = 0, hi = 0, total = 0;
  for (let i = 0; i < 12; i++) {
    const g = makeLeadGame(hand, filler);
    const a = decideBotAction(g, 'bot1', 'winrate');
    total++;
    if (a && a.type === 'play_cards' && breaksGroup(hand, a)) { bad++; console.log('   got structure-break:', JSON.stringify(a.cards)); }
    if (a && a.type === 'play_cards' && leadsWrongSingle(hand, a)) { hi++; console.log('   got high-single lead:', JSON.stringify(a.cards)); }
  }
  ok(`no structure-breaking lead over ${total} runs (bad=${bad})`, bad === 0);
  ok(`no high-single lead (leads 2 or 55, not K/5) over ${total} runs (hi=${hi})`, hi === 0);
}

console.log('\n[2] hand 4 4 5 6 6 8 8 8 K — lead must not split 888 into 88/8, or 44/66 into singles');
{
  const hand = ['spade_4', 'heart_4', 'spade_5', 'spade_6', 'heart_6', 'spade_8', 'heart_8', 'club_8', 'spade_K'];
  let bad = 0, hi = 0, total = 0;
  for (let i = 0; i < 12; i++) {
    const g = makeLeadGame(hand, filler);
    const a = decideBotAction(g, 'bot1', 'winrate');
    total++;
    if (a && a.type === 'play_cards' && breaksGroup(hand, a)) { bad++; console.log('   got structure-break:', JSON.stringify(a.cards)); }
    if (a && a.type === 'play_cards' && leadsWrongSingle(hand, a)) { hi++; console.log('   got high-single lead:', JSON.stringify(a.cards)); }
  }
  ok(`no structure-breaking lead over ${total} runs (bad=${bad})`, bad === 0);
  ok(`single lead is lowest singleton (5, not K) over ${total} runs (hi=${hi})`, hi === 0);
}

console.log(`\n${pass} checks passed`);
