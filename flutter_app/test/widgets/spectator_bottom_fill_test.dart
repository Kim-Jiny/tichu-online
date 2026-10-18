import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tichu_online/services/game_service.dart';
import 'package:tichu_online/theme/cartoon.dart';
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
                    const Positioned.fill(
                      child: ColoredBox(color: Colors.red, key: Key('content')),
                    ),
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

  // 띠는 창과 같은 색이어야 한다. 스컬킹 손패는 내 차례일 때 노랗게 바뀌는데
  // 띠가 종이색으로 고정돼 있으면 차례가 올 때마다 창 아래에 이음새가 보인다.
  testWidgets('채울 색을 바꿔 줄 수 있다', (t) async {
    const myTurn = Color(0xFFFFF1B8);
    await t.pumpWidget(
      ChangeNotifierProvider<GameService>.value(
        value: _FakeGame(),
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(padding: EdgeInsets.only(bottom: 34)),
            child: Scaffold(
              body: Stack(
                children: [
                  SpectatorBottomFill(when: (_) => true, color: (_) => myTurn),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final fill = find.descendant(
      of: find.byType(SpectatorBottomFill),
      matching: find.byType(ColoredBox),
    );
    expect(t.widget<ColoredBox>(fill).color, myTurn);
    // 띠가 안전 영역만큼만 차지해야 한다 — 더 높으면 손패를 가린다.
    expect(t.getSize(fill).height, 34);
  });

  testWidgets('색을 안 넘기면 종이색', (t) async {
    await t.pumpWidget(
      ChangeNotifierProvider<GameService>.value(
        value: _FakeGame(),
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(padding: EdgeInsets.only(bottom: 20)),
            child: Scaffold(
              body: Stack(children: [SpectatorBottomFill(when: (_) => true)]),
            ),
          ),
        ),
      ),
    );
    expect(
      t
          .widget<ColoredBox>(
            find.descendant(
              of: find.byType(SpectatorBottomFill),
              matching: find.byType(ColoredBox),
            ),
          )
          .color,
      Cartoon.paper,
    );
  });
}
