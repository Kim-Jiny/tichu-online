/**
 * Server-integrated Bot Player
 * Strategic AI for Tichu card game.
 */

class BotPlayer {
  constructor(id, nickname) {
    this.id = id;           // 'bot_1', 'bot_2', ...
    this.nickname = nickname; // '봇 1', '봇 2', ...
    this.isBot = true;
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

// ========== HAND EVALUATION SYSTEM ==========

/**
 * Greedily decompose hand into planned plays.
 * Priority: bombs → straights → steps → full houses → triples → pairs → singles
 * Returns array of card arrays representing planned plays.
 */
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

function decideLargeTichu(cards) {
  // Bots never declare large tichu
  return false;
}

function decideSmallTichu(cards, state) {
  // Bots never declare small tichu
  return false;
}


// ========== EXCHANGE STRATEGY ==========

function selectExchangeCards(cards) {
  const normalCards = cards.filter(c => !c.startsWith('special_'));
  const eval_ = evaluateHand(cards);
  const plans = decomposeHand(cards);

  // Find singles from the decomposed plan
  const singlePlans = plans.filter(p => p.length === 1).map(p => p[0]);

  // Cards NOT used in multi-card combos (safe to give away)
  const comboCards = new Set();
  for (const plan of plans) {
    if (plan.length > 1) {
      for (const c of plan) comboCards.add(c);
    }
  }

  const freeCards = normalCards.filter(c => !comboCards.has(c));

  // Sort free cards by value
  const freeByValue = [...freeCards].sort((a, b) => getCardValue(a) - getCardValue(b));
  const freeByValueDesc = [...freeCards].sort((a, b) => getCardValue(b) - getCardValue(a));

  // Low cards with no points (for giving to opponents)
  const lowNoPoints = freeByValue.filter(c => {
    const rank = getRankFromCard(c);
    return rank !== '5' && rank !== '10' && rank !== 'K';
  });

  // All cards sorted for fallback
  const allByValue = [...normalCards].sort((a, b) => getCardValue(a) - getCardValue(b));
  const allByValueDesc = [...normalCards].sort((a, b) => getCardValue(b) - getCardValue(a));

  const used = new Set();

  function pickCard(candidates, fallback) {
    for (const c of candidates) {
      if (!used.has(c)) { used.add(c); return c; }
    }
    for (const c of fallback) {
      if (!used.has(c)) { used.add(c); return c; }
    }
    // Ultimate fallback
    for (const c of cards) {
      if (!used.has(c)) { used.add(c); return c; }
    }
    return cards[0];
  }

  // PARTNER: Dragon > Phoenix > top card (by value desc)
  const partnerCandidates = [];
  if (cards.includes('special_dragon')) partnerCandidates.push('special_dragon');
  if (cards.includes('special_phoenix')) partnerCandidates.push('special_phoenix');
  partnerCandidates.push(...allByValueDesc);

  const partner = pickCard(partnerCandidates, allByValueDesc);

  // OPPONENTS: Low cards without points
  const oppCandidates = [...lowNoPoints];
  // Fallback: any low cards
  oppCandidates.push(...allByValue.filter(c => {
    const rank = getRankFromCard(c);
    return rank !== '5' && rank !== '10' && rank !== 'K' && c !== 'special_dragon' && c !== 'special_phoenix';
  }));
  oppCandidates.push(...allByValue.filter(c => c !== 'special_dragon' && c !== 'special_phoenix'));

  const left = pickCard(oppCandidates, allByValue);
  const right = pickCard(oppCandidates, allByValue);

  return { left, partner, right };
}


// ========== CALL RANK (WISH) STRATEGY ==========

/** Pick a rank the bot doesn't have, preferring high ranks to hurt opponents */
function pickCallRank(cards) {
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

function leadTrick(state, cards, normalCards, combos) {
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
      const callRank = pickCallRank(cards.filter(c => !birdStraight.includes(c)));
      return { type: 'play_cards', cards: birdStraight, callRank };
    }
    // Play bird as single
    const callRank = pickCallRank(cards);
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
    const lowSingles = normalCards
      .filter(c => getCardValue(c) <= 8)
      .sort((a, b) => getCardValue(a) - getCardValue(b));
    if (lowSingles.length > 0) {
      return { type: 'play_cards', cards: [lowSingles[0]] };
    }
    // No low singles, play the lowest card we have
    if (normalCards.length > 0) {
      const sorted = [...normalCards].sort((a, b) => getCardValue(a) - getCardValue(b));
      return { type: 'play_cards', cards: [sorted[0]] };
    }
  }

  // 4. If bomb is our only remaining cards, play it to finish
  for (const bomb of combos.bombs) {
    if (bomb.length === cards.length) {
      return { type: 'play_cards', cards: bomb };
    }
  }

  // 5. Plan-based play: follow decomposed hand plan
  // Play lowest multi-card combo first, then singles
  // Filter out bombs from lead plays - bombs should be saved for defensive use
  const bombSet = new Set(combos.bombs.flat());
  const multiCardPlans = plans.filter(p =>
    p.length >= 2 && !p.includes('special_dog') && !p.includes('special_bird') &&
    !(p.length === 4 && p.every(c => bombSet.has(c)))
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
    // Skip high-value combos (A=14, K=13): save them for later
    // Only play A/K combos when we have few cards left
    const safePlans = multiCardPlans.filter(p => {
      const hv = getHighestValue(p);
      if (hv >= 14) return cards.length <= 2; // A combo: only as the final play
      if (hv >= 13) return cards.length <= 6; // K combo: only in late game
      return true;
    });
    if (safePlans.length > 0) {
      return { type: 'play_cards', cards: safePlans[0] };
    }
    // No safe combo available. Prefer leading a LOW single (≤10) over burning
    // a high combo (e.g. AA pair with [3,4,A,A]). Low singles will lose
    // anyway, but the A's stay in hand as guaranteed late-game trick winners.
    // We only reroute for LOW singles though — burning a lone A/K single to
    // save a combo would be strictly worse.
    const lowSinglePlans = singlePlans.filter(p => getCardValue(p[0]) <= 10);
    if (lowSinglePlans.length > 0) {
      return { type: 'play_cards', cards: [lowSinglePlans[0][0]] };
    }
    // No low singles: play the high combo (better than burning K/A singles).
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

  // 8. Fallback
  if (normalCards.length > 0) {
    const sorted = [...normalCards].sort((a, b) => getCardValue(a) - getCardValue(b));
    return { type: 'play_cards', cards: [sorted[0]] };
  }

  const playable = cards.filter(c => c !== 'special_dog');
  if (playable.length > 0) {
    return { type: 'play_cards', cards: [playable[0]] };
  }

  return { type: 'play_cards', cards: [cards[0]] };
}


// ========== FOLLOW TRICK STRATEGY ==========

function followTrick(state, cards, normalCards, combos) {
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

  const partnerTichu = partner && !partner.hasFinished && (partner.hasSmallTichu || partner.hasLargeTichu);

  // === PARTNER PLAYED: usually pass, unless we can finish ===
  if (partnerPlayed) {
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
    const finishPlay = findFinishingPlay(comboType, lastValue, lastLength, cards, normalCards, combos);
    if (finishPlay) return { type: 'play_cards', cards: finishPlay };

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
    return handleFollowSingle(state, cards, normalCards, combos, lastValue, trickPts, minOppCards);
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

function handleFollowSingle(state, cards, normalCards, combos, lastValue, trickPts, minOppCards) {
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

  // Play lowest beating normal card
  if (beaters.length > 0) {
    // If opponent has few cards, play more aggressively (use stronger card)
    if (minOppCards <= 3 && beaters.length > 1) {
      // Play a strong beater to ensure we win
      return { type: 'play_cards', cards: [beaters[beaters.length - 1]] };
    }
    return { type: 'play_cards', cards: [beaters[0]] };
  }

  // Phoenix as single: conservative usage
  if (cards.includes('special_phoenix') && lastValue < 14.5) {
    const shouldUsePhoenix = (
      cards.length <= 3 ||  // few cards left
      (trickPts >= 15) ||  // valuable trick
      (minOppCards <= 2)    // opponent almost out
    );
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

  // Regular pairs (sorted lowest first by findCombos)
  for (const pair of combos.pairs) {
    const pairVal = getCardValue(pair[0]);
    if (pairVal > lastValue) {
      // Can finish?
      if (pair.length === cards.length) return { type: 'play_cards', cards: pair };
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

  for (const triple of combos.triples) {
    const tripleVal = getCardValue(triple[0]);
    if (tripleVal > lastValue) {
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

  for (const straight of combos.straights) {
    if (straight.length === lastLength) {
      const highVal = getHighestValue(straight);
      if (highVal > lastValue) {
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

  for (const fh of combos.fullHouses) {
    const fhTripleVal = getFullHouseTripleValue(fh);
    if (fhTripleVal > lastValue) {
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

  for (const step of combos.steps) {
    if (step.length === lastLength) {
      const highVal = getHighestValue(step);
      if (highVal > lastValue) {
        return { type: 'play_cards', cards: step };
      }
    }
  }

  // Phoenix steps
  for (const step of phoenixCombos.steps) {
    if (step.length === lastLength) {
      const highVal = getHighestValue(step.filter(c => c !== 'special_phoenix'));
      if (highVal > lastValue) {
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


// ========== MAIN DECISION FUNCTION ==========

function decideBotAction(game, botId) {
  const state = game.getStateForPlayer(botId);
  const phase = state.phase;
  const myCards = state.myCards || [];

  switch (phase) {
    case 'large_tichu_phase':
      if (!state.largeTichuResponded) {
        if (decideLargeTichu(myCards)) {
          return { type: 'declare_large_tichu' };
        }
        return { type: 'pass_large_tichu' };
      }
      break;

    case 'card_exchange':
      // Decide small tichu before exchanging (14 cards in hand)
      if (state.canDeclareSmallTichu && decideSmallTichu(myCards, state)) {
        return { type: 'declare_small_tichu' };
      }
      if (!state.exchangeDone && myCards.length >= 3) {
        return { type: 'exchange_cards', cards: selectExchangeCards(myCards) };
      }
      break;

    case 'playing':
      // Small tichu: can still declare with 14 cards
      if (state.canDeclareSmallTichu && decideSmallTichu(myCards, state)) {
        return { type: 'declare_small_tichu' };
      }

      // Call rank needed
      if (state.needsToCallRank) {
        return { type: 'call_rank', rank: pickCallRank(myCards) };
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
        return autoPlay(state, myCards);
      }
      break;
  }

  return null;
}

function autoPlay(state, cards) {
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
    return leadTrick(state, cards, normalCards, combos);
  }

  // Following a trick
  const followResult = followTrick(state, cards, normalCards, combos);

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


module.exports = { BotPlayer, decideBotAction };
