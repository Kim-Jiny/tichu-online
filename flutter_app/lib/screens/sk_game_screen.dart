import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/game_service.dart';
import '../services/network_service.dart';
import '../services/session_service.dart';
import '../models/sk_game_state.dart';
import '../models/player.dart';
import '../widgets/connection_overlay.dart';
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
  bool _chatOpen = false;
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
  bool _wasDisconnected = false;
  bool _waitingForRoomRecovery = false;
  GameService? _gameService;
  NetworkService? _networkService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gameService = context.read<GameService>();
      _gameService!.requestBlockedUsers();
      _networkService = context.read<NetworkService>();
      _networkService!.addListener(_onNetworkChanged);
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateCountdown();
    });
  }

  void _onNetworkChanged() {
    if (!mounted) return;
    final network = _networkService;
    if (network == null) return;
    if (!network.isConnected) {
      _wasDisconnected = true;
    } else if (_wasDisconnected && network.isConnected) {
      _wasDisconnected = false;
      context.read<GameService>().checkRoom();
    }
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
    _networkService?.removeListener(_onNetworkChanged);
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
      _gameEndCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.jumpTo(_chatScrollController.position.maxScrollExtent);
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
                      title: session.isRestoring ? L10n.of(context).skGameRecoveringGame : L10n.of(context).skGameCheckingState,
                    );
                  }

                  final state = game.skGameState;
                  final isSpectating = game.isSpectator;
                  if (isSpectating && game.hasRoom && !game.hasActiveGame && state == null) {
                    return _buildSpectatorWaitingRoom(game);
                  }
                  if (state == null) {
                    if (game.hasRoom) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _recoverRoomState();
                      });
                      return _buildRecoveryLoading(title: L10n.of(context).skGameReloadingRoom);
                    }
                    return _buildRecoveryLoading(title: L10n.of(context).skGameLoadingState);
                  }

                  _syncGameEndCountdown(state.phase);

                  // Clear selected card and bid when a NEW round's bidding starts
                  if (state.phase == 'bidding' && state.round != _lastBiddingRound) {
                    _lastBiddingRound = state.round;
                    if (_selectedCard != null || _selectedBid != null) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() { _selectedCard = null; _selectedBid = null; });
                      });
                    }
                  }
                  // Clear selected card if it's no longer in hand
                  if (_selectedCard != null && !state.myCards.contains(_selectedCard)) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _selectedCard = null);
                    });
                  }

                  if (isSpectating) {
                    return Stack(
                      children: [
                        Column(
                          children: [
                            _buildSpectatorTopBar(state, game),
                            _buildSpectatorScoreboard(state, game),
                            Expanded(
                              child: Column(
                                children: [
                                  const Spacer(),
                                  _buildTrickArea(state),
                                  const Spacer(),
                                ],
                              ),
                            ),
                            if (['bidding', 'playing', 'trick_end'].contains(state.phase))
                              _buildSpectatorHandArea(state, game),
                            if (state.phase == 'round_end') _buildRoundEndUI(state),
                            if (state.phase == 'game_end') _buildGameEndUI(state, game),
                          ],
                        ),
                        if (_chatOpen) _buildChatPanel(game),
                      ],
                    );
                  }

                  return Stack(
                    children: [
                      Column(
                        children: [
                          _buildTopBar(state, game),
                          _buildScoreboard(state, game),
                          Expanded(
                            child: Column(
                              children: [
                                const Spacer(),
                                _buildTrickArea(state),
                                const Spacer(),
                              ],
                            ),
                          ),
                          if (state.phase == 'bidding') _buildBiddingUI(state, game),
                          if (state.phase == 'playing' || state.phase == 'trick_end')
                            _buildHandArea(state, game),
                          if (state.phase == 'round_end') _buildRoundEndUI(state),
                          if (state.phase == 'game_end') _buildGameEndUI(state, game),
                        ],
                      ),
                      if (game.errorMessage != null)
                        _buildSKErrorBanner(game.errorMessage!),
                      if (game.timeoutPlayerName != null)
                        _buildSKTimeoutBanner(game.timeoutPlayerName!),
                      if (game.desertedPlayerName != null)
                        _buildSKDesertionBanner(game.desertedPlayerName!, game.desertedReason ?? 'leave'),
                      if (game.hasIncomingCardViewRequests)
                        _buildCardViewRequestPopup(game),
                      if (_viewersOpen) _buildViewersPanel(game),
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
    final players = game.roomPlayers.whereType<Player>().toList();
    return Padding(
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
                        color: const Color(0xFF6A5A52).withValues(alpha: 0.92),
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
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: wide ? 2 : 1,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: wide ? 1.65 : 2.3,
                            ),
                            itemCount: players.length,
                            itemBuilder: (context, index) {
                              final p = players[index];
                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFFE0D8D4)),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: p.isHost
                                            ? const Color(0xFFFFF2B3)
                                            : const Color(0xFFF2ECE8),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        p.isHost ? Icons.emoji_events : Icons.person,
                                        size: 18,
                                        color: p.isHost
                                            ? const Color(0xFFE6A800)
                                            : const Color(0xFF6A5A52),
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
                                          const SizedBox(height: 2),
                                          Text(
                                            p.isHost ? L10n.of(context).skGameHost : (p.isReady ? L10n.of(context).skGameReady : L10n.of(context).skGameWaiting),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: const Color(0xFF8A7A72).withValues(alpha: 0.92),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
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
            icon: Icons.chat_bubble_outline_rounded,
            active: _chatOpen,
            badgeCount: _chatOpen ? 0 : (game.chatMessages.length - _readChatCount).clamp(0, 99),
            onTap: () {
              setState(() {
                _chatOpen = !_chatOpen;
                if (_chatOpen) {
                  _readChatCount = game.chatMessages.length;
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
            Text(L10n.of(context).skGameSpectatorListTitle),
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
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F1F1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE0D8D4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.person, size: 16, color: Color(0xFF6A5A52)),
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
          if (!game.isSpectator)
            StatefulBuilder(
              builder: (context, setDialogState) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () {
                        game.setAutoAcceptCardView(!game.autoAcceptCardView);
                        setDialogState(() {});
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: game.autoAcceptCardView ? const Color(0xFFE8F5E9) : const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              game.autoAcceptCardView ? Icons.check_circle : Icons.check_circle_outline,
                              size: 16,
                              color: game.autoAcceptCardView ? const Color(0xFF4CAF50) : const Color(0xFF999999),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              L10n.of(context).skGameAlwaysAccept,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: game.autoAcceptCardView ? const Color(0xFF4CAF50) : const Color(0xFF999999),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () {
                        game.setAutoRejectCardView(!game.autoRejectCardView);
                        setDialogState(() {});
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: game.autoRejectCardView ? const Color(0xFFFFEBEE) : const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              game.autoRejectCardView ? Icons.block : Icons.block_outlined,
                              size: 16,
                              color: game.autoRejectCardView ? const Color(0xFFE53935) : const Color(0xFF999999),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              L10n.of(context).skGameAlwaysReject,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: game.autoRejectCardView ? const Color(0xFFE53935) : const Color(0xFF999999),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
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
    final hasViewers = game.cardViewers.isNotEmpty;
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
                  L10n.of(context).skGameRoundTrick(state.round, state.trickNumber),
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
          _buildTopActionButton(
            icon: Icons.history_rounded,
            active: false,
            onTap: () => _showScoreHistoryDialog(state),
          ),
          if (hasViewers) ...[
            const SizedBox(width: 6),
            _buildTopActionButton(
              icon: Icons.visibility,
              active: _viewersOpen,
              badgeCount: game.cardViewers.length,
              onTap: () {
                setState(() {
                  _viewersOpen = !_viewersOpen;
                });
              },
            ),
          ],
          const SizedBox(width: 6),
          _buildTopActionButton(
            icon: Icons.chat_bubble_outline_rounded,
            active: _chatOpen,
            badgeCount: _chatOpen ? 0 : (game.chatMessages.length - _readChatCount).clamp(0, 99),
            onTap: () {
              setState(() {
                _chatOpen = !_chatOpen;
                if (_chatOpen) {
                  _readChatCount = game.chatMessages.length;
                }
              });
            },
          ),
          const SizedBox(width: 6),
          _buildTopActionButton(
            icon: Icons.exit_to_app,
            active: false,
            iconColor: const Color(0xFFE53935),
            onTap: () => _showExitConfirmDialog(game),
          ),
        ],
      ),
    );
  }

  Widget _buildSpectatorTopBar(SKGameStateData state, GameService game) {
    if (state.players.isEmpty) return const SizedBox.shrink();
    final displayId = state.phase == 'bidding' ? state.roundStarter : state.currentPlayer;
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
                const Icon(Icons.visibility_rounded, size: 14, color: Colors.white),
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
                  L10n.of(context).skGameRoundTrick(state.round, state.trickNumber),
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
                      ? L10n.of(context).skGameBiddingInProgress(currentPlayerName)
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
          _buildTopActionButton(
            icon: Icons.history_rounded,
            active: false,
            onTap: () => _showScoreHistoryDialog(state),
          ),
          const SizedBox(width: 6),
          _buildTopActionButton(
            icon: Icons.chat_bubble_outline_rounded,
            active: _chatOpen,
            badgeCount: _chatOpen ? 0 : (game.chatMessages.length - _readChatCount).clamp(0, 99),
            onTap: () {
              setState(() {
                _chatOpen = !_chatOpen;
                if (_chatOpen) {
                  _readChatCount = game.chatMessages.length;
                }
              });
            },
          ),
          const SizedBox(width: 6),
          _buildTopActionButton(
            icon: Icons.exit_to_app,
            active: false,
            iconColor: const Color(0xFFFFC4C4),
            onTap: () => game.leaveRoom(),
          ),
        ],
      ),
    );
  }

  Widget _buildSpectatorScoreboard(SKGameStateData state, GameService game) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      margin: const EdgeInsets.only(bottom: 96),
      child: Row(
        children: state.players.map((p) {
          final isCurrentTurn = state.phase == 'bidding'
              ? p.id == state.roundStarter
              : p.id == state.currentPlayer;
          final isPending = game.pendingCardViewRequests.contains(p.id);
          final isApproved = game.approvedCardViews.contains(p.id) && p.canViewCards;
          final isViewing = _viewingPlayerId == p.id && isApproved;
          final trickPlay = state.currentTrick
              .cast<SKTrickPlay?>()
              .firstWhere((play) => play?.playerId == p.id, orElse: () => null);
          final isTrickWinner =
              state.phase == 'trick_end' && state.lastTrickWinner == p.id;
          return Expanded(
            child: GestureDetector(
                  onTap: () {
                    if (isApproved) {
                      setState(() => _viewingPlayerId = p.id);
                    } else if (isPending) {
                      // do nothing
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
                  child: SizedBox(
                    width: double.infinity,
                    child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        decoration: BoxDecoration(
                          color: isViewing
                              ? const Color(0xFFE3EFFF)
                              : isCurrentTurn
                                  ? const Color(0xFFFFF2B3)
                                  : Colors.white.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(12),
                          border: isViewing
                              ? Border.all(color: const Color(0xFF64B5F6), width: 2)
                              : isCurrentTurn
                                  ? Border.all(color: const Color(0xFFE6C86A), width: 2)
                                  : Border.all(color: const Color(0xFFE0D8D4)),
                        ),
                        child: Opacity(
                          opacity: p.connected ? 1.0 : 0.45,
                          child: Column(
                            children: [
                              // Timeout area (always reserved)
                              SizedBox(
                                height: 16,
                                child: p.timeoutCount > 0
                                    ? Text(
                                        '⏱ ${p.timeoutCount}/3',
                                        style: const TextStyle(
                                          color: Color(0xFFE65100),
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      )
                                    : null,
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (isCurrentTurn)
                                    Container(
                                      width: 6,
                                      height: 6,
                                      margin: const EdgeInsets.only(right: 4),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFE6A800),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  Flexible(
                                    child: Text(
                                      p.name,
                                      style: const TextStyle(
                                        color: Color(0xFF5A4038),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${p.totalScore}',
                                style: const TextStyle(
                                  color: Color(0xFF5A4038),
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              // Bid area (always reserved)
                              SizedBox(
                                height: 18,
                                child: p.hasBid && p.bid != null
                                    ? Container(
                                        margin: const EdgeInsets.only(top: 2),
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      )
                                    : p.hasBid && p.bid == null
                                        ? Container(
                                            margin: const EdgeInsets.only(top: 2),
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF0EBF8),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Icon(Icons.check, size: 12, color: Color(0xFF7A6A95)),
                                          )
                                        : null,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (isPending)
                        Positioned(
                          right: 2,
                          top: -4,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFFE0D8D4)),
                            ),
                            child: const Icon(Icons.schedule, size: 12, color: Color(0xFFFFB74D)),
                          ),
                        )
                      else if (isApproved)
                        Positioned(
                          right: 2,
                          top: -4,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFF64B5F6)),
                            ),
                            child: const Icon(Icons.visibility, size: 12, color: Color(0xFF64B5F6)),
                          ),
                        )
                      else
                        Positioned(
                          right: 2,
                          top: -4,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFFE0D8D4)),
                            ),
                            child: Icon(Icons.visibility_outlined, size: 12, color: const Color(0xFF8A7A72).withValues(alpha: 0.6)),
                          ),
                        ),
                      if (trickPlay != null)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: -90,
                          child: Center(
                            child: _buildPlayedCardBadge(
                              trickPlay,
                              highlighted: isTrickWinner,
                            ),
                          ),
                        ),
                    ],
                  ),
                  ),
                ),
              );
        }).toList(),
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
    final isApproved = viewingPlayer != null &&
        game.approvedCardViews.contains(viewingPlayer.id) &&
        viewingPlayer.canViewCards;
    final isPending = viewingPlayer != null &&
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
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFFB74D)),
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
              child: Text(
                L10n.of(context).skGamePlayerHand(viewingPlayer.name),
                style: const TextStyle(
                  color: Color(0xFF5A4038),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (viewingPlayer.cards.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  L10n.of(context).skGameNoCards,
                  style: const TextStyle(color: Color(0xFF8A7A72), fontSize: 12),
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
    if (_remainingSeconds <= 0 || state.players.isEmpty) return const SizedBox.shrink();

    final timerId = state.phase == 'bidding' ? state.roundStarter : state.currentPlayer;
    final currentPlayerName = state.players
        .firstWhere((p) => p.id == timerId, orElse: () => state.players.first)
        .name;
    final displayName = currentPlayerName.length > 8
        ? '${currentPlayerName.substring(0, 8)}…'
        : currentPlayerName;
    final turnLabel = state.phase == 'bidding'
        ? L10n.of(context).skGameLeaderLabel(displayName)
        : state.isMyTurn ? L10n.of(context).skGameMyTurn : L10n.of(context).skGameWaitingFor(displayName);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: _remainingSeconds <= 10
              ? const Color(0xFFFFE4E4)
              : Colors.white.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _remainingSeconds <= 10
                ? const Color(0xFFFF6B6B)
                : const Color(0xFFD7CEC8),
            width: _remainingSeconds <= 10 ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.schedule,
              size: 14,
              color: _remainingSeconds <= 10
                  ? const Color(0xFFCC4444)
                  : const Color(0xFF6A5A52),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                turnLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: _remainingSeconds <= 10
                      ? const Color(0xFFCC4444)
                      : const Color(0xFF5A4038),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              L10n.of(context).skGameSecondsShort(_remainingSeconds),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: _remainingSeconds <= 10
                    ? const Color(0xFFCC4444)
                    : const Color(0xFF5A4038),
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
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: active
                  ? const Color(0xFF5A4038).withValues(alpha: 0.92)
                  : Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 6,
                ),
              ],
            ),
            child: Icon(
              icon,
              size: 19,
              color: active
                  ? Colors.white
                  : (iconColor ?? const Color(0xFF5A4038)),
            ),
          ),
          if (badgeCount > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white, width: 1.2),
                ),
                child: Text(
                  badgeCount > 99 ? '99+' : '$badgeCount',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showExitConfirmDialog(GameService game) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: const Color(0xFFF8F4F1),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(L10n.of(context).skGameLeaveButton),
          ),
        ],
      ),
    );
  }

  // ── Scoreboard ──
  Widget _buildScoreboard(SKGameStateData state, GameService game) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      margin: const EdgeInsets.only(bottom: 96),
      child: Row(
        children: state.players.map((p) {
          final isCurrentTurn = state.phase == 'bidding'
              ? p.id == state.roundStarter
              : p.id == state.currentPlayer;
          final isSelf = p.position == 'self';
          final trickPlay = state.currentTrick
              .cast<SKTrickPlay?>()
              .firstWhere((play) => play?.playerId == p.id, orElse: () => null);
          final isTrickWinner =
              state.phase == 'trick_end' && state.lastTrickWinner == p.id;
          return Expanded(
            child: GestureDetector(
                  onTap: isSelf ? null : () => _showPlayerProfileDialog(p.name, game, isBot: p.id.startsWith('bot_')),
                  child: SizedBox(
                    width: double.infinity,
                    child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelf
                              ? Colors.white.withValues(alpha: 0.95)
                              : isCurrentTurn
                                  ? const Color(0xFFFFF2B3)
                                  : Colors.white.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(12),
                          border: isCurrentTurn
                              ? Border.all(color: const Color(0xFFE6C86A), width: 2)
                              : Border.all(color: const Color(0xFFE0D8D4)),
                          boxShadow: isSelf
                              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4)]
                              : null,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Timeout area (always reserved)
                            SizedBox(
                              height: 16,
                              child: p.timeoutCount > 0
                                  ? Text(
                                      '⏱ ${p.timeoutCount}/3',
                                      style: const TextStyle(
                                        color: Color(0xFFE65100),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    )
                                  : null,
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (isCurrentTurn)
                                  Container(
                                    width: 6,
                                    height: 6,
                                    margin: const EdgeInsets.only(right: 4),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFE6A800),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                Flexible(
                                  child: Text(
                                    p.name,
                                    style: TextStyle(
                                      color: const Color(0xFF5A4038),
                                      fontSize: 11,
                                      fontWeight: isSelf ? FontWeight.w800 : FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${p.totalScore}',
                              style: const TextStyle(
                                color: Color(0xFF5A4038),
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            // Bid area (always reserved)
                            SizedBox(
                              height: 18,
                              child: p.hasBid && p.bid != null
                                  ? Container(
                                      margin: const EdgeInsets.only(top: 2),
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    )
                                  : p.hasBid && p.bid == null
                                      ? Container(
                                          margin: const EdgeInsets.only(top: 2),
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF0EBF8),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Icon(Icons.check, size: 12, color: Color(0xFF7A6A95)),
                                        )
                                      : null,
                            ),
                          ],
                        ),
                      ),
                      if (trickPlay != null)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: -90,
                          child: Center(
                            child: _buildPlayedCardBadge(
                              trickPlay,
                              highlighted: isTrickWinner,
                            ),
                          ),
                        ),
                    ],
                  ),
                  ),
                ),
              );
        }).toList(),
      ),
    );
  }

  Widget _buildPlayedCardBadge(
    SKTrickPlay play, {
    required bool highlighted,
  }) {
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
            child: const Icon(
              Icons.check,
              size: 13,
              color: Colors.white,
            ),
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
                style: const TextStyle(color: Color(0xFFCC4444), fontWeight: FontWeight.bold, fontSize: 14),
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
                style: const TextStyle(color: Color(0xFFE65100), fontWeight: FontWeight.bold, fontSize: 14),
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
                style: const TextStyle(color: Color(0xFFCC4444), fontWeight: FontWeight.bold, fontSize: 14),
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
                      onPressed: () => game.respondCardViewRequest(spectatorId, false),
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
                      onPressed: () => game.respondCardViewRequest(spectatorId, true),
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
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: game.rejectAllCardViewRequests,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF999999),
                        side: const BorderSide(color: Color(0xFFCCCCCC)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      child: Text(L10n.of(context).skGameAlwaysReject, style: const TextStyle(fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        game.respondCardViewRequest(spectatorId, true);
                        game.setAutoAcceptCardView(true);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF4CAF50),
                        side: const BorderSide(color: Color(0xFF4CAF50)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      child: Text(L10n.of(context).skGameAlwaysAccept, style: const TextStyle(fontSize: 13)),
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

  Widget _buildChatPanel(GameService game) {
    if (game.chatMessages.length != _lastChatMessageCount) {
      _lastChatMessageCount = game.chatMessages.length;
      _readChatCount = game.chatMessages.length;
      _scrollChatToBottom();
    }

    final media = MediaQuery.of(context);
    final keyboardHeight = media.viewInsets.bottom;
    final topInset = media.padding.top;
    final availableWidth = (media.size.width - 16).clamp(220.0, 320.0);
    final topOffset = topInset + 42;
    final bottomOffset = 8 + keyboardHeight;
    final maxHeight = media.size.height - topOffset - bottomOffset;
    final panelHeight = maxHeight.clamp(160.0, 350.0);

    return Positioned(
      right: 8,
      top: topOffset,
      width: availableWidth,
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
                      L10n.of(context).skGameChat,
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
                    final isBlocked = sender.isNotEmpty && game.isBlocked(sender);

                    if (isBlocked) return const SizedBox.shrink();
                    return _buildChatBubble(sender, message, isMe, game);
                  },
                ),
              ),
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
                          hintText: L10n.of(context).skGameMessageHint,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12),
                        ),
                        style: const TextStyle(fontSize: 14),
                        onSubmitted: (_) => _sendChatMessage(game),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _sendChatMessage(game),
                      icon: const Icon(Icons.send, color: Color(0xFF64B5F6)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
                const Icon(Icons.visibility, size: 16, color: Color(0xFF5A4038)),
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
                  child: const Icon(Icons.close, size: 18, color: Color(0xFF999999)),
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
                      const Icon(Icons.person, size: 16, color: Color(0xFF888888)),
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
                          child: const Icon(Icons.close, size: 14, color: Color(0xFFE53935)),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildChatBubble(String sender, String message, bool isMe, GameService game) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: isMe || sender.isEmpty ? null : () => _showUserActionDialog(sender, game),
        child: Row(
          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe && sender.isNotEmpty) ...[
              CircleAvatar(
                radius: 14,
                backgroundColor: const Color(0xFFE0E0E0),
                child: Text(
                  sender[0],
                  style: const TextStyle(fontSize: 12, color: Color(0xFF5A4038)),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isMe && sender.isNotEmpty)
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
                  color: isBlocked ? const Color(0xFF4CAF50) : const Color(0xFFE53935),
                ),
                title: Text(isBlocked ? L10n.of(context).skGameUnblock : L10n.of(context).skGameBlock),
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
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: const Color(0xFFF8F4F1),
          titlePadding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
          contentPadding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
          title: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE8DDD8)),
            ),
            child: Text(
              L10n.of(context).skGameScoreHistory,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF3E312A),
              ),
            ),
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE8DDD8)),
                  ),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: state.players.map((p) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: p.position == 'self'
                              ? const Color(0xFFEAF2FF)
                              : const Color(0xFFF7F1EC),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${p.name} ${p.totalScore}',
                          style: const TextStyle(
                            color: Color(0xFF5A4038),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 360,
                  child: SingleChildScrollView(
                    child: Column(
                      children: state.scoreHistory.reversed.map((entry) {
                        final scores = entry['scores'] as Map<String, dynamic>? ?? {};
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE8DDD8)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Round ${entry['round']}',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF3E312A),
                                ),
                              ),
                              const SizedBox(height: 10),
                              ...state.players.map((p) {
                                final pScore = scores[p.id] as Map<String, dynamic>?;
                                if (pScore == null) return const SizedBox.shrink();
                                final roundScore = pScore['roundScore'] ?? 0;
                                final bonus = pScore['bonus'] ?? 0;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          p.name,
                                          style: const TextStyle(
                                            color: Color(0xFF5A4038),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '${pScore['bid']}/${pScore['tricks']}',
                                        style: const TextStyle(color: Color(0xFF8A7A72)),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        bonus > 0 ? '+$bonus' : '-',
                                        style: TextStyle(
                                          color: bonus > 0 ? const Color(0xFF4CAF50) : const Color(0xFF8A7A72),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        roundScore >= 0 ? '+$roundScore' : '$roundScore',
                                        style: TextStyle(
                                          color: roundScore >= 0 ? const Color(0xFF355D89) : const Color(0xFFE53935),
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
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
                state.phase == 'bidding' ? L10n.of(context).skGameBiddingPhase : L10n.of(context).skGamePlayCard,
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
        .firstWhere((p) => p.id == state.lastTrickWinner, orElse: () => state.players.first)
        .name;
    final bonus = state.lastTrickBonus;

    // Parse bonusDetail to detect expansion effects
    final detail = state.lastTrickBonusDetail;
    String? voidReason;
    String? whaleNullifyLabel;
    int lootBonusPoints = 0;
    bool isKraken = false;
    for (final entry in detail) {
      final type = entry['type'];
      if (type == 'kraken_void') {
        voidReason = L10n.of(context).skGameKrakenActivated;
        isKraken = true;
      } else if (type == 'white_whale_void') {
        voidReason = L10n.of(context).skGameWhiteWhaleActivated;
      } else if (type == 'white_whale_nullify') {
        whaleNullifyLabel = L10n.of(context).skGameWhiteWhaleNullify;
      } else if (type == 'loot_bonus') {
        lootBonusPoints = (entry['winnerPoints'] as num?)?.toInt() ?? 0;
      }
    }
    final isVoided = state.lastTrickVoided;

    // Voided trick → distinct banner
    if (isVoided && state.phase == 'trick_end') {
      final Color bgColor = isKraken
          ? const Color(0xFF2B1E3F).withValues(alpha: 0.92)
          : const Color(0xFF3A6B8F).withValues(alpha: 0.92);
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFFFD54F).withValues(alpha: 0.6),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                L10n.of(context).skGameTrickVoided,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFFFD54F),
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
              const SizedBox(height: 4),
              Text(
                L10n.of(context).skGameLeadPlayer(winnerName),
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
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
              state.phase == 'trick_end' ? L10n.of(context).skGameTrickWinner(winnerName) : L10n.of(context).skGameCheckingCards,
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
                    ? L10n.of(context).skGameBonusWithLoot(bonus, lootBonusPoints)
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
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
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
          if (game.myTimeoutCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _buildTimeoutResetChip(game),
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
          _buildHandRows(state.myCards, interactive: false, compact: isLandscape),
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
                  color: selected ? const Color(0xFF355D89) : const Color(0xFF5A4038),
                  fontWeight: FontWeight.bold,
                  fontSize: isLandscape ? 14 : 16,
                ),
                visualDensity: isLandscape ? VisualDensity.compact : VisualDensity.standard,
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                _selectedBid != null ? L10n.of(context).skGameBidSubmit(_selectedBid!) : L10n.of(context).skGameSelectNumber,
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
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final selectedCard = _selectedCard;
    final isSelectedLegal = selectedCard != null && state.legalCards.contains(selectedCard);

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
          if (game.myTimeoutCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 8, right: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _buildTimeoutResetChip(game),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
              legalCards: state.legalCards,
              isMyTurn: state.isMyTurn,
              compact: isLandscape,
            ),
          ),
        ],
      ),
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
    Widget buildCardWidget(String cardId, double cardWidth, double cardHeight, double padding) {
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
                            color: const Color(0xFF355D89).withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      )
                    : null,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: padding),
                  child: _buildCard(cardId, size: cardHeight, highlighted: isSelected),
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
        final perRow = compact ? cards.length : (cards.length <= 6 ? cards.length : (cards.length / 2).ceil());
        final dense = compact || cards.length >= 8;
        final cardPadding = dense ? (compact ? 1.0 : 1.5) : 3.0;
        final totalPadding = perRow * cardPadding * 2;
        final maxCardWidth = interactive
            ? (compact ? 42.0 : 55.0)
            : (compact ? 34.0 : 46.0);
        // Fill available width, only cap at max
        final cardWidth =
            ((availableWidth - totalPadding) / perRow).clamp(0.0, maxCardWidth);
        final cardHeight = (cardWidth * 1.4).clamp(
          interactive ? (compact ? 42.0 : 52.0) : (compact ? 34.0 : 42.0),
          interactive ? (compact ? 60.0 : 77.0) : (compact ? 50.0 : 64.0),
        );

        List<Widget> rowWidgets(List<String> row) {
          return row
              .map((cardId) => buildCardWidget(cardId, cardWidth, cardHeight, cardPadding))
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
        backgroundColor: const Color(0xFFF8F4F1),
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
                          border: Border.all(color: const Color(0xFFD8CCC5), width: 1.5),
                        ),
                        child: Column(
                          children: [
                            _buildCard('sk_escape', size: 80, highlighted: false),
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
                          border: Border.all(color: const Color(0xFFD24B4B), width: 1.5),
                        ),
                        child: Column(
                          children: [
                            _buildCard('sk_pirate', size: 80, highlighted: false),
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
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
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
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: isLandscape ? 5 : 6),
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
          // Table header
          Row(
            children: [
              const Expanded(flex: 3, child: Text('', style: TextStyle(fontSize: 11))),
              Expanded(
                flex: 2,
                child: Text(L10n.of(context).skGameBidTricks, textAlign: TextAlign.center,
                    style: TextStyle(fontSize: isLandscape ? 9 : 10, color: const Color(0xFF8A7A72), fontWeight: FontWeight.bold)),
              ),
              SizedBox(width: isLandscape ? 34 : 40, child: Text(L10n.of(context).skGameBonusHeader, textAlign: TextAlign.center,
                  style: TextStyle(fontSize: isLandscape ? 9 : 10, color: const Color(0xFF8A7A72), fontWeight: FontWeight.bold))),
              SizedBox(width: isLandscape ? 44 : 50, child: Text(L10n.of(context).skGameScoreHeader, textAlign: TextAlign.end,
                  style: TextStyle(fontSize: isLandscape ? 9 : 10, color: const Color(0xFF8A7A72), fontWeight: FontWeight.bold))),
            ],
          ),
          const Divider(height: 8),
          if (scores != null)
            ...state.players.map((p) {
              final pScore = scores[p.id] as Map<String, dynamic>?;
              if (pScore == null) return const SizedBox.shrink();
              final bid = pScore['bid'] ?? 0;
              final tricks = pScore['tricks'] ?? 0;
              final bonus = pScore['bonus'] ?? 0;
              final roundScore = pScore['roundScore'] ?? 0;
              final success = bid == 0 ? tricks == 0 : tricks == bid;
              return Container(
                padding: EdgeInsets.symmetric(vertical: isLandscape ? 3 : 4),
                decoration: BoxDecoration(
                  color: p.position == 'self'
                      ? const Color(0xFFF7F1EC)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        p.name,
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
                      width: isLandscape ? 34 : 40,
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
                      width: isLandscape ? 44 : 50,
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
                  ],
                ),
              );
            }),
          SizedBox(height: isLandscape ? 6 : 8),
          Text(
            L10n.of(context).skGameNextRoundPreparing,
            style: TextStyle(color: const Color(0xFF8A7A72), fontSize: isLandscape ? 11 : 12),
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
                        fontWeight: isWinner ? FontWeight.bold : FontWeight.normal,
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
                  ? L10n.of(context).skGameAutoReturnCountdown(_gameEndCountdown)
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
  void _showPlayerProfileDialog(String nickname, GameService game, {bool isBot = false}) {
    game.requestProfile(nickname);

    showDialog(
      context: context,
      builder: (ctx) {
        String selectedGame = 'skull_king';
        return StatefulBuilder(
          builder: (ctx, setDialogState) => Consumer<GameService>(
          builder: (ctx, game, _) {
            final profile = game.profileFor(nickname);
            final isLoading = profile == null || profile['nickname'] != nickname;
            final isBlockedUser = game.isBlocked(nickname);

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              backgroundColor: const Color(0xFFF8F4F1),
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
                                  SnackBar(content: Text(L10n.of(context).skGameFriendRequestSent)),
                                );
                              },
                            ),
                          _buildProfileIconButton(
                            icon: isBlockedUser ? Icons.block : Icons.shield_outlined,
                            color: isBlockedUser
                                ? const Color(0xFF64B5F6)
                                : const Color(0xFFFF8A65),
                            tooltip: isBlockedUser ? L10n.of(context).skGameUnblockUser : L10n.of(context).skGameBlockUser,
                            onTap: () {
                              if (isBlockedUser) {
                                game.unblockUserAction(nickname);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(L10n.of(context).skGameUserUnblocked)),
                                );
                              } else {
                                game.blockUserAction(nickname);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(L10n.of(context).skGameUserBlocked)),
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
                      constraints: const BoxConstraints(maxWidth: 420, maxHeight: 400),
                      child: SingleChildScrollView(
                        child: _buildProfileContent(
                          profile,
                          selectedGame: selectedGame,
                          onGameChanged: (g) => setDialogState(() => selectedGame = g),
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

  Widget _buildProfileContent(Map<String, dynamic> data, {
    required String selectedGame,
    required ValueChanged<String> onGameChanged,
  }) {
    final profile = data['profile'] as Map<String, dynamic>?;
    if (profile == null) {
      return Text(L10n.of(context).skGameProfileNotFound,
          style: const TextStyle(color: Color(0xFF8A7A72)));
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
                    Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
                    const SizedBox(height: 12),
                    ListTile(
                      leading: const Text('🃏', style: TextStyle(fontSize: 20)),
                      title: Text(l10n.lobbyTichu),
                      trailing: selectedGame == 'tichu' ? const Icon(Icons.check, color: Color(0xFF7E57C2)) : null,
                      onTap: () { Navigator.pop(bCtx); onGameChanged('tichu'); },
                    ),
                    ListTile(
                      leading: const Text('⚓', style: TextStyle(fontSize: 20)),
                      title: Text(l10n.lobbySkullKing),
                      trailing: selectedGame == 'skull_king' ? const Icon(Icons.check, color: Color(0xFF2D2D3D)) : null,
                      onTap: () { Navigator.pop(bCtx); onGameChanged('skull_king'); },
                    ),
                    ListTile(
                      leading: const Text('❤️', style: TextStyle(fontSize: 20)),
                      title: Text(l10n.lobbyLoveLetter),
                      trailing: selectedGame == 'love_letter' ? const Icon(Icons.check, color: Color(0xFFE91E63)) : null,
                      onTap: () { Navigator.pop(bCtx); onGameChanged('love_letter'); },
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
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: gameFgColor),
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
          Builder(builder: (_) {
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
          })
        else
          Builder(builder: (_) {
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
          }),
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
              _buildStatChip(L10n.of(context).skGameStatRecord, L10n.of(context).skGameRecordFormat(games, wins, losses)),
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
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF8A7A72),
            ),
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

  Widget _buildCard(String cardId, {double size = 60, bool highlighted = false}) {
    final info = _parseCardId(cardId);
    final w = size * 0.7;
    final h = size;
    final radius = BorderRadius.circular(6);

    final border = Border.all(
      color: highlighted ? const Color(0xFF355D89) : Colors.black.withValues(alpha: 0.15),
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
              errorBuilder: (_, e, s) => _buildSpecialFallback(fallbackLabel, size),
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
      Rect.fromLTWH(size.width * 0.2, size.height * 0.1, size.width * 0.6, size.height * 0.55),
      paint,
    );
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.32, size.height * 0.62, size.width * 0.36, size.height * 0.18),
      paint,
    );

    final cutout = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.fill;
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawOval(
      Rect.fromLTWH(size.width * 0.2, size.height * 0.1, size.width * 0.6, size.height * 0.55),
      paint,
    );
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.32, size.height * 0.62, size.width * 0.36, size.height * 0.18),
      paint,
    );
    canvas.drawCircle(Offset(size.width * 0.38, size.height * 0.36), size.width * 0.08, cutout);
    canvas.drawCircle(Offset(size.width * 0.62, size.height * 0.36), size.width * 0.08, cutout);
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
