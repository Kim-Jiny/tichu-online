import '../l10n/app_localizations.dart';

/// 미션 키 → 보여 줄 문장. 키가 늘면 여기와 arb 에 한 줄씩 더한다.
String missionTitle(L10n l10n, String key) {
  switch (key) {
    case 'tichu_play':
      return l10n.missionTichuPlay;
    case 'tichu_win':
      return l10n.missionTichuWin;
    case 'tichu_small':
      return l10n.missionTichuSmall;
    case 'tichu_large':
      return l10n.missionTichuLarge;
    case 'tichu_onetwo':
      return l10n.missionTichuOnetwo;
    case 'tichu_dog_finish':
      return l10n.missionTichuDogFinish;
    case 'tichu_bomb30':
      return l10n.missionTichuBomb30;
    case 'mighty_play':
      return l10n.missionMightyPlay;
    case 'mighty_win':
      return l10n.missionMightyWin;
    case 'mighty_bid20':
      return l10n.missionMightyBid20;
    case 'mighty_nt':
      return l10n.missionMightyNt;
    case 'mighty_all20':
      return l10n.missionMightyAll20;
    case 'mighty_friend7':
      return l10n.missionMightyFriend7;
    case 'sk_play':
      return l10n.missionSkPlay;
    case 'sk_win':
      return l10n.missionSkWin;
    case 'sk_pirates2':
      return l10n.missionSkPirates2;
    case 'sk_mermaid_king':
      return l10n.missionSkMermaidKing;
    case 'sk_ten_win':
      return l10n.missionSkTenWin;
    case 'll_play':
      return l10n.missionLlPlay;
    case 'll_win':
      return l10n.missionLlWin;
    case 'tichu_play3':
      return l10n.missionTichuPlay3;
    case 'tichu_win2':
      return l10n.missionTichuWin2;
    case 'tichu_dragon_win':
      return l10n.missionTichuDragonWin;
    case 'tichu_phoenix_win':
      return l10n.missionTichuPhoenixWin;
    case 'tichu_straight_win':
      return l10n.missionTichuStraightWin;
    case 'tichu_fullhouse_win':
      return l10n.missionTichuFullhouseWin;
    case 'tichu_steps_win':
      return l10n.missionTichuStepsWin;
    case 'tichu_bomb_play2':
      return l10n.missionTichuBombPlay2;
    case 'tichu_first_out3':
      return l10n.missionTichuFirstOut3;
    case 'tichu_break_tichu':
      return l10n.missionTichuBreakTichu;
    case 'mighty_play2':
      return l10n.missionMightyPlay2;
    case 'mighty_mighty_win':
      return l10n.missionMightyMightyWin;
    case 'mighty_joker_win':
      return l10n.missionMightyJokerWin;
    case 'mighty_trump3':
      return l10n.missionMightyTrump3;
    case 'mighty_point_trick':
      return l10n.missionMightyPointTrick;
    case 'mighty_declarer_success':
      return l10n.missionMightyDeclarerSuccess;
    case 'mighty_defend':
      return l10n.missionMightyDefend;
    case 'mighty_friend_success':
      return l10n.missionMightyFriendSuccess;
    case 'mighty_bid18':
      return l10n.missionMightyBid18;
    case 'sk_play2':
      return l10n.missionSkPlay2;
    case 'sk_bid_hit3':
      return l10n.missionSkBidHit3;
    case 'sk_zero_hit':
      return l10n.missionSkZeroHit;
    case 'sk_pirate_win2':
      return l10n.missionSkPirateWin2;
    case 'sk_mermaid_win':
      return l10n.missionSkMermaidWin;
    case 'sk_skullking_win2':
      return l10n.missionSkSkullkingWin2;
    case 'll_play2':
      return l10n.missionLlPlay2;
    case 'll_guard_hit':
      return l10n.missionLlGuardHit;
    case 'll_baron_win':
      return l10n.missionLlBaronWin;
    case 'll_round_win3':
      return l10n.missionLlRoundWin3;
    case 'll_last_standing':
      return l10n.missionLlLastStanding;
    case 'll_knock_out3':
      return l10n.missionLlKnockOut3;
  }
  return key;
}

String missionGameName(L10n l10n, String game) {
  switch (game) {
    case 'mighty':
      return l10n.missionsGameMighty;
    case 'skull_king':
      return l10n.missionsGameSkullKing;
    case 'love_letter':
      return l10n.missionsGameLoveLetter;
    default:
      return l10n.missionsGameTichu;
  }
}

String missionTierName(L10n l10n, int tier) {
  switch (tier) {
    case 3:
      return l10n.missionsTierHard;
    case 2:
      return l10n.missionsTierNormal;
    default:
      return l10n.missionsTierEasy;
  }
}

/// 서버가 돌려준 실패 이유 → 안내 문장.
String missionErrorText(L10n l10n, String reason, int dailyPicks) {
  switch (reason) {
    case 'too_many':
      return l10n.missionsErrTooMany(dailyPicks.toString());
    case 'already_picked':
      return l10n.missionsErrAlready;
    default:
      return l10n.missionsErrGeneric;
  }
}
