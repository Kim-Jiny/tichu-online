import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 강조색 바탕 위에는 ink 를 그대로 쓰면 안 된다.
///
/// 강조색(노랑·주황·초록·빨강·파랑)은 뜻을 가진 색이라 팔레트를 따라가지
/// 않는다. 그 위의 글자만 따라가면 어두운 테마에서 노란 바탕에 밝은
/// 글자가 된다 — 차례 표시, 티츄 성공 연출, 1등 뱃지, 라운드 결과가
/// 전부 그랬다.
///
/// 바탕에서 글자색을 끌어내야 한다(Cartoon.inkOn). 이 검사는 그 규칙이
/// 지켜지는지 소스에서 본다 — 어떤 색이 어떤 바탕 위에 놓이는지는
/// 위젯을 띄워서는 알 수 없다.
void main() {
  const accents = ['yellow', 'orange', 'orangeDeep', 'green', 'red', 'blue'];

  test('강조색 바탕 바로 아래에 Cartoon.ink 글자가 없다', () {
    final offenders = <String>[];
    for (final f
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      if (f.path.endsWith('theme/cartoon.dart')) continue;
      final lines = f.readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        final m = RegExp(
          'color:\\s*Cartoon\\.(${accents.join('|')})\\s*,',
        ).firstMatch(lines[i]);
        if (m == null) continue;
        // 바탕으로 쓰인 자리만 본다.
        final ctx = lines.sublist((i - 5).clamp(0, i), i + 1).join('\n');
        if (!RegExp('BoxDecoration|ColoredBox').hasMatch(ctx)) continue;
        for (var k = i + 1; k < lines.length && k < i + 15; k++) {
          if (RegExp('BoxDecoration|ColoredBox').hasMatch(lines[k])) break;
          if (RegExp(r'color:\s*Cartoon\.ink\b').hasMatch(lines[k])) {
            offenders.add('${f.path}:${k + 1}  (바탕 ${m.group(1)}, ink 명시)');
          }
          // 색을 안 적으면 기본값이 ink 라 같은 문제가 된다. 명시된
          // 것만 보던 때 스컬킹 트릭 승자 알약이 빠져나갔다.
          if (RegExp(
            r'Cartoon\.(text|userText)\(size: [0-9.]+\)',
          ).hasMatch(lines[k])) {
            offenders.add('${f.path}:${k + 1}  (바탕 ${m.group(1)}, 색 없음)');
          }
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          '강조색 바탕 위의 글자는 Cartoon.inkOn(바탕) 으로:\n'
          '${offenders.join('\n')}',
    );
  });
}
