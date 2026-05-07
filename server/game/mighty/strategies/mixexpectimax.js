'use strict';

/**
 * mixexpectimax strategy.
 *
 * Hybrid: a small set of explicit "hard rules" override the search policy,
 * everything else falls through to `expectimax_smart` unchanged.
 *
 * Rationale:
 *   The expectimax_smart depth-2 / 40-sample search is solid in aggregate
 *   but its rollout signal is too noisy in a few specific spots that the
 *   heuristic already gets right. We layer those in as hard rules, then
 *   defer to the search for everything else.
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
 *   8) Mighty-friend proactive joker lead — when bot is mighty-friend
 *      (friend card == mighty), holds joker, does NOT hold the joker-call
 *      card (so opp can pull joker any time), is leading, and joker still
 *      has power on the trick: cash joker now to dodge 조커콜.
 *      Declared suit:
 *        - 6+ trump-suit cards still outside our hand → declare trump
 *          (drain opp's trump while we're at it)
 *        - else → declare 부른문양 (= mighty's suit) for team coordination
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
 *  11) Friend's joker-call to kill opp's joker. Strict gating — we
 *      only fire when ALL of the following hold:
 *        1. non-NT bidding
 *        2. declarer does NOT hold the joker (it's not on our team)
 *        3. bot does NOT hold the joker (we'd kill our own)
 *        4. some opp player actually holds the joker
 *        5. sacrificing this lead doesn't break our plan — bot has no
 *           "fresh-suit effective top" we'd otherwise want to cash
 *        6. joker is an imminent threat — at least 4 tricks already
 *           done, so opp's joker is about to take a real trick
 *        7. bot has a meaningful follow-up — multiple legal cards
 *           (not single-card forced lead)
 *      Without rules 5-7 the call sacrifices tempo for a kill that
 *      isn't urgent enough; benchmark showed it dropped declarer
 *      success rate vs heuristic baseline.
 */

const expectimaxSmart = require('./expectimax_smart');
const MightyBotInternals = require('../MightyBot');
const { getCardInfo, RANK_ORDER } = require('../MightyDeck');

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

  const action = MightyBotInternals.decideMightyBotAction(game, botId, 'heuristic');
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

  const tops = [];
  for (const cardId of hand) {
    if (cardId === 'mighty_joker') continue;
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

  const tops = [];
  for (const cardId of hand) {
    if (cardId === 'mighty_joker') continue;
    if (cardId === mightyCard) continue;
    const info = getCardInfo(cardId);
    if (!info) continue;
    if (info.suit === trump) continue;
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
 * expectimax_smart doesn't override it with a needless over-cut.
 */
function _friendDeclarerSecureRule(game, botId) {
  if (!game.currentTrick || game.currentTrick.length === 0) return null;
  if (!MightyBotInternals.isFriend(game, botId)) return null;

  const declarerLed = game.currentTrick[0].pid === game.declarer;
  if (!declarerLed) return null;

  const currentWinner = MightyBotInternals.getCurrentTrickWinner(game);
  if (currentWinner !== game.declarer) return null;

  const winnerCard = MightyBotInternals.getWinnerCardId(game);
  if (!winnerCard) return null;
  if (!MightyBotInternals.isEffectiveTopOfSuit(winnerCard, game)) return null;

  const action = MightyBotInternals.decideMightyBotAction(game, botId, 'heuristic');
  if (!action || action.type !== 'play_card') return null;
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
  if (typeof game._currentTrickJokerHasPower !== 'function') return null;
  if (game._currentTrickJokerHasPower()) return null;

  const legal = game.getLegalCards(botId);
  if (!legal || legal.length <= 1) return null;
  if (!legal.includes('mighty_joker')) return null;

  const action = MightyBotInternals.decideMightyBotAction(game, botId, 'heuristic');
  if (!action || action.type !== 'play_card') return null;
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

  const action = MightyBotInternals.decideMightyBotAction(game, botId, 'heuristic');
  if (!action || action.type !== 'play_card') return null;
  return action;
}

/**
 * Rule 8: friend's proactive joker lead (all friend variants).
 *
 * Friend's joker isn't a "win this trick" card — it's a "return lead to
 * declarer / open a favorable suit flow" card. The fire condition and
 * suit pick follow the user's friend-joker spec.
 *
 * Fires when:
 *   - bot is friend AND about to lead
 *   - joker has power on this trick (no point burning a weak joker)
 *   - bot holds joker AND it's legal
 *   - bot does NOT hold the joker-call card (Case 1-1 says save joker
 *     when we DO hold it; Case 1-2 says use it actively when we don't)
 *
 * Declared-suit priority:
 *   2-1 trump, if opp likely still holds trump → drain it
 *   2-3 friend-call suit (the suit declarer named when calling friend)
 *   2-4 declarer's likely-strong suit (declarer led K/Q earlier with the
 *       higher card still unplayed → infer they hold it)
 *   2-5 my best continuation suit (delegated to the auto-suit picker
 *       inside makePlayAction → _pickJokerLeadSuit, which scores by
 *       length / effective top / opp-holds-suit / etc.)
 */
function _friendJokerLeadRule(game, botId) {
  if (game.currentTrick && game.currentTrick.length > 0) return null;
  if (!MightyBotInternals.isFriend(game, botId)) return null;

  if (typeof game._currentTrickJokerHasPower !== 'function') return null;
  if (!game._currentTrickJokerHasPower()) return null;

  const hand = game.hands[botId] || [];
  if (!hand.includes('mighty_joker')) return null;

  // Case 1-1: friend has joker-call card → save joker. Fall through.
  const jokerCallCard = game.getJokerCallCard();
  if (jokerCallCard && hand.includes(jokerCallCard)) return null;

  const legal = game.getLegalCards(botId);
  if (!legal || !legal.includes('mighty_joker')) return null;

  let declaredSuit = null;

  // 2-1: opp likely has trump → declare trump to drain it
  const trump = game.trumpSuit;
  const trumpActive = trump && trump !== 'no_trump';
  if (trumpActive && !MightyBotInternals.noRealOppTrumpLeft(game, botId)) {
    declaredSuit = trump;
  }

  // 2-3: friend-call suit (the declarer's signalled suit)
  if (!declaredSuit) {
    declaredSuit = MightyBotInternals.getFriendCardSuit(game);
  }

  // 2-4: declarer's inferred strong suit
  if (!declaredSuit) {
    declaredSuit = MightyBotInternals.declarerStrongSuit(game);
  }

  // 2-5: fall back to the auto-picker (length / effective top / opp-holds)
  if (declaredSuit) {
    return { type: 'play_card', cardId: 'mighty_joker', jokerSuit: declaredSuit };
  }
  return MightyBotInternals.makePlayAction('mighty_joker', game, botId);
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

  const heuristicAction = MightyBotInternals.decideMightyBotAction(game, botId, 'heuristic');
  if (!heuristicAction || heuristicAction.type !== 'play_card') return null;
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
 * Rule 11: friend leads joker-call to kill opp's joker.
 *
 * Fires when:
 *   - bot is friend AND about to lead
 *   - non-NT (joker-call has no effect in NT)
 *   - joker has power on this trick (otherwise the call is empty)
 *   - bot holds the joker-call card AND it's legal
 *   - bot does NOT hold the joker itself (we'd kill our own joker)
 *   - declarer does NOT hold the joker either (same reason — gov-side
 *     joker is on our team)
 *   - some opp player actually holds the joker (the only case where
 *     calling actually accomplishes something — kills the opp threat)
 *
 * Returns a play_card action with `jokerCall: true` flag set.
 */
function _friendJokerCallRule(game, botId) {
  if (game.currentTrick && game.currentTrick.length > 0) return null;
  if (!MightyBotInternals.isFriend(game, botId)) return null;

  // (1) Non-NT bidding.
  const trump = game.trumpSuit;
  if (!trump || trump === 'no_trump') return null;
  if (typeof game._currentTrickJokerHasPower !== 'function') return null;
  if (!game._currentTrickJokerHasPower()) return null;

  const jokerCallCard = game.getJokerCallCard();
  if (!jokerCallCard) return null;

  const hand = game.hands[botId] || [];
  if (!hand.includes(jokerCallCard)) return null;
  // (3) Bot doesn't hold joker.
  if (hand.includes('mighty_joker')) return null;

  // (2) Declarer doesn't hold joker.
  const declarerHand = game.hands[game.declarer] || [];
  if (declarerHand.includes('mighty_joker')) return null;

  const legal = game.getLegalCards(botId);
  if (!legal || !legal.includes(jokerCallCard)) return null;

  // (7) Meaningful follow-up — bot has alternatives, not a single-card
  // forced lead.
  if (legal.length <= 1) return null;

  // (4) Some opp actually holds the joker (perfect-info check; the
  // sampler-side signal inference is a separate concern).
  let oppHasJoker = false;
  for (const pid of game.playerIds) {
    if (pid === botId) continue;
    if (pid === game.declarer) continue;
    if (game.friendRevealed && pid === game.partner) continue;
    if ((game.hands[pid] || []).includes('mighty_joker')) {
      oppHasJoker = true;
      break;
    }
  }
  if (!oppHasJoker) return null;

  // (6) Joker damage is imminent — at least 4 tricks done so opp's
  // joker is about to take a real trick if we don't kill it now.
  if ((game.tricks || []).length < 4) return null;

  // (5) Sacrificing this lead must not break our plan. Proxy: bot has
  // no "fresh-suit effective top" (a non-trump A in a suit nobody has
  // led yet) it would otherwise be cashing. If we DO have one,
  // leading that A is the productive play, not the joker call.
  const mightyCard = game.getMightyCard();
  let hasFreshTop = false;
  for (const cardId of hand) {
    if (cardId === 'mighty_joker') continue;
    if (cardId === mightyCard) continue;
    if (cardId === jokerCallCard) continue;
    const info = getCardInfo(cardId);
    if (!info) continue;
    if (info.suit === trump) continue;
    if (!MightyBotInternals.isEffectiveTopOfSuit(cardId, game)) continue;
    if (MightyBotInternals.suitLedCount(game, info.suit) > 0) continue;
    hasFreshTop = true;
    break;
  }
  if (hasFreshTop) return null;

  return { type: 'play_card', cardId: jokerCallCard, jokerCall: true };
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

  const secureFollow = _friendDeclarerSecureRule(game, botId);
  if (secureFollow) return secureFollow;

  const weakJoker = _preserveWeakJokerRule(game, botId);
  if (weakJoker) return weakJoker;

  const govLeadDry = _govLeadNoOppTrumpRule(game, botId);
  if (govLeadDry) return govLeadDry;

  return null;
}

function decide(game, botId) {
  const ruled = _applyHardRules(game, botId);
  if (ruled) return ruled;
  return expectimaxSmart.decide(game, botId);
}

module.exports = { decide };
