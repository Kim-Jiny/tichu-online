import 'package:flutter/material.dart';

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
