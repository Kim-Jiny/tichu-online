import 'player.dart';
import '../widgets/tichu_effects.dart' show TichuFxKind;

/// 화면에 띄울 연출 하나가 "무슨 일" 인지만 담는다. 문구는 화면이 번역해서 만든다.
class TichuFxSignal {
  const TichuFxSignal(
    this.kind,
    this.name, {
    this.large = false,
    this.rank = 0,
  });

  final TichuFxKind kind;
  final String name;

  /// 라지 티츄인지 (아니면 스몰). 티츄와 무관한 연출에선 쓰지 않는다.
  final bool large;

  /// 패를 턴 순번. [TichuFxKind.finished] 에서만 쓴다.
  final int rank;
}

class _Snap {
  const _Snap(this.small, this.large, this.finish);
  final bool small;
  final bool large;
  final int finish;
}

/// 직전 상태와 지금 상태를 비교해 막 일어난 일을 찾아낸다.
///
/// 서버는 매번 판 전체 상태를 보내므로, "선언했다/털었다" 같은 사건은 상태가
/// 바뀌는 순간을 우리가 잡아야 한다. 처음 받은 상태(입장·재접속)는 기준으로만
/// 삼고 연출은 내지 않는다 — 이미 지난 일을 다시 틀면 이상하다.
class TichuFxDetector {
  Map<String, _Snap>? _prev;

  /// 재접속처럼 상태가 한 번에 건너뛰는 때: 다음 상태를 새 기준으로 삼는다.
  void reset() => _prev = null;

  /// [teamOf] 는 플레이어가 속한 팀을 돌려준다. 원투 판정에만 쓴다.
  List<TichuFxSignal> update(
    List<Player> players,
    String Function(Player) teamOf,
  ) {
    final now = <String, _Snap>{
      for (final p in players)
        p.id: _Snap(p.hasSmallTichu, p.hasLargeTichu, p.finishPosition),
    };
    final prev = _prev;
    _prev = now;
    if (prev == null) return const [];

    final out = <TichuFxSignal>[];

    // 선언. 라지가 우선이라 같이 켜져 있어도 한 번만 낸다.
    for (final p in players) {
      final before = prev[p.id];
      if (before == null) continue;
      if (p.hasLargeTichu && !before.large) {
        out.add(TichuFxSignal(TichuFxKind.declareLarge, p.name, large: true));
      } else if (p.hasSmallTichu && !before.small && !p.hasLargeTichu) {
        out.add(TichuFxSignal(TichuFxKind.declareSmall, p.name));
      }
    }

    // 패를 턴 순서대로. 한 번에 둘이 털려도 순번 순으로 처리한다.
    final finishers =
        players
            .where(
              (p) => p.finishPosition > 0 && (prev[p.id]?.finish ?? -1) == 0,
            )
            .toList()
          ..sort((a, b) => a.finishPosition.compareTo(b.finishPosition));

    for (final p in finishers) {
      final rank = p.finishPosition;

      if (rank == 2) {
        final first = players.where((q) => q.finishPosition == 1);
        if (first.isNotEmpty && teamOf(first.first) == teamOf(p)) {
          out.add(TichuFxSignal(TichuFxKind.oneTwo, p.name));
        } else {
          out.add(TichuFxSignal(TichuFxKind.finished, p.name, rank: rank));
        }
      } else {
        out.add(TichuFxSignal(TichuFxKind.finished, p.name, rank: rank));
      }

      // 티츄는 선언한 본인이 1등으로 털어야 성공. 첫 번째로 털린 그 순간에 승패가
      // 정해지니 그때 선언한 사람 모두에게 결과를 알려 준다.
      if (rank == 1) {
        for (final d in players) {
          if (!d.hasLargeTichu && !d.hasSmallTichu) continue;
          out.add(
            TichuFxSignal(
              d.id == p.id ? TichuFxKind.tichuSuccess : TichuFxKind.tichuFail,
              d.name,
              large: d.hasLargeTichu,
            ),
          );
        }
      }
    }
    return out;
  }
}
