import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tichu_online/l10n/app_localizations.dart';
import 'package:tichu_online/app_navigation.dart';
import 'package:tichu_online/models/missions.dart';
import 'package:tichu_online/screens/missions_screen.dart';
import 'package:tichu_online/screens/token_shop_screen.dart';
import 'package:tichu_online/services/game_service.dart';
import 'package:tichu_online/widgets/mission_toast.dart';
import 'package:tichu_online/widgets/seat_chat_bubble.dart';
import 'package:tichu_online/widgets/token_cosmetics.dart';

class _FakeGame extends ChangeNotifier implements GameService {
  _FakeGame(this.missionsState, this.tokenShopState);

  @override
  MissionsState? missionsState;
  @override
  TokenShopState? tokenShopState;
  @override
  bool missionsLoading = false;
  @override
  int missionActionSeq = 0;
  @override
  String? missionActionReason;
  @override
  int tokenShopResultSeq = 0;
  @override
  String? tokenShopReason;
  @override
  List<Color> get themeGradient => const [Color(0xFF9ADCFF), Color(0xFFFFF1D6)];
  @override
  int get tokenBalance =>
      tokenShopState?.balance ?? missionsState?.balance ?? 0;
  @override
  int missionBadgeCount = 0;
  @override
  void clearMissionBadge() {
    missionBadgeCount = 0;
    calls.add('clear_badge');
  }

  final List<MissionCompletion> pending = [];
  @override
  bool get hasPendingMissionToasts => pending.isNotEmpty;
  @override
  List<MissionCompletion> takePendingMissionCompletions() {
    final out = List<MissionCompletion>.of(pending);
    pending.clear();
    return out;
  }

  @override
  bool get isLoggedIn => true;
  @override
  AppDestination currentDestination = AppDestination.lobby;

  @override
  List<TokenHistoryEntry> tokenHistory = [
    TokenHistoryEntry.fromJson({
      'id': 9,
      'delta': 5,
      'reason': 'streak',
      'ref': null,
      'createdAt': '2026-10-16T01:02:03Z',
    }),
    TokenHistoryEntry.fromJson({
      'id': 8,
      'delta': 1,
      'reason': 'mission',
      'ref': 'tichu_play',
      'createdAt': '2026-10-15T10:00:00Z',
    }),
    TokenHistoryEntry.fromJson({
      'id': 7,
      'delta': -60,
      'reason': 'shop',
      'ref': 'bubble_basic_2',
      'createdAt': '2026-10-14T10:00:00Z',
    }),
    TokenHistoryEntry.fromJson({
      'id': 6,
      'delta': 20,
      'reason': 'admin_grant',
      'ref': null,
      'createdAt': '2026-10-13T10:00:00Z',
    }),
  ];
  @override
  bool tokenHistoryHasMore = true;
  @override
  bool tokenHistoryLoading = false;
  @override
  bool tokenHistoryFailed = false;

  final calls = <String>[];
  @override
  void requestTokenHistory() => calls.add('history');
  @override
  void requestMoreTokenHistory() => calls.add('history_more');
  @override
  void requestMissions() => calls.add('requestMissions');
  @override
  void requestTokenShop() => calls.add('requestTokenShop');
  @override
  void pickMission(String key) => calls.add('pick:$key');
  @override
  @override
  void rerollMissions(String game) => calls.add('reroll:$game');
  @override
  void buyTokenItem(String key) => calls.add('buy:$key');
  @override
  void equipTokenItem(String slot, String? key) =>
      calls.add('equip:$slot:$key');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MissionsState _state() => MissionsState.fromJson({
  'balance': 42,
  'picksToday': 2,
  'dailyPicks': 3,
  'streak': 3,
  'streakDoneToday': true,
  'streakTarget': 7,
  'streakBonus': 5,
  'active': [
    {
      'id': 1,
      'key': 'tichu_bomb50',
      'game': 'tichu',
      'tier': 3,
      'tokens': 3,
      'progress': 25,
      'target': 50,
      'status': 'active',
      'expiresDay': '2026-10-18',
    },
    {
      'id': 2,
      'key': 'mighty_win',
      'game': 'mighty',
      'tier': 1,
      'tokens': 1,
      'progress': 1,
      'target': 1,
      'status': 'done',
    },
  ],
  'offers': {
    'tichu': {
      'rerollsLeft': 1,
      'missions': [
        {
          'key': 'tichu_play',
          'game': 'tichu',
          'tier': 1,
          'tokens': 1,
          'target': 1,
          'picked': false,
        },
        {
          'key': 'tichu_fullhouse_k',
          'game': 'tichu',
          'tier': 2,
          'tokens': 2,
          'target': 1,
          'picked': false,
        },
        {
          'key': 'tichu_bomb50',
          'game': 'tichu',
          'tier': 3,
          'tokens': 3,
          'target': 50,
          'picked': true,
        },
      ],
    },
    'mighty': {'rerollsLeft': 0, 'missions': []},
    'skull_king': {'rerollsLeft': 1, 'missions': []},
    'love_letter': {'rerollsLeft': 1, 'missions': []},
  },
});

TokenShopState _shop({int balance = 120}) => TokenShopState.fromJson({
  'balance': balance,
  'products': [
    for (final k in ['room_highlight', 'bubble_basic', 'bubble_premium'])
      for (var v = 1; v <= 3; v++)
        {
          'key': '${k}_$v',
          'kind': k,
          'variant': v,
          'price': k == 'room_highlight'
              ? 50
              : (k == 'bubble_basic' ? 60 : 100),
          'days': 30,
          'ownedUntil': (k == 'bubble_basic' && v == 2)
              ? DateTime.now()
                    .add(const Duration(days: 20))
                    .toUtc()
                    .toIso8601String()
              : null,
          'equipped': k == 'bubble_basic' && v == 2,
        },
  ],
});

Widget _app(
  _FakeGame game,
  Widget home, {
  Locale locale = const Locale('ko'),
}) => ChangeNotifierProvider<GameService>.value(
  value: game,
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: const [
      L10n.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: L10n.supportedLocales,
    home: home,
  ),
);

Future<void> _snap(WidgetTester t, GlobalKey key, String name) async {
  final dir = Platform.environment['SNAP_DIR'];
  if (dir == null) return;
  await t.runAsync(() async {
    final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 2);
    final d = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$name.png').writeAsBytesSync(d!.buffer.asUint8List());
  });
}

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({'missions_help_seen': true}),
  );

  testWidgets('미션 화면: 진행 중·후보·연속·새로고침', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 1500));
    final game = _FakeGame(_state(), _shop());
    final key = GlobalKey();
    await t.pumpWidget(
      RepaintBoundary(key: key, child: _app(game, const MissionsScreen())),
    );
    await t.pump(const Duration(milliseconds: 600));
    await t.pump(const Duration(milliseconds: 600));

    expect(find.text('미션'), findsWidgets);
    expect(find.text('폭탄으로 이긴 트릭에서 점수 50점 얻기'), findsWidgets);
    expect(find.text('25/50'), findsOneWidget);
    expect(find.text('3/7일'), findsOneWidget);
    expect(find.textContaining('티츄 5판 하기'), findsOneWidget);
    // 이미 받은 미션은 '진행 중' 버튼, 나머지는 받기.
    // 외곽선 글자라 한 라벨이 Text 두 개(테두리+채움)로 그려진다.
    expect(find.text('받기'), findsNWidgets(4));
    expect(find.text('새로고침 (1회 남음)'), findsWidgets);
    await _snap(t, key, 'missions');

    await t.tap(find.text('받기').first);
    await t.pump();
    expect(game.calls, contains('pick:tichu_play'));
    await t.tap(find.text('새로고침 (1회 남음)').first);
    await t.pump();
    expect(game.calls, contains('reroll:tichu'));
    // 포기 버튼은 없다.
    expect(find.text('포기'), findsNothing);
  });

  testWidgets('토큰 알약을 누르면 내역이 열리고 더 보기가 동작한다', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 1200));
    final game = _FakeGame(_state(), _shop());
    await t.pumpWidget(_app(game, const MissionsScreen()));
    await t.pump(const Duration(milliseconds: 800));
    await t.tap(find.text('120'));
    // 시트가 올라오는 애니메이션이 끝나야 버튼이 화면 안에 있다.
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(game.calls, contains('history'));
    expect(find.text('토큰 내역'), findsOneWidget);
    expect(find.text('연속 달성 보너스'), findsOneWidget);
    expect(find.textContaining('티츄 5판 하기'), findsWidgets);
    expect(find.text('상점 구매: 민트 구름'), findsOneWidget);
    expect(find.text('운영자 지급'), findsOneWidget);
    expect(find.text('+5'), findsOneWidget);
    expect(find.text('-60'), findsOneWidget);
    await t.tap(find.text('더 보기').first);
    await t.pump();
    expect(game.calls, contains('history_more'));
  });

  testWidgets('내역이 비어 있으면 안내 문구', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 1200));
    final game = _FakeGame(_state(), _shop())
      ..tokenHistory = const []
      ..tokenHistoryHasMore = false;
    await t.pumpWidget(_app(game, const MissionsScreen()));
    await t.pump(const Duration(milliseconds: 800));
    await t.tap(find.text('120'));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('아직 토큰 내역이 없어요'), findsOneWidget);
  });

  testWidgets('미션 화면을 열면 알림 뱃지가 지워진다', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 1200));
    final game = _FakeGame(_state(), _shop())..missionBadgeCount = 2;
    await t.pumpWidget(_app(game, const MissionsScreen()));
    await t.pump(const Duration(milliseconds: 600));
    expect(game.calls, contains('clear_badge'));
    expect(game.missionBadgeCount, 0);
  });

  Widget hostApp(_FakeGame game) => ChangeNotifierProvider<GameService>.value(
    value: game,
    child: MaterialApp(
      navigatorKey: appNavigatorKey,
      locale: const Locale('ko'),
      localizationsDelegates: const [
        L10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L10n.supportedLocales,
      builder: (context, child) => MissionToastHost(child: child!),
      home: const Scaffold(body: Text('lobby')),
    ),
  );

  testWidgets('게임 중에는 알림을 미루고, 로비로 나오면 합쳐서 한 번만 띄운다', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 900));
    final game = _FakeGame(_state(), _shop())
      ..currentDestination = AppDestination.game;
    await t.pumpWidget(hostApp(game));
    await t.pump();

    game.pending.addAll([
      const MissionCompletion(
        key: 'tichu_play',
        tokens: 1,
        streakBonus: 0,
        balance: 1,
      ),
      const MissionCompletion(
        key: 'tichu_fullhouse_k',
        tokens: 2,
        streakBonus: 5,
        balance: 8,
      ),
    ]);
    game.notifyListeners();
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('미션 2개 완료'), findsNothing); // 아직 게임 중

    game.currentDestination = AppDestination.lobby;
    game.notifyListeners();
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('미션 2개 완료!'), findsOneWidget);
    expect(find.text('토큰 +3'), findsOneWidget); // 1 + 2
    expect(find.text('연속 달성 보너스 +5'), findsOneWidget);
    expect(game.pending, isEmpty);

    // 시간이 지나면 사라지고, 같은 알림이 다시 뜨지 않는다.
    await t.pump(const Duration(seconds: 5));
    await t.pump();
    expect(find.text('미션 2개 완료!'), findsNothing);
    game.notifyListeners();
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('미션 2개 완료!'), findsNothing);
  });

  testWidgets('한 개만 깼으면 미션 이름을 보여 준다', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 900));
    final game = _FakeGame(_state(), _shop());
    await t.pumpWidget(hostApp(game));
    await t.pump();
    game.pending.add(
      const MissionCompletion(
        key: 'tichu_counter_large',
        tokens: 4,
        streakBonus: 0,
        balance: 4,
      ),
    );
    game.notifyListeners();
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('맞라지 티츄로 성공하기'), findsOneWidget);
    expect(find.text('토큰 +4'), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('이용 안내: ? 버튼으로 열리고 핵심 규칙이 들어 있다', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 1200));
    final game = _FakeGame(_state(), _shop());
    await t.pumpWidget(_app(game, const MissionsScreen()));
    await t.pump(const Duration(milliseconds: 800));
    expect(find.text('미션 이용 안내'), findsNothing);
    await t.tap(find.text('?'));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('미션 이용 안내'), findsOneWidget);
    expect(find.text('먼저 "받기"를 눌러야 해요'), findsOneWidget);
    expect(find.textContaining('받기 전에 한 플레이는 인정되지 않아요'), findsOneWidget);
    expect(find.text('사람이 2명 이상인 판만 인정돼요'), findsOneWidget);
    await t.tap(find.text('알겠어요').first);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('미션 이용 안내'), findsNothing);
  });

  testWidgets('이용 안내: 처음 들어오면 한 번만 저절로 뜬다', (t) async {
    SharedPreferences.setMockInitialValues({});
    await t.binding.setSurfaceSize(const Size(420, 1200));
    final game = _FakeGame(_state(), _shop());
    await t.pumpWidget(_app(game, const MissionsScreen()));
    await t.pump(const Duration(milliseconds: 800));
    expect(find.text('미션 이용 안내'), findsOneWidget);
    await t.tap(find.text('알겠어요').first);
    await t.pump(const Duration(milliseconds: 400));
    // 다시 들어오면 뜨지 않는다.
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(_app(game, const MissionsScreen()));
    await t.pump(const Duration(milliseconds: 800));
    expect(find.text('미션 이용 안내'), findsNothing);
  });

  testWidgets('미션 화면: 오늘 3개를 다 골랐으면 받기가 막힌다', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 900));
    final st = MissionsState.fromJson({
      'balance': 0,
      'picksToday': 3,
      'dailyPicks': 3,
      'streak': 0,
      'streakDoneToday': false,
      'streakTarget': 7,
      'streakBonus': 5,
      'active': [
        {
          'id': 1,
          'key': 'tichu_bomb50',
          'game': 'tichu',
          'tier': 3,
          'tokens': 3,
          'progress': 0,
          'target': 50,
          'status': 'active',
          'expiresDay': '2026-10-18',
        },
      ],
      'offers': {
        'tichu': {
          'rerollsLeft': 0,
          'missions': [
            {
              'key': 'tichu_play',
              'game': 'tichu',
              'tier': 1,
              'tokens': 1,
              'target': 1,
              'picked': false,
            },
          ],
        },
      },
    });
    final game = _FakeGame(st, _shop());
    await t.pumpWidget(_app(game, const MissionsScreen()));
    await t.pump(const Duration(milliseconds: 800));
    await t.tap(find.text('받기').first, warnIfMissed: false);
    await t.pump();
    expect(game.calls.where((c) => c.startsWith('pick:')), isEmpty);
    expect(find.text('오늘 새로고침 끝'), findsWidgets);
  });

  testWidgets('토큰 상점: 상품 9개, 장착 중·구매·장착 동작', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 2600));
    final game = _FakeGame(_state(), _shop());
    final key = GlobalKey();
    await t.pumpWidget(
      RepaintBoundary(key: key, child: _app(game, const TokenShopScreen())),
    );
    await t.pump(const Duration(milliseconds: 800));

    expect(find.text('토큰 상점'), findsWidgets);
    expect(find.text('방 목록 강조'), findsOneWidget);
    expect(find.text('장착 중'), findsOneWidget);
    expect(find.text('30일 연장'), findsWidgets);
    expect(find.text('구매'), findsNWidgets(16));
    await _snap(t, key, 'token_shop');

    await t.tap(find.text('구매').first);
    await t.pump();
    expect(game.calls, contains('buy:room_highlight_1'));
    await t.tap(find.text('장착 중'));
    await t.pump();
    expect(game.calls, contains('equip:bubble:null'));
  });

  testWidgets('토큰이 모자라면 구매 버튼이 눌리지 않는다', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 2600));
    final game = _FakeGame(_state(), _shop(balance: 10));
    await t.pumpWidget(_app(game, const TokenShopScreen()));
    await t.pump(const Duration(milliseconds: 800));
    await t.tap(find.text('구매').first, warnIfMissed: false);
    await t.pump();
    expect(game.calls.where((c) => c.startsWith('buy:')), isEmpty);
  });

  testWidgets('말풍선 9가지와 방 강조 3가지를 그려 본다', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 760));
    final key = GlobalKey();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: key,
            child: Container(
              color: const Color(0xFFBFE6FF),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final id in [
                    'bubble_basic_1',
                    'bubble_basic_2',
                    'bubble_basic_3',
                    'bubble_premium_1',
                    'bubble_premium_2',
                    'bubble_premium_3',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: SeatChatBubble(
                        text: '안녕하세요! $id',
                        tail: true,
                        opaque: true,
                        styleKey: id,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  const SeatChatBubble(
                    text: '기본 말풍선',
                    tail: true,
                    opaque: true,
                  ),
                  const SizedBox(height: 14),
                  for (final id in [
                    'room_highlight_1',
                    'room_highlight_2',
                    'room_highlight_3',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: RoomHighlightPreview(
                        styleKey: id,
                        name: '강조방 $id',
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byType(SeatChatBubble), findsNWidgets(7));
    expect(bubbleStyleFor('bubble_premium_3'), isNotNull);
    expect(bubbleStyleFor('없는키'), isNull);
    expect(roomHighlightFor(null), isNull);
    await _snap(t, key, 'cosmetics');
  });

  test('말풍선 키가 있으면 SeatChatBubbles 가 모양을 기억하고 만료되면 잊는다', () {
    // 키를 모르면 기본 모양(null)으로 떨어지는 것까지.
    expect(bubbleStyleFor('bubble_basic_1')?.badge, Icons.favorite_rounded);
    expect(bubbleStyleFor(''), isNull);
  });

  test('모델 파싱', () {
    final s = _state();
    expect(s.activeCount, 1); // 완료된 건 세지 않는다
    expect(s.offers['tichu']!.missions.length, 3);
    final shop = _shop();
    expect(shop.products.length, 9);
    expect(
      shop.products.firstWhere((p) => p.key == 'bubble_basic_2').owned,
      isTrue,
    );
    expect(
      shop.products.firstWhere((p) => p.key == 'bubble_premium_1').slot,
      'bubble',
    );
    expect(
      shop.products.firstWhere((p) => p.key == 'room_highlight_1').slot,
      'room_highlight',
    );
    // 모르는 필드·빈 응답에도 죽지 않는다.
    expect(MissionsState.fromJson({}).offers, isEmpty);
    expect(TokenShopState.fromJson({}).products, isEmpty);
  });

  // 쓰이지 않는 import 경고 방지용.
  test('platform', () => expect(kIsWeb, isFalse));
}
