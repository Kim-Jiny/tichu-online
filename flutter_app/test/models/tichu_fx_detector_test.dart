import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/models/player.dart';
import 'package:tichu_online/models/tichu_fx_detector.dart';
import 'package:tichu_online/widgets/tichu_effects.dart';

Player p(
  String id,
  String position, {
  bool small = false,
  bool large = false,
  int finish = 0,
}) => Player(
  id: id,
  name: id,
  position: position,
  hasSmallTichu: small,
  hasLargeTichu: large,
  finishPosition: finish,
);

// self/partner = A, left/right = B
String teamOf(Player x) =>
    (x.position == 'self' || x.position == 'partner') ? 'A' : 'B';

List<Player> table({
  bool smallSelf = false,
  bool largeSelf = false,
  bool smallLeft = false,
  int self = 0,
  int partner = 0,
  int left = 0,
  int right = 0,
}) => [
  p('me', 'self', small: smallSelf, large: largeSelf, finish: self),
  p('pa', 'partner', finish: partner),
  p('le', 'left', small: smallLeft, finish: left),
  p('ri', 'right', finish: right),
];

List<TichuFxKind> kinds(List<TichuFxSignal> s) => s.map((e) => e.kind).toList();

void main() {
  test('처음 받은 상태는 기준일 뿐 연출을 내지 않는다 (재접속·입장)', () {
    final d = TichuFxDetector();
    expect(d.update(table(smallSelf: true, self: 1), teamOf), isEmpty);
  });

  test('스몰/라지 선언이 켜지는 순간 한 번만', () {
    final d = TichuFxDetector()..update(table(), teamOf);
    expect(kinds(d.update(table(smallSelf: true), teamOf)), [
      TichuFxKind.declareSmall,
    ]);
    // 같은 상태가 다시 와도 또 내지 않는다
    expect(d.update(table(smallSelf: true), teamOf), isEmpty);
  });

  test('라지 선언은 라지로', () {
    final d = TichuFxDetector()..update(table(), teamOf);
    final out = d.update(table(largeSelf: true), teamOf);
    expect(kinds(out), [TichuFxKind.declareLarge]);
    expect(out.first.large, isTrue);
  });

  test('선언한 사람이 1등이면 성공, 패 털기와 함께', () {
    final d = TichuFxDetector()..update(table(smallSelf: true), teamOf);
    final out = d.update(table(smallSelf: true, self: 1), teamOf);
    expect(kinds(out), [TichuFxKind.finished, TichuFxKind.tichuSuccess]);
    expect(out.first.rank, 1);
  });

  test('선언했는데 다른 사람이 먼저 털면 실패', () {
    final d = TichuFxDetector()..update(table(smallSelf: true), teamOf);
    final out = d.update(table(smallSelf: true, right: 1), teamOf);
    expect(kinds(out), [TichuFxKind.finished, TichuFxKind.tichuFail]);
    expect(out.last.name, 'me');
  });

  test('파트너가 먼저 털어도 본인 선언은 실패', () {
    final d = TichuFxDetector()..update(table(smallSelf: true), teamOf);
    final out = d.update(table(smallSelf: true, partner: 1), teamOf);
    expect(out.last.kind, TichuFxKind.tichuFail);
  });

  test('티츄 선언자가 없으면 결과 연출도 없다', () {
    final d = TichuFxDetector()..update(table(), teamOf);
    expect(kinds(d.update(table(left: 1), teamOf)), [TichuFxKind.finished]);
  });

  test('같은 팀이 1·2등이면 두 번째는 원투', () {
    final d = TichuFxDetector()..update(table(self: 1), teamOf);
    final out = d.update(table(self: 1, partner: 2), teamOf);
    expect(kinds(out), [TichuFxKind.oneTwo]);
  });

  test('다른 팀이 2등이면 그냥 패 털기', () {
    final d = TichuFxDetector()..update(table(self: 1), teamOf);
    final out = d.update(table(self: 1, left: 2), teamOf);
    expect(kinds(out), [TichuFxKind.finished]);
    expect(out.first.rank, 2);
  });

  test('새 판에서 순위가 0으로 돌아가는 건 연출이 아니다', () {
    final d = TichuFxDetector()..update(table(self: 1, partner: 2), teamOf);
    expect(d.update(table(), teamOf), isEmpty);
  });

  test('reset 후 첫 상태는 다시 기준이 된다', () {
    final d = TichuFxDetector()..update(table(), teamOf);
    d.reset();
    expect(d.update(table(self: 1), teamOf), isEmpty);
  });

  group('spectatorFxPlayers', () {
    // 서버 getStateForSpectator 와 같은 모양: position 이 숫자다.
    Map<String, dynamic> raw(
      String id,
      String team, {
      bool small = false,
      int finish = 0,
    }) => {
      'id': id,
      'name': id,
      'position': 0,
      'cards': <String>[],
      'hasSmallTichu': small,
      'hasLargeTichu': false,
      'finishPosition': finish,
      'team': team,
    };

    test('숫자 position 이어도 변환되고 팀을 찾는다', () {
      final fx = spectatorFxPlayers([raw('a', 'A'), raw('b', 'B')]);
      expect(fx.players.length, 2);
      expect(fx.teamOf(fx.players[0]), 'A');
      expect(fx.teamOf(fx.players[1]), 'B');
    });

    test('관전 상태로도 원투와 티츄 성공을 잡는다', () {
      final d = TichuFxDetector();
      final before = spectatorFxPlayers([
        raw('a', 'A', small: true),
        raw('b', 'B'),
        raw('c', 'A'),
        raw('d', 'B'),
      ]);
      d.update(before.players, before.teamOf);

      final first = spectatorFxPlayers([
        raw('a', 'A', small: true, finish: 1),
        raw('b', 'B'),
        raw('c', 'A'),
        raw('d', 'B'),
      ]);
      expect(kinds(d.update(first.players, first.teamOf)), [
        TichuFxKind.finished,
        TichuFxKind.tichuSuccess,
      ]);

      final second = spectatorFxPlayers([
        raw('a', 'A', small: true, finish: 1),
        raw('b', 'B'),
        raw('c', 'A', finish: 2),
        raw('d', 'B'),
      ]);
      expect(kinds(d.update(second.players, second.teamOf)), [
        TichuFxKind.oneTwo,
      ]);
    });
  });
}
