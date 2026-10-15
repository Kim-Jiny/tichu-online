import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 스컬킹 숫자 카드의 문양별 색. 게임 화면과 룰북이 같은 카드를 그리도록 한 곳에 둔다.
const Map<String, Color> skSuitColors = {
  'yellow': Color(0xFFD4A017),
  'green': Color(0xFF2E7D32),
  'purple': Color(0xFF6A1B9A),
  'black': Color(0xFF212121),
};

/// 스컬킹 숫자 카드. 비율은 가로 0.7 : 세로 1, [size] 는 세로 길이.
class SkNumberCard extends StatelessWidget {
  const SkNumberCard({
    super.key,
    required this.suit,
    required this.rank,
    this.size = 60,
    this.border,
    this.shadow,
  });

  final String suit;
  final String rank;
  final double size;
  final BoxBorder? border;
  final List<BoxShadow>? shadow;

  @override
  Widget build(BuildContext context) {
    final color = skSuitColors[suit] ?? Colors.grey;
    final w = size * 0.7;

    Widget corner() => Column(
      children: [
        Text(
          rank,
          style: TextStyle(
            fontSize: size * 0.18,
            fontWeight: FontWeight.w900,
            color: color,
            height: 1.0,
          ),
        ),
        SizedBox(
          width: size * 0.13,
          height: size * 0.13,
          child: CustomPaint(
            painter: SkSuitPainter(suit: suit, color: color),
            size: Size.square(size * 0.13),
          ),
        ),
      ],
    );

    return Container(
      width: w,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border:
            border ?? Border.all(color: Colors.black.withValues(alpha: 0.15)),
        boxShadow: shadow,
      ),
      child: Stack(
        children: [
          Positioned(left: 3, top: 2, child: corner()),
          Center(
            child: SizedBox(
              width: size * 0.32,
              height: size * 0.32,
              child: CustomPaint(
                painter: SkSuitPainter(
                  suit: suit,
                  color: color.withValues(alpha: 0.25),
                ),
              ),
            ),
          ),
          Positioned(
            right: 3,
            bottom: 2,
            child: Transform.rotate(angle: math.pi, child: corner()),
          ),
        ],
      ),
    );
  }
}

class SkSuitPainter extends CustomPainter {
  const SkSuitPainter({required this.suit, required this.color});

  final String suit;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    switch (suit) {
      case 'purple':
        _drawDiamond(canvas, size, paint);
        break;
      case 'green':
        _drawClub(canvas, size, paint);
        break;
      case 'yellow':
        _drawStar(canvas, size, paint);
        break;
      case 'black':
        _drawSkull(canvas, size, paint);
        break;
      default:
        _drawDiamond(canvas, size, paint);
        break;
    }
  }

  void _drawDiamond(Canvas canvas, Size size, Paint paint) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(0, size.height / 2)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawClub(Canvas canvas, Size size, Paint paint) {
    final r = size.width * 0.18;
    canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.28), r, paint);
    canvas.drawCircle(Offset(size.width * 0.3, size.height * 0.52), r, paint);
    canvas.drawCircle(Offset(size.width * 0.7, size.height * 0.52), r, paint);
    final stem = Path()
      ..moveTo(size.width * 0.45, size.height * 0.58)
      ..lineTo(size.width * 0.55, size.height * 0.58)
      ..lineTo(size.width * 0.62, size.height * 0.9)
      ..lineTo(size.width * 0.38, size.height * 0.9)
      ..close();
    canvas.drawPath(stem, paint);
  }

  void _drawStar(Canvas canvas, Size size, Paint paint) {
    final center = Offset(size.width / 2, size.height / 2);
    final outer = size.width / 2;
    final inner = outer * 0.45;
    final path = Path();
    for (int i = 0; i < 10; i++) {
      final radius = i.isEven ? outer : inner;
      final angle = -1.5708 + i * 0.6283;
      final point = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawSkull(Canvas canvas, Size size, Paint paint) {
    canvas.drawOval(
      Rect.fromLTWH(
        size.width * 0.2,
        size.height * 0.1,
        size.width * 0.6,
        size.height * 0.55,
      ),
      paint,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * 0.32,
        size.height * 0.62,
        size.width * 0.36,
        size.height * 0.18,
      ),
      paint,
    );

    final cutout = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.fill;
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawOval(
      Rect.fromLTWH(
        size.width * 0.2,
        size.height * 0.1,
        size.width * 0.6,
        size.height * 0.55,
      ),
      paint,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * 0.32,
        size.height * 0.62,
        size.width * 0.36,
        size.height * 0.18,
      ),
      paint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.38, size.height * 0.36),
      size.width * 0.08,
      cutout,
    );
    canvas.drawCircle(
      Offset(size.width * 0.62, size.height * 0.36),
      size.width * 0.08,
      cutout,
    );
    final nose = Path()
      ..moveTo(size.width * 0.5, size.height * 0.45)
      ..lineTo(size.width * 0.44, size.height * 0.56)
      ..lineTo(size.width * 0.56, size.height * 0.56)
      ..close();
    canvas.drawPath(nose, cutout);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant SkSuitPainter oldDelegate) {
    return suit != oldDelegate.suit || color != oldDelegate.color;
  }
}
