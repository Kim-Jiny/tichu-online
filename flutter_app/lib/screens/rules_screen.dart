import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../services/game_service.dart';
import '../widgets/game_type_icon.dart';
import '../widgets/playing_card.dart';

/// Rules / "게임설명" screen — accessible from the lobby header.
/// Shows Tichu and Skull King rules with exact card counts. The Skull King
/// tab also lists the optional expansions (Kraken / White Whale / Loot) with
/// their card counts so players understand what a room creator is enabling.
class RulesScreen extends StatefulWidget {
  const RulesScreen({super.key});

  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen> {
  String _selectedGame = 'tichu';

  @override
  Widget build(BuildContext context) {
    final themeColors = context.watch<GameService>().themeGradient;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: themeColors,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header with back button and title
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back),
                      color: const Color(0xFF8A7A72),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      L10n.of(context).rulesTitle,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF5A4038),
                      ),
                    ),
                  ],
                ),
              ),
              // Game selector chip — tapping opens a bottom sheet
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GestureDetector(
                  onTap: () => _showGamePicker(),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE0D8D4)),
                    ),
                    child: Row(
                      children: [
                        gameTypeSymbol(_selectedGame, size: 28),
                        const SizedBox(width: 10),
                        Text(
                          _gameLabel(_selectedGame),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _gameColor(_selectedGame),
                          ),
                        ),
                        const Spacer(),
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Color(0xFF8A7A72),
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: switch (_selectedGame) {
                    'tichu' => _buildTichuRules(),
                    'skull_king' => _buildSkullKingRules(),
                    'love_letter' => _buildLoveLetterRules(),
                    'mighty' => _buildMightyRules(),
                    _ => _buildTichuRules(),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Game picker helpers ───────────────────────────────────────────────────

  static const _games = ['tichu', 'skull_king', 'love_letter', 'mighty'];

  Color _gameColor(String key) => gameTypeColor(key);

  String _gameLabel(String key) => switch (key) {
    'tichu' => L10n.of(context).rulesTabTichu,
    'skull_king' => L10n.of(context).rulesTabSkullKing,
    'love_letter' => L10n.of(context).rulesTabLoveLetter,
    'mighty' => L10n.of(context).rulesTabMighty,
    _ => '',
  };

  void _showGamePicker() {
    showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD0C8C4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              for (final key in _games)
                _GamePickerTile(
                  gameKey: key,
                  color: _gameColor(key),
                  label: _gameLabel(key),
                  selected: key == _selectedGame,
                  onTap: () {
                    Navigator.pop(ctx, key);
                    setState(() => _selectedGame = key);
                  },
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  // ─── TICHU ─────────────────────────────────────────────────────────────────

  Widget _buildTichuRules() {
    const tichuAccent = Color(0xFF6C63FF);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(
          icon: Icons.flag,
          iconColor: tichuAccent,
          title: L10n.of(context).rulesTichuGoalTitle,
          art: 'assets/cards/dragon.webp',
          child: _RuleText(L10n.of(context).rulesTichuGoalBody),
        ),
        _section(
          icon: Icons.style,
          iconColor: tichuAccent,
          title: L10n.of(context).rulesTichuCardCompositionTitle,
          art: 'assets/icons/tichuSymbol.webp',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardCountRow(
                label: L10n.of(context).rulesTichuNumberCards,
                sub: L10n.of(context).rulesTichuNumberCardsSub,
                count: 52,
              ),
              const _Divider(),
              _CardCountRow(
                label: L10n.of(context).rulesTichuMahjong,
                sub: L10n.of(context).rulesTichuMahjongSub,
                count: 1,
                leading: _cardAsset('assets/cards/bird.webp'),
              ),
              const _Divider(),
              _CardCountRow(
                label: L10n.of(context).rulesTichuDog,
                sub: L10n.of(context).rulesTichuDogSub,
                count: 1,
                leading: _cardAsset('assets/cards/dog.webp'),
              ),
              const _Divider(),
              _CardCountRow(
                label: L10n.of(context).rulesTichuPhoenix,
                sub: L10n.of(context).rulesTichuPhoenixSub,
                count: 1,
                leading: _cardAsset('assets/cards/phoenix.webp'),
              ),
              const _Divider(),
              _CardCountRow(
                label: L10n.of(context).rulesTichuDragon,
                sub: L10n.of(context).rulesTichuDragonSub,
                count: 1,
                leading: _cardAsset('assets/cards/dragon.webp'),
              ),
            ],
          ),
        ),
        _section(
          icon: Icons.auto_awesome,
          iconColor: tichuAccent,
          title: L10n.of(context).rulesTichuSpecialTitle,
          art: 'assets/cards/phoenix.webp',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SpecialRule(
                emoji: '🐦',
                title: L10n.of(context).rulesTichuSpecialMahjongTitle,
                leadingAsset: 'assets/cards/bird.webp',
                lines: [
                  L10n.of(context).rulesTichuSpecialMahjongLine1,
                  L10n.of(context).rulesTichuSpecialMahjongLine2,
                ],
              ),
              const SizedBox(height: 10),
              _SpecialRule(
                emoji: '🐶',
                title: L10n.of(context).rulesTichuSpecialDogTitle,
                leadingAsset: 'assets/cards/dog.webp',
                lines: [
                  L10n.of(context).rulesTichuSpecialDogLine1,
                  L10n.of(context).rulesTichuSpecialDogLine2,
                ],
              ),
              const SizedBox(height: 10),
              _SpecialRule(
                emoji: '🔥',
                title: L10n.of(context).rulesTichuSpecialPhoenixTitle,
                leadingAsset: 'assets/cards/phoenix.webp',
                lines: [
                  L10n.of(context).rulesTichuSpecialPhoenixLine1,
                  L10n.of(context).rulesTichuSpecialPhoenixLine2,
                  L10n.of(context).rulesTichuSpecialPhoenixLine3,
                ],
              ),
              const SizedBox(height: 10),
              _SpecialRule(
                emoji: '🐉',
                title: L10n.of(context).rulesTichuSpecialDragonTitle,
                leadingAsset: 'assets/cards/dragon.webp',
                lines: [
                  L10n.of(context).rulesTichuSpecialDragonLine1,
                  L10n.of(context).rulesTichuSpecialDragonLine2,
                ],
              ),
            ],
          ),
        ),
        _section(
          icon: Icons.campaign,
          iconColor: tichuAccent,
          title: L10n.of(context).rulesTichuDeclarationTitle,
          art: 'assets/cards/bird.webp',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RuleText(L10n.of(context).rulesTichuDeclarationBody),
              const SizedBox(height: 10),
              _TichuDeclarationRow(
                title: L10n.of(context).rulesTichuLargeTichu,
                when: L10n.of(context).rulesTichuLargeTichuWhen,
                success: '+200',
                fail: '-200',
                accent: const Color(0xFFD32F2F),
              ),
              const SizedBox(height: 8),
              _TichuDeclarationRow(
                title: L10n.of(context).rulesTichuSmallTichu,
                when: L10n.of(context).rulesTichuSmallTichuWhen,
                success: '+100',
                fail: '-100',
                accent: const Color(0xFFFF8F00),
              ),
            ],
          ),
        ),
        _section(
          icon: Icons.format_list_numbered,
          iconColor: tichuAccent,
          title: L10n.of(context).rulesTichuFlowTitle,
          art: 'assets/cards/dog.webp',
          child: _RuleText(L10n.of(context).rulesTichuFlowBody),
        ),
        _section(
          icon: Icons.layers,
          iconColor: tichuAccent,
          title: L10n.of(context).rulesTichuPlayTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RuleText(L10n.of(context).rulesTichuPlayBody),
              const SizedBox(height: 14),
              _ComboRow(
                label: L10n.of(context).rulesTichuComboSingle,
                cards: const ['heart_K'],
              ),
              _ComboRow(
                label: L10n.of(context).rulesTichuComboPair,
                cards: const ['spade_9', 'heart_9'],
              ),
              _ComboRow(
                label: L10n.of(context).rulesTichuComboTriple,
                cards: const ['spade_6', 'heart_6', 'club_6'],
              ),
              _ComboRow(
                label: L10n.of(context).rulesTichuComboFullHouse,
                cards: const [
                  'spade_J',
                  'heart_J',
                  'club_J',
                  'spade_4',
                  'heart_4',
                ],
              ),
              _ComboRow(
                label: L10n.of(context).rulesTichuComboStraight,
                cards: const [
                  'spade_5',
                  'heart_6',
                  'club_7',
                  'diamond_8',
                  'spade_9',
                ],
              ),
              _ComboRow(
                label: L10n.of(context).rulesTichuComboPairSeq,
                cards: const ['spade_7', 'heart_7', 'spade_8', 'club_8'],
              ),
            ],
          ),
        ),
        _section(
          icon: Icons.local_fire_department,
          iconColor: const Color(0xFFE53935),
          title: L10n.of(context).rulesTichuBombTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ComboRow(
                label: L10n.of(context).rulesTichuComboBombFour,
                cards: const ['spade_10', 'heart_10', 'diamond_10', 'club_10'],
                accent: const Color(0xFFE53935),
              ),
              _ComboRow(
                label: L10n.of(context).rulesTichuComboBombStraightFlush,
                cards: const [
                  'spade_5',
                  'spade_6',
                  'spade_7',
                  'spade_8',
                  'spade_9',
                ],
                accent: const Color(0xFFE53935),
              ),
              const SizedBox(height: 4),
              _RuleText(L10n.of(context).rulesTichuBombBody),
            ],
          ),
        ),
        _section(
          icon: Icons.calculate,
          iconColor: tichuAccent,
          title: L10n.of(context).rulesTichuScoringTitle,
          child: _RuleText(L10n.of(context).rulesTichuScoringBody),
        ),
        _section(
          icon: Icons.emoji_events,
          iconColor: tichuAccent,
          title: L10n.of(context).rulesTichuWinTitle,
          art: 'assets/icons/crown.webp',
          child: _RuleText(L10n.of(context).rulesTichuWinBody),
        ),
      ],
    );
  }

  // ─── SKULL KING ────────────────────────────────────────────────────────────

  Widget _buildSkullKingRules() {
    const skAccent = Color(0xFF2D2D3D);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(
          icon: Icons.flag,
          iconColor: skAccent,
          title: L10n.of(context).rulesSkGoalTitle,
          art: 'assets/cards/sk_skull_king.webp',
          child: _RuleText(L10n.of(context).rulesSkGoalBody),
        ),
        _section(
          icon: Icons.style,
          iconColor: skAccent,
          title: L10n.of(context).rulesSkCardCompositionTitle,
          art: 'assets/cards/sk_card_back.webp',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardCountRow(
                label: L10n.of(context).rulesSkNumberCards,
                sub: L10n.of(context).rulesSkNumberCardsSub,
                count: 52,
              ),
              const _Divider(),
              _CardCountRow(
                label: L10n.of(context).rulesSkEscape,
                sub: L10n.of(context).rulesSkEscapeSub,
                count: 5,
                leading: _cardAsset('assets/cards/sk_escape.webp'),
              ),
              const _Divider(),
              _CardCountRow(
                label: L10n.of(context).rulesSkPirate,
                sub: L10n.of(context).rulesSkPirateSub,
                count: 4,
                leading: _cardAsset('assets/cards/sk_pirate.webp'),
              ),
              const _Divider(),
              _CardCountRow(
                label: L10n.of(context).rulesSkMermaid,
                sub: L10n.of(context).rulesSkMermaidSub,
                count: 2,
                leading: _cardAsset('assets/cards/sk_mermaid.webp'),
              ),
              const _Divider(),
              _CardCountRow(
                label: L10n.of(context).rulesSkSkullKing,
                sub: L10n.of(context).rulesSkSkullKingSub,
                count: 1,
                leading: _cardAsset('assets/cards/sk_skull_king.webp'),
              ),
              const _Divider(),
              _CardCountRow(
                label: L10n.of(context).rulesSkTigress,
                sub: L10n.of(context).rulesSkTigressSub,
                count: 1,
                leading: _cardAsset('assets/cards/sk_tigress.webp'),
                highlight: true,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF212121).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF212121).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.local_fire_department,
                      color: Color(0xFF212121),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: Color(0xFF3E312A),
                          ),
                          children: [
                            TextSpan(
                              text: '${L10n.of(context).rulesSkTrumpTitle}\n',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF212121),
                              ),
                            ),
                            TextSpan(text: L10n.of(context).rulesSkTrumpBody),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _section(
          icon: Icons.auto_awesome,
          iconColor: skAccent,
          title: L10n.of(context).rulesSkSpecialTitle,
          art: 'assets/cards/sk_pirate.webp',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SpecialRule(
                emoji: '🏳️',
                title: L10n.of(context).rulesSkSpecialEscapeTitle,
                leadingAsset: 'assets/cards/sk_escape.webp',
                lines: [
                  L10n.of(context).rulesSkSpecialEscapeLine1,
                  L10n.of(context).rulesSkSpecialEscapeLine2,
                ],
              ),
              const SizedBox(height: 10),
              _SpecialRule(
                emoji: '⚔️',
                title: L10n.of(context).rulesSkSpecialPirateTitle,
                leadingAsset: 'assets/cards/sk_pirate.webp',
                lines: [
                  L10n.of(context).rulesSkSpecialPirateLine1,
                  L10n.of(context).rulesSkSpecialPirateLine2,
                ],
              ),
              const SizedBox(height: 10),
              _SpecialRule(
                emoji: '🧜\u200d♀️',
                title: L10n.of(context).rulesSkSpecialMermaidTitle,
                leadingAsset: 'assets/cards/sk_mermaid.webp',
                lines: [
                  L10n.of(context).rulesSkSpecialMermaidLine1,
                  L10n.of(context).rulesSkSpecialMermaidLine2,
                  L10n.of(context).rulesSkSpecialMermaidLine3,
                ],
              ),
              const SizedBox(height: 10),
              _SpecialRule(
                emoji: '☠️',
                title: L10n.of(context).rulesSkSpecialSkullKingTitle,
                leadingAsset: 'assets/cards/sk_skull_king.webp',
                lines: [
                  L10n.of(context).rulesSkSpecialSkullKingLine1,
                  L10n.of(context).rulesSkSpecialSkullKingLine2,
                ],
              ),
              const SizedBox(height: 10),
              _SpecialRule(
                emoji: '🐯',
                title: L10n.of(context).rulesSkSpecialTigressTitle,
                leadingAsset: 'assets/cards/sk_tigress.webp',
                lines: [
                  L10n.of(context).rulesSkSpecialTigressLine1,
                  L10n.of(context).rulesSkSpecialTigressLine2,
                  L10n.of(context).rulesSkSpecialTigressLine3,
                  L10n.of(context).rulesSkSpecialTigressLine4,
                ],
                extra: const _TigressDisplayPreview(),
              ),
            ],
          ),
        ),
        _section(
          icon: Icons.format_list_numbered,
          iconColor: skAccent,
          title: L10n.of(context).rulesSkFlowTitle,
          art: 'assets/cards/sk_escape.webp',
          child: _RuleText(L10n.of(context).rulesSkFlowBody),
        ),
        _section(
          icon: Icons.visibility,
          iconColor: skAccent,
          title: L10n.of(context).rulesSkLeadDemoTitle,
          art: 'assets/cards/sk_tigress.webp',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FlowDemo(
                cards: const [
                  _SkMini.special('escape'),
                  _SkMini.number('purple', '5'),
                  _SkMini.next(),
                ],
                caption: L10n.of(context).rulesSkLeadDemoEscape,
                tag: L10n.of(context).rulesSkLeadDemoEscapeTag,
                tagColor: const Color(0xFF6A1B9A),
              ),
              const SizedBox(height: 10),
              _FlowDemo(
                cards: const [
                  _SkMini.special('pirate'),
                  _SkMini.number('purple', '5'),
                  _SkMini.next(),
                ],
                caption: L10n.of(context).rulesSkLeadDemoPirate,
                tag: L10n.of(context).rulesSkLeadDemoPirateTag,
                tagColor: const Color(0xFF455A64),
              ),
              const SizedBox(height: 10),
              _FlowDemo(
                cards: const [
                  _SkMini.special('loot'),
                  _SkMini.number('purple', '9'),
                ],
                caption: L10n.of(context).rulesSkLootDemo,
                tag: L10n.of(context).rulesSkLootDemoTag,
                tagColor: const Color(0xFF2E7D32),
              ),
            ],
          ),
        ),
        _section(
          icon: Icons.calculate,
          iconColor: skAccent,
          title: L10n.of(context).rulesSkScoringTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RuleText(L10n.of(context).rulesSkScoringBody),
              const SizedBox(height: 12),
              _ExampleBlock(
                title: L10n.of(context).rulesSkExample1Title,
                setup: L10n.of(context).rulesSkExample1Setup,
                calc: L10n.of(context).rulesSkExample1Calc,
                result: L10n.of(context).rulesSkExample1Result,
                positive: true,
              ),
              const SizedBox(height: 8),
              _ExampleBlock(
                title: L10n.of(context).rulesSkExample2Title,
                setup: L10n.of(context).rulesSkExample2Setup,
                calc: L10n.of(context).rulesSkExample2Calc,
                result: L10n.of(context).rulesSkExample2Result,
                positive: true,
              ),
              const SizedBox(height: 8),
              _ExampleBlock(
                title: L10n.of(context).rulesSkExample3Title,
                setup: L10n.of(context).rulesSkExample3Setup,
                calc: L10n.of(context).rulesSkExample3Calc,
                result: L10n.of(context).rulesSkExample3Result,
                positive: false,
              ),
              const SizedBox(height: 8),
              _ExampleBlock(
                title: L10n.of(context).rulesSkExample4Title,
                setup: L10n.of(context).rulesSkExample4Setup,
                calc: L10n.of(context).rulesSkExample4Calc,
                result: L10n.of(context).rulesSkExample4Result,
                positive: true,
              ),
              const SizedBox(height: 8),
              _ExampleBlock(
                title: L10n.of(context).rulesSkExample5Title,
                setup: L10n.of(context).rulesSkExample5Setup,
                calc: L10n.of(context).rulesSkExample5Calc,
                result: L10n.of(context).rulesSkExample5Result,
                positive: true,
              ),
              const SizedBox(height: 8),
              _ExampleBlock(
                title: L10n.of(context).rulesSkExample6Title,
                setup: L10n.of(context).rulesSkExample6Setup,
                calc: L10n.of(context).rulesSkExample6Calc,
                result: L10n.of(context).rulesSkExample6Result,
                positive: false,
              ),
            ],
          ),
        ),
        _section(
          icon: Icons.emoji_events,
          iconColor: const Color(0xFF2D2D3D),
          title: L10n.of(context).rulesSkWinTitle,
          art: 'assets/icons/crown.webp',
          child: _RuleText(L10n.of(context).rulesSkWinBody),
        ),
        _section(
          icon: Icons.extension,
          iconColor: const Color(0xFFFF8A65),
          title: L10n.of(context).rulesSkExpansionTitle,
          art: 'assets/cards/sk_kraken.webp',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RuleText(L10n.of(context).rulesSkExpansionBody),
              const SizedBox(height: 12),
              _expansionCard(
                assetPath: 'assets/cards/sk_kraken.webp',
                title: L10n.of(context).rulesSkExpKraken,
                count: 1,
                description: L10n.of(context).rulesSkExpKrakenDesc,
                color: const Color(0xFF2B1E3F),
              ),
              const SizedBox(height: 10),
              _expansionCard(
                assetPath: 'assets/cards/sk_white_whale.webp',
                title: L10n.of(context).rulesSkExpWhiteWhale,
                count: 1,
                description: L10n.of(context).rulesSkExpWhiteWhaleDesc,
                color: const Color(0xFF3A6B8F),
              ),
              const SizedBox(height: 10),
              _expansionCard(
                assetPath: 'assets/cards/sk_loot.webp',
                title: L10n.of(context).rulesSkExpLoot,
                count: 2,
                description: L10n.of(context).rulesSkExpLootDesc,
                color: const Color(0xFF8B6F22),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── LOVE LETTER ──────────────────────────────────────────────────────────

  Widget _buildLoveLetterRules() {
    const llAccent = Color(0xFFE91E63);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(
          icon: Icons.flag,
          iconColor: llAccent,
          title: L10n.of(context).rulesLlGoalTitle,
          art: 'assets/cards/ll_Princess.webp',
          child: _RuleText(L10n.of(context).rulesLlGoalBody),
        ),
        _section(
          icon: Icons.style,
          iconColor: llAccent,
          title: L10n.of(context).rulesLlCardCompositionTitle,
          art: 'assets/icons/llSymbol.webp',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardCountRow(
                label: L10n.of(context).rulesLlGuard,
                sub: L10n.of(context).rulesLlGuardSub,
                count: 5,
                leading: _cardAsset('assets/cards/ll_Guard.webp'),
              ),
              const _Divider(),
              _CardCountRow(
                label: L10n.of(context).rulesLlSpy,
                sub: L10n.of(context).rulesLlSpySub,
                count: 2,
                leading: _cardAsset('assets/cards/ll_Spy.webp'),
              ),
              const _Divider(),
              _CardCountRow(
                label: L10n.of(context).rulesLlBaron,
                sub: L10n.of(context).rulesLlBaronSub,
                count: 2,
                leading: _cardAsset('assets/cards/ll_Baron.webp'),
              ),
              const _Divider(),
              _CardCountRow(
                label: L10n.of(context).rulesLlHandmaid,
                sub: L10n.of(context).rulesLlHandmaidSub,
                count: 2,
                leading: _cardAsset('assets/cards/ll_Handmaid.webp'),
              ),
              const _Divider(),
              _CardCountRow(
                label: L10n.of(context).rulesLlPrince,
                sub: L10n.of(context).rulesLlPrinceSub,
                count: 2,
                leading: _cardAsset('assets/cards/ll_Prince.webp'),
              ),
              const _Divider(),
              _CardCountRow(
                label: L10n.of(context).rulesLlKing,
                sub: L10n.of(context).rulesLlKingSub,
                count: 1,
                leading: _cardAsset('assets/cards/ll_King.webp'),
              ),
              const _Divider(),
              _CardCountRow(
                label: L10n.of(context).rulesLlCountess,
                sub: L10n.of(context).rulesLlCountessSub,
                count: 1,
                leading: _cardAsset('assets/cards/ll_Countess.webp'),
              ),
              const _Divider(),
              _CardCountRow(
                label: L10n.of(context).rulesLlPrincess,
                sub: L10n.of(context).rulesLlPrincessSub,
                count: 1,
                leading: _cardAsset('assets/cards/ll_Princess.webp'),
              ),
            ],
          ),
        ),
        _section(
          icon: Icons.auto_awesome,
          iconColor: llAccent,
          title: L10n.of(context).rulesLlCardEffectsTitle,
          art: 'assets/cards/ll_Prince.webp',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SpecialRule(
                emoji: '\u{1F6E1}\u{FE0F}',
                title: L10n.of(context).rulesLlEffectGuardTitle,
                leadingAsset: 'assets/cards/ll_Guard.webp',
                lines: [
                  L10n.of(context).rulesLlEffectGuardLine1,
                  L10n.of(context).rulesLlEffectGuardLine2,
                ],
              ),
              const SizedBox(height: 10),
              _SpecialRule(
                emoji: '\u{1F50D}',
                title: L10n.of(context).rulesLlEffectSpyTitle,
                leadingAsset: 'assets/cards/ll_Spy.webp',
                lines: [L10n.of(context).rulesLlEffectSpyLine1],
              ),
              const SizedBox(height: 10),
              _SpecialRule(
                emoji: '\u{2694}\u{FE0F}',
                title: L10n.of(context).rulesLlEffectBaronTitle,
                leadingAsset: 'assets/cards/ll_Baron.webp',
                lines: [
                  L10n.of(context).rulesLlEffectBaronLine1,
                  L10n.of(context).rulesLlEffectBaronLine2,
                ],
              ),
              const SizedBox(height: 10),
              _SpecialRule(
                emoji: '\u{1F9D1}\u{200D}\u{1F91D}\u{200D}\u{1F9D1}',
                title: L10n.of(context).rulesLlEffectHandmaidTitle,
                leadingAsset: 'assets/cards/ll_Handmaid.webp',
                lines: [L10n.of(context).rulesLlEffectHandmaidLine1],
              ),
              const SizedBox(height: 10),
              _SpecialRule(
                emoji: '\u{1F451}',
                title: L10n.of(context).rulesLlEffectPrinceTitle,
                leadingAsset: 'assets/cards/ll_Prince.webp',
                lines: [
                  L10n.of(context).rulesLlEffectPrinceLine1,
                  L10n.of(context).rulesLlEffectPrinceLine2,
                ],
              ),
              const SizedBox(height: 10),
              _SpecialRule(
                emoji: '\u{1F934}',
                title: L10n.of(context).rulesLlEffectKingTitle,
                leadingAsset: 'assets/cards/ll_King.webp',
                lines: [L10n.of(context).rulesLlEffectKingLine1],
              ),
              const SizedBox(height: 10),
              _SpecialRule(
                emoji: '\u{1F483}',
                title: L10n.of(context).rulesLlEffectCountessTitle,
                leadingAsset: 'assets/cards/ll_Countess.webp',
                lines: [
                  L10n.of(context).rulesLlEffectCountessLine1,
                  L10n.of(context).rulesLlEffectCountessLine2,
                ],
              ),
              const SizedBox(height: 10),
              _SpecialRule(
                emoji: '\u{1F478}',
                title: L10n.of(context).rulesLlEffectPrincessTitle,
                leadingAsset: 'assets/cards/ll_Princess.webp',
                lines: [L10n.of(context).rulesLlEffectPrincessLine1],
              ),
            ],
          ),
        ),
        _section(
          icon: Icons.format_list_numbered,
          iconColor: llAccent,
          title: L10n.of(context).rulesLlFlowTitle,
          art: 'assets/cards/ll_Handmaid.webp',
          child: _RuleText(L10n.of(context).rulesLlFlowBody),
        ),
        _section(
          icon: Icons.emoji_events,
          iconColor: llAccent,
          title: L10n.of(context).rulesLlWinTitle,
          art: 'assets/icons/crown.webp',
          child: _RuleText(L10n.of(context).rulesLlWinBody),
        ),
      ],
    );
  }

  // ─── MIGHTY ──────────────────────────────────────────────────────────────

  Widget _buildMightyRules() {
    const mtAccent = Color(0xFF1565C0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(
          icon: Icons.flag,
          iconColor: mtAccent,
          title: L10n.of(context).rulesMtGoalTitle,
          art: 'assets/icons/mtSymbol.webp',
          child: _RuleText(L10n.of(context).rulesMtGoalBody),
        ),
        _section(
          icon: Icons.style,
          iconColor: mtAccent,
          title: L10n.of(context).rulesMtCardCompositionTitle,
          art: 'assets/icons/mtSymbol.webp',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _MightyDeckPreview(),
              const SizedBox(height: 8),
              _RuleText(L10n.of(context).rulesMtCardCompositionBody),
            ],
          ),
        ),
        _section(
          icon: Icons.auto_awesome,
          iconColor: mtAccent,
          title: L10n.of(context).rulesMtSpecialTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SpecialRule(
                emoji: '\u{1F451}',
                title: L10n.of(context).rulesMtSpecialMightyTitle,
                lines: [
                  L10n.of(context).rulesMtSpecialMightyLine1,
                  L10n.of(context).rulesMtSpecialMightyLine2,
                ],
                cardId: 'mighty_spade_A',
                altCardId: 'mighty_diamond_A',
                altCardLabel: L10n.of(context).rulesMtSpecialMightyAltLabel,
                // Matches the yellow star badge used on the mighty card in play.
                badgeIcon: Icons.star,
                badgeColor: const Color(0xFFFFB300),
              ),
              const SizedBox(height: 10),
              _SpecialRule(
                emoji: '\u{1F0CF}',
                title: L10n.of(context).rulesMtSpecialJokerTitle,
                lines: [
                  L10n.of(context).rulesMtSpecialJokerLine1,
                  L10n.of(context).rulesMtSpecialJokerLine2,
                ],
                cardId: 'mighty_joker',
                // The joker doesn't carry an in-game corner badge, but a
                // small purple mark here helps readers match the rule to
                // the joker artwork.
                badgeIcon: Icons.auto_awesome,
                badgeColor: const Color(0xFF7B1FA2),
              ),
              const SizedBox(height: 10),
              _SpecialRule(
                emoji: '\u{1F4E2}',
                title: L10n.of(context).rulesMtSpecialJokerCallTitle,
                lines: [
                  L10n.of(context).rulesMtSpecialJokerCallLine1,
                  L10n.of(context).rulesMtSpecialJokerCallLine2,
                ],
                cardId: 'mighty_club_3',
                // Matches the red gps_fixed badge on the joker-call card in play.
                badgeIcon: Icons.gps_fixed,
                badgeColor: const Color(0xFFE53935),
              ),
            ],
          ),
        ),
        _section(
          icon: Icons.gavel,
          iconColor: mtAccent,
          title: L10n.of(context).rulesMtBiddingTitle,
          child: _RuleText(L10n.of(context).rulesMtBiddingBody),
        ),
        _section(
          icon: Icons.block,
          iconColor: mtAccent,
          title: L10n.of(context).rulesMtDealMissTitle,
          child: _RuleText(L10n.of(context).rulesMtDealMissBody),
        ),
        _section(
          icon: Icons.gps_fixed,
          iconColor: mtAccent,
          title: L10n.of(context).rulesMtKillTitle,
          child: _RuleText(L10n.of(context).rulesMtKillBody),
        ),
        _section(
          icon: Icons.people,
          iconColor: mtAccent,
          title: L10n.of(context).rulesMtFriendTitle,
          child: _RuleText(L10n.of(context).rulesMtFriendBody),
        ),
        _section(
          icon: Icons.swap_horiz,
          iconColor: mtAccent,
          title: L10n.of(context).rulesMtKittyTitle,
          child: _RuleText(L10n.of(context).rulesMtKittyBody),
        ),
        _section(
          icon: Icons.format_list_numbered,
          iconColor: mtAccent,
          title: L10n.of(context).rulesMtTrickTitle,
          child: _RuleText(L10n.of(context).rulesMtTrickBody),
        ),
        _section(
          icon: Icons.calculate,
          iconColor: mtAccent,
          title: L10n.of(context).rulesMtScoringTitle,
          child: _RuleText(L10n.of(context).rulesMtScoringBody),
        ),
        _section(
          icon: Icons.emoji_events,
          iconColor: mtAccent,
          title: L10n.of(context).rulesMtWinTitle,
          art: 'assets/icons/crown.webp',
          child: _RuleText(L10n.of(context).rulesMtWinBody),
        ),
      ],
    );
  }

  // ─── Shared section helper ─────────────────────────────────────────────────

  Widget _section({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget child,
    String? art,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0D8D4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                art != null
                    ? _SectionArt(art)
                    : _SectionBadge(icon: icon, color: iconColor),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF3E312A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _expansionCard({
    required String assetPath,
    required String title,
    required int count,
    required String description,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.asset(
              assetPath,
              width: 44,
              height: 60,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  Container(width: 44, height: 60, color: color),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        L10n.of(context).rulesSkCardCount(count),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: Color(0xFF5A4038),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _cardAsset(String path) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.asset(
        path,
        width: 44,
        height: 60,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const SizedBox(width: 44, height: 60),
      ),
    );
  }

  static const _bodyStyle = TextStyle(
    fontSize: 15,
    height: 1.6,
    color: Color(0xFF5A4038),
  );
}

// ─── Row widget for card counts ──────────────────────────────────────────────

class _CardCountRow extends StatelessWidget {
  final String label;
  final String sub;
  final int count;
  final Widget? leading;
  final bool highlight;

  const _CardCountRow({
    required this.label,
    required this.sub,
    required this.count,
    this.leading,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 10)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: highlight
                              ? const Color(0xFFE65100)
                              : const Color(0xFF3E312A),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (highlight) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE0B2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          L10n.of(context).rulesSkIncludedByDefault,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFE65100),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF8A7A72),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF1EDE8),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE0D8D4)),
            ),
            child: Text(
              L10n.of(context).rulesSkCardCount(count),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF5A4038),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Divider(height: 1, color: Color(0xFFEAE2DE)),
    );
  }
}

// ─── Special card rule block (used in Tichu rules) ───────────────────────────

class _SpecialRule extends StatelessWidget {
  final String emoji;
  final String title;
  final List<String> lines;
  final Widget? extra;

  /// Optional card ID rendered as a small [PlayingCard] thumbnail at the
  /// right of the rule. When provided, takes visual priority over the
  /// [emoji] badge on the left (the emoji still shows for flavour).
  /// Accepts both Tichu ("spade_A") and Mighty ("mighty_spade_A") card
  /// IDs — the Mighty prefix is stripped before passing to [PlayingCard]
  /// so the correct artwork renders.
  final String? cardId;

  /// Alternate card shown side-by-side with [cardId] — used for the
  /// Mighty rule to show both the default ♠A and the ♦A fallback when
  /// spade is the chosen trump.
  final String? altCardId;

  /// Short caption rendered under the [altCardId] preview (e.g. a
  /// "when trump = ♠" footnote).
  final String? altCardLabel;

  /// Optional in-game corner badge (top-right of the card preview) so
  /// readers can tell at a glance that the Mighty / joker-call badge
  /// they see in play corresponds to this rule.
  final IconData? badgeIcon;
  final Color? badgeColor;

  /// 실제 카드 그림. 주어지면 이모지 대신 왼쪽에 크게 보여 준다.
  final String? leadingAsset;

  const _SpecialRule({
    this.leadingAsset,
    required this.emoji,
    required this.title,
    required this.lines,
    this.extra,
    this.cardId,
    this.altCardId,
    this.altCardLabel,
    this.badgeIcon,
    this.badgeColor,
  });

  /// Convert `mighty_spade_A` → `spade_A` and `mighty_joker` → `joker` so
  /// [PlayingCard] renders the actual in-game artwork instead of treating
  /// `mighty` as the suit.
  String _displayCardId(String id) {
    if (id == 'mighty_joker') return 'joker';
    return id.startsWith('mighty_') ? id.substring(7) : id;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F4F1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE8DDD8)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(emoji, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF3E312A),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, top: 2, bottom: 2),
                    child: Text(
                      '• $line',
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: Color(0xFF5A4038),
                      ),
                    ),
                  ),
                if (extra != null) ...[const SizedBox(height: 8), extra!],
              ],
            ),
          ),
          if (cardId != null) ...[
            const SizedBox(width: 10),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PlayingCard(
                  cardId: _displayCardId(cardId!),
                  width: 44,
                  height: 62,
                  isInteractive: false,
                  badgeIcon: badgeIcon,
                  badgeColor: badgeColor,
                ),
                if (altCardId != null) ...[
                  const SizedBox(height: 6),
                  PlayingCard(
                    cardId: _displayCardId(altCardId!),
                    width: 44,
                    height: 62,
                    isInteractive: false,
                    badgeIcon: badgeIcon,
                    badgeColor: badgeColor,
                  ),
                  if (altCardLabel != null) ...[
                    const SizedBox(height: 2),
                    SizedBox(
                      width: 56,
                      child: Text(
                        altCardLabel!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11,
                          height: 1.2,
                          color: Color(0xFF8A7A72),
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TigressDisplayPreview extends StatelessWidget {
  const _TigressDisplayPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF5E35B1).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF5E35B1).withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            L10n.of(context).rulesSkTigressPreviewTitle,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Color(0xFF4A327E),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _TigressChoiceCard(
                  assetPath: 'assets/cards/sk_escape.webp',
                  label: L10n.of(context).rulesSkTigressChoiceEscape,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TigressChoiceCard(
                  assetPath: 'assets/cards/sk_pirate.webp',
                  label: L10n.of(context).rulesSkTigressChoicePirate,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TigressChoiceCard extends StatelessWidget {
  final String assetPath;
  final String label;

  const _TigressChoiceCard({required this.assetPath, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.asset(
                assetPath,
                width: 36,
                height: 50,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 36,
                  height: 50,
                  color: const Color(0xFFEDE7F6),
                ),
              ),
            ),
            Positioned(
              left: -4,
              top: -4,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: const Color(0xFF5E35B1),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.2),
                ),
                child: const Icon(Icons.check, size: 10, color: Colors.white),
              ),
            ),
          ],
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF5A4038),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ─── Tichu declaration row (used in Tichu rules) ─────────────────────────────

// ─── Scoring example block (used in Skull King rules) ───────────────────────

class _ExampleBlock extends StatelessWidget {
  final String title;
  final String setup;
  final String calc;
  final String result;
  final bool positive;

  const _ExampleBlock({
    required this.title,
    required this.setup,
    required this.calc,
    required this.result,
    required this.positive,
  });

  @override
  Widget build(BuildContext context) {
    final accent = positive ? const Color(0xFF43A047) : const Color(0xFFC62828);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF3E312A),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  result,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            setup,
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Color(0xFF5A4038),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '→ $calc',
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6D615B),
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _TichuDeclarationRow extends StatelessWidget {
  final String title;
  final String when;
  final String success;
  final String fail;
  final Color accent;

  const _TichuDeclarationRow({
    required this.title,
    required this.when,
    required this.success,
    required this.fail,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF43A047),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  L10n.of(context).rulesTichuDeclSuccess(success),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFC62828),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  L10n.of(context).rulesTichuDeclFail(fail),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            when,
            style: const TextStyle(
              fontSize: 13,
              height: 1.45,
              color: Color(0xFF5A4038),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Bottom-sheet game picker tile ────────────────────────────────────────────

class _GamePickerTile extends StatelessWidget {
  final String gameKey;
  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _GamePickerTile({
    required this.gameKey,
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        color: selected ? color.withValues(alpha: 0.08) : null,
        child: Row(
          children: [
            gameTypeSymbol(gameKey, size: 34),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  color: selected ? color : const Color(0xFF5A4038),
                ),
              ),
            ),
            if (selected) Icon(Icons.check_rounded, color: color, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Small horizontal strip showing a sample of the Mighty deck: one Ace per
/// suit plus the joker. Purely decorative — helps the rulebook reader
/// visualise what "52 suited + joker" looks like.
class _MightyDeckPreview extends StatelessWidget {
  const _MightyDeckPreview();

  @override
  Widget build(BuildContext context) {
    // PlayingCard expects Tichu-style IDs ("spade_A", "joker"); the Mighty
    // prefix would otherwise be parsed as the suit.
    const cardIds = ['spade_A', 'heart_A', 'diamond_A', 'club_A', 'joker'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F4F1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE8DDD8)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (final id in cardIds)
            PlayingCard(
              cardId: id,
              width: 40,
              height: 56,
              isInteractive: false,
            ),
        ],
      ),
    );
  }
}

// ─── Readable body text ──────────────────────────────────────────────────────

/// 줄글 규칙 본문을 보기 좋게 풀어 그린다. 문자열은 그대로 두고 모양만 바꾼다:
/// 번호 줄은 동그란 번호 뱃지, "•"/"-" 줄은 들여쓴 글머리표, ":" 로 끝나는 줄은
/// 소제목, 빈 줄은 문단 간격.
class _RuleText extends StatelessWidget {
  const _RuleText(this.text);

  final String text;

  static const _ink = Color(0xFF5A4038);
  static const _strong = Color(0xFF3E312A);

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (final raw in text.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        rows.add(const SizedBox(height: 8));
        continue;
      }
      final indent = line.length - line.trimLeft().length;
      final t = line.trim();
      final num = RegExp(r'^(\d+)\.\s+(.*)$').firstMatch(t);
      if (num != null) {
        rows.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.only(top: 1, right: 10),
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEDE7F6),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    num.group(1)!,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF5E35B1),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    num.group(2)!,
                    style: _RulesScreenState._bodyStyle,
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }
      final bullet = RegExp(r'^[•\-]\s*(.*)$').firstMatch(t);
      if (bullet != null) {
        final deep = indent >= 2;
        rows.add(
          Padding(
            padding: EdgeInsets.only(left: deep ? 22 : 4, top: 3, bottom: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 9, right: 10),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: deep
                          ? const Color(0xFFB8A9A2)
                          : const Color(0xFF8A7A72),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    bullet.group(1)!,
                    style: _RulesScreenState._bodyStyle,
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }
      if (t.endsWith(':') || t.endsWith('：')) {
        rows.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 2),
            child: Text(
              t,
              style: const TextStyle(
                fontSize: 15,
                height: 1.5,
                fontWeight: FontWeight.w800,
                color: _strong,
              ),
            ),
          ),
        );
        continue;
      }
      rows.add(
        Padding(
          padding: EdgeInsets.only(
            left: indent >= 2 ? 22 : 0,
            top: 2,
            bottom: 2,
          ),
          child: Text(
            t,
            style: const TextStyle(fontSize: 15, height: 1.6, color: _ink),
          ),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }
}

// ─── Visual examples ─────────────────────────────────────────────────────────

/// 조합 이름 + 실제 카드 그림.
class _ComboRow extends StatelessWidget {
  const _ComboRow({
    required this.label,
    required this.cards,
    this.accent = const Color(0xFF6C63FF),
  });

  final String label;
  final List<String> cards;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final c in cards)
                PlayingCard(
                  cardId: c,
                  width: 44,
                  height: 62,
                  isInteractive: false,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 스컬킹 예시용 작은 카드. 숫자 카드는 문양 색 + 숫자, 특수 카드는 실제 그림.
class _SkMini extends StatelessWidget {
  const _SkMini.number(this.suit, this.rank) : special = null, next = false;
  const _SkMini.special(this.special) : suit = null, rank = null, next = false;
  const _SkMini.next() : suit = null, rank = null, special = null, next = true;

  final String? suit;
  final String? rank;
  final String? special;
  final bool next;

  static const _suitColors = {
    'yellow': Color(0xFFD4A017),
    'green': Color(0xFF2E7D32),
    'purple': Color(0xFF6A1B9A),
    'black': Color(0xFF212121),
  };

  @override
  Widget build(BuildContext context) {
    const w = 52.0, h = 73.0;
    if (special != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.asset(
          'assets/cards/sk_$special.webp',
          width: w,
          height: h,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox(width: w, height: h),
        ),
      );
    }
    if (next) {
      return Container(
        width: w,
        height: h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFB8A9A2), width: 1.5),
        ),
        child: const Text(
          '?',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: Color(0xFFB8A9A2),
          ),
        ),
      );
    }
    final color = _suitColors[suit] ?? const Color(0xFF212121);
    return Container(
      width: w,
      height: h,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color, width: 2),
      ),
      child: Text(
        rank!,
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }
}

/// 카드 몇 장이 순서대로 나오는 장면 + 설명 + 결과 태그.
class _FlowDemo extends StatelessWidget {
  const _FlowDemo({
    required this.cards,
    required this.caption,
    required this.tag,
    required this.tagColor,
  });

  final List<Widget> cards;
  final String caption;
  final String tag;
  final Color tagColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F4F1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8DDD8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 20,
                      color: Color(0xFFB8A9A2),
                    ),
                  ),
                cards[i],
              ],
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: tagColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              tag,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            caption,
            style: const TextStyle(
              fontSize: 14,
              height: 1.55,
              color: Color(0xFF5A4038),
            ),
          ),
        ],
      ),
    );
  }
}

/// 섹션 제목 앞의 그림: 그 게임의 실제 카드(또는 게임 심볼·왕관).
class _SectionArt extends StatelessWidget {
  const _SectionArt(this.asset);

  final String asset;

  @override
  Widget build(BuildContext context) {
    final isCard = asset.contains('/cards/');
    final image = Image.asset(
      asset,
      width: isCard ? 28 : 34,
      height: isCard ? 39 : 34,
      fit: isCard ? BoxFit.cover : BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => const SizedBox(width: 28, height: 39),
    );
    if (!isCard) return image;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(4), child: image),
    );
  }
}

/// 카드 그림이 마땅치 않은 섹션(점수, 폭탄 등)의 아이콘: 색 입힌 둥근 배지.
class _SectionBadge extends StatelessWidget {
  const _SectionBadge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, Colors.black, 0.25)!],
        ),
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    );
  }
}
