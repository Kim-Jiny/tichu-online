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

function _evaluatePlayActionScore(game, botId, action) {
  if (!action || action.type !== 'play_card') return -Infinity;
  const world = game.clone();
  const result = world.handleAction(botId, action);
  if (!result || !result.success) return -Infinity;
  const preScores = { ...game.scores };
  runRollout(world);
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

    const score = _evaluatePlayActionScore(game, botId, action);
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

  const oracleScore = _evaluatePlayActionScore(game, botId, oracleAction);
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
function _friendNTLeadRule(game, botId) {
  if (game.currentTrick && game.currentTrick.length > 0) return null;
  if (!MightyBotInternals.isFriend(game, botId)) return null;

  const trump = game.trumpSuit;
  if (trump && trump !== 'no_trump') return null;

  const hand = game.hands[botId] || [];
  if (hand.length === 0) return null;

  // While the declarer still holds the Mighty, don't recycle its home suit
  // (skipped for mighty/joker-friend designation — handled in the helper).
  const avoidSuit = MightyBotInternals.mightySuitToAvoidLeading(game, botId);

  const tops = [];
  for (const cardId of hand) {
    if (cardId === 'mighty_joker') continue;
    if (!MightyBotInternals.isEffectiveTopOfSuit(cardId, game)) continue;
    if (avoidSuit && getCardInfo(cardId).suit === avoidSuit) continue;
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

  const friendCard = game.friendCard;
  if (!friendCard
      || friendCard === 'no_friend'
      || friendCard === 'first_trick'
      || friendCard === 'mighty_joker'
      || friendCard === game.getMightyCard()) {
    return null;
  }
  const friendInfo = getCardInfo(friendCard);
  if (!friendInfo) return null;
  const friendSuit = friendInfo.suit;
  // Don't feed the called suit back when it IS the Mighty's home suit and the
  // declarer still holds the Mighty (would just burn declarer's Mighty).
  if (avoidSuit && friendSuit === avoidSuit) return null;

  const friendSuitCards = [];
  for (const cardId of hand) {
    if (cardId === 'mighty_joker') continue;
    const info = getCardInfo(cardId);
    if (!info || info.suit !== friendSuit) continue;
    friendSuitCards.push(cardId);
  }
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
  if (!opposition.some(pid => (game.hands[pid] || []).includes(jokerCallCard))) {
    return null;
  }

  const legal = game.getLegalCards(botId);
  if (!legal || !legal.includes('mighty_joker')) return null;

  const candidateActions = SUITS.map(suit => ({
    type: 'play_card',
    cardId: 'mighty_joker',
    jokerSuit: suit,
  }));

  return _preferActionOverOracle(game, botId, candidateActions);
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

function _applyHardRules(game, botId) {
  if (game.state !== 'playing' || game.currentPlayer !== botId) return null;

  const reveal = _friendCardRevealRule(game, botId);
  if (reveal) return reveal;

  const declarerSaveAlly = _declarerSavesAllyWinRule(game, botId);
  if (declarerSaveAlly) return declarerSaveAlly;

  const safeCheapWinner = _friendSafeWinnerRule(game, botId);
  if (safeCheapWinner) return safeCheapWinner;

  const jokerCall = _friendJokerCallRule(game, botId);
  if (jokerCall) return jokerCall;

  const mightyForceWin = _mightyFriendForceWinRule(game, botId);
  if (mightyForceWin) return mightyForceWin;

  const conservePoints = _friendConservePointsRule(game, botId);
  if (conservePoints) return conservePoints;

  const declarerSaveMighty = _declarerSaveMightyRule(game, botId);
  if (declarerSaveMighty) return declarerSaveMighty;

  const declarerJokerProbe = _declarerJokerProbeRule(game, botId);
  if (declarerJokerProbe) return declarerJokerProbe;

  const friendJoker = _friendJokerLeadRule(game, botId);
  if (friendJoker) return friendJoker;

  const suitedTopCash = _friendSuitedTopCashRule(game, botId);
  if (suitedTopCash) return suitedTopCash;

  const drawTrump = _friendDrawTrumpRule(game, botId);
  if (drawTrump) return drawTrump;

  const ntLead = _friendNTLeadRule(game, botId);
  if (ntLead) return ntLead;

  const ntFollowDumpHigh = _friendNTFollowDumpHighRule(game, botId);
  if (ntFollowDumpHigh) return ntFollowDumpHigh;

  const secureFollow = _friendDeclarerSecureRule(game, botId);
  if (secureFollow) return secureFollow;

  const noSafeWinner = _friendNoSafeWinnerRule(game, botId);
  if (noSafeWinner) return noSafeWinner;

  const cantWin = _cantWinDeferRule(game, botId);
  if (cantWin) return cantWin;

  const weakJoker = _preserveWeakJokerRule(game, botId);
  if (weakJoker) return weakJoker;

  const govLeadDry = _govLeadNoOppTrumpRule(game, botId);
  if (govLeadDry) return govLeadDry;

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

function decide(game, botId) {
  // Setting (세팅) declaration takes precedence over every other decision
  // path: the server-side `_canDeclareSetting` check already proves the
  // remaining hand wins unconditionally, so skipping to the round end and
  // sweeping all leftover point cards is strictly better than playing them
  // out one trick at a time. Mirrors the heuristic decidePlay's first
  // gate — kept here too because mixoracle reaches the oracle play path
  // without going through that gate.
  if (game.state === 'playing'
      && game.currentPlayer === botId
      && game.currentTrick
      && game.currentTrick.length === 0
      && typeof game._canDeclareSetting === 'function'
      && game._canDeclareSetting(botId)) {
    return { type: 'declare_setting' };
  }

  // Exact endgame solver: once few cards remain the position is small enough to
  // solve perfectly (full-information alpha-beta). It supersedes both the hard
  // rules and the rollout oracle there — those are heuristics, this is optimal.
  if (_solverEnabledFor(botId)) {
    const solved = endgameSolver.solve(game, botId);
    if (solved) return solved;
  }

  const ruled = _applyHardRules(game, botId);
  if (ruled) return ruled;

  const oracleAction = oracle.decide(game, botId);
  const censored = _oppositionTrumpLeadCensorRule(game, botId, oracleAction);
  if (censored) return censored;
  return oracleAction;
}

module.exports = { decide };
