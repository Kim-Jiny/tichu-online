import 'package:flutter/material.dart';

import '../theme/cartoon.dart';
import 'host_crown.dart';

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

/// 비밀방 표시: 주황 자물쇠.
class LockIcon extends StatelessWidget {
  const LockIcon({super.key, this.width = 20, this.height = 20});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: CustomPaint(painter: _LockPainter()),
  );
}

class _LockPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final sw = (s * 0.1).clamp(1.2, 2.8);
    final pad = sw / 2 + 0.3;
    final ox = (size.width - s) / 2;
    final oy = (size.height - s) / 2;
    double x(double t) => ox + pad + (s - pad * 2) * t;
    double y(double t) => oy + pad + (s - pad * 2) * t;
    final line = _line(sw);

    // 고리
    final shackle = Path()
      ..moveTo(x(0.26), y(0.46))
      ..lineTo(x(0.26), y(0.30))
      ..arcToPoint(
        Offset(x(0.74), y(0.30)),
        radius: Radius.circular((s - pad * 2) * 0.24),
      )
      ..lineTo(x(0.74), y(0.46));
    canvas.drawPath(shackle, line..strokeWidth = sw * 1.15);
    line.strokeWidth = sw;
    // 몸통
    final body = RRect.fromLTRBR(
      x(0.12),
      y(0.44),
      x(0.88),
      y(0.96),
      Radius.circular(s * 0.14),
    );
    canvas.drawRRect(body, _fill(Cartoon.orange));
    canvas.drawRRect(body, line);
    // 열쇠 구멍
    canvas.drawCircle(Offset(x(0.5), y(0.64)), s * 0.07, _fill(Cartoon.ink));
    canvas.drawLine(Offset(x(0.5), y(0.66)), Offset(x(0.5), y(0.80)), line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// 관전 허용 표시: 눈.
class EyeIcon extends StatelessWidget {
  const EyeIcon({super.key, this.width = 24, this.height = 18});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: CustomPaint(painter: _EyePainter()),
  );
}

class _EyePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final sw = (h * 0.11).clamp(1.2, 2.8);
    final pad = sw / 2 + 0.3;
    double x(double t) => pad + (w - pad * 2) * t;
    double y(double t) => pad + (h - pad * 2) * t;
    final line = _line(sw);

    final eye = Path()
      ..moveTo(x(0.0), y(0.5))
      ..quadraticBezierTo(x(0.5), y(-0.45), x(1.0), y(0.5))
      ..quadraticBezierTo(x(0.5), y(1.45), x(0.0), y(0.5))
      ..close();
    canvas.drawPath(eye, _fill(Colors.white));
    final c = Offset(x(0.5), y(0.5));
    final r = (h - pad * 2) * 0.3;
    canvas.save();
    canvas.clipPath(eye);
    canvas.drawCircle(c, r, _fill(Cartoon.blue));
    canvas.restore();
    canvas.drawCircle(c, r, line..strokeWidth = sw * 0.8);
    line.strokeWidth = sw;
    canvas.drawCircle(c, r * 0.45, _fill(Cartoon.ink));
    canvas.drawCircle(
      Offset(c.dx - r * 0.3, c.dy - r * 0.3),
      r * 0.2,
      _fill(Colors.white),
    );
    canvas.drawPath(eye, line);
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
  if (asset.endsWith('private.webp')) {
    return LockIcon(width: width ?? 20, height: height ?? 20);
  }
  if (asset.endsWith('allowSpectators.webp')) {
    return EyeIcon(width: width ?? 24, height: height ?? 18);
  }
  if (asset.endsWith('crown.webp')) {
    return HostCrown(size: width ?? 34);
  }
  return null;
}
