import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/services/game_service.dart';
import 'package:tichu_online/widgets/chat_bubble.dart';
import 'package:tichu_online/widgets/token_cosmetics.dart';

/// 채팅창 안의 말풍선에도 토큰 상점 말풍선 모양이 입혀진다.
class _FakeGame extends ChangeNotifier implements GameService {
  _FakeGame(this.bubbles);
  final Map<String, String> bubbles;

  @override
  String? chatBubbleFor(String nickname) => bubbles[nickname];
  @override
  String? chatPhotoUrlFor(String nickname) => null;
  @override
  Set<String> get blockedUsers => <String>{};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<void> pumpLine(
    WidgetTester t,
    _FakeGame game,
    String sender, {
    bool isMe = false,
  }) => t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ChatBubble(
          sender: sender,
          message: '안녕하세요',
          isMe: isMe,
          game: game,
        ),
      ),
    ),
  );

  /// 말풍선 몸통(메시지 글자를 감싼 Container)의 장식.
  BoxDecoration? bodyDecoration(WidgetTester t) {
    final c = t
        .widgetList<Container>(
          find.ancestor(
            of: find.text('안녕하세요'),
            matching: find.byType(Container),
          ),
        )
        .first;
    return c.decoration as BoxDecoration?;
  }

  testWidgets('장착한 사람의 채팅 줄은 그 모양(색·테두리)으로 그려진다', (t) async {
    final game = _FakeGame({'꾸밈이': 'bubble_basic_1'});
    await pumpLine(t, game, '꾸밈이');
    final style = bubbleStyleFor('bubble_basic_1')!;
    final deco = bodyDecoration(t)!;
    expect(deco.color, style.fill);
    expect((deco.border as Border).top.color, style.border);
  });

  testWidgets('상위 모양은 그라데이션과 글자색까지 바뀐다', (t) async {
    final game = _FakeGame({'꾸밈이': 'bubble_premium_3'});
    await pumpLine(t, game, '꾸밈이');
    final style = bubbleStyleFor('bubble_premium_3')!;
    expect(bodyDecoration(t)!.gradient, isNotNull);
    final text = t.widget<Text>(find.text('안녕하세요'));
    expect(text.style!.color, style.text);
  });

  testWidgets('내 말풍선도 장착했으면 그 모양(기본 파랑 대신)', (t) async {
    final game = _FakeGame({'나': 'bubble_basic_3'});
    await pumpLine(t, game, '나', isMe: true);
    expect(bodyDecoration(t)!.color, bubbleStyleFor('bubble_basic_3')!.fill);
  });

  testWidgets('장착하지 않았거나 모르는 키면 기본 모양', (t) async {
    final game = _FakeGame({'모름': 'bubble_unknown_9'});
    await pumpLine(t, game, '평범이');
    expect(bodyDecoration(t)!.color, Colors.white);
    await pumpLine(t, game, '모름');
    await pumpLine(t, game, '평범이', isMe: true);
    expect(bodyDecoration(t)!.color, const Color(0xFF64B5F6)); // 기본 내 말풍선 파랑
  });

  testWidgets('시스템 줄(보낸 사람 없음)에는 모양을 입히지 않는다', (t) async {
    final game = _FakeGame({'': 'bubble_basic_1'});
    await pumpLine(t, game, '');
  });
}
