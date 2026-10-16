'use strict';

/** 관리자 화면에 보여 줄 한국어 이름. 앱 문구(l10n)와는 별개다 — 운영자가 읽는 용도. */
const MISSION_LABEL_KO = {
  tichu_play: '티츄 한 판 끝까지 하기',
  tichu_win: '티츄 한 판 이기기',
  tichu_small: '스몰 티츄 성공하기',
  tichu_large: '라지 티츄 성공하기',
  tichu_onetwo: '우리 팀이 1·2등 하기',
  tichu_dog_finish: '개 카드로 마무리해 1·2등으로 패 털기',
  tichu_bomb30: '폭탄으로 점수 30점 얻기',
  mighty_play: '마이티 한 판 끝까지 하기',
  mighty_win: '마이티 한 판 이기기',
  mighty_bid20: '비딩 20점으로 성공하기',
  mighty_nt: '노트럼프 비딩으로 성공하기',
  mighty_all20: '여당으로 점수 카드 20장 모두 먹기',
  mighty_friend7: '친구로 참여해 점수 7점 이상 먹기',
  sk_play: '스컬킹 한 판 끝까지 하기',
  sk_win: '스컬킹 한 판 이기기',
  sk_pirates2: '스컬킹으로 해적 두 명 한 번에 잡기',
  sk_mermaid_king: '인어로 스컬킹 잡기',
  sk_ten_win: '숫자 10 카드로 트릭 이기기',
  ll_play: '러브레터 한 판 끝까지 하기',
  ll_win: '러브레터 한 판 이기기',
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
