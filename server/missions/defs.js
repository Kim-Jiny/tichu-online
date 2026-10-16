'use strict';

/**
 * 미션·토큰 정의. 숫자는 전부 여기 한 곳에서 조정한다.
 *
 * 토큰은 미션으로만 얻고(돈으로도 골드로도 못 산다) 토큰 상점에서만 쓴다.
 * 판정은 서버가 한다 — 앱이 "깼다"고 알리는 길은 없다.
 */

/**
 * 하루(KST)에 고를 수 있는 미션 수. 하루에 이만큼만 고를 수 있으니 토큰을 따로
 * 막지 않아도 하루 획득량은 자연히 정해진다. 한 번 고른 미션은 바꿀 수 없다(포기 기능 없음).
 */
const DAILY_PICKS = 3;

/**
 * 고른 미션이 유효한 날 수(고른 날 포함). 1 이면 당일 미션 — 고른 날(KST) 안에 깨야 하고,
 * 자정이 지나면 사라져 다음 날은 진행도 0 에서 새로 시작한다.
 */
const MISSION_LIFETIME_DAYS = 1;

/** 게임별로 하루에 보여 주는 후보 수. */
const OFFERS_PER_GAME = 3;

/** 게임별 새로고침 가능 횟수(하루). */
const DAILY_REROLLS = 1;

/** 하루 1개 이상 달성한 날이 이 일수만큼 이어지면 보너스. */
const STREAK_BONUS_DAYS = 7;
const STREAK_BONUS_TOKENS = 5;

/**
 * 미션으로 인정하려면 방에 사람이 이 수 이상이어야 한다(봇 방 파밍 방지).
 *
 * TODO(배포 전에 반드시): 지금은 혼자 봇과 하며 테스트하느라 1 로 풀어 두었다.
 * 정식 값은 2 — 환경변수 MISSION_MIN_HUMANS 로도 바꿀 수 있다.
 */
const MIN_HUMANS = Math.max(1, parseInt(process.env.MISSION_MIN_HUMANS, 10) || 1);

const GAMES = ['tichu', 'mighty', 'skull_king', 'love_letter'];

/**
 * event: 서버가 판정하는 이벤트 이름(missions.js 의 record 호출과 맞춘다).
 * target: 이벤트가 몇 번 일어나야 하는지.
 * tier: 1 쉬움 · 2 보통 · 3 어려움(토큰은 tokens 에 직접 적는다).
 */
const MISSIONS = [
  // ── 티츄 ──
  { key: 'tichu_play', game: 'tichu', tier: 2, tokens: 2, event: 'tichu.game_end', target: 5 },
  { key: 'tichu_win',       game: 'tichu', tier: 1, tokens: 1, event: 'tichu.game_win',     target: 1 },
  { key: 'tichu_small',     game: 'tichu', tier: 2, tokens: 2, event: 'tichu.small_success', target: 1 },
  { key: 'tichu_large',     game: 'tichu', tier: 3, tokens: 4, event: 'tichu.large_success', target: 1 },
  { key: 'tichu_onetwo',    game: 'tichu', tier: 2, tokens: 2, event: 'tichu.one_two',      target: 1 },
  { key: 'tichu_dog_finish', game: 'tichu', tier: 3, tokens: 3, event: 'tichu.dog_finish',  target: 1 },
  { key: 'tichu_bomb30',    game: 'tichu', tier: 3, tokens: 3, event: 'tichu.bomb_points',  target: 30 },

  // ── 마이티 ──
  { key: 'mighty_play', game: 'mighty', tier: 2, tokens: 2, event: 'mighty.game_end', target: 5 },
  { key: 'mighty_win',      game: 'mighty', tier: 1, tokens: 1, event: 'mighty.game_win',   target: 1 },
  { key: 'mighty_bid20',    game: 'mighty', tier: 2, tokens: 2, event: 'mighty.bid20_success', target: 1 },
  { key: 'mighty_nt',       game: 'mighty', tier: 3, tokens: 3, event: 'mighty.nt_success', target: 1 },
  { key: 'mighty_all20',    game: 'mighty', tier: 3, tokens: 4, event: 'mighty.declarer_all20', target: 1 },
  { key: 'mighty_friend7',  game: 'mighty', tier: 3, tokens: 3, event: 'mighty.friend_points', target: 7 },

  // ── 스컬킹 ──
  { key: 'sk_play', game: 'skull_king', tier: 2, tokens: 2, event: 'sk.game_end', target: 5 },
  { key: 'sk_win',          game: 'skull_king', tier: 1, tokens: 1, event: 'sk.game_win',   target: 1 },
  { key: 'sk_pirates2',     game: 'skull_king', tier: 3, tokens: 3, event: 'sk.skullking_two_pirates', target: 1 },
  { key: 'sk_mermaid_king', game: 'skull_king', tier: 3, tokens: 4, event: 'sk.mermaid_takes_skullking', target: 1 },
  { key: 'sk_ten_win',      game: 'skull_king', tier: 2, tokens: 2, event: 'sk.win_with_ten', target: 1 },

  // ── 러브레터 ──
  { key: 'll_play', game: 'love_letter', tier: 2, tokens: 2, event: 'll.game_end', target: 5 },
  { key: 'll_win',          game: 'love_letter', tier: 2, tokens: 2, event: 'll.game_win', target: 1 },

  // ── 추가 미션(다양하게) ──
  { key: 'tichu_win2', game: 'tichu', tier: 3, tokens: 3, event: 'tichu.game_win', target: 2 },
  { key: 'tichu_dragon_win', game: 'tichu', tier: 2, tokens: 2, event: 'tichu.dragon_win', target: 1 },
  { key: 'tichu_phoenix_win', game: 'tichu', tier: 2, tokens: 2, event: 'tichu.phoenix_win', target: 2 },
  { key: 'tichu_straight_win', game: 'tichu', tier: 1, tokens: 1, event: 'tichu.straight_win', target: 2 },
  { key: 'tichu_fullhouse_win', game: 'tichu', tier: 1, tokens: 1, event: 'tichu.fullhouse_win', target: 2 },
  { key: 'tichu_steps_win', game: 'tichu', tier: 2, tokens: 2, event: 'tichu.steps_win', target: 1 },
  { key: 'tichu_bomb_play2', game: 'tichu', tier: 2, tokens: 2, event: 'tichu.bomb_played', target: 2 },
  { key: 'tichu_first_out3', game: 'tichu', tier: 2, tokens: 2, event: 'tichu.first_out', target: 3 },
  { key: 'tichu_break_tichu', game: 'tichu', tier: 2, tokens: 2, event: 'tichu.tichu_broken', target: 1 },
  { key: 'mighty_mighty_win', game: 'mighty', tier: 1, tokens: 1, event: 'mighty.mighty_win', target: 1 },
  { key: 'mighty_joker_win', game: 'mighty', tier: 2, tokens: 2, event: 'mighty.joker_win', target: 1 },
  { key: 'mighty_trump3', game: 'mighty', tier: 1, tokens: 1, event: 'mighty.trump_win', target: 3 },
  { key: 'mighty_point_trick', game: 'mighty', tier: 2, tokens: 2, event: 'mighty.point_trick', target: 1 },
  { key: 'mighty_declarer_success', game: 'mighty', tier: 2, tokens: 2, event: 'mighty.declarer_success', target: 1 },
  { key: 'mighty_defend', game: 'mighty', tier: 2, tokens: 2, event: 'mighty.defend', target: 1 },
  { key: 'mighty_friend_success', game: 'mighty', tier: 2, tokens: 2, event: 'mighty.friend_success', target: 1 },
  { key: 'mighty_bid18', game: 'mighty', tier: 3, tokens: 3, event: 'mighty.bid18_success', target: 1 },
  { key: 'sk_bid_hit3', game: 'skull_king', tier: 2, tokens: 2, event: 'sk.bid_hit', target: 3 },
  { key: 'sk_zero_hit', game: 'skull_king', tier: 2, tokens: 2, event: 'sk.zero_hit', target: 1 },
  { key: 'sk_pirate_win2', game: 'skull_king', tier: 1, tokens: 1, event: 'sk.pirate_win', target: 2 },
  { key: 'sk_mermaid_win', game: 'skull_king', tier: 1, tokens: 1, event: 'sk.mermaid_win', target: 1 },
  { key: 'sk_skullking_win2', game: 'skull_king', tier: 2, tokens: 2, event: 'sk.skullking_win', target: 2 },
  { key: 'll_guard_hit', game: 'love_letter', tier: 1, tokens: 1, event: 'll.guard_hit', target: 1 },
  { key: 'll_baron_win', game: 'love_letter', tier: 1, tokens: 1, event: 'll.baron_win', target: 1 },
  { key: 'll_round_win3', game: 'love_letter', tier: 2, tokens: 2, event: 'll.round_win', target: 3 },
  { key: 'll_last_standing', game: 'love_letter', tier: 2, tokens: 2, event: 'll.last_standing', target: 1 },
  { key: 'll_knock_out3', game: 'love_letter', tier: 3, tokens: 3, event: 'll.knock_out', target: 3 },
];

const MISSION_BY_KEY = new Map(MISSIONS.map((m) => [m.key, m]));

/**
 * 토큰 상점. 전부 30일짜리 기간제이고 영구 상품은 없다.
 * slot 이 같은 상품은 한 번에 하나만 장착한다(말풍선은 기본·상위가 한 칸을 같이 쓴다).
 */
const SHOP_DAYS = 30;
const PRODUCT_KINDS = {
  room_highlight: { price: 50, slot: 'room_highlight' },
  bubble_basic: { price: 60, slot: 'bubble' },
  bubble_premium: { price: 100, slot: 'bubble' },
};
const VARIANTS_PER_KIND = 3;
const PRODUCTS = [];
for (const [kind, { price, slot }] of Object.entries(PRODUCT_KINDS)) {
  for (let v = 1; v <= VARIANTS_PER_KIND; v++) {
    PRODUCTS.push({ key: `${kind}_${v}`, kind, slot, variant: v, price, days: SHOP_DAYS });
  }
}
const PRODUCT_BY_KEY = new Map(PRODUCTS.map((p) => [p.key, p]));

module.exports = {
  DAILY_PICKS,
  MISSION_LIFETIME_DAYS,
  OFFERS_PER_GAME,
  DAILY_REROLLS,
  STREAK_BONUS_DAYS,
  STREAK_BONUS_TOKENS,
  MIN_HUMANS,
  GAMES,
  MISSIONS,
  MISSION_BY_KEY,
  SHOP_DAYS,
  PRODUCT_KINDS,
  PRODUCTS,
  PRODUCT_BY_KEY,
};
