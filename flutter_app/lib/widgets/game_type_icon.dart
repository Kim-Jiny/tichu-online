import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// The icon that stands for each game, as a Material glyph.
///
/// These used to be emoji ('🃏', '⚓', '❤️', '🃑'). On the web that is a
/// network dependency: the engine has no emoji glyphs of its own, so it went
/// to fonts.gstatic.com the first time one was painted — Noto Color Emoji
/// (153KB, ~300ms) for ⚓/❤️ and Noto Sans Symbols (68KB, ~260ms) for the two
/// playing-card characters. Opening "새 방 만들기" therefore showed the labels
/// before the icons, which read as slow image loading.
///
/// Material icons are already in the bundle (tree-shaken, ~32KB for the whole
/// app) so these paint on the first frame with no request at all. They also
/// take the game's colour, which the emoji could not — ⚓ and ❤️ arrived in
/// their own fixed colours while 🃏 and 🃑 were monochrome, so the four never
/// looked like one set.
IconData gameTypeIcon(String gameType) {
  switch (gameType) {
    case 'skull_king':
      return Icons.anchor;
    case 'love_letter':
      return Icons.favorite;
    case 'mighty':
      return Icons.military_tech;
    default:
      return Icons.style;
  }
}

/// The colour that stands for each game.
///
/// The room-creation picker is where people learn which colour is which game,
/// so that is the palette everywhere else has to agree with. It was written out
/// by hand in three places and the profile popup had drifted to a different
/// four — purple Tichu, green Mighty — which made the same game look like two.
Color gameTypeColor(String gameType) {
  switch (gameType) {
    case 'skull_king':
      return const Color(0xFF21455F);
    case 'love_letter':
      return const Color(0xFFE91E63);
    case 'mighty':
      return const Color(0xFF5C6BC0);
    default:
      return const Color(0xFF64B5F6);
  }
}

/// The game's name, in the player's language.
String gameTypeLabel(L10n l10n, String gameType) {
  switch (gameType) {
    case 'skull_king':
      return l10n.lobbySkullKing;
    case 'love_letter':
      return l10n.lobbyLoveLetter;
    case 'mighty':
      return l10n.lobbyMighty;
    default:
      return l10n.lobbyTichu;
  }
}

/// Text colour to put on top of [gameTypeColor] when it is used as a fill.
///
/// Tichu's blue is light enough that white on it is hard to read, so it takes
/// dark text while the other three take white.
Color gameTypeOnColor(String gameType) {
  return gameTypeColor(gameType).computeLuminance() > 0.42
      ? const Color(0xFF1B3A50)
      : Colors.white;
}
