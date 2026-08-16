import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/game_service.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/seat_chat_bubble.dart';
import '../widgets/bot_avatar.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/player_profile_dialog.dart';
import '../services/session_service.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../widgets/playing_card.dart';
import '../widgets/connection_overlay.dart';
import '../widgets/draggable_chat_panel.dart';
import '../widgets/spectator_controls.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n_helpers.dart';
import '../widgets/mid_game_join.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  /// The last thing each player said, shown briefly over their seat.
  late final SeatChatBubbles _seatChat = SeatChatBubbles(() {
    if (mounted) setState(() {});
  });

  // Responsive scale factor (updated every build)
  double _s = 1.0; // scale factor based on screen width
  double _ts = 1.0; // gentler scale for text and chrome — see build()

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
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
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
    _seatChat.dispose();
    _chatController.dispose();
    _chatScrollController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _updateCountdown() {
    if (!mounted) return;
    final state =
        _gameService?.gameState ?? context.read<GameService>().gameState;
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
        '2': 2,
        '3': 3,
        '4': 4,
        '5': 5,
        '6': 6,
        '7': 7,
        '8': 8,
        '9': 9,
        '10': 10,
        'J': 11,
        'Q': 12,
        'K': 13,
        'A': 14,
      };
      final values = cards.map((c) => rankValues[c.split('_')[1]] ?? 0).toList()
        ..sort();
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
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

    final shortestSide = screenSize.shortestSide;
    // The ceiling used to be a flat 1.0: the board is designed for a 400pt
    // phone and there was never a screen worth growing into. A desktop browser
    // is, and at 1.0 the cards sit tiny in the middle of a large window. Phones
    // and tablets keep the old ceiling — this is not the place to change how
    // the shipped app looks.
    _s = (shortestSide / 400).clamp(0.72, kIsWeb ? 1.3 : 1.0);
    // Text and chrome grow at half the rate of the board. Scaling everything
    // by _s turned a desktop window into a magnified phone — readable, but the
    // labels, icons and buttons all looked oversized next to the cards, which
    // are the only thing that actually needed the room. Half the excess keeps
    // text comfortable without that zoomed-in feel.
    //
    // Web only. Off the web _s also goes BELOW 1 (down to 0.72 on a small
    // phone), and halving that excess would make text LARGER than the shipped
    // app draws it — 0.80 becomes 0.90 on a 320pt screen, a 12.5% jump in
    // every label on a layout that was tuned at the smaller size. The app must
    // render exactly as it does today.
    _ts = kIsWeb ? 1 + (_s - 1) * 0.5 : _s;
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
              bottom: true,
              child: Consumer<GameService>(
                builder: (context, game, _) {
                  if (session.isRestoring || _waitingForRoomRecovery) {
                    final l10n = L10n.of(context);
                    return _buildRecoveryLoading(
                      title: session.isRestoring
                          ? l10n.gameRestoringGame
                          : l10n.gameCheckingState,
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
                  if (_prevPhase == 'card_exchange' &&
                      state.phase != 'card_exchange') {
                    _maybeShowExchangeSummary(state);
                  }
                  // Delay round end dialog so players can see the last card played
                  if (_prevPhase != 'round_end' &&
                      _prevPhase != 'game_end' &&
                      (state.phase == 'round_end' ||
                          state.phase == 'game_end')) {
                    _roundEndReady = false;
                    Future.delayed(const Duration(seconds: 1), () {
                      if (mounted) setState(() => _roundEndReady = true);
                    });
                  } else if (state.phase != 'round_end' &&
                      state.phase != 'game_end') {
                    _roundEndReady = false;
                  }
                  _prevPhase = state.phase;

                  return Stack(
                    children: [
                      if (_tichuOverlayColor(state) != null)
                        Positioned.fill(
                          child: Container(color: _tichuOverlayColor(state)),
                        ),
                      _buildPortraitGameLayout(state, game),

                      // Dialogs/Panels
                      // (Large Tichu is NOT here — it rides in the bottom
                      // column with the exchange panel so it sits on the hand.)
                      if (state.dragonPending) _buildDragonDialog(state, game),

                      if (state.needsToCallRank && !_birdCallDialogOpen)
                        _buildCallRankDialog(game),

                      if (_roundEndReady &&
                          (state.phase == 'round_end' ||
                              state.phase == 'game_end'))
                        _buildRoundEndDialog(state, game),

                      // Timeout banner
                      if (game.timeoutPlayerName != null)
                        _buildTimeoutBanner(game.timeoutPlayerName!),

                      // Desertion banner
                      if (game.desertedPlayerName != null)
                        _buildDesertionBanner(
                          game.desertedPlayerName!,
                          game.desertedReason ?? 'leave',
                        ),

                      // Error message banner
                      if (game.errorMessage != null)
                        _buildErrorBanner(game.errorMessage!),

                      // Spectator card view requests
                      if (game.hasIncomingCardViewRequests)
                        _buildCardViewRequestPopup(game),

                      // Viewers panel popup
                      if (_viewersOpen)
                        _buildViewersPanel(
                          game,
                          topOffset: _moreOpen ? 150 : 66,
                        ),

                      // Sound panel
                      if (_soundPanelOpen) _buildSoundPanel(game),

                      // More menu
                      if (_moreOpen) _buildMoreMenu(game),

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
    final timerBadge = _buildTimerBadge(state);
    return Stack(
      children: [
        Column(
          children: [
            _buildTopBar(state, game),
            Expanded(
              // Reserve a constant bottom slot equal to the typical max
              // hand-area height (full 14-card hand + name row + action
              // buttons ≈ 220–240). This pushes the trick board's vertical
              // center above the bottom overlay so cards don't sit on top
              // of it. Below 14 cards the hand shrinks under the reserve
              // and the board still doesn't move.
              child: Padding(
                padding: EdgeInsets.only(bottom: _handReserveHeight(context)),
                child: _buildOpponentsRing(state, game),
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
              // Same slot as the exchange panel — the two never show at once,
              // and both ask you to decide about the cards right below them.
              // It used to be a free-floating Positioned at a hand-height
              // guess, which drifted away from the hand as the board scaled.
              if (state.phase == 'large_tichu_phase' &&
                  !state.largeTichuResponded)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildLargeTichuDialog(game),
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
          Positioned(top: 48, left: 12, child: timerBadge),
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

  bool _canShowSmallTichu(GameStateData state) {
    return state.canDeclareSmallTichu &&
        state.phase != 'card_exchange' &&
        !state.players.any((p) => p.position == 'self' && p.hasLargeTichu);
  }

  Widget _buildMenuButton(GameService game) {
    return SpectatorActionButton(
      icon: Icons.exit_to_app,
      active: false,
      iconColor: const Color(0xFFE53935),
      onTap: () => _showLeaveGameDialog(game),
    );
  }

  Widget _buildChatButton(GameService game) {
    final totalMessages = game.chatMessages
        .where((m) => !game.isBlocked(m['sender'] as String? ?? ''))
        .length;

    // Initialize on first build so existing messages don't show as unread
    if (_lastSeenMessageCount < 0) {
      _lastSeenMessageCount = totalMessages;
    }
    // Update seen count when chat is open
    if (_chatOpen) {
      _lastSeenMessageCount = totalMessages;
    }
    final unreadCount = totalMessages - _lastSeenMessageCount;

    return SpectatorActionButton(
      icon: Icons.chat_bubble_outline_rounded,
      active: _chatOpen,
      badgeCount: unreadCount.clamp(0, 99),
      onTap: () => setState(() {
        _chatOpen = !_chatOpen;
        if (_chatOpen) {
          _lastSeenMessageCount = totalMessages;
          _scrollChatToBottom();
        }
      }),
    );
  }

  Widget _buildSoundButton(GameService game) {
    return SpectatorActionButton(
      icon: game.sfxVolume <= 0.01 ? Icons.volume_off : Icons.volume_up,
      active: _soundPanelOpen,
      onTap: () => setState(() => _soundPanelOpen = !_soundPanelOpen),
    );
  }

  Widget _buildMoreButton(GameService game) {
    return SpectatorActionButton(
      icon: Icons.more_horiz,
      active: _moreOpen,
      onTap: () => setState(() {
        _moreOpen = !_moreOpen;
        // Sub-panels (sound, viewers) are conceptually "inside" the
        // more menu — close them whenever more is toggled in either
        // direction so they don't stay floating after the parent menu
        // disappears.
        _soundPanelOpen = false;
        _viewersOpen = false;
      }),
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
            //
            // Sized by its contents. It was a flat 150, then 150 * the text
            // scale, and neither had anything to do with how wide three
            // buttons and two gaps actually are.
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
              mainAxisSize: MainAxisSize.min,
              spacing: 6,
              children: [
                _buildSpectatorButton(game),
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
      // The shared panel. Four screens carried a byte-identical copy of this
      // container, slider and title — and Tichu's copy had lost the spectator
      // title branch somewhere along the way.
      child: SpectatorSoundPanel(game: game, width: 180),
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

  Widget _buildChatBubble(
    String sender,
    String message,
    bool isMe,
    GameService game,
  ) {
    return ChatBubble(
      sender: sender,
      message: message,
      isMe: isMe,
      game: game,
      onTap: sender.isEmpty
          ? null
          : () => _showPlayerProfileDialog(sender, game),
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

  void _showPlayerProfileDialog(
    String nickname,
    GameService game, {
    bool isBot = false,
  }) {
    showPlayerProfileDialog(
      context,
      nickname,
      game,
      initialGame: 'tichu',
      subtitle: L10n.of(context).gamePlayerProfile,
      isBot: isBot,
      // Out of the way when the round ends, so the result screen isn't hidden
      // behind it.
      dismissWhen: (g) =>
          g.gameState == null || g.gameState!.phase == 'game_end',
    );
  }

  void _showLeaveGameDialog(GameService game) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.of(context).gameLeaveTitle),
        // In a mid-game-join room leaving does not end the match — a bot
        // takes the seat — but it is still recorded, so the warning has to say
        // which of the two is about to happen.
        content: Text(
          game.canLeaveInProgress
              ? L10n.of(
                  context,
                ).midLeaveConfirmBody(kMidGameJoinCooldownMinutes)
              : L10n.of(context).gameLeaveConfirm,
        ),
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
              blurRadius: 8 * _s,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFCC4444)),
            SizedBox(width: 8 * _s),
            Expanded(
              child: Text(
                displayMessage,
                style: TextStyle(
                  color: Color(0xFFCC4444),
                  fontWeight: FontWeight.bold,
                  fontSize: 14 * _ts,
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
              blurRadius: 8 * _s,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.timer_off, color: Color(0xFFE65100)),
            SizedBox(width: 8 * _s),
            Expanded(
              child: Text(
                L10n.of(context).gameTimeout(playerName),
                style: TextStyle(
                  color: Color(0xFFE65100),
                  fontWeight: FontWeight.bold,
                  fontSize: 14 * _ts,
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
              blurRadius: 8 * _s,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.person_off, color: Color(0xFFCC4444)),
            SizedBox(width: 8 * _s),
            Expanded(
              child: Text(
                reason == 'timeout'
                    ? L10n.of(context).gameDesertionTimeout(playerName)
                    : L10n.of(context).gameDesertionLeave(playerName),
                style: TextStyle(
                  color: Color(0xFFCC4444),
                  fontWeight: FontWeight.bold,
                  fontSize: 14 * _ts,
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
    final spectatorNickname =
        request['spectatorNickname'] ?? L10n.of(context).gameSpectator;
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
                    onPressed: () =>
                        game.respondCardViewRequest(spectatorId, false),
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
                    onPressed: () =>
                        game.respondCardViewRequest(spectatorId, true),
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
    // Plain, the way Skull King and Mighty have it. It used to carry a green
    // eye in its own corner for "someone can see my hand" and a long-press to
    // reach the card-view policy — both from when it sat alone in the top bar.
    // It now sits next to the visibility button in the more menu, which is
    // where the policy lives and which colours itself when there are viewers.
    return SpectatorActionButton(
      icon: Icons.people_alt,
      active: false,
      badgeCount: game.spectators.length,
      onTap: () {
        setState(() => _moreOpen = false);
        showSpectatorListDialog(context, game);
      },
    );
  }

  Widget _buildViewersButton(GameService game) {
    final hasViewers = game.cardViewers.isNotEmpty;
    return SpectatorActionButton(
      icon: Icons.visibility,
      active: _viewersOpen,
      badgeCount: game.cardViewers.length,
      // Blue while someone can see the hand — the same signal Skull King's
      // gives, and what the green corner dot on the spectator button used to.
      iconColor: hasViewers ? const Color(0xFF6A9BD1) : null,
      onTap: () => setState(() => _viewersOpen = !_viewersOpen),
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
                const Icon(
                  Icons.visibility,
                  size: 16,
                  color: Color(0xFF5A4038),
                ),
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

  // 스컬킹 4인 게임 스크린과 동일한 링 레이아웃.
  // 파트너/좌/우 세 좌석을 상단 아크 [200°, 270°, 340°] 에 배치하고,
  // 중앙 트릭 영역은 별도 Align 으로 얹는다. 사진 자체가 좌석의 가장자리 —
  // 배경 상자/패딩 없음. (참고: sk_game_screen.dart _buildScoreboard.)
  Widget _buildOpponentsRing(GameStateData state, GameService game) {
    _seatChat.consume(game);
    final partner = _firstWhereOrNull(
      state.players,
      (p) => p.position == 'partner',
    );
    final left = _firstWhereOrNull(state.players, (p) => p.position == 'left');
    final right = _firstWhereOrNull(
      state.players,
      (p) => p.position == 'right',
    );
    // 좌/우는 sin +0.5 (150°/30°) — self 가 차지한 하단과 파트너 사이에서
    // 살짝 아래쪽으로 치우쳐 앉는다.
    final positions = <(Player?, String, double)>[
      (left, 'left', 150.0),
      (partner, 'partner', 270.0),
      (right, 'right', 30.0),
    ];

    const seatWidthBase = 108.0;
    const seatHeightBase = 132.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final boardScale = math
            .min(width / 360.0, height / 400.0)
            .clamp(0.78, 1.45);
        final seatWidth = seatWidthBase * boardScale;
        final seatHeight = seatHeightBase * boardScale;
        final centerX = width / 2;
        final centerY = height * 0.46;
        final maxSeatRadiusX = math.max(0.0, centerX - seatWidth / 2 - 10);
        final seatRadiusX = math.min(
          width * 0.42,
          math.min(width >= 700 ? 233.0 : 188.0, maxSeatRadiusX),
        );
        final maxSeatRadiusY = math.max(0.0, centerY - seatHeight / 2 - 6);
        final seatRadiusY = math.min(
          height * 0.34,
          math.min(height >= 700 ? 220.0 : 196.0, maxSeatRadiusY),
        );

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // 좌석 먼저 — 트릭이 프로필 위로 얹히도록 뒤에 그린다 (관전과 동일).
            for (int i = 0; i < positions.length; i++) ...[
              () {
                final (p, key, angleDeg) = positions[i];
                final angle = angleDeg * math.pi / 180;
                // 좌/우 좌석은 X 를 각도 cos 이 아니라 항상 가장자리(±1)로
                // 고정. sin(150°/30°)=0.87 이라 cos 이 0.87로 안쪽으로 들어와
                // 보이던 문제를 없앤다. 세로만 sin 으로 조절.
                final horizontalDir = key == 'partner'
                    ? math.cos(angle)
                    : (key == 'left' ? -1.0 : 1.0);
                final seatLeft =
                    centerX + seatRadiusX * horizontalDir - seatWidth / 2;
                final seatTop =
                    centerY + seatRadiusY * math.sin(angle) - seatHeight / 2;
                return Positioned(
                  left: seatLeft,
                  top: seatTop,
                  width: seatWidth,
                  height: seatHeight,
                  child: _buildOpponentSeat(state, game, p, positionKey: key),
                );
              }(),
            ],
            // 중앙 트릭: Stack 마지막에 얹어 좌석 프로필 위로 그려진다.
            // Align 대신 Positioned(top) — Align 은 자식 높이가 커지면 top 이
            // 위로 밀려 "카드 표시할 때 트릭박스가 오히려 위로 자라는" 것처럼
            // 보인다. top 을 고정하면 카드는 항상 아래로만 자란다.
            Positioned(
              left: 0,
              right: 0,
              top: height * 0.52,
              child: IgnorePointer(
                child: Center(child: _buildCenterArea(state, game)),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildOpponentSeat(
    GameStateData state,
    GameService game,
    Player? p, {
    required String positionKey,
  }) {
    final isTurn = p != null && p.id == state.currentPlayer;
    final displayName =
        p?.name ??
        (positionKey == 'partner'
            ? L10n.of(context).gamePartner
            : positionKey == 'left'
            ? L10n.of(context).gameLeftPlayer
            : L10n.of(context).gameRightPlayer);
    final teamLabel = _teamForPosition(state, positionKey);
    final isMyTeam = positionKey == 'partner';
    final badge = _tichuBadgeForPlayer(p);
    final exchangeDone =
        state.phase == 'card_exchange' && (p?.hasExchanged ?? false);

    return GestureDetector(
      onTap: p != null
          ? () => _showPlayerProfileDialog(
              p.name,
              game,
              isBot: p.id.startsWith('bot_'),
            )
          : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final seatW = constraints.maxWidth;
          final seatH = constraints.maxHeight;
          final compact = seatH <= 108 || seatW <= 96;
          final seatScale = (seatW / 116.0).clamp(0.9, 1.5);
          // 좌석 높이의 절반 정도가 사진. SK 의 0.58 규칙과 동일 톤.
          final avatarDiameter = kIsWeb
              ? math
                    .min(seatH * 0.55, seatW * 0.7)
                    .clamp(52.0, 160.0)
                    .toDouble()
              : (seatH * 0.55).clamp(50.0, 108.0).toDouble();
          final nameFontSize = (compact ? 11.5 : 13.0) * seatScale;
          final contentWidth = math.max(
            avatarDiameter + 6,
            math.min((seatW - 8) * 0.92, avatarDiameter + 28),
          );

          return Align(
            alignment: Alignment.topCenter,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: contentWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if ((p?.timeoutCount ?? 0) > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          '⏱ ${p!.timeoutCount}/3',
                          style: TextStyle(
                            color: const Color(0xFFE65100),
                            fontSize: compact ? 9 : 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ProfileAvatar(
                      photoUrl: game.blockedUsers.contains(p?.name ?? '')
                          ? null
                          : game.resolvePhotoUrl(p?.photoUrl),
                      size: avatarDiameter,
                      blocked: game.blockedUsers.contains(p?.name ?? ''),
                      // 라지 티츄(빨강) / 스몰 티츄(파랑) > 현재 턴(노랑).
                      // 티츄 선언은 그 판의 결정적 신호라 턴보다 우선 노출.
                      border: (p?.hasLargeTichu ?? false)
                          ? Border.all(
                              color: const Color(0xFFD24B4B),
                              width: 2.0,
                            )
                          : (p?.hasSmallTichu ?? false)
                          ? Border.all(
                              color: const Color(0xFF4A90D9),
                              width: 2.0,
                            )
                          : isTurn
                          ? Border.all(
                              color: const Color(0xFFE6C86A),
                              width: 1.5,
                            )
                          : null,
                      fallback: (p?.isBot ?? false)
                          ? BotAvatar(size: avatarDiameter, name: p!.name)
                          : DefaultAvatar(size: avatarDiameter),
                    ),
                    SizedBox(height: 3 * _s),
                    if (badge != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: badge,
                      ),
                    // 이름+팀+연결상태를 SK 톤 pill 로. 현재 턴이면 노란 배경.
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: EdgeInsets.symmetric(
                        horizontal: 8 * _s,
                        vertical: 3 * _s,
                      ),
                      decoration: BoxDecoration(
                        color: isTurn
                            ? const Color(0xFFFFF2B3)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: isTurn
                            ? Border.all(color: const Color(0xFFE6C86A))
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(right: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 3,
                              vertical: 1,
                            ),
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
                                fontSize: 8 * _ts,
                                fontWeight: FontWeight.bold,
                                color: isMyTeam
                                    ? const Color(0xFF4A90D9)
                                    : const Color(0xFFD24B4B),
                              ),
                            ),
                          ),
                          if (!(p?.connected ?? true))
                            Padding(
                              padding: const EdgeInsets.only(right: 3),
                              child: Icon(
                                Icons.wifi_off,
                                size: 11,
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
                                color: (p?.connected ?? true)
                                    ? const Color(0xFF5A4038)
                                    : Colors.grey,
                                fontSize: nameFontSize,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (exchangeDone)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Icon(
                                Icons.check_circle,
                                size: 12,
                                color: const Color(0xFF3A8F52),
                              ),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(height: 3 * _s),
                    _buildCompactHandBacks(p?.cardCount ?? 0, scale: _s),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCenterArea(GameStateData state, GameService game) {
    // 중앙 트릭 영역은 배경 상자 없이 내용만 얹는다 (Mighty/SK/LL 톤).
    return Center(
      child: Container(
        width: 220 * _s,
        padding: EdgeInsets.symmetric(horizontal: 8 * _s, vertical: 6 * _s),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Phase caption, but not while playing: the turn line directly
            // below already says whose turn it is, and "게임 진행 중" tells the
            // table something it can see. The other phases (dealing, exchange,
            // round end) are worth naming.
            if (state.phase != 'playing')
              Text(
                _getPhaseName(state.phase),
                style: TextStyle(
                  fontSize: 15 * _ts,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF5A4038),
                ),
                textAlign: TextAlign.center,
              ),
            if (state.phase == 'playing') ...[
              SizedBox(height: 3 * _s),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      state.isMyTurn
                          ? L10n.of(context).gameMyTurn
                          : L10n.of(
                              context,
                            ).gamePlayerTurn(_getCurrentPlayerName(state)),
                      style: TextStyle(
                        fontSize: 17 * _ts,
                        color: state.isMyTurn
                            ? const Color(0xFFE6A800)
                            : const Color(0xFF5A4038),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  // 트릭박스 안 턴 표시 옆에 남은 시간을 함께 붙여 눈이 두 군데를
                  // 왔다갔다 하지 않게. 좌상단 타이머 뱃지는 그대로 유지 —
                  // 이건 트릭을 볼 때 자연스러운 위치에서 한 번 더 알려주는 용도.
                  if (_remainingSeconds > 0) ...[
                    SizedBox(width: 6 * _s),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 6 * _s,
                        vertical: 2 * _s,
                      ),
                      decoration: BoxDecoration(
                        color: _remainingSeconds <= 10
                            ? const Color(0xFFFFE4E4)
                            : const Color(0xFFF5EEE8),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _remainingSeconds <= 10
                              ? const Color(0xFFFF6B6B)
                              : const Color(0xFFD8CCC4),
                          width: _remainingSeconds <= 10 ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.schedule,
                            size: 13 * _ts,
                            color: _remainingSeconds <= 10
                                ? const Color(0xFFCC4444)
                                : const Color(0xFF6A5A52),
                          ),
                          SizedBox(width: 3 * _s),
                          Text(
                            '${_remainingSeconds}s',
                            style: TextStyle(
                              fontSize: 13 * _ts,
                              fontWeight: FontWeight.bold,
                              color: _remainingSeconds <= 10
                                  ? const Color(0xFFCC4444)
                                  : const Color(0xFF5A4038),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],

            // Call rank display
            if (state.callRank != null && state.callRank!.isNotEmpty) ...[
              SizedBox(height: 4 * _s),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0x33FF4444),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFFF4444),
                    width: 1.5 * _s,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('🐦', style: TextStyle(fontSize: 14 * _ts)),
                    SizedBox(width: 4 * _s),
                    Text(
                      L10n.of(context).gameCall(state.callRank!),
                      style: TextStyle(
                        fontSize: 16 * _ts,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFF4444),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            SizedBox(height: 4 * _s),

            if (game.dogPlayActive)
              _buildDogPlayedBanner(game.dogPlayPlayerName),

            if (game.dogPlayActive) SizedBox(height: 4 * _s),

            // Latest trick only
            if (state.currentTrick.isNotEmpty)
              _buildLatestTrick(state)
            else if (state.lastTrick.isNotEmpty &&
                (state.phase == 'round_end' || state.phase == 'game_end'))
              _buildLatestTrick(state, useLastTrick: true),
          ],
        ),
      ),
    );
  }

  Widget? _buildTimerBadge(GameStateData state) {
    if (_remainingSeconds <= 0) return null;
    final l10n = L10n.of(context);
    final currentPlayerName = _getCurrentPlayerName(state);
    final turnLabel = state.isMyTurn
        ? l10n.gameMyTurnShort
        : l10n.gamePlayerWaiting(currentPlayerName);
    final timerFontSize = 13 * _s;
    final timerIconSize = 14 * _s;
    const timerPadding = EdgeInsets.symmetric(horizontal: 10, vertical: 5);
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
            // 점수 pill 이 이미 leaderboard 아이콘을 달고 탭 → 히스토리를 열어주므로
            // 별도의 leaderboard 버튼은 중복. chat · more 만 노출.
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
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
        margin: compact ? EdgeInsets.zero : EdgeInsets.only(bottom: 2 * _s),
        padding: EdgeInsets.symmetric(
          horizontal: horizontal,
          vertical: vertical,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F4F0),
          borderRadius: BorderRadius.circular(8 * _s),
          border: Border.all(color: const Color(0xFFE6DCE8)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'A',
              style: TextStyle(
                fontSize: textFont,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF5A4038),
              ),
            ),
            Text(
              ':$aces',
              style: TextStyle(
                fontSize: textFont,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF8A7A6A),
              ),
            ),
            SizedBox(width: spacing),
            Text(
              'K',
              style: TextStyle(
                fontSize: textFont,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF5A4038),
              ),
            ),
            Text(
              ':$kings',
              style: TextStyle(
                fontSize: textFont,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF8A7A6A),
              ),
            ),
            SizedBox(width: spacing),
            Text('\u{1F409}', style: TextStyle(fontSize: iconFont)),
            Text(
              dragon ? '\u25CB' : '\u2715',
              style: TextStyle(
                fontSize: 12 * _ts,
                color: dragon
                    ? const Color(0xFF4A90D9)
                    : const Color(0xFFCCC0B8),
              ),
            ),
            SizedBox(width: compact ? 4 * _s : 6 * _s),
            Text('\u{1F426}', style: TextStyle(fontSize: iconFont)),
            Text(
              phoenix ? '\u25CB' : '\u2715',
              style: TextStyle(
                fontSize: 12 * _ts,
                color: phoenix
                    ? const Color(0xFFD4A030)
                    : const Color(0xFFCCC0B8),
              ),
            ),
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
                fontSize: 10 * _ts,
                fontWeight: FontWeight.bold,
                color: myLeading ? myColor : const Color(0xFF8A7A72),
              ),
            ),
            SizedBox(width: 3 * _s),
            Text(
              '$myScore',
              style: TextStyle(
                fontSize: 14 * _ts,
                fontWeight: FontWeight.bold,
                color: myLeading ? myColor : const Color(0xFF5A4038),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 6 * _s),
              child: Text(
                ':',
                style: TextStyle(
                  fontSize: 14 * _ts,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF8A7A72),
                ),
              ),
            ),
            Text(
              '$enemyScore',
              style: TextStyle(
                fontSize: 14 * _ts,
                fontWeight: FontWeight.bold,
                color: enemyLeading ? enemyColor : const Color(0xFF5A4038),
              ),
            ),
            SizedBox(width: 3 * _s),
            Text(
              myTeam == 'A' ? 'B' : 'A',
              style: TextStyle(
                fontSize: 10 * _ts,
                fontWeight: FontWeight.bold,
                color: enemyLeading ? enemyColor : const Color(0xFF8A7A72),
              ),
            ),
            // The finish line moved into the score-history dialog: next to the
            // running score it read as a fraction ("25 / 1000") rather than a
            // goal, and this bar is the one thing always on screen.
            SizedBox(width: 4 * _s),
            Icon(
              Icons.leaderboard_outlined,
              size: 12 * _s,
              color: const Color(0xFF8A7A72),
            ),
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
    // The Dog gets its own banner instead of going through the normal trick
    // pile, and it kept a hardcoded 32x45 card while every other played card is
    // 44x61 * _s — so on a scaled-up board the Dog came out at under half size.
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8 * _s, vertical: 6 * _s),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F5),
        borderRadius: BorderRadius.circular(12 * _s),
        border: Border.all(color: const Color(0xFFE6DCE8)),
      ),
      child: Column(
        children: [
          Text(
            playerName.isNotEmpty
                ? L10n.of(context).gameDogPlayedBy(
                    playerName.length > 8
                        ? '${playerName.substring(0, 8)}..'
                        : playerName,
                  )
                : L10n.of(context).gameDogPlayed,
            style: TextStyle(
              fontSize: 11 * _ts,
              color: const Color(0xFF8A7A72),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 4 * _s),
          PlayingCard(
            cardId: 'special_dog',
            width: 44 * _s,
            height: 61 * _s,
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
    // 팀 색으로 이름/뱃지만 물들이고, 배경 상자와 테두리는 없앤다 —
    // 다른 게임(SK/Mighty/LL) 과 동일한 톤. 낸 카드가 이미 트릭 자체다.
    final isMyTeam = state.players.any(
      (p) =>
          (p.position == 'self' || p.position == 'partner') &&
          p.id == lastPlay.playerId,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: lastPlay.playerName.length > 8
                      ? '${lastPlay.playerName.substring(0, 8)}..'
                      : lastPlay.playerName,
                  style: TextStyle(
                    fontSize: 14 * _ts,
                    fontWeight: FontWeight.bold,
                    color: isMyTeam
                        ? const Color(0xFF4A90D9)
                        : const Color(0xFFD94A5A),
                  ),
                ),
                TextSpan(
                  text: L10n.of(context).gamePlayedCards,
                  style: TextStyle(
                    fontSize: 12 * _ts,
                    color: Color(0xFF8A7A72),
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 4 * _s),
          _buildOverlappedTrick(lastPlay.cards, lastPlay: lastPlay),
        ],
      ),
    );
  }

  Widget _buildOverlappedTrick(List<String> cards, {TrickPlay? lastPlay}) {
    // 관전 트릭과 동일 톤: 44×62, minOverlap 24, maxOverlap 34.
    // 7장 이상은 두 줄로, 4장 이상은 살짝 겹치도록 아래 LayoutBuilder 에서 처리.
    final double baseCardW = 44 * _s;
    final double baseCardH = 62 * _s;
    var cardW = baseCardW;
    var cardH = baseCardH;
    final double minOverlap = 24 * _s;
    final double maxOverlap = 34 * _s;

    // Phoenix-as-single → overlay a chip on the card showing what rank
    // it beat (e.g. "↑Q"), so the table can read the play at a glance.
    final isPhoenixSingleTrick =
        lastPlay != null &&
        lastPlay.combo == 'single' &&
        cards.length == 1 &&
        cards[0] == 'special_phoenix' &&
        lastPlay.comboValue > 1;
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
                style: TextStyle(
                  fontSize: 9 * _ts,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF5A4038),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // 3장 이하만 나란히, 4장부터 overlap 경로로 태워 살짝 겹친다.
    if (cards.length <= 3) {
      return Wrap(
        alignment: WrapAlignment.center,
        spacing: 3,
        children: cards.map(playingCard).toList(),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth - 16; // padding

        // Shrink the cards rather than spill out of the box. Even at the
        // tightest overlap a long straight needs more width than the trick
        // panel has once the board is scaled up, and the overflow drew over
        // the seats around it. Proportions are kept, and the floor stops a
        // seven-card play from turning into confetti.
        cardW = baseCardW;
        cardH = baseCardH;
        if (cards.length > 1) {
          final needed = cardW + minOverlap * (cards.length - 1);
          if (needed > availableWidth) {
            final fit = (availableWidth / needed).clamp(0.62, 1.0);
            cardW *= fit;
            cardH *= fit;
          }
        }

        // Calculate overlap to fit all cards in one row
        final neededOverlap = cards.length > 1
            ? (availableWidth - cardW) / (cards.length - 1)
            : availableWidth;
        // 7장 이상은 한 줄에 밀어넣지 말고 두 줄로. 관전 트릭과 동일 규칙.
        final wantTwoRows = cards.length >= 7;

        if (!wantTwoRows && neededOverlap >= minOverlap) {
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
                    Positioned(left: i * overlap, child: playingCard(cards[i])),
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
              ? ((availableWidth - cardW) / (rowCards.length - 1)).clamp(
                  minOverlap,
                  maxOverlap,
                )
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
            SizedBox(height: 4 * _s),
            buildRow(row2),
          ],
        );
      },
    );
  }

  /// How much of the screen the two card rows may occupy.
  ///
  /// The hand used to be sized from available width alone. On a phone that is
  /// self-limiting — there simply isn't much width — but a desktop window has
  /// plenty, so the cards grew to their scaled maximum and left the table with
  /// what was over.
  static const double _handHeightShare = 0.26;

  /// Vertical space the board reserves for the hand panel: the rows, plus the
  /// name/status line and padding drawn around them.
  double _handReserveHeight(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    return (screenHeight * _handHeightShare + 76 * _s).clamp(
      180.0,
      screenHeight * 0.42,
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
            blurRadius: 10 * _s,
            offset: const Offset(0, -4),
          ),
        ],
        border: isMyTurn
            ? const Border(
                top: BorderSide(color: Color(0xFFFFCA28), width: 2.5),
              )
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
                    width: 0.5 * _s,
                  ),
                ),
                child: Text(
                  state.myTeam,
                  style: TextStyle(
                    fontSize: 8 * _ts,
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
                    fontSize: 12 * _ts,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF5A4038),
                  ),
                ),
              ),
              if (isMyTurn) ...[
                SizedBox(width: 6 * _s),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 8 * _s,
                    vertical: 3 * _s,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF2B3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE6C86A)),
                  ),
                  child: Text(
                    L10n.of(context).gameMyTurn,
                    style: TextStyle(
                      fontSize: 11 * _ts,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF5A4038),
                    ),
                  ),
                ),
              ],
              if (_tichuBadgeForSelf(state) != null) ...[
                SizedBox(width: 8 * _s),
                _tichuBadgeForSelf(state)!,
              ],
              if (game.myTimeoutCount > 0) ...[
                SizedBox(width: 8 * _s),
                GestureDetector(
                  onTap: () => game.resetTimeout(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
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
                          style: TextStyle(
                            fontSize: 12 * _ts,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFE65100),
                          ),
                        ),
                        SizedBox(width: 4 * _s),
                        Text(
                          L10n.of(context).gameNotAfk,
                          style: TextStyle(
                            fontSize: 11 * _ts,
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
          SizedBox(height: 8 * _s),

          // My hand - two rows (split in half)
          Padding(
            padding: EdgeInsets.symmetric(
              vertical: state.myCards.length >= 13 ? 6 : 10,
            ),
            child: _buildHandRows(state),
          ),
          SizedBox(height: 8 * _s),

          // Action buttons (stable layout)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed:
                    (state.phase == 'playing' &&
                        _selectedCards.isNotEmpty &&
                        !state.dragonPending &&
                        (state.isMyTurn ||
                            _isBombCombo(_selectedCards.toList())))
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
              SizedBox(width: 12 * _s),
              ElevatedButton(
                onPressed:
                    (state.phase == 'playing' &&
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
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 24 * _s),
      padding: EdgeInsets.symmetric(horizontal: 16 * _s, vertical: 12 * _s),
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
          Flexible(
            child: Text(
              L10n.of(context).gameLargeTichuQuestion,
              style: TextStyle(fontSize: 16 * _ts, fontWeight: FontWeight.bold),
            ),
          ),
          SizedBox(width: 12 * _s),
          ElevatedButton(
            onPressed: () => game.declareLargeTichu(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              textStyle: TextStyle(fontSize: 14 * _ts),
              padding: EdgeInsets.symmetric(
                horizontal: 16 * _s,
                vertical: 8 * _s,
              ),
            ),
            child: Text(L10n.of(context).gameDeclare),
          ),
          SizedBox(width: 12 * _s),
          OutlinedButton(
            onPressed: () => game.passLargeTichu(),
            style: OutlinedButton.styleFrom(
              textStyle: TextStyle(fontSize: 14 * _ts),
              padding: EdgeInsets.symmetric(
                horizontal: 16 * _s,
                vertical: 8 * _s,
              ),
            ),
            child: Text(L10n.of(context).gamePass),
          ),
        ],
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
      _trickPlayLog.add(
        _formatPlayLine(play, isBirdPlay ? state.callRank : null),
      );
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

  // The trick log was the last Korean left in the game itself: an English or
  // German player read their own moves back as "드래곤", "페어", "폭탄(4)".
  // Every other game screen had been translated; this one had not.
  String _formatPlayLine(TrickPlay play, String? callRank) {
    final l10n = L10n.of(context);
    final name = play.playerName.length > 6
        ? '${play.playerName.substring(0, 6)}…'
        : play.playerName;
    final desc = _comboShortDesc(play);
    if (callRank != null && callRank.isNotEmpty) {
      return '$name: $desc - ${l10n.trickCallSuffix(callRank)}';
    }
    return '$name: $desc';
  }

  String _comboShortDesc(TrickPlay play) {
    final l10n = L10n.of(context);
    final cards = play.cards;
    if (cards.length == 1) {
      final cid = cards[0];
      if (cid == 'special_phoenix' && play.comboValue > 1) {
        return l10n.trickPhoenixOver(_phoenixBeatLabel(play.comboValue));
      }
      if (cid == 'special_dragon') return l10n.trickCardDragon;
      if (cid == 'special_phoenix') return l10n.trickCardPhoenix;
      if (cid == 'special_bird') return l10n.trickCardMahjong;
      if (cid == 'special_dog') return l10n.trickCardDog;
      return _rankFromCardId(cid);
    }
    switch (play.combo) {
      case 'pair':
        return l10n.trickPair(_rankFromCardId(cards[0]));
      case 'triple':
        return l10n.trickTriple(_rankFromCardId(cards[0]));
      case 'full_house':
        return l10n.trickFullHouse(_rankFromCardId(cards[0]));
      case 'straight':
        return l10n.trickStraight(
          _rankLabelFromValue(play.comboValue),
          cards.length,
        );
      case 'steps':
        return l10n.trickSteps(
          _rankLabelFromValue(play.comboValue),
          cards.length,
        );
      case 'bomb_four':
        return l10n.trickBombFour;
      case 'bomb_straight_flush':
        return l10n.trickBombStraightFlush;
      default:
        return l10n.gameCardCount(cards.length);
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
            style: TextStyle(fontSize: 15 * _ts, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  Widget _buildExchangeDialog(GameStateData state, GameService game) {
    final left = _firstWhereOrNull(state.players, (p) => p.position == 'left');
    final partner = _firstWhereOrNull(
      state.players,
      (p) => p.position == 'partner',
    );
    final right = _firstWhereOrNull(
      state.players,
      (p) => p.position == 'right',
    );

    final selectedCard = _selectedCards.isNotEmpty
        ? _selectedCards.first
        : null;
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
                  selectedCard != null
                      ? L10n.of(context).gameSelectRecipient
                      : L10n.of(context).gameSelectExchangeCard(assignedCount),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
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
                    child: Text(
                      L10n.of(context).gameReset,
                      style: const TextStyle(fontSize: 12),
                    ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 0,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    L10n.of(context).gameExchangeComplete,
                    style: const TextStyle(fontSize: 12),
                  ),
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
              _buildExchangeButton(
                'left',
                left?.name ?? L10n.of(context).gameLeftPlayer,
                selectedCard,
              ),
              _buildExchangeButton(
                'partner',
                partner?.name ?? L10n.of(context).gamePartner,
                selectedCard,
              ),
              _buildExchangeButton(
                'right',
                right?.name ?? L10n.of(context).gameRightPlayer,
                selectedCard,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExchangeInline(GameStateData state, GameService game) {
    return _buildExchangeDialog(state, game);
  }

  Widget _buildExchangeButton(
    String position,
    String name,
    String? selectedCard,
  ) {
    final assignedCard = _exchangeAssignments[position];
    final isAssigned = assignedCard != null;
    final canAssign =
        selectedCard != null &&
        !isAssigned &&
        !_exchangeAssignments.containsValue(selectedCard);

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
            color: canAssign
                ? const Color(0xFF4D99FF)
                : const Color(0xFFDDD0CC),
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
                  fontSize: 12 * _ts,
                  fontWeight: FontWeight.bold,
                  color: isAssigned
                      ? const Color(0xFF3A5A40)
                      : const Color(0xFF5A4038),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isAssigned) ...[
              SizedBox(width: 4 * _s),
              Icon(Icons.check_circle, size: 14 * _s, color: Color(0xFF3A5A40)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDragonDialog(GameStateData state, GameService game) {
    final left = _firstWhereOrNull(state.players, (p) => p.position == 'left');
    final right = _firstWhereOrNull(
      state.players,
      (p) => p.position == 'right',
    );
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
          Text('\u{1F409}', style: TextStyle(fontSize: 20 * _ts)),
          SizedBox(width: 8 * _s),
          Text(
            message,
            style: TextStyle(
              fontSize: 14 * _ts,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2E7D32),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallRankDialog(GameService game) {
    final ranks = [
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      '10',
      'J',
      'Q',
      'K',
      'A',
    ];
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
            style: OutlinedButton.styleFrom(minimumSize: const Size(120, 40)),
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
      title = myScore > enemyScore
          ? l10n.gameMyTeamWin
          : (myScore < enemyScore ? l10n.gameEnemyTeamWin : l10n.gameDraw);
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
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (state.lastRoundScores.isNotEmpty) ...[
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: l10n.gameThisRound),
                  TextSpan(
                    text:
                        '${state.myTeam == 'A' ? state.lastRoundScores['teamA'] : state.lastRoundScores['teamB']}',
                    style: const TextStyle(
                      color: Color(0xFF4A90D9),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const TextSpan(text: ' : '),
                  TextSpan(
                    text:
                        '${state.myTeam == 'A' ? state.lastRoundScores['teamB'] : state.lastRoundScores['teamA']}',
                    style: const TextStyle(
                      color: Color(0xFFD24B4B),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ],
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: l10n.gameTotalScore),
                TextSpan(
                  text:
                      '${state.myTeam == 'A' ? state.totalScores['teamA'] : state.totalScores['teamB']}',
                  style: const TextStyle(
                    color: Color(0xFF4A90D9),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const TextSpan(text: ' : '),
                TextSpan(
                  text:
                      '${state.myTeam == 'A' ? state.totalScores['teamB'] : state.totalScores['teamA']}',
                  style: const TextStyle(
                    color: Color(0xFFD24B4B),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
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
        return _rankPill(
          l10n.gameRankDiamond,
          const Color(0xFF69B7FF),
          Icons.diamond_outlined,
        );
      case _RankTier.gold:
        return _rankPill(
          l10n.gameRankGold,
          const Color(0xFFFFD54F),
          Icons.emoji_events,
        );
      case _RankTier.silver:
        return _rankPill(
          l10n.gameRankSilver,
          const Color(0xFFB0BEC5),
          Icons.emoji_events,
        );
      case _RankTier.bronze:
        return _rankPill(
          l10n.gameRankBronze,
          const Color(0xFFC58B6B),
          Icons.emoji_events,
        );
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
          Icon(icon, size: 14 * _s, color: color),
          SizedBox(width: 4 * _s),
          Text(
            label,
            style: TextStyle(
              fontSize: 12 * _ts,
              fontWeight: FontWeight.bold,
              color: color,
            ),
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
          margin: EdgeInsets.all(32 * _s),
          padding: EdgeInsets.all(24 * _s),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: child,
        ),
      ),
    );
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

  /// 사진 아래에 얹는 카드 뒷면 컴팩트 스트립 — 마이티 먹은패 배지처럼
  /// 아주 좁은 폭으로 겹쳐 그리고, 넘치면 +N 배지로 표시한다. Tichu 는
  /// 상대 손을 카드 개수만 알려주면 되므로 예전 큰 뒷면 스택 대신 이걸로
  /// 갈아탄다.
  Widget _buildCompactHandBacks(int count, {double scale = 1.0}) {
    if (count <= 0) return const SizedBox.shrink();
    final cardW = 14.0 * scale;
    final cardH = 20.0 * scale;
    // 모든 카드를 그려주되 좌석 폭(≈60dp * scale)을 넘지 않도록 step 을 줄여
    // 겹침을 자동으로 조절. 최소 step 2dp 로 두어 아무리 많아도 카드가 완전히
    // 포개져 보이진 않도록.
    const double preferredStep = 4.0;
    const double minStep = 2.0;
    const double maxTotalW = 60.0;
    final double step = count <= 1
        ? preferredStep * scale
        : (math
                  .min(
                    preferredStep,
                    (maxTotalW - 14.0) / (count - 1),
                  )
                  .clamp(minStep, preferredStep)
              * scale);
    final totalW = cardW + step * (count - 1);
    // 우측 상단 카드에 살짝 겹치는 카운트 뱃지 — clipBehavior: none 이라
    // 좌석 밖으로 살짝 나가도 잘리지 않는다.
    final double badgeSize = 18.0 * scale;
    return SizedBox(
      width: totalW,
      height: cardH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < count; i++)
            Positioned(
              left: i * step,
              child: PlayingCard(
                cardId: '',
                isFaceUp: false,
                width: cardW,
                height: cardH,
                isInteractive: false,
              ),
            ),
          Positioned(
            right: -badgeSize * 0.35,
            top: -badgeSize * 0.35,
            child: Container(
              width: badgeSize,
              height: badgeSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF5A4038),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11 * _ts * scale,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.0,
                ),
              ),
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

      // Tap anywhere to dismiss, and it goes by itself after a few seconds.
      //
      // Two reasons. The close button used to call Navigator.pop with the
      // SCREEN's context, not the dialog's — when the room vanished under it
      // (desertion, room closed) the game screen was gone and that pop had
      // nothing valid to work with, so the popup could not be closed at all and
      // sat on top of the waiting room. And this is a read-only summary: making
      // someone find a button to dismiss what is effectively a notification is
      // work for nothing.
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (dialogCtx) {
          return _AutoDismissDialog(
            duration: const Duration(seconds: 6),
            child: _buildDialog(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    L10n.of(dialogCtx).gameReceivedCards,
                    style: TextStyle(
                      fontSize: 18 * _ts,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 12 * _s),
                  _buildExchangeSummaryRowLine([
                    _ExchangeSummaryItem(leftName, receivedLeft),
                    _ExchangeSummaryItem(partnerName, receivedPartner),
                    _ExchangeSummaryItem(rightName, receivedRight),
                  ]),
                  SizedBox(height: 12 * _s),
                  Text(
                    L10n.of(dialogCtx).gameTapToClose,
                    style: TextStyle(
                      fontSize: 12 * _ts,
                      color: const Color(0xFF9A8E8A),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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
      spacing: 12 * _s,
      runSpacing: 8 * _s,
      children: items
          .where((i) => i.cardId != null)
          .map(
            (item) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.name.length > 4
                      ? '${item.name.substring(0, 4)}…'
                      : item.name,
                  style: TextStyle(
                    fontSize: 12 * _ts,
                    color: const Color(0xFF8A7A72),
                  ),
                ),
                SizedBox(height: 4 * _s),
                PlayingCard(
                  cardId: item.cardId!,
                  width: 34 * _s,
                  height: 48 * _s,
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
            blurRadius: 6 * _s,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13 * _ts,
          fontWeight: FontWeight.bold,
          color: fg,
        ),
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
    final isExchangePhase =
        state.phase == 'card_exchange' && !state.exchangeDone;

    // Bug #5: Hide submitted exchange cards from hand display
    if (_exchangeSubmitted && state.exchangeDone && _exchangeGiven.isNotEmpty) {
      final givenCards = _exchangeGiven.values.toSet();
      cards = cards.where((c) => !givenCards.contains(c)).toList();
    }

    // 교환 단계에서 이미 할당된 카드는 선택 불가
    bool isCardAssigned(String cardId) =>
        _exchangeAssignments.containsValue(cardId);

    Widget buildCardWidget(
      String cardId,
      double cardWidth,
      double cardHeight,
      double padding,
    ) {
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
            onTap: assigned
                ? null
                : () => _toggleCard(cardId, singleSelect: isExchangePhase),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalMargin = 16.0;
        final availableWidth = constraints.maxWidth - (horizontalMargin * 2);
        final perRow = cards.length <= 6
            ? cards.length
            : (cards.length / 2).ceil();
        final dense = cards.length >= 13;
        final cardPadding = dense ? 2.0 : 3.0;
        final totalPadding = perRow * cardPadding * 2;
        // Scaled with the board — these were the only card sizes left in
        // absolute pixels, so on a large screen the hand stayed phone-sized
        // while the table around it grew.
        final maxWidth = (dense ? 46.0 : 50.0) * _s;
        final minWidth = (dense ? 34.0 : 38.0) * _s;
        var cardWidth = ((availableWidth - totalPadding) / perRow).clamp(
          minWidth,
          maxWidth,
        );
        final ratio = dense ? 1.35 : 1.4;
        var cardHeight = (cardWidth * ratio).clamp(
          (dense ? 48.0 : 53.0) * _s,
          (dense ? 64.0 : 70.0) * _s,
        );

        // Nothing above was looking at how much *height* the hand takes. Width
        // is plentiful on a desktop window, so the cards ran straight to their
        // scaled maximum and the two rows plus the panel around them swallowed
        // the table. Cap the rows at a share of the screen and, if that bites,
        // walk the width back down so the cards keep their proportions.
        final rows = cards.length <= 6 ? 1 : 2;
        final maxRowsHeight =
            MediaQuery.of(context).size.height * _handHeightShare;
        final maxCardHeight = maxRowsHeight / rows;
        if (cardHeight > maxCardHeight) {
          cardHeight = maxCardHeight;
          cardWidth = cardHeight / ratio;
        }

        List<Widget> rowWidgets(List<String> row) {
          return row
              .map(
                (cardId) =>
                    buildCardWidget(cardId, cardWidth, cardHeight, cardPadding),
              )
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

/// Dialog contents that close on a tap anywhere, and on their own after
/// [duration] — the way Mighty announces a call or a deal-miss.
///
/// The timer lives here, inside the dialog route, on purpose. The received-cards
/// popup used to close through the game screen's own context, so when the room
/// vanished underneath it (desertion, room closed) there was nothing left to pop
/// with and the popup sat on the waiting room, uncloseable. A timer owned by the
/// route is cancelled when the route goes, and pops only itself.
class _AutoDismissDialog extends StatefulWidget {
  final Duration duration;
  final Widget child;

  const _AutoDismissDialog({required this.duration, required this.child});

  @override
  State<_AutoDismissDialog> createState() => _AutoDismissDialogState();
}

class _AutoDismissDialogState extends State<_AutoDismissDialog> {
  Timer? _timer;
  ModalRoute<dynamic>? _route;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, _close);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Held rather than looked up at fire time: by then this context can be
    // deactivated, and the lookup throws.
    _route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _close() {
    if (!mounted) return;
    // Not on top any more: something opened over this, and popping would take
    // that instead. A tap can still dismiss this one once it's visible again.
    if (_route?.isCurrent != true) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _close,
      child: widget.child,
    );
  }
}
