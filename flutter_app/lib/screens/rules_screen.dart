import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
                    const Text(
                      '게임 설명',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF5A4038),
                      ),
                    ),
                  ],
                ),
              ),
              // Game type tabs
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'tichu',
                        label: Text('티츄'),
                        icon: Icon(Icons.style, size: 16),
                      ),
                      ButtonSegment(
                        value: 'skull_king',
                        label: Text('스컬킹'),
                        icon: Icon(Icons.anchor, size: 16),
                      ),
                    ],
                    selected: {_selectedGame},
                    onSelectionChanged: (s) => setState(() => _selectedGame = s.first),
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return _selectedGame == 'tichu'
                              ? const Color(0xFF6C63FF)
                              : const Color(0xFF2D2D3D);
                        }
                        return Colors.white;
                      }),
                      foregroundColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return _selectedGame == 'tichu'
                              ? Colors.white
                              : const Color(0xFFFFD54F);
                        }
                        return const Color(0xFF6A6A6A);
                      }),
                      shape: WidgetStateProperty.all(
                        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      side: WidgetStateProperty.all(
                        const BorderSide(color: Color(0xFFE0D8D4)),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: _selectedGame == 'tichu'
                      ? _buildTichuRules()
                      : _buildSkullKingRules(),
                ),
              ),
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
          title: '게임 목표',
          child: const Text(
            '4인 2팀(마주 본 두 사람이 한 팀)으로 진행하는 트릭테이킹 게임입니다. '
            '상대팀보다 먼저 목표 점수에 도달하면 승리합니다.',
            style: _bodyStyle,
          ),
        ),
        _section(
          icon: Icons.style,
          iconColor: tichuAccent,
          title: '카드 구성 (총 56장)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CardCountRow(
                label: '숫자 카드 (2 ~ A)',
                sub: '4 문양 × 13장',
                count: 52,
              ),
              const _Divider(),
              _CardCountRow(
                label: '참새 (Mahjong)',
                sub: '게임을 시작하는 카드',
                count: 1,
                leading: _cardAsset('assets/cards/bird.png'),
              ),
              const _Divider(),
              _CardCountRow(
                label: '개 (Dog)',
                sub: '리드권을 파트너에게 넘김',
                count: 1,
                leading: _cardAsset('assets/cards/dog.png'),
              ),
              const _Divider(),
              _CardCountRow(
                label: '불사조 (Phoenix)',
                sub: '만능 카드 (-25점)',
                count: 1,
                leading: _cardAsset('assets/cards/phoenix.png'),
              ),
              const _Divider(),
              _CardCountRow(
                label: '용 (Dragon)',
                sub: '가장 강한 카드 (+25점)',
                count: 1,
                leading: _cardAsset('assets/cards/dragon.png'),
              ),
            ],
          ),
        ),
        _section(
          icon: Icons.auto_awesome,
          iconColor: tichuAccent,
          title: '특수 카드 규칙',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _SpecialRule(
                emoji: '🐦',
                title: '참새 (Mahjong)',
                lines: [
                  '이 카드를 가진 사람이 가장 먼저 게임을 시작합니다.',
                  '참새 카드를 낼 때 원하는 숫자(2~14)를 선언할 수 있고, '
                  '다음 플레이어는 선언된 숫자를 포함한 조합을 반드시 내야 합니다. '
                  '(해당 숫자를 가지고 있지 않으면 무시 가능)',
                ],
              ),
              SizedBox(height: 10),
              _SpecialRule(
                emoji: '🐶',
                title: '개 (Dog)',
                lines: [
                  '리드할 때만 낼 수 있으며, 즉시 리드권을 파트너에게 넘깁니다.',
                  '점수 계산에서는 0점입니다.',
                ],
              ),
              SizedBox(height: 10),
              _SpecialRule(
                emoji: '🔥',
                title: '불사조 (Phoenix)',
                lines: [
                  '싱글로 낼 때는 앞에 낸 카드의 숫자 + 0.5로 취급됩니다. '
                  '단, 용 위에는 낼 수 없습니다.',
                  '조합(페어/트리플/풀하우스/스트레이트 등) 안에서 사용할 때는 '
                  '어떤 숫자로도 대체할 수 있습니다.',
                  '획득 시 -25점이므로 먹으면 손해입니다.',
                ],
              ),
              SizedBox(height: 10),
              _SpecialRule(
                emoji: '🐉',
                title: '용 (Dragon)',
                lines: [
                  '가장 강한 카드이며, 싱글로만 낼 수 있습니다.',
                  '획득 시 +25점이지만, 용으로 이긴 트릭은 상대팀 중 한 명에게 '
                  '넘겨줘야 합니다.',
                ],
              ),
            ],
          ),
        ),
        _section(
          icon: Icons.campaign,
          iconColor: tichuAccent,
          title: '티츄 선언',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                '티츄는 "이번 라운드에서 내가 1등으로 손패를 다 털겠다"는 선언입니다. '
                '성공하면 팀 점수가 올라가고 실패하면 감점됩니다.',
                style: _bodyStyle,
              ),
              SizedBox(height: 10),
              _TichuDeclarationRow(
                title: '라지티츄',
                when: '처음 8장만 받았을 때 (나머지 6장을 보기 전) 선언',
                success: '+200점',
                fail: '-200점',
                accent: Color(0xFFD32F2F),
              ),
              SizedBox(height: 8),
              _TichuDeclarationRow(
                title: '스몰티츄',
                when: '14장을 모두 받은 후, 첫 카드를 한 장도 내기 전에 선언',
                success: '+100점',
                fail: '-100점',
                accent: Color(0xFFFF8F00),
              ),
            ],
          ),
        ),
        _section(
          icon: Icons.format_list_numbered,
          iconColor: tichuAccent,
          title: '진행 순서',
          child: const Text(
            '1. 모든 플레이어가 먼저 8장씩 카드를 받습니다.\n'
            '2. 8장을 보고 원하면 라지티츄를 선언할 수 있습니다.\n'
            '3. 나머지 6장을 받아 총 14장이 됩니다.\n'
            '4. 나를 제외한 3명의 플레이어에게 카드를 1장씩 교환(패스)합니다.\n'
            '5. 교환 후 카드를 한 장도 내기 전에 원하면 스몰티츄를 선언할 수 있습니다.\n'
            '6. 참새(Mahjong)를 가진 사람이 먼저 카드를 내며 첫 리드를 시작합니다.',
            style: _bodyStyle,
          ),
        ),
        _section(
          icon: Icons.layers,
          iconColor: tichuAccent,
          title: '플레이 규칙',
          child: const Text(
            '• 선 플레이어가 낸 조합과 같은 형태의 조합만 그 위에 낼 수 있습니다. '
            '(예: 싱글 위에는 더 높은 싱글, 페어 위에는 더 높은 페어)\n'
            '• 사용 가능한 조합:\n'
            '   - 싱글 (카드 1장)\n'
            '   - 페어 (같은 숫자 2장)\n'
            '   - 트리플 (같은 숫자 3장)\n'
            '   - 풀하우스 (트리플 + 페어)\n'
            '   - 스트레이트 (연속된 숫자 5장 이상)\n'
            '   - 연속 페어 (연속된 페어 2쌍 이상 = 4장 이상)\n'
            '• 본인 차례에 낼 카드가 없거나 내기 싫으면 패스할 수 있습니다.',
            style: _bodyStyle,
          ),
        ),
        _section(
          icon: Icons.local_fire_department,
          iconColor: const Color(0xFFE53935),
          title: '폭탄',
          child: const Text(
            '폭탄은 자신의 차례가 아니더라도 언제든 낼 수 있으며, '
            '어떤 조합도 이길 수 있는 특수 조합입니다.\n\n'
            '• 포카드 폭탄: 같은 숫자 4장 (예: 7♠ 7♥ 7♦ 7♣)\n'
            '• 스트레이트 플러시 폭탄: 같은 문양으로 연속된 5장 이상\n\n'
            '폭탄끼리의 우열:\n'
            '  스트레이트 플러시 > 포카드\n'
            '  같은 종류끼리는 더 높은 숫자/더 긴 스트레이트가 우세',
            style: _bodyStyle,
          ),
        ),
        _section(
          icon: Icons.calculate,
          iconColor: tichuAccent,
          title: '점수 계산',
          child: const Text(
            '카드 점수:\n'
            '• 5: 5점\n'
            '• 10, K: 10점\n'
            '• 용: +25점 / 불사조: -25점\n'
            '• 나머지 카드: 0점\n\n'
            '라운드 정산:\n'
            '• 1등으로 손패를 다 턴 사람은 꼴찌(4등)가 그동안 먹은 트릭 점수를 '
            '모두 가져갑니다.\n'
            '• 꼴찌의 손에 남아있는 카드는 상대팀의 점수로 들어갑니다.\n'
            '• 마주 본 한 팀이 1등·2등으로 먼저 나가면 "원더(Double Victory)" — '
            '해당 라운드 즉시 종료, 이긴 팀 +200점 (트릭 점수 계산 없음).\n'
            '• 티츄 선언 성공/실패 보너스가 여기에 더해집니다.',
            style: _bodyStyle,
          ),
        ),
        _section(
          icon: Icons.emoji_events,
          iconColor: tichuAccent,
          title: '승리 조건',
          child: const Text(
            '방 생성 시 설정한 목표 점수(기본 1000점)에 먼저 도달한 팀이 승리합니다. '
            '랭크전은 1000점 고정입니다.',
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
          title: '게임 목표',
          child: const Text(
            '2~6명이 개인전으로 진행하는 트릭테이킹 게임입니다. 총 10 라운드 동안 '
            '매 라운드마다 자신이 이길 트릭 수를 정확히 예측해야 점수를 얻습니다.',
            style: _bodyStyle,
          ),
        ),
        _section(
          icon: Icons.style,
          iconColor: skAccent,
          title: '카드 구성 (기본 총 67장)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CardCountRow(
                label: '숫자 카드 (1 ~ 13)',
                sub: '4 문양 × 13장 (노랑 / 초록 / 보라 / 검정)',
                count: 52,
              ),
              const _Divider(),
              _CardCountRow(
                label: 'Escape (도주)',
                sub: '트릭을 이기지 않음',
                count: 5,
                leading: _cardAsset('assets/cards/sk_escape.png'),
              ),
              const _Divider(),
              _CardCountRow(
                label: 'Pirate (해적)',
                sub: '숫자 카드를 모두 이김',
                count: 4,
                leading: _cardAsset('assets/cards/sk_pirate.png'),
              ),
              const _Divider(),
              _CardCountRow(
                label: 'Mermaid (인어)',
                sub: '스컬킹을 포획 (+50 보너스)',
                count: 2,
                leading: _cardAsset('assets/cards/sk_mermaid.png'),
              ),
              const _Divider(),
              _CardCountRow(
                label: 'Skull King (스컬킹)',
                sub: '해적을 이김 (해적당 +30 보너스)',
                count: 1,
                leading: _cardAsset('assets/cards/sk_skull_king.png'),
              ),
              const _Divider(),
              _CardCountRow(
                label: 'Tigress (티그리스)',
                sub: '해적 또는 도주 중 선택하여 사용',
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
                        text: const TextSpan(
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: Color(0xFF3E312A),
                          ),
                          children: [
                            TextSpan(
                              text: '검정 문양 = 트럼프\n',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF212121),
                              ),
                            ),
                            TextSpan(
                              text: '검정 숫자 카드는 다른 문양의 숫자 카드를 '
                                  '숫자에 상관없이 모두 이깁니다. 단, 리드 수트(첫 숫자 카드의 문양)를 '
                                  '따라 낼 수 있다면 반드시 따라야 하고, 해당 문양이 없을 때만 '
                                  '검정을 낼 수 있습니다.',
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
          title: '특수 카드 규칙',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _SpecialRule(
                emoji: '🏳️',
                title: 'Escape (도주)',
                lines: [
                  '절대 트릭을 이기지 않습니다. 수트 팔로잉에 상관없이 언제든 낼 수 있습니다.',
                  '모든 플레이어가 도주만 낸 경우에는 가장 먼저 낸 플레이어(리드 플레이어)가 '
                  '트릭을 가져갑니다.',
                ],
              ),
              SizedBox(height: 10),
              _SpecialRule(
                emoji: '⚔️',
                title: 'Pirate (해적)',
                lines: [
                  '모든 숫자 카드(검정 트럼프 포함)를 이깁니다. 같은 트릭에 여러 해적이 '
                  '나오면 먼저 낸 해적이 이깁니다.',
                  '인어에게 이기지만 스컬킹에게는 패배합니다.',
                ],
              ),
              SizedBox(height: 10),
              _SpecialRule(
                emoji: '🧜\u200d♀️',
                title: 'Mermaid (인어)',
                lines: [
                  '해적에게는 패배하지만, 스컬킹을 포획하여 이깁니다.',
                  '인어가 스컬킹을 잡으면 해당 트릭 승자에게 +50 보너스.',
                  '인어만 나온 경우 숫자 카드를 이깁니다.',
                ],
              ),
              SizedBox(height: 10),
              _SpecialRule(
                emoji: '☠️',
                title: 'Skull King (스컬킹)',
                lines: [
                  '해적을 이기며, 해적 1명당 +30 보너스를 얻습니다.',
                  '단, 인어에게는 포획당해 패배합니다.',
                ],
              ),
              SizedBox(height: 10),
              _SpecialRule(
                emoji: '🐯',
                title: 'Tigress (티그리스) — 기본 3장',
                lines: [
                  '카드를 낼 때 해적 또는 도주 중 하나를 선택합니다.',
                  '해적으로 낸 티그리스는 해적과 동일하게 작동하며 '
                  '스컬킹에게 +30 보너스도 포함됩니다.',
                ],
              ),
            ],
          ),
        ),
        _section(
          icon: Icons.format_list_numbered,
          iconColor: skAccent,
          title: '진행 순서',
          child: const Text(
            '1. 라운드 N에서 각자 N장씩 카드를 받습니다. (1~10 라운드)\n'
            '2. 모든 플레이어가 동시에 자신이 이길 트릭 수를 예측(비드)합니다.\n'
            '3. 선 플레이어부터 카드를 내고, 수트 팔로잉 규칙에 따라 트릭을 진행합니다.\n'
            '4. 한 라운드가 끝나면 비드 성공/실패에 따라 점수를 계산합니다.',
            style: _bodyStyle,
          ),
        ),
        _section(
          icon: Icons.calculate,
          iconColor: skAccent,
          title: '점수 계산',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                '• 비드 0 성공 (트릭 0승): +10 × 라운드 번호\n'
                '• 비드 0 실패: -10 × 라운드 번호\n'
                '• 비드 N 성공 (정확히 N승): +20 × N + 보너스\n'
                '• 비드 N 실패: -10 × |차이| (보너스 없음)\n'
                '• 보너스는 비드를 정확히 맞혔을 때만 지급됩니다.',
                style: _bodyStyle,
              ),
              SizedBox(height: 12),
              _ExampleBlock(
                title: '예시 1. 단순 비드 성공',
                setup: '3라운드 · 비드 2 · 트릭 2승 · 보너스 없음',
                calc: '20 × 2 = 40',
                result: '+40점',
                positive: true,
              ),
              SizedBox(height: 8),
              _ExampleBlock(
                title: '예시 2. 비드 0 성공',
                setup: '5라운드 · 비드 0 · 트릭 0승',
                calc: '10 × 5 = 50',
                result: '+50점',
                positive: true,
              ),
              SizedBox(height: 8),
              _ExampleBlock(
                title: '예시 3. 비드 실패',
                setup: '5라운드 · 비드 3 · 트릭 1승 (차이 2)',
                calc: '-10 × 2 = -20',
                result: '-20점',
                positive: false,
              ),
              SizedBox(height: 8),
              _ExampleBlock(
                title: '예시 4. 스컬킹으로 해적 2명 포획',
                setup: '3라운드 · 비드 2 · 트릭 2승 · 보너스 +60 (해적 2×30)',
                calc: '(20 × 2) + 60 = 100',
                result: '+100점',
                positive: true,
              ),
              SizedBox(height: 8),
              _ExampleBlock(
                title: '예시 5. 인어로 스컬킹 포획',
                setup: '4라운드 · 비드 1 · 트릭 1승 · 보너스 +50 (인어×SK)',
                calc: '(20 × 1) + 50 = 70',
                result: '+70점',
                positive: true,
              ),
              SizedBox(height: 8),
              _ExampleBlock(
                title: '예시 6. 비드 0 실패 (트릭 먹힘)',
                setup: '7라운드 · 비드 0 · 트릭 1승',
                calc: '-10 × 7 = -70',
                result: '-70점',
                positive: false,
              ),
            ],
          ),
        ),
        _section(
          icon: Icons.emoji_events,
          iconColor: const Color(0xFF2D2D3D),
          title: '승리 조건',
          child: const Text(
            '10 라운드가 모두 끝난 후 누적 점수가 가장 높은 플레이어가 승리합니다.',
            style: _bodyStyle,
          ),
        ),
        _section(
          icon: Icons.extension,
          iconColor: const Color(0xFFFF8A65),
          title: '확장팩 (선택)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '방 생성 시 각 확장팩을 개별적으로 선택할 수 있습니다. '
                '확장팩 카드는 기본 덱에 추가로 섞입니다.',
                style: _bodyStyle,
              ),
              const SizedBox(height: 12),
              _expansionCard(
                assetPath: 'assets/cards/sk_kraken.png',
                title: '🐙 크라켄',
                count: 1,
                description:
                    '크라켄이 포함된 트릭은 무효가 됩니다. 아무도 트릭을 얻지 못하고 '
                    '보너스도 지급되지 않습니다. 크라켄이 없었다면 이겼을 플레이어가 '
                    '다음 트릭을 리드합니다.',
                color: const Color(0xFF2B1E3F),
              ),
              const SizedBox(height: 10),
              _expansionCard(
                assetPath: 'assets/cards/sk_white_whale.png',
                title: '🐋 화이트웨일',
                count: 1,
                description:
                    '모든 특수 카드의 효과를 무력화합니다. 트릭에서는 오직 숫자 카드만 '
                    '비교하며, 수트와 무관하게 가장 높은 숫자가 승리합니다. 숫자 카드가 '
                    '없는 경우 트릭이 무효가 됩니다.',
                color: const Color(0xFF3A6B8F),
              ),
              const SizedBox(height: 10),
              _expansionCard(
                assetPath: 'assets/cards/sk_loot.png',
                title: '💰 보물',
                count: 2,
                description:
                    '트릭을 이긴 사람이 트릭에 포함된 보물 1장당 +20 보너스를 얻고, '
                    '보물을 낸 각 플레이어도 자신의 보너스로 +20을 얻습니다. (비드 성공 시에만 지급)',
                color: const Color(0xFF8B6F22),
              ),
            ],
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
                        '$count장',
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
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: highlight
                            ? const Color(0xFFE65100)
                            : const Color(0xFF3E312A),
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
                        child: const Text(
                          '기본 포함',
                          style: TextStyle(
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
              '$count장',
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

  const _SpecialRule({
    required this.emoji,
    required this.title,
    required this.lines,
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
        ],
      ),
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
                  '성공 $success',
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
                  '실패 $fail',
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
