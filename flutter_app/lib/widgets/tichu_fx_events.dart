import '../l10n/app_localizations.dart';
import '../models/tichu_fx_detector.dart';
import 'tichu_effects.dart';

/// 판정된 사건([TichuFxSignal])을 화면에 띄울 배너 문구로 바꾼다.
/// 플레이 화면과 관전 화면이 같은 문구를 쓰도록 한 곳에 둔다.
///
/// [nextId] 는 배너마다 고유해야 하는 번호를 이어서 매긴다.
List<TichuFxEvent> buildTichuFxEvents(
  List<TichuFxSignal> signals,
  L10n l10n,
  int Function() nextId,
) {
  String score(TichuFxSignal s, {required bool plus}) {
    final n = s.large ? 200 : 100;
    return '${s.name}  ${plus ? '+' : '−'}$n';
  }

  final events = <TichuFxEvent>[];
  for (final s in signals) {
    final id = nextId();
    switch (s.kind) {
      case TichuFxKind.declareSmall:
        events.add(
          TichuFxEvent(
            id: id,
            kind: s.kind,
            title: l10n.gameFxSmallTichu,
            subtitle: s.name,
          ),
        );
      case TichuFxKind.declareLarge:
        events.add(
          TichuFxEvent(
            id: id,
            kind: s.kind,
            title: l10n.gameFxLargeTichu,
            subtitle: s.name,
          ),
        );
      case TichuFxKind.tichuSuccess:
        events.add(
          TichuFxEvent(
            id: id,
            kind: s.kind,
            title: s.large
                ? l10n.gameFxLargeTichuSuccess
                : l10n.gameFxSmallTichuSuccess,
            subtitle: score(s, plus: true),
          ),
        );
      case TichuFxKind.tichuFail:
        events.add(
          TichuFxEvent(
            id: id,
            kind: s.kind,
            title: s.large
                ? l10n.gameFxLargeTichuFail
                : l10n.gameFxSmallTichuFail,
            subtitle: score(s, plus: false),
          ),
        );
      case TichuFxKind.oneTwo:
        events.add(
          TichuFxEvent(
            id: id,
            kind: s.kind,
            title: l10n.gameFxOneTwo,
            subtitle: '+200',
          ),
        );
      case TichuFxKind.finished:
        events.add(
          TichuFxEvent(
            id: id,
            kind: s.kind,
            title: l10n.gameFxFinished(s.name),
            subtitle: l10n.gameFinishRank(s.rank),
          ),
        );
    }
  }
  // 큰 사건이 위로, "N등으로 털었다" 는 아래로.
  int weight(TichuFxKind k) => k == TichuFxKind.finished ? 1 : 0;
  events.sort((a, b) => weight(a.kind).compareTo(weight(b.kind)));
  return events;
}
