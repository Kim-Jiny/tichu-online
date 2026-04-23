'use strict';

const { getCardInfo, RANK_ORDER, SUITS } = require('./MightyDeck');

/**
 * Decide the next action for a Mighty bot.
 * Returns an action object or null if no action needed.
 */
function decideMightyBotAction(game, botId) {
  if (!game || !game.playerIds.includes(botId)) return null;

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

  const analyzeTrick = (cards) => {
    if (cards.length < 2) return;
    const leadCard = cards[0].cardId;
    if (leadCard === 'mighty_joker') return;
    const leadSuit = getCardInfo(leadCard).suit;

    for (let i = 1; i < cards.length; i++) {
      const play = cards[i];
      if (play.cardId === 'mighty_joker' || play.cardId === mightyCard) continue;
      if (getCardInfo(play.cardId).suit !== leadSuit) {
        voids[play.pid].add(leadSuit);
      }
    }
  };

  for (const trick of game.tricks) analyzeTrick(trick.cards);
  if (game.currentTrick.length > 1) analyzeTrick(game.currentTrick);

  return voids;
}

/** Count trump cards remaining in OTHER players' hands */
function _countOpponentTrumps(game, botId) {
  if (!game.trumpSuit || game.trumpSuit === 'no_trump') return 0;
  const played = _getPlayedCards(game);
  const myHand = new Set(game.hands[botId] || []);
  const discarded = new Set(game.discarded || []);
  let count = 0;

  for (const rank of ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A']) {
    const cardId = `mighty_${game.trumpSuit}_${rank}`;
    if (!played.has(cardId) && !myHand.has(cardId) && !discarded.has(cardId)) count++;
  }
  if (!played.has('mighty_joker') && !myHand.has('mighty_joker') && !discarded.has('mighty_joker')) count++;
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

  // Count cards of the chosen trump suit (used both for suit vote and for
  // capping how high we dare bid).
  let trumpCount = 0;
  for (const cardId of hand) {
    if (cardId === 'mighty_joker') continue;
    const info = getCardInfo(cardId);
    if (info.suit === bestTrump) trumpCount++;
  }

  let estimatedPoints = Math.min(20, game.options.minBid + Math.floor(strength / 2.5));

  // Trump length cap — long trump stabilises the bid, short trump forces us
  // toward the floor (or into a pass) even with a lot of raw high-card power.
  if (trumpCount <= 3) {
    estimatedPoints = Math.min(estimatedPoints, game.options.minBid);
  } else if (trumpCount === 4) {
    estimatedPoints = Math.min(estimatedPoints, game.options.minBid + 1);
  } else if (trumpCount === 5) {
    estimatedPoints = Math.min(estimatedPoints, game.options.minBid + 2);
  } else if (trumpCount >= 7) {
    estimatedPoints = Math.min(20, estimatedPoints + 1);
  }

  if (estimatedPoints < game.options.minBid || estimatedPoints <= game.currentBid.points) {
    return { type: 'submit_bid', pass: true };
  }

  let suit = bestTrump;

  // No-trump: only in a genuinely dominating hand. Previous criteria
  // (maxLen ≤ 4 && highCards ≥ 4) had a ~6 % success rate in sims.
  // Tightened: require joker or mighty, ≥ 5 A/K, and no long side suit.
  if (game.options.allowNoTrump) {
    const hasJoker = hand.includes('mighty_joker');
    const mightyCardForNT = 'mighty_spade_A'; // in NT, spade A is still mighty
    const hasMighty = hand.includes(mightyCardForNT);
    const suitCounts = {};
    let aceKingCount = 0;
    for (const cardId of hand) {
      if (cardId === 'mighty_joker') continue;
      const info = getCardInfo(cardId);
      suitCounts[info.suit] = (suitCounts[info.suit] || 0) + 1;
      if (info.rank === 'A' || info.rank === 'K') aceKingCount++;
    }
    const maxLen = Math.max(...Object.values(suitCounts), 0);
    if ((hasJoker || hasMighty) && maxLen <= 3 && aceKingCount >= 5) {
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

  if (game.currentBid.points >= 20) {
    if (bestSuit !== currentTrump && bestScore > currentScore + 5) {
      return { type: 'change_trump', suit: bestSuit };
    }
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

  // Group non-protected cards by suit
  const suitGroups = {};
  for (const suit of SUITS) suitGroups[suit] = [];
  for (const cardId of hand) {
    if (protectedCards.has(cardId)) continue;
    const info = getCardInfo(cardId);
    suitGroups[info.suit].push(cardId);
  }

  for (const suit of SUITS) {
    suitGroups[suit].sort((a, b) =>
      (RANK_ORDER[getCardInfo(a).rank] || 0) - (RANK_ORDER[getCardInfo(b).rank] || 0));
  }

  const discards = [];

  // Strategy: discard entire short non-trump suits to create voids
  const shortSuits = SUITS
    .filter(s => s !== trumpSuit && suitGroups[s].length > 0 && suitGroups[s].length <= 3)
    .sort((a, b) => suitGroups[a].length - suitGroups[b].length);

  for (const suit of shortSuits) {
    if (discards.length >= 3) break;
    for (const cardId of suitGroups[suit]) {
      if (discards.length >= 3) break;
      discards.push(cardId);
    }
  }

  // Fill remaining with weakest non-trump, non-protected cards.
  // Trumps are only considered when we genuinely don't have 3 non-trump
  // discardable cards (extreme trump hoarding case).
  if (discards.length < 3) {
    const nonTrumpPool = hand
      .filter(cardId => !protectedCards.has(cardId) && !discards.includes(cardId))
      .filter(cardId => {
        if (trumpSuit === 'no_trump') return true;
        return getCardInfo(cardId).suit !== trumpSuit;
      })
      .map(cardId => {
        const info = getCardInfo(cardId);
        let value = 0;
        if (info.point > 0) value += 30;
        value += RANK_ORDER[info.rank] || 0;
        return { cardId, value };
      })
      .sort((a, b) => a.value - b.value);

    for (const { cardId } of nonTrumpPool) {
      if (discards.length >= 3) break;
      discards.push(cardId);
    }
  }

  // Last-resort trump fallback (only when we have almost no non-trump cards)
  if (discards.length < 3) {
    const trumpPool = hand
      .filter(cardId => !protectedCards.has(cardId) && !discards.includes(cardId))
      .map(cardId => {
        const info = getCardInfo(cardId);
        let value = 0;
        if (info.point > 0) value += 30;
        value += RANK_ORDER[info.rank] || 0;
        return { cardId, value };
      })
      .sort((a, b) => a.value - b.value);
    for (const { cardId } of trumpPool) {
      if (discards.length >= 3) break;
      discards.push(cardId);
    }
  }

  // Pick friend card
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

  // Ensure friend card isn't in discards
  let finalDiscards = discards.filter(c => c !== friendCard);
  if (finalDiscards.length < 3) {
    // Refill preferring non-trump, falling back to trump only if forced
    const eligible = hand
      .filter(cardId => !protectedCards.has(cardId) && !finalDiscards.includes(cardId) && cardId !== friendCard)
      .map(cardId => {
        const info = getCardInfo(cardId);
        const isTrump = trumpSuit !== 'no_trump' && info.suit === trumpSuit;
        return {
          cardId,
          isTrump,
          value: (info.point > 0 ? 30 : 0) + (RANK_ORDER[info.rank] || 0),
        };
      });
    const nonTrumpFirst = [
      ...eligible.filter(e => !e.isTrump).sort((a, b) => a.value - b.value),
      ...eligible.filter(e => e.isTrump).sort((a, b) => a.value - b.value),
    ];
    for (const { cardId } of nonTrumpFirst) {
      if (finalDiscards.length >= 3) break;
      finalDiscards.push(cardId);
    }
  }

  return { type: 'discard_kitty', discards: finalDiscards.slice(0, 3), friendCard };
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

  // Option 1: non-trump Ace. Best when we have a 1-3 card holding in the suit;
  // void or very long suits get penalised (friend's A has less tactical value).
  for (const suit of SUITS) {
    if (suit === trumpSuit) continue;
    const s = suitInfo[suit];
    if (s.hasA) continue;
    const aceId = `mighty_${suit}_A`;
    if (aceId === mightyCard) continue;
    let score = 10;
    if (s.count === 1) score += 5;
    else if (s.count === 2) score += 3;
    else if (s.count === 3) score += 1;
    else if (s.count === 0) score -= 8;   // void: we can't even follow to feed friend's A — strictly worse than 4+ length
    else score -= 3;                      // 4+ suit: our own length already covers it
    if (s.hasK) score += 2;
    candidates.push({ cardId: aceId, score });
  }

  // Option 2: non-trump King where I already hold the Ace. In sims this
  // actually performs worse than other calls, so keep it available but weak —
  // only picked when nothing else scores better.
  for (const suit of SUITS) {
    if (suit === trumpSuit) continue;
    const s = suitInfo[suit];
    if (!s.hasA || s.hasK) continue;
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
    return candidates[0].cardId;
  }

  // Fallback: King of any suit where I lack the K
  for (const suit of SUITS) {
    if (suit === trumpSuit) continue;
    if (!suitInfo[suit].hasK) return `mighty_${suit}_K`;
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
    const pidIsGov = isGovernment(game, pid);
    if (botIsGov !== pidIsGov) return true;
    if (botIsGov && !game.friendRevealed && pid !== game.declarer) return true;
    if (!botIsGov && pid === game.declarer) return true;
  }
  return false;
}

function hasGovernmentBehind(game, botId) {
  const remaining = getRemainingPlayers(game, botId);
  for (const pid of remaining) {
    if (isGovernment(game, pid)) return true;
    if (!game.friendRevealed && pid === game.declarer) return true;
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
function pickSafeDump(legalCards, game) {
  const mightyCard = game.getMightyCard();
  const nonTrumpPoints = legalCards.filter(c => {
    if (c === 'mighty_joker' || c === mightyCard) return false;
    const info = getCardInfo(c);
    return info.point > 0 && info.suit !== game.trumpSuit;
  });
  if (nonTrumpPoints.length > 0) {
    return nonTrumpPoints.sort((a, b) =>
      RANK_ORDER[getCardInfo(b).rank] - RANK_ORDER[getCardInfo(a).rank])[0];
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
  if (legalCards.length === 1) {
    return makePlayAction(legalCards[0], game, botId);
  }

  const isLeading = game.currentTrick.length === 0;
  if (isLeading) {
    return makePlayAction(decideLeadCard(game, botId, legalCards), game, botId);
  } else {
    return makePlayAction(decideFollowCard(game, botId, legalCards), game, botId);
  }
}

function decideLeadCard(game, botId, legalCards) {
  const mightyCard = game.getMightyCard();
  const botIsGov = isGovernmentSelf(game, botId);

  // Joker-endgame override: 2 cards left on the trick-before-last, one is
  // joker. If we lead the non-joker and win, joker is forced onto the last
  // trick where it's weak (priority 0) and loses. Lead joker now instead —
  // it's still strong here, and the non-joker card leads the last trick,
  // where it can actually compete.
  if (legalCards.length === 2 && legalCards.includes('mighty_joker')) {
    const totalTricks = Math.floor(50 / (game.activePlayerCount || game.playerCount));
    const nextIsLast = game.tricks.length === totalTricks - 2;
    if (nextIsLast && !game.options.lastTrickJokerPower) {
      return 'mighty_joker';
    }
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

  // Phase 1: Mighty (sure winner in all cases)
  if (legalCards.includes(mightyCard)) return mightyCard;

  if (!hasTrump) {
    // ═══ NO-TRUMP DECLARER STRATEGY ═══
    // In NT there's no trump to draw. Play sure winners, then joker, then longest suit.

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
  const friendCardSuit = _getFriendCardSuit(game);
  const hasTrump = game.trumpSuit && game.trumpSuit !== 'no_trump';

  if (!hasTrump) {
    // ═══ NO-TRUMP FRIEND STRATEGY ═══
    // Step 1: Play mighty if we have it (sure winner)
    if (legalCards.includes(mightyCard)) return mightyCard;

    // Step 2: Play ALL effective top cards across all suits (exhaust sure winners)
    for (const [suit, cards] of Object.entries(suitCards)) {
      const sorted = cards.sort((a, b) =>
        RANK_ORDER[getCardInfo(b).rank] - RANK_ORDER[getCardInfo(a).rank]);
      if (_isEffectiveTopOfSuit(sorted[0], game)) return sorted[0];
    }

    // Step 3: Play joker (in NT, #2 card — play it before returning suit)
    if (legalCards.includes('mighty_joker')) return 'mighty_joker';

    // Step 4: All tops exhausted → return friend card suit to give declarer control
    if (friendCardSuit && suitCards[friendCardSuit] && suitCards[friendCardSuit].length > 0) {
      return suitCards[friendCardSuit].sort((a, b) =>
        RANK_ORDER[getCardInfo(b).rank] - RANK_ORDER[getCardInfo(a).rank])[0];
    }

    // Step 5: No friend suit left → lead from longest
    return _leadFromLongest(suitCards, legalCards);
  } else {
    // Trump: help draw trumps by leading trump, or return declarer's strong suit.
    // Use the self-aware check — pre-reveal, `game.partner` is null, so the default
    // _onlyGovernmentHasTrump would count the friend bot's own trumps as opposition
    // trumps and keep drawing forever. The friend knows it's itself.
    const oppOutOfTrump = _noRealOppTrumpLeft(game, botId);

    if (!oppOutOfTrump && suitCards[game.trumpSuit] && suitCards[game.trumpSuit].length > 0) {
      // Opposition still has trump → help draw by leading trump
      return suitCards[game.trumpSuit].sort((a, b) =>
        RANK_ORDER[getCardInfo(b).rank] - RANK_ORDER[getCardInfo(a).rank])[0];
    }

    // Opp has no trump left → switch to the friend-card suit to feed declarer
    const returnSuit = oppOutOfTrump ? friendCardSuit : game.trumpSuit;
    if (returnSuit && suitCards[returnSuit] && suitCards[returnSuit].length > 0) {
      return suitCards[returnSuit].sort((a, b) =>
        RANK_ORDER[getCardInfo(b).rank] - RANK_ORDER[getCardInfo(a).rank])[0];
    }
  }

  // Fallthrough: play mighty or top card
  if (legalCards.includes(mightyCard)) return mightyCard;
  return _leadFromLongest(suitCards, legalCards);
}

function _oppositionLead(game, botId, legalCards, suitCards, mightyCard) {
  const voids = _getKnownVoids(game);
  const declarerVoids = voids[game.declarer] || new Set();
  const hasTrump = game.trumpSuit && game.trumpSuit !== 'no_trump';

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

  // Joker-endgame override: in the {trump, joker} endgame, winning now with the
  // non-joker leaves joker alone to lead the next trick. If that next trick is
  // the last trick (joker weak by default), the joker lead collapses to
  // priority 0 and loses automatically. Swap to play joker NOW while it still
  // wins — the non-joker card becomes the next lead instead, where it has a
  // real chance.
  if (pick && pick !== 'mighty_joker' && winningCards.includes('mighty_joker')
      && winningCards.includes(pick) && legalCards.includes('mighty_joker')
      && legalCards.length === 2) {
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
    // almost always hold — just dump a non-trump point card. Don't trump-ruff our own ace.
    const winnerCard = getWinnerCardId(game);
    if (_isEffectiveTopOfSuit(winnerCard, game)) {
      return pickSafeDump(legalCards, game);
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

    if (!leadIsTrump && oppBehind && winningCards.length > 0) {
      const cheap = winningCards.filter(c => c !== mightyCard && c !== 'mighty_joker');
      const sureCheap = cheap.filter(c => _isEffectiveTopOfSuit(c, game));
      if (sureCheap.length > 0) return getWeakestCard(sureCheap, game);
      if (winningCards.includes(mightyCard)) return mightyCard;
      if (winningCards.includes('mighty_joker')) return 'mighty_joker';
      return pickSufficientWinner(winningCards, game, isLastPlayer, oppBehind);
    }
    return getSafeDiscard(legalCards, game);
  }

  if (winnerOnOurTeam) {
    // Ally winning, no one behind → safe to pile on points
    if (!oppBehind) {
      return pickSafeDump(legalCards, game);
    }

    const winnerCard = getWinnerCardId(game);
    const isSecure = winnerCard === mightyCard || winnerCard === 'mighty_joker' ||
      _isEffectiveTopOfSuit(winnerCard, game) ||
      (!isNT && winnerCard && getCardInfo(winnerCard).suit === game.trumpSuit &&
       getCardInfo(winnerCard).rank === 'A');

    if (isSecure) {
      return pickSafeDump(legalCards, game);
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
          return pickSafeDump(legalCards, game);
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

/** Get the suit of the friend-declared card */
function _getFriendCardSuit(game) {
  if (!game.friendCard || game.friendCard === 'no_friend' || game.friendCard === 'first_trick') {
    return null;
  }
  if (game.friendCard === 'mighty_joker') return null;
  const info = getCardInfo(game.friendCard);
  return info.suit || null;
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
  for (const pid of game.playerIds) {
    if (pid === game.declarer) continue;
    if (pid === selfPid) continue;
    if (game.friendRevealed && pid === game.partner) continue;
    const hand = game.hands[pid] || [];
    for (const cardId of hand) {
      if (cardId === 'mighty_joker') continue;
      const info = getCardInfo(cardId);
      if (info.suit === game.trumpSuit) return false;
    }
  }
  return true;
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

  // Joker call: when leading with joker-call card, activate to force joker out
  // NEVER joker-call in no-trump — joker is too valuable, don't waste tempo
  if (game.currentTrick.length === 0 && cardId === game.getJokerCallCard()) {
    if (game.trumpSuit && game.trumpSuit !== 'no_trump') {
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
function _pickJokerLeadSuit(game, botId) {
  const hand = game.hands[botId] || [];
  const trump = game.trumpSuit && game.trumpSuit !== 'no_trump' ? game.trumpSuit : null;
  // If we can be sure only government holds trump, make calling trump a last resort.
  const trumpDead = trump ? _noRealOppTrumpLeft(game, botId) : false;

  // Pre-compute: for every suit, do any opponent (non-gov seat that isn't self)
  // still hold that suit in their hand? If the suit is fully void across opp
  // seats, joker-calling it just forces free discards.
  const oppHoldsSuit = {};
  for (const suit of SUITS) oppHoldsSuit[suit] = false;
  for (const pid of game.playerIds) {
    if (pid === botId) continue;
    if (pid === game.declarer) continue;
    if (game.friendRevealed && pid === game.partner) continue;
    const h = game.hands[pid] || [];
    for (const cid of h) {
      if (cid === 'mighty_joker') continue;
      const info = getCardInfo(cid);
      if (info.suit) oppHoldsSuit[info.suit] = true;
    }
  }

  // Score each suit by our own strength in it
  const suitScore = {};
  for (const suit of SUITS) suitScore[suit] = 0;
  for (const cardId of hand) {
    if (cardId === 'mighty_joker') continue;
    const info = getCardInfo(cardId);
    suitScore[info.suit] += RANK_ORDER[info.rank] || 0;
  }
  // Boost suits where some opposition seat is known void (forced discards)
  const voids = _getKnownVoids(game);
  for (const pid of game.playerIds) {
    if (pid === botId) continue;
    for (const suit of (voids[pid] || [])) suitScore[suit] += 3;
  }
  // Huge bonus when opposition still holds the suit — that's the whole point of
  // calling it with joker. Penalty when calling trump while opp is out of it.
  for (const suit of SUITS) {
    if (oppHoldsSuit[suit]) suitScore[suit] += 50;
    if (suit === trump && trumpDead) suitScore[suit] -= 100;
  }

  let bestSuit = null;
  let bestScore = -Infinity;
  for (const [suit, score] of Object.entries(suitScore)) {
    if (score > bestScore) { bestScore = score; bestSuit = suit; }
  }
  // Safety fallbacks — trump if it exists, else spade
  if (!bestSuit) bestSuit = trump || 'spade';
  return bestSuit;
}

module.exports = { decideMightyBotAction };
