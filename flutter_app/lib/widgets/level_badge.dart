import 'package:flutter/material.dart';

/// Compact circular level badge rendered next to a nickname in the waiting
/// rooms. Background varies by tier:
///   1–10  bronze
///   11–20 silver
///   21–30 gold
///   31–40 black
///   41+   rainbow
/// Returns `SizedBox.shrink()` for null / non-positive levels so callers can
/// drop the badge in unconditionally for bots and pre-redeploy clients.
class LevelBadge extends StatelessWidget {
  final int? level;
  final double size;

  const LevelBadge({super.key, required this.level, this.size = 20});

  @override
  Widget build(BuildContext context) {
    final lv = level ?? 0;
    if (lv <= 0) return const SizedBox.shrink();

    final tier = _tierFor(lv);
    // Slightly smaller number on 2-digit levels so it stays inside the circle
    // at small sizes.
    final fontSize = lv > 99 ? size * 0.40 : lv > 9 ? size * 0.50 : size * 0.58;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: tier.gradient,
        boxShadow: [
          BoxShadow(
            color: tier.shadowColor,
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
        border: Border.all(color: tier.borderColor, width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        '$lv',
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          color: tier.textColor,
          height: 1.0,
          shadows: tier.textShadows,
        ),
      ),
    );
  }
}

class _LevelTier {
  final Gradient gradient;
  final Color borderColor;
  final Color textColor;
  final Color shadowColor;
  final List<Shadow>? textShadows;

  const _LevelTier({
    required this.gradient,
    required this.borderColor,
    required this.textColor,
    required this.shadowColor,
    this.textShadows,
  });
}

_LevelTier _tierFor(int level) {
  if (level <= 10) {
    // Bronze — radial shine on upper-left simulates light catching a struck
    // medallion; deep coppery edge gives it weight.
    return const _LevelTier(
      gradient: RadialGradient(
        center: Alignment(-0.4, -0.5),
        radius: 1.1,
        colors: [
          Color(0xFFFFD7A8),
          Color(0xFFCE7B36),
          Color(0xFF5A2A0A),
        ],
        stops: [0.0, 0.55, 1.0],
      ),
      borderColor: Color(0xFF3C1B05),
      textColor: Colors.white,
      shadowColor: Color(0x55000000),
      textShadows: [
        Shadow(color: Color(0x88000000), offset: Offset(0, 1), blurRadius: 1),
      ],
    );
  }
  if (level <= 20) {
    // Silver — cooler highlight, near-white shine, charcoal edge for
    // medallion contrast.
    return const _LevelTier(
      gradient: RadialGradient(
        center: Alignment(-0.4, -0.5),
        radius: 1.1,
        colors: [
          Color(0xFFFFFFFF),
          Color(0xFFC2C7CC),
          Color(0xFF5E646A),
        ],
        stops: [0.0, 0.55, 1.0],
      ),
      borderColor: Color(0xFF2F3338),
      textColor: Color(0xFF1A1A1A),
      shadowColor: Color(0x55000000),
      textShadows: [
        Shadow(color: Color(0x55FFFFFF), offset: Offset(0, 1), blurRadius: 1),
      ],
    );
  }
  if (level <= 30) {
    // Gold — warm cream highlight grading into rich amber, deep brown edge.
    return const _LevelTier(
      gradient: RadialGradient(
        center: Alignment(-0.4, -0.5),
        radius: 1.1,
        colors: [
          Color(0xFFFFF6C2),
          Color(0xFFE8B948),
          Color(0xFF8A5E00),
        ],
        stops: [0.0, 0.55, 1.0],
      ),
      borderColor: Color(0xFF4A3000),
      textColor: Color(0xFF2E1F00),
      shadowColor: Color(0x55A47000),
      textShadows: [
        Shadow(color: Color(0x66FFFFFF), offset: Offset(0, 1), blurRadius: 1),
      ],
    );
  }
  if (level <= 40) {
    // Black
    return const _LevelTier(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF3A3A3A), Color(0xFF0A0A0A)],
      ),
      borderColor: Color(0xFF000000),
      textColor: Color(0xFFFFD700),
      shadowColor: Color(0x55000000),
      textShadows: [
        Shadow(color: Color(0xCC000000), offset: Offset(0, 1), blurRadius: 2),
      ],
    );
  }
  // Rainbow (41+)
  return const _LevelTier(
    gradient: SweepGradient(
      colors: [
        Color(0xFFFF4D4D),
        Color(0xFFFFAA33),
        Color(0xFFFFE93D),
        Color(0xFF59D85B),
        Color(0xFF3DB8FF),
        Color(0xFF7A5CFF),
        Color(0xFFEF6BFF),
        Color(0xFFFF4D4D),
      ],
    ),
    borderColor: Color(0xFF6A3F9E),
    textColor: Colors.white,
    shadowColor: Color(0x55000000),
    textShadows: [
      Shadow(color: Color(0xCC000000), offset: Offset(0, 1), blurRadius: 2),
    ],
  );
}
