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
  });

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
        duration: Duration(milliseconds: 2400),
        titleSize: 36,
        icon: Icons.emoji_events,
      );
    case TichuFxKind.tichuFail:
      return const _FxStyle(
        colors: [Color(0xFF9E9E9E), Color(0xFF424242)],
        glow: Color(0xFF757575),
        duration: Duration(milliseconds: 1800),
        titleSize: 28,
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
                alignment: Alignment(0, -0.3 + i * 0.28),
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
    final isFail = widget.event.kind == TichuFxKind.tichuFail;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        // 앞 25% 에서 튀어나오고, 뒤 20% 에서 떠오르며 사라진다.
        final pop = Curves.elasticOut.transform((t / 0.25).clamp(0.0, 1.0));
        final out = ((t - 0.8) / 0.2).clamp(0.0, 1.0);
        final scale = (0.4 + 0.6 * pop) * (1 + 0.06 * math.sin(t * math.pi));
        // 실패는 좌우로 한 번 흔들려서 "아깝다" 는 느낌을 준다.
        final shake = isFail && t < 0.4
            ? math.sin(t / 0.4 * math.pi * 6) * 8 * (1 - t / 0.4)
            : 0.0;
        return Opacity(
          opacity: (1 - out) * (t < 0.06 ? t / 0.06 : 1),
          child: Transform.translate(
            offset: Offset(shake, -26 * out),
            child: Transform.scale(
              scale: scale,
              // 좁은 폰에서 340 이 화면보다 크면 잘리니 폭에 맞춰 줄인다.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: 340,
                  height: 150,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [_buildPlate(style)],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 배경 없이 글자만. 테두리 + 빛 번짐으로 어떤 판 색 위에서도 읽힌다.
  Widget _buildPlate(_FxStyle style) {
    final small = widget.event.kind == TichuFxKind.finished;
    final size = style.titleSize * (small ? 1.5 : 1.25);
    final fill = style.colors.first;
    final edge = style.colors.last;

    Widget title({required bool stroke}) => Text(
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
                ..strokeWidth = size * 0.16
                ..strokeJoin = StrokeJoin.round
                ..color = edge)
            : null,
        shadows: stroke
            ? [
                Shadow(
                  color: style.glow.withValues(alpha: 0.9),
                  blurRadius: 18,
                ),
                const Shadow(
                  color: Color(0x99000000),
                  blurRadius: 6,
                  offset: Offset(0, 3),
                ),
              ]
            : null,
      ),
    );

    return Column(
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
              fontSize: 20,
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
  }
}
