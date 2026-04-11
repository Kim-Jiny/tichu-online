/**
 * Skull King Game - State machine and rule engine
 *
 * States: waiting → dealing → bidding → playing → trick_end → round_end → game_end
 * 10 rounds, round N deals N cards
 * 2-6 players, individual play (no teams)
 */

const { createDeck, deal, getCardInfo, sortCards, CARD_TYPE, SK_EXPANSIONS } = require('./SkullKingDeck');
const { resolveTrick } = require('./SkullKingTrickResolver');
const { calculateRoundScore } = require('./SkullKingScoreCalc');

const TOTAL_ROUNDS = 10;
const LOOT_BONUS_POINTS = 20;

class SkullKingGame {
  constructor(playerIds, playerNames, options = {}) {
    this.playerIds = playerIds;
    this.playerNames = playerNames;
    this.playerCount = playerIds.length;
    this.gameType = 'skull_king';
    this.initialDealerIndex = 0;

    // Enabled expansions: subset of SK_EXPANSIONS ['kraken', 'white_whale', 'loot']
    const requested = Array.isArray(options.expansions) ? options.expansions : [];
    this.expansions = SK_EXPANSIONS.filter(x => requested.includes(x));

    this.state = 'waiting';
    this.round = 0;
    this.trickNumber = 0;

    // Per-round state
    this.hands = {};          // playerId -> [cardId]
    this.bids = {};           // playerId -> number | null
    this.tricks = {};         // playerId -> trick count won this round
    this.bonuses = {};        // playerId -> accumulated bonus this round
    this.currentTrick = [];   // [{playerId, cardId, tigressChoice?}]
    this.trickStarter = null; // playerId who leads the trick
    this.currentPlayer = null;

    // Scores
    this.totalScores = {};    // playerId -> total score
    this.scoreHistory = [];   // [{round, scores: {pid: {bid, tricks, bonus, roundScore}}}]
    this.lastRoundScores = {}; // playerId -> last round score

    // Init scores
    for (const pid of playerIds) {
      this.totalScores[pid] = 0;
    }

    // Trick end tracking
    this.lastTrickWinner = null;
    this.lastTrickBonus = 0;
    this.lastTrickBonusDetail = [];
    this.lastTrickVoided = false;
    this.nextPhaseAfterTrickEnd = null;

    this.resultSaved = false;
    this.deserted = false;
  }

  start() {
    this.round = 0;
    this.initialDealerIndex = Math.floor(Math.random() * this.playerCount);
    this.startNextRound();
  }

  startNextRound() {
    this.round++;
    this.trickNumber = 0;

    // Remember last trick winner from previous round for first trick lead
    const prevRoundWinner = this.lastTrickWinner;

    // Deal cards: round N → N cards per player
    const deck = createDeck(this.expansions);
    const hands = deal(deck, this.playerCount, this.round);

    this.hands = {};
    this.bids = {};
    this.tricks = {};
    this.bonuses = {};

    for (let i = 0; i < this.playerCount; i++) {
      const pid = this.playerIds[i];
      this.hands[pid] = sortCards(hands[i]).map(c => c.id);
      this.bids[pid] = null;
      this.tricks[pid] = 0;
      this.bonuses[pid] = 0;
    }

    this.currentTrick = [];
    this.trickStarter = null;
    this.lastTrickWinner = prevRoundWinner;
    this.lastTrickBonus = 0;
    this.lastTrickBonusDetail = [];
    this.lastTrickVoided = false;
    this.nextPhaseAfterTrickEnd = null;

    this.state = 'bidding';
  }

  handleAction(playerId, data) {
    switch (data.type) {
      case 'submit_bid':
        return this.handleSubmitBid(playerId, data.bid);
      case 'play_card':
        return this.handlePlayCard(playerId, data.cardId, data.tigressChoice);
      case 'next_round':
        return this.handleNextRound();
      default:
        return { success: false, message: `Unknown action: ${data.type}` };
    }
  }

  handleSubmitBid(playerId, bid) {
    if (this.state !== 'bidding') {
      return { success: false, message: '비딩 페이즈가 아닙니다' };
    }
    if (!this.playerIds.includes(playerId)) {
      return { success: false, message: '플레이어를 찾을 수 없습니다' };
    }
    if (this.bids[playerId] !== null) {
      return { success: false, message: '이미 비드를 제출했습니다' };
    }
    const bidNum = parseInt(bid);
    if (isNaN(bidNum) || bidNum < 0 || bidNum > this.round) {
      return { success: false, message: `비드는 0~${this.round} 사이여야 합니다` };
    }

    this.bids[playerId] = bidNum;

    // Check if all bids submitted
    const allBid = this.playerIds.every(pid => this.bids[pid] !== null);
    if (allBid) {
      this.startTrick();
    }

    return { success: true };
  }

  startTrick() {
    this.trickNumber++;
    this.currentTrick = [];
    this.nextPhaseAfterTrickEnd = null;
    // Clear stale trick-end fields so a new trick can't accidentally leak the
    // previous trick's void/bonus state if the UI ever stops gating by phase.
    this.lastTrickVoided = false;
    this.lastTrickBonus = 0;
    this.lastTrickBonusDetail = [];

    if (this.trickNumber === 1) {
      // Standard Skull King: dealer rotates each round and the player to the
      // dealer's left leads the first trick.
      const dealerIndex = (this.initialDealerIndex + this.round - 1) % this.playerCount;
      this.trickStarter = this.playerIds[(dealerIndex + 1) % this.playerCount];
    } else {
      // Subsequent tricks are led by the previous trick winner.
      this.trickStarter = this.lastTrickWinner || this.playerIds[0];
    }

    this.currentPlayer = this.trickStarter;
    this.state = 'playing';
  }

  handlePlayCard(playerId, cardId, tigressChoice) {
    if (this.state !== 'playing') {
      return { success: false, message: '플레이 페이즈가 아닙니다' };
    }
    if (playerId !== this.currentPlayer) {
      return { success: false, message: '당신의 차례가 아닙니다' };
    }

    // Validate card in hand
    const hand = this.hands[playerId];
    if (!hand || !hand.includes(cardId)) {
      return { success: false, message: '손에 없는 카드입니다' };
    }

    // Check suit following
    const legalCards = this.getLegalCards(playerId);
    if (!legalCards.includes(cardId)) {
      return { success: false, message: '수트 팔로잉 규칙을 위반했습니다' };
    }

    // Validate tigress choice
    const cardInfo = getCardInfo(cardId);
    if (!cardInfo) {
      return { success: false, message: '유효하지 않은 카드입니다' };
    }
    if (cardInfo.type === CARD_TYPE.TIGRESS) {
      if (!tigressChoice || (tigressChoice !== 'pirate' && tigressChoice !== 'escape')) {
        return { success: false, message: 'Tigress 선택이 필요합니다 (pirate/escape)' };
      }
    }

    // Play the card
    this.hands[playerId] = hand.filter(c => c !== cardId);
    this.currentTrick.push({
      playerId,
      cardId,
      tigressChoice: cardInfo.type === CARD_TYPE.TIGRESS ? tigressChoice : undefined,
    });

    // Check if trick is complete
    if (this.currentTrick.length === this.playerCount) {
      return this.completeTrick();
    }

    // Advance to next player
    this.currentPlayer = this.getNextPlayer(playerId);
    return { success: true };
  }

  completeTrick() {
    const result = resolveTrick(this.currentTrick);

    // winnerId is always set — even on voided tricks (Kraken / Whale with no
    // numbers) it represents who leads the next trick. For voided tricks we
    // must NOT increment the trick count or award bonuses.
    const voided = !!result.voided;

    this.lastTrickWinner = result.winnerId;
    this.lastTrickBonus = voided ? 0 : result.bonus;
    this.lastTrickBonusDetail = [...(result.bonusDetail || [])];
    this.lastTrickVoided = voided;

    if (!voided) {
      this.tricks[result.winnerId]++;
      this.bonuses[result.winnerId] += result.bonus;

      // Loot bonus: +20 per Loot card in the trick to the trick winner, plus
      // +20 to each player who played a Loot card. Both subject to bid-met
      // rule at round end (handled by SkullKingScoreCalc via this.bonuses).
      const lootPlayers = [];
      for (const play of this.currentTrick) {
        const info = getCardInfo(play.cardId);
        if (info && info.type === CARD_TYPE.LOOT) {
          lootPlayers.push(play.playerId);
        }
      }
      if (lootPlayers.length > 0) {
        const winnerLoot = LOOT_BONUS_POINTS * lootPlayers.length;
        this.bonuses[result.winnerId] += winnerLoot;
        for (const lootPid of lootPlayers) {
          this.bonuses[lootPid] += LOOT_BONUS_POINTS;
        }
        this.lastTrickBonus += winnerLoot;
        this.lastTrickBonusDetail.push({
          type: 'loot_bonus',
          count: lootPlayers.length,
          winnerPoints: winnerLoot,
          playerPoints: LOOT_BONUS_POINTS,
        });
      }
    }

    this.state = 'trick_end';

    const cardsRemaining = Object.values(this.hands).some(h => h.length > 0);
    this.nextPhaseAfterTrickEnd = cardsRemaining ? 'playing' : 'round_end';
    return { success: true };
  }

  advanceAfterTrickEnd() {
    if (this.state !== 'trick_end') return;

    if (this.nextPhaseAfterTrickEnd === 'round_end') {
      this.endRound();
      return;
    }

    this.startTrick();
  }

  endRound() {
    // Calculate scores
    const roundScoreData = {};
    for (const pid of this.playerIds) {
      const bid = this.bids[pid];
      const tricksWon = this.tricks[pid];
      const bonus = this.bonuses[pid];
      const roundScore = calculateRoundScore(bid, tricksWon, this.round, bonus);

      this.totalScores[pid] += roundScore;
      this.lastRoundScores[pid] = roundScore;

      // Only show bonus when bid was met (bonus is only applied on success)
      const bidSuccess = (bid === 0) ? (tricksWon === 0) : (tricksWon === bid);
      roundScoreData[pid] = {
        bid,
        tricks: tricksWon,
        bonus: bidSuccess ? bonus : 0,
        roundScore,
        totalScore: this.totalScores[pid],
      };
    }

    this.scoreHistory.push({
      round: this.round,
      scores: roundScoreData,
    });

    if (this.round >= TOTAL_ROUNDS) {
      this.state = 'game_end';
    } else {
      this.state = 'round_end';
    }
  }

  handleNextRound() {
    if (this.state !== 'round_end') {
      return { success: false, message: '라운드 종료 상태가 아닙니다' };
    }
    this.startNextRound();
    return { success: true };
  }

  nextRound() {
    if (this.state === 'round_end') {
      this.startNextRound();
    }
  }

  getLegalCards(playerId) {
    const hand = this.hands[playerId];
    if (!hand || hand.length === 0) return [];

    // If leading or no number cards played yet, all cards are legal
    if (this.currentTrick.length === 0) return [...hand];

    // Determine lead suit (first numbered card in trick)
    let leadSuit = null;
    for (const play of this.currentTrick) {
      const info = getCardInfo(play.cardId);
      let effectiveType = info.type;
      if (info.type === CARD_TYPE.TIGRESS) {
        effectiveType = play.tigressChoice === 'pirate' ? CARD_TYPE.PIRATE : CARD_TYPE.ESCAPE;
      }
      if (effectiveType === CARD_TYPE.NUMBER) {
        leadSuit = info.suit;
        break;
      }
    }

    // If no lead suit determined (all special cards so far), any card is legal
    if (!leadSuit) return [...hand];

    // Must follow lead suit if possible (special cards are always legal)
    const handInfos = hand.map(cardId => ({ cardId, info: getCardInfo(cardId) }));
    const hasLeadSuit = handInfos.some(h =>
      h.info.type === CARD_TYPE.NUMBER && h.info.suit === leadSuit
    );

    if (!hasLeadSuit) return [...hand]; // No lead-suit cards, play anything

    // Must play lead suit number cards OR special cards
    return handInfos
      .filter(h =>
        h.info.type !== CARD_TYPE.NUMBER || h.info.suit === leadSuit
      )
      .map(h => h.cardId);
  }

  getNextPlayer(currentPlayerId) {
    const idx = this.playerIds.indexOf(currentPlayerId);
    return this.playerIds[(idx + 1) % this.playerCount];
  }

  getStateForPlayer(playerId) {
    const playerIdx = this.playerIds.indexOf(playerId);

    // Build players array (relative positioning)
    const players = [];
    for (let i = 0; i < this.playerCount; i++) {
      const pid = this.playerIds[(playerIdx + i) % this.playerCount];
      const isSelf = pid === playerId;
      // During bidding, hide other players' bid values until all bids are in
      const isBidding = this.state === 'bidding';
      const bidValue = isSelf || !isBidding ? this.bids[pid] : null;
      const hasBid = this.bids[pid] !== null;
      players.push({
        id: pid,
        name: this.playerNames[pid] || pid,
        position: isSelf ? 'self' : `player_${i}`,
        cardCount: (this.hands[pid] || []).length,
        bid: bidValue,
        tricks: this.tricks[pid] || 0,
        totalScore: this.totalScores[pid] || 0,
        hasBid,
      });
    }

    // Build current trick with player names
    const currentTrick = this.currentTrick.map(play => ({
      playerId: play.playerId,
      playerName: this.playerNames[play.playerId] || play.playerId,
      cardId: play.cardId,
      tigressChoice: play.tigressChoice,
    }));

    // Legal cards for current player
    const legalCards = this.currentPlayer === playerId
      ? this.getLegalCards(playerId)
      : [];

    return {
      gameType: 'skull_king',
      phase: this.state,
      round: this.round,
      totalRounds: TOTAL_ROUNDS,
      trickNumber: this.trickNumber,
      players,
      myCards: this.hands[playerId] || [],
      currentPlayer: this.currentPlayer,
      isMyTurn: this.currentPlayer === playerId,
      currentTrick,
      legalCards,
      totalScores: { ...this.totalScores },
      lastRoundScores: { ...this.lastRoundScores },
      scoreHistory: this.scoreHistory,
      lastTrickWinner: this.lastTrickWinner,
      lastTrickBonus: this.lastTrickBonus,
      lastTrickBonusDetail: this.lastTrickBonusDetail,
      lastTrickVoided: this.lastTrickVoided,
      trickStarter: this.trickStarter,
      roundStarter: this._getRoundStarter(),
      expansions: [...this.expansions],
    };
  }

  getStateForSpectator(permittedPlayerIds = new Set()) {
    const players = this.playerIds.map(pid => ({
      id: pid,
      name: this.playerNames[pid] || pid,
      cards: permittedPlayerIds.has(pid) ? (this.hands[pid] || []) : [],
      canViewCards: permittedPlayerIds.has(pid),
      cardCount: (this.hands[pid] || []).length,
      bid: this.bids[pid],
      tricks: this.tricks[pid] || 0,
      totalScore: this.totalScores[pid] || 0,
      hasBid: this.bids[pid] !== null,
    }));

    const currentTrick = this.currentTrick.map(play => ({
      playerId: play.playerId,
      playerName: this.playerNames[play.playerId] || play.playerId,
      cardId: play.cardId,
      tigressChoice: play.tigressChoice,
    }));

    return {
      gameType: 'skull_king',
      phase: this.state,
      round: this.round,
      totalRounds: TOTAL_ROUNDS,
      trickNumber: this.trickNumber,
      players,
      currentPlayer: this.currentPlayer,
      currentTrick,
      totalScores: { ...this.totalScores },
      lastRoundScores: { ...this.lastRoundScores },
      scoreHistory: this.scoreHistory,
      lastTrickWinner: this.lastTrickWinner,
      lastTrickBonus: this.lastTrickBonus,
      lastTrickBonusDetail: this.lastTrickBonusDetail,
      lastTrickVoided: this.lastTrickVoided,
      trickStarter: this.trickStarter,
      roundStarter: this._getRoundStarter(),
      expansions: [...this.expansions],
    };
  }

  _getRoundStarter() {
    const dealerIndex = (this.initialDealerIndex + this.round - 1) % this.playerCount;
    return this.playerIds[(dealerIndex + 1) % this.playerCount];
  }

  getAutoTimeoutAction(playerId) {
    if (this.state === 'bidding' && this.bids[playerId] === null) {
      return { type: 'submit_bid', bid: 0 };
    }
    if (this.state === 'playing' && this.currentPlayer === playerId) {
      const legalCards = this.getLegalCards(playerId);
      if (legalCards.length > 0) {
        const cardId = legalCards[Math.floor(Math.random() * legalCards.length)];
        const info = getCardInfo(cardId);
        if (info.type === CARD_TYPE.TIGRESS) {
          const tigressChoice = Math.random() < 0.5 ? 'pirate' : 'escape';
          return { type: 'play_card', cardId, tigressChoice };
        }
        return { type: 'play_card', cardId };
      }
    }
    return null;
  }

  updatePlayerId(oldPlayerId, newPlayerId) {
    const idx = this.playerIds.indexOf(oldPlayerId);
    if (idx === -1) return;

    this.playerIds[idx] = newPlayerId;
    this.playerNames[newPlayerId] = this.playerNames[oldPlayerId];
    delete this.playerNames[oldPlayerId];

    // Update hands
    if (this.hands[oldPlayerId]) {
      this.hands[newPlayerId] = this.hands[oldPlayerId];
      delete this.hands[oldPlayerId];
    }

    // Update bids
    if (this.bids.hasOwnProperty(oldPlayerId)) {
      this.bids[newPlayerId] = this.bids[oldPlayerId];
      delete this.bids[oldPlayerId];
    }

    // Update tricks
    if (this.tricks.hasOwnProperty(oldPlayerId)) {
      this.tricks[newPlayerId] = this.tricks[oldPlayerId];
      delete this.tricks[oldPlayerId];
    }

    // Update bonuses
    if (this.bonuses.hasOwnProperty(oldPlayerId)) {
      this.bonuses[newPlayerId] = this.bonuses[oldPlayerId];
      delete this.bonuses[oldPlayerId];
    }

    // Update scores
    if (this.totalScores.hasOwnProperty(oldPlayerId)) {
      this.totalScores[newPlayerId] = this.totalScores[oldPlayerId];
      delete this.totalScores[oldPlayerId];
    }
    if (this.lastRoundScores.hasOwnProperty(oldPlayerId)) {
      this.lastRoundScores[newPlayerId] = this.lastRoundScores[oldPlayerId];
      delete this.lastRoundScores[oldPlayerId];
    }

    // Update current trick
    for (const play of this.currentTrick) {
      if (play.playerId === oldPlayerId) play.playerId = newPlayerId;
    }

    // Update current player / trick starter / last trick winner
    if (this.currentPlayer === oldPlayerId) this.currentPlayer = newPlayerId;
    if (this.trickStarter === oldPlayerId) this.trickStarter = newPlayerId;
    if (this.lastTrickWinner === oldPlayerId) this.lastTrickWinner = newPlayerId;

    // Update scoreHistory
    for (const entry of this.scoreHistory) {
      if (entry.scores && entry.scores[oldPlayerId] !== undefined) {
        entry.scores[newPlayerId] = entry.scores[oldPlayerId];
        delete entry.scores[oldPlayerId];
      }
    }
  }

  /**
   * Get final rankings (for game_end)
   * Returns array sorted by totalScore descending
   */
  getRankings() {
    const sorted = this.playerIds
      .map(pid => ({
        playerId: pid,
        nickname: this.playerNames[pid],
        score: this.totalScores[pid],
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

module.exports = SkullKingGame;
