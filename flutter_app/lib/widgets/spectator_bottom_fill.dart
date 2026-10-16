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
    // Stack 안에 있으므로 비울 때도 Positioned 여야 한다. 그냥 SizedBox.shrink 를
    // 돌려주면 위치 없는 0 크기 자식이 되어 Stack 이 0x0 으로 쪼그라들고, 그 위에
    // 얹은 게임 화면 전체가 흰 화면이 된다(웹·홈 바 없는 기기·관전 결과 화면).
    const none = Positioned(
      left: 0,
      bottom: 0,
      width: 0,
      height: 0,
      child: SizedBox.shrink(),
    );
    if (inset <= 0) return none;
    return Consumer<GameService>(
      builder: (context, game, _) {
        if (!when(game)) return none;
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

/// 관전 중 남의 패를 펼칠 때 "○○의 패 ✕" 알약을 손패 창 바로 위에 띄운다.
/// 이름·닫기가 창 안에 있으면 창이 높아져 좌석을 가린다.
class SpectatorHandWithChip extends StatelessWidget {
  const SpectatorHandWithChip({
    super.key,
    required this.label,
    required this.onClose,
    required this.child,
  });

  final String label;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onClose,
          child: Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.fromLTRB(12, 3, 6, 3),
            decoration: BoxDecoration(
              color: Cartoon.paper,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: Cartoon.ink, width: 1.8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: Cartoon.userText(size: 13),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.close_rounded, size: 18, color: Cartoon.ink),
              ],
            ),
          ),
        ),
        SizedBox(width: double.infinity, child: child),
      ],
    );
  }
}
