import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/cartoon.dart';
import 'game_symbols.dart';

/// 티츄 특수 카드(용·봉황·개·참새)의 그림 — 직접 그린 카툰 벡터.
/// 굵은 갈색 테두리 + 단색 몸통, 카드마다 파스텔 바탕과 모서리 표식.
class TichuSpecialArt extends StatelessWidget {
  const TichuSpecialArt(this.cardId, {super.key});

  final String cardId;

  static const _bg = {
    'special_dragon': Color(0xFFDDF3D2),
    'special_phoenix': Color(0xFFFFE7CC),
    'special_dog': Color(0xFFE3F1D6),
    'special_bird': Color(0xFFFFF1BF),
  };

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth.isFinite ? c.maxWidth : 60.0;
        final h = c.maxHeight.isFinite ? c.maxHeight : w * 1.5;
        final art = math.min(w * 0.94, h * 0.74);
        return Container(
          width: w,
          height: h,
          color: _bg[cardId] ?? Cartoon.paper,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _CornerMarks(cardId)),
              ),
              Align(
                alignment: const Alignment(0, 0.04),
                child: SizedBox(
                  width: art,
                  height: art,
                  child: cardId == 'special_dragon'
                      ? Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: CustomPaint(painter: _ArtPainter(cardId)),
                            ),
                            // 앱 심볼과 같은 얼굴을 몸 위에 얹는다.
                            Positioned(
                              left: art * 0.18,
                              top: art * 0.0,
                              width: art * 0.64,
                              height: art * 0.64,
                              child: const GameSymbol('tichu', size: 1000),
                            ),
                          ],
                        )
                      : CustomPaint(painter: _ArtPainter(cardId)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

Paint _fill(Color c) => Paint()..color = c;

Paint _line(double w) => Paint()
  ..color = Cartoon.ink
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeJoin = StrokeJoin.round
  ..strokeCap = StrokeCap.round;

/// 네 모서리 표식(불꽃·깃털·발바닥·숫자 1).
class _CornerMarks extends CustomPainter {
  _CornerMarks(this.cardId);

  final String cardId;

  @override
  void paint(Canvas canvas, Size size) {
    final m = size.width * 0.15;
    final pad = size.width * 0.10;
    final spots = [
      Offset(pad + m / 2, pad + m / 2),
      Offset(size.width - pad - m / 2, pad + m / 2),
      Offset(pad + m / 2, size.height - pad - m / 2),
      Offset(size.width - pad - m / 2, size.height - pad - m / 2),
    ];
    for (final o in spots) {
      canvas.save();
      canvas.translate(o.dx, o.dy);
      switch (cardId) {
        case 'special_dragon':
          _flame(canvas, m);
        case 'special_phoenix':
          _feather(canvas, m);
        case 'special_dog':
          _paw(canvas, m);
        default:
          _one(canvas, m);
      }
      canvas.restore();
    }
  }

  void _flame(Canvas canvas, double m) {
    final sw = (m * 0.12).clamp(1.0, 2.2);
    final p = Path()
      ..moveTo(0, -m * 0.55)
      ..quadraticBezierTo(m * 0.55, -m * 0.1, m * 0.35, m * 0.3)
      ..quadraticBezierTo(0, m * 0.65, -m * 0.35, m * 0.3)
      ..quadraticBezierTo(-m * 0.5, -m * 0.05, -m * 0.12, -m * 0.2)
      ..quadraticBezierTo(-m * 0.1, -m * 0.4, 0, -m * 0.55)
      ..close();
    canvas.drawPath(p, _fill(const Color(0xFFFF7A2F)));
    canvas.drawPath(p, _line(sw));
    canvas.drawCircle(
      Offset(0, m * 0.2),
      m * 0.14,
      _fill(const Color(0xFFFFD84D)),
    );
  }

  void _feather(Canvas canvas, double m) {
    final sw = (m * 0.12).clamp(1.0, 2.2);
    canvas.save();
    canvas.rotate(0.6);
    final p = Path()
      ..moveTo(0, -m * 0.6)
      ..quadraticBezierTo(m * 0.42, -m * 0.1, 0, m * 0.5)
      ..quadraticBezierTo(-m * 0.42, -m * 0.1, 0, -m * 0.6)
      ..close();
    canvas.drawPath(p, _fill(const Color(0xFF3E6BB5)));
    canvas.drawPath(p, _line(sw));
    canvas.drawLine(Offset(0, -m * 0.5), Offset(0, m * 0.65), _line(sw));
    canvas.restore();
  }

  void _paw(Canvas canvas, double m) {
    final sw = (m * 0.1).clamp(1.0, 2.0);
    final pad = _fill(const Color(0xFF6B4A2B));
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0, m * 0.18),
        width: m * 0.7,
        height: m * 0.55,
      ),
      pad,
    );
    for (final o in [
      Offset(-m * 0.34, -m * 0.12),
      Offset(-m * 0.12, -m * 0.34),
      Offset(m * 0.12, -m * 0.34),
      Offset(m * 0.34, -m * 0.12),
    ]) {
      canvas.drawCircle(o, m * 0.14, pad);
    }
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0, m * 0.18),
        width: m * 0.7,
        height: m * 0.55,
      ),
      _line(sw * 0.6),
    );
  }

  void _one(Canvas canvas, double m) {
    final tp = TextPainter(
      text: TextSpan(
        text: '1',
        style: TextStyle(
          fontSize: m * 1.15,
          fontFamily: 'Jua',
          fontWeight: FontWeight.w900,
          color: Cartoon.ink,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _CornerMarks old) => old.cardId != cardId;
}

class _ArtPainter extends CustomPainter {
  _ArtPainter(this.cardId);

  final String cardId;

  static const _orange = Color(0xFFFF8A2B);
  static const _yellow = Color(0xFFFFD84D);
  static const _paper = Color(0xFFFFFBF2);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final sw = (s * 0.03).clamp(1.2, 3.2);
    final line = _line(sw);
    double x(double t) => size.width * t;
    double y(double t) => size.height * t;
    Offset p(double a, double b) => Offset(x(a), y(b));
    void shape(Path path, Color c) {
      canvas.drawPath(path, _fill(c));
      canvas.drawPath(path, line);
    }

    switch (cardId) {
      case 'special_dragon':
        _dragon(canvas, size);
      case 'special_phoenix':
        _phoenix(canvas, size);
      case 'special_dog':
        // 귀(처진 갈색)
        for (final left in [true, false]) {
          final d = left ? -1.0 : 1.0;
          final ear = Path()
            ..moveTo(x(0.5 + d * 0.20), y(0.22))
            ..quadraticBezierTo(
              x(0.5 + d * 0.52),
              y(0.18),
              x(0.5 + d * 0.46),
              y(0.50),
            )
            ..quadraticBezierTo(
              x(0.5 + d * 0.30),
              y(0.56),
              x(0.5 + d * 0.22),
              y(0.40),
            )
            ..close();
          shape(ear, const Color(0xFF6B4A2B));
        }
        // 얼굴
        final face = Path()
          ..addOval(
            Rect.fromCenter(
              center: p(0.5, 0.50),
              width: x(0.62),
              height: y(0.58),
            ),
          );
        shape(face, _paper);
        // 눈 주위 무늬
        canvas.drawCircle(
          p(0.36, 0.44),
          s * 0.115,
          _fill(const Color(0xFF6B4A2B)),
        );
        // 눈
        for (final dx in [-0.14, 0.14]) {
          canvas.drawCircle(p(0.5 + dx, 0.44), s * 0.06, _fill(Cartoon.ink));
          canvas.drawCircle(
            p(0.5 + dx + 0.02, 0.425),
            s * 0.02,
            _fill(Colors.white),
          );
        }
        // 주둥이
        canvas.drawOval(
          Rect.fromCenter(
            center: p(0.5, 0.60),
            width: x(0.30),
            height: y(0.20),
          ),
          _fill(const Color(0xFFFFF0DC)),
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: p(0.5, 0.60),
            width: x(0.30),
            height: y(0.20),
          ),
          line,
        );
        final nose = Path()
          ..addOval(
            Rect.fromCenter(
              center: p(0.5, 0.55),
              width: x(0.12),
              height: y(0.07),
            ),
          );
        shape(nose, Cartoon.ink);
        // 입과 혀
        final tongue = Path()
          ..moveTo(x(0.44), y(0.64))
          ..quadraticBezierTo(x(0.44), y(0.76), x(0.5), y(0.76))
          ..quadraticBezierTo(x(0.56), y(0.76), x(0.56), y(0.64))
          ..close();
        shape(tongue, const Color(0xFFFF7A8A));
        canvas.drawPath(
          Path()
            ..moveTo(x(0.5), y(0.58))
            ..lineTo(x(0.5), y(0.64))
            ..moveTo(x(0.40), y(0.63))
            ..quadraticBezierTo(x(0.5), y(0.68), x(0.60), y(0.63)),
          line,
        );
        // 볼 홍조
        for (final dx in [-0.22, 0.22]) {
          canvas.drawCircle(
            p(0.5 + dx, 0.58),
            s * 0.04,
            _fill(const Color(0x66FF7A8A)),
          );
        }
      default: // 참새(1)
        // 나뭇가지
        canvas.drawPath(
          Path()
            ..moveTo(x(0.04), y(0.74))
            ..quadraticBezierTo(x(0.5), y(0.68), x(0.96), y(0.78)),
          _line(sw * 3.2)..color = Cartoon.ink,
        );
        canvas.drawPath(
          Path()
            ..moveTo(x(0.04), y(0.74))
            ..quadraticBezierTo(x(0.5), y(0.68), x(0.96), y(0.78)),
          _line(sw * 2)..color = const Color(0xFFB9783A),
        );
        // 꽃
        for (final (cx, cy) in [(0.18, 0.72), (0.84, 0.74)]) {
          for (var i = 0; i < 5; i++) {
            final a = i * 2 * math.pi / 5;
            canvas.drawCircle(
              p(
                cx,
                cy,
              ).translate(math.cos(a) * s * 0.05, math.sin(a) * s * 0.05),
              s * 0.04,
              _fill(const Color(0xFFFF6F61)),
            );
          }
          canvas.drawCircle(p(cx, cy), s * 0.03, _fill(_yellow));
        }
        // 꼬리
        final tail = Path()
          ..moveTo(x(0.34), y(0.56))
          ..lineTo(x(0.14), y(0.70))
          ..lineTo(x(0.22), y(0.52))
          ..close();
        shape(tail, const Color(0xFF8B5E34));
        // 몸통
        final body = Path()
          ..addOval(
            Rect.fromCenter(
              center: p(0.5, 0.52),
              width: x(0.46),
              height: y(0.40),
            ),
          );
        shape(body, const Color(0xFFB9783A));
        canvas.drawOval(
          Rect.fromCenter(
            center: p(0.54, 0.58),
            width: x(0.28),
            height: y(0.22),
          ),
          _fill(const Color(0xFFFFF1D6)),
        );
        // 날개
        final wing = Path()
          ..moveTo(x(0.36), y(0.48))
          ..quadraticBezierTo(x(0.30), y(0.64), x(0.48), y(0.64))
          ..quadraticBezierTo(x(0.54), y(0.54), x(0.36), y(0.48))
          ..close();
        shape(wing, const Color(0xFF8B5E34));
        // 머리
        canvas.drawCircle(
          p(0.62, 0.34),
          s * 0.15,
          _fill(const Color(0xFFB9783A)),
        );
        canvas.drawCircle(p(0.62, 0.34), s * 0.15, line);
        canvas.drawCircle(
          p(0.67, 0.36),
          s * 0.06,
          _fill(const Color(0xFFFFE9C9)),
        );
        final beak = Path()
          ..moveTo(x(0.74), y(0.32))
          ..lineTo(x(0.86), y(0.36))
          ..lineTo(x(0.74), y(0.40))
          ..close();
        shape(beak, _orange);
        canvas.drawCircle(p(0.66, 0.31), s * 0.026, _fill(Cartoon.ink));
        canvas.drawCircle(p(0.67, 0.30), s * 0.01, _fill(Colors.white));
        // 발
        for (final dx in [0.48, 0.56]) {
          canvas.drawLine(p(dx, 0.70), p(dx, 0.74), line);
        }
    }
  }

  void _cloud(Canvas canvas, Size size, double cx, double cy, double r) {
    final c = Paint()..color = Colors.white.withValues(alpha: 0.75);
    final w = size.width, h = size.height;
    for (final (dx, dy, k) in [
      (-0.9, 0.2, 0.7),
      (0.0, 0.0, 1.0),
      (0.95, 0.2, 0.75),
    ]) {
      canvas.drawCircle(
        Offset(w * cx + dx * r * w, h * cy + dy * r * w),
        r * w * k,
        c,
      );
    }
  }

  void _dragon(Canvas canvas, Size size) {
    final w = size.width, h = size.height, s = size.shortestSide;
    double x(double t) => w * t;
    double y(double t) => h * t;
    final sw = (s * 0.03).clamp(1.2, 3.2);
    const green = Color(0xFF4CAF3F);
    const greenDark = Color(0xFF2E8B34);
    const gold = Color(0xFFFFC928);
    const flame = Color(0xFFFF7A2F);

    _cloud(canvas, size, 0.18, 0.18, 0.08);
    _cloud(canvas, size, 0.86, 0.74, 0.07);

    // 몸통 중심선: 머리에서 내려와 S자로 감겨 꼬리까지
    final spine = Path()
      ..moveTo(x(0.50), y(0.44))
      ..cubicTo(x(0.10), y(0.46), x(0.12), y(0.69), x(0.50), y(0.69))
      ..cubicTo(x(0.90), y(0.69), x(0.88), y(0.91), x(0.42), y(0.91))
      ..cubicTo(x(0.30), y(0.91), x(0.22), y(0.89), x(0.16), y(0.84));
    final metric = spine.computeMetrics().first;
    final total = metric.length;

    // 몸통: 테두리 → 초록 → 배(연한 줄)
    Paint stroke(Color c, double wd) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = wd
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(spine, stroke(Cartoon.ink, s * 0.14 + sw * 2));
    canvas.drawPath(spine, stroke(green, s * 0.14));
    // 배 쪽 연한 줄(바깥 반대편으로 살짝 치우침은 생략하고 가운데 가늘게)
    canvas.drawPath(spine, stroke(const Color(0xFFB6E08A), s * 0.05));
    // 비늘 무늬
    for (var i = 1; i < 26; i++) {
      final t = total * i / 26;
      final tan = metric.getTangentForOffset(t)!;
      final n = Offset(-tan.vector.dy, tan.vector.dx);
      final c0 = tan.position + n * (s * 0.045);
      canvas.drawArc(
        Rect.fromCircle(center: c0, radius: s * 0.022),
        0,
        math.pi,
        false,
        _line(sw * 0.7)..color = greenDark,
      );
    }
    // 꼬리 끝 불꽃
    final tailEnd = metric.getTangentForOffset(total)!;
    canvas.save();
    canvas.translate(tailEnd.position.dx, tailEnd.position.dy);
    canvas.rotate(math.atan2(tailEnd.vector.dy, tailEnd.vector.dx));
    final tailFlame = Path()
      ..moveTo(0, -s * 0.05)
      ..quadraticBezierTo(s * 0.02, -s * 0.12, -s * 0.12, -s * 0.10)
      ..quadraticBezierTo(-s * 0.06, -s * 0.02, -s * 0.16, s * 0.04)
      ..quadraticBezierTo(-s * 0.04, s * 0.08, 0, s * 0.05)
      ..close();
    canvas.drawPath(tailFlame, _fill(flame));
    canvas.drawPath(tailFlame, _line(sw));
    canvas.drawCircle(Offset(-s * 0.03, 0), s * 0.025, _fill(gold));
    canvas.restore();

    // 앞발 하나(몸 가운데 아래쪽 곡선 안쪽)
    void paw(Offset at) {
      canvas.drawCircle(at, s * 0.045, _fill(green));
      canvas.drawCircle(at, s * 0.045, _line(sw));
      for (final dx in [-0.035, 0.0, 0.035]) {
        canvas.drawLine(
          at + Offset(dx * s, s * 0.04),
          at + Offset(dx * s * 1.3, s * 0.07),
          _line(sw * 1.1),
        );
      }
    }

    paw(Offset(x(0.26), y(0.56)));
    paw(Offset(x(0.74), y(0.80)));
  }

  void _phoenix(Canvas canvas, Size size) {
    final w = size.width, h = size.height, s = size.shortestSide;
    double x(double t) => w * t;
    double y(double t) => h * t;
    final sw = (s * 0.028).clamp(1.2, 3.2);
    const teal = Color(0xFF1FA8A0);
    const blue = Color(0xFF3E6BB5);
    const gold = Color(0xFFFFC928);

    _cloud(canvas, size, 0.16, 0.20, 0.08);
    _cloud(canvas, size, 0.86, 0.26, 0.07);

    // 깃털: 어깨에서 뻗어 나가는 곡선 잎. [curve] 로 끝을 휘게.
    void feather(
      Offset at,
      double angle,
      double len,
      double wid,
      Color c, {
      double curve = 0.0,
      bool eye = false,
      Color? tip,
    }) {
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(angle);
      final f = Path()
        ..moveTo(0, 0)
        ..cubicTo(
          wid,
          len * 0.25,
          wid * 1.1 + curve * len,
          len * 0.7,
          curve * len,
          len,
        )
        ..cubicTo(-wid * 1.1 + curve * len, len * 0.7, -wid, len * 0.25, 0, 0)
        ..close();
      canvas.drawPath(f, _fill(c));
      if (tip != null) {
        canvas.save();
        canvas.clipPath(f);
        canvas.drawRect(
          Rect.fromLTWH(-len, len * 0.6, len * 2, len),
          _fill(tip),
        );
        canvas.restore();
      }
      canvas.drawPath(f, _line(sw));
      if (eye) {
        final ec = Offset(curve * len * 0.85, len * 0.74);
        canvas.drawOval(
          Rect.fromCenter(center: ec, width: wid * 1.1, height: wid * 1.5),
          _fill(gold),
        );
        canvas.drawOval(
          Rect.fromCenter(center: ec, width: wid * 1.1, height: wid * 1.5),
          _line(sw * 0.7),
        );
        canvas.drawCircle(ec, wid * 0.22, _fill(blue));
      }
      canvas.restore();
    }

    final cx = x(0.5);
    // 꼬리깃 다섯 장(부채꼴, 끝이 살짝 휨)
    final tailAt = Offset(cx, y(0.60));
    feather(tailAt, -0.80, s * 0.36, s * 0.07, teal, curve: -0.10, eye: true);
    feather(tailAt, 0.80, s * 0.36, s * 0.07, teal, curve: 0.10, eye: true);
    feather(tailAt, -0.42, s * 0.42, s * 0.08, blue, curve: -0.08, eye: true);
    feather(tailAt, 0.42, s * 0.42, s * 0.08, blue, curve: 0.08, eye: true);
    feather(
      tailAt,
      0.0,
      s * 0.46,
      s * 0.09,
      const Color(0xFFFF7A2F),
      eye: true,
    );

    // 날개: 위로 활짝 펼친 깃 네 장씩
    for (final left in [true, false]) {
      final d = left ? -1.0 : 1.0;
      final sh = Offset(cx + d * s * 0.09, y(0.47));
      feather(sh, d * -2.55, s * 0.30, s * 0.07, gold);
      feather(sh, d * -2.15, s * 0.38, s * 0.085, const Color(0xFFFFA726));
      feather(sh, d * -1.78, s * 0.42, s * 0.09, const Color(0xFFFF7A2F));
      feather(sh, d * -1.45, s * 0.38, s * 0.085, const Color(0xFFE53935));
    }

    // 몸통
    final body = Rect.fromCenter(
      center: Offset(cx, y(0.50)),
      width: s * 0.24,
      height: s * 0.34,
    );
    canvas.drawOval(body, _fill(const Color(0xFFFF7A2F)));
    canvas.drawOval(body, _line(sw));
    final chest = Rect.fromCenter(
      center: Offset(cx, y(0.54)),
      width: s * 0.13,
      height: s * 0.20,
    );
    canvas.drawOval(chest, _fill(gold));

    // 목·머리(초록빛 노랑)
    final head = Offset(cx, y(0.31));
    canvas.drawCircle(head, s * 0.105, _fill(const Color(0xFFB8E04A)));
    canvas.drawCircle(head, s * 0.105, _line(sw));
    // 볏: 위로 휘어 올라간 세 가닥
    feather(
      Offset(cx - s * 0.02, y(0.235)),
      math.pi - 0.5,
      s * 0.14,
      s * 0.035,
      const Color(0xFFFF7A2F),
      curve: 0.10,
    );
    feather(
      Offset(cx, y(0.225)),
      math.pi,
      s * 0.17,
      s * 0.04,
      gold,
      curve: -0.08,
    );
    feather(
      Offset(cx + s * 0.02, y(0.235)),
      math.pi + 0.5,
      s * 0.14,
      s * 0.035,
      const Color(0xFFE53935),
      curve: -0.10,
    );
    // 부리
    final beak = Path()
      ..moveTo(cx - s * 0.035, y(0.325))
      ..lineTo(cx + s * 0.035, y(0.325))
      ..lineTo(cx, y(0.375))
      ..close();
    canvas.drawPath(beak, _fill(const Color(0xFFFF9A3C)));
    canvas.drawPath(beak, _line(sw * 0.9));
    // 눈
    for (final dx in [-0.045, 0.045]) {
      canvas.drawCircle(
        Offset(cx + dx * s, y(0.295)),
        s * 0.026,
        _fill(_paper),
      );
      canvas.drawCircle(
        Offset(cx + dx * s, y(0.295)),
        s * 0.026,
        _line(sw * 0.7),
      );
      canvas.drawCircle(
        Offset(cx + dx * s, y(0.297)),
        s * 0.014,
        _fill(Cartoon.ink),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ArtPainter old) => old.cardId != cardId;
}
