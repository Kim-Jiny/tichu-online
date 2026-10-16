'use strict';

/** 관리자 화면에 보여 줄 한국어 이름. 앱 문구(l10n)와는 별개다 — 운영자가 읽는 용도. */
const MISSION_LABEL_KO = {
  tichu_play: '티츄 5판 하기',
  tichu_win: '티츄 한 판 이기기',
  tichu_small: '스몰 티츄 성공하기',
  tichu_large: '라지 티츄 성공하기',
  tichu_onetwo: '우리 팀이 1·2등 하기',
  tichu_dog_finish: '개 카드로 마무리해 1·2등으로 패 털기',
  tichu_bomb30: '폭탄으로 점수 30점 얻기',
  mighty_play: '마이티 5판 하기',
  mighty_win: '마이티 한 판 이기기',
  mighty_bid20: '비딩 20점으로 성공하기',
  mighty_nt: '노트럼프 비딩으로 성공하기',
  mighty_all20: '여당으로 점수 카드 20장 모두 먹기',
  mighty_friend7: '친구로 참여해 점수 7점 이상 먹기',
  sk_play: '스컬킹 5판 하기',
  sk_win: '스컬킹 한 판 이기기',
  sk_pirates2: '스컬킹으로 해적 두 명 한 번에 잡기',
  sk_mermaid_king: '인어로 스컬킹 잡기',
  sk_ten_win: '숫자 10 카드로 트릭 이기기',
  ll_play: '러브레터 5판 하기',
  ll_win: '러브레터 한 판 이기기',
  tichu_win2: '티츄 2판 이기기',
  tichu_dragon_win: '용으로 트릭 이기기',
  tichu_phoenix_win: '봉황이 든 패로 트릭 2번 이기기',
  tichu_straight_win: '스트레이트로 트릭 2번 이기기',
  tichu_fullhouse_win: '풀하우스로 트릭 2번 이기기',
  tichu_steps_win: '연속 쌍(스텝)으로 트릭 이기기',
  tichu_bomb_play2: '폭탄 2번 내기',
  tichu_first_out3: '라운드 1등으로 3번 나가기',
  tichu_break_tichu: '상대 팀의 티츄 막아 내기',
  mighty_mighty_win: '마이티 카드로 트릭 이기기',
  mighty_joker_win: '조커로 트릭 이기기',
  mighty_trump3: '으뜸 카드로 트릭 3번 이기기',
  mighty_point_trick: '한 트릭에 점수 카드 3장 이상 먹기',
  mighty_declarer_success: '주공으로 성공하기',
  mighty_defend: '야당으로 주공 막기',
  mighty_friend_success: '친구로 참여해 주공팀 승리 돕기',
  mighty_bid18: '비딩 18점 이상으로 성공하기',
  sk_bid_hit3: '비딩을 3번 정확히 맞추기',
  sk_zero_hit: '0 비딩 성공하기',
  sk_pirate_win2: '해적으로 트릭 2번 이기기',
  sk_mermaid_win: '인어로 트릭 이기기',
  sk_skullking_win2: '스컬킹으로 트릭 2번 이기기',
  ll_guard_hit: '경비병으로 상대 카드 맞히기',
  ll_baron_win: '남작 대결에서 이기기',
  ll_round_win3: '라운드 3번 이기기',
  ll_last_standing: '상대를 모두 탈락시키고 라운드 이기기',
  ll_knock_out3: '상대 3명 탈락시키기',
};

const PRODUCT_LABEL_KO = {
  room_highlight_1: '방 목록 강조 · 금빛 테두리',
  room_highlight_2: '방 목록 강조 · 반짝이는 별',
  room_highlight_3: '방 목록 강조 · 분홍 리본',
  bubble_basic_1: '말풍선(기본) · 분홍 하트',
  bubble_basic_2: '말풍선(기본) · 민트 구름',
  bubble_basic_3: '말풍선(기본) · 노랑 별',
  bubble_premium_1: '말풍선(상위) · 용의 불꽃',
  bubble_premium_2: '말풍선(상위) · 벚꽃',
  bubble_premium_3: '말풍선(상위) · 번개',
};

const GAME_LABEL_KO = {
  tichu: '티츄',
  mighty: '마이티',
  skull_king: '스컬킹',
  love_letter: '러브레터',
};

const TIER_LABEL_KO = { 1: '쉬움', 2: '보통', 3: '어려움' };

const REASON_LABEL_KO = {
  mission: '미션 완료',
  streak: '연속 달성 보너스',
  shop: '토큰 상점 구매',
  admin_grant: '운영자 지급',
  admin_revoke: '운영자 회수',
};

module.exports = {
  MISSION_LABEL_KO,
  PRODUCT_LABEL_KO,
  GAME_LABEL_KO,
  TIER_LABEL_KO,
  REASON_LABEL_KO,
};
