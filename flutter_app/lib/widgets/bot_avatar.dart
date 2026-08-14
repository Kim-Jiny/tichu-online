import 'package:flutter/material.dart';
import 'profile_avatar.dart' show avatarCornerRadius;

/// Avatar for a bot seat.
///
/// Bots are not accounts, so they never go near the paid profile-photo path —
/// no upload, no object storage, no moderation. The art is a local asset picked
/// by bot number, and until those assets exist it falls back to a coloured
/// robot glyph. Either way a bot seat now has something in the avatar slot
/// instead of a hole, which is what kept the seat layout from lining up between
/// human and bot players.
///
/// Art lives in `assets/bots/bot1.webp` … `bot6.webp` (originals in `art/bots/`,
/// see the README there). Six covers the largest table, and anything beyond
/// wraps.
class BotAvatar extends StatelessWidget {
  final double size;

  /// Bot nickname, e.g. "봇 3" / "Bot 3". The trailing number picks the art —
  /// it is generated from the `bot_nickname` string, so the digits are there in
  /// every locale even when the word around them is not.
  final String name;

  /// Stamps a small robot marker on the corner.
  ///
  /// The art is a cartoon animal, which at a glance is indistinguishable from a
  /// human player's profile photo — so anywhere the seat is wide enough to
  /// mistake one for the other, the marker says which is which. Off by default
  /// because in-play seats draw this at 13-20px, where a corner badge is just
  /// noise.
  final bool showBadge;

  /// Corner radius. Null → a circle; a value → a rounded square, to match a
  /// host surface whose other avatars are rounded rects (the profile popup).
  final double? borderRadius;

  /// Bot speed — 'slow' | 'normal' | 'fast'. Colours the corner marker, so how
  /// fast a bot plays is readable from the seat itself instead of only from a
  /// separate chip: slow green, normal blue, fast red.
  final String? speed;

  const BotAvatar({
    super.key,
    required this.size,
    required this.name,
    this.showBadge = false,
    this.borderRadius,
    this.speed,
  });

  static const _artCount = 6;

  /// Fallback colours, used only if an asset fails to load. Distinct hues so
  /// two bots at one table never look the same.
  static const _palette = [
    (Color(0xFFE3F2FD), Color(0xFF1565C0)),
    (Color(0xFFE8F5E9), Color(0xFF2E7D32)),
    (Color(0xFFFFF3E0), Color(0xFFE65100)),
    (Color(0xFFF3E5F5), Color(0xFF6A1B9A)),
    (Color(0xFFFFEBEE), Color(0xFFC62828)),
    (Color(0xFFE0F7FA), Color(0xFF00838F)),
  ];

  /// 1-based index from the name, or 0 when there are no digits to read.
  int get _number {
    final m = RegExp(r'(\d+)').firstMatch(name);
    return m == null ? 0 : int.parse(m.group(1)!);
  }

  int get _slot => _number <= 0 ? 0 : (_number - 1) % _artCount;

  /// Same shape as a human's avatar — see [avatarCornerRadius]. A round bot
  /// next to a square player looks like two different kinds of thing.
  double get _radius => borderRadius ?? avatarCornerRadius(size);

  Widget _clip({required Widget child}) =>
      ClipRRect(borderRadius: BorderRadius.circular(_radius), child: child);

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = _palette[_slot];
    final glyph = DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: Center(
        child: Icon(
          Icons.smart_toy_rounded,
          size: size * 0.62,
          color: foreground,
        ),
      ),
    );

    final avatar = SizedBox(
      width: size,
      height: size,
      child: _clip(
        child: Image.asset(
          'assets/bots/bot${_slot + 1}.webp',
          width: size,
          height: size,
          fit: BoxFit.cover,
          // A file that failed to decode: show the glyph rather than Flutter's
          // broken-image box.
          errorBuilder: (_, _, _) => glyph,
        ),
      ),
    );
    if (!showBadge) return avatar;

    final badge = size * 0.42;
    final badgeColor = switch (speed) {
      'slow' => const Color(0xFF2E7D32),
      'fast' => const Color(0xFFC62828),
      _ => const Color(0xFF1565C0),
    };
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          avatar,
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: badge,
              height: badge,
              decoration: BoxDecoration(
                color: badgeColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Icon(
                Icons.smart_toy_rounded,
                size: badge * 0.62,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
