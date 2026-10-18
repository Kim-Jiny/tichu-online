import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/cartoon.dart';

/// 티츄 판 위에 잠깐 떴다 사라지는 연출들.
///
/// 티츄 선언은 작은 배지와 옅은 화면 색뿐이었고, 티츄 성공·실패나 원투처럼
/// 한 판의 점수를 크게 흔드는 순간은 아무 표시 없이 지나갔다. 점수 팝업이
/// 뜨기 전에 "방금 무슨 일이 일어났는지" 를 글자와 움직임으로 먼저 알려 준다.
///
/// ── 생김새 ──
/// 종이에 찍은 도장처럼 그린다. 두꺼운 잉크 테두리, 번짐 없는 단색
/// 그림자, Jua 글자, 그리고 뒤에 납작한 도형이 퍼진다.
///
/// 전에는 이 파일만 다른 세계였다. Jua 를 한 곳도 쓰지 않았고(앱의 다른
/// 글자는 전부 Jua 다), 빛 번짐이 여섯 군데 있었고, 색도 카툰 팔레트가
/// 아닌 자체 색이었다(B71C1C·9E9E9E 같은 머티리얼 기본색). 그래서 멀쩡한
/// 연출인데도 화면에 끼어들면 다른 앱에서 떨어져 나온 것처럼 보였다.
///
/// 움직임은 그대로 둔다 — 도장처럼 내리찍고 흔들리는 동작은 이미 이
/// 톤에 맞는다. 바꾸는 것은 색·글꼴·테두리·뒤 도형이다.
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
    required this.fill,
    required this.accent,
    required this.duration,
    required this.titleSize,
    this.icon,
    this.textFill,
  });

  /// 도장 판의 색.
  final Color fill;

  /// 뒤로 퍼지는 도형(살·불꽃·고리·금)의 색.
  final Color accent;

  /// 글자 속 색. 밝은 판에는 잉크, 진한 판에는 종이색.
  /// 글자 속 색. 넘기지 않으면 종이색 — 팔레트를 따라간다.
  final Color? textFill;

  final Duration duration;
  final double titleSize;
  final IconData? icon;
}

/// 색은 전부 카툰 팔레트에서 가져온다.
///
/// 실패를 회색(9E9E9E)으로 두지 않는다. 이 앱에 회색 면은 없어서 그
/// 자체로 튀고, "꺼진 화면" 처럼 보인다. 대신 종이색 판을 기울여 찍고
/// 뒤에 잉크 금을 그린다 — 같은 세계 안에서 잘못된 일이 일어난 모양.
_FxStyle _styleOf(TichuFxKind kind) {
  switch (kind) {
    case TichuFxKind.declareSmall:
      return const _FxStyle(
        fill: Cartoon.blue,
        accent: Cartoon.yellow,
        duration: Duration(milliseconds: 1900),
        titleSize: 36,
        icon: Icons.bolt_rounded,
      );
    case TichuFxKind.declareLarge:
      return const _FxStyle(
        fill: Cartoon.red,
        accent: Cartoon.orange,
        duration: Duration(milliseconds: 2300),
        titleSize: 42,
        icon: Icons.local_fire_department_rounded,
      );
    case TichuFxKind.tichuSuccess:
      return _FxStyle(
        fill: Cartoon.yellow,
        accent: Cartoon.orange,
        duration: Duration(milliseconds: 2900),
        titleSize: 36,
        icon: Icons.emoji_events_rounded,
        // 노란 판에는 종이색 글자가 묻힌다.
        textFill: Cartoon.ink,
      );
    case TichuFxKind.tichuFail:
      return _FxStyle(
        fill: Cartoon.cream,
        accent: Cartoon.ink,
        duration: Duration(milliseconds: 2300),
        titleSize: 30,
        icon: Icons.heart_broken_rounded,
        textFill: Cartoon.ink,
      );
    case TichuFxKind.oneTwo:
      return const _FxStyle(
        fill: Cartoon.green,
        accent: Cartoon.yellow,
        duration: Duration(milliseconds: 2800),
        titleSize: 40,
        icon: Icons.military_tech_rounded,
      );
    case TichuFxKind.finished:
      return _FxStyle(
        fill: Cartoon.paper,
        accent: Cartoon.orange,
        duration: Duration(milliseconds: 1500),
        titleSize: 20,
        textFill: Cartoon.ink,
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
    final isDeclare =
        kind == TichuFxKind.declareSmall || kind == TichuFxKind.declareLarge;
    final isLargeDeclare = kind == TichuFxKind.declareLarge;
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
        } else if (isDeclare) {
          // 도장 찍듯 크게 내리쳐 쾅 하고 박힌 뒤, 여운으로 한 번 출렁인다.
          // 라지는 박히는 순간 화면이 흔들린다.
          final hit = Curves.easeInCubic.transform((t / 0.16).clamp(0.0, 1.0));
          final after = ((t - 0.16) / 0.3).clamp(0.0, 1.0);
          scale =
              2.4 -
              1.4 * hit +
              0.09 * math.sin(after * math.pi * 3) * (1 - after);
          final quake = isLargeDeclare && after < 1
              ? math.sin(after * math.pi * 9) * 9 * (1 - after)
              : 0.0;
          offset = Offset(quake, -20 * out);
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
        if (!isSuccess && !isFail && !isDeclare) return plate;
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // 캔버스는 잘리지 않으니 글자 상자 밖으로 터져 나가도 그려진다.
            Positioned.fill(
              child: CustomPaint(
                painter: isDeclare
                    ? (isLargeDeclare
                          ? _FlamePainter(
                              t: t,
                              seed: widget.event.id,
                              accent: style.accent,
                            )
                          : _LightningPainter(
                              t: t,
                              seed: widget.event.id,
                              accent: style.accent,
                            ))
                    : isSuccess
                    ? _BurstPainter(
                        t: t,
                        large: large,
                        accent: style.accent,
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

  /// 도장 한 장. 두꺼운 잉크 테두리 + 번짐 없는 단색 그림자.
  ///
  /// 전에는 상자 없이 글자만 띄우고 뒤를 검게 번지게 깔았다. 그 번짐이
  /// 이 앱에서 유일한 '안개' 였다 — 다른 모든 면은 테두리가 또렷하다.
  Widget _buildPlate(_FxStyle style, double t) {
    final small = widget.event.kind == TichuFxKind.finished;
    final size = style.titleSize * (small ? 1.2 : 1.0);
    final title = Cartoon.outlinedText(
      widget.event.title,
      size: size,
      fill: style.textFill ?? Cartoon.paper,
      maxLines: 2,
      // 외곽선은 획 뒤에 깔리므로 글자 '속' 을 먹지는 않는다. 대신 획
      // 바깥으로 두께의 절반만큼 번지는데, 그게 한글의 속공간을 메운다 —
      // '공' 의 동그라미, '패' 의 좁은 틈이 먼저 막힌다. 한글은 라틴보다
      // 속이 좁아서 같은 두께에서 먼저 뭉개진다.
      //
      // 36px 글자의 속공간은 대략 3~4px 이다. 기본 비율(0.28)은 번짐이
      // 5.0px, 0.13 도 2.3px 이라 양쪽에서 4.6px 를 먹어 그 틈이 그대로
      // 닫혔다. 0.06 이면 1.1px 로 윤곽만 남는다.
      //
      // 얇아도 되는 이유: 여기서 가독성을 맡는 것은 외곽선이 아니라 판이다.
      // 글자가 테두리 있는 단색 판 위에 있어서 배경과 이미 분리된다.
      strokeWidth: size * 0.06,
    );

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 18 : 24,
        vertical: small ? 10 : 16,
      ),
      decoration: BoxDecoration(
        color: style.fill,
        borderRadius: BorderRadius.circular(small ? 16 : 22),
        border: Border.all(color: Cartoon.ink, width: small ? 2.2 : 3.4),
        boxShadow: [
          BoxShadow(color: Cartoon.ink, offset: Offset(0, small ? 3 : 5)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (style.icon != null) ...[
                // 아이콘도 글자처럼 테두리를 두른다. 단색 면 위에 같은
                // 계열 아이콘을 그냥 얹으면 윤곽이 사라진다.
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(style.icon, size: size * 1.05, color: Cartoon.ink),
                    Icon(style.icon, size: size * 0.82, color: style.textFill),
                  ],
                ),
                const SizedBox(width: 8),
              ],
              Flexible(child: title),
            ],
          ),
          if (widget.event.subtitle != null) ...[
            const SizedBox(height: 2),
            // 닉네임과 점수가 들어오므로 Jua 가 아닌 글꼴을 쓴다
            // (userText — 사용자가 입력한 글자용).
            Text(
              widget.event.subtitle!,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Cartoon.userText(
                size: 16,
                color: style.textFill == Cartoon.ink
                    ? Cartoon.ink.withValues(alpha: 0.75)
                    : Cartoon.paper,
                weight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// ── 뒤에 퍼지는 도형들 ──
///
/// 모두 같은 규칙으로 그린다: 납작한 단색 면 + 잉크 외곽선, 번짐 없음.
/// 전에는 빛줄기·불길·빗줄기를 반투명 그라데이션으로 그렸는데, 그 재질이
/// 이 앱에 없는 유일한 것이었다.

/// 잉크 외곽선을 두른 면을 칠한다. 카툰 도형은 전부 이 한 쌍으로 그린다.
void _inked(Canvas c, Path path, Color fill, {double width = 2.4}) {
  c.drawPath(path, Paint()..color = fill);
  c.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeJoin = StrokeJoin.round
      ..color = Cartoon.ink,
  );
}

/// 꼭짓점이 [points] 개인 납작한 별(터지는 모양).
Path _starPath(Offset c, double outer, double inner, int points, double rot) {
  final p = Path();
  for (var i = 0; i < points * 2; i++) {
    final r = i.isEven ? outer : inner;
    final a = rot + i * math.pi / points;
    final o = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
    if (i == 0) {
      p.moveTo(o.dx, o.dy);
    } else {
      p.lineTo(o.dx, o.dy);
    }
  }
  return p..close();
}

/// 티츄 성공: 잉크 고리가 퍼지고, 납작한 색종이가 흩날린다.
class _BurstPainter extends CustomPainter {
  _BurstPainter({
    required this.t,
    required this.large,
    required this.accent,
    required this.seed,
  });

  final double t;
  final bool large;
  final Color accent;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final base = math.min(size.width, size.height);
    final rnd = math.Random(seed);

    // 퍼지는 잉크 고리 두 겹. 선만 그린다 — 면을 깔면 글자를 덮는다.
    for (var i = 0; i < 2; i++) {
      final ring = ((t - i * 0.12) / 0.5).clamp(0.0, 1.0);
      if (ring <= 0 || ring >= 1) continue;
      final r = base * (0.18 + 0.52 * Curves.easeOutCubic.transform(ring));
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (large ? 6.0 : 4.5) * (1 - ring)
          ..color = Cartoon.ink.withValues(alpha: (1 - ring) * 0.55),
      );
    }

    // 뒤에서 터지는 별 하나. 판보다 작게 두어 글자를 가리지 않는다.
    final pop = ((t - 0.02) / 0.3).clamp(0.0, 1.0);
    if (pop > 0 && pop < 1) {
      final r = base * 0.3 * Curves.easeOutBack.transform(pop);
      canvas.saveLayer(
        null,
        Paint()..color = Colors.white.withValues(alpha: 1 - pop),
      );
      _inked(
        canvas,
        _starPath(c, r, r * 0.52, large ? 12 : 10, -math.pi / 2),
        accent,
        width: 2.6,
      );
      canvas.restore();
    }

    // 납작한 색종이. 회전하는 사각형이고, 그림자도 번짐도 없다.
    final n = large ? 26 : 18;
    for (var i = 0; i < n; i++) {
      final delay = rnd.nextDouble() * 0.2;
      final life = ((t - delay) / 0.8).clamp(0.0, 1.0);
      if (life <= 0) continue;
      final a = rnd.nextDouble() * math.pi * 2;
      final dist = base * (0.1 + 0.45 * rnd.nextDouble());
      final fly = Curves.easeOutCubic.transform(life);
      final p = Offset(
        c.dx + math.cos(a) * dist * fly,
        c.dy + math.sin(a) * dist * fly + base * 0.5 * life * life,
      );
      final w = base * 0.028;
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(a + life * 6);
      _inked(
        canvas,
        Path()..addRect(
          Rect.fromCenter(center: Offset.zero, width: w, height: w * 1.6),
        ),
        _confettiColors[i % _confettiColors.length].withValues(
          alpha: (1 - life).clamp(0.0, 1.0),
        ),
        width: 1.4,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t;
}

/// 색종이 색. 카툰 팔레트 그대로 — 로비의 CartoonConfetti 와 같은 세계다.
const _confettiColors = [
  Cartoon.orange,
  Cartoon.blue,
  Cartoon.green,
  Cartoon.red,
  Cartoon.yellow,
];

/// 티츄 실패: 판 뒤로 잉크 금이 가고, 조각이 아래로 떨어진다.
///
/// 전에는 어두운 기운을 깔고 빗줄기를 내렸다. 이 앱에 반투명 안개가
/// 들어가는 곳은 여기뿐이어서, 실패 연출만 화면을 끄는 것처럼 보였다.
class _GloomPainter extends CustomPainter {
  _GloomPainter({required this.t, required this.large, required this.seed});

  final double t;
  final bool large;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final base = math.min(size.width, size.height);
    final rnd = math.Random(seed);

    // 금. 가운데에서 바깥으로 꺾이며 자란다.
    final grow = Curves.easeOutCubic.transform((t / 0.3).clamp(0.0, 1.0));
    final fade = 1 - ((t - 0.75) / 0.25).clamp(0.0, 1.0);
    final cracks = large ? 7 : 5;
    for (var i = 0; i < cracks; i++) {
      final a = (i / cracks) * math.pi * 2 + rnd.nextDouble() * 0.5;
      final len = base * (0.3 + 0.22 * rnd.nextDouble()) * grow;
      final path = Path()..moveTo(c.dx, c.dy);
      var cur = c;
      final steps = 3;
      for (var k = 1; k <= steps; k++) {
        final jitter = (rnd.nextDouble() - 0.5) * 0.5;
        final seg = len / steps;
        cur = Offset(
          cur.dx + math.cos(a + jitter) * seg,
          cur.dy + math.sin(a + jitter) * seg,
        );
        path.lineTo(cur.dx, cur.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (large ? 4.0 : 3.0)
          ..strokeCap = StrokeCap.round
          ..color = Cartoon.ink.withValues(alpha: 0.5 * fade),
      );
    }

    // 떨어지는 조각. 삼각형 몇 개가 아래로 흘러내린다.
    final n = large ? 10 : 7;
    for (var i = 0; i < n; i++) {
      final delay = rnd.nextDouble() * 0.25;
      final life = ((t - 0.2 - delay) / 0.7).clamp(0.0, 1.0);
      if (life <= 0) continue;
      final x = c.dx + (rnd.nextDouble() - 0.5) * base * 0.7;
      final y = c.dy + base * 0.08 + base * 0.6 * life * life;
      final r = base * 0.022;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(life * 3 + i);
      final tri = Path()
        ..moveTo(0, -r)
        ..lineTo(r, r * 0.8)
        ..lineTo(-r, r * 0.8)
        ..close();
      _inked(
        canvas,
        tri,
        Cartoon.cream.withValues(alpha: 1 - life),
        width: 1.6,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_GloomPainter old) => old.t != t;
}

/// 스몰 티츄 선언: 도장이 박히는 순간 뒤로 집중선이 뻗고 별이 튄다.
///
/// 만화의 집중선이다. 전에는 실제 번개처럼 생긴 선을 그렸는데, 그 묘사만
/// 사실적이어서 납작한 카드·좌석 위에 겹치면 겉돌았다.
class _LightningPainter extends CustomPainter {
  _LightningPainter({
    required this.t,
    required this.seed,
    required this.accent,
  });

  final double t;
  final int seed;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final base = math.min(size.width, size.height);
    final rnd = math.Random(seed);

    // 집중선: 가운데를 비우고 바깥으로 뻗는 삼각 살.
    final hit = Curves.easeOutCubic.transform((t / 0.22).clamp(0.0, 1.0));
    final fade = 1 - ((t - 0.5) / 0.4).clamp(0.0, 1.0);
    if (hit > 0 && fade > 0) {
      const spokes = 14;
      final inner = base * 0.26;
      final outer = base * (0.34 + 0.4 * hit);
      for (var i = 0; i < spokes; i++) {
        final a = (i / spokes) * math.pi * 2 + rnd.nextDouble() * 0.06;
        final w = 0.055 + rnd.nextDouble() * 0.035;
        final path = Path()
          ..moveTo(
            c.dx + inner * math.cos(a - w),
            c.dy + inner * math.sin(a - w),
          )
          ..lineTo(c.dx + outer * math.cos(a), c.dy + outer * math.sin(a))
          ..lineTo(
            c.dx + inner * math.cos(a + w),
            c.dy + inner * math.sin(a + w),
          )
          ..close();
        _inked(
          canvas,
          path,
          Cartoon.blue.withValues(alpha: 0.85 * fade),
          width: 1.8,
        );
      }
    }

    // 튀는 별 몇 개.
    for (var i = 0; i < 7; i++) {
      final delay = rnd.nextDouble() * 0.18;
      final life = ((t - delay) / 0.55).clamp(0.0, 1.0);
      if (life <= 0 || life >= 1) continue;
      final a = rnd.nextDouble() * math.pi * 2;
      final dist =
          base *
          (0.26 + 0.26 * rnd.nextDouble()) *
          Curves.easeOutCubic.transform(life);
      final p = Offset(c.dx + math.cos(a) * dist, c.dy + math.sin(a) * dist);
      final r = base * 0.035 * (1 - life);
      _inked(
        canvas,
        _starPath(p, r, r * 0.4, 4, a),
        accent.withValues(alpha: (1 - life).clamp(0.0, 1.0)),
        width: 1.4,
      );
    }
  }

  @override
  bool shouldRepaint(_LightningPainter old) => old.t != t;
}

/// 라지 티츄 선언: 뒤에서 톱니 폭발이 한 번 커지고, 두꺼운 살이 뻗는다.
///
/// 만화의 폭발 도형이다(전에는 불길을 그라데이션으로 그렸다).
class _FlamePainter extends CustomPainter {
  _FlamePainter({required this.t, required this.seed, required this.accent});

  final double t;
  final int seed;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final base = math.min(size.width, size.height);
    final rnd = math.Random(seed);

    final hit = Curves.easeOutBack.transform((t / 0.24).clamp(0.0, 1.0));
    final fade = 1 - ((t - 0.55) / 0.4).clamp(0.0, 1.0);

    // 톱니 폭발 두 겹. 바깥은 주황, 안쪽은 빨강.
    if (hit > 0 && fade > 0) {
      for (var layer = 0; layer < 2; layer++) {
        final r = base * (layer == 0 ? 0.52 : 0.4) * hit;
        final path = Path();
        const teeth = 11;
        for (var i = 0; i < teeth * 2; i++) {
          final far = i.isEven;
          final rr = far ? r : r * (0.62 + rnd.nextDouble() * 0.1);
          final a = -math.pi / 2 + i * math.pi / teeth + layer * 0.14;
          final o = Offset(c.dx + rr * math.cos(a), c.dy + rr * math.sin(a));
          if (i == 0) {
            path.moveTo(o.dx, o.dy);
          } else {
            path.lineTo(o.dx, o.dy);
          }
        }
        path.close();
        _inked(
          canvas,
          path,
          (layer == 0 ? accent : Cartoon.red).withValues(alpha: 0.9 * fade),
          width: layer == 0 ? 3.0 : 2.4,
        );
      }
    }

    // 날아가는 불씨 — 납작한 둥근 조각.
    for (var i = 0; i < 14; i++) {
      final delay = rnd.nextDouble() * 0.2;
      final life = ((t - delay) / 0.7).clamp(0.0, 1.0);
      if (life <= 0 || life >= 1) continue;
      final a = rnd.nextDouble() * math.pi * 2;
      final dist =
          base *
          (0.3 + 0.3 * rnd.nextDouble()) *
          Curves.easeOutCubic.transform(life);
      final p = Offset(
        c.dx + math.cos(a) * dist,
        c.dy + math.sin(a) * dist - base * 0.18 * life,
      );
      final r = base * 0.026 * (1 - life);
      _inked(
        canvas,
        Path()..addOval(Rect.fromCircle(center: p, radius: r)),
        (i.isEven ? Cartoon.yellow : accent).withValues(
          alpha: (1 - life).clamp(0.0, 1.0),
        ),
        width: 1.3,
      );
    }
  }

  @override
  bool shouldRepaint(_FlamePainter old) => old.t != t;
}
