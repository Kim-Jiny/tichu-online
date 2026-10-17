import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/l10n/app_localizations.dart';
import 'package:tichu_online/models/sk_game_state.dart';
import 'package:tichu_online/theme/cartoon.dart';
import 'package:tichu_online/widgets/sk_card_highlight.dart';
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
    double Function(int, int)? seatAngle,
    Map<String, SkCardHighlight>? highlights,
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
              seatAngle: seatAngle,
              buildCard: (id, {size = 60, highlight = SkCardHighlight.none}) {
                highlights?[id] = highlight;
                return Container(
                  key: ValueKey('card:$id'),
                  width: size * 0.7,
                  height: size,
                  color: highlight == SkCardHighlight.none
                      ? Colors.grey
                      : Colors.blue,
                );
              },
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

  testWidgets('벤트: 가져온 카드에는 승리 표식이 아니라 가져온 표식', (t) async {
    // 전에는 강조가 bool 하나여서, 덱에서 가져온 카드에 트릭 승리
    // 표식(트로피)이 붙었다. 가져온 카드는 이긴 카드가 아니다.
    final marks = <String, SkCardHighlight>{};
    await pump(
      t,
      _json(
        pirate: 'bendt',
        hand: ['sk_yellow_1', 'sk_green_2', 'sk_black_3', 'sk_purple_4'],
        info: {
          'drawn': ['sk_black_3', 'sk_purple_4'],
        },
      ),
      highlights: marks,
    );
    expect(marks['sk_black_3'], SkCardHighlight.drawn);
    expect(marks['sk_purple_4'], SkCardHighlight.drawn);
    expect(marks['sk_yellow_1'], SkCardHighlight.none);
    expect(marks['sk_green_2'], SkCardHighlight.none);
    expect(
      marks.values,
      isNot(contains(SkCardHighlight.winner)),
      reason: '가져온 카드에 승리 표식',
    );
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

  testWidgets('창에 그 능력이 무엇인지 적혀 있다', (t) async {
    // 능력은 트릭을 이겨야 열리고 자주 나오지 않는다. 창이 떴을 때
    // "무엇을 고르는 중인지" 만 있고 "왜 고를 수 있는지" 가 없으면,
    // 처음 보는 사람은 창을 읽고도 모른다.
    await pump(t, _json(pirate: 'rosie'));
    final l = L10n.of(t.element(find.byType(SkAbilityPanel)));
    expect(find.text(l.skAbilityTitle(l.skCardRosie)), findsOneWidget);
    expect(find.text(l.skAbilityDescRosie), findsOneWidget);
  });

  testWidgets('로지: 좌석 각도를 주면 테이블과 같은 자리에 놓는다', (t) async {
    // 이름만 나열하면 "왼쪽 사람" 을 고르려는 사람이 목록에서 그게
    // 누군지 다시 찾아야 한다. 각도를 주면 보던 자리 그대로 눌러야 한다.
    //
    // 상대 2명: 왼쪽 위(200°) 와 오른쪽 위(340°) — 게임 화면과 같은 값.
    final calls = await pump(
      t,
      _json(pirate: 'rosie'),
      seatAngle: (i, n) => [200.0, 340.0][i] * 3.141592653589793 / 180,
    );
    // 버튼 안에서만 찾는다. 창 위쪽의 능력 설명에도 '나' 가 들어 있어서
    // ("…사람을 나를 포함해 아무나 지목합니다") 아무 Text 나 집으면
    // 설명 줄의 위치를 재게 된다.
    //
    // CartoonButton 은 글자를 외곽선과 채움 두 겹으로 그리므로 같은
    // 텍스트가 두 개씩 잡힌다 — 위치만 보면 되니 첫 번째를 쓴다.
    Finder inButton(String label) => find.descendant(
      of: find.byType(CartoonButton),
      matching: find.textContaining(label),
    );
    final left = t.getCenter(inButton('철수').first);
    final right = t.getCenter(inButton('영희').first);
    final me = t.getCenter(inButton('나').first);

    expect(left.dx, lessThan(right.dx), reason: '철수가 영희보다 왼쪽이어야 한다');
    expect(me.dy, greaterThan(left.dy), reason: '나는 둘보다 아래(내 자리)여야 한다');
    expect(me.dy, greaterThan(right.dy));

    // 그래도 눌러서 고를 수 있어야 한다.
    await t.tap(find.text('철수').first);
    await t.pump();
    expect(calls.single['leaderId'], 'p1');
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('로지: 각도를 안 주면 이름 목록으로 돌아간다', (t) async {
    final calls = await pump(t, _json(pirate: 'rosie'));
    await t.tap(find.text('철수').first);
    await t.pump();
    expect(calls.single['leaderId'], 'p1');
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('해리: 입찰 범위를 벗어나는 버튼은 눌리지 않는다', (t) async {
    final calls = await pump(t, _json(pirate: 'harry', bid: 0));
    expect(find.textContaining('지금 0'), findsWidgets);
    // 버튼 안에서만 찾는다. 창 위쪽의 능력 설명에도 '+1'·'-1' 이 들어
    // 있어서, 아무 Text 나 집으면 설명을 눌러 놓고 "안 눌렸다" 고
    // 넘어가 버린다 — 실제로 그렇게 통과하던 단정이었다.
    Finder btn(String label) => find.descendant(
      of: find.byType(CartoonButton),
      matching: find.textContaining(label),
    );
    await t.tap(btn('-1').first, warnIfMissed: false);
    expect(calls, isEmpty);
    await t.tap(btn('+1').first);
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
