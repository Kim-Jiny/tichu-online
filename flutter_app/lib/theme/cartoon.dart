import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 카툰 스타일 UI 의 공통 재료.
///
/// 규칙 세 가지만 지키면 어느 화면이든 같은 결이 난다.
///  1. 모든 면은 진한 [Cartoon.ink] 테두리(2.5~3px)로 둘러싼다.
///  2. 그림자는 번지지 않는 단색, 아래로만 어긋나게 (스티커처럼).
///  3. 제목·버튼 글자는 [Cartoon.font](Jua) 에 두꺼운 외곽선.
///
/// 화면은 이 파일의 위젯만 쓰고 색·그림자를 직접 정하지 않는다 — 스타일을
/// 바꾸고 싶을 때 여기 한 곳만 고치면 된다.
class Cartoon {
  Cartoon._();

  static const String font = 'Jua';

  /// 모든 테두리와 단색 그림자의 색.
  static const Color ink = Color(0xFF3B2A20);

  static const Color cream = Color(0xFFFFF4DC);
  static const Color paper = Color(0xFFFFFBF2);
  static const Color skyTop = Color(0xFF9ADCFF);
  static const Color skyBottom = Color(0xFFFFF1D6);

  static const Color orange = Color(0xFFFF9A1F);
  static const Color orangeDeep = Color(0xFFE0720A);
  static const Color blue = Color(0xFF4DA3FF);
  static const Color green = Color(0xFF45C06A);
  static const Color red = Color(0xFFFF5A5F);
  static const Color yellow = Color(0xFFFFD43B);

  static const double border = 3;
  static const double shadow = 5;

  /// 외곽선 + 채움을 겹쳐 그린 글자. 어떤 배경 위에서도 읽힌다.
  static Widget outlinedText(
    String text, {
    double size = 32,
    Color fill = Colors.white,
    Color stroke = ink,
    double letterSpacing = 0,
    TextAlign align = TextAlign.center,
    int? maxLines,
  }) {
    TextStyle style({required bool outline}) => TextStyle(
      fontFamily: font,
      fontSize: size,
      letterSpacing: letterSpacing,
      height: 1.1,
      color: outline ? null : fill,
      foreground: outline
          ? (Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = size * 0.28
              ..strokeJoin = StrokeJoin.round
              ..color = stroke)
          : null,
    );
    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          text,
          textAlign: align,
          maxLines: maxLines,
          style: style(outline: true),
        ),
        Text(
          text,
          textAlign: align,
          maxLines: maxLines,
          style: style(outline: false),
        ),
      ],
    );
  }

  /// 본문용 글자: 진한 갈색, Jua.
  static TextStyle text({
    double size = 16,
    Color color = ink,
    double? height,
  }) =>
      TextStyle(fontFamily: font, fontSize: size, color: color, height: height);

  static BoxDecoration panelDecoration({
    Color color = paper,
    double radius = 24,
    double shadowOffset = shadow,
  }) => BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: ink, width: border),
    boxShadow: [BoxShadow(color: ink, offset: Offset(0, shadowOffset))],
  );

  static InputDecoration inputDecoration({
    required String hint,
    IconData? icon,
    double radius = 16,
  }) {
    OutlineInputBorder b(Color c, double w) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide(color: c, width: w),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: text(size: 16, color: ink.withValues(alpha: 0.4)),
      prefixIcon: icon == null ? null : Icon(icon, color: ink),
      filled: true,
      fillColor: Colors.white,
      enabledBorder: b(ink, 2.5),
      focusedBorder: b(orange, 3),
      border: b(ink, 2.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    );
  }
}

/// 하늘색 → 크림 그라데이션 위에 은은한 점 무늬. 화면 배경.
class CartoonBackground extends StatelessWidget {
  const CartoonBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Cartoon.skyTop, Cartoon.skyBottom],
        ),
      ),
      child: CustomPaint(painter: _DotsPainter(), child: child),
    );
  }
}

class _DotsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.28);
    const step = 46.0;
    var row = 0;
    for (var y = 12.0; y < size.height; y += step) {
      final shift = row.isEven ? 0.0 : step / 2;
      for (var x = shift; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 5, paint);
      }
      row++;
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => false;
}

/// 흰 종이 느낌의 둥근 패널: 두꺼운 테두리 + 단색 그림자.
class CartoonPanel extends StatelessWidget {
  const CartoonPanel({
    super.key,
    required this.child,
    this.color = Cartoon.paper,
    this.radius = 24,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final Color color;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: Cartoon.panelDecoration(color: color, radius: radius),
      child: child,
    );
  }
}

/// 누르면 그림자만큼 쑥 들어가는 통통한 버튼.
class CartoonButton extends StatefulWidget {
  const CartoonButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.color = Cartoon.orange,
    this.height = 56,
    this.radius = 18,
    this.expand = true,
  });

  /// null 이면 비활성(회색, 눌리지 않음).
  final VoidCallback? onPressed;
  final Widget child;
  final Color color;
  final double height;
  final double radius;
  final bool expand;

  /// 버튼 안에 넣을 기본 글자: Jua + 외곽선.
  static Widget label(String text, {double size = 20}) =>
      Cartoon.outlinedText(text, size: size, maxLines: 1);

  @override
  State<CartoonButton> createState() => _CartoonButtonState();
}

class _CartoonButtonState extends State<CartoonButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final color = enabled ? widget.color : const Color(0xFFBDB5AE);
    final depth = _down ? 1.0 : Cartoon.shadow;
    final button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTap: widget.onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 70),
        height: widget.height,
        margin: EdgeInsets.only(top: Cartoon.shadow - depth),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(widget.radius),
          border: Border.all(color: Cartoon.ink, width: Cartoon.border),
          boxShadow: [BoxShadow(color: Cartoon.ink, offset: Offset(0, depth))],
        ),
        child: Stack(
          children: [
            // 위쪽 하이라이트 띠: 빛을 받은 통통한 느낌
            Positioned(
              left: 10,
              right: 10,
              top: 5,
              height: widget.height * 0.22,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: enabled ? 0.35 : 0.2),
                  borderRadius: BorderRadius.circular(widget.height),
                ),
              ),
            ),
            Center(child: widget.child),
          ],
        ),
      ),
    );
    final padded = Padding(
      padding: const EdgeInsets.only(bottom: Cartoon.shadow),
      child: button,
    );
    return widget.expand
        ? SizedBox(width: double.infinity, child: padded)
        : padded;
  }
}

/// 둥둥 떠다니는 장식(로고 등). 위아래로 천천히 흔들린다.
class CartoonFloat extends StatefulWidget {
  const CartoonFloat({super.key, required this.child, this.amplitude = 6});

  final Widget child;
  final double amplitude;

  @override
  State<CartoonFloat> createState() => _CartoonFloatState();
}

class _CartoonFloatState extends State<CartoonFloat>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value * 2 * math.pi;
        return Transform.translate(
          offset: Offset(0, math.sin(t) * widget.amplitude),
          child: Transform.rotate(angle: math.sin(t) * 0.03, child: child),
        );
      },
      child: widget.child,
    );
  }
}
