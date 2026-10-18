import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 손패 창 아래 안전 영역이 잘려 보이지 않는지.
///
/// 창은 SafeArea 안에 그려지므로, 홈 바가 있는 기기에서는 창 아래 띠에
/// 배경 그라데이션이 그대로 비친다 — 창이 거기서 잘린 것처럼 읽힌다.
/// 스컬킹에서 먼저 고쳤고(SpectatorBottomFill), 티츄에는 빠져 있었다.
///
/// 띠와 창이 '같은 색' 이어야 한다는 것이 이 수정의 핵심이다. 두 곳에서
/// 색을 따로 계산하면 차례가 바뀔 때마다(내 차례 노랑 / 5초 이하 붉음 /
/// 평소 종이색) 이음새가 보인다. 그래서 한 함수로 모았고, 그게 유지되는지
/// 소스에서 확인한다 — 홈 바가 있는 기기를 테스트에서 띄울 수 없으므로
/// 위젯을 그려 보는 것으로는 잡히지 않는다.
void main() {
  const screens = {
    '티츄': 'lib/screens/game_screen.dart',
    '스컬킹': 'lib/screens/sk_game_screen.dart',
    '마이티': 'lib/screens/mighty_game_screen.dart',
    '러브레터': 'lib/screens/ll_game_screen.dart',
  };
  final src = {
    for (final e in screens.entries) e.key: File(e.value).readAsStringSync(),
  };

  // 네 게임이 모두 아래에 손패 창을 그린다. 한 곳만 빠지거나 조건이
  // 어긋난 채 남는 것이 이 문제의 반복 패턴이었다 — 마이티와 러브레터는
  // 띠를 '관전자에게만' 칠하고 있어서, 정작 대부분의 사람이 잘린 화면을
  // 봤다. 그래서 네 화면을 한 번에 본다.
  for (final name in screens.keys) {
    test('$name 화면이 안전 영역 띠를 채운다', () {
      expect(
        src[name]!.contains('SpectatorBottomFill'),
        isTrue,
        reason: '$name 화면에 띠가 없다 — 손패 창 아래가 잘려 보인다',
      );
    });

    test('$name 띠가 관전자에게만 칠해지지 않는다', () {
      // `when:` 안의 g.isSpectator 는 플레이어를 빼버린다는 뜻이다.
      final i = src[name]!.indexOf('SpectatorBottomFill');
      if (i < 0) return; // 위 테스트가 이미 실패한다
      final block = src[name]!.substring(i, i + 700);
      final when = block.substring(
        block.indexOf('when:'),
        block.indexOf('color:') > 0 ? block.indexOf('color:') : block.length,
      );
      expect(
        when.contains('isSpectator'),
        isFalse,
        reason: '$name 띠가 관전자 조건에 묶여 있다',
      );
    });
  }

  group('띠 색과 창 색이 갈라지지 않는다', () {
    // 창 색이 차례에 따라 바뀌는 화면(티츄·러브레터)은 띠도 같이 바뀌어야
    // 한다. 고정 색으로 채우면 차례마다 이음새가 보인다.
    for (final name in ['티츄', '러브레터']) {
      test('$name 은 색을 한 함수에서 가져온다', () {
        expect(
          src[name]!.contains('_bottomAreaColor('),
          isTrue,
          reason: '$name 의 색 계산이 한곳에 모여 있지 않다',
        );
        final uses = RegExp(
          r'_bottomAreaColor\(',
        ).allMatches(src[name]!).length;
        expect(
          uses,
          greaterThanOrEqualTo(3),
          reason: '선언 1 + 창 1 + 띠 1 이어야 한다 (실제 $uses)',
        );
      });
    }

    test('내 차례 색을 화면마다 따로 적지 않는다', () {
      // 전에는 네 게임이 각자 #FFF1B8 을 적어 두고 있었다. 한 곳만
      // 팔레트를 안 거치면 그 화면에서만 노란 바탕에 밝은 글자가 된다 —
      // 실제로 여섯 곳 중 세 곳이 그랬다. 지금은 공용 토큰 하나다.
      for (final name in ['티츄', '스컬킹', '마이티', '러브레터']) {
        for (final hex in ['0xFFFFF1B8', '0xFFFFC9C4']) {
          expect(
            src[name]!.contains(hex),
            isFalse,
            reason: '$name 이 $hex 를 직접 적는다 — Cartoon.myTurn 을 쓸 것',
          );
        }
      }
      expect(src['티츄']!.contains('Cartoon.myTurn'), isTrue);
    });
  });
}
