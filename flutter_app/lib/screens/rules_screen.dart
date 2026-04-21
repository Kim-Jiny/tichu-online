import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../services/game_service.dart';

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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE0D8D4)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _gameIcon(_selectedGame),
                          color: _gameColor(_selectedGame),
                          size: 20,
                        ),
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

  IconData _gameIcon(String key) => switch (key) {
        'tichu' => Icons.style,
        'skull_king' => Icons.anchor,
        'love_letter' => Icons.favorite,
        'mighty' => Icons.military_tech,
        _ => Icons.style,
      };

  Color _gameColor(String key) => switch (key) {
        'tichu' => const Color(0xFF6C63FF),
        'skull_king' => const Color(0xFF2D2D3D),
        'love_letter' => const Color(0xFFE91E63),
        'mighty' => const Color(0xFF1565C0),
        _ => const Color(0xFF6C63FF),
      };

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
                  icon: _gameIcon(key),
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
          child: Text(
            L10n.of(context).rulesTichuGoalBody,
            style: _bodyStyle,
          ),
        ),
        _section(
          icon: Icons.style,
          iconColor: tichuAccent,
          title: L10n.of(context).rulesTichuCardCompositionTitle,
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
                leading: _cardAsset('assets/cards/bird.png'),
              ),
              const _Divider(),
              _CardCountRow(
                label: L10n.of(context).rulesTichuDog,
                sub: L10n.of(context).rulesTichuDogSub,
                count: 1,
                leading: _cardAsset('assets/cards/dog.png'),
              ),
              const _Divider(),
              _CardCountRow(
                label: L10n.of(context).rulesTichuPhoenix,
                sub: L10n.of(context).rulesTichuPhoenixSub,
                count: 1,
                leading: _cardAsset('assets/cards/phoenix.png'),
              ),
              const _Divider(),
              _CardCountRow(
                label: L10n.of(context).rulesTichuDragon,
                sub: L10n.of(context).rulesTichuDragonSub,
                count: 1,
                leading: _cardAsset('assets/cards/dragon.png'),
              ),
            ],
          ),
        ),
        _section(
          icon: Icons.auto_awesome,
          iconColor: tichuAccent,
          title: L10n.of(context).rulesTichuSpecialTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SpecialRule(
                emoji: '🐦',
                title: L10n.of(context).rulesTichuSpecialMahjongTitle,
                lines: [
                  L10n.of(context).rulesTichuSpecialMahjongLine1,
                  L10n.of(context).rulesTichuSpecialMahjongLine2,
                ],
              ),
              const SizedBox(height: 10),
              _SpecialRule(
                emoji: '🐶',
                title: L10n.of(context).rulesTichuSpecialDogTitle,
                lines: [
                  L10n.of(context).rulesTichuSpecialDogLine1,
                  L10n.of(context).rulesTichuSpecialDogLine2,
                ],
              ),
              const SizedBox(height: 10),
              _SpecialRule(
                emoji: '🔥',
                title: L10n.of(context).rulesTichuSpecialPhoenixTitle,
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                L10n.of(context).rulesTichuDeclarationBody,
                style: _bodyStyle,
              ),
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
          child: Text(
            L10n.of(context).rulesTichuFlowBody,
            style: _bodyStyle,
          ),
        ),
        _section(
          icon: Icons.layers,
          iconColor: tichuAccent,
          title: L10n.of(context).rulesTichuPlayTitle,
          child: Text(
            L10n.of(context).rulesTichuPlayBody,
            style: _bodyStyle,
          ),
        ),
        _section(
          icon: Icons.local_fire_department,
          iconColor: const Color(0xFFE53935),
          title: L10n.of(context).rulesTichuBombTitle,
          child: Text(
            L10n.of(context).rulesTichuBombBody,
            style: _bodyStyle,
          ),
        ),
        _section(
          icon: Icons.calculate,
          iconColor: tichuAccent,
          title: L10n.of(context).rulesTichuScoringTitle,
          child: Text(
            L10n.of(context).rulesTichuScoringBody,
            style: _bodyStyle,
          ),
        ),
        _section(
          icon: Icons.emoji_events,
          iconColor: tichuAccent,
          title: L10n.of(context).rulesTichuWinTitle,
          child: Text(
            L10n.of(context).rulesTichuWinBody,
            style: _bodyStyle,
          ),
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
          child: Text(
            L10n.of(context).rulesSkGoalBody,
            style: _bodyStyle,
          ),
        ),
        _section(
          icon: Icons.style,
          iconColor: skAccent,
          title: L10n.of(context).rulesSkCardCompositionTitle,
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
                leading: _cardAsset('assets/cards/sk_escape.png'),
              ),
              const _Divider(),
              _CardCountRow(
                label: L10n.of(context).rulesSkPirate,
                sub: L10n.of(context).rulesSkPirateSub,
                count: 4,
                leading: _cardAsset('assets/cards/sk_pirate.png'),
              ),
              const _Divider(),
              _CardCountRow(
                label: L10n.of(context).rulesSkMermaid,
                sub: L10n.of(context).rulesSkMermaidSub,
                count: 2,
                leading: _cardAsset('assets/cards/sk_mermaid.png'),
              ),
              const _Divider(),
              _CardCountRow(
                label: L10n.of(context).rulesSkSkullKing,
                sub: L10n.of(context).rulesSkSkullKingSub,
                count: 1,
                leading: _cardAsset('assets/cards/sk_skull_king.png'),
              ),
              const _Divider(),
              _CardCountRow(
                label: L10n.of(context).rulesSkTigress,
                sub: L10n.of(context).rulesSkTigressSub,
                count: 3,
                leading: _cardAsset('assets/cards/sk_tigress.png'),
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
                            fontSize: 12,
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
                            TextSpan(
                              text: L10n.of(context).rulesSkTrumpBody,
                            ),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SpecialRule(
                emoji: '🏳️',
                title: L10n.of(context).rulesSkSpecialEscapeTitle,
                lines: [
                  L10n.of(context).rulesSkSpecialEscapeLine1,
                  L10n.of(context).rulesSkSpecialEscapeLine2,
                ],
              ),
              const SizedBox(height: 10),
              _SpecialRule(
                emoji: '⚔️',
                title: L10n.of(context).rulesSkSpecialPirateTitle,
                lines: [
                  L10n.of(context).rulesSkSpecialPirateLine1,
                  L10n.of(context).rulesSkSpecialPirateLine2,
                ],
              ),
              const SizedBox(height: 10),
              _SpecialRule(
                emoji: '🧜\u200d♀️',
                title: L10n.of(context).rulesSkSpecialMermaidTitle,
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
                lines: [
                  L10n.of(context).rulesSkSpecialSkullKingLine1,
                  L10n.of(context).rulesSkSpecialSkullKingLine2,
                ],
              ),
              const SizedBox(height: 10),
              _SpecialRule(
                emoji: '🐯',
                title: L10n.of(context).rulesSkSpecialTigressTitle,
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
          child: Text(
            L10n.of(context).rulesSkFlowBody,
            style: _bodyStyle,
          ),
        ),
        _section(
          icon: Icons.calculate,
          iconColor: skAccent,
          title: L10n.of(context).rulesSkScoringTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                L10n.of(context).rulesSkScoringBody,
                style: _bodyStyle,
              ),
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
          child: Text(
            L10n.of(context).rulesSkWinBody,
            style: _bodyStyle,
          ),
        ),
        _section(
          icon: Icons.extension,
          iconColor: const Color(0xFFFF8A65),
          title: L10n.of(context).rulesSkExpansionTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                L10n.of(context).rulesSkExpansionBody,
                style: _bodyStyle,
              ),
              const SizedBox(height: 12),
              _expansionCard(
                assetPath: 'assets/cards/sk_kraken.png',
                title: L10n.of(context).rulesSkExpKraken,
                count: 1,
                description: L10n.of(context).rulesSkExpKrakenDesc,
                color: const Color(0xFF2B1E3F),
              ),
              const SizedBox(height: 10),
              _expansionCard(
                assetPath: 'assets/cards/sk_white_whale.png',
                title: L10n.of(context).rulesSkExpWhiteWhale,
                count: 1,
                description: L10n.of(context).rulesSkExpWhiteWhaleDesc,
                color: const Color(0xFF3A6B8F),
              ),
              const SizedBox(height: 10),
              _expansionCard(
                assetPath: 'assets/cards/sk_loot.png',
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
          child: Text(
            L10n.of(context).rulesLlGoalBody,
            style: _bodyStyle,
          ),
        ),
        _section(
          icon: Icons.style,
          iconColor: llAccent,
          title: L10n.of(context).rulesLlCardCompositionTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardCountRow(
                label: L10n.of(context).rulesLlGuard,
                sub: L10n.of(context).rulesLlGuardSub,
                count: 5,
                leading: _cardAsset('assets/cards/ll_Guard.png'),
              ),
              const _Divider(),
              _CardCountRow(
                label: L10n.of(context).rulesLlSpy,
                sub: L10n.of(context).rulesLlSpySub,
                count: 2,
                leading: _cardAsset('assets/cards/ll_Spy.png'),
              ),
              const _Divider(),
              _CardCountRow(
                label: L10n.of(context).rulesLlBaron,
                sub: L10n.of(context).rulesLlBaronSub,
                count: 2,
                leading: _cardAsset('assets/cards/ll_Baron.png'),
              ),
              const _Divider(),
              _CardCountRow(
                label: L10n.of(context).rulesLlHandmaid,
                sub: L10n.of(context).rulesLlHandmaidSub,
                count: 2,
                leading: _cardAsset('assets/cards/ll_Handmaid.png'),
              ),
              const _Divider(),
              _CardCountRow(
                label: L10n.of(context).rulesLlPrince,
                sub: L10n.of(context).rulesLlPrinceSub,
                count: 2,
                leading: _cardAsset('assets/cards/ll_Prince.png'),
              ),
              const _Divider(),
              _CardCountRow(
                label: L10n.of(context).rulesLlKing,
                sub: L10n.of(context).rulesLlKingSub,
                count: 1,
                leading: _cardAsset('assets/cards/ll_King.png'),
              ),
              const _Divider(),
              _CardCountRow(
                label: L10n.of(context).rulesLlCountess,
                sub: L10n.of(context).rulesLlCountessSub,
                count: 1,
                leading: _cardAsset('assets/cards/ll_Countess.png'),
              ),
              const _Divider(),
              _CardCountRow(
                label: L10n.of(context).rulesLlPrincess,
                sub: L10n.of(context).rulesLlPrincessSub,
                count: 1,
                leading: _cardAsset('assets/cards/ll_Princess.png'),
              ),
            ],
          ),
        ),
        _section(
          icon: Icons.auto_awesome,
          iconColor: llAccent,
          title: L10n.of(context).rulesLlCardEffectsTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SpecialRule(
                emoji: '\u{1F6E1}\u{FE0F}',
                title: L10n.of(context).rulesLlEffectGuardTitle,
                lines: [
                  L10n.of(context).rulesLlEffectGuardLine1,
                  L10n.of(context).rulesLlEffectGuardLine2,
                ],
              ),
              const SizedBox(height: 10),
              _SpecialRule(
                emoji: '\u{1F50D}',
                title: L10n.of(context).rulesLlEffectSpyTitle,
                lines: [
                  L10n.of(context).rulesLlEffectSpyLine1,
                ],
              ),
              const SizedBox(height: 10),
              _SpecialRule(
                emoji: '\u{2694}\u{FE0F}',
                title: L10n.of(context).rulesLlEffectBaronTitle,
                lines: [
                  L10n.of(context).rulesLlEffectBaronLine1,
                  L10n.of(context).rulesLlEffectBaronLine2,
                ],
              ),
              const SizedBox(height: 10),
              _SpecialRule(
                emoji: '\u{1F9D1}\u{200D}\u{1F91D}\u{200D}\u{1F9D1}',
                title: L10n.of(context).rulesLlEffectHandmaidTitle,
                lines: [
                  L10n.of(context).rulesLlEffectHandmaidLine1,
                ],
              ),
              const SizedBox(height: 10),
              _SpecialRule(
                emoji: '\u{1F451}',
                title: L10n.of(context).rulesLlEffectPrinceTitle,
                lines: [
                  L10n.of(context).rulesLlEffectPrinceLine1,
                  L10n.of(context).rulesLlEffectPrinceLine2,
                ],
              ),
              const SizedBox(height: 10),
              _SpecialRule(
                emoji: '\u{1F934}',
                title: L10n.of(context).rulesLlEffectKingTitle,
                lines: [
                  L10n.of(context).rulesLlEffectKingLine1,
                ],
              ),
              const SizedBox(height: 10),
              _SpecialRule(
                emoji: '\u{1F483}',
                title: L10n.of(context).rulesLlEffectCountessTitle,
                lines: [
                  L10n.of(context).rulesLlEffectCountessLine1,
                  L10n.of(context).rulesLlEffectCountessLine2,
                ],
              ),
              const SizedBox(height: 10),
              _SpecialRule(
                emoji: '\u{1F478}',
                title: L10n.of(context).rulesLlEffectPrincessTitle,
                lines: [
                  L10n.of(context).rulesLlEffectPrincessLine1,
                ],
              ),
            ],
          ),
        ),
        _section(
          icon: Icons.format_list_numbered,
          iconColor: llAccent,
          title: L10n.of(context).rulesLlFlowTitle,
          child: Text(
            L10n.of(context).rulesLlFlowBody,
            style: _bodyStyle,
          ),
        ),
        _section(
          icon: Icons.emoji_events,
          iconColor: llAccent,
          title: L10n.of(context).rulesLlWinTitle,
          child: Text(
            L10n.of(context).rulesLlWinBody,
            style: _bodyStyle,
          ),
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
          child: Text(
            L10n.of(context).rulesMtGoalBody,
            style: _bodyStyle,
          ),
        ),
        _section(
          icon: Icons.style,
          iconColor: mtAccent,
          title: L10n.of(context).rulesMtCardCompositionTitle,
          child: Text(
            L10n.of(context).rulesMtCardCompositionBody,
            style: _bodyStyle,
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
              ),
              const SizedBox(height: 10),
              _SpecialRule(
                emoji: '\u{1F0CF}',
                title: L10n.of(context).rulesMtSpecialJokerTitle,
                lines: [
                  L10n.of(context).rulesMtSpecialJokerLine1,
                  L10n.of(context).rulesMtSpecialJokerLine2,
                ],
              ),
              const SizedBox(height: 10),
              _SpecialRule(
                emoji: '\u{1F4E2}',
                title: L10n.of(context).rulesMtSpecialJokerCallTitle,
                lines: [
                  L10n.of(context).rulesMtSpecialJokerCallLine1,
                  L10n.of(context).rulesMtSpecialJokerCallLine2,
                ],
              ),
            ],
          ),
        ),
        _section(
          icon: Icons.gavel,
          iconColor: mtAccent,
          title: L10n.of(context).rulesMtBiddingTitle,
          child: Text(
            L10n.of(context).rulesMtBiddingBody,
            style: _bodyStyle,
          ),
        ),
        _section(
          icon: Icons.people,
          iconColor: mtAccent,
          title: L10n.of(context).rulesMtFriendTitle,
          child: Text(
            L10n.of(context).rulesMtFriendBody,
            style: _bodyStyle,
          ),
        ),
        _section(
          icon: Icons.format_list_numbered,
          iconColor: mtAccent,
          title: L10n.of(context).rulesMtTrickTitle,
          child: Text(
            L10n.of(context).rulesMtTrickBody,
            style: _bodyStyle,
          ),
        ),
        _section(
          icon: Icons.calculate,
          iconColor: mtAccent,
          title: L10n.of(context).rulesMtScoringTitle,
          child: Text(
            L10n.of(context).rulesMtScoringBody,
            style: _bodyStyle,
          ),
        ),
        _section(
          icon: Icons.emoji_events,
          iconColor: mtAccent,
          title: L10n.of(context).rulesMtWinTitle,
          child: Text(
            L10n.of(context).rulesMtWinBody,
            style: _bodyStyle,
          ),
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
                Icon(icon, color: iconColor, size: 18),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF3E312A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
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
              errorBuilder: (_, _, _) => Container(
                width: 44,
                height: 60,
                color: color,
              ),
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
                          fontSize: 11,
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
                    fontSize: 12,
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
        width: 28,
        height: 38,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const SizedBox(width: 28, height: 38),
      ),
    );
  }

  static const _bodyStyle = TextStyle(
    fontSize: 13,
    height: 1.55,
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
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 10),
          ],
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
                          fontSize: 13,
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
                            fontSize: 9,
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
                    fontSize: 11,
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
                fontSize: 12,
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

  const _SpecialRule({
    required this.emoji,
    required this.title,
    required this.lines,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F4F1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE8DDD8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF3E312A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final line in lines) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 2, bottom: 2),
              child: Text(
                '• $line',
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: Color(0xFF5A4038),
                ),
              ),
            ),
          ],
          if (extra != null) ...[const SizedBox(height: 8), extra!],
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
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Color(0xFF4A327E),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _TigressChoiceCard(
                  assetPath: 'assets/cards/sk_escape.png',
                  label: L10n.of(context).rulesSkTigressChoiceEscape,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TigressChoiceCard(
                  assetPath: 'assets/cards/sk_pirate.png',
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
              fontSize: 11,
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
                    fontSize: 12,
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
                    fontSize: 11,
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
              fontSize: 11,
              height: 1.4,
              color: Color(0xFF5A4038),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '→ $calc',
            style: const TextStyle(
              fontSize: 11,
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
                  fontSize: 13,
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
                    fontSize: 10,
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
                    fontSize: 10,
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
              fontSize: 11,
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
  final IconData icon;
  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _GamePickerTile({
    required this.icon,
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
            Icon(icon, color: color, size: 22),
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
            if (selected)
              Icon(Icons.check_rounded, color: color, size: 20),
          ],
        ),
      ),
    );
  }
}
