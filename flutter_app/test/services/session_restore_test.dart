import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/services/game_service.dart';
import 'package:tichu_online/services/network_service.dart';
import 'package:tichu_online/services/restore_sync_tracker.dart';
import 'package:tichu_online/services/session_service.dart';

class FakeNetworkService extends NetworkService {
  bool disconnected = false;

  @override
  Future<void> ensureConnected([String? url]) async {}

  @override
  Future<bool> reconnect() async => true;

  @override
  void disconnect({bool intentional = true}) {
    disconnected = true;
  }
}

class FakeGameService extends ChangeNotifier implements GameService {
  bool resetCalled = false;

  @override
  void reset() {
    resetCalled = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('RestoreSyncTracker completes only after explicit complete', () async {
    final tracker = RestoreSyncTracker();

    var requestCount = 0;
    bool? completed;
    final future = tracker.begin(
      timeout: const Duration(seconds: 1),
      request: () => requestCount++,
    );
    future.then((value) => completed = value);

    expect(requestCount, 1);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(completed, isNull);

    tracker.complete();
    expect(await future, isTrue);
    expect(completed, isTrue);
  });

  test('RestoreSyncTracker returns false when explicit completion is missing', () async {
    final tracker = RestoreSyncTracker();

    final result = await tracker.begin(
      timeout: const Duration(milliseconds: 20),
      request: () {},
    );

    expect(result, isFalse);
  });

  test('SessionService can suppress one auto restore attempt after reset', () {
    final network = FakeNetworkService();
    final game = FakeGameService();
    final session = SessionService(network, game);

    session.resetToLoginState(suppressAutoRestore: true);

    expect(session.consumeAutoRestoreSuppression(), isTrue);
    expect(session.consumeAutoRestoreSuppression(), isFalse);
    expect(network.disconnected, isTrue);
    expect(game.resetCalled, isTrue);
  });
}
