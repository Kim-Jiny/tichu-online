import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'shots_support.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('skull king shots', (tester) async {
    final s = Shots(binding, tester);
    final gs = await s.boot();
    gs.createRoom('스컬킹 한 판', gameType: 'skull_king', maxPlayers: 4,
        skExpansions: const ['kraken', 'white_whale', 'loot', 'pirate_abilities']);
    await s.wait(3);
    for (var i = 0; i < 3; i++) { gs.addBot(speed: 'fast'); await s.wait(0.6); }
    await s.snap('10_sk_room');
    gs.startGame();
    var tries = 0, bidRound = -1, gotAbility = false, gotPlay = false;
    void tick() {
      final st = gs.skGameState;
      if (st == null) return;
      if (st.phase == 'bidding' && st.round != bidRound) {
        bidRound = st.round;
        gs.submitBid(st.round >= 3 ? 1 : 0);
      } else if (st.phase == 'playing' && st.isMyTurn && st.myCards.isNotEmpty) {
        gs.playCard(st.myCards[tries++ % st.myCards.length]);
      } else if (st.isMyAbilityTurn && gotAbility) {
        gs.skUsePirateAbility(wager: 10, delta: 0);
      }
    }
    bool playReady() {
      final st = gs.skGameState;
      return st != null && st.phase == 'playing' && st.round >= 4 && st.isMyTurn &&
          st.currentTrick.isNotEmpty && st.myCards.length >= 3;
    }
    await s.until(() => playReady() || (gs.skGameState?.isMyAbilityTurn ?? false), timeout: 400, tick: tick);
    if (gs.skGameState?.isMyAbilityTurn ?? false) {
      gotAbility = true;
      await s.snap('12_sk_ability', settle: 2);
      await s.until(playReady, timeout: 400, tick: tick);
    }
    gotPlay = playReady();
    await s.snap(gotPlay ? '11_sk_play' : '11_sk_fail', settle: 2);
    gs.leaveRoom();
    await s.wait(3);
  });
}
