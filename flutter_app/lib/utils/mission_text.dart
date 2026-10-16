import '../l10n/app_localizations.dart';

/// 미션 키 → 보여 줄 문장. 키가 늘면 여기와 arb 에 한 줄씩 더한다.
String missionTitle(L10n l10n, String key) {
  switch (key) {
    case 'tichu_play':
      return l10n.missionTichuPlay;
    case 'tichu_win':
      return l10n.missionTichuWin;
    case 'tichu_win_streak4':
      return l10n.missionTichuWinStreak4;
    case 'tichu_onetwo':
      return l10n.missionTichuOnetwo;
    case 'tichu_dog_finish':
      return l10n.missionTichuDogFinish;
    case 'tichu_bomb50':
      return l10n.missionTichuBomb50;
    case 'tichu_straight_win':
      return l10n.missionTichuStraightWin;
    case 'tichu_fullhouse_win':
      return l10n.missionTichuFullhouseWin;
    case 'tichu_steps_win':
      return l10n.missionTichuStepsWin;
    case 'tichu_bomb_play':
      return l10n.missionTichuBombPlay;
    case 'tichu_first_out5':
      return l10n.missionTichuFirstOut5;
    case 'tichu_break_tichu':
      return l10n.missionTichuBreakTichu;
    case 'tichu_straight8':
      return l10n.missionTichuStraight8;
    case 'tichu_straight10':
      return l10n.missionTichuStraight10;
    case 'tichu_fullhouse_k':
      return l10n.missionTichuFullhouseK;
    case 'tichu_fullhouse_a':
      return l10n.missionTichuFullhouseA;
    case 'tichu_straight_flush':
      return l10n.missionTichuStraightFlush;
    case 'tichu_phoenix_single_win':
      return l10n.missionTichuPhoenixSingleWin;
    case 'tichu_counter_small':
      return l10n.missionTichuCounterSmall;
    case 'tichu_counter_large':
      return l10n.missionTichuCounterLarge;
    case 'tichu_tichu_onetwo':
      return l10n.missionTichuTichuOnetwo;
    case 'mighty_play':
      return l10n.missionMightyPlay;
    case 'mighty_win':
      return l10n.missionMightyWin;
    case 'mighty_win_streak4':
      return l10n.missionMightyWinStreak4;
    case 'mighty_nt20':
      return l10n.missionMightyNt20;
    case 'mighty_bid18':
      return l10n.missionMightyBid18;
    case 'mighty_nt':
      return l10n.missionMightyNt;
    case 'mighty_all20':
      return l10n.missionMightyAll20;
    case 'mighty_friend7':
      return l10n.missionMightyFriend7;
    case 'mighty_mighty_win':
      return l10n.missionMightyMightyWin;
    case 'mighty_dillmiss':
      return l10n.missionMightyDillmiss;
    case 'mighty_win5':
      return l10n.missionMightyWin5;
    case 'mighty_joker_win':
      return l10n.missionMightyJokerWin;
    case 'mighty_declarer_success':
      return l10n.missionMightyDeclarerSuccess;
    case 'mighty_point2':
      return l10n.missionMightyPoint2;
    case 'mighty_point4':
      return l10n.missionMightyPoint4;
    case 'mighty_point5':
      return l10n.missionMightyPoint5;
    case 'mighty_joker_kill_friend':
      return l10n.missionMightyJokerKillFriend;
    case 'mighty_joker_kill_defender':
      return l10n.missionMightyJokerKillDefender;
    case 'sk_play':
      return l10n.missionSkPlay;
    case 'sk_win':
      return l10n.missionSkWin;
    case 'sk_win_streak4':
      return l10n.missionSkWinStreak4;
    case 'sk_pirates2':
      return l10n.missionSkPirates2;
    case 'sk_mermaid_king':
      return l10n.missionSkMermaidKing;
    case 'sk_ten_win':
      return l10n.missionSkTenWin;
    case 'sk_bid_hit6':
      return l10n.missionSkBidHit6;
    case 'sk_bid_hit12':
      return l10n.missionSkBidHit12;
    case 'sk_zero_hit':
      return l10n.missionSkZeroHit;
    case 'sk_pirate_win':
      return l10n.missionSkPirateWin;
    case 'sk_mermaid_win':
      return l10n.missionSkMermaidWin;
    case 'sk_skullking_win':
      return l10n.missionSkSkullkingWin;
    case 'll_play':
      return l10n.missionLlPlay;
    case 'll_win':
      return l10n.missionLlWin;
    case 'll_win_streak4':
      return l10n.missionLlWinStreak4;
    case 'll_guard_hit':
      return l10n.missionLlGuardHit;
    case 'll_baron_win':
      return l10n.missionLlBaronWin;
    case 'll_round_win':
      return l10n.missionLlRoundWin;
    case 'll_last_standing':
      return l10n.missionLlLastStanding;
    case 'll_knock_out6':
      return l10n.missionLlKnockOut6;
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
