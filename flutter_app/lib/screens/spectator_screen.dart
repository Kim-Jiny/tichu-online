import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n_helpers.dart';
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
                  title: L10n.of(context).spectatorRecovering,
                  subtitle: localizeRestorePhase(session, L10n.of(context)),
                );
              }

              final destination = game.currentDestination;
              if (destination != AppDestination.spectator) {
                if (!_isLeaving) {
                  _isLeaving = true;
                }
                return _buildRecoveryLoading(
                  title: L10n.of(context).spectatorTransitioning,
                  subtitle: L10n.of(context).spectatorRecheckingState,
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
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.visibility, size: 14, color: Color(0xFF4A4080)),
                        const SizedBox(width: 4),
                        Text(
                          L10n.of(context).spectatorWatching,
                          style: const TextStyle(
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
                        Text(
                          L10n.of(context).spectatorWaitingForGame,
                          style: const TextStyle(
                            color: Color(0xFF8A8A8A),
                            fontSize: 15,
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
            isEmpty ? L10n.of(context).spectatorSit : name,
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
              isHost ? L10n.of(context).spectatorHost : (isReady ? L10n.of(context).spectatorReady : L10n.of(context).spectatorWaiting),
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

    return GestureDetector(
      onTap: () => _showPlayerProfileDialog(name, game),
      child: content,
    );
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
    final l10n = L10n.of(context);
    final winnerText = teamA > teamB ? l10n.spectatorTeamWin('A') : teamB > teamA ? l10n.spectatorTeamWin('B') : l10n.spectatorDraw;

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
                l10n.spectatorTeamScores(teamA as int, teamB as int),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6A5A52),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.spectatorAutoReturn,
                style: const TextStyle(fontSize: 12, color: Color(0xFF8A7A72)),
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.visibility, size: 12, color: Color(0xFF4A4080)),
                      const SizedBox(width: 3),
                      Text(
                        L10n.of(context).spectatorWatching,
                        style: const TextStyle(
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
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.visibility, size: 14, color: Color(0xFF4A4080)),
                          const SizedBox(width: 4),
                          Text(
                            L10n.of(context).spectatorWatching,
                            style: const TextStyle(
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
    final l10n = L10n.of(context);
    switch (phase) {
      case 'large_tichu_phase':
        return l10n.spectatorPhaseLargeTichu;
      case 'card_exchange':
        return l10n.spectatorPhaseCardExchange;
      case 'playing':
        return l10n.spectatorPhasePlaying;
      case 'round_end':
        return l10n.spectatorPhaseRoundEnd;
      case 'game_end':
        return l10n.spectatorPhaseGameEnd;
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
                L10n.of(context).spectatorFinished,
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
              L10n.of(context).spectatorRequesting(cardCount),
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
              L10n.of(context).spectatorRequestCardView(cardCount),
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
            Text(
              L10n.of(context).spectatorSoundEffects,
              style: const TextStyle(
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
        title: Row(
          children: [
            const Icon(Icons.people_alt, color: Color(0xFF5A4038)),
            const SizedBox(width: 8),
            Text(L10n.of(context).spectatorListTitle),
          ],
        ),
        content: spectators.isEmpty
            ? SizedBox(
                height: 60,
                child: Center(
                  child: Text(
                    L10n.of(context).spectatorNoSpectators,
                    style: const TextStyle(color: Color(0xFF9A8E8A)),
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
            child: Text(L10n.of(context).spectatorClose),
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
                color: Color(0xFF64B5F6),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    L10n.of(context).spectatorChat,
                    style: const TextStyle(
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
                  String message = msg['message'] as String? ?? '';
                  if (message == 'chat_banned') {
                    final mins = msg['remainingMinutes'] as int? ?? 0;
                    message = localizeChatBanned(mins, L10n.of(context));
                  }
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
                      decoration: InputDecoration(
                        hintText: L10n.of(context).spectatorMessageHint,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
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
            L10n.of(context).spectatorNewTrick,
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
            Text(
              L10n.of(context).spectatorPlayedCards(
                playerName.length > 8 ? '${playerName.substring(0, 8)}..' : playerName,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 12 : 14,
                fontWeight: FontWeight.bold,
                color: nameColor,
              ),
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

  // ====================== PROFILE DIALOG ======================

  void _showPlayerProfileDialog(String nickname, GameService game) {
    game.requestProfile(nickname);

    showDialog(
      context: context,
      builder: (ctx) {
        return Consumer<GameService>(
          builder: (ctx, game, _) {
            final profile = game.profileFor(nickname);
            final isLoading = profile == null || profile['nickname'] != nickname;
            final isMe = nickname == game.playerName;
            final isBlockedUser = game.isBlocked(nickname);

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              titlePadding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
              contentPadding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
              title: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE8DDD8)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F0F7),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.person_outline,
                            color: Color(0xFF4F6B7A),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nickname,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF3E312A),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isMe ? L10n.of(context).gameMyProfile : L10n.of(context).gamePlayerProfile,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF84766E),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (!isMe) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (game.friends.contains(nickname))
                            _buildProfileIconButton(
                              icon: Icons.check,
                              color: const Color(0xFFBDBDBD),
                              tooltip: L10n.of(context).gameAlreadyFriend,
                              onTap: () {},
                            )
                          else if (game.sentFriendRequests.contains(nickname))
                            _buildProfileIconButton(
                              icon: Icons.hourglass_top,
                              color: const Color(0xFFBDBDBD),
                              tooltip: L10n.of(context).gameRequestPending,
                              onTap: () {},
                            )
                          else
                            _buildProfileIconButton(
                              icon: Icons.person_add,
                              color: const Color(0xFF81C784),
                              tooltip: L10n.of(context).gameAddFriend,
                              onTap: () {
                                game.addFriendAction(nickname);
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(L10n.of(context).gameFriendRequestSent)),
                                );
                              },
                            ),
                          _buildProfileIconButton(
                            icon: isBlockedUser ? Icons.block : Icons.shield_outlined,
                            color: isBlockedUser
                                ? const Color(0xFF64B5F6)
                                : const Color(0xFFFF8A65),
                            tooltip: isBlockedUser ? L10n.of(context).gameUnblock : L10n.of(context).gameBlock,
                            onTap: () {
                              if (isBlockedUser) {
                                game.unblockUserAction(nickname);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(L10n.of(context).gameUnblocked)),
                                );
                              } else {
                                game.blockUserAction(nickname);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(L10n.of(context).gameBlocked)),
                                );
                              }
                            },
                          ),
                          _buildProfileIconButton(
                            icon: Icons.flag,
                            color: const Color(0xFFE57373),
                            tooltip: L10n.of(context).gameReport,
                            onTap: () {
                              Navigator.pop(ctx);
                              _showReportDialog(nickname, game);
                            },
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              content: isLoading
                  ? const SizedBox(
                      height: 140,
                      width: 360,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 420,
                        maxHeight: 560,
                      ),
                      child: SingleChildScrollView(
                        child: _buildPlayerProfileContent(profile),
                      ),
                    ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(L10n.of(context).gameClose),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildProfileIconButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }

  Widget _buildPlayerProfileContent(Map<String, dynamic> data) {
    final profile = data['profile'] as Map<String, dynamic>?;
    if (profile == null) {
      return Text(L10n.of(context).gameProfileNotFound);
    }

    final totalGames = profile['totalGames'] ?? 0;
    final wins = profile['wins'] ?? 0;
    final losses = profile['losses'] ?? 0;
    final winRate = profile['winRate'] ?? 0;
    final seasonRating = profile['seasonRating'] ?? 1000;
    final seasonGames = profile['seasonGames'] ?? 0;
    final seasonWins = profile['seasonWins'] ?? 0;
    final seasonLosses = profile['seasonLosses'] ?? 0;
    final seasonWinRate = profile['seasonWinRate'] ?? 0;
    final level = profile['level'] ?? 1;
    final expTotal = profile['expTotal'] ?? 0;
    final leaveCount = profile['leaveCount'] ?? 0;
    final reportCount = profile['reportCount'] ?? 0;
    final bannerKey = profile['bannerKey']?.toString();
    final recentMatches = data['recentMatches'] as List<dynamic>? ?? [];
    final profileNickname = data['nickname']?.toString() ?? '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildProfileHeader(level as int, expTotal as int, bannerKey),
        const SizedBox(height: 8),
        _buildMannerLeaveRow(totalGames: totalGames as int, reportCount: reportCount as int, leaveCount: leaveCount as int),
        const SizedBox(height: 10),
        _buildProfileSectionCard(
          title: L10n.of(context).gameTichuSeasonRanked,
          accent: const Color(0xFF7A6A95),
          background: const Color(0xFFF6F3FA),
          icon: Icons.emoji_events,
          iconColor: const Color(0xFFFFD54F),
          mainText: '$seasonRating',
          chips: [
            _buildStatChip(L10n.of(context).gameStatRecord, L10n.of(context).gameRecordFormat(seasonGames as int, seasonWins as int, seasonLosses as int)),
            _buildStatChip(L10n.of(context).gameStatWinRate, '$seasonWinRate%'),
          ],
        ),
        const SizedBox(height: 10),
        _buildProfileSectionCard(
          title: L10n.of(context).gameOverallRecord,
          accent: const Color(0xFF5A4038),
          background: const Color(0xFFF5F5F5),
          icon: Icons.star,
          iconColor: const Color(0xFFFFB74D),
          mainText: '',
          chips: [
            _buildStatChip(L10n.of(context).gameStatRecord, L10n.of(context).gameRecordFormat(totalGames as int, wins as int, losses as int)),
            _buildStatChip(L10n.of(context).gameStatWinRate, '$winRate%'),
          ],
        ),
        const SizedBox(height: 12),
        _buildRecentMatches(recentMatches, profileNickname),
      ],
    );
  }

  Widget _buildProfileHeader(int level, int expTotal, String? bannerKey) {
    final expInLevel = expTotal % 100;
    final expPercent = expInLevel / 100;
    final banner = _bannerStyle(bannerKey);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: banner.gradient,
        color: banner.gradient == null ? Colors.white.withValues(alpha: 0.95) : null,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0D8D4)),
      ),
      child: Row(
        children: [
          Text(
            'Lv.$level',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF5A4038),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: expPercent,
                    minHeight: 6,
                    backgroundColor: const Color(0xFFEFE7E3),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF64B5F6)),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$expInLevel/100 EXP',
                  style: const TextStyle(fontSize: 9, color: Color(0xFF9A8E8A)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  _BannerStyle _bannerStyle(String? key) {
    switch (key) {
      case 'banner_pastel':
        return const _BannerStyle(gradient: LinearGradient(colors: [Color(0xFFF6C1C9), Color(0xFFF3E7EA)]));
      case 'banner_blossom':
        return const _BannerStyle(gradient: LinearGradient(colors: [Color(0xFFF7D6D0), Color(0xFFF3E9E6)]));
      case 'banner_mint':
        return const _BannerStyle(gradient: LinearGradient(colors: [Color(0xFFCDEBD8), Color(0xFFEFF8F2)]));
      case 'banner_sunset_7d':
        return const _BannerStyle(gradient: LinearGradient(colors: [Color(0xFFFFC3A0), Color(0xFFFFE5B4)]));
      case 'banner_season_gold':
        return const _BannerStyle(gradient: LinearGradient(colors: [Color(0xFFFFE082), Color(0xFFFFF3C0)]));
      case 'banner_season_silver':
        return const _BannerStyle(gradient: LinearGradient(colors: [Color(0xFFCFD8DC), Color(0xFFF1F3F4)]));
      case 'banner_season_bronze':
        return const _BannerStyle(gradient: LinearGradient(colors: [Color(0xFFD7B59A), Color(0xFFF4E8DC)]));
      default:
        return const _BannerStyle();
    }
  }

  Widget _buildMannerLeaveRow({required int totalGames, required int reportCount, required int leaveCount}) {
    final manner = _calcMannerScore(totalGames, leaveCount, reportCount);
    final color = _mannerColor(manner);
    final icon = _mannerIcon(manner);
    final l10n = L10n.of(context);
    final compact = MediaQuery.of(context).size.width < 400;
    final boxDeco = BoxDecoration(
      color: Colors.white.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE0D8D4)),
    );
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: boxDeco,
            child: compact
                ? Column(children: [
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(icon, color: color, size: 16),
                      const SizedBox(width: 4),
                      Flexible(child: Text(l10n.rankingMannerScore, style: const TextStyle(fontSize: 11, color: Color(0xFF8A8A8A)), overflow: TextOverflow.ellipsis)),
                    ]),
                    const SizedBox(height: 2),
                    Text('$manner', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
                  ])
                : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(icon, color: color, size: 16),
                    const SizedBox(width: 6),
                    Flexible(child: Text('${l10n.rankingMannerScore} $manner', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color), overflow: TextOverflow.ellipsis)),
                  ]),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: boxDeco,
            child: compact
                ? Column(children: [
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.warning_amber_rounded, color: Color(0xFFE57373), size: 16),
                      const SizedBox(width: 4),
                      Flexible(child: Text(l10n.gameDesertionLabel, style: const TextStyle(fontSize: 11, color: Color(0xFF8A8A8A)), overflow: TextOverflow.ellipsis)),
                    ]),
                    const SizedBox(height: 2),
                    Text('$leaveCount', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF9A6A6A))),
                  ])
                : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.warning_amber_rounded, color: Color(0xFFE57373), size: 16),
                    const SizedBox(width: 6),
                    Flexible(child: Text(l10n.gameDesertions(leaveCount), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF9A6A6A)), overflow: TextOverflow.ellipsis)),
                  ]),
          ),
        ),
      ],
    );
  }

  static int _calcMannerScore(int totalGames, int leaveCount, int reportCount) {
    int score = 1000;
    score -= leaveCount * 5;
    score -= reportCount * 3;
    score += (totalGames ~/ 10) * 5;
    return score.clamp(0, 1000);
  }

  static Color _mannerColor(int score) {
    if (score >= 800) return const Color(0xFF4CAF50);
    if (score >= 500) return const Color(0xFFFF9800);
    return const Color(0xFFE53935);
  }

  static IconData _mannerIcon(int score) {
    if (score >= 800) return Icons.sentiment_very_satisfied;
    if (score >= 500) return Icons.sentiment_neutral;
    return Icons.sentiment_very_dissatisfied;
  }

  Widget _buildProfileSectionCard({
    required String title,
    required Color accent,
    required Color background,
    required IconData icon,
    required Color iconColor,
    required String mainText,
    required List<Widget> chips,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: background.withValues(alpha: 0.6)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 16),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (mainText.isNotEmpty)
                Text(
                  mainText,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: accent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: chips,
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0D8D4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: Color(0xFF8A8A8A)),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Color(0xFF5A4038),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentMatches(List<dynamic> recentMatches, String profileNickname) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0D8D4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            L10n.of(context).gameRecentMatchesThree,
            style: const TextStyle(fontSize: 12, color: Color(0xFF8A8A8A)),
          ),
          const SizedBox(height: 8),
          if (recentMatches.isEmpty)
            Text(
              L10n.of(context).gameNoRecentMatches,
              style: const TextStyle(fontSize: 12, color: Color(0xFF9A8E8A)),
            )
          else
            Column(
              children: recentMatches.take(3).map<Widget>((match) {
                return _buildMatchRow(match, profileNickname);
              }).toList(),
            ),
        ],
      ),
    );
  }

  String _formatTeam(dynamic p1, dynamic p2) {
    final a = p1?.toString() ?? '-';
    final b = p2?.toString() ?? '-';
    return '$a·$b';
  }

  String _formatShortDate(dynamic value) {
    try {
      final dt = DateTime.parse(value.toString()).toLocal();
      return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return '-';
    }
  }

  Widget _buildMatchRow(dynamic match, String profileNickname) {
    final deserterNickname = match['deserterNickname']?.toString();
    final isDesertionLoss = match['isDesertionLoss'] == true ||
        (deserterNickname != null &&
            deserterNickname.isNotEmpty &&
            deserterNickname == profileNickname);
    final isDraw = match['isDraw'] == true;
    final won = !isDraw && match['won'] == true;
    final teamAScore = match['teamAScore'] ?? 0;
    final teamBScore = match['teamBScore'] ?? 0;
    final teamA = _formatTeam(match['playerA1'], match['playerA2']);
    final teamB = _formatTeam(match['playerB1'], match['playerB2']);
    final date = _formatShortDate(match['createdAt']);
    final isRanked = match['isRanked'] == true;

    final l10n = L10n.of(context);
    final Color badgeColor;
    final String badgeText;
    if (isDesertionLoss) {
      badgeColor = const Color(0xFFFFB74D);
      badgeText = l10n.gameMatchDesertion;
    } else if (isDraw) {
      badgeColor = const Color(0xFFBDBDBD);
      badgeText = l10n.gameMatchDraw;
    } else if (won) {
      badgeColor = const Color(0xFF81C784);
      badgeText = l10n.gameMatchWin;
    } else {
      badgeColor = const Color(0xFFE57373);
      badgeText = l10n.gameMatchLoss;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: badgeColor,
              shape: BoxShape.circle,
            ),
            child: Text(
              badgeText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      date,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8A8A8A),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: isRanked
                            ? const Color(0xFFFFF3E0)
                            : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isRanked ? l10n.gameMatchTypeRanked : l10n.gameMatchTypeNormal,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: isRanked
                              ? const Color(0xFFE65100)
                              : const Color(0xFF9E9E9E),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$teamA : $teamB',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5A4038),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            '$teamAScore : $teamBScore',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF5A4038),
            ),
          ),
        ],
      ),
    );
  }

  void _showReportDialog(String nickname, GameService game) {
    final reasonController = TextEditingController();
    final l10n = L10n.of(context);
    final reasons = [
      l10n.gameReportReasonAbuse,
      l10n.gameReportReasonSpam,
      l10n.gameReportReasonNickname,
      l10n.gameReportReasonGameplay,
      l10n.gameReportReasonOther,
    ];
    String? selectedReason;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (ctx, setState) {
          final media = MediaQuery.of(ctx);
          return AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  const Icon(Icons.flag, color: Color(0xFFE57373)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      L10n.of(context).gameReportTitle(nickname),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 420,
                  maxHeight: media.size.height * 0.55,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF1F1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFF0C7C7)),
                        ),
                        child: Text(
                          L10n.of(context).gameReportWarning,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF9A4A4A),
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          L10n.of(context).gameSelectReason,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: reasons.map((r) {
                          final isSelected = selectedReason == r;
                          return InkWell(
                            onTap: () => setState(() => selectedReason = r),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFFDDECF7)
                                    : const Color(0xFFF6F2F0),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFF9EC5E6)
                                      : const Color(0xFFE2D8D4),
                                ),
                              ),
                              child: Text(
                                r,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isSelected
                                      ? const Color(0xFF3E6D8E)
                                      : const Color(0xFF6A5A52),
                                  fontWeight:
                                      isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: reasonController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: L10n.of(context).gameReportDetailHint,
                          filled: true,
                          fillColor: const Color(0xFFF7F2F0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFE0D6D1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFE0D6D1)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFB9A8A1)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(L10n.of(context).gameCancel),
                ),
                ElevatedButton(
                  onPressed: selectedReason == null
                      ? null
                      : () {
                          final detail = reasonController.text.trim();
                          final reason = detail.isEmpty
                              ? selectedReason!
                              : '${selectedReason!} / $detail';
                          Navigator.pop(ctx);
                          game.reportResultSuccess = null;
                          game.reportResultMessage = null;
                          game.reportUserAction(nickname, reason);
                          late void Function() listener;
                          Timer? cleanupTimer;
                          listener = () {
                            if (game.reportResultMessage != null) {
                              game.removeListener(listener);
                              cleanupTimer?.cancel();
                              if (mounted) {
                                final success = game.reportResultSuccess == true;
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  SnackBar(
                                    content: Text(game.reportResultMessage!),
                                    backgroundColor:
                                        success ? null : const Color(0xFFE57373),
                                  ),
                                );
                              }
                              game.reportResultSuccess = null;
                              game.reportResultMessage = null;
                            }
                          };
                          game.addListener(listener);
                          cleanupTimer = Timer(const Duration(seconds: 10), () {
                            game.removeListener(listener);
                          });
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE57373),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(L10n.of(context).gameReportSubmit),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BannerStyle {
  const _BannerStyle({this.gradient});
  final LinearGradient? gradient;
}
