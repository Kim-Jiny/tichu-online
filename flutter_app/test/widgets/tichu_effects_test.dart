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
}
