import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/cartoon.dart';

// 네 게임의 로고 — 직접 그린 카툰 벡터. 굵은 갈색 테두리 + 단색 몸통.
// 티츄(용 얼굴) · 스컬킹(왕관 쓴 해골) · 러브레터(하트 봉인 편지) · 마이티(스페이드 카드와 별).

class GameSymbol extends StatelessWidget {
  const GameSymbol(this.gameType, {super.key, this.size = 28});

  final String gameType;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _SymbolPainter(gameType)),
  );
}

class _SymbolPainter extends CustomPainter {
  _SymbolPainter(this.gameType);

  final String gameType;

  static const _red = Color(0xFFE53935);
  static const _yellow = Color(0xFFFFD84D);
  static const _paper = Color(0xFFFFFBF2);
  static const _bone = Color(0xFFFFF4DC);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final sw = (s * 0.07).clamp(1.2, 3.0);
    final pad = sw / 2 + 0.3;
    double x(double t) => pad + (s - pad * 2) * t;
    double y(double t) => pad + (s - pad * 2) * t;
    Offset p(double a, double b) => Offset(x(a), y(b));
    final line = Paint()
      ..color = Cartoon.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    Paint fill(Color c) => Paint()..color = c;
    void shape(Path path, Color c) {
      canvas.drawPath(path, fill(c));
      canvas.drawPath(path, line);
    }

    switch (gameType) {
      case 'skull_king':
        _skull(canvas, s, x, y, p, line, fill, shape);
      case 'love_letter':
        _letter(canvas, s, x, y, p, line, fill, shape);
      case 'mighty':
        _mighty(canvas, s, x, y, p, line, fill, shape);
      default:
        _dragon(canvas, s, x, y, p, line, fill, shape);
    }
  }

  void _dragon(
    Canvas canvas,
    double s,
    double Function(double) x,
    double Function(double) y,
    Offset Function(double, double) p,
    Paint line,
    Paint Function(Color) fill,
    void Function(Path, Color) shape,
  ) {
    const dark = Color(0xFFB71C1C);
    // 옆 지느러미(뾰족한 귀)
    for (final left in [true, false]) {
      final d = left ? 1.0 : -1.0;
      final cx = left ? 0.0 : 1.0;
      final fin = Path()
        ..moveTo(x(cx + d * 0.22), y(0.46))
        ..lineTo(x(cx + d * 0.06), y(0.40))
        ..lineTo(x(cx + d * 0.14), y(0.54))
        ..lineTo(x(cx + d * 0.06), y(0.66))
        ..lineTo(x(cx + d * 0.22), y(0.68))
        ..close();
      shape(fin, dark);
    }
    // 뿔: 뒤로 휘어진 긴 뿔
    for (final left in [true, false]) {
      final d = left ? 1.0 : -1.0;
      final cx = left ? 0.0 : 1.0;
      final horn = Path()
        ..moveTo(x(cx + d * 0.30), y(0.30))
        ..quadraticBezierTo(x(cx + d * 0.20), y(0.10), x(cx + d * 0.06), y(0.0))
        ..quadraticBezierTo(
          x(cx + d * 0.44),
          y(0.04),
          x(cx + d * 0.44),
          y(0.30),
        )
        ..close();
      shape(horn, _yellow);
    }
    // 얼굴: 위는 둥글고 아래로 좁아지는 역삼각 턱
    final face = Path()
      ..moveTo(x(0.20), y(0.50))
      ..quadraticBezierTo(x(0.20), y(0.22), x(0.5), y(0.22))
      ..quadraticBezierTo(x(0.80), y(0.22), x(0.80), y(0.50))
      ..quadraticBezierTo(x(0.80), y(0.80), x(0.5), y(0.97))
      ..quadraticBezierTo(x(0.20), y(0.80), x(0.20), y(0.50))
      ..close();
    shape(face, _red);
    // 이마 무늬
    final crest = Path()
      ..moveTo(x(0.5), y(0.24))
      ..lineTo(x(0.43), y(0.38))
      ..lineTo(x(0.57), y(0.38))
      ..close();
    shape(crest, dark);
    // 눈: 노란 눈 + 세로 눈동자 + 화난 눈썹
    for (final left in [true, false]) {
      final d = left ? 1.0 : -1.0;
      final cx = left ? 0.0 : 1.0;
      final ex = cx + d * 0.33;
      final eye = Path()
        ..moveTo(x(ex - 0.14), y(0.50))
        ..quadraticBezierTo(x(ex), y(0.36), x(ex + 0.14), y(0.50))
        ..quadraticBezierTo(x(ex), y(0.60), x(ex - 0.14), y(0.50))
        ..close();
      shape(eye, _yellow);
      canvas.drawLine(p(ex, 0.43), p(ex, 0.56), line);
      // 눈썹(안쪽이 아래로)
      final brow = Path()
        ..moveTo(x(ex - 0.11 * d), y(0.36))
        ..lineTo(x(ex + 0.11 * d), y(0.44));
      canvas.drawPath(brow, line..strokeWidth = line.strokeWidth * 1.3);
      line.strokeWidth = line.strokeWidth / 1.3;
    }
    // 주둥이와 콧구멍, 송곳니
    canvas.drawCircle(p(0.43, 0.70), s * 0.026, fill(Cartoon.ink));
    canvas.drawCircle(p(0.57, 0.70), s * 0.026, fill(Cartoon.ink));
    for (final fx in [0.40, 0.60]) {
      final fang = Path()
        ..moveTo(x(fx - 0.045), y(0.80))
        ..lineTo(x(fx), y(0.91))
        ..lineTo(x(fx + 0.045), y(0.80))
        ..close();
      shape(fang, _paper);
    }
    final mouth = Path()
      ..moveTo(x(0.34), y(0.79))
      ..quadraticBezierTo(x(0.5), y(0.84), x(0.66), y(0.79));
    canvas.drawPath(mouth, line);
  }

  void _skull(
    Canvas canvas,
    double s,
    double Function(double) x,
    double Function(double) y,
    Offset Function(double, double) p,
    Paint line,
    Paint Function(Color) fill,
    void Function(Path, Color) shape,
  ) {
    // 두개골
    final skull = Path()
      ..moveTo(x(0.16), y(0.58))
      ..quadraticBezierTo(x(0.10), y(0.24), x(0.5), y(0.24))
      ..quadraticBezierTo(x(0.90), y(0.24), x(0.84), y(0.58))
      ..quadraticBezierTo(x(0.83), y(0.72), x(0.72), y(0.76))
      ..lineTo(x(0.72), y(0.94))
      ..lineTo(x(0.28), y(0.94))
      ..lineTo(x(0.28), y(0.76))
      ..quadraticBezierTo(x(0.17), y(0.72), x(0.16), y(0.58))
      ..close();
    shape(skull, _bone);
    // 이빨 줄
    for (final tx in [0.40, 0.50, 0.60]) {
      canvas.drawLine(
        p(tx, 0.82),
        p(tx, 0.94),
        line..strokeWidth = line.strokeWidth * 0.7,
      );
    }
    line.strokeWidth = line.strokeWidth / 0.7;
    // 눈(화난)
    for (final left in [true, false]) {
      final d = left ? 1.0 : -1.0;
      final cx = left ? 0.0 : 1.0;
      final eye = Path()
        ..moveTo(x(cx + d * 0.18), y(0.46))
        ..lineTo(x(cx + d * 0.44), y(0.52))
        ..lineTo(x(cx + d * 0.40), y(0.68))
        ..quadraticBezierTo(
          x(cx + d * 0.26),
          y(0.74),
          x(cx + d * 0.20),
          y(0.62),
        )
        ..close();
      shape(eye, Cartoon.ink);
    }
    // 코
    final nose = Path()
      ..moveTo(x(0.5), y(0.64))
      ..lineTo(x(0.44), y(0.76))
      ..lineTo(x(0.56), y(0.76))
      ..close();
    shape(nose, Cartoon.ink);
    // 왕관
    final crown = Path()
      ..moveTo(x(0.22), y(0.30))
      ..lineTo(x(0.16), y(0.06))
      ..lineTo(x(0.34), y(0.18))
      ..lineTo(x(0.5), y(0.0))
      ..lineTo(x(0.66), y(0.18))
      ..lineTo(x(0.84), y(0.06))
      ..lineTo(x(0.78), y(0.30))
      ..close();
    shape(crown, _yellow);
    canvas.drawCircle(p(0.5, 0.17), s * 0.035, fill(_red));
  }

  void _letter(
    Canvas canvas,
    double s,
    double Function(double) x,
    double Function(double) y,
    Offset Function(double, double) p,
    Paint line,
    Paint Function(Color) fill,
    void Function(Path, Color) shape,
  ) {
    canvas.save();
    canvas.translate(x(0.5), y(0.5));
    canvas.rotate(-0.18);
    final r = RRect.fromLTRBR(
      -s * 0.46,
      -s * 0.32,
      s * 0.46,
      s * 0.32,
      Radius.circular(s * 0.08),
    );
    canvas.drawRRect(r, fill(_paper));
    canvas.drawRRect(r, line);
    // 뚜껑 선
    final flap = Path()
      ..moveTo(-s * 0.44, -s * 0.28)
      ..lineTo(0, s * 0.08)
      ..lineTo(s * 0.44, -s * 0.28);
    canvas.drawPath(flap, line);
    // 하트 봉인
    final hc = Offset(0, s * 0.06);
    final hs = s * 0.17;
    final heart = Path()
      ..moveTo(hc.dx, hc.dy + hs * 0.9)
      ..cubicTo(
        hc.dx - hs * 1.5,
        hc.dy - hs * 0.1,
        hc.dx - hs * 0.7,
        hc.dy - hs * 1.1,
        hc.dx,
        hc.dy - hs * 0.4,
      )
      ..cubicTo(
        hc.dx + hs * 0.7,
        hc.dy - hs * 1.1,
        hc.dx + hs * 1.5,
        hc.dy - hs * 0.1,
        hc.dx,
        hc.dy + hs * 0.9,
      )
      ..close();
    canvas.drawPath(heart, fill(const Color(0xFFFF4D79)));
    canvas.drawPath(heart, line);
    canvas.restore();
  }

  void _mighty(
    Canvas canvas,
    double s,
    double Function(double) x,
    double Function(double) y,
    Offset Function(double, double) p,
    Paint line,
    Paint Function(Color) fill,
    void Function(Path, Color) shape,
  ) {
    canvas.save();
    canvas.translate(x(0.48), y(0.54));
    canvas.rotate(0.16);
    final r = RRect.fromLTRBR(
      -s * 0.31,
      -s * 0.44,
      s * 0.31,
      s * 0.44,
      Radius.circular(s * 0.09),
    );
    canvas.drawRRect(r, fill(_paper));
    canvas.drawRRect(r, line);
    // 스페이드
    final sp = Path()
      ..moveTo(0, -s * 0.24)
      ..cubicTo(s * 0.34, s * 0.02, s * 0.20, s * 0.26, 0, s * 0.12)
      ..cubicTo(-s * 0.20, s * 0.26, -s * 0.34, s * 0.02, 0, -s * 0.24)
      ..close();
    canvas.drawPath(sp, fill(Cartoon.ink));
    final stem = Path()
      ..moveTo(0, s * 0.04)
      ..lineTo(-s * 0.09, s * 0.30)
      ..lineTo(s * 0.09, s * 0.30)
      ..close();
    canvas.drawPath(stem, fill(Cartoon.ink));
    canvas.restore();
    // 별
    final star = Path();
    final cx = x(0.80), cy = y(0.18), R = s * 0.17, r2 = R * 0.46;
    for (var i = 0; i < 10; i++) {
      final rad = i.isEven ? R : r2;
      final a = -math.pi / 2 + i * math.pi / 5;
      final pt = Offset(cx + rad * math.cos(a), cy + rad * math.sin(a));
      i == 0 ? star.moveTo(pt.dx, pt.dy) : star.lineTo(pt.dx, pt.dy);
    }
    star.close();
    shape(star, _yellow);
  }

  @override
  bool shouldRepaint(covariant _SymbolPainter old) => old.gameType != gameType;
}
