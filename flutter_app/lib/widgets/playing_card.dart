import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/game_service.dart';

class PlayingCard extends StatelessWidget {
  final String cardId;
  final bool isSelected;
  final bool isFaceUp;
  final bool isInteractive;
  final VoidCallback? onTap;
  final double width;
  final double height;
  final IconData? badgeIcon;
  final Color? badgeColor;
  final Color? borderColor;

  const PlayingCard({
    super.key,
    required this.cardId,
    this.isSelected = false,
    this.isFaceUp = true,
    this.isInteractive = true,
    this.onTap,
    this.width = 60,
    this.height = 84,
    this.badgeIcon,
    this.badgeColor,
    this.borderColor,
  });

  static const Map<String, Color> suitColors = {
    'spade': Color(0xFF2B2B2B),  // matte black
    'heart': Color(0xFFD24B4B),  // matte red
    'diamond': Color(0xFF6FB6E5), // matte sky
    'club': Color(0xFF4BAA6A),   // matte green
  };

  static const Map<String, String> specialImages = {
    'special_bird': 'assets/cards/bird.webp',
    'special_dog': 'assets/cards/dog.webp',
    'special_phoenix': 'assets/cards/phoenix.webp',
    'special_dragon': 'assets/cards/dragon.webp',
  };

  @override
  Widget build(BuildContext context) {
    final cardColors = context.watch<GameService>().cardBackColors;
    final backBg = cardColors[0];
    final backBorder = cardColors[1];

    final effectiveBorderColor = isSelected
        ? const Color(0xFF4D99FF)
        : borderColor ?? (isFaceUp ? const Color(0xFFE6DCE8) : backBorder);
    final effectiveBorderWidth = isSelected ? 2.0 : (borderColor != null ? 2.0 : 1.0);

    return GestureDetector(
      onTap: isInteractive ? onTap : null,
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              transform: Matrix4.translationValues(0, isSelected ? -8 : 0, 0),
              decoration: BoxDecoration(
                color: isFaceUp ? Colors.white : backBg,
                borderRadius: BorderRadius.circular((width / 48 * 14).clamp(4, 14)),
                border: Border.all(
                  color: effectiveBorderColor,
                  width: effectiveBorderWidth,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE1D7E6).withValues(alpha: 0.4),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: isFaceUp ? _buildFrontFace() : _buildBackFace(cardColors),
            ),
            if (badgeIcon != null)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: badgeColor ?? const Color(0xFFE53935),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Icon(badgeIcon, size: 11, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFrontFace() {
    if (cardId == 'joker') {
      return _buildJokerCard();
    }
    if (cardId.startsWith('special_')) {
      return _buildSpecialCard();
    }
    return _buildNormalCard();
  }

  Widget _buildJokerCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: Image.asset(
        'assets/cards/joker.webp',
        fit: BoxFit.cover,
        width: width,
        height: height,
        errorBuilder: (ctx, err, stack) => _buildJokerFallback(),
      ),
    );
  }

  Widget _buildJokerFallback() {
    final scale = (width / 48).clamp(0.7, 1.3);
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF3E0), Color(0xFFFFE0B2)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '\u2605',
              style: TextStyle(
                fontSize: 20 * scale,
                color: const Color(0xFFFF6F00),
              ),
            ),
            SizedBox(height: 2 * scale),
            Text(
              'JOKER',
              style: TextStyle(
                fontSize: 9 * scale,
                fontWeight: FontWeight.bold,
                color: const Color(0xFFE65100),
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNormalCard() {
    final parts = cardId.split('_');
    if (parts.length < 2) return const SizedBox();

    final suit = parts[0];
    final rank = parts[1];
    final color = suitColors[suit] ?? Colors.black;

    // Scale based on card width (base: 48)
    final scale = (width / 48).clamp(0.7, 1.3);
    final symbolSize = 14.0 * scale;
    final rankSize = 22.0 * scale;

    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: symbolSize,
              height: symbolSize,
              child: CustomPaint(
                painter: SuitPainter(suit: suit, color: color),
              ),
            ),
            SizedBox(height: 2 * scale),
            Text(
              rank,
              style: TextStyle(
                fontSize: rankSize,
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecialCard() {
    final imagePath = specialImages[cardId];
    if (imagePath == null) {
      return const Center(child: Text('?'));
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: Image.asset(
        imagePath,
        fit: BoxFit.cover,
        width: width,
        height: height,
      ),
    );
  }

  Widget _buildBackFace(List<Color> cardColors) {
    // The outer AnimatedContainer already paints the theme background +
    // border for the back face. Strip the inner chrome and just drop a
    // small dragon icon in the center.
    final iconSize = (width * 0.45).clamp(14.0, 36.0);
    return Center(
      child: Image.asset(
        'assets/dragonIcon.webp',
        width: iconSize,
        height: iconSize,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}

/// Renders a suit glyph via [SuitPainter], bypassing the OS emoji font so the
/// colour is predictable on Android (where ♥ / ♦ are otherwise promoted to
/// coloured emoji that ignore [TextStyle.color]).
class SuitIcon extends StatelessWidget {
  final String suit;
  final double size;
  final Color? color;

  const SuitIcon({super.key, required this.suit, this.size = 16, this.color});

  @override
  Widget build(BuildContext context) {
    if (suit == 'no_trump') {
      return Text(
        'NT',
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.bold,
          color: color ?? const Color(0xFF7B1FA2),
        ),
      );
    }
    final paintColor = color ?? PlayingCard.suitColors[suit] ?? const Color(0xFF5A4038);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: SuitPainter(suit: suit, color: paintColor),
      ),
    );
  }
}

/// Draws suit symbols using Canvas paths — consistent colors on all platforms.
class SuitPainter extends CustomPainter {
  final String suit;
  final Color color;

  SuitPainter({required this.suit, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    switch (suit) {
      case 'heart':
        _drawHeart(canvas, size, paint);
      case 'diamond':
        _drawDiamond(canvas, size, paint);
      case 'spade':
        _drawSpade(canvas, size, paint);
      case 'club':
        _drawClub(canvas, size, paint);
    }
  }

  void _drawHeart(Canvas canvas, Size size, Paint paint) {
    final w = size.width;
    final h = size.height;
    final path = Path();
    // Bottom tip, then two full rounded lobes with a deep centre dip.
    path.moveTo(w * 0.5, h * 0.97);
    path.cubicTo(w * -0.02, h * 0.60, w * 0.02, h * 0.20, w * 0.22, h * 0.12);
    path.cubicTo(w * 0.38, h * 0.05, w * 0.47, h * 0.14, w * 0.5, h * 0.30);
    path.cubicTo(w * 0.53, h * 0.14, w * 0.62, h * 0.05, w * 0.78, h * 0.12);
    path.cubicTo(w * 0.98, h * 0.20, w * 1.02, h * 0.60, w * 0.5, h * 0.97);
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawDiamond(Canvas canvas, Size size, Paint paint) {
    final w = size.width;
    final h = size.height;
    final path = Path();
    path.moveTo(w * 0.5, 0);
    path.lineTo(w, h * 0.5);
    path.lineTo(w * 0.5, h);
    path.lineTo(0, h * 0.5);
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawSpade(Canvas canvas, Size size, Paint paint) {
    final w = size.width;
    final h = size.height;
    // Leaf body: sharp top tip, two full rounded bottom lobes, and a raised
    // centre cusp between them (the classic spade notch).
    final path = Path();
    path.moveTo(w * 0.5, 0);
    // Down-left to the left lobe, then curl in to the centre cusp.
    path.cubicTo(w * 0.12, h * 0.30, w * -0.05, h * 0.60, w * 0.22, h * 0.70);
    path.cubicTo(w * 0.36, h * 0.76, w * 0.48, h * 0.70, w * 0.5, h * 0.58);
    // Out to the right lobe, then back up to the top tip.
    path.cubicTo(w * 0.52, h * 0.70, w * 0.64, h * 0.76, w * 0.78, h * 0.70);
    path.cubicTo(w * 1.05, h * 0.60, w * 0.88, h * 0.30, w * 0.5, 0);
    path.close();
    canvas.drawPath(path, paint);
    // Stem: narrow at the cusp, flaring out to a wide base.
    final stemPath = Path();
    stemPath.moveTo(w * 0.5, h * 0.55);
    stemPath.quadraticBezierTo(w * 0.46, h * 0.80, w * 0.33, h * 0.98);
    stemPath.lineTo(w * 0.67, h * 0.98);
    stemPath.quadraticBezierTo(w * 0.54, h * 0.80, w * 0.5, h * 0.55);
    stemPath.close();
    canvas.drawPath(stemPath, paint);
  }

  void _drawClub(Canvas canvas, Size size, Paint paint) {
    final w = size.width;
    final h = size.height;
    final r = w * 0.23;
    // Three lobes.
    canvas.drawCircle(Offset(w * 0.5, h * 0.27), r, paint); // top
    canvas.drawCircle(Offset(w * 0.25, h * 0.55), r, paint); // left
    canvas.drawCircle(Offset(w * 0.75, h * 0.55), r, paint); // right
    // Flared stem (matches the spade), overlapping the lobes so there's no gap.
    final stemPath = Path();
    stemPath.moveTo(w * 0.40, h * 0.46);
    stemPath.quadraticBezierTo(w * 0.44, h * 0.74, w * 0.31, h * 0.98);
    stemPath.lineTo(w * 0.69, h * 0.98);
    stemPath.quadraticBezierTo(w * 0.56, h * 0.74, w * 0.60, h * 0.46);
    stemPath.close();
    canvas.drawPath(stemPath, paint);
  }

  @override
  bool shouldRepaint(SuitPainter old) => suit != old.suit || color != old.color;
}
