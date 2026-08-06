import 'package:flutter/material.dart';

/// The 방장 (host) marker that overhangs a seat's top-left corner.
///
/// Was the 👑 emoji, which every platform draws differently — flat and grey-gold
/// on some Android builds, a different shape on iOS. This is our own art, so the
/// host reads the same everywhere.
///
/// The asset is trimmed to the crown (the source had a wide, near-invisible glow
/// that made the crown itself a speck at icon size) and scaled down to 120px
/// wide, which is still 3x the largest size drawn here.
class HostCrown extends StatelessWidget {
  /// Drawn width; height follows the art's aspect ratio.
  final double size;

  const HostCrown({super.key, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/icons/crown.webp',
      width: size,
      // A missing asset must not take the seat layout with it — the emoji is a
      // fine stand-in.
      errorBuilder: (_, _, _) => Text(
        '👑',
        style: TextStyle(fontSize: size * 0.8, height: 1.0),
      ),
    );
  }
}
