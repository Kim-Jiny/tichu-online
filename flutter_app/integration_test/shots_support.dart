import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:tichu_online/main.dart' as app;
import 'package:tichu_online/services/game_service.dart';

/// 스토어 스크린샷 촬영 도우미. 실제 앱을 띄워 두고 탭·대기·촬영만 한다.
class Shots {
  Shots(this.binding, this.tester);
  final IntegrationTestWidgetsFlutterBinding binding;
  final WidgetTester tester;
  bool _converted = false;

  /// 흐르는 애니메이션(반짝임 등)이 있어 pumpAndSettle 은 끝나지 않는다.
  Future<void> wait([double seconds = 1]) async {
    final end = DateTime.now().add(Duration(milliseconds: (seconds * 1000).round()));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<bool> waitFor(Finder f, {double timeout = 20}) async {
    final end = DateTime.now().add(Duration(milliseconds: (timeout * 1000).round()));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
      if (f.evaluate().isNotEmpty) return true;
    }
    return false;
  }

  Future<void> tapText(String text, {double timeout = 20, int index = 0}) async {
    final f = find.text(text);
    if (!await waitFor(f, timeout: timeout)) {
      throw 'text not found: $text';
    }
    await tester.tap(f.at(index));
    await wait(0.6);
  }

  /// 호스트의 watcher.js 가 그 순간의 시뮬레이터 화면을 simctl 로 찍는다(상태 표시줄 포함).
  Future<void> snap(String name, {double settle = 1.5}) async {
    await wait(settle);
    const dir = '/private/tmp/shots_req';
    final ack = File('$dir/$name.ack');
    if (ack.existsSync()) ack.deleteSync();
    File('$dir/$name.req').writeAsStringSync('1');
    final end = DateTime.now().add(const Duration(seconds: 20));
    while (!ack.existsSync() && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (!ack.existsSync()) throw 'screenshot ack timeout: $name';
  }

  BuildContext get ctx => tester.element(find.byType(Navigator).first);

  /// 약관 동의 → 로그인 → 로비까지. 로그인한 GameService 를 돌려준다.
  Future<GameService> boot() async {
    app.main();
    await wait(5);
    await tapText('이용약관에 동의합니다');
    await tapText('시작하기');
    await wait(2);
    await snap('00_login');
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'shotdemo');
    await tester.enterText(fields.at(1), 'shots1234!');
    FocusManager.instance.primaryFocus?.unfocus();
    await wait(1.2);
    await tapText('로그인');
    await wait(14);
    if (find.text('괜찮아요').evaluate().isNotEmpty) await tapText('괜찮아요');
    await wait(2);
    final coach = find.textContaining('미션을 선택');
    if (coach.evaluate().isNotEmpty) {
      await tester.tap(coach.first, warnIfMissed: false);
      await wait(1);
    }
    return Provider.of<GameService>(ctx, listen: false);
  }

  /// 조건이 될 때까지 0.5초마다 [tick] 을 돌린다. 끝나면 true.
  Future<bool> until(bool Function() done, {double timeout = 120, void Function()? tick}) async {
    final end = DateTime.now().add(Duration(milliseconds: (timeout * 1000).round()));
    while (DateTime.now().isBefore(end)) {
      if (done()) return true;
      tick?.call();
      await wait(0.5);
    }
    return done();
  }
}
