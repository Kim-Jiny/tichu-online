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

// ─── BIDDING ─────────────────────────────────────────────

function decideBid(game, botId) {
  const hand = game.hands[botId];
  const strength = evaluateHandStrength(hand, game);

  const estimatedPoints = Math.min(20, game.options.minBid + Math.floor(strength / 2.5));

  if (estimatedPoints >= game.options.minBid && estimatedPoints > game.currentBid.points) {
    const suit = pickBestTrump(hand);
    return { type: 'submit_bid', points: estimatedPoints, suit };
  }

  return { type: 'submit_bid', pass: true };
}

function evaluateHandStrength(hand, game) {
  let strength = 0;

  for (const cardId of hand) {
    if (cardId === 'mighty_joker') {
      strength += 2;
      continue;
    }
    const info = getCardInfo(cardId);
    if (info.rank === 'A') strength += 1.5;
    else if (info.rank === 'K') strength += 1;
  }

  // Long suit bonus: only if maxLen >= 6
  const suitCounts = {};
  for (const cardId of hand) {
    if (cardId === 'mighty_joker') continue;
    const info = getCardInfo(cardId);
    suitCounts[info.suit] = (suitCounts[info.suit] || 0) + 1;
  }
  const maxSuitLen = Math.max(...Object.values(suitCounts), 0);
  if (maxSuitLen >= 6) strength += 1;

  return Math.round(strength);
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

// ─── KITTY DISCARD ───────────────────────────────────────

function decideKittyDiscard(game, botId) {
  const hand = game.hands[botId]; // 13 cards at this point
  const trumpSuit = game.trumpSuit;

  // Sort by weakness: non-trump, non-point, low rank
  const ranked = hand.map(cardId => {
    const info = getCardInfo(cardId);
    let value = 0;
    if (cardId === 'mighty_joker') value = 100;
    else if (cardId === game.getMightyCard()) value = 99;
    else {
      if (info.point > 0) value += 30;
      if (info.suit === trumpSuit) value += 20;
      value += RANK_ORDER[info.rank] || 0;
    }
    return { cardId, value };
  });

  ranked.sort((a, b) => a.value - b.value);

  // Pick friend card: call mighty if we don't have it
  const mightyCard = game.getMightyCard();
  let friendCard;
  if (!hand.includes(mightyCard)) {
    friendCard = mightyCard;
  } else {
    friendCard = pickFriendCard(hand, game);
  }

  // Pick 3 weakest cards as discards, excluding friend card
  const discards = ranked
    .filter(r => r.cardId !== friendCard)
    .slice(0, 3)
    .map(r => r.cardId);

  return { type: 'discard_kitty', discards, friendCard };
}

function pickFriendCard(hand, game) {
  const candidates = ['mighty_spade_A', 'mighty_heart_A', 'mighty_diamond_A', 'mighty_club_A',
    'mighty_spade_K', 'mighty_heart_K', 'mighty_diamond_K', 'mighty_club_K'];

  for (const card of candidates) {
    if (!hand.includes(card) && card !== game.getMightyCard()) {
      return card;
    }
  }
  return 'no_friend';
}

// ─── HELPER FUNCTIONS ───────────────────────────────────

function getRemainingPlayers(game, botId) {
  const botIdx = game.currentTrick.findIndex(p => p.pid === botId);
  // Bot hasn't played yet; count from currentTrick.length onward in play order
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
  const botIsGov = isGovernment(game, botId);
  for (const pid of remaining) {
    const pidIsGov = isGovernment(game, pid);
    if (botIsGov !== pidIsGov) return true;
    // If friend not revealed and bot is opposition, declarer behind counts
    if (!botIsGov && !game.friendRevealed && pid !== game.declarer) {
      // Unknown: could be friend, treat conservatively
    }
    if (!botIsGov && pid === game.declarer) return true;
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
      if (rank > bestRank) {
        bestRank = rank;
        best = cardId;
      }
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

// ─── TRICK PLAY ──────────────────────────────────────────

function decidePlay(game, botId) {
  const legalCards = game._getLegalCards(botId);
  if (legalCards.length === 0) return null;
  if (legalCards.length === 1) {
    return makePlayAction(legalCards[0], game);
  }

  const isLeading = game.currentTrick.length === 0;

  if (isLeading) {
    return makePlayAction(decideLeadCard(game, botId, legalCards), game);
  } else {
    return makePlayAction(decideFollowCard(game, botId, legalCards), game);
  }
}

function decideLeadCard(game, botId, legalCards) {
  const mightyCard = game.getMightyCard();
  const botIsGov = isGovernment(game, botId);

  // Group cards by suit
  const suitCards = {};
  for (const cardId of legalCards) {
    if (cardId === 'mighty_joker') continue;
    const info = getCardInfo(cardId);
    if (!suitCards[info.suit]) suitCards[info.suit] = [];
    suitCards[info.suit].push(cardId);
  }

  if (botIsGov) {
    // Government lead: play sure winners first to collect points
    // Mighty
    if (legalCards.includes(mightyCard)) return mightyCard;
    // Trump A/K (likely top cards)
    if (game.trumpSuit && game.trumpSuit !== 'no_trump' && suitCards[game.trumpSuit]) {
      const trumpCards = suitCards[game.trumpSuit].sort((a, b) =>
        RANK_ORDER[getCardInfo(b).rank] - RANK_ORDER[getCardInfo(a).rank]);
      const topTrump = trumpCards[0];
      const topRank = getCardInfo(topTrump).rank;
      if (topRank === 'A' || topRank === 'K') return topTrump;
    }

    // ─── Friend-aware lead: return suits to partner ───
    if (game.friendRevealed && game.partner && botId === game.partner) {
      const friendCardSuit = _getFriendCardSuit(game);
      const hasTrump = game.trumpSuit && game.trumpSuit !== 'no_trump';

      if (!hasTrump) {
        // No-trump bid: lead top card first, then return friend-card suit
        const topCard = _getTopWinnerFromHand(legalCards, suitCards, game);
        if (topCard) return topCard;
        // Return friend-card suit
        if (friendCardSuit && suitCards[friendCardSuit] && suitCards[friendCardSuit].length > 0) {
          const sorted = suitCards[friendCardSuit].sort((a, b) =>
            RANK_ORDER[getCardInfo(b).rank] - RANK_ORDER[getCardInfo(a).rank]);
          return sorted[0];
        }
      } else {
        // Trump bid: return trump suit to declarer
        // But if only declarer+friend have trump → return friend-card suit instead
        const onlyGovHasTrump = _onlyGovernmentHasTrump(game);
        const returnSuit = onlyGovHasTrump ? friendCardSuit : game.trumpSuit;

        if (returnSuit && suitCards[returnSuit] && suitCards[returnSuit].length > 0) {
          const sorted = suitCards[returnSuit].sort((a, b) =>
            RANK_ORDER[getCardInfo(b).rank] - RANK_ORDER[getCardInfo(a).rank]);
          return sorted[0];
        }
      }
    }
  } else {
    // Opposition lead: prefer short suits to create voids
    let shortestSuit = null;
    let shortestLen = Infinity;
    for (const [suit, cards] of Object.entries(suitCards)) {
      // Skip trump suit for void creation
      if (suit === game.trumpSuit) continue;
      if (cards.length > 0 && cards.length < shortestLen) {
        shortestLen = cards.length;
        shortestSuit = suit;
      }
    }
    if (shortestSuit && suitCards[shortestSuit].length > 0) {
      // Lead highest from shortest suit
      const sorted = suitCards[shortestSuit].sort((a, b) =>
        RANK_ORDER[getCardInfo(b).rank] - RANK_ORDER[getCardInfo(a).rank]);
      return sorted[0];
    }
  }

  // Fallback: lead highest from longest suit
  let bestSuit = null;
  let bestLen = 0;
  for (const [suit, cards] of Object.entries(suitCards)) {
    if (cards.length > bestLen) {
      bestLen = cards.length;
      bestSuit = suit;
    }
  }

  if (bestSuit && suitCards[bestSuit].length > 0) {
    const sorted = suitCards[bestSuit].sort((a, b) =>
      RANK_ORDER[getCardInfo(b).rank] - RANK_ORDER[getCardInfo(a).rank]);
    return sorted[0];
  }

  return legalCards[0];
}

function decideFollowCard(game, botId, legalCards) {
  const mightyCard = game.getMightyCard();
  const currentWinner = getCurrentTrickWinner(game);
  const botIsGov = isGovernment(game, botId);
  const winnerIsGov = isGovernment(game, currentWinner);
  const winningCards = legalCards.filter(cardId => canBeatCurrentWinner(game, cardId));

  // Determine if winner is on our team
  const winnerOnOurTeam = botIsGov
    ? winnerIsGov
    : (game.friendRevealed
      ? !winnerIsGov
      : currentWinner !== game.declarer);

  if (botIsGov) {
    return governmentFollow(game, botId, legalCards, winningCards, currentWinner, winnerOnOurTeam, mightyCard);
  } else {
    return oppositionFollow(game, botId, legalCards, winningCards, currentWinner, winnerOnOurTeam, mightyCard);
  }
}

function governmentFollow(game, botId, legalCards, winningCards, currentWinner, winnerOnOurTeam, mightyCard) {
  const oppBehind = hasOppositionBehind(game, botId);
  const isFriend = botId === game.partner && game.friendRevealed;
  const declarerLed = game.currentTrick.length > 0 && game.currentTrick[0].pid === game.declarer;

  // ─── Friend helping declarer's lead ───
  // Only help with strong cards when declarer's card is genuinely weak.
  // If declarer has the effective top of the suit (e.g. K when A=mighty),
  // just dump points — don't waste mighty/joker preemptively.
  if (isFriend && declarerLed && winnerOnOurTeam && oppBehind) {
    const winnerCard = getWinnerCardId(game);
    if (!_isEffectiveTopOfSuit(winnerCard, game)) {
      // Declarer's card is NOT the top of its suit → help take the trick
      if (winningCards.includes(mightyCard)) return mightyCard;
      if (winningCards.includes('mighty_joker')) return 'mighty_joker';
      if (winningCards.length > 0) return getStrongestCard(winningCards, game);
    }
    // Declarer has top of suit → fall through to normal "ally winning" logic
  }

  if (winnerOnOurTeam) {
    if (!oppBehind) {
      // Ally winning, no opposition behind → dump point cards
      const bestPoint = getBestPointCard(legalCards);
      if (bestPoint) return bestPoint;
      return getWeakestCard(legalCards, game);
    }
    // Ally winning but opposition still behind
    // Only dump points if winner has top card (mighty/joker/trump A)
    const winnerCard = getWinnerCardId(game);
    if (winnerCard === mightyCard || winnerCard === 'mighty_joker' ||
        (game.trumpSuit && game.trumpSuit !== 'no_trump' && winnerCard &&
         winnerCard !== 'mighty_joker' && getCardInfo(winnerCard).suit === game.trumpSuit &&
         getCardInfo(winnerCard).rank === 'A')) {
      const bestPoint = getBestPointCard(legalCards);
      if (bestPoint) return bestPoint;
    }
    return getNonPointWeakest(legalCards, game);
  }

  // Enemy winning
  if (winningCards.length > 0) {
    if (oppBehind) {
      // Enemy winning, opposition behind → use strong card to secure
      // Prefer mighty > joker > trump high
      if (winningCards.includes(mightyCard)) return mightyCard;
      if (winningCards.includes('mighty_joker')) return 'mighty_joker';
      // Strongest winning card
      return getStrongestCard(winningCards, game);
    }
    // Enemy winning, no opposition behind → weakest winning card
    return getWeakestCard(winningCards, game);
  }

  // Can't win
  return getNonPointWeakest(legalCards, game);
}

function oppositionFollow(game, botId, legalCards, winningCards, currentWinner, winnerOnOurTeam, mightyCard) {
  const govBehind = hasGovernmentBehind(game, botId);
  const trickPoints = getTrickPointCount(game);

  if (!winnerOnOurTeam) {
    // Government is winning
    // Joker snipe: if we have joker, trick has 2+ point cards, and we can win
    if (legalCards.includes('mighty_joker') && trickPoints >= 2 &&
        canBeatCurrentWinner(game, 'mighty_joker')) {
      return 'mighty_joker';
    }
    // Try to beat with weakest winning card
    if (winningCards.length > 0) {
      return getWeakestCard(winningCards, game);
    }
    // Can't win → non-point weakest
    return getNonPointWeakest(legalCards, game);
  }

  // Our team (opposition ally) is winning
  if (!govBehind) {
    // No government behind → dump point cards
    const bestPoint = getBestPointCard(legalCards);
    if (bestPoint) return bestPoint;
    return getWeakestCard(legalCards, game);
  }
  // Government still behind → don't feed them points
  return getNonPointWeakest(legalCards, game);
}

function hasGovernmentBehind(game, botId) {
  const remaining = getRemainingPlayers(game, botId);
  for (const pid of remaining) {
    if (isGovernment(game, pid)) return true;
    // If friend not revealed, declarer is known government
    if (!game.friendRevealed && pid === game.declarer) return true;
  }
  return false;
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
    (leadCard === jokerCallCard);

  let bestPlay = null;
  let bestPriority = -1;
  for (const play of game.currentTrick) {
    const priority = game._getCardPriority(play.cardId, leadSuit, jokerIsWeak, mightyCard);
    if (priority > bestPriority) {
      bestPriority = priority;
      bestPlay = play;
    }
  }
  return bestPlay ? bestPlay.cardId : null;
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
    if (value > strongestValue) {
      strongestValue = value;
      strongest = cardId;
    }
  }

  return strongest;
}

// ─── TRICK EVALUATION ───────────────────────────────────

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
    (leadCard === jokerCallCard);

  let bestPlay = null;
  let bestPriority = -1;

  for (const play of game.currentTrick) {
    const priority = game._getCardPriority(play.cardId, leadSuit, jokerIsWeak, mightyCard);
    if (priority > bestPriority) {
      bestPriority = priority;
      bestPlay = play;
    }
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
    (leadCard === jokerCallCard);

  const cardPriority = game._getCardPriority(cardId, leadSuit, jokerIsWeak, mightyCard);

  let bestPriority = -1;
  for (const play of game.currentTrick) {
    const p = game._getCardPriority(play.cardId, leadSuit, jokerIsWeak, mightyCard);
    if (p > bestPriority) bestPriority = p;
  }

  return cardPriority > bestPriority;
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
    if (value < weakestValue) {
      weakestValue = value;
      weakest = cardId;
    }
  }

  return weakest;
}

// ─── FRIEND LEAD HELPERS ────────────────────────────────

/**
 * Check if a card is the effective top of its suit.
 * e.g. Spade K is the top when Spade A is the Mighty card.
 * Mighty and Joker are always top.
 */
function _isEffectiveTopOfSuit(cardId, game) {
  if (!cardId) return false;
  const mightyCard = game.getMightyCard();
  if (cardId === mightyCard) return true;
  if (cardId === 'mighty_joker') return true;

  const info = getCardInfo(cardId);
  const mightyInfo = getCardInfo(mightyCard);

  // A is top of its suit unless A itself is the mighty of that suit
  if (info.rank === 'A' && !(mightyInfo.suit === info.suit && mightyInfo.rank === 'A')) {
    return true;
  }
  // K is top of the mighty suit (since A of that suit = mighty, removed from normal play)
  if (info.rank === 'K' && mightyInfo.suit === info.suit && mightyInfo.rank === 'A') {
    return true;
  }

  return false;
}

/** Get the suit of the friend-declared card */
function _getFriendCardSuit(game) {
  if (!game.friendCard || game.friendCard === 'no_friend' || game.friendCard === 'first_trick') {
    return null;
  }
  const info = getCardInfo(game.friendCard);
  return info.suit || null;
}

/** Check if only government (declarer + partner) still hold trump cards */
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
    const topRank = getCardInfo(sorted[0]).rank;
    if (topRank === 'A') return sorted[0];
  }
  return null;
}

function makePlayAction(cardId, game) {
  const action = { type: 'play_card', cardId };
  if (cardId === 'mighty_joker' && game.currentTrick.length === 0) {
    action.jokerSuit = game.trumpSuit && game.trumpSuit !== 'no_trump'
      ? game.trumpSuit : 'spade';
  }
  return action;
}

module.exports = { decideMightyBotAction };
