import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/widgets/seat_chat_bubble.dart';

/// 좌석 말풍선의 크기 규칙.
///
/// 기본값은 폰에 맞춰 잡혀 있다 — 좌석이 작아서 말풍선이 커지면 옆자리를
/// 덮는다. 웹·태블릿은 화면이 넓은데 같은 11pt 한 줄이라 작고, 문장 대부분이
/// ... 로 끝났다. 그래서 화면 폭을 기준으로 그 사이를 매운다.

/// 좌석 하나를 화면 가운데 앉히고 말풍선을 띄운다.
Widget seatAt(Size screen, {String text = '가나다라마바사아자차카타파하'}) {
  return MediaQuery(
    data: MediaQueryData(size: screen),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Overlay(
        initialEntries: [
          OverlayEntry(
            builder: (_) => Center(
              child: SeatBubbleAnchor(
                text: text,
                child: const SizedBox(width: 100, height: 120),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

SeatChatBubble bubbleOf(WidgetTester tester) =>
    tester.widget<SeatChatBubble>(find.byType(SeatChatBubble));

void main() {
  testWidgets('폰 폭에서는 지금 크기 그대로 — 11pt 한 줄', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(seatAt(const Size(360, 800)));
    await tester.pumpAndSettle();

    expect(bubbleOf(tester).fontSize, 11);
    expect(bubbleOf(tester).maxLines, 1);
  });

  testWidgets('넓은 화면에서는 글씨가 커지고 두 줄까지 나온다', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(seatAt(const Size(1280, 900)));
    await tester.pumpAndSettle();

    expect(bubbleOf(tester).fontSize, greaterThan(11));
    expect(bubbleOf(tester).maxLines, 2);
  });

  testWidgets('그 사이 폭은 사이 크기 — 갑자기 튀지 않는다', (tester) async {
    tester.view.physicalSize = const Size(640, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(seatAt(const Size(640, 900)));
    await tester.pumpAndSettle();

    final size = bubbleOf(tester).fontSize;
    expect(size, greaterThan(11));
    expect(size, lessThan(15));
  });

  testWidgets('가장자리 좌석은 화면 밖으로 나가지 않는다', (tester) async {
    // 티츄 보드의 좌/우 좌석 자리. 말풍선은 좌석 한가운데에 걸리므로,
    // 폭을 그대로 주면 왼쪽이 화면 밖으로 넘어간다.
    const screen = Size(360, 800);
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: screen),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (_) => Align(
                alignment: Alignment.centerLeft,
                child: SeatBubbleAnchor(
                  text: '한 줄이 길면 어떻게 보이는지도 봐야 하니까 길게 씁니다',
                  child: const SizedBox(width: 100, height: 120),
                ),
              ),
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byType(SeatChatBubble));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(screen.width));
  });
}
