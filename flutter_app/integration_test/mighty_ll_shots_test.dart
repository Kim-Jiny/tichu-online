import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'shots_support.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('mighty + love letter shots', (tester) async {
    final s = Shots(binding, tester);
    final gs = await s.boot();

    // ---- 마이티 ----
    gs.createRoom(T.of('roomMighty'), gameType: 'mighty', maxPlayers: 5);
    await s.wait(3);
    for (var i = 0; i < 4; i++) { gs.addBot(speed: 'fast'); await s.wait(0.6); }
    await s.snap('20_mighty_room');
    gs.startGame();
    var tries = 0;
    bool mReady() {
      final st = gs.mightyGameState;
      return st != null && st.phase == 'playing' && st.isMyTurn &&
          st.currentTrick.length >= 2 && st.myCards.length >= 7;
    }
    await s.until(mReady, timeout: 300, tick: () {
      final st = gs.mightyGameState;
      if (st == null) return;
      if (st.phase == 'bidding' && st.isMyTurn) {
        gs.mightyPass();
      } else if (st.phase == 'playing' && st.isMyTurn && st.myCards.isNotEmpty) {
        gs.mightyPlayCard(st.myCards[tries++ % st.myCards.length]);
      }
    });
    await s.snap(mReady() ? '21_mighty_play' : '21_mighty_fail', settle: 2);
    gs.leaveRoom();
    await s.wait(4);

    // ---- 러브레터 ----
    gs.createRoom(T.of('roomLl'), gameType: 'love_letter', maxPlayers: 4);
    await s.wait(3);
    for (var i = 0; i < 3; i++) { gs.addBot(speed: 'fast'); await s.wait(0.6); }
    await s.snap('30_ll_room');
    gs.startGame();
    var turns = 0;
    bool lReady() {
      final st = gs.llGameState;
      return st != null && st.phase == 'playing' && st.isMyTurn && turns >= 1;
    }
    await s.until(lReady, timeout: 200, tick: () {
      final st = gs.llGameState;
      if (st == null) return;
      if (st.phase == 'playing' && st.isMyTurn && st.myCards.isNotEmpty && turns < 1) {
        turns++;
        gs.llPlayCard(st.myCards.first);
      } else if (st.pendingEffect != null) {
        final t = st.pendingEffect!.validTargets;
        if (t.isNotEmpty) gs.llSelectTarget(t.first);
      }
    });
    await s.snap(lReady() ? '31_ll_play' : '31_ll_fail', settle: 2);
  });
}
