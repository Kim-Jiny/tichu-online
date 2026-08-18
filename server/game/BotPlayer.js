/**
 * Server-integrated Bot Player
 * Strategic AI for Tichu card game.
 */

const { performance } = require('perf_hooks');
const { createDeck } = require('./Deck');
const { getComboType, COMBO } = require('./CardValidator');

const VALID_BOT_STRATEGIES = ['heuristic', 'winrate', 'oracle', 'mixoracle', 'pimc_play', 'pimc_full', 'expectimax', 'expectimax_smart', 'mixexpectimax'];

class BotPlayer {
  constructor(id, nickname, speed = 'normal', strategy = 'heuristic') {
    this.id = id;           // 'bot_1', 'bot_2', ...
    this.nickname = nickname; // '봇 1', '봇 2', ...
    this.isBot = true;
    this.speed = speed;     // 'fast', 'normal', 'slow'
    this.strategy = VALID_BOT_STRATEGIES.includes(strategy)
      ? (strategy === 'mixexpectimax' ? 'mixoracle' : strategy)
      : 'heuristic';
  }
}

// ========== UTILITY FUNCTIONS ==========

/** Card point value for scoring: 5→5, 10/K→10, Dragon→25, Phoenix→-25 */
function getCardPointValue(cardId) {
  if (cardId === 'special_dragon') return 25;
  if (cardId === 'special_phoenix') return -25;
  const rank = cardId.split('_')[1];
  if (rank === '5') return 5;
  if (rank === '10' || rank === 'K') return 10;
  return 0;
}

/** Estimate total points in current trick */
function estimateTrickPoints(trick) {
  if (!trick || trick.length === 0) return 0;
  let pts = 0;
  for (const play of trick) {
    for (const card of play.cards) {
      pts += getCardPointValue(card);
    }
  }
  return pts;
}

/** Get partner player info from state */
function getPartner(state) {
  const players = state.players || [];
  return players.find(p => p.position === 'partner');
}

/** Get opponent player infos from state */
function getOpponents(state) {
  const players = state.players || [];
  return players.filter(p => p.position === 'left' || p.position === 'right');
}

/** Card play value (for comparison). Phoenix=14.5, Dragon=15, Bird=1, Dog=0 */
function getCardValue(cardId) {
  if (cardId === 'special_bird') return 1;
  if (cardId === 'special_dog') return 0;
  if (cardId === 'special_phoenix') return 14.5;
  if (cardId === 'special_dragon') return 15;
  const rankValues = { '2':2,'3':3,'4':4,'5':5,'6':6,'7':7,'8':8,'9':9,'10':10,'J':11,'Q':12,'K':13,'A':14 };
  const rank = cardId.split('_')[1];
  return rankValues[rank] || 0;
}

function getHighestValue(cards) {
  if (!cards || cards.length === 0) return 0;
  return Math.max(...cards.map(c => getCardValue(c)));
}

function getFullHouseTripleValue(cards) {
  const counts = {};
  for (const c of cards) {
    const v = getCardValue(c);
    counts[v] = (counts[v] || 0) + 1;
  }
  for (const [v, cnt] of Object.entries(counts)) {
    if (cnt === 3) return Number(v);
  }
  return getHighestValue(cards);
}

function getRankFromCard(cardId) {
  if (cardId.startsWith('special_')) return null;
  return cardId.split('_')[1];
}

// ----- Bomb preservation helpers -----------------------------------------
// findCombos generates pairs/triples/steps from ANY group of size >= 2/3 in
// the hand — including the 2-or-3 card subsets of a 4-of-a-kind. The
// followTrick / winrate paths then happily pick those, breaking the bomb to
// win a single trick. These helpers detect the situation so callers can
// filter such candidates out.
//
// Returns the Set of card-values that form a 4-of-a-kind in `cards`.
function getBombValues(cards) {
  const counts = {};
  for (const c of cards) {
    if (c.startsWith('special_')) continue;
    const v = getCardValue(c);
    counts[v] = (counts[v] || 0) + 1;
  }
  const set = new Set();
  for (const [v, cnt] of Object.entries(counts)) {
    if (cnt === 4) set.add(Number(v));
  }
  return set;
}

// True iff `play` touches a 4-of-a-kind in the hand but is NOT the bomb
// itself (i.e. uses 1, 2, or 3 of the 4). Phoenix is treated as "doesn't
// touch": a phoenix-extended pair/triple at a bomb value still costs us a
// bomb card, so we check value membership directly.
function playBreaksBomb(play, bombValues) {
  if (!bombValues || bombValues.size === 0) return false;
  const vals = [];
  for (const c of play) {
    if (c.startsWith('special_')) continue;
    vals.push(getCardValue(c));
  }
  const touched = vals.filter(v => bombValues.has(v));
  if (touched.length === 0) return false;
  // Count per bomb-value involved: 4 of any one = the full bomb (fine).
  const perVal = {};
  for (const v of touched) perVal[v] = (perVal[v] || 0) + 1;
  for (const [v, cnt] of Object.entries(perVal)) {
    if (cnt !== 4) return true; // partial use of a quad -> breaks bomb
  }
  return false;
}

// ========== HAND EVALUATION SYSTEM ==========

/**
 * Greedily decompose hand into planned plays.
 * Priority: bombs → straights → steps → full houses → triples → pairs → singles
 * Returns array of card arrays representing planned plays.
 */
/** True when the play is a 5+ same-suit consecutive run — i.e. a straight
 *  flush bomb. findCombos/decomposeHand only flag 4-of-a-kind as bombs, so
 *  without this check straight flushes leak into `plans` as regular
 *  straights and the bot burns them on free leads. */
function isStraightFlushBomb(cardIds) {
  if (!cardIds || cardIds.length < 5) return false;
  if (cardIds.some(c => c.startsWith('special_'))) return false;
  const suit = cardIds[0].split('_')[0];
  if (!cardIds.every(c => c.split('_')[0] === suit)) return false;
  const values = cardIds.map(c => getCardValue(c)).sort((a, b) => a - b);
  for (let i = 1; i < values.length; i++) {
    if (values[i] !== values[i - 1] + 1) return false;
  }
  return true;
}


/**
 * 아직 아무도 안 낸 카드 중 value 보다 높은 게 몇 장 남았는지.
 *
 * 내 손패 + 이미 걷힌 트릭 + 지금 트릭에 깔린 카드를 전체 덱에서 빼면 남는다.
 * 전부 사람도 눈으로 볼 수 있는 정보다(남의 손패는 보지 않는다).
 */
function countOutstandingAbove(game, botId, value) {
  if (!game || !game.hands) return null;
  const seen = new Set(game.hands[botId] || []);
  for (const pile of Object.values(game.trickPiles || {})) {
    for (const c of pile) seen.add(c);
  }
  for (const play of (game.currentTrick || [])) {
    for (const c of (play.cards || [])) seen.add(c);
  }
  for (const c of (game.pendingTrickCards || [])) seen.add(c);

  let n = 0;
  for (const suit of ['spade', 'heart', 'diamond', 'club']) {
    for (const rank of ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A']) {
      const id = `${suit}_${rank}`;
      if (seen.has(id)) continue;
      if (getCardValue(id) > value) n++;
    }
  }
  if (!seen.has('special_dragon')) n++;   // 용은 봉황 위에 언제나 올라온다
  return n;
}

function decomposeHand(cards) {
  const normalCards = cards.filter(c => !c.startsWith('special_'));
  const specialCards = cards.filter(c => c.startsWith('special_'));
  const plans = [];

  // Work with a mutable copy
  let remaining = [...normalCards];

  // Group by value
  function groupByValue(cardList) {
    const byValue = {};
    for (const card of cardList) {
      const v = getCardValue(card);
      if (!byValue[v]) byValue[v] = [];
      byValue[v].push(card);
    }
    return byValue;
  }

  // 1. Extract four-of-a-kind bombs
  let byValue = groupByValue(remaining);
  for (const [v, group] of Object.entries(byValue)) {
    if (group.length === 4) {
      plans.push([...group]);
      remaining = remaining.filter(c => !group.includes(c));
    }
  }

  // 2. Extract straights (5+ consecutive).
  // Preserve Ace as single if the straight is long enough without it: an A left
  // in hand as a single is a near-guaranteed trick winner, while the remaining
  // straight (still >=5) is barely weaker.
  byValue = groupByValue(remaining);
  const values = Object.keys(byValue).map(Number).sort((a, b) => a - b);
  if (values.length >= 5) {
    let runStart = 0;
    for (let i = 1; i <= values.length; i++) {
      if (i === values.length || values[i] !== values[i - 1] + 1) {
        let runEnd = i; // exclusive
        let runLen = runEnd - runStart;
        // If run ends at Ace and still has room, drop the Ace.
        if (runLen > 5 && values[runEnd - 1] === 14) {
          runEnd -= 1;
          runLen -= 1;
        }
        if (runLen >= 5) {
          const straightCards = [];
          for (let j = runStart; j < runEnd; j++) {
            straightCards.push(byValue[values[j]][0]);
          }
          plans.push(straightCards);
          remaining = remaining.filter(c => !straightCards.includes(c));
        }
        runStart = i;
      }
    }
  }

  // 3. Extract steps (consecutive pairs).
  // Preserve Ace-pair if the step is long enough without it: A-pair alone is
  // stronger than most step finales it would be glued into.
  byValue = groupByValue(remaining);
  const pairValues = [];
  for (const [v, group] of Object.entries(byValue)) {
    if (group.length >= 2) pairValues.push(Number(v));
  }
  pairValues.sort((a, b) => a - b);
  if (pairValues.length >= 2) {
    let runStart = 0;
    for (let i = 1; i <= pairValues.length; i++) {
      if (i === pairValues.length || pairValues[i] !== pairValues[i - 1] + 1) {
        let runEnd = i;
        let runLen = runEnd - runStart;
        if (runLen > 2 && pairValues[runEnd - 1] === 14) {
          runEnd -= 1;
          runLen -= 1;
        }
        if (runLen >= 2) {
          const stepCards = [];
          for (let j = runStart; j < runEnd; j++) {
            const group = byValue[pairValues[j]];
            stepCards.push(group[0], group[1]);
          }
          plans.push(stepCards);
          remaining = remaining.filter(c => !stepCards.includes(c));
        }
        runStart = i;
      }
    }
  }

  // 4. Extract full houses (triple + pair)
  byValue = groupByValue(remaining);
  const triples = [];
  const pairs = [];
  for (const [v, group] of Object.entries(byValue)) {
    if (group.length >= 3) triples.push({ v: Number(v), cards: group.slice(0, 3) });
    else if (group.length >= 2) pairs.push({ v: Number(v), cards: group.slice(0, 2) });
  }
  for (const triple of triples) {
    if (pairs.length > 0) {
      const pair = pairs.shift();
      plans.push([...pair.cards, ...triple.cards]);
      remaining = remaining.filter(c => !pair.cards.includes(c) && !triple.cards.includes(c));
    }
  }

  // 5. Remaining triples
  byValue = groupByValue(remaining);
  for (const [v, group] of Object.entries(byValue)) {
    if (group.length >= 3) {
      const triple = group.slice(0, 3);
      plans.push(triple);
      remaining = remaining.filter(c => !triple.includes(c));
    }
  }

  // 6. Remaining pairs
  byValue = groupByValue(remaining);
  for (const [v, group] of Object.entries(byValue)) {
    if (group.length >= 2) {
      const pair = group.slice(0, 2);
      plans.push(pair);
      remaining = remaining.filter(c => !pair.includes(c));
    }
  }

  // 7. Remaining singles (normal cards)
  for (const c of remaining) {
    plans.push([c]);
  }

  // 8. Special cards as singles (except dog which is situational)
  for (const c of specialCards) {
    plans.push([c]);
  }

  return plans;
}

/**
 * Evaluate hand strength.
 * Returns { score, playCount, hasBomb, highCards }
 */
function evaluateHand(cards) {
  const plans = decomposeHand(cards);
  const normalCards = cards.filter(c => !c.startsWith('special_'));
  const playCount = plans.length;

  let score = 0;

  // Fewer plays needed = stronger hand (base: 100 - playCount * 7)
  score += Math.max(0, 100 - playCount * 7);

  // High card bonuses
  const hasAce = normalCards.some(c => getRankFromCard(c) === 'A');
  const hasDragon = cards.includes('special_dragon');
  const hasPhoenix = cards.includes('special_phoenix');
  const hasBomb = plans.some(p => p.length === 4 && !p[0].startsWith('special_'));

  if (hasDragon) score += 15;
  if (hasPhoenix) score += 10;
  if (hasAce) score += 5;
  if (hasBomb) score += 15;

  // Multi-card combo bonus (straights, steps, full houses reduce play count significantly)
  const multiCardPlays = plans.filter(p => p.length >= 3);
  score += multiCardPlays.length * 5;

  // Penalty for low singles (2, 3, 4 as singles)
  const lowSingles = plans.filter(p =>
    p.length === 1 && !p[0].startsWith('special_') && getCardValue(p[0]) <= 4
  );
  score -= lowSingles.length * 5;

  return { score, playCount, hasBomb, hasAce, hasDragon, hasPhoenix };
}


// ========== TICHU DECLARATION ==========

function decideLargeTichu(cards, game) {
  // 봇은 스스로는 라지티츄를 부르지 않는다. 어드민 봇방에서 티츄 흐름을
  // 시험하려고 켜둔 방(botTichuMode)에서만 부른다 — 사람 상대로는 예전과
  // 똑같이 조용하다.
  return game?.botTichuMode === 'large';
}

function decideSmallTichu(cards, state, game) {
  // 같은 이유. 라지로 켜둔 방에서는 이미 라지를 불렀으니 스몰은 건드리지
  // 않는다(규칙상 둘 다는 안 된다).
  return game?.botTichuMode === 'small';
}


// ========== EXCHANGE STRATEGY ==========

function selectExchangeCards(cards) {
  const plans = decomposeHand(cards);
  const bombCards = new Set(findCombos(cards.filter(c => !c.startsWith('special_'))).bombs.flat());
  const planSizeByCard = new Map();
  for (const plan of plans) {
    for (const card of plan) {
      planSizeByCard.set(card, Math.max(planSizeByCard.get(card) || 0, plan.length));
    }
  }

  const meta = cards.map((card) => {
    const rank = getRankFromCard(card);
    const value = getCardValue(card);
    const planSize = planSizeByCard.get(card) || 1;
    const isSpecial = card.startsWith('special_');
    const isPointCard = rank === '5' || rank === '10' || rank === 'K';
    const isAce = rank === 'A';
    const isKing = rank === 'K';
    const isBird = card === 'special_bird';
    const isDog = card === 'special_dog';
    const isPhoenix = card === 'special_phoenix';
    const isDragon = card === 'special_dragon';
    const inMultiPlan = planSize >= 2;
    return {
      card,
      rank,
      value,
      planSize,
      isSpecial,
      isPointCard,
      isAce,
      isKing,
      isBird,
      isDog,
      isPhoenix,
      isDragon,
      inMultiPlan,
      isBombCard: bombCards.has(card),
    };
  });

  function opponentGivePenalty(info) {
    let penalty = 0;
    if (info.isDragon) penalty += 1000;
    else if (info.isPhoenix) penalty += 900;
    else if (info.isBird) penalty += 700;
    else if (info.isDog) penalty += 120;
    else if (info.isSpecial) penalty += 500;

    if (info.isBombCard) penalty += 700;
    if (info.inMultiPlan) penalty += 220 + info.planSize * 25;
    if (info.isAce) penalty += 420;
    else if (info.isKing) penalty += 220;
    else penalty += info.value * 20;
    if (info.isPointCard) penalty += 140;

    // Cheap dead singles are what we actually want to dump to opponents.
    // Aces are NOT cheap — without this guard the -140 bonus made a lone
    // ace look more dumpable than paired low cards, so all-paired hands
    // would gift the opponent an A.
    if (!info.isSpecial && !info.inMultiPlan && !info.isPointCard && !info.isAce) {
      penalty -= 140;
      if (info.value <= 4) penalty -= 50;
      else if (info.value <= 7) penalty -= 20;
    }
    return penalty;
  }

  const used = new Set();


  function pickOpponentCard() {
    const available = meta
      .filter(info => !used.has(info.card))
      .sort((a, b) => opponentGivePenalty(a) - opponentGivePenalty(b));
    const chosen = available[0] || meta.find(info => !used.has(info.card));
    if (!chosen) return cards[0];
    used.add(chosen.card);
    return chosen.card;
  }

  /**
   * The partner gets the best card in hand: Dragon, else Phoenix, else the
   * highest number card.
   *
   * This used to be a score that weighed strength against keeping one's own
   * shapes together, and the weighing came out wrong: a King taken from KK
   * scored 154 against a loose 10's 185, so the partner got the 10 and the
   * pair stayed home. Same for a hand whose only high cards were paired.
   *
   * The exchange is the one moment you can arm the only other player on your
   * side, and a split pair is a cheaper loss than a partner who cannot take a
   * trick. Nor does it depend on anyone declaring Tichu — a declaration only
   * raises the stakes on the same card.
   */
  function pickPartnerCard() {
    const remaining = meta.filter(info => !used.has(info.card));
    if (remaining.length === 0) return cards[0];
    const chosen =
      remaining.find(info => info.isDragon)
      || remaining.find(info => info.isPhoenix)
      // Bird and Dog are specials but not strength — they lose to any number
      // card here, which is why this looks at the normal cards only.
      || remaining
        .filter(info => !info.isSpecial)
        .sort((a, b) => b.value - a.value)[0]
      || remaining[0];
    used.add(chosen.card);
    return chosen.card;
  }

  // The partner's card is decided first and taken off the table: it is the one
  // choice with no trade-off left in it, and picking the opponents' first
  // would let a cheap-to-dump reading of the same card claim it.
  const partner = pickPartnerCard();
  const left = pickOpponentCard();
  const right = pickOpponentCard();

  return { left, partner, right };
}


// ========== CALL RANK (WISH) STRATEGY ==========

/** Pick a rank the bot doesn't have, preferring high ranks to hurt opponents.
 *  When `state` carries our team's tichu and exchange info, override with the
 *  rank of the card we gave to the right opp — forces them to spend it and
 *  helps the declaring teammate reach 1st. */
function pickCallRank(cards, state) {
  if (state && isTeamTichuLive(state) && state.exchangeGiven) {
    const rightCard = state.exchangeGiven.right;
    if (rightCard && !rightCard.startsWith('special_')) {
      const rank = getRankFromCard(rightCard);
      if (rank) return rank;
    }
  }

  const normalCards = cards.filter(c => !c.startsWith('special_'));
  const myRanks = new Set(normalCards.map(c => getRankFromCard(c)));

  // Wish for a high rank we DON'T have (forces opponents to play strong cards)
  const wishOrder = ['A', 'K', 'Q', 'J', '10', '9', '8', '7', '6', '5', '4', '3', '2'];
  for (const rank of wishOrder) {
    if (!myRanks.has(rank)) return rank;
  }

  // Fallback: random
  return wishOrder[Math.floor(Math.random() * wishOrder.length)];
}


// ========== DRAGON GIVE STRATEGY ==========

/** Give dragon trick to the opponent with MORE cards (more likely to finish last) */
function decideDragonGive(state) {
  const opponents = getOpponents(state);
  const left = opponents.find(p => p.position === 'left');
  const right = opponents.find(p => p.position === 'right');

  if (!left || !right) return 'left';

  // If one opponent already finished, give to the other
  if (left.hasFinished && !right.hasFinished) return 'right';
  if (right.hasFinished && !left.hasFinished) return 'left';
  if (left.hasFinished && right.hasFinished) return 'left'; // both finished, doesn't matter

  // Give to the one with MORE cards (more likely to be last)
  if (left.cardCount > right.cardCount) return 'left';
  if (right.cardCount > left.cardCount) return 'right';

  // Tie: random
  return Math.random() > 0.5 ? 'left' : 'right';
}

function isPartnerTichuLive(state, partner) {
  if (!partner || partner.hasFinished) return false;
  if (!partner.hasSmallTichu && !partner.hasLargeTichu) return false;
  const players = state.players || [];
  const someoneElseFinishedFirst = players.some(p => p.id !== partner.id && p.finishPosition === 1);
  return !someoneElseFinishedFirst;
}

/** True when our team (self or partner) has a live tichu declaration —
 *  the declarer hasn't finished and no other player has taken 1st yet. */
function isTeamTichuLive(state) {
  const players = state.players || [];
  const declarers = players.filter(p =>
    (p.position === 'self' || p.position === 'partner')
    && !p.hasFinished
    && (p.hasSmallTichu || p.hasLargeTichu)
  );
  for (const decl of declarers) {
    const someoneElseFinishedFirst = players.some(
      p => p.id !== decl.id && p.finishPosition === 1
    );
    if (!someoneElseFinishedFirst) return true;
  }
  return false;
}


// ========== FIND COMBOS ==========

function findCombos(cards) {
  const result = { pairs: [], triples: [], straights: [], fullHouses: [], steps: [], bombs: [] };

  const byValue = {};
  for (const card of cards) {
    const v = getCardValue(card);
    if (!byValue[v]) byValue[v] = [];
    byValue[v].push(card);
  }

  const values = Object.keys(byValue).map(Number).sort((a, b) => a - b);

  // Pairs, triples, bombs
  for (const v of values) {
    const group = byValue[v];
    if (group.length >= 2) result.pairs.push([group[0], group[1]]);
    if (group.length >= 3) result.triples.push([group[0], group[1], group[2]]);
    if (group.length === 4) result.bombs.push([group[0], group[1], group[2], group[3]]);
  }

  // Straights (5+ consecutive)
  if (values.length >= 5) {
    let runStart = 0;
    for (let i = 1; i <= values.length; i++) {
      if (i === values.length || values[i] !== values[i - 1] + 1) {
        const runLen = i - runStart;
        if (runLen >= 5) {
          // All valid-length straights from this run
          for (let len = 5; len <= runLen; len++) {
            for (let start = runStart; start + len <= i; start++) {
              const straightCards = [];
              for (let j = start; j < start + len; j++) {
                straightCards.push(byValue[values[j]][0]);
              }
              result.straights.push(straightCards);
            }
          }
        }
        runStart = i;
      }
    }
  }

  // Full houses
  for (const triple of result.triples) {
    const tripleVal = getCardValue(triple[0]);
    for (const pair of result.pairs) {
      const pairVal = getCardValue(pair[0]);
      if (pairVal !== tripleVal) {
        result.fullHouses.push([...pair, ...triple]);
        break;
      }
    }
  }

  // Steps (consecutive pairs) - generate all valid sub-lengths
  if (result.pairs.length >= 2) {
    const pairValues = result.pairs.map(p => getCardValue(p[0])).sort((a, b) => a - b);
    let runStart = 0;
    for (let i = 1; i <= pairValues.length; i++) {
      if (i === pairValues.length || pairValues[i] !== pairValues[i - 1] + 1) {
        const runLen = i - runStart;
        if (runLen >= 2) {
          for (let len = 2; len <= runLen; len++) {
            for (let start = runStart; start + len <= i; start++) {
              const stepCards = [];
              for (let j = start; j < start + len; j++) {
                const pv = pairValues[j];
                const group = byValue[pv];
                stepCards.push(group[0], group[1]);
              }
              result.steps.push(stepCards);
            }
          }
        }
        runStart = i;
      }
    }
  }

  // Sort by value (lowest first)
  result.pairs.sort((a, b) => getCardValue(a[0]) - getCardValue(b[0]));
  result.triples.sort((a, b) => getCardValue(a[0]) - getCardValue(b[0]));
  result.straights.sort((a, b) => getHighestValue(a) - getHighestValue(b));
  result.fullHouses.sort((a, b) => getFullHouseTripleValue(a) - getFullHouseTripleValue(b));
  result.steps.sort((a, b) => getHighestValue(a) - getHighestValue(b));

  return result;
}

/**
 * Find combos that use Phoenix as a wildcard.
 * Phoenix can act as: pair partner, triple filler, straight gap filler, full house part.
 */
function findCombosWithPhoenix(cards) {
  const hasPhoenix = cards.includes('special_phoenix');
  if (!hasPhoenix) return { pairs: [], triples: [], straights: [], fullHouses: [], steps: [] };

  const normalCards = cards.filter(c => !c.startsWith('special_'));
  const result = { pairs: [], triples: [], straights: [], fullHouses: [], steps: [] };

  const byValue = {};
  for (const card of normalCards) {
    const v = getCardValue(card);
    if (!byValue[v]) byValue[v] = [];
    byValue[v].push(card);
  }
  const values = Object.keys(byValue).map(Number).sort((a, b) => a - b);

  // Phoenix + single = pair
  for (const v of values) {
    const group = byValue[v];
    if (group.length >= 1) {
      result.pairs.push([group[0], 'special_phoenix']);
    }
  }

  // Phoenix + pair = triple
  for (const v of values) {
    const group = byValue[v];
    if (group.length >= 2) {
      result.triples.push([group[0], group[1], 'special_phoenix']);
    }
  }

  // Phoenix fills gap in straight
  if (values.length >= 4) {
    // Try building 5-card straights with Phoenix filling one gap
    for (let startIdx = 0; startIdx < values.length; startIdx++) {
      for (let endIdx = startIdx + 3; endIdx < values.length && endIdx < startIdx + 14; endIdx++) {
        const span = values[endIdx] - values[startIdx];
        const cardCount = endIdx - startIdx + 1;
        // With phoenix, we need exactly span = cardCount (no gap) or span = cardCount + 1 - 1 (one gap)
        // Total cards including phoenix = cardCount + 1
        const totalWithPhoenix = cardCount + 1;
        if (totalWithPhoenix < 5 || totalWithPhoenix > 14) continue;

        // Check if the values in this range are consecutive with at most 1 gap
        const rangeValues = values.slice(startIdx, endIdx + 1);
        let gaps = 0;
        for (let i = 1; i < rangeValues.length; i++) {
          const diff = rangeValues[i] - rangeValues[i - 1];
          if (diff === 2) gaps++;
          else if (diff > 2) { gaps = 99; break; }
        }

        if (gaps <= 1 && totalWithPhoenix >= 5) {
          const straightCards = [];
          for (let j = startIdx; j <= endIdx; j++) {
            straightCards.push(byValue[values[j]][0]);
          }
          straightCards.push('special_phoenix');
          result.straights.push(straightCards);
        }
      }
    }
  }

  // Phoenix + triple + single or Phoenix + pair + pair = full house
  for (const v1 of values) {
    const g1 = byValue[v1];
    if (g1.length >= 3) {
      // Triple exists, Phoenix makes a pair with any single
      for (const v2 of values) {
        if (v2 === v1) continue;
        const g2 = byValue[v2];
        if (g2.length >= 1) {
          result.fullHouses.push([g2[0], 'special_phoenix', g1[0], g1[1], g1[2]]);
          break; // one per triple
        }
      }
    }
    if (g1.length >= 2) {
      // Pair exists, Phoenix makes triple with another pair
      for (const v2 of values) {
        if (v2 === v1) continue;
        const g2 = byValue[v2];
        if (g2.length >= 2) {
          // Phoenix joins the higher pair as triple
          const tripleVal = Math.max(v1, v2);
          const pairVal = Math.min(v1, v2);
          const tripleGroup = byValue[tripleVal];
          const pairGroup = byValue[pairVal];
          result.fullHouses.push([pairGroup[0], pairGroup[1], tripleGroup[0], tripleGroup[1], 'special_phoenix']);
          break;
        }
      }
    }
  }

  // Phoenix in steps: Phoenix completes a pair for consecutive pairs
  const singleValues = values.filter(v => byValue[v].length === 1);
  const pairPlusValues = values.filter(v => byValue[v].length >= 2);
  // Try: one single + phoenix makes a pair, combined with adjacent real pairs
  for (const sv of singleValues) {
    const adjacentPairs = pairPlusValues.filter(pv => Math.abs(pv - sv) <= 3);
    // Find a consecutive run including sv (as phoenix-pair) and real pairs
    const allPairValues = [...adjacentPairs, sv].sort((a, b) => a - b);
    if (allPairValues.length >= 2) {
      let runStart = 0;
      for (let i = 1; i <= allPairValues.length; i++) {
        if (i === allPairValues.length || allPairValues[i] !== allPairValues[i - 1] + 1) {
          const runLen = i - runStart;
          if (runLen >= 2) {
            const runVals = allPairValues.slice(runStart, i);
            if (runVals.includes(sv)) {
              const stepCards = [];
              for (const rv of runVals) {
                const group = byValue[rv];
                if (rv === sv) {
                  stepCards.push(group[0], 'special_phoenix');
                } else {
                  stepCards.push(group[0], group[1]);
                }
              }
              result.steps.push(stepCards);
            }
          }
          runStart = i;
        }
      }
    }
  }

  // Sort by value
  result.pairs.sort((a, b) => getCardValue(a[0]) - getCardValue(b[0]));
  result.triples.sort((a, b) => getCardValue(a[0]) - getCardValue(b[0]));
  result.straights.sort((a, b) => getHighestValue(a) - getHighestValue(b));
  result.fullHouses.sort((a, b) => getFullHouseTripleValue(a) - getFullHouseTripleValue(b));
  result.steps.sort((a, b) => getHighestValue(a) - getHighestValue(b));

  return result;
}

/** Find straights that include Bird (value 1, so 1-2-3-4-5) */
function findStraightIncludingBird(cards) {
  if (!cards.includes('special_bird')) return null;
  const normalCards = cards.filter(c => !c.startsWith('special_'));

  const byValue = {};
  for (const card of normalCards) {
    const v = getCardValue(card);
    if (!byValue[v]) byValue[v] = [];
    byValue[v].push(card);
  }

  // Bird=1, need 2,3,4,5 at minimum for a 5-card straight
  const needed = [2, 3, 4, 5];
  const straightCards = ['special_bird'];
  let hasPhoeixFill = false;

  for (const v of needed) {
    if (byValue[v] && byValue[v].length > 0) {
      straightCards.push(byValue[v][0]);
    } else if (cards.includes('special_phoenix') && !hasPhoeixFill) {
      straightCards.push('special_phoenix');
      hasPhoeixFill = true;
    } else {
      return null; // Can't complete
    }
  }

  if (straightCards.length >= 5) return straightCards;
  return null;
}


// ========== BOMB TIMING STRATEGY ==========

/**
 * Decide whether to use a bomb right now.
 * Returns the bomb cards to play, or null if shouldn't bomb.
 */
function shouldBomb(state, cards, combos) {
  if (combos.bombs.length === 0) return null;

  const trick = state.currentTrick || [];
  if (trick.length === 0) return null;

  const lastPlay = trick[trick.length - 1];
  const partner = getPartner(state);
  const opponents = getOpponents(state);
  const trickPts = estimateTrickPoints(trick);

  // Never bomb partner's trick
  if (partner && lastPlay.playerId === partner.id) return null;

  // Find a bomb that actually beats the current trick
  const lastComboType = lastPlay.combo;
  const lastValue = lastPlay.comboValue || 0;
  const isBombOnBoard = lastComboType === 'bomb_four' || lastComboType === 'bomb_straight_flush';

  // Find the weakest bomb that can beat
  let usableBomb = null;
  for (const bomb of combos.bombs) {
    const bombValue = getCardValue(bomb[0]); // all same value for 4-of-a-kind
    if (isBombOnBoard) {
      // Must beat the existing bomb
      if (lastComboType === 'bomb_four' && bombValue > lastValue) {
        usableBomb = bomb;
        break; // use weakest winning bomb
      }
      // Can't beat a straight flush bomb with a 4-of-a-kind
      if (lastComboType === 'bomb_straight_flush') continue;
    } else {
      // Bomb beats any non-bomb
      usableBomb = bomb;
      break;
    }
  }

  if (!usableBomb) return null;

  // Immediately bomb: opponent declared tichu
  const oppTichuDeclarer = opponents.find(o => o.hasSmallTichu || o.hasLargeTichu);
  if (oppTichuDeclarer && lastPlay.playerId === oppTichuDeclarer.id) {
    return usableBomb;
  }

  // Bomb if trick points >= 20 and opponent played
  if (trickPts >= 20) return usableBomb;

  // Bomb if bombing lets us go out (bomb is our last cards)
  if (usableBomb.length === cards.length) return usableBomb;

  // Bomb if opponent has <= 3 cards (urgent defense)
  const dangerousOpp = opponents.find(o => !o.hasFinished && o.cardCount <= 3);
  if (dangerousOpp) return usableBomb;

  // Don't bomb for low-value tricks
  return null;
}


// ========== LEAD TRICK STRATEGY ==========

// A "lock play" is one we expect to win uncontested in lead. Used to
// decide whether burning a high combo is justified: only do it if every
// leftover play is also a guaranteed winner (i.e. we chain-finish).
function isLockPlay(plan) {
  if (!plan || plan.length === 0) return false;
  if (plan.length === 1) {
    const cid = plan[0];
    if (cid === 'special_dragon') return true;
    if (getCardValue(cid) >= 14) return true; // A single
    return false;
  }
  const hv = getHighestValue(plan);
  if (plan.length === 2) return hv >= 13;     // K-pair or higher
  return hv >= 12;                              // longer combos: Q+ is safe
}

// Returns true if playing `combo` lets us chain-finish — every leftover
// play wins the lead (lock), except at most ONE non-lock play that empties
// the hand (going out cancels the need to win that final trick). So
// [A,A,K,K,3] after AA chain-finishes (KK is a lock, 3 empties the hand);
// but [3,9,A,A] after AA does not (both 3 and 9 are non-locks).
function canChainOut(combo, cards) {
  if (combo.length === cards.length) return true;
  const remaining = cards.filter(c => !combo.includes(c));
  if (remaining.length === 0) return true;
  const remainingPlans = decomposeHand(remaining);
  if (remainingPlans.length === 0) return false;
  let nonLock = 0;
  for (const p of remainingPlans) {
    if (!isLockPlay(p)) nonLock++;
    if (nonLock > 1) return false;
  }
  return true;
}

function leadTrick(state, cards, normalCards, combos, intel) {
  const partner = getPartner(state);
  const opponents = getOpponents(state);
  const plans = decomposeHand(cards);

  const partnerTichu = partner && !partner.hasFinished && (partner.hasSmallTichu || partner.hasLargeTichu);

  // 0. 1v1 endgame strategies (partner finished, only 1 opponent active)
  const activeOpponents = opponents.filter(o => !o.hasFinished);
  const partnerFinished = !partner || partner.hasFinished;
  const is1v1 = partnerFinished && activeOpponents.length === 1;

  // 0a. 1v1 + opponent on RIGHT: playing dog returns the lead to us (partner
  // and the left opp are both finished, so next-active cycles back to me).
  // Burn the dog now while it's a free action — it's dead weight otherwise.
  if (is1v1 && activeOpponents[0].position === 'right' && cards.includes('special_dog')) {
    return { type: 'play_cards', cards: ['special_dog'] };
  }

  // 0b. 1v1 + opponent has exactly 1 card: they can't follow any combo, so
  // dump combos first (largest clears the most cards), then high singles.
  if (is1v1 && activeOpponents[0].cardCount === 1) {
    const bombSet = new Set(combos.bombs.flat());
    const multiPlans = plans.filter(p =>
      p.length >= 2 && !p.includes('special_dog') && !p.includes('special_bird') &&
      !(p.length === 4 && p.every(c => bombSet.has(c)))
    );
    if (multiPlans.length > 0) {
      multiPlans.sort((a, b) => b.length - a.length);
      return { type: 'play_cards', cards: multiPlans[0] };
    }
    const playable = cards.filter(c => c !== 'special_dog');
    if (playable.length > 0) {
      playable.sort((a, b) => getCardValue(b) - getCardValue(a));
      return { type: 'play_cards', cards: [playable[0]] };
    }
  }

  // 1. Bird: try to include in a straight first
  if (cards.includes('special_bird')) {
    const birdStraight = findStraightIncludingBird(cards);
    if (birdStraight) {
      const callRank = pickCallRank(cards.filter(c => !birdStraight.includes(c)), state);
      return { type: 'play_cards', cards: birdStraight, callRank };
    }
    // Play bird as single
    const callRank = pickCallRank(cards, state);
    return { type: 'play_cards', cards: ['special_bird'], callRank };
  }

  // 2. Dog: use when partner has fewer cards or declared tichu
  if (cards.includes('special_dog')) {
    if (partner && !partner.hasFinished) {
      const partnerFewCards = partner.cardCount <= 5;
      const myCards = cards.filter(c => c !== 'special_dog');

      // Stuck-dog guard: if remaining cards (without dog) can't win any lead,
      // we'll never get another chance to play the dog as a follow — so play it now.
      // Only triggers in the endgame (≤3 non-dog cards) to avoid wasting dog early.
      let stuckDogRisk = false;
      if (myCards.length > 0 && myCards.length <= 3) {
        const remainingPlans = decomposeHand(myCards);
        const canWinLead = remainingPlans.some(p => {
          if (p.length === 1) {
            const v = getCardValue(p[0]);
            return v >= 13 || p[0] === 'special_dragon';
          }
          return p.length >= 2; // any combo is likely to lead a trick
        });
        stuckDogRisk = !canWinLead;
      }

      // Play dog if partner declared tichu, has few cards, we have many cards,
      // or the remaining hand can't win a lead (dog would get stuck otherwise).
      if (partnerTichu || partnerFewCards || myCards.length >= 10 || stuckDogRisk) {
        return { type: 'play_cards', cards: ['special_dog'] };
      }
    }
  }

  // 3. Partner declared tichu: play lowest single to hand over the lead
  //    Don't try to empty our hand fast - let partner finish first
  if (partnerTichu) {
    // Bomb cards aren't really "singles" — pulling one out leaves a 3-of-a-
    // kind and kills the bomb. Filter them out from the low-single picks.
    const bombValuesT = getBombValues(cards);
    const lowSingles = normalCards
      .filter(c => getCardValue(c) <= 8 && !bombValuesT.has(getCardValue(c)))
      .sort((a, b) => getCardValue(a) - getCardValue(b));
    if (lowSingles.length > 0) {
      return { type: 'play_cards', cards: [lowSingles[0]] };
    }
    // No low non-bomb singles → fall back to the lowest non-bomb card.
    const nonBombSorted = normalCards
      .filter(c => !bombValuesT.has(getCardValue(c)))
      .sort((a, b) => getCardValue(a) - getCardValue(b));
    if (nonBombSorted.length > 0) {
      return { type: 'play_cards', cards: [nonBombSorted[0]] };
    }
    // Truly nothing but bomb-rank cards — fall through to the bomb path
    // below (branches 4 / 7) rather than breaking the bomb here.
  }

  // 4. If bomb is our only remaining cards, play it to finish
  for (const bomb of combos.bombs) {
    if (bomb.length === cards.length) {
      return { type: 'play_cards', cards: bomb };
    }
  }

  // 5. Plan-based play: follow decomposed hand plan
  // Play lowest multi-card combo first, then singles
  // Filter out bombs from lead plays — bombs should be saved for defensive use.
  // findCombos only flags 4-of-a-kind in `combos.bombs`, so we additionally
  // detect straight-flush bombs (5+ same-suit consecutive) inline; otherwise
  // they leak in as a normal straight and the bot burns them on a free lead.
  const bombSet = new Set(combos.bombs.flat());
  const multiCardPlans = plans.filter(p =>
    p.length >= 2 && !p.includes('special_dog') && !p.includes('special_bird') &&
    !(p.length === 4 && p.every(c => bombSet.has(c))) &&
    !isStraightFlushBomb(p)
  );
  const singlePlans = plans.filter(p =>
    p.length === 1 && !p[0].startsWith('special_')
  ).sort((a, b) => getCardValue(a[0]) - getCardValue(b[0]));

  // Prefer multi-card combos (play lowest value first)
  if (multiCardPlans.length > 0) {
    // Sort by lowest value first — preserve high cards, clear cheap combos
    multiCardPlans.sort((a, b) => {
      return getHighestValue(a) - getHighestValue(b);
    });
    // Skip high-value combos (A=14, K=13) unless they're part of a chain-out.
    // Burning an A-pair or K-pair early is wasted leverage if the bot can't
    // finish the hand in one go — the leftover low cards just hand the lead
    // back to the opponents anyway.
    const safePlans = multiCardPlans.filter(p => {
      const hv = getHighestValue(p);
      if (hv >= 13) return canChainOut(p, cards);  // A/K combo: chain-out only
      if (hv >= 12) return cards.length <= 8;       // Q combo: late game only
      return true;
    });
    if (safePlans.length > 0) {
      return { type: 'play_cards', cards: safePlans[0] };
    }
    // No safe combo. Prefer leading a non-high single (≤Q=12) over burning
    // a high combo — the high pair/triple stays in hand as future trick
    // winners. Even J/Q single loses cheaper than burning AA/KK on a hopeful
    // chain that won't materialize.
    const nonHighSinglePlans = singlePlans.filter(p => getCardValue(p[0]) <= 12);
    if (nonHighSinglePlans.length > 0) {
      return { type: 'play_cards', cards: [nonHighSinglePlans[0][0]] };
    }
    // Only high singles + high combos left — play the lowest combo since
    // burning a lone A/K single would be strictly worse.
    return { type: 'play_cards', cards: multiCardPlans[0] };
  }

  // 6. Single card - play lowest
  if (singlePlans.length > 0) {
    return { type: 'play_cards', cards: [singlePlans[0][0]] };
  }

  // 7. Only bomb + specials left: play a special rather than breaking the bomb
  if (combos.bombs.length > 0) {
    if (cards.includes('special_phoenix')) {
      return { type: 'play_cards', cards: ['special_phoenix'] };
    }
    if (cards.includes('special_dragon')) {
      return { type: 'play_cards', cards: ['special_dragon'] };
    }
    // No specials available - play the lowest bomb (no other choice)
    return { type: 'play_cards', cards: combos.bombs[0] };
  }

  // 8. Fallback — lowest non-bomb single. Bomb cards stay glued together so
  // shouldBomb / branches 4 & 7 can decide their fate as a unit.
  if (normalCards.length > 0) {
    const bombValuesF = getBombValues(cards);
    const sorted = [...normalCards]
      .filter(c => !bombValuesF.has(getCardValue(c)))
      .sort((a, b) => getCardValue(a) - getCardValue(b));
    if (sorted.length > 0) {
      return { type: 'play_cards', cards: [sorted[0]] };
    }
    // Only bomb cards left → play the bomb instead of pulling one out.
    if (combos.bombs.length > 0) {
      return { type: 'play_cards', cards: combos.bombs[0] };
    }
  }

  const playable = cards.filter(c => c !== 'special_dog');
  if (playable.length > 0) {
    return { type: 'play_cards', cards: [playable[0]] };
  }

  return { type: 'play_cards', cards: [cards[0]] };
}


// ========== FOLLOW TRICK STRATEGY ==========

function followTrick(state, cards, normalCards, combos, intel) {
  const trick = state.currentTrick || [];
  const lastPlay = trick[trick.length - 1];
  const comboType = lastPlay.combo;
  const lastValue = lastPlay.comboValue || getHighestValue(
    lastPlay.cards.filter(c => c !== 'special_phoenix')
  );
  const lastLength = lastPlay.cards.length;

  const partner = getPartner(state);
  const opponents = getOpponents(state);
  const trickPts = estimateTrickPoints(trick);

  // Check if partner played last
  const partnerPlayed = partner && lastPlay.playerId === partner.id;

  // Can I go out with this play?
  function canFinishWith(playCards) {
    return playCards.length === cards.length;
  }

  // Find opponent card counts
  const minOppCards = opponents
    .filter(o => !o.hasFinished)
    .reduce((min, o) => Math.min(min, o.cardCount), Infinity);

  const partnerTichu = isPartnerTichuLive(state, partner);

  // === PARTNER PLAYED: usually pass, unless we can finish ===
  if (partnerPlayed) {
    // Never overtake a live tichu from partner. If we go out first or steal
    // their trick, we are effectively forcing their declaration to fail.
    if (partnerTichu) {
      return { type: 'pass' };
    }

    // Don't step on partner's mid/high combos (comboValue ≥ 9). Even a
    // finish play here would steal partner's earned points. Skip only
    // when partner has finished — at that point they can't benefit from
    // holding the trick.
    if (lastValue >= 9 && partner && !partner.hasFinished) {
      return { type: 'pass' };
    }

    // Check if we can finish by beating partner
    const finishPlay = findFinishingPlay(comboType, lastValue, lastLength, cards, normalCards, combos);
    if (finishPlay) return { type: 'play_cards', cards: finishPlay };

    // If partner already finished, play normally instead of passing
    if (partner && partner.hasFinished) {
      // Fall through to normal play logic
    } else {
      return { type: 'pass' };
    }
  }

  // === BOMB CHECK ===
  const bombPlay = shouldBomb(state, cards, combos);
  if (bombPlay) return { type: 'play_cards', cards: bombPlay };

  // === PARTNER DECLARED TICHU: stay passive, let partner take the lead ===
  // But if partner already passed, we should take the trick to prevent opponents from winning it
  if (partnerTichu) {
    // Check if partner already passed (passCount >= 1 means at least one person passed)
    // If partner is not the last player and trick doesn't contain partner's play, partner passed
    const partnerPlayedInTrick = trick.some(t => t.playerId === partner.id);
    const partnerPassed = !partnerPlayedInTrick && (state.passCount || 0) >= 1;

    if (partnerPassed) {
      // Partner passed - we should try to take the trick with lowest possible cards
      // Fall through to normal opponent play logic below
    } else if (trickPts >= 20 && minOppCards <= 2) {
      // Fall through to normal opponent play logic below
    } else {
      return { type: 'pass' };
    }
  }

  // === OPPONENT PLAYED ===
  if (comboType === 'single') {
    return handleFollowSingle(state, cards, normalCards, combos, lastValue, trickPts, minOppCards, intel);
  }

  if (comboType === 'pair') {
    return handleFollowPair(state, cards, normalCards, combos, lastValue, trickPts, minOppCards);
  }

  if (comboType === 'triple') {
    return handleFollowTriple(state, cards, normalCards, combos, lastValue, trickPts, minOppCards);
  }

  if (comboType === 'straight') {
    return handleFollowStraight(state, cards, normalCards, combos, lastValue, lastLength, trickPts, minOppCards);
  }

  if (comboType === 'full_house') {
    return handleFollowFullHouse(state, cards, normalCards, combos, lastValue, trickPts, minOppCards);
  }

  if (comboType === 'steps') {
    return handleFollowSteps(state, cards, normalCards, combos, lastValue, lastLength, trickPts, minOppCards);
  }

  // Try bombs as last resort for any unknown combo
  const fallbackBomb = shouldBomb(state, cards, combos);
  if (fallbackBomb) return { type: 'play_cards', cards: fallbackBomb };

  return { type: 'pass' };
}

function handleFollowSingle(state, cards, normalCards, combos, lastValue, trickPts, minOppCards, intel) {
  const phoenixCombos = findCombosWithPhoenix(cards);

  // Find all normal cards that can beat
  const beaters = normalCards
    .filter(c => getCardValue(c) > lastValue)
    .sort((a, b) => getCardValue(a) - getCardValue(b));

  // Can finish?
  if (cards.length === 1 && normalCards.length === 1 && getCardValue(normalCards[0]) > lastValue) {
    return { type: 'play_cards', cards: [normalCards[0]] };
  }
  if (cards.length === 1 && cards.includes('special_dragon') && lastValue < 15) {
    return { type: 'play_cards', cards: ['special_dragon'] };
  }
  if (cards.length === 1 && cards.includes('special_phoenix') && lastValue < 14.5) {
    return { type: 'play_cards', cards: ['special_phoenix'] };
  }

  // Play lowest beating normal card — but try NOT to break a pair/triple
  // for a low-value trick. Breaking a pair just to win a 2/3 lead trades a
  // future strong combo for one cheap trick, which is usually a bad deal.
  if (beaters.length > 0) {
    // Endgame aggression: opponent is about to finish — commit a stronger
    // beater to lock the win regardless of combo preservation.
    if (minOppCards <= 3 && beaters.length > 1) {
      return { type: 'play_cards', cards: [beaters[beaters.length - 1]] };
    }

    // Classify beaters by whether they're "loose" (the only card at that
    // rank in hand → not part of a pair/triple) or "in-combo" (playing
    // would break a pair/triple).
    const valueCounts = {};
    for (const c of normalCards) {
      const v = getCardValue(c);
      valueCounts[v] = (valueCounts[v] || 0) + 1;
    }
    const loose = beaters.filter(c => valueCounts[getCardValue(c)] === 1);

    // Cheap loose card (≤9): play freely; preserves any pairs, no waste.
    if (loose.length > 0) {
      const lowestLoose = loose[0];
      const looseVal = getCardValue(lowestLoose);
      if (looseVal <= 9) {
        return { type: 'play_cards', cards: [lowestLoose] };
      }
      // High loose card (10+) for a worthless low trick with hand slack →
      // skip. Don't burn a J/Q/K/A just to take a 0-point single-2 trick.
      if (trickPts < 5 && lastValue < 10
          && cards.length >= 5 && minOppCards > 4) {
        return { type: 'pass' };
      }
      // Trick has stakes or hand running low → commit the loose high card
      // (still preferable to breaking a pair).
      return { type: 'play_cards', cards: [lowestLoose] };
    }

    // Every beater would break a pair/triple. Save the combo when the trick
    // is worthless and there's no pressure: pass.
    if (trickPts < 5 && lastValue < 10
        && cards.length >= 5 && minOppCards > 4) {
      return { type: 'pass' };
    }
    // Otherwise it's worth breaking — play the lowest beater.
    return { type: 'play_cards', cards: [beaters[0]] };
  }

  // 봉황 단독: "선을 잡을 수 있을 때만" 쓴다.
  //
  // 봉황은 낸 순간 (직전 값 + 0.5)이 된다. 10 위에 내면 10.5라서 아직 안 나온
  // J·Q·K·A 아무 장에나 바로 잡힌다 — 선도 못 잡고 -25점짜리 카드만 버리는
  // 자리다. 예전에는 lastValue >= 10 이면 냈는데, 그게 바로 그 자리였다.
  //
  // 그래서 임계값 대신 남은 상위 카드를 센다. 내 손패·걷힌 트릭·지금 트릭에서
  // 안 보인 카드가 곧 남들 손에 있는 카드고, 그중 몇 장이 이 봉황을 넘을 수
  // 있는지가 판단 기준이다. 사람도 세는 정보다.
  if (cards.includes('special_phoenix') && lastValue < 14.5) {
    const resultValue = lastValue + 0.5;
    const beatersOut = intel && intel.game
      ? countOutstandingAbove(intel.game, intel.botId, resultValue)
      : null;
    // 셀 수 없으면(시뮬 등 game 미전달) 예전처럼 A 근처에서만 쓴다.
    const holdsLead = beatersOut === null ? lastValue >= 13 : beatersOut <= 2;
    // A/B 측정용 좌석 게이트(마이티 solver 와 같은 방식). 켜지면 예전 규칙을
    // 그대로 쓴다 — 같은 딜에서 두 규칙을 맞붙이려고 남겨 둔다.
    const legacyGate = typeof global.__tichuPhoenixLegacy === 'function'
      && global.__tichuPhoenixLegacy(intel && intel.botId);
    const shouldUsePhoenix = legacyGate ? (
      cards.length <= 2
      || lastValue >= 13
      || (lastValue >= 10 && (
        cards.length <= 4 || trickPts >= 15 || minOppCards <= 2
      ))
    ) : (() => {
      // 선을 못 지키면 그냥 -25를 상대에게 얹어 주는 셈이라, 강제 상황이
      // 아니면 내지 않는다.
      if (cards.length <= 2) return true;      // 끝내야 하는 자리
      if (!holdsLead) return false;
      // 선을 지킨다고 다 이득은 아니다. 이 트릭을 우리가 가져가면 봉황의
      // -25도 같이 먹으므로, 트릭 점수가 그걸 덮거나 선 자체가 값어치를
      // 할 때(곧 털 수 있다 / 상대가 곧 나간다)만 낸다.
      return trickPts >= 25 || cards.length <= 5 || minOppCards <= 2;
    })();
    if (shouldUsePhoenix) {
      return { type: 'play_cards', cards: ['special_phoenix'] };
    }
  }

  // Dragon as single
  if (cards.includes('special_dragon') && lastValue < 15) {
    const shouldUseDragon = (
      cards.length <= 2 ||  // almost done
      trickPts >= 15 ||     // valuable trick worth winning
      lastValue >= 14       // opponent played A — dragon is the only answer
    );
    if (shouldUseDragon) {
      return { type: 'play_cards', cards: ['special_dragon'] };
    }
  }

  return { type: 'pass' };
}

function handleFollowPair(state, cards, normalCards, combos, lastValue, trickPts, minOppCards) {
  const phoenixCombos = findCombosWithPhoenix(cards);
  const bombValues = getBombValues(cards);

  // Regular pairs (sorted lowest first by findCombos)
  for (const pair of combos.pairs) {
    const pairVal = getCardValue(pair[0]);
    if (pairVal > lastValue) {
      // Can finish?
      if (pair.length === cards.length) return { type: 'play_cards', cards: pair };
      // Bomb preservation: pairs at a quad's value come from the bomb. Skip
      // — let the bomb decision (shouldBomb above) own that pile of cards.
      if (bombValues.has(pairVal)) continue;
      // Save A pair unless trick is valuable or urgent
      if (pairVal >= 14 && trickPts < 20 && cards.length > 5 && minOppCards > 3) {
        continue;
      }
      return { type: 'play_cards', cards: pair };
    }
  }

  // Phoenix pairs
  for (const pair of phoenixCombos.pairs) {
    const pairValue = getCardValue(pair.find(c => c !== 'special_phoenix'));
    if (pairValue > lastValue) {
      // Only use phoenix pair if worth it
      if (cards.length <= 4 || trickPts >= 10 || minOppCards <= 2) {
        return { type: 'play_cards', cards: pair };
      }
    }
  }

  return { type: 'pass' };
}

function handleFollowTriple(state, cards, normalCards, combos, lastValue, trickPts, minOppCards) {
  const phoenixCombos = findCombosWithPhoenix(cards);
  const bombValues = getBombValues(cards);

  for (const triple of combos.triples) {
    const tripleVal = getCardValue(triple[0]);
    if (tripleVal > lastValue) {
      // Bomb preservation: triples at a quad's value steal 3 of 4 bomb
      // cards. Skip — the bomb itself stays available via shouldBomb.
      // (Exception: hand fits exactly — let it finish.)
      if (bombValues.has(tripleVal) && triple.length !== cards.length) continue;
      // Save A triple (value=14) unless trick has 20+ points, few cards left, or opponent almost out
      if (tripleVal >= 14 && trickPts < 20 && cards.length > 5 && minOppCards > 3) {
        continue;
      }
      return { type: 'play_cards', cards: triple };
    }
  }

  // Phoenix triples
  for (const triple of phoenixCombos.triples) {
    const tripleValue = getCardValue(triple.find(c => c !== 'special_phoenix'));
    if (tripleValue > lastValue) {
      if (cards.length <= 5 || trickPts >= 10 || minOppCards <= 2) {
        return { type: 'play_cards', cards: triple };
      }
    }
  }

  return { type: 'pass' };
}

function handleFollowStraight(state, cards, normalCards, combos, lastValue, lastLength, trickPts, minOppCards) {
  const phoenixCombos = findCombosWithPhoenix(cards);
  const bombValues = getBombValues(cards);

  for (const straight of combos.straights) {
    if (straight.length === lastLength) {
      const highVal = getHighestValue(straight);
      if (highVal > lastValue) {
        // A straight that crosses a quad rank would peel one card off the
        // bomb. Skip unless the play finishes us out.
        if (playBreaksBomb(straight, bombValues)
            && straight.length !== cards.length) continue;
        return { type: 'play_cards', cards: straight };
      }
    }
  }

  // Phoenix straights - compute the effective high value including phoenix position
  for (const straight of phoenixCombos.straights) {
    if (straight.length === lastLength) {
      // Phoenix extends the straight at top or fills a gap
      // The effective high value is the max value that the straight reaches
      const normalVals = straight.filter(c => c !== 'special_phoenix').map(c => getCardValue(c)).sort((a, b) => a - b);
      let effectiveHigh = normalVals[normalVals.length - 1];
      // Check if phoenix extends at top (all consecutive without gap)
      let hasGap = false;
      for (let i = 1; i < normalVals.length; i++) {
        if (normalVals[i] - normalVals[i-1] === 2) hasGap = true;
      }
      if (!hasGap) effectiveHigh = normalVals[normalVals.length - 1] + 1;

      if (effectiveHigh > lastValue) {
        if (straight.length === cards.length || trickPts >= 10 || minOppCards <= 3) {
          return { type: 'play_cards', cards: straight };
        }
      }
    }
  }

  return { type: 'pass' };
}

function handleFollowFullHouse(state, cards, normalCards, combos, lastValue, trickPts, minOppCards) {
  const phoenixCombos = findCombosWithPhoenix(cards);
  const bombValues = getBombValues(cards);

  for (const fh of combos.fullHouses) {
    const fhTripleVal = getFullHouseTripleValue(fh);
    if (fhTripleVal > lastValue) {
      // The triple half of an FH at a bomb value uses 3 of 4 quad cards;
      // the pair half at a bomb value uses 2 of 4. Either way the bomb is
      // dead. Skip unless finishing.
      if (playBreaksBomb(fh, bombValues) && fh.length !== cards.length) continue;
      return { type: 'play_cards', cards: fh };
    }
  }

  // Phoenix full houses - compute true triple value (phoenix acts as part of the triple)
  for (const fh of phoenixCombos.fullHouses) {
    const fhTripleVal = getPhoenixFullHouseTripleValue(fh);
    if (fhTripleVal > lastValue) {
      if (cards.length <= 7 || trickPts >= 10 || minOppCards <= 3) {
        return { type: 'play_cards', cards: fh };
      }
    }
  }

  return { type: 'pass' };
}

/** Get triple value for a full house containing phoenix */
function getPhoenixFullHouseTripleValue(cards) {
  const normalCards = cards.filter(c => c !== 'special_phoenix');
  const counts = {};
  for (const c of normalCards) {
    const v = getCardValue(c);
    counts[v] = (counts[v] || 0) + 1;
  }
  const entries = Object.entries(counts).map(([v, cnt]) => ({ v: Number(v), cnt }));

  // If there's a real triple (3 cards of same value), that's the triple value
  for (const e of entries) {
    if (e.cnt === 3) return e.v;
  }

  // Phoenix makes the higher pair into a triple
  // entries should be like [{v:4, cnt:2}, {v:7, cnt:2}] → phoenix makes max into triple
  if (entries.length === 2 && entries.every(e => e.cnt === 2)) {
    return Math.max(entries[0].v, entries[1].v);
  }

  // entries like [{v:X, cnt:3}, {v:Y, cnt:1}] → phoenix makes the single into a pair
  for (const e of entries) {
    if (e.cnt === 3) return e.v;
  }

  // Fallback
  return getHighestValue(normalCards);
}

function handleFollowSteps(state, cards, normalCards, combos, lastValue, lastLength, trickPts, minOppCards) {
  const phoenixCombos = findCombosWithPhoenix(cards);
  const bombValues = getBombValues(cards);

  for (const step of combos.steps) {
    if (step.length === lastLength) {
      const highVal = getHighestValue(step);
      if (highVal > lastValue) {
        // Bomb preservation: any rank inside the step that also forms a
        // quad means we'd be tearing the bomb apart for a step trick. Skip
        // unless this step finishes the hand.
        if (playBreaksBomb(step, bombValues)
            && step.length !== cards.length) continue;
        return { type: 'play_cards', cards: step };
      }
    }
  }

  // Phoenix steps
  for (const step of phoenixCombos.steps) {
    if (step.length === lastLength) {
      const highVal = getHighestValue(step.filter(c => c !== 'special_phoenix'));
      if (highVal > lastValue) {
        if (playBreaksBomb(step, bombValues)
            && step.length !== cards.length) continue;
        if (step.length === cards.length || trickPts >= 10 || minOppCards <= 3) {
          return { type: 'play_cards', cards: step };
        }
      }
    }
  }

  return { type: 'pass' };
}

/** Find a play that uses ALL remaining cards to finish */
function findFinishingPlay(comboType, lastValue, lastLength, cards, normalCards, combos) {
  if (comboType === 'single' && cards.length === 1) {
    const card = cards[0];
    if (card === 'special_dragon' && lastValue < 15) return [card];
    if (card === 'special_phoenix' && lastValue < 14.5) return [card];
    if (!card.startsWith('special_') && getCardValue(card) > lastValue) return [card];
  }
  if (comboType === 'pair' && cards.length === 2) {
    const v = getCardValue(cards[0]);
    const v2 = getCardValue(cards[1]);
    if (v === v2 && v > lastValue) return cards;
    // Phoenix pair
    if (cards.includes('special_phoenix')) {
      const other = cards.find(c => c !== 'special_phoenix');
      if (other && getCardValue(other) > lastValue) return cards;
    }
  }
  if (comboType === 'triple' && cards.length === 3) {
    for (const triple of combos.triples) {
      if (triple.length === 3 && getCardValue(triple[0]) > lastValue) return triple;
    }
  }
  // Check if all cards form a valid straight/full house/steps
  if (cards.length === lastLength) {
    if (comboType === 'straight') {
      for (const s of combos.straights) {
        if (s.length === lastLength && getHighestValue(s) > lastValue) return s;
      }
    }
    if (comboType === 'full_house') {
      for (const fh of combos.fullHouses) {
        if (getFullHouseTripleValue(fh) > lastValue) return fh;
      }
    }
    if (comboType === 'steps') {
      for (const st of combos.steps) {
        if (st.length === lastLength && getHighestValue(st) > lastValue) return st;
      }
    }
  }
  return null;
}


// ========== WIN-RATE SEARCH ==========

const TICHU_SEARCH_MAX_STEPS = 192;

function normalizeTichuStrategy(strategy) {
  if (strategy === 'heuristic') return 'heuristic';
  if (strategy === 'winrate') return 'winrate';
  // Legacy UI values from other game types map to the upgraded Tichu search.
  return 'winrate';
}

function getBotTeamKey(game, botId) {
  return game.teams.teamA.includes(botId) ? 'teamA' : 'teamB';
}

function getOpposingTeamKey(teamKey) {
  return teamKey === 'teamA' ? 'teamB' : 'teamA';
}

function removeCardsOnce(cards, playedCards) {
  const remaining = cards.slice();
  for (const card of playedCards) {
    const idx = remaining.indexOf(card);
    if (idx !== -1) remaining.splice(idx, 1);
  }
  return remaining;
}

function shuffleArray(arr) {
  const copy = arr.slice();
  for (let i = copy.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [copy[i], copy[j]] = [copy[j], copy[i]];
  }
  return copy;
}

function getActionKey(action) {
  if (!action) return '';
  if (action.type === 'play_cards') {
    const cards = (action.cards || []).slice().sort().join(',');
    return `play:${cards}:${action.callRank || ''}`;
  }
  if (action.type === 'exchange_cards') {
    return `exchange:${action.cards?.left || ''}:${action.cards?.partner || ''}:${action.cards?.right || ''}`;
  }
  if (action.type === 'dragon_give') return `dragon:${action.target}`;
  if (action.type === 'call_rank') return `call:${action.rank}`;
  return action.type || '';
}

function getPlayActionStrength(action) {
  if (!action || action.type !== 'play_cards') return -1;
  const cards = action.cards || [];
  return getHighestValue(cards.filter(c => c !== 'special_phoenix'));
}

function buildPlayAction(cards, allCards, isLead, state) {
  if (!cards || cards.length === 0) return null;
  const action = { type: 'play_cards', cards: cards.slice() };
  if (isLead && cards.includes('special_bird')) {
    const remaining = removeCardsOnce(allCards, cards);
    action.callRank = pickCallRank(remaining, state);
  }
  return action;
}

function collectRawPlayCandidates(cards, isLead, state) {
  const candidates = [];
  const normalCards = cards.filter(c => !c.startsWith('special_'));
  const combos = findCombos(normalCards);
  const phoenixCombos = findCombosWithPhoenix(cards);

  for (const card of cards) {
    candidates.push(buildPlayAction([card], cards, isLead, state));
  }

  const comboGroups = [
    combos.pairs, combos.triples, combos.straights, combos.fullHouses, combos.steps, combos.bombs,
    phoenixCombos.pairs, phoenixCombos.triples, phoenixCombos.straights, phoenixCombos.fullHouses, phoenixCombos.steps,
  ];
  for (const group of comboGroups) {
    for (const combo of group) {
      candidates.push(buildPlayAction(combo, cards, isLead, state));
    }
  }

  const birdStraight = findStraightIncludingBird(cards);
  if (birdStraight) {
    candidates.push(buildPlayAction(birdStraight, cards, isLead, state));
  }

  const allInPlay = buildPlayAction(cards, cards, isLead, state);
  if (allInPlay) candidates.push(allInPlay);

  return candidates.filter(Boolean);
}

function canApplyAction(game, botId, action) {
  // Fast path: play_cards legality via the game's pure validator — no clone.
  // This is the hot spot: a full hand yields dozens of play candidates, and the
  // old clone()+handleAction per candidate was the dominant per-decision cost
  // (uncapped by the search time budget). Pass/dragon_give are few, so they keep
  // the simple clone path.
  if (action && action.type === 'play_cards' && typeof game.canPlayCards === 'function') {
    return game.canPlayCards(botId, action.cards || []).success === true;
  }
  const clone = game.clone();
  clone._suppressBotSearchLogs = true;
  const result = clone.handleAction(botId, action);
  return !!(result && result.success);
}

function filterLegalActions(game, botId, actions) {
  const seen = new Set();
  const legal = [];
  for (const action of actions) {
    const key = getActionKey(action);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    if (canApplyAction(game, botId, action)) {
      legal.push(action);
    }
  }
  return legal;
}

function prunePlayCandidates(actions, heuristicAction, handSize) {
  if (actions.length <= 1) return actions;

  const heuristicKey = getActionKey(heuristicAction);
  const maxCandidates = handSize <= 4 ? 12 : handSize <= 8 ? 10 : 8;
  const kept = [];
  const keptKeys = new Set();
  const groups = new Map();

  function keep(action) {
    const key = getActionKey(action);
    if (!key || keptKeys.has(key)) return;
    kept.push(action);
    keptKeys.add(key);
  }

  for (const action of actions) {
    if (action.type !== 'play_cards') {
      keep(action);
      continue;
    }
    const combo = getComboType(action.cards || []);
    const groupKey = `${combo.type}:${combo.length || (action.cards || []).length}`;
    if (!groups.has(groupKey)) groups.set(groupKey, []);
    groups.get(groupKey).push(action);

    if ((action.cards || []).length === handSize || combo.type === COMBO.BOMB_FOUR || combo.type === COMBO.BOMB_STRAIGHT_FLUSH) {
      keep(action);
    }
  }

  if (heuristicAction) keep(heuristicAction);

  for (const group of groups.values()) {
    group.sort((a, b) => getPlayActionStrength(a) - getPlayActionStrength(b));
    if (group.length > 0) keep(group[0]);
    if (group.length > 1) keep(group[group.length - 1]);
  }

  if (kept.length > maxCandidates) {
    kept.sort((a, b) => scoreCandidatePriority(b, heuristicKey, handSize) - scoreCandidatePriority(a, heuristicKey, handSize));
    return kept.slice(0, maxCandidates);
  }

  if (kept.length < maxCandidates) {
    const extras = actions
      .filter(action => !keptKeys.has(getActionKey(action)))
      .sort((a, b) => scoreCandidatePriority(b, heuristicKey, handSize) - scoreCandidatePriority(a, heuristicKey, handSize));
    for (const action of extras) {
      if (kept.length >= maxCandidates) break;
      keep(action);
    }
  }

  return kept;
}

function scoreCandidatePriority(action, heuristicKey, handSize) {
  const key = getActionKey(action);
  if (key === heuristicKey) return 10000;
  if (action.type === 'pass') return 5000;
  if (action.type === 'dragon_give') return 5000;
  if (action.type !== 'play_cards') return 4000;

  const combo = getComboType(action.cards || []);
  let score = 1000;
  if ((action.cards || []).length === handSize) score += 8000;
  if (combo.type === COMBO.BOMB_FOUR || combo.type === COMBO.BOMB_STRAIGHT_FLUSH) score += 4000;
  score += (action.cards || []).length * 40;
  score -= getPlayActionStrength(action);
  return score;
}

function buildWinrateCandidates(game, botId, state = game.getStateForPlayer(botId)) {
  const cards = state.myCards || [];
  if (state.phase !== 'playing') return [];

  if (state.needsToCallRank) {
    return [{ type: 'call_rank', rank: pickCallRank(cards, state) }];
  }
  if (game.dragonPending && game.dragonDecider === botId) {
    return [
      { type: 'dragon_give', target: 'left' },
      { type: 'dragon_give', target: 'right' },
    ].filter(action => canApplyAction(game, botId, action));
  }
  if (!state.isMyTurn) return [];

  const rawActions = collectRawPlayCandidates(cards, (state.currentTrick || []).length === 0, state);
  if ((state.currentTrick || []).length > 0) {
    rawActions.push({ type: 'pass' });
  }

  let legalActions = filterLegalActions(game, botId, rawActions);
  const heuristicAction = autoPlay(state, cards, { game, botId });

  // A3: never bomb partner's trick. Heuristic's shouldBomb returns null
  // when partner played last, but winrate's candidate list still carries
  // bomb options — strip them so simulation noise can't pick a bomb that
  // steals the partner's trick.
  const partner = getPartner(state);
  const trick = state.currentTrick || [];
  const lastPlay = trick[trick.length - 1];
  if (lastPlay && partner && lastPlay.playerId === partner.id) {
    legalActions = legalActions.filter(action => {
      if (action.type !== 'play_cards') return true;
      const combo = getComboType(action.cards || []);
      return combo.type !== COMBO.BOMB_FOUR
        && combo.type !== COMBO.BOMB_STRAIGHT_FLUSH;
    });
  }

  // A4: enforce shouldBomb on follow tricks. shouldBomb owns the "when
  // to bomb" decision (tichu defense, ≥20 pts, finish-by-bomb, opp ≤3
  // cards). If it says no, strip bomb candidates from the winrate search
  // — rollouts otherwise find a shallow "win this trick" line and burn
  // a 100-point combo on a worthless trick (e.g. a mahjong wish on a
  // rank we don't hold, or a single low card behind us). Lead bombs
  // are handled by leadTrick's own logic and aren't filtered here.
  // Finishing plays bypass the filter — going out matters more.
  if (lastPlay) {
    const bombCombos = findCombos(cards.filter(c => !c.startsWith('special_')));
    const wantsBomb = shouldBomb(state, cards, bombCombos);
    if (!wantsBomb) {
      legalActions = legalActions.filter(action => {
        if (action.type !== 'play_cards') return true;
        const playCards = action.cards || [];
        if (playCards.length === cards.length) return true;
        const combo = getComboType(playCards);
        return combo.type !== COMBO.BOMB_FOUR
          && combo.type !== COMBO.BOMB_STRAIGHT_FLUSH;
      });
    }
  }

  // A5: never overtake partner's mid/high plays (comboValue ≥ 9). Even
  // when there's no tichu in play, stealing a teammate's strong lead
  // wastes their card and rarely pays off — keep only pass for winrate.
  // Exception: partner has already finished, so they can't benefit.
  if (lastPlay
      && partner
      && !partner.hasFinished
      && lastPlay.playerId === partner.id
      && (lastPlay.comboValue || 0) >= 9) {
    legalActions = legalActions.filter(action => action.type !== 'play_cards');
  }

  // D-extra: don't burn Phoenix as a single on a low card. Phoenix as
  // single becomes lastValue + 0.5 so on a 4 it lands at 4.5 — easily
  // reclaimed by any 5+. Reserve for high-card territory or true
  // endgame so winrate's rollouts can't pick the "instant trick win"
  // line that nukes a 25-point card.
  if (lastPlay
      && lastPlay.combo === 'single'
      && (lastPlay.comboValue || 0) < 10
      && cards.length > 2
      && cards.includes('special_phoenix')) {
    legalActions = legalActions.filter(action => {
      if (action.type !== 'play_cards') return true;
      const cardsInAction = action.cards || [];
      return !(cardsInAction.length === 1 && cardsInAction[0] === 'special_phoenix');
    });
  }

  // Bomb preservation: drop ANY non-bomb play that uses (but doesn't
  // exhaust) cards from a 4-of-a-kind in hand. findCombos generates
  // pairs/triples/steps/straights/full-houses from quad cards too, and
  // winrate would happily pick e.g. pair-of-6 from a 6666 quad to win one
  // trick — destroying a bomb worth 100 points and an automatic trick
  // win in the process. The bomb itself stays in legalActions (as a
  // BOMB_FOUR / BOMB_STRAIGHT_FLUSH); shouldBomb owns the "when to use"
  // decision. Finishing plays bypass the filter — going out matters more
  // than a held bomb.
  const bombValues = getBombValues(cards);
  if (bombValues.size > 0) {
    legalActions = legalActions.filter(action => {
      if (action.type !== 'play_cards') return true;
      const playCards = action.cards || [];
      // Finishing the hand: always allow regardless of bomb preservation.
      if (playCards.length === cards.length) return true;
      const combo = getComboType(playCards);
      // Real bombs (the full quad / SF) must stay — that's what we WANT.
      if (combo.type === COMBO.BOMB_FOUR
          || combo.type === COMBO.BOMB_STRAIGHT_FLUSH) return true;
      return !playBreaksBomb(playCards, bombValues);
    });
  }

  // Lead structure preservation: when LEADING (empty trick), a shallow winrate
  // rollout over-values grabbing the current trick, so it pulls a single out of
  // a pair/triple (55 -> 5) or a pair out of a triple (888 -> 88), stranding the
  // leftover card. The heuristic's decomposeHand never does this — it leads the
  // leftover singles and keeps same-rank groups whole (pair/triple/full-house).
  // Mirror that: on lead, drop any single/pair/triple play that uses only PART
  // of a larger same-rank group we hold. Straights/steps/full-houses span
  // different ranks and are left alone (decomposeHand itself pulls one card from
  // a pair to build a straight). Finishing plays and real bombs are exempt.
  if (trick.length === 0) {
    const heldByValue = {};
    for (const c of cards) {
      if (c.startsWith('special_')) continue;
      const v = getCardValue(c);
      heldByValue[v] = (heldByValue[v] || 0) + 1;
    }
    legalActions = legalActions.filter(action => {
      if (action.type !== 'play_cards') return true;
      const playCards = action.cards || [];
      if (playCards.length === cards.length) return true; // finishing play
      const combo = getComboType(playCards);
      if (combo.type !== COMBO.SINGLE
        && combo.type !== COMBO.PAIR
        && combo.type !== COMBO.TRIPLE) return true; // only same-rank groups
      const normal = playCards.find(c => !c.startsWith('special_'));
      if (!normal) return true; // pure special (e.g. lone phoenix) — leave it
      const v = getCardValue(normal);
      // Breaks a larger held group of this rank → strands the remainder.
      return (heldByValue[v] || 0) <= playCards.length;
    });

    // Lead low-single bias: a shallow rollout over-values winning the current
    // trick, so it leads a HIGH single (K/A) instead of dumping a low one —
    // burning a stopper. The heuristic always leads its LOWEST single. Match
    // that: among NORMAL single-card lead candidates, keep only the lowest.
    // Combos (pairs/straights/steps/full-houses) and special singles (bird/dog/
    // phoenix/dragon, which have their own lead rules) are left for the rollout.
    const normalSingles = legalActions.filter(a =>
      a.type === 'play_cards'
      && (a.cards || []).length === 1
      && !a.cards[0].startsWith('special_'));
    if (normalSingles.length > 1) {
      let lowest = normalSingles[0];
      for (const a of normalSingles) {
        if (getCardValue(a.cards[0]) < getCardValue(lowest.cards[0])) lowest = a;
      }
      const dropKeys = new Set(
        normalSingles.filter(a => a !== lowest).map(a => getActionKey(a)));
      legalActions = legalActions.filter(a => !dropKeys.has(getActionKey(a)));
    }
  }

  // Pair preservation: on a cheap low single lead (worthless trick, opp
  // not close to finishing, hand still has slack), drop candidate SINGLE
  // plays that would break a pair/triple in hand. Forces the simulator
  // to choose between pass and a "loose" (singleton-rank) beater.
  // Mirrors the same gate used in handleFollowSingle so winrate doesn't
  // overrule the heuristic by valuing "win cheap trick" over preserving
  // future combo value. Special cards already covered by the D-extra
  // phoenix filter above; bombs and combos aren't single plays.
  if (lastPlay
      && lastPlay.combo === 'single'
      && (lastPlay.comboValue || 0) < 10
      && cards.length >= 5) {
    const trickPts = estimateTrickPoints(trick);
    const activeOpps = getOpponents(state).filter(o => !o.hasFinished);
    const minOppCards = activeOpps.length === 0
      ? Infinity
      : activeOpps.reduce((min, o) => Math.min(min, o.cardCount), Infinity);
    if (trickPts < 5 && minOppCards > 4) {
      const normalCards = cards.filter(c => !c.startsWith('special_'));
      const valueCounts = {};
      for (const c of normalCards) {
        const v = getCardValue(c);
        valueCounts[v] = (valueCounts[v] || 0) + 1;
      }
      legalActions = legalActions.filter(action => {
        if (action.type !== 'play_cards') return true;
        const acts = action.cards || [];
        if (acts.length !== 1) return true; // only single plays
        const c = acts[0];
        if (c.startsWith('special_')) return true; // phoenix/dragon — let other filters handle
        const v = getCardValue(c);
        return valueCounts[v] === 1; // keep only loose (singleton-rank) singles
      });
    }
  }

  // Layer heuristic's strategic rules onto winrate's search. In cases
  // where the heuristic has a strong tactical preference that the noisy
  // simulation can mis-weigh (partner tichu protection, 1v1 endgame,
  // special-card usage), force the search to honor the heuristic's pick
  // rather than letting rollout noise override it.
  if (shouldHonorHeuristic(state, heuristicAction)) {
    return [heuristicAction];
  }

  return prunePlayCandidates(legalActions, heuristicAction, cards.length);
}

/** True when winrate should defer to the heuristic's chosen action because
 *  the situation has a known-good tactical answer that simulation noise
 *  can mis-evaluate. Covers:
 *    A — partner tichu live (pass on follow, passive lead). The "never
 *        bomb partner's trick" rule (A3) is enforced separately by
 *        filtering bomb candidates upstream.
 *    C — 1v1 endgame (partner finished, only one opponent active).
 *    D — heuristic chose to play a special card (Bird/Dog/Phoenix/Dragon),
 *        which have conservative usage rules baked into the heuristic. */
function shouldHonorHeuristic(state, heuristicAction) {
  if (!heuristicAction) return false;
  if (heuristicAction.type !== 'play_cards' && heuristicAction.type !== 'pass') {
    return false;
  }

  const partner = getPartner(state);
  const opponents = getOpponents(state);

  // A: partner tichu live — honor follow pass and passive lead.
  if (isPartnerTichuLive(state, partner)) return true;

  // C: 1v1 endgame — partner finished, only one opponent active.
  const partnerFinished = !partner || partner.hasFinished;
  const activeOpps = opponents.filter(o => !o.hasFinished);
  if (partnerFinished && activeOpps.length === 1) return true;

  // D: heuristic plays a special card (Bird/Dog/Phoenix/Dragon).
  if (heuristicAction.type === 'play_cards') {
    const playedCards = heuristicAction.cards || [];
    if (playedCards.some(c => c.startsWith('special_'))) return true;
  }

  return false;
}

function determinizeGameForBot(game, botId) {
  const world = game.clone();
  world._suppressBotSearchLogs = true;

  const knownCards = new Set(world.hands[botId] || []);
  for (const pile of Object.values(world.trickPiles || {})) {
    for (const card of pile) knownCards.add(card);
  }
  for (const play of (world.currentTrick || [])) {
    for (const card of play.cards || []) knownCards.add(card);
  }
  for (const card of (world.pendingTrickCards || [])) {
    knownCards.add(card);
  }

  const unseenCards = createDeck()
    .map(card => card.id)
    .filter(cardId => !knownCards.has(cardId));
  const shuffled = shuffleArray(unseenCards);

  let cursor = 0;
  for (const pid of world.playerIds) {
    if (pid === botId) {
      world.hands[pid] = (game.hands[pid] || []).slice();
      continue;
    }
    const need = (game.hands[pid] || []).length;
    world.hands[pid] = shuffled.slice(cursor, cursor + need);
    cursor += need;
  }

  return world;
}

function getPendingSimulationActor(game) {
  if (game.needsToCallRank) return game.needsToCallRank;
  if (game.dragonPending) return game.dragonDecider;
  return game.currentPlayer;
}

// Plays a determinized world to round_end with the heuristic policy. Returns
// true only if it reached a terminal state (so the score is meaningful). An
// early-game rollout replays a whole round (~60 heuristic decisions) and can
// take 100-250ms on its own — longer than the search's whole time budget — and
// the per-candidate deadline outside can't interrupt a rollout already running.
// So we check `deadline` INSIDE the loop and bail (returning false) the moment
// it's exceeded; the caller discards that incomplete sample. This hard-caps a
// single decision at ~budget instead of letting one fat rollout overshoot it.
function runHeuristicRollout(game, deadline = 0) {
  let steps = 0;
  while (game.state !== 'round_end' && game.state !== 'game_end' && steps < TICHU_SEARCH_MAX_STEPS) {
    if (deadline && performance.now() >= deadline) return false;
    const actor = getPendingSimulationActor(game);
    if (!actor) break;

    let action = decideHeuristicBotAction(game, actor);
    if (!action) action = game.getAutoTimeoutAction(actor);
    if (!action) break;

    let result = game.handleAction(actor, action);
    if (!result || !result.success) {
      const fallback = game.getAutoTimeoutAction(actor);
      if (!fallback) break;
      result = game.handleAction(actor, fallback);
      if (!result || !result.success) break;
    }
    steps++;
  }
  return game.state === 'round_end' || game.state === 'game_end';
}

function evaluateSimulatedOutcome(game, botId) {
  const myTeam = getBotTeamKey(game, botId);
  const oppTeam = getOpposingTeamKey(myTeam);
  const margin = (game.totalScores[myTeam] || 0) - (game.totalScores[oppTeam] || 0);
  const roundMargin = game.lastRoundScores
    ? (game.lastRoundScores[myTeam] || 0) - (game.lastRoundScores[oppTeam] || 0)
    : margin;
  const win = margin > 0 ? 1 : margin < 0 ? 0 : 0.5;
  return { win, margin, roundMargin };
}

function getSearchSampleCount(cardCount) {
  if (cardCount <= 3) return 8;
  if (cardCount <= 6) return 6;
  if (cardCount <= 9) return 4;
  return 3;
}

function getWinrateSearchBudget(game, state, candidateCount) {
  const handSize = (state.myCards || []).length;
  const trickSize = (state.currentTrick || []).length;
  const hasActiveCall = !!state.callRank && trickSize > 0;

  let samples = getSearchSampleCount(handSize);
  // Budgets lowered from 90–140ms: the search is synchronous on the single
  // event-loop thread, so the old caps let one Tichu bot decision stall the
  // whole server for up to ~160ms. Typical decisions finish in a few ms; only
  // rare early-game positions hit the cap, so trimming the cap mostly affects
  // the tail (the spikes) and leaves common decisions untouched. A full sample
  // pass over all candidates costs ~10–30ms, so ~50–60ms still guarantees every
  // candidate is evaluated at least once.
  let timeBudgetMs = 55;

  if (trickSize === 0) {
    timeBudgetMs = 60;
  }
  if (hasActiveCall) {
    samples = Math.max(2, samples - 1);
    timeBudgetMs = 45;
  }
  if (candidateCount >= 8) {
    samples = Math.max(2, samples - 1);
    timeBudgetMs = Math.min(timeBudgetMs, 50);
  }
  if (handSize <= 4) {
    timeBudgetMs += 10;
  }

  return { samples, timeBudgetMs };
}

function rankWinrateEntry(entry, heuristicKey, handSize) {
  if (!entry || entry.samples === 0) return -Infinity;
  const winRate = entry.winSum / entry.samples;
  const avgMargin = entry.marginSum / entry.samples;
  const avgRoundMargin = entry.roundMarginSum / entry.samples;
  const priority = scoreCandidatePriority(entry.action, heuristicKey, handSize);
  return (winRate * 1000000) + (avgMargin * 1000) + avgRoundMargin + (priority / 1000000);
}

function chooseBestWinrateAction(game, botId, candidates, state = game.getStateForPlayer(botId), diagTiming = null) {
  if (candidates.length <= 1) return candidates[0] || null;

  const diagOn = process.env.DIAG !== '0';
  const diagSlowMs = Number.isFinite(Number(process.env.DIAG_BOT_SLOW_MS))
    ? Number(process.env.DIAG_BOT_SLOW_MS)
    : 100;
  const diagStart = diagOn ? process.hrtime.bigint() : 0n;
  let evals = 0;
  let completedRollouts = 0;
  let stoppedByBudget = false;
  let heuristicMs = 0;
  let setupMs = 0;
  let determinizeMs = 0;
  // state build + candidate build happen in decideWinrateBotAction (one shared
  // getStateForPlayer), passed in via diagTiming so the whole bot-decide span
  // shows up on one line instead of hiding ~half the time outside this fn.
  const stateMs = diagTiming ? diagTiming.stateMs : 0;
  const candMs = diagTiming ? diagTiming.candMs : 0;

  const handSize = (state.myCards || []).length;
  const heuristicStart = diagOn ? process.hrtime.bigint() : 0n;
  const heuristicAction = autoPlay(state, state.myCards || [], { game, botId });
  if (diagOn) heuristicMs = Number(process.hrtime.bigint() - heuristicStart) / 1e6;
  const heuristicKey = getActionKey(heuristicAction);
  const { samples, timeBudgetMs } = getWinrateSearchBudget(game, state, candidates.length);
  const setupStart = diagOn ? process.hrtime.bigint() : 0n;
  const stats = new Map();
  for (const candidate of candidates) {
    stats.set(getActionKey(candidate), {
      action: candidate,
      winSum: 0,
      marginSum: 0,
      roundMarginSum: 0,
      samples: 0,
    });
  }

  let activeKeys = candidates
    .slice()
    .sort((a, b) => scoreCandidatePriority(b, heuristicKey, handSize) - scoreCandidatePriority(a, heuristicKey, handSize))
    .map(getActionKey);
  if (diagOn) setupMs = Number(process.hrtime.bigint() - setupStart) / 1e6;
  const deadline = performance.now() + timeBudgetMs;

  for (let sample = 0; sample < samples && activeKeys.length > 0; sample++) {
    if (performance.now() >= deadline) {
      stoppedByBudget = true;
      break;
    }
    const detStart = diagOn ? process.hrtime.bigint() : 0n;
    const baseWorld = determinizeGameForBot(game, botId);
    if (diagOn) determinizeMs += Number(process.hrtime.bigint() - detStart) / 1e6;
    for (const key of activeKeys) {
      if (performance.now() >= deadline) {
        stoppedByBudget = true;
        break;
      }
      const entry = stats.get(key);
      if (!entry) continue;
      const sim = baseWorld.clone();
      sim._suppressBotSearchLogs = true;

      const result = sim.handleAction(botId, entry.action);
      if (!result || !result.success) continue;

      // Deadline-aware: a single rollout can exceed the whole budget, so it may
      // bail mid-play. Discard the incomplete sample and stop sampling — time's up.
      evals++;
      const completed = runHeuristicRollout(sim, deadline);
      if (!completed) {
        stoppedByBudget = true;
        activeKeys = [];
        break;
      }
      const outcome = evaluateSimulatedOutcome(sim, botId);
      entry.winSum += outcome.win;
      entry.marginSum += outcome.margin;
      entry.roundMarginSum += outcome.roundMargin;
      entry.samples += 1;
      completedRollouts++;
    }

    // Successive halving: after each round, keep only the best-performing
    // candidates so we don't spend the entire budget evaluating dominated lines.
    if (activeKeys.length > 3 && performance.now() < deadline) {
      activeKeys = activeKeys
        .map(key => stats.get(key))
        .filter(entry => entry && entry.samples > 0)
        .sort((a, b) => rankWinrateEntry(b, heuristicKey, handSize) - rankWinrateEntry(a, heuristicKey, handSize))
        .slice(0, sample === 0 ? Math.max(4, Math.ceil(activeKeys.length / 2)) : 3)
        .map(entry => getActionKey(entry.action));
    }
  }

  let best = null;
  for (const entry of stats.values()) {
    if (entry.samples === 0) continue;
    entry.winRate = entry.winSum / entry.samples;
    entry.avgMargin = entry.marginSum / entry.samples;
    entry.avgRoundMargin = entry.roundMarginSum / entry.samples;

    if (!best
        || entry.winRate > best.winRate
        || (entry.winRate === best.winRate && entry.avgMargin > best.avgMargin)
        || (entry.winRate === best.winRate && entry.avgMargin === best.avgMargin && entry.avgRoundMargin > best.avgRoundMargin)
        || (entry.winRate === best.winRate && entry.avgMargin === best.avgMargin && entry.avgRoundMargin === best.avgRoundMargin
            && scoreCandidatePriority(entry.action, heuristicKey, handSize) > scoreCandidatePriority(best.action, heuristicKey, handSize))) {
      best = entry;
    }
  }

  if (!best) {
    const heuristicCandidate = candidates.find(action => getActionKey(action) === heuristicKey);
    const fallback = heuristicCandidate || candidates[0];
    if (diagOn) {
      const elapsed = Number(process.hrtime.bigint() - diagStart) / 1e6;
      if (elapsed > diagSlowMs) {
        console.log(`[DIAG] tichu-winrate-detail ${elapsed.toFixed(0)}ms bot=${botId} budget=${timeBudgetMs}ms hand=${handSize} candidates=${candidates.length} state=${stateMs.toFixed(0)}ms cand=${candMs.toFixed(0)}ms heur=${heuristicMs.toFixed(0)}ms setup=${setupMs.toFixed(0)}ms det=${determinizeMs.toFixed(0)}ms evals=${evals} completed=${completedRollouts} samples=0 stopped=${stoppedByBudget ? 1 : 0} fallback=${getActionKey(fallback)}`);
      }
    }
    return fallback;
  }

  if (diagOn) {
    const elapsed = Number(process.hrtime.bigint() - diagStart) / 1e6;
    if (elapsed > diagSlowMs) {
      console.log(`[DIAG] tichu-winrate-detail ${elapsed.toFixed(0)}ms bot=${botId} budget=${timeBudgetMs}ms hand=${handSize} candidates=${candidates.length} state=${stateMs.toFixed(0)}ms cand=${candMs.toFixed(0)}ms heur=${heuristicMs.toFixed(0)}ms setup=${setupMs.toFixed(0)}ms det=${determinizeMs.toFixed(0)}ms evals=${evals} completed=${completedRollouts} samples=${best.samples} stopped=${stoppedByBudget ? 1 : 0} best=${getActionKey(best.action)}`);
    }
  }
  return best.action;
}

function decideWinrateBotAction(game, botId) {
  const diagOn = process.env.DIAG !== '0';
  // Build state ONCE and thread it through buildWinrateCandidates +
  // chooseBestWinrateAction. getStateForPlayer used to run 3x per decision.
  const stateStart = diagOn ? process.hrtime.bigint() : 0n;
  const state = game.getStateForPlayer(botId);
  const stateMs = diagOn ? Number(process.hrtime.bigint() - stateStart) / 1e6 : 0;
  if (state.phase !== 'playing') {
    return decideHeuristicBotAction(game, botId);
  }

  const candStart = diagOn ? process.hrtime.bigint() : 0n;
  const candidates = buildWinrateCandidates(game, botId, state);
  const candMs = diagOn ? Number(process.hrtime.bigint() - candStart) / 1e6 : 0;
  if (candidates.length === 0) {
    return decideHeuristicBotAction(game, botId);
  }
  return chooseBestWinrateAction(game, botId, candidates, state, { stateMs, candMs });
}


// ========== MAIN DECISION FUNCTION ==========

function decideHeuristicBotAction(game, botId) {
  const state = game.getStateForPlayer(botId);
  const phase = state.phase;
  const myCards = state.myCards || [];
  // 카드 카운팅에 쓰는 통로. state 에는 걷힌 트릭이 안 실려 있어서(공개
  // 정보인데도) game 을 그대로 내려보낸다.
  const intel = { game, botId };

  switch (phase) {
    case 'large_tichu_phase':
      if (!state.largeTichuResponded) {
        if (decideLargeTichu(myCards, game)) {
          return { type: 'declare_large_tichu' };
        }
        return { type: 'pass_large_tichu' };
      }
      break;

    case 'card_exchange':
      // Decide small tichu before exchanging (14 cards in hand)
      if (state.canDeclareSmallTichu && decideSmallTichu(myCards, state, game)) {
        return { type: 'declare_small_tichu' };
      }
      if (!state.exchangeDone && myCards.length >= 3) {
        return { type: 'exchange_cards', cards: selectExchangeCards(myCards) };
      }
      break;

    case 'playing':
      // Small tichu: can still declare with 14 cards
      if (state.canDeclareSmallTichu && decideSmallTichu(myCards, state, game)) {
        return { type: 'declare_small_tichu' };
      }

      // Call rank needed
      if (state.needsToCallRank) {
        return { type: 'call_rank', rank: pickCallRank(myCards, state) };
      }

      // Dragon give
      if (game.dragonPending) {
        if (game.dragonDecider === botId) {
          return { type: 'dragon_give', target: decideDragonGive(state) };
        }
        return null;
      }

      if (state.isMyTurn) {
        // Safety: if we have no cards but game thinks it's our turn
        if (myCards.length === 0) {
          // No cards left — pass if possible, otherwise engine will auto-finish
          if (state.currentTrick && state.currentTrick.length > 0) {
            return { type: 'pass' };
          }
          return null;
        }
        return autoPlay(state, myCards, intel);
      }
      break;
  }

  return null;
}

function autoPlay(state, cards, intel) {
  const trick = state.currentTrick || [];
  const callRank = state.callRank;

  if (cards.length === 0) return null;

  const normalCards = cards.filter(c => !c.startsWith('special_'));
  const combos = findCombos(normalCards);

  // Fulfill a call if needed
  if (callRank && trick.length > 0) {
    const calledCards = normalCards.filter(c => {
      const rank = c.split('_')[1];
      return rank === callRank;
    });
    if (calledCards.length > 0) {
      const lastPlay = trick[trick.length - 1];
      const lastValue = lastPlay.comboValue || 0;
      const comboType = lastPlay.combo;
      const lastLength = lastPlay.cards.length;

      // Try to play a combo containing the called card that beats the trick
      const callPlay = findCallFulfillPlay(comboType, lastValue, lastLength, calledCards, cards, normalCards, combos);
      if (callPlay) return { type: 'play_cards', cards: callPlay };
    }
  }

  // Leading a trick - if callRank is active and we have the card, play it
  if (callRank && trick.length === 0) {
    const calledCards = normalCards.filter(c => {
      const rank = c.split('_')[1];
      return rank === callRank;
    });
    if (calledCards.length > 0) {
      return { type: 'play_cards', cards: [calledCards[0]] };
    }
  }

  // Leading a trick
  if (trick.length === 0) {
    return leadTrick(state, cards, normalCards, combos, intel);
  }

  // Following a trick
  const followResult = followTrick(state, cards, normalCards, combos, intel);

  // If call obligation is active, verify our play is valid
  if (callRank && trick.length > 0) {
    const calledCards = normalCards.filter(c => {
      const rank = c.split('_')[1];
      return rank === callRank;
    });
    if (calledCards.length > 0) {
      const lastPlay = trick[trick.length - 1];
      const lastValue = lastPlay.comboValue || 0;
      const comboType = lastPlay.combo;
      const lastLength = lastPlay.cards.length;

      // If the follow result doesn't include a called card, or is a pass,
      // we need to find a play that includes the called card
      const playCards = followResult.cards || [];
      const includesCalledCard = playCards.some(c => {
        const rank = c.split('_')[1];
        return rank === callRank;
      });

      if (followResult.type === 'pass' || (followResult.type === 'play_cards' && !includesCalledCard)) {
        const bruteForcedPlay = bruteForceCallPlay(comboType, lastValue, lastLength, calledCards, cards);
        if (bruteForcedPlay) return { type: 'play_cards', cards: bruteForcedPlay };
      }
    }
  }

  return followResult;
}

/**
 * Brute-force search for a valid play containing a called card.
 * Tries small subsets first for efficiency.
 */
function bruteForceCallPlay(comboType, lastValue, lastLength, calledCards, allCards) {
  // We need to find subsets of the hand that:
  // 1. Include at least one called card
  // 2. Form a valid combo of the right type and length
  // 3. Beat the current trick value

  // Import getComboType-like logic inline for validation
  // Try the simplest approach: only try subsets of the right size
  const hand = [...allCards];
  const targetLen = lastLength;

  // For efficiency, limit to subsets up to size 8
  if (targetLen > 8) return null;

  // Generate subsets of target length that include at least one calledCard
  const calledIndices = [];
  const otherIndices = [];
  for (let i = 0; i < hand.length; i++) {
    if (calledCards.includes(hand[i])) calledIndices.push(i);
    else otherIndices.push(i);
  }

  // For each called card, try combinations with other cards
  for (const ci of calledIndices) {
    if (targetLen === 1) {
      // Single
      if (comboType === 'single' && getCardValue(hand[ci]) > lastValue) {
        return [hand[ci]];
      }
      continue;
    }

    // Generate combinations of (targetLen - 1) from remaining cards
    const remaining = hand.filter((_, i) => i !== ci);
    const combos = getCombinations(remaining, targetLen - 1);
    for (const combo of combos) {
      const subset = [hand[ci], ...combo];
      // Quick validation: check if this could form the right combo type
      const values = subset.filter(c => !c.startsWith('special_')).map(c => getCardValue(c));
      const hasPhoenix = subset.includes('special_phoenix');

      if (comboType === 'pair' && targetLen === 2) {
        if (hasPhoenix) {
          const other = subset.find(c => c !== 'special_phoenix');
          if (other && getCardValue(other) > lastValue && !other.startsWith('special_')) return subset;
        } else if (values.length === 2 && values[0] === values[1] && values[0] > lastValue) {
          return subset;
        }
      }

      if (comboType === 'triple' && targetLen === 3) {
        if (hasPhoenix) {
          const normals = subset.filter(c => c !== 'special_phoenix');
          const nVals = normals.map(c => getCardValue(c));
          if (nVals.length === 2 && nVals[0] === nVals[1] && nVals[0] > lastValue) return subset;
        } else if (values.length === 3 && values[0] === values[1] && values[1] === values[2] && values[0] > lastValue) {
          return subset;
        }
      }

      if (comboType === 'straight' && targetLen >= 5) {
        const sorted = [...new Set(values)].sort((a, b) => a - b);
        if (hasPhoenix) {
          // Check for at most 1 gap
          if (sorted.length + 1 >= targetLen) {
            let gaps = 0;
            for (let i = 1; i < sorted.length; i++) {
              const diff = sorted[i] - sorted[i-1];
              if (diff === 2) gaps++;
              else if (diff > 2) { gaps = 99; break; }
            }
            if ((gaps === 0 && sorted.length + 1 === targetLen) || (gaps === 1 && sorted.length + 1 === targetLen)) {
              const highVal = Math.max(sorted[sorted.length - 1], gaps === 0 ? sorted[sorted.length - 1] + 1 : sorted[sorted.length - 1]);
              if (highVal > lastValue) return subset;
            }
          }
        } else if (sorted.length === targetLen) {
          let isConsec = true;
          for (let i = 1; i < sorted.length; i++) {
            if (sorted[i] !== sorted[i-1] + 1) { isConsec = false; break; }
          }
          if (isConsec && sorted[sorted.length - 1] > lastValue) return subset;
        }
      }

      if (comboType === 'full_house' && targetLen === 5) {
        const counts = {};
        for (const c of subset) {
          if (c === 'special_phoenix') continue;
          const v = getCardValue(c);
          counts[v] = (counts[v] || 0) + 1;
        }
        const entries = Object.entries(counts);
        if (hasPhoenix) {
          if (entries.length === 2) {
            const [c1, c2] = entries.map(([, cnt]) => cnt);
            const [v1, v2] = entries.map(([v]) => Number(v));
            if ((c1 === 3 && c2 === 1) || (c1 === 1 && c2 === 3)) {
              const tripleVal = c1 === 3 ? v1 : v2;
              if (tripleVal > lastValue) return subset;
            }
            if (c1 === 2 && c2 === 2) {
              const tripleVal = Math.max(v1, v2);
              if (tripleVal > lastValue) return subset;
            }
          }
        } else {
          if (entries.length === 2) {
            const [c1, c2] = entries.map(([, cnt]) => cnt);
            const [v1, v2] = entries.map(([v]) => Number(v));
            if ((c1 === 3 && c2 === 2) || (c1 === 2 && c2 === 3)) {
              const tripleVal = c1 === 3 ? v1 : v2;
              if (tripleVal > lastValue) return subset;
            }
          }
        }
      }

      if (comboType === 'steps' && targetLen >= 4 && targetLen % 2 === 0) {
        const counts = {};
        for (const c of subset) {
          if (c === 'special_phoenix') continue;
          const v = getCardValue(c);
          counts[v] = (counts[v] || 0) + 1;
        }
        const entries = Object.entries(counts).map(([v, c]) => ({ v: Number(v), c })).sort((a, b) => a.v - b.v);
        const numPairs = targetLen / 2;
        if (hasPhoenix) {
          let valid = true;
          let phoenixUsed = false;
          for (const e of entries) {
            if (e.c === 2) continue;
            if (e.c === 1 && !phoenixUsed) { phoenixUsed = true; continue; }
            valid = false; break;
          }
          if (valid && entries.length === numPairs) {
            let consec = true;
            for (let i = 1; i < entries.length; i++) {
              if (entries[i].v !== entries[i-1].v + 1) { consec = false; break; }
            }
            if (consec && entries[entries.length - 1].v > lastValue) return subset;
          }
        } else {
          if (entries.length === numPairs && entries.every(e => e.c === 2)) {
            let consec = true;
            for (let i = 1; i < entries.length; i++) {
              if (entries[i].v !== entries[i-1].v + 1) { consec = false; break; }
            }
            if (consec && entries[entries.length - 1].v > lastValue) return subset;
          }
        }
      }
    }
  }

  // Also try bombs (4-of-a-kind) containing the called card
  for (const ci of calledIndices) {
    const val = getCardValue(hand[ci]);
    const sameVal = hand.filter(c => getCardValue(c) === val && !c.startsWith('special_'));
    if (sameVal.length === 4) return sameVal;
  }

  return null;
}

/** Generate combinations of size k from array */
function getCombinations(arr, k) {
  if (k === 0) return [[]];
  if (arr.length < k) return [];
  if (k === arr.length) return [arr];

  const results = [];
  // Limit to prevent combinatorial explosion
  if (arr.length > 14 || k > 6) return [];

  function helper(start, current) {
    if (current.length === k) {
      results.push([...current]);
      return;
    }
    // Limit total results
    if (results.length > 1000) return;
    for (let i = start; i < arr.length; i++) {
      current.push(arr[i]);
      helper(i + 1, current);
      current.pop();
    }
  }
  helper(0, []);
  return results;
}

/**
 * Find a valid combo containing a called-rank card that beats the current trick.
 * Tries the simplest matching combos first.
 */
function findCallFulfillPlay(comboType, lastValue, lastLength, calledCards, allCards, normalCards, combos) {
  // Single
  if (comboType === 'single') {
    for (const c of calledCards) {
      if (getCardValue(c) > lastValue) return [c];
    }
  }

  // Pair: find a pair containing the called card
  if (comboType === 'pair') {
    for (const pair of combos.pairs) {
      if (pair.some(c => calledCards.includes(c)) && getCardValue(pair[0]) > lastValue) {
        return pair;
      }
    }
    // Try phoenix pair
    if (allCards.includes('special_phoenix')) {
      for (const c of calledCards) {
        if (getCardValue(c) > lastValue) {
          return [c, 'special_phoenix'];
        }
      }
    }
  }

  // Triple
  if (comboType === 'triple') {
    for (const triple of combos.triples) {
      if (triple.some(c => calledCards.includes(c)) && getCardValue(triple[0]) > lastValue) {
        return triple;
      }
    }
  }

  // Straight
  if (comboType === 'straight') {
    for (const straight of combos.straights) {
      if (straight.length === lastLength && straight.some(c => calledCards.includes(c))) {
        if (getHighestValue(straight) > lastValue) return straight;
      }
    }
  }

  // Full house
  if (comboType === 'full_house') {
    for (const fh of combos.fullHouses) {
      if (fh.some(c => calledCards.includes(c)) && getFullHouseTripleValue(fh) > lastValue) {
        return fh;
      }
    }
  }

  // Steps
  if (comboType === 'steps') {
    for (const step of combos.steps) {
      if (step.length === lastLength && step.some(c => calledCards.includes(c))) {
        if (getHighestValue(step) > lastValue) return step;
      }
    }
  }

  // Bombs can beat any combo type
  for (const bomb of combos.bombs) {
    if (bomb.some(c => calledCards.includes(c))) {
      return bomb;
    }
  }

  // Phoenix combos: check if phoenix + called card can form a valid beating combo
  const phoenixCombos = findCombosWithPhoenix(allCards);
  if (comboType === 'pair') {
    for (const pair of phoenixCombos.pairs) {
      if (pair.some(c => calledCards.includes(c))) {
        const pairVal = getCardValue(pair.find(c => c !== 'special_phoenix'));
        if (pairVal > lastValue) return pair;
      }
    }
  }
  if (comboType === 'triple') {
    for (const triple of phoenixCombos.triples) {
      if (triple.some(c => calledCards.includes(c))) {
        const tripleVal = getCardValue(triple.find(c => c !== 'special_phoenix'));
        if (tripleVal > lastValue) return triple;
      }
    }
  }
  if (comboType === 'straight') {
    for (const straight of phoenixCombos.straights) {
      if (straight.length === lastLength && straight.some(c => calledCards.includes(c))) {
        const highVal = getHighestValue(straight.filter(c => c !== 'special_phoenix'));
        if (highVal > lastValue) return straight;
      }
    }
  }
  if (comboType === 'full_house') {
    for (const fh of phoenixCombos.fullHouses) {
      if (fh.some(c => calledCards.includes(c))) {
        const fhVal = getFullHouseTripleValue(fh);
        if (fhVal > lastValue) return fh;
      }
    }
  }
  if (comboType === 'steps') {
    for (const step of phoenixCombos.steps) {
      if (step.length === lastLength && step.some(c => calledCards.includes(c))) {
        const highVal = getHighestValue(step.filter(c => c !== 'special_phoenix'));
        if (highVal > lastValue) return step;
      }
    }
  }

  return null;
}

function decideBotAction(game, botId, strategy = 'heuristic') {
  const normalized = normalizeTichuStrategy(strategy);
  if (normalized === 'winrate') {
    return decideWinrateBotAction(game, botId);
  }
  return decideHeuristicBotAction(game, botId);
}


module.exports = {
  BotPlayer,
  decideBotAction,
  VALID_BOT_STRATEGIES,
  // Exported so the exchange can be exercised on its own: it is a pure
  // hand -> three cards function, and the alternative is standing up a
  // whole game to see which card the partner gets.
  selectExchangeCards,
};
