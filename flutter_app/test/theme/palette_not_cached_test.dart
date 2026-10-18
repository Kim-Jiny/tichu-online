import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/theme/cartoon.dart';
import 'package:tichu_online/utils/banner_ink.dart';

/// 팔레트에서 계산한 색을 변수에 담아 두면 한 번만 계산되고 굳는다.
///
/// Dart 의 `static final` 과 최상위 변수는 처음 읽힐 때 한 번 계산된다.
/// 그래서 밝은 한 벌에서 공지를 한 번 읽고 테마를 바꾸면, 어두운 글자가
/// 그대로 남는다. 반대로 어두운 한 벌에서 먼저 계산되면 밝은 배너 위에
/// 밝은 글자가 올라간다. 어느 쪽이든 '무엇을 먼저 봤는가' 가 색을
/// 정하게 된다 — 그래서 눈으로는 재현이 들쭉날쭉하다.
///
/// 팔레트를 쓰는 값은 getter 여야 한다.
void main() {
  tearDown(() => Cartoon.usePalette(cartoonLight));

  test('팔레트 값을 변수에 굳혀 두지 않는다', () {
    final offenders = <String>[];
    final decl = RegExp(
      r'^(?:[ \t]*static[ \t]+final\b'
      r'|(?:final[ \t]+)?(?:Color|TextStyle|LinearGradient|BoxDecoration)[ \t]+\w+[ \t]*=)',
      multiLine: true,
    );
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final src = file.readAsStringSync();
      for (final m in decl.allMatches(src)) {
        final body = _statement(src, m.end);
        if (!body.contains('Cartoon.')) continue;
        offenders.add(
          '${file.path}:${src.substring(0, m.start).split('\n').length}',
        );
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          '팔레트를 쓰는 값은 getter 로 둘 것 — final 은 처음 계산된 색이 굳는다:\n'
          '${offenders.join('\n')}',
    );
  });

  test('밝은 배너 위 글자는 한 벌이 바뀌어도 어둡다', () {
    // 배너는 산 물건이라 어느 한 벌에서나 제 색 그대로다. 밝은 배너
    // 위의 글자가 팔레트를 따라 밝아지면 읽히지 않는다.
    const bright = LinearGradient(
      colors: [Color(0xFFFFE0B2), Color(0xFFFFF3E0)],
    );
    for (final palette in [cartoonLight, cartoonDark]) {
      Cartoon.usePalette(palette);
      final ink = profileBannerInk(bright, null);
      final onIt = _contrast(ink, bright.colors.first);
      expect(
        onIt,
        greaterThan(4.5),
        reason:
            '${palette.dark ? "어두운" : "밝은"} 한 벌에서 ${onIt.toStringAsFixed(2)}:1',
      );
    }
  });
}

/// `=` 뒤부터 괄호 밖의 첫 `;` 까지.
String _statement(String src, int from) {
  var depth = 0;
  for (var i = from; i < src.length; i++) {
    final c = src[i];
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') depth--;
    if (c == ';' && depth == 0) return src.substring(from, i);
  }
  return src.substring(from);
}

double _contrast(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  final hi = x > y ? x : y;
  final lo = x > y ? y : x;
  return (hi + 0.05) / (lo + 0.05);
}
