import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/models/mighty_game_state.dart';

/// 힘없는 조커(1트릭·막 트릭)로 리드한 트릭의 리드 무늬.
///
/// 서버는 그 조커의 부른 무늬를 받지 않고, 두 번째로 나온 카드가 리드 무늬를
/// 정한다(MightyGame._leadSuitOf). 화면도 같은 규칙으로 읽어야 가운데 트릭
/// 박스의 무늬가 비어 보이지 않는다.
///
/// 화면이 쓰는 그 계산(MightyGameStateData.leadSuit)을 그대로 부른다 —
/// 규칙을 여기 다시 적으면 코드가 어긋나도 초록으로 남는다.

MightyGameStateData stateWith(List<String> trick, {String? declared}) {
  return MightyGameStateData(
    currentTrick: trick
        .map((c) => MightyTrickPlay(playerId: 'p', playerName: 'p', cardId: c))
        .toList(),
    jokerSuitDeclared: declared,
  );
}

String? leadSuitOf(List<String> trick, String? declared) =>
    stateWith(trick, declared: declared).leadSuit;

void main() {
  test('보통 카드로 리드하면 그 무늬', () {
    expect(leadSuitOf(['mighty_club_5'], null), 'club');
  });

  test('조커가 무늬를 불렀으면 부른 무늬', () {
    expect(leadSuitOf(['mighty_joker'], 'spade'), 'spade');
  });

  test('힘없는 조커는 두 번째 카드가 리드 무늬', () {
    expect(
      leadSuitOf(['mighty_joker', 'mighty_club_5'], null),
      'club',
    );
  });

  test('두 번째 카드가 아직 없으면 정해진 무늬가 없다', () {
    // 이 시점의 두 번째 사람은 아무 카드나 낼 수 있다.
    expect(leadSuitOf(['mighty_joker'], null), isNull);
  });

  test('부른 무늬가 있어도 두 번째 카드가 이기지 않는다', () {
    // 중간 트릭: 부른 무늬가 그대로 남는다.
    expect(
      leadSuitOf(['mighty_joker', 'mighty_club_5'], 'spade'),
      'spade',
    );
  });
}
