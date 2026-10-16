import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/l10n/app_localizations.dart';
import 'package:tichu_online/screens/force_update_screen.dart';

Widget _app(Widget child, {Locale locale = const Locale('ko')}) => MaterialApp(
  locale: locale,
  localizationsDelegates: const [
    L10n.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: L10n.supportedLocales,
  home: child,
);

void main() {
  testWidgets('앱: 새 버전 안내와 업데이트 버튼', (t) async {
    await t.binding.setSurfaceSize(const Size(400, 800));
    var taps = 0;
    await t.pumpWidget(
      _app(ForceUpdateScreen(isWeb: false, onPressed: () => taps++)),
    );
    await t.pump(const Duration(milliseconds: 1200));
    expect(t.takeException(), isNull);
    expect(find.text('새 버전이 나왔어요!'), findsWidgets);
    expect(find.textContaining('업데이트가 꼭 필요해요'), findsOneWidget);
    expect(find.textContaining('필요한 버전'), findsNothing);
    await t.tap(find.text('업데이트하러 가기').first);
    expect(taps, 1);
  });

  testWidgets('웹: 새로고침 문구와 버튼', (t) async {
    await t.binding.setSurfaceSize(const Size(400, 800));
    await t.pumpWidget(_app(ForceUpdateScreen(isWeb: true, onPressed: () {})));
    await t.pump(const Duration(milliseconds: 1200));
    expect(find.textContaining('새로고침하면 바로 이어서'), findsOneWidget);
    expect(find.text('새로고침'), findsWidgets);
    expect(find.text('업데이트하러 가기'), findsNothing);
  });

  testWidgets('작은 화면·영어·독일어에서도 넘치지 않는다', (t) async {
    for (final locale in const [Locale('en'), Locale('de')]) {
      await t.binding.setSurfaceSize(const Size(320, 560));
      await t.pumpWidget(
        _app(ForceUpdateScreen(isWeb: false, onPressed: () {}), locale: locale),
      );
      await t.pump(const Duration(milliseconds: 1200));
      expect(t.takeException(), isNull, reason: locale.languageCode);
    }
  });
}
