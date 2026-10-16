import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/l10n/app_localizations.dart';
import 'package:tichu_online/models/sk_game_state.dart';
import 'package:tichu_online/widgets/sk_pirate_ability_panel.dart';

Map<String, dynamic> _json({
  required String pirate,
  List<String> hand = const ['sk_yellow_1', 'sk_green_2', 'sk_black_3'],
  Map<String, dynamic>? info,
  int bid = 1,
  int round = 3,
}) => {
  'phase': 'pirate_ability',
  'round': round,
  'trickNumber': 1,
  'expansions': ['pirate_abilities'],
  'myCards': hand,
  'players': [
    {
      'id': 'me',
      'name': '나',
      'position': 'self',
      'bid': bid,
      'cardCount': hand.length,
    },
    {
      'id': 'p1',
      'name': '철수',
      'position': 'player_1',
      'bid': 1,
      'cardCount': 3,
    },
    {
      'id': 'p2',
      'name': '영희',
      'position': 'player_2',
      'bid': 0,
      'cardCount': 3,
    },
  ],
  'pendingAbility': {
    'playerId': 'me',
    'pirate': pirate,
    'cardId': 'sk_pirate_1',
  },
  'abilityInfo': info,
  'rascalWagers': {'me': 10},
  'abilitySeq': 3,
  'lastAbility': {'playerId': 'p1', 'pirate': 'harry', 'delta': 1, 'bid': 2},
};

void main() {
  test('해적 능력 상태를 읽는다', () {
    final s = SKGameStateData.fromJson(
      _json(
        pirate: 'bendt',
        info: {
          'drawn': ['sk_green_2', 'sk_black_3'],
        },
      ),
    );
    expect(s.hasPirateAbilities, isTrue);
    expect(s.isMyAbilityTurn, isTrue);
    expect(s.pendingAbility!.pirate, 'bendt');
    expect(s.abilityDrawn, ['sk_green_2', 'sk_black_3']);
    expect(s.abilitySeq, 3);
    expect(s.lastAbility!.delta, 1);
    expect(s.lastAbility!.bid, 2);
    expect(s.rascalWagers['me'], 10);
  });

  test('능력이 없으면 기본값이다', () {
    final s = SKGameStateData.fromJson({'phase': 'playing', 'players': []});
    expect(s.pendingAbility, isNull);
    expect(s.isMyAbilityTurn, isFalse);
    expect(s.hasPirateAbilities, isFalse);
    expect(s.abilitySeq, 0);
    expect(s.abilityUndealt, isEmpty);
  });

  test('남의 능력이면 내 차례가 아니다', () {
    final j = _json(pirate: 'rosie');
    j['pendingAbility'] = {'playerId': 'p1', 'pirate': 'rosie'};
    expect(SKGameStateData.fromJson(j).isMyAbilityTurn, isFalse);
  });

  test('해적 카드 id 와 이름', () {
    expect(skPirateKeyOf('sk_pirate_1'), 'rascal');
    expect(skPirateKeyOf('sk_pirate_2'), 'rosie');
    expect(skPirateKeyOf('sk_pirate_3'), 'bendt');
    expect(skPirateKeyOf('sk_pirate_4'), 'harry');
    expect(skPirateKeyOf('sk_pirate_5'), 'juanita');
    expect(skPirateKeyOf('sk_tigress_1'), isNull);
    expect(skPirateCardId('juanita'), 'sk_pirate_5');
  });

  Future<List<Map<String, Object?>>> pump(
    WidgetTester t,
    Map<String, dynamic> json, {
    Locale locale = const Locale('ko'),
    Size size = const Size(400, 800),
  }) async {
    final calls = <Map<String, Object?>>[];
    await t.binding.setSurfaceSize(size);
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
        home: Scaffold(
          body: Center(
            child: SkAbilityPanel(
              state: SKGameStateData.fromJson(json),
              buildCard: (id, {size = 60, highlighted = false}) => Container(
                key: ValueKey('card:$id'),
                width: size * 0.7,
                height: size,
                color: highlighted ? Colors.blue : Colors.grey,
              ),
              onUse: ({leaderId, discard, wager, delta}) => calls.add({
                'leaderId': leaderId,
                'discard': discard,
                'wager': wager,
                'delta': delta,
              }),
            ),
          ),
        ),
      ),
    );
    await t.pump();
    return calls;
  }

  testWidgets('로지: 사람을 골라 다음 선으로 지목', (t) async {
    final calls = await pump(t, _json(pirate: 'rosie'));
    expect(find.text('로지의 능력'), findsWidgets);
    expect(find.text('나 (나)'), findsWidgets);
    await t.tap(find.text('영희').first);
    expect(calls.single['leaderId'], 'p2');
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('벤트: 2장을 골라야 버릴 수 있다', (t) async {
    final calls = await pump(
      t,
      _json(
        pirate: 'bendt',
        hand: ['sk_yellow_1', 'sk_green_2', 'sk_black_3', 'sk_purple_4'],
        info: {
          'drawn': ['sk_black_3', 'sk_purple_4'],
        },
      ),
    );
    expect(find.text('버리기 (0/2)'), findsWidgets);
    await t.tap(find.text('버리기 (0/2)').first, warnIfMissed: false);
    expect(calls, isEmpty);
    await t.tap(find.byKey(const ValueKey('card:sk_yellow_1')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('card:sk_green_2')));
    await t.pump();
    // 3장째는 못 고른다
    await t.tap(find.byKey(const ValueKey('card:sk_black_3')));
    await t.pump();
    expect(find.text('버리기 (2/2)'), findsWidgets);
    await t.tap(find.text('버리기 (2/2)').first);
    expect(calls.single['discard'], ['sk_yellow_1', 'sk_green_2']);
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('라스칼: 0/10/20점', (t) async {
    final calls = await pump(t, _json(pirate: 'rascal'));
    await t.tap(find.text('20점').first);
    await t.pump();
    expect(calls.single['wager'], 20);
    // 한 번 보내면 곧바로 다시 못 보낸다
    await t.tap(find.text('10점').first, warnIfMissed: false);
    expect(calls.length, 1);
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('해리: 입찰 범위를 벗어나는 버튼은 눌리지 않는다', (t) async {
    final calls = await pump(t, _json(pirate: 'harry', bid: 0));
    expect(find.textContaining('지금 0'), findsWidgets);
    await t.tap(find.textContaining('-1').first, warnIfMissed: false);
    expect(calls, isEmpty);
    await t.tap(find.textContaining('+1').first);
    expect(calls.single['delta'], 1);
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('후아니타: 안 나눠 준 카드를 보고 확인', (t) async {
    final calls = await pump(
      t,
      _json(
        pirate: 'juanita',
        info: {
          'undealt': ['sk_red_1', 'sk_black_9', 'sk_escape_1'],
        },
      ),
    );
    expect(find.byKey(const ValueKey('card:sk_black_9')), findsOneWidget);
    await t.tap(find.text('확인').first);
    expect(calls.length, 1);
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('작은 화면·영어·독일어에서도 넘치지 않는다', (t) async {
    for (final locale in const [Locale('en'), Locale('de'), Locale('ko')]) {
      for (final p in ['rosie', 'bendt', 'rascal', 'harry', 'juanita']) {
        await pump(
          t,
          _json(
            pirate: p,
            hand: List.generate(10, (i) => 'sk_yellow_${i + 1}'),
            info: {
              'drawn': ['sk_yellow_1', 'sk_yellow_2'],
              'undealt': List.generate(14, (i) => 'sk_green_${i + 1}'),
            },
            round: 10,
          ),
          locale: locale,
          size: const Size(320, 560),
        );
        expect(t.takeException(), isNull, reason: '$p ${locale.languageCode}');
      }
    }
  });
}
