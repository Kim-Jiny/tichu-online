import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 색을 지정하지 않은 `TextStyle` 은 주변 Material 기본값(검정)을 물려받는다.
/// 어두운 한 벌에서는 어두운 바탕에 검정 글자가 되어 읽을 수 없다.
///
/// 색이 없어도 괜찮은 두 경우만 빠져나간다 —
///  * 이모지만 담은 글자: 글리프 자체가 색을 들고 있다.
///  * 버튼 라벨: 버튼의 `foregroundColor` 가 색을 공급한다.
void main() {
  test('색 없는 TextStyle 이 남아 있지 않다', () {
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final src = file.readAsStringSync();
      for (final m in RegExp(r'\bTextStyle\(').allMatches(src)) {
        final body = _balanced(src, m.end);
        if (body == null) continue;
        if (body.contains('color') || body.contains('inherit')) continue;

        final line = src.substring(0, m.start).split('\n').length;
        final before = src.substring(
          (m.start - 500).clamp(0, m.start),
          m.start,
        );
        // 버튼이 foregroundColor 로 글자색을 공급하는 자리.
        final window =
            before + src.substring(m.end, (m.end + 500).clamp(0, src.length));
        if (window.contains('foregroundColor:')) continue;
        if (_emojiOnly(before)) continue;
        offenders.add('${file.path}:$line');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          '색이 없으면 Material 기본 검정을 물려받아 어두운 한 벌에서 사라진다. '
          'Cartoon.ink 나 바탕에서 끌어낸 Cartoon.inkOn(...) 을 지정할 것:\n'
          '${offenders.join('\n')}',
    );
  });
  test('입력칸이 글자색 없이 놓여 있지 않다', () {
    // TextField 에 style 이 아예 없으면 테마 기본 글자색을 물려받아
    // 어두운 한 벌에서 어두운 바탕에 어두운 글자가 된다. 생성자가
    // 없으니 위 검사에는 걸리지 않는다 — 방 만들기의 시간 제한 칸이
    // 그렇게 빠져나가 입력값만 안 보였다.
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final src = file.readAsStringSync();
      for (final m in RegExp(
        r'\b(TextField|TextFormField)\(',
      ).allMatches(src)) {
        final body = _balanced(src, m.end);
        if (body == null || _hasTopLevelStyle(body)) continue;
        offenders.add(
          '${file.path}:${src.substring(0, m.start).split('\n').length}',
        );
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          '입력칸에 style 을 줄 것. 사용자가 친 글자는 Cartoon.userText:\n'
          '${offenders.join('\n')}',
    );
  });
}

/// `TextStyle(` 여는 괄호 다음부터 짝이 맞는 닫는 괄호까지.
String? _balanced(String src, int open) {
  var depth = 1;
  for (var i = open; i < src.length; i++) {
    if (src[i] == '(') depth++;
    if (src[i] == ')') depth--;
    if (depth == 0) return src.substring(open, i);
  }
  return null;
}

/// 바로 앞의 `Text('...'` 가 이모지(또는 \u{...} 탈출)만 담고 있는지.
bool _emojiOnly(String before) {
  final m = RegExp(
    '''Text\\(\\s*['"]([^'"]*)['"]\\s*,\\s*style:\\s*(const\\s+)?\$''',
  ).firstMatch(before);
  if (m == null) return false;
  final text = m.group(1)!;
  if (text.contains(r'\u{')) return true;
  return text.runes.every((r) => r > 0x2000);
}

/// 중첩 호출 안의 `style:` 은 이 입력칸의 것이 아니다 — 깊이 0 만 본다.
bool _hasTopLevelStyle(String body) {
  var depth = 0;
  for (var i = 0; i < body.length; i++) {
    final c = body[i];
    if (c == '(') {
      depth++;
    } else if (c == ')') {
      depth--;
    } else if (depth == 0 && body.startsWith('style:', i)) {
      return true;
    }
  }
  return false;
}
