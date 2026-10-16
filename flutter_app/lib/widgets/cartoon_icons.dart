import 'dart:math' as math;
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

/// 룰북: 빨간 표지에 하얀 책장, 가운데 노란 별이 박힌 책.
class RulebookIcon extends StatelessWidget {
  const RulebookIcon({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _RulebookPainter()),
  );
}

class _RulebookPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final sw = (s * 0.075).clamp(1.2, 2.6);
    final pad = sw / 2 + 0.3;
    double x(double t) => pad + (s - pad * 2) * t;
    double y(double t) => pad + (s - pad * 2) * t;
    final line = _line(sw);

    // 책장(오른쪽·아래로 살짝 드러난 하얀 면)
    final pages = RRect.fromLTRBR(
      x(0.20),
      y(0.12),
      x(0.94),
      y(0.90),
      Radius.circular(s * 0.07),
    );
    canvas.drawRRect(pages, _fill(const Color(0xFFFFFBF2)));
    canvas.drawRRect(pages, line);
    // 책장 결
    final pageLine = _line(sw * 0.6)
      ..color = Cartoon.ink.withValues(alpha: 0.35);
    canvas.drawLine(
      Offset(x(0.30), y(0.96)),
      Offset(x(0.88), y(0.96)),
      pageLine,
    );

    // 표지
    final cover = RRect.fromLTRBR(
      x(0.06),
      y(0.06),
      x(0.84),
      y(0.84),
      Radius.circular(s * 0.09),
    );
    canvas.drawRRect(cover, _fill(const Color(0xFFFF5A5F)));
    canvas.drawRRect(cover, line);
    // 책등
    canvas.drawLine(Offset(x(0.20), y(0.08)), Offset(x(0.20), y(0.82)), line);

    // 별
    final cx = x(0.53), cy = y(0.45), r = s * 0.19, r2 = r * 0.45;
    final star = Path();
    for (var i = 0; i < 10; i++) {
      final rad = i.isEven ? r : r2;
      final a = -3.14159265 / 2 + i * 3.14159265 / 5;
      final px = cx + rad * _cos(a), py = cy + rad * _sin(a);
      if (i == 0) {
        star.moveTo(px, py);
      } else {
        star.lineTo(px, py);
      }
    }
    star.close();
    canvas.drawPath(star, _fill(const Color(0xFFFFD84D)));
    canvas.drawPath(star, _line(sw * 0.8));
  }

  double _cos(double a) => math.cos(a);
  double _sin(double a) => math.sin(a);

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 룰북 섹션 제목 앞에 붙는 그림들. 굵은 갈색 테두리 + 단색 몸통으로 직접 그렸다.
enum RuleGlyphKind {
  goal,
  cards,
  megaphone,
  order,
  combos,
  bomb,
  score,
  trophy,
  eye,
  gavel,
  ban,
  people,
  swap,
  sparkle,
  target,
  star,
  puzzle,
  check,
}

class RuleGlyph extends StatelessWidget {
  const RuleGlyph(this.kind, {super.key, this.size = 28});

  final RuleGlyphKind kind;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _RuleGlyphPainter(kind)),
  );
}

class _RuleGlyphPainter extends CustomPainter {
  _RuleGlyphPainter(this.kind);

  final RuleGlyphKind kind;

  static const _red = Color(0xFFFF5A5F);
  static const _yellow = Color(0xFFFFD84D);
  static const _blue = Color(0xFF4A90D9);
  static const _green = Color(0xFF4CAF50);
  static const _paper = Color(0xFFFFFBF2);
  static const _orange = Color(0xFFFF9F43);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final sw = (s * 0.075).clamp(1.2, 2.6);
    final pad = sw / 2 + 0.3;
    double x(double t) => pad + (s - pad * 2) * t;
    double y(double t) => pad + (s - pad * 2) * t;
    Offset p(double a, double b) => Offset(x(a), y(b));
    final line = _line(sw);
    void shape(Path path, Color c) {
      canvas.drawPath(path, _fill(c));
      canvas.drawPath(path, line);
    }

    RRect rr(double l, double t, double r, double b, double rad) =>
        RRect.fromLTRBR(x(l), y(t), x(r), y(b), Radius.circular(s * rad));

    switch (kind) {
      case RuleGlyphKind.goal:
        canvas.drawLine(
          p(0.22, 0.10),
          p(0.22, 0.94),
          line..strokeWidth = sw * 1.2,
        );
        final f = Path()
          ..moveTo(x(0.24), y(0.12))
          ..quadraticBezierTo(x(0.45), y(0.02), x(0.62), y(0.14))
          ..quadraticBezierTo(x(0.80), y(0.26), x(0.94), y(0.14))
          ..lineTo(x(0.94), y(0.56))
          ..quadraticBezierTo(x(0.80), y(0.68), x(0.62), y(0.56))
          ..quadraticBezierTo(x(0.45), y(0.44), x(0.24), y(0.54))
          ..close();
        shape(f, _red);
      case RuleGlyphKind.cards:
        canvas.save();
        canvas.translate(x(0.36), y(0.52));
        canvas.rotate(-0.28);
        final back = RRect.fromLTRBR(
          -s * 0.24,
          -s * 0.34,
          s * 0.24,
          s * 0.34,
          Radius.circular(s * 0.07),
        );
        canvas.drawRRect(back, _fill(_blue));
        canvas.drawRRect(back, line);
        canvas.restore();
        canvas.save();
        canvas.translate(x(0.62), y(0.52));
        canvas.rotate(0.2);
        final front = RRect.fromLTRBR(
          -s * 0.24,
          -s * 0.34,
          s * 0.24,
          s * 0.34,
          Radius.circular(s * 0.07),
        );
        canvas.drawRRect(front, _fill(_paper));
        canvas.drawRRect(front, line);
        final d = Path()
          ..moveTo(0, -s * 0.14)
          ..lineTo(s * 0.11, 0)
          ..lineTo(0, s * 0.14)
          ..lineTo(-s * 0.11, 0)
          ..close();
        canvas.drawPath(d, _fill(_red));
        canvas.drawPath(d, _line(sw * 0.8));
        canvas.restore();
      case RuleGlyphKind.megaphone:
        final cone = Path()
          ..moveTo(x(0.14), y(0.36))
          ..lineTo(x(0.56), y(0.16))
          ..lineTo(x(0.56), y(0.84))
          ..lineTo(x(0.14), y(0.64))
          ..close();
        shape(cone, _yellow);
        shape(Path()..addRRect(rr(0.04, 0.34, 0.22, 0.66, 0.05)), _orange);
        shape(Path()..addRRect(rr(0.56, 0.12, 0.70, 0.88, 0.05)), _red);
        final grip = Path()
          ..moveTo(x(0.22), y(0.64))
          ..lineTo(x(0.30), y(0.92))
          ..lineTo(x(0.44), y(0.90))
          ..lineTo(x(0.42), y(0.72));
        canvas.drawPath(grip, line);
        canvas.drawLine(p(0.80, 0.30), p(0.96, 0.22), line);
        canvas.drawLine(p(0.82, 0.50), p(0.98, 0.50), line);
        canvas.drawLine(p(0.80, 0.70), p(0.96, 0.78), line);
      case RuleGlyphKind.order:
        for (var i = 0; i < 3; i++) {
          final cy = 0.20 + i * 0.30;
          canvas.drawCircle(
            p(0.18, cy),
            s * 0.11,
            _fill(i == 0 ? _red : _blue),
          );
          canvas.drawCircle(p(0.18, cy), s * 0.11, line);
          shape(
            Path()..addRRect(rr(0.38, cy - 0.09, 0.96, cy + 0.09, 0.05)),
            _paper,
          );
        }
      case RuleGlyphKind.combos:
        for (var i = 0; i < 3; i++) {
          canvas.save();
          canvas.translate(x(0.5), y(0.80));
          canvas.rotate(-0.5 + i * 0.5);
          final c = RRect.fromLTRBR(
            -s * 0.19,
            -s * 0.68,
            s * 0.19,
            s * 0.06,
            Radius.circular(s * 0.06),
          );
          canvas.drawRRect(
            c,
            _fill(i == 2 ? _red : (i == 1 ? _yellow : _paper)),
          );
          canvas.drawRRect(c, line);
          canvas.restore();
        }
      case RuleGlyphKind.bomb:
        canvas.drawCircle(
          p(0.46, 0.60),
          s * 0.34,
          _fill(const Color(0xFF3B3B4F)),
        );
        canvas.drawCircle(p(0.46, 0.60), s * 0.34, line);
        canvas.drawCircle(
          p(0.34, 0.48),
          s * 0.07,
          _fill(Colors.white.withValues(alpha: 0.7)),
        );
        shape(
          Path()..addRRect(rr(0.38, 0.16, 0.56, 0.30, 0.03)),
          const Color(0xFF6B6B7F),
        );
        final fuse = Path()
          ..moveTo(x(0.50), y(0.16))
          ..quadraticBezierTo(x(0.62), y(0.04), x(0.78), y(0.12));
        canvas.drawPath(fuse, line);
        final spark = Path();
        for (var i = 0; i < 8; i++) {
          final r = i.isEven ? s * 0.11 : s * 0.05;
          final a = i * math.pi / 4;
          final pt = Offset(
            x(0.84) + r * math.cos(a),
            y(0.12) + r * math.sin(a),
          );
          i == 0 ? spark.moveTo(pt.dx, pt.dy) : spark.lineTo(pt.dx, pt.dy);
        }
        spark.close();
        shape(spark, _yellow);
      case RuleGlyphKind.score:
        for (var i = 2; i >= 0; i--) {
          final cy = 0.34 + i * 0.22;
          final e = Rect.fromLTRB(x(0.10), y(cy - 0.12), x(0.90), y(cy + 0.12));
          final body = Path()
            ..addRect(
              Rect.fromLTRB(
                e.left,
                e.center.dy,
                e.right,
                e.bottom - e.height * 0.0,
              ),
            )
            ..addOval(e);
          canvas.drawOval(
            Rect.fromLTRB(
              e.left,
              e.top + s * 0.08,
              e.right,
              e.bottom + s * 0.08,
            ),
            _fill(const Color(0xFFE0A800)),
          );
          canvas.drawOval(e, _fill(_yellow));
          canvas.drawOval(e, line);
          body.close();
        }
        canvas.drawCircle(p(0.5, 0.34), s * 0.07, _line(sw * 0.8));
      case RuleGlyphKind.trophy:
        _TrophyPainter().paint(canvas, size);
      case RuleGlyphKind.eye:
        final eye = Path()
          ..moveTo(x(0.02), y(0.5))
          ..quadraticBezierTo(x(0.5), y(0.02), x(0.98), y(0.5))
          ..quadraticBezierTo(x(0.5), y(0.98), x(0.02), y(0.5))
          ..close();
        shape(eye, _paper);
        canvas.drawCircle(p(0.5, 0.5), s * 0.2, _fill(_blue));
        canvas.drawCircle(p(0.5, 0.5), s * 0.2, line);
        canvas.drawCircle(
          p(0.5, 0.5),
          s * 0.08,
          _fill(const Color(0xFF2B2B3A)),
        );
        canvas.drawCircle(p(0.56, 0.44), s * 0.04, _fill(Colors.white));
      case RuleGlyphKind.gavel:
        canvas.save();
        canvas.translate(x(0.5), y(0.46));
        canvas.rotate(-0.6);
        final head = RRect.fromLTRBR(
          -s * 0.30,
          -s * 0.30,
          s * 0.30,
          -s * 0.04,
          Radius.circular(s * 0.07),
        );
        final handle = RRect.fromLTRBR(
          -s * 0.06,
          -s * 0.06,
          s * 0.06,
          s * 0.52,
          Radius.circular(s * 0.04),
        );
        canvas.drawRRect(handle, _fill(const Color(0xFFB9783A)));
        canvas.drawRRect(handle, line);
        canvas.drawRRect(head, _fill(_orange));
        canvas.drawRRect(head, line);
        canvas.restore();
        shape(Path()..addRRect(rr(0.44, 0.84, 0.98, 0.96, 0.04)), _paper);
      case RuleGlyphKind.ban:
        canvas.drawCircle(p(0.5, 0.5), s * 0.42, _fill(_red));
        canvas.drawCircle(p(0.5, 0.5), s * 0.42, line);
        shape(Path()..addRRect(rr(0.22, 0.42, 0.78, 0.58, 0.05)), _paper);
      case RuleGlyphKind.people:
        for (final (cx, col) in [(0.34, _blue), (0.68, _orange)]) {
          canvas.drawCircle(p(cx, 0.32), s * 0.16, _fill(_paper));
          canvas.drawCircle(p(cx, 0.32), s * 0.16, line);
          final body = Path()
            ..moveTo(x(cx - 0.26), y(0.92))
            ..quadraticBezierTo(x(cx - 0.26), y(0.54), x(cx), y(0.54))
            ..quadraticBezierTo(x(cx + 0.26), y(0.54), x(cx + 0.26), y(0.92))
            ..close();
          shape(body, col);
        }
      case RuleGlyphKind.swap:
        for (final top in [true, false]) {
          final yy = top ? 0.32 : 0.68;
          canvas.drawLine(p(0.10, yy), p(0.80, yy), line);
          final ah = Path();
          if (top) {
            ah
              ..moveTo(x(0.62), y(yy - 0.18))
              ..lineTo(x(0.94), y(yy))
              ..lineTo(x(0.62), y(yy + 0.18))
              ..close();
          } else {
            ah
              ..moveTo(x(0.38), y(yy - 0.18))
              ..lineTo(x(0.06), y(yy))
              ..lineTo(x(0.38), y(yy + 0.18))
              ..close();
          }
          shape(ah, top ? _red : _blue);
        }
      case RuleGlyphKind.sparkle:
        Path star4(double cx, double cy, double r) => Path()
          ..moveTo(x(cx), y(cy - r))
          ..quadraticBezierTo(x(cx), y(cy), x(cx + r), y(cy))
          ..quadraticBezierTo(x(cx), y(cy), x(cx), y(cy + r))
          ..quadraticBezierTo(x(cx), y(cy), x(cx - r), y(cy))
          ..quadraticBezierTo(x(cx), y(cy), x(cx), y(cy - r))
          ..close();
        shape(star4(0.42, 0.56, 0.40), _yellow);
        shape(star4(0.82, 0.18, 0.16), _orange);
        shape(star4(0.84, 0.82, 0.12), _paper);
      case RuleGlyphKind.target:
        canvas.drawCircle(p(0.5, 0.5), s * 0.42, _fill(_paper));
        canvas.drawCircle(p(0.5, 0.5), s * 0.42, line);
        canvas.drawCircle(p(0.5, 0.5), s * 0.28, _fill(_red));
        canvas.drawCircle(p(0.5, 0.5), s * 0.28, line);
        canvas.drawCircle(p(0.5, 0.5), s * 0.14, _fill(_paper));
        canvas.drawCircle(p(0.5, 0.5), s * 0.14, line);
        canvas.drawCircle(p(0.5, 0.5), s * 0.04, _fill(Cartoon.ink));
      case RuleGlyphKind.star:
        final st = Path();
        for (var i = 0; i < 10; i++) {
          final r = i.isEven ? s * 0.44 : s * 0.19;
          final a = -math.pi / 2 + i * math.pi / 5;
          final pt = Offset(
            x(0.5) + r * math.cos(a),
            y(0.54) + r * math.sin(a),
          );
          i == 0 ? st.moveTo(pt.dx, pt.dy) : st.lineTo(pt.dx, pt.dy);
        }
        st.close();
        shape(st, _yellow);
      case RuleGlyphKind.puzzle:
        final pz = Path()
          ..moveTo(x(0.12), y(0.30))
          ..lineTo(x(0.40), y(0.30))
          ..arcToPoint(
            p(0.60, 0.30),
            radius: Radius.circular(s * 0.10),
            clockwise: false,
          )
          ..lineTo(x(0.88), y(0.30))
          ..lineTo(x(0.88), y(0.50))
          ..arcToPoint(
            p(0.88, 0.70),
            radius: Radius.circular(s * 0.10),
            clockwise: false,
          )
          ..lineTo(x(0.88), y(0.90))
          ..lineTo(x(0.12), y(0.90))
          ..close();
        shape(pz, _green);
      case RuleGlyphKind.check:
        final ck = Path()
          ..moveTo(x(0.14), y(0.54))
          ..lineTo(x(0.40), y(0.80))
          ..lineTo(x(0.88), y(0.22));
        canvas.drawPath(ck, _line(sw * 2.4)..color = Cartoon.ink);
        canvas.drawPath(ck, _line(sw * 1.3)..color = _green);
    }
  }

  @override
  bool shouldRepaint(covariant _RuleGlyphPainter old) => old.kind != kind;
}

/// 쿠폰 아이콘: 양옆이 움푹 파인 노란 티켓, 가운데 점선, 왼쪽에 큼직한 별.
/// 살짝 기울어 있어서 "뜯어 쓰는 쿠폰"처럼 보인다.
class CouponGlyph extends StatelessWidget {
  const CouponGlyph({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _CouponPainter()),
  );
}

class _CouponPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final sw = (s * 0.075).clamp(1.2, 2.6);
    final line = _line(sw);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-0.16);
    // 티켓 몸통: 폭 0.94s · 높이 0.62s. 좌우 가운데에 반원 홈.
    final w = s * 0.94 - sw;
    final h = s * 0.62 - sw;
    final r = s * 0.10; // 모서리 둥글기
    final notch = s * 0.095; // 홈 반지름
    final left = -w / 2, right = w / 2, top = -h / 2, bottom = h / 2;
    final body = Path()
      ..moveTo(left + r, top)
      ..lineTo(right - r, top)
      ..arcToPoint(Offset(right, top + r), radius: Radius.circular(r))
      ..lineTo(right, -notch)
      ..arcToPoint(
        Offset(right, notch),
        radius: Radius.circular(notch),
        clockwise: false,
      )
      ..lineTo(right, bottom - r)
      ..arcToPoint(Offset(right - r, bottom), radius: Radius.circular(r))
      ..lineTo(left + r, bottom)
      ..arcToPoint(Offset(left, bottom - r), radius: Radius.circular(r))
      ..lineTo(left, notch)
      ..arcToPoint(
        Offset(left, -notch),
        radius: Radius.circular(notch),
        clockwise: false,
      )
      ..lineTo(left, top + r)
      ..arcToPoint(Offset(left + r, top), radius: Radius.circular(r))
      ..close();
    // 바닥 그림자(단색)
    canvas.drawPath(body.shift(Offset(0, sw * 0.9)), _fill(Cartoon.ink));
    canvas.drawPath(body, _fill(Cartoon.yellow));
    // 아래쪽 절반을 살짝 진하게 — 통통한 느낌
    canvas.save();
    canvas.clipPath(body);
    canvas.drawRect(
      Rect.fromLTRB(left, h * 0.18, right, bottom),
      _fill(const Color(0xFFFFC21A)),
    );
    canvas.restore();
    canvas.drawPath(body, line);
    // 점선(오른쪽 1/3 지점)
    final dx = w * 0.18;
    final dash = Paint()
      ..color = Cartoon.ink.withValues(alpha: 0.55)
      ..strokeWidth = sw * 0.7
      ..strokeCap = StrokeCap.round;
    final span = h - r * 1.4;
    const n = 5;
    for (var i = 0; i < n; i++) {
      final y0 = -span / 2 + span * (i / n) + span / n * 0.15;
      final y1 = y0 + span / n * 0.55;
      canvas.drawLine(Offset(dx, y0), Offset(dx, y1), dash);
    }
    // 왼쪽의 별
    final cx = -w * 0.10;
    final cy = 0.0;
    final star = Path();
    final R = h * 0.31;
    final rr = R * 0.45;
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5;
      final rad = i.isEven ? R : rr;
      final p = Offset(cx + rad * math.cos(a), cy + rad * math.sin(a));
      if (i == 0) {
        star.moveTo(p.dx, p.dy);
      } else {
        star.lineTo(p.dx, p.dy);
      }
    }
    star.close();
    canvas.drawPath(star, _fill(Cartoon.orange));
    canvas.drawPath(star, line..strokeWidth = sw * 0.85);
    // 별 하이라이트
    canvas.drawCircle(
      Offset(cx - R * 0.18, cy - R * 0.3),
      R * 0.11,
      _fill(Colors.white.withValues(alpha: 0.85)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
