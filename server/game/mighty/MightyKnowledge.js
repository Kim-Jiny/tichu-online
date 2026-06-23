'use strict';

/**
 * MightyKnowledge — perfect-information world-knowledge queries.
 *
 * The server bot can see every hand, so most "what does the table look like"
 * questions have exact answers. This module centralises those queries (team
 * membership, current trick winner, who can still beat it, who holds the
 * trumps / Mighty / joker) so the decision code (MightyBot, the endgame solver,
 * the strategy layers) shares one source of truth instead of re-deriving them
 * inline. Every function is pure over the game state and depends only on the
 * game object + MightyDeck — no dependency back on MightyBot (one-way import).
 */

const { getCardInfo, RANK_ORDER } = require('./MightyDeck');

// ── Turn order ────────────────────────────────────────────────────────────

/** Players who still have to play in the current trick, after `botId`. */
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

// ── Team membership ───────────────────────────────────────────────────────

/** Declared government: declarer + (revealed) partner. */
function isGovernment(game, playerId) {
  if (playerId === game.declarer) return true;
  if (game.friendRevealed && playerId === game.partner) return true;
  return false;
}

/** Government including the friend even before reveal (full-info). */
function isGovernmentSelf(game, playerId) {
  if (isGovernment(game, playerId)) return true;
  return _isFriend(game, playerId);
}

/** Check if a player is the friend (even before reveal, by checking hand). */
function _isFriend(game, playerId) {
  if (playerId === game.declarer) return false;
  if (game.friendRevealed && playerId === game.partner) return true;
  if (!game.friendRevealed && game.friendCard && game.friendCard !== 'no_friend' && game.friendCard !== 'first_trick') {
    const hand = game.hands[playerId] || [];
    if (hand.includes(game.friendCard)) return true;
  }
  return false;
}

// ── Current trick winner / beatability ────────────────────────────────────

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

/** Card id of the play currently winning the trick. */
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

/** Would `cardId`, played now, beat the current trick winner? */
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

// ── Trump / Mighty / joker possession ─────────────────────────────────────

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

/** True if any player on the side opposing `selfPid` still holds the joker
 *  (which beats trump). Omniscient — reads full hands like the other helpers. */
function _oppHoldsJoker(game, selfPid) {
  const selfIsGov = isGovernmentSelf(game, selfPid);
  for (const pid of game.playerIds) {
    if (pid === selfPid) continue;
    if (isGovernmentSelf(game, pid) === selfIsGov) continue;
    if ((game.hands[pid] || []).includes('mighty_joker')) return true;
  }
  return false;
}

/** True if any player on the side opposing `selfPid` still holds the Mighty
 *  (which beats trump). Omniscient — reads full hands like the other helpers. */
function _oppHoldsMighty(game, selfPid) {
  const mightyCard = game.getMightyCard();
  if (!mightyCard) return false;
  const selfIsGov = isGovernmentSelf(game, selfPid);
  for (const pid of game.playerIds) {
    if (pid === selfPid) continue;
    if (isGovernmentSelf(game, pid) === selfIsGov) continue;
    if ((game.hands[pid] || []).includes(mightyCard)) return true;
  }
  return false;
}

/**
 * True if NO opponent (player not on `botId`'s team) can over-ruff `trumpCard`
 * — no opponent holds a higher trump, the Mighty, or the joker. Such a trump is
 * a "live ruffer": it still WINS a future trick by ruffing, so it's worth
 * keeping rather than discarding. Allies over-ruffing is fine (trick stays on
 * our team), so only opponents count.
 */
function _trumpSurvivesOpp(game, botId, trumpCard) {
  const trump = game.trumpSuit;
  if (!trump || trump === 'no_trump') return false;
  if (!trumpCard) return false;
  const info0 = getCardInfo(trumpCard);
  if (!info0 || info0.suit !== trump) return false;
  const mightyCard = game.getMightyCard();
  const myRank = RANK_ORDER[info0.rank] || 0;
  const botIsGov = isGovernmentSelf(game, botId);
  for (const pid of game.playerIds) {
    if (pid === botId) continue;
    if (isGovernmentSelf(game, pid) === botIsGov) continue; // skip allies
    for (const cid of (game.hands[pid] || [])) {
      if (cid === mightyCard || cid === 'mighty_joker') return false;
      const info = getCardInfo(cid);
      if (info.suit === trump && (RANK_ORDER[info.rank] || 0) > myRank) return false;
    }
  }
  return true;
}

/**
 * True if the team's current trick winner is LOCKED — the winner is on our team
 * AND no opponent still to play in this trick holds a card that can beat it.
 * `canBeatCurrentWinner` over-estimates beatability for must-follow situations,
 * so this never reports "locked" when an opponent could actually steal the
 * trick — safe to act on.
 */
function _trickLockedForUs(game, botId) {
  if (!game.currentTrick || game.currentTrick.length === 0) return false;
  const botIsGov = isGovernmentSelf(game, botId);
  const winner = getCurrentTrickWinner(game);
  if (!winner || isGovernmentSelf(game, winner) !== botIsGov) return false; // not ours
  for (const pid of getRemainingPlayers(game, botId)) {
    if (isGovernmentSelf(game, pid) === botIsGov) continue; // allies can't hurt us
    for (const cid of (game.hands[pid] || [])) {
      if (canBeatCurrentWinner(game, cid)) return false;
    }
  }
  return true;
}

module.exports = {
  getRemainingPlayers,
  isGovernment,
  isGovernmentSelf,
  _isFriend,
  getCurrentTrickWinner,
  getWinnerCardId,
  canBeatCurrentWinner,
  _onlyGovernmentHasTrump,
  _noRealOppTrumpLeft,
  _oppHoldsJoker,
  _oppHoldsMighty,
  _trumpSurvivesOpp,
  _trickLockedForUs,
};
