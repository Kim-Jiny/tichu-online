import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/utils/spectator_line.dart';

/// The spectator line above the chat, when a room gets popular.
///
/// The failure this prevents is not cosmetic: the strip sits inside the chat
/// panel, so a line that grows with the audience takes the chat with it. Two
/// dozen watchers must cost the same vertical space as two.

void main() {
  test('everyone fits when the names are short', () {
    final line = spectatorLine(['가', '나', '다']);
    expect(line.shown, ['가', '나', '다']);
    expect(line.hidden, 0);
  });

  test('a crowd is cut, and the remainder is counted', () {
    final line = spectatorLine(List.generate(30, (i) => '관전자$i'));
    expect(line.shown.length, lessThan(10));
    expect(line.hidden, 30 - line.shown.length);
    // Whatever the split, the drawn text stays within a line or two.
    final width = line.shown.fold<int>(0, (n, s) => n + s.length + 2);
    expect(width, lessThanOrEqualTo(34 + 12));
  });

  test('a name that busts the budget on its own still shows', () {
    // "외 4명" with no name at all would say somebody is watching without
    // saying who — worse than one name and a count.
    final huge = '아' * 40;
    final line = spectatorLine([huge, '나', '다', '라']);
    expect(line.shown, [huge]);
    expect(line.hidden, 3);
  });

  test('a long first name still leaves room for short ones', () {
    final line = spectatorLine(['아주아주아주긴닉네임입니다요', '나', '다', '라']);
    expect(line.shown.length, 4);
    expect(line.hidden, 0);
  });

  test('blank names are dropped rather than drawn as empty commas', () {
    final line = spectatorLine(['가', '', '   ', '나']);
    expect(line.shown, ['가', '나']);
    expect(line.hidden, 0);
  });

  test('nobody watching', () {
    expect(spectatorLine(const []).shown, isEmpty);
    expect(spectatorLine(const []).hidden, 0);
    expect(spectatorLine(const ['', '  ']).hidden, 0);
  });

  test('the cut is stable — the same list gives the same line', () {
    final names = List.generate(12, (i) => '보는사람$i');
    expect(spectatorLine(names).shown, spectatorLine(names).shown);
  });
}
