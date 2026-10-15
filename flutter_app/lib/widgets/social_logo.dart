import 'package:flutter/material.dart';

/// 소셜 로그인/연동 버튼에 쓰는 로고들. 로그인 화면과 설정의 연동 팝업이 같이 쓴다.
class KakaoLogo extends StatelessWidget {
  const KakaoLogo({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _KakaoLogoPainter());
}

class _KakaoLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF3C1E1E)
      ..style = PaintingStyle.fill;

    final cx = size.width / 2;
    final cy = size.height * 0.42;
    final rx = size.width * 0.48;
    final ry = size.height * 0.36;

    // Speech bubble body (ellipse)
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2),
      paint,
    );

    // Speech bubble tail
    final tail = Path()
      ..moveTo(cx - size.width * 0.1, cy + ry * 0.75)
      ..lineTo(cx - size.width * 0.18, size.height * 0.92)
      ..lineTo(cx + size.width * 0.08, cy + ry * 0.85)
      ..close();
    canvas.drawPath(tail, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
