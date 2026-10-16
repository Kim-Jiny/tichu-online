import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tichu_online/services/game_service.dart';
import 'package:tichu_online/widgets/spectator_bottom_fill.dart';

class _FakeGame extends ChangeNotifier implements GameService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  // 비어 있을 때 Stack 이 0x0 으로 쪼그라들어 화면이 통째로 흰색이 되던 회귀.
  for (final inset in [0.0, 34.0]) {
    testWidgets('채울 게 없어도 위 내용은 화면 전체 크기 (inset $inset)', (t) async {
      await t.pumpWidget(
        ChangeNotifierProvider<GameService>.value(
          value: _FakeGame(),
          child: MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(padding: EdgeInsets.only(bottom: inset)),
              child: Scaffold(
                body: Stack(
                  children: [
                    SpectatorBottomFill(when: (_) => false),
                    const Positioned.fill(child: ColoredBox(color: Colors.red, key: Key('content'))),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(t.getSize(find.byKey(const Key('content'))), const Size(800, 600));
    });
  }
}
