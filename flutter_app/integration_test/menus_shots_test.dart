import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'shots_support.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('menu shots', (tester) async {
    final s = Shots(binding, tester);
    await s.boot();
    Future<void> open(String label) async {
      await s.waitFor(find.text(label));
      await tester.tapAt(tester.getCenter(find.text(label).first) - const Offset(0, 32));
      await s.wait(2.5);
    }
    Future<void> back() async {
      await tester.tap(find.byIcon(Icons.arrow_back_rounded).first);
      await s.wait(1.5);
    }
    Future<void> dismissCoach() async {
      for (final t in ['오늘의 출석', '알겠어요']) {
        final f = find.textContaining(t);
        if (f.evaluate().isNotEmpty) {
          await tester.tap(f.first, warnIfMissed: false);
          await s.wait(1.2);
        }
      }
      if (find.text('출석 체크').evaluate().isNotEmpty) {
        for (final ic in [Icons.close_rounded, Icons.close]) {
          final f = find.byIcon(ic);
          if (f.evaluate().isNotEmpty) {
            await tester.tap(f.first);
            break;
          }
        }
        await s.wait(1.2);
      }
    }

    await open('상점');
    await dismissCoach();
    await s.snap('40_shop');
    await back();

    await open('랭킹');
    await s.snap('41_ranking');
    await back();

    await open('미션');
    await dismissCoach();
    final pick = find.text('받기');
    for (var i = 0; i < 2 && pick.evaluate().isNotEmpty; i++) {
      await tester.tap(pick.first);
      await s.wait(1.5);
    }
    await s.snap('42_missions');
    await back();

    await open('내 프로필');
    await s.snap('43_profile');
    Navigator.of(s.ctx).maybePop();
    await s.wait(1.5);

    await open('친구');
    await s.snap('44_friends');
  });
}
