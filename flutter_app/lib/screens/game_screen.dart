import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/game_service.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/bot_avatar.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/player_profile_body.dart';
import '../widgets/player_profile_header.dart';
import '../services/session_service.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../widgets/playing_card.dart';
import '../widgets/connection_overlay.dart';
import '../widgets/draggable_chat_panel.dart';
import '../widgets/spectator_controls.dart';
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

  // Rolling per-trick play log (top-left overlay under the timer). Each
  // new currentTrick entry adds a one-line summary, reset when the trick
  // clears (currentTrick empties after a win) or when phase != 'playing'.
  final List<String> _trickPlayLog = [];
  final List<String> _trickPlayLogKeys = [];
  final List<bool> _trickPlayLogIsMine = [];

  // 턴 타이머
  Timer? _countdownTimer;
  int _remainingSeconds = 0;
  int _lastTickSoundSecond = 999;
  bool _birdCallDialogOpen = false;
  bool _roundEndReady = false; // delay before showing round end dialog
  bool _waitingForRoomRecovery = false;
  GameService? _gameService;
  bool _profileRequested = false; // C8: Prevent requestProfile loop
  int _lastSeenMessageCount = -1; // -1 = not yet initialized

  @override
  void initState() {
    super.initState();
    // 로그인 후 차단 목록 요청
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gameService = context.read<GameService>();
      _gameService!.requestBlockedUsers();
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateCountdown();
    });
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
              // Delay round end dialog so players can see the last card played
              if (_prevPhase != 'round_end' && _prevPhase != 'game_end' &&
                  (state.phase == 'round_end' || state.phase == 'game_end')) {
                _roundEndReady = false;
                Future.delayed(const Duration(seconds: 1), () {
                  if (mounted) setState(() => _roundEndReady = true);
                });
              } else if (state.phase != 'round_end' && state.phase != 'game_end') {
                _roundEndReady = false;
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

                  if (_roundEndReady && (state.phase == 'round_end' || state.phase == 'game_end'))
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
    // Board (top bar + partner area + middle/trick area) stays in a Column
    // and fills all available vertical space — middle area never resizes
    // when the hand height or inline prompts change.
    //
    // Hand area and the optional inline prompts (exchange, dragon given,
    // small tichu) are pulled out into a bottom-anchored overlay so they
    // can grow/shrink without pushing the board around. They visually sit
    // on top of the middle area's bottom edge.
    //
    // Turn timer is also a separate top-left overlay for the same reason —
    // its appearance/disappearance can't grow the topbar column.
    final timerBadge = _buildTimerBadge(state, isLandscape: false);
    return Stack(
      children: [
        Column(
          children: [
            _buildTopBar(state, game),
            _buildPartnerArea(state, game),
            Expanded(
              // Reserve a constant bottom slot equal to the typical max
              // hand-area height (full 14-card hand + name row + action
              // buttons ≈ 220–240). This pushes the trick board's vertical
              // center above the bottom overlay so cards don't sit on top
              // of it. Below 14 cards the hand shrinks under the reserve
              // and the board still doesn't move.
              child: Padding(
                padding: const EdgeInsets.only(bottom: 220),
                child: _buildMiddleArea(state, game),
              ),
            ),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              // Counter and small-tichu button sit ABOVE the hand box,
              // outside its rounded card area, on opposite sides.
              if ((game.hasTopCardCounter && state.phase == 'playing') ||
                  _canShowSmallTichu(state))
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (game.hasTopCardCounter && state.phase == 'playing')
                      Padding(
                        padding: const EdgeInsets.only(left: 12, bottom: 4),
                        child: _buildTopCardCounter(state),
                      )
                    else
                      const SizedBox.shrink(),
                    if (_canShowSmallTichu(state))
                      _buildSmallTichuInline(game)
                    else
                      const SizedBox.shrink(),
                  ],
                ),
              _buildBottomArea(state, game),
            ],
          ),
        ),
        if (timerBadge != null)
          Positioned(
            top: 48,
            left: 12,
            child: timerBadge,
          ),
        // Trick-play log overlay (LL-style) — what was played in the
        // current trick. Clears between tricks. Sits below the timer.
        //
        // Kept to the left third: the partner's nameplate is centred at the same
        // height, and a full-width log ran its longest lines ("봇 2: 5스트레이트(5장)
        // - 콜A") straight underneath the avatar. Lines already ellipsize.
        Positioned(
          top: 82,
          left: 12,
          width: MediaQuery.of(context).size.width * 0.38,
          child: IgnorePointer(child: _buildTrickLogOverlay(state)),
        ),
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
        // Sub-panels (sound, viewers) are conceptually "inside" the
        // more menu — close them whenever more is toggled in either
        // direction so they don't stay floating after the parent menu
        // disappears.
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
            // Always wide enough for all 3 entries — viewers button now
            // shows regardless of hasViewers so that always_deny users
            // (who never have any viewer) can still reach the card-view
            // policy toggle inside the panel.
            width: 150,
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
                _buildViewersButton(game),
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
    return DraggableChatPanel(
      accentColor: const Color(0xFF64B5F6),
      sendIconColor: const Color(0xFF64B5F6),
      title: L10n.of(context).gameChat,
      hintText: L10n.of(context).gameMessageHint,
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
        return _buildChatBubble(sender, message, isMe, game);
      },
    );
  }

  Widget _buildChatBubble(String sender, String message, bool isMe, GameService game) {
    return ChatBubble(
      sender: sender,
      message: message,
      isMe: isMe,
      game: game,
      onTap: sender.isEmpty ? null : () => _showPlayerProfileDialog(sender, game),
    );
  }
  void _scrollChatToBottom() {
    // ListView is reverse:true so offset 0 == bottom (newest). Used to
    // snap the user back when a new message arrives while they were
    // scrolled up.
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

  void _showPlayerProfileDialog(String nickname, GameService game, {bool isBot = false}) {
    // A bot has no account, so this would only ever come back empty and the
    // popup would render its "profile not found" error.
    if (!isBot) game.requestProfile(nickname);

    showDialog(
      context: context,
      builder: (ctx) {
        return Consumer<GameService>(
          builder: (ctx, game, _) {
            // Auto-dismiss when the game ends so the round/result screen isn't hidden behind the dialog.
            final gs = game.gameState;
            if (gs == null || gs.phase == 'game_end') {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!ctx.mounted) return;
                final route = ModalRoute.of(ctx);
                if (route != null && route.isCurrent) Navigator.of(ctx).pop();
              });
            }
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
                      subtitle: L10n.of(ctx).gamePlayerProfile,
                      subtitleBuilder: (inner) => profileLevelStrip(
                        (inner?['level'] as int?) ?? 1,
                        (inner?['expTotal'] as int?) ?? 0,
                      ),
                      isBot: isBot,
                      onCloseDialog: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              content: isBot
                  ? SizedBox(width: 320, child: botProfileBody(context))
                  : isLoading
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
                        child: PlayerProfileBody(
                          data: profile,
                          game: game,
                          initialGame: 'tichu',
                        ),
                      ),
                    ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(L10n.of(ctx).gameClose),
                ),
              ],
            );
          },
        );
      },
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
            // Always-allow / always-deny live on the eye-icon viewers
            // panel (and in app settings) since they're a policy about
            // "my cards", not about this single request.
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
      // Always allow long-press so users (especially those set to
      // always_deny — who have no viewers and thus no in-game UI to
      // change the policy back) can still access the pref toggle.
      onLongPress: () => setState(() => _viewersOpen = !_viewersOpen),
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
            const Divider(height: 16, color: Color(0xFFEDE5E0)),
            _buildCardViewPrefSection(game),
          ],
        ),
      ),
    );
  }

  /// Card-view policy selector ('ask' / 'always_allow' / 'always_deny').
  /// Mirrors what the user can change from app settings; the choice
  /// persists per account on the server.
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
            color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
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
              if (selected)
                Icon(Icons.check, size: 14, color: color),
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
              photoUrl: game.blockedUsers.contains(partner?.name ?? '')
                  ? null
                  : game.resolvePhotoUrl(partner?.photoUrl),
              isBot: partner?.isBot ?? false,
              avatarSize: 40,
              avatarBeside: true,
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
            cardWidth: 30 * _s,
            cardHeight: 42 * _s,
            overlap: 19 * _s,
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
          width: 80 * _s,
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
                  photoUrl: game.blockedUsers.contains(left?.name ?? '')
                      ? null
                      : game.resolvePhotoUrl(left?.photoUrl),
                  isBot: left?.isBot ?? false,
                  avatarSize: 34,
                ),
              ),
              Text(
                _getPlayerInfo(left),
                style: TextStyle(fontSize: 9 * _s, color: const Color(0xFF8A7A72)),
              ),
              const SizedBox(height: 4),
              _buildOverlappedHandVertical(
                count: left?.cardCount ?? 0,
                cardWidth: 26 * _s,
                cardHeight: 36 * _s,
                overlap: 25 * _s,
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
          width: 80 * _s,
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
                  photoUrl: game.blockedUsers.contains(right?.name ?? '')
                      ? null
                      : game.resolvePhotoUrl(right?.photoUrl),
                  isBot: right?.isBot ?? false,
                  avatarSize: 34,
                ),
              ),
              Text(
                _getPlayerInfo(right),
                style: TextStyle(fontSize: 9 * _s, color: const Color(0xFF8A7A72)),
              ),
              const SizedBox(height: 4),
              _buildOverlappedHandVertical(
                count: right?.cardCount ?? 0,
                cardWidth: 26 * _s,
                cardHeight: 36 * _s,
                overlap: 25 * _s,
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
              _buildLatestTrick(state)
            else if (state.lastTrick.isNotEmpty && (state.phase == 'round_end' || state.phase == 'game_end'))
              _buildLatestTrick(state, useLastTrick: true),

          ],
        ),
      ),
    );
  }

  Widget? _buildTimerBadge(GameStateData state, {required bool isLandscape}) {
    if (_remainingSeconds <= 0) return null;
    final l10n = L10n.of(context);
    final currentPlayerName = _getCurrentPlayerName(state);
    final compactPlayerName = currentPlayerName.length > 4
        ? '${currentPlayerName.substring(0, 4)}…'
        : currentPlayerName;
    final turnLabel = state.isMyTurn
        ? l10n.gameMyTurnShort
        : (isLandscape ? l10n.gamePlayerTurnShort(compactPlayerName) : l10n.gamePlayerWaiting(currentPlayerName));
    final timerFontSize = isLandscape ? 11.5 * _s : 13 * _s;
    final timerIconSize = isLandscape ? 12.5 * _s : 14 * _s;
    final timerPadding = isLandscape
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
        : const EdgeInsets.symmetric(horizontal: 10, vertical: 5);
    return Container(
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
    );
  }

  Widget _buildTopBar(GameStateData state, GameService game) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    // Portrait shows the timer as an overlay on top of the game board
    // (see _buildPortraitGameLayout), so don't include it in the topbar
    // column there — it caused the whole board to jump in height when the
    // timer appeared/disappeared between turns.
    final timerBadge = isLandscape
        ? _buildTimerBadge(state, isLandscape: true)
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
      child: Stack(
        alignment: Alignment.center,
        children: [
          _buildScoreBar(state),
          // Top-card counter is rendered as a floating top-left overlay
          // (see _buildPortraitGameLayout) so it doesn't compete with
          // the scoreBar for horizontal space.
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
            // The finish line moved into the score-history dialog: next to the
            // running score it read as a fraction ("25 / 1000") rather than a
            // goal, and this bar is the one thing always on screen.
            SizedBox(width: 4 * _s),
            Icon(Icons.history, size: 12 * _s, color: const Color(0xFF8A7A72)),
          ],
        ),
      ),
    );
  }

  void _showScoreHistoryDialog(GameStateData state) {
    showTichuScoreHistoryDialog(
      context,
      history: state.scoreHistory,
      totalA: state.totalScores['teamA'] ?? 0,
      totalB: state.totalScores['teamB'] ?? 0,
      myTeam: state.myTeam,
      targetScore: context.read<GameService>().roomTargetScore,
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

  Widget _buildLatestTrick(GameStateData state, {bool useLastTrick = false}) {
    final trick = useLastTrick ? state.lastTrick : state.currentTrick;
    if (trick.isEmpty) return const SizedBox.shrink();
    final lastPlay = trick.last;
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
          _buildOverlappedTrick(lastPlay.cards, lastPlay: lastPlay),
        ],
      ),
    );
  }

  Widget _buildOverlappedTrick(List<String> cards, {TrickPlay? lastPlay}) {
    // Scaled, not fixed: the trick is what the table is actually looking at and
    // 36x50 read small, but a fixed bump would wrap a plain 4-card play onto two
    // rows on the narrowest phones. Long combos still fit — the layout below
    // tightens the overlap and falls back to two rows.
    final double cardW = 44 * _s;
    final double cardH = 61 * _s;
    final double minOverlap = 22 * _s;
    final double maxOverlap = 32 * _s;

    // Phoenix-as-single → overlay a chip on the card showing what rank
    // it beat (e.g. "↑Q"), so the table can read the play at a glance.
    final isPhoenixSingleTrick = lastPlay != null
        && lastPlay.combo == 'single'
        && cards.length == 1
        && cards[0] == 'special_phoenix'
        && lastPlay.comboValue > 1;
    final phoenixBeatLabel = isPhoenixSingleTrick
        ? _phoenixBeatLabel(lastPlay.comboValue)
        : null;

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
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF5A4038),
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
        children: cards.map(playingCard).toList(),
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
                      child: playingCard(cards[i]),
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
                    child: playingCard(rowCards[i]),
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

  Widget _buildTrickLogOverlay(GameStateData state) {
    if (state.phase != 'playing' || state.currentTrick.isEmpty) {
      if (_trickPlayLog.isNotEmpty) {
        _trickPlayLog.clear();
        _trickPlayLogKeys.clear();
        _trickPlayLogIsMine.clear();
      }
      return const SizedBox.shrink();
    }
    final trick = state.currentTrick;
    for (var i = 0; i < trick.length; i++) {
      final play = trick[i];
      final key = '$i/${play.playerId}/${play.cards.join(",")}';
      if (_trickPlayLogKeys.contains(key)) continue;
      // Bird-only call suffix: append "- 콜N" only on the play that
      // actually produced the wish (the play containing special_bird).
      final isBirdPlay = play.cards.contains('special_bird');
      _trickPlayLog.add(_formatPlayLine(play, isBirdPlay ? state.callRank : null));
      _trickPlayLogKeys.add(key);
      _trickPlayLogIsMine.add(_isMyTeamPlay(state, play.playerId));
      while (_trickPlayLog.length > 4) {
        _trickPlayLog.removeAt(0);
        _trickPlayLogKeys.removeAt(0);
        _trickPlayLogIsMine.removeAt(0);
      }
    }
    if (_trickPlayLog.isEmpty) return const SizedBox.shrink();
    final reversed = _trickPlayLog.reversed.toList();
    final reversedMine = _trickPlayLogIsMine.reversed.toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < reversed.length; i++) ...[
          if (i > 0) const SizedBox(height: 2),
          Text(
            reversed[i],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: reversedMine[i]
                  ? const Color(0xFF2F6FC4)
                  : const Color(0xFFB23A3A),
              fontSize: i == 0 ? 13 : 11,
              fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  bool _isMyTeamPlay(GameStateData state, String playerId) {
    for (final p in state.players) {
      if (p.id == playerId) {
        return p.position == 'self' || p.position == 'partner';
      }
    }
    return true;
  }

  String _formatPlayLine(TrickPlay play, String? callRank) {
    final name = play.playerName.length > 6
        ? '${play.playerName.substring(0, 6)}…'
        : play.playerName;
    final desc = _comboShortDesc(play);
    if (callRank != null && callRank.isNotEmpty) {
      return '$name: $desc - 콜$callRank';
    }
    return '$name: $desc';
  }

  String _comboShortDesc(TrickPlay play) {
    final cards = play.cards;
    if (cards.length == 1) {
      final cid = cards[0];
      if (cid == 'special_phoenix' && play.comboValue > 1) {
        return '봉황 ${_phoenixBeatLabel(play.comboValue)}';
      }
      if (cid == 'special_dragon') return '드래곤';
      if (cid == 'special_phoenix') return '봉황';
      if (cid == 'special_bird') return '새';
      if (cid == 'special_dog') return '개';
      return _rankFromCardId(cid);
    }
    switch (play.combo) {
      case 'pair':
        return '${_rankFromCardId(cards[0])} 페어';
      case 'triple':
        return '${_rankFromCardId(cards[0])} 트리플';
      case 'full_house':
        return '${_rankFromCardId(cards[0])} 풀하우스';
      case 'straight':
        return '${_rankLabelFromValue(play.comboValue)}스트레이트(${cards.length}장)';
      case 'steps':
        return '${_rankLabelFromValue(play.comboValue)}스텝(${cards.length}장)';
      case 'bomb_four':
        return '폭탄(4)';
      case 'bomb_straight_flush':
        return '스플 폭탄';
      default:
        return '${cards.length}장';
    }
  }

  String _rankFromCardId(String cardId) {
    if (cardId.startsWith('special_')) return cardId.split('_')[1];
    final parts = cardId.split('_');
    return parts.length >= 2 ? parts[1] : cardId;
  }

  String _phoenixBeatLabel(double comboValue) {
    final beat = comboValue.floor();
    if (beat >= 14) return '↑A';
    if (beat == 13) return '↑K';
    if (beat == 12) return '↑Q';
    if (beat == 11) return '↑J';
    return '↑$beat';
  }

  String _rankLabelFromValue(double comboValue) {
    final v = comboValue.floor();
    if (v >= 14) return 'A';
    if (v == 13) return 'K';
    if (v == 12) return 'Q';
    if (v == 11) return 'J';
    if (v <= 0) return '';
    return '$v';
  }

  Widget _buildSmallTichuInline(GameService game) {
    // Small chip-style button anchored to the right edge — mirrors the
    // top-card counter on the opposite side so the row above the hand
    // box stays visually balanced.
    return Padding(
      padding: const EdgeInsets.only(right: 12, bottom: 4),
      child: Align(
        alignment: Alignment.centerRight,
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
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Text(
            L10n.of(context).gameSmallTichuDeclare,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ),
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
              Flexible(
                child: Text(
                  selectedCard != null ? L10n.of(context).gameSelectRecipient : L10n.of(context).gameSelectExchangeCard(assignedCount),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
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
            Flexible(
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isAssigned ? const Color(0xFF3A5A40) : const Color(0xFF5A4038),
                ),
                overflow: TextOverflow.ellipsis,
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
    String? photoUrl,
    bool isBot = false,
    double avatarSize = 26,
    bool avatarBeside = false,
  }) {
    final maxLen = _maxNameLen;
    final displayName = name.length > maxLen ? '${name.substring(0, maxLen)}..' : name;
    final s = _s;
    // Only built when there is something to show, so photo-less, non-bot
    // players keep the exact original nameplate layout.
    final avatar = (photoUrl != null || isBot)
        ? ProfileAvatar(
            photoUrl: photoUrl,
            size: avatarSize * s,
            fallback: isBot
                ? BotAvatar(size: avatarSize * s, name: name)
                : SizedBox(width: avatarSize * s, height: avatarSize * s),
          )
        : null;
    final plate = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The avatar goes above the pill by default. `avatarBeside` puts it to
        // the left instead: the partner seat sits at the top of the board where
        // vertical space is what everything else is competing for, and width is
        // free — so there it can be half again as big without costing the board
        // a single pixel.
        if (avatar != null && !avatarBeside)
          Padding(padding: EdgeInsets.only(bottom: 3 * s), child: avatar),
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
    if (avatar == null || !avatarBeside) return plate;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        avatar,
        SizedBox(width: 6 * s),
        plate,
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

