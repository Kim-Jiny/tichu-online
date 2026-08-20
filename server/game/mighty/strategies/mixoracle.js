'use strict';

/**
 * mixoracle strategy.
 *
 * Hybrid: a small set of explicit "hard rules" override the policy,
 * everything else falls through to `oracle`.
 *
 * Rationale:
 *   The perfect-information oracle is strong overall, but in a few specific
 *   spots the hand-tuned heuristic expresses clearer team-tempo intent. We
 *   layer those in as hard rules, then defer to the oracle for everything
 *   else.
 *
 * Rules currently enforced:
 *   1+2) Friend-card reveal mirror — when bot is the unrevealed friend on
 *      a declarer-led trick AND the heuristic picks the friend card
 *      itself, honor that pick directly. Covers:
 *        - joker-friend safe-window reveal (trump-mode)
 *        - mighty-friend rescue / reinforcement
 *        - suit-friend (e.g. ♣A) responding to declarer's bait lead in
 *          the friend-card suit — the natural reveal moment. Without
 *          this, later rules (e.g. rule 10) can override the heuristic's
 *          friend-card pick on a point-card / ruff-risk basis, and the
 *          partnership never surfaces.
 *   3) Friend lead — draw trump (lowest trump) when:
 *      - bot is the friend (revealed or not) and is leading
 *      - the bidding is NOT no-trump
 *      - opp team likely still holds trump
 *      - bot has no "safe fresh top" (a non-trump effective-top card in a
 *        suit nobody has led yet)
 *      - bot has a non-mighty trump in hand
 *      Without this, the bot tends to lead an already-led non-trump suit,
 *      letting opp trump-ruff or dump cheaply. Drawing trump first forces
 *      opp's trumps out so later non-trump leads survive.
 *   4) Friend lead in NT — cash all effective tops (mighty included, joker
 *      excluded), highest first; once tops are spent, return the called
 *      suit (부른문양 = friend-card's suit) HIGH-first so we either keep
 *      the lead or force opp's high card out. Only applies to NT
 *      (no_trump). Without this, the heuristic prioritises feeding the
 *      call suit before the bot's own tops, leaving high cards stranded.
 *   5) Friend on declarer-secure follow — when declarer led, declarer is
 *      currently the trick winner, AND declarer's card is the effective
 *      top of its suit, the trick is locked in. Defer to the heuristic's
 *      pick (which dumps safely without burning mighty/joker, OR plays
 *      the joker as the trump-mode safe-window reveal — both desirable).
 *      Without this, expectimax sometimes over-cuts declarer's secured
 *      trick with mighty/joker — pointlessly stealing the lead and
 *      wasting a finisher.
 *   6) Preserve weak joker — when joker has no power on the current trick
 *      (first/last trick by default, or jokerCall active) and the bot
 *      has > 1 legal card, defer to the heuristic. The heuristic
 *      explicitly avoids burning a powerless joker; expectimax sometimes
 *      dumps it as "weakest" via rollout score noise. Applies to all
 *      roles (declarer, friend, opposition) since the joker's value is
 *      role-independent — it only matters that the trick can't take it.
 *   7) Government lead with no real opp trump left — when bot is on the
 *      declarer team (declarer or friend) about to lead in non-NT, and
 *      no real opp still holds trump, defer to the heuristic. The
 *      heuristic explicitly avoids leading trump in this state (Phase
 *      2/5 of governmentLead gate on `!_onlyGovernmentHasTrump`); without
 *      this, expectimax keeps draining the team's own trumps until none
 *      are left, leaving the team helpless against opp's later runs.
 *   8) Friend joker lead under real joker-call threat — when a friend is
 *      leading with a powered joker, an opponent actually holds the
 *      joker-call card, and an exact rollout says cashing joker now beats
 *      the oracle's baseline lead, override to the best scored joker suit.
 *   9) Mighty-friend force-win when team's win isn't secure — declarer
 *      led, the team's current win-state is NOT secure (either declarer
 *      is currently losing, OR declarer's winning card isn't an effective
 *      top with opp behind able to over-cut), AND mighty is legal in our
 *      hand → play mighty. The heuristic's "minimum sufficient winner"
 *      logic prefers a probabilistically-safe cheap winner (e.g., A of
 *      lead suit), but `_isSafeFriendWinner` only spot-checks ruff risk
 *      and lets fragile picks through. When the team's trick is at risk,
 *      forcing mighty makes it unconditional — guaranteed win + reveal
 *      for team coordination.
 *  10) Friend conserve points on unsafe declarer-led tricks — when the
 *      heuristic would pick a non-trump POINT card (A/K/Q/J/10) as a
 *      cheap winner on an unsafe trick AND opp may still trump-ruff
 *      (countOpponentTrumps > 0), prefer to concede with a non-point
 *      card rather than hand the points to opp via a likely ruff. Falls
 *      through if no non-point legal alternative exists or trump isn't
 *      active. Specific to non-mighty-friend follow (mighty-friend is
 *      already handled by rule 9).
 *  12) Friend lead in suited (non-NT) — cash all safe fresh non-trump
 *      tops first, highest rank first. A "safe fresh top" is the
 *      effective top of a non-trump suit that nobody has led yet —
 *      same definition as the gate in rule 3. Rule 3 only fires when
 *      such tops are absent (it triggers the trump drain), so this
 *      rule covers the symmetric case: tops PRESENT → cash them
 *      before falling through. Combined with rule 3's highest-trump
 *      drain, friend's suited lead now goes:
 *        1. safe non-trump top (highest first)
 *        2. high trump (highest first, drains opp)
 *        3. expectimax / joker / fallbacks
 *  13) Declarer joker-probe trump — when declarer leads in suited mode
 *      and our highest non-mighty trump is NOT the effective top of
 *      the trump suit (i.e., a higher trump is unaccounted for), fire
 *      the joker declaring trump to bait that high trump out instead
 *      of leading our suboptimal top. Covers the user's joker-strategy
 *      cases:
 *        - no trump A in hand → joker first to drain opp's A
 *        - have A but K missing → after A is gone, our K isn't safe →
 *          joker before leading Q
 *        - any subsequent gap that breaks our drain sequence
 *  14) Declarer save mighty for last — when leading suited and we hold
 *      both mighty and a productive trump, trump comes first. Mighty
 *      is an unconditional winner whose value persists; trump tops are
 *      time-sensitive (every passing trick risks opp burning theirs).
 *      Rule fires only when (a) opp still has trump and (b) our top
 *      non-mighty trump IS the effective top — i.e., a productive
 *      drain step. When the top isn't safe, we let rule 13 take over.
 *  11) Friend joker-call against the actual opposing joker — when the
 *      friend can legally lead the joker-call card, an opponent really
 *      holds the joker, and an exact rollout says the forced call beats
 *      the oracle's baseline lead, override to the call.
 */

const oracle = require('./oracle');
const { runRollout } = require('./rollout');
const endgameSolver = require('../MightyEndgameSolver');
const MightyBotInternals = require('../MightyBot');

// Endgame solver on by default; MIGHTY_NO_SOLVER=1 disables (for A-B testing).
const SOLVER_ON = process.env.MIGHTY_NO_SOLVER !== '1';

// Per-seat gate hook (testing only). When global.__mightySolverGate is a
// function, the solver is enabled for a seat only if it returns true — lets a
// head-to-head harness pit solver seats against oracle-only seats at one table.
function _solverEnabledFor(botId) {
  if (!SOLVER_ON) return false;
  const gate = global.__mightySolverGate;
  return typeof gate === 'function' ? gate(botId) : true;
}
const { getCardInfo, RANK_ORDER, SUITS } = require('../MightyDeck');

// Wall-clock cap for the multi-candidate play sweep. Caps how long the single
// event-loop thread is blocked on rollouts; the first candidate always runs, so
// we never return without a pick. See oracle.js EVAL_BUDGET_MS.
const EVAL_BUDGET_MS = 12;

function _diagNumberEnv(name, fallback) {
  const n = Number(process.env[name]);
  return Number.isFinite(n) && n >= 0 ? n : fallback;
}

function _diagElapsedMs(start) {
  return Number(process.hrtime.bigint() - start) / 1e6;
}

function _maxActiveHandSize(game) {
  let max = 0;
  for (const pid of game.playerIds || []) {
    if (game.excludedPlayers && game.excludedPlayers.has(pid)) continue;
    const n = (game.hands && game.hands[pid] && game.hands[pid].length) || 0;
    if (n > max) max = n;
  }
  return max;
}

function _heuristicPlayAction(game, botId) {
  const action = MightyBotInternals.decideMightyBotAction(game, botId, 'heuristic');
  if (!action || action.type !== 'play_card') return null;
  return action;
}

function _roundDelta(preScores, finalGame, botId) {
  const before = preScores[botId] || 0;
  const after = (finalGame.scores && finalGame.scores[botId]) || 0;
  return after - before;
}

function _playActionKey(action) {
  if (!action || action.type !== 'play_card') return null;
  return [
    action.cardId || '',
    action.jokerSuit || '',
    action.jokerCall === true ? 'call' : '',
  ].join('|');
}

function _evaluatePlayActionScore(game, botId, action, deadline = 0) {
  if (!action || action.type !== 'play_card') return -Infinity;
  const world = game.clone();
  const result = world.handleAction(botId, action);
  if (!result || !result.success) return -Infinity;
  const preScores = { ...game.scores };
  runRollout(world, deadline);
  if (deadline && Date.now() >= deadline
      && world.state !== 'round_end'
      && world.state !== 'game_end') {
    return -Infinity;
  }
  return _roundDelta(preScores, world, botId);
}

function _bestPlayAction(game, botId, actions) {
  const seen = new Set();
  let bestAction = null;
  let bestScore = -Infinity;
  const deadline = Date.now() + EVAL_BUDGET_MS;

  for (const action of actions) {
    const key = _playActionKey(action);
    if (!key || seen.has(key)) continue;
    seen.add(key);

    const score = _evaluatePlayActionScore(game, botId, action, deadline);
    if (score > bestScore) {
      bestScore = score;
      bestAction = action;
    }
    // Stop once the budget is spent; the best-so-far stands.
    if (Date.now() > deadline) break;
  }

  return { action: bestAction, score: bestScore };
}

function _preferActionOverOracle(game, botId, candidateActions) {
  const candidate = _bestPlayAction(game, botId, candidateActions);
  if (!candidate.action) return null;

  const oracleAction = oracle.decide(game, botId);
  if (!oracleAction || oracleAction.type !== 'play_card') return candidate.action;

  if (_playActionKey(candidate.action) === _playActionKey(oracleAction)) {
    return candidate.action;
  }

  const oracleScore = _evaluatePlayActionScore(game, botId, oracleAction, Date.now() + EVAL_BUDGET_MS);
  // 오라클 평가가 시간초과로 미완성(-Infinity)이면 후보가 낫다고 단정할 수 없다.
  // 이 경우 오라클 추천을 유지한다(null 반환). 안 그러면 어려운(=롤아웃이 느린)
  // 국면에서 봇이 계통적으로 오라클을 버리고 휴리스틱으로 흘러 약해진다.
  if (oracleScore === -Infinity) return null;
  return candidate.score > oracleScore ? candidate.action : null;
}

function _isGovernmentTeam(game, pid) {
  return pid === game.declarer || MightyBotInternals.isFriend(game, pid);
}

function _getOppositionPlayers(game, botId) {
  const botIsGov = _isGovernmentTeam(game, botId);
  return game.playerIds.filter(pid => {
    if (pid === botId) return false;
    if (game.excludedPlayers && game.excludedPlayers.has(pid)) return false;
    return _isGovernmentTeam(game, pid) !== botIsGov;
  });
}

/**
 * Rule 1+2 mirror: unrevealed friend honors the heuristic's friend-card
 * pick on a declarer-led trick. Covers all friend variants where the
 * friend is a specific card (joker, mighty, or any regular suit card).
 *
 * Note: this MUST run before rules 9/10 so a friend-card pick is never
 * overridden by force-mighty / conserve-points logic — the friend card
 * IS the partnership-reveal moment and the heuristic already knows when
 * it's the right play.
 */
function _friendCardRevealRule(game, botId) {
  if (!game.currentTrick || game.currentTrick.length === 0) return null;
  if (!MightyBotInternals.isFriend(game, botId)) return null;
  if (game.friendRevealed) return null;

  const declarerLed = game.currentTrick[0].pid === game.declarer;
  if (!declarerLed) return null;

  const friendCard = game.friendCard;
  if (!friendCard
      || friendCard === 'no_friend'
      || friendCard === 'first_trick') {
    return null;
  }

  const action = _heuristicPlayAction(game, botId);
  if (!action || action.type !== 'play_card') return null;
  if (action.cardId !== friendCard) return null;
  return action;
}

/**
 * True if the bot has a non-trump non-mighty non-joker card that is the
 * effective top of its suit AND that suit hasn't been led yet — i.e., a
 * "safe fresh top" the bot can lead without much over-cut risk.
 */
function _hasSafeFreshTop(game, botId) {
  const trump = game.trumpSuit;
  const trumpActive = trump && trump !== 'no_trump';
  const mightyCard = game.getMightyCard();
  const hand = game.hands[botId] || [];

  for (const cardId of hand) {
    if (cardId === 'mighty_joker') continue;
    if (cardId === mightyCard) continue;
    const info = getCardInfo(cardId);
    if (!info) continue;
    if (trumpActive && info.suit === trump) continue;

    if (!MightyBotInternals.isEffectiveTopOfSuit(cardId, game)) continue;
    if (MightyBotInternals.suitLedCount(game, info.suit) > 0) continue;
    return true;
  }
  return false;
}

/**
 * Rule 3: friend leads trump to draw opp's trumps.
 *
 * Fires only when:
 *   - bot is friend AND about to lead
 *   - non-NT bidding (trump suit defined)
 *   - opp likely still holds trump (countOpponentTrumps > 0; this counts
 *     trumps unaccounted for in our hand / played / discarded — strictly
 *     it includes possible declarer-held trumps, but in practice if any
 *     trump is unaccounted for, opp may hold it)
 *   - no safe fresh non-trump top to lead
 *   - bot has at least one non-mighty trump in hand to actually draw with
 *
 * Returns a play_card action for the highest non-mighty trump, else null.
 * Highest-first lets declarer read the field — every high trump that goes
 * by tells declarer one fewer threat sits with opp, so they can plan the
 * drain accordingly. (Standard Korean-Mighty signalling convention.)
 */
function _friendDrawTrumpRule(game, botId) {
  if (game.currentTrick && game.currentTrick.length > 0) return null;
  if (!MightyBotInternals.isFriend(game, botId)) return null;

  const trump = game.trumpSuit;
  if (!trump || trump === 'no_trump') return null;

  if (MightyBotInternals.countOpponentTrumps(game, botId) <= 0) return null;
  // Don't draw trump when only our own team (declarer + friend) still holds
  // real trump. countOpponentTrumps counts the joker as a "trump", but the
  // joker isn't a trump-suit card — a trump lead can't draw it, it just lets
  // opp beat our trump with the joker. noRealOppTrumpLeft ignores the joker
  // and checks actual trump-suit holdings, so gate on it here.
  if (MightyBotInternals.noRealOppTrumpLeft(game, botId)) return null;
  if (_hasSafeFreshTop(game, botId)) return null;

  const mightyCard = game.getMightyCard();
  const hand = game.hands[botId] || [];
  const trumpInHand = [];
  for (const cardId of hand) {
    if (cardId === 'mighty_joker') continue;
    if (cardId === mightyCard) continue;
    const info = getCardInfo(cardId);
    if (!info || info.suit !== trump) continue;
    trumpInHand.push(cardId);
  }
  if (trumpInHand.length === 0) return null;

  trumpInHand.sort((a, b) => {
    const ra = RANK_ORDER[getCardInfo(a).rank] || 0;
    const rb = RANK_ORDER[getCardInfo(b).rank] || 0;
    return rb - ra;
  });
  const pick = trumpInHand[0];

  return MightyBotInternals.makePlayAction(pick, game, botId);
}

/**
 * Rule 4: friend NT lead — tops first, then return the called suit.
 *
 * Fires only when:
 *   - bot is friend AND about to lead
 *   - bidding is no-trump
 *   - bot has either an effective top to cash OR cards in the called
 *     (friend-card) suit to return
 *
 * Returns a play_card action; falls through (null) when neither applies
 * (e.g., friend variant with no called suit — joker/mighty/first_trick/
 * no_friend — and no tops left).
 */
/**
 * 부른 문양 — 주공이 프렌드를 끌어낸 무늬.
 *
 * 보통은 프렌드 카드의 무늬 그대로다(♣A 프렌드 → 클로버). 그런데 마이티/조커를
 * 프렌드 카드로 부른 경우엔 카드 자체에 무늬 의미가 없다. 마이티가 ♠A 라고
 * 스페이드를 부른 게 아니다. 이때는 **주공이 프렌드를 끌어내려고 리드한 그
 * 트릭의 무늬**가 부른 문양이다 — 주공이 ♣4 를 깔고 프렌드가 마이티로 받아
 * 나왔으면 클로버가 부른 문양이고, 나중에 돌려줘야 할 곳도 클로버다.
 *
 * 주공이 아닌 사람이 리드한 트릭에서 프렌드 카드가 나왔으면 신호가 아니므로
 * null 을 돌려준다(예전처럼 오라클에 맡긴다).
 */
function _calledSuit(game) {
  const friendCard = game.friendCard;
  if (!friendCard || friendCard === 'no_friend' || friendCard === 'first_trick') {
    return null;
  }

  if (friendCard !== 'mighty_joker' && friendCard !== game.getMightyCard()) {
    const info = getCardInfo(friendCard);
    return (info && info.suit) || null;
  }

  // A/B 측정용 좌석 게이트. 켜지면 예전(마이티/조커 프렌드는 포기) 동작으로 돈다.
  if (typeof global.__mightyCalledSuitLegacy === 'function'
      && global.__mightyCalledSuitLegacy()) {
    return null;
  }

  for (const trick of game.tricks || []) {
    if (!(trick.cards || []).some(c => c.cardId === friendCard)) continue;
    if (trick.leader !== game.declarer) return null;
    if (trick.leadSuit && typeof global.__mightyCalledSuitHook === 'function') {
      global.__mightyCalledSuitHook(trick.leadSuit);
    }
    return trick.leadSuit || null;
  }

  // 아직 프렌드 카드가 안 나왔다면 — 마이티/조커 프렌드는 카드를 낼 때까지
  // 드러나지 않는다 — 주공이 처음 깐 무늬가 곧 부른 문양이다. 주공은 그
  // 무늬로 프렌드를 끌어내려는 것이고, 돌려줄 곳도 거기다.
  if (!game.friendRevealed) {
    for (const trick of game.tricks || []) {
      if (trick.leader !== game.declarer) continue;
      if (trick.leadSuit && typeof global.__mightyCalledSuitHook === 'function') {
        global.__mightyCalledSuitHook(trick.leadSuit);
      }
      return trick.leadSuit || null;
    }
  }
  return null;
}

function _friendNTLeadRule(game, botId) {
  if (game.currentTrick && game.currentTrick.length > 0) return null;
  if (!MightyBotInternals.isFriend(game, botId)) return null;

  const trump = game.trumpSuit;
  if (trump && trump !== 'no_trump') return null;

  const hand = game.hands[botId] || [];
  if (hand.length === 0) return null;

  // NT 에서는 원래 마이티 무늬 회피를 안 걸었다 — 부른 문양이 마침 마이티
  // 무늬여도 돌려줄 수 있어야 하기 때문이다. 다만 주공의 그 무늬 보유가
  // 마이티 한 장뿐이면 돌리는 순간 마이티가 강제로 끌려 나오므로, 그 좁은
  // 경우만 NT 에서도 피한다(_mightySuitToAvoidLeading 이 그 판정을 한다).
  const avoidSuit = MightyBotInternals.mightySuitToAvoidLeading(game, botId);
  const leadable = avoidSuit
    ? hand.filter(c => c === 'mighty_joker' || getCardInfo(c).suit !== avoidSuit)
    : hand;

  const friendSuit = _calledSuit(game);
  const calledSuitCards = friendSuit
    ? leadable.filter(c => c !== 'mighty_joker'
        && (getCardInfo(c) || {}).suit === friendSuit)
    : [];

  // 아직 드러나지 않은 마이티 프렌드는 마이티를 "현금화할 top" 으로 세지
  // 않는다. 마이티는 언제든 이기는 카드라 top 목록의 맨 앞에 서지만, 여기서
  // 던지면 두 가지를 한꺼번에 버린다: 아무도 위협하지 않는 트릭에 최강 카드를
  // 쓰고, 그러면서 프렌드가 누구인지 알려준다. 주공이 부른 무늬를 돌려줄 수
  // 있을 때만 미룬다 — 돌려줄 게 없으면 마이티로라도 선을 잡는 게 맞다.
  const holdMighty = game.friendCard === game.getMightyCard()
    && !game.friendRevealed
    && calledSuitCards.length > 0;

  const tops = [];
  for (const cardId of leadable) {
    if (cardId === 'mighty_joker') continue;
    if (holdMighty && cardId === game.getMightyCard()) continue;
    if (!MightyBotInternals.isEffectiveTopOfSuit(cardId, game)) continue;
    tops.push(cardId);
  }
  if (tops.length > 0) {
    tops.sort((a, b) => {
      const ra = RANK_ORDER[getCardInfo(a).rank] || 0;
      const rb = RANK_ORDER[getCardInfo(b).rank] || 0;
      return rb - ra;
    });
    return MightyBotInternals.makePlayAction(tops[0], game, botId);
  }

  if (!friendSuit) return null;
  const friendSuitCards = [...calledSuitCards];
  if (friendSuitCards.length === 0) return null;

  // Called-suit return goes HIGH-first: leading the highest remaining
  // called-suit card either wins outright (if opp's higher card stays
  // home) or forces opp's high card out — either way it preserves our
  // lead. Leading low here lets opp keep their A and stop our flow.
  friendSuitCards.sort((a, b) => {
    const ra = RANK_ORDER[getCardInfo(a).rank] || 0;
    const rb = RANK_ORDER[getCardInfo(b).rank] || 0;
    return rb - ra;
  });
  return MightyBotInternals.makePlayAction(friendSuitCards[0], game, botId);
}

/**
 * Rule 12: friend lead in suited (non-NT) — cash safe non-trump tops first.
 *
 * Pairs with rule 3: rule 3 drains opp trump when there's NO safe fresh
 * top to cash; this rule cashes the top when there IS one. Without this,
 * mix falls through to expectimax for the "I have both a safe top AND
 * high trumps" case, and rollout noise sometimes leaves both unplayed.
 *
 * Returns the highest safe fresh non-trump top, else null.
 */
function _friendSuitedTopCashRule(game, botId) {
  if (game.currentTrick && game.currentTrick.length > 0) return null;
  if (!MightyBotInternals.isFriend(game, botId)) return null;

  const trump = game.trumpSuit;
  if (!trump || trump === 'no_trump') return null;

  const hand = game.hands[botId] || [];
  if (hand.length === 0) return null;
  const mightyCard = game.getMightyCard();

  // While the declarer still holds the Mighty, don't cash a top in its home
  // suit (skipped for mighty/joker-friend designation / when we hold trump).
  const avoidSuit = MightyBotInternals.mightySuitToAvoidLeading(game, botId);

  const tops = [];
  for (const cardId of hand) {
    if (cardId === 'mighty_joker') continue;
    if (cardId === mightyCard) continue;
    const info = getCardInfo(cardId);
    if (!info) continue;
    if (info.suit === trump) continue;
    if (avoidSuit && info.suit === avoidSuit) continue;
    if (!MightyBotInternals.isEffectiveTopOfSuit(cardId, game)) continue;
    if (MightyBotInternals.suitLedCount(game, info.suit) > 0) continue;
    tops.push(cardId);
  }
  if (tops.length === 0) return null;

  tops.sort((a, b) => {
    const ra = RANK_ORDER[getCardInfo(a).rank] || 0;
    const rb = RANK_ORDER[getCardInfo(b).rank] || 0;
    return rb - ra;
  });
  return MightyBotInternals.makePlayAction(tops[0], game, botId);
}

/**
 * Rule 5: friend on declarer-secure follow — defer to heuristic.
 *
 * Fires when:
 *   - bot is friend
 *   - declarer led the current trick
 *   - declarer is the current winner
 *   - declarer's card is the effective top of its suit (no over-cut path
 *     remains within suit-follow rules — mighty / joker stay as the only
 *     theoretical over-cut, which is exactly what we want to avoid)
 *
 * Returns the heuristic play action, else null. The heuristic in this
 * branch (governmentFollow line ~1560 dumpSafe + the joker safe-window
 * reveal block) already produces the right behaviour; mix just makes sure
 * oracle doesn't override it with a needless over-cut.
 */
/**
 * Rule 16: friend on declarer-led trick with no safe winner → defer to
 * heuristic.
 *
 * When the bot is forced to follow the lead (e.g., trump-suit lead and
 * we hold only trump) AND no card in our legal set is a `_isSafeFriendWinner`,
 * we will inevitably over-trump declarer or lose to an opp behind. The
 * choice is then between burning a high card (e.g. trump A vulnerable to
 * joker over-cut) or dumping a low one. The heuristic correctly picks the
 * low dump (`getSafeDiscard`); expectimax sometimes chases the high one
 * via rollout score.
 *
 * The shared candidate filter (`filterFriendSafeCandidates`) keeps the
 * full legal set as a fallback when no safe winner exists, so expectimax
 * sees high winners as candidates. This rule short-circuits that path
 * when there's no safe winner at all — heuristic's loss-minimisation is
 * the right call.
 */
function _friendNoSafeWinnerRule(game, botId) {
  if (!game.currentTrick || game.currentTrick.length === 0) return null;
  if (!MightyBotInternals.isFriend(game, botId)) return null;

  const declarerLed = game.currentTrick[0].pid === game.declarer;
  if (!declarerLed) return null;

  const legal = game.getLegalCards(botId);
  if (!legal || legal.length === 0) return null;

  for (const cardId of legal) {
    if (!MightyBotInternals.canBeatCurrentWinner(game, cardId)) continue;
    if (MightyBotInternals.isSafeFriendWinner(cardId, game, botId)) {
      return null; // safe winner exists — let expectimax decide
    }
  }

  const action = _heuristicPlayAction(game, botId);
  if (!action) return null;
  return action;
}

/**
 * Rule 19: declarer doesn't over-cut friend's secure win.
 *
 * When bot is declarer and the current trick winner is friend (revealed
 * or pre-reveal but holding friend card) AND friend's winning card is
 * secure (effective top, or perfect-info confirms no opp behind beats
 * it), declarer should dump — not over-cut their own ally with mighty
 * etc. The heuristic handles this via dumpSafe in the winnerOnOurTeam
 * branch, but expectimax sometimes burns a finisher via rollout noise.
 *
 * Mirror of rule 5 for declarer-side perspective.
 */
function _declarerSavesAllyWinRule(game, botId) {
  if (!game.currentTrick || game.currentTrick.length === 0) return null;
  if (botId !== game.declarer) return null;

  const currentWinner = MightyBotInternals.getCurrentTrickWinner(game);
  if (!currentWinner || currentWinner === botId) return null;
  if (!MightyBotInternals.isFriend(game, currentWinner)) return null;

  const winnerCard = MightyBotInternals.getWinnerCardId(game);
  if (!winnerCard) return null;

  const winnerIsEffectiveTop = MightyBotInternals.isEffectiveTopOfSuit(winnerCard, game);
  const winnerWillHold = MightyBotInternals.winnerCardWillHold(game, botId);
  if (!winnerIsEffectiveTop && !winnerWillHold) return null;

  const action = _heuristicPlayAction(game, botId);
  if (!action) return null;
  return action;
}

/**
 * Rule 18: friend follow with a safe non-mighty/non-joker winner → defer
 * to heuristic. Stops expectimax from picking mighty/joker as a "winner"
 * via rollout noise when a cheap safe winner exists. Heuristic naturally
 * picks the cheap winner via `safeSameSuit` filter.
 *
 * Example: declarer leads ♣4 trick 1, friend holds ♣A + mighty. ♣A is
 * the textbook safe top of suit (effective top, no opp likely void on
 * trick 1). Mighty is overkill. Without this rule, expectimax sometimes
 * burns mighty for no benefit.
 */
function _friendSafeWinnerRule(game, botId) {
  if (!game.currentTrick || game.currentTrick.length === 0) return null;
  if (!MightyBotInternals.isFriend(game, botId)) return null;

  const declarerLed = game.currentTrick[0].pid === game.declarer;
  if (!declarerLed) return null;

  const mightyCard = game.getMightyCard();
  const legal = game.getLegalCards(botId);
  if (!legal || legal.length === 0) return null;

  let hasSafeCheapWinner = false;
  for (const cardId of legal) {
    if (cardId === mightyCard) continue;
    if (cardId === 'mighty_joker') continue;
    if (!MightyBotInternals.canBeatCurrentWinner(game, cardId)) continue;
    if (MightyBotInternals.isSafeFriendWinner(cardId, game, botId)) {
      hasSafeCheapWinner = true;
      break;
    }
  }
  if (!hasSafeCheapWinner) return null;

  const action = _heuristicPlayAction(game, botId);
  if (!action) return null;
  return action;
}

/**
 * Rule 17: nobody-can-win → defer to heuristic.
 *
 * When NO card in our legal set can beat the current trick winner (e.g.,
 * joker is on the table and we don't hold mighty), we will lose the
 * trick no matter what we play. The right move is to dump the cheapest
 * non-point card so opp doesn't pick up our high cards. The heuristic
 * does this via `getNonPointWeakest` / `getSafeDiscard`; expectimax
 * sometimes picks a high card via rollout noise, e.g., burning a trump A
 * onto a joker-on-table trick.
 *
 * Applies to ALL roles (friend / declarer / opposition).
 */
function _cantWinDeferRule(game, botId) {
  if (!game.currentTrick || game.currentTrick.length === 0) return null;
  const legal = game.getLegalCards(botId);
  if (!legal || legal.length === 0) return null;

  for (const cardId of legal) {
    if (MightyBotInternals.canBeatCurrentWinner(game, cardId)) return null;
  }

  const action = _heuristicPlayAction(game, botId);
  if (!action) return null;
  return action;
}

/**
 * NT (노기루다) follow-dump rule: revealed friend following a declarer-led
 * trick in no-trump mode dumps HIGH first (highest legal card that
 * doesn't beat declarer). Reason: in NT the highest card of the led
 * suit wins; if the friend keeps high cards, they may accidentally
 * steal a future trick (a weaker declarer lead the friend can't help
 * winning), forcing declarer to give up their planned play. Burning
 * high cards while declarer is leading keeps friend's later cards
 * "naturally low" — they can't outbid declarer's next lead.
 *
 * Fires before _friendDeclarerSecureRule (which would dump low via the
 * heuristic) so NT specifically gets the HIGH-first behavior.
 */
function _friendNTFollowDumpHighRule(game, botId) {
  if (game.trumpSuit && game.trumpSuit !== 'no_trump') return null;
  if (!game.currentTrick || game.currentTrick.length === 0) return null;
  if (!game.friendRevealed) return null;
  if (!MightyBotInternals.isFriend(game, botId)) return null;

  const ledPlay = game.currentTrick[0];
  if (!ledPlay || ledPlay.playerId !== game.declarer) return null;

  const legal = game.getLegalCards(botId);
  if (!legal || legal.length <= 1) return null;

  // Joker is too flexible to dump generically — preserve-weak-joker
  // rule handles its case.
  const candidates = legal.filter((c) => c !== 'mighty_joker');
  if (candidates.length === 0) return null;

  // Highest legal card that loses to the current winner (declarer).
  // Falling back to the highest legal card if all options would win
  // (forced overtake — unavoidable).
  let bestNonWinning = null;
  let bestNonWinningRank = -1;
  let bestAny = null;
  let bestAnyRank = -1;
  for (const cardId of candidates) {
    const info = getCardInfo(cardId);
    if (!info) continue;
    const rank = RANK_ORDER[info.rank] || 0;
    if (rank > bestAnyRank) {
      bestAnyRank = rank;
      bestAny = cardId;
    }
    if (!MightyBotInternals.canBeatCurrentWinner(game, cardId)) {
      if (rank > bestNonWinningRank) {
        bestNonWinningRank = rank;
        bestNonWinning = cardId;
      }
    }
  }
  const pick = bestNonWinning || bestAny;
  if (!pick) return null;
  return MightyBotInternals.makePlayAction(pick, game, botId);
}

function _friendDeclarerSecureRule(game, botId) {
  if (!game.currentTrick || game.currentTrick.length === 0) return null;
  if (!MightyBotInternals.isFriend(game, botId)) return null;

  const currentWinner = MightyBotInternals.getCurrentTrickWinner(game);
  if (currentWinner !== game.declarer) return null;

  const winnerCard = MightyBotInternals.getWinnerCardId(game);
  if (!winnerCard) return null;

  // Two safety paths: declarer's card is the effective top of its suit
  // (within-suit no over-ruff possible), OR perfect-info shows no opp
  // behind has any card that beats it. The latter covers cases where
  // declarer ruffed mid-trump (e.g., ♥10) but no opp seat has a higher
  // trump or mighty/powered joker — heuristic correctly dumps but
  // expectimax sometimes burns mighty/joker as a "reinforcement".
  const winnerIsEffectiveTop = MightyBotInternals.isEffectiveTopOfSuit(winnerCard, game);
  const winnerWillHold = MightyBotInternals.winnerCardWillHold(game, botId);
  if (!winnerIsEffectiveTop && !winnerWillHold) return null;

  const action = _heuristicPlayAction(game, botId);
  if (!action) return null;
  return action;
}

/**
 * Rule 6: preserve weak joker — defer to heuristic when joker is in legal
 * cards but powerless on the current trick (first/last trick default, or
 * jokerCall active). Applies regardless of role.
 *
 * Heuristic guarantees:
 *   - Lead path filters out powerless joker when there's an alternative
 *     (`decideLeadCard` lines ~1013-1019).
 *   - Follow path's safe-dump helpers exclude joker (`pickSafeDump` /
 *     `pickSafeDumpKeepingTops`); `pickSufficientWinner` doesn't include
 *     a powerless joker since `canBeatCurrentWinner` returns false.
 * So the heuristic's pick is reliably non-joker here. The only escape
 * (heuristic also returns joker) is when joker is forced legal-only —
 * the early `legal.length <= 1` gate handles that.
 */
function _preserveWeakJokerRule(game, botId) {
  const hand = game.hands[botId] || [];
  if (!hand.includes('mighty_joker')) return null;

  // Joker is wasted whenever it CAN'T take the current trick — burning
  // it sacrifices future trick-taking power for nothing. Two cases:
  //   1. Joker has no power (first/last trick default, or jokerCall
  //      active) — joker is just a low card.
  //   2. Mighty is already on the table — joker loses to mighty
  //      regardless of power, so playing it just hands it to declarer.
  const jokerHasPower = typeof game._currentTrickJokerHasPower === 'function'
    && game._currentTrickJokerHasPower();
  const mightyCard = game.getMightyCard();
  const mightyOnTable = (game.currentTrick || []).some(p => p.cardId === mightyCard);
  if (jokerHasPower && !mightyOnTable) return null;

  const legal = game.getLegalCards(botId);
  if (!legal || legal.length <= 1) return null;
  if (!legal.includes('mighty_joker')) return null;

  const action = _heuristicPlayAction(game, botId);
  if (!action) return null;
  if (action.cardId === 'mighty_joker') return null;
  return action;
}

/**
 * Rule 7: government bot leading in non-NT with no real opp trump left —
 * defer to heuristic.
 *
 * "Real opp trump" excludes our own hand and (when revealed) the partner's
 * hand. When all trumps are concentrated on the declarer team, drawing
 * trump is wasted tempo — every trump played leaves us with one fewer
 * defender against opp's later runs. The heuristic's governmentLead
 * Phase 2 / Phase 5 already gate trump leads on `!_onlyGovernmentHasTrump`;
 * mix mirrors that here so expectimax can't override with a trump lead.
 */
function _govLeadNoOppTrumpRule(game, botId) {
  if (game.currentTrick && game.currentTrick.length > 0) return null;

  const isDeclarer = botId === game.declarer;
  const isFriendBot = MightyBotInternals.isFriend(game, botId);
  if (!isDeclarer && !isFriendBot) return null;

  const trump = game.trumpSuit;
  if (!trump || trump === 'no_trump') return null;

  if (!MightyBotInternals.noRealOppTrumpLeft(game, botId)) return null;

  const action = _heuristicPlayAction(game, botId);
  if (!action) return null;
  return action;
}

/**
 * Rule 8: proactive friend joker lead, but only when the exact rollout
 * beats the current oracle lead.
 *
 * This is now a perfect-information override rather than a policy gate:
 * only consider the lead when an opponent still holds the joker-call card,
 * so the joker is genuinely exposed to a future forced pull.
 */
function _friendJokerLeadRule(game, botId) {
  if (game.currentTrick && game.currentTrick.length > 0) return null;
  if (!MightyBotInternals.isFriend(game, botId)) return null;

  if (typeof game._currentTrickJokerHasPower !== 'function') return null;
  if (!game._currentTrickJokerHasPower()) return null;

  const hand = game.hands[botId] || [];
  if (!hand.includes('mighty_joker')) return null;

  const jokerCallCard = game.getJokerCallCard();
  if (!jokerCallCard || hand.includes(jokerCallCard)) return null;

  const trump = game.trumpSuit;
  if (!trump || trump === 'no_trump') return null;

  const opposition = _getOppositionPlayers(game, botId);
  const oppThreat = opposition.some(pid => (game.hands[pid] || []).includes(jokerCallCard));
  // 주공이 조커콜 카드를 들고 있고 아직 프렌드가 안 드러났으면, 주공은 내가
  // 조커를 들고 있는 줄 모른다. 사람 주공은 상대 조커를 끌어내려고 그냥 쏘고,
  // 그러면 우리 조커가 헛되이 타 버린다. 봇 주공은 이제 우리 편 조커를 보고
  // 안 쏘지만(_teammateHoldsJoker), 사람은 볼 수가 없다.
  // 그 전에 내 리드로 조커를 값나가게 쓰는 게 낫다.
  // 공개 여부와 무관하다. 공개 전이면 주공이 우리 조커를 모르고 쏘고, 공개
  // 뒤여도 사람 주공은 잊거나 야당을 노리고 쏜다 — 어느 쪽이든 맞는 건 우리
  // 조커다("주공이 쏜 총에 프렌즈가 맞는다"). 예전에는 공개 전만 위협으로
  // 봐서, 프렌드가 드러난 뒤에는 이 룰이 아예 안 걸렸다.
  const declarerThreat = game.declarer !== botId
    && (game.hands[game.declarer] || []).includes(jokerCallCard)
    // A/B 측정용 좌석 게이트. 켜지면 예전(상대 위협만 봄) 동작으로 돈다.
    && !(typeof global.__mightyDeclarerJokerThreatLegacy === 'function'
      && global.__mightyDeclarerJokerThreatLegacy(botId));

  if (!oppThreat && !declarerThreat) return null;

  const legal = game.getLegalCards(botId);
  if (!legal || !legal.includes('mighty_joker')) return null;

  const candidateActions = SUITS.map(suit => ({
    type: 'play_card',
    cardId: 'mighty_joker',
    jokerSuit: suit,
  }));

  const picked = _preferActionOverOracle(game, botId, candidateActions);
  if (picked) return picked;

  // 주공이 조커콜 카드를 들고 있어서 생긴 위협이면 롤아웃 승인을 기다리지 않는다.
  // 롤아웃은 주공을 "손패를 다 아는 봇"으로 놓고 굴리기 때문에 "주공이 모르고
  // 쏠 수 있다"는 위험 자체를 값으로 못 매긴다(1500라운드에서 11번 감지 중 2번만
  // 수락했다). 사람 주공이 앉는 실제 판에서 조커가 헛되이 끌려 나가는 걸 막으려면
  // 여기서는 그냥 쓰는 게 맞다. 무늬만 후보 중 제일 좋은 걸로 고른다.
  if (!declarerThreat) return null;
  const suit = _jokerSuitAgainstDeclarer(game, botId);
  if (suit) {
    return { type: 'play_card', cardId: 'mighty_joker', jokerSuit: suit };
  }
  const forced = _bestPlayAction(game, botId, candidateActions);
  return forced.action || null;
}

/** 아직 한 장도 안 나온 기루다 장수. */
function _unplayedTrumpCount(game) {
  const trump = game.trumpSuit;
  if (!trump || trump === 'no_trump') return 0;
  const played = MightyBotInternals.getPlayedCards(game);
  let out = 0;
  for (const cardId of played) {
    if (cardId === 'mighty_joker') continue;
    if ((getCardInfo(cardId) || {}).suit === trump) out++;
  }
  return 13 - out;
}

/**
 * 조커를 쓸 때 부를 무늬.
 *
 * 조커로 리드하면 다들 부른 무늬를 따라내야 하고, 트릭은 조커가 가져간다.
 * 그러니 "주공이 무엇을 버리게 만들 것인가" 를 고르는 일이다.
 *
 *   기루다가 6장 이상 남았으면 → 기루다.
 *     아직 흔하니 한 장 빼도 아깝지 않고, 야당 기루다까지 같이 훑는다. 단
 *     주공의 기루다가 탑카드뿐이면 부르지 않는다 — 물패를 빼려던 게 주공의
 *     제일 좋은 카드를 빼는 게 된다.
 *   6장 미만이면 → 주공이 제일 값없는 카드를 낼 무늬.
 *     기루다가 귀해진 판에서 주공 기루다를 뽑아내면 손해다. 점수 없는 낮은
 *     카드가 나올 무늬로 부른다.
 */
function _jokerSuitAgainstDeclarer(game, botId) {
  const trump = game.trumpSuit;
  if (!trump || trump === 'no_trump') return null;
  const declarerHand = game.hands[game.declarer] || [];
  if (declarerHand.length === 0) return null;

  const mightyCard = game.getMightyCard();
  // 우리 편 손에서 끌려 나오면 안 되는 카드.
  //
  // 마이티는 판을 가져올 카드고, 프렌드 카드는 그게 나오는 순간 프렌드가
  // 공개된다 — 프렌드 카드가 마이티인 판(♠A 프렌즈)에서 스페이드를 부르면
  // 둘 다 한 번에 날아간다. 조커로 무늬를 부르는 건 상대에게 무엇을 내게
  // 할지 고르는 일인데, 그러다 우리 것을 빼내면 안 된다.
  const protect = new Set([mightyCard, game.friendCard]);

  // 주공이 그 무늬에서 낼 수밖에 없는 카드 = 가진 것 중 제일 낮은 것.
  // 지켜야 할 카드밖에 없는 무늬는 아예 후보에서 뺀다(null).
  const forcedCard = (suit) => {
    let worst = null;
    for (const cardId of declarerHand) {
      if (cardId === 'mighty_joker') continue;
      const info = getCardInfo(cardId) || {};
      if (info.suit !== suit) continue;
      if (protect.has(cardId)) return null;
      if (!worst || RANK_ORDER[info.rank] < RANK_ORDER[(getCardInfo(worst) || {}).rank]) {
        worst = cardId;
      }
    }
    return worst;
  };

  // 기루다를 부르는 이유는 야당 기루다를 같이 훑기 위해서다. 일곱 장이
  // 남았어도 그게 전부 우리 편(주공·프렌드) 손에 있으면 훑을 게 없다 —
  // 우리 기루다만 한 장 축내는 셈이라 부를 이유가 없다.
  if (_unplayedTrumpCount(game) >= 6
      && MightyBotInternals.countOpponentTrumps(game, botId) > 0) {
    const card = forcedCard(trump);
    if (card && !MightyBotInternals.isEffectiveTopOfSuit(card, game)) return trump;
  }

  let best = null;
  let bestScore = Infinity;
  for (const suit of SUITS) {
    if (suit === trump) continue;
    const card = forcedCard(suit);
    if (!card) continue;
    if (MightyBotInternals.isEffectiveTopOfSuit(card, game)) continue;
    const info = getCardInfo(card) || {};
    // 점수패를 빼는 건 손해다(우리가 먹는 트릭이라 점수는 우리 것이지만,
    // 주공 손에서 나중에 쓸 카드가 사라진다). 같은 값이면 낮은 카드부터.
    const score = (info.point || 0) * 100 + (RANK_ORDER[info.rank] || 0);
    if (score < bestScore) {
      bestScore = score;
      best = suit;
    }
  }
  return best;
}

/**
 * Rule 9: mighty-friend force-win when team's trick isn't secure.
 *
 * Fires when:
 *   - bot is friend AND friend card == mighty
 *   - declarer led the current trick
 *   - bot has mighty in hand AND it's legal
 *   - team's win is NOT secure: either
 *       (a) the current trick winner is not on declarer's team, OR
 *       (b) the current winner IS on the team but their card isn't an
 *           effective top of its suit AND opp behind exists (so over-cut
 *           is still possible)
 *
 * Forces mighty as the unconditional secure winner. Without this the
 * heuristic falls into `safeSameSuit` / `safeTrump` etc. which use
 * probabilistic safety checks; when those misjudge ruff risk the team
 * loses the trick.
 */
function _mightyFriendForceWinRule(game, botId) {
  if (!game.currentTrick || game.currentTrick.length === 0) return null;
  if (!MightyBotInternals.isFriend(game, botId)) return null;

  const mightyCard = game.getMightyCard();
  if (!mightyCard) return null;
  if (game.friendCard !== mightyCard) return null;

  const hand = game.hands[botId] || [];
  if (!hand.includes(mightyCard)) return null;

  const legal = game.getLegalCards(botId);
  if (!legal || !legal.includes(mightyCard)) return null;

  const declarerLed = game.currentTrick[0].pid === game.declarer;
  if (!declarerLed) return null;

  const currentWinner = MightyBotInternals.getCurrentTrickWinner(game);
  const winnerOnTeam = currentWinner === game.declarer
    || (game.friendRevealed && currentWinner === game.partner);

  if (winnerOnTeam) {
    const winnerCard = MightyBotInternals.getWinnerCardId(game);
    if (winnerCard && MightyBotInternals.isEffectiveTopOfSuit(winnerCard, game)) {
      return null;
    }
    if (!MightyBotInternals.hasOppositionBehind(game, botId)) return null;
  }

  // Don't burn mighty if a safe non-mighty winner is in our legal set.
  // E.g., declarer leads ♣4 trick 1 and we hold ♣A — ♣A is the safe
  // top-of-suit winner; mighty would be over-kill.
  for (const cardId of legal) {
    if (cardId === mightyCard) continue;
    if (cardId === 'mighty_joker') continue;
    if (!MightyBotInternals.canBeatCurrentWinner(game, cardId)) continue;
    if (MightyBotInternals.isSafeFriendWinner(cardId, game, botId)) {
      return null;
    }
  }

  // 위의 "안전한 승리 카드" 검사는 러프를 한 장이라도 맞을 수 있으면 통과하지
  // 못한다. 그래서 첫 트릭처럼 기루다가 하나도 안 빠진 시점에는 리드 무늬
  // 에이스를 들고도 전부 "안전하지 않다"가 되어 마이티가 강제된다. 판돈이 거의
  // 없는 트릭은 그 무늬 최상위로 받고 마이티를 남긴다(휴리스틱과 같은 기준).
  const winningCards = legal.filter(c => MightyBotInternals.canBeatCurrentWinner(game, c));
  if (MightyBotInternals.topOfSuitInsteadOfMighty(game, botId, winningCards)) {
    return null;
  }

  return MightyBotInternals.makePlayAction(mightyCard, game, botId);
}

/**
 * Rule 10: friend conserves points on unsafe declarer-led tricks.
 *
 * Fires when:
 *   - bot is friend, declarer led
 *   - team's win is NOT secure (mirrors rule 9's check)
 *   - trump is active (no ruff risk in NT — heuristic safeSameSuit there
 *     is genuinely safe)
 *   - opp may still hold trump (countOpponentTrumps > 0)
 *   - heuristic's pick is a non-trump non-mighty non-joker POINT card
 *   - bot has at least one non-point legal alternative
 *
 * Returns a play action for the weakest non-point card (preferring
 * non-trump first to keep low trump as a future blocker).
 */
function _friendConservePointsRule(game, botId) {
  if (!game.currentTrick || game.currentTrick.length === 0) return null;
  if (!MightyBotInternals.isFriend(game, botId)) return null;

  const trump = game.trumpSuit;
  if (!trump || trump === 'no_trump') return null;
  if (MightyBotInternals.countOpponentTrumps(game, botId) <= 0) return null;

  const declarerLed = game.currentTrick[0].pid === game.declarer;
  if (!declarerLed) return null;

  const currentWinner = MightyBotInternals.getCurrentTrickWinner(game);
  const winnerOnTeam = currentWinner === game.declarer
    || (game.friendRevealed && currentWinner === game.partner);
  if (winnerOnTeam) {
    const winnerCard = MightyBotInternals.getWinnerCardId(game);
    if (winnerCard && MightyBotInternals.isEffectiveTopOfSuit(winnerCard, game)) {
      return null;
    }
    if (!MightyBotInternals.hasOppositionBehind(game, botId)) return null;
  }

  const heuristicAction = _heuristicPlayAction(game, botId);
  if (!heuristicAction) return null;
  const heuristicCard = heuristicAction.cardId;
  if (!heuristicCard) return null;
  if (heuristicCard === game.getMightyCard()) return null;
  if (heuristicCard === 'mighty_joker') return null;

  const heuristicInfo = getCardInfo(heuristicCard);
  if (!heuristicInfo) return null;
  if (heuristicInfo.suit === trump) return null;
  if (heuristicInfo.point === 0) return null;

  // Trust the heuristic's own safety verdict: if it considers the pick a
  // genuinely safe friend winner (passes `_isSafeFriendWinner`), don't
  // override. This handles trick 1 A leads — no suit has been led yet, so
  // no opp can be inferred void → A is genuinely safe and shouldn't be
  // demoted to a non-point concede.
  if (MightyBotInternals.isSafeFriendWinner(heuristicCard, game, botId)) return null;

  const legal = game.getLegalCards(botId);
  if (!legal || legal.length === 0) return null;
  const mightyCard = game.getMightyCard();

  const nonPointLegal = legal.filter(c => {
    if (c === mightyCard) return false;
    if (c === 'mighty_joker') return false;
    const info = getCardInfo(c);
    return info && info.point === 0;
  });
  if (nonPointLegal.length === 0) return null;

  const nonTrumpFirst = nonPointLegal.filter(c => getCardInfo(c).suit !== trump);
  const pool = nonTrumpFirst.length > 0 ? nonTrumpFirst : nonPointLegal;
  pool.sort((a, b) => {
    const ra = RANK_ORDER[getCardInfo(a).rank] || 0;
    const rb = RANK_ORDER[getCardInfo(b).rank] || 0;
    return ra - rb;
  });
  const pick = pool[0];

  return MightyBotInternals.makePlayAction(pick, game, botId);
}

/**
 * Rule 11: friend joker-call, but only when the exact rollout says the
 * forced call beats the current oracle lead.
 */
function _friendJokerCallRule(game, botId) {
  if (game.currentTrick && game.currentTrick.length > 0) return null;
  if (!MightyBotInternals.isFriend(game, botId)) return null;

  const trump = game.trumpSuit;
  if (!trump || trump === 'no_trump') return null;
  if (typeof game._currentTrickJokerHasPower !== 'function') return null;
  if (!game._currentTrickJokerHasPower()) return null;

  const jokerCallCard = game.getJokerCallCard();
  if (!jokerCallCard) return null;

  const hand = game.hands[botId] || [];
  if (!hand.includes(jokerCallCard)) return null;

  const legal = game.getLegalCards(botId);
  if (!legal || !legal.includes(jokerCallCard)) return null;

  const opposition = _getOppositionPlayers(game, botId);
  if (!opposition.some(pid => (game.hands[pid] || []).includes('mighty_joker'))) {
    return null;
  }

  return _preferActionOverOracle(game, botId, [
    { type: 'play_card', cardId: jokerCallCard, jokerCall: true },
  ]);
}

/**
 * Rule 13: declarer joker-probe trump.
 * Fires only when declarer leads suited and the top non-mighty trump in
 * hand is NOT the effective top of trump suit (a higher trump still
 * floats). Drops joker declaring trump to drag that gap out. Also fires
 * if declarer has joker but zero non-mighty trumps — same logic, no
 * effective top means the lead has to be the joker.
 */
function _declarerJokerProbeRule(game, botId) {
  if (game.currentTrick && game.currentTrick.length > 0) return null;
  if (botId !== game.declarer) return null;

  const trump = game.trumpSuit;
  if (!trump || trump === 'no_trump') return null;

  if (typeof game._currentTrickJokerHasPower !== 'function') return null;
  if (!game._currentTrickJokerHasPower()) return null;

  const hand = game.hands[botId] || [];
  if (!hand.includes('mighty_joker')) return null;

  const legal = game.getLegalCards(botId);
  if (!legal.includes('mighty_joker')) return null;

  const mightyCard = game.getMightyCard();
  const ranks = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];
  let myTopTrump = null;
  let myTopRankIdx = -1;
  for (const cardId of hand) {
    if (cardId === 'mighty_joker') continue;
    if (cardId === mightyCard) continue;
    const info = getCardInfo(cardId);
    if (!info || info.suit !== trump) continue;
    const idx = ranks.indexOf(info.rank);
    if (idx > myTopRankIdx) { myTopRankIdx = idx; myTopTrump = cardId; }
  }

  if (myTopTrump && MightyBotInternals.isEffectiveTopOfSuit(myTopTrump, game)) {
    return null;
  }
  if (MightyBotInternals.noRealOppTrumpLeft(game, botId)) {
    return null;
  }

  return { type: 'play_card', cardId: 'mighty_joker', jokerSuit: trump };
}

/**
 * Rule 14: declarer saves mighty until trump is drained.
 * When declarer leads suited with both mighty AND a non-mighty trump
 * that IS the effective top of trump suit, lead the trump (drain) first
 * instead of mighty. Mighty's win is preserved for later.
 */
function _declarerSaveMightyRule(game, botId) {
  if (game.currentTrick && game.currentTrick.length > 0) return null;
  if (botId !== game.declarer) return null;

  const trump = game.trumpSuit;
  if (!trump || trump === 'no_trump') return null;

  const mightyCard = game.getMightyCard();
  const hand = game.hands[botId] || [];
  if (!hand.includes(mightyCard)) return null;

  const legal = game.getLegalCards(botId);
  if (!legal.includes(mightyCard)) return null;

  if (MightyBotInternals.noRealOppTrumpLeft(game, botId)) return null;

  const ranks = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];
  let trumpLead = null;
  let topIdx = -1;
  for (const cardId of hand) {
    if (cardId === 'mighty_joker') continue;
    if (cardId === mightyCard) continue;
    const info = getCardInfo(cardId);
    if (!info || info.suit !== trump) continue;
    const idx = ranks.indexOf(info.rank);
    if (idx > topIdx) { topIdx = idx; trumpLead = cardId; }
  }
  if (!trumpLead) return null;
  if (!MightyBotInternals.isEffectiveTopOfSuit(trumpLead, game)) return null;
  if (!legal.includes(trumpLead)) return null;

  return MightyBotInternals.makePlayAction(trumpLead, game, botId);
}

/**
 * 점수 걸린 트릭을 확실히 먹을 수 있으면 먹는다.
 *
 * 유저 리포트: 기루다 클로버, 주공이 1트릭 초구로 ♥K 를 냈는데 바로 뒷자리
 * 야당이 ♥A 를 들고도 안 냈다. 롤아웃 오라클은 "에이스를 아꼈다가 더 큰 트릭을
 * 먹는다"를 곧잘 고르는데, 눈앞의 점수를 확실히 가져올 수 있으면 그게 먼저다.
 * 아껴 둔 에이스가 나중에 그 값을 하리라는 보장은 없고, 지금 안 먹으면 그
 * 점수는 상대 것이 된다.
 *
 * 조건은 셋뿐이다 — (1) 지금 이기고 있는 사람이 상대편, (2) 트릭에 점수가
 * 깔려 있음, (3) 마이티/조커가 아닌 카드로 뒤에서 아무도 못 받아치는 승리가
 * 가능함. 마이티·조커를 빼는 건 그 둘은 "확실한 승리"가 아니라 낭비 판단이
 * 따로 필요해서다(9·10번 룰).
 *
 * 판돈 0점짜리 트릭은 건드리지 않는다. 그건 에이스를 아끼는 게 맞다.
 * 엔드게임 솔버는 이 룰보다 먼저 돌아 정확한 수를 그대로 낸다.
 */
function _takeSurePointTrickRule(game, botId) {
  if (game.state !== 'playing') return null;
  if (!game.currentTrick || game.currentTrick.length === 0) return null;

  const winner = MightyBotInternals.getCurrentTrickWinner(game);
  if (!winner || winner === botId) return null;

  // 상대편인지는 봇이 실제로 아는 만큼만 본다. 정부(주공·프렌드)는 서로를
  // 알지만, 야당은 공개 전까지 숨은 프렌드가 누군지 모른다 — 여기서 전지적
  // 정보를 쓰면 야당이 프렌드 정체를 아는 것처럼 두게 된다.
  const botIsGov = _isGovernmentTeam(game, botId);
  const winnerIsEnemy = botIsGov
    ? !_isGovernmentTeam(game, winner)
    : MightyBotInternals.isGovernment(game, winner);
  if (!winnerIsEnemy) return null;

  let pot = 0;
  for (const play of game.currentTrick) {
    if (!play || !play.cardId || play.cardId === 'mighty_joker') continue;
    pot += (getCardInfo(play.cardId) || {}).point || 0;
  }
  if (pot === 0) return null;

  const mightyCard = game.getMightyCard();
  const legal = game.getLegalCards(botId) || [];
  const sure = legal.filter(cardId => cardId !== mightyCard
    && cardId !== 'mighty_joker'
    && MightyBotInternals.canBeatCurrentWinner(game, cardId)
    && MightyBotInternals.isSafeFriendWinner(cardId, game, botId));
  if (sure.length === 0) return null;

  // 휴리스틱이 이미 확실한 승리수를 고르고 있으면 그 선택을 존중한다.
  const heuristicAction = _heuristicPlayAction(game, botId);
  if (heuristicAction && sure.includes(heuristicAction.cardId)) return heuristicAction;

  // 아니면 그중 가장 싼 카드로. 기루다는 남겨 두는 게 낫다.
  const trump = game.trumpSuit;
  const cost = (cardId) => {
    const info = getCardInfo(cardId) || {};
    const isTrump = trump && trump !== 'no_trump' && info.suit === trump;
    return (isTrump ? 100 : 0) + (RANK_ORDER[info.rank] || 0);
  };
  const pick = sure.slice().sort((a, b) => cost(a) - cost(b))[0];
  return MightyBotInternals.makePlayAction(pick, game, botId);
}

/**
 * 프렌드가 조커콜을 들었으면, 그에게 선을 넘기기 전에 주공이 조커를 턴다.
 *
 * 유저 리포트의 뒤집힌 판이다. 주공(봇)이 조커를 들고 프렌즈(사람)가 조커콜
 * 카드를 들고 있으면, 프렌즈가 선을 잡는 순간 조커콜이 날아올 수 있다 —
 * 사람은 같은 편 조커가 어디 있는지 모르고, 야당을 노려 쏜다. 그러면 주공의
 * 조커가 헛되이 끌려 나간다.
 *
 * 그래서 프렌즈가 이 트릭을 먹게 생겼으면 그 자리에서 조커로 덮는다. 트릭은
 * 주공이 가져가고(점수는 어차피 같은 편), 선이 프렌즈에게 안 넘어가니 쏠
 * 기회 자체가 없어지며, 조커는 값을 하고 빠진다.
 *
 * 따라내는 자리에서만 걸린다 — 무늬를 부르지 않으므로 우리 편 마이티나
 * 프렌드 카드를 끌어낼 위험이 없다.
 *
 * 1트릭은 조커에 힘이 없어(_currentTrickJokerHasPower) 저절로 빠진다.
 */
function _declarerSpendJokerBeforeFriendLeadRule(game, botId) {
  if (game.state !== 'playing') return null;
  if (!game.currentTrick || game.currentTrick.length === 0) return null;
  if (botId !== game.declarer) return null;

  if (typeof game._currentTrickJokerHasPower !== 'function') return null;
  if (!game._currentTrickJokerHasPower()) return null;

  const legal = game.getLegalCards(botId) || [];
  if (!legal.includes('mighty_joker')) return null;
  if (!MightyBotInternals.canBeatCurrentWinner(game, 'mighty_joker')) return null;

  // 이 트릭을 먹게 생긴 사람이 프렌드인가.
  const winner = MightyBotInternals.getCurrentTrickWinner(game);
  if (!winner || !MightyBotInternals.isFriend(game, winner)) return null;

  // 그 프렌드가 조커콜 카드를 들고 있어야 위협이다.
  const jokerCallCard = game.getJokerCallCard();
  if (!jokerCallCard) return null;
  if (!(game.hands[winner] || []).includes(jokerCallCard)) return null;

  return MightyBotInternals.makePlayAction('mighty_joker', game, botId);
}

// 하드 룰은 순서가 곧 우선순위다. 이름을 같이 들고 있는 이유는 어떤 룰이
// 수를 냈는지 추적할 수 있어야 시뮬레이션에서 원인을 짚을 수 있어서다
// (global.__mightyRuleTrace).
const HARD_RULES = [
  ['friendCardReveal', _friendCardRevealRule],
  // declarerSavesAllyWin 보다 앞이다. 그 룰은 "아군이 이기는 트릭은 덮지
  // 말고 버려라" 인데, 이건 그 예외다 — 덮는 이유가 트릭이 아니라 조커를
  // 털어 조커콜을 피하는 것이라서.
  ['declarerSpendJokerBeforeFriendLead', _declarerSpendJokerBeforeFriendLeadRule],
  ['declarerSavesAllyWin', _declarerSavesAllyWinRule],
  ['friendSafeWinner', _friendSafeWinnerRule],
  ['friendJokerCall', _friendJokerCallRule],
  ['mightyFriendForceWin', _mightyFriendForceWinRule],
  ['friendConservePoints', _friendConservePointsRule],
  ['declarerSaveMighty', _declarerSaveMightyRule],
  ['declarerJokerProbe', _declarerJokerProbeRule],
  ['friendJokerLead', _friendJokerLeadRule],
  ['friendSuitedTopCash', _friendSuitedTopCashRule],
  ['friendDrawTrump', _friendDrawTrumpRule],
  ['friendNTLead', _friendNTLeadRule],
  ['friendNTFollowDumpHigh', _friendNTFollowDumpHighRule],
  ['friendDeclarerSecure', _friendDeclarerSecureRule],
  ['friendNoSafeWinner', _friendNoSafeWinnerRule],
  ['takeSurePointTrick', _takeSurePointTrickRule],
  ['cantWinDefer', _cantWinDeferRule],
  ['preserveWeakJoker', _preserveWeakJokerRule],
  ['govLeadNoOppTrump', _govLeadNoOppTrumpRule],
];

function _applyHardRules(game, botId) {
  if (game.state !== 'playing' || game.currentPlayer !== botId) return null;

  for (const [name, rule] of HARD_RULES) {
    const action = rule(game, botId);
    if (action) {
      if (typeof global.__mightyRuleTrace === 'function') {
        global.__mightyRuleTrace(name, game, botId, action);
      }
      return action;
    }
  }
  return null;
}

// Opposition lead censor — guards against oracle picking a trump-suit lead
// when the bot is on the defending side and the lead has no guaranteed
// upside. Three pass-through conditions (Option B):
//   (a) Lead card is the mighty card (always wins the trick).
//   (b) Lead card is the effective top of the trump suit (mighty already
//       played + bot holds the highest remaining trump).
//   (c) Declarer team has ≤1 trumps left (so this lead drains them dry).
// Otherwise replace the oracle's trump lead with the heuristic's non-trump
// lead. This avoids the common "야당이 괜히 기루다 던져서 declarer 무료 회수"
// failure mode where oracle's perfect-info eval picks a marginal trump lead.
function _oppositionTrumpLeadCensorRule(game, botId, oracleAction) {
  if (game.state !== 'playing' || game.currentPlayer !== botId) return null;
  if (!game.currentTrick || game.currentTrick.length !== 0) return null;
  if (!game.trumpSuit || game.trumpSuit === 'no_trump') return null;
  if (_isGovernmentTeam(game, botId)) return null;
  if (!oracleAction || oracleAction.type !== 'play_card') return null;

  const cardId = oracleAction.cardId;
  if (!cardId || cardId === 'mighty_joker') return null;

  const mightyCard = game.getMightyCard();
  if (cardId === mightyCard) return null; // (a) mighty lead is always fine

  const info = getCardInfo(cardId);
  if (!info || info.suit !== game.trumpSuit) return null;

  // (b) effective top of trump suit — no higher trump remains
  if (MightyBotInternals.isEffectiveTopOfSuit(cardId, game)) return null;

  // (c) declarer team is nearly trump-empty — this lead drains them
  const oppTrumpsLeft = MightyBotInternals.countOpponentTrumps(game, botId);
  if (oppTrumpsLeft <= 1) return null;

  // Not advantageous — substitute the heuristic's lead, which already
  // explicitly avoids trump for opposition (only its longest-suit fallback
  // can pick trump; verify before swapping).
  const alt = _heuristicPlayAction(game, botId);
  if (!alt) return null;
  if (alt.cardId === cardId) return null;
  if (alt.cardId !== 'mighty_joker') {
    const altInfo = getCardInfo(alt.cardId);
    if (altInfo && altInfo.suit === game.trumpSuit) return null;
  }
  return alt;
}

/**
 * 마이티 낭비 검열 — 오라클이 따라내기로 마이티를 고를 때, 판돈이 거의 없는
 * 트릭이면 그 무늬 최상위 카드로 바꾼다.
 *
 * 오라클은 모든 손패를 보고 계산하기 때문에 "여기서 ♠K 는 어차피 러프당한다"
 * 까지 알고 마이티로 덮는다. 계산상으론 트릭을 확실히 가져오지만, 판돈 0~1점
 * 짜리 첫 트릭에서 게임 최강 카드를 쓰는 건 남는 장사가 아니다 — 최상위가
 * 잘려도 잃는 건 몇 점이고, 마이티를 남기면 나중에 큰 트릭을 확실히 가져온다.
 * 게다가 자리에서 보는 사람 눈에는 그냥 최강 카드를 버린 걸로 보인다.
 *
 * 판돈이 커졌거나 손패가 얼마 안 남았으면(= 마이티를 쓸 트릭이 없으면)
 * 헬퍼가 null 을 돌려주므로 오라클 판단을 그대로 둔다.
 */
function _mightyWasteCensorRule(game, botId, oracleAction) {
  if (game.state !== 'playing' || game.currentPlayer !== botId) return null;
  if (!game.currentTrick || game.currentTrick.length === 0) return null;
  if (!oracleAction || oracleAction.type !== 'play_card') return null;
  if (oracleAction.cardId !== game.getMightyCard()) return null;

  const legal = game.getLegalCards(botId) || [];
  const winningCards = legal.filter(c => MightyBotInternals.canBeatCurrentWinner(game, c));
  const alt = MightyBotInternals.topOfSuitInsteadOfMighty(game, botId, winningCards);
  if (!alt) return null;

  return MightyBotInternals.makePlayAction(alt, game, botId);
}

/**
 * 점수 헌납 검열 — 오라클이 "어차피 못 이기는 트릭"에 점수 카드를 버리려 하면
 * 값싼 카드로 바꾼다. 롤아웃 평가가 1점짜리 차이를 자주 놓치는데, 상대가
 * 가져갈 트릭에 K 를 얹어 주는 건 사람 눈엔 그냥 점수를 갖다 바치는 장면이다.
 * 판단 기준은 휴리스틱과 같은 헬퍼를 쓴다.
 */
function _pointDonationCensorRule(game, botId, oracleAction) {
  if (game.state !== 'playing' || game.currentPlayer !== botId) return null;
  if (!oracleAction || oracleAction.type !== 'play_card') return null;
  const alt = MightyBotInternals.cheapDiscardInsteadOfPoint(game, botId, oracleAction.cardId);
  if (!alt) return null;
  return MightyBotInternals.makePlayAction(alt, game, botId);
}

/**
 * 마이티 강제 유도 검열 — 프렌드가 선을 잡았는데 오라클이 마이티 무늬를
 * 돌리려 하고, 주공의 그 무늬 보유가 마이티 한 장뿐이면 다른 리드로 바꾼다.
 * 그 무늬를 돌리는 순간 주공은 팔로우할 카드가 없어 마이티를 버려야 한다.
 * 좁은 경우(loneMighty)만 개입한다 — 넓은 회피 규칙까지 오라클에 강제하면
 * 손대는 범위가 너무 커진다.
 */
function _mightySuitLeadCensorRule(game, botId, oracleAction) {
  if (game.state !== 'playing' || game.currentPlayer !== botId) return null;
  if (!game.currentTrick || game.currentTrick.length !== 0) return null;
  if (!oracleAction || oracleAction.type !== 'play_card') return null;

  const cardId = oracleAction.cardId;
  if (!cardId || cardId === 'mighty_joker') return null;
  const avoid = MightyBotInternals.loneMightySuitToAvoidLeading(game, botId);
  if (!avoid) return null;
  const info = getCardInfo(cardId);
  if (!info || info.suit !== avoid) return null;

  // 휴리스틱은 같은 회피 규칙을 이미 반영한다. 그래도 그 무늬를 고르면
  // (다른 리드가 없다는 뜻이므로) 오라클 판단을 그대로 둔다.
  const alt = _heuristicPlayAction(game, botId);
  if (!alt || alt.type !== 'play_card' || !alt.cardId) return null;
  if (alt.cardId === cardId) return null;
  if (alt.cardId !== 'mighty_joker') {
    const altInfo = getCardInfo(alt.cardId);
    if (!altInfo || altInfo.suit === avoid) return null;
  }
  return alt;
}

/**
 * 현장 진단 — NT 에서 프렌드가 리드했는데, 같은 무늬에 더 높은 카드를 들고
 * 있으면서 낮은 카드를 냈을 때 그 순간 상태를 통째로 찍는다.
 *
 * 유저가 "부른 문양을 K 두고 Q 부터 낸다"고 제보했는데 자가대국·재구성으로는
 * 재현이 안 됐다(조커 프렌드/구버전/자기친구 세 가설 모두 ♦Q 가 안 나옴).
 * 실제 판에서 잡아야 원인을 짚을 수 있어서, MIGHTY_DIAG_NT_LEAD=1 일 때만 켠다.
 */
const NT_LEAD_DIAG = process.env.MIGHTY_DIAG_NT_LEAD === '1';

function _diagNtFriendLead(game, botId, action, path) {
  try {
    if (!action || action.type !== 'play_card' || !action.cardId) return;
    if (game.state !== 'playing') return;
    if (game.currentTrick && game.currentTrick.length !== 0) return;
    if (game.trumpSuit && game.trumpSuit !== 'no_trump') return;
    if (!MightyBotInternals.isFriend(game, botId)) return;
    if (action.cardId === 'mighty_joker') return;

    const info = getCardInfo(action.cardId);
    if (!info) return;
    const hand = game.hands[botId] || [];
    const higher = hand.filter((c) => {
      if (c === 'mighty_joker' || c === action.cardId) return false;
      const ci = getCardInfo(c);
      return ci && ci.suit === info.suit
        && (RANK_ORDER[ci.rank] || 0) > (RANK_ORDER[info.rank] || 0);
    });
    if (higher.length === 0) return;

    const strip = (x) => String(x).replace(/mighty_/g, '');
    console.log('[DIAG-NTLEAD] ' + JSON.stringify({
      path,
      bot: botId,
      played: strip(action.cardId),
      higherInHand: higher.map(strip),
      declarer: game.declarer,
      partner: game.partner,
      friendCard: strip(game.friendCard),
      friendRevealed: game.friendRevealed,
      bid: game.currentBid,
      hands: Object.fromEntries(Object.entries(game.hands)
        .map(([k, v]) => [k, (v || []).map(strip)])),
      tricks: (game.tricks || []).map(t => ({
        leader: t.leader,
        leadSuit: t.leadSuit,
        winner: t.winner,
        cards: (t.cards || []).map(x => `${x.pid}:${strip(x.cardId)}`),
      })),
    }));
  } catch (e) { /* 진단이 게임을 막으면 안 된다 */ }
}

function decide(game, botId) {
  const __diagOn = process.env.DIAG !== '0';
  const __diagSlowMs = _diagNumberEnv('DIAG_BOT_SLOW_MS', 100);
  const __diagStart = __diagOn ? process.hrtime.bigint() : 0n;
  let __settingMs = 0;
  let __solverMs = 0;
  let __rulesMs = 0;
  let __oracleMs = 0;
  let __censorMs = 0;
  let __path = 'none';
  let __solverNodes = '-';

  const __finish = (action) => {
    if (NT_LEAD_DIAG) _diagNtFriendLead(game, botId, action, __path);
    if (typeof global.__mightyPathTrace === 'function') {
      global.__mightyPathTrace(__path, game, botId, action);
    }
    if (__diagOn) {
      const __totalMs = _diagElapsedMs(__diagStart);
      if (__totalMs > __diagSlowMs) {
        const hand = (game.hands && game.hands[botId] && game.hands[botId].length) || 0;
        const trick = (game.currentTrick && game.currentTrick.length) || 0;
        const actionInfo = action
          ? `${action.type || '-'}:${action.cardId || action.points || action.suit || action.pass || '-'}`
          : 'null';
        console.log(`[DIAG] mixoracle-detail ${__totalMs.toFixed(0)}ms bot=${botId} phase=${game.state} path=${__path} hand=${hand} maxHand=${_maxActiveHandSize(game)} trick=${trick} setting=${__settingMs.toFixed(0)}ms solver=${__solverMs.toFixed(0)}ms rules=${__rulesMs.toFixed(0)}ms oracle=${__oracleMs.toFixed(0)}ms censor=${__censorMs.toFixed(0)}ms nodes=${__solverNodes} action=${actionInfo}`);
      }
    }
    return action;
  };

  // Setting (세팅) declaration takes precedence over every other decision
  // path: the server-side `_canDeclareSetting` check already proves the
  // remaining hand wins unconditionally, so skipping to the round end and
  // sweeping all leftover point cards is strictly better than playing them
  // out one trick at a time. Mirrors the heuristic decidePlay's first
  // gate — kept here too because mixoracle reaches the oracle play path
  // without going through that gate.
  const __settingStart = __diagOn ? process.hrtime.bigint() : 0n;
  const canDeclareSetting = game.state === 'playing'
      && game.currentPlayer === botId
      && game.currentTrick
      && game.currentTrick.length === 0
      && typeof game._canDeclareSetting === 'function'
      && game._canDeclareSetting(botId);
  if (__diagOn) __settingMs = _diagElapsedMs(__settingStart);
  if (canDeclareSetting) {
    __path = 'setting';
    return __finish({ type: 'declare_setting' });
  }

  // Exact endgame solver: once few cards remain the position is small enough to
  // solve perfectly (full-information alpha-beta). It supersedes both the hard
  // rules and the rollout oracle there — those are heuristics, this is optimal.
  if (_solverEnabledFor(botId)) {
    const __solverStart = __diagOn ? process.hrtime.bigint() : 0n;
    const solved = endgameSolver.solve(game, botId);
    if (__diagOn) __solverMs = _diagElapsedMs(__solverStart);
    if (solved) {
      __path = 'solver';
      __solverNodes = solved.__nodes ?? '-';
      return __finish(solved);
    }
  }

  const __rulesStart = __diagOn ? process.hrtime.bigint() : 0n;
  const ruled = _applyHardRules(game, botId);
  if (__diagOn) __rulesMs = _diagElapsedMs(__rulesStart);
  if (ruled) {
    __path = 'rules';
    return __finish(ruled);
  }

  const __oracleStart = __diagOn ? process.hrtime.bigint() : 0n;
  const oracleAction = oracle.decide(game, botId);
  if (__diagOn) __oracleMs = _diagElapsedMs(__oracleStart);
  const __censorStart = __diagOn ? process.hrtime.bigint() : 0n;
  const censored = _oppositionTrumpLeadCensorRule(game, botId, oracleAction);
  if (__diagOn) __censorMs = _diagElapsedMs(__censorStart);
  if (censored) {
    __path = 'censor';
    return __finish(censored);
  }
  const mightyCensored = _mightyWasteCensorRule(game, botId, oracleAction);
  if (mightyCensored) {
    __path = 'mightyCensor';
    return __finish(mightyCensored);
  }
  const donationCensored = _pointDonationCensorRule(game, botId, oracleAction);
  if (donationCensored) {
    __path = 'donationCensor';
    return __finish(donationCensored);
  }
  const mightySuitCensored = _mightySuitLeadCensorRule(game, botId, oracleAction);
  if (mightySuitCensored) {
    __path = 'mightySuitCensor';
    return __finish(mightySuitCensored);
  }
  __path = 'oracle';
  return __finish(oracleAction);
}

module.exports = { decide };
