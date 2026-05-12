import 'package:flutter/material.dart';

/// Compact circular level badge rendered next to a nickname in the waiting
/// rooms. Background varies by tier:
///   1–5   bronze
///   6–10  silver
///   11–15 gold
///   16–20 diamond
///   21+   rainbow
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
  if (level <= 5) {
    // Bronze
    return const _LevelTier(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFE3A772), Color(0xFF8B4513)],
      ),
      borderColor: Color(0xFF6B3410),
      textColor: Colors.white,
      shadowColor: Color(0x33000000),
      textShadows: [
        Shadow(color: Color(0x66000000), offset: Offset(0, 1), blurRadius: 1),
      ],
    );
  }
  if (level <= 10) {
    // Silver
    return const _LevelTier(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF2F2F2), Color(0xFF9A9A9A)],
      ),
      borderColor: Color(0xFF6F6F6F),
      textColor: Color(0xFF333333),
      shadowColor: Color(0x33000000),
    );
  }
  if (level <= 15) {
    // Gold
    return const _LevelTier(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFE38A), Color(0xFFC79100)],
      ),
      borderColor: Color(0xFF8A6500),
      textColor: Color(0xFF4A3500),
      shadowColor: Color(0x33B07700),
    );
  }
  if (level <= 20) {
    // Diamond (icy blue)
    return const _LevelTier(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFE3F8FF), Color(0xFF6FB6E5)],
      ),
      borderColor: Color(0xFF3A7CA5),
      textColor: Color(0xFF143E5C),
      shadowColor: Color(0x336FB6E5),
    );
  }
  // Rainbow (21+)
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
