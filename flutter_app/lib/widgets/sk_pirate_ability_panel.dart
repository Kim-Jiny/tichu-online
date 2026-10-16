import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/sk_game_state.dart';
import '../theme/cartoon.dart';
import 'game_chrome.dart';

/// 해적 이름(id 의 번호 → 이름 키). 서버 `PIRATE_NAMES` 와 같아야 한다.
const skPirateByNumber = {
  '1': 'rascal',
  '2': 'rosie',
  '3': 'bendt',
  '4': 'harry',
  '5': 'juanita',
};

/// 카드 id → 해적 이름 키. 해적(번호 있는 것)이 아니면 null.
String? skPirateKeyOf(String cardId) {
  final m = RegExp(r'^sk_pirate_(\d+)$').firstMatch(cardId);
  return m == null ? null : skPirateByNumber[m.group(1)];
}

/// 해적 이름 키 → 카드 id(설명 화면의 그림용).
String skPirateCardId(String pirate) {
  for (final e in skPirateByNumber.entries) {
    if (e.value == pirate) return 'sk_pirate_${e.key}';
  }
  return 'sk_pirate_1';
}

String skPirateName(L10n l10n, String pirate) {
  switch (pirate) {
    case 'rascal':
      return l10n.skCardRascal;
    case 'rosie':
      return l10n.skCardRosie;
    case 'bendt':
      return l10n.skCardBendt;
    case 'harry':
      return l10n.skCardHarry;
    case 'juanita':
      return l10n.skCardJuanita;
    default:
      return l10n.skCardPirate;
  }
}

String skPirateAbilityDesc(L10n l10n, String pirate) {
  switch (pirate) {
    case 'rascal':
      return l10n.skAbilityDescRascal;
    case 'rosie':
      return l10n.skAbilityDescRosie;
    case 'bendt':
      return l10n.skAbilityDescBendt;
    case 'harry':
      return l10n.skAbilityDescHarry;
    case 'juanita':
      return l10n.skAbilityDescJuanita;
    default:
      return '';
  }
}

/// 카드 한 장을 그려 주는 함수(게임 화면의 `_buildCard` 를 넘겨 받는다).
typedef SkCardBuilder =
    Widget Function(String cardId, {double size, bool highlighted});

/// 트릭을 이긴 해적의 능력을 쓰는 사람에게 뜨는 선택 패널.
class SkAbilityPanel extends StatefulWidget {
  const SkAbilityPanel({
    super.key,
    required this.state,
    required this.buildCard,
    required this.onUse,
  });

  final SKGameStateData state;
  final SkCardBuilder buildCard;

  /// 능력마다 필요한 값만 채워서 부른다.
  final void Function({
    String? leaderId,
    List<String>? discard,
    int? wager,
    int? delta,
  })
  onUse;

  @override
  State<SkAbilityPanel> createState() => _SkAbilityPanelState();
}

class _SkAbilityPanelState extends State<SkAbilityPanel> {
  final Set<String> _picked = {};
  bool _sent = false; // 두 번 눌러 두 번 보내지 않게

  @override
  void didUpdateWidget(covariant SkAbilityPanel old) {
    super.didUpdateWidget(old);
    if (old.state.pendingAbility?.pirate !=
            widget.state.pendingAbility?.pirate ||
        old.state.round != widget.state.round ||
        old.state.trickNumber != widget.state.trickNumber) {
      _picked.clear();
      _sent = false;
    }
  }

  void _send({
    String? leaderId,
    List<String>? discard,
    int? wager,
    int? delta,
  }) {
    if (_sent) return;
    setState(() => _sent = true);
    widget.onUse(
      leaderId: leaderId,
      discard: discard,
      wager: wager,
      delta: delta,
    );
    // 서버가 거절하면(오류 배너) 패널이 그대로 남으니, 잠시 뒤 다시 누를 수 있게 푼다.
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _sent = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final ab = widget.state.pendingAbility;
    if (ab == null) return const SizedBox.shrink();
    final pirate = ab.pirate;
    final name = skPirateName(l10n, pirate);

    Widget body;
    switch (pirate) {
      case 'rosie':
        body = _rosie(l10n);
      case 'bendt':
        body = _bendt(l10n);
      case 'rascal':
        body = _rascal(l10n);
      case 'harry':
        body = _harry(l10n);
      default:
        body = _juanita(l10n);
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 420,
        maxHeight: MediaQuery.of(context).size.height * 0.82,
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 18),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: Cartoon.paper,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Cartoon.ink, width: 2.8),
          boxShadow: const [
            BoxShadow(color: Cartoon.ink, offset: Offset(0, 4)),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  widget.buildCard(skPirateCardId(pirate), size: 62),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      l10n.skAbilityTitle(name),
                      style: Cartoon.text(size: 21),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              body,
            ],
          ),
        ),
      ),
    );
  }

  Widget _prompt(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: Cartoon.userText(size: 14.5, weight: FontWeight.w700, height: 1.4),
    ),
  );

  Widget _rosie(L10n l10n) {
    final players = [...widget.state.players]
      ..sort(
        (a, b) =>
            (a.position == 'self' ? 0 : 1) - (b.position == 'self' ? 0 : 1),
      );
    return Column(
      children: [
        _prompt(l10n.skAbilityRosiePrompt),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in players)
              gameButton(
                p.position == 'self'
                    ? '${l10n.skAbilityMe} (${p.name})'
                    : p.name,
                _sent ? null : () => _send(leaderId: p.id),
                color: p.position == 'self' ? Cartoon.green : Cartoon.orange,
                height: 44,
                size: 16,
                hPad: 16,
              ),
          ],
        ),
      ],
    );
  }

  Widget _bendt(L10n l10n) {
    final need = widget.state.abilityDrawn.length;
    final hand = widget.state.myCards;
    return Column(
      children: [
        _prompt(l10n.skAbilityBendtPrompt(need)),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 14,
          children: [
            for (final id in hand)
              GestureDetector(
                onTap: _sent
                    ? null
                    : () => setState(() {
                        if (_picked.contains(id)) {
                          _picked.remove(id);
                        } else if (_picked.length < need) {
                          _picked.add(id);
                        }
                      }),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Opacity(
                        opacity: _picked.contains(id) ? 0.45 : 1,
                        child: widget.buildCard(
                          id,
                          size: 70,
                          highlighted: widget.state.abilityDrawn.contains(id),
                        ),
                      ),
                      if (_picked.contains(id))
                        const Positioned.fill(
                          child: Center(
                            child: Icon(
                              Icons.delete_outline_rounded,
                              color: Cartoon.red,
                              size: 30,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        gameButton(
          l10n.skAbilityBendtConfirm(_picked.length, need),
          (_sent || _picked.length != need)
              ? null
              : () => _send(discard: _picked.toList()),
          color: Cartoon.green,
        ),
      ],
    );
  }

  Widget _rascal(L10n l10n) {
    return Column(
      children: [
        _prompt(l10n.skAbilityRascalPrompt),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            gameButton(
              l10n.skAbilityRascalNone,
              _sent ? null : () => _send(wager: 0),
              color: const Color(0xFF9E9E9E),
              height: 44,
              size: 16,
            ),
            for (final w in const [10, 20])
              gameButton(
                l10n.skAbilityPoints(w),
                _sent ? null : () => _send(wager: w),
                color: w == 20 ? Cartoon.red : Cartoon.orange,
                height: 44,
                size: 16,
              ),
          ],
        ),
      ],
    );
  }

  Widget _harry(L10n l10n) {
    final self = widget.state.players.firstWhere(
      (p) => p.position == 'self',
      orElse: () => widget.state.players.first,
    );
    final bid = self.bid ?? 0;
    final max = widget.state.round;
    return Column(
      children: [
        _prompt(l10n.skAbilityHarryPrompt(bid)),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            gameButton(
              '-1  (${bid - 1})',
              (_sent || bid - 1 < 0) ? null : () => _send(delta: -1),
              color: Cartoon.orange,
              height: 44,
              size: 16,
            ),
            gameButton(
              l10n.skAbilityHarryKeep,
              _sent ? null : () => _send(delta: 0),
              color: const Color(0xFF9E9E9E),
              height: 44,
              size: 16,
            ),
            gameButton(
              '+1  (${bid + 1})',
              (_sent || bid + 1 > max) ? null : () => _send(delta: 1),
              color: Cartoon.green,
              height: 44,
              size: 16,
            ),
          ],
        ),
      ],
    );
  }

  Widget _juanita(L10n l10n) {
    return Column(
      children: [
        _prompt(l10n.skAbilityJuanitaPrompt),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 5,
          runSpacing: 12,
          children: [
            for (final id in widget.state.abilityUndealt)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: widget.buildCard(id, size: 52),
              ),
          ],
        ),
        const SizedBox(height: 10),
        gameButton(
          l10n.skAbilityConfirm,
          _sent ? null : () => _send(),
          color: Cartoon.green,
        ),
      ],
    );
  }
}
