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

  const PlayingCard({
    super.key,
    required this.cardId,
    this.isSelected = false,
    this.isFaceUp = true,
    this.isInteractive = true,
    this.onTap,
    this.width = 60,
    this.height = 84,
  });

  static const Map<String, Color> suitColors = {
    'spade': Color(0xFF2B2B2B),  // matte black
    'heart': Color(0xFFD24B4B),  // matte red
    'diamond': Color(0xFF6FB6E5), // matte sky
    'club': Color(0xFF4BAA6A),   // matte green
  };

  static const Map<String, String> specialImages = {
    'special_bird': 'assets/cards/bird.png',
    'special_dog': 'assets/cards/dog.png',
    'special_phoenix': 'assets/cards/phoenix.png',
    'special_dragon': 'assets/cards/dragon.png',
  };

  @override
  Widget build(BuildContext context) {
    final cardColors = context.watch<GameService>().cardBackColors;
    final backBg = cardColors[0];
    final backBorder = cardColors[1];

    return GestureDetector(
      onTap: isInteractive ? onTap : null,
      child: SizedBox(
        width: width,
        height: height,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          transform: Matrix4.translationValues(0, isSelected ? -8 : 0, 0),
          decoration: BoxDecoration(
            color: isFaceUp ? Colors.white : backBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF4D99FF)
                  : isFaceUp ? const Color(0xFFE6DCE8) : backBorder,
              width: isSelected ? 2 : 1,
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
      ),
    );
  }

  Widget _buildFrontFace() {
    if (cardId.startsWith('special_')) {
      return _buildSpecialCard();
    }
    return _buildNormalCard();
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: symbolSize,
            height: symbolSize,
            child: CustomPaint(
              painter: _SuitPainter(suit: suit, color: color),
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
    final backBg = cardColors[0];
    final backBorder = cardColors[1];
    final innerBorder = cardColors[2];

    return Container(
      decoration: BoxDecoration(
        color: backBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: backBorder,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE1D7E6).withValues(alpha: 0.5),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        children: [
          Center(
            child: Container(
              width: width * 0.6,
              height: height * 0.6,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: innerBorder,
                  width: 1.5,
                ),
              ),
              child: const Center(
                child: Text(
                  '🐥',
                  style: TextStyle(fontSize: 20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Draws suit symbols using Canvas paths — consistent colors on all platforms.
class _SuitPainter extends CustomPainter {
  final String suit;
  final Color color;

  _SuitPainter({required this.suit, required this.color});

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
    // Start at bottom tip
    path.moveTo(w * 0.5, h * 0.95);
    // Left curve
    path.cubicTo(w * -0.1, h * 0.55, w * -0.05, h * 0.1, w * 0.5, h * 0.3);
    // Right curve
    path.cubicTo(w * 1.05, h * 0.1, w * 1.1, h * 0.55, w * 0.5, h * 0.95);
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
    final path = Path();
    // Top tip
    path.moveTo(w * 0.5, 0);
    // Left curve
    path.cubicTo(w * -0.1, h * 0.35, w * -0.05, h * 0.75, w * 0.5, h * 0.6);
    // Right curve
    path.cubicTo(w * 1.05, h * 0.75, w * 1.1, h * 0.35, w * 0.5, 0);
    path.close();
    canvas.drawPath(path, paint);
    // Stem
    final stemPath = Path();
    stemPath.moveTo(w * 0.35, h * 0.6);
    stemPath.quadraticBezierTo(w * 0.5, h * 0.75, w * 0.5, h);
    stemPath.quadraticBezierTo(w * 0.5, h * 0.75, w * 0.65, h * 0.6);
    stemPath.lineTo(w * 0.58, h * 0.95);
    stemPath.lineTo(w * 0.42, h * 0.95);
    stemPath.close();
    canvas.drawPath(stemPath, paint);
  }

  void _drawClub(Canvas canvas, Size size, Paint paint) {
    final w = size.width;
    final h = size.height;
    final r = w * 0.24;
    // Three circles
    canvas.drawCircle(Offset(w * 0.5, h * 0.25), r, paint); // top
    canvas.drawCircle(Offset(w * 0.22, h * 0.52), r, paint); // left
    canvas.drawCircle(Offset(w * 0.78, h * 0.52), r, paint); // right
    // Stem
    final stemRect = Rect.fromLTWH(w * 0.4, h * 0.5, w * 0.2, h * 0.45);
    canvas.drawRect(stemRect, paint);
  }

  @override
  bool shouldRepaint(_SuitPainter old) => suit != old.suit || color != old.color;
}
