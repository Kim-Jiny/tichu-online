import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/l10n/app_localizations.dart';
import 'package:tichu_online/widgets/ad_reward_dialog.dart';

void main() {
  late ValueNotifier<bool> ready;
  late int watched;

  setUp(() {
    ready = ValueNotifier(true);
    watched = 0;
  });
  tearDown(() => ready.dispose());

  Future<void> open(WidgetTester t, Future<int?> Function() load) async {
    await t.pumpWidget(
      MaterialApp(
        locale: const Locale('ko'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AdRewardDialog(
                  loadUsed: load,
                  adReady: ready,
                  isAdLoading: () => false,
                  maxRewards: 5,
                  onWatch: () => watched++,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
  }

  Finder watchButton() => find.textContaining('50골드 받기');

  testWidgets('응답이 3초 넘게 늦어도 시청할 수 없다', (t) async {
    final response = Completer<int?>();
    await open(t, () => response.future);
    await t.pump(const Duration(seconds: 4));
    expect(watchButton(), findsNothing);
    expect(watched, 0);
    response.complete(5);
    await t.pumpAndSettle();
    expect(watchButton(), findsNothing);
    expect(find.text('다시 시도'), findsNothing);
  });

  testWidgets('조회 실패 후 재조회에 성공해야 시청할 수 있다', (t) async {
    var calls = 0;
    await open(t, () async => ++calls == 1 ? null : 2);
    await t.pumpAndSettle();
    expect(watchButton(), findsNothing);
    await t.tap(find.text('다시 시도'));
    await t.pumpAndSettle();
    expect(calls, 2);
    expect(watchButton(), findsNWidgets(2));
    await t.tap(watchButton().last);
    await t.pumpAndSettle();
    expect(watched, 1);
  });

  testWidgets('시간 초과는 이전 횟수로 시청을 허용하지 않는다', (t) async {
    final response = Completer<int?>();
    await open(
      t,
      () => response.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () => null,
      ),
    );
    await t.pump(const Duration(seconds: 9));
    await t.pumpAndSettle();
    expect(watchButton(), findsNothing);
    expect(find.text('다시 시도'), findsOneWidget);
    expect(watched, 0);
    response.complete(0);
    await t.pumpAndSettle();
    expect(watchButton(), findsNothing);
  });

  testWidgets('창을 닫은 뒤 늦게 응답해도 예외가 없다', (t) async {
    final response = Completer<int?>();
    await open(t, () => response.future);
    await t.tap(find.text('닫기'));
    await t.pumpAndSettle();
    response.complete(0);
    await t.pump();
    expect(t.takeException(), isNull);
    expect(watched, 0);
  });
}
