import 'dart:async';
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

  /// Jua 는 앱 문자열 글자만 담은 서브셋이라, 없는 글자가 나오면 이쪽으로 넘어간다.
  /// (웹은 Pretendard, 네이티브는 이름이 없으면 시스템 글꼴.) 사용자가 입력한
  /// 글자(방 이름, 닉네임, 입력창)에는 Jua 를 아예 쓰지 않는다.
  static const List<String> fontFallback = ['Pretendard'];

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

  // 두껍고 큰 그림자가 화면을 번잡하게 해서 한 단계씩 줄였다 (3/5 → 2.2/3).
  static const double border = 2.2;
  static const double shadow = 3;

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
      fontFamilyFallback: fontFallback,
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
  }) => TextStyle(
    fontFamily: font,
    fontFamilyFallback: fontFallback,
    fontSize: size,
    color: color,
    height: height,
  );

  /// 사용자가 입력하거나 서버가 내려준 글자용: Jua 없이 기본 글꼴, 같은 색.
  static TextStyle userText({
    double size = 16,
    Color color = ink,
    FontWeight weight = FontWeight.w700,
    double? height,
  }) => TextStyle(
    fontSize: size,
    color: color,
    fontWeight: weight,
    height: height,
  );

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
        // alignment 로 가운데에 두고 자식은 그대로 쓴다. 예전에는 Center 로 감쌌는데, Center 는
        // 폭이 정해진 자리(ListTile.trailing 처럼)에서 남는 폭을 전부 차지해 expand:false 버튼이
        // 줄 전체 폭으로 부풀었고, 우편함의 '받기' 버튼이 "Trailing widget consumes the entire
        // tile width" 로 레이아웃을 깨뜨려 보상이 든 우편이 아예 안 보였다.
        child: Stack(
          alignment: Alignment.center,
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
            widget.child,
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

/// 처음 나타날 때 통통 튀어 들어온다. [delay] 로 여러 개를 차례로 띄울 수 있다.
///
/// 한 번 재생하고 끝이다 — 같은 State 가 살아 있는 동안 다시 빌드돼도 반복하지
/// 않으니, 목록 항목은 안정적인 key 를 붙여 새로 생긴 것만 등장하게 한다.
class CartoonEntrance extends StatefulWidget {
  const CartoonEntrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.from = const Offset(0, 24),
    this.pop = true,
  });

  final Widget child;
  final Duration delay;

  /// 시작 위치(최종 위치 기준 px).
  final Offset from;

  /// true 면 살짝 커졌다 자리잡는 탄성, false 면 부드럽게만.
  final bool pop;

  @override
  State<CartoonEntrance> createState() => _CartoonEntranceState();
}

class _CartoonEntranceState extends State<CartoonEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = _c.value;
        final move = Curves.easeOutCubic.transform((t / 0.7).clamp(0.0, 1.0));
        final scale = widget.pop
            ? 0.82 + 0.18 * Curves.elasticOut.transform(t)
            : 1.0;
        return Opacity(
          opacity: (t / 0.35).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: widget.from * (1 - move),
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
    );
  }
}

/// 누르는 동안 눌려 들어가고, 떼면 탄성 있게 되돌아온다.
class CartoonPressable extends StatefulWidget {
  const CartoonPressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.92,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  @override
  State<CartoonPressable> createState() => _CartoonPressableState();
}

class _CartoonPressableState extends State<CartoonPressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        duration: Duration(milliseconds: _down ? 70 : 380),
        curve: _down ? Curves.easeOut : Curves.elasticOut,
        child: widget.child,
      ),
    );
  }
}

/// 숨 쉬듯 아주 살짝 커졌다 작아진다 — "여기를 눌러" 라는 신호.
class CartoonPulse extends StatefulWidget {
  const CartoonPulse({super.key, required this.child, this.amount = 0.02});

  final Widget child;
  final double amount;

  @override
  State<CartoonPulse> createState() => _CartoonPulseState();
}

class _CartoonPulseState extends State<CartoonPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) => Transform.scale(
        scale: 1 + widget.amount * Curves.easeInOut.transform(_c.value),
        child: child,
      ),
    );
  }
}

/// 카툰 테마: 다이얼로그·시트·버튼·입력창·스위치를 한 번에 같은 결로 만든다.
///
/// 화면 하나를 `Theme(data: cartoonTheme(...))` 로 감싸면, 그 화면에서 연
/// showDialog / showModalBottomSheet 도 이 테마를 물려받는다(Flutter 가
/// 호출한 context 의 테마를 캡처한다). 화면별로 대화상자를 일일이 고치지 않아도
/// 되고, 나중에 앱 전체 테마로 올리기도 쉽다.
ThemeData cartoonTheme(ThemeData base) {
  const ink = Cartoon.ink;
  TextStyle jua(double size, {Color color = ink}) => TextStyle(
    fontFamily: Cartoon.font,
    fontFamilyFallback: Cartoon.fontFallback,
    fontSize: size,
    color: color,
  );
  final side = BorderSide(color: ink, width: 2.5);
  RoundedRectangleBorder shape(double r) => RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(r),
    side: side,
  );
  OutlineInputBorder border(Color c, double w) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: c, width: w),
  );
  return base.copyWith(
    dialogTheme: DialogThemeData(
      backgroundColor: Cartoon.paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: ink, width: 3),
      ),
      titleTextStyle: jua(21),
      contentTextStyle: base.textTheme.bodyMedium?.copyWith(
        color: ink,
        fontSize: 15,
        height: 1.5,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Cartoon.paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        side: BorderSide(color: ink, width: 3),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Cartoon.orange,
        foregroundColor: Colors.white,
        elevation: 0,
        textStyle: jua(16, color: Colors.white),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: shape(14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: ink, textStyle: jua(16)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Cartoon.orange,
        foregroundColor: Colors.white,
        elevation: 0,
        textStyle: jua(16, color: Colors.white),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: shape(14),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Cartoon.paper,
      surfaceTintColor: Colors.transparent,
      shape: shape(16),
      textStyle: jua(16),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        textStyle: jua(15),
        side: side,
        shape: shape(14),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      hintStyle: TextStyle(color: ink.withValues(alpha: 0.4)),
      border: border(ink, 2.5),
      enabledBorder: border(ink, 2.5),
      focusedBorder: border(Cartoon.orange, 3),
      errorBorder: border(Cartoon.red, 2.5),
      focusedErrorBorder: border(Cartoon.red, 3),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : ink,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Cartoon.green : Colors.white,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(ink),
      trackOutlineWidth: const WidgetStatePropertyAll(2.5),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Cartoon.paper,
      contentTextStyle: jua(16),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: ink, width: 2.2),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: ink.withValues(alpha: 0.12),
      thickness: 1.5,
    ),
  );
}

/// 한 번 터지는 색종이. 부모 가운데에서 위로 솟았다가 흩날리며 떨어진다.
/// 터치는 통과시킨다. 구매 완료 같은 축하 장면 뒤에 깐다.
class CartoonConfetti extends StatefulWidget {
  const CartoonConfetti({super.key, this.seed = 1, this.count = 54});

  final int seed;
  final int count;

  @override
  State<CartoonConfetti> createState() => _CartoonConfettiState();
}

class _CartoonConfettiState extends State<CartoonConfetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _ConfettiPainter(_c.value, widget.seed, widget.count),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t, this.seed, this.count);

  final double t;
  final int seed;
  final int count;

  static const _colors = [
    Color(0xFFFFD43B),
    Color(0xFFFF8A65),
    Color(0xFF4DD0E1),
    Color(0xFFBA68C8),
    Color(0xFFFFFFFF),
    Color(0xFFAED581),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final rng = math.Random(seed * 7919 + 17);
    for (var i = 0; i < count; i++) {
      final ang = -math.pi / 2 + (rng.nextDouble() - 0.5) * 3.8;
      final speed = 160 + rng.nextDouble() * 260;
      final spin = (rng.nextDouble() - 0.5) * 18;
      final w = 6 + rng.nextDouble() * 6;
      final color = _colors[rng.nextInt(_colors.length)];
      final delay = rng.nextDouble() * 0.1;
      final tt = ((t - delay) / 0.9).clamp(0.0, 1.0);
      if (t < delay || tt >= 1) continue;
      final dist = speed * Curves.easeOut.transform(tt) * 1.1;
      final pos = Offset(
        c.dx + math.cos(ang) * dist,
        c.dy + math.sin(ang) * dist + 340 * tt * tt,
      );
      final alpha = 1 - ((tt - 0.7) / 0.3).clamp(0.0, 1.0);
      canvas
        ..save()
        ..translate(pos.dx, pos.dy)
        ..rotate(spin * tt)
        ..scale(1, math.cos(tt * 14 + i).abs() * 0.8 + 0.2);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: w, height: w * 0.6),
        Paint()..color = color.withValues(alpha: alpha),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

/// 단순한 카툰 링 로더: 진한 테두리 고리 위로 주황 호가 돈다. 그림은 없다 —
/// 로딩 중이라는 것만 조용히 알린다.
class CartoonLoader extends StatefulWidget {
  const CartoonLoader({super.key, this.size = 52});

  final double size;

  @override
  State<CartoonLoader> createState() => _CartoonLoaderState();
}

class _CartoonLoaderState extends State<CartoonLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) =>
            CustomPaint(painter: _RingLoaderPainter(_c.value)),
      ),
    );
  }
}

class _RingLoaderPainter extends CustomPainter {
  _RingLoaderPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width * 0.17; // 고리 두께
    final rect = Rect.fromLTWH(w, w, size.width - 2 * w, size.height - 2 * w);
    // 바탕 고리(연한 크림)에 테두리를 두르고, 그 위로 주황 호가 돈다.
    Paint ring(double width, Color color) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = width
      ..color = color;
    canvas.drawArc(rect, 0, math.pi * 2, false, ring(w + 5, Cartoon.ink));
    canvas.drawArc(rect, 0, math.pi * 2, false, ring(w, Cartoon.cream));
    final start = t * math.pi * 2;
    const sweep = math.pi * 0.85;
    canvas.drawArc(rect, start, sweep, false, ring(w + 5, Cartoon.ink));
    canvas.drawArc(rect, start, sweep, false, ring(w, Cartoon.orange));
  }

  @override
  bool shouldRepaint(_RingLoaderPainter old) => old.t != t;
}

/// "연결 중" 뒤에 점 세 개가 차례로 튄다.
class CartoonDotsText extends StatefulWidget {
  const CartoonDotsText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<CartoonDotsText> createState() => _CartoonDotsTextState();
}

class _CartoonDotsTextState extends State<CartoonDotsText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? Cartoon.text(size: 19);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          child: Text(widget.text, style: style, textAlign: TextAlign.center),
        ),
        const SizedBox(width: 3),
        AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.only(left: 3, bottom: 4),
                  child: Transform.translate(
                    offset: Offset(
                      0,
                      -7 *
                          math.max(
                            0.0,
                            math.sin((_c.value * 2 * math.pi) - i * 0.9),
                          ),
                    ),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: style.color ?? Cartoon.ink,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 연결·로그인 중 화면에 올리는 안내 카드: 링 로더 + 제목(점이 튐) + 부제.
class CartoonLoadingCard extends StatelessWidget {
  const CartoonLoadingCard({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return CartoonEntrance(
      from: const Offset(0, 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.symmetric(horizontal: 28),
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
        decoration: Cartoon.panelDecoration(radius: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CartoonLoader(),
            const SizedBox(height: 10),
            CartoonDotsText(title),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: Cartoon.userText(
                  size: 13,
                  weight: FontWeight.w500,
                  color: Cartoon.ink.withValues(alpha: 0.65),
                  height: 1.4,
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
