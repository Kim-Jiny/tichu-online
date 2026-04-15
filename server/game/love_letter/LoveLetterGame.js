/**
 * Love Letter Game - State machine and rule engine
 *
 * States: waiting → playing → effect_resolve → round_end → game_end
 * 2-4 players, token-based victory (2p: 4 tokens, 3-4p: 3 tokens)
 */

const { deal, getCardInfo, sortCards, CARD_TYPE, CARD_VALUES, GUESSABLE_TYPES } = require('./LoveLetterDeck');

class LoveLetterGame {
  constructor(playerIds, playerNames, options = {}) {
    this.playerIds = playerIds;
    this.playerNames = playerNames;
    this.playerCount = playerIds.length;
    this.gameType = 'love_letter';

    // Token target: 2p → 4, 3-4p → 3
    this.targetTokens = options.targetTokens || (this.playerCount === 2 ? 4 : 3);

    this.state = 'waiting';
    this.round = 0;

    // Game-wide state
    this.tokens = {};
    for (const pid of playerIds) {
      this.tokens[pid] = 0;
    }
    this.roundHistory = [];

    // Per-round state (initialized in startNextRound)
    this.hands = {};
    this.discardPiles = {};
    this.drawPile = [];
    this.setAside = null;
    this.faceUpCards = [];
    this.eliminated = {};
    this.protected = {};
    this.currentPlayer = null;
    this.pendingEffect = null;
    this.hasDrawn = false;

    this.resultSaved = false;
    this.deserted = false;
  }

  start() {
    this.round = 0;
    this.startNextRound();
  }

  startNextRound() {
    this.round++;

    const result = deal(this.playerIds);
    this.hands = {};
    this.discardPiles = {};
    this.eliminated = {};
    this.protected = {};

    for (const pid of this.playerIds) {
      this.hands[pid] = result.hands[pid].map(c => c.id);
      this.discardPiles[pid] = [];
      this.eliminated[pid] = false;
      this.protected[pid] = false;
    }

    this.drawPile = result.drawPile.map(c => c.id);
    this.setAside = result.setAside.id;
    this.faceUpCards = result.faceUpCards.map(c => c.id);
    this.pendingEffect = null;
    this.hasDrawn = false;

    // First player is random in round 1, then the round winner leads
    if (this.round === 1) {
      this.currentPlayer = this.playerIds[Math.floor(Math.random() * this.playerCount)];
    }
    // else currentPlayer is already set to last round winner

    // Draw a card for the first player
    this._drawCard(this.currentPlayer);
    this.state = 'playing';
  }

  _drawCard(playerId) {
    if (this.drawPile.length > 0) {
      const card = this.drawPile.shift();
      this.hands[playerId].push(card);
      this.hasDrawn = true;
    }
  }

  _getAlivePlayers() {
    return this.playerIds.filter(pid => !this.eliminated[pid]);
  }

  _getTargetablePlayers(playerId) {
    const alive = this._getAlivePlayers().filter(pid => pid !== playerId);
    // Filter out protected players
    const targetable = alive.filter(pid => !this.protected[pid]);
    return targetable;
  }

  handleAction(playerId, data) {
    switch (data.type) {
      case 'play_card':
        return this.handlePlayCard(playerId, data.cardId);
      case 'select_target':
        return this.handleSelectTarget(playerId, data.targetId);
      case 'guard_guess':
        return this.handleGuardGuess(playerId, data.targetId, data.guess);
      case 'effect_ack':
        return this.handleEffectAck(playerId);
      case 'next_round':
        return this.handleNextRound();
      default:
        return { success: false, messageKey: 'game_unknown_action', messageParams: { type: data.type } };
    }
  }

  handlePlayCard(playerId, cardId) {
    if (this.state !== 'playing') {
      return { success: false, messageKey: 'll_not_play_phase' };
    }
    if (playerId !== this.currentPlayer) {
      return { success: false, messageKey: 'll_not_your_turn' };
    }
    if (this.eliminated[playerId]) {
      return { success: false, messageKey: 'll_eliminated' };
    }

    const hand = this.hands[playerId];
    if (!hand || !hand.includes(cardId)) {
      return { success: false, messageKey: 'll_card_not_in_hand' };
    }

    const cardInfo = getCardInfo(cardId);
    if (!cardInfo) {
      return { success: false, messageKey: 'll_invalid_card' };
    }

    // Countess rule: must play Countess if holding King or Prince
    if (cardInfo.type !== CARD_TYPE.COUNTESS && hand.length > 1) {
      const hasCountess = hand.some(c => getCardInfo(c)?.type === CARD_TYPE.COUNTESS);
      if (hasCountess && (cardInfo.type === CARD_TYPE.KING || cardInfo.type === CARD_TYPE.PRINCE)) {
        return { success: false, messageKey: 'll_countess_forced' };
      }
    }

    // Remove card from hand
    this.hands[playerId] = hand.filter(c => c !== cardId);
    this.discardPiles[playerId].push(cardId);

    // Process card effect
    return this._processCardEffect(playerId, cardInfo, cardId);
  }

  _processCardEffect(playerId, cardInfo, cardId) {
    const targetable = this._getTargetablePlayers(playerId);

    switch (cardInfo.type) {
      case CARD_TYPE.PRINCESS:
        // Playing Princess = instant elimination
        this._eliminatePlayer(playerId);
        return this._advanceTurnOrEndRound();

      case CARD_TYPE.COUNTESS:
        // No effect, just discard
        return this._advanceTurnOrEndRound();

      case CARD_TYPE.HANDMAID:
        // Protection until next turn
        this.protected[playerId] = true;
        return this._advanceTurnOrEndRound();

      case CARD_TYPE.GUARD:
        if (targetable.length === 0) {
          // No valid target, effect fizzles
          return this._advanceTurnOrEndRound();
        }
        // Need target + guess
        this.state = 'effect_resolve';
        this.pendingEffect = {
          type: 'guard',
          playerId,
          cardId,
          needsTarget: true,
          needsGuess: true,
          validTargets: targetable,
        };
        return { success: true };

      case CARD_TYPE.SPY:
        if (targetable.length === 0) {
          return this._advanceTurnOrEndRound();
        }
        this.state = 'effect_resolve';
        this.pendingEffect = {
          type: 'spy',
          playerId,
          cardId,
          needsTarget: true,
          validTargets: targetable,
        };
        return { success: true };

      case CARD_TYPE.BARON:
        if (targetable.length === 0) {
          return this._advanceTurnOrEndRound();
        }
        this.state = 'effect_resolve';
        this.pendingEffect = {
          type: 'baron',
          playerId,
          cardId,
          needsTarget: true,
          validTargets: targetable,
        };
        return { success: true };

      case CARD_TYPE.PRINCE:
        // Prince can target self or others
        const princeTargets = this._getAlivePlayers().filter(pid =>
          pid === playerId || !this.protected[pid]
        );
        if (princeTargets.length === 0) {
          return this._advanceTurnOrEndRound();
        }
        this.state = 'effect_resolve';
        this.pendingEffect = {
          type: 'prince',
          playerId,
          cardId,
          needsTarget: true,
          validTargets: princeTargets,
        };
        return { success: true };

      case CARD_TYPE.KING:
        if (targetable.length === 0) {
          return this._advanceTurnOrEndRound();
        }
        this.state = 'effect_resolve';
        this.pendingEffect = {
          type: 'king',
          playerId,
          cardId,
          needsTarget: true,
          validTargets: targetable,
        };
        return { success: true };

      default:
        return { success: false, messageKey: 'll_invalid_card' };
    }
  }

  handleSelectTarget(playerId, targetId) {
    if (this.state !== 'effect_resolve' || !this.pendingEffect) {
      return { success: false, messageKey: 'll_no_pending_effect' };
    }
    if (this.pendingEffect.playerId !== playerId) {
      return { success: false, messageKey: 'll_not_your_turn' };
    }
    if (!this.pendingEffect.needsTarget) {
      return { success: false, messageKey: 'll_no_target_needed' };
    }
    if (!this.pendingEffect.validTargets.includes(targetId)) {
      return { success: false, messageKey: 'll_invalid_target' };
    }

    this.pendingEffect.targetId = targetId;
    this.pendingEffect.needsTarget = false;

    // Guard still needs a guess
    if (this.pendingEffect.type === 'guard' && this.pendingEffect.needsGuess) {
      return { success: true };
    }

    // Resolve the effect
    return this._resolveEffect();
  }

  handleGuardGuess(playerId, targetId, guess) {
    if (this.state !== 'effect_resolve' || !this.pendingEffect) {
      return { success: false, messageKey: 'll_no_pending_effect' };
    }
    if (this.pendingEffect.playerId !== playerId) {
      return { success: false, messageKey: 'll_not_your_turn' };
    }
    if (this.pendingEffect.type !== 'guard') {
      return { success: false, messageKey: 'll_not_guard_effect' };
    }

    // If target not yet selected, set it
    if (this.pendingEffect.needsTarget) {
      if (!this.pendingEffect.validTargets.includes(targetId)) {
        return { success: false, messageKey: 'll_invalid_target' };
      }
      this.pendingEffect.targetId = targetId;
      this.pendingEffect.needsTarget = false;
    }

    // Validate guess (cannot guess Guard)
    if (!GUESSABLE_TYPES.includes(guess)) {
      return { success: false, messageKey: 'll_invalid_guess' };
    }

    this.pendingEffect.guess = guess;
    this.pendingEffect.needsGuess = false;

    return this._resolveEffect();
  }

  handleEffectAck(playerId) {
    if (this.state !== 'effect_resolve' || !this.pendingEffect) {
      return { success: false, messageKey: 'll_no_pending_effect' };
    }
    if (!this.pendingEffect.resolved) {
      return { success: false, messageKey: 'll_effect_not_resolved' };
    }

    // Only the acting player needs to ack
    if (this.pendingEffect.playerId !== playerId) {
      return { success: false, messageKey: 'll_not_your_turn' };
    }

    this.pendingEffect = null;
    return this._advanceTurnOrEndRound();
  }

  handleNextRound() {
    if (this.state !== 'round_end') {
      return { success: false, messageKey: 'll_not_round_end' };
    }
    this.startNextRound();
    return { success: true };
  }

  _resolveEffect() {
    const effect = this.pendingEffect;
    const targetId = effect.targetId;

    switch (effect.type) {
      case 'guard': {
        const targetHand = this.hands[targetId];
        const targetCard = targetHand[0];
        const targetInfo = getCardInfo(targetCard);
        const correct = targetInfo && targetInfo.type === effect.guess;

        effect.result = {
          correct,
          targetCard: correct ? targetCard : null,
        };

        if (correct) {
          this._eliminatePlayer(targetId);
        }
        effect.resolved = true;
        return { success: true };
      }

      case 'spy': {
        const targetHand = this.hands[targetId];
        effect.result = {
          revealedCard: targetHand[0],
        };
        effect.resolved = true;
        return { success: true };
      }

      case 'baron': {
        const myCard = this.hands[effect.playerId][0];
        const targetCard = this.hands[targetId][0];
        const myInfo = getCardInfo(myCard);
        const targetInfo = getCardInfo(targetCard);
        const myValue = myInfo ? myInfo.value : 0;
        const targetValue = targetInfo ? targetInfo.value : 0;

        let loser = null;
        if (myValue > targetValue) {
          loser = targetId;
        } else if (targetValue > myValue) {
          loser = effect.playerId;
        }
        // Tie: nobody eliminated

        effect.result = {
          myCard,
          targetCard,
          loser,
        };

        if (loser) {
          this._eliminatePlayer(loser);
        }
        effect.resolved = true;
        return { success: true };
      }

      case 'prince': {
        const targetHand = this.hands[targetId];
        const discardedCard = targetHand[0];
        const discardedInfo = getCardInfo(discardedCard);

        // Discard the card
        this.hands[targetId] = [];
        this.discardPiles[targetId].push(discardedCard);

        if (discardedInfo && discardedInfo.type === CARD_TYPE.PRINCESS) {
          // Forced to discard Princess = eliminated
          this._eliminatePlayer(targetId);
          effect.result = { discardedCard, eliminated: true };
        } else {
          // Draw a new card
          if (this.drawPile.length > 0) {
            const newCard = this.drawPile.shift();
            this.hands[targetId].push(newCard);
          } else if (this.setAside) {
            // Draw pile empty: take the set-aside card
            this.hands[targetId].push(this.setAside);
            this.setAside = null;
          }
          // If no cards available (empty draw pile + no set-aside), player has 0 cards
          // but is still alive — round will end when _advanceTurnOrEndRound checks
          effect.result = { discardedCard, eliminated: false };
        }
        effect.resolved = true;
        return { success: true };
      }

      case 'king': {
        // Swap hands
        const myHand = this.hands[effect.playerId];
        const targetHand = this.hands[targetId];
        this.hands[effect.playerId] = targetHand;
        this.hands[targetId] = myHand;

        effect.result = { swapped: true };
        effect.resolved = true;
        return { success: true };
      }

      default:
        return { success: false, messageKey: 'll_invalid_effect' };
    }
  }

  _eliminatePlayer(playerId) {
    this.eliminated[playerId] = true;
    // Discard their hand
    const hand = this.hands[playerId];
    if (hand && hand.length > 0) {
      this.discardPiles[playerId].push(...hand);
      this.hands[playerId] = [];
    }
  }

  _advanceTurnOrEndRound() {
    const alive = this._getAlivePlayers();

    // Check round end conditions
    if (alive.length <= 1 || this.drawPile.length === 0) {
      return this._endRound();
    }

    // Advance to next alive player
    let nextIdx = (this.playerIds.indexOf(this.currentPlayer) + 1) % this.playerCount;
    while (this.eliminated[this.playerIds[nextIdx]]) {
      nextIdx = (nextIdx + 1) % this.playerCount;
    }
    this.currentPlayer = this.playerIds[nextIdx];

    // Clear protection at start of their turn
    this.protected[this.currentPlayer] = false;

    // Draw a card
    this.hasDrawn = false;
    this._drawCard(this.currentPlayer);

    this.state = 'playing';
    return { success: true };
  }

  _endRound() {
    const alive = this._getAlivePlayers();
    let roundWinner = null;

    if (alive.length === 1) {
      roundWinner = alive[0];
    } else if (alive.length > 1) {
      // Compare hands: highest card wins; tie → highest discard pile sum wins
      let bestValue = -1;
      let bestDiscardSum = -1;
      let bestPlayer = null;
      for (const pid of alive) {
        const hand = this.hands[pid];
        if (hand.length > 0) {
          const info = getCardInfo(hand[0]);
          const value = info ? info.value : 0;
          const discardSum = this.discardPiles[pid].reduce((sum, cid) => {
            const ci = getCardInfo(cid);
            return sum + (ci ? ci.value : 0);
          }, 0);
          if (value > bestValue || (value === bestValue && discardSum > bestDiscardSum)) {
            bestValue = value;
            bestDiscardSum = discardSum;
            bestPlayer = pid;
          }
        }
      }
      roundWinner = bestPlayer;
    }

    if (roundWinner) {
      this.tokens[roundWinner]++;
      this.currentPlayer = roundWinner; // Winner leads next round
    }

    this.roundHistory.push({
      round: this.round,
      winner: roundWinner,
      winnerName: roundWinner ? this.playerNames[roundWinner] : null,
      // Final hands of alive players for display
      finalHands: alive.reduce((acc, pid) => {
        acc[pid] = this.hands[pid][0] || null;
        return acc;
      }, {}),
    });

    // Check for game winner
    const gameWinner = this.playerIds.find(pid => this.tokens[pid] >= this.targetTokens);
    if (gameWinner) {
      this.state = 'game_end';
    } else {
      this.state = 'round_end';
    }

    return { success: true };
  }

  getStateForPlayer(playerId) {
    const playerIdx = this.playerIds.indexOf(playerId);

    const players = [];
    for (let i = 0; i < this.playerCount; i++) {
      const pid = this.playerIds[(playerIdx + i) % this.playerCount];
      const isSelf = pid === playerId;
      players.push({
        id: pid,
        name: this.playerNames[pid] || pid,
        position: isSelf ? 'self' : `player_${i}`,
        cardCount: (this.hands[pid] || []).length,
        tokens: this.tokens[pid] || 0,
        eliminated: !!this.eliminated[pid],
        protected: !!this.protected[pid],
        discardPile: this.discardPiles[pid] || [],
      });
    }

    // Pending effect: filter sensitive info
    let pendingEffect = null;
    if (this.pendingEffect) {
      pendingEffect = {
        type: this.pendingEffect.type,
        playerId: this.pendingEffect.playerId,
        targetId: this.pendingEffect.targetId || null,
        needsTarget: !!this.pendingEffect.needsTarget,
        needsGuess: !!this.pendingEffect.needsGuess,
        validTargets: this.pendingEffect.validTargets || [],
        resolved: !!this.pendingEffect.resolved,
        guess: this.pendingEffect.guess || null,
      };

      // Show result only to involved players
      if (this.pendingEffect.resolved && this.pendingEffect.result) {
        const eff = this.pendingEffect;
        if (eff.playerId === playerId || eff.targetId === playerId) {
          pendingEffect.result = eff.result;
        } else {
          // Other players see limited info
          if (eff.type === 'guard') {
            pendingEffect.result = { correct: eff.result.correct };
          } else if (eff.type === 'baron') {
            pendingEffect.result = { loser: eff.result.loser };
          } else if (eff.type === 'prince') {
            pendingEffect.result = {
              discardedCard: eff.result.discardedCard,
              eliminated: eff.result.eliminated,
            };
          } else if (eff.type === 'king') {
            pendingEffect.result = { swapped: true };
          }
          // Spy: no result shown to others
        }
      }
    }

    return {
      gameType: 'love_letter',
      phase: this.state,
      round: this.round,
      players,
      myCards: this.hands[playerId] || [],
      currentPlayer: this.currentPlayer,
      isMyTurn: this.currentPlayer === playerId,
      drawPileCount: this.drawPile.length,
      faceUpCards: this.faceUpCards,
      pendingEffect,
      tokens: { ...this.tokens },
      targetTokens: this.targetTokens,
      roundHistory: this.roundHistory,
      guessableCards: [...GUESSABLE_TYPES],
    };
  }

  getStateForSpectator(permittedPlayerIds = new Set()) {
    const players = this.playerIds.map(pid => ({
      id: pid,
      name: this.playerNames[pid] || pid,
      cards: permittedPlayerIds.has(pid) ? (this.hands[pid] || []) : [],
      canViewCards: permittedPlayerIds.has(pid),
      cardCount: (this.hands[pid] || []).length,
      tokens: this.tokens[pid] || 0,
      eliminated: !!this.eliminated[pid],
      protected: !!this.protected[pid],
      discardPile: this.discardPiles[pid] || [],
    }));

    let pendingEffect = null;
    if (this.pendingEffect) {
      pendingEffect = {
        type: this.pendingEffect.type,
        playerId: this.pendingEffect.playerId,
        targetId: this.pendingEffect.targetId || null,
        needsTarget: !!this.pendingEffect.needsTarget,
        needsGuess: !!this.pendingEffect.needsGuess,
        validTargets: this.pendingEffect.validTargets || [],
        resolved: !!this.pendingEffect.resolved,
        guess: this.pendingEffect.guess || null,
      };
      if (this.pendingEffect.resolved && this.pendingEffect.result) {
        pendingEffect.result = this.pendingEffect.result;
      }
    }

    return {
      gameType: 'love_letter',
      phase: this.state,
      round: this.round,
      players,
      currentPlayer: this.currentPlayer,
      drawPileCount: this.drawPile.length,
      faceUpCards: this.faceUpCards,
      pendingEffect,
      tokens: { ...this.tokens },
      targetTokens: this.targetTokens,
      roundHistory: this.roundHistory,
      guessableCards: [...GUESSABLE_TYPES],
    };
  }

  getAutoTimeoutAction(playerId) {
    if (this.state === 'playing' && this.currentPlayer === playerId) {
      const hand = this.hands[playerId];
      if (!hand || hand.length === 0) return null;

      // Play the lowest-value card (but respect Countess rule)
      const sorted = sortCards(hand);
      const hasCountess = sorted.some(c => getCardInfo(c)?.type === CARD_TYPE.COUNTESS);
      const hasKingOrPrince = sorted.some(c => {
        const info = getCardInfo(c);
        return info && (info.type === CARD_TYPE.KING || info.type === CARD_TYPE.PRINCE);
      });
      if (hasCountess && hasKingOrPrince) {
        const countessCard = sorted.find(c => getCardInfo(c)?.type === CARD_TYPE.COUNTESS);
        return { type: 'play_card', cardId: countessCard };
      }
      return { type: 'play_card', cardId: sorted[0] };
    }

    if (this.state === 'effect_resolve' && this.pendingEffect) {
      const eff = this.pendingEffect;
      if (eff.playerId !== playerId) return null;

      if (eff.resolved) {
        return { type: 'effect_ack' };
      }

      if (eff.needsTarget || eff.needsGuess) {
        const target = eff.validTargets?.[0];
        if (eff.type === 'guard') {
          return {
            type: 'guard_guess',
            targetId: target,
            guess: GUESSABLE_TYPES[Math.floor(Math.random() * GUESSABLE_TYPES.length)],
          };
        }
        return { type: 'select_target', targetId: target };
      }
    }

    return null;
  }

  nextRound() {
    if (this.state === 'round_end') {
      this.startNextRound();
    }
  }

  updatePlayerId(oldPlayerId, newPlayerId) {
    const idx = this.playerIds.indexOf(oldPlayerId);
    if (idx === -1) return;

    this.playerIds[idx] = newPlayerId;
    this.playerNames[newPlayerId] = this.playerNames[oldPlayerId];
    delete this.playerNames[oldPlayerId];

    // Update hands
    if (this.hands[oldPlayerId] !== undefined) {
      this.hands[newPlayerId] = this.hands[oldPlayerId];
      delete this.hands[oldPlayerId];
    }

    // Update discard piles
    if (this.discardPiles[oldPlayerId] !== undefined) {
      this.discardPiles[newPlayerId] = this.discardPiles[oldPlayerId];
      delete this.discardPiles[oldPlayerId];
    }

    // Update eliminated / protected
    if (this.eliminated.hasOwnProperty(oldPlayerId)) {
      this.eliminated[newPlayerId] = this.eliminated[oldPlayerId];
      delete this.eliminated[oldPlayerId];
    }
    if (this.protected.hasOwnProperty(oldPlayerId)) {
      this.protected[newPlayerId] = this.protected[oldPlayerId];
      delete this.protected[oldPlayerId];
    }

    // Update tokens
    if (this.tokens.hasOwnProperty(oldPlayerId)) {
      this.tokens[newPlayerId] = this.tokens[oldPlayerId];
      delete this.tokens[oldPlayerId];
    }

    // Update current player
    if (this.currentPlayer === oldPlayerId) this.currentPlayer = newPlayerId;

    // Update pending effect
    if (this.pendingEffect) {
      if (this.pendingEffect.playerId === oldPlayerId) this.pendingEffect.playerId = newPlayerId;
      if (this.pendingEffect.targetId === oldPlayerId) this.pendingEffect.targetId = newPlayerId;
      if (this.pendingEffect.validTargets) {
        this.pendingEffect.validTargets = this.pendingEffect.validTargets.map(
          id => id === oldPlayerId ? newPlayerId : id
        );
      }
    }

    // Update round history
    for (const entry of this.roundHistory) {
      if (entry.winner === oldPlayerId) entry.winner = newPlayerId;
      if (entry.finalHands && entry.finalHands[oldPlayerId] !== undefined) {
        entry.finalHands[newPlayerId] = entry.finalHands[oldPlayerId];
        delete entry.finalHands[oldPlayerId];
      }
    }
  }

  getRankings() {
    const sorted = this.playerIds
      .map(pid => ({
        playerId: pid,
        nickname: this.playerNames[pid],
        score: this.tokens[pid],
      }))
      .sort((a, b) => b.score - a.score);

    let currentRank = 1;
    return sorted.map((entry, idx) => {
      if (idx > 0 && entry.score < sorted[idx - 1].score) {
        currentRank = idx + 1;
      }
      return { ...entry, rank: currentRank };
    });
  }
}

module.exports = LoveLetterGame;
