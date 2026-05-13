'use strict';

const { getCardInfo, RANK_ORDER, SUITS } = require('./MightyDeck');

/**
 * Decide the next action for a Mighty bot. Single user-facing strategy:
 * mixoracle (hard rules layered on top of the oracle perfect-info evaluator).
 * The internal 'heuristic' branch is still reachable so mixoracle's hard
 * rules can ask "what would the pure heuristic do here?" without recursing
 * back into mixoracle.
 */
function decideMightyBotAction(game, botId, strategy = 'mixoracle') {
  if (!game || !game.playerIds.includes(botId)) return null;
  if (strategy === 'heuristic') return _heuristicDecide(game, botId);
  return require('./strategies/mixoracle').decide(game, botId);
}

function _heuristicDecide(game, botId) {
  if (game.state === 'bidding' && game.currentPlayer === botId) {
    return decideBid(game, botId);
  }

  if (game.state === 'kill_select' && game.declarer === botId) {
    return decideKillTarget(game, botId);
  }

  if (game.state === 'kitty_exchange' && game.declarer === botId) {
    const trumpChange = considerTrumpChange(game, botId);
    if (trumpChange) return trumpChange;
    return decideKittyDiscard(game, botId);
  }

  if (game.state === 'playing' && game.currentPlayer === botId) {
    return decidePlay(game, botId);
  }

  if (game.state === 'round_end') {
    return { type: 'next_round' };
  }

  return null;
}

// ═══════════════════════════════════════════════════════════
//  CARD COUNTING INFRASTRUCTURE
//  Human-like tracking of played cards, voids, and game state
// ═══════════════════════════════════════════════════════════

/** Get all cards played in previous tricks and current trick */
function _getPlayedCards(game) {
  const played = new Set();
  for (const trick of (game.tricks || [])) {
    for (const play of (trick.cards || [])) {
      played.add(play.cardId);
    }
  }
  for (const play of (game.currentTrick || [])) {
    played.add(play.cardId);
  }
  return played;
}

/** Track which suits each player has shown void in (from trick history) */
function _getKnownVoids(game) {
  const voids = {};
  for (const pid of game.playerIds) voids[pid] = new Set();
  const mightyCard = game.getMightyCard();

  const analyzeTrick = (trick) => {
    const cards = trick?.cards || [];
    if (cards.length < 2) return;
    const leadCard = cards[0].cardId;
    const leadSuit = trick?.leadSuit
      || (leadCard === 'mighty_joker' ? game.jokerSuitDeclared : getCardInfo(leadCard).suit);
    if (!leadSuit) return;

    for (let i = 1; i < cards.length; i++) {
      const play = cards[i];
      if (play.cardId === 'mighty_joker' || play.cardId === mightyCard) continue;
      if (getCardInfo(play.cardId).suit !== leadSuit) {
        voids[play.pid].add(leadSuit);
      }
    }
  };

  for (const trick of game.tricks) analyzeTrick(trick);
  if (game.currentTrick.length > 1) {
    const leadCardId = game.currentTrick[0]?.cardId;
    analyzeTrick({
      cards: game.currentTrick,
      leadSuit: leadCardId === 'mighty_joker'
        ? game.jokerSuitDeclared
        : (leadCardId ? getCardInfo(leadCardId).suit : null),
    });
  }

  return voids;
}

/** Count cards of `suit` not in own hand, not played, not discarded —
 *  i.e., still live in someone else's hand. */
function _countCardsInSuitOutsideHand(game, botId, suit) {
  if (!suit || suit === 'no_trump') return 0;
  const played = _getPlayedCards(game);
  const myHand = new Set(game.hands[botId] || []);
  const discarded = new Set(game.discarded || []);
  let count = 0;
  for (const rank of ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A']) {
    const cardId = `mighty_${suit}_${rank}`;
    if (!played.has(cardId) && !myHand.has(cardId) && !discarded.has(cardId)) count++;
  }
  return count;
}

/** Count trump threats held by the actual opposing team. */
function _countOpponentTrumps(game, botId) {
  if (!game.trumpSuit || game.trumpSuit === 'no_trump') return 0;
  let count = 0;
  const botIsGov = isGovernmentSelf(game, botId);

  for (const pid of game.playerIds) {
    if (pid === botId) continue;
    if (game.excludedPlayers && game.excludedPlayers.has(pid)) continue;
    if (isGovernmentSelf(game, pid) === botIsGov) continue;

    for (const cardId of (game.hands[pid] || [])) {
      if (cardId === 'mighty_joker') {
        count++;
        continue;
      }
      const info = getCardInfo(cardId);
      if (info && info.suit === game.trumpSuit) count++;
    }
  }
  return count;
}

/** Get government's total collected point cards so far */
function _getGovernmentPointCount(game) {
  let points = 0;
  const govIds = new Set([game.declarer]);
  if (game.partner) govIds.add(game.partner);
  for (const pid of govIds) {
    points += (game.pointCards[pid] || []).length;
  }
  return points;
}

/**
 * True if the opposition is in a "critical endgame": 2 or fewer tricks
 * remain (the current one included) AND the declarer team has not yet
 * accumulated enough point cards to make their bid. At that point opp
 * should stop conserving mighty/joker/trump and play to deny the last
 * handful of points — letting declarer grab a 1-point trick can be the
 * difference between a failed and made bid.
 */
function _oppCriticalEndgame(game) {
  const active = game.activePlayerCount || game.playerCount;
  if (!active) return false;
  const totalTricks = Math.floor(50 / active);
  const tricksRemaining = totalTricks - game.tricks.length;
  if (tricksRemaining > 2) return false;
  const bidTarget = game.currentBid?.points || 0;
  if (!bidTarget) return false;
  const govPoints = _getGovernmentPointCount(game);
  return govPoints < bidTarget;
}

/** Count how many point cards remain in all hands (not yet played/discarded) */
function _countRemainingPointCards(game) {
  const played = _getPlayedCards(game);
  const discarded = new Set(game.discarded || []);
  let count = 0;
  for (const suit of SUITS) {
    for (const rank of ['A', 'K', 'Q', 'J', '10']) {
      const cardId = `mighty_${suit}_${rank}`;
      if (!played.has(cardId) && !discarded.has(cardId)) count++;
    }
  }
  return count;
}

/** Check if a specific card is still unplayed (could be in someone's hand) */
function _isCardStillInPlay(game, cardId) {
  const played = _getPlayedCards(game);
  const discarded = new Set(game.discarded || []);
  return !played.has(cardId) && !discarded.has(cardId);
}

// ═══════════════════════════════════════════════════════════
//  BIDDING
// ═══════════════════════════════════════════════════════════

function decideBid(game, botId) {
  const hand = game.hands[botId];

  // Bots never declare deal miss. It costs 5 points now for a speculative pool
  // reward later, and in practice the bot was burning points on marginal hands.
  // Sim data: dealmiss was hit ~19-25 % of eligible rounds — pass instead.

  const strength = evaluateHandStrength(hand, game);
  const bestTrump = pickBestTrump(hand);

  // Count cards of the chosen trump suit + flag non-trump A presence.
  // "non-trump A" = any A whose suit ≠ bestTrump (includes mighty in
  // non-spade-trump bidding). It guarantees a credible first-trick
  // lead (1st trick disallows trump leads), so without one the bot
  // can't safely commit to a high bid.
  let trumpCount = 0;
  let hasNonTrumpA = false;
  for (const cardId of hand) {
    if (cardId === 'mighty_joker') continue;
    const info = getCardInfo(cardId);
    if (info.suit === bestTrump) {
      trumpCount++;
    } else if (info.rank === 'A') {
      hasNonTrumpA = true;
    }
  }

  // 6p hands are 8 cards (vs 5p's 10), so trump-count thresholds shift
  // down by one. 6p minBid is also 14 (vs 13).
  const is6p = game.playerCount === 6;
  const passThreshold = is6p ? 3 : 4;       // < this → pass
  const cap1Trump = passThreshold;          // +1 over minBid
  const cap2Trump = passThreshold + 1;      // +2 over minBid
  const boostTrump = passThreshold + 3;     // long trump bonus

  // Suited bid gate: refuse to bid when trump support is too thin —
  // opp drains us before we cash anything.
  if (trumpCount < passThreshold) {
    return { type: 'submit_bid', pass: true };
  }

  let estimatedPoints = Math.min(20, game.options.minBid + Math.floor(strength / 2.5));

  // Trump length cap.
  if (trumpCount === cap1Trump) {
    estimatedPoints = Math.min(estimatedPoints, game.options.minBid + 1);
  } else if (trumpCount === cap2Trump) {
    estimatedPoints = Math.min(estimatedPoints, game.options.minBid + 2);
  } else if (trumpCount >= boostTrump) {
    estimatedPoints = Math.min(20, estimatedPoints + 1);
  }

  // 15+ bid requires a non-trump A — a credible first-trick lead.
  // Without one, cap at 14 even if strength + trump count would
  // otherwise allow more.
  if (!hasNonTrumpA && estimatedPoints >= 15) {
    estimatedPoints = 14;
  }

  if (estimatedPoints < game.options.minBid || estimatedPoints <= game.currentBid.points) {
    return { type: 'submit_bid', pass: true };
  }

  let suit = bestTrump;

  // No-trump: only fire when the hand can credibly take every lead.
  //   - MUST hold both mighty (♠A in NT) AND joker — those are the two
  //     unconditional winners.
  //   - There must be exactly one "missing-A" non-spade suit where we
  //     hold K AND Q. Calling that A as friend → friend drops it on our
  //     lead, then our K and Q are the top of that suit.
  //   - In every OTHER non-spade suit we already hold A — those become
  //     trick winners on lead.
  // Together: mighty + joker + 3 side-suit A's + K+Q in the friend suit
  // covers every lead-winning slot in NT.
  if (game.options.allowNoTrump) {
    const handSet = new Set(hand);
    const hasJoker = handSet.has('mighty_joker');
    const hasMighty = handSet.has('mighty_spade_A');

    let missingASuit = null;
    for (const s of ['heart', 'diamond', 'club']) {
      const hasA = handSet.has(`mighty_${s}_A`);
      const hasK = handSet.has(`mighty_${s}_K`);
      const hasQ = handSet.has(`mighty_${s}_Q`);
      if (!hasA && hasK && hasQ) {
        missingASuit = s;
        break;
      }
    }

    let allOtherAs = false;
    if (missingASuit) {
      allOtherAs = ['heart', 'diamond', 'club']
        .filter(s => s !== missingASuit)
        .every(s => handSet.has(`mighty_${s}_A`));
    }

    if (hasMighty && hasJoker && missingASuit && allOtherAs) {
      suit = 'no_trump';
    }
  }

  return { type: 'submit_bid', points: estimatedPoints, suit };
}

function evaluateHandStrength(hand, game) {
  let strength = 0;
  const mightyCard = game.trumpSuit === 'spade' ? 'mighty_diamond_A' : 'mighty_spade_A';

  for (const cardId of hand) {
    if (cardId === 'mighty_joker') { strength += 2.5; continue; }
    if (cardId === mightyCard) { strength += 2.5; continue; }
    const info = getCardInfo(cardId);
    if (info.rank === 'A') strength += 1.5;
    else if (info.rank === 'K') strength += 1;
    else if (info.rank === 'Q') strength += 0.5;
  }

  const suitCounts = {};
  for (const cardId of hand) {
    if (cardId === 'mighty_joker') continue;
    const info = getCardInfo(cardId);
    suitCounts[info.suit] = (suitCounts[info.suit] || 0) + 1;
  }

  const maxSuitLen = Math.max(...Object.values(suitCounts), 0);
  if (maxSuitLen >= 7) strength += 3;
  else if (maxSuitLen >= 6) strength += 2;
  else if (maxSuitLen >= 5) strength += 1;

  const voidCount = SUITS.filter(s => !suitCounts[s] || suitCounts[s] === 0).length;
  strength += voidCount * 0.5;

  return strength;
}

function pickBestTrump(hand) {
  const stats = {};
  for (const suit of SUITS) {
    stats[suit] = { count: 0, rankSum: 0, hasA: false, hasK: false, hasQ: false };
  }
  for (const cardId of hand) {
    if (cardId === 'mighty_joker') continue;
    const info = getCardInfo(cardId);
    const s = stats[info.suit];
    s.count++;
    s.rankSum += RANK_ORDER[info.rank] || 0;
    if (info.rank === 'A') s.hasA = true;
    else if (info.rank === 'K') s.hasK = true;
    else if (info.rank === 'Q') s.hasQ = true;
  }

  let bestSuit = 'spade';
  let bestScore = -Infinity;
  for (const suit of SUITS) {
    const s = stats[suit];
    // Favour length heavily (each trump card is worth ~12 points of score).
    // Top honours add extra certainty; very short trump gets penalised because
    // opp can draw us out quickly.
    let score = s.count * 12 + s.rankSum;
    if (s.hasA) score += 6;
    if (s.hasK) score += 3;
    if (s.hasQ) score += 1;
    if (s.count <= 3) score -= (4 - s.count) * 10;
    if (score > bestScore) { bestScore = score; bestSuit = suit; }
  }
  return bestSuit;
}

// ═══════════════════════════════════════════════════════════
//  TRUMP CHANGE CONSIDERATION
// ═══════════════════════════════════════════════════════════

function considerTrumpChange(game, botId) {
  if (!game.options.allowTrumpChange) return null;
  // Don't change away from no-trump (NT is a deliberate strategic choice)
  if (game.trumpSuit === 'no_trump') return null;
  const hand = game.hands[botId];
  const currentTrump = game.trumpSuit;

  const suitScore = {};
  for (const suit of SUITS) {
    let count = 0, strength = 0;
    for (const cardId of hand) {
      if (cardId === 'mighty_joker') continue;
      const info = getCardInfo(cardId);
      if (info.suit === suit) {
        count++;
        strength += RANK_ORDER[info.rank] || 0;
        if (info.rank === 'A') strength += 5;
        if (info.rank === 'K') strength += 3;
      }
    }
    suitScore[suit] = count * 10 + strength;
  }

  let bestSuit = currentTrump;
  let bestScore = -1;
  for (const suit of SUITS) {
    if (suitScore[suit] > bestScore) {
      bestScore = suitScore[suit];
      bestSuit = suit;
    }
  }

  const currentScore = currentTrump && currentTrump !== 'no_trump'
    ? (suitScore[currentTrump] || 0) : 0;

  // At the 20-point ceiling: 20 NT blocks all change (handled by early
  // return above since trumpSuit === 'no_trump'); 20 with a suit only permits
  // a change to NT, which this bot does not evaluate, so skip.
  if (game.currentBid.points >= 20) {
    return null;
  }

  const penalty = game.options.trumpChangePenalty || 2;
  if (bestSuit !== currentTrump && bestScore > currentScore + 20) {
    if (game.currentBid.points + penalty <= 20) {
      return { type: 'change_trump', suit: bestSuit };
    }
  }

  return null;
}

// ═══════════════════════════════════════════════════════════
//  KILL TARGET SELECTION (6p kill-mighty)
// ═══════════════════════════════════════════════════════════

/**
 * Pick a card to "kill" when 6p kill-mighty requires the declarer to choose.
 * Priority — pick the strongest card NOT in our own hand:
 *   1. Joker
 *   2. Trump A (if trump is a suit)
 *   3. Trump K (if trump is a suit)
 *   4. Mighty (spade A, or diamond A when trump is spade)
 *   5. A of our longest non-trump suit (fallback: K of that suit)
 *   6. Trump Q
 *   7. Trump J
 *   8. Remaining Aces then Kings in SUITS order
 * Cards already in the bot's hand are skipped at every step.
 */
function decideKillTarget(game, botId) {
  const hand = new Set(game.hands[botId] || []);
  const trump = game.trumpSuit;
  const mightyCard = game.getMightyCard();
  const pick = (cardId) => (hand.has(cardId) ? null : cardId);

  // 1. Joker
  let choice = pick('mighty_joker');
  if (choice) return { type: 'declare_kill', cardId: choice };

  // 2-3, 6-7. Trump honours (A, K, Q, J) when trump is a real suit
  if (trump && trump !== 'no_trump') {
    choice = pick(`mighty_${trump}_A`); if (choice) return { type: 'declare_kill', cardId: choice };
    choice = pick(`mighty_${trump}_K`); if (choice) return { type: 'declare_kill', cardId: choice };
  }

  // 4. Mighty (falls in between trump K and longest-side A)
  choice = pick(mightyCard);
  if (choice) return { type: 'declare_kill', cardId: choice };

  // 5. A then K of the longest non-trump side suit
  const sideSuits = SUITS
    .filter(s => s !== trump || trump === 'no_trump')
    .map(s => {
      let count = 0;
      for (const cid of hand) {
        if (cid === 'mighty_joker') continue;
        const info = getCardInfo(cid);
        if (info.suit === s) count++;
      }
      return { suit: s, count };
    })
    .sort((a, b) => b.count - a.count);
  for (const { suit } of sideSuits) {
    const ace = `mighty_${suit}_A`;
    if (!hand.has(ace) && ace !== mightyCard) return { type: 'declare_kill', cardId: ace };
  }
  for (const { suit } of sideSuits) {
    const king = `mighty_${suit}_K`;
    if (!hand.has(king)) return { type: 'declare_kill', cardId: king };
  }

  if (trump && trump !== 'no_trump') {
    choice = pick(`mighty_${trump}_Q`); if (choice) return { type: 'declare_kill', cardId: choice };
    choice = pick(`mighty_${trump}_J`); if (choice) return { type: 'declare_kill', cardId: choice };
  }

  // Generic A-then-K sweep across all suits
  for (const rank of ['A', 'K', 'Q', 'J', '10', '9', '8', '7', '6', '5', '4', '3', '2']) {
    for (const suit of SUITS) {
      const cid = `mighty_${suit}_${rank}`;
      if (!hand.has(cid)) return { type: 'declare_kill', cardId: cid };
    }
  }

  // Should be unreachable — we're missing every card? fall back to joker
  return { type: 'declare_kill', cardId: 'mighty_joker' };
}

// ═══════════════════════════════════════════════════════════
//  KITTY DISCARD & FRIEND SELECTION
// ═══════════════════════════════════════════════════════════

function decideKittyDiscard(game, botId) {
  const hand = game.hands[botId];
  const trumpSuit = game.trumpSuit;
  const mightyCard = game.getMightyCard();
  const protectedCards = new Set([mightyCard, 'mighty_joker']);

  const suitGroups = groupMightyCardsBySuit(hand, protectedCards);

  // Pick friend card before scoring discards so the bot does not accidentally
  // throw away the card it is about to call.
  let friendCard;
  if (!hand.includes(mightyCard)) {
    friendCard = mightyCard;
  } else {
    const trumpCount = trumpSuit !== 'no_trump' ? (suitGroups[trumpSuit] || []).length : 0;
    const hasJoker = hand.includes('mighty_joker');
    // Solo criteria — strict. Simulation showed loose solo tanked the win rate;
    // a genuinely solo-able hand is a long trump AND a joker AND a real reason
    // not to want a partner's side-suit winner.
    const isSuited = trumpSuit && trumpSuit !== 'no_trump';
    if (isSuited && hasJoker && trumpCount >= 6) {
      friendCard = 'no_friend';
    } else {
      friendCard = pickFriendCard(hand, game);
    }
  }

  const eligible = hand.filter(cardId =>
    !protectedCards.has(cardId) && cardId !== friendCard);
  const discards = chooseKittyDiscards(eligible, game, suitGroups);

  return { type: 'discard_kitty', discards, friendCard };
}

function groupMightyCardsBySuit(cards, excluded = new Set()) {
  const suitGroups = {};
  for (const suit of SUITS) suitGroups[suit] = [];
  for (const cardId of cards) {
    if (excluded.has(cardId) || cardId === 'mighty_joker') continue;
    const info = getCardInfo(cardId);
    if (info.suit) suitGroups[info.suit].push(cardId);
  }
  for (const suit of SUITS) {
    suitGroups[suit].sort((a, b) =>
      (RANK_ORDER[getCardInfo(a).rank] || 0) - (RANK_ORDER[getCardInfo(b).rank] || 0));
  }
  return suitGroups;
}

function chooseKittyDiscards(eligible, game, suitGroups) {
  if (eligible.length <= 3) return eligible.slice(0, 3);

  let best = null;
  for (let i = 0; i < eligible.length - 2; i++) {
    for (let j = i + 1; j < eligible.length - 1; j++) {
      for (let k = j + 1; k < eligible.length; k++) {
        const combo = [eligible[i], eligible[j], eligible[k]];
        const score = scoreKittyDiscardCombo(combo, game, suitGroups);
        if (!best || score > best.score || (score === best.score && combo.join('|') < best.cards.join('|'))) {
          best = { score, cards: combo };
        }
      }
    }
  }
  return best ? best.cards : eligible.slice(0, 3);
}

function scoreKittyDiscardCombo(combo, game, suitGroups) {
  const trumpSuit = game.trumpSuit;
  let score = 0;
  const discardedBySuit = {};
  let bankedPoints = 0;
  let trumpDiscards = 0;

  for (const cardId of combo) {
    const info = getCardInfo(cardId);
    if (!info.suit) continue;
    discardedBySuit[info.suit] = (discardedBySuit[info.suit] || 0) + 1;
    if (info.point > 0) bankedPoints++;
    if (trumpSuit !== 'no_trump' && info.suit === trumpSuit) trumpDiscards++;
    score += scoreKittyDiscardCard(cardId, game, suitGroups);
  }

  // Discarded point cards are already secured for the declarer, so low point
  // cards are attractive. The per-card score still protects A/K winners.
  score += bankedPoints * 4;

  for (const suit of Object.keys(discardedBySuit)) {
    if (trumpSuit !== 'no_trump' && suit === trumpSuit) continue;
    const suitSize = (suitGroups[suit] || []).length;
    const discardedCount = discardedBySuit[suit];
    if (discardedCount === suitSize && suitSize > 0 && suitSize <= 3) {
      score += 36 - (suitSize * 4); // creating a side-suit void is valuable
    } else if (suitSize <= 2) {
      score += discardedCount * 6;
    }
  }

  if (trumpDiscards > 0) {
    const trumpCount = trumpSuit !== 'no_trump' ? (suitGroups[trumpSuit] || []).length : 0;
    score -= trumpDiscards * (trumpCount >= 7 ? 6 : 28);
    if (trumpDiscards >= 2 && trumpCount < 7) score -= 20;
  }

  return score;
}

function scoreKittyDiscardCard(cardId, game, suitGroups) {
  const info = getCardInfo(cardId);
  const trumpSuit = game.trumpSuit;
  const isTrump = trumpSuit !== 'no_trump' && info.suit === trumpSuit;
  const rankValue = RANK_ORDER[info.rank] || 0;
  const suitSize = (suitGroups[info.suit] || []).length;
  let score = 0;

  score += isTrump ? -35 : 18;
  score += Math.max(0, 11 - rankValue); // low cards are easier to release

  if (info.point > 0) {
    // Banking 10/J/Q is usually better than carrying a likely loser. A/K are
    // real control cards and should only be discarded when a void is worth it.
    if (info.rank === '10') score += 28;
    else if (info.rank === 'J') score += 22;
    else if (info.rank === 'Q') score += 14;
    else if (info.rank === 'K') score -= 10;
    else if (info.rank === 'A') score -= 24;
  }

  if (!isTrump && suitSize <= 3) score += (4 - suitSize) * 4;
  if (!isTrump && suitSize >= 5 && rankValue >= 12) score -= 8;
  if (isTrump && rankValue >= 11) score -= 18;

  return score;
}

/**
 * Pick a friend card by scoring multiple candidate calls:
 *   1. Non-trump Ace of a suit where declarer has a 1-3 card holding (best
 *      when singleton, still ok when void).
 *   2. Non-trump King of a suit where declarer already holds the Ace — the
 *      friend's K backs up declarer's A for two guaranteed wins.
 *   3. Joker call — whoever holds the joker becomes friend; extra-valuable
 *      when trump is strong (joker wins ruffed tricks too).
 *
 * Higher score wins. Stable across repeats of the same hand shape but
 * differentiates on hand composition, producing visible variety across rounds.
 */
function pickFriendCard(hand, game) {
  const mightyCard = game.getMightyCard();
  const trumpSuit = game.trumpSuit;
  const hasJoker = hand.includes('mighty_joker');

  const suitInfo = {};
  for (const suit of SUITS) {
    suitInfo[suit] = { count: 0, hasA: false, hasK: false };
  }
  for (const cardId of hand) {
    if (cardId === 'mighty_joker' || cardId === mightyCard) continue;
    const info = getCardInfo(cardId);
    suitInfo[info.suit].count++;
    if (info.rank === 'A') suitInfo[info.suit].hasA = true;
    if (info.rank === 'K') suitInfo[info.suit].hasK = true;
  }

  const candidates = [];

  // Option 1: non-trump Ace. Hard requirement — bot must hold ≥1 card in
  // the suit. A friend's A surfaces when somebody leads that suit and the
  // friend covers; if the bot is void it can't lead it (and cuts with a
  // trump on follow-up), so the friend's A may sit untouched the whole
  // round. Sweet spot is 1–3 cards: a single low rank tempts a follow,
  // 2–3 keeps optionality. 4+ length means the bot already covers the
  // suit so a friend's A is mostly redundant.
  for (const suit of SUITS) {
    if (suit === trumpSuit) continue;
    const s = suitInfo[suit];
    if (s.hasA) continue;
    if (s.count === 0) continue;          // hard skip: void → friend can never surface
    const aceId = `mighty_${suit}_A`;
    if (aceId === mightyCard) continue;
    let score = 10;
    if (s.count === 1) score += 5;
    else if (s.count === 2) score += 3;
    else if (s.count === 3) score += 1;
    else score -= 3;                      // 4+ suit: our own length already covers it
    if (s.hasK) score += 2;
    candidates.push({ cardId: aceId, score });
  }

  // Option 2: non-trump King where I already hold the Ace. Bot leads the K,
  // friend's A covers → reveal. Requires count ≥ 1 (defensive: hasA implies
  // count ≥ 1 already, but the explicit check guards against future edits).
  for (const suit of SUITS) {
    if (suit === trumpSuit) continue;
    const s = suitInfo[suit];
    if (!s.hasA || s.hasK) continue;
    if (s.count === 0) continue;
    const kingId = `mighty_${suit}_K`;
    let score = 9;
    if (s.count <= 3) score += 2;
    candidates.push({ cardId: kingId, score });
  }

  // Option 3: joker call. Sim data shows joker calls win ~45-49% — as strong
  // as a mighty call. Boost the base so it outranks a marginal side-A.
  if (!hasJoker) {
    let score = 16;
    const trumpCount = trumpSuit !== 'no_trump' ? (suitInfo[trumpSuit]?.count || 0) : 0;
    if (trumpCount >= 4) score += 2;
    if (!trumpSuit || trumpSuit === 'no_trump') score += 2;
    candidates.push({ cardId: 'mighty_joker', score });
  }

  if (candidates.length > 0) {
    candidates.sort((a, b) => b.score - a.score);
    const winner = candidates[0];
    // If even the best candidate is poor (e.g., the only option left is a
    // void-suit A because the declarer is self-sufficient in every other
    // suit), solo is a better call than a friend who can never actually
    // win their suit. Threshold 5 sits comfortably between the void-A
    // floor (2) and the 4+-length-A floor (7).
    if (winner.score < 5) {
      if (typeof globalThis.__mightySimHook === 'function') {
        try { globalThis.__mightySimHook(hand, 'no_friend', candidates.slice(0, 3)); } catch { /* ignore */ }
      }
      return 'no_friend';
    }
    if (typeof globalThis.__mightySimHook === 'function') {
      try { globalThis.__mightySimHook(hand, winner.cardId, candidates.slice(0, 3)); } catch { /* ignore */ }
    }
    return winner.cardId;
  }

  // Fallback: King of any suit where I lack the K AND have at least one
  // card to lead. Skipping void suits keeps the friend pickable in play.
  for (const suit of SUITS) {
    if (suit === trumpSuit) continue;
    const s = suitInfo[suit];
    if (s.hasK) continue;
    if (s.count === 0) continue;
    return `mighty_${suit}_K`;
  }

  return 'no_friend';
}

// ═══════════════════════════════════════════════════════════
//  HELPER FUNCTIONS
// ═══════════════════════════════════════════════════════════

function getRemainingPlayers(game, botId) {
  const playedIds = new Set(game.currentTrick.map(p => p.pid));
  const leaderIdx = game.playerIds.indexOf(game.currentTrick[0].pid);
  const excluded = game.excludedPlayers || new Set();
  const remaining = [];
  for (let i = 0; i < game.playerCount; i++) {
    const pid = game.playerIds[(leaderIdx + i) % game.playerCount];
    if (excluded.has(pid)) continue;
    if (!playedIds.has(pid) && pid !== botId) {
      remaining.push(pid);
    }
  }
  return remaining;
}

function isGovernment(game, playerId) {
  if (playerId === game.declarer) return true;
  if (game.friendRevealed && playerId === game.partner) return true;
  return false;
}

function isGovernmentSelf(game, playerId) {
  if (isGovernment(game, playerId)) return true;
  return _isFriend(game, playerId);
}

function getTrickPointCount(game) {
  let count = 0;
  for (const play of game.currentTrick) {
    if (play.cardId === 'mighty_joker') continue;
    const info = getCardInfo(play.cardId);
    if (info.point > 0) count++;
  }
  return count;
}

function hasOppositionBehind(game, botId) {
  const remaining = getRemainingPlayers(game, botId);
  const botIsGov = isGovernmentSelf(game, botId);
  for (const pid of remaining) {
    const pidIsGov = isGovernmentSelf(game, pid);
    if (botIsGov !== pidIsGov) return true;
  }
  return false;
}

function hasGovernmentBehind(game, botId) {
  const remaining = getRemainingPlayers(game, botId);
  for (const pid of remaining) {
    if (isGovernmentSelf(game, pid)) return true;
  }
  return false;
}

function getBestPointCard(legalCards) {
  let best = null;
  let bestRank = -1;
  for (const cardId of legalCards) {
    if (cardId === 'mighty_joker') continue;
    const info = getCardInfo(cardId);
    if (info.point > 0) {
      const rank = RANK_ORDER[info.rank] || 0;
      if (rank > bestRank) { bestRank = rank; best = cardId; }
    }
  }
  return best;
}

function getNonPointWeakest(legalCards, game) {
  const mightyCard = game.getMightyCard();
  const nonPoint = legalCards.filter(cardId => {
    if (cardId === mightyCard || cardId === 'mighty_joker') return false;
    return getCardInfo(cardId).point === 0;
  });
  if (nonPoint.length > 0) return getWeakestCard(nonPoint, game);
  return getWeakestCard(legalCards, game);
}

/** Weakest card that's NOT a trump (and not mighty/joker) — used to dump off-suit safely. */
function getNonTrumpWeakest(legalCards, game) {
  const mightyCard = game.getMightyCard();
  const nonTrump = legalCards.filter(cardId => {
    if (cardId === mightyCard || cardId === 'mighty_joker') return false;
    const info = getCardInfo(cardId);
    return info.suit !== game.trumpSuit;
  });
  if (nonTrump.length > 0) return getWeakestCard(nonTrump, game);
  return getNonPointWeakest(legalCards, game);
}

/**
 * "Safe discard" for uncertain-ally-winning / can't-win scenarios.
 * Avoids both point cards (don't hand opp points) and trump cards (don't
 * burn trump). Tiered fallback: non-point non-trump → non-point → non-trump → any.
 */
function getSafeDiscard(legalCards, game) {
  const mightyCard = game.getMightyCard();
  const isSpecial = (c) => c === mightyCard || c === 'mighty_joker';

  const nonPointNonTrump = legalCards.filter(c => {
    if (isSpecial(c)) return false;
    const info = getCardInfo(c);
    return info.point === 0 && info.suit !== game.trumpSuit;
  });
  if (nonPointNonTrump.length > 0) return getWeakestCard(nonPointNonTrump, game);

  const nonPoint = legalCards.filter(c => {
    if (isSpecial(c)) return false;
    return getCardInfo(c).point === 0;
  });
  if (nonPoint.length > 0) return getWeakestCard(nonPoint, game);

  const nonTrump = legalCards.filter(c => {
    if (isSpecial(c)) return false;
    return getCardInfo(c).suit !== game.trumpSuit;
  });
  if (nonTrump.length > 0) return getWeakestCard(nonTrump, game);

  return getWeakestCard(legalCards, game);
}

/**
 * Pick the MINIMAL card that wins the trick.
 * - Last player: cheapest is always safe (no one left to overcut).
 * - Opp behind, non-trump lead + we're ruffing with trump: use the LOWEST
 *   trump. Any unplayed trump already beats the entire lead suit; the only
 *   overcut path is opp spending a higher trump on this very trick, which is
 *   rare enough that the conservation is worth it.
 * - Opp behind, trump lead (or lead-suit follow): we need an actual
 *   guaranteed winner (effective top of the lead suit). Fall back to
 *   mighty/joker only when no cheap sure winner exists.
 */
function pickSufficientWinner(winningCards, game, isLastPlayer, oppBehind) {
  const mightyCard = game.getMightyCard();
  const cheap = winningCards.filter(c => c !== mightyCard && c !== 'mighty_joker');

  if (isLastPlayer) {
    if (cheap.length > 0) return getWeakestCard(cheap, game);
    return winningCards[0];
  }

  if (oppBehind) {
    // Ruffing path: lead is a non-trump card and we can beat it with a trump.
    const trump = game.trumpSuit;
    const hasTrumpSuit = trump && trump !== 'no_trump';
    const leadCard = game.currentTrick[0] && game.currentTrick[0].cardId;
    const leadIsTrump = leadCard === 'mighty_joker' ||
      (leadCard && hasTrumpSuit && getCardInfo(leadCard).suit === trump);
    if (!leadIsTrump && hasTrumpSuit) {
      const cheapTrumps = cheap.filter(c => getCardInfo(c).suit === trump);
      if (cheapTrumps.length > 0) return getWeakestCard(cheapTrumps, game);
    }

    // Lead-suit (or trump-suit) follow: need a guaranteed top-of-suit winner.
    const sureCheap = cheap.filter(c => _isEffectiveTopOfSuit(c, game));
    if (sureCheap.length > 0) return getWeakestCard(sureCheap, game);
    if (winningCards.includes(mightyCard)) return mightyCard;
    if (winningCards.includes('mighty_joker')) return 'mighty_joker';
    if (cheap.length > 0) return getStrongestCard(cheap, game);
    return winningCards[0];
  }

  // Only allies behind — cheapest works
  if (cheap.length > 0) return getWeakestCard(cheap, game);
  return winningCards[0];
}

/**
 * Pick a "safe dump" — prefer to give a point card to our ally without burning
 * trumps, mighty, or joker. Falls back to non-trump non-point weakest.
 */
// Friend-aware safe dump: keeps the bot's own effective non-trump tops in
// hand. Friend bots that dump their A (or unplayed-K, etc.) onto declarer's
// already-winning trick give up a guaranteed lead-trick they could have
// taken later for the team. Trumps and non-top point cards still get
// dumped, matching the original pickSafeDump priority.
function pickSafeDumpKeepingTops(legalCards, game) {
  const mightyCard = game.getMightyCard();
  const safe = legalCards.filter(c => {
    if (c === mightyCard || c === 'mighty_joker') return false;
    const info = getCardInfo(c);
    if (info.suit === game.trumpSuit) return true;
    return !_isEffectiveTopOfSuit(c, game);
  });
  if (safe.length === 0) return pickSafeDump(legalCards, game);
  return pickSafeDump(safe, game);
}

function pickSafeDump(legalCards, game) {
  const mightyCard = game.getMightyCard();
  const nonTrumpPoints = legalCards.filter(c => {
    if (c === 'mighty_joker' || c === mightyCard) return false;
    const info = getCardInfo(c);
    return info.point > 0 && info.suit !== game.trumpSuit;
  });
  if (nonTrumpPoints.length > 0) {
    // All Mighty point cards are worth 1 pt each, so when several are
    // eligible, dump the LOWEST-rank one first. This preserves higher
    // cards' future trick-taking power (e.g., ♥A vs ♥10 both feed an
    // ally's winning trick the same 1 pt, but ♥A still wins us
    // future ♥ tricks if we keep it).
    return nonTrumpPoints.sort((a, b) =>
      RANK_ORDER[getCardInfo(a).rank] - RANK_ORDER[getCardInfo(b).rank])[0];
  }
  // No non-trump point card: dump weakest non-trump non-point before touching trump
  const nonTrumpNonPoint = legalCards.filter(c => {
    if (c === 'mighty_joker' || c === mightyCard) return false;
    const info = getCardInfo(c);
    return info.point === 0 && info.suit !== game.trumpSuit;
  });
  if (nonTrumpNonPoint.length > 0) return getWeakestCard(nonTrumpNonPoint, game);
  // Only trump-ish cards remain (mighty/joker/trumps) — play weakest trump
  return getNonPointWeakest(legalCards, game);
}

function getStrongestCard(cards, game) {
  const mightyCard = game.getMightyCard();
  let strongest = cards[0];
  let strongestValue = -1;

  for (const cardId of cards) {
    let value;
    if (cardId === mightyCard) value = 1000;
    else if (cardId === 'mighty_joker') value = 900;
    else {
      const info = getCardInfo(cardId);
      value = RANK_ORDER[info.rank] || 0;
      if (info.suit === game.trumpSuit) value += 100;
    }
    if (value > strongestValue) { strongestValue = value; strongest = cardId; }
  }
  return strongest;
}

function getWeakestCard(cards, game) {
  const mightyCard = game.getMightyCard();
  let weakest = cards[0];
  let weakestValue = 9999;

  for (const cardId of cards) {
    let value;
    if (cardId === mightyCard) value = 1000;
    else if (cardId === 'mighty_joker') value = 900;
    else {
      const info = getCardInfo(cardId);
      value = RANK_ORDER[info.rank] || 0;
      if (info.suit === game.trumpSuit) value += 100;
      if (info.point > 0) value += 50;
    }
    if (value < weakestValue) { weakestValue = value; weakest = cardId; }
  }
  return weakest;
}

// ═══════════════════════════════════════════════════════════
//  TRICK PLAY — LEADING
// ═══════════════════════════════════════════════════════════

function decidePlay(game, botId) {
  const legalCards = game._getLegalCards(botId);
  if (legalCards.length === 0) return null;

  // Setting (세팅) declaration: when leading, if the server says the
  // remaining hand is unconditionally winning (`_canDeclareSetting`),
  // claim every remaining point card via setting instead of playing the
  // rest of the round trick-by-trick. The server-side check already
  // handles every edge case (mode, weak-trick gates, opp pool, etc.),
  // so the bot just defers to it.
  if (game.currentTrick.length === 0
      && typeof game._canDeclareSetting === 'function'
      && game._canDeclareSetting(botId)) {
    return { type: 'declare_setting' };
  }

  if (legalCards.length === 1) {
    return makePlayAction(legalCards[0], game, botId);
  }

  const isLeading = game.currentTrick.length === 0;

  // Joker-call defense: when joker-call is active and we hold both the
  // joker and the Mighty, play Mighty to absorb the call. The joker-call
  // can't actually pull the Mighty out — so this is a strict win (we keep
  // the joker for later, and Mighty was already a 'spend it sometime'
  // card). Server's _getLegalCards exposes both as legal in this state,
  // and the bot should prefer Mighty here.
  if (!isLeading) {
    const leadCard = game.currentTrick[0]?.cardId;
    const jokerCallCard = game.getJokerCallCard();
    const jokerCallLed = leadCard === jokerCallCard
      && game.jokerCallActive
      && jokerCallCard != null;
    if (jokerCallLed) {
      const mightyCard = game.getMightyCard();
      if (legalCards.includes('mighty_joker')
          && mightyCard
          && legalCards.includes(mightyCard)) {
        return makePlayAction(mightyCard, game, botId);
      }
    }
  }

  if (isLeading) {
    return makePlayAction(decideLeadCard(game, botId, legalCards), game, botId);
  } else {
    return makePlayAction(decideFollowCard(game, botId, legalCards), game, botId);
  }
}

function decideLeadCard(game, botId, legalCards) {
  const mightyCard = game.getMightyCard();
  const botIsGov = isGovernmentSelf(game, botId);

  // Joker-endgame override: the last trick uses a weak joker by default
  // (priority 0 — it loses to anything). If we still hold joker and we're
  // leading, the penultimate trick is the last chance to cash it in at
  // priority 900. Otherwise the role-specific strategies below may keep
  // hoarding joker (opposition never leads it at all, declarer only leads
  // it when trump is drained) and the joker ends up wasted on a losing
  // last-trick play.
  if (legalCards.includes('mighty_joker')) {
    const totalTricks = Math.floor(50 / (game.activePlayerCount || game.playerCount));
    const nextIsLast = game.tricks.length === totalTricks - 2;
    if (nextIsLast && !game.options.lastTrickJokerPower) {
      return 'mighty_joker';
    }
  }

  // Joker without power on this trick can't win and gives up the lead for
  // zero offensive value. Filter it out so role-specific logic doesn't
  // accidentally lead it. (Penultimate-trick cash-in above already handled
  // the "spend it before last-trick" case.)
  if (legalCards.includes('mighty_joker') && !game._currentTrickJokerHasPower() && legalCards.length > 1) {
    legalCards = legalCards.filter(c => c !== 'mighty_joker');
  }

  // Group cards by suit
  const suitCards = {};
  for (const cardId of legalCards) {
    if (cardId === 'mighty_joker') continue;
    const info = getCardInfo(cardId);
    if (!suitCards[info.suit]) suitCards[info.suit] = [];
    suitCards[info.suit].push(cardId);
  }

  if (botIsGov) {
    return _governmentLead(game, botId, legalCards, suitCards, mightyCard);
  } else {
    return _oppositionLead(game, botId, legalCards, suitCards, mightyCard);
  }
}

function _governmentLead(game, botId, legalCards, suitCards, mightyCard) {
  const isFriendBot = _isFriend(game, botId);
  const hasTrump = game.trumpSuit && game.trumpSuit !== 'no_trump';

  if (isFriendBot) {
    return _friendLead(game, botId, legalCards, suitCards, mightyCard);
  }

  // Declarer 2nd-trick joker-call: if we're the declarer leading the second
  // trick (one trick already done), with a suited bid and a non-joker friend,
  // and we hold the joker-call card — fire it now to force opp's joker out
  // before the friend reveal commits the table to a side.
  if (botId === game.declarer
      && hasTrump
      && game.tricks.length === 1
      && game.friendCard !== 'mighty_joker') {
    const jokerCallCard = game.getJokerCallCard();
    if (jokerCallCard && legalCards.includes(jokerCallCard)) {
      return jokerCallCard;
    }
  }

  // Phase 1: Mighty (sure winner in all cases)
  if (legalCards.includes(mightyCard)) return mightyCard;

  // (Removed: early proactive joker lead.) Burning joker right after
  // mighty wastes its trick-taking power before we've seen the field.
  // Optimal sequence in suited play is mighty → trump A → trump K →
  // joker (only after trump is drained). The post-Phase-3 joker block
  // below (gated on `_onlyGovernmentHasTrump`) handles the "trump
  // drained" case. NT path still leads joker after sure tops as one of
  // the natural high winners.

  // Friend-bait helper: lead a low non-A/non-friend card in the friend-card
  // suit so the friend can cover with their A/K and reveal themselves. Skipped
  // for joker / first-trick / Mighty-friends / no-friend variants where the
  // friend card isn't a suited side card. Returns null if not applicable.
  const friendBaitCard = (() => {
    if (game.friendRevealed) return null;
    const fc = game.friendCard;
    if (!fc || fc === 'no_friend' || fc === 'first_trick' || fc === 'mighty_joker' || fc === mightyCard) {
      return null;
    }
    const fInfo = getCardInfo(fc);
    const fSuit = fInfo?.suit;
    if (!fSuit || fSuit === game.trumpSuit) return null;
    const cards = suitCards[fSuit];
    if (!cards || cards.length === 0) return null;
    // Don't lead the friend card itself (we don't hold it anyway since we
    // called it — but safe-guard for any edge case).
    const baitable = cards.filter(c => c !== fc && getCardInfo(c).rank !== 'A');
    if (baitable.length === 0) return null;
    return baitable.sort((a, b) =>
      RANK_ORDER[getCardInfo(a).rank] - RANK_ORDER[getCardInfo(b).rank])[0];
  })();

  if (!hasTrump) {
    // ═══ NO-TRUMP DECLARER STRATEGY ═══
    // In NT there's no trump to draw. Play sure winners, then joker, then longest suit.

    // Bait friend BEFORE burning sure-top non-friend-suit cards. Otherwise
    // the friend may never get a natural opportunity to cover.
    if (friendBaitCard) return friendBaitCard;

    // Play all effective top cards across all suits
    for (const [suit, cards] of Object.entries(suitCards)) {
      const sorted = cards.sort((a, b) =>
        RANK_ORDER[getCardInfo(b).rank] - RANK_ORDER[getCardInfo(a).rank]);
      if (_isEffectiveTopOfSuit(sorted[0], game)) return sorted[0];
    }

    // Joker: in NT, joker is #2 card. Play it (especially after mighty is gone).
    if (legalCards.includes('mighty_joker')) return 'mighty_joker';

    // Lead from longest suit to try to establish it
    return _leadFromLongest(suitCards, legalCards);
  }

  // ═══ SUITED TRUMP DECLARER STRATEGY ═══
  // Phase 2: DRAW TRUMPS — but only when opposition actually still holds trump.
  // If the only trumps left are with us + friend, drawing trump is wasted tempo.
  if (suitCards[game.trumpSuit] && suitCards[game.trumpSuit].length > 0) {
    if (!_onlyGovernmentHasTrump(game)) {
      const trumpCards = suitCards[game.trumpSuit].sort((a, b) =>
        RANK_ORDER[getCardInfo(b).rank] - RANK_ORDER[getCardInfo(a).rank]);
      return trumpCards[0];
    }
  }

  // Friend-bait phase: trump is drawn (or only government has it left), so
  // a low friend-suit lead won't get ruffed by opp. Friend covers with the
  // called A/K, reveals, team coordinates from here. Comes BEFORE sure-top
  // burns in non-friend suits.
  if (friendBaitCard) return friendBaitCard;

  // Phase 3: Trumps drawn — play sure winners
  for (const [suit, cards] of Object.entries(suitCards)) {
    if (suit === game.trumpSuit) continue;
    const sorted = cards.sort((a, b) =>
      RANK_ORDER[getCardInfo(b).rank] - RANK_ORDER[getCardInfo(a).rank]);
    if (_isEffectiveTopOfSuit(sorted[0], game)) return sorted[0];
  }

  // Phase 4: Joker — safe when no real opponent holds trump anymore. Using the
  // opp-aware check (excludes revealed partner) instead of the raw unseen-trump
  // count so joker leads become available as soon as we've confirmed opp is dry.
  if (legalCards.includes('mighty_joker') && _onlyGovernmentHasTrump(game)) {
    return 'mighty_joker';
  }

  // Phase 5: Lead remaining trumps — skip when only government holds trump.
  // Leading trump there just lets opp discard junk; feed them a non-trump instead
  // so they're forced to spend real cards.
  if (suitCards[game.trumpSuit] && suitCards[game.trumpSuit].length > 0
      && !_onlyGovernmentHasTrump(game)) {
    return suitCards[game.trumpSuit].sort((a, b) =>
      RANK_ORDER[getCardInfo(b).rank] - RANK_ORDER[getCardInfo(a).rank])[0];
  }

  // Phase 6: Lead from longest suit (prefer non-trump first so opp must follow)
  const nonTrumpSuitCards = {};
  for (const [suit, cards] of Object.entries(suitCards)) {
    if (suit !== game.trumpSuit && cards.length > 0) nonTrumpSuitCards[suit] = cards;
  }
  if (Object.keys(nonTrumpSuitCards).length > 0) {
    return _leadFromLongest(nonTrumpSuitCards, legalCards);
  }
  return _leadFromLongest(suitCards, legalCards);
}

function _friendLead(game, botId, legalCards, suitCards, mightyCard) {
  // Mighty-friends variant: strip the Mighty from the lead pool so we
  // don't out ourselves (and waste the card) on a trick we already win.
  if (_shouldHoldMightyInMightyFriends(game, legalCards)) {
    legalCards = legalCards.filter(c => c !== mightyCard);
    const withoutMighty = {};
    for (const [suit, cards] of Object.entries(suitCards)) {
      const kept = cards.filter(c => c !== mightyCard);
      if (kept.length > 0) withoutMighty[suit] = kept;
    }
    suitCards = withoutMighty;
  }

  // Revealed friend with no trump: avoid leading spade while the Mighty
  // is still live — a high-spade lead usually just forces the declarer
  // to burn Mighty on our trick.
  if (_shouldAvoidSpadeLead(game, botId, suitCards, mightyCard)) {
    const withoutSpade = {};
    for (const [suit, cards] of Object.entries(suitCards)) {
      if (suit !== 'spade' && cards.length > 0) withoutSpade[suit] = cards;
    }
    suitCards = withoutSpade;
    legalCards = legalCards.filter(c =>
      c === 'mighty_joker' || getCardInfo(c).suit !== 'spade');
  }

  const friendCardSuit = _getFriendCardSuit(game);
  const hasTrump = game.trumpSuit && game.trumpSuit !== 'no_trump';
  const isFirstTrickFriend = game.friendCard === 'first_trick';
  const isMightyFriendsVariant = game.friendCard === mightyCard;

  // Helper: highest-first sort of a card list
  const sortHigh = (cards) => [...cards].sort((a, b) =>
    RANK_ORDER[getCardInfo(b).rank] - RANK_ORDER[getCardInfo(a).rank]);

  if (!hasTrump) {
    // ═══ NO-TRUMP FRIEND STRATEGY ═══
    // Priority per user rule:
    //   1) Call suit (friend-card suit): always feed it back if held — that's
    //      the suit declarer signalled by naming.
    //   2) Declarer's inferred strong suit: declarer led K or Q earlier while
    //      higher rank(s) remain unplayed → declarer probably holds A → keep
    //      pushing that suit so declarer can cash.
    //   3) Effective tops elsewhere; mighty / joker as fallback winners.
    if (friendCardSuit && suitCards[friendCardSuit] && suitCards[friendCardSuit].length > 0) {
      return sortHigh(suitCards[friendCardSuit])[0];
    }

    const strongSuit = _declarerStrongSuit(game);
    if (strongSuit && suitCards[strongSuit] && suitCards[strongSuit].length > 0) {
      return sortHigh(suitCards[strongSuit])[0];
    }

    if (legalCards.includes(mightyCard)) return mightyCard;

    for (const cards of Object.values(suitCards)) {
      const sorted = sortHigh(cards);
      if (_isEffectiveTopOfSuit(sorted[0], game)) return sorted[0];
    }

    if (legalCards.includes('mighty_joker')) return 'mighty_joker';

    return _leadFromLongest(suitCards, legalCards);
  }

  // ═══ SUITED FRIEND STRATEGY ═══

  // First-trick-friend variant: prefer trump (high-to-low) regardless of
  // top status. When trump is dry, fall back to the suit of the very first
  // trick — the only signal the table has about the friendship in this
  // variant, so re-leading it nudges declarer to grab back tempo.
  if (isFirstTrickFriend) {
    const trumpHi = sortHigh(suitCards[game.trumpSuit] || []);
    if (trumpHi.length > 0) return trumpHi[0];
    const firstSuit = _firstTrickLeadSuit(game);
    if (firstSuit && suitCards[firstSuit] && suitCards[firstSuit].length > 0) {
      return sortHigh(suitCards[firstSuit])[0];
    }
    // fall through to default suited friend logic
  }

  // Mighty-friends variant: Mighty was already filtered out above by
  // _shouldHoldMightyInMightyFriends. Lead a non-Mighty top first so we
  // collect points without burning Mighty, then 'return' trump suit — but
  // skip the trump return when trump has already been a lead suit at least
  // once before (no point recycling a suit the table has already drawn).
  if (isMightyFriendsVariant) {
    // Effective top in non-trump suits first
    for (const [suit, cards] of Object.entries(suitCards)) {
      if (suit === game.trumpSuit) continue;
      const sorted = sortHigh(cards);
      if (_isEffectiveTopOfSuit(sorted[0], game)) return sorted[0];
    }
    // Effective top in trump suit
    const trumpHi = sortHigh(suitCards[game.trumpSuit] || []);
    if (trumpHi.length > 0 && _isEffectiveTopOfSuit(trumpHi[0], game)) {
      return trumpHi[0];
    }
    // Trump suit lead — only when not already led in a prior trick
    const ledSuits = _suitsAlreadyLed(game);
    if (trumpHi.length > 0 && !ledSuits.has(game.trumpSuit)) {
      return trumpHi[0];
    }
    // fall through to default suited friend logic
  }

  // Joker lead — but only when trump isn't worth draining first. Per
  // the joker-strategy spec: trump-controllable → drain trump first,
  // joker later. Trump uncontrollable → lead joker now.
  //
  // Heuristic for "trump uncontrollable": opp holds at least as many
  // trumps as we do, OR we hold no trump at all. In those cases trying
  // to drain is hopeless and the joker is the better lead.
  if (legalCards.includes('mighty_joker')) {
    const myTrumpCount = (game.trumpSuit && game.trumpSuit !== 'no_trump')
      ? (suitCards[game.trumpSuit] || []).length : 0;
    const oppTrumpsForJoker = _countOpponentTrumps(game, botId);
    const trumpUncontrollable = myTrumpCount === 0 || oppTrumpsForJoker >= myTrumpCount;
    if (trumpUncontrollable) {
      return 'mighty_joker';
    }
    // Otherwise fall through — drain trump first (handled below by the
    // "default suited friend strategy" trump-lead branch).
  }

  // Effective non-trump top: a guaranteed trick the friend can take while
  // saving trump for ruffs later. Beats the trump-draw default — '선
  // 먹었을때 한 트릭이라도 해줄 수 있는 카드'.
  //
  // Top-of-led-suit guard: leading a top in a suit that's ALREADY been led
  // once invites a ruff (someone is likely void in that suit by now). Restrict
  // to fresh (never-led) suits when EITHER ≥3 trumps still sit in opp hands,
  // OR the friend-card suit (기루) still has 5+ cards live in opp hands —
  // in the latter case the bot should be flushing 기루 rather than gambling a
  // top on a stale suit.
  const oppTrumpCount = _countOpponentTrumps(game, botId);
  const trumpHeavyOpp = oppTrumpCount >= 3;
  const friendSuitOut = friendCardSuit
    ? _countCardsInSuitOutsideHand(game, botId, friendCardSuit) : 0;
  const friendSuitRich = friendSuitOut >= 5;

  // Friend-suit drain: when 기루 is still rich and we hold a top of it,
  // lead it first to force opp to burn ammo in their fattest suit.
  if (friendSuitRich && friendCardSuit
      && suitCards[friendCardSuit] && suitCards[friendCardSuit].length > 0) {
    const sorted = sortHigh(suitCards[friendCardSuit]);
    if (_isEffectiveTopOfSuit(sorted[0], game)) return sorted[0];
  }

  const ledSuitsForTopGuard = (trumpHeavyOpp || friendSuitRich) ? _suitsAlreadyLed(game) : null;
  for (const [suit, cards] of Object.entries(suitCards)) {
    if (suit === game.trumpSuit) continue;
    if (ledSuitsForTopGuard && ledSuitsForTopGuard.has(suit)) continue;
    const sorted = sortHigh(cards);
    if (_isEffectiveTopOfSuit(sorted[0], game)) return sorted[0];
  }

  // Default suited friend strategy: help draw trumps by leading trump,
  // or return declarer's strong suit. _noRealOppTrumpLeft excludes self
  // (pre-reveal `game.partner` is null but this bot is government).
  const oppOutOfTrump = _noRealOppTrumpLeft(game, botId);

  if (!oppOutOfTrump && suitCards[game.trumpSuit] && suitCards[game.trumpSuit].length > 0) {
    return sortHigh(suitCards[game.trumpSuit])[0];
  }

  const returnSuit = oppOutOfTrump ? friendCardSuit : game.trumpSuit;
  if (returnSuit && suitCards[returnSuit] && suitCards[returnSuit].length > 0) {
    return sortHigh(suitCards[returnSuit])[0];
  }

  // Friend-suit drain fallback: when 기루 is still rich and we hold any 기루,
  // lead the highest one even when it's not yet an effective top. Sacrificing
  // 기루 K to draw out opp's 기루 A still flushes the suit (no ruff possible
  // in-suit) and beats _leadFromLongest's stale-suit pick — that path lands
  // on our longest non-trump, often a previously-led suit where opp went
  // void and is waiting to ruff.
  if (friendSuitRich && friendCardSuit
      && suitCards[friendCardSuit] && suitCards[friendCardSuit].length > 0) {
    return sortHigh(suitCards[friendCardSuit])[0];
  }

  // Fallthrough: play mighty or top card
  if (legalCards.includes(mightyCard)) return mightyCard;
  return _leadFromLongest(suitCards, legalCards);
}

function _oppositionLead(game, botId, legalCards, suitCards, mightyCard) {
  const voids = _getKnownVoids(game);
  const declarerVoids = voids[game.declarer] || new Set();
  const hasTrump = game.trumpSuit && game.trumpSuit !== 'no_trump';

  // Critical endgame: ≤ 2 tricks left and declarer short of bid. Lead our
  // strongest available card (sure top, then mighty, then joker, then any
  // high trump) so the opp side actually takes the trick rather than
  // setting up a future one we'll never reach. Skips the "avoid declarer
  // voids" guard — if they ruff it, at least they burn a trump to deny
  // us, and we're already in endgame.
  if (_oppCriticalEndgame(game)) {
    // Try effective-top non-trump first (guaranteed winner if nobody ruffs).
    for (const [suit, cards] of Object.entries(suitCards)) {
      if (suit === game.trumpSuit) continue;
      const sorted = cards.sort((a, b) =>
        RANK_ORDER[getCardInfo(b).rank] - RANK_ORDER[getCardInfo(a).rank]);
      if (_isEffectiveTopOfSuit(sorted[0], game)) return sorted[0];
    }
    if (legalCards.includes(mightyCard)) return mightyCard;
    if (legalCards.includes('mighty_joker')) return 'mighty_joker';
    // Fall through to normal logic if we have no clear winner.
  }

  // Strategy 1: If we have a sure top card, lead it to collect points safely
  for (const [suit, cards] of Object.entries(suitCards)) {
    if (suit === game.trumpSuit) continue;
    const sorted = cards.sort((a, b) =>
      RANK_ORDER[getCardInfo(b).rank] - RANK_ORDER[getCardInfo(a).rank]);
    if (_isEffectiveTopOfSuit(sorted[0], game)) {
      // Only lead if declarer isn't void in this suit (they'd trump it)
      if (!declarerVoids.has(suit)) return sorted[0];
    }
  }

  // Strategy 2: Lead suits where declarer IS void → force them to waste trump
  // But only if WE don't have high cards there (we'd lose them)
  if (hasTrump) {
    for (const suit of declarerVoids) {
      if (suit === game.trumpSuit) continue;
      if (suitCards[suit] && suitCards[suit].length > 0) {
        // Lead low from this suit — declarer must trump or discard
        const sorted = suitCards[suit].sort((a, b) =>
          RANK_ORDER[getCardInfo(a).rank] - RANK_ORDER[getCardInfo(b).rank]);
        // Only lead if card is expendable (not a point card or high card)
        const lowest = sorted[0];
        const lowestInfo = getCardInfo(lowest);
        if (lowestInfo.point === 0 || RANK_ORDER[lowestInfo.rank] <= RANK_ORDER['Q']) {
          return lowest;
        }
      }
    }
  }

  // Strategy 3: Create voids — lead low from shortest non-trump suit
  // AVOID friend card suit (don't help declarer find partner)
  const friendCardSuit = _getFriendCardSuit(game);
  let shortestSuit = null;
  let shortestLen = Infinity;
  for (const [suit, cards] of Object.entries(suitCards)) {
    if (suit === game.trumpSuit) continue;
    // Avoid leading friend card suit if friend not revealed
    if (!game.friendRevealed && suit === friendCardSuit) continue;
    if (cards.length > 0 && cards.length < shortestLen) {
      shortestLen = cards.length;
      shortestSuit = suit;
    }
  }
  if (shortestSuit && suitCards[shortestSuit].length > 0) {
    const sorted = suitCards[shortestSuit].sort((a, b) =>
      RANK_ORDER[getCardInfo(a).rank] - RANK_ORDER[getCardInfo(b).rank]);
    return sorted[0];
  }

  // Strategy 4: fallback — any non-trump suit, lead low
  for (const [suit, cards] of Object.entries(suitCards)) {
    if (suit === game.trumpSuit) continue;
    if (cards.length > 0) {
      return cards.sort((a, b) =>
        RANK_ORDER[getCardInfo(a).rank] - RANK_ORDER[getCardInfo(b).rank])[0];
    }
  }

  return _leadFromLongest(suitCards, legalCards);
}

/** Fallback: lead highest from longest suit */
function _leadFromLongest(suitCards, legalCards) {
  let bestSuit = null;
  let bestLen = 0;
  for (const [suit, cards] of Object.entries(suitCards)) {
    if (cards.length > bestLen) { bestLen = cards.length; bestSuit = suit; }
  }

  if (bestSuit && suitCards[bestSuit].length > 0) {
    return suitCards[bestSuit].sort((a, b) =>
      RANK_ORDER[getCardInfo(b).rank] - RANK_ORDER[getCardInfo(a).rank])[0];
  }

  return legalCards[0];
}

// ═══════════════════════════════════════════════════════════
//  TRICK PLAY — FOLLOWING
// ═══════════════════════════════════════════════════════════

function decideFollowCard(game, botId, legalCards) {
  const mightyCard = game.getMightyCard();
  const currentWinner = getCurrentTrickWinner(game);
  const botIsGov = isGovernmentSelf(game, botId);
  const winnerIsGov = isGovernment(game, currentWinner);
  const winningCards = legalCards.filter(cardId => canBeatCurrentWinner(game, cardId));

  // First-trick-friend (초구 프렌즈): the first-trick winner becomes declarer's
  // partner. If the bot isn't the declarer, it actively tries to win the first
  // trick whenever it holds an effective-top A-equivalent or is the last player
  // able to take the pot. This overrides the usual "conserve mighty" logic.
  if (game.friendCard === 'first_trick' && game.tricks.length === 0
      && botId !== game.declarer && winningCards.length > 0) {
    const isLastPlayer = game.currentTrick.length === game.activePlayerCount - 1;
    const sureWinners = winningCards.filter(c => _isEffectiveTopOfSuit(c, game));
    if (sureWinners.length > 0) return getWeakestCard(sureWinners, game);
    if (isLastPlayer) return getWeakestCard(winningCards, game);
  }

  const winnerOnOurTeam = botIsGov
    ? winnerIsGov
    : (game.friendRevealed ? !winnerIsGov : currentWinner !== game.declarer);

  const pick = botIsGov
    ? governmentFollow(game, botId, legalCards, winningCards, currentWinner, winnerOnOurTeam, mightyCard)
    : oppositionFollow(game, botId, legalCards, winningCards, currentWinner, winnerOnOurTeam, mightyCard);

  // Joker-endgame override (penultimate trick): the last trick uses a weak
  // joker by default, so whatever the follow logic picked now, hoarding
  // joker into trick N means it auto-loses. If joker is still in legal
  // cards and can beat the current trick, play it here instead — even if
  // the natural pick was a safe dump. Losing the last trick is cheaper
  // than wasting joker outright, and winning an "extra" trick can only
  // help (declarer team collects, opp team denies declarer).
  if (pick && pick !== 'mighty_joker' && legalCards.includes('mighty_joker')
      && winningCards.includes('mighty_joker')) {
    const totalTricks = Math.floor(50 / (game.activePlayerCount || game.playerCount));
    const nextIsLast = game.tricks.length === totalTricks - 2;
    if (nextIsLast && !game.options.lastTrickJokerPower) {
      return 'mighty_joker';
    }
  }
  return pick;
}

function governmentFollow(game, botId, legalCards, winningCards, currentWinner, winnerOnOurTeam, mightyCard) {
  const oppBehind = hasOppositionBehind(game, botId);
  const isFriend = _isFriend(game, botId);
  const declarerLed = game.currentTrick.length > 0 && game.currentTrick[0].pid === game.declarer;
  const trickPoints = getTrickPointCount(game);
  const isLastPlayer = game.currentTrick.length === (game.activePlayerCount || game.playerCount) - 1;
  const isNT = !game.trumpSuit || game.trumpSuit === 'no_trump';
  // Friend bots preserve their effective tops while dumping; declarer keeps
  // the original behaviour (free to dump anything since they're collecting
  // points, not lead opportunities).
  const dumpSafe = isFriend ? pickSafeDumpKeepingTops : pickSafeDump;

  // ─── Friend responding to declarer's lead ───
  if (isFriend && declarerLed) {
    if (!winnerOnOurTeam) {
      // Declarer is LOSING → rescue with the MINIMUM sufficient winning card
      // (never burn mighty/joker when a trump ruff or lead-suit A would do)
      if (winningCards.length > 0) {
        return pickSufficientWinner(winningCards, game, isLastPlayer, oppBehind);
      }
      // Can't win — dump the safest card (no points, no trump)
      return getSafeDiscard(legalCards, game);
    }
    // Declarer is winning. If their card is an effective top (e.g., non-trump A), it will
    // almost always hold — just dump a non-trump point card. Don't trump-ruff our own ace,
    // and don't burn the joker just to reveal the partnership.
    const winnerCard = getWinnerCardId(game);
    const declarerSecure = _isEffectiveTopOfSuit(winnerCard, game);

    // Joker-friend safe-window reveal: when declarer's lead is TRULY
    // unbeatable AND joker has power on this trick, joker can be cashed
    // for partnership reveal — joker is collected by declarer either way
    // (mighty beats joker), so we trade joker's future taking utility
    // for the immediate reveal AND a dodge of 조커콜.
    //
    // Gating:
    //   - joker must have power on this trick. On trick 1 / last trick
    //     (default options) joker can't take anything anyway, so burning
    //     it as a "reveal" is just waste — the trick goes to declarer
    //     regardless of which card we drop. Save joker for a powered
    //     trick where it might still take.
    //   - declarer's lead must be truly unbeatable: mighty led, OR bot
    //     is the last player and declarer is currently winning. Plain
    //     effective-top A leads can still be over-ruffed mid-trick.
    //   - trump-active only. NT joker is too valuable.
    const trumpActiveForReveal = game.trumpSuit && game.trumpSuit !== 'no_trump';
    const jokerHasPower = typeof game._currentTrickJokerHasPower === 'function'
      && game._currentTrickJokerHasPower();
    const mightyLed = winnerCard === mightyCard;
    const safeRevealWindow = (mightyLed || isLastPlayer) && jokerHasPower;
    if (safeRevealWindow
        && trumpActiveForReveal
        && game.friendCard === 'mighty_joker'
        && !game.friendRevealed
        && legalCards.includes('mighty_joker')) {
      return 'mighty_joker';
    }

    if (declarerSecure) {
      return dumpSafe(legalCards, game);
    }
    // Joker-friend reveal: when our friend card IS the joker, the only way
    // to surface the partnership is to play it. Declarer led a non-top card,
    // joker is legal (joker bypasses suit-follow), and joker beats everything
    // except mighty — `winningCards.includes('mighty_joker')` already filters
    // out first/last-trick weak-joker windows AND mighty-on-table windows.
    // Cashing it here trades the joker for an immediate reveal so the team
    // can coordinate the rest of the round.
    if (game.friendCard === 'mighty_joker'
        && !game.friendRevealed
        && legalCards.includes('mighty_joker')
        && winningCards.includes('mighty_joker')) {
      return 'mighty_joker';
    }
    // Declarer led a non-top card (e.g., ♥10 while ♥J/Q/K/A are still unplayed)
    // and opp is still behind. If we don't cover, opp will cascade their point
    // cards onto this trick. Reinforce with a GUARANTEED winner — A of the
    // lead suit first, else mighty/joker. A cheap-trump ruff isn't good
    // enough here: opp behind can still over-trump it, whereas declarer is
    // explicitly trusting the friend to secure this trick. Only fall back to
    // the cheap-ruff path (via pickSufficientWinner) when no guaranteed
    // finisher is available.
    // Exception: trump leads are usually intentional trump-draws; duck with
    // a low trump instead of burning mighty.
    const leadCard = game.currentTrick[0].cardId;
    const leadIsTrump = leadCard === 'mighty_joker' ||
      (game.trumpSuit && game.trumpSuit !== 'no_trump' &&
       getCardInfo(leadCard).suit === game.trumpSuit);

    if (winningCards.length > 0) {
      // "끝까지 이김" check: only commit to a winner if it survives the rest
      // of the trick. Priority — same suit > trump > joker > mighty. The
      // safety filter applies to BOTH non-trump and trump leads (a trump
      // mid-rank can be over-cut by a higher trump just like a side-suit Q
      // can be over-cut by K/A).
      const leadSuit = leadCard === 'mighty_joker'
        ? game.jokerSuitDeclared
        : getCardInfo(leadCard).suit;
      const trump = game.trumpSuit;
      const trumpActive = trump && trump !== 'no_trump';

      if (leadSuit) {
        const safeSameSuit = winningCards.filter(c => {
          if (c === mightyCard || c === 'mighty_joker') return false;
          return getCardInfo(c).suit === leadSuit && _isSafeFriendWinner(c, game, botId);
        });
        if (safeSameSuit.length > 0) return getWeakestCard(safeSameSuit, game);
      }

      if (trumpActive && leadSuit !== trump) {
        const safeTrump = winningCards.filter(c => {
          if (c === mightyCard || c === 'mighty_joker') return false;
          return getCardInfo(c).suit === trump && _isSafeFriendWinner(c, game, botId);
        });
        if (safeTrump.length > 0) return getWeakestCard(safeTrump, game);
      }

      if (winningCards.includes('mighty_joker')
          && _isSafeFriendWinner('mighty_joker', game, botId)) {
        return 'mighty_joker';
      }
      if (winningCards.includes(mightyCard) && oppBehind) return mightyCard;
      // No safe winner against opp-behind cut risk → concede cleanly.
    }
    return getSafeDiscard(legalCards, game);
  }

  if (winnerOnOurTeam) {
    // Ally winning, no one behind → safe to pile on points
    if (!oppBehind) {
      return dumpSafe(legalCards, game);
    }

    const winnerCard = getWinnerCardId(game);
    const isSecure = winnerCard === mightyCard || winnerCard === 'mighty_joker' ||
      _isEffectiveTopOfSuit(winnerCard, game) ||
      (!isNT && winnerCard && getCardInfo(winnerCard).suit === game.trumpSuit &&
       getCardInfo(winnerCard).rank === 'A') ||
      _winnerCardWillHold(game, botId);

    if (isSecure) {
      return dumpSafe(legalCards, game);
    }

    // Unsecure ally: reinforce on valuable tricks OR when safe-discard would
    // still hand opp a point card
    if (winningCards.length > 0) {
      // Guard: don't over-reinforce with mighty/joker when the ally is already
      // winning with a strong trump ruff (J+). Only mighty / higher trump can
      // beat it, and burning a specials-tier finisher (and, if the friend card
      // is the joker, revealing the partnership) isn't worth the marginal
      // insurance on a trick declarer is already taking.
      const cheap = winningCards.filter(c => c !== mightyCard && c !== 'mighty_joker');
      if (cheap.length === 0 && !isNT && winnerCard
          && winnerCard !== mightyCard && winnerCard !== 'mighty_joker') {
        const winnerInfo = getCardInfo(winnerCard);
        if (winnerInfo.suit === game.trumpSuit &&
            RANK_ORDER[winnerInfo.rank] >= RANK_ORDER['J']) {
          return dumpSafe(legalCards, game);
        }
      }
      if (isNT || trickPoints >= 2 || isLastPlayer) {
        return pickSufficientWinner(winningCards, game, isLastPlayer, oppBehind);
      }
      const safe = getSafeDiscard(legalCards, game);
      if (getCardInfo(safe).point > 0) {
        return pickSufficientWinner(winningCards, game, isLastPlayer, oppBehind);
      }
      return safe;
    }
    return getSafeDiscard(legalCards, game);
  }

  // ─── Enemy winning ───
  if (winningCards.length > 0) {
    if (!isNT && trickPoints <= 1 && !isLastPlayer) {
      // Suited low-value: don't waste mighty/joker
      const cheapWinners = winningCards.filter(c => c !== mightyCard && c !== 'mighty_joker');
      if (cheapWinners.length > 0) {
        return oppBehind ? getStrongestCard(cheapWinners, game) : getWeakestCard(cheapWinners, game);
      }
      return getNonPointWeakest(legalCards, game);
    }
    return pickSufficientWinner(winningCards, game, isLastPlayer, oppBehind);
  }

  return getNonPointWeakest(legalCards, game);
}

function oppositionFollow(game, botId, legalCards, winningCards, currentWinner, winnerOnOurTeam, mightyCard) {
  const govBehind = hasGovernmentBehind(game, botId);
  const trickPoints = getTrickPointCount(game);
  const isLastPlayer = game.currentTrick.length === (game.activePlayerCount || game.playerCount) - 1;
  const govPoints = _getGovernmentPointCount(game);
  const bidTarget = game.currentBid.points;
  const isNT = !game.trumpSuit || game.trumpSuit === 'no_trump';

  if (!winnerOnOurTeam) {
    // Government is winning

    // End-game: if government already has enough points, don't waste good cards
    if (govPoints >= bidTarget && trickPoints === 0) {
      return getNonPointWeakest(legalCards, game);
    }

    // Critical endgame override: 2 or fewer tricks remain AND declarer
    // hasn't made bid yet. Every trick declarer takes here could lock in
    // success, so spend any winner we have — including mighty/joker on a
    // 0-point trick. Hoarding specials through the final tricks just lets
    // government mop up.
    if (_oppCriticalEndgame(game) && winningCards.length > 0) {
      return pickSufficientWinner(winningCards, game, isLastPlayer, govBehind);
    }

    // Joker snipe: use joker on high-value tricks
    if (legalCards.includes('mighty_joker') && trickPoints >= 2 &&
        canBeatCurrentWinner(game, 'mighty_joker')) {
      return 'mighty_joker';
    }

    if (isNT) {
      if (winningCards.length > 0) {
        return pickSufficientWinner(winningCards, game, isLastPlayer, govBehind);
      }
      return getNonPointWeakest(legalCards, game);
    }

    // ═══ SUITED: conserve trump and specials ═══
    if (trickPoints === 0 && !govBehind) {
      return getNonPointWeakest(legalCards, game);
    }

    // Don't waste trump on pointless tricks
    if (trickPoints === 0 && winningCards.length > 0) {
      const nonTrumpWinners = winningCards.filter(c => {
        if (c === 'mighty_joker') return false;
        const info = getCardInfo(c);
        return info.suit !== game.trumpSuit;
      });
      if (nonTrumpWinners.length > 0) return getWeakestCard(nonTrumpWinners, game);
      return getNonPointWeakest(legalCards, game);
    }

    // Don't waste mighty/joker on low-value tricks unless last player
    if (trickPoints <= 1 && !isLastPlayer && winningCards.length > 0) {
      const cheapWinners = winningCards.filter(c => c !== mightyCard && c !== 'mighty_joker');
      if (cheapWinners.length > 0) return getWeakestCard(cheapWinners, game);
      return getNonPointWeakest(legalCards, game);
    }

    if (winningCards.length > 0) return pickSufficientWinner(winningCards, game, isLastPlayer, govBehind);
    return getNonPointWeakest(legalCards, game);
  }

  // ─── Our team (opposition ally) is winning ───
  // NEVER trump-steal an ally's already-winning trick. Dump safely.
  if (!govBehind) {
    return pickSafeDump(legalCards, game);
  }

  const winnerCard = getWinnerCardId(game);
  const isSecure = winnerCard === mightyCard || winnerCard === 'mighty_joker' ||
    _isEffectiveTopOfSuit(winnerCard, game);

  if (isSecure) {
    return pickSafeDump(legalCards, game);
  }

  // Ally not secure — reinforce on valuable tricks OR when safe-discard would
  // hand over a point card
  if (winningCards.length > 0) {
    // Symmetric to governmentFollow: don't over-reinforce with mighty/joker
    // when the ally is already on a strong trump ruff (J+); only mighty / top
    // trump can overcut, and burning our finisher for that marginal insurance
    // isn't worth it.
    const cheap = winningCards.filter(c => c !== mightyCard && c !== 'mighty_joker');
    if (cheap.length === 0 && !isNT && winnerCard
        && winnerCard !== mightyCard && winnerCard !== 'mighty_joker') {
      const winnerInfo = getCardInfo(winnerCard);
      if (winnerInfo.suit === game.trumpSuit &&
          RANK_ORDER[winnerInfo.rank] >= RANK_ORDER['J']) {
        return pickSafeDump(legalCards, game);
      }
    }
    if (trickPoints >= 2 || isLastPlayer || isNT) {
      return pickSufficientWinner(winningCards, game, isLastPlayer, govBehind);
    }
    const safe = getSafeDiscard(legalCards, game);
    if (getCardInfo(safe).point > 0) {
      return pickSufficientWinner(winningCards, game, isLastPlayer, govBehind);
    }
    return safe;
  }
  return getSafeDiscard(legalCards, game);
}

// ═══════════════════════════════════════════════════════════
//  TRICK EVALUATION
// ═══════════════════════════════════════════════════════════

function getCurrentTrickWinner(game) {
  if (game.currentTrick.length === 0) return null;

  const mightyCard = game.getMightyCard();
  const leadCard = game.currentTrick[0].cardId;
  const leadSuit = leadCard === 'mighty_joker' ? game.jokerSuitDeclared : getCardInfo(leadCard).suit;
  const isFirstTrick = game.tricks.length === 0;
  const totalTricks = Math.floor(50 / (game.activePlayerCount || game.playerCount));
  const isLastTrick = game.tricks.length === totalTricks - 1;
  const jokerCallCard = game.getJokerCallCard();
  const jokerIsWeak = (isFirstTrick && !game.options.firstTrickJokerPower) ||
    (isLastTrick && !game.options.lastTrickJokerPower) ||
    (leadCard === jokerCallCard && game.jokerCallActive);

  let bestPlay = null;
  let bestPriority = -1;

  for (const play of game.currentTrick) {
    const priority = game._getCardPriority(play.cardId, leadSuit, jokerIsWeak, mightyCard);
    if (priority > bestPriority) { bestPriority = priority; bestPlay = play; }
  }

  return bestPlay ? bestPlay.pid : null;
}

/**
 * Perfect-info safety check: will the currently winning card survive
 * the rest of the trick? Scans every opp seat that hasn't played yet
 * for any card that could beat the current winner. Used by friend's
 * follow logic so we don't burn mighty/joker reinforcing a trick that
 * was always going to hold anyway.
 */
function _winnerCardWillHold(game, botId) {
  const winnerCard = getWinnerCardId(game);
  if (!winnerCard) return false;
  const playedPids = new Set((game.currentTrick || []).map(p => p.pid));
  const botIsGov = isGovernmentSelf(game, botId);
  for (const pid of game.playerIds) {
    if (pid === botId) continue;
    if (playedPids.has(pid)) continue;
    if (game.excludedPlayers && game.excludedPlayers.has(pid)) continue;
    if (isGovernmentSelf(game, pid) === botIsGov) continue;
    const legal = new Set(game.getLegalCards(pid) || []);
    const hand = game.hands[pid] || [];
    for (const cardId of hand) {
      if (legal.has(cardId) && canBeatCurrentWinner(game, cardId)) return false;
    }
  }
  return true;
}

function canBeatCurrentWinner(game, cardId) {
  const mightyCard = game.getMightyCard();
  if (cardId === mightyCard) return true;

  const leadCard = game.currentTrick[0].cardId;
  const leadSuit = leadCard === 'mighty_joker' ? game.jokerSuitDeclared : getCardInfo(leadCard).suit;
  const isFirstTrick = game.tricks.length === 0;
  const totalTricks = Math.floor(50 / (game.activePlayerCount || game.playerCount));
  const isLastTrick = game.tricks.length === totalTricks - 1;
  const jokerCallCard = game.getJokerCallCard();
  const jokerIsWeak = (isFirstTrick && !game.options.firstTrickJokerPower) ||
    (isLastTrick && !game.options.lastTrickJokerPower) ||
    (leadCard === jokerCallCard && game.jokerCallActive);

  const cardPriority = game._getCardPriority(cardId, leadSuit, jokerIsWeak, mightyCard);

  let bestPriority = -1;
  for (const play of game.currentTrick) {
    const p = game._getCardPriority(play.cardId, leadSuit, jokerIsWeak, mightyCard);
    if (p > bestPriority) bestPriority = p;
  }

  return cardPriority > bestPriority;
}

function getWinnerCardId(game) {
  const mightyCard = game.getMightyCard();
  const leadCard = game.currentTrick[0].cardId;
  const leadSuit = leadCard === 'mighty_joker' ? game.jokerSuitDeclared : getCardInfo(leadCard).suit;
  const isFirstTrick = game.tricks.length === 0;
  const totalTricks = Math.floor(50 / (game.activePlayerCount || game.playerCount));
  const isLastTrick = game.tricks.length === totalTricks - 1;
  const jokerCallCard = game.getJokerCallCard();
  const jokerIsWeak = (isFirstTrick && !game.options.firstTrickJokerPower) ||
    (isLastTrick && !game.options.lastTrickJokerPower) ||
    (leadCard === jokerCallCard && game.jokerCallActive);

  let bestPlay = null;
  let bestPriority = -1;
  for (const play of game.currentTrick) {
    const priority = game._getCardPriority(play.cardId, leadSuit, jokerIsWeak, mightyCard);
    if (priority > bestPriority) { bestPriority = priority; bestPlay = play; }
  }
  return bestPlay ? bestPlay.cardId : null;
}

// ═══════════════════════════════════════════════════════════
//  CARD ANALYSIS HELPERS
// ═══════════════════════════════════════════════════════════

/** Check if a player is the friend (even before reveal, by checking hand) */
function _isFriend(game, playerId) {
  if (playerId === game.declarer) return false;
  if (game.friendRevealed && playerId === game.partner) return true;
  if (!game.friendRevealed && game.friendCard && game.friendCard !== 'no_friend' && game.friendCard !== 'first_trick') {
    const hand = game.hands[playerId] || [];
    if (hand.includes(game.friendCard)) return true;
  }
  return false;
}

/**
 * Check if a card is the effective top of its suit.
 * Considers: mighty removal, and whether higher cards have already been played.
 */
function _isEffectiveTopOfSuit(cardId, game) {
  if (!cardId) return false;
  const mightyCard = game.getMightyCard();
  if (cardId === mightyCard) return true;
  if (cardId === 'mighty_joker') return true;

  const info = getCardInfo(cardId);
  const played = _getPlayedCards(game);

  const rankOrder = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];
  const myRankIdx = rankOrder.indexOf(info.rank);

  for (let i = rankOrder.length - 1; i > myRankIdx; i--) {
    const higherCardId = `mighty_${info.suit}_${rankOrder[i]}`;
    if (higherCardId === mightyCard) continue;
    if (!played.has(higherCardId)) return false;
  }

  return true;
}

/** Declarer's actual strongest continuation side-suit under full information. */
function _declarerStrongSuit(game) {
  const hand = game.hands[game.declarer] || [];
  if (hand.length === 0) return null;

  const mightyCard = game.getMightyCard();
  let bestSuit = null;
  let bestScore = -Infinity;

  for (const suit of SUITS) {
    if (suit === game.trumpSuit) continue;
    const cards = hand.filter(cardId => {
      if (cardId === 'mighty_joker' || cardId === mightyCard) return false;
      const info = getCardInfo(cardId);
      return info?.suit === suit;
    });
    if (cards.length === 0) continue;

    const sorted = cards.sort((a, b) =>
      (RANK_ORDER[getCardInfo(b).rank] || 0) - (RANK_ORDER[getCardInfo(a).rank] || 0));
    const top = sorted[0];
    let score = cards.length * 12 + (RANK_ORDER[getCardInfo(top).rank] || 0);
    if (_isEffectiveTopOfSuit(top, game)) score += 100;
    if (cards.length > 1 && _isEffectiveTopOfSuit(sorted[1], game)) score += 30;

    if (score > bestScore) {
      bestScore = score;
      bestSuit = suit;
    }
  }

  return bestSuit;
}

/** How many tricks have led with this suit (including in-progress current trick). */
function _suitLedCount(game, suit) {
  if (!suit) return 0;
  let count = 0;
  const consider = (trick) => {
    if (!trick?.leadCardId) return;
    const leadSuit = trick.leadSuit
      || (trick.leadCardId === 'mighty_joker' ? game.jokerSuitDeclared : null);
    if (leadSuit) {
      if (leadSuit === suit) count++;
      return;
    }
    const info = getCardInfo(trick.leadCardId);
    if (info?.suit === suit) count++;
  };
  for (const t of (game.tricks || [])) {
    if (t.cards && t.cards.length > 0) {
      consider({
        leadCardId: t.cards[0].cardId,
        leadSuit: t.leadSuit,
      });
    }
  }
  if (game.currentTrick.length > 0) {
    const leadCardId = game.currentTrick[0].cardId;
    consider({
      leadCardId,
      leadSuit: leadCardId === 'mighty_joker'
        ? game.jokerSuitDeclared
        : getCardInfo(leadCardId).suit,
    });
  }
  return count;
}

/** Will `cardId`, played now, survive the rest of the trick against actual legal opponent replies? */
function _isSafeFriendWinner(cardId, game, botId) {
  if (!game.currentTrick || game.currentTrick.length === 0) return false;
  const legal = game.getLegalCards(botId) || [];
  if (!legal.includes(cardId)) return false;

  const world = game.clone();
  const action = makePlayAction(cardId, world, botId);
  const result = world.handleAction(botId, action);
  if (!result || !result.success) return false;

  // Trick closed immediately, so nobody is left to answer.
  if (world.state === 'trick_end' || world.state === 'round_end' || world.state === 'game_end') {
    return true;
  }

  const currentWinner = getCurrentTrickWinner(world);
  if (currentWinner !== botId) return false;

  const botIsGov = isGovernmentSelf(world, botId);
  const remaining = getRemainingPlayers(world, botId);
  for (const pid of remaining) {
    if (isGovernmentSelf(world, pid) === botIsGov) continue;
    const oppLegal = world.getLegalCards(pid) || [];
    for (const oppCard of oppLegal) {
      if (canBeatCurrentWinner(world, oppCard)) return false;
    }
  }

  return true;
}

/** Get the suit of the friend-declared card */
function _getFriendCardSuit(game) {
  if (!game.friendCard || game.friendCard === 'no_friend' || game.friendCard === 'first_trick') {
    return null;
  }
  if (game.friendCard === 'mighty_joker') return null;
  const info = getCardInfo(game.friendCard);
  return info.suit || null;
}

/**
 * Mighty-friends variant: the bot's hidden friend identity is revealed
 * the moment the Mighty is played (since friendCard === mightyCard).
 * Leading with Mighty on a trick-start blows that cover AND burns the
 * card on a trick we were already going to win — hold it for a follow
 * play instead. Only applies when the bot still has at least one
 * alternative legal card; if Mighty is the only legal play, play it.
 */
function _shouldHoldMightyInMightyFriends(game, legalCards) {
  const mightyCard = game.getMightyCard();
  if (game.friendCard !== mightyCard) return false;
  if (game.friendRevealed) return false;
  if (!legalCards.includes(mightyCard)) return false;
  return legalCards.length > 1;
}

/**
 * Revealed-friend + no-trump-in-hand + Mighty-still-live heuristic:
 * spade is the Mighty's home suit, so leading a high spade tends to
 * force the declarer to burn Mighty on our trick (we were already
 * winning it for the government). Strip spade from the lead pool when
 * any non-spade alternative exists. No-op when we have trump cards
 * (trump leads take priority anyway) or when Mighty has already been
 * played. Does not fire in the Mighty-friends variant since friend is
 * revealed exactly when Mighty is played, which contradicts the
 * "Mighty still live" side of this guard.
 */
function _shouldAvoidSpadeLead(game, botId, suitCards, mightyCard) {
  if (!game.friendRevealed || botId !== game.partner) return false;
  const hasTrumpInHand = game.trumpSuit && game.trumpSuit !== 'no_trump'
    && (suitCards[game.trumpSuit] || []).length > 0;
  if (hasTrumpInHand) return false;
  const played = _getPlayedCards(game);
  if (played.has(mightyCard)) return false;
  const spadeCards = suitCards.spade || [];
  if (spadeCards.length === 0) return false;
  for (const [suit, cards] of Object.entries(suitCards)) {
    if (suit !== 'spade' && cards.length > 0) return true;
  }
  return false;
}

/** Check if only government still hold trump cards */
function _onlyGovernmentHasTrump(game) {
  if (!game.trumpSuit || game.trumpSuit === 'no_trump') return false;
  for (const pid of game.playerIds) {
    if (pid === game.declarer || pid === game.partner) continue;
    const hand = game.hands[pid] || [];
    for (const cardId of hand) {
      if (cardId === 'mighty_joker') continue;
      const info = getCardInfo(cardId);
      if (info.suit === game.trumpSuit) return false;
    }
  }
  return true;
}

/**
 * Variant of _onlyGovernmentHasTrump that also excludes `selfPid` — needed by
 * the friend bot pre-reveal, where `game.partner` is still null but the bot
 * itself knows it is part of government and should not count its own trumps
 * as opposition trumps.
 */
function _noRealOppTrumpLeft(game, selfPid) {
  if (!game.trumpSuit || game.trumpSuit === 'no_trump') return false;
  const selfIsGov = isGovernmentSelf(game, selfPid);
  for (const pid of game.playerIds) {
    if (pid === selfPid) continue;
    if (isGovernmentSelf(game, pid) === selfIsGov) continue;
    const hand = game.hands[pid] || [];
    for (const cardId of hand) {
      if (cardId === 'mighty_joker') continue;
      const info = getCardInfo(cardId);
      if (info.suit === game.trumpSuit) return false;
    }
  }
  return true;
}

/** Suits that have already appeared as the lead card of any completed trick.
 *  Used by friend-bot lead heuristics to avoid recycling a suit that the
 *  table has already seen.
 */
function _suitsAlreadyLed(game) {
  const out = new Set();
  for (const t of game.tricks || []) {
    if (!t.cards || t.cards.length === 0) continue;
    if (t.leadSuit) {
      out.add(t.leadSuit);
      continue;
    }
    const info = getCardInfo(t.cards[0].cardId);
    if (info?.suit) out.add(info.suit);
  }
  return out;
}

/** Lead suit of the very first trick of the round, or null if not played
 *  yet / lead was a joker without a declared suit.
 */
function _firstTrickLeadSuit(game) {
  if (!game.tricks || game.tricks.length === 0) return null;
  const t = game.tricks[0];
  if (!t.cards || t.cards.length === 0) return null;
  if (t.leadSuit) return t.leadSuit;
  const info = getCardInfo(t.cards[0].cardId);
  return info?.suit || null;
}

/** Find a sure-winner top card (non-trump A that hasn't been played) */
function _getTopWinnerFromHand(legalCards, suitCards, game) {
  for (const [suit, cards] of Object.entries(suitCards)) {
    if (suit === game.trumpSuit) continue;
    const sorted = cards.sort((a, b) =>
      RANK_ORDER[getCardInfo(b).rank] - RANK_ORDER[getCardInfo(a).rank]);
    if (_isEffectiveTopOfSuit(sorted[0], game)) return sorted[0];
  }
  return null;
}

// ═══════════════════════════════════════════════════════════
//  PLAY ACTION BUILDER
// ═══════════════════════════════════════════════════════════

function makePlayAction(cardId, game, botId) {
  const action = { type: 'play_card', cardId };

  if (cardId === 'mighty_joker' && game.currentTrick.length === 0) {
    action.jokerSuit = _pickJokerLeadSuit(game, botId);
  }

  // Joker call: when leading with joker-call card, activate to force joker out.
  // NEVER joker-call in no-trump — joker is too valuable, don't waste tempo.
  // Also skip when joker has no power in this trick (first/last-trick power
  // option disabled) — calling it there has no effect.
  if (game.currentTrick.length === 0 && cardId === game.getJokerCallCard()) {
    if (game.trumpSuit && game.trumpSuit !== 'no_trump'
        && game._currentTrickJokerHasPower()) {
      action.jokerCall = true;
    }
  }

  return action;
}

/** Pick the best suit to declare when leading joker.
 *  Prefer suits where opponents still hold cards (so they have to follow and
 *  waste real material) and where we have follow-up strength. Avoid declaring
 *  trump when only government (and friend) still hold trump — that just lets
 *  opponents discard junk. Fall back to trump only if nothing else works.
 */
/**
 * Pick the suit to declare when leading joker.
 *
 * Goal (per user spec): pick the suit where we can KEEP winning after the
 * joker takes its trick. Joker isn't a one-trick winner — it's a "lead-
 * retaining and continuation" card.
 *
 * Scoring components, by priority:
 *   1. Continuation: do we hold the effective top of the suit (or the
 *      second-top with the top out)? That guarantees we win the very
 *      next lead in that suit.
 *   2. Length: more cards in suit means we can keep cashing it.
 *   3. Forces opp to spend: opp must hold the suit (otherwise the joker
 *      call just hands them free discards — explicitly forbidden).
 *   4. Trump-suit handling: only call trump while opp still has trump.
 *      A trump-dead joker call is wasted tempo (opp dumps junk).
 *   5. Government-side flush: when we're government and the friend-card
 *      suit (기루) still has lots of cards outside our hand AND opp
 *      holds it, drain that suit first.
 */
function _pickJokerLeadSuit(game, botId) {
  const hand = game.hands[botId] || [];
  const trump = game.trumpSuit && game.trumpSuit !== 'no_trump' ? game.trumpSuit : null;
  const trumpDead = trump ? _noRealOppTrumpLeft(game, botId) : false;
  const mightyCard = game.getMightyCard();

  // Which suits do players on the opposing team still hold?
  const oppHoldsSuit = {};
  for (const suit of SUITS) oppHoldsSuit[suit] = false;
  const botIsGov = isGovernmentSelf(game, botId);
  for (const pid of game.playerIds) {
    if (pid === botId) continue;
    if (isGovernmentSelf(game, pid) === botIsGov) continue;
    const h = game.hands[pid] || [];
    for (const cid of h) {
      if (cid === 'mighty_joker') continue;
      const info = getCardInfo(cid);
      if (info.suit) oppHoldsSuit[info.suit] = true;
    }
  }

  // Per-suit hand inventory (skip mighty/joker).
  const suitCards = {};
  for (const suit of SUITS) suitCards[suit] = [];
  for (const cardId of hand) {
    if (cardId === 'mighty_joker') continue;
    if (cardId === mightyCard) continue;
    const info = getCardInfo(cardId);
    if (info.suit) suitCards[info.suit].push(cardId);
  }

  const suitScore = {};
  for (const suit of SUITS) {
    const cards = suitCards[suit];
    let score = 0;

    // Continuation — the most important factor. After the joker takes
    // this trick, can we lead the suit again and still win?
    let hasTop = false;
    let hasSecondTop = false;
    if (cards.length > 0) {
      const sorted = [...cards].sort((a, b) =>
        (RANK_ORDER[getCardInfo(b).rank] || 0) - (RANK_ORDER[getCardInfo(a).rank] || 0));
      const top = sorted[0];
      hasTop = _isEffectiveTopOfSuit(top, game);
      if (!hasTop && sorted.length > 1) {
        // Tentatively assume the top card pulls out via the joker call;
        // if our second-highest then becomes the post-trick effective
        // top (no other higher unaccounted card), count it as a top.
        hasSecondTop = _isEffectiveTopOfSuit(sorted[1], game)
          // OR: my #1 is just below the absolute top, and a higher
          // card (likely the A) hasn't been played yet — then we
          // hope the joker call burns it. Approximate as:
          || (RANK_ORDER[getCardInfo(top).rank] >= RANK_ORDER['Q']);
      }
    }
    if (hasTop) score += 200;
    else if (hasSecondTop) score += 100;
    else if (cards.length > 0) score += 20;
    // else: no card in suit — bot can't continue at all → no bonus

    // Length: more cards = more continuation tricks.
    score += cards.length * 8;

    // Forces opp to spend. No opp in suit = forbidden "안전한 문양"
    // (free discards for opp) — heavy penalty.
    if (oppHoldsSuit[suit]) {
      score += 30;
    } else {
      score -= 200;
    }

    // Trump-suit specifics.
    if (suit === trump) {
      if (trumpDead) score -= 100;
    }

    suitScore[suit] = score;
  }

  // Known-void boosts (forced discards from those seats).
  const voids = _getKnownVoids(game);
  for (const pid of game.playerIds) {
    if (pid === botId) continue;
    for (const suit of (voids[pid] || [])) suitScore[suit] += 3;
  }

  // Government flush: 기루 still rich + opp still holds it → drain it.
  const friendCardSuit = _getFriendCardSuit(game);
  const isGovernment = botId === game.declarer || _isFriend(game, botId);
  if (isGovernment && friendCardSuit && oppHoldsSuit[friendCardSuit]
      && _countCardsInSuitOutsideHand(game, botId, friendCardSuit) >= 5) {
    suitScore[friendCardSuit] += 200;
  }

  let bestSuit = null;
  let bestScore = -Infinity;
  for (const [suit, score] of Object.entries(suitScore)) {
    if (score > bestScore) { bestScore = score; bestSuit = suit; }
  }
  if (!bestSuit) bestSuit = trump || 'spade';
  return bestSuit;
}

module.exports = {
  decideMightyBotAction,
  pickFriendCard,
  // Helpers reused by strategy variants in ./strategies/*.
  groupMightyCardsBySuit,
  chooseKittyDiscards,
  considerTrumpChange,
  makePlayAction,
  getKnownVoids: _getKnownVoids,
  getPlayedCards: _getPlayedCards,
  isFriend: _isFriend,
  isSafeFriendWinner: _isSafeFriendWinner,
  isEffectiveTopOfSuit: _isEffectiveTopOfSuit,
  countOpponentTrumps: _countOpponentTrumps,
  suitLedCount: _suitLedCount,
  canBeatCurrentWinner,
  getCurrentTrickWinner,
  getWinnerCardId,
  noRealOppTrumpLeft: _noRealOppTrumpLeft,
  hasOppositionBehind,
  declarerStrongSuit: _declarerStrongSuit,
  getFriendCardSuit: _getFriendCardSuit,
  winnerCardWillHold: _winnerCardWillHold,
};
