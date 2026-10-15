import 'package:flutter/material.dart';

import '../theme/cartoon.dart';

/// 방장 왕관: 카툰 스타일로 직접 그린 벡터 아이콘(굵은 갈색 테두리 + 노란 몸통).
///
/// 이미지 파일 대신 CustomPainter 로 그려서 어떤 크기·기기에서도 선명하고,
/// 플랫폼마다 모양이 달라지는 이모지에도 기대지 않는다.
class HostCrown extends StatelessWidget {
  /// 그려지는 너비. 높이는 너비의 0.8배.
  final double size;

  const HostCrown({super.key, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 0.8,
      child: CustomPaint(painter: _CrownPainter()),
    );
  }
}

class _CrownPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = (w * 0.09).clamp(1.4, 3.0);
    // 바깥 여백: 테두리가 잘리지 않게 안쪽으로 그린다.
    final pad = stroke / 2 + 0.5;
    double x(double t) => pad + (w - pad * 2) * t;
    double y(double t) => pad + (h - pad * 2) * t;

    // 왕관 몸통: 뾰족한 세 봉우리와 두 골짜기.
    final body = Path()
      ..moveTo(x(0.04), y(0.30))
      ..lineTo(x(0.26), y(0.58))
      ..lineTo(x(0.50), y(0.12))
      ..lineTo(x(0.74), y(0.58))
      ..lineTo(x(0.96), y(0.30))
      ..lineTo(x(0.88), y(0.90))
      ..lineTo(x(0.12), y(0.90))
      ..close();

    final fill = Paint()..color = Cartoon.yellow;
    final line = Paint()
      ..color = Cartoon.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(body, fill);

    // 아래쪽 띠(살짝 진한 노랑)
    final band = Path()
      ..moveTo(x(0.105), y(0.68))
      ..lineTo(x(0.895), y(0.68))
      ..lineTo(x(0.88), y(0.90))
      ..lineTo(x(0.12), y(0.90))
      ..close();
    canvas.drawPath(band, Paint()..color = Cartoon.orange);

    // 왼쪽 위 하이라이트
    canvas.drawLine(
      Offset(x(0.16), y(0.36)),
      Offset(x(0.24), y(0.48)),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..strokeWidth = stroke * 0.8
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawPath(body, line);
    canvas.drawLine(Offset(x(0.105), y(0.68)), Offset(x(0.895), y(0.68)), line);

    // 봉우리 끝 구슬
    final r = w * 0.075;
    for (final c in [
      Offset(x(0.04), y(0.30)),
      Offset(x(0.50), y(0.12)),
      Offset(x(0.96), y(0.30)),
    ]) {
      canvas.drawCircle(c, r, Paint()..color = Cartoon.red);
      canvas.drawCircle(c, r, line..strokeWidth = stroke * 0.8);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
