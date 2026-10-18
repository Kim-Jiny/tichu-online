import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/screens/sk_board_layout.dart';

/// 보드 자리 배치를 숫자로 확인한다.
///
/// 좌석이 겹치는지는 인원수·각도·반지름·좌석 크기가 함께 정한다. 그래서
/// 크기를 조금 키우면 어떤 인원에서만 겹치는데, 2~6인 × 여러 화면을 사람이
/// 매번 눈으로 보기는 어렵다. 전수로 돌려 둔다.
void main() {
  // 실제로 쓰이는 화면들. 작은 폰부터 태블릿·가로까지.
  const screens = <(String, Size)>[
    ('작은 폰', Size(320, 568)),
    ('보통 폰', Size(390, 760)),
    ('큰 폰', Size(430, 932)),
    ('작은 태블릿', Size(600, 900)),
    ('태블릿', Size(834, 1112)),
    ('가로 폰', Size(760, 390)),
    ('가로 태블릿', Size(1112, 834)),
  ];

  group('자리가 겹치지 않는다', () {
    for (final spectator in [false, true]) {
      final who = spectator ? '관전' : '플레이어';
      // 플레이어는 상대 1~5명(2~6인 게임), 관전자는 2~6명 전원.
      final counts = spectator ? [2, 3, 4, 5, 6] : [1, 2, 3, 4, 5];
      for (final n in counts) {
        for (final (label, size) in screens) {
          test('$who · 상대 $n명 · $label', () {
            final isLandscape = size.width > size.height;
            final l = solveSkBoardLayout(
              size: size,
              opponentCount: n,
              isLandscape: isLandscape,
              spectator: spectator,
            );
            expect(
              l.overlappingPairs(gap: 6),
              isEmpty,
              reason:
                  '자리가 겹친다 (scale ${l.scale.toStringAsFixed(2)}, '
                  '좌석 ${l.seatWidth.toStringAsFixed(0)}×'
                  '${l.seatHeight.toStringAsFixed(0)})',
            );
            expect(l.outOfBoundsSeats(), isEmpty, reason: '자리가 보드 밖으로 나갔다');
            // 줄이다 바닥을 치면 각도 표를 손봐야 한다는 뜻이다.
            expect(
              l.scale,
              greaterThan(0.62),
              reason: '겹침을 피하려고 끝까지 줄어들었다 — 각도 배치를 봐야 한다',
            );
          });
        }
      }
    }
  });

  test('전보다 커졌다', () {
    // 이 작업의 목적이다. 보통 폰에서 예전 값(98×118, 카드 72)보다 커야 한다.
    final l = solveSkBoardLayout(
      size: const Size(390, 760),
      opponentCount: 3,
      isLandscape: false,
      spectator: false,
    );
    expect(l.seatWidth, greaterThan(98 * 1.083));
    expect(l.seatHeight, greaterThan(118 * 1.083));
    expect(l.playedCardHeight, greaterThan(72 * 1.083));
  });

  test('화면이 클수록 커진다', () {
    double seat(Size s) => solveSkBoardLayout(
      size: s,
      opponentCount: 3,
      isLandscape: s.width > s.height,
      spectator: false,
    ).seatWidth;
    expect(seat(const Size(600, 900)), greaterThan(seat(const Size(390, 760))));
    expect(seat(const Size(390, 760)), greaterThan(seat(const Size(320, 568))));
  });

  test('인원이 많아도 읽을 만한 크기는 남는다', () {
    for (final n in [4, 5]) {
      final l = solveSkBoardLayout(
        size: const Size(390, 760),
        opponentCount: n,
        isLandscape: false,
        spectator: false,
      );
      expect(
        l.seatWidth,
        greaterThan(84),
        reason: '상대 $n명에서 자리가 너무 작아졌다 (${l.seatWidth.toStringAsFixed(0)})',
      );
    }
  });

  test('각도 표의 길이가 인원수와 맞는다', () {
    for (final spectator in [false, true]) {
      for (var n = 1; n <= 6; n++) {
        expect(
          skSeatAnglesDeg(n, spectator: spectator).length,
          n,
          reason: 'spectator=$spectator n=$n',
        );
      }
    }
  });
}
