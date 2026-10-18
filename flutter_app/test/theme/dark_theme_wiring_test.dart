import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 테마가 바뀔 때 색 한 벌도 같이 바뀌는지.
///
/// 테마가 바뀌는 곳이 네 군데다(장착 응답, 해제, 상점 결과, 로그아웃).
/// 각자 팔레트를 바꾸게 두면 한 곳만 빠져도 배경은 어두운데 글자는
/// 어두운 상태가 된다 — 그 화면만 안 보인다.
///
/// 그래서 대입을 setter 한 곳으로 모았다. 그 구조가 유지되는지 본다.
/// (GameService 는 테스트에서 만들 수 없다 — Firebase 가 필요하다.)
void main() {
  final src = File('lib/services/game_service.dart').readAsStringSync();

  test('테마 대입이 setter 를 거친다', () {
    expect(
      src.contains('set equippedTheme(String? key)'),
      isTrue,
      reason: '대입이 흩어져 있으면 한 곳만 빠져도 색이 어긋난다',
    );
    expect(
      src.contains('Cartoon.usePalette('),
      isTrue,
      reason: '테마가 바뀌어도 색 한 벌을 갈아 끼우지 않는다',
    );
  });

  test('필드에 직접 쓰는 곳이 남아 있지 않다', () {
    // _equippedTheme 에 직접 쓰면 setter 를 건너뛴다.
    final direct = RegExp(r'_equippedTheme\s*=').allMatches(src).length;
    expect(direct, 1, reason: 'setter 안의 한 번 말고 $direct 곳에서 직접 쓴다');
  });

  test('어두운 테마 목록이 이름 규칙이 아니라 목록이다', () {
    // 'theme_dark*' 같은 규칙으로 하면 'theme_darkwood' 처럼 의도하지
    // 않은 이름이 조용히 끌려 들어간다.
    expect(src.contains('darkThemeKeys'), isTrue);
    expect(
      src.contains("startsWith('theme_dark"),
      isFalse,
      reason: '이름 규칙으로 판정하면 의도 밖의 테마가 어두워진다',
    );
  });

  test('그 테마가 실제로 상점에 있다', () {
    // 앱이 아는 키와 서버가 파는 키가 어긋나면, 사 놓고 색이 안 바뀐다.
    final db = File('../server/db/database.js').readAsStringSync();
    final keys = RegExp(r"darkThemeKeys = \{([^}]*)\}").firstMatch(src);
    expect(keys, isNotNull);
    for (final m in RegExp(r"'([^']+)'").allMatches(keys!.group(1)!)) {
      final key = m.group(1)!;
      expect(db.contains("'$key'"), isTrue, reason: '$key 가 상점에 없다');
      expect(
        src.contains("case '$key':"),
        isTrue,
        reason: '$key 의 배경·카드 뒷면 색이 없다',
      );
    }
  });
}
