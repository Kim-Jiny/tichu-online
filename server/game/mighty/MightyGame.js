'use strict';

const { SUITS, RANKS, RANK_ORDER, deal, getCardInfo, sortCards } = require('./MightyDeck');
const { countPoints, calculateRoundScores } = require('./MightyScoring');
const { mapKeys, mapId } = require('../historyIds');

class MightyGame {
  constructor(playerIds, playerNames, options = {}) {
    this.playerIds = playerIds;
    this.playerNames = playerNames;
    this.playerCount = playerIds.length; // 5 (or 6 future)
    this.gameType = 'mighty';

    // Randomness source. Defaults to Math.random (production). Pass options.rng
    // (e.g. MightyDeck.makeRng(seed)) for reproducible deals in tests/sim A-B.
    this._rng = typeof options.rng === 'function' ? options.rng : Math.random;

    // Mode: '6p' starts kill-mighty (8 cards + 5 kitty + kill phase + min bid 14 + deal-miss 0)
    //       '5p' is classic mighty (10 cards + 3 kitty + no kill + min bid 13 + deal-miss 0.5).
    // After a kill or suicide, a 6p game transitions to '5p' semantics for the remaining
    // tricks (or the re-bid after suicide).
    const is6p = playerIds.length >= 6;
    this.mode = is6p ? '6p' : '5p';
    this.activePlayerCount = playerIds.length;
    this.excludedPlayers = new Set();

    // Options (house rules)
    this.options = {
      minBid: options.minBid || (is6p ? 14 : 13),
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
    this.dealMissPool = 0; // Accumulated points paid by deal-miss declarers; goes to next successful declarer
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
    this.lastDealMissEvent = null; // { playerId, playerName, cards, handScore, round } — visible to all; dismiss by tap locally, server clears on next round
    this.lastKillEvent = null; // { declarerId, declarerName, targetCardId, victimId, victimName, wasKitty } — same tap-to-dismiss UX
    this.lastSettingEvent = null; // { playerId, playerName, cards, round } — set when a player declares 세팅 (skip-remaining-tricks claim); cleared at next round
    this.newlyReceivedCards = {}; // pid → [cardId, ...] highlight for post-kill redistribution; cleared when kitty phase ends
    this.revealGracePeriodEndAt = 0; // when a reveal event fires, bot actions are held until this timestamp (ms since epoch) so players can read the overlay
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
    const { hands, kitty } = deal(this.playerIds, this._rng);
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
    this.lastDealMissEvent = null;
    this.lastKillEvent = null;
    this.lastSettingEvent = null;
    this.newlyReceivedCards = {};

    // Restore mode/active count for a fresh round — previous round may have ended in 5p
    // semantics (kill/suicide), but a new 6-player round starts fresh in 6p mode.
    if (this.playerCount >= 6) {
      this.mode = '6p';
      this.options.minBid = 14;
    } else {
      this.mode = '5p';
      this.options.minBid = 13;
    }
    this.excludedPlayers = new Set();
    this.activePlayerCount = this.playerCount;

    for (const pid of this.playerIds) {
      this.pointCards[pid] = [];
    }

    // Move dealer (advance by 1 each round)
    this.dealerIndex = (this.dealerIndex + 1) % this.playerCount;

    // Set bid order: active players only, starting from left of dealer
    this.bidOrder = this._buildBidOrder();
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
      case 'declare_deal_miss': return this._handleDealMiss(playerId, action);
      case 'declare_kill': return this._handleDeclareKill(playerId, action);
      case 'change_trump': return this._handleChangeTrump(playerId, action);
      case 'raise_bid': return this._handleRaiseBid(playerId, action);
      case 'discard_kitty': return this._handleDiscardKitty(playerId, action);
      case 'play_card': return this._handlePlayCard(playerId, action);
      case 'declare_setting': return this._handleDeclareSetting(playerId, action);
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

  // ─── DEAL MISS ──────────────────────────────────────────
  //
  // During bidding, before you have made any bid or pass, if your hand is
  // very weak (≤ 0.5 deal-miss points) you may declare a deal miss.
  // You pay 5 points into a pool; the pool is awarded to the next declarer
  // who succeeds. Scoring (only for deal-miss eligibility):
  //   spade A = 0, joker = erases the strongest point card,
  //   A/K/Q/J = 1, 10 = 0.5.
  _evaluateDealMissScore(hand) {
    let total = 0;
    let hasJoker = false;
    let maxCardValue = 0;
    for (const cardId of hand) {
      if (cardId === 'mighty_joker') { hasJoker = true; continue; }
      if (cardId === 'mighty_spade_A') continue; // mighty — worth 0
      const info = getCardInfo(cardId);
      let v = 0;
      if (info.rank === 'A' || info.rank === 'K' || info.rank === 'Q' || info.rank === 'J') v = 1;
      else if (info.rank === '10') v = 0.5;
      if (v > 0) {
        total += v;
        if (v > maxCardValue) maxCardValue = v;
      }
    }
    if (hasJoker) total -= maxCardValue;
    if (total < 0) total = 0;
    return total;
  }

  _dealMissThreshold() {
    // 6p kill-mighty: must be exactly 0. 5p classic: 0.5 or lower.
    return this.mode === '6p' ? 0 : 0.5;
  }

  /** Active (non-excluded) seats starting from the player left of the dealer. */
  _buildBidOrder() {
    const order = [];
    for (let i = 1; i <= this.playerCount; i++) {
      const pid = this.playerIds[(this.dealerIndex + i) % this.playerCount];
      if (!this.excludedPlayers.has(pid)) order.push(pid);
    }
    return order;
  }

  _canDeclareDealMiss(playerId) {
    if (this.state !== 'bidding') return false;
    if (this.currentPlayer !== playerId) return false;
    if (this.bids[playerId] !== undefined) return false;
    return this._evaluateDealMissScore(this.hands[playerId] || []) <= this._dealMissThreshold();
  }

  _handleDealMiss(playerId, action) {
    if (this.state !== 'bidding') {
      return { success: false, messageKey: 'mighty_not_bidding_phase' };
    }
    if (playerId !== this.currentPlayer) {
      return { success: false, messageKey: 'game_not_your_turn' };
    }
    if (this.bids[playerId] !== undefined) {
      return { success: false, messageKey: 'mighty_deal_miss_already_acted' };
    }
    const handScore = this._evaluateDealMissScore(this.hands[playerId] || []);
    if (handScore > this._dealMissThreshold()) {
      return { success: false, messageKey: 'mighty_deal_miss_hand_too_strong' };
    }

    // Snapshot the revealed hand BEFORE redealing (so everyone can see what was called)
    const eventRound = this.round;
    const eventPlayerName = this.playerNames[playerId] || playerId;
    const eventCards = [...(this.hands[playerId] || [])];

    // Penalty: 5 points off declarer, into the pool
    this.scores[playerId] -= 5;
    this.dealMissPool += 5;

    // Record the event in history so it's visible on the scoreboard
    const histScores = {};
    for (const pid of this.playerIds) histScores[pid] = (pid === playerId) ? -5 : 0;
    this.scoreHistory.push({
      round: this.round,
      dealMiss: true,
      dealMisser: playerId,
      dealMissPool: this.dealMissPool,
      handScore,
      scores: histScores,
    });

    // Redeal with the SAME dealer (same-dealer semantics like "everyone passed"),
    // but do advance the round counter so this shows as a distinct round.
    const savedDealer = this.dealerIndex;
    this.startNewRound();
    this.dealerIndex = savedDealer;
    this.bidOrder = this._buildBidOrder();
    this.currentPlayer = this.bidOrder[0];

    // Publish the reveal so every client can show who declared and what they held
    this.lastDealMissEvent = {
      playerId,
      playerName: eventPlayerName,
      cards: sortCards(eventCards, null),
      handScore,
      round: eventRound,
    };
    this.revealGracePeriodEndAt = Date.now() + 1000;
    return { success: true };
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
    const active = this.activePlayerCount;

    // 20 NT is the true ceiling (nothing can beat it) → instant win. A 20
    // suited bid can still be raised to 20 NT by another player, so keep
    // the bidding loop running in that case.
    if (this.currentBid.points === 20 && this.currentBid.suit === 'no_trump') {
      this._finalizeBidding();
      return { success: true };
    }

    // Check if bidding is over (everyone passed except one bidder)
    if (this.passCount >= active - 1 && this.currentBid.bidder) {
      this._finalizeBidding();
      return { success: true };
    }

    if (this.passCount >= active) {
      // Everyone passed - redeal with same dealer (don't inflate round counter)
      const savedDealer = this.dealerIndex;
      const savedRound = this.round;
      this.startNewRound();
      this.round = savedRound;
      this.dealerIndex = savedDealer;
      // Rebuild bid order from same dealer
      this.bidOrder = this._buildBidOrder();
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
    const n = this.bidOrder.length;
    for (let i = 1; i <= n; i++) {
      const idx = (startIdx + i) % n;
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
    this.currentPlayer = this.declarer;

    if (this.mode === '6p') {
      // 6p kill-mighty: declarer picks a kill target before touching the kitty
      this.state = 'kill_select';
    } else {
      // 5p classic: declarer picks up the 3-card kitty immediately
      this.state = 'kitty_exchange';
      this.hands[this.declarer] = this.hands[this.declarer].concat(this.kitty);
    }
  }

  // ─── KILL PHASE (6p kill-mighty) ────────────────────────
  //
  // After bidding in 6p mode, the declarer picks a "kill target" card that
  // they do NOT hold. If the target is in another player's hand, that player
  // is eliminated from the round (0 points); their 8-card hand plus the
  // 5-card kitty (13 cards) are shuffled and redistributed so the declarer
  // receives 5 new cards and each of the other 4 survivors receives 2. The
  // game then proceeds as 5-player mighty from kitty-exchange onward.
  //
  // If the target card is in the kitty, the declarer commits "suicide":
  // their hand + kitty (13 cards) are shuffled, 2 each go to the other 5
  // players, 3 become the new kitty, and bidding restarts in 5p mode.
  //
  // Either way the killed/suicided player is out of the round and scores 0.

  _handleDeclareKill(playerId, action) {
    if (this.state !== 'kill_select') {
      return { success: false, messageKey: 'mighty_not_kill_phase' };
    }
    if (playerId !== this.declarer) {
      return { success: false, messageKey: 'mighty_not_declarer' };
    }
    const { cardId } = action || {};
    if (!cardId || typeof cardId !== 'string') {
      return { success: false, messageKey: 'mighty_invalid_kill_target' };
    }
    if ((this.hands[playerId] || []).includes(cardId)) {
      return { success: false, messageKey: 'mighty_kill_in_own_hand' };
    }

    let victimId = null;
    let wasKitty = false;
    if (this.kitty.includes(cardId)) {
      wasKitty = true;
    } else {
      for (const pid of this.playerIds) {
        if (pid === this.declarer) continue;
        if ((this.hands[pid] || []).includes(cardId)) {
          victimId = pid;
          break;
        }
      }
      if (!victimId) {
        return { success: false, messageKey: 'mighty_invalid_kill_target' };
      }
    }

    // Build reveal event for all clients. (New cards-each player receives
    // are stored in this.newlyReceivedCards and shown during kitty phase.)
    this.lastKillEvent = {
      declarerId: this.declarer,
      declarerName: this.playerNames[this.declarer] || this.declarer,
      targetCardId: cardId,
      victimId: wasKitty ? this.declarer : victimId,
      victimName: wasKitty
        ? (this.playerNames[this.declarer] || this.declarer)
        : (this.playerNames[victimId] || victimId),
      wasKitty,
    };
    this.revealGracePeriodEndAt = Date.now() + 1000;

    if (wasKitty) {
      this._resolveSuicide();
    } else {
      this._resolveKill(victimId);
    }
    return { success: true };
  }

  _shuffle(arr) {
    const a = arr.slice();
    const rng = this._rng || Math.random;
    for (let i = a.length - 1; i > 0; i--) {
      const j = Math.floor(rng() * (i + 1));
      [a[i], a[j]] = [a[j], a[i]];
    }
    return a;
  }

  _resolveKill(victimId) {
    // Pool = victim's 8-card hand + the 5-card kitty = 13 cards
    const pool = this._shuffle([...(this.hands[victimId] || []), ...this.kitty]);
    this.newlyReceivedCards = {};

    // Declarer gets 5 added → total 13 (8 original + 5 new)
    const forDeclarer = pool.slice(0, 5);
    this.hands[this.declarer] = this.hands[this.declarer].concat(forDeclarer);
    this.newlyReceivedCards[this.declarer] = forDeclarer;

    // 4 surviving non-declarer, non-victim players get 2 each
    let idx = 5;
    for (const pid of this.playerIds) {
      if (pid === this.declarer || pid === victimId) continue;
      const got = pool.slice(idx, idx + 2);
      idx += 2;
      this.hands[pid] = (this.hands[pid] || []).concat(got);
      this.newlyReceivedCards[pid] = got;
    }

    // Victim is emptied and excluded from the round
    this.hands[victimId] = [];
    this.excludedPlayers.add(victimId);
    this.activePlayerCount = this.playerCount - this.excludedPlayers.size;

    // From here on the round follows 5p semantics
    this.mode = '5p';
    this.options.minBid = 13;
    this.kitty = []; // consumed by redistribution; the declarer will discard 3 below

    // Declarer now holds 13 cards — enter normal 5p kitty exchange (discard 3)
    this.state = 'kitty_exchange';
    this.currentPlayer = this.declarer;
  }

  _resolveSuicide() {
    // Pool = declarer's 8 + kitty 5 = 13 cards
    const pool = this._shuffle([...(this.hands[this.declarer] || []), ...this.kitty]);
    this.newlyReceivedCards = {};

    // 5 surviving (non-declarer) players each get 2 cards
    let idx = 0;
    for (const pid of this.playerIds) {
      if (pid === this.declarer) continue;
      const got = pool.slice(idx, idx + 2);
      idx += 2;
      this.hands[pid] = (this.hands[pid] || []).concat(got);
      this.newlyReceivedCards[pid] = got;
    }

    // Remaining 3 cards become the new kitty
    this.kitty = pool.slice(idx);

    const suicidedDeclarer = this.declarer;
    this.hands[suicidedDeclarer] = [];
    this.excludedPlayers.add(suicidedDeclarer);
    this.activePlayerCount = this.playerCount - this.excludedPlayers.size;

    // Switch to 5p rules for the re-bid
    this.mode = '5p';
    this.options.minBid = 13;

    // Reset bidding state (suicided declarer is out, survivors re-bid fresh)
    this.declarer = null;
    this.trumpSuit = null;
    this.currentBid = { points: 0, suit: null, bidder: null };
    this.bids = {};
    this.passCount = 0;

    // Bid order: active (non-excluded) seats starting from left of original dealer
    this.bidOrder = this._buildBidOrder();
    this.currentPlayer = this.bidOrder[0];
    this.state = 'bidding';
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

    // At the 20-point ceiling:
    //   • 20 NT is the hard ceiling — no contract change of any kind.
    //   • 20 with a suit can only be changed to 20 NT (no penalty, no other suit).
    if (this.currentBid.points >= 20) {
      if (this.currentBid.suit === 'no_trump') {
        return { success: false, messageKey: 'mighty_bid_at_cap' };
      }
      if (suit !== 'no_trump') {
        return { success: false, messageKey: 'mighty_20suit_only_nt' };
      }
      this.trumpSuit = suit;
      this.currentBid.suit = suit;
      return { success: true };
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

    // Kitty-exchange is over — drop any post-kill redistribution highlights
    this.newlyReceivedCards = {};
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

    // Joker call: leader plays the joker-call card and declares joker call.
    // Ignored when joker has no power in this trick (first/last trick with
    // their respective *JokerPower option disabled) — calling the joker is
    // pointless since it can't win there anyway.
    if (this.currentTrick.length === 0) {
      this.jokerCallActive =
        jokerCall === true && this._currentTrickJokerHasPower();
    }

    // If playing joker as lead, a real suit must be declared — no silent
    // default. The client now blocks the Play button until the user picks;
    // this is the server-side defense for old or misbehaving clients.
    if (cardId === 'mighty_joker' && this.currentTrick.length === 0) {
      // 힘없는 조커는 무늬를 부르지 않는다(기본 옵션에서 1트릭·막 트릭).
      // 어차피 지는 카드라 부른 무늬로 남을 묶을 이유가 없다 — 리드 무늬는
      // 다음 사람이 내는 카드가 정한다(_leadSuitOf 참고). 옛 클라이언트가
      // 무늬를 실어 보내도 그냥 버린다.
      if (this._currentTrickJokerHasPower()) {
        if (!jokerSuit || !SUITS.includes(jokerSuit)) {
          return { success: false, messageKey: 'mighty_joker_suit_required' };
        }
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
    if (this.currentTrick.length === this.activePlayerCount) {
      return this._resolveTrick();
    }

    // Next player
    this._advanceToNextPlayer();
    return { success: true };
  }

  _countRemainingTrumps() {
    if (!this.trumpSuit || this.trumpSuit === 'no_trump') return null;
    let count = 0;
    for (const pid of this.playerIds) {
      const hand = this.hands[pid] || [];
      for (const cardId of hand) {
        if (cardId === 'mighty_joker') continue;
        const info = getCardInfo(cardId);
        if (info.suit === this.trumpSuit) count++;
      }
    }
    return { count, suit: this.trumpSuit };
  }

  _getLegalCards(playerId) {
    const hand = this.hands[playerId] || [];
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
    const leadSuit = this._leadSuitOf(this.currentTrick);

    // Joker call card led with jokerCall active → joker holder must play
    // joker, UNLESS they also hold the Mighty (Mighty defends the call;
    // joker-call cannot pull the Mighty out). Letting Mighty stand as a
    // second legal option preserves the standard Korean-Mighty defense.
    const jokerCallCard = this.getJokerCallCard();
    if (leadCard === jokerCallCard && this.jokerCallActive && hand.includes('mighty_joker')) {
      const mightyCardForCall = this.getMightyCard();
      if (mightyCardForCall && hand.includes(mightyCardForCall)) {
        return ['mighty_joker', mightyCardForCall];
      }
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
    // Skip any excluded seats (killed/suicided in kill-mighty)
    for (let i = 1; i <= this.playerCount; i++) {
      const nextPid = this.playerIds[(currentIdx + i) % this.playerCount];
      if (!this.excludedPlayers.has(nextPid)) {
        this.currentPlayer = nextPid;
        return;
      }
    }
  }

  _totalTricksThisRound() {
    // Total cards in play / active seats. For 5p (or 6p post-kill) this is 10.
    return Math.floor(50 / this.activePlayerCount);
  }

  // True when joker retains full power in the trick currently being led.
  // First/last trick joker power is option-gated; when joker has no power
  // there, joker-call has no meaning and must not be honored.
  /**
   * 이 트릭의 리드 무늬.
   *
   * 보통은 첫 카드의 무늬고, 조커로 리드하면 부른 무늬다. 단 힘없는 조커는
   * (기본 옵션에서 1트릭·막 트릭) 무늬를 부르지 않는다 — 그때는 두 번째로
   * 나온 카드가 리드 무늬를 정한다.
   *
   * 그래야 조커가 지는 카드로 남는다. 부른 무늬를 그대로 쓰면, 그 무늬를
   * 아무도 안 들었을 때 나머지가 전부 우선순위 0 으로 묶이고 맨 앞에 놓인
   * 조커가 그 트릭을 가져가 버린다.
   *
   * 두 번째 카드가 아직 안 나왔으면 null 이다. 그 시점에는 따라낼 무늬가
   * 정해지지 않았다는 뜻이라 두 번째 사람은 아무거나 낼 수 있다.
   */
  _leadSuitOf(plays) {
    if (!plays || plays.length === 0) return null;
    const leadCard = plays[0].cardId;
    if (leadCard !== 'mighty_joker') return getCardInfo(leadCard).suit;
    if (this._currentTrickJokerHasPower()) return this.jokerSuitDeclared;
    const second = plays[1];
    if (!second) return null;
    return second.cardId === 'mighty_joker'
      ? null
      : getCardInfo(second.cardId).suit;
  }

  _currentTrickJokerHasPower() {
    const trickIdx = this.tricks.length;
    const totalTricks = this._totalTricksThisRound();
    const isFirst = trickIdx === 0;
    const isLast = trickIdx === totalTricks - 1;
    if (isFirst && !this.options.firstTrickJokerPower) return false;
    if (isLast && !this.options.lastTrickJokerPower) return false;
    return true;
  }

  _resolveTrick() {
    const trickNumber = this.tricks.length; // 0-indexed
    const isFirstTrick = trickNumber === 0;
    const totalTricks = this._totalTricksThisRound();
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

    const leadSuit = this._leadSuitOf(this.currentTrick);

    this.tricks.push({
      leader: this.currentTrick[0].pid,
      leadSuit,
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

    const totalTricks = this._totalTricksThisRound();
    if (this.tricks.length >= totalTricks) {
      this._endRound();
      return;
    }

    // Winner leads next trick
    this.currentPlayer = this.lastTrickWinner;
    this.state = 'playing';
  }

  // ─── SETTING (세팅) ─────────────────────────────────────
  //
  // A player on lead whose remaining hand is unconditionally winning can
  // declare 세팅: reveal the hand, skip the remaining tricks, and have all
  // remaining point cards awarded to their collection. Lead-only because
  // the detection assumes the setter chooses which card enters each trick.

  /**
   * True iff `playerId` is currently eligible to declare setting:
   *   - playing phase, leading (empty current trick), their turn
   *   - not an excluded mighty seat
   *   - hand is non-empty (1-card setting allowed if the card is itself
   *     unconditional — equivalent UX-wise to playing it on the last
   *     trick, but exposed as a declaration for consistency)
   *   - every card in their hand is beyond anything the rest of the room
   *     could legally play against it given the remaining-trick rules.
   */
  _canDeclareSetting(playerId) {
    if (this.state !== 'playing') return false;
    if (this.currentPlayer !== playerId) return false;
    if (this.currentTrick.length !== 0) return false;
    if (this.excludedPlayers.has(playerId)) return false;
    const hand = this.hands[playerId];
    if (!hand || hand.length === 0) return false;

    const mightyCard = this.getMightyCard();
    const trump = this.trumpSuit;
    const hasTrump = trump && trump !== 'no_trump';

    // Collective pool of everything still in other (active) seats' hands.
    // Suit-distribution among opponents is unknown, so any "any opp could
    // ruff" or "any opp could follow-suit higher" situation defeats the
    // declaration conservatively.
    const oppPool = new Set();
    for (const pid of this.playerIds) {
      if (pid === playerId) continue;
      if (this.excludedPlayers.has(pid)) continue;
      for (const c of this.hands[pid] || []) oppPool.add(c);
    }

    const totalTricks = this._totalTricksThisRound();
    const lastTrickIdx = totalTricks - 1;
    const remainingIndices = [];
    for (let i = 0; i < hand.length; i++) remainingIndices.push(this.tricks.length + i);
    const weakTrick = (idx) =>
      (idx === 0 && !this.options.firstTrickJokerPower) ||
      (idx === lastTrickIdx && !this.options.lastTrickJokerPower);
    const allRemainingWeak = remainingIndices.every(weakTrick);
    const anyRemainingStrong = remainingIndices.some(i => !weakTrick(i));

    const rankIdx = (r) => RANK_ORDER[r] || 0;

    for (const cardId of hand) {
      if (cardId === mightyCard) continue; // unconditional winner

      if (cardId === 'mighty_joker') {
        if (allRemainingWeak) return false;   // joker can't lead any remaining trick
        if (oppPool.has(mightyCard)) return false; // opp mighty overcuts
        continue;
      }

      const info = getCardInfo(cardId);
      if (!info) return false;
      const isTrumpCard = hasTrump && info.suit === trump;

      if (isTrumpCard) {
        // Any higher trump still out beats us.
        const myRank = rankIdx(info.rank);
        for (const r of Object.keys(RANK_ORDER)) {
          if (rankIdx(r) <= myRank) continue;
          const id = `mighty_${trump}_${r}`;
          if (id === mightyCard) continue; // handled separately
          if (oppPool.has(id)) return false;
        }
        if (oppPool.has(mightyCard)) return false;
        // Joker beats any trump (except mighty). If a non-weak trick remains
        // and opp holds joker, opp saves it for a non-weak trick.
        if (oppPool.has('mighty_joker') && anyRemainingStrong) return false;
        continue;
      }

      // Non-trump lead.
      if (oppPool.has(mightyCard)) return false;
      if (oppPool.has('mighty_joker') && anyRemainingStrong) return false;
      // Higher same-suit in opp pool → opp follows suit and wins.
      const myRank = rankIdx(info.rank);
      for (const r of Object.keys(RANK_ORDER)) {
        if (rankIdx(r) <= myRank) continue;
        const id = `mighty_${info.suit}_${r}`;
        if (id === mightyCard) continue;
        if (oppPool.has(id)) return false;
      }
      // Any trump left in opp pool is a latent ruff: since the setter
      // holds no more of this suit worth checking (we already covered the
      // higher-rank follow above) and suit distribution is unknown, at
      // least one opp may be void and able to ruff. Treat conservatively.
      if (hasTrump) {
        for (const c of oppPool) {
          if (c === 'mighty_joker' || c === mightyCard) continue;
          const ci = getCardInfo(c);
          if (ci && ci.suit === trump) return false;
        }
      }
    }
    return true;
  }

  _handleDeclareSetting(playerId, _action) {
    if (!this._canDeclareSetting(playerId)) {
      return { success: false, messageKey: 'mighty_setting_invalid' };
    }
    const hand = this.hands[playerId] || [];
    const snapshot = sortCards([...hand], this.trumpSuit);

    // Setting skips the remaining tricks, so a friend card still sitting in
    // someone's hand would never be played and the round would score as
    // 노프렌드 (isSolo) even though a friend exists. Resolve it now — the round
    // ends immediately after this, so revealing leaks nothing.
    if (!this.friendRevealed && this.friendCard) {
      if (this.friendCard === 'first_trick') {
        // 초구 프렌드 with trick 0 skipped: the skipped tricks are all
        // attributed to the setter, so the setter takes the first trick.
        this.partner = playerId;
        this.friendRevealed = true;
      } else {
        for (const pid of this.playerIds) {
          if (this.excludedPlayers.has(pid)) continue;
          if ((this.hands[pid] || []).includes(this.friendCard)) {
            this.partner = pid;
            this.friendRevealed = true;
            break;
          }
        }
      }
    }

    // Award every remaining point card (across all active hands) to the
    // setter. Non-point remainders just get discarded — they don't affect
    // the score calculation.
    for (const pid of this.playerIds) {
      if (this.excludedPlayers.has(pid)) continue;
      for (const cardId of this.hands[pid] || []) {
        const info = getCardInfo(cardId);
        if (info && info.point > 0) {
          this.pointCards[playerId].push(cardId);
        }
      }
      this.hands[pid] = [];
    }

    // Pad the tricks array so the completed-trick count stays correct for
    // UI stats (each skipped trick is attributed to the setter).
    const totalTricks = this._totalTricksThisRound();
    while (this.tricks.length < totalTricks) {
      this.tricks.push({
        leader: playerId,
        winner: playerId,
        cards: [],
        setting: true,
      });
    }

    this.lastSettingEvent = {
      playerId,
      playerName: this.playerNames[playerId] || playerId,
      cards: snapshot,
      round: this.round,
    };
    this.revealGracePeriodEndAt = Date.now() + 1000;

    this._endRound();
    return { success: true };
  }

  _determineTrickWinner(isFirstTrick, isLastTrick) {
    const mightyCard = this.getMightyCard();
    const jokerCallCard = this.getJokerCallCard();
    const leadCard = this.currentTrick[0].cardId;
    let leadSuit = this._leadSuitOf(this.currentTrick);

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

    // Excluded players (killed/suicided in kill-mighty) score 0; only active
    // seats take part in the declarer-vs-defenders scoring calculation.
    const activePlayerIds = this.playerIds.filter(pid => !this.excludedPlayers.has(pid));

    const result = calculateRoundScores({
      declarer: this.declarer,
      partner: this.partner,
      playerIds: activePlayerIds,
      pointCards: this.pointCards,
      bid: this.currentBid.points,
      trumpSuit: this.trumpSuit,
      options: this.options,
    });

    // Fill 0 for excluded players so downstream UI doesn't miss them
    for (const pid of this.playerIds) {
      if (!(pid in result.scores)) result.scores[pid] = 0;
    }

    // Apply scores
    for (const pid of this.playerIds) {
      this.scores[pid] += result.scores[pid];
    }

    // Deal-miss pool: awarded in full to the declarer on success
    let dealMissBonus = 0;
    if (result.success && this.dealMissPool > 0) {
      dealMissBonus = this.dealMissPool;
      this.scores[this.declarer] += dealMissBonus;
      this.dealMissPool = 0;
      // Reflect the bonus in result.scores so round-end UI matches cumulative totals
      result.scores[this.declarer] = (result.scores[this.declarer] || 0) + dealMissBonus;
    }
    result.dealMissBonus = dealMissBonus;

    const historyScores = { ...result.scores };

    this.scoreHistory.push({
      round: this.round,
      bid: this.currentBid.points,
      trumpSuit: this.trumpSuit,
      declarer: this.declarer,
      partner: this.partner,
      success: result.success,
      declarerPoints: result.declarerPoints,
      dealMissBonus,
      scores: historyScores,
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

  // ─── MATCH MIGRATION (blue/green drain) ─────────────────
  // See TichuGame.getMatchProgress. Nickname-keyed so the payload
  // survives the playerId remap a reconnect performs on the peer.

  getMatchProgress() {
    const toNickname = (pid) => this.playerNames[pid];
    const totals = {};
    for (const pid of this.playerIds) {
      totals[this.playerNames[pid]] = this.scores[pid] || 0;
    }
    return {
      round: this.round,
      seatOrder: this.playerIds.map((id) => this.playerNames[id]),
      totals,
      // Per-round breakdown for the scoreboard. The id-bearing fields are
      // exactly the ones updatePlayerId rewrites — keep the two in step.
      history: this.scoreHistory.map((entry) => ({
        ...entry,
        declarer: mapId(entry.declarer, toNickname),
        partner: mapId(entry.partner, toNickname),
        dealMisser: mapId(entry.dealMisser, toNickname),
        scores: mapKeys(entry.scores, toNickname),
      })),
      // The dealer advances one seat per round; restarting the rotation on
      // the peer would deal out of turn. Safe as a bare index because the
      // seating is restored verbatim.
      dealerIndex: this.dealerIndex,
    };
  }

  // Called instead of start() when a room resumes a migrated match. The
  // round counter and dealer have to be seeded BEFORE startNewRound(),
  // which advances both.
  resumeMatch(progress) {
    if (!progress) {
      this.start();
      return;
    }
    for (const pid of this.playerIds) this.scores[pid] = 0;
    this.round = progress.round || 0;
    this.dealerIndex = Number.isInteger(progress.dealerIndex)
      ? progress.dealerIndex % this.playerCount
      : 0;
    const byNickname = {};
    for (const pid of this.playerIds) byNickname[this.playerNames[pid]] = pid;
    for (const [nickname, score] of Object.entries(progress.totals || {})) {
      const pid = byNickname[nickname];
      if (pid !== undefined) this.scores[pid] = score;
    }
    const toId = (nickname) => byNickname[nickname];
    this.scoreHistory = Array.isArray(progress.history)
      ? progress.history.map((entry) => ({
        ...entry,
        declarer: mapId(entry.declarer, toId),
        partner: mapId(entry.partner, toId),
        dealMisser: mapId(entry.dealMisser, toId),
        scores: mapKeys(entry.scores, toId),
      }))
      : [];
    this.startNewRound();
  }

  // ─── STATE FOR PLAYER ───────────────────────────────────

  buildStateBroadcastCache() {
    const governmentIds = new Set();
    if (this.declarer) governmentIds.add(this.declarer);
    if (this.friendRevealed && this.partner) governmentIds.add(this.partner);

    const trickCounts = {};
    for (const pid of this.playerIds) trickCounts[pid] = 0;
    for (const trick of this.tricks) {
      if (trick && trick.winner) trickCounts[trick.winner] = (trickCounts[trick.winner] || 0) + 1;
    }

    const pointCounts = {};
    for (const pid of this.playerIds) {
      pointCounts[pid] = countPoints(this.pointCards[pid] || []);
    }

    const currentTrick = this.currentTrick.map(play => ({
      playerId: play.pid,
      playerName: this.playerNames[play.pid] || play.pid,
      cardId: play.cardId,
    }));

    const tricks = this.tricks.map(t => ({
      leader: t.leader,
      winner: t.winner,
      cards: t.cards.map(c => ({ playerId: c.pid, cardId: c.cardId })),
    }));

    const hasTrumpCounter = this.trumpSuit && this.trumpSuit !== 'no_trump'
      && (this.state === 'playing' || this.state === 'trick_end');

    return {
      governmentIds,
      trickCounts,
      pointCounts,
      publicBids: this._getPublicBids(),
      currentTrick,
      tricks,
      mightyCard: this.trumpSuit ? this.getMightyCard() : null,
      jokerCallCard: this.trumpSuit ? this.getJokerCallCard() : null,
      jokerHasPower: this._currentTrickJokerHasPower(),
      remainingTrumps: hasTrumpCounter ? this._countRemainingTrumps() : undefined,
      excludedPlayers: [...this.excludedPlayers],
    };
  }

  getStateForPlayer(playerId, permittedPlayerIds = new Set(), broadcastCache = null) {
    const cache = broadcastCache || this.buildStateBroadcastCache();
    const playerIdx = this.playerIds.indexOf(playerId);
    const isMyTurn = this.currentPlayer === playerId;
    const legalCards = isMyTurn && this.state === 'playing'
      ? this._getLegalCards(playerId) : [];

    // Excluded (killed / self-KO'd) players can act like pseudo-spectators —
    // they can see the cards of players who approved a card-view request.
    const isExcluded = this.excludedPlayers.has(playerId);

    // Build players array (relative positioning, same pattern as SK)
    // Government = declarer + revealed partner; opposition = everyone else
    const players = [];
    for (let i = 0; i < this.playerCount; i++) {
      const pid = this.playerIds[(playerIdx + i) % this.playerCount];
      const isSelf = pid === playerId;
      const isGovt = cache.governmentIds.has(pid);
      const canReveal = isExcluded && permittedPlayerIds.has(pid);
      players.push({
        id: pid,
        name: this.playerNames[pid] || pid,
        position: isSelf ? 'self' : `player_${i}`,
        cardCount: (this.hands[pid] || []).length,
        bid: this.bids[pid] !== undefined ? this.bids[pid] : null,
        trickCount: cache.trickCounts[pid] || 0,
        pointCount: cache.pointCounts[pid] || 0,
        pointCards: isGovt ? [] : (this.pointCards[pid] || []),
        // Surface hand cards the same way the spectator state does when an
        // excluded player has been granted permission to peek.
        cards: canReveal ? sortCards(this.hands[pid] || [], this.trumpSuit) : [],
        canViewCards: canReveal,
        connected: true,
        timeoutCount: 0,
      });
    }

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
      bids: cache.publicBids,
      currentPlayer: this.currentPlayer,
      isMyTurn,
      currentTrick: cache.currentTrick,
      legalCards,
      scores: this.scores,
      scoreHistory: this.scoreHistory,
      roundResult: this.state === 'round_end' || this.state === 'game_end' ? this.roundResult : null,
      mightyCard: cache.mightyCard,
      jokerCallCard: cache.jokerCallCard,
      jokerCallActive: this.jokerCallActive,
      jokerHasPower: cache.jokerHasPower,
      jokerSuitDeclared: this.jokerSuitDeclared,
      lastTrickCards: this.state === 'trick_end' ? this.lastTrickCards : [],
      lastTrickWinner: this.state === 'trick_end' ? this.lastTrickWinner : null,
      dealMissPool: this.dealMissPool,
      lastDealMissEvent: this.lastDealMissEvent,
      canDeclareDealMiss: this._canDeclareDealMiss(playerId),
      canDeclareSetting: this._canDeclareSetting(playerId),
      lastSettingEvent: this.lastSettingEvent,
      mode: this.mode,
      excludedPlayers: cache.excludedPlayers,
      lastKillEvent: this.lastKillEvent,
      tricks: cache.tricks,
    };

    // Remaining trump count (for trump counter item)
    if (this.trumpSuit && this.trumpSuit !== 'no_trump' && (this.state === 'playing' || this.state === 'trick_end')) {
      state.remainingTrumps = cache.remainingTrumps;
    }

    // Kitty phase: show 13 cards to declarer + which cards came from kitty
    if (this.state === 'kitty_exchange' && playerId === this.declarer) {
      state.kittyReceived = true;
      state.kittyCards = this.kitty;
    }

    // Per-seat highlight: cards received via kill/suicide redistribution.
    // Only during kitty-exchange (kill case) or bidding right after suicide,
    // and only to the player themselves.
    if (this.newlyReceivedCards && this.newlyReceivedCards[playerId]
        && (this.state === 'kitty_exchange' || this.state === 'bidding')) {
      state.newlyReceivedCards = this.newlyReceivedCards[playerId];
    }

    return state;
  }

  getStateForSpectator(permittedPlayerIds = new Set(), broadcastCache = null) {
    const cache = broadcastCache || this.buildStateBroadcastCache();

    const players = this.playerIds.map((pid, i) => ({
      id: pid,
      name: this.playerNames[pid] || pid,
      position: `player_${i}`,
      cards: permittedPlayerIds.has(pid) ? sortCards(this.hands[pid] || [], this.trumpSuit) : [],
      canViewCards: permittedPlayerIds.has(pid),
      cardCount: (this.hands[pid] || []).length,
      bid: this.bids[pid] !== undefined ? this.bids[pid] : null,
      trickCount: cache.trickCounts[pid] || 0,
      pointCount: cache.pointCounts[pid] || 0,
      pointCards: cache.governmentIds.has(pid) ? [] : (this.pointCards[pid] || []),
      connected: true,
      timeoutCount: 0,
    }));

    return {
      gameType: this.gameType,
      phase: this.state,
      round: this.round,
      players,
      currentPlayer: this.currentPlayer,
      currentTrick: cache.currentTrick,
      trumpSuit: this.trumpSuit,
      declarer: this.declarer,
      friendRevealed: this.friendRevealed,
      partner: this.friendRevealed ? this.partner : null,
      friendCard: this.state !== 'bidding' ? this.friendCard : null,
      currentBid: this.currentBid,
      bids: cache.publicBids,
      scores: this.scores,
      scoreHistory: this.scoreHistory,
      roundResult: this.state === 'round_end' || this.state === 'game_end' ? this.roundResult : null,
      mightyCard: cache.mightyCard,
      jokerCallCard: cache.jokerCallCard,
      jokerCallActive: this.jokerCallActive,
      jokerHasPower: cache.jokerHasPower,
      jokerSuitDeclared: this.jokerSuitDeclared,
      lastTrickCards: this.state === 'trick_end' ? this.lastTrickCards : [],
      lastTrickWinner: this.state === 'trick_end' ? this.lastTrickWinner : null,
      dealMissPool: this.dealMissPool,
      lastDealMissEvent: this.lastDealMissEvent,
      lastSettingEvent: this.lastSettingEvent,
      mode: this.mode,
      excludedPlayers: cache.excludedPlayers,
      lastKillEvent: this.lastKillEvent,
      remainingTrumps: cache.remainingTrumps,
      tricks: cache.tricks,
      // Let spectators mark which of the declarer's cards came from the kitty —
      // but ONLY when this spectator may already view the declarer's hand.
      // Otherwise the kitty composition would leak to unpermitted spectators.
      kittyCards:
        this.state === 'kitty_exchange' && permittedPlayerIds.has(this.declarer)
          ? this.kitty
          : [],
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

    // lastDealMissEvent
    if (this.lastDealMissEvent && this.lastDealMissEvent.playerId === oldId) {
      this.lastDealMissEvent.playerId = newId;
    }

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
      if (entry.dealMisser === oldId) entry.dealMisser = newId;
    }

    // excludedPlayers (kill/suicide)
    if (this.excludedPlayers.has(oldId)) {
      this.excludedPlayers.delete(oldId);
      this.excludedPlayers.add(newId);
    }

    // newlyReceivedCards (post-kill highlight)
    if (this.newlyReceivedCards && this.newlyReceivedCards[oldId] !== undefined) {
      this.newlyReceivedCards[newId] = this.newlyReceivedCards[oldId];
      delete this.newlyReceivedCards[oldId];
    }

    // lastKillEvent references
    if (this.lastKillEvent) {
      if (this.lastKillEvent.declarerId === oldId) this.lastKillEvent.declarerId = newId;
      if (this.lastKillEvent.victimId === oldId) this.lastKillEvent.victimId = newId;
    }
  }

  // ─── AUTO TIMEOUT ───────────────────────────────────────

  /// 시간이 지나 대신 친구를 골라야 할 때 무엇을 부를 것인가.
  ///
  /// 예전에는 마이티를 손에 들고 있으면 곧장 노프렌즈였다. 노프렌즈는 "혼자
  /// 다 감당하겠다" 는 선언이라 목표 점수가 올라간다. 자리를 비웠다는 이유로
  /// 그 계약을 떠안으면 그 판은 대체로 진다 — 잠수한 사람만 손해가 아니라
  /// 같은 편이 될 사람도, 남은 사람 전부의 한 판도 같이 버려진다.
  ///
  /// 그래서 부를 수 있는 카드가 하나라도 있으면 친구를 세운다. 손에 없는
  /// 카드 중 강한 것부터 — 마이티, 조커, 기루다 위쪽, 그다음 각 무늬의 A·K.
  /// 사람이 직접 고를 때도 대개 이 순서다.
  ///
  /// 손에 없는 카드를 부르는 것이 핵심이다. 자기가 든 카드를 부르면 스스로
  /// 친구가 되어 결국 노프렌즈와 같아진다.
  _autoFriendCard(hand) {
    const held = new Set(hand || []);
    const candidates = [this.getMightyCard(), 'mighty_joker'];
    if (this.trumpSuit && this.trumpSuit !== 'no_trump') {
      for (const rank of ['A', 'K', 'Q', 'J', '10']) {
        candidates.push(`mighty_${this.trumpSuit}_${rank}`);
      }
    }
    for (const suit of ['spade', 'diamond', 'heart', 'club']) {
      for (const rank of ['A', 'K']) candidates.push(`mighty_${suit}_${rank}`);
    }
    for (const cardId of candidates) {
      if (!held.has(cardId)) return cardId;
    }
    // 후보를 전부 손에 들고 있는 손패. 그런 손이면 노프렌즈가 손해도 아니다.
    return 'no_friend';
  }

  getAutoTimeoutAction(playerId) {
    if (this.state === 'bidding' && this.currentPlayer === playerId) {
      return { type: 'submit_bid', pass: true };
    }

    if (this.state === 'kill_select' && playerId === this.declarer) {
      // Fallback: kill the highest non-own card we can find in the deck
      const myHand = new Set(this.hands[playerId] || []);
      const preferredOrder = ['mighty_joker'];
      const mighty = this.getMightyCard();
      const trump = this.trumpSuit;
      if (trump && trump !== 'no_trump') {
        preferredOrder.push(`mighty_${trump}_A`);
        preferredOrder.push(`mighty_${trump}_K`);
      }
      preferredOrder.push(mighty);
      for (const cid of preferredOrder) {
        if (!myHand.has(cid)) return { type: 'declare_kill', cardId: cid };
      }
      // Last resort: any card
      for (const suit of ['spade', 'heart', 'diamond', 'club']) {
        for (const rank of ['A', 'K', 'Q', 'J', '10', '9', '8', '7', '6', '5', '4', '3', '2']) {
          const cid = `mighty_${suit}_${rank}`;
          if (!myHand.has(cid)) return { type: 'declare_kill', cardId: cid };
        }
      }
      return null;
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
      return { type: 'discard_kitty', discards,
        friendCard: this._autoFriendCard(hand) };
    }

    if (this.state === 'playing' && this.currentPlayer === playerId) {
      const legalCards = this._getLegalCards(playerId);
      if (legalCards.length > 0) {
        const cardId = legalCards[Math.floor((this._rng || Math.random)() * legalCards.length)];
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

  /** Public legal-cards accessor for bot strategies. */
  getLegalCards(playerId) {
    return this._getLegalCards(playerId);
  }

  /** Player whose turn it is, including kill_select / kitty_exchange where the
   *  declarer acts but `currentPlayer` isn't set. */
  getPendingActor() {
    if (this.currentPlayer) return this.currentPlayer;
    if (this.state === 'kill_select' || this.state === 'kitty_exchange') return this.declarer;
    return null;
  }

  /** Deep clone for bot search (PIMC, expectimax). Caller may mutate freely.
   *  Hot path — called O(samples × candidates) per decision. Immutable refs
   *  (playerIds, playerNames, gameType, playerCount) are shared; everything
   *  else is deep-copied. */
  clone() {
    const c = Object.create(MightyGame.prototype);
    // Shared (never mutated after construction)
    c.playerIds = this.playerIds;
    c.playerNames = this.playerNames;
    c.gameType = this.gameType;
    c.playerCount = this.playerCount;
    // Primitives — copied by value
    c.state = this.state;
    c.round = this.round;
    c.mode = this.mode;
    c.activePlayerCount = this.activePlayerCount;
    c.dealMissPool = this.dealMissPool;
    c.trumpSuit = this.trumpSuit;
    c.declarer = this.declarer;
    c.partner = this.partner;
    c.friendCard = this.friendCard;
    c.friendRevealed = this.friendRevealed;
    c.passCount = this.passCount;
    c.currentBidderIndex = this.currentBidderIndex;
    c.currentPlayer = this.currentPlayer;
    c.dealerIndex = this.dealerIndex;
    c.jokerSuitDeclared = this.jokerSuitDeclared;
    c.jokerCallActive = this.jokerCallActive;
    c.lastTrickWinner = this.lastTrickWinner;
    c.revealGracePeriodEndAt = this.revealGracePeriodEndAt;
    // Mutable — deep clone. options.minBid mutates on kill so we copy.
    c.options = { ...this.options };
    c.kitty = this.kitty.slice();
    c.bidOrder = this.bidOrder.slice();
    c.discarded = this.discarded.slice();
    c.lastTrickCards = this.lastTrickCards.slice();
    c.bids = { ...this.bids };
    c.currentBid = { ...this.currentBid };
    c.scores = { ...this.scores };
    c.excludedPlayers = new Set(this.excludedPlayers);
    c.hands = {};
    for (const pid of this.playerIds) c.hands[pid] = (this.hands[pid] || []).slice();
    c.pointCards = {};
    for (const pid of this.playerIds) c.pointCards[pid] = (this.pointCards[pid] || []).slice();
    c.newlyReceivedCards = {};
    for (const pid of this.playerIds) {
      if (this.newlyReceivedCards[pid]) c.newlyReceivedCards[pid] = this.newlyReceivedCards[pid].slice();
    }
    // currentTrick: array of {pid, cardId} — shallow-clone the entries
    c.currentTrick = this.currentTrick.map(p => ({ ...p }));
    // tricks: array of {leader, winner, cards: [{pid, cardId}, ...]}
    c.tricks = this.tricks.map(t => ({
      leader: t.leader,
      leadSuit: t.leadSuit || null,
      winner: t.winner,
      cards: t.cards.map(p => ({ ...p })),
    }));
    // scoreHistory rarely changes within a round but copy defensively
    c.scoreHistory = this.scoreHistory.slice();
    // roundResult is null until round_end — shallow ok (not mutated post-set)
    c.roundResult = this.roundResult;
    // Reveal-event payloads: shallow share (not mutated, only replaced)
    c.lastDealMissEvent = this.lastDealMissEvent;
    c.lastKillEvent = this.lastKillEvent;
    c.lastSettingEvent = this.lastSettingEvent;
    return c;
  }

  /** JSON-safe snapshot for worker-thread bot offload. MUST mirror clone()'s
   *  field set — clone() defines exactly the state a bot search needs, so a
   *  worker reconstructed from this behaves identically to one on the main
   *  thread. Kept in sync with clone() by a parity test (see
   *  test/serialize-roundtrip). Only excludedPlayers (a Set) needs conversion;
   *  everything else is primitives / plain arrays / plain objects. Shared refs
   *  (playerIds, playerNames, gameType, playerCount) are included because
   *  workers don't share memory. Live refs are fine: the postMessage boundary
   *  structured-clones them. */
  serialize() {
    return {
      playerIds: this.playerIds,
      playerNames: this.playerNames,
      gameType: this.gameType,
      playerCount: this.playerCount,
      state: this.state,
      round: this.round,
      mode: this.mode,
      activePlayerCount: this.activePlayerCount,
      dealMissPool: this.dealMissPool,
      trumpSuit: this.trumpSuit,
      declarer: this.declarer,
      partner: this.partner,
      friendCard: this.friendCard,
      friendRevealed: this.friendRevealed,
      passCount: this.passCount,
      currentBidderIndex: this.currentBidderIndex,
      currentPlayer: this.currentPlayer,
      dealerIndex: this.dealerIndex,
      jokerSuitDeclared: this.jokerSuitDeclared,
      jokerCallActive: this.jokerCallActive,
      lastTrickWinner: this.lastTrickWinner,
      revealGracePeriodEndAt: this.revealGracePeriodEndAt,
      options: this.options,
      kitty: this.kitty,
      bidOrder: this.bidOrder,
      discarded: this.discarded,
      lastTrickCards: this.lastTrickCards,
      bids: this.bids,
      currentBid: this.currentBid,
      scores: this.scores,
      excludedPlayers: [...this.excludedPlayers], // Set -> array
      hands: this.hands,
      pointCards: this.pointCards,
      newlyReceivedCards: this.newlyReceivedCards,
      currentTrick: this.currentTrick,
      tricks: this.tricks,
      scoreHistory: this.scoreHistory,
      roundResult: this.roundResult,
      lastDealMissEvent: this.lastDealMissEvent,
      lastKillEvent: this.lastKillEvent,
      lastSettingEvent: this.lastSettingEvent,
    };
  }

  /** Rebuild a working instance from serialize() output (called in the worker).
   *  Mirror of clone()'s reconstruction but from a plain snapshot. `s` is
   *  already a private copy (structured-cloned across postMessage), so we may
   *  adopt its refs directly. */
  static reconstruct(s) {
    const c = Object.create(MightyGame.prototype);
    Object.assign(c, s);
    c.excludedPlayers = new Set(s.excludedPlayers || []); // array -> Set
    return c;
  }
}

module.exports = MightyGame;
