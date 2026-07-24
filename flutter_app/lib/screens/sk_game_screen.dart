import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/game_service.dart';
import '../services/session_service.dart';
import '../models/sk_game_state.dart';
import '../models/player.dart';
import '../widgets/connection_overlay.dart';
import '../widgets/level_badge.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/draggable_chat_panel.dart';
import '../widgets/spectator_controls.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n_helpers.dart';

class SKGameScreen extends StatefulWidget {
  const SKGameScreen({super.key});

  @override
  State<SKGameScreen> createState() => _SKGameScreenState();
}

class _SKGameScreenState extends State<SKGameScreen> {
  int? _selectedBid;
  String? _selectedCard;
  String? _viewingPlayerId;
  Timer? _cardViewRequestTimer;
  int _lastBiddingRound = -1;
  // Pre-select tracking: remember the last trick number we saw so we can
  // drop a queued card when a new trick starts (lead suit changes).
  int _lastSkTrickNumber = -1;
  bool _chatOpen = false;
  bool _soundPanelOpen = false;
  bool _moreOpen = false;
  int _readChatCount = 0;
  bool _viewersOpen = false;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  int _lastChatMessageCount = 0;

  // Timer
  Timer? _countdownTimer;
  Timer? _gameEndCountdownTimer;
  int _remainingSeconds = 0;
  int _gameEndCountdown = 3;
  bool _gameEndCountdownActive = false;
  bool _waitingForRoomRecovery = false;
  GameService? _gameService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gameService = context.read<GameService>();
      _gameService!.requestBlockedUsers();
      _readChatCount = _gameService!.chatMessages.length;
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateCountdown();
    });
  }

  Future<void> _recoverRoomState() async {
    if (_waitingForRoomRecovery) return;
    _waitingForRoomRecovery = true;
    await context.read<GameService>().checkRoomAndWait();
    if (!mounted) return;
    setState(() => _waitingForRoomRecovery = false);
  }

  @override
  void dispose() {
    _chatController.dispose();
    _chatScrollController.dispose();
    _countdownTimer?.cancel();
    _gameEndCountdownTimer?.cancel();
    _cardViewRequestTimer?.cancel();
    super.dispose();
  }

  void _updateCountdown() {
    if (!mounted) return;
    final state = _gameService?.skGameState;
    if (state == null || state.turnDeadline == null) {
      if (_remainingSeconds != 0) setState(() => _remainingSeconds = 0);
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final remaining = ((state.turnDeadline! - now) / 1000).ceil().clamp(0, 999);
    if (remaining != _remainingSeconds) {
      setState(() => _remainingSeconds = remaining);
    }
  }

  void _syncGameEndCountdown(String phase) {
    if (phase == 'game_end') {
      if (_gameEndCountdownActive) return;
      _gameEndCountdownActive = true;
      _gameEndCountdown = 3;
      _gameEndCountdownTimer?.cancel();
      _gameEndCountdownTimer = Timer.periodic(const Duration(seconds: 1), (
        timer,
      ) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        if (_gameEndCountdown <= 1) {
          timer.cancel();
          setState(() => _gameEndCountdown = 0);
          // Fallback: return to room if server hasn't already transitioned us
          _gameService?.returnToRoom();
          return;
        }
        setState(() => _gameEndCountdown -= 1);
      });
      return;
    }

    if (_gameEndCountdownActive) {
      _gameEndCountdownActive = false;
      _gameEndCountdownTimer?.cancel();
      _gameEndCountdown = 3;
    }
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

  @override
  Widget build(BuildContext context) {
    final themeColors = context.watch<GameService>().themeGradient;
    final session = context.watch<SessionService>();

    return ConnectionOverlay(
      child: PopScope(
        canPop: false,
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: themeColors,
              ),
            ),
            child: SafeArea(
              child: Consumer<GameService>(
                builder: (context, game, _) {
                  if (session.isRestoring || _waitingForRoomRecovery) {
                    return _buildRecoveryLoading(
                      title: session.isRestoring
                          ? L10n.of(context).skGameRecoveringGame
                          : L10n.of(context).skGameCheckingState,
                    );
                  }

                  final state = game.skGameState;
                  final isSpectating = game.isSpectator;
                  if (isSpectating &&
                      game.hasRoom &&
                      !game.hasActiveGame &&
                      state == null) {
                    return _buildSpectatorWaitingRoom(game);
                  }
                  if (state == null) {
                    if (game.hasRoom) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _recoverRoomState();
                      });
                      return _buildRecoveryLoading(
                        title: L10n.of(context).skGameReloadingRoom,
                      );
                    }
                    return _buildRecoveryLoading(
                      title: L10n.of(context).skGameLoadingState,
                    );
                  }

                  // A partial/early reconnect snapshot can arrive with an
                  // empty player list; several builders below resolve the self
                  // player via players.firstWhere(..., orElse: players.first),
                  // which throws StateError on an empty list. Hold on the
                  // loading view until the roster is populated.
                  if (state.players.isEmpty) {
                    return _buildRecoveryLoading(
                      title: L10n.of(context).skGameLoadingState,
                    );
                  }

                  _syncGameEndCountdown(state.phase);

                  // Clear selected card and bid when a NEW round's bidding starts
                  if (state.phase == 'bidding' &&
                      state.round != _lastBiddingRound) {
                    _lastBiddingRound = state.round;
                    if (_selectedCard != null || _selectedBid != null) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() {
                            _selectedCard = null;
                            _selectedBid = null;
                          });
                        }
                      });
                    }
                  }
                  // Clear selected card if it's no longer in hand
                  if (_selectedCard != null &&
                      !state.myCards.contains(_selectedCard)) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _selectedCard = null);
                    });
                  }
                  // Clear queued pre-selection on trick boundaries: the lead
                  // suit changes each new trick, so yesterday's pick may no
                  // longer be legal.
                  if (_lastSkTrickNumber != state.trickNumber) {
                    if (_lastSkTrickNumber != -1 && _selectedCard != null) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        setState(() => _selectedCard = null);
                      });
                    }
                    _lastSkTrickNumber = state.trickNumber;
                  }

                  if (isSpectating) {
                    return Stack(
                      children: [
                        Column(
                          children: [
                            _buildSpectatorTopBar(state, game),
                            if ([
                              'bidding',
                              'playing',
                              'trick_end',
                            ].contains(state.phase))
                              _buildBoardStage(
                                board: _buildSpectatorScoreboard(state, game),
                                bottomOverlay: _buildSpectatorBottomOverlay(
                                  _buildSpectatorHandArea(state, game),
                                ),
                              ),
                            if (state.phase == 'round_end')
                              _buildBoardStage(
                                board: _buildSpectatorScoreboard(state, game),
                                bottomOverlay: _buildRoundEndUI(state),
                              ),
                            if (state.phase == 'game_end')
                              _buildBoardStage(
                                board: _buildSpectatorScoreboard(state, game),
                                bottomOverlay: _buildGameEndUI(state, game),
                              ),
                          ],
                        ),
                        if (_moreOpen) _buildMoreMenu(game),
                        if (_soundPanelOpen) _buildSoundPanel(game),
                        if (_chatOpen) _buildChatPanel(game),
                      ],
                    );
                  }

                  return Stack(
                    children: [
                      Column(
                        children: [
                          _buildTopBar(state, game),
                          if (state.phase == 'bidding') ...[
                            _buildBoardStage(
                              board: _buildScoreboard(state, game),
                              bottomOverlay: SingleChildScrollView(
                                child: _buildBiddingUI(state, game),
                              ),
                            ),
                          ],
                          if (state.phase == 'playing' ||
                              state.phase == 'trick_end')
                            _buildBoardStage(
                              board: _buildScoreboard(state, game),
                              bottomOverlay: _buildHandArea(state, game),
                            ),
                          if (state.phase == 'round_end')
                            _buildBoardStage(
                              board: _buildScoreboard(state, game),
                              bottomOverlay: _buildRoundEndUI(state),
                            ),
                          if (state.phase == 'game_end')
                            _buildBoardStage(
                              board: _buildScoreboard(state, game),
                              bottomOverlay: _buildGameEndUI(state, game),
                            ),
                        ],
                      ),
                      if (game.errorMessage != null)
                        _buildSKErrorBanner(game.errorMessage!),
                      if (game.timeoutPlayerName != null)
                        _buildSKTimeoutBanner(game.timeoutPlayerName!),
                      if (game.desertedPlayerName != null)
                        _buildSKDesertionBanner(
                          game.desertedPlayerName!,
                          game.desertedReason ?? 'leave',
                        ),
                      if (game.hasIncomingCardViewRequests)
                        _buildCardViewRequestPopup(game),
                      if (_moreOpen) _buildMoreMenu(game),
                      if (_viewersOpen) _buildViewersPanel(game),
                      if (_soundPanelOpen) _buildSoundPanel(game),
                      if (_chatOpen) _buildChatPanel(game),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBoardStage({required Widget board, Widget? bottomOverlay}) {
    final bottomPadding = bottomOverlay is _SKSpectatorHandAreaMarker
        ? 50.0
        : 120.0;
    return Expanded(
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomPadding),
              child: board,
            ),
          ),
          if (bottomOverlay != null)
            Align(alignment: Alignment.bottomCenter, child: bottomOverlay),
        ],
      ),
    );
  }

  Widget _buildSpectatorBottomOverlay(Widget child) {
    return _SKSpectatorHandAreaMarker(child: child);
  }

  Widget _buildRecoveryLoading({required String title}) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
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
          ],
        ),
      ),
    );
  }

  Widget _buildSpectatorWaitingRoom(GameService game) {
    final slots = game.roomPlayers;
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          child: Column(
            children: [
              _buildSpectatorRoomHeader(game),
              const SizedBox(height: 14),
              Expanded(
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 760),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFE0D8D4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          L10n.of(context).skGameSpectatorWaitingTitle,
                          style: const TextStyle(
                            color: Color(0xFF3E312A),
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          L10n.of(context).skGameSpectatorWaitingDesc,
                          style: TextStyle(
                            color: const Color(
                              0xFF6A5A52,
                            ).withValues(alpha: 0.92),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, gridConstraints) {
                              final wide = gridConstraints.maxWidth > 620;
                              return GridView.builder(
                                // Top padding gives the host 👑 overhang on
                                // the first row room to render without being
                                // clipped by GridView's default Clip.hardEdge.
                                padding: const EdgeInsets.only(top: 6),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: wide ? 2 : 1,
                                      mainAxisSpacing: 10,
                                      crossAxisSpacing: 12,
                                      childAspectRatio: wide ? 4.8 : 4.4,
                                    ),
                                itemCount: slots.length,
                                itemBuilder: (context, index) {
                                  return _buildSpectatorSlot(
                                    game,
                                    slots[index],
                                    index,
                                  );
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          L10n.of(context).spectatorWaitingForGame,
                          style: const TextStyle(
                            color: Color(0xFF8A8A8A),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_soundPanelOpen) _buildSoundPanel(game),
        if (_chatOpen) _buildChatPanel(game),
      ],
    );
  }

  Widget _buildSpectatorSlot(GameService game, Player? player, int slotIndex) {
    final bool isBlocked = game.roomBlockedSlots.contains(slotIndex);
    final bool isEmpty = player == null;

    if (isBlocked) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF0EDED),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFD8CFCB)),
        ),
        child: const Row(
          children: [
            Icon(Icons.block, size: 24, color: Color(0xFFBDB5B0)),
            SizedBox(width: 10),
            Text('', style: TextStyle(color: Color(0xFFBDB5B0), fontSize: 13)),
          ],
        ),
      );
    }

    if (isEmpty) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => game.switchToPlayer(slotIndex),
          borderRadius: BorderRadius.circular(16),
          splashColor: Colors.blue.withValues(alpha: 0.2),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F2F0),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFD8CFCB)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.person_add,
                  size: 24,
                  color: Color(0xFF9AA7B0),
                ),
                const SizedBox(width: 10),
                Text(
                  L10n.of(context).spectatorSit,
                  style: const TextStyle(
                    color: Color(0xFF9AA7B0),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final p = player;
    final bool isReady = p.isReady;
    return GestureDetector(
      onTap: () => _showPlayerProfileDialog(p.name, game),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isReady
                    ? const Color(0xFF9ED6A5)
                    : const Color(0xFFE0D8D4),
                width: isReady ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                ProfileAvatar(
                  photoUrl: game.resolvePhotoUrl(p.photoUrl),
                  size: 36,
                  blocked: game.blockedUsers.contains(p.name),
                  fallback: p.level != null
                      ? LevelBadge(level: p.level, size: 36)
                      : Container(
                          width: 36,
                          height: 36,
                          decoration: const BoxDecoration(
                            color: Color(0xFFF2ECE8),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.person,
                            size: 18,
                            color: Color(0xFF6A5A52),
                          ),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF3E312A),
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      // Host = 👑 overhang, ready = background check watermark.
                      // No textual status line so the layout stays stable.
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (isReady)
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
          if (p.isHost)
            const Positioned(
              left: -2,
              top: -6,
              child: Text(
                '👑',
                style: TextStyle(fontSize: 18, height: 1.0),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSpectatorRoomHeader(GameService game) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF21455F).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => game.leaveRoom(),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              L10n.of(context).skGameSpectatorStandby,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              game.currentRoomName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _buildTopActionButton(
            icon: Icons.people_alt,
            active: false,
            badgeCount: game.spectators.length,
            onTap: () => _showSpectatorListDialog(game),
          ),
          const SizedBox(width: 6),
          _buildTopActionButton(
            icon: game.sfxVolume <= 0.01 ? Icons.volume_off : Icons.volume_up,
            active: _soundPanelOpen,
            onTap: () {
              setState(() {
                _soundPanelOpen = !_soundPanelOpen;
                if (_soundPanelOpen) _chatOpen = false;
              });
            },
          ),
          const SizedBox(width: 6),
          _buildTopActionButton(
            icon: Icons.chat_bubble_outline_rounded,
            active: _chatOpen,
            badgeCount: _chatOpen
                ? 0
                : (game.chatMessages.length - _readChatCount).clamp(0, 99),
            onTap: () {
              setState(() {
                _chatOpen = !_chatOpen;
                if (_chatOpen) {
                  _readChatCount = game.chatMessages.length;
                  _soundPanelOpen = false;
                }
              });
            },
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
            Flexible(
              child: Text(
                L10n.of(context).skGameSpectatorListTitle,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: spectators.isEmpty
            ? SizedBox(
                height: 60,
                child: Center(
                  child: Text(
                    L10n.of(context).skGameNoSpectators,
                    style: const TextStyle(color: Color(0xFF9A8E8A)),
                  ),
                ),
              )
            : SizedBox(
                width: double.maxFinite,
                height: 220,
                child: ListView.separated(
                  itemCount: spectators.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final nickname = spectators[index]['nickname'] ?? '';
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F1F1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE0D8D4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.person,
                            size: 16,
                            color: Color(0xFF6A5A52),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              nickname,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF5A4038),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(L10n.of(context).commonClose),
          ),
        ],
      ),
    );
  }

  // ── Top Bar ──
  Widget _buildTopBar(SKGameStateData state, GameService game) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          // Round/Trick info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFCCCCCC)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.anchor, size: 14, color: Color(0xFF5A4038)),
                const SizedBox(width: 5),
                Text(
                  L10n.of(
                    context,
                  ).skGameRoundTrick(state.round, state.trickNumber),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5A4038),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          if (state.expansions.isNotEmpty) ...[
            _buildTopActionButton(
              icon: Icons.help_outline,
              active: false,
              onTap: () => _showExpansionGuide(state),
            ),
            const SizedBox(width: 6),
          ],
          _buildTopActionButton(
            icon: Icons.history_rounded,
            active: false,
            onTap: () => _showScoreHistoryDialog(state),
          ),
          const SizedBox(width: 6),
          _buildTopActionButton(
            icon: Icons.chat_bubble_outline_rounded,
            active: _chatOpen,
            badgeCount: _chatOpen
                ? 0
                : (game.chatMessages.length - _readChatCount).clamp(0, 99),
            onTap: () {
              setState(() {
                _chatOpen = !_chatOpen;
                if (_chatOpen) {
                  _readChatCount = game.chatMessages.length;
                  _moreOpen = false;
                  _soundPanelOpen = false;
                  _viewersOpen = false;
                }
              });
            },
          ),
          const SizedBox(width: 6),
          _buildTopActionButton(
            icon: Icons.more_horiz,
            active: _moreOpen,
            onTap: () {
              setState(() {
                _moreOpen = !_moreOpen;
                if (_moreOpen) {
                  _chatOpen = false;
                  _soundPanelOpen = false;
                  _viewersOpen = false;
                } else {
                  _soundPanelOpen = false;
                }
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSpectatorTopBar(SKGameStateData state, GameService game) {
    if (state.players.isEmpty) return const SizedBox.shrink();
    final displayId = state.phase == 'bidding'
        ? state.roundStarter
        : state.currentPlayer;
    final currentPlayerName = state.players
        .firstWhere((p) => p.id == displayId, orElse: () => state.players.first)
        .name;

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF21455F).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.visibility_rounded,
                  size: 14,
                  color: Colors.white,
                ),
                const SizedBox(width: 5),
                Text(
                  L10n.of(context).skGameSpectating,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  L10n.of(
                    context,
                  ).skGameRoundTrick(state.round, state.trickNumber),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  state.phase == 'bidding'
                      ? L10n.of(
                          context,
                        ).skGameBiddingInProgress(currentPlayerName)
                      : L10n.of(context).skGamePlayerTurn(currentPlayerName),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (state.expansions.isNotEmpty) ...[
            _buildTopActionButton(
              icon: Icons.help_outline,
              active: false,
              onTap: () => _showExpansionGuide(state),
            ),
            const SizedBox(width: 6),
          ],
          _buildTopActionButton(
            icon: Icons.history_rounded,
            active: false,
            onTap: () => _showScoreHistoryDialog(state),
          ),
          const SizedBox(width: 6),
          _buildTopActionButton(
            icon: Icons.chat_bubble_outline_rounded,
            active: _chatOpen,
            badgeCount: _chatOpen
                ? 0
                : (game.chatMessages.length - _readChatCount).clamp(0, 99),
            onTap: () {
              setState(() {
                _chatOpen = !_chatOpen;
                if (_chatOpen) {
                  _readChatCount = game.chatMessages.length;
                  _moreOpen = false;
                  _soundPanelOpen = false;
                }
              });
            },
          ),
          const SizedBox(width: 6),
          _buildTopActionButton(
            icon: Icons.more_horiz,
            active: _moreOpen,
            onTap: () {
              setState(() {
                _moreOpen = !_moreOpen;
                if (_moreOpen) {
                  _chatOpen = false;
                  _soundPanelOpen = false;
                } else {
                  _soundPanelOpen = false;
                }
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMoreMenu(GameService game) {
    final hasViewers = game.cardViewers.isNotEmpty;
    return Positioned(
      top: 58,
      right: 8,
      child: Container(
        // Players see 4 actions (incl. card-view); spectators have no cards so
        // the card-view button is hidden and the menu is narrower.
        width: game.isSpectator ? 158 : 210,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildTopActionButton(
              icon: Icons.people_alt,
              active: false,
              badgeCount: game.spectators.length,
              onTap: () {
                setState(() {
                  _moreOpen = false;
                  _soundPanelOpen = false;
                });
                _showSpectatorListDialog(game);
              },
            ),
            // Card-view policy controls — players only (spectators have no
            // cards for anyone to view). Always shown for players so even
            // always_deny users can reach the policy UI.
            if (!game.isSpectator)
              _buildTopActionButton(
                icon: Icons.visibility,
                active: _viewersOpen,
                badgeCount: hasViewers ? game.cardViewers.length : 0,
                onTap: () {
                  setState(() {
                    _moreOpen = false;
                    _soundPanelOpen = false;
                    _viewersOpen = !_viewersOpen;
                  });
                },
              ),
            _buildTopActionButton(
              icon: game.sfxVolume <= 0.01 ? Icons.volume_off : Icons.volume_up,
              active: _soundPanelOpen,
              onTap: () {
                setState(() {
                  _soundPanelOpen = !_soundPanelOpen;
                  _moreOpen = false;
                  if (_soundPanelOpen) {
                    _viewersOpen = false;
                  }
                });
              },
            ),
            _buildTopActionButton(
              icon: Icons.exit_to_app,
              active: false,
              iconColor: const Color(0xFFE53935),
              onTap: () {
                setState(() {
                  _moreOpen = false;
                  _soundPanelOpen = false;
                });
                if (game.isSpectator) {
                  game.leaveRoom();
                } else {
                  _showExitConfirmDialog(game);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSoundPanel(GameService game) {
    final l10n = L10n.of(context);
    final title = game.isSpectator
        ? l10n.spectatorSoundEffects
        : l10n.gameSoundEffects;

    return Positioned(
      top: 122,
      right: 8,
      child: Container(
        width: 190,
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
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF5A4038),
              ),
            ),
            Slider(
              value: game.sfxVolume,
              onChanged: (value) => game.setSfxVolume(value),
              onChangeEnd: (value) => game.setSfxVolume(value, persist: true),
              min: 0,
              max: 1,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpectatorScoreboard(SKGameStateData state, GameService game) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    const playedCardWidth = 72 * 0.7;
    const seatWidth = 118.0;
    const seatHeight = 92.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final playerCount = state.players.length;
          final centerX = width / 2;
          final centerY = isLandscape ? height * 0.39 : height * 0.41;
          final maxSeatRadiusX = math.max(0.0, centerX - seatWidth / 2 - 10);
          final seatRadiusX = math.min(
            width * _seatRadiusXFactor(playerCount),
            math.min(
              _seatRadiusXCap(width, playerCount, spectator: true),
              maxSeatRadiusX,
            ),
          );
          final maxSeatRadiusY = math.max(0.0, centerY - seatHeight / 2 - 6);
          final seatRadiusY = math.min(
            height * (isLandscape ? 0.34 : 0.35),
            math.min(_seatRadiusYCap(height, spectator: true), maxSeatRadiusY),
          );

          // 3-player game spectator: drop the trick box a bit so it sits below
          // the opponents' played cards.
          final threePlayerSpectatorDrop = state.players.length == 3
              ? (isLandscape ? 18.0 : 24.0)
              : 0.0;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Align(
                  alignment: Alignment(0, isLandscape ? 0.36 : 0.46),
                  child: Transform.translate(
                    offset: Offset(
                      0,
                      (isLandscape ? -34 : -42) + threePlayerSpectatorDrop,
                    ),
                    child: IgnorePointer(child: _buildTrickArea(state)),
                  ),
                ),
              ),
              for (int i = 0; i < state.players.length; i++) ...[
                () {
                  final p = state.players[i];
                  final angle = _spectatorSeatAngleForIndex(
                    i,
                    state.players.length,
                  );
                  final seatLift = _seatVerticalLift(
                    angle,
                    isLandscape: isLandscape,
                    spectatorMode: true,
                  );
                  final seatLeft =
                      centerX + seatRadiusX * math.cos(angle) - seatWidth / 2;
                  final seatTop =
                      centerY +
                      seatRadiusY * math.sin(angle) -
                      seatHeight / 2 -
                      seatLift;

                  return Positioned(
                    left: seatLeft,
                    top: seatTop,
                    width: seatWidth,
                    height: seatHeight,
                    child: _buildSpectatorSeat(state, game, p),
                  );
                }(),
              ],
              for (int i = 0; i < state.players.length; i++) ...[
                () {
                  final p = state.players[i];
                  final angle = _spectatorSeatAngleForIndex(
                    i,
                    state.players.length,
                  );
                  final seatLift = _seatVerticalLift(
                    angle,
                    isLandscape: isLandscape,
                    spectatorMode: true,
                  );
                  final seatLeft =
                      centerX + seatRadiusX * math.cos(angle) - seatWidth / 2;
                  final seatTop =
                      centerY +
                      seatRadiusY * math.sin(angle) -
                      seatHeight / 2 -
                      seatLift;
                  final cardLeft = seatLeft + (seatWidth - playedCardWidth) / 2;
                  final cardTop = seatTop + seatHeight + 2;
                  final trickPlay = state.currentTrick
                      .cast<SKTrickPlay?>()
                      .firstWhere(
                        (play) => play?.playerId == p.id,
                        orElse: () => null,
                      );
                  final isTrickWinner =
                      state.phase == 'trick_end' &&
                      state.lastTrickWinner == p.id;

                  if (trickPlay == null) return const SizedBox.shrink();
                  return Positioned(
                    left: cardLeft,
                    top: cardTop,
                    child: _buildPlayedCardBadge(
                      trickPlay,
                      highlighted: isTrickWinner,
                    ),
                  );
                }(),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildSpectatorHandArea(SKGameStateData state, GameService game) {
    // Find the player we're currently viewing
    final viewingPlayer = _viewingPlayerId == null
        ? null
        : state.players.cast<SKPlayer?>().firstWhere(
            (p) => p?.id == _viewingPlayerId,
            orElse: () => null,
          );
    final isApproved =
        viewingPlayer != null &&
        game.approvedCardViews.contains(viewingPlayer.id) &&
        viewingPlayer.canViewCards;
    final isPending =
        viewingPlayer != null &&
        game.pendingCardViewRequests.contains(viewingPlayer.id);

    // No target selected yet
    if (viewingPlayer == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: const Border(top: BorderSide(color: Color(0xFFE0D8D4))),
        ),
        child: Text(
          L10n.of(context).skGameTapToRequestCards,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF8A7A72),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    // Pending — waiting for response
    if (isPending && !isApproved) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: const Border(top: BorderSide(color: Color(0xFFE0D8D4))),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFFFB74D),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              L10n.of(context).skGameRequestingCardView(viewingPlayer.name),
              style: const TextStyle(
                color: Color(0xFF8A7A72),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    // Approved — show hand
    if (isApproved) {
      return Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: const Border(top: BorderSide(color: Color(0xFFE0D8D4))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const SizedBox(width: 32),
                  Expanded(
                    child: Text(
                      L10n.of(context).skGamePlayerHand(viewingPlayer.name),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF5A4038),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      padding: EdgeInsets.zero,
                      splashRadius: 18,
                      icon: const Icon(
                        Icons.close,
                        size: 18,
                        color: Color(0xFF8A7A72),
                      ),
                      onPressed: () => setState(() => _viewingPlayerId = null),
                    ),
                  ),
                ],
              ),
            ),
            if (viewingPlayer.cards.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  L10n.of(context).skGameNoCards,
                  style: const TextStyle(
                    color: Color(0xFF8A7A72),
                    fontSize: 12,
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _buildHandRows(viewingPlayer.cards, interactive: false),
              ),
          ],
        ),
      );
    }

    // Not pending, not approved — rejected or timed out, show hint
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: const Border(top: BorderSide(color: Color(0xFFE0D8D4))),
      ),
      child: Text(
        L10n.of(context).skGameCardViewRejected(viewingPlayer.name),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFF8A7A72),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildCenterTimerBadge(SKGameStateData state) {
    if (_remainingSeconds <= 0 || state.players.isEmpty) {
      return const SizedBox.shrink();
    }

    final timerId = state.phase == 'bidding'
        ? state.roundStarter
        : state.currentPlayer;
    final currentPlayerName = state.players
        .firstWhere((p) => p.id == timerId, orElse: () => state.players.first)
        .name;
    final displayName = currentPlayerName.length > 8
        ? '${currentPlayerName.substring(0, 8)}…'
        : currentPlayerName;
    final urgent = _remainingSeconds <= 10;
    final primaryColor = urgent
        ? const Color(0xFFCC4444)
        : const Color(0xFF5A4038);
    final timerText = L10n.of(context).skGameSecondsShort(_remainingSeconds);

    final boxDecoration = BoxDecoration(
      color: urgent
          ? const Color(0xFFFFE4E4)
          : Colors.white.withValues(alpha: 0.82),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: urgent ? const Color(0xFFFF6B6B) : const Color(0xFFD7CEC8),
        width: urgent ? 2 : 1,
      ),
    );

    // Bidding badge lays out label / name / timer vertically so long
    // nicknames don't get truncated the way a single-row "선 플레이어: X" 40s"
    // did on narrower screens.
    if (state.phase == 'bidding') {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: boxDecoration,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                L10n.of(context).skGameLeaderLabelShort,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: urgent
                      ? const Color(0xFFCC4444)
                      : const Color(0xFF8A7A72),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                currentPlayerName,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: primaryColor,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.schedule, size: 13, color: primaryColor),
                  const SizedBox(width: 4),
                  Text(
                    timerText,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: primaryColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // Playing-phase badge stays single-row (compact "내 턴 / OOO 대기" + timer).
    final turnLabel = state.isMyTurn
        ? L10n.of(context).skGameMyTurn
        : L10n.of(context).skGameWaitingFor(displayName);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: boxDecoration,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule, size: 14, color: primaryColor),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                turnLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: primaryColor,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              timerText,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: primaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopActionButton({
    required IconData icon,
    required VoidCallback onTap,
    required bool active,
    int badgeCount = 0,
    Color? iconColor,
  }) {
    return SpectatorActionButton(
      icon: icon,
      active: active,
      onTap: onTap,
      badgeCount: badgeCount,
      iconColor: iconColor,
    );
  }

  void _showExpansionGuide(SKGameStateData state) {
    final l10n = L10n.of(context);
    final entries = <({String cardId, String name, String desc})>[
      for (final id in state.expansions)
        switch (id) {
          'kraken' => (
            cardId: 'sk_kraken',
            name: l10n.rulesSkExpKraken,
            desc: l10n.rulesSkExpKrakenDesc,
          ),
          'white_whale' => (
            cardId: 'sk_white_whale',
            name: l10n.rulesSkExpWhiteWhale,
            desc: l10n.rulesSkExpWhiteWhaleDesc,
          ),
          'loot' => (
            cardId: 'sk_loot_1',
            name: l10n.rulesSkExpLoot,
            desc: l10n.rulesSkExpLootDesc,
          ),
          _ => (cardId: '', name: id, desc: ''),
        },
    ];
    if (entries.isEmpty) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.skGameIncludedExpansions,
                style: const TextStyle(
                  color: Color(0xFF5A4038),
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 14),
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
                        color: const Color(0xFFFBF6F2),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFEDE3DD)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (e.cardId.isNotEmpty)
                            _buildCard(e.cardId, size: 86),
                          if (e.cardId.isNotEmpty) const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  e.name,
                                  style: const TextStyle(
                                    color: Color(0xFF3E312A),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (e.desc.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    e.desc,
                                    style: const TextStyle(
                                      color: Color(0xFF6A5A52),
                                      fontSize: 12,
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
    );
  }

  void _showExitConfirmDialog(GameService game) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          L10n.of(context).skGameLeaveTitle,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Color(0xFF3E312A),
          ),
        ),
        content: Text(
          L10n.of(context).skGameLeaveConfirm,
          style: const TextStyle(fontSize: 14, color: Color(0xFF6A5A52)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(L10n.of(context).commonCancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              game.leaveGame();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(L10n.of(context).skGameLeaveButton),
          ),
        ],
      ),
    );
  }

  // ── Scoreboard ──
  Widget _buildScoreboard(SKGameStateData state, GameService game) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    const playedCardWidth = 72 * 0.7;
    const seatWidth = 118.0;
    const seatHeight = 92.0;
    final opponents = state.players
        .where((p) => p.position != 'self')
        .toList(growable: false);
    final selfPlayer = state.players.cast<SKPlayer?>().firstWhere(
      (p) => p?.position == 'self',
      orElse: () => null,
    );
    final selfTrickPlay = selfPlayer == null
        ? null
        : state.currentTrick.cast<SKTrickPlay?>().firstWhere(
            (play) => play?.playerId == selfPlayer.id,
            orElse: () => null,
          );
    final isSelfTrickWinner =
        state.phase == 'trick_end' && state.lastTrickWinner == selfPlayer?.id;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final opponentCount = opponents.length;
          final centerX = width / 2;
          final centerY = isLandscape ? height * 0.39 : height * 0.41;
          final maxSeatRadiusX = math.max(0.0, centerX - seatWidth / 2 - 10);
          final seatRadiusX = math.min(
            width * _seatRadiusXFactor(opponentCount),
            math.min(
              _seatRadiusXCap(width, opponentCount, spectator: false),
              maxSeatRadiusX,
            ),
          );
          final maxSeatRadiusY = math.max(0.0, centerY - seatHeight / 2 - 6);
          final seatRadiusY = math.min(
            height * (isLandscape ? 0.35 : 0.36),
            math.min(_seatRadiusYCap(height, spectator: false), maxSeatRadiusY),
          );
          final bottomMostOpponentCardTop = opponents.isEmpty
              ? centerY
              : List.generate(
                  opponents.length,
                  (i) =>
                      centerY +
                      seatRadiusY *
                          math.sin(_topSeatAngleForIndex(i, opponents.length)) +
                      seatHeight / 2 +
                      2,
                ).reduce(math.max);
          final trickBoxLowerBound = height * (isLandscape ? 0.60 : 0.64);
          final selfCardTop = math.min(
            height - 60,
            math.max(bottomMostOpponentCardTop + 40, trickBoxLowerBound),
          );

          // 3-player game (2 opponents): drop the trick box below the
          // opponents' played cards so it doesn't crowd the seat row.
          final twoOpponentTrickDrop = opponents.length == 2
              ? (isLandscape ? 18.0 : 24.0)
              : 0.0;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Align(
                  alignment: Alignment(0, isLandscape ? 0.36 : 0.46),
                  child: Transform.translate(
                    offset: Offset(
                      0,
                      (isLandscape ? -34 : -42) + twoOpponentTrickDrop,
                    ),
                    child: IgnorePointer(child: _buildTrickArea(state)),
                  ),
                ),
              ),
              for (int i = 0; i < opponents.length; i++) ...[
                () {
                  final p = opponents[i];
                  final angle = _topSeatAngleForIndex(i, opponents.length);
                  final seatLift = _seatVerticalLift(
                    angle,
                    isLandscape: isLandscape,
                  );
                  final seatLeft =
                      centerX + seatRadiusX * math.cos(angle) - seatWidth / 2;
                  final seatTop =
                      centerY +
                      seatRadiusY * math.sin(angle) -
                      seatHeight / 2 -
                      seatLift;

                  return Positioned(
                    left: seatLeft,
                    top: seatTop,
                    width: seatWidth,
                    height: seatHeight,
                    child: _buildPlayerSeat(state, game, p, isSelf: false),
                  );
                }(),
              ],
              for (int i = 0; i < opponents.length; i++) ...[
                () {
                  final p = opponents[i];
                  final angle = _topSeatAngleForIndex(i, opponents.length);
                  final seatLift = _seatVerticalLift(
                    angle,
                    isLandscape: isLandscape,
                  );
                  final seatLeft =
                      centerX + seatRadiusX * math.cos(angle) - seatWidth / 2;
                  final seatTop =
                      centerY +
                      seatRadiusY * math.sin(angle) -
                      seatHeight / 2 -
                      seatLift;
                  final cardLeft = seatLeft + (seatWidth - playedCardWidth) / 2;
                  final cardTop = seatTop + seatHeight + 2;
                  final trickPlay = state.currentTrick
                      .cast<SKTrickPlay?>()
                      .firstWhere(
                        (play) => play?.playerId == p.id,
                        orElse: () => null,
                      );
                  final isTrickWinner =
                      state.phase == 'trick_end' &&
                      state.lastTrickWinner == p.id;

                  if (trickPlay == null) return const SizedBox.shrink();
                  return Positioned(
                    left: cardLeft,
                    top: cardTop,
                    child: _buildPlayedCardBadge(
                      trickPlay,
                      highlighted: isTrickWinner,
                    ),
                  );
                }(),
              ],
              if (selfTrickPlay != null)
                Positioned(
                  left: centerX - playedCardWidth / 2,
                  top: selfCardTop,
                  child: _buildPlayedCardBadge(
                    selfTrickPlay,
                    highlighted: isSelfTrickWinner,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  double _seatAngleForIndex(
    int index,
    int playerCount, {
    bool includeBottomSeat = true,
  }) {
    if (includeBottomSeat) {
      if (index == 0) return math.pi / 2;
      final opponents = playerCount - 1;
      if (opponents <= 1) return math.pi * 1.5;
      final customOpponentAngles = _customSeatAnglesDeg(opponents);
      if (customOpponentAngles != null) {
        return customOpponentAngles[index - 1] * math.pi / 180;
      }
      final startDeg = _seatArcStartDeg(opponents);
      final endDeg = _seatArcEndDeg(opponents);
      final progress = (index - 1) / (opponents - 1);
      final angleDeg = startDeg + (endDeg - startDeg) * progress;
      return angleDeg * math.pi / 180;
    }

    if (playerCount <= 1) return math.pi * 1.5;
    final customAngles = _customSeatAnglesDeg(playerCount);
    if (customAngles != null) {
      return customAngles[index] * math.pi / 180;
    }
    final startDeg = _seatArcStartDeg(playerCount);
    final endDeg = _seatArcEndDeg(playerCount);
    final progress = index / (playerCount - 1);
    final angleDeg = startDeg + (endDeg - startDeg) * progress;
    return angleDeg * math.pi / 180;
  }

  double _topSeatAngleForIndex(int index, int playerCount) {
    if (playerCount <= 1) return math.pi * 1.5;
    final customAngles = _customSeatAnglesDeg(playerCount);
    if (customAngles != null) {
      return customAngles[index] * math.pi / 180;
    }
    final startDeg = _seatArcStartDeg(playerCount);
    final endDeg = _seatArcEndDeg(playerCount);
    final progress = index / (playerCount - 1);
    final angleDeg = startDeg + (endDeg - startDeg) * progress;
    return angleDeg * math.pi / 180;
  }

  double _spectatorSeatAngleForIndex(int index, int playerCount) {
    if (playerCount <= 1) return math.pi * 1.5;
    final customAngles = _customSpectatorSeatAnglesDeg(playerCount);
    if (customAngles != null) {
      return customAngles[index] * math.pi / 180;
    }
    return _seatAngleForIndex(index, playerCount, includeBottomSeat: false);
  }

  List<double>? _customSeatAnglesDeg(int count) {
    switch (count) {
      case 4:
        return const [172, 238, 302, 368];
      case 5:
        // top(270) + two vertical columns. Lower seats mirror the upper ones
        // across the horizontal axis so each side shares the same X: left
        // column at 207.5/152.5 (cos ≈ -0.887), right at 332.5/387.5
        // (cos ≈ +0.887). Order: lower-left, upper-left, top, upper-right,
        // lower-right.
        return const [152.5, 207.5, 270.0, 332.5, 387.5];
      default:
        return null;
    }
  }

  List<double>? _customSpectatorSeatAnglesDeg(int count) {
    switch (count) {
      case 6:
        return const [132, 180, 236, 304, 360, 408];
      default:
        return null;
    }
  }

  double _seatRadiusXFactor(int count) {
    if (count >= 5) return 0.44;
    if (count == 4) return 0.43;
    if (count == 3) return 0.40;
    return 0.38;
  }

  double _seatRadiusXCap(double width, int count, {required bool spectator}) {
    final base = spectator
        ? (count >= 5 ? 228.0 : 182.0)
        : (count >= 5 ? 236.0 : 188.0);
    if (width >= 1200) return base + 130;
    if (width >= 900) return base + 90;
    if (width >= 700) return base + 45;
    return base;
  }

  double _seatRadiusYCap(double height, {required bool spectator}) {
    final base = spectator ? 196.0 : 202.0;
    if (height >= 1100) return base + 90;
    if (height >= 850) return base + 50;
    if (height >= 700) return base + 24;
    return base;
  }

  double _seatVerticalLift(
    double angle, {
    required bool isLandscape,
    bool spectatorMode = false,
  }) {
    final cornerWeight = math.pow(math.cos(angle).abs(), 1.15).toDouble();
    final lowerCornerWeight = math.max(0.0, math.sin(angle));
    final baseLift =
        cornerWeight * (isLandscape ? 24.0 : 30.0) +
        lowerCornerWeight * (isLandscape ? 10.0 : 14.0);
    if (!spectatorMode) return baseLift;
    final upperWeight = math.max(0.0, -math.sin(angle));
    final reduction = (1 - upperWeight) * (isLandscape ? 12.0 : 18.0);
    return math.max(0.0, baseLift - reduction);
  }

  double _seatArcStartDeg(int count) {
    if (count >= 5) return 145.0;
    if (count == 4) return 198.0;
    if (count == 3) return 210.0;
    return 225.0;
  }

  double _seatArcEndDeg(int count) {
    if (count >= 5) return 395.0;
    if (count == 4) return 342.0;
    if (count == 3) return 330.0;
    return 315.0;
  }

  Widget _buildSpectatorSeat(
    SKGameStateData state,
    GameService game,
    SKPlayer p,
  ) {
    final isCurrentTurn = state.phase == 'bidding'
        ? p.id == state.roundStarter
        : p.id == state.currentPlayer;
    final isPending = game.pendingCardViewRequests.contains(p.id);
    final isApproved = game.approvedCardViews.contains(p.id) && p.canViewCards;
    final isViewing = _viewingPlayerId == p.id && isApproved;

    return GestureDetector(
      onTap: () {
        if (isApproved) {
          setState(() {
            _viewingPlayerId = _viewingPlayerId == p.id ? null : p.id;
          });
        } else if (isPending) {
          return;
        } else {
          _cardViewRequestTimer?.cancel();
          game.requestCardView(p.id);
          setState(() => _viewingPlayerId = p.id);
          _cardViewRequestTimer = Timer(const Duration(seconds: 5), () {
            if (!mounted) return;
            game.expireCardViewRequest(p.id);
          });
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxHeight <= 72 || constraints.maxWidth <= 98;
          final horizontalPadding = compact ? 5.0 : 6.0;
          final verticalPadding = compact ? 4.0 : 6.0;
          final timeoutHeight = compact ? 12.0 : 16.0;
          final dotSize = compact ? 5.0 : 6.0;
          final offlineIconSize = compact ? 10.0 : 12.0;
          final nameFontSize = compact ? 10.0 : 11.0;
          final scoreFontSize = compact ? 13.0 : 15.0;
          final bidHeight = compact ? 14.0 : 18.0;
          final bidFontSize = compact ? 10.0 : 11.0;
          final bidHorizontalPadding = compact ? 4.0 : 6.0;
          final bidTopMargin = compact ? 1.0 : 2.0;
          final spacing = compact ? 1.0 : 2.0;
          final contentWidth = math.max(
            24.0,
            (constraints.maxWidth - horizontalPadding * 2) * 0.7,
          );

          final labelTint = isViewing
              ? const Color(0xFFE3EFFF).withValues(alpha: 0.88)
              : isCurrentTurn
              ? const Color(0xFFFFF0C9).withValues(alpha: 0.88)
              : const Color(0xFFFFFCFA).withValues(alpha: 0.62);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalPadding,
            ),
            decoration: const BoxDecoration(),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topCenter,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 6 : 8,
                        vertical: compact ? 4 : 5,
                      ),
                      decoration: BoxDecoration(
                        color: labelTint,
                        borderRadius: BorderRadius.circular(14),
                        border: isViewing
                            ? Border.all(
                                color: const Color(0xFF64B5F6),
                                width: 1.5,
                              )
                            : isCurrentTurn
                            ? Border.all(
                                color: const Color(0xFFE6C86A),
                                width: 1.5,
                              )
                            : null,
                      ),
                      child: SizedBox(
                        width: contentWidth,
                        child: Opacity(
                          opacity: p.connected ? 1.0 : 0.45,
                          child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SizedBox(
                              height: timeoutHeight,
                              child: p.timeoutCount > 0
                                  ? Text(
                                      '⏱ ${p.timeoutCount}/3',
                                      style: TextStyle(
                                        color: const Color(0xFFE65100),
                                        fontSize: compact ? 8.5 : 10,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    )
                                  : null,
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isCurrentTurn)
                                  Container(
                                    width: dotSize,
                                    height: dotSize,
                                    margin: EdgeInsets.only(
                                      right: compact ? 3 : 4,
                                    ),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFE6A800),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                if (!p.connected)
                                  Padding(
                                    padding: EdgeInsets.only(
                                      right: compact ? 2 : 3,
                                    ),
                                    child: Icon(
                                      Icons.wifi_off,
                                      size: offlineIconSize,
                                      color: const Color(0xFFE53935),
                                    ),
                                  ),
                                Flexible(
                                  child: Text(
                                    p.name,
                                    style: TextStyle(
                                      color: p.connected
                                          ? const Color(0xFF5A4038)
                                          : const Color(0xFFE53935),
                                      fontSize: nameFontSize,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: spacing),
                            Text(
                              '${p.totalScore}',
                              style: TextStyle(
                                color: const Color(0xFF5A4038),
                                fontSize: scoreFontSize,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(
                              height: bidHeight,
                              child: p.hasBid && p.bid != null
                                  ? Container(
                                      margin: EdgeInsets.only(
                                        top: bidTopMargin,
                                      ),
                                      padding: EdgeInsets.symmetric(
                                        horizontal: bidHorizontalPadding,
                                        vertical: compact ? 0 : 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: p.tricks == p.bid
                                            ? const Color(0xFFE8F5E9)
                                            : p.tricks > p.bid!
                                            ? const Color(0xFFFFF3E0)
                                            : const Color(0xFFF5F5F5),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${p.tricks}/${p.bid}',
                                        style: TextStyle(
                                          color: p.tricks == p.bid
                                              ? const Color(0xFF4CAF50)
                                              : p.tricks > p.bid!
                                              ? const Color(0xFFE65100)
                                              : const Color(0xFF8A7A72),
                                          fontSize: bidFontSize,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    )
                                  : p.hasBid && p.bid == null
                                  ? Container(
                                      margin: EdgeInsets.only(
                                        top: bidTopMargin,
                                      ),
                                      padding: EdgeInsets.symmetric(
                                        horizontal: bidHorizontalPadding,
                                        vertical: compact ? 0 : 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF0EBF8),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        Icons.check,
                                        size: compact ? 10 : 12,
                                        color: const Color(0xFF7A6A95),
                                      ),
                                    )
                                  : null,
                            ),
                          ],
                        ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isApproved
                                ? const Color(0xFF64B5F6)
                                : const Color(0xFFE0D8D4),
                          ),
                        ),
                        child: Icon(
                          isPending
                              ? Icons.schedule
                              : isApproved
                              ? Icons.visibility
                              : Icons.visibility_outlined,
                          size: 12,
                          color: isPending
                              ? const Color(0xFFFFB74D)
                              : isApproved
                              ? const Color(0xFF64B5F6)
                              : const Color(0xFF8A7A72).withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlayerSeat(
    SKGameStateData state,
    GameService game,
    SKPlayer p, {
    required bool isSelf,
  }) {
    final isCurrentTurn = state.phase == 'bidding'
        ? p.id == state.roundStarter
        : p.id == state.currentPlayer;

    return GestureDetector(
      onTap: isSelf
          ? null
          : () => _showPlayerProfileDialog(
              p.name,
              game,
              isBot: p.id.startsWith('bot_'),
            ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              !isSelf &&
              (constraints.maxHeight <= 70 || constraints.maxWidth <= 96);
          final horizontalPadding = compact ? 5.0 : 8.0;
          final verticalPadding = compact ? 4.0 : 8.0;
          final timeoutHeight = compact ? 12.0 : 16.0;
          final dotSize = compact ? 5.0 : 6.0;
          final offlineIconSize = compact ? 10.0 : 12.0;
          final nameFontSize = isSelf ? 12.0 : (compact ? 10.0 : 11.0);
          final scoreFontSize = isSelf ? 16.0 : (compact ? 13.0 : 15.0);
          final bidHeight = compact ? 14.0 : 18.0;
          final bidFontSize = compact ? 10.0 : 11.0;
          final bidHorizontalPadding = compact ? 4.0 : 6.0;
          final bidTopMargin = compact ? 1.0 : 2.0;
          final spacing = compact ? 1.0 : 2.0;
          final contentWidth = math.max(
            24.0,
            (constraints.maxWidth - horizontalPadding * 2) * 0.7,
          );

          final labelTint = isSelf
              ? Colors.white.withValues(alpha: 0.96)
              : isCurrentTurn
              ? const Color(0xFFFFF0C9).withValues(alpha: 0.88)
              : const Color(0xFFFFFCFA).withValues(alpha: 0.62);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalPadding,
            ),
            decoration: const BoxDecoration(),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topCenter,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 6 : 8,
                    vertical: compact ? 4 : 5,
                  ),
                  decoration: BoxDecoration(
                    color: labelTint,
                    borderRadius: BorderRadius.circular(isSelf ? 16 : 14),
                    border: isCurrentTurn
                        ? Border.all(
                            color: const Color(0xFFE6C86A),
                            width: 1.5,
                          )
                        : null,
                  ),
                  child: SizedBox(
                    width: contentWidth,
                    child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        height: timeoutHeight,
                        child: p.timeoutCount > 0
                            ? Text(
                                '⏱ ${p.timeoutCount}/3',
                                style: TextStyle(
                                  color: const Color(0xFFE65100),
                                  fontSize: compact ? 8.5 : 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              )
                            : null,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isCurrentTurn)
                            Container(
                              width: dotSize,
                              height: dotSize,
                              margin: EdgeInsets.only(right: compact ? 3 : 4),
                              decoration: const BoxDecoration(
                                color: Color(0xFFE6A800),
                                shape: BoxShape.circle,
                              ),
                            ),
                          if (!p.connected)
                            Padding(
                              padding: EdgeInsets.only(right: compact ? 2 : 3),
                              child: Icon(
                                Icons.wifi_off,
                                size: offlineIconSize,
                                color: const Color(0xFFE53935),
                              ),
                            ),
                          if (p.photoUrl != null)
                            Padding(
                              padding:
                                  EdgeInsets.only(right: compact ? 2 : 3),
                              child: ProfileAvatar(
                                photoUrl: game.resolvePhotoUrl(p.photoUrl),
                                size: compact ? 14 : 16,
                                blocked: game.blockedUsers.contains(p.name),
                                fallback: SizedBox(
                                  width: compact ? 14 : 16,
                                  height: compact ? 14 : 16,
                                ),
                              ),
                            ),
                          Flexible(
                            child: Text(
                              p.name,
                              style: TextStyle(
                                color: p.connected
                                    ? const Color(0xFF5A4038)
                                    : const Color(0xFFE53935),
                                fontSize: nameFontSize,
                                fontWeight: isSelf
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: spacing),
                      Text(
                        '${p.totalScore}',
                        style: TextStyle(
                          color: const Color(0xFF5A4038),
                          fontSize: scoreFontSize,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(
                        height: bidHeight,
                        child: p.hasBid && p.bid != null
                            ? Container(
                                margin: EdgeInsets.only(top: bidTopMargin),
                                padding: EdgeInsets.symmetric(
                                  horizontal: bidHorizontalPadding,
                                  vertical: compact ? 0 : 1,
                                ),
                                decoration: BoxDecoration(
                                  color: p.tricks == p.bid
                                      ? const Color(0xFFE8F5E9)
                                      : p.tricks > p.bid!
                                      ? const Color(0xFFFFF3E0)
                                      : const Color(0xFFF5F5F5),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${p.tricks}/${p.bid}',
                                  style: TextStyle(
                                    color: p.tricks == p.bid
                                        ? const Color(0xFF4CAF50)
                                        : p.tricks > p.bid!
                                        ? const Color(0xFFE65100)
                                        : const Color(0xFF8A7A72),
                                    fontSize: bidFontSize,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            : p.hasBid && p.bid == null
                            ? Container(
                                margin: EdgeInsets.only(top: bidTopMargin),
                                padding: EdgeInsets.symmetric(
                                  horizontal: bidHorizontalPadding,
                                  vertical: compact ? 0 : 1,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0EBF8),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.check,
                                  size: compact ? 10 : 12,
                                  color: const Color(0xFF7A6A95),
                                ),
                              )
                            : null,
                      ),
                    ],
                  ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlayedCardBadge(SKTrickPlay play, {required bool highlighted}) {
    final isTigressChoice =
        play.tigressChoice == 'pirate' || play.tigressChoice == 'escape';
    final displayCardId = play.tigressChoice == 'pirate'
        ? 'sk_pirate'
        : play.tigressChoice == 'escape'
        ? 'sk_escape'
        : play.cardId;
    final card = _buildCard(displayCardId, size: 72, highlighted: highlighted);
    if (!isTigressChoice) return card;
    // Overlay a small check-mark badge in the top-left corner so players can
    // tell that this pirate/escape is actually a Tigress that was played as
    // the chosen form.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        card,
        Positioned(
          left: -4,
          top: -4,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: const Color(0xFF5E35B1),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: const Icon(Icons.check, size: 13, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _buildSKErrorBanner(String message) {
    return Positioned(
      bottom: 200,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFE4E4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFF6B6B)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFCC4444)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                localizeServiceMessage(message, L10n.of(context)),
                style: const TextStyle(
                  color: Color(0xFFCC4444),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSKTimeoutBanner(String playerName) {
    return Positioned(
      bottom: 240,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E0),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFFB74D)),
        ),
        child: Row(
          children: [
            const Icon(Icons.timer_off, color: Color(0xFFE65100)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                L10n.of(context).skGameTimeout(playerName),
                style: const TextStyle(
                  color: Color(0xFFE65100),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSKDesertionBanner(String playerName, String reason) {
    return Positioned(
      bottom: 240,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFE4E4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFF6B6B)),
        ),
        child: Row(
          children: [
            const Icon(Icons.person_off, color: Color(0xFFCC4444)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                reason == 'timeout'
                    ? L10n.of(context).skGameDesertionTimeout(playerName)
                    : L10n.of(context).skGameDesertionLeave(playerName),
                style: const TextStyle(
                  color: Color(0xFFCC4444),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardViewRequestPopup(GameService game) {
    final request = game.firstIncomingCardViewRequest;
    if (request == null) return const SizedBox.shrink();

    final spectatorId = request['spectatorId'] ?? '';
    final spectatorNickname = request['spectatorNickname'] ?? '';

    return Positioned(
      top: 72,
      left: 16,
      right: 16,
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.visibility, color: Color(0xFF6A6090)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      L10n.of(context).skGameCardViewRequest(spectatorNickname),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF4A4080),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          game.respondCardViewRequest(spectatorId, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFCC6666),
                        side: const BorderSide(color: Color(0xFFCC6666)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      child: Text(L10n.of(context).skGameReject),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () =>
                          game.respondCardViewRequest(spectatorId, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6A9BD1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      child: Text(L10n.of(context).skGameAllow),
                    ),
                  ),
                ],
              ),
              // Always-allow / always-deny moved to app settings + the
              // eye-icon viewers panel since it's a per-account policy
              // about "my cards", not a per-request choice.
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatPanel(GameService game) {
    if (game.chatMessages.length != _lastChatMessageCount) {
      _lastChatMessageCount = game.chatMessages.length;
      _readChatCount = game.chatMessages.length;
      _scrollChatToBottom();
    }

    return DraggableChatPanel(
      accentColor: const Color(0xFF21455F),
      sendIconColor: const Color(0xFF64B5F6),
      title: L10n.of(context).skGameChat,
      hintText: L10n.of(context).skGameMessageHint,
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
        final isBlocked = sender.isNotEmpty && game.isBlocked(sender);
        if (isBlocked) return const SizedBox.shrink();
        return _buildChatBubble(sender, message, isMe, game);
      },
    );
  }

  Widget _buildViewersPanel(GameService game) {
    return Positioned(
      top: 58,
      right: 8,
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.visibility,
                  size: 16,
                  color: Color(0xFF5A4038),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    L10n.of(context).skGameViewingMyHand,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF5A4038),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _viewersOpen = false),
                  child: const Icon(
                    Icons.close,
                    size: 18,
                    color: Color(0xFF999999),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (game.cardViewers.isEmpty)
              Text(
                L10n.of(context).skGameNoViewers,
                style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
              )
            else
              ...game.cardViewers.map((viewer) {
                final nickname = viewer['nickname'] ?? '';
                final spectatorId = viewer['id'] ?? '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.person,
                        size: 16,
                        color: Color(0xFF888888),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          nickname,
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => game.revokeCardView(spectatorId),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFEBEE),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 14,
                            color: Color(0xFFE53935),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            const Divider(height: 16, color: Color(0xFFEDE5E0)),
            _buildCardViewPrefSection(game),
          ],
        ),
      ),
    );
  }

  /// 3-option (ask / always_allow / always_deny) toggle pinned to the
  /// bottom of the viewers panel so users can change their card-view
  /// policy without leaving the game.
  Widget _buildCardViewPrefSection(GameService game) {
    final l10n = L10n.of(context);
    Widget radio({
      required String value,
      required String label,
      required IconData icon,
      required Color color,
    }) {
      final selected = game.cardViewPref == value;
      return GestureDetector(
        onTap: () => game.setCardViewPref(value),
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? color : const Color(0xFFE6DCE8),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 14,
                color: selected ? color : const Color(0xFF999999),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    color: selected ? color : const Color(0xFF5A4038),
                  ),
                ),
              ),
              if (selected) Icon(Icons.check, size: 14, color: color),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.gameCardViewPolicyTitle,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFF5A4038),
          ),
        ),
        const SizedBox(height: 6),
        radio(
          value: 'ask',
          label: l10n.gameCardViewPolicyAsk,
          icon: Icons.help_outline,
          color: const Color(0xFF6A6090),
        ),
        radio(
          value: 'always_allow',
          label: l10n.gameCardViewPolicyAllow,
          icon: Icons.check_circle,
          color: const Color(0xFF4CAF50),
        ),
        radio(
          value: 'always_deny',
          label: l10n.gameCardViewPolicyDeny,
          icon: Icons.block,
          color: const Color(0xFFE53935),
        ),
      ],
    );
  }

  Widget _buildChatBubble(
    String sender,
    String message,
    bool isMe,
    GameService game,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: isMe || sender.isEmpty
            ? null
            : () => _showUserActionDialog(sender, game),
        child: Row(
          mainAxisAlignment: isMe
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe && sender.isNotEmpty) ...[
              CircleAvatar(
                radius: 14,
                backgroundColor: const Color(0xFFE0E0E0),
                child: Text(
                  sender[0],
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF5A4038),
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment: isMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (!isMe && sender.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        sender,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF8A8A8A),
                        ),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isMe
                          ? const Color(0xFF21455F)
                          : const Color(0xFFF0F0F0),
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
      ),
    );
  }

  void _showUserActionDialog(String nickname, GameService game) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isBlocked = game.isBlocked(nickname);
        return Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                nickname,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF3E312A),
                ),
              ),
              const SizedBox(height: 14),
              ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: Text(L10n.of(context).skGameViewProfile),
                onTap: () {
                  Navigator.pop(ctx);
                  _showPlayerProfileDialog(nickname, game);
                },
              ),
              ListTile(
                leading: Icon(
                  isBlocked ? Icons.lock_open_rounded : Icons.block_outlined,
                  color: isBlocked
                      ? const Color(0xFF4CAF50)
                      : const Color(0xFFE53935),
                ),
                title: Text(
                  isBlocked
                      ? L10n.of(context).skGameUnblock
                      : L10n.of(context).skGameBlock,
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  if (isBlocked) {
                    game.unblockUserAction(nickname);
                  } else {
                    game.blockUserAction(nickname);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showScoreHistoryDialog(SKGameStateData state) {
    final cumulativeScores = <String, int>{
      for (final p in state.players) p.id: 0,
    };

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: const Color(0xFFFCFAF8),
        titlePadding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
        contentPadding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        title: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1EA),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.table_chart_rounded,
                      size: 16,
                      color: Color(0xFFC96E34),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    L10n.of(context).skGameScoreHistory,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF3E312A),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${state.scoreHistory.length}R',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF8A7A72),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: LayoutBuilder(
              builder: (context, constraints) {
                Widget cell(
                  String text, {
                  TextAlign align = TextAlign.center,
                  FontWeight fontWeight = FontWeight.w600,
                  Color color = const Color(0xFF5A4038),
                  double fontSize = 12,
                  EdgeInsets padding = const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 9,
                  ),
                }) {
                  return Padding(
                    padding: padding,
                    child: Text(
                      text,
                      textAlign: align,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: fontWeight,
                        color: color,
                        height: 1.2,
                      ),
                    ),
                  );
                }

                return Table(
                  columnWidths: {
                    0: const FlexColumnWidth(0.6),
                    for (int i = 0; i < state.players.length; i++)
                      i + 1: const FlexColumnWidth(1),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFF1EA),
                        border: Border(
                          bottom: BorderSide(color: Color(0xFFF0D9CB), width: 1),
                        ),
                      ),
                      children: [
                        cell(
                          'R',
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: const Color(0xFFC96E34),
                        ),
                        ...state.players.map(
                          (p) => cell(
                            p.name.length > 4 ? p.name.substring(0, 4) : p.name,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            color: p.position == 'self'
                                ? const Color(0xFF355D89)
                                : const Color(0xFFC96E34),
                          ),
                        ),
                      ],
                    ),
                    ...state.scoreHistory.asMap().entries.map((mapEntry) {
                      final rowIndex = mapEntry.key;
                      final entry = mapEntry.value;
                      final scores =
                          entry['scores'] as Map<String, dynamic>? ?? {};

                      for (final p in state.players) {
                        final pScore = scores[p.id] as Map<String, dynamic>?;
                        cumulativeScores[p.id] =
                            (cumulativeScores[p.id] ?? 0) +
                            ((pScore?['roundScore'] as num?)?.toInt() ?? 0);
                      }

                      return TableRow(
                        decoration: BoxDecoration(
                          color: rowIndex.isOdd
                              ? const Color(0xFFFAF4F0)
                              : null,
                        ),
                        children: [
                          cell(
                            '${entry['round']}',
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: const Color(0xFF8A7A72),
                          ),
                          ...state.players.map((p) {
                            final pScore =
                                scores[p.id] as Map<String, dynamic>?;
                            if (pScore == null) {
                              return cell('-', color: const Color(0xFFC9BCB5));
                            }
                            final roundScore =
                                (pScore['roundScore'] as num?)?.toInt() ?? 0;
                            final scoreColor = roundScore < 0
                                ? const Color(0xFFC94256)
                                : const Color(0xFF3E312A);

                            return cell(
                              '$roundScore',
                              fontSize: 14,
                              fontWeight: p.position == 'self'
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: scoreColor,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 7,
                              ),
                            );
                          }),
                        ],
                      );
                    }),
                    TableRow(
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFF1EA),
                        border: Border(
                          top: BorderSide(color: Color(0xFFF0D9CB), width: 1.5),
                        ),
                      ),
                      children: [
                        cell(
                          L10n.of(context).commonTotal,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: const Color(0xFF3E312A),
                        ),
                        ...state.players.map((p) {
                          final total = cumulativeScores[p.id] ?? 0;
                          return cell(
                            '$total',
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            color: total < 0
                                ? const Color(0xFFC94256)
                                : const Color(0xFF3E312A),
                          );
                        }),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(L10n.of(context).commonClose),
          ),
        ],
      ),
    );
  }

  // ── Trick Area ──
  Widget _buildTrickArea(SKGameStateData state) {
    if (state.currentTrick.isEmpty) {
      return Center(
        child: Container(
          width: 180,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.anchor, size: 20, color: Color(0xFF8A7A72)),
              const SizedBox(height: 4),
              Text(
                state.phase == 'bidding'
                    ? L10n.of(context).skGameBiddingPhase
                    : L10n.of(context).skGamePlayCard,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF5A4038),
                ),
              ),
              _buildCenterTimerBadge(state),
            ],
          ),
        ),
      );
    }

    if (state.players.isEmpty) return const SizedBox.shrink();
    final winnerName = state.players
        .firstWhere(
          (p) => p.id == state.lastTrickWinner,
          orElse: () => state.players.first,
        )
        .name;
    final bonus = state.lastTrickBonus;

    // Parse bonusDetail to detect expansion effects
    final detail = state.lastTrickBonusDetail;
    String? voidReason;
    String? whaleNullifyLabel;
    int lootBonusPoints = 0;
    bool isKraken = false;
    bool hasWhiteWhaleEffect = false;
    for (final entry in detail) {
      final type = entry['type'];
      if (type == 'kraken_void') {
        voidReason = L10n.of(context).skGameKrakenActivated;
        isKraken = true;
      } else if (type == 'white_whale_void') {
        voidReason = L10n.of(context).skGameWhiteWhaleActivated;
        hasWhiteWhaleEffect = true;
      } else if (type == 'white_whale_nullify') {
        whaleNullifyLabel = L10n.of(context).skGameWhiteWhaleNullify;
        hasWhiteWhaleEffect = true;
      } else if (type == 'loot_bonus') {
        lootBonusPoints = (entry['winnerPoints'] as num?)?.toInt() ?? 0;
      }
    }
    if (isKraken) {
      voidReason = L10n.of(context).skGameKrakenActivated;
      hasWhiteWhaleEffect = false;
    }
    final isVoided = state.lastTrickVoided;

    // Voided trick → distinct banner
    if (isVoided && state.phase == 'trick_end') {
      final Color accentColor = isKraken
          ? const Color(0xFFFFD54F)
          : const Color(0xFFDBF3FF);
      final List<Color> gradientColors = isKraken
          ? [
              const Color(0xFF1A102A).withValues(alpha: 0.97),
              const Color(0xFF2B1E3F).withValues(alpha: 0.93),
              const Color(0xFF4A2F63).withValues(alpha: 0.90),
            ]
          : [
              const Color(0xFF163C54).withValues(alpha: 0.97),
              const Color(0xFF2F6687).withValues(alpha: 0.93),
              const Color(0xFF6CA6C4).withValues(alpha: 0.90),
            ];
      return Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 260),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.70),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildCard(
                    isKraken ? 'sk_kraken' : 'sk_white_whale',
                    size: 50,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          L10n.of(context).skGameTrickVoided,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: accentColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          voidReason ?? '',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                L10n.of(context).skGameLeadPlayer(winnerName),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white.withValues(alpha: 0.82),
                ),
              ),
              _buildCenterTimerBadge(state),
            ],
          ),
        ),
      );
    }

    if (!isKraken && hasWhiteWhaleEffect && state.phase == 'trick_end') {
      return Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 270),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFFE6F6FF).withValues(alpha: 0.98),
                const Color(0xFFD2ECFA).withValues(alpha: 0.96),
                const Color(0xFFB7DBEE).withValues(alpha: 0.94),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF4F88A8).withValues(alpha: 0.55),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2B5C78).withValues(alpha: 0.16),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildCard('sk_white_whale', size: 52),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          L10n.of(context).skGameTrickWinner(winnerName),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF214A62),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          whaleNullifyLabel ??
                              L10n.of(context).skGameWhiteWhaleActivated,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF356B89),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (bonus > 0) ...[
                const SizedBox(height: 8),
                Text(
                  lootBonusPoints > 0
                      ? L10n.of(
                          context,
                        ).skGameBonusWithLoot(bonus, lootBonusPoints)
                      : L10n.of(context).skGameBonus(bonus),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2E8B57),
                  ),
                ),
              ],
              _buildCenterTimerBadge(state),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              state.phase == 'trick_end'
                  ? L10n.of(context).skGameTrickWinner(winnerName)
                  : L10n.of(context).skGameCheckingCards,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Color(0xFF5A4038),
              ),
            ),
            if (whaleNullifyLabel != null && state.phase == 'trick_end') ...[
              const SizedBox(height: 4),
              Text(
                whaleNullifyLabel,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF3A6B8F),
                ),
              ),
            ],
            if (state.phase == 'trick_end' && bonus > 0) ...[
              const SizedBox(height: 4),
              Text(
                lootBonusPoints > 0
                    ? L10n.of(
                        context,
                      ).skGameBonusWithLoot(bonus, lootBonusPoints)
                    : L10n.of(context).skGameBonus(bonus),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF43A047),
                ),
              ),
            ],
            _buildCenterTimerBadge(state),
          ],
        ),
      ),
    );
  }

  // ── Bidding UI ──
  Widget _buildBiddingUI(SKGameStateData state, GameService game) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final selfPlayer = state.players.firstWhere(
      (p) => p.position == 'self',
      orElse: () => state.players.first,
    );
    final isMyBidTurn = !selfPlayer.hasBid;

    if (selfPlayer.hasBid) {
      return Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildSelfStatusRow(
                selfPlayer,
                game,
                compact: isLandscape,
              ),
            ),
            Text(
              L10n.of(context).skGameBidDone(selfPlayer.bid ?? 0),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF5A4038),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              L10n.of(context).skGameWaitingOthers,
              style: const TextStyle(fontSize: 12, color: Color(0xFF8A7A72)),
            ),
            SizedBox(height: isLandscape ? 8 : 12),
            // Keep the hand visible while waiting for other bids — the
            // player has already locked in their bid, no reason to hide
            // their own cards from themselves.
            _buildHandRows(
              state.myCards,
              interactive: false,
              compact: isLandscape,
            ),
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, isLandscape ? 12 : 16),
      decoration: BoxDecoration(
        color: isMyBidTurn
            ? const Color(0xFFFFF6D8).withValues(alpha: 0.96)
            : Colors.white.withValues(alpha: 0.92),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(
            color: isMyBidTurn
                ? const Color(0xFFE6C86A)
                : const Color(0xFFE0D8D4),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildSelfStatusRow(
              selfPlayer,
              game,
              compact: isLandscape,
            ),
          ),
          Text(
            L10n.of(context).skGameBidPrompt,
            style: TextStyle(
              color: const Color(0xFF5A4038),
              fontSize: isLandscape ? 13 : 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: isLandscape ? 6 : 8),
          // Card preview (overlapping like Tichu)
          _buildHandRows(
            state.myCards,
            interactive: false,
            compact: isLandscape,
          ),
          SizedBox(height: isLandscape ? 8 : 12),
          Wrap(
            spacing: 8,
            runSpacing: isLandscape ? 6 : 8,
            children: List.generate(state.round + 1, (i) {
              final selected = _selectedBid == i;
              return ChoiceChip(
                label: Text('$i'),
                selected: selected,
                onSelected: (_) => setState(() => _selectedBid = i),
                selectedColor: const Color(0xFFE6F1FF),
                labelStyle: TextStyle(
                  color: selected
                      ? const Color(0xFF355D89)
                      : const Color(0xFF5A4038),
                  fontWeight: FontWeight.bold,
                  fontSize: isLandscape ? 14 : 16,
                ),
                visualDensity: isLandscape
                    ? VisualDensity.compact
                    : VisualDensity.standard,
              );
            }),
          ),
          SizedBox(height: isLandscape ? 6 : 8),
          SizedBox(
            width: double.infinity,
            height: isLandscape ? 40 : 44,
            child: FilledButton(
              onPressed: _selectedBid != null
                  ? () {
                      game.submitBid(_selectedBid!);
                      setState(() => _selectedBid = null);
                    }
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE6F1FF),
                foregroundColor: const Color(0xFF355D89),
                disabledBackgroundColor: const Color(0xFFE0E0E0),
                disabledForegroundColor: const Color(0xFF9E9E9E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                _selectedBid != null
                    ? L10n.of(context).skGameBidSubmit(_selectedBid!)
                    : L10n.of(context).skGameSelectNumber,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: isLandscape ? 14 : 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Hand Area ──
  Widget _buildHandArea(SKGameStateData state, GameService game) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final selfPlayer = state.players.firstWhere(
      (p) => p.position == 'self',
      orElse: () => state.players.first,
    );
    final selectedCard = _selectedCard;
    final isSelectedLegal =
        selectedCard != null && state.legalCards.contains(selectedCard);
    // Pre-selection: during playing phase while it isn't our turn yet, we
    // can compute which cards WOULD be legal (based on the current lead
    // suit, if any) and let the user queue one up. When the turn arrives,
    // the server-authoritative state.legalCards takes over.
    final canPreselect =
        state.phase == 'playing' &&
        !state.isMyTurn &&
        state.currentTrick.isNotEmpty;
    final effectiveLegalCards = state.isMyTurn
        ? state.legalCards
        : (canPreselect
              ? _previewSkLegalCards(state).toList()
              : const <String>[]);

    return Container(
      padding: EdgeInsets.fromLTRB(8, 8, 8, isLandscape ? 8 : 12),
      decoration: BoxDecoration(
        color: state.isMyTurn
            ? const Color(0xFFFFF6D8).withValues(alpha: 0.96)
            : Colors.white.withValues(alpha: 0.92),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(
            color: state.isMyTurn
                ? const Color(0xFFE6C86A)
                : const Color(0xFFE0D8D4),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
            child: _buildSelfStatusRow(
              selfPlayer,
              game,
              compact: isLandscape,
            ),
          ),
          // Play button above cards
          if (state.isMyTurn && selectedCard != null && isSelectedLegal)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 8, right: 8),
              child: SizedBox(
                width: double.infinity,
                height: isLandscape ? 38 : 42,
                child: FilledButton.icon(
                  onPressed: () {
                    if (selectedCard.startsWith('sk_tigress')) {
                      _showTigressDialog(game, selectedCard);
                    } else {
                      game.playCard(selectedCard);
                      setState(() => _selectedCard = null);
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE6F1FF),
                    foregroundColor: const Color(0xFF355D89),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow, size: 20),
                  label: Text(
                    L10n.of(context).skGamePlayCardButton,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: isLandscape ? 14 : 15,
                    ),
                  ),
                ),
              ),
            )
          else if (state.isMyTurn)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                L10n.of(context).skGameSelectCard,
                style: TextStyle(
                  color: const Color(0xFF5A4038),
                  fontSize: isLandscape ? 13 : 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          // Hand cards (overlapping like Tichu)
          Padding(
            padding: EdgeInsets.symmetric(vertical: isLandscape ? 2 : 4),
            child: _buildHandRows(
              state.myCards,
              interactive: true,
              legalCards: effectiveLegalCards,
              isMyTurn: state.isMyTurn || canPreselect,
              compact: isLandscape,
            ),
          ),
        ],
      ),
    );
  }

  // Single-row status: timeout reset (left) + tricks/bid + score (right).
  Widget _buildSelfStatusRow(
    SKPlayer selfPlayer,
    GameService game, {
    required bool compact,
  }) {
    final tricks = selfPlayer.tricks;
    final bid = selfPlayer.bid;
    final hasBid = selfPlayer.hasBid && bid != null;
    final matches = hasBid && tricks == bid;
    final exceeds = hasBid && tricks > bid;

    final trickBidBg = matches
        ? const Color(0xFFE8F5E9)
        : exceeds
        ? const Color(0xFFFFF3E0)
        : const Color(0xFFE8F1FF);
    final trickBidFg = matches
        ? const Color(0xFF2E7D32)
        : exceeds
        ? const Color(0xFFE65100)
        : const Color(0xFF355D89);

    Widget chip({
      required IconData icon,
      required String value,
      required Color bg,
      required Color fg,
    }) {
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 4 : 5,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: compact ? 14 : 16, color: fg),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                color: fg,
                fontSize: compact ? 13 : 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    // Center the trick-bid + score chips horizontally; timeout reset
    // (rare) anchors to the left without pushing the centered chips.
    return Stack(
      alignment: Alignment.center,
      children: [
        if (game.myTimeoutCount > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: _buildTimeoutResetChip(game),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            chip(
              icon: Icons.workspace_premium_outlined,
              value: '$tricks/${hasBid ? bid : "-"}',
              bg: trickBidBg,
              fg: trickBidFg,
            ),
            const SizedBox(width: 8),
            chip(
              icon: Icons.stars_rounded,
              value: '${selfPlayer.totalScore}',
              bg: const Color(0xFFF6EFE8),
              fg: const Color(0xFF6A4B3A),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTimeoutResetChip(GameService game) {
    return GestureDetector(
      onTap: () => game.resetTimeout(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E0),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFFB74D)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.timer_off_outlined,
              size: 15,
              color: Color(0xFFE65100),
            ),
            const SizedBox(width: 5),
            Text(
              '${game.myTimeoutCount}/3',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFFE65100),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              L10n.of(context).skGameReset,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFFE65100),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Overlapping Hand Rows (Tichu-style) ──
  Widget _buildHandRows(
    List<String> cards, {
    bool interactive = false,
    List<String> legalCards = const [],
    bool isMyTurn = false,
    bool compact = false,
  }) {
    Widget buildCardWidget(
      String cardId,
      double cardWidth,
      double cardHeight,
      double padding,
    ) {
      final isLegal = legalCards.contains(cardId);
      final isSelected = interactive && _selectedCard == cardId;

      Widget card = Padding(
        padding: EdgeInsets.symmetric(horizontal: padding),
        child: _buildCard(cardId, size: cardHeight, highlighted: isSelected),
      );

      if (interactive) {
        card = GestureDetector(
          onTap: isMyTurn && isLegal
              ? () => setState(() {
                  _selectedCard = isSelected ? null : cardId;
                })
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            transform: Matrix4.translationValues(0, isSelected ? -12 : 0, 0),
            child: Opacity(
              opacity: !isMyTurn || isLegal ? 1.0 : 0.4,
              child: Container(
                decoration: isSelected
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF355D89,
                            ).withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      )
                    : null,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: padding),
                  child: _buildCard(
                    cardId,
                    size: cardHeight,
                    highlighted: isSelected,
                  ),
                ),
              ),
            ),
          ),
        );
      }

      return card;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalMargin = compact ? 10.0 : 12.0;
        final availableWidth = constraints.maxWidth - (horizontalMargin * 2);
        final perRow = compact
            ? cards.length
            : (cards.length <= 6 ? cards.length : (cards.length / 2).ceil());
        final dense = compact || cards.length >= 8;
        final cardPadding = dense ? (compact ? 1.0 : 1.5) : 3.0;
        final totalPadding = perRow * cardPadding * 2;
        final maxCardWidth = interactive
            ? (compact ? 42.0 : 55.0)
            : (compact ? 34.0 : 46.0);
        // Fill available width, only cap at max
        final cardWidth = ((availableWidth - totalPadding) / perRow).clamp(
          0.0,
          maxCardWidth,
        );
        final cardHeight = (cardWidth * 1.4).clamp(
          interactive ? (compact ? 42.0 : 52.0) : (compact ? 34.0 : 42.0),
          interactive ? (compact ? 60.0 : 77.0) : (compact ? 50.0 : 64.0),
        );

        List<Widget> rowWidgets(List<String> row) {
          return row
              .map(
                (cardId) =>
                    buildCardWidget(cardId, cardWidth, cardHeight, cardPadding),
              )
              .toList();
        }

        if (compact || cards.length <= 6) {
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalMargin),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: rowWidgets(cards),
            ),
          );
        }

        final half = (cards.length / 2).ceil();
        final firstRow = cards.take(half).toList();
        final secondRow = cards.skip(half).toList();

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalMargin),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: rowWidgets(firstRow),
              ),
              SizedBox(height: dense ? 2 : 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: rowWidgets(secondRow),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showTigressDialog(GameService game, String cardId) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        game.playCard(cardId, tigressChoice: 'escape');
                        setState(() => _selectedCard = null);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFFD8CCC5),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          children: [
                            _buildCard(
                              'sk_escape',
                              size: 80,
                              highlighted: false,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              L10n.of(context).skGameTigressEscape,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF6A5A52),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        game.playCard(cardId, tigressChoice: 'pirate');
                        setState(() => _selectedCard = null);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF0F0),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFFD24B4B),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          children: [
                            _buildCard(
                              'sk_pirate',
                              size: 80,
                              highlighted: false,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              L10n.of(context).skGameTigressPirate,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFD24B4B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Round End ──
  Widget _buildRoundEndUI(SKGameStateData state) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final lastHistory = state.scoreHistory.isNotEmpty
        ? state.scoreHistory.last
        : null;
    final scores = lastHistory?['scores'] as Map<String, dynamic>?;

    return Container(
      padding: EdgeInsets.all(isLandscape ? 12 : 16),
      margin: EdgeInsets.all(isLandscape ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0D8D4)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: isLandscape
              ? MediaQuery.of(context).size.height * 0.42
              : MediaQuery.of(context).size.height * 0.5,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: isLandscape ? 5 : 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F1EC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE7DBD4)),
                ),
                child: Text(
                  L10n.of(context).skGameRoundResult(state.round),
                  style: TextStyle(
                    color: Color(0xFF5A4038),
                    fontSize: isLandscape ? 14 : 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              SizedBox(height: isLandscape ? 8 : 12),
              // Table header — rank # / name / bid·tricks / bonus / round / total
              Row(
                children: [
                  SizedBox(
                    width: isLandscape ? 18 : 22,
                    child: Text(
                      '#',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: isLandscape ? 9 : 10,
                        color: const Color(0xFF8A7A72),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Expanded(
                    flex: 3,
                    child: Text('', style: TextStyle(fontSize: 11)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      L10n.of(context).skGameBidTricks,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: isLandscape ? 9 : 10,
                        color: const Color(0xFF8A7A72),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: isLandscape ? 30 : 34,
                    child: Text(
                      L10n.of(context).skGameBonusHeader,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: isLandscape ? 9 : 10,
                        color: const Color(0xFF8A7A72),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: isLandscape ? 40 : 44,
                    child: Text(
                      L10n.of(context).skGameScoreHeader,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: isLandscape ? 9 : 10,
                        color: const Color(0xFF8A7A72),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: isLandscape ? 42 : 46,
                    child: Text(
                      L10n.of(context).skGameTotalScoreHeader,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: isLandscape ? 9 : 10,
                        color: const Color(0xFF8A7A72),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 8),
              if (scores != null)
                ...(() {
                  // Sort by total score desc — keeps the leaderboard ordering
                  // so rank is immediate. Tiebreaker keeps original order.
                  final ranked = [...state.players]
                    ..sort((a, b) => b.totalScore.compareTo(a.totalScore));
                  return ranked.asMap().entries.map((entry) {
                    final rank = entry.key + 1;
                    final p = entry.value;
                    final pScore = scores[p.id] as Map<String, dynamic>?;
                    if (pScore == null) return const SizedBox.shrink();
                    final bid = pScore['bid'] ?? 0;
                    final tricks = pScore['tricks'] ?? 0;
                    final bonus = pScore['bonus'] ?? 0;
                    final roundScore = pScore['roundScore'] ?? 0;
                    final success = bid == 0 ? tricks == 0 : tricks == bid;
                    final rankColor = rank == 1
                        ? const Color(0xFFD4A24A)
                        : rank == 2
                            ? const Color(0xFF9A9A9A)
                            : rank == 3
                                ? const Color(0xFFB07A4A)
                                : const Color(0xFFA89A92);
                    return Container(
                      padding: EdgeInsets.symmetric(
                        vertical: isLandscape ? 3 : 4,
                      ),
                      decoration: BoxDecoration(
                        color: p.position == 'self'
                            ? const Color(0xFFF7F1EC)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: isLandscape ? 18 : 22,
                            child: Text(
                              '$rank',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: rankColor,
                                fontSize: isLandscape ? 12 : 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              p.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: const Color(0xFF5A4038),
                                fontSize: isLandscape ? 12 : 13,
                                fontWeight: p.position == 'self'
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  success ? Icons.check_circle : Icons.cancel,
                                  size: 12,
                                  color: success
                                      ? const Color(0xFF4CAF50)
                                      : const Color(0xFFE53935),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '$tricks/$bid',
                                  style: const TextStyle(
                                    color: Color(0xFF5A4038),
                                    fontSize: 12,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: isLandscape ? 30 : 34,
                            child: bonus > 0
                                ? Text(
                                    '+$bonus',
                                    style: TextStyle(
                                      color: Color(0xFFFFB74D),
                                      fontSize: isLandscape ? 10 : 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  )
                                : const SizedBox.shrink(),
                          ),
                          SizedBox(
                            width: isLandscape ? 40 : 44,
                            child: Text(
                              '${roundScore > 0 ? '+' : ''}$roundScore',
                              style: TextStyle(
                                color: roundScore >= 0
                                    ? const Color(0xFF4CAF50)
                                    : const Color(0xFFE53935),
                                fontSize: isLandscape ? 12 : 14,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.end,
                            ),
                          ),
                          SizedBox(
                            width: isLandscape ? 42 : 46,
                            child: Text(
                              '${p.totalScore}',
                              style: TextStyle(
                                color: const Color(0xFF5A4038),
                                fontSize: isLandscape ? 12 : 14,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ],
                      ),
                    );
                  });
                })(),
              SizedBox(height: isLandscape ? 6 : 8),
              Text(
                L10n.of(context).skGameNextRoundPreparing,
                style: TextStyle(
                  color: const Color(0xFF8A7A72),
                  fontSize: isLandscape ? 11 : 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Game End ──
  Widget _buildGameEndUI(SKGameStateData state, GameService game) {
    final sorted = List<SKPlayer>.from(state.players)
      ..sort((a, b) => b.totalScore.compareTo(a.totalScore));

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0D8D4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F1EC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE7DBD4)),
            ),
            child: Text(
              L10n.of(context).skGameGameOver,
              style: const TextStyle(
                color: Color(0xFF5A4038),
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 16),
          ...sorted.asMap().entries.map((entry) {
            final rank = entry.key + 1;
            final p = entry.value;
            final isWinner = rank == 1;
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: isWinner
                    ? const Color(0xFFFFF8E1)
                    : Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(10),
                border: isWinner
                    ? Border.all(color: const Color(0xFFFFD700))
                    : null,
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: isWinner
                          ? const Color(0xFFFFD700)
                          : const Color(0xFFF5F5F5),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isWinner
                            ? const Color(0xFFFFB300)
                            : const Color(0xFFE0D8D4),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '$rank',
                        style: TextStyle(
                          color: isWinner
                              ? Colors.black
                              : const Color(0xFF5A4038),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      p.name,
                      style: TextStyle(
                        color: const Color(0xFF5A4038),
                        fontSize: isWinner ? 16 : 14,
                        fontWeight: isWinner
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  Text(
                    '${p.totalScore}',
                    style: TextStyle(
                      color: const Color(0xFF5A4038),
                      fontSize: isWinner ? 18 : 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFC7DCF8)),
            ),
            child: Text(
              _gameEndCountdown > 0
                  ? L10n.of(
                      context,
                    ).skGameAutoReturnCountdown(_gameEndCountdown)
                  : L10n.of(context).skGameReturningToRoom,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF355D89),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Player Profile Dialog (same pattern as Tichu) ──
  void _showPlayerProfileDialog(
    String nickname,
    GameService game, {
    bool isBot = false,
  }) {
    game.requestProfile(nickname);

    showDialog(
      context: context,
      builder: (ctx) {
        String selectedGame = 'skull_king';
        return StatefulBuilder(
          builder: (ctx, setDialogState) => Consumer<GameService>(
            builder: (ctx, game, _) {
              // Auto-dismiss when the game ends so the round/result screen isn't hidden behind the dialog.
              final sk = game.skGameState;
              if (sk == null || sk.phase == 'game_end') {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!ctx.mounted) return;
                  final route = ModalRoute.of(ctx);
                  if (route != null && route.isCurrent) Navigator.of(ctx).pop();
                });
              }
              final profile = game.profileFor(nickname);
              final isLoading =
                  profile == null || profile['nickname'] != nickname;
              final isBlockedUser = game.isBlocked(nickname);

              return AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
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
                                  L10n.of(context).skGamePlayerProfile,
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
                      const SizedBox(height: 12),
                      if (!isBot)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (game.friends.contains(nickname))
                              _buildProfileIconButton(
                                icon: Icons.check,
                                color: const Color(0xFFBDBDBD),
                                tooltip: L10n.of(context).skGameAlreadyFriend,
                                onTap: () {},
                              )
                            else if (game.sentFriendRequests.contains(nickname))
                              _buildProfileIconButton(
                                icon: Icons.hourglass_top,
                                color: const Color(0xFFBDBDBD),
                                tooltip: L10n.of(context).skGameRequestPending,
                                onTap: () {},
                              )
                            else
                              _buildProfileIconButton(
                                icon: Icons.person_add,
                                color: const Color(0xFF81C784),
                                tooltip: L10n.of(context).skGameAddFriend,
                                onTap: () {
                                  game.addFriendAction(nickname);
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        L10n.of(
                                          context,
                                        ).skGameFriendRequestSent,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            _buildProfileIconButton(
                              icon: isBlockedUser
                                  ? Icons.block
                                  : Icons.shield_outlined,
                              color: isBlockedUser
                                  ? const Color(0xFF64B5F6)
                                  : const Color(0xFFFF8A65),
                              tooltip: isBlockedUser
                                  ? L10n.of(context).skGameUnblockUser
                                  : L10n.of(context).skGameBlockUser,
                              onTap: () {
                                if (isBlockedUser) {
                                  game.unblockUserAction(nickname);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        L10n.of(context).skGameUserUnblocked,
                                      ),
                                    ),
                                  );
                                } else {
                                  game.blockUserAction(nickname);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        L10n.of(context).skGameUserBlocked,
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                          ],
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
                          maxHeight: 400,
                        ),
                        child: SingleChildScrollView(
                          child: _buildProfileContent(
                            profile,
                            selectedGame: selectedGame,
                            onGameChanged: (g) =>
                                setDialogState(() => selectedGame = g),
                          ),
                        ),
                      ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(L10n.of(context).commonClose),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildProfileContent(
    Map<String, dynamic> data, {
    required String selectedGame,
    required ValueChanged<String> onGameChanged,
  }) {
    final profile = data['profile'] as Map<String, dynamic>?;
    if (profile == null) {
      return Text(
        L10n.of(context).skGameProfileNotFound,
        style: const TextStyle(color: Color(0xFF8A7A72)),
      );
    }

    final l10n = L10n.of(context);
    final totalGames = profile['totalGames'] ?? 0;
    final wins = profile['wins'] ?? 0;
    final losses = profile['losses'] ?? 0;
    final winRate = profile['winRate'] ?? 0;
    final level = profile['level'] ?? 1;

    // Game selector config
    String gameLabel;
    String gameEmoji;
    Color gameBgColor;
    Color gameFgColor;
    switch (selectedGame) {
      case 'skull_king':
        gameLabel = l10n.lobbySkullKing;
        gameEmoji = '⚓';
        gameBgColor = const Color(0xFF2D2D3D);
        gameFgColor = const Color(0xFFFFD54F);
        break;
      case 'love_letter':
        gameLabel = l10n.lobbyLoveLetter;
        gameEmoji = '❤️';
        gameBgColor = const Color(0xFFE91E63);
        gameFgColor = Colors.white;
        break;
      default:
        gameLabel = l10n.lobbyTichu;
        gameEmoji = '🃏';
        gameBgColor = const Color(0xFF7E57C2);
        gameFgColor = Colors.white;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Level
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(12),
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
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Game selector button
        InkWell(
          onTap: () {
            showModalBottomSheet(
              context: context,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              builder: (bCtx) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      leading: const Text('🃏', style: TextStyle(fontSize: 20)),
                      title: Text(l10n.lobbyTichu),
                      trailing: selectedGame == 'tichu'
                          ? const Icon(Icons.check, color: Color(0xFF7E57C2))
                          : null,
                      onTap: () {
                        Navigator.pop(bCtx);
                        onGameChanged('tichu');
                      },
                    ),
                    ListTile(
                      leading: const Text('⚓', style: TextStyle(fontSize: 20)),
                      title: Text(l10n.lobbySkullKing),
                      trailing: selectedGame == 'skull_king'
                          ? const Icon(Icons.check, color: Color(0xFF2D2D3D))
                          : null,
                      onTap: () {
                        Navigator.pop(bCtx);
                        onGameChanged('skull_king');
                      },
                    ),
                    ListTile(
                      leading: const Text('❤️', style: TextStyle(fontSize: 20)),
                      title: Text(l10n.lobbyLoveLetter),
                      trailing: selectedGame == 'love_letter'
                          ? const Icon(Icons.check, color: Color(0xFFE91E63))
                          : null,
                      onTap: () {
                        Navigator.pop(bCtx);
                        onGameChanged('love_letter');
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: gameBgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Text(gameEmoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    gameLabel,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: gameFgColor,
                    ),
                  ),
                ),
                Icon(Icons.arrow_drop_down, color: gameFgColor),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (selectedGame == 'tichu')
          _buildStatsCard(
            title: l10n.skGameTichuRecord,
            icon: Icons.style,
            iconColor: const Color(0xFFFFB74D),
            bgColor: const Color(0xFFF5F5F5),
            games: totalGames,
            wins: wins,
            losses: losses,
            winRate: winRate,
          )
        else if (selectedGame == 'skull_king')
          Builder(
            builder: (_) {
              final skGames = profile['skTotalGames'] ?? 0;
              final skWins = profile['skWins'] ?? 0;
              final skLosses = profile['skLosses'] ?? 0;
              final skWinRate = profile['skWinRate'] ?? 0;
              return _buildStatsCard(
                title: l10n.skGameSkullKingRecord,
                icon: Icons.anchor,
                iconColor: const Color(0xFF3949AB),
                bgColor: const Color(0xFFE8EAF6),
                games: skGames,
                wins: skWins,
                losses: skLosses,
                winRate: skWinRate,
              );
            },
          )
        else
          Builder(
            builder: (_) {
              final llGames = profile['llTotalGames'] ?? 0;
              final llWins = profile['llWins'] ?? 0;
              final llLosses = profile['llLosses'] ?? 0;
              final llWinRate = profile['llWinRate'] ?? 0;
              return _buildStatsCard(
                title: l10n.skGameLoveLetterRecord,
                icon: Icons.favorite,
                iconColor: const Color(0xFFE91E63),
                bgColor: const Color(0xFFFCE4EC),
                games: llGames,
                wins: llWins,
                losses: llLosses,
                winRate: llWinRate,
              );
            },
          ),
      ],
    );
  }

  Widget _buildStatsCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required int games,
    required int wins,
    required int losses,
    required int winRate,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bgColor.withValues(alpha: 0.6)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 16),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF5A4038),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatChip(
                L10n.of(context).skGameStatRecord,
                L10n.of(context).skGameRecordFormat(games, wins, losses),
              ),
              _buildStatChip(L10n.of(context).skGameStatWinRate, '$winRate%'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0D8D4)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: Color(0xFF8A7A72)),
          ),
          const SizedBox(height: 2),
          Text(
            value,
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

  // ── SK Card Widget ──
  // Suit symbols and colors for number cards
  static const _suitColors = {
    'yellow': Color(0xFFD4A017),
    'green': Color(0xFF2E7D32),
    'purple': Color(0xFF6A1B9A),
    'black': Color(0xFF212121),
  };

  // Special card asset mapping
  static const _specialAssets = {
    'skull_king': 'assets/cards/sk_skull_king.png',
    'pirate': 'assets/cards/sk_pirate.png',
    'mermaid': 'assets/cards/sk_mermaid.png',
    'escape': 'assets/cards/sk_escape.png',
    'tigress': 'assets/cards/sk_tigress.png',
    'kraken': 'assets/cards/sk_kraken.png',
    'white_whale': 'assets/cards/sk_white_whale.png',
    'loot': 'assets/cards/sk_loot.png',
  };
  static const _specialLabels = {
    'skull_king': 'SKULL\nKING',
    'pirate': 'PIRATE',
    'mermaid': 'MERMAID',
    'escape': 'ESCAPE',
    'tigress': 'TIGRESS',
    'kraken': 'KRAKEN',
    'white_whale': 'WHITE\nWHALE',
    'loot': 'LOOT',
  };
  static const _specialBgColors = {
    'skull_king': Color(0xFF1A1A1A),
    'pirate': Color(0xFF8B1A1A),
    'mermaid': Color(0xFF0D5E7A),
    'escape': Color(0xFF757575),
    'tigress': Color(0xFF5E35B1),
    'kraken': Color(0xFF2B1E3F),
    'white_whale': Color(0xFF3A6B8F),
    'loot': Color(0xFF8B6F22),
  };

  Widget _buildCard(
    String cardId, {
    double size = 60,
    bool highlighted = false,
  }) {
    final info = _parseCardId(cardId);
    final w = size * 0.7;
    final h = size;
    final radius = BorderRadius.circular(6);

    final border = Border.all(
      color: highlighted
          ? const Color(0xFF355D89)
          : Colors.black.withValues(alpha: 0.15),
      width: highlighted ? 2.5 : 1,
    );
    final shadow = [
      BoxShadow(
        color: highlighted
            ? const Color(0xFF355D89).withValues(alpha: 0.4)
            : Colors.black.withValues(alpha: 0.10),
        blurRadius: highlighted ? 8 : 3,
        offset: const Offset(0, 1),
      ),
    ];

    // ── Number card: playing-card style ──
    if (info.type == 'number') {
      final color = _suitColors[info.suit] ?? Colors.grey;

      return Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: radius,
          border: border,
          boxShadow: shadow,
        ),
        child: Stack(
          children: [
            // Top-left: rank + suit
            Positioned(
              left: 3,
              top: 2,
              child: Column(
                children: [
                  Text(
                    info.rank,
                    style: TextStyle(
                      fontSize: size * 0.18,
                      fontWeight: FontWeight.w900,
                      color: color,
                      height: 1.0,
                    ),
                  ),
                  SizedBox(
                    width: size * 0.13,
                    height: size * 0.13,
                    child: _buildSuitGlyph(info.suit, color, size * 0.13),
                  ),
                ],
              ),
            ),
            // Center: large suit symbol
            Center(
              child: _buildSuitGlyph(
                info.suit,
                color.withValues(alpha: 0.25),
                size * 0.32,
              ),
            ),
            // Bottom-right: rank + suit (upside down)
            Positioned(
              right: 3,
              bottom: 2,
              child: Transform.rotate(
                angle: 3.14159,
                child: Column(
                  children: [
                    Text(
                      info.rank,
                      style: TextStyle(
                        fontSize: size * 0.18,
                        fontWeight: FontWeight.w900,
                        color: color,
                        height: 1.0,
                      ),
                    ),
                    SizedBox(
                      width: size * 0.13,
                      height: size * 0.13,
                      child: _buildSuitGlyph(info.suit, color, size * 0.13),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ── Special card: image with fallback ──
    final bgColor = _specialBgColors[info.type] ?? const Color(0xFF424242);
    // Pirates use per-card artwork (sk_pirate1..4.png) so each of the 4
    // pirates looks distinct. Non-pirate specials (and pirate with no number)
    // fall back to the default asset from _specialAssets.
    String? assetPath;
    if (info.type == 'pirate' && info.number.isNotEmpty) {
      assetPath = 'assets/cards/sk_pirate${info.number}.png';
    } else {
      assetPath = _specialAssets[info.type];
    }
    final fallbackLabel = _specialLabels[info.type] ?? '?';

    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: radius,
        border: border,
        boxShadow: shadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: assetPath != null
          ? Image.asset(
              assetPath,
              fit: BoxFit.cover,
              errorBuilder: (_, e, s) =>
                  _buildSpecialFallback(fallbackLabel, size),
            )
          : _buildSpecialFallback(fallbackLabel, size),
    );
  }

  Widget _buildSpecialFallback(String label, double size) {
    return Center(
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.14,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          height: 1.2,
        ),
      ),
    );
  }

  Widget _buildSuitGlyph(String suit, Color color, double size) {
    return CustomPaint(
      painter: _SkSuitPainter(suit: suit, color: color),
      size: Size.square(size),
    );
  }

  /// Preview the set of legal cards for SK follow-suit rules, used to let
  /// the user pre-select a card while it isn't their turn yet. Mirrors the
  /// server's SkullKingGame.getLegalCards: if no numbered card has been
  /// led yet, anything is legal; otherwise must follow the lead suit if
  /// possible, and special (non-number) cards are always legal.
  Set<String> _previewSkLegalCards(SKGameStateData state) {
    final hand = state.myCards;
    final trick = state.currentTrick;
    if (hand.isEmpty) return const <String>{};
    if (trick.isEmpty) return hand.toSet();
    // Determine lead suit from the first actual number card in the trick.
    // Tigress counts as pirate or escape based on the player's choice, so
    // it never sets the lead suit.
    String? leadSuit;
    for (final play in trick) {
      final info = _parseCardId(play.cardId);
      var type = info.type;
      if (type == 'tigress') {
        type = play.tigressChoice == 'pirate' ? 'pirate' : 'escape';
      }
      if (type == 'number') {
        leadSuit = info.suit;
        break;
      }
    }
    if (leadSuit == null) return hand.toSet();
    final hasLeadSuit = hand.any((c) {
      final info = _parseCardId(c);
      return info.type == 'number' && info.suit == leadSuit;
    });
    if (!hasLeadSuit) return hand.toSet();
    return hand.where((c) {
      final info = _parseCardId(c);
      return info.type != 'number' || info.suit == leadSuit;
    }).toSet();
  }

  _CardInfo _parseCardId(String cardId) {
    if (cardId == 'sk_skull_king') return _CardInfo(type: 'skull_king');
    if (cardId == 'sk_kraken') return _CardInfo(type: 'kraken');
    if (cardId == 'sk_white_whale') return _CardInfo(type: 'white_whale');
    if (cardId.startsWith('sk_tigress')) return _CardInfo(type: 'tigress');
    if (cardId == 'sk_escape') return _CardInfo(type: 'escape');
    if (cardId == 'sk_pirate') return _CardInfo(type: 'pirate');
    if (cardId == 'sk_mermaid') return _CardInfo(type: 'mermaid');
    if (cardId.startsWith('sk_escape_')) {
      return _CardInfo(type: 'escape', number: cardId.split('_').last);
    }
    if (cardId.startsWith('sk_pirate_')) {
      return _CardInfo(type: 'pirate', number: cardId.split('_').last);
    }
    if (cardId.startsWith('sk_mermaid_')) {
      return _CardInfo(type: 'mermaid', number: cardId.split('_').last);
    }
    if (cardId.startsWith('sk_loot_')) {
      return _CardInfo(type: 'loot', number: cardId.split('_').last);
    }
    final parts = cardId.split('_');
    if (parts.length == 3) {
      return _CardInfo(type: 'number', suit: parts[1], rank: parts[2]);
    }
    return _CardInfo(type: 'unknown');
  }
}

class _CardInfo {
  final String type;
  final String suit;
  final String rank;
  final String number;

  _CardInfo({
    this.type = 'unknown',
    this.suit = '',
    this.rank = '',
    this.number = '',
  });
}

class _SkSuitPainter extends CustomPainter {
  const _SkSuitPainter({required this.suit, required this.color});

  final String suit;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    switch (suit) {
      case 'purple':
        _drawDiamond(canvas, size, paint);
        break;
      case 'green':
        _drawClub(canvas, size, paint);
        break;
      case 'yellow':
        _drawStar(canvas, size, paint);
        break;
      case 'black':
        _drawSkull(canvas, size, paint);
        break;
      default:
        _drawDiamond(canvas, size, paint);
        break;
    }
  }

  void _drawDiamond(Canvas canvas, Size size, Paint paint) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(0, size.height / 2)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawClub(Canvas canvas, Size size, Paint paint) {
    final r = size.width * 0.18;
    canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.28), r, paint);
    canvas.drawCircle(Offset(size.width * 0.3, size.height * 0.52), r, paint);
    canvas.drawCircle(Offset(size.width * 0.7, size.height * 0.52), r, paint);
    final stem = Path()
      ..moveTo(size.width * 0.45, size.height * 0.58)
      ..lineTo(size.width * 0.55, size.height * 0.58)
      ..lineTo(size.width * 0.62, size.height * 0.9)
      ..lineTo(size.width * 0.38, size.height * 0.9)
      ..close();
    canvas.drawPath(stem, paint);
  }

  void _drawStar(Canvas canvas, Size size, Paint paint) {
    final center = Offset(size.width / 2, size.height / 2);
    final outer = size.width / 2;
    final inner = outer * 0.45;
    final path = Path();
    for (int i = 0; i < 10; i++) {
      final radius = i.isEven ? outer : inner;
      final angle = -1.5708 + i * 0.6283;
      final point = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawSkull(Canvas canvas, Size size, Paint paint) {
    canvas.drawOval(
      Rect.fromLTWH(
        size.width * 0.2,
        size.height * 0.1,
        size.width * 0.6,
        size.height * 0.55,
      ),
      paint,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * 0.32,
        size.height * 0.62,
        size.width * 0.36,
        size.height * 0.18,
      ),
      paint,
    );

    final cutout = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.fill;
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawOval(
      Rect.fromLTWH(
        size.width * 0.2,
        size.height * 0.1,
        size.width * 0.6,
        size.height * 0.55,
      ),
      paint,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * 0.32,
        size.height * 0.62,
        size.width * 0.36,
        size.height * 0.18,
      ),
      paint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.38, size.height * 0.36),
      size.width * 0.08,
      cutout,
    );
    canvas.drawCircle(
      Offset(size.width * 0.62, size.height * 0.36),
      size.width * 0.08,
      cutout,
    );
    final nose = Path()
      ..moveTo(size.width * 0.5, size.height * 0.45)
      ..lineTo(size.width * 0.44, size.height * 0.56)
      ..lineTo(size.width * 0.56, size.height * 0.56)
      ..close();
    canvas.drawPath(nose, cutout);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SkSuitPainter oldDelegate) {
    return suit != oldDelegate.suit || color != oldDelegate.color;
  }
}

class _SKSpectatorHandAreaMarker extends StatelessWidget {
  const _SKSpectatorHandAreaMarker({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
