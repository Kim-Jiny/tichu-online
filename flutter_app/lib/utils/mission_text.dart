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
