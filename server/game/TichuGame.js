const { createDeck, deal, getCardValue, sortCards } = require('./Deck');
const { getComboType, canBeat, isBomb, arrangeCardsWithPhoenix, COMBO } = require('./CardValidator');
const { calculateRoundScores, calculateTrickPoints } = require('./ScoreCalculator');

const STATE = {
  WAITING: 'waiting',
  DEALING_FIRST_8: 'dealing_first_8',
  LARGE_TICHU_PHASE: 'large_tichu_phase',
  DEALING_REMAINING_6: 'dealing_remaining_6',
  CARD_EXCHANGE: 'card_exchange',
  PLAYING: 'playing',
  ROUND_END: 'round_end',
  GAME_END: 'game_end',
};

class TichuGame {
  constructor(playerIds, playerNames) {
    // playerIds: [p0, p1, p2, p3] seated clockwise
    // Teams: p0 & p2 = Team A, p1 & p3 = Team B
    this.playerIds = playerIds;
    this.playerNames = playerNames;
    this.teams = {
      teamA: [playerIds[0], playerIds[2]],
      teamB: [playerIds[1], playerIds[3]],
    };
    this.totalScores = { teamA: 0, teamB: 0 };
    this.targetScore = 1000;
    this.state = STATE.WAITING;
    this.round = 0;

    // Per-round state
    this.resetRound();
  }

  resetRound() {
    this.hands = {};         // playerId -> [cardId]
    this.trickPiles = {};    // playerId -> [cardId] (collected tricks)
    this.largeTichuDeclarations = [];
    this.smallTichuDeclarations = [];
    this.largeTichuResponses = {}; // playerId -> true/false
    this.exchangeCards = {};  // playerId -> { left, partner, right }
    this.exchangeDone = {};
    this.receivedFrom = {};  // playerId -> { left: cardId, partner: cardId, right: cardId }

    this.currentTrick = [];   // [{ playerId, cards, combo }]
    this.currentPlayer = null;
    this.passCount = 0;
    this.lastPlayedBy = null;
    this.trickStarter = null;
    this.finishOrder = [];

    this.callRank = null;  // rank called by bird player
    this.needsToCallRank = null; // player who needs to call (just played bird)
    this.dragonPending = false; // waiting for dragon give decision
    this.dragonDecider = null;

    this.dealData = null;

    for (const pid of this.playerIds) {
      this.hands[pid] = [];
      this.trickPiles[pid] = [];
    }
  }

  start() {
    this.round++;
    this.resetRound();
    this.state = STATE.DEALING_FIRST_8;

    const deck = createDeck();
    this.dealData = deal(deck);

    // Deal first 8 cards
    for (let i = 0; i < 4; i++) {
      this.hands[this.playerIds[i]] = this.dealData.first8[i].map((c) => c.id);
    }

    this.state = STATE.LARGE_TICHU_PHASE;
  }

  handleAction(playerId, data) {
    switch (data.type) {
      case 'declare_large_tichu':
        return this.handleLargeTichu(playerId, true);
      case 'pass_large_tichu':
        return this.handleLargeTichu(playerId, false);
      case 'declare_small_tichu':
        return this.handleSmallTichuDeclaration(playerId);
      case 'next_round':
        return this.handleNextRound(playerId);
      case 'exchange_cards':
        return this.handleExchange(playerId, data.cards);
      case 'play_cards':
        return this.handlePlayCards(playerId, data.cards, data.callRank);
      case 'pass':
        return this.handlePass(playerId);
      case 'dragon_give':
        return this.handleDragonGive(playerId, data.target);
      case 'call_rank':
        return this.handleCallRank(playerId, data.rank);
      default:
        return { success: false, message: `Unknown action: ${data.type}` };
    }
  }

  handleNextRound(_playerId) {
    if (this.state !== STATE.ROUND_END) {
      return { success: false, message: 'Round is not finished' };
    }
    this.nextRound();
    return { success: true };
  }

  handleLargeTichu(playerId, declare) {
    if (this.state !== STATE.LARGE_TICHU_PHASE) {
      return { success: false, message: 'Not in Large Tichu phase' };
    }
    if (this.largeTichuResponses[playerId] !== undefined) {
      return { success: false, message: 'Already responded' };
    }

    this.largeTichuResponses[playerId] = declare;
    if (declare) {
      this.largeTichuDeclarations.push(playerId);
    }

    // Check if all players responded
    if (Object.keys(this.largeTichuResponses).length === 4) {
      this.dealRemainingCards();
    }

    return {
      success: true,
      broadcast: {
        type: declare ? 'large_tichu_declared' : 'large_tichu_passed',
        player: playerId,
        playerName: this.playerNames[playerId],
      },
    };
  }

  dealRemainingCards() {
    this.state = STATE.DEALING_REMAINING_6;
    for (let i = 0; i < 4; i++) {
      const remaining = this.dealData.remaining6[i].map((c) => c.id);
      this.hands[this.playerIds[i]].push(...remaining);
    }
    this.state = STATE.CARD_EXCHANGE;
  }

  handleSmallTichuDeclaration(playerId) {
    // Small Tichu can be declared before playing first card (14 cards in hand)
    if (this.state !== STATE.CARD_EXCHANGE && this.state !== STATE.PLAYING) {
      return { success: false, message: 'Cannot declare Small Tichu now' };
    }
    if (this.smallTichuDeclarations.includes(playerId)) {
      return { success: false, message: 'Already declared Small Tichu' };
    }
    if (this.largeTichuDeclarations.includes(playerId)) {
      return { success: false, message: 'Already declared Large Tichu' };
    }
    if (this.hands[playerId].length < 14) {
      return { success: false, message: 'Can only declare Small Tichu with 14 cards' };
    }

    this.smallTichuDeclarations.push(playerId);
    return {
      success: true,
      broadcast: {
        type: 'small_tichu_declared',
        player: playerId,
        playerName: this.playerNames[playerId],
      },
    };
  }

  handleExchange(playerId, cards) {
    if (this.state !== STATE.CARD_EXCHANGE) {
      return { success: false, message: 'Not in exchange phase' };
    }
    if (this.exchangeDone[playerId]) {
      return { success: false, message: 'Already exchanged' };
    }
    // cards = { left: cardId, partner: cardId, right: cardId }
    if (!cards.left || !cards.partner || !cards.right) {
      return { success: false, message: 'Must select 3 cards to exchange' };
    }
    // Verify player has these cards
    const exchangeList = [cards.left, cards.partner, cards.right];
    for (const c of exchangeList) {
      if (!this.hands[playerId].includes(c)) {
        return { success: false, message: `Card ${c} not in hand` };
      }
    }
    // Check for duplicates
    if (new Set(exchangeList).size !== 3) {
      return { success: false, message: 'Must select 3 different cards' };
    }

    this.exchangeCards[playerId] = cards;
    this.exchangeDone[playerId] = true;

    // Check if all exchanged
    if (Object.keys(this.exchangeDone).length === 4) {
      this.performExchange();
    }

    return { success: true };
  }

  performExchange() {
    // Each player gives 1 card to left, 1 to partner, 1 to right
    // Seating: 0, 1, 2, 3 clockwise
    // Consistent with getStateForPlayer: (i+1)%4 = right, (i+2)%4 = partner, (i+3)%4 = left
    const receiving = {};
    for (const pid of this.playerIds) {
      receiving[pid] = [];
      this.receivedFrom[pid] = {};
    }

    for (let i = 0; i < 4; i++) {
      const pid = this.playerIds[i];
      const ex = this.exchangeCards[pid];
      const rightIdx = (i + 1) % 4;
      const partnerIdx = (i + 2) % 4;
      const leftIdx = (i + 3) % 4;

      // Remove given cards from hand
      this.hands[pid] = this.hands[pid].filter(
        (c) => c !== ex.left && c !== ex.partner && c !== ex.right
      );

      // Add to recipients and track who gave what
      const leftPid = this.playerIds[leftIdx];
      const partnerPid = this.playerIds[partnerIdx];
      const rightPid = this.playerIds[rightIdx];

      receiving[leftPid].push(ex.left);
      receiving[partnerPid].push(ex.partner);
      receiving[rightPid].push(ex.right);

      // From the recipient's perspective:
      // pid gives to left -> leftPid receives from right
      this.receivedFrom[leftPid].right = ex.left;
      // pid gives to partner -> partnerPid receives from partner
      this.receivedFrom[partnerPid].partner = ex.partner;
      // pid gives to right -> rightPid receives from left
      this.receivedFrom[rightPid].left = ex.right;
    }

    // Add received cards
    for (const pid of this.playerIds) {
      this.hands[pid].push(...receiving[pid]);
    }

    this.startPlaying();
  }

  startPlaying() {
    this.state = STATE.PLAYING;
    // Bird holder goes first
    for (const pid of this.playerIds) {
      if (this.hands[pid].includes('special_bird')) {
        this.currentPlayer = pid;
        this.trickStarter = pid;
        break;
      }
    }
  }

  handlePlayCards(playerId, cardIds, callRank = null) {
    if (this.state !== STATE.PLAYING) {
      return { success: false, message: 'Not in playing phase' };
    }
    if (this.dragonPending) {
      return { success: false, message: 'Waiting for Dragon give decision' };
    }
    if (playerId !== this.currentPlayer) {
      // S5: Verify cards in hand BEFORE combo validation
      if (!Array.isArray(cardIds)) {
        return { success: false, message: 'Invalid cards' };
      }
      for (const c of cardIds) {
        if (!this.hands[playerId].includes(c)) {
          return { success: false, message: 'Not your turn' };
        }
      }
      // Allow bombs from anyone (interruption)
      const combo = getComboType(cardIds);
      if (!isBomb(combo)) {
        return { success: false, message: 'Not your turn' };
      }
      // Bomb interruption
      return this.playBomb(playerId, cardIds, combo);
    }

    // S11: Validate cardIds is an array
    if (!Array.isArray(cardIds) || cardIds.length === 0) {
      return { success: false, message: 'Invalid cards' };
    }

    // Verify cards in hand
    for (const c of cardIds) {
      if (!this.hands[playerId].includes(c)) {
        return { success: false, message: `Card ${c} not in hand` };
      }
    }

    // Check Dog - special play
    if (cardIds.length === 1 && cardIds[0] === 'special_dog') {
      return this.playDog(playerId);
    }

    // Validate combo
    const combo = getComboType(cardIds);
    if (combo.type === COMBO.INVALID) {
      return { success: false, message: 'Invalid card combination' };
    }

    // If Phoenix played as single, set value to current top + 0.5
    if (combo.isPhoenix && this.currentTrick.length > 0) {
      const lastCombo = this.currentTrick[this.currentTrick.length - 1].combo;
      combo.value = lastCombo.value + 0.5;
    }

    // Check if can beat current trick
    if (this.currentTrick.length > 0) {
      const lastCombo = this.currentTrick[this.currentTrick.length - 1].combo;
      if (!canBeat(lastCombo, combo)) {
        return { success: false, message: 'Cannot beat current cards' };
      }
    }

    // Check call fulfillment
    if (this.callRank && this.currentTrick.length > 0) {
      if (!this.isCallFulfilled(playerId, cardIds, combo)) {
        // Player must fulfill call if possible
        if (this.canFulfillCallAndBeat(playerId)) {
          return { success: false, message: `Must play a card of rank ${this.callRank} (Call)` };
        }
      }
    }

    // Play the cards (arrange Phoenix position for display)
    const arrangedCards = arrangeCardsWithPhoenix(cardIds, combo);
    this.removeCardsFromHand(playerId, cardIds);
    this.currentTrick.push({ playerId, cards: arrangedCards, combo });
    this.lastPlayedBy = playerId;
    this.passCount = 0;

    const result = {
      success: true,
      broadcast: {
        type: 'cards_played',
        player: playerId,
        playerName: this.playerNames[playerId],
        cards: arrangedCards,
        combo: combo.type,
        phoenixAs: combo.phoenixAs,
      },
    };

    // Check if Bird was played (player must call)
    if (cardIds.includes('special_bird')) {
      if (callRank) {
        // Call provided with Bird play - process immediately
        const validRanks = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];
        if (validRanks.includes(callRank) || validRanks.includes(callRank.toString())) {
          this.callRank = callRank.toString();
          result.broadcast.callRank = this.callRank;
        }
      } else {
        // No call provided - wait for separate call
        result.broadcast.birdPlayed = true;
        this.needsToCallRank = playerId;
      }
    }

    // Check if call is fulfilled
    if (this.callRank) {
      const hasWishRank = cardIds.some((c) => {
        const v = getCardValue(c);
        return v.toString() === this.callRank || this.getRankName(v) === this.callRank;
      });
      if (hasWishRank) {
        this.callRank = null;
        result.broadcast.callFulfilled = true;
      }
    }

    // Check if player finished
    if (this.hands[playerId].length === 0) {
      this.finishOrder.push(playerId);
      result.broadcast.playerFinished = true;
      result.broadcast.finishPosition = this.finishOrder.length;

      // Check for 1-2 finish (same team finishes 1st and 2nd)
      if (this.finishOrder.length === 2) {
        const first = this.finishOrder[0];
        const second = this.finishOrder[1];
        const firstTeam = this.teams.teamA.includes(first) ? 'teamA' : 'teamB';
        const secondTeam = this.teams.teamA.includes(second) ? 'teamA' : 'teamB';
        if (firstTeam === secondTeam) {
          result.broadcast.oneTwoFinish = true;
          result.broadcast.winningTeam = firstTeam;
          this.endRound();
          return result;
        }
      }

      // Check if round is over (3 players finished)
      if (this.finishOrder.length >= 3) {
        this.endRound();
        return result;
      }
    }

    // Dragon special: winner must give trick to opponent
    if (cardIds.includes('special_dragon')) {
      // Dragon effect handled when trick is won
    }

    // Advance turn
    this.advanceTurn();
    return result;
  }

  playBomb(playerId, cardIds, combo) {
    // Verify cards in hand
    for (const c of cardIds) {
      if (!this.hands[playerId].includes(c)) {
        return { success: false, message: `Card ${c} not in hand` };
      }
    }

    if (this.currentTrick.length > 0) {
      const lastCombo = this.currentTrick[this.currentTrick.length - 1].combo;
      if (!canBeat(lastCombo, combo)) {
        return { success: false, message: 'Bomb is not strong enough' };
      }
    }

    this.removeCardsFromHand(playerId, cardIds);
    this.currentTrick.push({ playerId, cards: cardIds, combo });
    this.lastPlayedBy = playerId;
    this.passCount = 0;
    this.currentPlayer = playerId;
    this.advanceTurn();

    return {
      success: true,
      broadcast: {
        type: 'bomb_played',
        player: playerId,
        playerName: this.playerNames[playerId],
        cards: cardIds,
        combo: combo.type,
      },
    };
  }

  playDog(playerId) {
    if (this.currentTrick.length > 0) {
      return { success: false, message: 'Dog can only be played to start a trick' };
    }

    this.removeCardsFromHand(playerId, ['special_dog']);

    // Dog passes lead to partner
    const partnerIdx = (this.playerIds.indexOf(playerId) + 2) % 4;
    const partner = this.playerIds[partnerIdx];

    // If partner already finished, find next active player
    if (this.finishOrder.includes(partner)) {
      this.currentPlayer = this.getNextActivePlayer(partner);
    } else {
      this.currentPlayer = partner;
    }
    this.trickStarter = this.currentPlayer;

    return {
      success: true,
      broadcast: {
        type: 'dog_played',
        player: playerId,
        playerName: this.playerNames[playerId],
        nextPlayer: this.currentPlayer,
      },
    };
  }

  handlePass(playerId) {
    if (this.state !== STATE.PLAYING) {
      return { success: false, message: 'Not in playing phase' };
    }
    if (playerId !== this.currentPlayer) {
      return { success: false, message: 'Not your turn' };
    }
    if (this.currentTrick.length === 0) {
      return { success: false, message: 'Cannot pass when starting a new trick' };
    }

    // Check if player CAN play (Call obligation)
    if (this.callRank && this.canFulfillCallAndBeat(playerId)) {
      return { success: false, message: `Must play a card of rank ${this.callRank} (Call)` };
    }

    this.passCount++;

    const result = {
      success: true,
      broadcast: {
        type: 'player_passed',
        player: playerId,
        playerName: this.playerNames[playerId],
      },
    };

    // Count active players (not finished)
    const activePlayers = this.playerIds.filter((p) => !this.finishOrder.includes(p));
    const passesNeeded = activePlayers.length - 1;

    // Check if trick is won
    if (this.passCount >= passesNeeded) {
      this.resolveTrick();
    } else {
      this.advanceTurn();
    }

    return result;
  }

  resolveTrick() {
    const winner = this.lastPlayedBy;
    const allTrickCards = [];
    for (const play of this.currentTrick) {
      allTrickCards.push(...play.cards);
    }

    // Check if Dragon won the trick
    const lastPlay = this.currentTrick[this.currentTrick.length - 1];
    if (lastPlay.cards.includes('special_dragon')) {
      // Dragon winner must give trick to an opponent
      this.dragonPending = true;
      this.dragonDecider = winner;
      this.pendingTrickCards = allTrickCards;
      // Don't clear trick yet; wait for dragon_give
      this.currentTrick = [];
      this.passCount = 0;
      return;
    }

    // Add cards to winner's trick pile
    this.trickPiles[winner].push(...allTrickCards);

    // Clear trick
    this.currentTrick = [];
    this.passCount = 0;
    this.lastPlayedBy = null;

    // Winner starts next trick
    if (this.finishOrder.includes(winner)) {
      this.currentPlayer = this.getNextActivePlayer(winner);
    } else {
      this.currentPlayer = winner;
    }
    this.trickStarter = this.currentPlayer;
  }

  handleDragonGive(playerId, target) {
    if (!this.dragonPending || this.dragonDecider !== playerId) {
      return { success: false, message: 'Not waiting for your Dragon give decision' };
    }

    // Target must be an opponent (left or right)
    // Consistent with getStateForPlayer: (i+1)%4 = right, (i+3)%4 = left
    const myIdx = this.playerIds.indexOf(playerId);
    const rightIdx = (myIdx + 1) % 4;
    const leftIdx = (myIdx + 3) % 4;
    let targetId;

    if (target === 'left') {
      targetId = this.playerIds[leftIdx];
    } else if (target === 'right') {
      targetId = this.playerIds[rightIdx];
    } else {
      return { success: false, message: 'Target must be "left" or "right"' };
    }

    // Verify target is an opponent
    const myTeam = this.teams.teamA.includes(playerId) ? 'teamA' : 'teamB';
    const targetTeam = this.teams.teamA.includes(targetId) ? 'teamA' : 'teamB';
    if (myTeam === targetTeam) {
      return { success: false, message: 'Must give Dragon trick to an opponent' };
    }

    this.trickPiles[targetId].push(...this.pendingTrickCards);
    this.dragonPending = false;
    this.dragonDecider = null;
    this.pendingTrickCards = null;

    // Winner starts next trick
    if (this.finishOrder.includes(playerId)) {
      this.currentPlayer = this.getNextActivePlayer(playerId);
    } else {
      this.currentPlayer = playerId;
    }
    this.trickStarter = this.currentPlayer;

    return {
      success: true,
      broadcast: {
        type: 'dragon_given',
        from: playerId,
        fromName: this.playerNames[playerId],
        to: targetId,
        targetName: this.playerNames[targetId],
      },
    };
  }

  handleCallRank(playerId, rank) {
    if (this.state !== STATE.PLAYING) {
      return { success: false, message: 'Not in playing phase' };
    }
    // Verify this player just played Bird
    if (this.currentTrick.length === 0) {
      return { success: false, message: 'No current trick' };
    }
    const lastPlay = this.currentTrick[this.currentTrick.length - 1];
    if (lastPlay.playerId !== playerId || !lastPlay.cards.includes('special_bird')) {
      return { success: false, message: 'Only the Bird player can call' };
    }

    // Allow "none" to skip calling
    if (rank === 'none') {
      this.callRank = null;
      this.needsToCallRank = null;
      console.log(`[DEBUG] call_rank skipped: player chose no call`);
      return {
        success: true,
        broadcast: {
          type: 'call_rank',
          player: playerId,
          playerName: this.playerNames[playerId],
          rank: null,
        },
      };
    }

    // Validate rank (2-14 or "2"-"A")
    const validRanks = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];
    if (!validRanks.includes(rank) && !validRanks.includes(rank.toString())) {
      return { success: false, message: 'Invalid call rank' };
    }

    this.callRank = rank.toString();
    this.needsToCallRank = null;
    console.log(`[DEBUG] call_rank handled: callRank=${this.callRank}, needsToCallRank=${this.needsToCallRank}`);

    return {
      success: true,
      broadcast: {
        type: 'call_rank',
        player: playerId,
        playerName: this.playerNames[playerId],
        rank: this.callRank,
      },
    };
  }

  // Helper: Check if call is fulfilled in played cards
  isCallFulfilled(playerId, cardIds, combo) {
    if (!this.callRank) return true;
    const wishValue = this.rankToValue(this.callRank);
    return cardIds.some((c) => getCardValue(c) === wishValue);
  }

  canFulfillCall(playerId) {
    if (!this.callRank) return false;
    const wishValue = this.rankToValue(this.callRank);
    return this.hands[playerId].some((c) => getCardValue(c) === wishValue);
  }

  canFulfillCallAndBeat(playerId) {
    if (!this.callRank) return false;
    if (this.currentTrick.length === 0) return false;

    const lastCombo = this.currentTrick[this.currentTrick.length - 1].combo;
    if (!lastCombo) return false;

    const hand = this.hands[playerId];
    const wishValue = this.rankToValue(this.callRank);
    const wishMask = hand.reduce((mask, cardId, idx) => {
      return getCardValue(cardId) === wishValue ? (mask | (1 << idx)) : mask;
    }, 0);

    if (wishMask === 0) return false;

    const totalMasks = 1 << hand.length;
    for (let mask = 1; mask < totalMasks; mask++) {
      if ((mask & wishMask) === 0) continue;

      const subset = [];
      for (let i = 0; i < hand.length; i++) {
        if (mask & (1 << i)) subset.push(hand[i]);
      }

      const combo = getComboType(subset);
      if (combo.type === COMBO.INVALID) continue;

      if (combo.isPhoenix && this.currentTrick.length > 0) {
        combo.value = lastCombo.value + 0.5;
      }

      if (canBeat(lastCombo, combo)) {
        return true;
      }
    }

    return false;
  }

  rankToValue(rank) {
    const map = { '2': 2, '3': 3, '4': 4, '5': 5, '6': 6, '7': 7, '8': 8, '9': 9, '10': 10, 'J': 11, 'Q': 12, 'K': 13, 'A': 14 };
    return map[rank] || parseInt(rank) || 0;
  }

  getRankName(value) {
    const map = { 2: '2', 3: '3', 4: '4', 5: '5', 6: '6', 7: '7', 8: '8', 9: '9', 10: '10', 11: 'J', 12: 'Q', 13: 'K', 14: 'A' };
    return map[value] || '';
  }

  removeCardsFromHand(playerId, cardIds) {
    for (const c of cardIds) {
      const idx = this.hands[playerId].indexOf(c);
      if (idx !== -1) this.hands[playerId].splice(idx, 1);
    }
  }

  advanceTurn() {
    const currentIdx = this.playerIds.indexOf(this.currentPlayer);
    let nextIdx = (currentIdx + 1) % 4;

    // Skip finished players
    for (let i = 0; i < 4; i++) {
      const candidate = this.playerIds[nextIdx];
      if (!this.finishOrder.includes(candidate)) {
        this.currentPlayer = candidate;
        return;
      }
      nextIdx = (nextIdx + 1) % 4;
    }
  }

  getNextActivePlayer(fromPlayer) {
    const fromIdx = this.playerIds.indexOf(fromPlayer);
    let nextIdx = (fromIdx + 1) % 4;
    for (let i = 0; i < 4; i++) {
      const candidate = this.playerIds[nextIdx];
      if (!this.finishOrder.includes(candidate)) {
        return candidate;
      }
      nextIdx = (nextIdx + 1) % 4;
    }
    return null;
  }

  endRound() {
    this.state = STATE.ROUND_END;

    // Add remaining active player to finish order
    for (const pid of this.playerIds) {
      if (!this.finishOrder.includes(pid)) {
        this.finishOrder.push(pid);
      }
    }

    const roundScores = calculateRoundScores({
      finishOrder: this.finishOrder,
      teams: this.teams,
      trickPiles: this.trickPiles,
      smallTichuDeclarations: this.smallTichuDeclarations,
      largeTichuDeclarations: this.largeTichuDeclarations,
      playerCards: this.hands,
    });

    this.totalScores.teamA += roundScores.teamA;
    this.totalScores.teamB += roundScores.teamB;

    // Check if game is over (tied scores → continue playing)
    if ((this.totalScores.teamA >= this.targetScore || this.totalScores.teamB >= this.targetScore)
        && this.totalScores.teamA !== this.totalScores.teamB) {
      this.state = STATE.GAME_END;
    }

    this.lastRoundScores = roundScores;
  }

  // Start next round
  nextRound() {
    if (this.state === STATE.GAME_END) return;
    this.start();
  }

  getStateForPlayer(playerId) {
    const playerIdx = this.playerIds.indexOf(playerId);
    const otherPlayers = [];

    for (let i = 0; i < 4; i++) {
      const pid = this.playerIds[i];
      const relativePos = ((i - playerIdx) + 4) % 4;
      // 0=self, 1=right, 2=partner, 3=left
      let position;
      if (relativePos === 0) position = 'self';
      else if (relativePos === 1) position = 'right';
      else if (relativePos === 2) position = 'partner';
      else position = 'left';

      otherPlayers.push({
        id: pid,
        name: this.playerNames[pid],
        position: position,
        cardCount: this.hands[pid].length,
        hasFinished: this.finishOrder.includes(pid),
        finishPosition: this.finishOrder.indexOf(pid) + 1 || 0,
        hasSmallTichu: this.smallTichuDeclarations.includes(pid),
        hasLargeTichu: this.largeTichuDeclarations.includes(pid),
      });
    }

    return {
      phase: this.state,
      round: this.round,
      myCards: sortCards(this.hands[playerId]).map((c) => typeof c === 'string' ? c : c.id),
      players: otherPlayers,
      currentPlayer: this.currentPlayer,
      isMyTurn: this.currentPlayer === playerId,
      currentTrick: this.currentTrick.map((t) => ({
        playerId: t.playerId,
        playerName: this.playerNames[t.playerId],
        cards: t.cards,
        combo: t.combo.type,
        comboValue: t.combo.value,
      })),
      teams: this.teams,
      totalScores: this.totalScores,
      lastRoundScores: this.lastRoundScores || null,
      finishOrder: this.finishOrder,
      callRank: this.callRank,
      needsToCallRank: this.needsToCallRank === playerId,
      dragonPending: this.dragonPending && this.dragonDecider === playerId,
      exchangeDone: !!this.exchangeDone[playerId],
      receivedFrom: this.receivedFrom[playerId] || null,
      largeTichuResponded: this.largeTichuResponses[playerId] !== undefined,
      canDeclareSmallTichu: this.hands[playerId].length === 14 &&
        !this.smallTichuDeclarations.includes(playerId) &&
        !this.largeTichuDeclarations.includes(playerId),
    };
  }

  getStateForSpectator(permittedPlayerIds = new Set()) {
    const players = this.playerIds.map((pid, i) => {
      const canSeeCards = permittedPlayerIds.has(pid);
      return {
        id: pid,
        name: this.playerNames[pid],
        position: i,
        cards: canSeeCards
          ? sortCards(this.hands[pid]).map((c) => typeof c === 'string' ? c : c.id)
          : [],
        cardCount: this.hands[pid].length,
        canSeeCards: canSeeCards,
        hasFinished: this.finishOrder.includes(pid),
        finishPosition: this.finishOrder.indexOf(pid) + 1 || 0,
        hasSmallTichu: this.smallTichuDeclarations.includes(pid),
        hasLargeTichu: this.largeTichuDeclarations.includes(pid),
        team: this.teams.teamA.includes(pid) ? 'A' : 'B',
      };
    });

    return {
      phase: this.state,
      round: this.round,
      players: players,
      currentPlayer: this.currentPlayer,
      currentPlayerName: this.playerNames[this.currentPlayer],
      currentTrick: this.currentTrick.map((t) => ({
        playerId: t.playerId,
        playerName: this.playerNames[t.playerId],
        cards: t.cards,
        combo: t.combo.type,
        comboValue: t.combo.value,
      })),
      teams: this.teams,
      totalScores: this.totalScores,
      lastRoundScores: this.lastRoundScores || null,
      finishOrder: this.finishOrder,
      callRank: this.callRank,
      dragonPending: this.dragonPending,
      dragonDecider: this.dragonDecider ? this.playerNames[this.dragonDecider] : null,
    };
  }

  // Auto timeout action for when a player's turn timer expires
  getAutoTimeoutAction(playerId) {
    if (this.state !== STATE.PLAYING) return null;

    // Needs to call rank (played bird without calling)
    if (this.needsToCallRank === playerId) {
      const ranks = ['2','3','4','5','6','7','8','9','10','J','Q','K','A'];
      return { type: 'call_rank', rank: ranks[Math.floor(Math.random() * ranks.length)] };
    }

    // Dragon give decision pending
    if (this.dragonPending && this.dragonDecider === playerId) {
      return { type: 'dragon_give', target: 'left' };
    }

    if (this.currentPlayer !== playerId) return null;

    // Must start a new trick (can't pass) → play lowest card
    if (this.currentTrick.length === 0) {
      const hand = this.hands[playerId];
      const sorted = [...hand].sort((a, b) => getCardValue(a) - getCardValue(b));
      const card = sorted[0];
      if (card === 'special_bird') {
        const ranks = ['2','3','4','5','6','7','8','9','10','J','Q','K','A'];
        return { type: 'play_cards', cards: [card], callRank: ranks[Math.floor(Math.random() * ranks.length)] };
      }
      return { type: 'play_cards', cards: [card] };
    }

    // Call obligation → find and play a card fulfilling the call
    if (this.callRank && this.canFulfillCallAndBeat(playerId)) {
      return this._findCallFulfillPlay(playerId);
    }

    // Otherwise → pass
    return { type: 'pass' };
  }

  // Find a playable card combination that fulfills the active call
  _findCallFulfillPlay(playerId) {
    const hand = this.hands[playerId];
    const wishValue = this.rankToValue(this.callRank);
    const lastCombo = this.currentTrick[this.currentTrick.length - 1].combo;

    const wishMask = hand.reduce((mask, cardId, idx) => {
      return getCardValue(cardId) === wishValue ? (mask | (1 << idx)) : mask;
    }, 0);

    if (wishMask === 0) return { type: 'pass' };

    const totalMasks = 1 << hand.length;
    for (let mask = 1; mask < totalMasks; mask++) {
      if ((mask & wishMask) === 0) continue;

      const subset = [];
      for (let i = 0; i < hand.length; i++) {
        if (mask & (1 << i)) subset.push(hand[i]);
      }

      const combo = getComboType(subset);
      if (combo.type === COMBO.INVALID) continue;

      if (combo.isPhoenix && this.currentTrick.length > 0) {
        combo.value = lastCombo.value + 0.5;
      }

      if (canBeat(lastCombo, combo)) {
        return { type: 'play_cards', cards: subset };
      }
    }

    return { type: 'pass' };
  }

  // Update player ID when reconnecting
  updatePlayerId(oldPlayerId, newPlayerId) {
    const idx = this.playerIds.indexOf(oldPlayerId);
    if (idx === -1) return false;

    // Update playerIds array
    this.playerIds[idx] = newPlayerId;

    // Update playerNames
    this.playerNames[newPlayerId] = this.playerNames[oldPlayerId];
    delete this.playerNames[oldPlayerId];

    // Update teams
    for (const team of ['teamA', 'teamB']) {
      const teamIdx = this.teams[team].indexOf(oldPlayerId);
      if (teamIdx !== -1) {
        this.teams[team][teamIdx] = newPlayerId;
      }
    }

    // Update hands
    if (this.hands[oldPlayerId]) {
      this.hands[newPlayerId] = this.hands[oldPlayerId];
      delete this.hands[oldPlayerId];
    }

    // Update trickPiles
    if (this.trickPiles[oldPlayerId]) {
      this.trickPiles[newPlayerId] = this.trickPiles[oldPlayerId];
      delete this.trickPiles[oldPlayerId];
    }

    // Update declarations
    const largeTichuIdx = this.largeTichuDeclarations.indexOf(oldPlayerId);
    if (largeTichuIdx !== -1) this.largeTichuDeclarations[largeTichuIdx] = newPlayerId;

    const smallTichuIdx = this.smallTichuDeclarations.indexOf(oldPlayerId);
    if (smallTichuIdx !== -1) this.smallTichuDeclarations[smallTichuIdx] = newPlayerId;

    // Update responses
    if (this.largeTichuResponses[oldPlayerId] !== undefined) {
      this.largeTichuResponses[newPlayerId] = this.largeTichuResponses[oldPlayerId];
      delete this.largeTichuResponses[oldPlayerId];
    }

    // Update exchange
    if (this.exchangeCards[oldPlayerId]) {
      this.exchangeCards[newPlayerId] = this.exchangeCards[oldPlayerId];
      delete this.exchangeCards[oldPlayerId];
    }
    if (this.exchangeDone[oldPlayerId]) {
      this.exchangeDone[newPlayerId] = this.exchangeDone[oldPlayerId];
      delete this.exchangeDone[oldPlayerId];
    }

    // S12: Update receivedFrom
    if (this.receivedFrom[oldPlayerId]) {
      this.receivedFrom[newPlayerId] = this.receivedFrom[oldPlayerId];
      delete this.receivedFrom[oldPlayerId];
    }

    // Update finishOrder
    const finishIdx = this.finishOrder.indexOf(oldPlayerId);
    if (finishIdx !== -1) this.finishOrder[finishIdx] = newPlayerId;

    // Update current state
    if (this.currentPlayer === oldPlayerId) this.currentPlayer = newPlayerId;
    if (this.lastPlayedBy === oldPlayerId) this.lastPlayedBy = newPlayerId;
    if (this.trickStarter === oldPlayerId) this.trickStarter = newPlayerId;
    if (this.needsToCallRank === oldPlayerId) this.needsToCallRank = newPlayerId;
    if (this.dragonDecider === oldPlayerId) this.dragonDecider = newPlayerId;

    // Update trick plays
    for (const trick of this.currentTrick) {
      if (trick.playerId === oldPlayerId) trick.playerId = newPlayerId;
    }

    console.log(`Updated player ID: ${oldPlayerId} -> ${newPlayerId}`);
    return true;
  }
}

module.exports = TichuGame;
