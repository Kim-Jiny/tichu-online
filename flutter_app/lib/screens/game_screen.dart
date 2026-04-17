import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/game_service.dart';
import '../services/network_service.dart';
import '../services/session_service.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../widgets/playing_card.dart';
import '../widgets/connection_overlay.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n_helpers.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  // Responsive scale factor (updated every build)
  double _s = 1.0;  // scale factor based on screen width
  int _maxNameLen = 4;

  final Set<String> _selectedCards = {};

  // 카드 교환용 상태
  final Map<String, String> _exchangeAssignments = {}; // position -> cardId
  final Map<String, String> _exchangeGiven = {}; // position -> cardId
  bool _exchangeSummaryShown = false;
  String _prevPhase = ''; // track phase transitions
  bool _exchangeSubmitted = false;

  // 채팅
  bool _chatOpen = false;
  bool _viewersOpen = false;
  bool _soundPanelOpen = false;
  bool _moreOpen = false;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  int _lastChatMessageCount = 0;

  // 턴 타이머
  Timer? _countdownTimer;
  int _remainingSeconds = 0;
  int _lastTickSoundSecond = 999;
  bool _wasDisconnected = false;
  bool _birdCallDialogOpen = false;
  bool _waitingForRoomRecovery = false;
  GameService? _gameService;
  NetworkService? _networkService; // C6: Cache for safe dispose
  bool _profileRequested = false; // C8: Prevent requestProfile loop
  int _lastSeenMessageCount = -1; // -1 = not yet initialized

  @override
  void initState() {
    super.initState();
    // 로그인 후 차단 목록 요청
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
    // Clear stale UI state from previous connection
    _selectedCards.clear();
    _exchangeAssignments.clear();
    _exchangeGiven.clear();
    _exchangeSubmitted = false;
    await context.read<GameService>().checkRoomAndWait();
    if (!mounted) return;
    setState(() {
      _waitingForRoomRecovery = false;
    });
  }

  Widget _buildRecoveryLoading({
    required String title,
    String? subtitle,
    Color spinnerColor = Colors.white,
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
            CircularProgressIndicator(color: spinnerColor),
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

  @override
  void dispose() {
    // C6: Use cached reference instead of context.read in dispose
    _networkService?.removeListener(_onNetworkChanged);
    _chatController.dispose();
    _chatScrollController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _updateCountdown() {
    if (!mounted) return;
    final state = _gameService?.gameState ?? context.read<GameService>().gameState;
    if (state == null || state.turnDeadline == null) {
      if (_remainingSeconds != 0) {
        setState(() => _remainingSeconds = 0);
      }
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final remaining = ((state.turnDeadline! - now) / 1000).ceil().clamp(0, 999);
    if (remaining != _remainingSeconds) {
      setState(() => _remainingSeconds = remaining);
      if (state.isMyTurn &&
          remaining <= 3 &&
          remaining > 0 &&
          remaining != _lastTickSoundSecond) {
        _lastTickSoundSecond = remaining;
        context.read<GameService>().playCountdownTick();
      }
    }
  }

  void _toggleCard(String cardId, {bool singleSelect = false}) {
    setState(() {
      if (_selectedCards.contains(cardId)) {
        _selectedCards.remove(cardId);
      } else {
        if (singleSelect) {
          _selectedCards.clear();
        }
        _selectedCards.add(cardId);
      }
    });
  }

  void _playCards() {
    if (_selectedCards.isEmpty) return;

    // Bird 포함 시 콜 선택 먼저
    if (_selectedCards.contains('special_bird')) {
      _showBirdCallDialog();
      return;
    }

    context.read<GameService>().playCards(_selectedCards.toList());
    setState(() => _selectedCards.clear());
  }

  bool _isBombCombo(List<String> cards) {
    // Four of a kind: 4 non-special cards with same rank
    if (cards.length == 4) {
      if (cards.any((c) => c.startsWith('special_'))) return false;
      final ranks = cards.map((c) => c.split('_')[1]).toSet();
      return ranks.length == 1;
    }
    // Straight flush: 5+ same-suit consecutive cards (no specials)
    if (cards.length >= 5) {
      if (cards.any((c) => c.startsWith('special_'))) return false;
      final suits = cards.map((c) => c.split('_')[0]).toSet();
      if (suits.length != 1) return false;
      const rankValues = {
        '2': 2, '3': 3, '4': 4, '5': 5, '6': 6, '7': 7, '8': 8,
        '9': 9, '10': 10, 'J': 11, 'Q': 12, 'K': 13, 'A': 14,
      };
      final values = cards.map((c) => rankValues[c.split('_')[1]] ?? 0).toList()..sort();
      for (int i = 1; i < values.length; i++) {
        if (values[i] != values[i - 1] + 1) return false;
      }
      return true;
    }
    return false;
  }

  void _showBirdCallDialog() {
    _birdCallDialogOpen = true;
    final lowRanks = ['2', '3', '4', '5', '6', '7', '8'];
    final highRanks = ['9', '10', 'J', 'Q', 'K', 'A'];
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          title: Row(
            children: [
              const Text('🐦', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(
                L10n.of(context).gameSparrowCall,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF3E312A),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F1EC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE7DBD4)),
                  ),
                  child: Text(
                    L10n.of(context).gameSelectNumberToCall,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6A5A52),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _buildBirdCallRankRow(ctx, lowRanks),
                const SizedBox(height: 8),
                _buildBirdCallRankRow(ctx, highRanks),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      _birdCallDialogOpen = false;
                      Navigator.pop(ctx);
                      context.read<GameService>().playCards(
                        _selectedCards.toList(),
                        callRank: 'none',
                      );
                      setState(() => _selectedCards.clear());
                    },
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      side: const BorderSide(color: Color(0xFFD8CCC5)),
                      foregroundColor: const Color(0xFF6A5A52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                    label: Text(L10n.of(context).gameNoCall),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: TextButton(
                    onPressed: () {
                      _birdCallDialogOpen = false;
                      Navigator.pop(ctx);
                      setState(() => _selectedCards.clear());
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF6A5A52),
                    ),
                    child: Text(L10n.of(context).gameCancelPickAnother),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBirdCallRankRow(BuildContext ctx, List<String> ranks) {
    return Row(
      children: ranks.map((rank) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: FilledButton(
              onPressed: () {
                _birdCallDialogOpen = false;
                Navigator.pop(ctx);
                context.read<GameService>().playCards(
                  _selectedCards.toList(),
                  callRank: rank,
                );
                setState(() => _selectedCards.clear());
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE6F1FF),
                foregroundColor: const Color(0xFF355D89),
                minimumSize: const Size(0, 42),
                padding: const EdgeInsets.symmetric(horizontal: 0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Text(
                rank,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF355D89),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  void _passTurn() {
    context.read<GameService>().passTurn();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final isLandscape = mediaQuery.orientation == Orientation.landscape;
    final shortestSide = screenSize.shortestSide;
    _s = (shortestSide / 400).clamp(0.72, 1.0);
    _maxNameLen = screenSize.width < 370 ? 3 : (isLandscape ? 6 : 4);
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
            bottom: !isLandscape,
              child: Consumer<GameService>(
              builder: (context, game, _) {
                if (session.isRestoring || _waitingForRoomRecovery) {
                  final l10n = L10n.of(context);
                  return _buildRecoveryLoading(
                    title: session.isRestoring ? l10n.gameRestoringGame : l10n.gameCheckingState,
                    subtitle: session.isRestoring
                        ? localizeRestorePhase(session, l10n)
                        : l10n.gameRecheckingRoomState,
                  );
                }

                final state = game.gameState;
                if (state == null) {
                  if (game.hasRoom) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        _recoverRoomState();
                      }
                    });
                    return _buildRecoveryLoading(
                      title: L10n.of(context).gameReloadingRoom,
                      subtitle: L10n.of(context).gameWaitForRestore,
                    );
                  }

                  return _buildRecoveryLoading(
                    title: L10n.of(context).gamePreparingScreen,
                    subtitle: L10n.of(context).gameAdjustingScreen,
                  );
                }

                final destination = game.currentDestination;
                if (destination != AppDestination.game) {
                  return _buildRecoveryLoading(
                    title: L10n.of(context).gameTransitioningScreen,
                    subtitle: L10n.of(context).gameRecheckingDestination,
                  );
                }

                _waitingForRoomRecovery = false;

              // Bug #1: Clear exchange assignments when phase leaves card_exchange
              if (state.phase != 'card_exchange') {
                if (_exchangeAssignments.isNotEmpty || _exchangeSubmitted) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    setState(() {
                      _exchangeAssignments.clear();
                      _selectedCards.clear();
                      _exchangeSubmitted = false;
                    });
                  });
                }
              }

              // Track phase transitions for exchange summary
              if (state.phase == 'card_exchange' && !state.exchangeDone) {
                _exchangeSummaryShown = false;
              }
              // Only show exchange summary on card_exchange → playing transition
              if (_prevPhase == 'card_exchange' && state.phase != 'card_exchange') {
                _maybeShowExchangeSummary(state);
              }
              _prevPhase = state.phase;

              return Stack(
                children: [
                  if (_tichuOverlayColor(state) != null)
                    Positioned.fill(
                      child: Container(
                        color: _tichuOverlayColor(state),
                      ),
                    ),
                  isLandscape
                      ? _buildLandscapeGameLayout(state, game)
                      : _buildPortraitGameLayout(state, game),

                  // Dialogs/Panels
                  if (state.phase == 'large_tichu_phase' &&
                      !state.largeTichuResponded)
                    _buildLargeTichuDialog(game),


                  if (state.dragonPending) _buildDragonDialog(state, game),

                  if (state.needsToCallRank && !_birdCallDialogOpen) _buildCallRankDialog(game),

                  if (state.phase == 'round_end' || state.phase == 'game_end')
                    _buildRoundEndDialog(state, game),

                  // Timeout banner
                  if (game.timeoutPlayerName != null)
                    _buildTimeoutBanner(game.timeoutPlayerName!),

                  // Desertion banner
                  if (game.desertedPlayerName != null)
                    _buildDesertionBanner(game.desertedPlayerName!, game.desertedReason ?? 'leave'),

                  // Error message banner
                  if (game.errorMessage != null)
                    _buildErrorBanner(game.errorMessage!),

                  // Spectator card view requests
                  if (game.hasIncomingCardViewRequests)
                    _buildCardViewRequestPopup(game),

                  // Viewers panel popup
                  if (_viewersOpen)
                    _buildViewersPanel(game, topOffset: _moreOpen ? 150 : 66),

                  // Sound panel
                  if (_soundPanelOpen)
                    _buildSoundPanel(game),

                  // More menu
                  if (_moreOpen)
                    _buildMoreMenu(game),

                  // Chat panel
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

  Widget _buildPortraitGameLayout(GameStateData state, GameService game) {
    return Column(
      children: [
        _buildTopBar(state, game),
        _buildPartnerArea(state, game),
        Expanded(
          child: _buildMiddleArea(state, game),
        ),
        if (state.phase == 'card_exchange' && !state.exchangeDone)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildExchangeInline(state, game),
          ),
        if (game.dragonGivenMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildDragonGivenInline(game.dragonGivenMessage!),
          ),
        if (_canShowSmallTichu(state))
          _buildSmallTichuInline(game),
        _buildBottomArea(state, game),
      ],
    );
  }

  Widget _buildLandscapeGameLayout(GameStateData state, GameService game) {
    return Column(
      children: [
        _buildTopBar(state, game),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    children: [
                      _buildPartnerArea(state, game),
                      Expanded(
                        child: _buildMiddleArea(state, game),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 6,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: constraints.maxHeight),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (state.phase == 'card_exchange' && !state.exchangeDone)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _buildExchangeInline(state, game),
                                ),
                              if (game.dragonGivenMessage != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _buildDragonGivenInline(
                                    game.dragonGivenMessage!,
                                  ),
                                ),
                              if (_canShowSmallTichu(state))
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _buildSmallTichuInline(game),
                                ),
                              _buildBottomArea(state, game),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  bool _canShowSmallTichu(GameStateData state) {
    return state.canDeclareSmallTichu &&
        state.phase != 'card_exchange' &&
        !state.players.any(
          (p) => p.position == 'self' && p.hasLargeTichu,
        );
  }

  Widget _buildMenuButton(GameService game) {
    return GestureDetector(
      onTap: () => _showLeaveGameDialog(game),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.8),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
            ),
          ],
        ),
        child: const Icon(
          Icons.logout,
          color: Color(0xFFE53935),
          size: 20,
        ),
      ),
    );
  }

  Widget _buildChatButton(GameService game) {
    final totalMessages = game.chatMessages.where((m) =>
      !game.isBlocked(m['sender'] as String? ?? '')
    ).length;

    // Initialize on first build so existing messages don't show as unread
    if (_lastSeenMessageCount < 0) {
      _lastSeenMessageCount = totalMessages;
    }
    // Update seen count when chat is open
    if (_chatOpen) {
      _lastSeenMessageCount = totalMessages;
    }
    final unreadCount = totalMessages - _lastSeenMessageCount;

    return GestureDetector(
      onTap: () => setState(() {
        _chatOpen = !_chatOpen;
        if (_chatOpen) {
          _lastSeenMessageCount = totalMessages;
          _scrollChatToBottom();
        }
      }),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _chatOpen
                  ? const Color(0xFF64B5F6)
                  : Colors.white.withValues(alpha: 0.8),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                ),
              ],
            ),
            child: Icon(
              Icons.chat_bubble_outline,
              color: _chatOpen ? Colors.white : const Color(0xFF5A4038),
              size: 20,
            ),
          ),
          if (unreadCount > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Color(0xFFE53935),
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                child: Text(
                  unreadCount > 9 ? '9+' : '$unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
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
              : Colors.white.withValues(alpha: 0.8),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
            ),
          ],
        ),
        child: Icon(
          hasMuted ? Icons.volume_off : Icons.volume_up,
          color: _soundPanelOpen ? Colors.white : const Color(0xFF5A4038),
          size: 20,
        ),
      ),
    );
  }

  Widget _buildMoreButton(GameService game) {
    return GestureDetector(
      onTap: () => setState(() {
        _moreOpen = !_moreOpen;
        if (!_moreOpen) return;
        _soundPanelOpen = false;
        _viewersOpen = false;
      }),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _moreOpen
              ? const Color(0xFF81C784)
              : Colors.white.withValues(alpha: 0.8),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
            ),
          ],
        ),
        child: Icon(
          Icons.more_horiz,
          color: _moreOpen ? Colors.white : const Color(0xFF5A4038),
          size: 20,
        ),
      ),
    );
  }

  Widget _buildMoreMenu(GameService game) {
    final hasViewers = game.cardViewers.isNotEmpty;
    return Positioned(
      top: 56,
      right: 10,
      child: AnimatedOpacity(
        opacity: _moreOpen ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        child: AnimatedScale(
          scale: _moreOpen ? 1 : 0.95,
          duration: const Duration(milliseconds: 160),
          child: Container(
            width: hasViewers ? 150 : 110,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                if (hasViewers) _buildViewersButton(game),
                _buildSoundButton(game),
                _buildMenuButton(game),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSoundPanel(GameService game) {
    return Positioned(
      top: _moreOpen ? 108 : 56,
      right: 10,
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
              L10n.of(context).gameSoundEffects,
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

  Widget _buildChatPanel(GameService game) {
    if (game.chatMessages.length != _lastChatMessageCount) {
      _lastChatMessageCount = game.chatMessages.length;
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
                    L10n.of(context).gameChat,
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

                  return _buildChatBubble(sender, message, isMe, game);
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
                        hintText: L10n.of(context).gameMessageHint,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
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

  Widget _buildChatBubble(String sender, String message, bool isMe, GameService game) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: isMe ? null : () => _showUserActionDialog(sender, game),
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

  void _showPlayerProfileDialog(String nickname, GameService game, {bool isBot = false}) {
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
                      if (!isBot) ...[
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

  Widget _buildMannerLeaveRow({required int totalGames, required int reportCount, required int leaveCount}) {
    final manner = _calcMannerScore(totalGames, leaveCount, reportCount);
    final color = _mannerColor(manner);
    final icon = _mannerIcon(manner);
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0D8D4)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 6),
                Text(
                  '${L10n.of(context).rankingMannerScore} $manner',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0D8D4)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFE57373), size: 16),
                const SizedBox(width: 6),
                Text(
                  L10n.of(context).gameDesertions(leaveCount),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF9A6A6A),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showRecentMatchesDialog(
    List<dynamic> recentMatches,
    String profileNickname,
  ) {
    showDialog(
      context: context,
      builder: (ctx) {
        final media = MediaQuery.of(ctx).size;
        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
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
            child: Row(
              children: [
                const Icon(Icons.history, color: Color(0xFF6A5A52)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        L10n.of(context).gameRecentMatchesTitle,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF3E312A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        L10n.of(context).gameRecentMatchesDesc(recentMatches.length),
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
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: media.width > 700 ? 520 : media.width - 40,
              maxHeight: media.height * 0.72,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: recentMatches.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, index) =>
                  _buildMatchRow(recentMatches[index], profileNickname),
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

  Widget _buildRecentMatches(
    List<dynamic> recentMatches,
    String profileNickname,
  ) {
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
          Row(
            children: [
              Text(
                L10n.of(context).gameRecentMatchesThree,
                style: const TextStyle(fontSize: 12, color: Color(0xFF8A8A8A)),
              ),
              const Spacer(),
              if (recentMatches.length > 3)
                TextButton(
                  onPressed: () =>
                      _showRecentMatchesDialog(recentMatches, profileNickname),
                  child: Text(L10n.of(context).gameSeeMore),
                ),
            ],
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

  void _showUserActionDialog(String nickname, GameService game) {
    final isBlocked = game.isBlocked(nickname);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              nickname,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF5A4038),
              ),
            ),
            const SizedBox(height: 20),
            _buildActionButton(
              icon: Icons.person_search,
              label: L10n.of(context).gameViewProfile,
              color: const Color(0xFF64B5F6),
              onTap: () {
                Navigator.pop(context);
                _showPlayerProfileDialog(nickname, game);
              },
            ),
            const SizedBox(height: 10),
            _buildActionButton(
              icon: Icons.person_add,
              label: L10n.of(context).gameAddFriend,
              color: const Color(0xFF81C784),
              onTap: () {
                Navigator.pop(context);
                game.addFriendAction(nickname);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(L10n.of(context).gameFriendRequestSent)),
                );
              },
            ),
            const SizedBox(height: 10),
            _buildActionButton(
              icon: isBlocked ? Icons.check_circle : Icons.block,
              label: isBlocked ? L10n.of(context).gameUnblock : L10n.of(context).gameBlock,
              color: isBlocked ? const Color(0xFF64B5F6) : const Color(0xFFFF8A65),
              onTap: () {
                Navigator.pop(context);
                if (isBlocked) {
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
            const SizedBox(height: 10),
            _buildActionButton(
              icon: Icons.flag,
              label: L10n.of(context).gameReport,
              color: const Color(0xFFE57373),
              onTap: () {
                Navigator.pop(context);
                _showReportDialog(nickname, game);
              },
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(L10n.of(context).gameCancel),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
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
                        // C5: Add timeout to remove listener if server never responds
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

  void _showLeaveGameDialog(GameService game) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.of(context).gameLeaveTitle),
        content: Text(L10n.of(context).gameLeaveConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(L10n.of(context).gameCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              game.leaveGame();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(L10n.of(context).gameLeave),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    final isCallError = message.contains('Call');
    final displayMessage = isCallError
        ? L10n.of(context).gameCallError
        : localizeServiceMessage(message, L10n.of(context));

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
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFCC4444)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                displayMessage,
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

  Widget _buildTimeoutBanner(String playerName) {
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
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.timer_off, color: Color(0xFFE65100)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                L10n.of(context).gameTimeout(playerName),
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

  Widget _buildDesertionBanner(String playerName, String reason) {
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
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.person_off, color: Color(0xFFCC4444)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                reason == 'timeout'
                    ? L10n.of(context).gameDesertionTimeout(playerName)
                    : L10n.of(context).gameDesertionLeave(playerName),
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
    if (request == null) {
      return const SizedBox.shrink();
    }
    final spectatorNickname = request['spectatorNickname'] ?? L10n.of(context).gameSpectator;
    final spectatorId = request['spectatorId'] ?? '';

    return Positioned(
      top: 60,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
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
                    L10n.of(context).gameCardViewRequest(spectatorNickname),
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
                    child: Text(L10n.of(context).gameReject),
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
                    child: Text(L10n.of(context).gameAllow),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      game.rejectAllCardViewRequests();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF999999),
                      side: const BorderSide(color: Color(0xFFCCCCCC)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: Text(L10n.of(context).gameAlwaysReject, style: const TextStyle(fontSize: 13)),
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
                    child: Text(L10n.of(context).gameAlwaysAllow, style: const TextStyle(fontSize: 13)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpectatorButton(GameService game) {
    final count = game.spectators.length;
    final hasViewers = game.cardViewers.isNotEmpty;
    return GestureDetector(
      onTap: () => _showSpectatorListDialog(game),
      onLongPress: hasViewers ? () => setState(() => _viewersOpen = !_viewersOpen) : null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                ),
              ],
            ),
            child: const Icon(
              Icons.people_alt,
              color: Color(0xFF5A4038),
              size: 20,
            ),
          ),
          if (hasViewers)
            Positioned(
              bottom: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: Color(0xFF81C784),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.visibility,
                  size: 10,
                  color: Colors.white,
                ),
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

  Widget _buildViewersButton(GameService game) {
    final count = game.cardViewers.length;
    return GestureDetector(
      onTap: () => setState(() => _viewersOpen = !_viewersOpen),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _viewersOpen
                  ? const Color(0xFF81C784)
                  : Colors.white.withValues(alpha: 0.8),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                ),
              ],
            ),
            child: Icon(
              Icons.visibility,
              color: _viewersOpen ? Colors.white : const Color(0xFF5A4038),
              size: 20,
            ),
          ),
          if (count > 0)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Color(0xFFE53935),
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
            Text(L10n.of(context).gameSpectatorList),
          ],
        ),
        content: spectators.isEmpty
            ? SizedBox(
                height: 60,
                child: Center(
                  child: Text(
                    L10n.of(context).gameNoSpectators,
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
                              L10n.of(context).gameAlwaysAllow,
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
                              L10n.of(context).gameAlwaysReject,
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
            child: Text(L10n.of(context).gameClose),
          ),
        ],
      ),
    );
  }

  Widget _buildViewersPanel(GameService game, {double topOffset = 48}) {
    return Positioned(
      top: topOffset,
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
                    L10n.of(context).gameViewingMyCards,
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
                L10n.of(context).gameNoViewers,
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

  Widget _buildPartnerArea(GameStateData state, GameService game) {
    final partner = _firstWhereOrNull(
      state.players,
      (p) => p.position == 'partner',
    );
    final isPartnerTurn = partner?.id == state.currentPlayer;

    return Container(
      padding: EdgeInsets.all(10 * _s),
      child: Column(
        children: [
          GestureDetector(
            onTap: partner != null ? () => _showPlayerProfileDialog(partner.name, game, isBot: partner.id.startsWith('bot_')) : null,
            child: _buildTurnName(
              name: partner?.name ?? L10n.of(context).gamePartner,
              isTurn: isPartnerTurn,
              badge: _tichuBadgeForPlayer(partner),
              exchangeDone: state.phase == 'card_exchange' && (partner?.hasExchanged ?? false),
              connected: partner?.connected ?? true,
              timeoutCount: partner?.timeoutCount ?? 0,
              teamLabel: _teamForPosition(state, 'partner'),
              isMyTeam: true,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            _getPlayerInfo(partner),
            style: TextStyle(
              fontSize: 11 * _s,
              color: const Color(0xFF8A7A72),
            ),
          ),
          const SizedBox(height: 6),
          // Card backs
          _buildOverlappedHand(
            count: partner?.cardCount ?? 0,
            cardWidth: 26 * _s,
            cardHeight: 36 * _s,
            overlap: 16 * _s,
            maxVisible: 14,
          ),
        ],
      ),
    );
  }

  Widget _buildMiddleArea(GameStateData state, GameService game) {
    final left = _firstWhereOrNull(state.players, (p) => p.position == 'left');
    final right = _firstWhereOrNull(state.players, (p) => p.position == 'right');
    final isLeftTurn = left?.id == state.currentPlayer;
    final isRightTurn = right?.id == state.currentPlayer;

    return Row(
      children: [
        // Left player
        SizedBox(
          width: 70 * _s,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: left != null ? () => _showPlayerProfileDialog(left.name, game, isBot: left.id.startsWith('bot_')) : null,
                child: _buildTurnName(
                  name: left?.name ?? L10n.of(context).gameLeftPlayer,
                  isTurn: isLeftTurn,
                  fontSize: 11,
                  badge: _tichuBadgeForPlayer(left),
                  exchangeDone: state.phase == 'card_exchange' && (left?.hasExchanged ?? false),
                  connected: left?.connected ?? true,
                  timeoutCount: left?.timeoutCount ?? 0,
                  teamLabel: _teamForPosition(state, 'left'),
                  isMyTeam: false,
                ),
              ),
              Text(
                _getPlayerInfo(left),
                style: TextStyle(fontSize: 9 * _s, color: const Color(0xFF8A7A72)),
              ),
              const SizedBox(height: 4),
              _buildOverlappedHandVertical(
                count: left?.cardCount ?? 0,
                cardWidth: 22 * _s,
                cardHeight: 30 * _s,
                overlap: 22 * _s,
                maxVisible: 14,
              ),
            ],
          ),
        ),

        // Center area
        Expanded(
          child: _buildCenterArea(state, game),
        ),

        // Right player
        SizedBox(
          width: 70 * _s,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: right != null ? () => _showPlayerProfileDialog(right.name, game, isBot: right.id.startsWith('bot_')) : null,
                child: _buildTurnName(
                  name: right?.name ?? L10n.of(context).gameRightPlayer,
                  isTurn: isRightTurn,
                  fontSize: 11,
                  badge: _tichuBadgeForPlayer(right),
                  exchangeDone: state.phase == 'card_exchange' && (right?.hasExchanged ?? false),
                  connected: right?.connected ?? true,
                  timeoutCount: right?.timeoutCount ?? 0,
                  teamLabel: _teamForPosition(state, 'right'),
                  isMyTeam: false,
                ),
              ),
              Text(
                _getPlayerInfo(right),
                style: TextStyle(fontSize: 9 * _s, color: const Color(0xFF8A7A72)),
              ),
              const SizedBox(height: 4),
              _buildOverlappedHandVertical(
                count: right?.cardCount ?? 0,
                cardWidth: 22 * _s,
                cardHeight: 30 * _s,
                overlap: 22 * _s,
                maxVisible: 14,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCenterArea(GameStateData state, GameService game) {
    return Center(
      child: Container(
        width: 220 * _s,
        padding: EdgeInsets.symmetric(horizontal: 8 * _s, vertical: 6 * _s),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Phase & Turn info
            Text(
              _getPhaseName(state.phase),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Color(0xFF5A4038),
              ),
              textAlign: TextAlign.center,
            ),
            if (state.phase == 'playing') ...[
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    state.isMyTurn ? L10n.of(context).gameMyTurn : L10n.of(context).gamePlayerTurn(_getCurrentPlayerName(state)),
                    style: TextStyle(
                      fontSize: 11,
                      color: state.isMyTurn
                          ? const Color(0xFFE6A800)
                          : const Color(0xFF8A7A72),
                      fontWeight:
                          state.isMyTurn ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ],

            // Call rank display
            if (state.callRank != null && state.callRank!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0x33FF4444),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFF4444), width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '🐦',
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      L10n.of(context).gameCall(state.callRank!),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFF4444),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 4),

            if (game.dogPlayActive)
              _buildDogPlayedBanner(game.dogPlayPlayerName),

            if (game.dogPlayActive) const SizedBox(height: 4),

            // Latest trick only
            if (state.currentTrick.isNotEmpty)
              _buildLatestTrick(state),

          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(GameStateData state, GameService game) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final currentPlayerName = _getCurrentPlayerName(state);
    final compactPlayerName = currentPlayerName.length > 4
        ? '${currentPlayerName.substring(0, 4)}…'
        : currentPlayerName;
    final l10n = L10n.of(context);
    final turnLabel = state.isMyTurn
        ? l10n.gameMyTurnShort
        : (isLandscape ? l10n.gamePlayerTurnShort(compactPlayerName) : l10n.gamePlayerWaiting(currentPlayerName));
    final timerFontSize = isLandscape ? 11.5 * _s : 13 * _s;
    final timerIconSize = isLandscape ? 12.5 * _s : 14 * _s;
    final timerPadding = isLandscape
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
        : const EdgeInsets.symmetric(horizontal: 10, vertical: 5);
    final timerBadge = _remainingSeconds > 0
        ? Container(
            padding: timerPadding,
            decoration: BoxDecoration(
              color: _remainingSeconds <= 10
                  ? const Color(0xFFFFE4E4)
                  : Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _remainingSeconds <= 10
                    ? const Color(0xFFFF6B6B)
                    : const Color(0xFFCCCCCC),
                width: _remainingSeconds <= 10 ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.schedule,
                  size: timerIconSize,
                  color: _remainingSeconds <= 10
                      ? const Color(0xFFCC4444)
                      : const Color(0xFF6A5A52),
                ),
                SizedBox(width: 5 * _s),
                Flexible(
                  child: Text(
                    l10n.gameTimerLabel(turnLabel, _remainingSeconds),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: timerFontSize,
                      fontWeight: FontWeight.bold,
                      color: _remainingSeconds <= 10
                          ? const Color(0xFFCC4444)
                          : const Color(0xFF5A4038),
                    ),
                  ),
                ),
              ],
            ),
          )
        : null;

    if (isLandscape) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  if (game.hasTopCardCounter && state.phase == 'playing')
                    Flexible(child: _buildTopCardCounter(state, compact: true)),
                  if (game.hasTopCardCounter &&
                      state.phase == 'playing' &&
                      timerBadge != null)
                    const SizedBox(width: 6),
                  if (timerBadge != null) Flexible(child: timerBadge),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Flexible(child: Align(alignment: Alignment.center, child: _buildScoreBar(state))),
            const SizedBox(width: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSpectatorButton(game),
                const SizedBox(width: 6),
                _buildChatButton(game),
                const SizedBox(width: 6),
                _buildMoreButton(game),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              _buildScoreBar(state),
              if (game.hasTopCardCounter && state.phase == 'playing')
                Align(
                  alignment: Alignment.centerLeft,
                  child: _buildTopCardCounter(state),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSpectatorButton(game),
                    const SizedBox(width: 6),
                    _buildChatButton(game),
                    const SizedBox(width: 6),
                    _buildMoreButton(game),
                  ],
                ),
              ),
            ],
          ),
          if (_remainingSeconds > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: timerBadge,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopCardCounter(GameStateData state, {bool compact = false}) {
    final aces = state.remainingAces;
    final kings = state.remainingKings;
    final dragon = state.remainingDragon > 0;
    final phoenix = state.remainingPhoenix > 0;
    final horizontal = compact ? 6.0 * _s : 8.0 * _s;
    final vertical = compact ? 3.0 * _s : 4.0 * _s;
    final spacing = compact ? 5.0 * _s : 8.0 * _s;
    final iconFont = compact ? 12.0 * _s : 13.0 * _s;
    final textFont = compact ? 12.0 * _s : 13.0 * _s;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: compact
            ? EdgeInsets.zero
            : EdgeInsets.only(bottom: 2 * _s),
        padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F4F0),
          borderRadius: BorderRadius.circular(8 * _s),
          border: Border.all(color: const Color(0xFFE6DCE8)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('A', style: TextStyle(fontSize: textFont, fontWeight: FontWeight.bold, color: const Color(0xFF5A4038))),
            Text(':$aces', style: TextStyle(fontSize: textFont, fontWeight: FontWeight.bold, color: const Color(0xFF8A7A6A))),
            SizedBox(width: spacing),
            Text('K', style: TextStyle(fontSize: textFont, fontWeight: FontWeight.bold, color: const Color(0xFF5A4038))),
            Text(':$kings', style: TextStyle(fontSize: textFont, fontWeight: FontWeight.bold, color: const Color(0xFF8A7A6A))),
            SizedBox(width: spacing),
            Text('\u{1F409}', style: TextStyle(fontSize: iconFont)),
            Text(dragon ? '\u25CB' : '\u2715', style: TextStyle(fontSize: 12 * _s, color: dragon ? const Color(0xFF4A90D9) : const Color(0xFFCCC0B8))),
            SizedBox(width: compact ? 4 * _s : 6 * _s),
            Text('\u{1F426}', style: TextStyle(fontSize: iconFont)),
            Text(phoenix ? '\u25CB' : '\u2715', style: TextStyle(fontSize: 12 * _s, color: phoenix ? const Color(0xFFD4A030) : const Color(0xFFCCC0B8))),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreBar(GameStateData state) {
    final teamA = state.totalScores['teamA'] ?? 0;
    final teamB = state.totalScores['teamB'] ?? 0;
    final myTeam = state.myTeam;
    final myScore = myTeam == 'A' ? teamA : teamB;
    final enemyScore = myTeam == 'A' ? teamB : teamA;
    final myLeading = myScore > enemyScore;
    final enemyLeading = enemyScore > myScore;
    const myColor = Color(0xFF4A90D9);
    const enemyColor = Color(0xFFD24B4B);

    return GestureDetector(
      onTap: () => _showScoreHistoryDialog(state),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12 * _s, vertical: 5 * _s),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F4F0),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE6DCE8)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              myTeam,
              style: TextStyle(
                fontSize: 10 * _s,
                fontWeight: FontWeight.bold,
                color: myLeading ? myColor : const Color(0xFF8A7A72),
              ),
            ),
            SizedBox(width: 3 * _s),
            Text(
              '$myScore',
              style: TextStyle(
                fontSize: 14 * _s,
                fontWeight: FontWeight.bold,
                color: myLeading ? myColor : const Color(0xFF5A4038),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 6 * _s),
              child: Text(
                ':',
                style: TextStyle(
                  fontSize: 14 * _s,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF8A7A72),
                ),
              ),
            ),
            Text(
              '$enemyScore',
              style: TextStyle(
                fontSize: 14 * _s,
                fontWeight: FontWeight.bold,
                color: enemyLeading ? enemyColor : const Color(0xFF5A4038),
              ),
            ),
            SizedBox(width: 3 * _s),
            Text(
              myTeam == 'A' ? 'B' : 'A',
              style: TextStyle(
                fontSize: 10 * _s,
                fontWeight: FontWeight.bold,
                color: enemyLeading ? enemyColor : const Color(0xFF8A7A72),
              ),
            ),
            SizedBox(width: 4 * _s),
            Icon(Icons.history, size: 12 * _s, color: const Color(0xFF8A7A72)),
          ],
        ),
      ),
    );
  }

  void _showScoreHistoryDialog(GameStateData state) {
    final history = state.scoreHistory;
    final tA = state.totalScores['teamA'] ?? 0;
    final tB = state.totalScores['teamB'] ?? 0;
    final myTeam = state.myTeam;
    final myTotal = myTeam == 'A' ? tA : tB;
    final enemyTotal = myTeam == 'A' ? tB : tA;
    final myLabel = myTeam;
    final enemyLabel = myTeam == 'A' ? 'B' : 'A';

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360, maxHeight: 560),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F2EF),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE8DDD7)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEADFD8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.history,
                          color: Color(0xFF6A5A52),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              L10n.of(context).gameScoreHistory,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF5A4038),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              L10n.of(context).gameScoreHistorySubtitle,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF8A7A72),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _buildScoreHistoryTotalCard(
                        label: 'TEAM $myLabel',
                        score: myTotal,
                        color: const Color(0xFF4A90D9),
                        leading: myTotal >= enemyTotal,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildScoreHistoryTotalCard(
                        label: 'TEAM $enemyLabel',
                        score: enemyTotal,
                        color: const Color(0xFFD24B4B),
                        leading: enemyTotal >= myTotal,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (history.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9F6F4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE8DDD7)),
                    ),
                    child: Text(
                      L10n.of(context).gameNoCompletedRounds,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF8A7A72),
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: history.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final r = history[i];
                        final round = r['round'] ?? i + 1;
                        final rawA = r['teamA'] ?? 0;
                        final rawB = r['teamB'] ?? 0;
                        final rMy = myTeam == 'A' ? rawA : rawB;
                        final rEnemy = myTeam == 'A' ? rawB : rawA;
                        final myWon = rMy > rEnemy;
                        final enemyWon = rEnemy > rMy;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFCFAF8),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFEAE0DA)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 52,
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1E8E2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'R$round',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF7A675E),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildScoreHistoryDelta(
                                  label: myLabel,
                                  score: rMy,
                                  color: const Color(0xFF4A90D9),
                                  highlighted: myWon,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildScoreHistoryDelta(
                                  label: enemyLabel,
                                  score: rEnemy,
                                  color: const Color(0xFFD24B4B),
                                  highlighted: enemyWon,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(L10n.of(context).gameClose),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScoreHistoryTotalCard({
    required String label,
    required int score,
    required Color color,
    required bool leading,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$score',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: leading ? color : const Color(0xFF5A4038),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreHistoryDelta({
    required String label,
    required int score,
    required Color color,
    required bool highlighted,
  }) {
    final display = score >= 0 ? '+$score' : '$score';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: highlighted ? color.withValues(alpha: 0.12) : const Color(0xFFF7F2EF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            L10n.of(context).gameTeamLabel(label),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            display,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: highlighted ? color : const Color(0xFF5A4038),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDogPlayedBanner(String playerName) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6DCE8)),
      ),
      child: Column(
        children: [
          Text(
            playerName.isNotEmpty
                ? L10n.of(context).gameDogPlayedBy(playerName.length > 8 ? '${playerName.substring(0, 8)}..' : playerName)
                : L10n.of(context).gameDogPlayed,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF8A7A72),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          const PlayingCard(
            cardId: 'special_dog',
            width: 32,
            height: 45,
            isInteractive: false,
          ),
        ],
      ),
    );
  }

  Widget _buildLatestTrick(GameStateData state) {
    final lastPlay = state.currentTrick.last;
    // Bug #9: Determine team color from player position
    final isMyTeam = state.players.any((p) =>
      (p.position == 'self' || p.position == 'partner') && p.id == lastPlay.playerId);
    final trickBgColor = isMyTeam
        ? const Color(0xFFE3F0FF) // blue tint for my team
        : const Color(0xFFFFE8EC); // pink tint for opponent
    final trickBorderColor = isMyTeam
        ? const Color(0xFFB3D4F7)
        : const Color(0xFFF5C0C8);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: trickBgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: trickBorderColor),
      ),
      child: Column(
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: lastPlay.playerName.length > 8
                      ? '${lastPlay.playerName.substring(0, 8)}..'
                      : lastPlay.playerName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isMyTeam ? const Color(0xFF4A90D9) : const Color(0xFFD94A5A),
                  ),
                ),
                TextSpan(
                  text: L10n.of(context).gamePlayedCards,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8A7A72),
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          _buildOverlappedTrick(lastPlay.cards),
        ],
      ),
    );
  }

  Widget _buildOverlappedTrick(List<String> cards) {
    const double cardW = 36;
    const double cardH = 50;
    const double minOverlap = 20;
    const double maxOverlap = 30;

    if (cards.length <= 4) {
      return Wrap(
        alignment: WrapAlignment.center,
        spacing: 3,
        children: cards
            .map((cardId) => PlayingCard(
                  cardId: cardId,
                  width: cardW,
                  height: cardH,
                  isInteractive: false,
                ))
            .toList(),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth - 16; // padding
        // Calculate overlap to fit all cards in one row
        final neededOverlap = cards.length > 1
            ? (availableWidth - cardW) / (cards.length - 1)
            : availableWidth;

        if (neededOverlap >= minOverlap) {
          // Fits in one row
          final overlap = neededOverlap.clamp(minOverlap, maxOverlap);
          final totalWidth = cardW + overlap * (cards.length - 1);
          return Center(
            child: SizedBox(
              width: totalWidth,
              height: cardH,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (int i = 0; i < cards.length; i++)
                    Positioned(
                      left: i * overlap,
                      child: PlayingCard(
                        cardId: cards[i],
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

        // Split into two rows
        final mid = (cards.length + 1) ~/ 2;
        final row1 = cards.sublist(0, mid);
        final row2 = cards.sublist(mid);

        Widget buildRow(List<String> rowCards) {
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
                      cardId: rowCards[i],
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

  Widget _buildBottomArea(GameStateData state, GameService game) {
    final isMyTurn = state.isMyTurn;
    return Container(
      padding: EdgeInsets.all(10 * _s),
      decoration: BoxDecoration(
        color: isMyTurn
            ? const Color(0xFFFFF8E1)
            : Colors.white.withValues(alpha: 0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: isMyTurn
                ? const Color(0xFFFFD54F).withValues(alpha: 0.4)
                : Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
        border: isMyTurn
            ? const Border(top: BorderSide(color: Color(0xFFFFCA28), width: 2.5))
            : null,
      ),
      child: Column(
        children: [
          // My name (tappable for profile) + status
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                margin: EdgeInsets.only(right: 4 * _s),
                padding: EdgeInsets.symmetric(horizontal: 3 * _s, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F0FF),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: const Color(0xFF4A90D9),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  state.myTeam,
                  style: TextStyle(
                    fontSize: 8 * _s,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF4A90D9),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _showPlayerProfileDialog(game.playerName, game),
                child: Text(
                  game.playerName,
                  style: TextStyle(
                    fontSize: 12 * _s,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF5A4038),
                  ),
                ),
              ),
              if (isMyTurn) ...[
                SizedBox(width: 6 * _s),
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 8 * _s, vertical: 3 * _s),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF2B3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE6C86A)),
                  ),
                  child: Text(
                    L10n.of(context).gameMyTurn,
                    style: TextStyle(
                      fontSize: 11 * _s,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF5A4038),
                    ),
                  ),
                ),
              ],
              if (_tichuBadgeForSelf(state) != null) ...[
                const SizedBox(width: 8),
                _tichuBadgeForSelf(state)!,
              ],
              if (game.myTimeoutCount > 0) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => game.resetTimeout(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFFB74D)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${game.myTimeoutCount}/3',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFE65100),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          L10n.of(context).gameNotAfk,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFE65100),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),

          // My hand - two rows (split in half)
          Padding(
            padding: EdgeInsets.symmetric(vertical: state.myCards.length >= 13 ? 6 : 10),
            child: _buildHandRows(state),
          ),
          const SizedBox(height: 8),

          // Action buttons (stable layout)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: (state.phase == 'playing' &&
                        _selectedCards.isNotEmpty &&
                        !state.dragonPending &&
                        (state.isMyTurn || _isBombCombo(_selectedCards.toList())))
                    ? _playCards
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDAF3E1),
                  foregroundColor: const Color(0xFF2F5A40),
                  disabledBackgroundColor: const Color(0xFFCAC3BF),
                  disabledForegroundColor: const Color(0xFF7A6E68),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(L10n.of(context).gamePlay),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: (state.phase == 'playing' &&
                        state.isMyTurn &&
                        state.currentTrick.isNotEmpty)
                    ? _passTurn
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF3EDE8),
                  foregroundColor: const Color(0xFF5A4E48),
                  disabledBackgroundColor: const Color(0xFFCFC7C2),
                  disabledForegroundColor: const Color(0xFF7D736E),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(L10n.of(context).gamePass),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLargeTichuDialog(GameService game) {
    return Positioned(
      bottom: 280,
      left: 0,
      right: 0,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              L10n.of(context).gameLargeTichuQuestion,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: () => game.declareLargeTichu(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD700),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: Text(L10n.of(context).gameDeclare),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: () => game.passLargeTichu(),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: Text(L10n.of(context).gamePass),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallTichuInline(GameService game) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ElevatedButton(
        onPressed: () {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(L10n.of(context).gameSmallTichuConfirmTitle),
              content: Text(L10n.of(context).gameSmallTichuConfirmContent),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(L10n.of(context).gameCancel),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    game.declareSmallTichu();
                  },
                  child: Text(L10n.of(context).gameDeclareButton),
                ),
              ],
            ),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFFE4B5),
          foregroundColor: const Color(0xFF8B6914),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(L10n.of(context).gameSmallTichuDeclare, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildExchangeDialog(GameStateData state, GameService game) {
    final left = _firstWhereOrNull(state.players, (p) => p.position == 'left');
    final partner = _firstWhereOrNull(state.players, (p) => p.position == 'partner');
    final right = _firstWhereOrNull(state.players, (p) => p.position == 'right');

    final selectedCard = _selectedCards.isNotEmpty ? _selectedCards.first : null;
    final assignedCount = _exchangeAssignments.length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                selectedCard != null ? L10n.of(context).gameSelectRecipient : L10n.of(context).gameSelectExchangeCard(assignedCount),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              if (_exchangeAssignments.isNotEmpty) ...[
                const SizedBox(width: 6),
                SizedBox(
                  height: 28,
                  child: TextButton(
                    onPressed: () {
                      setState(() {
                        _exchangeAssignments.clear();
                        _selectedCards.clear();
                      });
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(L10n.of(context).gameReset, style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              SizedBox(
                height: 28,
                child: ElevatedButton(
                  onPressed: assignedCount == 3
                      ? () {
                          _exchangeGiven
                            ..clear()
                            ..addAll(_exchangeAssignments);
                          _exchangeSummaryShown = false;
                          game.exchangeCards(
                            _exchangeAssignments['left']!,
                            _exchangeAssignments['partner']!,
                            _exchangeAssignments['right']!,
                          );
                          setState(() {
                            _exchangeSubmitted = true;
                            _exchangeAssignments.clear();
                            _selectedCards.clear();
                          });
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC7E6D0),
                    foregroundColor: const Color(0xFF3A5A40),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(L10n.of(context).gameExchangeComplete, style: const TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildExchangeButton('left', left?.name ?? L10n.of(context).gameLeftPlayer, selectedCard),
              _buildExchangeButton('partner', partner?.name ?? L10n.of(context).gamePartner, selectedCard),
              _buildExchangeButton('right', right?.name ?? L10n.of(context).gameRightPlayer, selectedCard),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExchangeInline(GameStateData state, GameService game) {
    return _buildExchangeDialog(state, game);
  }

  Widget _buildExchangeButton(String position, String name, String? selectedCard) {
    final assignedCard = _exchangeAssignments[position];
    final isAssigned = assignedCard != null;
    final canAssign = selectedCard != null && !isAssigned && !_exchangeAssignments.containsValue(selectedCard);

    return GestureDetector(
      onTap: canAssign
          ? () {
              setState(() {
                _exchangeAssignments[position] = selectedCard;
                _selectedCards.clear();
              });
            }
          : isAssigned
              ? () {
                  setState(() {
                    _exchangeAssignments.remove(position);
                  });
                }
              : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isAssigned
              ? const Color(0xFFC7E6D0)
              : canAssign
                  ? const Color(0xFFE8F4FF)
                  : const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: canAssign ? const Color(0xFF4D99FF) : const Color(0xFFDDD0CC),
            width: canAssign ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isAssigned ? const Color(0xFF3A5A40) : const Color(0xFF5A4038),
              ),
            ),
            if (isAssigned) ...[
              const SizedBox(width: 4),
              const Icon(Icons.check_circle, size: 14, color: Color(0xFF3A5A40)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDragonDialog(GameStateData state, GameService game) {
    final left = _firstWhereOrNull(state.players, (p) => p.position == 'left');
    final right = _firstWhereOrNull(state.players, (p) => p.position == 'right');
    final leftName = left?.name ?? L10n.of(context).gameLeftPlayer;
    final rightName = right?.name ?? L10n.of(context).gameRightPlayer;
    return _buildDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            L10n.of(context).gameDragonQuestion,
            style: const TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              ElevatedButton(
                onPressed: () => game.dragonGive('left'),
                child: Text(leftName),
              ),
              ElevatedButton(
                onPressed: () => game.dragonGive('right'),
                child: Text(rightName),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDragonGivenInline(String message) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF66BB6A)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('\u{1F409}', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Text(
            message,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2E7D32),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallRankDialog(GameService game) {
    final ranks = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];
    return _buildDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            L10n.of(context).gameSelectCallRank,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: ranks.map((rank) {
              return ElevatedButton(
                onPressed: () => game.callRank(rank),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(48, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: Text(rank),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => game.callRank('none'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(120, 40),
            ),
            child: Text(L10n.of(context).gameNoCall),
          ),
        ],
      ),
    );
  }

  Widget _buildRoundEndDialog(GameStateData state, GameService game) {
    final isGameEnd = state.phase == 'game_end';
    final l10n = L10n.of(context);
    String title = isGameEnd ? l10n.gameGameEnd : l10n.gameRoundEnd;

    if (isGameEnd) {
      final teamA = state.totalScores['teamA'] ?? 0;
      final teamB = state.totalScores['teamB'] ?? 0;
      final myTeam = state.myTeam;
      final myScore = myTeam == 'A' ? teamA : teamB;
      final enemyScore = myTeam == 'A' ? teamB : teamA;
      title = myScore > enemyScore ? l10n.gameMyTeamWin : (myScore < enemyScore ? l10n.gameEnemyTeamWin : l10n.gameDraw);
    }

    // C8: Only request profile once to prevent rebuild loop
    if (isGameEnd && game.isRankedRoom && !_profileRequested) {
      final profile = game.profileFor(game.playerName);
      if (profile == null || profile['nickname'] != game.playerName) {
        _profileRequested = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) game.requestProfile(game.playerName);
        });
      }
    }

    return _buildDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          if (state.lastRoundScores.isNotEmpty) ...[
            Text.rich(
              TextSpan(children: [
                TextSpan(text: l10n.gameThisRound),
                TextSpan(text: '${state.myTeam == 'A' ? state.lastRoundScores['teamA'] : state.lastRoundScores['teamB']}', style: const TextStyle(color: Color(0xFF4A90D9), fontWeight: FontWeight.bold)),
                const TextSpan(text: ' : '),
                TextSpan(text: '${state.myTeam == 'A' ? state.lastRoundScores['teamB'] : state.lastRoundScores['teamA']}', style: const TextStyle(color: Color(0xFFD24B4B), fontWeight: FontWeight.bold)),
              ]),
              style: const TextStyle(fontSize: 14),
            ),
          ],
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: l10n.gameTotalScore),
              TextSpan(text: '${state.myTeam == 'A' ? state.totalScores['teamA'] : state.totalScores['teamB']}', style: const TextStyle(color: Color(0xFF4A90D9), fontWeight: FontWeight.bold)),
              const TextSpan(text: ' : '),
              TextSpan(text: '${state.myTeam == 'A' ? state.totalScores['teamB'] : state.totalScores['teamA']}', style: const TextStyle(color: Color(0xFFD24B4B), fontWeight: FontWeight.bold)),
            ]),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          if (isGameEnd && game.isRankedRoom) ...[
            const SizedBox(height: 14),
            _buildRankedResult(game),
          ],
          const SizedBox(height: 12),
          Text(
            isGameEnd ? l10n.gameAutoReturnLobby : l10n.gameAutoNextRound,
            style: const TextStyle(fontSize: 12, color: Color(0xFF8A7A72)),
          ),
        ],
      ),
    );
  }

  Widget _buildRankedResult(GameService game) {
    final profile = game.profileFor(game.playerName);
    if (profile == null || profile['nickname'] != game.playerName) {
      return const SizedBox(
        height: 40,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final data = profile['profile'] as Map<String, dynamic>?;
    if (data == null) {
      return const SizedBox.shrink();
    }
    final seasonRating = data['seasonRating'] ?? 1000;
    final tier = _rankTier(seasonRating);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F3FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4DFF2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _rankBadge(tier),
          const SizedBox(width: 10),
          Text(
            L10n.of(context).gameRankedScore(seasonRating as int),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF4A4080),
            ),
          ),
        ],
      ),
    );
  }

  _RankTier _rankTier(int rating) {
    if (rating >= 1500) return _RankTier.diamond;
    if (rating >= 1300) return _RankTier.gold;
    if (rating >= 1100) return _RankTier.silver;
    return _RankTier.bronze;
  }

  Widget _rankBadge(_RankTier tier) {
    final l10n = L10n.of(context);
    switch (tier) {
      case _RankTier.diamond:
        return _rankPill(l10n.gameRankDiamond, const Color(0xFF69B7FF), Icons.diamond_outlined);
      case _RankTier.gold:
        return _rankPill(l10n.gameRankGold, const Color(0xFFFFD54F), Icons.emoji_events);
      case _RankTier.silver:
        return _rankPill(l10n.gameRankSilver, const Color(0xFFB0BEC5), Icons.emoji_events);
      case _RankTier.bronze:
        return _rankPill(l10n.gameRankBronze, const Color(0xFFC58B6B), Icons.emoji_events);
    }
  }

  Widget _rankPill(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildDialog({required Widget child}) {
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
          child: child,
        ),
      ),
    );
  }

  String _getPlayerInfo(Player? player) {
    if (player == null) return '';
    if (player.hasFinished) return L10n.of(context).gameFinishPosition(player.finishPosition);

    return L10n.of(context).gameCardCount(player.cardCount);
  }

  String _getPhaseName(String phase) {
    final l10n = L10n.of(context);
    switch (phase) {
      case 'large_tichu_phase':
        return l10n.gamePhaseLargeTichu;
      case 'dealing_remaining_6':
        return l10n.gamePhaseDealing;
      case 'card_exchange':
        return l10n.gamePhaseExchange;
      case 'playing':
        return l10n.gamePhasePlaying;
      case 'round_end':
        return l10n.gamePhaseRoundEnd;
      case 'game_end':
        return l10n.gamePhaseGameEnd;
      default:
        return phase;
    }
  }

  String _getCurrentPlayerName(GameStateData state) {
    if (state.currentPlayer == null) return '';
    final player = _firstWhereOrNull(
      state.players,
      (p) => p.id == state.currentPlayer,
    );
    return player?.name ?? '';
  }

  Widget _buildOverlappedHand({
    required int count,
    required double cardWidth,
    required double cardHeight,
    required double overlap,
    int maxVisible = 12,
  }) {
    final visible = count.clamp(0, maxVisible);
    final totalWidth = visible == 0
        ? 0.0
        : cardWidth + (visible - 1) * (cardWidth - overlap);

    return SizedBox(
      height: cardHeight,
      child: Center(
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            SizedBox(width: totalWidth, height: cardHeight),
            for (var i = 0; i < visible; i++)
              Positioned(
                left: i * (cardWidth - overlap),
                child: PlayingCard(
                  cardId: '',
                  isFaceUp: false,
                  width: cardWidth,
                  height: cardHeight,
                  isInteractive: false,
                ),
              ),
            if (count > visible)
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE6DCE8)),
                  ),
                  child: Text(
                    '+${count - visible}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF8A7A72),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlappedHandVertical({
    required int count,
    required double cardWidth,
    required double cardHeight,
    required double overlap,
    int maxVisible = 8,
  }) {
    final visible = count.clamp(0, maxVisible);
    final totalHeight = visible == 0
        ? 0.0
        : cardHeight + (visible - 1) * (cardHeight - overlap);

    return SizedBox(
      width: cardWidth,
      height: totalHeight,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          for (var i = 0; i < visible; i++)
            Positioned(
              top: i * (cardHeight - overlap),
              child: PlayingCard(
                cardId: '',
                isFaceUp: false,
                width: cardWidth,
                height: cardHeight,
                isInteractive: false,
              ),
            ),
        ],
      ),
    );
  }

  Player? _firstWhereOrNull(
    Iterable<Player> players,
    bool Function(Player p) test,
  ) {
    for (final p in players) {
      if (test(p)) return p;
    }
    return null;
  }

  void _maybeShowExchangeSummary(GameStateData state) {
    if (_exchangeSummaryShown) return;
    if (!state.exchangeDone) return;
    // Wait until exchange is fully performed (phase moves past card_exchange)
    if (state.phase == 'card_exchange') return;

    // Use local _exchangeGiven if available, otherwise fall back to server data
    final givenData = _exchangeGiven.isNotEmpty
        ? _exchangeGiven
        : state.exchangeGiven;
    if (givenData == null || givenData.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _exchangeSummaryShown) return;
      _exchangeSummaryShown = true;
      final leftName = _nameForPosition(state, 'left');
      final partnerName = _nameForPosition(state, 'partner');
      final rightName = _nameForPosition(state, 'right');

      // Use server-provided receivedFrom data
      final receivedLeft = state.receivedFrom?['left'];
      final receivedPartner = state.receivedFrom?['partner'];
      final receivedRight = state.receivedFrom?['right'];

      showDialog(
        context: context,
        builder: (_) => _buildDialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                L10n.of(context).gameReceivedCards,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _buildExchangeSummaryRowLine([
                _ExchangeSummaryItem(leftName, receivedLeft),
                _ExchangeSummaryItem(partnerName, receivedPartner),
                _ExchangeSummaryItem(rightName, receivedRight),
              ]),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE8E0DC),
                  foregroundColor: const Color(0xFF6A5A52),
                ),
                child: Text(L10n.of(context).gameClose),
              ),
            ],
          ),
        ),
      );
    });
  }

  String _nameForPosition(GameStateData state, String position) {
    final p = _firstWhereOrNull(state.players, (pl) => pl.position == position);
    return p?.name ?? position;
  }

  Widget _buildExchangeSummaryRowLine(List<_ExchangeSummaryItem> items) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: items
          .where((i) => i.cardId != null)
          .map(
            (item) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.name.length > 4 ? '${item.name.substring(0, 4)}…' : item.name,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8A7A72),
                  ),
                ),
                const SizedBox(height: 4),
                PlayingCard(
                  cardId: item.cardId!,
                  width: 34,
                  height: 48,
                  isInteractive: false,
                ),
              ],
            ),
          )
          .toList(),
    );
  }

  String _teamForPosition(GameStateData state, String position) {
    final myTeam = state.myTeam;
    final sameTeam = (position == 'self' || position == 'partner');
    return sameTeam ? myTeam : (myTeam == 'A' ? 'B' : 'A');
  }

  Widget _buildTurnName({
    required String name,
    required bool isTurn,
    double fontSize = 14,
    Widget? badge,
    bool exchangeDone = false,
    bool connected = true,
    int timeoutCount = 0,
    String? teamLabel,
    bool isMyTeam = false,
  }) {
    final maxLen = _maxNameLen;
    final displayName = name.length > maxLen ? '${name.substring(0, maxLen)}..' : name;
    final s = _s;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (badge != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: badge,
          ),
        if (timeoutCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 4 * s, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFB74D)),
              ),
              child: Text(
                '⏱ $timeoutCount/3',
                style: TextStyle(
                  fontSize: 8 * s,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFE65100),
                ),
              ),
            ),
          ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 3 * s),
          decoration: BoxDecoration(
            color: isTurn ? const Color(0xFFFFF2B3) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: isTurn
                ? Border.all(color: const Color(0xFFE6C86A))
                : null,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 120 * s),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (teamLabel != null)
                  Container(
                    margin: EdgeInsets.only(right: 4 * s),
                    padding: EdgeInsets.symmetric(horizontal: 3 * s, vertical: 1),
                    decoration: BoxDecoration(
                      color: isMyTeam
                          ? const Color(0xFFE3F0FF)
                          : const Color(0xFFFFE8EC),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isMyTeam
                            ? const Color(0xFF4A90D9)
                            : const Color(0xFFD24B4B),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      teamLabel,
                      style: TextStyle(
                        fontSize: 8 * s,
                        fontWeight: FontWeight.bold,
                        color: isMyTeam
                            ? const Color(0xFF4A90D9)
                            : const Color(0xFFD24B4B),
                      ),
                    ),
                  ),
                if (!connected)
                  Container(
                    margin: EdgeInsets.only(right: 4 * s),
                    child: Icon(
                      Icons.wifi_off,
                      size: 12 * s,
                      color: Colors.red,
                    ),
                  )
                else if (isTurn)
                  Container(
                    width: 6 * s,
                    height: 6 * s,
                    margin: EdgeInsets.only(right: 4 * s),
                    decoration: const BoxDecoration(
                      color: Color(0xFFE6A800),
                      shape: BoxShape.circle,
                    ),
                  ),
                Flexible(
                  child: Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: fontSize * s,
                      fontWeight: FontWeight.bold,
                      color: connected ? const Color(0xFF5A4038) : Colors.grey,
                    ),
                  ),
                ),
                if (exchangeDone)
                  Container(
                    margin: EdgeInsets.only(left: 4 * s),
                    child: Icon(
                      Icons.check_circle,
                      size: 12 * s,
                      color: const Color(0xFF3A8F52),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget? _tichuBadgeForPlayer(Player? player) {
    if (player == null) return null;
    if (player.hasLargeTichu) {
      return _tichuBadge(
        label: L10n.of(context).gameBadgeLarge,
        bg: const Color(0xFFFF4444),
        fg: Colors.white,
        border: const Color(0xFFCC0000),
      );
    }
    if (player.hasSmallTichu) {
      return _tichuBadge(
        label: L10n.of(context).gameBadgeSmall,
        bg: const Color(0xFF2979FF),
        fg: Colors.white,
        border: const Color(0xFF1565C0),
      );
    }
    return null;
  }

  Widget? _tichuBadgeForSelf(GameStateData state) {
    final me = _firstWhereOrNull(state.players, (p) => p.position == 'self');
    return _tichuBadgeForPlayer(me);
  }

  Widget _tichuBadge({
    required String label,
    required Color bg,
    required Color fg,
    required Color border,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: bg.withValues(alpha: 0.4),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }

  Color? _tichuOverlayColor(GameStateData state) {
    final anyLarge = state.players.any((p) => p.hasLargeTichu);
    final anySmall = state.players.any((p) => p.hasSmallTichu);
    if (anyLarge) return const Color(0x33FF6B6B);
    if (anySmall) return const Color(0x334BA3FF);
    return null;
  }

  Widget _buildHandRows(GameStateData state) {
    List<String> cards = state.myCards;
    final isExchangePhase = state.phase == 'card_exchange' && !state.exchangeDone;

    // Bug #5: Hide submitted exchange cards from hand display
    if (_exchangeSubmitted && state.exchangeDone && _exchangeGiven.isNotEmpty) {
      final givenCards = _exchangeGiven.values.toSet();
      cards = cards.where((c) => !givenCards.contains(c)).toList();
    }

    // 교환 단계에서 이미 할당된 카드는 선택 불가
    bool isCardAssigned(String cardId) => _exchangeAssignments.containsValue(cardId);

    Widget buildCardWidget(String cardId, double cardWidth, double cardHeight, double padding) {
      final assigned = isCardAssigned(cardId);
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: padding),
        child: Opacity(
          opacity: assigned ? 0.4 : 1.0,
          child: PlayingCard(
            cardId: cardId,
            width: cardWidth,
            height: cardHeight,
            isSelected: _selectedCards.contains(cardId),
            onTap: assigned ? null : () => _toggleCard(cardId, singleSelect: isExchangePhase),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalMargin = 16.0;
        final availableWidth = constraints.maxWidth - (horizontalMargin * 2);
        final perRow = cards.length <= 6 ? cards.length : (cards.length / 2).ceil();
        final dense = cards.length >= 13;
        final cardPadding = dense ? 2.0 : 3.0;
        final totalPadding = perRow * cardPadding * 2;
        final maxWidth = dense ? 46.0 : 50.0;
        final minWidth = dense ? 34.0 : 38.0;
        final cardWidth =
            ((availableWidth - totalPadding) / perRow).clamp(minWidth, maxWidth);
        final cardHeight = (cardWidth * (dense ? 1.35 : 1.4)).clamp(
          dense ? 48.0 : 53.0,
          dense ? 64.0 : 70.0,
        );

        List<Widget> rowWidgets(List<String> row) {
          return row
              .map((cardId) => buildCardWidget(cardId, cardWidth, cardHeight, cardPadding))
              .toList();
        }

        if (cards.length <= 6) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: horizontalMargin),
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
          padding: const EdgeInsets.symmetric(horizontal: horizontalMargin),
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
}

enum _RankTier { bronze, silver, gold, diamond }

class _ExchangeSummaryItem {
  final String name;
  final String? cardId;
  const _ExchangeSummaryItem(this.name, this.cardId);
}

class _BannerStyle {
  const _BannerStyle({this.gradient});
  final LinearGradient? gradient;
}
