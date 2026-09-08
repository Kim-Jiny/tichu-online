/**
 * Skull("스컬") Game - state machine and rule engine
 *
 * States: waiting → placing ⇄ bidding → revealing → round_end → game_end
 * 3-6 players, no teams, no shared deck — each player owns a private pool
 * of 4 discs (3 rose + 1 skull) that only ever shrinks over the match.
 *
 * A round has three phases:
 *  - placing: seat-order turns, each player places one disc face-down on
 *    their own stack, or (having placed ≥1 already) opens the bidding.
 *    The instant anyone bids, placing is over for everyone this round.
 *  - bidding: an auction. Only players still owed a response to the
 *    current highest bid get asked; passing removes you from the round's
 *    auction for good. Ends when only the highest bidder is left, or their
 *    bid equals the total discs on the table (nobody could outbid that).
 *  - revealing: the winning bidder must flip that many discs without
 *    hitting a skull — starting with their own stack (auto-resolved, no
 *    decision to make since they placed those discs themselves), then
 *    picking which opponent's stack to pull from, one flip at a time.
 *    A skull ends the challenge; otherwise reaching the bid succeeds.
 *
 * Success scores a point (2 wins the game); bidding = the entire table's
 * discs and succeeding wins instantly. Failure permanently discards one of
 * the challenger's own remaining discs (their choice which) — the only
 * "equipment shrinks" mechanic in this codebase, so updatePlayerId and the
 * blue/green round-boundary migration both have to carry `pool` exactly.
 */

'use strict';

const { DISC, TARGET_SUCCESSES, freshPool, poolSize } = require('./SkullBiddingDeck');
const { mapId } = require('../historyIds');

class SkullBiddingGame {
  constructor(playerIds, playerNames, options = {}) {
    this.playerIds = playerIds;
    this.playerNames = playerNames;
    this.playerCount = playerIds.length;
    this.gameType = 'skull_bidding';

    this.targetSuccesses = options.targetSuccesses || TARGET_SUCCESSES;

    this.state = 'waiting';
    this.round = 0;

    this.pool = {};
    this.successCount = {};
    this.eliminated = {};
    for (const pid of playerIds) {
      this.pool[pid] = freshPool();
      this.successCount[pid] = 0;
      this.eliminated[pid] = false;
    }

    this.hand = {};
    this.stack = {};
    this.placedThisRound = new Set();
    this.currentPlayer = null;

    this.highestBid = 0;
    this.highestBidder = null;
    this.biddingQueue = [];
    this.biddingPasses = new Set();
    this.tableTotal = null;

    this.challengerId = null;
    this.targetFlips = null;
    this.flippedCount = 0;
    this.revealLog = [];
    this.failed = false;
    this.pendingDiscard = null;
    this.pendingNextLeader = null;

    this.gameWinner = null;
    this.roundHistory = [];

    this.resultSaved = false;
    this.deserted = false;
  }

  start() {
    this.round = 0;
    this.currentPlayer = this.playerIds[Math.floor(Math.random() * this.playerCount)];
    this._startNextRound();
  }

  _activePlayers() {
    return this.playerIds.filter((pid) => !this.eliminated[pid]);
  }

  /** Next active player after `pid` in seat order, wrapping. */
  _nextActive(pid) {
    const active = this._activePlayers();
    if (active.length === 0) return null;
    const idx = this.playerIds.indexOf(pid);
    for (let step = 1; step <= this.playerCount; step++) {
      const candidate = this.playerIds[(idx + step) % this.playerCount];
      if (!this.eliminated[candidate]) return candidate;
    }
    return null;
  }

  /** Resolve a proposed round leader to an active player (they may have
   *  just been eliminated by the round that just ended). */
  _resolveLeader(pid) {
    if (pid !== null && pid !== undefined && !this.eliminated[pid]) return pid;
    return this._nextActive(pid) ?? this._activePlayers()[0] ?? null;
  }

  _startNextRound() {
    this.round++;
    this.hand = {};
    this.stack = {};
    this.placedThisRound = new Set();
    this.highestBid = 0;
    this.highestBidder = null;
    this.biddingQueue = [];
    this.biddingPasses = new Set();
    this.tableTotal = null;
    this.challengerId = null;
    this.targetFlips = null;
    this.flippedCount = 0;
    this.revealLog = [];
    this.failed = false;
    this.pendingDiscard = null;
    this.pendingNextLeader = null;

    for (const pid of this._activePlayers()) {
      this.hand[pid] = { ...this.pool[pid] };
      this.stack[pid] = [];
    }

    this.currentPlayer = this._resolveLeader(this.currentPlayer);
    this.state = 'placing';
  }

  handleAction(playerId, data) {
    switch (data.type) {
      case 'place_disc':
        return this.handlePlaceDisc(playerId, data.discType);
      case 'start_bid':
        return this.handleStartBid(playerId, data.amount);
      case 'raise_bid':
        return this.handleRaiseBid(playerId, data.amount);
      case 'pass':
        return this.handlePass(playerId);
      case 'reveal_target':
        return this.handleRevealTarget(playerId, data.targetId);
      case 'discard_disc':
        return this.handleDiscardDisc(playerId, data.discardType);
      case 'next_round':
        return this.handleNextRound();
      default:
        return { success: false, messageKey: 'game_unknown_action', messageParams: { type: data.type } };
    }
  }

  handlePlaceDisc(playerId, discType) {
    if (this.state !== 'placing') return { success: false, messageKey: 'skb_not_placing_phase' };
    if (playerId !== this.currentPlayer) return { success: false, messageKey: 'skb_not_your_turn' };
    if (discType !== DISC.ROSE && discType !== DISC.SKULL) {
      return { success: false, messageKey: 'skb_invalid_disc' };
    }
    const hand = this.hand[playerId];
    if (!hand || poolSize(hand) === 0) return { success: false, messageKey: 'skb_no_discs_left' };
    if (discType === DISC.ROSE && hand.roses <= 0) return { success: false, messageKey: 'skb_no_rose_left' };
    if (discType === DISC.SKULL && !hand.hasSkull) return { success: false, messageKey: 'skb_no_skull_left' };

    if (discType === DISC.ROSE) hand.roses--;
    else hand.hasSkull = false;
    this.stack[playerId].push(discType);
    this.placedThisRound.add(playerId);

    this.currentPlayer = this._nextActive(playerId);
    return { success: true };
  }

  handleStartBid(playerId, amount) {
    if (this.state !== 'placing') return { success: false, messageKey: 'skb_not_placing_phase' };
    if (playerId !== this.currentPlayer) return { success: false, messageKey: 'skb_not_your_turn' };
    if (!this.placedThisRound.has(playerId)) return { success: false, messageKey: 'skb_must_place_before_bid' };
    const tableTotal = this._activePlayers().reduce((sum, pid) => sum + this.stack[pid].length, 0);
    if (!Number.isInteger(amount) || amount < 1 || amount > tableTotal) {
      return { success: false, messageKey: 'skb_invalid_bid' };
    }

    this.state = 'bidding';
    this.tableTotal = tableTotal;
    this.highestBid = amount;
    this.highestBidder = playerId;
    this.biddingPasses = new Set();
    return this._armBiddingQueueAfter(playerId);
  }

  handleRaiseBid(playerId, amount) {
    if (this.state !== 'bidding') return { success: false, messageKey: 'skb_not_bidding_phase' };
    if (playerId !== this.currentPlayer) return { success: false, messageKey: 'skb_not_your_turn' };
    if (!Number.isInteger(amount) || amount <= this.highestBid || amount > this.tableTotal) {
      return { success: false, messageKey: 'skb_invalid_bid' };
    }

    this.highestBid = amount;
    this.highestBidder = playerId;
    return this._armBiddingQueueAfter(playerId);
  }

  handlePass(playerId) {
    if (this.state !== 'bidding') return { success: false, messageKey: 'skb_not_bidding_phase' };
    if (playerId !== this.currentPlayer) return { success: false, messageKey: 'skb_not_your_turn' };

    this.biddingPasses.add(playerId);
    this.biddingQueue.shift();
    return this._continueBiddingOrResolve();
  }

  /** Rebuilds the queue of players still owed a response to the current
   *  bid — everyone active except the bidder and anyone who's already
   *  passed (passing is final for the round). Resolves immediately if
   *  nobody's left to ask, or the bid already claims the whole table. */
  _armBiddingQueueAfter(bidderId) {
    if (this.highestBid === this.tableTotal) {
      return this._concludeBidding(bidderId);
    }
    const order = [];
    let pid = this._nextActive(bidderId);
    for (let i = 0; i < this.playerCount && pid !== null; i++) {
      if (pid === bidderId) break;
      if (!this.biddingPasses.has(pid)) order.push(pid);
      pid = this._nextActive(pid);
    }
    this.biddingQueue = order;
    return this._continueBiddingOrResolve();
  }

  _continueBiddingOrResolve() {
    if (this.biddingQueue.length === 0) {
      return this._concludeBidding(this.highestBidder);
    }
    this.currentPlayer = this.biddingQueue[0];
    return { success: true };
  }

  _concludeBidding(challengerId) {
    this.challengerId = challengerId;
    this.targetFlips = this.highestBid;
    return this._startRevealing();
  }

  _startRevealing() {
    this.state = 'revealing';
    this.currentPlayer = this.challengerId;
    this.flippedCount = 0;
    this.revealLog = [];
    this.failed = false;

    const ownStack = this.stack[this.challengerId];
    while (this.flippedCount < this.targetFlips && ownStack.length > 0) {
      const disc = ownStack.pop();
      this.revealLog.push({ playerId: this.challengerId, disc });
      this.flippedCount++;
      if (disc === DISC.SKULL) { this.failed = true; break; }
    }

    if (this.failed) {
      this.pendingDiscard = { playerId: this.challengerId };
      return { success: true };
    }
    if (this.flippedCount >= this.targetFlips) {
      return this._resolveRoundSuccess();
    }
    return { success: true }; // awaiting reveal_target
  }

  handleRevealTarget(playerId, targetId) {
    if (this.state !== 'revealing' || this.pendingDiscard) {
      return { success: false, messageKey: 'skb_not_revealing_phase' };
    }
    if (playerId !== this.challengerId) return { success: false, messageKey: 'skb_not_your_turn' };
    if (targetId === playerId || this.eliminated[targetId]) {
      return { success: false, messageKey: 'skb_invalid_target' };
    }
    const stack = this.stack[targetId];
    if (!stack || stack.length === 0) return { success: false, messageKey: 'skb_empty_stack' };

    const disc = stack.pop();
    this.revealLog.push({ playerId: targetId, disc });
    this.flippedCount++;

    if (disc === DISC.SKULL) {
      this.failed = true;
      this.pendingDiscard = { playerId: this.challengerId };
      return { success: true };
    }
    if (this.flippedCount >= this.targetFlips) {
      return this._resolveRoundSuccess();
    }
    return { success: true };
  }

  handleDiscardDisc(playerId, discardType) {
    if (!this.pendingDiscard || this.pendingDiscard.playerId !== playerId) {
      return { success: false, messageKey: 'skb_no_pending_discard' };
    }
    const pool = this.pool[playerId];
    if (discardType === DISC.ROSE && pool.roses > 0) pool.roses--;
    else if (discardType === DISC.SKULL && pool.hasSkull) pool.hasSkull = false;
    else return { success: false, messageKey: 'skb_invalid_discard' };

    if (poolSize(pool) === 0) this.eliminated[playerId] = true;
    this.pendingDiscard = null;
    return this._resolveRoundFailure();
  }

  _pushHistory(result) {
    this.roundHistory.push({
      round: this.round,
      challengerId: this.challengerId,
      bid: this.targetFlips,
      tableTotal: this.tableTotal,
      result,
    });
  }

  _resolveRoundSuccess() {
    const instantWin = this.targetFlips === this.tableTotal;
    this.successCount[this.challengerId] = (this.successCount[this.challengerId] || 0) + 1;
    this._pushHistory('success');

    if (instantWin || this.successCount[this.challengerId] >= this.targetSuccesses) {
      this.gameWinner = this.challengerId;
      this.state = 'game_end';
      return { success: true };
    }

    this.pendingNextLeader = this.challengerId;
    this.state = 'round_end';
    return { success: true };
  }

  _resolveRoundFailure() {
    this._pushHistory('fail');

    const active = this._activePlayers();
    if (active.length <= 1) {
      this.gameWinner = active[0] || null;
      this.state = 'game_end';
      return { success: true };
    }

    this.pendingNextLeader = this.challengerId;
    this.state = 'round_end';
    return { success: true };
  }

  handleNextRound() {
    if (this.state !== 'round_end') return { success: false, messageKey: 'skb_not_round_end' };
    this.currentPlayer = this._resolveLeader(this.pendingNextLeader);
    this._startNextRound();
    return { success: true };
  }

  // Mirrors Love Letter's convenience wrapper — some auto-advance paths in
  // server.js call this directly instead of routing through handleAction.
  nextRound() {
    if (this.state === 'round_end') {
      this.currentPlayer = this._resolveLeader(this.pendingNextLeader);
      this._startNextRound();
    }
  }

  getAutoTimeoutAction(playerId) {
    if (playerId !== this.currentPlayer) return null;

    if (this.state === 'placing') {
      const hand = this.hand[playerId];
      if (!hand || poolSize(hand) === 0) return { type: 'start_bid', amount: 1 };
      return hand.roses > 0
        ? { type: 'place_disc', discType: DISC.ROSE }
        : { type: 'place_disc', discType: DISC.SKULL };
    }
    if (this.state === 'bidding') {
      return { type: 'pass' };
    }
    if (this.state === 'revealing') {
      if (this.pendingDiscard && this.pendingDiscard.playerId === playerId) {
        const pool = this.pool[playerId];
        return { type: 'discard_disc', discardType: pool.roses > 0 ? DISC.ROSE : DISC.SKULL };
      }
      if (!this.pendingDiscard) {
        const target = this.playerIds.find(
          (pid) => pid !== playerId && !this.eliminated[pid] && (this.stack[pid] || []).length > 0
        );
        if (target) return { type: 'reveal_target', targetId: target };
      }
      return null;
    }
    if (this.state === 'round_end') {
      return { type: 'next_round' };
    }
    return null;
  }

  getStateForPlayer(playerId) {
    const playerIdx = this.playerIds.indexOf(playerId);
    const players = [];
    for (let i = 0; i < this.playerCount; i++) {
      const pid = this.playerIds[(playerIdx + i) % this.playerCount];
      players.push({
        id: pid,
        name: this.playerNames[pid] || pid,
        position: pid === playerId ? 'self' : `player_${i}`,
        poolRemaining: poolSize(this.pool[pid]),
        handCount: this.hand[pid] ? poolSize(this.hand[pid]) : 0,
        stackCount: (this.stack[pid] || []).length,
        successCount: this.successCount[pid] || 0,
        eliminated: !!this.eliminated[pid],
      });
    }

    return {
      gameType: 'skull_bidding',
      phase: this.state,
      round: this.round,
      players,
      // Only the viewer's own hand carries disc identity.
      myHand: { ...(this.hand[playerId] || { roses: 0, hasSkull: false }) },
      currentPlayer: this.currentPlayer,
      isMyTurn: this.currentPlayer === playerId,
      highestBid: this.highestBid,
      highestBidder: this.highestBidder,
      tableTotal: this.tableTotal,
      biddingQueue: [...this.biddingQueue],
      challengerId: this.challengerId,
      targetFlips: this.targetFlips,
      flippedCount: this.flippedCount,
      revealLog: [...this.revealLog],
      pendingDiscard: this.pendingDiscard,
      targetSuccesses: this.targetSuccesses,
      gameWinner: this.gameWinner,
      roundHistory: this.roundHistory,
    };
  }

  getStateForSpectator(permittedPlayerIds = new Set()) {
    const players = this.playerIds.map((pid) => ({
      id: pid,
      name: this.playerNames[pid] || pid,
      hand: permittedPlayerIds.has(pid) ? { ...(this.hand[pid] || { roses: 0, hasSkull: false }) } : null,
      canViewHand: permittedPlayerIds.has(pid),
      poolRemaining: poolSize(this.pool[pid]),
      handCount: this.hand[pid] ? poolSize(this.hand[pid]) : 0,
      stackCount: (this.stack[pid] || []).length,
      successCount: this.successCount[pid] || 0,
      eliminated: !!this.eliminated[pid],
    }));

    return {
      gameType: 'skull_bidding',
      phase: this.state,
      round: this.round,
      players,
      currentPlayer: this.currentPlayer,
      highestBid: this.highestBid,
      highestBidder: this.highestBidder,
      tableTotal: this.tableTotal,
      biddingQueue: [...this.biddingQueue],
      challengerId: this.challengerId,
      targetFlips: this.targetFlips,
      flippedCount: this.flippedCount,
      revealLog: [...this.revealLog],
      pendingDiscard: this.pendingDiscard,
      targetSuccesses: this.targetSuccesses,
      gameWinner: this.gameWinner,
      roundHistory: this.roundHistory,
    };
  }

  // ─── MATCH MIGRATION (blue/green drain) ─────────────────
  // Round-boundary only (see TichuGame.getMatchProgress) — this is only
  // ever called while state === 'round_end' / 'waiting', so mid-round
  // bidding/reveal state never needs to survive a migration.

  getMatchProgress() {
    const toId = (pid) => this.playerNames[pid];
    const pools = {};
    const successes = {};
    const eliminated = {};
    for (const pid of this.playerIds) {
      pools[this.playerNames[pid]] = { ...this.pool[pid] };
      successes[this.playerNames[pid]] = this.successCount[pid] || 0;
      eliminated[this.playerNames[pid]] = !!this.eliminated[pid];
    }
    return {
      round: this.round,
      pools,
      successes,
      eliminated,
      leader: this.currentPlayer ? this.playerNames[this.currentPlayer] || null : null,
      history: this.roundHistory.map((entry) => ({
        ...entry,
        challengerId: mapId(entry.challengerId, toId),
      })),
    };
  }

  resumeMatch(progress) {
    if (!progress) {
      this.start();
      return;
    }
    this.round = progress.round || 0;
    const byNickname = {};
    for (const pid of this.playerIds) byNickname[this.playerNames[pid]] = pid;

    for (const [nickname, pool] of Object.entries(progress.pools || {})) {
      const pid = byNickname[nickname];
      if (pid !== undefined) this.pool[pid] = { ...pool };
    }
    for (const [nickname, s] of Object.entries(progress.successes || {})) {
      const pid = byNickname[nickname];
      if (pid !== undefined) this.successCount[pid] = s;
    }
    for (const [nickname, e] of Object.entries(progress.eliminated || {})) {
      const pid = byNickname[nickname];
      if (pid !== undefined) this.eliminated[pid] = e;
    }

    const toId = (nickname) => byNickname[nickname];
    this.roundHistory = Array.isArray(progress.history)
      ? progress.history.map((entry) => ({ ...entry, challengerId: mapId(entry.challengerId, toId) }))
      : [];

    const leader = progress.leader ? byNickname[progress.leader] : undefined;
    this.currentPlayer = leader !== undefined
      ? leader
      : this.playerIds[Math.floor(Math.random() * this.playerCount)];
    this._startNextRound();
  }

  updatePlayerId(oldPlayerId, newPlayerId) {
    const idx = this.playerIds.indexOf(oldPlayerId);
    if (idx === -1) return;

    this.playerIds[idx] = newPlayerId;
    this.playerNames[newPlayerId] = this.playerNames[oldPlayerId];
    delete this.playerNames[oldPlayerId];

    const rekey = (obj) => {
      if (obj && obj.hasOwnProperty(oldPlayerId)) {
        obj[newPlayerId] = obj[oldPlayerId];
        delete obj[oldPlayerId];
      }
    };
    rekey(this.pool);
    rekey(this.successCount);
    rekey(this.eliminated);
    rekey(this.hand);
    rekey(this.stack);

    if (this.placedThisRound.has(oldPlayerId)) {
      this.placedThisRound.delete(oldPlayerId);
      this.placedThisRound.add(newPlayerId);
    }
    if (this.biddingPasses.has(oldPlayerId)) {
      this.biddingPasses.delete(oldPlayerId);
      this.biddingPasses.add(newPlayerId);
    }
    this.biddingQueue = this.biddingQueue.map((pid) => (pid === oldPlayerId ? newPlayerId : pid));

    if (this.currentPlayer === oldPlayerId) this.currentPlayer = newPlayerId;
    if (this.highestBidder === oldPlayerId) this.highestBidder = newPlayerId;
    if (this.challengerId === oldPlayerId) this.challengerId = newPlayerId;
    if (this.gameWinner === oldPlayerId) this.gameWinner = newPlayerId;
    if (this.pendingDiscard && this.pendingDiscard.playerId === oldPlayerId) {
      this.pendingDiscard.playerId = newPlayerId;
    }
    if (this.pendingNextLeader === oldPlayerId) this.pendingNextLeader = newPlayerId;

    for (const entry of this.revealLog) {
      if (entry.playerId === oldPlayerId) entry.playerId = newPlayerId;
    }
    for (const entry of this.roundHistory) {
      if (entry.challengerId === oldPlayerId) entry.challengerId = newPlayerId;
    }
  }

  getRankings() {
    const sorted = this.playerIds
      .map((pid) => ({
        playerId: pid,
        nickname: this.playerNames[pid],
        score: this.successCount[pid] || 0,
        poolRemaining: poolSize(this.pool[pid]),
      }))
      .sort((a, b) => b.score - a.score || b.poolRemaining - a.poolRemaining);

    let currentRank = 1;
    return sorted.map((entry, idx) => {
      if (idx > 0 && (entry.score < sorted[idx - 1].score
        || (entry.score === sorted[idx - 1].score && entry.poolRemaining < sorted[idx - 1].poolRemaining))) {
        currentRank = idx + 1;
      }
      return { ...entry, rank: currentRank };
    });
  }
}

module.exports = SkullBiddingGame;
