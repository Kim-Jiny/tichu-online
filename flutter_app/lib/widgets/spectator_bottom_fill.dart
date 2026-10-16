import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/game_service.dart';
import '../theme/cartoon.dart';

/// 관전 화면은 SafeArea 안에서 아래 손패/안내 창을 그리기 때문에, 홈 바가 있는
/// 기기에서는 창 아래 안전 영역이 배경 그라데이션으로 비어 창이 떠 보인다.
/// 그 띠를 창과 같은 종이색으로 채운다. SafeArea 보다 먼저(뒤에) 놓는다.
class SpectatorBottomFill extends StatelessWidget {
  final bool Function(GameService game) when;
  const SpectatorBottomFill({super.key, required this.when});

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).padding.bottom;
    if (inset <= 0) return const SizedBox.shrink();
    return Consumer<GameService>(
      builder: (context, game, _) {
        if (!when(game)) return const SizedBox.shrink();
        return Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: inset,
          child: const ColoredBox(color: Cartoon.paper),
        );
      },
    );
  }
}
