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
      for (final t in [T.of('checkinCoach'), T.of('gotit')]) {
        final f = find.textContaining(t);
        if (f.evaluate().isNotEmpty) {
          await tester.tap(f.first, warnIfMissed: false);
          await s.wait(1.2);
        }
      }
      if (find.text(T.of('checkin')).evaluate().isNotEmpty) {
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

    await open(T.of('shop'));
    await dismissCoach();
    await s.snap('40_shop');
    await back();

    await open(T.of('ranking'));
    await s.snap('41_ranking');
    await back();

    await open(T.of('missions'));
    await dismissCoach();
    final pick = find.text(T.of('pick'));
    for (var i = 0; i < 2 && pick.evaluate().isNotEmpty; i++) {
      await tester.tap(pick.first);
      await s.wait(1.5);
    }
    await s.snap('42_missions');
    await back();

    await open(T.of('profile'));
    await s.snap('43_profile');
    Navigator.of(s.ctx).maybePop();
    await s.wait(1.5);

    await open(T.of('friends'));
    await s.snap('44_friends');
  });
}
