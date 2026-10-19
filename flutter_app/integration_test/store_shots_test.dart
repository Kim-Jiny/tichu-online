import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:tichu_online/main.dart' as app;
import 'package:tichu_online/services/game_service.dart';

import 'shots_support.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('store shots', (tester) async {
    final s = Shots(binding, tester);
    final gs = await s.boot();
    await s.snap('01_lobby');

    // ---- 티츄 ----
    gs.createRoom(T.of('roomTichu'), gameType: 'tichu');
    await s.wait(3);
    for (var i = 0; i < 3; i++) {
      gs.addBot(speed: 'fast');
      await s.wait(0.6);
    }
    await s.snap('02_tichu_room');
    gs.startGame();
    var gotGrand = false, gotPlay = false;
    for (var i = 0; i < 400 && !gotPlay; i++) {
      await s.wait(0.5);
      final st = gs.gameState;
      if (st == null) continue;
      if (i % 10 == 0) debugPrint('[SHOT] i=$i phase=${st.phase} my=${st.isMyTurn} cards=${st.myCards.length} trick=${st.currentTrick.length}');
      if (st.phase == 'large_tichu_phase' && !gotGrand) {
        gotGrand = true;
        await s.snap('03_tichu_grand', settle: 2);
        gs.passLargeTichu();
      } else if (st.phase == 'card_exchange' && st.myCards.length >= 3 && !st.exchangeDone) {
        final c = st.myCards;
        gs.exchangeCards(c[0], c[1], c[2]);
      } else if (find.text(T.of('dismiss')).evaluate().isNotEmpty) {
        await tester.tap(find.text(T.of('dismiss')));
      } else if (st.phase == 'playing' && st.isMyTurn && st.currentTrick.isNotEmpty && st.myCards.length >= 11) {
        gotPlay = true;
        await s.snap('04_tichu_play', settle: 2);
      } else if (st.phase == 'playing' && st.isMyTurn && st.currentTrick.isEmpty && st.myCards.isNotEmpty) {
        // 내 차례가 선공이면 가장 낮은 카드 한 장으로 넘긴다.
        gs.playCards([st.myCards.last]);
      } else if (st.phase == 'playing' && st.isMyTurn) {
        gs.passTurn();
      }
    }
    gs.leaveRoom();
    await s.wait(3);
  });
}
