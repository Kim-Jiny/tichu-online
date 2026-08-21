import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/game_service.dart';

/// 자리 사진 오른쪽 위에 붙는 잠수 교체 버튼.
///
/// 프로필 팝업 안에 두었더니 한 단계 숨어 있었다. 이 버튼이 필요한 순간은
/// 판이 멈춰서 다들 기다리고 있는 때인데, 그때 "자리를 눌러 팝업을 열고
/// 아래를 본다" 는 세 걸음은 길다. 멈춰 있는 그 자리에 바로 붙인다.
///
/// [game] 이 자를 수 있다고 알려 준 자리에만 나타난다. 화면이 스스로
/// 판단하지 않는 이유는 판단이 두 벌이면 어긋나기 때문이고, 어긋나면 멀쩡히
/// 두고 있는 사람에게 버튼이 붙는다. 상대가 돌아와 한 수 두면 다음 상태와
/// 함께 사라진다.
///
/// 자를 수 없을 때는 [child] 를 **그대로** 돌려준다. 빈 Stack 으로 감싸면
/// 네 게임 화면의 자리 배치가 미묘하게 달라진다.
class AfkKickBadge extends StatelessWidget {
  const AfkKickBadge({
    super.key,
    required this.child,
    required this.game,
    required this.nickname,
    required this.avatarSize,
    this.corner = Alignment.topRight,
  });

  /// 감쌀 아바타.
  final Widget child;

  /// null 이면 아무것도 안 붙인다. 러브레터 화면은 서비스를 늦게 잡아서
  /// 첫 프레임에 null 일 수 있는데, 거기서 터지면 판 전체가 안 그려진다.
  final GameService? game;

  /// 이 자리에 앉은 사람. 서버가 준 목록과 대조한다.
  final String nickname;

  /// 아바타 지름. 배지 크기와 위치를 여기에 맞춘다 — 자리 크기가 화면·기기
  /// 마다 달라서 고정값을 쓰면 작은 화면에서 사진을 덮는다.
  final double avatarSize;

  /// 사진의 어느 모서리에 붙일지. 기본은 오른쪽 위인데, 마이티는 거기에
  /// 카드보기 배지가 이미 있어서 오른쪽 아래로 내린다. 두 배지가 겹치면
  /// 어느 쪽을 누른 건지 알 수 없고, 하나는 되돌릴 수 없는 동작이다.
  final Alignment corner;

  @override
  Widget build(BuildContext context) {
    final g = game;
    final reason = g?.kickReasonFor(nickname);
    if (g == null || reason == null) return child;

    // 사진의 40% 정도. 손가락으로 누를 수 있는 최소치는 지키되, 큰 화면에서
    // 사진만큼 커지지는 않게 위아래를 자른다.
    final d = (avatarSize * 0.4).clamp(18.0, 28.0);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          // 사진 모서리에 걸치게 둔다. 완전히 바깥에 두면 자리 사이 간격이
          // 좁은 배치에서 옆자리를 침범한다.
          top: corner.y < 0 ? -d * 0.28 : null,
          bottom: corner.y > 0 ? -d * 0.28 : null,
          left: corner.x < 0 ? -d * 0.28 : null,
          right: corner.x > 0 ? -d * 0.28 : null,
          child: Semantics(
            button: true,
            label: L10n.of(context).kickAfkAction,
            child: Material(
              color: const Color(0xFFC1553F),
              shape: const CircleBorder(),
              elevation: 2,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => confirmAfkKick(context, nickname, g, reason),
                child: SizedBox(
                  width: d,
                  height: d,
                  child: Icon(
                    Icons.smart_toy_outlined,
                    size: d * 0.6,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 자르기 전에 한 번 묻는다.
///
/// 상대에게는 되돌릴 수 없는 일이다 — 자리를 봇이 받고 전적에 탈주가 남는다.
/// 자리 위의 작은 버튼이라 더욱, 손이 스쳐 일어날 일은 아니어야 한다.
///
/// [reason] 에 따라 묻는 말이 다르다. 방장이 판단하는 근거가 "접속이
/// 끊겼다" 와 "붙어는 있는데 안 둔다" 로 다르고, 둘을 뭉뚱그리면 접속은
/// 멀쩡한 사람에게 연결이 끊겼다고 말하게 된다.
Future<void> confirmAfkKick(
  BuildContext context,
  String nickname,
  GameService game,
  String reason,
) async {
  final l10n = L10n.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(
        reason == 'disconnected'
            ? l10n.kickAfkConfirmTitleOffline(nickname)
            : l10n.kickAfkConfirmTitleIdle(nickname),
      ),
      content: Text(l10n.kickAfkConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFFC1553F)),
          child: Text(l10n.kickAfkConfirmAction),
        ),
      ],
    ),
  );
  if (ok == true) game.kickAfkPlayer(nickname);
}
