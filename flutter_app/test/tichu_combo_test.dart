import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/utils/tichu_combo.dart';

void main() {
  bool lead(List<String> c) => tichuCanPlay(c, myTurn: true);
  bool onto(List<String> c, String t, int len, double v, {bool turn = true}) =>
      tichuCanPlay(c, myTurn: turn, trickType: t, trickLength: len, trickValue: v);

  test('선공 조합', () {
    expect(lead(['spade_5']), true);
    expect(lead(['spade_5', 'heart_5']), true);
    expect(lead(['spade_5', 'heart_6']), false);
    expect(lead(['special_dog']), true);
    expect(lead(['spade_5', 'special_phoenix']), true);
    expect(lead(['spade_3', 'heart_4', 'club_5', 'spade_6', 'heart_7']), true);
    expect(lead(['spade_3', 'heart_4', 'club_5', 'spade_6', 'heart_8']), false);
    expect(lead(['spade_3', 'heart_3', 'club_4', 'spade_4']), true);
    expect(lead(['spade_3', 'heart_3', 'club_3', 'spade_9', 'heart_9']), true);
  });

  test('앞 패 이기기', () {
    expect(onto(['spade_7'], 'single', 1, 6), true);
    expect(onto(['spade_6'], 'single', 1, 6), false);
    expect(onto(['special_dog'], 'single', 1, 6), false);
    expect(onto(['special_phoenix'], 'single', 1, 14), true);
    expect(onto(['special_phoenix'], 'single', 1, 15), false);
    expect(onto(['spade_7', 'heart_7'], 'single', 1, 6), false);
  });

  test('폭탄', () {
    final bomb = ['spade_9', 'heart_9', 'club_9', 'diamond_9'];
    expect(onto(bomb, 'pair', 2, 14), true);
    expect(onto(bomb, 'pair', 2, 14, turn: false), true);
    expect(onto(['spade_5'], 'single', 1, 3, turn: false), false);
    expect(tichuCanPlay(bomb, myTurn: false), false);
  });
}
