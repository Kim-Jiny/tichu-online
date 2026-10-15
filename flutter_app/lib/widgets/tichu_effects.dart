import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 티츄 판 위에 잠깐 떴다 사라지는 연출들.
///
/// 티츄 선언은 작은 배지와 옅은 화면 색뿐이었고, 티츄 성공·실패나 원투처럼
/// 한 판의 점수를 크게 흔드는 순간은 아무 표시 없이 지나갔다. 점수 팝업이
/// 뜨기 전에 "방금 무슨 일이 일어났는지" 를 글자와 움직임으로 먼저 알려 준다.
enum TichuFxKind {
  /// 스몰·라지 티츄 선언
  declareSmall,
  declareLarge,

  /// 선언한 사람이 1등으로 털었다
  tichuSuccess,

  /// 선언했는데 다른 사람이 먼저 털었다
  tichuFail,

  /// 한 팀이 1·2등을 차지했다
  oneTwo,

  /// 누군가 패를 다 털었다
  finished,
}

class TichuFxEvent {
  TichuFxEvent({
    required this.id,
    required this.kind,
    required this.title,
    this.subtitle,
    this.large = false,
  });

  /// 라지 티츄 성공·실패 — 연출을 한 단계 더 크게.
  final bool large;
  final int id;
  final TichuFxKind kind;
  final String title;
  final String? subtitle;
}

class _FxStyle {
  const _FxStyle({
    required this.colors,
    required this.glow,
    required this.duration,
    required this.titleSize,
    this.icon,
  });

  final List<Color> colors;
  final Color glow;
  final Duration duration;
  final double titleSize;
  final IconData? icon;
}

_FxStyle _styleOf(TichuFxKind kind) {
  switch (kind) {
    case TichuFxKind.declareSmall:
      return const _FxStyle(
        colors: [Color(0xFF4BA3FF), Color(0xFF1565C0)],
        glow: Color(0xFF4BA3FF),
        duration: Duration(milliseconds: 1700),
        titleSize: 34,
        icon: Icons.bolt,
      );
    case TichuFxKind.declareLarge:
      return const _FxStyle(
        colors: [Color(0xFFFF6B6B), Color(0xFFB71C1C)],
        glow: Color(0xFFFF6B6B),
        duration: Duration(milliseconds: 2000),
        titleSize: 38,
        icon: Icons.local_fire_department,
      );
    case TichuFxKind.tichuSuccess:
      return const _FxStyle(
        colors: [Color(0xFFFFE082), Color(0xFFF57F17)],
        glow: Color(0xFFFFD54F),
        duration: Duration(milliseconds: 2900),
        titleSize: 36,
        icon: Icons.emoji_events,
      );
    case TichuFxKind.tichuFail:
      return const _FxStyle(
        colors: [Color(0xFF9E9E9E), Color(0xFF424242)],
        glow: Color(0xFF757575),
        duration: Duration(milliseconds: 2300),
        titleSize: 30,
        icon: Icons.heart_broken,
      );
    case TichuFxKind.oneTwo:
      return const _FxStyle(
        colors: [Color(0xFFFFD54F), Color(0xFF8E24AA)],
        glow: Color(0xFFFFCA28),
        duration: Duration(milliseconds: 2800),
        titleSize: 40,
        icon: Icons.military_tech,
      );
    case TichuFxKind.finished:
      return const _FxStyle(
        colors: [Color(0xFFFFFFFF), Color(0xFFFFE0B2)],
        glow: Color(0xFFFFB74D),
        duration: Duration(milliseconds: 1500),
        titleSize: 20,
      );
  }
}

/// 진행 중인 연출들을 세로로 쌓아서 그린다. 터치는 모두 통과시킨다.
class TichuFxLayer extends StatelessWidget {
  const TichuFxLayer({super.key, required this.events, required this.onDone});

  final List<TichuFxEvent> events;
  final void Function(int id) onDone;

  VoidCallback _doneFor(int id) =>
      () => onDone(id);

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            for (var i = 0; i < events.length; i++)
              // 같은 순간에 여러 개가 겹치면 위아래로 밀어 서로 안 가린다.
              // onDone 은 애니메이션이 끝날 때 불리는데, 그 사이 events 가
              // 줄어 있을 수 있으니 인덱스가 아니라 id 를 미리 잡아 둔다.
              Align(
                // 키가 Align 에 있어야 앞 배너가 빠져도 뒤 배너 상태(진행 중인
                // 애니메이션)가 새로 시작되지 않는다.
                key: ValueKey(events[i].id),
                alignment: Alignment(0, -0.5 + i * 0.22),
                child: _FxBanner(
                  event: events[i],
                  onDone: _doneFor(events[i].id),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FxBanner extends StatefulWidget {
  const _FxBanner({required this.event, required this.onDone});

  final TichuFxEvent event;
  final VoidCallback onDone;

  @override
  State<_FxBanner> createState() => _FxBannerState();
}

class _FxBannerState extends State<_FxBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final _FxStyle _style;

  @override
  void initState() {
    super.initState();
    _style = _styleOf(widget.event.kind);
    _c = AnimationController(vsync: this, duration: _style.duration)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onDone();
      })
      ..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = _style;
    final kind = widget.event.kind;
    final isFail = kind == TichuFxKind.tichuFail;
    final isSuccess = kind == TichuFxKind.tichuSuccess;
    final large = widget.event.large;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final out = ((t - 0.8) / 0.2).clamp(0.0, 1.0);
        double scale;
        Offset offset;
        double angle = 0;
        if (isFail) {
          // 위에서 쾅 내리꽂히고, 바닥에서 튕긴 뒤 한 번 부르르 떨고,
          // 끝에는 힘없이 아래로 가라앉는다.
          final slam = Curves.bounceOut.transform((t / 0.24).clamp(0.0, 1.0));
          final shakeT = ((t - 0.24) / 0.26).clamp(0.0, 1.0);
          final shake =
              math.sin(shakeT * math.pi * 7) * (large ? 10 : 6) * (1 - shakeT);
          offset = Offset(shake, -150 * (1 - slam) + 34 * out);
          scale = 0.9 + 0.1 * slam;
          angle = -0.035 * slam;
        } else {
          // 앞 25% 에서 튀어나오고, 뒤 20% 에서 떠오르며 사라진다.
          final pop = Curves.elasticOut.transform((t / 0.25).clamp(0.0, 1.0));
          scale = (0.4 + 0.6 * pop) * (1 + 0.06 * math.sin(t * math.pi));
          offset = Offset(0, -26 * out);
        }
        final plate = Opacity(
          opacity: ((1 - out) * (t < 0.06 ? t / 0.06 : 1)).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: offset,
            child: Transform.rotate(
              angle: angle,
              child: Transform.scale(
                scale: scale,
                // 좁은 폰에서 340 이 화면보다 크면 잘리니 폭에 맞춰 줄인다.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  // 높이는 내용에 맡기고 폭만 제한한다. 고정 높이였을 때는
                  // 번짐 배경 여백이 붙자 넘쳤다.
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: _buildPlate(style, t),
                  ),
                ),
              ),
            ),
          ),
        );
        if (!isSuccess && !isFail) return plate;
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // 캔버스는 잘리지 않으니 글자 상자 밖으로 터져 나가도 그려진다.
            Positioned.fill(
              child: CustomPaint(
                painter: isSuccess
                    ? _BurstPainter(
                        t: t,
                        large: large,
                        glow: style.glow,
                        seed: widget.event.id,
                      )
                    : _GloomPainter(t: t, large: large, seed: widget.event.id),
              ),
            ),
            plate,
          ],
        );
      },
    );
  }

  Widget _title({
    required bool stroke,
    required double size,
    required Color fill,
    required _FxStyle style,
  }) => Text(
    widget.event.title,
    textAlign: TextAlign.center,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w900,
      height: 1.1,
      color: stroke ? null : fill,
      foreground: stroke
          ? (Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = size * 0.26
              ..strokeJoin = StrokeJoin.round
              ..color = const Color(0xFF1B1030))
          : null,
      shadows: stroke
          ? [
              Shadow(color: style.glow.withValues(alpha: 0.8), blurRadius: 16),
              const Shadow(
                color: Color(0xCC000000),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ]
          : null,
    ),
  );

  /// 배경 없이 글자만. 테두리 + 빛 번짐으로 어떤 판 색 위에서도 읽힌다.
  Widget _buildPlate(_FxStyle style, double t) {
    final small = widget.event.kind == TichuFxKind.finished;
    final size = style.titleSize * (small ? 1.2 : 1.0);
    final fill = style.colors.first;
    final edge = style.colors.last;

    final shimmer = widget.event.kind == TichuFxKind.tichuSuccess;
    Widget title({required bool stroke}) {
      final text = _title(stroke: stroke, size: size, fill: fill, style: style);
      if (stroke || !shimmer) return text;
      // 글자 위로 빛이 한 번 훑고 지나간다.
      final sweep = ((t - 0.2) / 0.5).clamp(0.0, 1.0);
      return ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (r) => LinearGradient(
          colors: [fill, Colors.white, fill],
          stops: [
            (sweep - 0.18).clamp(0.0, 1.0),
            sweep,
            (sweep + 0.18).clamp(0.0, 1.0),
          ],
        ).createShader(r),
        child: text,
      );
    }

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (style.icon != null) ...[
              Icon(
                style.icon,
                color: fill,
                size: size * 0.95,
                shadows: [Shadow(color: edge, blurRadius: 10)],
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Stack(
                alignment: Alignment.center,
                children: [title(stroke: true), title(stroke: false)],
              ),
            ),
          ],
        ),
        if (widget.event.subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            widget.event.subtitle!,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              shadows: [
                Shadow(color: edge, blurRadius: 8),
                const Shadow(
                  color: Color(0xCC000000),
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
        ],
      ],
    );

    // 상자는 아니고, 글자 뒤만 은은하게 어둡게 깔아 밝은 판 위에서도 읽히게 한다.
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [
            Colors.black.withValues(alpha: 0.5),
            Colors.black.withValues(alpha: 0),
          ],
          stops: const [0.35, 1],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 26),
        child: content,
      ),
    );
  }
}

/// 티츄 성공: 뒤에서 빛줄기가 돌고, 충격파가 퍼지며, 색종이가 터져 떨어진다.
class _BurstPainter extends CustomPainter {
  _BurstPainter({
    required this.t,
    required this.large,
    required this.glow,
    required this.seed,
  });

  final double t;
  final bool large;
  final Color glow;
  final int seed;

  static const _confetti = [
    Color(0xFFFFD54F),
    Color(0xFFFF8A65),
    Color(0xFF4DD0E1),
    Color(0xFFBA68C8),
    Color(0xFFFFFFFF),
    Color(0xFFAED581),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final fade = 1 - ((t - 0.72) / 0.28).clamp(0.0, 1.0);

    // 빛줄기: 바깥으로 갈수록 옅어지고 천천히 돈다.
    final rayIn = Curves.easeOut.transform((t / 0.22).clamp(0.0, 1.0));
    final rayR = (large ? 300.0 : 230.0) * rayIn;
    if (rayR > 1) {
      final path = Path();
      const n = 14;
      for (var i = 0; i < n; i++) {
        final a = i * 2 * math.pi / n + t * 0.9;
        const half = 0.075;
        path
          ..moveTo(c.dx, c.dy)
          ..lineTo(
            c.dx + math.cos(a - half) * rayR,
            c.dy + math.sin(a - half) * rayR,
          )
          ..lineTo(
            c.dx + math.cos(a + half) * rayR,
            c.dy + math.sin(a + half) * rayR,
          )
          ..close();
      }
      canvas.drawPath(
        path,
        Paint()
          ..shader = RadialGradient(
            colors: [
              glow.withValues(alpha: 0.5 * fade),
              glow.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: c, radius: rayR)),
      );
    }

    // 충격파 고리
    final ringT = (t / 0.4).clamp(0.0, 1.0);
    if (ringT < 1) {
      canvas.drawCircle(
        c,
        30 + (large ? 260 : 200) * Curves.easeOut.transform(ringT),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5 * (1 - ringT) + 1
          ..color = Colors.white.withValues(alpha: 0.8 * (1 - ringT)),
      );
    }

    // 색종이
    final rng = math.Random(seed * 7919 + 13);
    final count = large ? 64 : 34;
    for (var i = 0; i < count; i++) {
      final ang = -math.pi / 2 + (rng.nextDouble() - 0.5) * 3.6;
      final speed = (140 + rng.nextDouble() * 240) * (large ? 1.2 : 1.0);
      final spin = (rng.nextDouble() - 0.5) * 18;
      final w = 5 + rng.nextDouble() * 6;
      final color = _confetti[rng.nextInt(_confetti.length)];
      final delay = rng.nextDouble() * 0.08;
      final tt = ((t - delay) / 0.88).clamp(0.0, 1.0);
      if (t < delay || tt >= 1) continue;
      final dist = speed * Curves.easeOut.transform(tt) * 1.1;
      final pos = Offset(
        c.dx + math.cos(ang) * dist,
        c.dy + math.sin(ang) * dist + 300 * tt * tt,
      );
      final alpha = 1 - ((tt - 0.7) / 0.3).clamp(0.0, 1.0);
      canvas
        ..save()
        ..translate(pos.dx, pos.dy)
        ..rotate(spin * tt)
        // 납작해졌다 펴지며 팔랑거리는 느낌
        ..scale(1, math.cos(tt * 14 + i).abs() * 0.8 + 0.2);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: w, height: w * 0.6),
        Paint()..color = color.withValues(alpha: alpha),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t;
}

/// 티츄 실패: 어두운 기운이 깔리고 빗줄기가 내린다. 라지는 붉은 충격이 한 번 더.
class _GloomPainter extends CustomPainter {
  _GloomPainter({required this.t, required this.large, required this.seed});

  final double t;
  final bool large;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final fade = 1 - ((t - 0.75) / 0.25).clamp(0.0, 1.0);
    final fadeIn = (t / 0.15).clamp(0.0, 1.0);

    // 글자 뒤로 먹구름처럼 깔리는 어둠
    canvas.drawCircle(
      c,
      large ? 230 : 180,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF000000).withValues(alpha: 0.45 * fade * fadeIn),
            const Color(0xFF000000).withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: large ? 230 : 180)),
    );

    // 바닥에 닿는 순간의 충격파 (라지는 붉게)
    final hit = ((t - 0.2) / 0.3).clamp(0.0, 1.0);
    if (t > 0.2 && hit < 1) {
      canvas.drawCircle(
        c,
        20 + (large ? 200 : 120) * Curves.easeOut.transform(hit),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4 * (1 - hit) + 1
          ..color = (large ? const Color(0xFFE53935) : const Color(0xFF9E9E9E))
              .withValues(alpha: 0.7 * (1 - hit)),
      );
    }

    // 빗줄기
    final rng = math.Random(seed * 104729 + 7);
    final n = large ? 36 : 22;
    final paint = Paint()
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < n; i++) {
      final x = c.dx + (rng.nextDouble() - 0.5) * 340;
      final speed = 1.1 + rng.nextDouble() * 0.5;
      final phase = rng.nextDouble();
      final len = 10 + rng.nextDouble() * 10;
      final p = (t * speed + phase) % 1.0;
      final y = c.dy - 160 + 330 * p;
      paint.color = const Color(
        0xFF90A4AE,
      ).withValues(alpha: 0.55 * fade * fadeIn);
      canvas.drawLine(Offset(x, y), Offset(x - 2, y + len), paint);
    }
  }

  @override
  bool shouldRepaint(_GloomPainter old) => old.t != t;
}
