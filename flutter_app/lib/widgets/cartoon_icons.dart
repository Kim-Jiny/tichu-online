import 'package:flutter/material.dart';

import '../theme/cartoon.dart';

// 직접 그린 카툰 아이콘(벡터). 굵은 갈색 테두리 + 단색 몸통이라 어느 크기에서도 선명하다.

Paint _fill(Color c) => Paint()..color = c;

Paint _line(double w) => Paint()
  ..color = Cartoon.ink
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeJoin = StrokeJoin.round
  ..strokeCap = StrokeCap.round;

/// 랭크전 표시: 노란 트로피.
class RankedIcon extends StatelessWidget {
  const RankedIcon({super.key, this.width = 20, this.height = 18});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: CustomPaint(painter: _TrophyPainter()),
  );
}

class _TrophyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final sw = (s * 0.09).clamp(1.2, 2.6);
    final pad = sw / 2 + 0.3;
    final ox = (size.width - s) / 2;
    final oy = (size.height - s) / 2;
    double x(double t) => ox + pad + (s - pad * 2) * t;
    double y(double t) => oy + pad + (s - pad * 2) * t;
    final line = _line(sw);

    // 손잡이 두 개
    for (final left in [true, false]) {
      final sx = left ? 0.22 : 0.78;
      final ex = left ? 0.02 : 0.98;
      final h = Path()
        ..moveTo(x(sx), y(0.14))
        ..quadraticBezierTo(x(ex), y(0.10), x(left ? 0.10 : 0.90), y(0.40))
        ..quadraticBezierTo(
          x(left ? 0.16 : 0.84),
          y(0.52),
          x(left ? 0.26 : 0.74),
          y(0.52),
        );
      canvas.drawPath(h, line);
    }
    // 컵
    final cup = Path()
      ..moveTo(x(0.20), y(0.06))
      ..lineTo(x(0.80), y(0.06))
      ..lineTo(x(0.76), y(0.42))
      ..quadraticBezierTo(x(0.70), y(0.64), x(0.50), y(0.66))
      ..quadraticBezierTo(x(0.30), y(0.64), x(0.24), y(0.42))
      ..close();
    canvas.drawPath(cup, _fill(Cartoon.yellow));
    canvas.drawLine(
      Offset(x(0.30), y(0.14)),
      Offset(x(0.33), y(0.34)),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..strokeWidth = sw * 0.8
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(cup, line);
    // 받침대
    canvas.drawLine(Offset(x(0.50), y(0.66)), Offset(x(0.50), y(0.82)), line);
    final base = RRect.fromLTRBR(
      x(0.28),
      y(0.80),
      x(0.72),
      y(0.98),
      Radius.circular(s * 0.05),
    );
    canvas.drawRRect(base, _fill(Cartoon.orange));
    canvas.drawRRect(base, line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// 중도 참가(봇 자리 대체) 표시: 파란 로봇 얼굴.
class BotSwapIcon extends StatelessWidget {
  const BotSwapIcon({super.key, this.width = 20, this.height = 16});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: CustomPaint(painter: _RobotPainter()),
  );
}

class _RobotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final sw = (s * 0.09).clamp(1.2, 2.6);
    final pad = sw / 2 + 0.3;
    final ox = (size.width - s) / 2;
    final oy = (size.height - s) / 2;
    double x(double t) => ox + pad + (s - pad * 2) * t;
    double y(double t) => oy + pad + (s - pad * 2) * t;
    final line = _line(sw);

    // 안테나
    canvas.drawLine(Offset(x(0.5), y(0.20)), Offset(x(0.5), y(0.04)), line);
    canvas.drawCircle(Offset(x(0.5), y(0.06)), s * 0.07, _fill(Cartoon.red));
    canvas.drawCircle(
      Offset(x(0.5), y(0.06)),
      s * 0.07,
      line..strokeWidth = sw * 0.8,
    );
    line.strokeWidth = sw;
    // 귀
    for (final cx in [0.04, 0.96]) {
      final ear = RRect.fromLTRBR(
        x(cx - 0.04),
        y(0.46),
        x(cx + 0.04),
        y(0.72),
        Radius.circular(s * 0.04),
      );
      canvas.drawRRect(ear, _fill(Cartoon.orange));
      canvas.drawRRect(ear, line);
    }
    // 머리
    final head = RRect.fromLTRBR(
      x(0.10),
      y(0.20),
      x(0.90),
      y(0.94),
      Radius.circular(s * 0.2),
    );
    canvas.drawRRect(head, _fill(Cartoon.blue));
    canvas.drawRRect(head, line);
    // 눈
    for (final cx in [0.34, 0.66]) {
      canvas.drawCircle(Offset(x(cx), y(0.52)), s * 0.1, _fill(Colors.white));
      canvas.drawCircle(
        Offset(x(cx), y(0.52)),
        s * 0.1,
        line..strokeWidth = sw * 0.8,
      );
      canvas.drawCircle(Offset(x(cx), y(0.54)), s * 0.04, _fill(Cartoon.ink));
    }
    line.strokeWidth = sw;
    // 입
    canvas.drawLine(Offset(x(0.38), y(0.78)), Offset(x(0.62), y(0.78)), line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// 예전 이미지 경로로 부르던 곳을 위한 연결: 새로 그린 아이콘이 있으면 그것을 준다.
Widget? cartoonIconForAsset(String asset, {double? width, double? height}) {
  if (asset.endsWith('lankIcon.webp')) {
    return RankedIcon(width: width ?? 20, height: height ?? 18);
  }
  if (asset.endsWith('allowBotReplacement.webp')) {
    return BotSwapIcon(width: width ?? 20, height: height ?? 18);
  }
  return null;
}
