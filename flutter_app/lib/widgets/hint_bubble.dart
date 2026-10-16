import 'package:flutter/material.dart';

import '../theme/cartoon.dart';

/// 어떤 버튼을 가리키는 카툰 말풍선("오늘의 미션을 선택하세요!" 같은 안내).
///
/// [pointsDown] 이면 꼬리가 아래를 향한다 — 버튼 위에 띄울 때. 아니면 위를 향한다.
/// 꼬리는 말풍선 가운데에 있고, 버튼 가운데에 맞춰 띄우는 건 호출하는 쪽의 일이다.
class HintBubble extends StatelessWidget {
  const HintBubble({
    super.key,
    required this.text,
    required this.pointsDown,
    this.onTap,
    this.maxWidth = 230,
  });

  final String text;
  final bool pointsDown;
  final VoidCallback? onTap;
  final double maxWidth;

  /// 아주 조금만 비치게 — 뒤의 화면이 완전히 가려지지 않는다.
  static const opacity = 0.93;

  static const _tailHeight = 9.0;
  static const _border = 2.0;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Cartoon.paper,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Cartoon.ink, width: _border),
        boxShadow: const [BoxShadow(color: Cartoon.ink, offset: Offset(0, 2))],
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Cartoon.userText(
          size: 13.5,
          weight: FontWeight.w800,
          height: 1.25,
        ),
      ),
    );
    // 꼬리를 몸통 테두리 위에 겹쳐 그려 꼬리 밑변 자리의 줄을 가린다.
    final tail = Transform.translate(
      offset: Offset(0, pointsDown ? -_border : _border),
      child: CustomPaint(
        size: const Size(18, _tailHeight),
        painter: _TailPainter(pointsDown: pointsDown),
      ),
    );
    final bubble = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: pointsDown ? [body, tail] : [tail, body],
      ),
    );
    return Material(
      type: MaterialType.transparency,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 380),
        curve: Curves.elasticOut,
        builder: (context, t, child) => Opacity(
          opacity: t.clamp(0.0, 1.0) * opacity,
          child: Transform.scale(
            scale: 0.7 + 0.3 * t,
            alignment: pointsDown
                ? Alignment.bottomCenter
                : Alignment.topCenter,
            child: child,
          ),
        ),
        child: onTap == null
            ? bubble
            : GestureDetector(onTap: onTap, child: bubble),
      ),
    );
  }
}

class _TailPainter extends CustomPainter {
  const _TailPainter({required this.pointsDown});
  final bool pointsDown;

  @override
  void paint(Canvas canvas, Size size) {
    final path = pointsDown
        ? (Path()
            ..moveTo(0, 0)
            ..lineTo(size.width / 2, size.height)
            ..lineTo(size.width, 0))
        : (Path()
            ..moveTo(0, size.height)
            ..lineTo(size.width / 2, 0)
            ..lineTo(size.width, size.height));
    // 밑변은 선 없이 종이색으로만 채워 몸통 테두리를 덮는다.
    canvas.drawPath(Path.from(path)..close(), Paint()..color = Cartoon.paper);
    canvas.drawPath(
      path,
      Paint()
        ..color = Cartoon.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = HintBubble._border
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _TailPainter old) =>
      old.pointsDown != pointsDown;
}
