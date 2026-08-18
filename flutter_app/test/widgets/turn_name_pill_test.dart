import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/widgets/turn_name_pill.dart';

/// 차례 표시가 네 게임에서 같은 모양이어야 한다.
///
/// 사진 테두리만으로도 차례를 말할 수는 있지만, 테두리는 역할·패 열람과
/// 색을 나눠 쓰는 자리다. 이름에 배경이 깔리는 건 그 자리 하나에만 생기는
/// 변화라 판을 훑을 때 걸린다.
///
/// 크기가 상태에 따라 달라지면 차례가 넘어갈 때마다 이름이 밀린다 — 그게
/// 여기서 제일 지키고 싶은 것이다.

BoxDecoration decorationOf(WidgetTester t) {
  final c = t.widget<AnimatedContainer>(find.byType(AnimatedContainer));
  return c.decoration! as BoxDecoration;
}

void main() {
  Future<void> pump(WidgetTester t, {required bool isTurn}) => t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: TurnNamePill(isTurn: isTurn, child: const Text('플레이어')),
        ),
      ),
    ),
  );

  testWidgets('차례면 노란 배경과 금색 테두리', (t) async {
    await pump(t, isTurn: true);
    await t.pumpAndSettle();
    final d = decorationOf(t);
    expect(d.color, TurnNamePill.background);
    expect((d.border! as Border).top.color, TurnNamePill.border);
  });

  testWidgets('차례가 아니면 아무것도 그리지 않는다', (t) async {
    await pump(t, isTurn: false);
    await t.pumpAndSettle();
    final d = decorationOf(t);
    expect(d.color, Colors.transparent);
    expect((d.border! as Border).top.color, Colors.transparent);
  });

  testWidgets('차례가 오가도 크기가 그대로다', (t) async {
    await pump(t, isTurn: false);
    await t.pumpAndSettle();
    final off = t.getSize(find.byType(TurnNamePill));
    await pump(t, isTurn: true);
    await t.pumpAndSettle();
    final on = t.getSize(find.byType(TurnNamePill));
    expect(on, off, reason: '크기가 변하면 차례마다 이름이 밀린다');
  });
}
