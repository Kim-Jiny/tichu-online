import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/player.dart';
import '../services/game_service.dart';
import '../services/session_service.dart';
import '../widgets/playing_card.dart';
import '../widgets/connection_overlay.dart';

class SpectatorScreen extends StatefulWidget {
  const SpectatorScreen({super.key});

  @override
  State<SpectatorScreen> createState() => _SpectatorScreenState();
}

class _SpectatorScreenState extends State<SpectatorScreen> {
  bool _isLeaving = false;
  bool _chatOpen = false;
  bool _soundPanelOpen = false;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  Widget _buildRecoveryLoading({
    required String title,
    String? subtitle,
  }) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.14),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (subtitle != null && subtitle.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.82),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  int _lastChatMessageCount = 0;

  @override
  void dispose() {
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _leaveRoom(GameService game) {
    if (_isLeaving) return;
    _isLeaving = true;
    game.leaveRoom();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionService>();
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    // C9: Wrap in ConnectionOverlay for reconnection support
    return ConnectionOverlay(
      child: PopScope(
        canPop: false,
        child: Scaffold(
      resizeToAvoidBottomInset: false,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF8F4F6),
              Color(0xFFF0E8F0),
              Color(0xFFE8F0F8),
            ],
          ),
        ),
        child: SafeArea(
          bottom: !isLandscape,
          child: Consumer<GameService>(
            builder: (context, game, _) {
              if (session.isRestoring) {
                return _buildRecoveryLoading(
                  title: '관전 복구 중...',
                  subtitle: session.restoreStatusMessage,
                );
              }

              final destination = game.currentDestination;
              if (destination != AppDestination.spectator) {
                if (!_isLeaving) {
                  _isLeaving = true;
                }
                return _buildRecoveryLoading(
                  title: '관전 화면 전환 중...',
                  subtitle: '현재 관전 상태를 다시 확인하고 있습니다.',
                );
              }
              if (_isLeaving) {
                _isLeaving = false;
              }

              final state = game.spectatorGameState;
              if (!game.hasSpectatorGameState || state == null) {
                return _buildWaitingRoomView(context, game, isLandscape);
              }

              return _buildSpectatorView(context, game, state, isLandscape);
            },
          ),
        ),
      ),
    ),
    ),
    );
  }

  Widget _buildWaitingRoomView(
    BuildContext context,
    GameService game,
    bool isLandscape,
  ) {
    final players = game.roomPlayers;

    return Stack(
      children: [
        Column(
          children: [
            // Top bar
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE0D8D4)),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => _leaveRoom(game),
                    icon: const Icon(Icons.arrow_back, color: Color(0xFF6A5A52)),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8E0F8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.visibility, size: 14, color: Color(0xFF4A4080)),
                        SizedBox(width: 4),
                        Text(
                          '관전중',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF4A4080),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      game.currentRoomName,
                      style: const TextStyle(
                        color: Color(0xFF5A4038),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _buildSpectatorButton(game),
                  const SizedBox(width: 6),
                  _buildSoundButton(game),
                  const SizedBox(width: 6),
                  _buildChatButton(),
                ],
              ),
            ),

            // Player slots
            Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(isLandscape ? 12 : 20),
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: isLandscape ? 920 : 560,
                    ),
                    padding: EdgeInsets.all(isLandscape ? 20 : 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE0D8D4)),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFD9CCC8).withValues(alpha: 0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isLandscape)
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 20,
                            runSpacing: 20,
                            children: [
                              _buildWaitingTeamCard(
                                label: 'TEAM A',
                                color: const Color(0xFF6A9BD1),
                                children: [
                                  _buildPlayerSlot(game, players[0], 0),
                                  _buildPlayerSlot(game, players[2], 2),
                                ],
                              ),
                              _buildWaitingTeamCard(
                                label: 'TEAM B',
                                color: const Color(0xFFF5B8C0),
                                children: [
                                  _buildPlayerSlot(game, players[1], 1),
                                  _buildPlayerSlot(game, players[3], 3),
                                ],
                              ),
                            ],
                          )
                        else ...[
                          _buildWaitingTeamLabel(
                            label: 'TEAM A',
                            color: const Color(0xFF6A9BD1),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildPlayerSlot(game, players[0], 0),
                              const SizedBox(width: 16),
                              _buildPlayerSlot(game, players[2], 2),
                            ],
                          ),
                          const SizedBox(height: 24),
                          _buildWaitingTeamLabel(
                            label: 'TEAM B',
                            color: const Color(0xFFF5B8C0),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildPlayerSlot(game, players[1], 1),
                              const SizedBox(width: 16),
                              _buildPlayerSlot(game, players[3], 3),
                            ],
                          ),
                        ],
                        SizedBox(height: isLandscape ? 20 : 28),
                        // Waiting text
                        const Text(
                          '게임 시작 대기 중...',
                          style: TextStyle(
                            color: Color(0xFF8A8A8A),
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFB0A8A4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),

        // Sound panel overlay
        if (_soundPanelOpen) _buildSoundPanel(game),

        // Chat panel overlay
        if (_chatOpen) _buildChatPanel(game),
      ],
    );
  }

  Widget _buildWaitingTeamLabel({
    required String label,
    required Color color,
  }) {
    return Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 14,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildWaitingTeamCard({
    required String label,
    required Color color,
    required List<Widget> children,
  }) {
    return Container(
      width: 320,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F6F4),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6DDD8)),
      ),
      child: Column(
        children: [
          _buildWaitingTeamLabel(label: label, color: color),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: children,
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerSlot(GameService game, Player? player, int slotIndex) {
    final bool isEmpty = player == null;
    final String name = isEmpty ? '' : player.name;
    final bool isReady = isEmpty ? false : player.isReady;
    final bool isHost = isEmpty ? false : player.isHost;

    final content = Container(
      width: 130,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: isEmpty ? const Color(0xFFF7F2F0) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isEmpty
              ? const Color(0xFFD8CFCB)
              : isReady
                  ? const Color(0xFF9ED6A5)
                  : const Color(0xFFE0D8D4),
          width: isReady ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isEmpty ? Icons.person_add : Icons.person,
            color: isEmpty ? const Color(0xFF9AA7B0) : const Color(0xFF6A5A52),
            size: 30,
          ),
          const SizedBox(height: 8),
          Text(
            isEmpty ? '착석' : name,
            style: TextStyle(
              color: isEmpty ? const Color(0xFF9AA7B0) : const Color(0xFF5A4038),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          if (!isEmpty) ...[
            const SizedBox(height: 4),
            Text(
              isHost ? '방장' : (isReady ? '준비완료' : '대기중'),
              style: TextStyle(
                color: isHost
                    ? const Color(0xFFE6A800)
                    : isReady
                        ? const Color(0xFF4BAA6A)
                        : const Color(0xFF9A8E8A),
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );

    if (isEmpty) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => game.switchToPlayer(slotIndex),
          borderRadius: BorderRadius.circular(16),
          splashColor: Colors.blue.withValues(alpha: 0.2),
          child: content,
        ),
      );
    }

    return content;
  }

  Widget _buildSpectatorView(
    BuildContext context,
    GameService game,
    Map<String, dynamic> state,
    bool isLandscape,
  ) {
    final players = (state['players'] as List?) ?? [];
    final currentTrick = (state['currentTrick'] as List?) ?? [];
    final phase = state['phase'] ?? '';
    final totalScores = state['totalScores'] as Map<String, dynamic>? ?? {};
    final currentPlayer = state['currentPlayer'] ?? '';
    final round = state['round'] ?? 1;

    return Stack(
      children: [
        Column(
          children: [
            _buildTopBar(
              context,
              game,
              phase,
              round,
              totalScores,
              isLandscape,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: isLandscape
                    ? _buildLandscapeSpectatorBoard(
                        game,
                        players,
                        currentPlayer,
                        currentTrick,
                      )
                    : _buildPortraitSpectatorBoard(
                        game,
                        players,
                        currentPlayer,
                        currentTrick,
                      ),
              ),
            ),
          ],
        ),

        // Sound panel overlay
        if (_soundPanelOpen) _buildSoundPanel(game),

        // Chat panel overlay
        if (_chatOpen) _buildChatPanel(game),

        // Bug #10: Game end overlay for spectators
        if (phase == 'game_end')
          _buildGameEndOverlay(game, totalScores),
      ],
    );
  }

  Widget _buildPortraitSpectatorBoard(
    GameService game,
    List players,
    String currentPlayer,
    List currentTrick,
  ) {
    return Column(
      children: [
        if (players.length > 2)
          _buildPlayerSection(game, players[2], currentPlayer),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (players.length > 3)
                _buildPlayerSection(game, players[3], currentPlayer, isLeft: true),
              Expanded(
                child: _buildTrickArea(currentTrick),
              ),
              if (players.length > 1)
                _buildPlayerSection(game, players[1], currentPlayer, isRight: true),
            ],
          ),
        ),
        if (players.isNotEmpty)
          _buildPlayerSection(game, players[0], currentPlayer),
      ],
    );
  }

  Widget _buildLandscapeSpectatorBoard(
    GameService game,
    List players,
    String currentPlayer,
    List currentTrick,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cramped = constraints.maxHeight < 390;
        final compact = constraints.maxHeight < 520;
        final sideWidth = cramped
            ? 72.0
            : (constraints.maxHeight > 620 ? 104.0 : 86.0);
        final playerSlotHeight = (constraints.maxHeight *
                (cramped ? 0.20 : (compact ? 0.23 : 0.26)))
            .clamp(cramped ? 48.0 : 56.0, constraints.maxHeight > 620 ? 108.0 : 92.0);
        final trickSlotHeight = (constraints.maxHeight *
                (cramped ? 0.34 : (compact ? 0.40 : 0.46)))
            .clamp(cramped ? 76.0 : 88.0, constraints.maxHeight > 620 ? 180.0 : 132.0);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (players.length > 3)
              SizedBox(
                width: sideWidth,
                child: _buildScaledPlayerSection(
                  game,
                  players[3],
                  currentPlayer,
                  isLeft: true,
                  compact: compact,
                  forceScaleDown: cramped,
                ),
              ),
            if (players.length > 3) const SizedBox(width: 6),
            Expanded(
              child: Column(
                children: [
                  if (players.length > 2)
                    SizedBox(
                      height: playerSlotHeight,
                      child: _buildScaledPlayerSection(
                        game,
                        players[2],
                        currentPlayer,
                        compact: compact,
                        forceScaleDown: cramped,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: trickSlotHeight,
                          maxWidth: constraints.maxWidth,
                        ),
                        child: _buildTrickArea(
                          currentTrick,
                          compact: compact,
                          landscapeCompact: compact,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (players.isNotEmpty)
                    SizedBox(
                      height: playerSlotHeight,
                      child: _buildScaledPlayerSection(
                        game,
                        players[0],
                        currentPlayer,
                        compact: compact,
                        forceScaleDown: cramped,
                      ),
                    ),
                ],
              ),
            ),
            if (players.length > 1) const SizedBox(width: 6),
            if (players.length > 1)
              SizedBox(
                width: sideWidth,
                child: _buildScaledPlayerSection(
                  game,
                  players[1],
                  currentPlayer,
                  isRight: true,
                  compact: compact,
                  forceScaleDown: cramped,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildScaledPlayerSection(
    GameService game,
    Map<String, dynamic> player,
    String currentPlayerId, {
    bool isLeft = false,
    bool isRight = false,
    bool compact = false,
    bool forceScaleDown = false,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final child = ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: constraints.maxWidth,
            maxHeight: constraints.maxHeight,
          ),
          child: _buildPlayerSection(
            game,
            player,
            currentPlayerId,
            isLeft: isLeft,
            isRight: isRight,
            compact: compact,
          ),
        );
        return Align(
          alignment: Alignment.center,
          child: forceScaleDown
              ? FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: child,
                )
              : child,
        );
      },
    );
  }

  Widget _buildGameEndOverlay(GameService game, Map<String, dynamic> scores) {
    final teamA = scores['teamA'] ?? 0;
    final teamB = scores['teamB'] ?? 0;
    final winnerText = teamA > teamB ? 'Team A 승리!' : teamB > teamA ? 'Team B 승리!' : '무승부!';

    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                winnerText,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF5A4038),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Team A: $teamA | Team B: $teamB',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6A5A52),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '3초 후 대기실로 이동...',
                style: TextStyle(fontSize: 12, color: Color(0xFF8A7A72)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    GameService game,
    String phase,
    int round,
    Map<String, dynamic> scores,
    bool isLandscape,
  ) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: EdgeInsets.symmetric(
        horizontal: isLandscape ? 10 : 12,
        vertical: isLandscape ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0D8D4)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD9CCC8).withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: isLandscape
          ? Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                  onPressed: () => _leaveRoom(game),
                  icon: const Icon(
                    Icons.arrow_back,
                    color: Color(0xFF6A5A52),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8E0F8),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.visibility, size: 12, color: Color(0xFF4A4080)),
                      SizedBox(width: 3),
                      Text(
                        '관전중',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF4A4080),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'R$round | ${_getPhaseText(phase)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF8A7E78),
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _buildScoreChip(
                  'A',
                  scores['teamA'] ?? 0,
                  const Color(0xFF6A9BD1),
                  compact: true,
                ),
                const SizedBox(width: 4),
                _buildScoreChip(
                  'B',
                  scores['teamB'] ?? 0,
                  const Color(0xFFF5B8C0),
                  compact: true,
                ),
                const SizedBox(width: 6),
                _buildSpectatorButton(game),
                const SizedBox(width: 4),
                _buildSoundButton(game),
                const SizedBox(width: 4),
                _buildChatButton(),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => _leaveRoom(game),
                      icon: const Icon(Icons.arrow_back, color: Color(0xFF6A5A52)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8E0F8),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.visibility, size: 14, color: Color(0xFF4A4080)),
                          SizedBox(width: 4),
                          Text(
                            '관전중',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF4A4080),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    _buildSpectatorButton(game),
                    const SizedBox(width: 6),
                    _buildSoundButton(game),
                    const SizedBox(width: 6),
                    _buildChatButton(),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      'R$round | ${_getPhaseText(phase)}',
                      style:
                          const TextStyle(color: Color(0xFF8A7E78), fontSize: 12),
                    ),
                    const Spacer(),
                    _buildScoreChip(
                      'A',
                      scores['teamA'] ?? 0,
                      const Color(0xFF6A9BD1),
                    ),
                    const SizedBox(width: 6),
                    _buildScoreChip(
                      'B',
                      scores['teamB'] ?? 0,
                      const Color(0xFFF5B8C0),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildScoreChip(
    String label,
    dynamic score,
    Color color, {
    bool compact = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(compact ? 7 : 8),
      ),
      child: Text(
        '$label: $score',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: compact ? 11 : 12,
        ),
      ),
    );
  }

  String _getPhaseText(String phase) {
    switch (phase) {
      case 'large_tichu_phase':
        return '라지 티츄';
      case 'card_exchange':
        return '카드 교환';
      case 'playing':
        return '플레이 중';
      case 'round_end':
        return '라운드 종료';
      case 'game_end':
        return '게임 종료';
      default:
        return phase;
    }
  }

  Widget _buildPlayerSection(
    GameService game,
    Map<String, dynamic> player,
    String currentPlayerId, {
    bool isLeft = false,
    bool isRight = false,
    bool compact = false,
  }) {
    final playerId = player['id'] ?? '';
    final name = player['name'] ?? '';
    final cards = (player['cards'] as List?) ?? [];
    final cardCount = player['cardCount'] ?? 0;
    final canSeeCards = player['canSeeCards'] == true;
    final team = player['team'] ?? '';
    final isCurrentTurn = playerId == currentPlayerId;
    final hasFinished = player['hasFinished'] ?? false;
    final finishPosition = player['finishPosition'] ?? 0;
    final hasSmallTichu = player['hasSmallTichu'] ?? false;
    final hasLargeTichu = player['hasLargeTichu'] ?? false;
    final connected = player['connected'] ?? true;
    final vertical = isLeft || isRight;

    final isPending = game.pendingCardViewRequests.contains(playerId);
    final teamColor = team == 'A' ? const Color(0xFF6A9BD1) : const Color(0xFFF5B8C0);

    return Container(
      margin: EdgeInsets.all(compact ? 2 : 4),
      padding: EdgeInsets.all(compact ? 6 : 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrentTurn ? const Color(0xFFF3C97A) : const Color(0xFFE6DDD8),
          width: isCurrentTurn ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE5DAD6).withValues(alpha: 0.35),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Player name and status
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!connected)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.wifi_off, size: 12, color: Colors.red),
                )
              else
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: teamColor,
                    shape: BoxShape.circle,
                  ),
                ),
              Flexible(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: connected ? const Color(0xFF4E3A34) : Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: compact ? 11 : 12,
                  ),
                ),
              ),
              if (hasLargeTichu) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE86A6A),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'LT',
                    style: TextStyle(color: Colors.white, fontSize: 8),
                  ),
                ),
              ] else if (hasSmallTichu) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1A15F),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'T',
                    style: TextStyle(color: Colors.white, fontSize: 8),
                  ),
                ),
              ],
              if (hasFinished && finishPosition > 0) ...[
                const SizedBox(width: 4),
                Text(
                  '#$finishPosition',
                  style: const TextStyle(
                    color: Color(0xFF6BBE7A),
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          // Cards or request button
          if (hasFinished && cardCount == 0)
            Padding(
              padding: EdgeInsets.all(compact ? 6 : 8),
              child: Text(
                '완료',
                style: TextStyle(
                  color: const Color(0xFF9A8E8A),
                  fontSize: compact ? 9 : 10,
                ),
              ),
            )
          else if (canSeeCards && cards.isNotEmpty)
            vertical
                ? _buildRotatedCards(cards, isLeft: isLeft, compact: compact)
                : _buildHorizontalCards(cards, compact: compact)
          else
            _buildCardRequestArea(
              game,
              playerId,
              cardCount,
              isPending,
              vertical,
              compact: compact,
            ),
        ],
      ),
    );
  }

  Widget _buildRotatedCards(
    List cards, {
    bool isLeft = true,
    bool compact = false,
  }) {
    final cardWidth = compact ? 24.0 : 30.0;
    final cardHeight = compact ? 36.0 : 45.0;
    final overlap = compact ? 14.0 : 20.0;

    final totalHeight = cardHeight + (cards.length - 1) * overlap;
    // 좌측: 90도 (pi/2), 우측: 270도 (3*pi/2 = -pi/2)
    final angle = isLeft ? 1.5708 : -1.5708;

    return SizedBox(
      width: cardHeight + 4, // 회전 후 잘림 방지
      height: totalHeight.clamp(40.0, compact ? 180.0 : 300.0),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < cards.length; i++)
            Positioned(
              top: i * overlap,
              left: 0,
              child: SizedBox(
                width: cardHeight,
                height: cardHeight,
                child: Center(
                  child: Transform.rotate(
                    angle: angle,
                    child: SizedBox(
                      width: cardWidth,
                      height: cardHeight,
                      child: PlayingCard(
                        cardId: cards[i].toString(),
                        width: cardWidth,
                        height: cardHeight,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCardRequestArea(
    GameService game,
    String playerId,
    int cardCount,
    bool isPending,
    bool vertical, {
    bool compact = false,
  }) {
    if (isPending) {
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: compact ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFFFEFD8),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: compact ? 14 : 16,
              height: compact ? 14 : 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFF2A65A),
              ),
            ),
            SizedBox(height: compact ? 3 : 4),
            Text(
              '요청중... ($cardCount장)',
              style: TextStyle(
                color: const Color(0xFFB58343),
                fontSize: compact ? 9 : 10,
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () => game.requestCardView(playerId),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: compact ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF4FF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFB7D3EF)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.visibility,
              color: const Color(0xFF4F88C8),
              size: compact ? 16 : 20,
            ),
            SizedBox(height: compact ? 1 : 2),
            Text(
              '패 보기 요청 ($cardCount장)',
              style: TextStyle(
                color: const Color(0xFF4F88C8),
                fontSize: compact ? 9 : 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHorizontalCards(List cards, {bool compact = false}) {
    final cardWidth = compact ? 24.0 : 30.0;
    final cardHeight = compact ? 36.0 : 45.0;
    final overlap = compact ? 16.0 : 20.0;

    final totalWidth = cardWidth + (cards.length - 1) * overlap;

    return SizedBox(
      height: cardHeight,
      width: totalWidth.clamp(40.0, compact ? 200.0 : 280.0),
      child: Stack(
        children: [
          for (int i = 0; i < cards.length; i++)
            Positioned(
              left: i * overlap,
              child: SizedBox(
                width: cardWidth,
                height: cardHeight,
                child: PlayingCard(
                  cardId: cards[i].toString(),
                  width: cardWidth,
                  height: cardHeight,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSoundButton(GameService game) {
    final hasMuted = game.sfxVolume <= 0.01;
    return GestureDetector(
      onTap: () => setState(() => _soundPanelOpen = !_soundPanelOpen),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _soundPanelOpen
              ? const Color(0xFF81C784)
              : Colors.white.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFE0D8D4)),
        ),
        child: Icon(
          hasMuted ? Icons.volume_off : Icons.volume_up,
          color: _soundPanelOpen ? Colors.white : const Color(0xFF6A5A52),
          size: 18,
        ),
      ),
    );
  }

  Widget _buildSoundPanel(GameService game) {
    return Positioned(
      top: 96,
      right: 12,
      child: Container(
        width: 180,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '효과음',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF5A4038),
              ),
            ),
            Slider(
              value: game.sfxVolume,
              onChanged: (v) => game.setSfxVolume(v),
              onChangeEnd: (v) => game.setSfxVolume(v, persist: true),
              min: 0,
              max: 1,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpectatorButton(GameService game) {
    final count = game.spectators.length;
    return GestureDetector(
      onTap: () => _showSpectatorListDialog(game),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE0D8D4)),
            ),
            child: const Icon(
              Icons.people_alt,
              color: Color(0xFF6A5A52),
              size: 18,
            ),
          ),
          if (count > 0)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Color(0xFF7E57C2),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showSpectatorListDialog(GameService game) {
    final spectators = game.spectators;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.people_alt, color: Color(0xFF5A4038)),
            SizedBox(width: 8),
            Text('관전자 목록'),
          ],
        ),
        content: spectators.isEmpty
            ? const SizedBox(
                height: 60,
                child: Center(
                  child: Text(
                    '관전자가 없습니다',
                    style: TextStyle(color: Color(0xFF9A8E8A)),
                  ),
                ),
              )
            : SizedBox(
                width: 240,
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: spectators.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final name = spectators[i]['nickname'] ?? '';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        name,
                        style: const TextStyle(fontSize: 13, color: Color(0xFF5A4038)),
                      ),
                    );
                  },
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  Widget _buildChatButton() {
    return GestureDetector(
      onTap: () => setState(() {
        _chatOpen = !_chatOpen;
        if (_chatOpen) {
          _scrollChatToBottom();
        }
      }),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _chatOpen
              ? const Color(0xFF77B8E8)
              : Colors.white.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFE0D8D4)),
        ),
        child: Icon(
          Icons.chat_bubble_outline,
          color: _chatOpen ? Colors.white : const Color(0xFF6A5A52),
          size: 18,
        ),
      ),
    );
  }

  Widget _buildChatPanel(GameService game) {
    if (game.chatMessages.length != _lastChatMessageCount) {
      _lastChatMessageCount = game.chatMessages.length;
      _scrollChatToBottom();
    }
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height - media.viewInsets.bottom - 74;
    final panelHeight = maxHeight < 240
        ? 240.0
        : (maxHeight < 350 ? maxHeight : 350.0);
    final panelWidth = (media.size.width - 16).clamp(220.0, 320.0);

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      right: 8,
      top: 50,
      width: panelWidth,
      height: panelHeight,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF77B8E8),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Text(
                    '채팅',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => _chatOpen = false),
                    child: const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ],
              ),
            ),
            // Messages
            Expanded(
              child: ListView.builder(
                controller: _chatScrollController,
                padding: const EdgeInsets.all(8),
                itemCount: game.chatMessages.length,
                itemBuilder: (context, index) {
                  final msg = game.chatMessages[index];
                  final sender = msg['sender'] as String? ?? '';
                  final message = msg['message'] as String? ?? '';
                  final isMe = sender == game.playerName;
                  final isBlocked = game.isBlocked(sender);

                  if (isBlocked) return const SizedBox.shrink();

                  return _buildChatBubble(sender, message, isMe);
                },
              ),
            ),
            // Input
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _chatController,
                      decoration: const InputDecoration(
                        hintText: '메시지 입력...',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12),
                      ),
                      style: const TextStyle(fontSize: 14),
                      onSubmitted: (_) => _sendChatMessage(game),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _sendChatMessage(game),
                    icon: const Icon(Icons.send, color: Color(0xFF77B8E8)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatBubble(String sender, String message, bool isMe) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: const Color(0xFFE0E0E0),
              child: Text(
                sender.isNotEmpty ? sender[0] : '?',
                style: const TextStyle(fontSize: 12, color: Color(0xFF5A4038)),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      sender,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF8A8A8A)),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isMe ? const Color(0xFF64B5F6) : const Color(0xFFF0F0F0),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    message,
                    style: TextStyle(
                      fontSize: 14,
                      color: isMe ? Colors.white : const Color(0xFF333333),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.jumpTo(
          _chatScrollController.position.maxScrollExtent,
        );
      }
    });
  }

  void _sendChatMessage(GameService game) {
    final message = _chatController.text.trim();
    if (message.isEmpty) return;
    game.sendChatMessage(message);
    _chatController.clear();
    _scrollChatToBottom();
  }

  Widget _buildTrickArea(
    List currentTrick, {
    bool compact = false,
    bool landscapeCompact = false,
  }) {
    if (currentTrick.isEmpty) {
      return Center(
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 16,
            vertical: compact ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '새 판 시작',
            style: TextStyle(
              color: const Color(0xFF9A8E8A),
              fontSize: compact ? 12 : 14,
            ),
          ),
        ),
      );
    }

    final lastPlay = currentTrick.last;
    final playerName = lastPlay['playerName'] ?? '';
    final cards = (lastPlay['cards'] as List?) ?? [];

    // Alternate colors based on play index (even = blue, odd = pink)
    final playIndex = currentTrick.length - 1;
    final isBlue = playIndex % 2 == 0;
    final bgColor = isBlue ? const Color(0xFFE3F0FF) : const Color(0xFFFFE8EC);
    final borderColor = isBlue ? const Color(0xFFB3D4F7) : const Color(0xFFF5C0C8);
    final nameColor = isBlue ? const Color(0xFF4A90D9) : const Color(0xFFD94A5A);

    return Center(
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: playerName.length > 8 ? '${playerName.substring(0, 8)}..' : playerName,
                    style: TextStyle(
                      fontSize: compact ? 12 : 14,
                      fontWeight: FontWeight.bold,
                      color: nameColor,
                    ),
                  ),
                  TextSpan(
                    text: '가 낸 패',
                    style: TextStyle(
                      fontSize: compact ? 11 : 12,
                      color: const Color(0xFF8A7A72),
                    ),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: compact ? 4 : 6),
            _buildOverlappedCards(
              cards,
              compact: compact,
              forceSingleRow: landscapeCompact,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlappedCards(
    List cards, {
    bool compact = false,
    bool forceSingleRow = false,
  }) {
    final double cardW = compact ? 24 : 36;
    final double cardH = compact ? 34 : 50;
    final double minOverlap = compact ? 10 : 20;
    final double maxOverlap = compact ? 18 : 30;

    if (cards.length <= 4) {
      return Wrap(
        alignment: WrapAlignment.center,
        spacing: 3,
        children: cards
            .map((cardId) => PlayingCard(
                  cardId: cardId.toString(),
                  width: cardW,
                  height: cardH,
                  isInteractive: false,
                ))
            .toList(),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth - 16;
        final neededOverlap = cards.length > 1
            ? (availableWidth - cardW) / (cards.length - 1)
            : availableWidth;

        if (neededOverlap >= minOverlap || forceSingleRow) {
          final overlap =
              (forceSingleRow ? neededOverlap : neededOverlap.clamp(minOverlap, maxOverlap))
                  .clamp(compact ? 7.0 : minOverlap, maxOverlap);
          final totalWidth = cardW + overlap * (cards.length - 1);
          return Center(
            child: SizedBox(
              width: totalWidth.clamp(cardW, constraints.maxWidth),
              height: cardH,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (int i = 0; i < cards.length; i++)
                    Positioned(
                      left: i * overlap,
                      child: PlayingCard(
                        cardId: cards[i].toString(),
                        width: cardW,
                        height: cardH,
                        isInteractive: false,
                      ),
                    ),
                ],
              ),
            ),
          );
        }

        final mid = (cards.length + 1) ~/ 2;
        final row1 = cards.sublist(0, mid);
        final row2 = cards.sublist(mid);

        Widget buildRow(List rowCards) {
          final overlap = rowCards.length > 1
              ? ((availableWidth - cardW) / (rowCards.length - 1)).clamp(minOverlap, maxOverlap)
              : 0.0;
          final totalWidth = cardW + overlap * (rowCards.length - 1);
          return SizedBox(
            width: totalWidth,
            height: cardH,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (int i = 0; i < rowCards.length; i++)
                  Positioned(
                    left: i * overlap,
                    child: PlayingCard(
                      cardId: rowCards[i].toString(),
                      width: cardW,
                      height: cardH,
                      isInteractive: false,
                    ),
                  ),
              ],
            ),
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            buildRow(row1),
            const SizedBox(height: 4),
            buildRow(row2),
          ],
        );
      },
    );
  }
}
