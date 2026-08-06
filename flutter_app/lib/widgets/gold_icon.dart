import 'package:flutter/material.dart';

/// The gold coin art, wherever an amount of gold is shown.
///
/// Replaces `Icons.monetization_on` — a generic dollar-coin glyph that had to be
/// tinted per call site and still looked like currency rather than this game's
/// gold. One widget so every price, balance and reward uses the same art at the
/// same optical size.
///
/// Three tiers, picked from [amount]: a single coin, a small pile from 10,000,
/// and a pile with bars from 100,000. Pass the number being shown and the art
/// follows it; omit it (a balance-agnostic header, say) and the single coin is
/// used.
///
/// Sized by HEIGHT, not by a square box: the pile art is ~1.3x wider than tall,
/// so forcing it into a square would draw it noticeably smaller than the coin
/// beside it in the same row.
///
/// Each asset is trimmed to the art (the sources carry a wide low-alpha glow
/// that would otherwise shrink the subject) and scaled to 144px tall, 3x the
/// largest size drawn anywhere.
class GoldIcon extends StatelessWidget {
  /// Drawn height. Matches what the old `Icon(size:)` was set to.
  final double size;

  /// The amount this icon labels, used to pick the tier. Null → single coin.
  final int? amount;

  const GoldIcon({super.key, this.size = 20, this.amount});

  static const _single = 'assets/icons/goldIcon.webp';
  static const _pile = 'assets/icons/goldIcon2.webp';
  static const _hoard = 'assets/icons/goldIcon3.webp';

  static String assetFor(int? amount) {
    if (amount == null) return _single;
    if (amount >= 100000) return _hoard;
    if (amount >= 10000) return _pile;
    return _single;
  }

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetFor(amount),
      height: size,
      fit: BoxFit.contain,
      // A price row must not turn into a broken-image box if the asset is
      // missing from a build.
      errorBuilder: (_, _, _) => Icon(
        Icons.monetization_on,
        size: size,
        color: const Color(0xFFFFB74D),
      ),
    );
  }
}
