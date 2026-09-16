import 'package:flutter/material.dart';

/// One coaster from a Skull ("스컬") player's pool — a rose or a skull,
/// face-up or face-down.
///
/// The face art (assets/cards/skull_rose.webp / skull_skull.webp) is a
/// portrait card image, not a circular asset, so it's center-cropped into
/// the coaster via BoxFit.cover — same trick as everywhere else round meets
/// rectangular art in this codebase.
class SkullDisc extends StatelessWidget {
  final bool isSkull;
  final bool isFaceUp;
  final bool isSelected;
  final bool isInteractive;
  final VoidCallback? onTap;
  final double size;

  const SkullDisc({
    super.key,
    required this.isSkull,
    this.isFaceUp = true,
    this.isSelected = false,
    this.isInteractive = true,
    this.onTap,
    this.size = 56,
  });

  static const Color roseColor = Color(0xFFD24B7A);
  static const Color skullColor = Color(0xFF5A4038);
  static const Color backColor = Color(0xFF6A4A42);
  static const Color backRing = Color(0xFFC9A876);

  @override
  Widget build(BuildContext context) {
    final color = isSkull ? skullColor : roseColor;
    return GestureDetector(
      onTap: isInteractive ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        transform: Matrix4.translationValues(0, isSelected ? -6 : 0, 0),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isFaceUp ? Colors.white : backColor,
          border: Border.all(
            color: isFaceUp
                ? (isSelected ? const Color(0xFF4D99FF) : color.withValues(alpha: 0.55))
                : backRing,
            width: isSelected ? 2.5 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: (isSelected ? const Color(0xFF4D99FF) : Colors.black)
                  .withValues(alpha: isSelected ? 0.3 : 0.12),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: isFaceUp
            ? ClipOval(
                child: Image.asset(
                  isSkull
                      ? 'assets/cards/skull_skull.webp'
                      : 'assets/cards/skull_rose.webp',
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  errorBuilder: (_, e, s) => Text(
                    isSkull ? '💀' : '🌹',
                    style: TextStyle(fontSize: size * 0.5),
                  ),
                ),
              )
            : Icon(Icons.circle, size: size * 0.28, color: backRing),
      ),
    );
  }
}

/// A small fanned/stacked pile of face-down discs — used to show how many
/// discs a seat has placed this round without revealing their identity.
class SkullDiscStack extends StatelessWidget {
  final int count;
  final double discSize;

  const SkullDiscStack({super.key, required this.count, this.discSize = 22});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return SizedBox(height: discSize);
    const step = 8.0;
    final width = discSize + step * (count - 1).clamp(0, 999);
    return SizedBox(
      width: width,
      height: discSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < count; i++)
            Positioned(
              left: step * i,
              child: SkullDisc(
                isSkull: false,
                isFaceUp: false,
                isInteractive: false,
                size: discSize,
              ),
            ),
        ],
      ),
    );
  }
}
