import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tichu_online/services/game_service.dart';
import 'package:tichu_online/widgets/playing_card.dart';
import 'package:tichu_online/widgets/tichu_special_art.dart';

/// PlayingCard 는 카드 뒷면 색을 GameService 에서 읽는다. 이 테스트가 보는
/// 것은 앞면 테두리라서, 뒷면 색만 고정으로 돌려주는 가짜면 충분하다.
class _FakeGame extends ChangeNotifier implements GameService {
  @override
  List<Color> get cardBackColors => const [
    Color(0xFF2B3A67),
    Color(0xFF1B2444),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 특수 카드 네 장을 손패 크기에서 서로 구분할 수 있는지.
///
/// 작아지면 그림만으로는 갈리지 않는다. 용·봉황은 둘 다 붉은 계열이고,
/// 개·참새는 실루엣이 비슷하다. 그래서 둘씩 다른 방법으로 가른다 —
/// 용·봉황은 테두리 색, 개·참새는 모서리 뱃지.
void main() {
  Widget host(Widget child) => ChangeNotifierProvider<GameService>(
    create: (_) => _FakeGame(),
    child: MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );

  group('용·봉황은 테두리 색으로 갈린다', () {
    test('둘만 색을 가진다', () {
      expect(PlayingCard.specialBorders.keys.toSet(), {
        'special_dragon',
        'special_phoenix',
      });
    });

    test('초록과 빨강이고, 서로 충분히 다르다', () {
      final dragon = PlayingCard.specialBorders['special_dragon']!;
      final phoenix = PlayingCard.specialBorders['special_phoenix']!;
      // 용은 초록(녹색 성분이 가장 큼), 봉황은 빨강(적색 성분이 가장 큼).
      expect(dragon.g, greaterThan(dragon.r));
      expect(dragon.g, greaterThan(dragon.b));
      expect(phoenix.r, greaterThan(phoenix.g));
      expect(phoenix.r, greaterThan(phoenix.b));
    });

    testWidgets('앞면에는 그 색이 쓰이고 뒷면에는 안 쓰인다', (t) async {
      // 뒷면에까지 색이 나가면 뒤집힌 패만 보고 손에 뭐가 있는지 알 수 있다.
      for (final faceUp in [true, false]) {
        await t.pumpWidget(host(const SizedBox()));
        await t.pumpWidget(
          host(
            PlayingCard(
              cardId: 'special_dragon',
              width: 48,
              height: 67,
              isFaceUp: faceUp,
              isInteractive: false,
            ),
          ),
        );
        await t.pump();
        final found = t
            .widgetList<Container>(find.byType(Container))
            .map((c) => c.decoration)
            .whereType<BoxDecoration>()
            .any(
              (d) =>
                  d.border is Border &&
                  (d.border as Border).top.color ==
                      PlayingCard.specialBorders['special_dragon'],
            );
        expect(
          found,
          faceUp,
          reason: faceUp ? '앞면에 용 테두리가 없다' : '뒷면에 용 테두리가 보인다',
        );
      }
    });
  });

  group('개·참새는 모서리 뱃지로 갈린다', () {
    testWidgets('개에는 발바닥, 참새에는 숫자 1', (t) async {
      await t.pumpWidget(
        host(
          const SizedBox(
            width: 60,
            height: 84,
            child: TichuSpecialArt('special_dog'),
          ),
        ),
      );
      await t.pump();
      expect(find.byIcon(Icons.pets_rounded), findsOneWidget);
      expect(find.text('1'), findsNothing);

      await t.pumpWidget(
        host(
          const SizedBox(
            width: 60,
            height: 84,
            child: TichuSpecialArt('special_bird'),
          ),
        ),
      );
      await t.pump();
      expect(find.text('1'), findsOneWidget);
      expect(find.byIcon(Icons.pets_rounded), findsNothing);
    });

    testWidgets('용·봉황에는 뱃지가 없다 — 테두리로 이미 갈린다', (t) async {
      for (final id in ['special_dragon', 'special_phoenix']) {
        await t.pumpWidget(
          host(SizedBox(width: 60, height: 84, child: TichuSpecialArt(id))),
        );
        await t.pump();
        expect(find.byIcon(Icons.pets_rounded), findsNothing);
        expect(find.text('1'), findsNothing);
      }
    });
  });

  group('개를 냈을 때는 카드가 아니라 강아지만', () {
    test('배경 지운 그림이 번들에 있다', () {
      final f = File('assets/cards/dog_art.webp');
      expect(
        f.existsSync(),
        isTrue,
        reason:
            'dog_art.webp 가 없다 — server/tools/make_sk_creature_art.js 로 뽑는다',
      );
      // 투명 영역이 있어야 '배경을 지운' 그림이다. 원본 카드와 크기가
      // 다른지로 대신 확인한다(원본은 520x793 카드 비율).
      expect(f.lengthSync(), greaterThan(1000));
    });

    test('날아가는 연출은 강아지, 트릭 자리는 카드 — 서로 바뀌지 않게', () {
      // 한 번 반대로 넣은 적이 있다. 두 곳 모두 'special_dog' 를 다루므로
      // 파일 전체에서 그림 경로가 한 번이라도 나오면 통과해 버렸다.
      // 그래서 자리별로 따로 본다.
      final src = File('lib/screens/game_screen.dart').readAsStringSync();

      // 날아가는 연출(_DogFlight)은 배경 지운 강아지를 쓴다.
      final flight = src.substring(src.indexOf('class _DogFlightState'));
      expect(
        flight.contains('assets/cards/dog_art.webp'),
        isTrue,
        reason: '날아가는 연출이 카드를 띄운다 — 강아지여야 한다',
      );

      // 트릭 자리(_buildDogPlayedBanner)는 카드를 쓴다.
      final start = src.indexOf('Widget _buildDogPlayedBanner');
      final banner = src.substring(
        start,
        src.indexOf('Widget _buildLatestTrick'),
      );
      expect(
        banner.contains('assets/cards/dog_art.webp'),
        isFalse,
        reason: '트릭 자리가 강아지를 띄운다 — 다른 낸 패와 같은 카드 모양이어야 한다',
      );
      expect(
        banner.contains("cardId: 'special_dog'"),
        isTrue,
        reason: '트릭 자리에 개 카드가 없다',
      );

      // 그림이 없을 때 연출이 통째로 사라지면 선이 누구에게 갔는지 안 보인다.
      expect(flight.contains('errorBuilder'), isTrue);
    });
  });
}
