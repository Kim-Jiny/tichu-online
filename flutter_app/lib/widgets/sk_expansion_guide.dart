import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/cartoon.dart';
import 'sk_pirate_ability_panel.dart';

/// 이 방에 들어간 확장팩 카드를 한 장씩 보여 주는 시트.
///
/// 게임 화면과 방 대기실 양쪽에서 쓴다. 대기실에서 먼저 볼 수 있어야
/// 하는 이유는 간단하다 — 확장팩은 방을 만들 때 정해지고, 처음 보는
/// 카드가 무슨 일을 하는지는 그 카드가 트릭을 가져간 뒤가 아니라 그
/// 전에 알아야 쓸모가 있다.
///
/// 카드 그림을 [cardBuilder] 로 받는 이유: 게임 화면은 자기 카드 위젯
/// (테두리·그림자·이름표가 붙은 것)을 그대로 쓰고 싶어 하고, 대기실에는
/// 그 위젯이 없다. 넘기지 않으면 아래 기본 그림을 쓴다.
typedef SkGuideCardBuilder = Widget Function(String cardId, double size);

/// 시트에 들어갈 한 줄.
typedef SkGuideEntry = ({String cardId, String name, String desc});

/// [expansions] 에 든 확장팩의 설명 줄들.
///
/// 해적 능력 모드가 켜져 있으면 다섯 해적의 능력도 이어 붙인다 — 모드
/// 하나만 적어 두면 "무슨 능력이 있는지"는 여전히 모른다.
List<SkGuideEntry> skExpansionGuideEntries(L10n l10n, List<String> expansions) {
  final hasPirateAbilities = expansions.contains('pirate_abilities');
  return [
    for (final id in expansions)
      switch (id) {
        'kraken' => (
          cardId: 'sk_kraken',
          name: l10n.rulesSkExpKraken,
          // 크라켄과 흰고래가 함께 나왔을 때의 순서 규칙을 같이 적는다.
          // 둘 중 하나만 읽는 사람이 있으므로 양쪽에 모두 붙인다.
          desc:
              '${l10n.rulesSkExpKrakenDesc}\n\n${l10n.rulesSkExpCreatureOrder}',
        ),
        'white_whale' => (
          cardId: 'sk_white_whale',
          name: l10n.rulesSkExpWhiteWhale,
          desc:
              '${l10n.rulesSkExpWhiteWhaleDesc}\n\n${l10n.rulesSkExpCreatureOrder}',
        ),
        'loot' => (
          cardId: 'sk_loot_1',
          name: l10n.rulesSkExpLoot,
          desc: l10n.rulesSkExpLootDesc,
        ),
        'pirate_abilities' => (
          cardId: '',
          name: l10n.rulesSkExpPirate,
          desc: l10n.rulesSkExpPirateDesc,
        ),
        _ => (cardId: '', name: id, desc: ''),
      },
    if (hasPirateAbilities)
      for (final pirate in skPirateByNumber.values)
        (
          cardId: skPirateCardId(pirate),
          name: skPirateName(l10n, pirate),
          desc: skPirateAbilityDesc(l10n, pirate),
        ),
  ];
}

/// 확장팩 카드 안내를 연다. 보여 줄 것이 없으면 아무 일도 하지 않는다.
void showSkExpansionGuide(
  BuildContext context,
  List<String> expansions, {
  SkGuideCardBuilder? cardBuilder,
}) {
  final l10n = L10n.of(context);
  final entries = skExpansionGuideEntries(l10n, expansions);
  if (entries.isEmpty) return;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Cartoon.paper,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      side: BorderSide(color: Cartoon.ink, width: 2.5),
    ),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        // 화면을 꽉 채우지 않는다. isScrollControlled 를 켜면(목록이 길어도
        // 안에서 스크롤되게 하려면 필요하다) 시트가 위까지 올라붙어서,
        // 아래로 끌어내릴 손잡이도 바깥을 누를 여백도 보이지 않는다.
        // 토큰 내역 시트(token_widgets.dart)와 같은 비율이다.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.78,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Cartoon.ink.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              // 제목과 닫기 버튼. 끌어내리기와 바깥 누르기로도 닫히지만,
              // 그 둘은 눈에 보이지 않아서 한 번도 안 해 본 사람에게는
              // 닫는 방법이 없는 것과 같다.
              Row(
                children: [
                  // 닫기 버튼과 같은 너비를 왼쪽에 둬서 제목이 가운데 온다.
                  const SizedBox(width: 40),
                  Expanded(
                    child: Text(
                      l10n.skGameIncludedExpansions,
                      textAlign: TextAlign.center,
                      style: Cartoon.text(size: 19),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: IconButton(
                      icon: const Icon(Icons.close_rounded, size: 22),
                      color: Cartoon.ink,
                      tooltip: MaterialLocalizations.of(ctx).closeButtonLabel,
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final e = entries[i];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Cartoon.cream,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (e.cardId.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child:
                                  cardBuilder?.call(e.cardId, 86) ??
                                  _SkGuideCard(e.cardId),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(e.name, style: Cartoon.text(size: 17)),
                                if (e.desc.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    e.desc,
                                    style: Cartoon.userText(
                                      size: 13,
                                      color: Cartoon.ink.withValues(alpha: 0.8),
                                      weight: FontWeight.w600,
                                      height: 1.45,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 게임 화면 밖에서 쓰는 기본 카드 그림.
///
/// 카드 id 는 `sk_loot_1` 처럼 번호가 붙어 올 수 있는데 그림은 번호 없는
/// 한 장뿐이다(`sk_loot.webp`). 해적만 번호별로 그림이 다르다.
class _SkGuideCard extends StatelessWidget {
  const _SkGuideCard(this.cardId);

  final String cardId;

  String get _asset {
    // sk_pirate_3 → sk_pirate3 (해적은 번호마다 그림이 다르다)
    final pirate = RegExp(r'^sk_pirate_(\d+)$').firstMatch(cardId);
    if (pirate != null) return 'assets/cards/sk_pirate${pirate.group(1)}.webp';
    // sk_loot_1 / sk_escape_2 → 번호를 떼고 한 장을 쓴다
    final numbered = RegExp(r'^(sk_[a-z_]+?)_\d+$').firstMatch(cardId);
    final base = numbered != null ? numbered.group(1)! : cardId;
    return 'assets/cards/$base.webp';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 86,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Cartoon.ink, width: 2),
        boxShadow: const [BoxShadow(color: Cartoon.ink, offset: Offset(0, 2))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        _asset,
        fit: BoxFit.cover,
        // 그림이 없으면 빈 칸 대신 종이색을 둔다 — 시트가 깨져 보이지 않게.
        errorBuilder: (_, _, _) => Container(color: Cartoon.paper),
      ),
    );
  }
}
