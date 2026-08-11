import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

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

/// The artwork that stands for each game.
///
/// Drawn symbols. They replaced Material glyphs — four borrowed shapes (an
/// anchor, a heart, a medal, a card fan) standing in for four games none of
/// them was made for — which had themselves replaced emoji ('🃏', '⚓', '❤️',
/// '🃑'). The emoji were the real problem: the web engine carries no emoji
/// glyphs, so the first paint fetched Noto Color Emoji (153KB) and Noto Sans
/// Symbols (68KB) from fonts.gstatic.com and "새 방 만들기" showed labels
/// before icons. These are bundled webp, ~4KB each, and paint on the first
/// frame like the glyphs did.
///
/// Masters live in `assets_src/`; the recipe that produced these is in the
/// README beside them.
String gameTypeAsset(String gameType) {
  switch (gameType) {
    case 'skull_king':
      return 'assets/icons/skSymbol.webp';
    case 'love_letter':
      return 'assets/icons/llSymbol.webp';
    case 'mighty':
      return 'assets/icons/mtSymbol.webp';
    default:
      return 'assets/icons/tichuSymbol.webp';
  }
}

/// [gameTypeAsset] as a widget, sized like an [Icon] of the same [size].
///
/// The art is not square — Tichu is 112×144, Love Letter 144×131 — so it is
/// fitted inside a square box the way an icon would be, and callers can go on
/// laying out square slots. It carries its own colours, so unlike the glyph it
/// takes no tint.
Widget gameTypeSymbol(String gameType, {double size = 20}) {
  return Image.asset(
    gameTypeAsset(gameType),
    width: size,
    height: size,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.medium,
  );
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
