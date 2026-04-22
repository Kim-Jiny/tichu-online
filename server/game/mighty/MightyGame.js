'use strict';

const { SUITS, RANKS, RANK_ORDER, deal, getCardInfo, sortCards } = require('./MightyDeck');
const { countPoints, calculateRoundScores } = require('./MightyScoring');

class MightyGame {
  constructor(playerIds, playerNames, options = {}) {
    this.playerIds = playerIds;
    this.playerNames = playerNames;
    this.playerCount = playerIds.length; // 5 (or 6 future)
    this.gameType = 'mighty';

    // Options (house rules)
    this.options = {
      minBid: options.minBid || 13,
      allowNoTrump: options.allowNoTrump !== false,
      allowTrumpChange: options.allowTrumpChange !== false,
      trumpChangePenalty: options.trumpChangePenalty || 2,
      jokerCallCard: options.jokerCallCard || 'auto',
      soloBonus: options.soloBonus || 2,
      perfectBonus: options.perfectBonus || 2,
      firstTrickJokerPower: options.firstTrickJokerPower === true,
      lastTrickJokerPower: options.lastTrickJokerPower === true,
      targetScore: options.targetScore || null,
      scoreMultiplier: options.scoreMultiplier || 1,
    };

    // Game state
    this.state = 'waiting';
    this.round = 0;
    this.hands = {};
    this.kitty = [];
    this.trumpSuit = null;
    this.declarer = null;
    this.partner = null;
    this.friendCard = null;
    this.friendRevealed = false;
    this.currentBid = { points: 0, suit: null, bidder: null };
    this.bids = {};
    this.passCount = 0;
    this.bidOrder = [];
    this.currentBidderIndex = 0;
    this.currentPlayer = null;
    this.tricks = [];
    this.currentTrick = [];
    this.pointCards = {};
    this.scores = {};
    this.scoreHistory = []; // [{round, bid, declarer, partner, success, scores: {pid: score}}]
    this.discarded = [];
    this.dealerIndex = 0;
    this.roundResult = null;
    this.jokerSuitDeclared = null; // When joker is led, declarer chooses a suit
    this.jokerCallActive = false; // true when joker-call card is played with jokerCall flag
    this.lastTrickCards = [];
    this.lastTrickWinner = null;
  }

  start() {
    for (const pid of this.playerIds) {
      this.scores[pid] = 0;
    }
    this.startNewRound();
  }

  startNewRound() {
    this.round++;
    this.state = 'dealing';

    // Reset round state
    const { hands, kitty } = deal(this.playerIds);
    this.hands = hands;
    this.kitty = kitty;
    this.trumpSuit = null;
    this.declarer = null;
    this.partner = null;
    this.friendCard = null;
    this.friendRevealed = false;
    this.currentBid = { points: 0, suit: null, bidder: null };
    this.bids = {};
    this.passCount = 0;
    this.currentPlayer = null;
    this.tricks = [];
    this.currentTrick = [];
    this.pointCards = {};
    this.discarded = [];
    this.roundResult = null;
    this.jokerSuitDeclared = null;
    this.jokerCallActive = false;
    this.lastTrickCards = [];
    this.lastTrickWinner = null;

    for (const pid of this.playerIds) {
      this.pointCards[pid] = [];
    }

    // Move dealer (advance by 1 each round)
    this.dealerIndex = (this.dealerIndex + 1) % this.playerCount;

    // Set bid order: starting from left of dealer
    this.bidOrder = [];
    for (let i = 1; i <= this.playerCount; i++) {
      this.bidOrder.push(this.playerIds[(this.dealerIndex + i) % this.playerCount]);
    }
    this.currentBidderIndex = 0;

    this.state = 'bidding';
    this.currentPlayer = this.bidOrder[0];
  }

  getMightyCard() {
    return this.trumpSuit === 'spade' ? 'mighty_diamond_A' : 'mighty_spade_A';
  }

  getJokerCallCard() {
    if (this.options.jokerCallCard !== 'auto') {
      return `mighty_${this.options.jokerCallCard}`;
    }
    return this.trumpSuit === 'club' ? 'mighty_spade_3' : 'mighty_club_3';
  }

  isMightyCard(cardId) {
    return cardId === this.getMightyCard();
  }

  handleAction(playerId, action) {
    switch (action.type) {
      case 'submit_bid': return this._handleBid(playerId, action);
      case 'change_trump': return this._handleChangeTrump(playerId, action);
      case 'raise_bid': return this._handleRaiseBid(playerId, action);
      case 'discard_kitty': return this._handleDiscardKitty(playerId, action);
      case 'play_card': return this._handlePlayCard(playerId, action);
      case 'next_round': return this._handleNextRound(playerId, action);
      default:
        return { success: false, messageKey: 'mighty_invalid_action' };
    }
  }

  // ─── BIDDING ────────────────────────────────────────────

  _handleBid(playerId, action) {
    if (this.state !== 'bidding') {
      return { success: false, messageKey: 'mighty_not_bidding_phase' };
    }
    if (playerId !== this.currentPlayer) {
      return { success: false, messageKey: 'game_not_your_turn' };
    }

    const { points, suit, pass } = action;

    if (pass) {
      this.bids[playerId] = 'pass';
      this.passCount++;
      return this._advanceBidding();
    }

    // Validate bid
    if (!Number.isInteger(points) || points < this.options.minBid || points > 20) {
      return { success: false, messageKey: 'mighty_bid_invalid_points' };
    }
    if (suit !== 'no_trump' && !SUITS.includes(suit)) {
      return { success: false, messageKey: 'mighty_bid_invalid_suit' };
    }
    if (suit === 'no_trump' && !this.options.allowNoTrump) {
      return { success: false, messageKey: 'mighty_no_trump_not_allowed' };
    }

    // Must be higher than current bid
    if (!this._isHigherBid(points, suit)) {
      return { success: false, messageKey: 'mighty_bid_too_low' };
    }

    this.bids[playerId] = { points, suit };
    this.currentBid = { points, suit, bidder: playerId };
    return this._advanceBidding();
  }

  _isHigherBid(points, suit) {
    if (this.currentBid.points === 0) return true;
    if (points > this.currentBid.points) return true;
    if (points === this.currentBid.points) {
      // No trump is higher than suited at same point level
      if (suit === 'no_trump' && this.currentBid.suit !== 'no_trump') return true;
    }
    return false;
  }

  _advanceBidding() {
    // Check if bidding is over
    if (this.passCount >= this.playerCount - 1 && this.currentBid.bidder) {
      // Everyone passed except one bidder
      this._finalizeBidding();
      return { success: true };
    }

    if (this.passCount >= this.playerCount) {
      // Everyone passed - redeal with same dealer (don't inflate round counter)
      const savedDealer = this.dealerIndex;
      const savedRound = this.round;
      this.startNewRound();
      this.round = savedRound;
      this.dealerIndex = savedDealer;
      // Rebuild bid order from same dealer
      this.bidOrder = [];
      for (let i = 1; i <= this.playerCount; i++) {
        this.bidOrder.push(this.playerIds[(this.dealerIndex + i) % this.playerCount]);
      }
      this.currentPlayer = this.bidOrder[0];
      return { success: true };
    }

    // Move to next non-passed player
    let next = this._findNextBidder();
    if (next === null) {
      this._finalizeBidding();
      return { success: true };
    }

    this.currentPlayer = next;
    return { success: true };
  }

  _findNextBidder() {
    const startIdx = this.bidOrder.indexOf(this.currentPlayer);
    for (let i = 1; i <= this.playerCount; i++) {
      const idx = (startIdx + i) % this.playerCount;
      const pid = this.bidOrder[idx];
      if (this.bids[pid] !== 'pass') {
        // If this is the only remaining bidder (the current bid holder)
        if (pid === this.currentBid.bidder) {
          const remaining = this.bidOrder.filter(p => this.bids[p] !== 'pass');
          if (remaining.length <= 1) return null;
        }
        return pid;
      }
    }
    return null;
  }

  _finalizeBidding() {
    this.declarer = this.currentBid.bidder;
    this.trumpSuit = this.currentBid.suit;
    this.state = 'kitty_exchange';
    this.currentPlayer = this.declarer;

    // Declarer picks up kitty
    this.hands[this.declarer] = this.hands[this.declarer].concat(this.kitty);
  }

  // ─── TRUMP CHANGE (during kitty exchange) ───────────────

  _handleChangeTrump(playerId, action) {
    if (this.state !== 'kitty_exchange') {
      return { success: false, messageKey: 'mighty_not_kitty_phase' };
    }
    if (playerId !== this.declarer) {
      return { success: false, messageKey: 'mighty_not_declarer' };
    }
    if (!this.options.allowTrumpChange) {
      return { success: false, messageKey: 'mighty_trump_change_disabled' };
    }

    const { suit } = action;
    if (suit !== 'no_trump' && !SUITS.includes(suit)) {
      return { success: false, messageKey: 'mighty_bid_invalid_suit' };
    }
    if (suit === this.trumpSuit) {
      return { success: false, messageKey: 'mighty_same_trump' };
    }

    const newPoints = Math.min(20, this.currentBid.points + this.options.trumpChangePenalty);
    if (newPoints === this.currentBid.points) {
      return { success: false, messageKey: 'mighty_bid_at_cap' };
    }

    this.trumpSuit = suit;
    this.currentBid.points = newPoints;
    this.currentBid.suit = suit;
    return { success: true };
  }

  // ─── RAISE BID (during kitty exchange, without trump change) ──

  _handleRaiseBid(playerId, action) {
    if (this.state !== 'kitty_exchange') {
      return { success: false, messageKey: 'mighty_not_kitty_phase' };
    }
    if (playerId !== this.declarer) {
      return { success: false, messageKey: 'mighty_not_declarer' };
    }

    const newPoints = Math.min(20, this.currentBid.points + this.options.trumpChangePenalty);
    if (newPoints === this.currentBid.points) {
      return { success: false, messageKey: 'mighty_bid_at_cap' };
    }

    this.currentBid.points = newPoints;
    return { success: true };
  }

  // ─── KITTY EXCHANGE ─────────────────────────────────────

  _handleDiscardKitty(playerId, action) {
    if (this.state !== 'kitty_exchange') {
      return { success: false, messageKey: 'mighty_not_kitty_phase' };
    }
    if (playerId !== this.declarer) {
      return { success: false, messageKey: 'mighty_not_declarer' };
    }

    const { discards, friendCard } = action;

    // Validate discards
    if (!Array.isArray(discards) || discards.length !== 3) {
      return { success: false, messageKey: 'mighty_must_discard_three' };
    }

    // Check for duplicates
    if (new Set(discards).size !== discards.length) {
      return { success: false, messageKey: 'mighty_must_discard_three' };
    }

    const hand = this.hands[this.declarer];
    for (const cardId of discards) {
      if (!hand.includes(cardId)) {
        return { success: false, messageKey: 'mighty_card_not_in_hand' };
      }
    }

    // Cannot discard point cards into kitty (they go to declarer's points)
    // Actually in Mighty, discarded point cards count for declarer at end

    // Cannot discard the mighty card or joker
    const mightyCard = this.getMightyCard();
    if (discards.includes(mightyCard)) {
      return { success: false, messageKey: 'mighty_cannot_discard_mighty' };
    }
    if (discards.includes('mighty_joker')) {
      return { success: false, messageKey: 'mighty_cannot_discard_joker' };
    }

    // Validate friend card
    if (friendCard && friendCard !== 'none') {
      // friendCard must be a valid card id, 'no_friend', or 'first_trick'
      if (friendCard !== 'no_friend' && friendCard !== 'first_trick') {
        if (friendCard !== 'mighty_joker') {
          const info = getCardInfo(friendCard);
          if (!info.suit || !info.rank) {
            return { success: false, messageKey: 'mighty_invalid_friend_card' };
          }
        }
        // Cannot discard the declared friend card
        if (discards.includes(friendCard)) {
          return { success: false, messageKey: 'mighty_cannot_discard_friend' };
        }
      }
    }

    // Perform discard
    this.discarded = discards;
    this.hands[this.declarer] = hand.filter(c => !discards.includes(c));

    // Point cards in discards count for declarer
    for (const cardId of discards) {
      const info = getCardInfo(cardId);
      if (info.point > 0) {
        this.pointCards[this.declarer].push(cardId);
      }
    }

    // Set friend card
    if (!friendCard || friendCard === 'no_friend') {
      this.friendCard = null; // Solo play
    } else {
      this.friendCard = friendCard;
    }

    // Start playing
    this.state = 'playing';
    this.currentPlayer = this.declarer; // Declarer leads first trick
    return { success: true };
  }

  // ─── TRICK PLAY ─────────────────────────────────────────

  _handlePlayCard(playerId, action) {
    if (this.state !== 'playing') {
      return { success: false, messageKey: 'mighty_not_play_phase' };
    }
    if (playerId !== this.currentPlayer) {
      return { success: false, messageKey: 'game_not_your_turn' };
    }

    const { cardId, jokerSuit, jokerCall } = action;
    const hand = this.hands[playerId];

    if (!hand.includes(cardId)) {
      return { success: false, messageKey: 'mighty_card_not_in_hand' };
    }

    // Validate card is legal
    const legalCards = this._getLegalCards(playerId);
    if (!legalCards.includes(cardId)) {
      return { success: false, messageKey: 'mighty_illegal_card' };
    }

    // Joker call: leader plays the joker-call card and declares joker call
    if (this.currentTrick.length === 0) {
      this.jokerCallActive = jokerCall === true;
    }

    // If playing joker as lead, must declare suit (must be an actual suit, not no_trump)
    if (cardId === 'mighty_joker' && this.currentTrick.length === 0) {
      if (!jokerSuit || !SUITS.includes(jokerSuit)) {
        // Default to trump or spade
        this.jokerSuitDeclared = this.trumpSuit && this.trumpSuit !== 'no_trump'
          ? this.trumpSuit : 'spade';
      } else {
        this.jokerSuitDeclared = jokerSuit;
      }
    }

    // Play the card
    this.hands[playerId] = hand.filter(c => c !== cardId);
    this.currentTrick.push({ pid: playerId, cardId });

    // Check friend reveal
    if (this.friendCard && cardId === this.friendCard && !this.friendRevealed) {
      this.partner = playerId;
      this.friendRevealed = true;
    }

    // Check if trick is complete
    if (this.currentTrick.length === this.playerCount) {
      return this._resolveTrick();
    }

    // Next player
    this._advanceToNextPlayer();
    return { success: true };
  }

  _getLegalCards(playerId) {
    const hand = this.hands[playerId];
    if (hand.length === 0) return [];

    // Leading
    if (this.currentTrick.length === 0) {
      // First trick: cannot lead with trump suit cards (joker is still allowed)
      if (this.tricks.length === 0 && this.trumpSuit && this.trumpSuit !== 'no_trump') {
        const nonTrump = hand.filter(c => {
          if (c === 'mighty_joker') return true; // joker always leadable
          const info = getCardInfo(c);
          return info.suit !== this.trumpSuit;
        });
        if (nonTrump.length > 0) return nonTrump;
      }
      return hand;
    }

    const leadCard = this.currentTrick[0].cardId;
    const leadInfo = getCardInfo(leadCard);
    let leadSuit;

    if (leadCard === 'mighty_joker') {
      leadSuit = this.jokerSuitDeclared;
    } else {
      leadSuit = leadInfo.suit;
    }

    // Joker call card led with jokerCall active → joker holder must play joker
    const jokerCallCard = this.getJokerCallCard();
    if (leadCard === jokerCallCard && this.jokerCallActive && hand.includes('mighty_joker')) {
      // Must play joker (unless it's the only card rule - simplified: must play joker)
      return ['mighty_joker'];
    }

    // Joker and mighty can always be played
    const mightyCard = this.getMightyCard();
    const alwaysPlayable = [];
    if (hand.includes('mighty_joker')) alwaysPlayable.push('mighty_joker');
    if (hand.includes(mightyCard)) alwaysPlayable.push(mightyCard);

    // Must follow lead suit if possible (mighty is a normal suit card for follow purposes)
    const suitCards = hand.filter(c => {
      if (c === 'mighty_joker') return false;
      const info = getCardInfo(c);
      return info.suit === leadSuit;
    });

    if (suitCards.length > 0) {
      // Must follow suit, joker also allowed
      const legal = new Set([...suitCards, ...alwaysPlayable]);
      return hand.filter(c => legal.has(c));
    }

    // No suit cards: any card is legal
    return hand;
  }

  _advanceToNextPlayer() {
    const currentIdx = this.playerIds.indexOf(this.currentPlayer);
    this.currentPlayer = this.playerIds[(currentIdx + 1) % this.playerCount];
  }

  _resolveTrick() {
    const trickNumber = this.tricks.length; // 0-indexed
    const isFirstTrick = trickNumber === 0;
    const totalTricks = Math.floor(50 / this.playerCount); // 10 for 5 players
    const isLastTrick = trickNumber === totalTricks - 1;

    const winner = this._determineTrickWinner(isFirstTrick, isLastTrick);

    // Collect point cards
    for (const play of this.currentTrick) {
      const info = getCardInfo(play.cardId);
      if (info.point > 0) {
        this.pointCards[winner].push(play.cardId);
      }
    }

    // Save trick cards for trick_end display before clearing
    this.lastTrickCards = this.currentTrick.map(play => ({
      playerId: play.pid,
      playerName: this.playerNames[play.pid] || play.pid,
      cardId: play.cardId,
    }));
    this.lastTrickWinner = winner;

    // First-trick friend: if friendCard is 'first_trick' and this is trick 0, winner becomes partner
    if (trickNumber === 0 && this.friendCard === 'first_trick' && !this.friendRevealed) {
      this.partner = winner;
      this.friendRevealed = true;
    }

    this.tricks.push({
      leader: this.currentTrick[0].pid,
      cards: this.currentTrick.slice(),
      winner,
    });

    this.currentTrick = [];
    this.jokerSuitDeclared = null;
    this.jokerCallActive = false;

    // Show trick_end state so clients can display the last trick
    this.state = 'trick_end';
    return { success: true };
  }

  advanceAfterTrickEnd() {
    if (this.state !== 'trick_end') return;

    const totalTricks = Math.floor(50 / this.playerCount);
    if (this.tricks.length >= totalTricks) {
      this._endRound();
      return;
    }

    // Winner leads next trick
    this.currentPlayer = this.lastTrickWinner;
    this.state = 'playing';
  }

  _determineTrickWinner(isFirstTrick, isLastTrick) {
    const mightyCard = this.getMightyCard();
    const jokerCallCard = this.getJokerCallCard();
    const leadCard = this.currentTrick[0].cardId;
    const leadInfo = getCardInfo(leadCard);
    let leadSuit = leadCard === 'mighty_joker' ? this.jokerSuitDeclared : leadInfo.suit;

    // Joker loses power when: option says no power on first/last trick, or joker-call card is led with call active
    const jokerIsWeak =
      (isFirstTrick && !this.options.firstTrickJokerPower) ||
      (isLastTrick && !this.options.lastTrickJokerPower) ||
      (leadCard === jokerCallCard && this.jokerCallActive);

    let bestPlay = null;
    let bestPriority = -1;

    for (const play of this.currentTrick) {
      const priority = this._getCardPriority(play.cardId, leadSuit, jokerIsWeak, mightyCard);
      if (priority > bestPriority) {
        bestPriority = priority;
        bestPlay = play;
      }
    }

    return bestPlay.pid;
  }

  _getCardPriority(cardId, leadSuit, jokerIsWeak, mightyCard) {
    // Mighty: highest priority (1000)
    if (cardId === mightyCard) return 1000;

    // Joker: second highest if power is active (900 + rank doesn't matter)
    if (cardId === 'mighty_joker') {
      return jokerIsWeak ? 0 : 900;
    }

    const info = getCardInfo(cardId);

    // Trump suit: 200 + rank value
    if (this.trumpSuit && this.trumpSuit !== 'no_trump' && info.suit === this.trumpSuit) {
      return 200 + RANK_ORDER[info.rank];
    }

    // Lead suit: 100 + rank value
    if (info.suit === leadSuit) {
      return 100 + RANK_ORDER[info.rank];
    }

    // Off-suit: no trick-winning power
    return 0;
  }

  // ─── ROUND END ──────────────────────────────────────────

  _endRound() {
    this.state = 'round_end';

    const result = calculateRoundScores({
      declarer: this.declarer,
      partner: this.partner,
      playerIds: this.playerIds,
      pointCards: this.pointCards,
      bid: this.currentBid.points,
      trumpSuit: this.trumpSuit,
      options: this.options,
    });

    // Apply scores
    for (const pid of this.playerIds) {
      this.scores[pid] += result.scores[pid];
    }

    this.scoreHistory.push({
      round: this.round,
      bid: this.currentBid.points,
      trumpSuit: this.trumpSuit,
      declarer: this.declarer,
      partner: this.partner,
      success: result.success,
      declarerPoints: result.declarerPoints,
      scores: { ...result.scores },
    });

    this.roundResult = result;

    // Check game end
    if (this.options.targetScore) {
      const maxScore = Math.max(...Object.values(this.scores));
      if (maxScore >= this.options.targetScore) {
        this.state = 'game_end';
        return { success: true };
      }
    } else {
      // Single round mode
      this.state = 'game_end';
      return { success: true };
    }

    return { success: true };
  }

  _handleNextRound(playerId, action) {
    if (this.state !== 'round_end') {
      return { success: false, messageKey: 'mighty_not_round_end' };
    }
    this.startNewRound();
    return { success: true };
  }

  /** Called by server auto-advance timer (same pattern as SK/LL) */
  nextRound() {
    if (this.state === 'round_end') {
      this.startNewRound();
    }
  }

  // ─── STATE FOR PLAYER ───────────────────────────────────

  getStateForPlayer(playerId) {
    const playerIdx = this.playerIds.indexOf(playerId);
    const isMyTurn = this.currentPlayer === playerId;
    const legalCards = isMyTurn && this.state === 'playing'
      ? this._getLegalCards(playerId) : [];

    // Build players array (relative positioning, same pattern as SK)
    // Government = declarer + revealed partner; opposition = everyone else
    const governmentIds = new Set();
    if (this.declarer) governmentIds.add(this.declarer);
    if (this.friendRevealed && this.partner) governmentIds.add(this.partner);

    const players = [];
    for (let i = 0; i < this.playerCount; i++) {
      const pid = this.playerIds[(playerIdx + i) % this.playerCount];
      const isSelf = pid === playerId;
      const isGovt = governmentIds.has(pid);
      players.push({
        id: pid,
        name: this.playerNames[pid] || pid,
        position: isSelf ? 'self' : `player_${i}`,
        cardCount: (this.hands[pid] || []).length,
        bid: this.bids[pid] !== undefined ? this.bids[pid] : null,
        trickCount: this.tricks.filter(t => t.winner === pid).length,
        pointCount: countPoints(this.pointCards[pid] || []),
        pointCards: isGovt ? [] : (this.pointCards[pid] || []),
        connected: true,
        timeoutCount: 0,
      });
    }

    // Build current trick with player names
    const currentTrick = this.currentTrick.map(play => ({
      playerId: play.pid,
      playerName: this.playerNames[play.pid] || play.pid,
      cardId: play.cardId,
    }));

    const state = {
      gameType: this.gameType,
      phase: this.state,
      round: this.round,
      players,
      myCards: sortCards(this.hands[playerId] || [], this.trumpSuit),
      trumpSuit: this.trumpSuit,
      declarer: this.declarer,
      friendRevealed: this.friendRevealed,
      partner: this.friendRevealed ? this.partner : null,
      friendCard: this.state !== 'bidding' ? this.friendCard : null,
      currentBid: this.currentBid,
      bids: this._getPublicBids(),
      currentPlayer: this.currentPlayer,
      isMyTurn,
      currentTrick,
      legalCards,
      scores: this.scores,
      scoreHistory: this.scoreHistory,
      roundResult: this.state === 'round_end' || this.state === 'game_end' ? this.roundResult : null,
      mightyCard: this.trumpSuit ? this.getMightyCard() : null,
      jokerCallCard: this.trumpSuit ? this.getJokerCallCard() : null,
      jokerCallActive: this.jokerCallActive,
      lastTrickCards: this.state === 'trick_end' ? this.lastTrickCards : [],
      lastTrickWinner: this.state === 'trick_end' ? this.lastTrickWinner : null,
      tricks: this.tricks.map(t => ({
        leader: t.leader,
        winner: t.winner,
        cards: t.cards.map(c => ({ playerId: c.pid, cardId: c.cardId })),
      })),
    };

    // Kitty phase: show 13 cards to declarer + which cards came from kitty
    if (this.state === 'kitty_exchange' && playerId === this.declarer) {
      state.kittyReceived = true;
      state.kittyCards = this.kitty;
    }

    return state;
  }

  getStateForSpectator(permittedPlayerIds = new Set()) {
    const governmentIds = new Set();
    if (this.declarer) governmentIds.add(this.declarer);
    if (this.friendRevealed && this.partner) governmentIds.add(this.partner);

    const players = this.playerIds.map(pid => ({
      id: pid,
      name: this.playerNames[pid] || pid,
      cards: permittedPlayerIds.has(pid) ? sortCards(this.hands[pid] || [], this.trumpSuit) : [],
      canViewCards: permittedPlayerIds.has(pid),
      cardCount: (this.hands[pid] || []).length,
      bid: this.bids[pid] !== undefined ? this.bids[pid] : null,
      trickCount: this.tricks.filter(t => t.winner === pid).length,
      pointCount: countPoints(this.pointCards[pid] || []),
      pointCards: governmentIds.has(pid) ? [] : (this.pointCards[pid] || []),
    }));

    const currentTrick = this.currentTrick.map(play => ({
      playerId: play.pid,
      playerName: this.playerNames[play.pid] || play.pid,
      cardId: play.cardId,
    }));

    return {
      gameType: this.gameType,
      phase: this.state,
      round: this.round,
      players,
      currentPlayer: this.currentPlayer,
      currentTrick,
      trumpSuit: this.trumpSuit,
      declarer: this.declarer,
      friendRevealed: this.friendRevealed,
      partner: this.friendRevealed ? this.partner : null,
      friendCard: this.state !== 'bidding' ? this.friendCard : null,
      currentBid: this.currentBid,
      bids: this._getPublicBids(),
      scores: this.scores,
      scoreHistory: this.scoreHistory,
      roundResult: this.state === 'round_end' || this.state === 'game_end' ? this.roundResult : null,
      mightyCard: this.trumpSuit ? this.getMightyCard() : null,
      jokerCallCard: this.trumpSuit ? this.getJokerCallCard() : null,
      jokerCallActive: this.jokerCallActive,
      lastTrickCards: this.state === 'trick_end' ? this.lastTrickCards : [],
      lastTrickWinner: this.state === 'trick_end' ? this.lastTrickWinner : null,
      tricks: this.tricks.map(t => ({
        leader: t.leader,
        winner: t.winner,
        cards: t.cards.map(c => ({ playerId: c.pid, cardId: c.cardId })),
      })),
    };
  }

  _getPublicBids() {
    const pub = {};
    for (const pid of this.playerIds) {
      if (this.bids[pid] !== undefined) {
        pub[pid] = this.bids[pid];
      }
    }
    return pub;
  }

  _getTrickCounts() {
    const counts = {};
    for (const pid of this.playerIds) {
      counts[pid] = this.tricks.filter(t => t.winner === pid).length;
    }
    return counts;
  }

  _getPointCounts() {
    const counts = {};
    for (const pid of this.playerIds) {
      counts[pid] = countPoints(this.pointCards[pid] || []);
    }
    return counts;
  }

  // ─── RECONNECT ─────────────────────────────────────────

  updatePlayerId(oldId, newId) {
    // playerIds
    const idx = this.playerIds.indexOf(oldId);
    if (idx >= 0) this.playerIds[idx] = newId;

    // playerNames
    if (this.playerNames[oldId] !== undefined) {
      this.playerNames[newId] = this.playerNames[oldId];
      delete this.playerNames[oldId];
    }

    // hands
    if (this.hands[oldId] !== undefined) {
      this.hands[newId] = this.hands[oldId];
      delete this.hands[oldId];
    }

    // pointCards
    if (this.pointCards[oldId] !== undefined) {
      this.pointCards[newId] = this.pointCards[oldId];
      delete this.pointCards[oldId];
    }

    // scores
    if (this.scores[oldId] !== undefined) {
      this.scores[newId] = this.scores[oldId];
      delete this.scores[oldId];
    }

    // bids
    if (this.bids[oldId] !== undefined) {
      this.bids[newId] = this.bids[oldId];
      delete this.bids[oldId];
    }

    // bidOrder
    const bidIdx = this.bidOrder.indexOf(oldId);
    if (bidIdx >= 0) this.bidOrder[bidIdx] = newId;

    // currentPlayer
    if (this.currentPlayer === oldId) this.currentPlayer = newId;

    // declarer / partner
    if (this.declarer === oldId) this.declarer = newId;
    if (this.partner === oldId) this.partner = newId;

    // currentBid.bidder
    if (this.currentBid && this.currentBid.bidder === oldId) {
      this.currentBid.bidder = newId;
    }

    // lastTrickWinner
    if (this.lastTrickWinner === oldId) this.lastTrickWinner = newId;

    // lastTrickCards
    for (const play of this.lastTrickCards) {
      if (play.playerId === oldId) play.playerId = newId;
    }

    // currentTrick
    for (const play of this.currentTrick) {
      if (play.pid === oldId) play.pid = newId;
    }

    // completed tricks
    for (const trick of this.tricks) {
      if (trick.winner === oldId) trick.winner = newId;
      if (trick.leader === oldId) trick.leader = newId;
      if (Array.isArray(trick.cards)) {
        for (const play of trick.cards) {
          if (play.pid === oldId) play.pid = newId;
        }
      }
    }

    // roundResult (scores keyed by player id)
    if (this.roundResult && this.roundResult.scores && this.roundResult.scores[oldId] !== undefined) {
      this.roundResult.scores[newId] = this.roundResult.scores[oldId];
      delete this.roundResult.scores[oldId];
    }

    // scoreHistory
    for (const entry of this.scoreHistory) {
      if (entry.scores && entry.scores[oldId] !== undefined) {
        entry.scores[newId] = entry.scores[oldId];
        delete entry.scores[oldId];
      }
      if (entry.declarer === oldId) entry.declarer = newId;
      if (entry.partner === oldId) entry.partner = newId;
    }
  }

  // ─── AUTO TIMEOUT ───────────────────────────────────────

  getAutoTimeoutAction(playerId) {
    if (this.state === 'bidding' && this.currentPlayer === playerId) {
      return { type: 'submit_bid', pass: true };
    }

    if (this.state === 'kitty_exchange' && playerId === this.declarer) {
      const hand = this.hands[playerId];
      const mighty = this.getMightyCard();
      // Discard 3 weakest cards, excluding mighty and joker
      const safe = hand.filter(c => c !== mighty && c !== 'mighty_joker');
      const nonPoint = safe.filter(c => getCardInfo(c).point === 0);
      const discards = nonPoint.length >= 3
        ? nonPoint.slice(-3)
        : safe.slice(0, 3);
      // Pick a friend card: mighty if not in hand, otherwise no_friend
      const friendCard = hand.includes(mighty) ? 'no_friend' : mighty;
      return { type: 'discard_kitty', discards, friendCard };
    }

    if (this.state === 'playing' && this.currentPlayer === playerId) {
      const legalCards = this._getLegalCards(playerId);
      if (legalCards.length > 0) {
        const cardId = legalCards[Math.floor(Math.random() * legalCards.length)];
        const result = { type: 'play_card', cardId };
        if (cardId === 'mighty_joker' && this.currentTrick.length === 0) {
          result.jokerSuit = this.trumpSuit && this.trumpSuit !== 'no_trump'
            ? this.trumpSuit : 'spade';
        }
        // Bot always activates joker call when leading the joker-call card
        if (this.currentTrick.length === 0 && cardId === this.getJokerCallCard()) {
          result.jokerCall = true;
        }
        return result;
      }
    }

    return null;
  }
}

module.exports = MightyGame;
