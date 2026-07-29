import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n_helpers.dart';
import '../models/player.dart';
import '../services/game_service.dart';
import '../utils/level_curve.dart';
import '../services/session_service.dart';
import '../widgets/playing_card.dart';
import '../widgets/connection_overlay.dart';
import '../widgets/draggable_chat_panel.dart';
import '../widgets/level_badge.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/player_profile_header.dart';
import '../widgets/title_chip.dart';
import '../widgets/spectator_controls.dart';

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
  int _readChatCount = 0;

  @override
  void initState() {
    super.initState();
    // Treat chat history that already exists when joining as read, so the
    // unread badge only counts messages received after entering.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final count = context.read<GameService>().chatMessages.length;
      setState(() {
        _readChatCount = count;
        _lastChatMessageCount = count;
      });
    });
  }

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
                  _buildChatButton(game),
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
                        if (game.currentGameType == 'tichu' && game.roomRandomSeating)
                          // Random-seating Tichu: flat SK-style list, no team
                          // framing (teams are randomized at game start).
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              for (int i = 0; i < players.length; i++)
                                _buildPlayerSlot(game, players[i], i),
                            ],
                          )
                        else if (isLandscape)
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

    final content = Container(
      width: 130,
      // Fixed height equalizes empty / filled-no-title / filled-with-title
      // states. Without this the title row added ~18px so empty slots
      // looked shorter than seated ones.
      height: 100,
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
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isEmpty ? Icons.person_add : Icons.person,
            color: isEmpty
                ? const Color(0xFF9AA7B0)
                : const Color(0xFF6A5A52),
            size: 28,
          ),
          const SizedBox(height: 6),
          if (!isEmpty && player.titleName != null) ...[
            TitleChip(
              titleKey: player.titleKey,
              titleName: player.titleName,
              fontSize: 10,
              iconSize: 10,
            ),
            const SizedBox(height: 2),
          ],
          if (isEmpty)
            Text(
              L10n.of(context).spectatorSit,
              style: const TextStyle(
                color: Color(0xFF9AA7B0),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (player.photoUrl != null || player.level != null) ...[
                  ProfileAvatar(
                    photoUrl: game.resolvePhotoUrl(player.photoUrl),
                    size: 18,
                    blocked: game.blockedUsers.contains(player.name),
                    fallback: player.level != null
                        ? LevelBadge(level: player.level, size: 18)
                        : const SizedBox(width: 18, height: 18),
                  ),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    name,
                    style: const TextStyle(
                      color: Color(0xFF5A4038),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          // Host status is conveyed by the 👑 overhang on the top-left and
          // ready status by the subtle check watermark behind the slot — no
          // textual status line is rendered so the layout doesn't shift.
        ],
      ),
    );

    final stacked = Stack(
      clipBehavior: Clip.none,
      children: [
        content,
        if (!isEmpty && isReady)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Icon(
                  Icons.check_circle,
                  size: 56,
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.18),
                ),
              ),
            ),
          ),
        if (!isEmpty && player.isHost)
          const Positioned(
            left: -2,
            top: -6,
            child: Text(
              '👑',
              style: TextStyle(fontSize: 18, height: 1.0),
            ),
          ),
      ],
    );

    if (isEmpty) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => game.switchToPlayer(slotIndex),
          borderRadius: BorderRadius.circular(16),
          splashColor: Colors.blue.withValues(alpha: 0.2),
          child: stacked,
        ),
      );
    }

    return GestureDetector(
      onTap: () => _showPlayerProfileDialog(name, game),
      child: stacked,
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
    final callRank = state['callRank'] as String?;
    final scoreHistory = (state['scoreHistory'] as List?) ?? [];

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
              scoreHistory,
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
                        callRank: callRank,
                      )
                    : _buildPortraitSpectatorBoard(
                        game,
                        players,
                        currentPlayer,
                        currentTrick,
                        callRank: callRank,
                      ),
              ),
            ),
          ],
        ),

        // Server error banner (e.g. "X has set always-deny" when a
        // card-view request fizzles). Plays the role of the in-game
        // _buildErrorBanner so spectators don't get silent no-ops.
        if (game.errorMessage != null)
          _buildSpectatorErrorBanner(game.errorMessage!),

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

  Widget _buildSpectatorErrorBanner(String message) {
    return Positioned(
      bottom: 80,
      left: 20,
      right: 20,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFEBEE),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE57373)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline, size: 16, color: Color(0xFFC62828)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  localizeServiceMessage(message, L10n.of(context)),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFFC62828),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPortraitSpectatorBoard(
    GameService game,
    List players,
    String currentPlayer,
    List currentTrick, {
    String? callRank,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Lock the left/right slot widths so a long nickname can't widen
        // the side column and pull the trick area off-center. Mirrors the
        // sideWidth pattern used in the landscape board.
        final sideWidth = (constraints.maxWidth * 0.22).clamp(76.0, 108.0);
        return Column(
          children: [
            if (players.length > 2)
              _buildPlayerSection(game, players[2], currentPlayer),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (players.length > 3)
                    SizedBox(
                      width: sideWidth,
                      child: _buildPlayerSection(
                        game,
                        players[3],
                        currentPlayer,
                        isLeft: true,
                      ),
                    ),
                  Expanded(
                    child: _buildTrickArea(
                      currentTrick,
                      callRank: callRank,
                      players: players,
                    ),
                  ),
                  if (players.length > 1)
                    SizedBox(
                      width: sideWidth,
                      child: _buildPlayerSection(
                        game,
                        players[1],
                        currentPlayer,
                        isRight: true,
                      ),
                    ),
                ],
              ),
            ),
            if (players.isNotEmpty)
              _buildPlayerSection(game, players[0], currentPlayer),
          ],
        );
      },
    );
  }

  Widget _buildLandscapeSpectatorBoard(
    GameService game,
    List players,
    String currentPlayer,
    List currentTrick, {
    String? callRank,
  }) {
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
                          callRank: callRank,
                          players: players,
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
    List scoreHistory,
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
                _buildScoreHistoryButton(game, scoreHistory, scores),
                const SizedBox(width: 4),
                _buildSpectatorButton(game),
                const SizedBox(width: 4),
                _buildSoundButton(game),
                const SizedBox(width: 4),
                _buildChatButton(game),
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
                    _buildScoreHistoryButton(game, scoreHistory, scores),
                    const SizedBox(width: 6),
                    _buildSpectatorButton(game),
                    const SizedBox(width: 6),
                    _buildSoundButton(game),
                    const SizedBox(width: 6),
                    _buildChatButton(game),
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
    final isCurrentTurn = playerId == currentPlayerId;
    final hasFinished = player['hasFinished'] ?? false;
    final finishPosition = player['finishPosition'] ?? 0;
    final hasSmallTichu = player['hasSmallTichu'] ?? false;
    final hasLargeTichu = player['hasLargeTichu'] ?? false;
    final connected = player['connected'] ?? true;
    final vertical = isLeft || isRight;

    final isPending = game.pendingCardViewRequests.contains(playerId);

    // Faint team tint as the slot background (replaces the removed dot
    // indicator) so spectators can still tell which team each player is on
    // at a glance. Team A → cool blue, Team B → warm rose.
    final team = player['team']?.toString() ?? '';
    final slotBg = team == 'A'
        ? const Color(0xFFE9F2FB)
        : team == 'B'
            ? const Color(0xFFFBECEF)
            : Colors.white.withValues(alpha: 0.98);

    return Container(
      margin: EdgeInsets.all(compact ? 2 : 4),
      padding: EdgeInsets.all(compact ? 6 : 8),
      decoration: BoxDecoration(
        color: slotBg,
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
                ),
              // Spectating a game used to be the one place a paid profile photo
              // never appeared: this view is separate from both the player's
              // game screen and the spectator waiting room, and only those two
              // had the avatar.
              if (player['photoUrl'] != null)
                Padding(
                  padding: EdgeInsets.only(right: compact ? 3 : 4),
                  child: ProfileAvatar(
                    photoUrl: game.resolvePhotoUrl(player['photoUrl'] as String?),
                    size: compact ? 16 : 20,
                    blocked: game.blockedUsers.contains(name),
                    fallback: SizedBox(
                      width: compact ? 16 : 20,
                      height: compact ? 16 : 20,
                    ),
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
      // Cap at a full 14-card hand height + small buffer. Previous
      // 180/300 caps clipped the last card when holding a full hand.
      height: totalHeight.clamp(40.0, compact ? 240.0 : 320.0),
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

    // Cap at a full 14-card hand width + small buffer. The previous
    // 200/280 caps clipped the rightmost card when a player held a full
    // hand (14 × 20 + 30 = 290 non-compact / 14 × 16 + 24 = 232 compact).
    return SizedBox(
      height: cardHeight,
      width: totalWidth.clamp(40.0, compact ? 244.0 : 304.0),
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
    return SpectatorActionButton(
      icon: game.sfxVolume <= 0.01 ? Icons.volume_off : Icons.volume_up,
      active: _soundPanelOpen,
      onTap: () => setState(() => _soundPanelOpen = !_soundPanelOpen),
    );
  }

  Widget _buildSoundPanel(GameService game) {
    return Positioned(
      top: 96,
      right: 12,
      child: SpectatorSoundPanel(game: game, width: 180),
    );
  }

  Widget _buildSpectatorButton(GameService game) {
    return SpectatorActionButton(
      icon: Icons.people_alt,
      active: false,
      badgeCount: game.spectators.length,
      onTap: () => showSpectatorListDialog(context, game.spectators),
    );
  }

  Widget _buildScoreHistoryButton(
    GameService game,
    List scoreHistory,
    Map<String, dynamic> scores,
  ) {
    return SpectatorActionButton(
      icon: Icons.history,
      active: false,
      onTap: () => showTichuScoreHistoryDialog(
        context,
        history: scoreHistory
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
        totalA: scores['teamA'] ?? 0,
        totalB: scores['teamB'] ?? 0,
      ),
    );
  }

  Widget _buildChatButton(GameService game) {
    return SpectatorActionButton(
      icon: Icons.chat_bubble_outline,
      active: _chatOpen,
      badgeCount: _chatOpen
          ? 0
          : (game.chatMessages.length - _readChatCount).clamp(0, 99),
      onTap: () => setState(() {
        _chatOpen = !_chatOpen;
        if (_chatOpen) {
          _readChatCount = game.chatMessages.length;
          _scrollChatToBottom();
        }
      }),
    );
  }

  Widget _buildChatPanel(GameService game) {
    if (game.chatMessages.length != _lastChatMessageCount) {
      _lastChatMessageCount = game.chatMessages.length;
      // Panel only builds while open, so keep the read marker current to
      // avoid a stale unread badge after the user closes the chat.
      _readChatCount = game.chatMessages.length;
      _scrollChatToBottom();
    }
    return DraggableChatPanel(
      accentColor: const Color(0xFF64B5F6),
      sendIconColor: const Color(0xFF77B8E8),
      title: L10n.of(context).spectatorChat,
      hintText: L10n.of(context).spectatorMessageHint,
      controller: _chatController,
      scrollController: _chatScrollController,
      onSend: () => _sendChatMessage(game),
      onClose: () => setState(() => _chatOpen = false),
      itemCount: game.chatMessages.length,
      itemBuilder: (context, index) {
        final msg = game.chatMessages[game.chatMessages.length - 1 - index];
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
            // Chat lines carry only a nickname, so the photo comes from whatever
            // roster is loaded; the initial-letter circle stays as the fallback.
            ProfileAvatar(
              photoUrl: context.read<GameService>().chatPhotoUrlFor(sender),
              size: 28,
              blocked: context.read<GameService>().blockedUsers.contains(sender),
              fallback: CircleAvatar(
                radius: 14,
                backgroundColor: const Color(0xFFE0E0E0),
                child: Text(
                  sender.isNotEmpty ? sender[0] : '?',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF5A4038)),
                ),
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
    // ListView is reverse:true so offset 0 == bottom.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScrollController.hasClients) return;
      _chatScrollController.jumpTo(0);
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
    String? callRank,
    List players = const [],
  }) {
    final hasCall = callRank != null && callRank.isNotEmpty;

    Widget callBadge() {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0x33FF4444),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFF4444), width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🐦', style: TextStyle(fontSize: 11)),
            const SizedBox(width: 3),
            Text(
              L10n.of(context).gameCall(callRank!),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFF4444),
              ),
            ),
          ],
        ),
      );
    }

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                L10n.of(context).spectatorNewTrick,
                style: TextStyle(
                  color: const Color(0xFF9A8E8A),
                  fontSize: compact ? 12 : 14,
                ),
              ),
              if (hasCall) ...[
                SizedBox(height: compact ? 4 : 6),
                callBadge(),
              ],
            ],
          ),
        ),
      );
    }

    final lastPlay = currentTrick.last;
    final playerName = lastPlay['playerName'] ?? '';
    final cards = (lastPlay['cards'] as List?) ?? [];
    final lastCombo = (lastPlay['combo'] ?? '') as String;
    final lastComboValue = (lastPlay['comboValue'] as num?)?.toDouble() ?? 0;

    // Color by the playing player's team so the trick box matches the seat
    // tint (Team A → blue, Team B → rose). Falls back to blue when the team
    // can't be resolved. Previously this alternated by play index, which
    // clashed with the team-colored seats.
    final lastPlayerId = (lastPlay['playerId'] ?? '').toString();
    String lastTeam = '';
    for (final p in players) {
      if (p is Map && (p['id']?.toString() ?? '') == lastPlayerId) {
        lastTeam = p['team']?.toString() ?? '';
        break;
      }
    }
    final isBlue = lastTeam != 'B';
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
            if (hasCall) ...[
              callBadge(),
              SizedBox(height: compact ? 4 : 6),
            ],
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
              combo: lastCombo,
              comboValue: lastComboValue,
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
    String combo = '',
    double comboValue = 0,
  }) {
    final double cardW = compact ? 24 : 36;
    final double cardH = compact ? 34 : 50;
    final double minOverlap = compact ? 10 : 20;
    final double maxOverlap = compact ? 18 : 30;

    final isPhoenixSingleTrick = combo == 'single'
        && cards.length == 1
        && cards[0].toString() == 'special_phoenix'
        && comboValue > 1;
    final String? phoenixBeatLabel =
        isPhoenixSingleTrick ? _phoenixBeatLabel(comboValue) : null;

    Widget playingCard(String cardId) {
      final card = PlayingCard(
        cardId: cardId,
        width: cardW,
        height: cardH,
        isInteractive: false,
      );
      if (cardId != 'special_phoenix' || phoenixBeatLabel == null) return card;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          card,
          Positioned(
            right: -4,
            bottom: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFFFC107),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                phoenixBeatLabel,
                style: TextStyle(
                  fontSize: compact ? 8 : 9,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF5A4038),
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (cards.length <= 4) {
      return Wrap(
        alignment: WrapAlignment.center,
        spacing: 3,
        children: cards.map((c) => playingCard(c.toString())).toList(),
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

  String _phoenixBeatLabel(double comboValue) {
    final beat = comboValue.floor();
    if (beat >= 14) return '↑A';
    if (beat == 13) return '↑K';
    if (beat == 12) return '↑Q';
    if (beat == 11) return '↑J';
    return '↑$beat';
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
                    PlayerProfileHeader(
                      nickname: nickname,
                      profile: profile,
                      game: game,
                      subtitle: L10n.of(context).gamePlayerProfile,
                      subtitleBuilder: (inner) => _buildProfileSubtitle(
                        (inner?['level'] as int?) ?? 1,
                        (inner?['expTotal'] as int?) ?? 0,
                      ),
                      onCloseDialog: () => Navigator.pop(ctx),
                    ),
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
    final leaveCount = profile['leaveCount'] ?? 0;
    final reportCount = profile['reportCount'] ?? 0;
    final recentMatches = data['recentMatches'] as List<dynamic>? ?? [];
    final profileNickname = data['nickname']?.toString() ?? '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
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

  Widget _buildProfileSubtitle(int level, int expTotal) {
    final p = LevelCurve.progress(level, expTotal);
    return Row(
      children: [
        Text(
          'Lv.$level',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF5A4038),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: p.fraction,
              minHeight: 4,
              backgroundColor: const Color(0xFFEFE7E3),
              valueColor: const AlwaysStoppedAnimation(Colors.black),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '${p.expInLevel}/${p.expToNext}',
          style: const TextStyle(fontSize: 9, color: Color(0xFF9A8E8A)),
        ),
      ],
    );
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

}

