import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/l10n/app_localizations.dart';
import 'package:tichu_online/widgets/sk_expansion_guide.dart';

/// 확장팩 카드 안내 — 방 대기실과 게임 화면이 같이 쓴다.
///
/// 보는 것: 켠 확장팩만 나오는가, 해적 능력 모드면 다섯 해적이 따라오는가,
/// 크라켄·흰고래 설명에 순서 규칙(나중에 낸 쪽이 적용)이 붙는가.
/// 마지막이 중요한 이유는 둘 중 하나만 읽는 사람이 있어서다 — 한쪽에만
/// 적으면 반만 아는 상태가 된다.

Future<L10n> _l10n(WidgetTester t, [Locale locale = const Locale('ko')]) async {
  late L10n out;
  await t.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        L10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L10n.supportedLocales,
      home: Builder(
        builder: (ctx) {
          out = L10n.of(ctx);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return out;
}

void main() {
  testWidgets('켠 확장팩만 나온다', (t) async {
    final l = await _l10n(t);
    expect(skExpansionGuideEntries(l, const []), isEmpty);

    final kraken = skExpansionGuideEntries(l, const ['kraken']);
    expect(kraken.length, 1);
    expect(kraken.single.cardId, 'sk_kraken');

    final two = skExpansionGuideEntries(l, const ['kraken', 'loot']);
    expect(two.map((e) => e.cardId).toList(), ['sk_kraken', 'sk_loot_1']);
  });

  testWidgets('해적 능력 모드는 다섯 해적을 함께 설명한다', (t) async {
    final l = await _l10n(t);
    final e = skExpansionGuideEntries(l, const ['pirate_abilities']);
    // 모드 한 줄 + 해적 5장. 모드만 적으면 "무슨 능력인지"는 여전히 모른다.
    expect(e.length, 6);
    final cards = e.map((x) => x.cardId).where((c) => c.isNotEmpty).toList();
    expect(cards, [
      'sk_pirate_1',
      'sk_pirate_2',
      'sk_pirate_3',
      'sk_pirate_4',
      'sk_pirate_5',
    ]);
    for (final x in e) {
      expect(x.name, isNotEmpty, reason: '이름이 비면 줄이 비어 보인다');
    }
  });

  testWidgets('크라켄·흰고래 설명에 순서 규칙이 양쪽 다 붙는다', (t) async {
    final l = await _l10n(t);
    final e = skExpansionGuideEntries(l, const ['kraken', 'white_whale']);
    expect(e.length, 2);
    for (final x in e) {
      expect(
        x.desc.contains(l.rulesSkExpCreatureOrder),
        isTrue,
        reason: '${x.cardId} 에 순서 규칙이 빠졌다 — 한쪽만 읽는 사람이 있다',
      );
    }
  });

  testWidgets('영어·독일어에서도 비어 있지 않다', (t) async {
    for (final loc in const [Locale('en'), Locale('de')]) {
      final l = await _l10n(t, loc);
      final e = skExpansionGuideEntries(l, const [
        'kraken',
        'white_whale',
        'loot',
        'pirate_abilities',
      ]);
      expect(e.length, 9, reason: '$loc');
      for (final x in e) {
        expect(x.name, isNotEmpty, reason: '$loc / ${x.cardId}');
        expect(x.desc, isNotEmpty, reason: '$loc / ${x.cardId}');
      }
    }
  });

  testWidgets('시트가 화면을 다 먹지 않고 닫기 버튼으로 닫힌다', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 760));
    addTearDown(() => t.binding.setSurfaceSize(null));

    late BuildContext ctx;
    await t.pumpWidget(
      MaterialApp(
        locale: const Locale('ko'),
        localizationsDelegates: const [
          L10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (c) {
            ctx = c;
            return const Scaffold(body: SizedBox.shrink());
          },
        ),
      ),
    );

    // 해적 능력 모드까지 켜서 줄이 가장 많은 경우로 연다.
    showSkExpansionGuide(ctx, const [
      'kraken',
      'white_whale',
      'loot',
      'pirate_abilities',
    ]);
    await t.pumpAndSettle();

    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget, reason: '시트가 떠야 한다');

    // 화면을 꽉 채우면 끌어내릴 손잡이도 바깥을 누를 여백도 안 보인다.
    final h = t.getSize(sheet).height;
    expect(h, lessThan(760 * 0.85), reason: '시트가 화면을 거의 다 덮었다 (높이 $h)');

    // 닫기 버튼이 보이고, 실제로 닫혀야 한다.
    final close = find.byIcon(Icons.close_rounded);
    expect(close, findsOneWidget, reason: '닫기 버튼이 보여야 한다');
    await t.tap(close);
    await t.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing, reason: '닫혀야 한다');
  });

  testWidgets('모르는 확장팩 키가 와도 시트가 깨지지 않는다', (t) async {
    final l = await _l10n(t);
    // 서버가 새 확장팩을 먼저 내보내고 앱이 아직 모를 수 있다.
    final e = skExpansionGuideEntries(l, const ['kraken', 'something_new']);
    expect(e.length, 2);
    expect(e.last.name, 'something_new');
    expect(e.last.cardId, isEmpty, reason: '없는 그림을 찾지 않아야 한다');
  });
}
