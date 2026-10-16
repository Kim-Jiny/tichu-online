import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tichu_online/l10n/app_localizations.dart';
import 'package:tichu_online/services/game_service.dart';
import 'package:tichu_online/widgets/coupon_redeem.dart';

class _FakeGame extends ChangeNotifier implements GameService {
  final sent = <String>[];
  CouponOutcome outcome = const CouponOutcome(
    success: true,
    rewardType: 'gold',
    rewardGold: 500,
  );

  @override
  Future<CouponOutcome> redeemCoupon(String code) async {
    sent.add(code);
    return outcome;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<_FakeGame> openDialog(WidgetTester t, {String? preset}) async {
    final game = _FakeGame();
    await t.binding.setSurfaceSize(const Size(420, 900));
    await t.pumpWidget(
      ChangeNotifierProvider<GameService>.value(
        value: game,
        child: MaterialApp(
          locale: const Locale('ko'),
          localizationsDelegates: const [
            L10n.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: L10n.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () =>
                      showCouponRedeemDialog(context, presetCode: preset),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pump(const Duration(milliseconds: 500));
    return game;
  }

  testWidgets('입력하면 대문자로 바뀌고 공백은 빠진다', (t) async {
    await openDialog(t);
    await t.enterText(find.byType(TextField), ' welcome 2026 ');
    await t.pump();
    final field = t.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'WELCOME2026');
  });

  testWidgets('비어 있으면 등록 버튼이 막혀 있고, 글자를 넣으면 풀린다', (t) async {
    final game = await openDialog(t);
    // 비어 있을 때 등록을 눌러도 아무것도 보내지 않는다.
    await t.tap(find.text('등록').first, warnIfMissed: false);
    await t.pump();
    expect(game.sent, isEmpty);
    await t.enterText(find.byType(TextField), 'ABC');
    await t.pump();
    await t.tap(find.text('등록').first);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(game.sent, ['ABC']);
  });

  testWidgets('성공하면 받은 보상을 보여 주고 확인으로 닫힌다', (t) async {
    final game = await openDialog(t, preset: 'hello');
    // 미리 채운 코드도 대문자로 정리돼 있다.
    expect(
      t.widget<TextField>(find.byType(TextField)).controller!.text,
      'HELLO',
    );
    await t.tap(find.text('등록').first);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(game.sent, ['HELLO']);
    expect(find.text('쿠폰이 등록됐어요!'), findsOneWidget);
    expect(find.textContaining('골드 500'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await t.tap(find.text('확인').first);
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(find.text('쿠폰이 등록됐어요!'), findsNothing);
  });

  testWidgets('실패하면 서버 메시지를 보여 주고 고치기 시작하면 사라진다', (t) async {
    final game = await openDialog(t, preset: 'WRONG');
    game.outcome = const CouponOutcome(success: false, message: '없는 쿠폰이에요');
    await t.tap(find.text('등록').first);
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('없는 쿠폰이에요'), findsOneWidget);
    // 입력 칸과 버튼은 그대로 — 다시 시도할 수 있다.
    expect(find.byType(TextField), findsOneWidget);
    await t.enterText(find.byType(TextField), 'RIGHT');
    await t.pump();
    expect(find.text('없는 쿠폰이에요'), findsNothing);
  });

  testWidgets('붙여넣기 버튼은 클립보드 코드를 정리해 넣고, 글자가 있으면 지우기로 바뀐다', (t) async {
    await openDialog(t);
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData')
          return <String, dynamic>{'text': ' summer-2026 \n'};
        return null;
      },
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await t.tap(find.byIcon(Icons.content_paste_rounded));
    await t.pump(const Duration(milliseconds: 200));
    expect(
      t.widget<TextField>(find.byType(TextField)).controller!.text,
      'SUMMER-2026',
    );
    expect(find.byIcon(Icons.content_paste_rounded), findsNothing);
    await t.tap(find.byIcon(Icons.close_rounded));
    await t.pump();
    expect(t.widget<TextField>(find.byType(TextField)).controller!.text, '');
    expect(find.byIcon(Icons.content_paste_rounded), findsOneWidget);
  });

  testWidgets('클립보드가 비어 있으면 안내만 하고 입력은 그대로', (t) async {
    await openDialog(t);
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData')
          return <String, dynamic>{'text': ''};
        return null;
      },
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await t.tap(find.byIcon(Icons.content_paste_rounded));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('복사해 둔 코드가 없어요'), findsOneWidget);
  });
}
