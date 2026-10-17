import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// 스컬킹 보드의 자리 계산.
///
/// 화면에서 떼어 둔 이유는 눈이 아니라 숫자로 확인하기 위해서다. 좌석이
/// 겹치는지는 인원수·각도·반지름·좌석 크기가 함께 정하는 일이라, 크기를
/// 조금 키우면 어떤 인원에서만 겹친다. 사람 눈으로 2~6인을 매번 다 확인할
/// 수는 없으니 계산으로 확인한다(sk_board_layout_test.dart).
///
/// 좌표계는 보드 영역 기준이다. 좌석은 중심점이 타원 위에 놓이고, 나(self)는
/// 아래 가운데에 따로 앉는다.
class SkBoardLayout {
  const SkBoardLayout({
    required this.size,
    required this.opponentCount,
    required this.isLandscape,
    required this.spectator,
    required this.seatWidth,
    required this.seatHeight,
    required this.playedCardHeight,
    required this.center,
    required this.radiusX,
    required this.radiusY,
    required this.seatAnglesDeg,
    required this.scale,
  });

  final Size size;
  final int opponentCount;
  final bool isLandscape;
  final bool spectator;

  final double seatWidth;
  final double seatHeight;
  final double playedCardHeight;
  final Offset center;
  final double radiusX;
  final double radiusY;

  /// 상대 자리의 각도(도). 길이는 [opponentCount].
  final List<double> seatAnglesDeg;

  /// 기본 크기에 곱해진 값. 겹침을 피하려고 줄어들었을 수 있다.
  final double scale;

  double get playedCardWidth => playedCardHeight * 0.7;

  /// i번째 상대 자리의 사각형(올려 놓기 전 기준 위치).
  Rect seatRect(int i) {
    final a = seatAnglesDeg[i] * math.pi / 180;
    return Rect.fromCenter(
      center: Offset(
        center.dx + radiusX * math.cos(a),
        center.dy + radiusY * math.sin(a),
      ),
      width: seatWidth,
      height: seatHeight,
    );
  }

  /// 겹치는 자리 쌍. 비어 있어야 정상이다.
  List<(int, int)> overlappingPairs({double gap = 0}) {
    final out = <(int, int)>[];
    for (var i = 0; i < opponentCount; i++) {
      for (var j = i + 1; j < opponentCount; j++) {
        final a = seatRect(i).inflate(gap / 2);
        final b = seatRect(j).inflate(gap / 2);
        if (a.overlaps(b)) out.add((i, j));
      }
    }
    return out;
  }

  /// 보드 밖으로 나간 자리.
  List<int> outOfBoundsSeats({double slack = 0.5}) => [
    for (var i = 0; i < opponentCount; i++)
      if (seatRect(i).left < -slack ||
          seatRect(i).top < -slack ||
          seatRect(i).right > size.width + slack ||
          seatRect(i).bottom > size.height + slack)
        i,
  ];
}

/// 좌석 크기의 기준값.
///
/// 전에는 98×118 이었다. 화면에서 자잘해 보인다는 이야기가 있어 키웠는데,
/// 그냥 키우면 자리가 많은 인원(5~6인)에서 겹친다. 그래서 아래 solve 가
/// 겹치지 않는 선까지만 키운다 — 적은 인원에서는 이 값을 다 쓰고, 많은
/// 인원에서는 알아서 줄어든다.
const double kSkSeatWidthBase = 116.0;
const double kSkSeatHeightBase = 138.0;

/// 관전 자리는 더 높다. 사진 아래에 점수와 입찰 칩이 한 줄씩 더 들어가서,
/// 플레이어와 같은 높이로 두면 사진이 먼저 줄어든다(예전 118 대 128 의 차이를
/// 같은 비율로 옮긴 값).
const double kSkSpectatorSeatHeightBase = 150.0;
const double kSkPlayedCardBase = 86.0;

/// 인원별 자리 각도(도). 0°가 오른쪽, 시계 방향(화면 y가 아래로 자라므로).
///
/// 플레이어는 자기가 아래 가운데에 앉으므로 상대는 위쪽 호에 퍼지고,
/// 관전자는 자기 자리가 없어 아래까지 고르게 퍼진다.
List<double> skSeatAnglesDeg(int opponentCount, {required bool spectator}) {
  if (opponentCount <= 0) return const [];
  if (opponentCount == 1) return const [270.0];
  if (spectator) {
    switch (opponentCount) {
      case 3:
        // 관전자는 자기 자리가 없으니 3인을 top + 아래 양옆으로 벌린다.
        return const [155.0, 270.0, 385.0];
      case 6:
        return const [132, 180, 236, 304, 360, 408];
    }
  } else {
    switch (opponentCount) {
      case 3:
        // 옆 두 자리를 210/330 에서 200/340 으로 내려 위쪽 뭉침을 푼다.
        return const [200.0, 270.0, 340.0];
      case 4:
        return const [172, 238, 302, 368];
      case 5:
        // top + 좌우 세로 두 줄. 아래 자리는 위 자리를 가로축으로 반사해
        // 같은 x 를 쓴다.
        return const [152.5, 207.5, 270.0, 332.5, 387.5];
    }
  }
  // 표가 없는 인원은 호 위에 고르게.
  final startDeg = spectator ? 150.0 : 190.0;
  final endDeg = spectator ? 390.0 : 350.0;
  return [
    for (var i = 0; i < opponentCount; i++)
      startDeg + (endDeg - startDeg) * (i / (opponentCount - 1)),
  ];
}

/// 주어진 화면에서 겹치지 않는 가장 큰 배치를 찾는다.
///
/// 크기를 키우는 일은 인원마다 한계가 다르다. 상수를 인원별로 손으로
/// 적어 두면 각도 표를 한 번 건드릴 때마다 다시 맞춰야 하므로, 기준값에서
/// 시작해 겹치지 않을 때까지 줄이는 쪽을 택했다. 적은 인원에서는 한 번에
/// 끝나고, 많은 인원에서만 몇 단계 줄어든다.
///
/// [seatGap] 은 자리 사이에 두는 최소 여백이다. 0 이면 딱 붙어도 통과하는데,
/// 그건 겹치지 않을 뿐 붙어 보인다.
SkBoardLayout solveSkBoardLayout({
  required Size size,
  required int opponentCount,
  required bool isLandscape,
  required bool spectator,
  double seatGap = 6,
}) {
  final width = size.width;
  final height = size.height;
  final angles = skSeatAnglesDeg(opponentCount, spectator: spectator);

  // 화면이 클수록 크게. 기준은 360×400 이고, 아주 작은 화면에서도 0.80 보다
  // 작아지지는 않게 둔다(그 아래로는 글자가 읽히지 않는다).
  final fitScale = math
      .min(width / 360.0, height / 400.0)
      .clamp(0.80, 1.55)
      .toDouble();

  final centerX = width / 2;
  final centerY = spectator
      ? (opponentCount >= 6 ? height * 0.46 : height * 0.44)
      : (isLandscape ? height * 0.42 : height * 0.46);

  SkBoardLayout build(double scale) {
    final seatW = kSkSeatWidthBase * scale;
    final seatH =
        (spectator ? kSkSpectatorSeatHeightBase : kSkSeatHeightBase) * scale;
    // 자리가 화면 밖으로 나가지 않는 선까지만 벌린다.
    final maxRx = math.max(0.0, centerX - seatW / 2 - 8);
    final maxRy = math.max(0.0, centerY - seatH / 2 - 6);
    final rx = math.min(width * _radiusXFactor(opponentCount), maxRx);
    final ry = math.min(height * (isLandscape ? 0.35 : 0.36), maxRy);
    return SkBoardLayout(
      size: size,
      opponentCount: opponentCount,
      isLandscape: isLandscape,
      spectator: spectator,
      seatWidth: seatW,
      seatHeight: seatH,
      playedCardHeight: kSkPlayedCardBase * scale,
      center: Offset(centerX, centerY),
      radiusX: rx,
      radiusY: ry,
      seatAnglesDeg: angles,
      scale: scale,
    );
  }

  var scale = fitScale;
  var layout = build(scale);
  // 겹치면 줄인다. 0.62 아래로는 더 줄여도 읽히지 않으므로 거기서 멈춘다 —
  // 그 지점까지 갔다면 자리 배치(각도 표) 쪽을 손봐야 한다는 뜻이다.
  var guard = 0;
  while (layout.overlappingPairs(gap: seatGap).isNotEmpty &&
      scale > 0.62 &&
      guard++ < 40) {
    scale = (scale - 0.02).clamp(0.62, 1.55).toDouble();
    layout = build(scale);
  }
  return layout;
}

double _radiusXFactor(int count) {
  if (count >= 5) return 0.44;
  if (count == 4) return 0.43;
  if (count == 3) return 0.40;
  return 0.38;
}
