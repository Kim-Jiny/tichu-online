import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
// Platform fakes isolate GameService from native Firebase in this test.
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_messaging_platform_interface/firebase_messaging_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tichu_online/services/game_service.dart';
import 'package:tichu_online/services/network_service.dart';

class _Core extends FirebasePlatform {
  @override
  FirebaseAppPlatform app([String name = '[DEFAULT]']) => FirebaseAppPlatform(
    name,
    const FirebaseOptions(
      apiKey: 'test',
      appId: 'test',
      messagingSenderId: 'test',
      projectId: 'test',
    ),
  );
}

class _Messaging extends FirebaseMessagingPlatform {
  @override
  FirebaseMessagingPlatform delegateFor({required FirebaseApp app}) => this;
  @override
  FirebaseMessagingPlatform setInitialValues({bool? isAutoInitEnabled}) => this;
  @override
  Stream<String> get onTokenRefresh => const Stream.empty();
}

class _Network extends NetworkService {
  final incoming = StreamController<Map<String, dynamic>>.broadcast();
  final sent = <Map<String, dynamic>>[];
  final queued = <Map<String, dynamic>>[];

  @override
  Stream<Map<String, dynamic>> get messageStream => incoming.stream;
  @override
  void send(Map<String, dynamic> data) => sent.add(Map.of(data));
  @override
  Future<void> queueForRetry(Map<String, dynamic> data) async {
    queued.add(Map.of(data));
  }
}

void main() {
  late _Network network;
  late GameService game;
  var disposed = false;
  void disposeGame() {
    if (disposed) return;
    disposed = true;
    game.dispose();
  }

  void start() {
    disposed = false;
    SharedPreferences.setMockInitialValues({});
    FirebasePlatform.instance = _Core();
    FirebaseMessagingPlatform.instance = _Messaging();
    network = _Network();
    game = GameService(network)..playerName = 'A';
  }

  tearDown(() async {
    disposeGame();
    network.dispose();
    await network.incoming.close();
  });

  int attempts(String id) => network.sent
      .where((m) => m['type'] == 'ad_reward' && m['claimId'] == id)
      .length;

  for (final response in <Map<String, dynamic>>[
    {'success': true, 'gold': 50, 'remaining': 4},
    {'success': false, 'messageKey': 'db_ad_reward_exhausted'},
    {'success': false, 'messageKey': 'db_reward_grant_failed'},
  ]) {
    testWidgets('이전 광고 응답은 새 광고 재시도를 종료하지 않는다: $response', (t) async {
      start();
      game.claimAdReward();
      final oldId = network.sent.last['claimId'] as String;
      game.claimAdReward();
      final newId = network.sent.last['claimId'] as String;
      expect(newId, isNot(oldId));
      expect(network.queued.single['claimId'], oldId);

      network.incoming.add({
        'type': 'ad_reward_result',
        'claimId': oldId,
        ...response,
      });
      await t.pump();
      expect(game.adRewardResult, isNull);
      // An old wallet snapshot must not replace current totals either.
      expect(game.gold, 0);
      await t.pump(const Duration(seconds: 8));
      expect(attempts(newId), 2);
      disposeGame();
    });
  }

  testWidgets('자신의 성공 응답을 받으면 재시도를 종료한다', (t) async {
    start();
    game.claimAdReward();
    final id = network.sent.last['claimId'] as String;
    network.incoming.add({
      'type': 'ad_reward_result',
      'claimId': id,
      'success': true,
      'gold': 100,
      'remaining': 3,
    });
    await t.pump();
    expect(game.gold, 100);
    expect(game.adRewardResult, 'ad_reward_success');
    await t.pump(const Duration(seconds: 9));
    expect(attempts(id), 1);
    disposeGame();
  });

  testWidgets('자신의 일시 오류는 같은 id 로 재시도한다', (t) async {
    start();
    game.claimAdReward();
    final id = network.sent.last['claimId'] as String;
    network.incoming.add({
      'type': 'ad_reward_result',
      'claimId': id,
      'success': false,
    });
    await t.pump();
    await t.pump(const Duration(seconds: 2));
    expect(attempts(id), 2);
    disposeGame();
  });

  testWidgets('id 없는 응답은 진행 중인 요청을 종료하지 않는다', (t) async {
    start();
    game.claimAdReward();
    final id = network.sent.last['claimId'] as String;
    network.incoming.add({
      'type': 'ad_reward_result',
      'success': true,
      'gold': 50,
      'remaining': 4,
    });
    await t.pump();
    await t.pump(const Duration(seconds: 8));
    expect(attempts(id), 2);
    disposeGame();
  });
}
