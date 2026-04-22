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
  const strength = evaluateHandStrength(hand, game);

  const estimatedPoints = Math.min(20, game.options.minBid + Math.floor(strength / 2.5));

  if (estimatedPoints >= game.options.minBid && estimatedPoints > game.currentBid.points) {
    let suit = pickBestTrump(hand);

    // Consider no-trump for balanced hands with many high cards
    if (game.options.allowNoTrump) {
      const suitCounts = {};
      let highCards = 0;
      for (const cardId of hand) {
        if (cardId === 'mighty_joker') continue;
        const info = getCardInfo(cardId);
        suitCounts[info.suit] = (suitCounts[info.suit] || 0) + 1;
        if (info.rank === 'A' || info.rank === 'K') highCards++;
      }
      const maxLen = Math.max(...Object.values(suitCounts), 0);
      if (maxLen <= 4 && highCards >= 4) {
        suit = 'no_trump';
      }
    }

    return { type: 'submit_bid', points: estimatedPoints, suit };
  }

  return { type: 'submit_bid', pass: true };
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
  const suitCounts = {};
  const suitStrength = {};

  for (const cardId of hand) {
    if (cardId === 'mighty_joker') continue;
    const info = getCardInfo(cardId);
    suitCounts[info.suit] = (suitCounts[info.suit] || 0) + 1;
    suitStrength[info.suit] = (suitStrength[info.suit] || 0) + RANK_ORDER[info.rank];
  }

  let bestSuit = 'spade';
  let bestScore = -1;

  for (const suit of SUITS) {
    const score = (suitCounts[suit] || 0) * 10 + (suitStrength[suit] || 0);
    if (score > bestScore) {
      bestScore = score;
      bestSuit = suit;
    }
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

  // Fill remaining with weakest non-trump, non-protected cards
  if (discards.length < 3) {
    const remaining = hand
      .filter(cardId => !protectedCards.has(cardId) && !discards.includes(cardId))
      .map(cardId => {
        const info = getCardInfo(cardId);
        let value = 0;
        if (info.point > 0) value += 30;
        if (info.suit === trumpSuit) value += 20;
        value += RANK_ORDER[info.rank] || 0;
        return { cardId, value };
      })
      .sort((a, b) => a.value - b.value);

    for (const { cardId } of remaining) {
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
    if (trumpSuit !== 'no_trump' && trumpCount >= 6 && hasJoker) {
      friendCard = 'no_friend';
    } else {
      friendCard = pickFriendCard(hand, game);
    }
  }

  // Ensure friend card isn't in discards
  let finalDiscards = discards.filter(c => c !== friendCard);
  if (finalDiscards.length < 3) {
    const extra = hand
      .filter(cardId => !protectedCards.has(cardId) && !finalDiscards.includes(cardId) && cardId !== friendCard)
      .map(cardId => {
        const info = getCardInfo(cardId);
        return { cardId, value: (info.point > 0 ? 30 : 0) + (info.suit === trumpSuit ? 20 : 0) + (RANK_ORDER[info.rank] || 0) };
      })
      .sort((a, b) => a.value - b.value);
    for (const { cardId } of extra) {
      if (finalDiscards.length >= 3) break;
      finalDiscards.push(cardId);
    }
  }

  return { type: 'discard_kitty', discards: finalDiscards.slice(0, 3), friendCard };
}

/**
 * Smart friend card selection.
 * Call the Ace of the suit where declarer is WEAKEST (needs the most help).
 */
function pickFriendCard(hand, game) {
  const mightyCard = game.getMightyCard();
  const trumpSuit = game.trumpSuit;

  // Count cards per non-trump suit
  const suitCounts = {};
  for (const suit of SUITS) suitCounts[suit] = 0;
  for (const cardId of hand) {
    if (cardId === 'mighty_joker' || cardId === mightyCard) continue;
    const info = getCardInfo(cardId);
    suitCounts[info.suit]++;
  }

  // Sort non-trump suits by count ascending (weakest first)
  const targetSuits = SUITS
    .filter(s => s !== trumpSuit)
    .sort((a, b) => suitCounts[a] - suitCounts[b]);

  // Call Ace of weakest suit (if we don't have it and it's not the mighty)
  for (const suit of targetSuits) {
    const aceId = `mighty_${suit}_A`;
    if (!hand.includes(aceId) && aceId !== mightyCard) {
      return aceId;
    }
  }

  // All non-trump aces in hand → call King of weakest suit
  for (const suit of targetSuits) {
    const kingId = `mighty_${suit}_K`;
    if (!hand.includes(kingId)) {
      return kingId;
    }
  }

  return 'no_friend';
}

// ═══════════════════════════════════════════════════════════
//  HELPER FUNCTIONS
// ═══════════════════════════════════════════════════════════

function getRemainingPlayers(game, botId) {
  const playedIds = new Set(game.currentTrick.map(p => p.pid));
  const leaderIdx = game.playerIds.indexOf(game.currentTrick[0].pid);
  const remaining = [];
  for (let i = 0; i < game.playerCount; i++) {
    const pid = game.playerIds[(leaderIdx + i) % game.playerCount];
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
  // Phase 2: DRAW TRUMPS — THE critical declarer strategy
  if (suitCards[game.trumpSuit] && suitCards[game.trumpSuit].length > 0) {
    const oppTrumps = _countOpponentTrumps(game, botId);
    if (oppTrumps > 0) {
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

  // Phase 4: Joker — safe when no opponent trumps remain
  if (legalCards.includes('mighty_joker')) {
    if (_countOpponentTrumps(game, botId) === 0) return 'mighty_joker';
  }

  // Phase 5: Lead remaining trumps
  if (suitCards[game.trumpSuit] && suitCards[game.trumpSuit].length > 0) {
    return suitCards[game.trumpSuit].sort((a, b) =>
      RANK_ORDER[getCardInfo(b).rank] - RANK_ORDER[getCardInfo(a).rank])[0];
  }

  // Phase 6: Lead from longest suit
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
    // Trump: help draw trumps by leading trump, or return declarer's strong suit
    const onlyGovHasTrump = _onlyGovernmentHasTrump(game);

    if (!onlyGovHasTrump && suitCards[game.trumpSuit] && suitCards[game.trumpSuit].length > 0) {
      // Opposition still has trump → help draw by leading trump
      return suitCards[game.trumpSuit].sort((a, b) =>
        RANK_ORDER[getCardInfo(b).rank] - RANK_ORDER[getCardInfo(a).rank])[0];
    }

    // Trumps drawn or only gov has them → return friend-card suit
    const returnSuit = onlyGovHasTrump ? friendCardSuit : game.trumpSuit;
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

  const winnerOnOurTeam = botIsGov
    ? winnerIsGov
    : (game.friendRevealed ? !winnerIsGov : currentWinner !== game.declarer);

  if (botIsGov) {
    return governmentFollow(game, botId, legalCards, winningCards, currentWinner, winnerOnOurTeam, mightyCard);
  } else {
    return oppositionFollow(game, botId, legalCards, winningCards, currentWinner, winnerOnOurTeam, mightyCard);
  }
}

function governmentFollow(game, botId, legalCards, winningCards, currentWinner, winnerOnOurTeam, mightyCard) {
  const oppBehind = hasOppositionBehind(game, botId);
  const isFriend = _isFriend(game, botId);
  const declarerLed = game.currentTrick.length > 0 && game.currentTrick[0].pid === game.declarer;
  const trickPoints = getTrickPointCount(game);
  const isLastPlayer = game.currentTrick.length === game.playerCount - 1;
  const isNT = !game.trumpSuit || game.trumpSuit === 'no_trump';

  // ─── Friend helping declarer's lead ───
  if (isFriend && declarerLed) {
    if (!winnerOnOurTeam) {
      // Declarer is LOSING → rescue
      // In NT: always rescue (every trick matters for control)
      // In suited: conserve mighty/joker for valuable tricks
      if (isNT || trickPoints >= 2 || isLastPlayer) {
        if (winningCards.includes(mightyCard)) return mightyCard;
        if (winningCards.includes('mighty_joker')) return 'mighty_joker';
      }
      if (winningCards.length > 0) return getStrongestCard(winningCards, game);
    } else if (oppBehind) {
      const winnerCard = getWinnerCardId(game);
      if (!_isEffectiveTopOfSuit(winnerCard, game)) {
        // Declarer's card is NOT top → opposition will beat it → must protect
        // In NT: always protect (control > point conservation)
        if (isNT || trickPoints >= 2) {
          if (winningCards.includes(mightyCard)) return mightyCard;
          if (winningCards.includes('mighty_joker')) return 'mighty_joker';
        }
        if (winningCards.length > 0) return getStrongestCard(winningCards, game);
      }
    }
  }

  if (winnerOnOurTeam) {
    // ─── NT: if our winning card is NOT top, we must reinforce ───
    if (isNT && oppBehind) {
      const winnerCard = getWinnerCardId(game);
      if (winnerCard && winnerCard !== mightyCard && winnerCard !== 'mighty_joker' &&
          !_isEffectiveTopOfSuit(winnerCard, game)) {
        // Our card will get beaten → play stronger card to secure
        if (winningCards.length > 0) return getStrongestCard(winningCards, game);
      }
    }

    if (!oppBehind) {
      // Ally winning, no opposition behind → dump point cards
      const bestPoint = getBestPointCard(legalCards);
      if (bestPoint) return bestPoint;
      return getWeakestCard(legalCards, game);
    }
    // Ally winning but opposition still behind → only dump if trick is secure
    const winnerCard = getWinnerCardId(game);
    const isSecure = winnerCard === mightyCard || winnerCard === 'mighty_joker' ||
      _isEffectiveTopOfSuit(winnerCard, game) ||
      (!isNT && winnerCard &&
       winnerCard !== 'mighty_joker' && getCardInfo(winnerCard).suit === game.trumpSuit &&
       getCardInfo(winnerCard).rank === 'A');

    if (isSecure) {
      const bestPoint = getBestPointCard(legalCards);
      if (bestPoint) return bestPoint;
    }
    return getNonPointWeakest(legalCards, game);
  }

  // ─── Enemy winning ───
  if (winningCards.length > 0) {
    // In NT: always fight for the trick (control matters), less conservation
    if (!isNT && trickPoints <= 1 && !isLastPlayer) {
      // Suited: conserve mighty/joker on low-point tricks
      const cheapWinners = winningCards.filter(c => c !== mightyCard && c !== 'mighty_joker');
      if (cheapWinners.length > 0) {
        return oppBehind ? getStrongestCard(cheapWinners, game) : getWeakestCard(cheapWinners, game);
      }
      return getNonPointWeakest(legalCards, game);
    }

    if (oppBehind) {
      if (winningCards.includes(mightyCard)) return mightyCard;
      if (winningCards.includes('mighty_joker')) return 'mighty_joker';
      return getStrongestCard(winningCards, game);
    }
    return getWeakestCard(winningCards, game);
  }

  return getNonPointWeakest(legalCards, game);
}

function oppositionFollow(game, botId, legalCards, winningCards, currentWinner, winnerOnOurTeam, mightyCard) {
  const govBehind = hasGovernmentBehind(game, botId);
  const trickPoints = getTrickPointCount(game);
  const isLastPlayer = game.currentTrick.length === game.playerCount - 1;
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
      // ═══ NT OPPOSITION: fight for control, less conservation ═══
      // In NT every trick matters — always try to win if we can
      if (winningCards.length > 0) {
        return getWeakestCard(winningCards, game);
      }
      return getNonPointWeakest(legalCards, game);
    }

    // ═══ SUITED: conserve trump and specials ═══
    // No points in trick, no more gov behind → don't bother winning
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

    if (winningCards.length > 0) return getWeakestCard(winningCards, game);
    return getNonPointWeakest(legalCards, game);
  }

  // Our team (opposition ally) is winning
  if (!govBehind) {
    const bestPoint = getBestPointCard(legalCards);
    if (bestPoint) return bestPoint;
    return getWeakestCard(legalCards, game);
  }

  // Government still behind → check if ally's card is secure
  const winnerCard = getWinnerCardId(game);
  const isSecure = winnerCard === mightyCard || winnerCard === 'mighty_joker' ||
    _isEffectiveTopOfSuit(winnerCard, game);

  if (isSecure) {
    const bestPoint = getBestPointCard(legalCards);
    if (bestPoint) return bestPoint;
  }

  // In NT: if ally's card is not secure, try to reinforce it
  if (isNT && !isSecure && winningCards.length > 0) {
    return getWeakestCard(winningCards, game);
  }

  return getNonPointWeakest(legalCards, game);
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
  const totalTricks = Math.floor(50 / game.playerCount);
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
  const totalTricks = Math.floor(50 / game.playerCount);
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
  const totalTricks = Math.floor(50 / game.playerCount);
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
 *  Choose suit where we have follow-up strength, or where opponents are weak. */
function _pickJokerLeadSuit(game, botId) {
  const hand = game.hands[botId] || [];
  const voids = _getKnownVoids(game);

  // Score each suit: our strength + how many opponents are void (can't follow)
  const suitScore = {};
  for (const suit of SUITS) suitScore[suit] = 0;

  for (const cardId of hand) {
    if (cardId === 'mighty_joker') continue;
    const info = getCardInfo(cardId);
    suitScore[info.suit] += RANK_ORDER[info.rank];
  }

  // Bonus for suits where opponents are void (they'll be forced to discard)
  for (const pid of game.playerIds) {
    if (pid === botId) continue;
    for (const suit of (voids[pid] || [])) {
      suitScore[suit] += 3;
    }
  }

  let bestSuit = game.trumpSuit && game.trumpSuit !== 'no_trump' ? game.trumpSuit : 'spade';
  let bestScore = -1;
  for (const [suit, score] of Object.entries(suitScore)) {
    if (score > bestScore) { bestScore = score; bestSuit = suit; }
  }
  return bestSuit;
}

module.exports = { decideMightyBotAction };
