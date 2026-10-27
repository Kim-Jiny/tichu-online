/**
 * Skull King Game - State machine and rule engine
 *
 * States: waiting → dealing → bidding → playing → trick_end → round_end → game_end
 * 10 rounds, round N deals N cards
 * 2-6 players, individual play (no teams)
 */

const { createDeck, dealWithRest, getCardInfo, sortCards, pirateNameOf, CARD_TYPE, SK_EXPANSIONS } = require('./SkullKingDeck');
const { resolveTrick } = require('./SkullKingTrickResolver');
const { calculateRoundScore } = require('./SkullKingScoreCalc');
const { mapKeys } = require('../historyIds');

const TOTAL_ROUNDS = 10;
const LOOT_BONUS_POINTS = 20;
const RASCAL_WAGERS = [0, 10, 20];
const BENDT_DRAW = 2;

const SERIALIZED_FIELDS = [
  'playerIds', 'playerNames', 'playerCount', 'gameType', 'initialDealerIndex', 'expansions',
  'state', 'round', 'trickNumber', 'hands', 'bids', 'tricks', 'bonuses', 'lootAlliances',
  'currentTrick', 'roundPlays', 'trickStarter', 'currentPlayer', 'totalScores', 'lastRoundScores',
  'lastTrickWinner', 'nextPhaseAfterTrickEnd', 'pendingAbility', 'nextLeaderOverride',
  'rascalWagers', 'undealt',
];

class SkullKingGame {
  constructor(playerIds, playerNames, options = {}) {
    this.playerIds = playerIds;
    this.playerNames = playerNames;
    this.playerCount = playerIds.length;
    this.gameType = 'skull_king';
    this.initialDealerIndex = 0;

    // Enabled expansions: subset of SK_EXPANSIONS ['kraken', 'white_whale', 'loot', 'pirate_abilities']
    const requested = Array.isArray(options.expansions) ? options.expansions : [];
    this.expansions = SK_EXPANSIONS.filter(x => requested.includes(x));

    // 해적 능력 모드. 해적 5장은 모드와 상관없이 덱에 있고, 켰을 때만 트릭을 이긴 사람이 능력을 쓴다.
    this.pendingAbility = null;   // { playerId, pirate, cardId, started, drawn? } — 쓰는 중인 능력
    this.nextLeaderOverride = null; // Rosie 가 지목한 다음 트릭 선
    this.rascalWagers = {};       // playerId -> 0|10|20 (이번 라운드 Rascal 내기)
    this.undealt = [];            // 이번 라운드에 안 나눠 준 카드(Bendt 가 뽑고 Juanita 가 본다)
    this.lastAbility = null;      // 방금 쓴 능력 — 모두에게 보여 줄 알림용(공개 정보만)
    this.abilitySeq = 0;          // lastAbility 가 바뀔 때마다 +1 (앱이 알림을 한 번만 띄우는 용도)

    this.state = 'waiting';
    this.round = 0;
    this.trickNumber = 0;

    // Per-round state
    this.hands = {};          // playerId -> [cardId]
    this.bids = {};           // playerId -> number | null
    this.tricks = {};         // playerId -> trick count won this round
    this.bonuses = {};        // playerId -> accumulated bonus this round
    this.lootAlliances = [];  // [{winnerId, looterId}] — settled at round end
    this.currentTrick = [];   // [{playerId, cardId, tigressChoice?}]
    // 이번 라운드에 나온 카드 전부(시간순). 봇이 남은 카드를 세고 누가 무늬가 없는지 추리하는 데 쓴다.
    // 화면으로 나가는 상태(getStateForPlayer 등)에는 넣지 않는다.
    this.roundPlays = [];
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

    // 미션 판정용 이벤트 — { playerId, event, amount }. 서버가 액션 뒤에 꺼내 간다.
    this.missionEvents = [];

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
    const { hands, rest } = dealWithRest(deck, this.playerCount, this.round);
    this.undealt = rest.map(c => c.id);
    this.pendingAbility = null;
    this.nextLeaderOverride = null;
    this.rascalWagers = {};

    this.hands = {};
    this.bids = {};
    this.tricks = {};
    this.bonuses = {};
    this.lootAlliances = [];
    this.roundPlays = [];

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

  // The player the bot scheduler / stuck-bot watchdog should act on. Bidding is
  // SIMULTANEOUS, and currentPlayer during bidding is stale (often a player who
  // already bid) — without this the watchdog would mis-read a stale-currentPlayer
  // bot as "stranded" while the table merely waits for a slow HUMAN bidder, and
  // fire false recoveries. Surface a real non-bidder instead: a bot → the
  // watchdog recovers it; a human → the watchdog's own isBot check stands down.
  getPendingActor() {
    if (this.state === 'pirate_ability' && this.pendingAbility) {
      return this.pendingAbility.playerId;
    }
    if (this.state === 'bidding') {
      for (const pid of this.playerIds) {
        if (this.bids[pid] === null) return pid;
      }
      return null; // all bids in (transient) — nothing pending
    }
    return this.currentPlayer || null;
  }

  handleAction(playerId, data) {
    switch (data.type) {
      case 'submit_bid':
        return this.handleSubmitBid(playerId, data.bid);
      case 'play_card':
        return this.handlePlayCard(playerId, data.cardId, data.tigressChoice);
      case 'use_pirate_ability':
        return this.handleUsePirateAbility(playerId, data);
      case 'next_round':
        return this.handleNextRound();
      default:
        return { success: false, messageKey: 'game_unknown_action', messageParams: { type: data.type } };
    }
  }

  handleSubmitBid(playerId, bid) {
    if (this.state !== 'bidding') {
      return { success: false, messageKey: 'sk_not_bidding_phase' };
    }
    if (!this.playerIds.includes(playerId)) {
      return { success: false, messageKey: 'player_not_found' };
    }
    if (this.bids[playerId] !== null) {
      return { success: false, messageKey: 'sk_bid_already_submitted' };
    }
    const bidNum = parseInt(bid);
    if (isNaN(bidNum) || bidNum < 0 || bidNum > this.round) {
      return { success: false, messageKey: 'sk_bid_range', messageParams: { max: this.round } };
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
      // Subsequent tricks are led by the previous trick winner — unless Rosie
      // handed the lead to someone else.
      this.trickStarter = this.nextLeaderOverride || this.lastTrickWinner || this.playerIds[0];
    }
    this.nextLeaderOverride = null;

    this.currentPlayer = this.trickStarter;
    this.state = 'playing';
  }

  handlePlayCard(playerId, cardId, tigressChoice) {
    if (this.state !== 'playing') {
      return { success: false, messageKey: 'sk_not_play_phase' };
    }
    if (playerId !== this.currentPlayer) {
      return { success: false, messageKey: 'sk_not_your_turn' };
    }

    // Validate card in hand
    const hand = this.hands[playerId];
    if (!hand || !hand.includes(cardId)) {
      return { success: false, messageKey: 'sk_card_not_in_hand' };
    }

    // Check suit following
    const legalCards = this.getLegalCards(playerId);
    if (!legalCards.includes(cardId)) {
      return { success: false, messageKey: 'sk_suit_follow_violated' };
    }

    // Validate tigress choice
    const cardInfo = getCardInfo(cardId);
    if (!cardInfo) {
      return { success: false, messageKey: 'sk_invalid_card' };
    }
    if (cardInfo.type === CARD_TYPE.TIGRESS) {
      if (!tigressChoice || (tigressChoice !== 'pirate' && tigressChoice !== 'escape')) {
        return { success: false, messageKey: 'sk_tigress_choice_required' };
      }
    }

    // Play the card
    this.hands[playerId] = hand.filter(c => c !== cardId);
    const play = {
      playerId,
      cardId,
      tigressChoice: cardInfo.type === CARD_TYPE.TIGRESS ? tigressChoice : undefined,
    };
    this.currentTrick.push(play);
    this.roundPlays.push({ ...play });

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
      this._collectTrickMissionEvents(result);

      // Loot: the player who played it and the trick winner form an alliance.
      // Each gets +20 per Loot card, but only if BOTH made their bid exactly —
      // so nothing is added to this.bonuses here; endRound settles alliances.
      const lootPlayers = [];
      for (const play of this.currentTrick) {
        const info = getCardInfo(play.cardId);
        if (info && info.type === CARD_TYPE.LOOT) {
          lootPlayers.push(play.playerId);
        }
      }
      if (lootPlayers.length > 0) {
        const winnerLoot = LOOT_BONUS_POINTS * lootPlayers.length;
        for (const lootPid of lootPlayers) {
          this.lootAlliances.push({ winnerId: result.winnerId, looterId: lootPid });
        }
        // lastTrickBonus 에는 더하지 않는다.
        //
        // 이 값은 "이 트릭으로 지금 받은 점수"로 화면에 나가지만, 루트는
        // 라운드가 끝날 때 동맹 양쪽이 모두 공약을 맞혀야 지급된다
        // (endRound 의 _bidMet 검사). 더해 두면 자주 못 받는 +20/+40 을
        // 받은 것처럼 광고하고, 라운드 끝에 그 차이를 설명하는 것도 없다.
        //
        // 대신 detail 에 pending 으로 남겨, 화면이 "조건이 맞으면 받는다"로
        // 그릴 수 있게 한다.
        this.lastTrickBonusDetail.push({
          type: 'loot_bonus',
          count: lootPlayers.length,
          winnerPoints: winnerLoot,
          playerPoints: LOOT_BONUS_POINTS,
          // 아직 확정되지 않았다는 표시. 옛 앱은 이 키를 모르고 지나간다.
          pending: true,
        });
      }
    }

    this.state = 'trick_end';

    const cardsRemaining = Object.values(this.hands).some(h => h.length > 0);
    this.nextPhaseAfterTrickEnd = cardsRemaining ? 'playing' : 'round_end';
    this.pendingAbility = voided ? null : this._abilityForWinner(result.winnerId, cardsRemaining);
    return { success: true };
  }

  /**
   * 트릭을 이긴 카드가 이름 있는 해적(Tigress 로 낸 해적은 아님)이면 그 능력을 쓸 권리가 생긴다.
   * 마지막 트릭 뒤에는 Harry 만 의미가 있다(나머지는 쓸 곳이 없다). 쓸 곳이 없으면 아예 건너뛴다.
   */
  _abilityForWinner(winnerId, cardsRemaining) {
    if (!this.expansions.includes('pirate_abilities')) return null;
    const play = this.currentTrick.find(p => p.playerId === winnerId);
    const pirate = play ? pirateNameOf(play.cardId) : null;
    if (!pirate) return null;
    if (!cardsRemaining && pirate !== 'harry') return null;
    if (pirate === 'bendt' && (this.undealt.length === 0 || (this.hands[winnerId] || []).length === 0)) return null;
    if (pirate === 'juanita' && this.undealt.length === 0) return null;
    return { playerId: winnerId, pirate, cardId: play.cardId, started: false };
  }

  _beginAbility() {
    const ab = this.pendingAbility;
    ab.started = true;
    this.state = 'pirate_ability';
    this.currentPlayer = ab.playerId;
    if (ab.pirate === 'bendt') {
      // 더미에서 2장을 손에 넣고, 이어서 아무 2장이나 버린다(방금 뽑은 것도 가능).
      const n = Math.min(BENDT_DRAW, this.undealt.length);
      ab.drawn = this.undealt.splice(0, n);
      this.hands[ab.playerId] = sortCards([...this.hands[ab.playerId], ...ab.drawn]);
    }
  }

  handleUsePirateAbility(playerId, data) {
    const ab = this.pendingAbility;
    if (this.state !== 'pirate_ability' || !ab) {
      return { success: false, messageKey: 'sk_ability_not_pending' };
    }
    if (playerId !== ab.playerId) {
      return { success: false, messageKey: 'sk_not_your_turn' };
    }
    const bad = { success: false, messageKey: 'sk_ability_invalid' };
    const info = { playerId, pirate: ab.pirate };

    switch (ab.pirate) {
      case 'rosie': {
        if (!this.playerIds.includes(data.leaderId)) return bad;
        this.nextLeaderOverride = data.leaderId;
        info.targetId = data.leaderId;
        break;
      }
      case 'bendt': {
        const discard = Array.isArray(data.discard) ? data.discard : [];
        const need = (ab.drawn || []).length;
        const hand = this.hands[playerId] || [];
        if (discard.length !== need || new Set(discard).size !== need) return bad;
        if (!discard.every(id => hand.includes(id))) return bad;
        this.hands[playerId] = hand.filter(id => !discard.includes(id));
        info.count = need;
        break;
      }
      case 'rascal': {
        const wager = Number(data.wager);
        if (!RASCAL_WAGERS.includes(wager)) return bad;
        this.rascalWagers[playerId] = wager;
        info.wager = wager;
        break;
      }
      case 'juanita':
        break; // 보기만 한다 — 확인하면 끝
      case 'harry': {
        const delta = Number(data.delta);
        if (![-1, 0, 1].includes(delta)) return bad;
        const next = this.bids[playerId] + delta;
        if (next < 0 || next > this.round) return bad;
        this.bids[playerId] = next;
        info.delta = delta;
        info.bid = next;
        break;
      }
      default:
        return bad;
    }

    this.pendingAbility = null;
    this.lastAbility = info;
    this.abilitySeq++;
    this._continueAfterTrick();
    return { success: true };
  }

  /** 능력을 쓰지 못하는 상황(타임아웃·탈락)에서 기본 선택. */
  _defaultAbilityAction() {
    const ab = this.pendingAbility;
    if (!ab) return null;
    switch (ab.pirate) {
      case 'rosie': return { type: 'use_pirate_ability', leaderId: ab.playerId };
      case 'bendt': return { type: 'use_pirate_ability', discard: [...(ab.drawn || [])] };
      case 'rascal': return { type: 'use_pirate_ability', wager: 0 };
      case 'harry': return { type: 'use_pirate_ability', delta: 0 };
      default: return { type: 'use_pirate_ability' };
    }
  }

  /** 트릭 결과에서 나오는 미션 이벤트: 스컬킹이 해적 둘 이상, 인어가 스컬킹, 숫자 10 으로 승리. */
  _collectTrickMissionEvents(result) {
    const winner = result.winnerId;
    for (const d of result.bonusDetail || []) {
      if (d.type === 'sk_captures_pirates' && d.count >= 2) {
        this._pushMissionEvent({ playerId: winner, event: 'sk.skullking_two_pirates', amount: 1 });
      }
      if (d.type === 'mermaid_captures_sk') {
        this._pushMissionEvent({ playerId: winner, event: 'sk.mermaid_takes_skullking', amount: 1 });
      }
    }
    const winPlay = this.currentTrick.find((p) => p.playerId === winner);
    const info = winPlay ? getCardInfo(winPlay.cardId) : null;
    if (info && info.type === CARD_TYPE.NUMBER && info.value === 10) {
      this._pushMissionEvent({ playerId: winner, event: 'sk.win_with_ten', amount: 1 });
    }
    // 어떤 카드로 이겼는지(미션): 해적(호랑이를 해적으로 낸 것 포함)·인어·스컬킹.
    if (info) {
      const asPirate = info.type === CARD_TYPE.PIRATE
        || (info.type === CARD_TYPE.TIGRESS && winPlay.tigressChoice === 'pirate');
      if (asPirate) this._pushMissionEvent({ playerId: winner, event: 'sk.pirate_win', amount: 1 });
      else if (info.type === CARD_TYPE.MERMAID) this._pushMissionEvent({ playerId: winner, event: 'sk.mermaid_win', amount: 1 });
      else if (info.type === CARD_TYPE.SKULL_KING) this._pushMissionEvent({ playerId: winner, event: 'sk.skullking_win', amount: 1 });
    }
  }

  // 직렬화로 복원된 게임에는 생성자가 안 돌아 missionEvents 가 없다.
  _pushMissionEvent(e) {
    if (!this.missionEvents) this.missionEvents = [];
    this.missionEvents.push(e);
  }

  drainMissionEvents() {
    const out = this.missionEvents || [];
    this.missionEvents = [];
    return out;
  }

  advanceAfterTrickEnd() {
    if (this.state !== 'trick_end') return;

    // 이긴 해적의 능력이 남아 있으면 먼저 쓰게 한다.
    if (this.pendingAbility && !this.pendingAbility.started) {
      this._beginAbility();
      return;
    }
    this._continueAfterTrick();
  }

  _continueAfterTrick() {
    if (this.nextPhaseAfterTrickEnd === 'round_end') {
      this.endRound();
      return;
    }
    this.startTrick();
  }

  _bidMet(pid) {
    const bid = this.bids[pid];
    return bid === 0 ? this.tricks[pid] === 0 : this.tricks[pid] === bid;
  }

  endRound() {
    // Settle Loot alliances: each member gets +20 only when both met their bid.
    // (Winner who played their own Loot is an alliance of one: +20 once.)
    const lootBonus = {};
    for (const pid of this.playerIds) lootBonus[pid] = 0;
    for (const { winnerId, looterId } of this.lootAlliances || []) {
      if (!this._bidMet(winnerId) || !this._bidMet(looterId)) continue;
      lootBonus[winnerId] += LOOT_BONUS_POINTS;
      if (looterId !== winnerId) lootBonus[looterId] += LOOT_BONUS_POINTS;
    }

    // Calculate scores
    const roundScoreData = {};
    for (const pid of this.playerIds) {
      const bid = this.bids[pid];
      const tricksWon = this.tricks[pid];
      const bonus = this.bonuses[pid] + lootBonus[pid];
      let roundScore = calculateRoundScore(bid, tricksWon, this.round, bonus);
      // Rascal 의 내기: 입찰을 맞히면 걸어 둔 점수를 더 받고, 못 맞히면 그만큼 잃는다.
      const wager = (this.rascalWagers || {})[pid] || 0;
      if (wager) roundScore += this._bidMet(pid) ? wager : -wager;

      this.totalScores[pid] += roundScore;
      this.lastRoundScores[pid] = roundScore;

      // Only show bonus when bid was met (bonus is only applied on success)
      const bidSuccess = (bid === 0) ? (tricksWon === 0) : (tricksWon === bid);
      if (bidSuccess) {
        this._pushMissionEvent({ playerId: pid, event: 'sk.bid_hit', amount: 1 });
        if (bid === 0) this._pushMissionEvent({ playerId: pid, event: 'sk.zero_hit', amount: 1 });
      }
      roundScoreData[pid] = {
        bid,
        tricks: tricksWon,
        bonus: bidSuccess ? bonus : 0,
        wager,
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
      return { success: false, messageKey: 'sk_not_round_end' };
    }
    this.startNextRound();
    return { success: true };
  }

  nextRound() {
    if (this.state === 'round_end') {
      this.startNextRound();
    }
  }

  // ─── MATCH MIGRATION (blue/green drain) ─────────────────
  // See TichuGame.getMatchProgress. Nickname-keyed so the payload
  // survives the playerId remap a reconnect performs on the peer.

  getMatchProgress() {
    const toNickname = (pid) => this.playerNames[pid];
    const totals = {};
    for (const pid of this.playerIds) {
      totals[this.playerNames[pid]] = this.totalScores[pid] || 0;
    }
    return {
      round: this.round,
      seatOrder: this.playerIds.map((id) => this.playerNames[id]),
      totals,
      // Per-round breakdown for the scoreboard. `scores` is the only
      // id-bearing field — same set updatePlayerId rewrites.
      history: this.scoreHistory.map((entry) => ({
        ...entry,
        scores: mapKeys(entry.scores, toNickname),
      })),
      // Dealer rotates off this across the whole match (see startNextRound),
      // so re-rolling it on the peer would make the dealer jump mid-match.
      // Safe as a bare index because the seating is restored verbatim.
      initialDealerIndex: this.initialDealerIndex,
    };
  }

  // Unlike the other games SK deals exactly `round` cards, so the round
  // counter has to be seeded BEFORE the deal — hence startNextRound()
  // here instead of start(), which would reset it to 0 and deal round 1.
  resumeMatch(progress) {
    if (!progress) {
      this.start();
      return;
    }
    this.round = progress.round || 0;
    this.initialDealerIndex = Number.isInteger(progress.initialDealerIndex)
      ? progress.initialDealerIndex % this.playerCount
      : Math.floor(Math.random() * this.playerCount);
    const byNickname = {};
    for (const pid of this.playerIds) byNickname[this.playerNames[pid]] = pid;
    for (const [nickname, score] of Object.entries(progress.totals || {})) {
      const pid = byNickname[nickname];
      if (pid !== undefined) this.totalScores[pid] = score;
    }
    const toId = (nickname) => byNickname[nickname];
    this.scoreHistory = Array.isArray(progress.history)
      ? progress.history.map((entry) => ({
        ...entry,
        scores: mapKeys(entry.scores, toId),
      }))
      : [];
    this.startNextRound();
  }

  /**
   * Lead suit of the current trick. Escape / Loot / Tigress-as-escape are
   * transparent: the next number card sets the suit. Any other special
   * (Pirate, Mermaid, Skull King, Kraken, White Whale, Tigress-as-pirate)
   * played before a number means there is NO lead suit, and numbers played
   * after it do not create one.
   */
  getLeadSuit() {
    for (const play of this.currentTrick) {
      const info = getCardInfo(play.cardId);
      let type = info.type;
      if (type === CARD_TYPE.TIGRESS) {
        type = play.tigressChoice === 'pirate' ? CARD_TYPE.PIRATE : CARD_TYPE.ESCAPE;
      }
      if (type === CARD_TYPE.ESCAPE || type === CARD_TYPE.LOOT) continue;
      return type === CARD_TYPE.NUMBER ? info.suit : null;
    }
    return null;
  }

  getLegalCards(playerId) {
    const hand = this.hands[playerId];
    if (!hand || hand.length === 0) return [];

    // If leading or no number cards played yet, all cards are legal
    if (this.currentTrick.length === 0) return [...hand];

    const leadSuit = this.getLeadSuit();

    // No lead suit (only escapes so far, or a pirate/mermaid/SK/Kraken/Whale
    // came first) — any card is legal
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

  /** JSON-safe snapshot for worker-thread bot offload. Everything a bot decision
   *  reads: the table, the round so far (roundPlays) and the pirate-ability state.
   *  Score history and mission events are left out — no bot looks at them. When a
   *  new field starts to matter to a bot, add it here (test_serialize_roundtrip). */
  serialize() {
    const snap = {};
    for (const k of SERIALIZED_FIELDS) snap[k] = this[k];
    return snap;
  }

  /** Rebuild a working instance from serialize() output (called in the worker). */
  static reconstruct(s) {
    const g = Object.create(SkullKingGame.prototype);
    Object.assign(g, s);
    g.scoreHistory = [];
    g.missionEvents = [];
    g.lastAbility = null;
    return g;
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
    const legalCards = this.currentPlayer === playerId && this.state === 'playing'
      ? this.getLegalCards(playerId)
      : [];
    // 능력을 쓰는 동안 currentPlayer 는 능력 주인이지만 카드를 낼 차례는 아니다.
    const isMyTurn = this.currentPlayer === playerId && this.state !== 'pirate_ability';
    const ab = this.pendingAbility;
    const abilityInfo = ab && ab.playerId === playerId
      ? {
        // 내 능력일 때만 주는 비공개 정보: Bendt 가 방금 뽑은 카드, Juanita 가 보는 안 나눈 카드.
        drawn: ab.drawn ? [...ab.drawn] : undefined,
        undealt: ab.pirate === 'juanita' ? sortCards(this.undealt) : undefined,
      }
      : null;

    return {
      gameType: 'skull_king',
      phase: this.state,
      round: this.round,
      totalRounds: TOTAL_ROUNDS,
      trickNumber: this.trickNumber,
      players,
      myCards: this.hands[playerId] || [],
      currentPlayer: this.currentPlayer,
      isMyTurn,
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
      pendingAbility: this.pendingAbility
        ? { playerId: this.pendingAbility.playerId, pirate: this.pendingAbility.pirate, cardId: this.pendingAbility.cardId }
        : null,
      lastAbility: this.lastAbility,
      abilitySeq: this.abilitySeq,
      rascalWagers: { ...(this.rascalWagers || {}) },
      abilityInfo,
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
      pendingAbility: this.pendingAbility
        ? { playerId: this.pendingAbility.playerId, pirate: this.pendingAbility.pirate, cardId: this.pendingAbility.cardId }
        : null,
      lastAbility: this.lastAbility,
      abilitySeq: this.abilitySeq,
      rascalWagers: { ...(this.rascalWagers || {}) },
    };
  }

  _getRoundStarter() {
    const dealerIndex = (this.initialDealerIndex + this.round - 1) % this.playerCount;
    return this.playerIds[(dealerIndex + 1) % this.playerCount];
  }

  getAutoTimeoutAction(playerId) {
    if (this.state === 'bidding' && this.bids[playerId] === null) {
      // 자리를 비운 사람은 1승을 부른다.
      //
      // 예전에는 0이었다. 0은 "한 판도 못 먹겠다" 는 선언이라 한 번이라도
      // 먹으면 그대로 감점이고, 손을 놓은 사람은 아무 카드나 내다가 곧잘
      // 먹는다. 1은 맞히면 점수를 받고 틀려도 0을 어겼을 때와 같은 폭으로
      // 깎인다 — 같은 위험에 얻을 것이 있는 쪽이다.
      //
      // 1라운드는 카드가 한 장이라 상한도 1이다. round 를 상한으로 씌우는
      // 것은 라운드가 아직 0인 순간(딜 직전)에 거절당하지 않게 하기 위한
      // 것이고, 그 경우 0으로 떨어진다.
      return { type: 'submit_bid', bid: Math.min(1, this.round) };
    }
    if (this.state === 'pirate_ability' && this.pendingAbility
        && this.pendingAbility.playerId === playerId) {
      return this._defaultAbilityAction();
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

    // Update pirate-ability state
    if (this.pendingAbility && this.pendingAbility.playerId === oldPlayerId) {
      this.pendingAbility.playerId = newPlayerId;
    }
    if (this.nextLeaderOverride === oldPlayerId) this.nextLeaderOverride = newPlayerId;
    if (this.rascalWagers && this.rascalWagers.hasOwnProperty(oldPlayerId)) {
      this.rascalWagers[newPlayerId] = this.rascalWagers[oldPlayerId];
      delete this.rascalWagers[oldPlayerId];
    }
    if (this.lastAbility) {
      if (this.lastAbility.playerId === oldPlayerId) this.lastAbility.playerId = newPlayerId;
      if (this.lastAbility.targetId === oldPlayerId) this.lastAbility.targetId = newPlayerId;
    }

    // Update loot alliances
    for (const a of this.lootAlliances || []) {
      if (a.winnerId === oldPlayerId) a.winnerId = newPlayerId;
      if (a.looterId === oldPlayerId) a.looterId = newPlayerId;
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
    // ...and the round's plays so far (the bot's card counting reads them by player)
    for (const play of this.roundPlays || []) {
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
