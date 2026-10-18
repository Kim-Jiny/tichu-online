import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/theme/cartoon.dart';
import 'package:tichu_online/widgets/token_cosmetics.dart';

/// 산 물건(말풍선·방 목록 강조)은 테마와 무관하게 같은 모양이어야 한다.
///
/// 바탕은 상품마다 고정인데 글자색만 팔레트를 따라가면, 어두운 테마에서
/// 연분홍 말풍선 위에 밝은 글자가 얹혀 안 보인다. 실제로 그랬다.
void main() {
  double ratio(Color a, Color b) {
    final v = [a.computeLuminance(), b.computeLuminance()]..sort();
    return (v[1] + 0.05) / (v[0] + 0.05);
  }

  tearDown(() => Cartoon.usePalette(cartoonLight));

  const bubbles = [
    'bubble_basic_1',
    'bubble_basic_2',
    'bubble_basic_3',
    'bubble_premium_1',
    'bubble_premium_2',
    'bubble_premium_3',
  ];
  const highlights = [
    'room_highlight_1',
    'room_highlight_2',
    'room_highlight_3',
  ];

  for (final palette in [cartoonLight, cartoonDark]) {
    final name = palette.dark ? '어두운' : '밝은';

    test('$name 한 벌: 말풍선 글자가 제 바탕 위에서 읽힌다', () {
      Cartoon.usePalette(palette);
      for (final key in bubbles) {
        final s = bubbleStyleFor(key);
        expect(s, isNotNull, reason: '$key 가 없다');
        // 글자색을 직접 적어 둔 상품은 그 선택을 존중한다. 흰 글자에
        // 주황 바탕처럼 대비가 낮은 것도 있는데, 그건 원래 그렇게 만든
        // 것이지 테마 때문에 생긴 문제가 아니다.
        if (s!.text != null) continue;
        final bg = s.fillEnd == null
            ? s.fill
            : Color.lerp(s.fill, s.fillEnd, 0.5)!;
        expect(
          ratio(s.inkOn, bg),
          greaterThanOrEqualTo(4.5),
          reason: '$key 의 글자가 바탕에 묻힌다',
        );
      }
    });

    test('$name 한 벌: 방 강조 글자가 읽힌다', () {
      Cartoon.usePalette(palette);
      for (final key in highlights) {
        final s = roomHighlightFor(key);
        expect(s, isNotNull, reason: '$key 가 없다');
        expect(
          ratio(s!.inkOn, s.fill),
          greaterThanOrEqualTo(4.5),
          reason: '$key 의 글자가 바탕에 묻힌다',
        );
      }
    });
  }

  test('테마가 바뀌어도 같은 글자색 — 산 물건은 변하지 않는다', () {
    Cartoon.usePalette(cartoonLight);
    final light = {
      for (final k in [...bubbles, ...highlights])
        k: (bubbleStyleFor(k)?.inkOn ?? roomHighlightFor(k)!.inkOn).toARGB32(),
    };
    Cartoon.usePalette(cartoonDark);
    for (final k in light.keys) {
      final now = (bubbleStyleFor(k)?.inkOn ?? roomHighlightFor(k)!.inkOn)
          .toARGB32();
      expect(now, light[k], reason: '$k 의 글자색이 테마를 따라 바뀐다');
    }
  });
}
