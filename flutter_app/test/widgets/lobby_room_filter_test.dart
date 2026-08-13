import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/screens/lobby_screen.dart' show filterRoomsByGame;

/// Which rooms the lobby list shows for a given filter.
///
/// The chips used to be hide-toggles: tapping the one labelled 티츄 removed
/// Tichu from the list, and seeing one game alone took three taps on the other
/// three. That is backwards from what a coloured chip with a game's name on it
/// reads as, and it is why players asked for an "전체" button that was, in
/// effect, already the default.
///
/// The rule now is the obvious one — null shows everything, a game shows only
/// that game — and this pins it so the sense cannot quietly invert again.

class _R {
  final String gameType;
  const _R(this.gameType);
}

void main() {
  const rooms = [
    _R('tichu'),
    _R('mighty'),
    _R('tichu'),
    _R('love_letter'),
  ];

  test('no filter shows every room', () {
    expect(filterRoomsByGame(rooms, null, (r) => r.gameType), hasLength(4));
  });

  test('picking a game shows that game, not everything except it', () {
    final out = filterRoomsByGame(rooms, 'tichu', (r) => r.gameType);
    expect(out, hasLength(2));
    expect(out.every((r) => r.gameType == 'tichu'), isTrue,
        reason: 'the old behaviour returned exactly the other two');
  });

  test('a game nobody is playing shows nothing, not everything', () {
    // The empty result is what raises "이 게임의 방이 없어요". Falling back to
    // the full list instead would be worse: the chip would look selected while
    // showing other games' rooms.
    expect(filterRoomsByGame(rooms, 'skull_king', (r) => r.gameType), isEmpty);
  });

  test('the original list is not modified', () {
    filterRoomsByGame(rooms, 'mighty', (r) => r.gameType);
    expect(rooms, hasLength(4));
  });
}
