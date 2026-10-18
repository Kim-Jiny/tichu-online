import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/theme/cartoon.dart';
import 'package:tichu_online/utils/banner_ink.dart';
import 'package:tichu_online/widgets/notice_body.dart';
import 'package:tichu_online/widgets/seat_chat_bubble.dart';
import 'package:tichu_online/widgets/title_chip.dart';

/// 위젯을 실제로 그려서 나온 픽셀로 대비를 잰다.
///
/// 지금까지의 검사는 전부 소스를 글자로 훑는 방식이었고, 세 종류를
/// 원리적으로 못 잡았다:
///
///  * 정규식이 나열한 타입 밖의 선언 — `Map<String, Color>` 로 된 색표
///  * 문법은 멀쩡하고 맥락만 틀린 것 — 배너 위에 팔레트를 태운 칭호
///  * 소스에 아예 없는 글자 — `maxLength` 가 붙이는 '0/N' 표시
///
/// 셋 다 "그려 놓고 보면" 바로 드러난다. 그래서 여기서는 위젯을 두 팔레트로
/// 각각 그리고, 나온 그림에서 바탕색과 가장 먼 색을 글자로 보아 대비를 잰다.
/// 무엇이 글자를 그렇게 칠했는지는 묻지 않는다 — 결과만 본다.
void main() {
  const aa = 4.5;

  tearDown(() => Cartoon.usePalette(cartoonLight));

  /// 밝은 배너 하나. 상품 색이라 어느 한 벌에서나 이대로다.
  const brightBanner = LinearGradient(
    colors: [Color(0xFFFFE0B2), Color(0xFFFFF3E0)],
  );

  /// [build] 가 만든 위젯을 두 한 벌에서 각각 그려 대비를 확인한다.
  Future<void> checkBothPalettes(
    WidgetTester tester,
    String what,
    Widget Function() build, {
    Color? background,
  }) async {
    for (final palette in [cartoonLight, cartoonDark]) {
      Cartoon.usePalette(palette);
      final name = palette.dark ? '어두운' : '밝은';
      final ratio = await _renderedContrast(
        tester,
        build(),
        background ?? Cartoon.paper,
      );
      expect(
        ratio,
        greaterThanOrEqualTo(aa),
        reason: '$what — $name 한 벌에서 ${ratio.toStringAsFixed(2)}:1',
      );
    }
  }

  testWidgets('말풍선 글자', (tester) async {
    await checkBothPalettes(
      tester,
      '대기실 기본 말풍선',
      () => const SeatChatBubble(text: '가나다라'),
    );
    await checkBothPalettes(
      tester,
      '게임 화면 불투명 말풍선',
      () => const SeatChatBubble(text: '가나다라', opaque: true),
    );
  });

  testWidgets('공지 본문', (tester) async {
    await checkBothPalettes(
      tester,
      '공지·문의 답변·약관 본문',
      () => const SizedBox(width: 300, child: NoticeBody(content: '가나다라마바사')),
    );
  });

  testWidgets('칭호 — 앱의 판 위', (tester) async {
    for (final key in ['title_pirate', 'title_tactician', 'custom:slate']) {
      await checkBothPalettes(
        tester,
        '칭호 $key',
        () => TitleChip(titleKey: key, titleName: '칭호', fontSize: 28),
      );
    }
  });

  testWidgets('칭호 — 밝은 배너 위', (tester) async {
    // 배너는 상품 색이라 한 벌을 안 탄다. 칭호만 팔레트를 따라 밝아지면
    // 어두운 한 벌에서 밝은 배너에 밝은 글자가 된다.
    for (final key in ['title_pirate', 'title_tactician']) {
      for (final palette in [cartoonLight, cartoonDark]) {
        Cartoon.usePalette(palette);
        final ratio = await _renderedContrast(
          tester,
          DecoratedBox(
            decoration: const BoxDecoration(gradient: brightBanner),
            child: TitleChip(
              titleKey: key,
              titleName: '칭호',
              fontSize: 28,
              onInk: profileBannerInk(brightBanner, null),
            ),
          ),
          brightBanner.colors.first,
        );
        expect(
          ratio,
          greaterThanOrEqualTo(aa),
          reason:
              '밝은 배너 위 $key — ${palette.dark ? "어두운" : "밝은"} 한 벌에서 '
              '${ratio.toStringAsFixed(2)}:1',
        );
      }
    }
  });

  testWidgets('글자 수 표시', (tester) async {
    // maxLength 가 붙이는 '0/N' 은 소스에 없는 글자다. 그려 봐야 보인다.
    await checkBothPalettes(
      tester,
      "입력칸의 '0/10' 표시",
      () => SizedBox(
        width: 300,
        child: TextField(
          maxLength: 10,
          style: Cartoon.userText(size: 15),
          decoration: InputDecoration(
            counterStyle: Cartoon.text(
              size: 12,
              color: Cartoon.ink.withValues(alpha: 0.78),
            ),
          ),
        ),
      ),
    );
  });
}

/// [child] 를 [background] 위에 그려, 바탕에서 가장 먼 픽셀과의 대비를 낸다.
///
/// 반글림(anti-alias)으로 흐려진 가장자리 픽셀이 가장 진한 색을 가리지
/// 않도록, 색마다 몇 번 나왔는지 세어 **드물게 나온 색은 버린다** — 글자
/// 획의 속은 충분히 많이 나오고, 가장자리 한 줄은 그렇지 않다.
Future<double> _renderedContrast(
  WidgetTester tester,
  Widget child,
  Color background,
) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: background,
        body: Center(
          child: RepaintBoundary(
            key: key,
            child: ColoredBox(color: background, child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  ByteData? data;
  var width = 0;
  var height = 0;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    width = image.width;
    height = image.height;
    data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  });

  final pixels = data!.buffer.asUint8List();
  final pageRgb =
      (background.r * 255).round() << 16 |
      (background.g * 255).round() << 8 |
      (background.b * 255).round();

  final counts = <int, int>{};
  for (var i = 0; i < width * height; i++) {
    final o = i * 4;
    if (pixels[o + 3] < 250) continue; // 반투명 가장자리는 버린다
    final rgb = (pixels[o] << 16) | (pixels[o + 1] << 8) | pixels[o + 2];
    if (rgb == pageRgb) continue; // 위젯 둘레로 비치는 페이지 배경
    counts[rgb] = (counts[rgb] ?? 0) + 1;
  }
  if (counts.length < 2) return 21; // 글자가 안 그려졌으면 잴 것이 없다

  // 넓이로 가린다. '바탕에서 가장 먼 색' 을 글자로 보면 안 된다 — 위젯
  // 둘레로 비치는 페이지 배경이 글자보다 멀어서, 글자가 바탕에 묻혀
  // 있어도 그쪽을 집어 통과시킨다. 실제로 그렇게 놓친 적이 있다.
  //
  // 넓이 순으로는 늘 '위젯 제 바탕 > 글자 획 속 > 반글림 중간색' 이다.
  // 획 속은 한 색으로 넓게 차지만 중간색은 색마다 몇 픽셀씩만 나온다.
  final sorted = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final fill = Color(0xFF000000 | sorted.first.key);

  // 바탕을 가린 다음에는 '가장 먼 색' 이 글자다. 두 번째로 넓은 색을
  // 집으면 안 된다 — 가는 획은 속보다 반글림 중간색이 더 넓을 때가 있어,
  // 멀쩡한 글자를 흐리다고 잡는다.
  //
  // 획으로 인정할 최소 넓이를 둔다. 중간색은 색마다 몇 픽셀씩만 나오므로
  // 고정 하한으로 걸러진다. 바탕 넓이에 비례시키면 안 된다 — 바탕이
  // 넓을수록 문턱이 올라가 작은 글자가 통째로 걸러진다.
  const minStrokePixels = 12;
  var worst = 1.0;
  for (final e in sorted.skip(1)) {
    if (e.value < minStrokePixels) continue;
    final r = _contrast(Color(0xFF000000 | e.key), fill);
    if (r > worst) worst = r;
  }
  return worst;
}

double _contrast(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  final hi = x > y ? x : y;
  final lo = x > y ? y : x;
  return (hi + 0.05) / (lo + 0.05);
}
