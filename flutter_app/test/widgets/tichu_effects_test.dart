import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/widgets/tichu_effects.dart';

Widget _host(Widget fx, {VoidCallback? onBelowTap}) => MaterialApp(
  home: Scaffold(
    body: Stack(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onBelowTap,
          child: const SizedBox.expand(),
        ),
        Positioned.fill(child: fx),
      ],
    ),
  ),
);

void main() {
  testWidgets('모든 연출이 그려지고, 끝나면 onDone 을 부른다', (tester) async {
    final done = <int>[];
    final events = [
      for (final (i, k) in TichuFxKind.values.indexed)
        TichuFxEvent(id: i + 1, kind: k, title: '제목 ${k.name}', subtitle: '부제'),
    ];
    await tester.pumpWidget(
      _host(TichuFxLayer(events: events, onDone: done.add)),
    );

    // 팝 애니메이션 중간 — 글자가 보이고 예외가 없어야 한다.
    await tester.pump(const Duration(milliseconds: 300));
    // 테두리 글자와 채움 글자 두 겹으로 그린다.
    expect(find.text('제목 oneTwo'), findsWidgets);
    expect(find.text('제목 tichuFail'), findsWidgets);
    expect(tester.takeException(), isNull);

    // 가장 긴 연출(2.8s)보다 뒤 — 전부 끝났다고 알려야 한다.
    await tester.pump(const Duration(seconds: 3));
    expect(done.toSet(), {for (var i = 1; i <= events.length; i++) i});
  });

  testWidgets('연출이 없으면 아래 화면 터치가 그대로 간다', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        TichuFxLayer(events: const [], onDone: (_) {}),
        onBelowTap: () => taps++,
      ),
    );
    await tester.tapAt(const Offset(20, 20));
    expect(taps, 1);
  });

  testWidgets('연출 중에도 아래 화면의 터치를 막지 않는다', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        TichuFxLayer(
          events: [
            TichuFxEvent(id: 1, kind: TichuFxKind.declareLarge, title: '라지'),
          ],
          onDone: (_) {},
        ),
        onBelowTap: () => taps++,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tapAt(const Offset(20, 20));
    expect(taps, 1);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('목록이 줄어든 뒤에 끝나는 연출도 예외 없이 id 로 알린다', (tester) async {
    final events = [
      TichuFxEvent(id: 1, kind: TichuFxKind.finished, title: 'a'), // 1.5s
      TichuFxEvent(id: 2, kind: TichuFxKind.oneTwo, title: 'b'), // 2.8s
    ];
    final done = <int>[];
    late StateSetter set;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return TichuFxLayer(
              events: List.of(events),
              onDone: (id) {
                done.add(id);
                set(() => events.removeWhere((e) => e.id == id));
              },
            );
          },
        ),
      ),
    );
    // 1번이 먼저 끝나 목록에서 빠진 뒤, 인덱스가 밀린 2번이 끝난다.
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(tester.takeException(), isNull);
    expect(done, [1, 2]);
  });

  // ── 생김새가 앱과 같은 세계에 있는지 ──
  //
  // 이 파일만 다른 톤으로 흘러갔던 적이 있다. Jua 를 한 곳도 쓰지 않고,
  // 빛 번짐이 여섯 군데 있고, 머티리얼 기본색(B71C1C·9E9E9E)을 쓰고
  // 있었다. 눈으로는 "좀 안 맞네" 로만 보여서 오래 남았다. 그래서 그
  // 세 가지를 소스에서 직접 확인한다 — 위젯을 띄워 색을 읽는 것보다
  // 이쪽이 틀렸을 때 무엇을 고쳐야 하는지 분명하다.
  group('카툰 톤을 벗어나지 않는다', () {
    final src = File('lib/widgets/tichu_effects.dart').readAsStringSync();

    test('번짐을 쓰지 않는다 — 카툰은 테두리가 또렷한 단색 면이다', () {
      final blur = RegExp(
        r'blurRadius|MaskFilter|ImageFilter\.blur',
      ).allMatches(src).map((m) => m.group(0)).toList();
      expect(blur, isEmpty, reason: '번짐이 남아 있다: $blur');
    });

    test('색을 직접 적지 않는다 — 카툰 팔레트에서 가져온다', () {
      // 0xFF... 로 박힌 색은 팔레트 밖이라는 뜻이다.
      final hard = RegExp(
        r'0x[fF]{2}[0-9a-fA-F]{6}',
      ).allMatches(src).map((m) => m.group(0)).toSet();
      expect(hard, isEmpty, reason: '팔레트 밖의 색: $hard');
    });

    test('글자는 Jua 를 쓴다(공용 헬퍼로)', () {
      expect(
        src.contains('Cartoon.outlinedText'),
        isTrue,
        reason: '제목이 공용 외곽선 글자 헬퍼를 쓰지 않는다',
      );
      // 닉네임·점수는 사용자 글자라 Jua 가 아니어야 한다.
      expect(
        src.contains('Cartoon.userText'),
        isTrue,
        reason: '부제(닉네임·점수)가 사용자 글자 헬퍼를 쓰지 않는다',
      );
    });

    test('큰 글자의 외곽선은 비율 기본값을 쓰지 않는다', () {
      // 기본 비율(0.28)은 버튼 크기(11~30)에 맞춰 둔 값이다. 외곽선은 획
      // 가운데에 그려지므로 절반이 안쪽을 먹는데, 36~42 에서는 10~12px 이
      // 되어 Jua 의 획보다 두꺼워진다 — 글자 속이 사라져 덩어리로 보였다.
      expect(
        src.contains('strokeWidth:'),
        isTrue,
        reason: '제목이 외곽선 두께를 직접 주지 않는다(기본 비율이면 뭉개진다)',
      );
      final m = RegExp(r'strokeWidth: size \* ([0-9.]+)').firstMatch(src);
      expect(m, isNotNull, reason: 'strokeWidth 를 글자 크기 비율로 주지 않는다');
      final ratio = double.parse(m!.group(1)!);
      // 번짐(두께/2)이 한글 속공간(36px 글자에서 3~4px)의 절반을 넘으면
      // '공'·'패' 의 틈이 닫혀 글자로 안 읽힌다. 0.13 도 두꺼웠다.
      expect(
        ratio,
        lessThanOrEqualTo(0.08),
        reason: '비율 $ratio → 36px 에서 번짐 ${36 * ratio / 2}px, 한글 속이 막힌다',
      );
    });

    test('판에는 잉크 테두리와 단색 그림자가 있다', () {
      expect(src.contains('color: Cartoon.ink'), isTrue);
      expect(
        src.contains('BoxShadow(color: Cartoon.ink'),
        isTrue,
        reason: '번짐 없는 단색 그림자가 아니다',
      );
    });
  });
}
