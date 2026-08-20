import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tichu_online/widgets/draggable_chat_panel.dart';

/// 떠 있는 채팅창의 전송 버튼이 실제로 눌리는지.
///
/// 유저 리포트: 안드로이드에서 전송 버튼이 안 눌린다. 키보드의 완료로는
/// 보내진다. 패널 오른쪽 아래에 리사이즈 손잡이가 얹혀 있는데(36×36,
/// HitTestBehavior.opaque, 본문보다 나중에 그려짐) 전송 버튼이 정확히 그
/// 자리에 있었다 — 손잡이엔 onTap 이 없으니 탭은 그냥 사라지고, 손가락이
/// 조금이라도 움직이면 onPanStart 가 물려 키보드만 내려갔다.

Widget harness({required VoidCallback onSend, Size size = const Size(420, 800)}) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            DraggableChatPanel(
              accentColor: Colors.blue,
              sendIconColor: Colors.blue,
              title: '채팅',
              hintText: '메시지 입력...',
              controller: TextEditingController(),
              scrollController: ScrollController(),
              onSend: onSend,
              onClose: () {},
              itemCount: 0,
              itemBuilder: (_, _) => const SizedBox.shrink(),
              persistKey: 'test_chat_panel',
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('전송 버튼을 누르면 눌린다 — 리사이즈 손잡이에 가리지 않는다',
      (tester) async {
    var sent = 0;
    await tester.pumpWidget(harness(onSend: () => sent++));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(sent, 1, reason: '탭이 손잡이에 먹히면 여기서 0 이 된다');
  });

  testWidgets('전송 버튼과 리사이즈 손잡이가 겹치지 않는다', (tester) async {
    await tester.pumpWidget(harness(onSend: () {}));
    await tester.pumpAndSettle();

    final send = tester.getRect(find.byIcon(Icons.send));
    final grip = tester.getRect(find.byIcon(Icons.open_in_full));
    expect(send.overlaps(grip), isFalse,
        reason: '전송 $send / 손잡이 $grip');
  });
}
