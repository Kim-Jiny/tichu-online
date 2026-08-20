import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/widgets/docked_chat_panel.dart';

/// 대기실 채팅창 크기 조절.
///
/// 유저 리포트: 키보드가 올라와 있으면 크기 조절이 안 된다. 키보드가 차지한
/// 만큼 이 패널이 앉을 상자가 줄고, 좌석 몫을 떼고 나면 남는 게 거의 없어서
/// 높이가 한 값에 고정된다 — 끌어도 화면이 안 움직인다. 떠 있는 채팅창은
/// 드래그를 시작할 때 키보드를 내려서 이 상황을 피하고 있었다.

Widget harness({required ValueChanged<double> onResize}) {
  return MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          SizedBox(
            height: 300,
            child: DockedChatPanel(
              accentColor: Colors.blue,
              sendIconColor: Colors.blue,
              title: '채팅',
              hintText: '메시지 입력...',
              controller: TextEditingController(),
              scrollController: ScrollController(),
              onSend: () {},
              onUndock: () {},
              itemCount: 0,
              itemBuilder: (_, _) => const SizedBox.shrink(),
              onResize: onResize,
              onResizeEnd: () {},
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('헤더를 끌면 크기 조절 요청이 올라온다', (tester) async {
    final asked = <double>[];
    await tester.pumpWidget(harness(onResize: asked.add));
    await tester.pumpAndSettle();

    await tester.drag(find.byIcon(Icons.drag_handle), const Offset(0, -40));
    await tester.pumpAndSettle();

    expect(asked, isNotEmpty);
    expect(asked.last, greaterThan(300), reason: '위로 끌었으면 더 큰 높이를 요청해야 한다');
  });

  testWidgets('크기 조절을 시작하면 키보드부터 내린다', (tester) async {
    // 키보드가 떠 있는 채로는 상한이 바닥값보다 낮아져 아무리 끌어도 높이가
    // 안 바뀐다. 그래서 드래그 시작에 포커스를 놓는다.
    await tester.pumpWidget(harness(onResize: (_) {}));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
      isTrue,
      reason: '준비 상태 확인',
    );

    await tester.drag(find.byIcon(Icons.drag_handle), const Offset(0, -40));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
      isFalse,
    );
  });
}
