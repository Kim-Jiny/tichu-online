import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/l10n/app_localizations_ko.dart';
import 'package:tichu_online/models/tichu_fx_detector.dart';
import 'package:tichu_online/widgets/tichu_effects.dart';
import 'package:tichu_online/widgets/tichu_fx_events.dart';

void main() {
  test('1~3등만 띄우고 4등은 띄우지 않는다', () {
    var seq = 0;
    final events = buildTichuFxEvents(
      [
        for (var r = 1; r <= 4; r++)
          TichuFxSignal(TichuFxKind.finished, '홍길동', rank: r),
      ],
      L10nKo(),
      () => ++seq,
    );
    expect(events.length, 3);
    expect(events.map((e) => e.title), everyElement(isNot(contains('4등'))));
    expect(events.first.title, '홍길동 1등!');
  });
}
