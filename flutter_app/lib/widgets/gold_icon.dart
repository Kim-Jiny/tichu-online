import 'package:flutter/material.dart';

/// The gold coin, wherever an amount of gold is shown.
///
/// Replaces `Icons.monetization_on` — a generic dollar-coin glyph that had to be
/// tinted per call site and still looked like currency rather than this game's
/// gold. One widget so every price, balance and reward uses the same coin at the
/// same optical size.
///
/// The asset is trimmed to the coin (the source had a wide low-alpha glow) and
/// scaled to 144px, which is 3x the largest size drawn anywhere.
class GoldIcon extends StatelessWidget {
  /// Drawn box size. Matches what the old `Icon(size:)` was set to.
  final double size;

  const GoldIcon({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/icons/goldIcon.png',
      width: size,
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
