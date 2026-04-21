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

  // Estimate how many points we can win
  const estimatedPoints = Math.min(20, game.options.minBid - 1 + strength);

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
      strength += 3;
      continue;
    }
    const info = getCardInfo(cardId);
    if (info.rank === 'A') strength += 2;
    else if (info.rank === 'K') strength += 1.5;
    else if (info.rank === 'Q') strength += 1;
    else if (info.rank === 'J') strength += 0.5;
  }

  // Count suit lengths (long suits are stronger)
  const suitCounts = {};
  for (const cardId of hand) {
    if (cardId === 'mighty_joker') continue;
    const info = getCardInfo(cardId);
    suitCounts[info.suit] = (suitCounts[info.suit] || 0) + 1;
  }
  const maxSuitLen = Math.max(...Object.values(suitCounts), 0);
  if (maxSuitLen >= 5) strength += maxSuitLen - 4;

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
    // Call highest card we don't have
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
  // Try to find a strong card we don't have
  const candidates = ['mighty_spade_A', 'mighty_heart_A', 'mighty_diamond_A', 'mighty_club_A',
    'mighty_spade_K', 'mighty_heart_K', 'mighty_diamond_K', 'mighty_club_K'];

  for (const card of candidates) {
    if (!hand.includes(card) && card !== game.getMightyCard()) {
      return card;
    }
  }
  return 'no_friend';
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

  // Lead mighty early if we have it (strong opening)
  if (legalCards.includes(mightyCard) && game.tricks.length < 3) {
    return mightyCard;
  }

  // Lead from longest suit
  const suitCards = {};
  for (const cardId of legalCards) {
    if (cardId === 'mighty_joker') continue;
    const info = getCardInfo(cardId);
    if (!suitCards[info.suit]) suitCards[info.suit] = [];
    suitCards[info.suit].push(cardId);
  }

  let bestSuit = null;
  let bestLen = 0;
  for (const [suit, cards] of Object.entries(suitCards)) {
    if (cards.length > bestLen) {
      bestLen = cards.length;
      bestSuit = suit;
    }
  }

  if (bestSuit && suitCards[bestSuit].length > 0) {
    // Lead highest from longest suit
    const sorted = suitCards[bestSuit].sort((a, b) => {
      return RANK_ORDER[getCardInfo(b).rank] - RANK_ORDER[getCardInfo(a).rank];
    });
    return sorted[0];
  }

  return legalCards[0];
}

function decideFollowCard(game, botId, legalCards) {
  const mightyCard = game.getMightyCard();
  const currentWinner = getCurrentTrickWinner(game);

  // Determine if we're on the declarer's team
  const isDeclarer = botId === game.declarer;
  const isPartner = game.friendRevealed && botId === game.partner;
  const isDeclarerTeam = isDeclarer || isPartner;

  // Check if current winner is on our team
  const winnerOnOurTeam = isDeclarerTeam
    ? (currentWinner === game.declarer || (game.friendRevealed && currentWinner === game.partner))
    : (game.friendRevealed
        ? (currentWinner !== game.declarer && currentWinner !== game.partner)
        : (currentWinner !== game.declarer)); // Unknown partner: try to beat declarer

  if (winnerOnOurTeam) {
    // Teammate is winning: play lowest legal card
    return getWeakestCard(legalCards, game);
  }

  // Try to win the trick
  const winningCards = legalCards.filter(cardId => canBeatCurrentWinner(game, cardId));

  if (winningCards.length > 0) {
    // Play weakest winning card
    return getWeakestCard(winningCards, game);
  }

  // Can't win: play weakest card
  return getWeakestCard(legalCards, game);
}

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

function makePlayAction(cardId, game) {
  const action = { type: 'play_card', cardId };
  if (cardId === 'mighty_joker' && game.currentTrick.length === 0) {
    action.jokerSuit = game.trumpSuit && game.trumpSuit !== 'no_trump'
      ? game.trumpSuit : 'spade';
  }
  return action;
}

module.exports = { decideMightyBotAction };
