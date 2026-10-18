import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/theme/cartoon.dart';

/// 본문을 `Cartoon.ink` 의 알파로 흐리게 깔아 쓰는 자리들이, 두 한 벌
/// 모두에서 본문 대비 기준(WCAG AA, 4.5:1)을 넘는지 본다.
///
/// 알파는 색이 아니라 섞임이다. 같은 0.6 이 밝은 바탕에서는 3.85, 어두운
/// 바탕에서는 5.40 이 된다 — 한쪽만 보고 정하면 반대쪽이 무너진다.
///
/// 0.5 미만은 보지 않는다. 입력칸 안내문과 비활성 상태라 흐린 것이 뜻이고,
/// 진하게 만들면 실제 입력값과 구분되지 않는다.
void main() {
  const aa = 4.5;

  test('흐린 본문 글자가 두 한 벌에서 모두 읽힌다', () {
    final alphas = _textAlphasInSource();
    expect(alphas, isNotEmpty, reason: '본문 알파를 하나도 못 찾았다 — 검사가 썩었다');

    final failures = <String>[];
    for (final entry in alphas.entries) {
      for (final palette in [cartoonLight, cartoonDark]) {
        final behind = palette.paper;
        final blended = _composite(palette.ink, behind, entry.key);
        final got = _contrast(blended, behind);
        if (got < aa) {
          final label = palette.dark ? '어두운' : '밝은';
          failures.add(
            '알파 ${entry.key} → $label 한 벌에서 ${got.toStringAsFixed(2)}:1 '
            '(${entry.value.first} 외 ${entry.value.length - 1}곳)',
          );
        }
      }
    }
    expect(
      failures,
      isEmpty,
      reason: '본문 글자가 $aa:1 에 못 미친다. 알파를 올릴 것:\n${failures.join('\n')}',
    );
  });

  test('밝은 한 벌이 어두운 쪽보다 흐리다는 점을 잊지 않는다', () {
    // 처음 이 문제를 어두운 테마 탓으로 봤지만, 재 보니 밝은 쪽이 더
    // 흐렸다. 같은 알파에서 밝은 한 벌의 대비가 늘 더 낮다 — 밝은 쪽을
    // 기준으로 알파를 정해야 양쪽이 산다.
    for (final alpha in [0.5, 0.6, 0.7, 0.78]) {
      final light = _contrast(
        _composite(cartoonLight.ink, cartoonLight.paper, alpha),
        cartoonLight.paper,
      );
      final dark = _contrast(
        _composite(cartoonDark.ink, cartoonDark.paper, alpha),
        cartoonDark.paper,
      );
      expect(light, lessThan(dark), reason: '알파 $alpha');
    }
  });
}

/// `Cartoon.text(...)` / `Cartoon.userText(...)` / `TextStyle(...)` 안에
/// 쓰인 `Cartoon.ink` 알파들. 테두리·구분선·아이콘·바탕의 알파는 글자가
/// 아니므로 세지 않는다.
Map<double, List<String>> _textAlphasInSource() {
  const bodyFloor = 0.5; // 아래는 안내문·비활성이라 흐린 것이 뜻이다
  const textOwners = {'userText', 'text', 'TextStyle'};
  // alpha 가 다음 줄로 넘어간 형태도 본다 — 한 줄만 보다 7곳을 놓쳤다.
  final pattern = RegExp(
    r'Cartoon\.ink\.withValues\(\s*alpha:\s*(0\.\d+),?\s*\)',
    dotAll: true,
  );
  final found = <double, List<String>>{};

  for (final file in Directory('lib').listSync(recursive: true)) {
    if (file is! File || !file.path.endsWith('.dart')) continue;
    final src = file.readAsStringSync();
    for (final m in pattern.allMatches(src)) {
      final alpha = double.parse(m.group(1)!);
      if (alpha < bodyFloor) continue;
      if (!textOwners.contains(_enclosingCall(src, m.start))) continue;
      final line = src.substring(0, m.start).split('\n').length;
      found.putIfAbsent(alpha, () => []).add('${file.path}:$line');
    }
  }
  return found;
}

/// `index` 를 감싸는 가장 가까운 열린 괄호의 호출 이름.
String _enclosingCall(String src, int index) {
  var depth = 0;
  for (var i = index - 1; i >= 0; i--) {
    final ch = src[i];
    if (ch == ')') {
      depth++;
    } else if (ch == '(') {
      if (depth == 0) {
        final name = RegExp(
          r'([A-Za-z_][\w.]*)\s*$',
        ).firstMatch(src.substring(0, i));
        return (name?.group(1) ?? '?').split('.').last;
      }
      depth--;
    }
  }
  return '?';
}

/// 알파를 바탕에 섞어 눈에 닿는 실제 색을 낸다.
Color _composite(Color fg, Color bg, double alpha) => Color.fromARGB(
  255,
  (fg.r * 255 * alpha + bg.r * 255 * (1 - alpha)).round(),
  (fg.g * 255 * alpha + bg.g * 255 * (1 - alpha)).round(),
  (fg.b * 255 * alpha + bg.b * 255 * (1 - alpha)).round(),
);

double _contrast(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  final hi = x > y ? x : y;
  final lo = x > y ? y : x;
  return (hi + 0.05) / (lo + 0.05);
}
