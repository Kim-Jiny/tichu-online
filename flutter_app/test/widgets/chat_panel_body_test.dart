import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/widgets/chat_panel_body.dart';

/// 엔터로 한 줄 보낸 뒤에도 입력창에 그대로 커서가 있어야 한다.
///
/// 한 줄짜리 TextField 는 제출을 처리하고 나서 포커스를 놓는 게 기본이다.
/// 폼에서는 그게 맞지만 채팅에서는 아니다 — 한 마디로 끝나는 일이 드물어서,
/// 보낼 때마다 입력창을 다시 눌러야 한다. 키보드로 치는 웹에서 특히 걸린다.

Widget harness({
  required TextEditingController controller,
  required VoidCallback onSend,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ChatPanelBody(
        scrollController: ScrollController(),
        controller: controller,
        hintText: '메시지 입력...',
        onSend: onSend,
        sendIconColor: Colors.blue,
        itemCount: 0,
        itemBuilder: (_, _) => const SizedBox.shrink(),
        onTapMessages: () {},
      ),
    ),
  );
}

bool inputHasFocus(WidgetTester tester) {
  final field = tester.widget<TextField>(find.byType(TextField));
  return field.focusNode?.hasFocus ?? false;
}

void main() {
  testWidgets('엔터로 보낸 뒤에도 입력창에 커서가 남는다', (tester) async {
    var sent = 0;
    final controller = TextEditingController();
    await tester.pumpWidget(harness(
      controller: controller,
      onSend: () {
        sent++;
        controller.clear();
      },
    ));

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '안녕하세요');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    // 포커스를 되찾는 건 프레임이 끝난 뒤다 — 그전에 보면 놓친 상태로 보인다.
    await tester.pumpAndSettle();

    expect(sent, 1);
    expect(inputHasFocus(tester), isTrue);
  });

  testWidgets('연달아 여러 줄을 보낼 수 있다', (tester) async {
    var sent = 0;
    final controller = TextEditingController();
    await tester.pumpWidget(harness(
      controller: controller,
      onSend: () {
        sent++;
        controller.clear();
      },
    ));

    await tester.tap(find.byType(TextField));
    await tester.pump();
    for (final line in ['하나', '둘', '셋']) {
      await tester.enterText(find.byType(TextField), line);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }

    expect(sent, 3, reason: '중간에 포커스를 잃으면 두 번째부터 입력이 안 들어간다');
    expect(inputHasFocus(tester), isTrue);
  });

  testWidgets('키보드가 올라온 채로 버튼을 눌러도 한 번에 보내진다', (tester) async {
    // 유저 리포트: 앱에서 전송 버튼이 안 눌린다. 키보드로 완료를 치면 보내진다.
    // TextField 는 바깥을 탭하면 포커스를 놓는데 바로 옆 버튼도 바깥이라,
    // 누르는 순간 키보드가 내려가고 그 사이 창이 움직여 탭이 취소됐다.
    var sent = 0;
    final controller = TextEditingController();
    await tester.pumpWidget(harness(
      controller: controller,
      onSend: () {
        sent++;
        controller.clear();
      },
    ));

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '버튼으로 한 번에');
    expect(inputHasFocus(tester), isTrue, reason: '준비 상태 확인');

    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(sent, 1);
    expect(inputHasFocus(tester), isTrue,
        reason: '포커스가 빠지면 키보드가 내려가고 그 프레임에 탭이 씹힌다');
  });

  testWidgets('보내기 버튼으로 보낼 때는 포커스를 건드리지 않는다', (tester) async {
    // 버튼은 마우스·손가락으로 누르는 길이다. 그쪽까지 강제로 포커스를 주면
    // 폰에서 키보드가 다시 올라온다.
    var sent = 0;
    final controller = TextEditingController();
    await tester.pumpWidget(harness(
      controller: controller,
      onSend: () {
        sent++;
        controller.clear();
      },
    ));

    await tester.enterText(find.byType(TextField), '버튼으로');
    // 입력창에서 손을 뗀 상태를 만든다 — 폰에서 키보드를 내리고 버튼만
    // 누르는 경우다.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(inputHasFocus(tester), isFalse, reason: '준비 상태 확인');

    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(sent, 1);
    expect(inputHasFocus(tester), isFalse,
        reason: '버튼으로 보냈는데 포커스가 붙으면 폰에서 키보드가 다시 올라온다');
  });
}
