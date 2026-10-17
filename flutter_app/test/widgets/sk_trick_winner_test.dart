import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/models/sk_game_state.dart';

/// 무효 트릭에는 이긴 사람이 없다.
///
/// 서버는 무효일 때도 lastTrickWinner 를 채워 보낸다 — 거기 들어가는 건
/// "이긴 사람" 이 아니라 "다음 트릭을 시작할 사람" 이다(크라켄 규칙).
/// 그 둘을 같은 값으로 읽으면, 크라켄으로 무효가 된 트릭에서 승리 표식이
/// 뜬다. 화면은 lastTrickVoided 를 함께 봐야 한다.
///
/// 화면 위젯은 GameService 없이 띄울 수 없어서, 화면이 쓰는 판정식을
/// 그대로 옮겨 상태만으로 확인한다.
bool showsWinnerMark(SKGameStateData s, String playerId) =>
    !s.lastTrickVoided && s.lastTrickWinner == playerId;

SKGameStateData state({required bool voided, String winner = 'p1'}) =>
    SKGameStateData.fromJson({
      'phase': 'trick_end',
      'players': const [
        {'id': 'p1', 'name': '철수', 'position': 'player_1'},
        {'id': 'me', 'name': '나', 'position': 'self'},
      ],
      'lastTrickWinner': winner,
      'lastTrickVoided': voided,
    });

void main() {
  test('보통 트릭은 이긴 사람에게 표식', () {
    final s = state(voided: false);
    expect(showsWinnerMark(s, 'p1'), isTrue);
    expect(showsWinnerMark(s, 'me'), isFalse);
  });

  test('크라켄으로 무효가 되면 아무에게도 표식이 없다', () {
    // 무효여도 winnerId 는 채워져 온다(다음 선). 그걸 승자로 읽으면 안 된다.
    final s = state(voided: true);
    expect(s.lastTrickWinner, 'p1', reason: '다음 선은 여전히 들어온다');
    expect(showsWinnerMark(s, 'p1'), isFalse, reason: '무효 트릭에 승리 표식');
    expect(showsWinnerMark(s, 'me'), isFalse);
  });

  test('흰고래가 숫자 없이 무효로 만들어도 마찬가지', () {
    expect(showsWinnerMark(state(voided: true, winner: 'me'), 'me'), isFalse);
  });

  test('lastTrickVoided 가 없는 옛 서버 응답은 무효가 아니다', () {
    final s = SKGameStateData.fromJson({
      'phase': 'trick_end',
      'players': const [
        {'id': 'p1', 'name': '철수', 'position': 'player_1'},
      ],
      'lastTrickWinner': 'p1',
    });
    expect(s.lastTrickVoided, isFalse);
    expect(showsWinnerMark(s, 'p1'), isTrue);
  });
}
