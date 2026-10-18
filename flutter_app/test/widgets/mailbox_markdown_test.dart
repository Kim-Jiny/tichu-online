import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/widgets/notice_body.dart';

/// 우편 본문도 공지·문의 답변·약관과 같은 문법으로 읽힌다.
///
/// 우편은 운영자가 쓰는 글이고, 그 사람은 다른 화면에서 쓰던 문법을
/// 여기서도 쓴다. 읽는 쪽만 모르면 `**굵게**` 가 별표째로 나온다 —
/// 공지에서 한 번 겪은 일이다.
void main() {
  test('우편함이 본문을 NoticeBody 로 그린다', () {
    final src = File('lib/screens/mailbox_screen.dart').readAsStringSync();
    expect(
      src.contains("NoticeBody(content: (mail['body'] ?? '').toString())"),
      isTrue,
      reason: '우편 본문이 NoticeBody 를 거치지 않는다 — 마크다운이 글자 그대로 나온다',
    );
  });

  testWidgets('우편에서 흔한 문법이 글자 그대로 남지 않는다', (tester) async {
    const body = '**굵게** 안내\n\n- 첫째\n- 둘째\n\n[링크](https://tichu.kr)';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 320, child: NoticeBody(content: body)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 별표와 대괄호가 화면에 남아 있으면 파싱되지 않은 것이다.
    final shown = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((w) => w.text.toPlainText())
        .join('\n');
    expect(shown, contains('굵게'));
    expect(shown, contains('첫째'));
    expect(shown, contains('링크'));
    expect(shown, isNot(contains('**')));
    expect(shown, isNot(contains('](https://')));
  });
}
