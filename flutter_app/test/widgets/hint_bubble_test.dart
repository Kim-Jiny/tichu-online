import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/widgets/hint_bubble.dart';

void main() {
  testWidgets('말풍선은 글자를 보여 주고, 누르면 콜백이 불린다', (t) async {
    var taps = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: HintBubble(
              text: '오늘의 미션을 선택하세요!',
              pointsDown: true,
              onTap: () => taps++,
            ),
          ),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('오늘의 미션을 선택하세요!'), findsOneWidget);
    await t.tap(find.text('오늘의 미션을 선택하세요!'));
    expect(taps, 1);
  });

  testWidgets('꼬리 방향에 따라 꼬리가 몸통 아래/위에 놓인다', (t) async {
    Future<double> tailY(bool down) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: HintBubble(text: '안내', pointsDown: down),
            ),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 500));
      final text = t.getCenter(find.text('안내')).dy;
      final tail = t.getCenter(find.byType(CustomPaint).last).dy;
      return tail - text;
    }

    expect(await tailY(true), greaterThan(0)); // 아래를 가리키는 꼬리는 글자 아래
    expect(await tailY(false), lessThan(0)); // 위를 가리키는 꼬리는 글자 위
  });
}
