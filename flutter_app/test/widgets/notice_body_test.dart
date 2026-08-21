import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/widgets/notice_body.dart';

/// 공지 본문 렌더링.
///
/// 예전에는 Text 하나에 통째로 넣어서, 운영자가 쓴 `**문의하기**` 가 별표째로
/// 보이고 문단이 한 덩어리로 붙었다. 실제로 쓰이는 문법만 알아본다.

void main() {
  group('블록 나누기', () {
    test('빈 줄이 문단을 나눈다', () {
      final b = parseNoticeBlocks('첫 문단입니다.\n\n둘째 문단입니다.');
      expect(b.length, 2);
      expect(b.every((x) => x.kind == NoticeBlockKind.paragraph), isTrue);
      expect(b[0].text, '첫 문단입니다.');
      expect(b[1].text, '둘째 문단입니다.');
    });

    test('한 문단 안의 줄바꿈은 유지된다', () {
      final b = parseNoticeBlocks('첫 줄\n둘째 줄');
      expect(b.length, 1);
      expect(b[0].text, '첫 줄\n둘째 줄');
    });

    test('# 과 ## 은 제목', () {
      final b = parseNoticeBlocks('# 큰제목\n\n## 작은제목');
      expect(b[0].kind, NoticeBlockKind.heading1);
      expect(b[0].text, '큰제목');
      expect(b[1].kind, NoticeBlockKind.heading2);
    });

    test('- 와 * 는 글머리표 목록으로 묶인다', () {
      final b = parseNoticeBlocks('- 하나\n- 둘\n* 셋');
      expect(b.length, 1);
      expect(b[0].kind, NoticeBlockKind.bullet);
      expect(b[0].items, ['하나', '둘', '셋']);
      expect(b[0].marker(0), '•');
    });

    test('숫자 목록은 번호를 매긴다', () {
      final b = parseNoticeBlocks('1. 하나\n2. 둘');
      expect(b[0].items, ['하나', '둘']);
      expect(b[0].marker(0), '1.');
      expect(b[0].marker(1), '2.');
    });

    test('--- 는 구분선', () {
      final b = parseNoticeBlocks('위\n\n---\n\n아래');
      expect(b[1].kind, NoticeBlockKind.divider);
    });

    test('제목은 문단보다 위 여백이 넓다', () {
      final b = parseNoticeBlocks('문단\n\n# 제목');
      expect(b[1].spacingBefore, greaterThan(b[0].spacingBefore));
    });
  });

  group('한 줄 안의 문법', () {
    test('**굵게** 는 별표를 떼고 굵게', () {
      final p = parseInline('앱 내 **문의하기**를 통해');
      expect(p.map((x) => x.text).join(), '앱 내 문의하기를 통해');
      expect(p.firstWhere((x) => x.text == '문의하기').bold, isTrue);
    });

    test('링크는 보이는 글만 남기고 주소를 붙든다', () {
      final p = parseInline('자세히는 [공식 카페](https://cafe.naver.com/x) 에서');
      expect(p.map((x) => x.text).join(), '자세히는 공식 카페 에서');
      expect(p.firstWhere((x) => x.href != null).href, 'https://cafe.naver.com/x');
    });

    test('문법이 없으면 그대로 한 조각', () {
      final p = parseInline('그냥 문장입니다');
      expect(p.length, 1);
      expect(p.single.text, '그냥 문장입니다');
      expect(p.single.bold, isFalse);
    });

    test('짝이 안 맞는 별표는 글자 그대로 둔다', () {
      // 깨진 화면보다 그냥 글씨가 낫다.
      final p = parseInline('별표 하나 * 만 있음');
      expect(p.map((x) => x.text).join(), '별표 하나 * 만 있음');
      expect(p.every((x) => !x.bold), isTrue);
    });
  });

  testWidgets('실제 공지가 별표 없이 그려진다', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: NoticeBody(
          content: '기능 개선 의견은 앱 내 **문의하기**로 알려주세요.\n\n'
              '- 봇 플레이 제보\n- 불편한 점',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('**'), findsNothing, reason: '별표가 그대로 보이면 안 된다');
    expect(find.textContaining('문의하기'), findsOneWidget);
    expect(find.text('•'), findsNWidgets(2));
  });
}
