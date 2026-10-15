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
    'spade': Color(0xFF2B2B2B), // matte black
    'heart': Color(0xFFD24B4B), // matte red
    'diamond': Color(0xFF6FB6E5), // matte sky
    'club': Color(0xFF4BAA6A), // matte green
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

    // 입체감: 진한 테두리 + 아래로 어긋난 단색 그림자(카드가 종이처럼 떠 보이게),
    // 앞면은 위가 밝고 아래가 살짝 따뜻한 그라데이션. 선택하면 더 높이 떠오른다.
    const edge = Color(0xFF3B2A20);
    final effectiveBorderColor = isSelected
        ? const Color(0xFF2F7DE0)
        : borderColor ?? edge.withValues(alpha: isFaceUp ? 0.7 : 0.85);
    final effectiveBorderWidth = isSelected
        ? 2.4
        : (borderColor != null ? 2.4 : (width < 40 ? 1.2 : 1.5));
    final lift = isSelected ? -12.0 : 0.0;
    final shadowY = isSelected ? 5.0 : 2.5;
    final radius = (width / 48 * 12).clamp(4.0, 13.0);

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
              transform: Matrix4.translationValues(0, lift, 0),
              decoration: BoxDecoration(
                color: isFaceUp ? Colors.white : backBg,
                gradient: isFaceUp
                    ? const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFFFFFFF), Color(0xFFF6EEE2)],
                      )
                    : null,
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(
                  color: effectiveBorderColor,
                  width: effectiveBorderWidth,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isSelected
                        ? const Color(0xFF1F4F94)
                        : const Color(0xFF8C7B6C),
                    offset: Offset(0, shadowY),
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
                    border: Border.all(
                      color: const Color(0xFF3B2A20),
                      width: 1.5,
                    ),
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
    return _artFill('assets/cards/joker.webp', fallback: _buildJokerFallback);
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

    return _artFill(imagePath);
  }

  /// 그림 카드: 그림 자체가 카드 테두리(흰 둥근 틀)를 품고 있어서 그대로 얹으면
  /// 우리 테두리 안에 또 하나의 테두리가 생긴다. 살짝 확대해 그림의 가장자리를
  /// 잘라 내고, 둥근 모서리를 바깥 카드와 맞춘다.
  Widget _artFill(String imagePath, {Widget Function()? fallback}) {
    final outer = (width / 48 * 12).clamp(4.0, 13.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular((outer - 1.5).clamp(3.0, 12.0)),
      child: Transform.scale(
        scale: 1.07,
        child: Image.asset(
          imagePath,
          fit: BoxFit.cover,
          width: width,
          height: height,
          errorBuilder: fallback == null ? null : (c, e, st) => fallback(),
        ),
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
    final paintColor =
        color ?? PlayingCard.suitColors[suit] ?? const Color(0xFF5A4038);
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
