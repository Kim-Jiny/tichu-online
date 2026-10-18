import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 테마가 정한 색은 팔레트를 거치면 안 된다.
///
/// 테마는 바탕을 정하는 '주체' 다. 그 색을 다시 팔레트에 통과시키면
/// 두 번 뒤집힌다 — 어두운 테마의 남색 배경이 밝아져서 로비가 환해졌다.
///
/// 배너·말풍선·방 강조도 같다. 그쪽은 상품이라 테마와 무관해야 한다
/// (cosmetics_contrast_test.dart).
void main() {
  test('테마 색 표에 surface/onSurface 가 없다', () {
    final src = File('lib/services/game_service.dart').readAsStringSync();
    final offenders = <String>[];
    for (final fn in [
      'List<Color> themeGradientFor(',
      'List<Color> cardBackColorsFor(',
    ]) {
      final i = src.indexOf(fn);
      expect(i, greaterThan(0), reason: '$fn 을 찾지 못했다');
      final j = src.indexOf('\n  }\n', i);
      final block = src.substring(i, j);
      for (final m in RegExp(
        r'Cartoon\.(surface|onSurface)\(',
      ).allMatches(block)) {
        offenders.add('$fn 안  Cartoon.${m.group(1)}(');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: '테마가 정한 색을 팔레트에 또 통과시킨다:\n${offenders.join('\n')}',
    );
  });

  test('상품 카탈로그도 팔레트를 거치지 않는다', () {
    final src = File('lib/widgets/token_cosmetics.dart').readAsStringSync();
    for (final name in ['_bubbleStyles', '_roomHighlights']) {
      final i = src.indexOf('$name = {');
      expect(i, greaterThan(0), reason: '$name 을 찾지 못했다');
      final j = src.indexOf('\n};', i);
      final block = src.substring(i, j);
      expect(
        RegExp(r'Cartoon\.(surface|onSurface)\(').hasMatch(block),
        isFalse,
        reason: '$name 의 색이 테마를 따라간다 — 산 물건은 변하면 안 된다',
      );
    }
  });

  test('팔레트 변환이 겹쳐 있지 않다', () {
    // surface / onSurface 는 한 번만 거쳐야 한다. 두 번 통과하면 어두운
    // 한 벌에서 값이 밀린다 — onSurface 는 0.78 → 0.62 로 대비가 깎이고,
    // surface 는 0.20 → 0.30 으로 바탕이 들뜬다. 밝은 한 벌은 변환이
    // 그냥 통과하므로 겹쳐도 드러나지 않는다. 그래서 눈으로는 못 잡는다.
    final nested = <String>[];
    final pattern = RegExp(
      r'Cartoon\.(?:onSurface|surface)\(\s*Cartoon\.(?:onSurface|surface)\(',
    );
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final src = file.readAsStringSync();
      for (final m in pattern.allMatches(src)) {
        nested.add(
          '${file.path}:${src.substring(0, m.start).split('\n').length}',
        );
      }
    }
    expect(
      nested,
      isEmpty,
      reason: '팔레트 변환은 한 번만 거칠 것. 안쪽 호출만 남겨라:\n${nested.join('\n')}',
    );
  });
}
