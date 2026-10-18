import '../utils/tichu_combo.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:ui' show ImageFilter;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/game_service.dart';
import '../widgets/afk_kick_badge.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/seat_chat_bubble.dart';
import '../widgets/bot_avatar.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/player_profile_dialog.dart';
import '../services/session_service.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../models/tichu_fx_detector.dart';
import '../widgets/tichu_effects.dart';
import '../theme/cartoon.dart';
import '../widgets/tichu_fx_events.dart';
import '../widgets/playing_card.dart';
import '../widgets/connection_overlay.dart';
import '../widgets/draggable_chat_panel.dart';
import '../widgets/game_chrome.dart';
import '../widgets/spectator_controls.dart';
import '../widgets/spectator_bottom_fill.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n_helpers.dart';
import '../widgets/mid_game_join.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  int _dogBannerDismissedSeq = -1;

  /// The last thing each player said, shown briefly over their seat.
  late final SeatChatBubbles _seatChat = SeatChatBubbles(() {
    if (mounted) setState(() {});
  });

  /// Wraps a board seat so a chat bubble can hang above it.
  ///
  /// Drawn on the overlay, not inside the seat's own Stack — otherwise the
  /// trick layer, which this board deliberately paints over the seats, would
  /// swallow the line.
  Widget _withSeatBubble(String nickname, Widget seat) {
    return SeatBubbleAnchor(
      text: _seatChat.textFor(nickname),
      styleKey: _seatChat.styleFor(nickname),
      suppressed: _chatOpen,
      child: seat,
    );
  }

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
  bool _wasMyTurn = false;
  bool _birdCallDialogOpen = false;
  bool _roundEndReady = false; // delay before showing round end dialog

  // 티츄 선언·패 털기·원투 연출. 상태가 바뀌는 순간을 detector 가 잡아 주고,
  // 여기엔 지금 화면에 떠 있는 것만 남는다.
  final TichuFxDetector _fxDetector = TichuFxDetector();
  final List<TichuFxEvent> _fx = [];
  int _fxSeq = 0;
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

  /// 상태가 바뀐 순간을 연출로 바꾼다. build 안에서 불리므로 setState 는 다음
  /// 프레임으로 미룬다.
  void _collectFx(GameStateData state) {
    final signals = _fxDetector.update(
      state.players,
      (p) => _teamForPosition(state, p.position),
    );
    if (signals.isEmpty) return;
    playTichuFxSounds(signals);
    final events = buildTichuFxEvents(
      signals,
      L10n.of(context),
      () => ++_fxSeq,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _fx.addAll(events);
        // 한꺼번에 쌓여도 화면을 가리지 않게 최근 4개만 남긴다.
        while (_fx.length > 4) {
          _fx.removeAt(0);
        }
      });
    });
  }

  Future<void> _recoverRoomState() async {
    if (_waitingForRoomRecovery) return;
    _waitingForRoomRecovery = true;
    // Clear stale UI state from previous connection
    _fxDetector.reset();
    _fx.clear();
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

  Widget _buildRecoveryLoading({required String title, String? subtitle}) {
    return Center(
      child: CartoonLoadingCard(title: title, subtitle: subtitle),
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
    // 내 차례가 막 시작되면 짧게 진동해서 다른 곳을 보고 있어도 알아채게 한다.
    final myTurnNow = state != null && state.isMyTurn;
    if (myTurnNow && !_wasMyTurn && state.phase == 'playing') {
      HapticFeedback.mediumImpact();
    }
    _wasMyTurn = myTurnNow;
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
        HapticFeedback.heavyImpact();
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

  // 고른 패가 지금 낼 수 있는 조합인지(조합 성립 + 앞 패를 이기는지). 소원 의무는 서버가 판정.
  bool _canPlaySelected(GameStateData state) {
    final last = state.currentTrick.isEmpty ? null : state.currentTrick.last;
    return tichuCanPlay(
      _selectedCards.toList(),
      myTurn: state.isMyTurn,
      trickType: last?.combo,
      trickLength: last?.cards.length ?? 0,
      trickValue: last?.comboValue ?? 0,
    );
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
          backgroundColor: Cartoon.paper,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
            side: BorderSide(color: Cartoon.ink, width: 2.5),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          title: Row(
            children: [
              const Text('🐦', style: TextStyle(fontSize: 26)),
              const SizedBox(width: 8),
              Text(
                L10n.of(context).gameSparrowCall,
                style: Cartoon.text(size: 22),
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
                    color: Cartoon.cream,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    L10n.of(context).gameSelectNumberToCall,
                    textAlign: TextAlign.center,
                    style: Cartoon.text(size: 15),
                  ),
                ),
                const SizedBox(height: 10),
                _buildBirdCallRankRow(ctx, lowRanks),
                _buildBirdCallRankRow(ctx, highRanks),
                const SizedBox(height: 6),
                gameButton(
                  L10n.of(context).gameNoCall,
                  () {
                    _birdCallDialogOpen = false;
                    Navigator.pop(ctx);
                    context.read<GameService>().playCards(
                      _selectedCards.toList(),
                      callRank: 'none',
                    );
                    setState(() => _selectedCards.clear());
                  },
                  color: const Color(0xFFB9B1A8),
                  height: 46,
                  size: 17,
                ),
                const SizedBox(height: 2),
                Center(
                  child: TextButton(
                    onPressed: () {
                      _birdCallDialogOpen = false;
                      Navigator.pop(ctx);
                      setState(() => _selectedCards.clear());
                    },
                    style: TextButton.styleFrom(foregroundColor: Cartoon.ink),
                    child: Text(
                      L10n.of(context).gameCancelPickAnother,
                      style: Cartoon.text(size: 16),
                    ),
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
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: gameButton(
              rank,
              () {
                _birdCallDialogOpen = false;
                Navigator.pop(ctx);
                context.read<GameService>().playCards(
                  _selectedCards.toList(),
                  callRank: rank,
                );
                setState(() => _selectedCards.clear());
              },
              color: Cartoon.blue,
              height: 42,
              size: 17,
              expand: true,
              hPad: 0,
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
            // 손패 창은 SafeArea 안에 그려지므로, 홈 바가 있는 기기에서는
            // 창 아래 안전 영역에 배경 그라데이션이 그대로 비친다 — 창이
            // 거기서 잘린 것처럼 보인다. 그 띠를 창과 같은 색으로 채운다.
            // (스컬킹 화면에서 같은 것을 고쳤고, 같은 위젯을 쓴다.)
            child: Stack(
              children: [
                SpectatorBottomFill(
                  // 창이 보이는 동안만. 복구 로딩이나 다른 화면으로 넘어가는
                  // 중에는 창이 없으므로 띠만 남으면 그게 더 어색하다.
                  when: (g) =>
                      g.gameState != null &&
                      g.currentDestination == AppDestination.game,
                  color: (g) => _bottomAreaColor(g.gameState),
                ),
                Positioned.fill(
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
                            subtitle: L10n.of(
                              context,
                            ).gameRecheckingDestination,
                          );
                        }

                        _waitingForRoomRecovery = false;

                        // Bug #1: Clear exchange assignments when phase leaves card_exchange
                        if (state.phase != 'card_exchange') {
                          if (_exchangeAssignments.isNotEmpty ||
                              _exchangeSubmitted) {
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
                        if (state.phase == 'card_exchange' &&
                            !state.exchangeDone) {
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
                        _collectFx(state);

                        return Stack(
                          children: [
                            if (_tichuOverlayColor(state) != null)
                              Positioned.fill(
                                child: Container(
                                  color: _tichuOverlayColor(state),
                                ),
                              ),
                            _buildPortraitGameLayout(state, game),

                            // Dialogs/Panels
                            // (Large Tichu is NOT here — it rides in the bottom
                            // column with the exchange panel so it sits on the hand.)
                            if (state.dragonPending)
                              _buildDragonDialog(state, game),

                            if (state.needsToCallRank && !_birdCallDialogOpen)
                              _buildCallRankDialog(game),

                            // Tichu / finish / one-two effects sit under the score
                            // dialog (a banner over the board hid the scores) and
                            // let touches through.
                            Positioned.fill(
                              child: TichuFxLayer(
                                events: _fx,
                                onDone: (id) {
                                  if (mounted) {
                                    setState(
                                      () => _fx.removeWhere((e) => e.id == id),
                                    );
                                  }
                                },
                              ),
                            ),

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
              ],
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
    // 플레이 중에는 가운데 차례 알약 옆에 이미 남은 시간이 있다. 위쪽 뱃지는
    // 교환·라지 티츄처럼 가운데에 시간이 없는 단계에서만 보여 준다.
    final timerBadge = state.phase == 'playing'
        ? null
        : _buildTimerBadge(state);
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
          top: timerBadge == null ? 52 : 82,
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
      iconColor: Cartoon.onSurface(const Color(0xFFE53935)),
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
            decoration: Cartoon.panelDecoration(radius: 18, shadowOffset: 3),
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
        backgroundColor: Cartoon.paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: BorderSide(color: Cartoon.ink, width: 2.5),
        ),
        title: Text(
          L10n.of(context).gameLeaveTitle,
          style: Cartoon.text(size: 22),
        ),
        // In a mid-game-join room leaving does not end the match — a bot
        // takes the seat — but it is still recorded, so the warning has to say
        // which of the two is about to happen.
        content: Text(
          game.canLeaveInProgress
              ? L10n.of(
                  context,
                ).midLeaveConfirmBody(kMidGameJoinCooldownMinutes)
              : L10n.of(context).gameLeaveConfirm,
          style: Cartoon.text(size: 16.5, height: 1.4),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(foregroundColor: Cartoon.ink),
            child: Text(
              L10n.of(context).gameCancel,
              style: Cartoon.text(size: 17),
            ),
          ),
          gameButton(L10n.of(context).gameLeave, () {
            Navigator.pop(ctx);
            game.leaveGame();
          }, color: Cartoon.red),
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
      child: GameNoticeBar(
        icon: Icons.warning_rounded,
        text: displayMessage,
        scale: _s,
      ),
    );
  }

  Widget _buildTimeoutBanner(String playerName) {
    return Positioned(
      bottom: 240,
      left: 20,
      right: 20,
      child: GameNoticeBar(
        icon: Icons.timer_off_rounded,
        color: Cartoon.yellow,
        text: L10n.of(context).gameTimeout(playerName),
        scale: _s,
      ),
    );
  }

  Widget _buildDesertionBanner(String playerName, String reason) {
    return Positioned(
      bottom: 240,
      left: 20,
      right: 20,
      child: GameNoticeBar(
        icon: Icons.person_off_rounded,
        text: reason == 'timeout'
            ? L10n.of(context).gameDesertionTimeout(playerName)
            : L10n.of(context).gameDesertionLeave(playerName),
        scale: _s,
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
        decoration: Cartoon.panelDecoration(radius: 22, shadowOffset: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.visibility_rounded, color: Cartoon.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    L10n.of(context).gameCardViewRequest(spectatorNickname),
                    style: Cartoon.userText(size: 15),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: gameButton(
                    L10n.of(context).gameReject,
                    () => game.respondCardViewRequest(spectatorId, false),
                    color: Cartoon.red,
                    height: 44,
                    size: 16,
                    expand: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: gameButton(
                    L10n.of(context).gameAllow,
                    () => game.respondCardViewRequest(spectatorId, true),
                    color: Cartoon.blue,
                    height: 44,
                    size: 16,
                    expand: true,
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
      iconColor: hasViewers ? Cartoon.onSurface(const Color(0xFF6A9BD1)) : null,
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
        decoration: Cartoon.panelDecoration(radius: 18, shadowOffset: 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.visibility_rounded, size: 18, color: Cartoon.ink),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    L10n.of(context).gameViewingMyCards,
                    style: Cartoon.text(size: 15),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _viewersOpen = false),
                  child: Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: Cartoon.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (game.cardViewers.isEmpty)
              Text(
                L10n.of(context).gameNoViewers,
                style: Cartoon.text(
                  size: 13,
                  color: Cartoon.ink.withValues(alpha: 0.5),
                ),
              )
            else
              ...game.cardViewers.map((viewer) {
                final nickname = viewer['nickname'] ?? '';
                final spectatorId = viewer['id'] ?? '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(
                        Icons.person_rounded,
                        size: 17,
                        color: Cartoon.ink.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          nickname,
                          style: Cartoon.userText(size: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => game.revokeCardView(spectatorId),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: gamePillDecoration(
                            radius: 8,
                            color: Cartoon.surface(
                              Cartoon.surface(const Color(0xFFFFD9D6)),
                            ),
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 14,
                            color: Cartoon.red,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            Container(
              height: 2,
              margin: const EdgeInsets.symmetric(vertical: 8),
              color: Cartoon.ink.withValues(alpha: 0.15),
            ),
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
          decoration:
              gamePillDecoration(
                radius: 12,
                color: selected ? Cartoon.tint(color, 0.8) : Cartoon.cream,
              ).copyWith(
                border: Border.all(
                  color: selected ? color : Cartoon.ink.withValues(alpha: 0.35),
                  width: selected ? 2.4 : 1.6,
                ),
              ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? color : Cartoon.ink.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: Cartoon.text(
                    size: 13,
                    color: selected ? color : Cartoon.ink,
                  ),
                ),
              ),
              if (selected) Icon(Icons.check_rounded, size: 16, color: color),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.gameCardViewPolicyTitle, style: Cartoon.text(size: 14)),
        const SizedBox(height: 6),
        radio(
          value: 'ask',
          label: l10n.gameCardViewPolicyAsk,
          icon: Icons.help_outline,
          color: Cartoon.blue,
        ),
        radio(
          value: 'always_allow',
          label: l10n.gameCardViewPolicyAllow,
          icon: Icons.check_circle_rounded,
          color: Cartoon.green,
        ),
        radio(
          value: 'always_deny',
          label: l10n.gameCardViewPolicyDeny,
          icon: Icons.block_rounded,
          color: Cartoon.red,
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
                  // 빈 자리(p == null)엔 띄울 말이 없다.
                  child: _withSeatBubble(
                    p?.name ?? '',
                    _buildOpponentSeat(state, game, p, positionKey: key),
                  ),
                );
              }(),
            ],
            // 개: 낸 자리에서 선공을 받는 자리로 날아간다.
            if (game.dogPlayActive &&
                game.dogFromId != null &&
                game.dogToId != null)
              () {
                Offset? seatCenter(String id) {
                  final pl = _firstWhereOrNull(
                    state.players,
                    (p) => p.id == id,
                  );
                  if (pl == null) return null;
                  if (pl.position == 'self') {
                    return Offset(centerX, height - 8 * boardScale);
                  }
                  for (final (_, key, angleDeg) in positions) {
                    if (key != pl.position) continue;
                    final a = angleDeg * math.pi / 180;
                    final dx = key == 'partner'
                        ? math.cos(a)
                        : (key == 'left' ? -1.0 : 1.0);
                    return Offset(
                      centerX + seatRadiusX * dx,
                      centerY + seatRadiusY * math.sin(a),
                    );
                  }
                  return null;
                }

                final from = seatCenter(game.dogFromId!);
                final to = seatCenter(game.dogToId!);
                if (from == null || to == null) return const SizedBox.shrink();
                return Positioned.fill(
                  child: IgnorePointer(
                    child: _DogFlight(
                      key: ValueKey(game.dogPlaySeq),
                      from: from,
                      to: to,
                      cardWidth: 44 * _s,
                      cardHeight: 61 * _s,
                    ),
                  ),
                );
              }(),
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
                          style: Cartoon.text(
                            size: compact ? 10 : 11,
                            color: Cartoon.orangeDeep,
                          ),
                        ),
                      ),
                    AfkKickBadge(
                      game: game,
                      nickname: p?.name ?? '',
                      avatarSize: avatarDiameter,
                      child: ProfileAvatar(
                        photoUrl: game.blockedUsers.contains(p?.name ?? '')
                            ? null
                            : game.resolvePhotoUrl(p?.photoUrl),
                        size: avatarDiameter,
                        blocked: game.blockedUsers.contains(p?.name ?? ''),
                        // 라지 티츄(빨강) / 스몰 티츄(파랑) > 현재 턴(노랑).
                        // 티츄 선언은 그 판의 결정적 신호라 턴보다 우선 노출.
                        border: (p?.hasLargeTichu ?? false)
                            ? Border.all(color: Cartoon.red, width: 3.0)
                            : (p?.hasSmallTichu ?? false)
                            ? Border.all(color: Cartoon.blue, width: 3.0)
                            : isTurn
                            ? Border.all(color: Cartoon.orange, width: 3.0)
                            : Border.all(color: Cartoon.ink, width: 2.0),
                        fallback: (p?.isBot ?? false)
                            ? BotAvatar(size: avatarDiameter, name: p!.name)
                            : DefaultAvatar(size: avatarDiameter),
                      ),
                    ),
                    SizedBox(height: 3 * _s),
                    if (badge != null || (p?.finishPosition ?? 0) > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ?badge,
                            if (badge != null && (p?.finishPosition ?? 0) > 0)
                              SizedBox(width: 4 * _s),
                            if ((p?.finishPosition ?? 0) > 0)
                              _finishBadge(p!.finishPosition),
                          ],
                        ),
                      ),
                    // 이름+팀+연결상태를 SK 톤 pill 로. 현재 턴이면 노란 배경.
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: EdgeInsets.symmetric(
                        horizontal: 8 * _s,
                        vertical: 3 * _s,
                      ),
                      decoration: BoxDecoration(
                        color: isTurn ? Cartoon.yellow : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        border: isTurn
                            ? Border.all(color: Cartoon.ink, width: 1.6)
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
                              color: isMyTeam ? Cartoon.blue : Cartoon.red,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              teamLabel,
                              style: Cartoon.text(
                                size: 10 * _ts,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          if (!(p?.connected ?? true))
                            Padding(
                              padding: const EdgeInsets.only(right: 3),
                              child: Icon(
                                Icons.wifi_off,
                                size: 11,
                                color: Cartoon.red,
                              ),
                            ),
                          Flexible(
                            child: Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                              style: Cartoon.userText(
                                size: nameFontSize + 1,
                                color: (p?.connected ?? true)
                                    ? Cartoon.ink
                                    : Cartoon.ink.withValues(alpha: 0.4),
                              ),
                            ),
                          ),
                          if (exchangeDone)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Icon(
                                Icons.check_circle,
                                size: 12,
                                color: Cartoon.onSurface(
                                  Cartoon.onSurface(const Color(0xFF3A8F52)),
                                ),
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
    // 다른 패가 한 번이라도 나온 뒤에는 그 개 배너를 다시 보이지 않는다. 트릭이
    // 치워져 판이 비면 아직 남아 있는 개 연출이 다시 떠오르던 것을 막는다.
    if (game.dogPlayActive && state.currentTrick.isNotEmpty) {
      _dogBannerDismissedSeq = game.dogPlaySeq;
    }
    final showDogBanner =
        game.dogPlayActive &&
        state.currentTrick.isEmpty &&
        _dogBannerDismissedSeq != game.dogPlaySeq;
    return Center(
      child: Container(
        width: 260 * _s,
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
                style: Cartoon.text(size: 20 * _ts),
                textAlign: TextAlign.center,
              ),
            if (state.phase == 'playing') ...[
              SizedBox(height: 3 * _s),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    // 내 차례면 주황 알약, 남의 차례면 크림 알약에 이름.
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12 * _s,
                        vertical: 3 * _s,
                      ),
                      decoration: gamePillDecoration(
                        color: state.isMyTurn ? Cartoon.orange : Cartoon.cream,
                      ),
                      child: Text(
                        state.isMyTurn
                            ? L10n.of(context).gameMyTurn
                            : L10n.of(
                                context,
                              ).gamePlayerTurn(_getCurrentPlayerName(state)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: state.isMyTurn
                            ? Cartoon.text(size: 18 * _ts, color: Colors.white)
                            : Cartoon.userText(size: 16 * _ts),
                      ),
                    ),
                  ),
                  // 트릭박스 안 턴 표시 옆에 남은 시간을 함께 붙여 눈이 두 군데를
                  // 왔다갔다 하지 않게. 좌상단 타이머 뱃지는 그대로 유지 —
                  // 이건 트릭을 볼 때 자연스러운 위치에서 한 번 더 알려주는 용도.
                  if (_remainingSeconds > 0) ...[
                    SizedBox(width: 6 * _s),
                    Text(
                      '${_remainingSeconds}s',
                      style: Cartoon.text(
                        size: 18 * _ts,
                        color: _remainingSeconds <= 10
                            ? Cartoon.red
                            : Cartoon.ink.withValues(alpha: 0.7),
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
                  horizontal: 12,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: Cartoon.surface(
                    Cartoon.surface(const Color(0xFFFFD9D6)),
                  ),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: Cartoon.ink, width: 1.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('🐦', style: TextStyle(fontSize: 16 * _ts)),
                    SizedBox(width: 4 * _s),
                    Text(
                      L10n.of(context).gameCall(state.callRank!),
                      style: Cartoon.text(size: 18 * _ts, color: Cartoon.red),
                    ),
                  ],
                ),
              ),
            ],

            SizedBox(height: 4 * _s),

            // 개 배너는 다음 사람이 새 트릭을 시작하기 전까지만. 그 뒤에도 남아
            // 있으면 개 카드와 새로 낸 패가 위아래로 두 벌 보여 헷갈린다.
            if (showDogBanner)
              _buildDogPlayedBanner(
                game.dogPlayPlayerName,
                toName: game.dogToName,
              ),

            if (showDogBanner) SizedBox(height: 4 * _s),

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
    final urgent = _remainingSeconds <= 10;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10 * _s, vertical: 4 * _s),
      decoration: gamePillDecoration(
        radius: 14,
        color: urgent
            ? Cartoon.surface(Cartoon.surface(const Color(0xFFFFD9D6)))
            : Cartoon.cream,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule_rounded,
            size: 16 * _s,
            color: urgent ? Cartoon.red : Cartoon.ink,
          ),
          SizedBox(width: 5 * _s),
          Flexible(
            child: Text(
              l10n.gameTimerLabel(turnLabel, _remainingSeconds),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: Cartoon.userText(
                size: 14 * _s,
                color: urgent ? Cartoon.red : Cartoon.ink,
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
    final horizontal = compact ? 8.0 * _s : 10.0 * _s;
    final vertical = compact ? 3.0 * _s : 4.0 * _s;
    final spacing = compact ? 6.0 * _s : 9.0 * _s;
    final iconFont = compact ? 13.0 * _s : 14.0 * _s;
    final textFont = compact ? 13.0 * _s : 15.0 * _s;
    final sub = Cartoon.ink.withValues(alpha: 0.55);
    Widget mark(bool alive, Color on) => Text(
      alive ? '\u25CB' : '\u2715',
      style: TextStyle(
        fontSize: 13 * _ts,
        fontWeight: FontWeight.w900,
        color: alive ? on : Cartoon.ink.withValues(alpha: 0.25),
      ),
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: compact ? EdgeInsets.zero : EdgeInsets.only(bottom: 2 * _s),
        padding: EdgeInsets.symmetric(
          horizontal: horizontal,
          vertical: vertical,
        ),
        decoration: gamePillDecoration(radius: 14 * _s),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('A', style: Cartoon.text(size: textFont)),
            Text(
              ':$aces',
              style: Cartoon.text(size: textFont, color: sub),
            ),
            SizedBox(width: spacing),
            Text('K', style: Cartoon.text(size: textFont)),
            Text(
              ':$kings',
              style: Cartoon.text(size: textFont, color: sub),
            ),
            SizedBox(width: spacing),
            Text('\u{1F409}', style: TextStyle(fontSize: iconFont)),
            mark(dragon, Cartoon.blue),
            SizedBox(width: compact ? 4 * _s : 6 * _s),
            Text('\u{1F426}', style: TextStyle(fontSize: iconFont)),
            mark(phoenix, Cartoon.orangeDeep),
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
    final dim = Cartoon.ink.withValues(alpha: 0.5);

    return CartoonPressable(
      scale: 0.94,
      onTap: () => _showScoreHistoryDialog(state),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14 * _s, vertical: 4 * _s),
        decoration: gamePillDecoration(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              myTeam,
              style: Cartoon.text(
                size: 12 * _ts,
                color: myLeading ? Cartoon.blue : dim,
              ),
            ),
            SizedBox(width: 4 * _s),
            Text(
              '$myScore',
              style: Cartoon.text(
                size: 19 * _ts,
                color: myLeading ? Cartoon.blue : Cartoon.ink,
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 6 * _s),
              child: Text(
                ':',
                style: Cartoon.text(size: 17 * _ts, color: dim),
              ),
            ),
            Text(
              '$enemyScore',
              style: Cartoon.text(
                size: 19 * _ts,
                color: enemyLeading ? Cartoon.red : Cartoon.ink,
              ),
            ),
            SizedBox(width: 4 * _s),
            Text(
              myTeam == 'A' ? 'B' : 'A',
              style: Cartoon.text(
                size: 12 * _ts,
                color: enemyLeading ? Cartoon.red : dim,
              ),
            ),
            // The finish line moved into the score-history dialog: next to the
            // running score it read as a fraction ("25 / 1000") rather than a
            // goal, and this bar is the one thing always on screen.
            SizedBox(width: 6 * _s),
            Icon(Icons.leaderboard_rounded, size: 15 * _s, color: dim),
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

  Widget _buildDogPlayedBanner(String playerName, {String toName = ''}) {
    String clip(String n) => n.length > 8 ? '${n.substring(0, 8)}..' : n;
    // The Dog gets its own banner instead of going through the normal trick
    // pile, and it kept a hardcoded 32x45 card while every other played card is
    // 44x61 * _s — so on a scaled-up board the Dog came out at under half size.
    return Container(
      // 일반 트릭처럼 상자 없이 글자와 카드만. 상자가 있으면 같은 화면의 다른
      // 패와 달라 보여서 "패가 두 벌"처럼 읽혔다.
      padding: EdgeInsets.symmetric(horizontal: 8 * _s, vertical: 6 * _s),
      child: Column(
        children: [
          Text(
            playerName.isNotEmpty && toName.isNotEmpty
                ? L10n.of(
                    context,
                  ).gameDogPassedTo(clip(playerName), clip(toName))
                : playerName.isNotEmpty
                ? L10n.of(context).gameDogPlayedBy(
                    playerName.length > 8
                        ? '${playerName.substring(0, 8)}..'
                        : playerName,
                  )
                : L10n.of(context).gameDogPlayed,
            style: Cartoon.userText(
              size: 12.5 * _ts,
              color: Cartoon.ink.withValues(alpha: 0.7),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 4 * _s),
          // 트릭 자리에는 '카드' 를 둔다. 여기는 무엇이 나왔는지 기록처럼
          // 남는 자리라서, 다른 낸 패들과 같은 모양이어야 나란히 읽힌다.
          // (배경을 지운 강아지는 날아가는 연출 쪽에서 쓴다 — _DogFlight.)
          PlayingCard(
            cardId: 'special_dog',
            width: 52 * _s,
            height: 73 * _s,
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
                  style: Cartoon.userText(
                    size: 16 * _ts,
                    color: isMyTeam
                        ? Cartoon.onSurface(const Color(0xFF2F6FC4))
                        : Cartoon.onSurface(const Color(0xFFC73A4B)),
                  ),
                ),
                TextSpan(
                  text: L10n.of(context).gamePlayedCards,
                  style: Cartoon.text(
                    size: 14 * _ts,
                    color: Cartoon.ink.withValues(alpha: 0.65),
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
    final double baseCardW = 52 * _s;
    final double baseCardH = 73 * _s;
    var cardW = baseCardW;
    var cardH = baseCardH;

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
                color: Cartoon.yellow,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: Cartoon.inkOn(Cartoon.yellow),
                  width: 1.5,
                ),
              ),
              child: Text(
                phoenixBeatLabel,
                style: Cartoon.text(size: 12 * _ts),
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

        // 7장 이상은 한 줄에 밀어넣지 말고 두 줄로. 관전 트릭과 동일 규칙.
        final rows = cards.length >= 7 ? 2 : 1;
        final perRow = (cards.length + rows - 1) ~/ rows;

        // 카드 크기와 겹침은 "한 줄에 들어갈 장수" 기준으로 정한다. 예전엔
        // 전체 장수로 줄여서, 두 줄로 나눌 긴 스트레이트가 오히려 쪼그라들고
        // (겹침은 고정 px 라) 간격도 어긋났다. 겹침은 카드 폭 비율로 유지한다.
        const minRatio = 24 / 44;
        const maxRatio = 34 / 44;
        cardW = baseCardW;
        cardH = baseCardH;
        final needed = cardW * (1 + minRatio * (perRow - 1));
        if (needed > availableWidth) {
          final fit = (availableWidth / needed).clamp(0.62, 1.0);
          cardW *= fit;
          cardH *= fit;
        }
        final rowMinOverlap = cardW * minRatio;
        final rowMaxOverlap = cardW * maxRatio;

        Widget buildRow(List<String> rowCards) {
          final overlap = rowCards.length > 1
              ? ((availableWidth - cardW) / (perRow - 1)).clamp(
                  rowMinOverlap,
                  rowMaxOverlap,
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

        if (rows == 1) return Center(child: buildRow(cards));

        final row1 = cards.sublist(0, perRow);
        final row2 = cards.sublist(perRow);
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

  /// 손패 창의 바탕색.
  ///
  /// 창 아래 안전 영역을 채우는 띠(SpectatorBottomFill)가 같은 값을 써야
  /// 하므로 여기 모아 둔다. 두 곳에서 따로 계산하면 차례가 바뀔 때마다
  /// 창과 띠 사이에 이음새가 보인다.
  Color _bottomAreaColor(GameStateData? state) {
    final isMyTurn = state?.isMyTurn == true;
    // 내 차례에 5초 이하로 남으면 바탕이 붉어져 시간이 없다는 걸 한눈에 보여 준다.
    final urgent = isMyTurn && _remainingSeconds > 0 && _remainingSeconds <= 5;
    if (urgent) return Cartoon.myTurnUrgent;
    if (isMyTurn) return Cartoon.myTurn;
    return Cartoon.paper;
  }

  Widget _buildBottomArea(GameStateData state, GameService game) {
    final isMyTurn = state.isMyTurn;
    return Container(
      padding: EdgeInsets.all(10 * _s),
      // 내 차례엔 노란 바탕과 두꺼운 윗줄, 아니면 크림 바탕. 번지는 그림자 대신
      // 윗줄 하나로만 구분한다.
      decoration: BoxDecoration(
        color: _bottomAreaColor(state),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(
          top: BorderSide(color: Cartoon.ink, width: isMyTurn ? 3.2 : 2.2),
        ),
      ),
      child: Column(
        children: [
          // My name (tappable for profile) + status
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                margin: EdgeInsets.only(right: 6 * _s),
                padding: EdgeInsets.symmetric(horizontal: 6 * _s, vertical: 1),
                decoration: BoxDecoration(
                  color: Cartoon.blue,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  state.myTeam,
                  style: Cartoon.text(
                    size: 11 * _ts,
                    color: Cartoon.surface(Colors.white),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _showPlayerProfileDialog(game.playerName, game),
                child: Text(
                  game.playerName,
                  style: Cartoon.userText(size: 14 * _ts),
                ),
              ),
              if (isMyTurn) ...[
                SizedBox(width: 6 * _s),
                CartoonPulse(
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 10 * _s,
                      vertical: 2 * _s,
                    ),
                    decoration: BoxDecoration(
                      color: Cartoon.orange,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: Cartoon.inkOn(Cartoon.orange),
                        width: 1.6,
                      ),
                    ),
                    child: Text(
                      L10n.of(context).gameMyTurn,
                      style: Cartoon.text(size: 13 * _ts, color: Colors.white),
                    ),
                  ),
                ),
              ],
              if (_tichuBadgeForSelf(state) != null) ...[
                SizedBox(width: 8 * _s),
                _tichuBadgeForSelf(state)!,
              ],
              if (_selfFinishPosition(state) > 0) ...[
                SizedBox(width: 8 * _s),
                _finishBadge(_selfFinishPosition(state)),
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
                      color: Cartoon.yellow,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Cartoon.inkOn(Cartoon.yellow),
                        width: 1.6,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${game.myTimeoutCount}/3',
                          style: Cartoon.text(size: 13 * _ts),
                        ),
                        SizedBox(width: 4 * _s),
                        Text(
                          L10n.of(context).gameNotAfk,
                          style: Cartoon.text(size: 12 * _ts),
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
              gameButton(
                L10n.of(context).gamePlay,
                (state.phase == 'playing' &&
                        _selectedCards.isNotEmpty &&
                        !state.dragonPending &&
                        _canPlaySelected(state))
                    ? _playCards
                    : null,
                color: Cartoon.green,
                height: 50,
                size: 20,
                hPad: 30,
              ),
              SizedBox(width: 14 * _s),
              gameButton(
                L10n.of(context).gamePass,
                (state.phase == 'playing' &&
                        state.isMyTurn &&
                        state.currentTrick.isNotEmpty)
                    ? _passTurn
                    : null,
                color: Cartoon.blue,
                height: 50,
                size: 20,
                hPad: 30,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLargeTichuDialog(GameService game) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 20 * _s),
      padding: EdgeInsets.symmetric(horizontal: 16 * _s, vertical: 12 * _s),
      decoration: Cartoon.panelDecoration(radius: 22, shadowOffset: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              L10n.of(context).gameLargeTichuQuestion,
              style: Cartoon.text(size: 18 * _ts, height: 1.2),
            ),
          ),
          SizedBox(width: 12 * _s),
          gameButton(
            L10n.of(context).gameDeclare,
            () => game.declareLargeTichu(),
            color: Cartoon.orange,
            height: 42,
            size: 17,
            hPad: 14,
          ),
          SizedBox(width: 8 * _s),
          gameButton(
            L10n.of(context).gamePass,
            () => game.passLargeTichu(),
            color: const Color(0xFFB9B1A8),
            height: 42,
            size: 17,
            hPad: 14,
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
            style: Cartoon.userText(
              size: i == 0 ? 14 : 12,
              color: reversedMine[i]
                  ? Cartoon.onSurface(const Color(0xFF2F6FC4))
                  : Cartoon.onSurface(const Color(0xFFB23A3A)),
              weight: i == 0 ? FontWeight.w800 : FontWeight.w700,
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
        // cards[0] is a pair card (the server lays out pair → triple), and a
        // full house ranks by its triple — 22288 read "8 full house".
        return l10n.trickFullHouse(_rankLabelFromValue(play.comboValue));
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
        return l10n.trickBombFour(_rankFromCardId(cards[0]));
      case 'bomb_straight_flush':
        return l10n.trickBombStraightFlush(
          _rankLabelFromValue(play.comboValue),
          cards.length,
        );
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
        child: gameButton(
          L10n.of(context).gameSmallTichuDeclare,
          () {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: Cartoon.paper,
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                  side: BorderSide(color: Cartoon.ink, width: 2.5),
                ),
                title: Text(
                  L10n.of(context).gameSmallTichuConfirmTitle,
                  style: Cartoon.text(size: 22),
                ),
                content: Text(
                  L10n.of(context).gameSmallTichuConfirmContent,
                  style: Cartoon.text(size: 16.5, height: 1.4),
                ),
                actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: TextButton.styleFrom(foregroundColor: Cartoon.ink),
                    child: Text(
                      L10n.of(context).gameCancel,
                      style: Cartoon.text(size: 17),
                    ),
                  ),
                  gameButton(L10n.of(context).gameDeclareButton, () {
                    Navigator.of(ctx).pop();
                    game.declareSmallTichu();
                  }),
                ],
              ),
            );
          },
          color: Cartoon.yellow,
          height: 40,
          size: 17,
          hPad: 16,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: Cartoon.panelDecoration(radius: 20, shadowOffset: 3),
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
                  style: Cartoon.text(size: 16),
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
                      style: Cartoon.text(size: 14),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              gameButton(
                L10n.of(context).gameExchangeComplete,
                assignedCount == 3
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
                color: Cartoon.green,
                height: 36,
                size: 15,
                hPad: 12,
              ),
            ],
          ),
          const SizedBox(height: 8),
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
              ? Cartoon.surface(const Color(0xFFCDEFD6))
              : canAssign
              ? Cartoon.surface(const Color(0xFFD6EAFF))
              : Cartoon.cream,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: canAssign
                ? Cartoon.blue
                : Cartoon.ink.withValues(alpha: 0.35),
            width: canAssign ? 2.4 : 1.6,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                name,
                style: Cartoon.userText(size: 14 * _ts),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isAssigned) ...[
              SizedBox(width: 4 * _s),
              Icon(
                Icons.check_circle_rounded,
                size: 16 * _s,
                color: Cartoon.green,
              ),
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
    final l10n = L10n.of(context);
    // 자리 기준으로 왼쪽·오른쪽을 양쪽에 둔다. 용을 줄 때는 이름보다 "내 왼쪽/오른쪽
    // 사람"으로 고르는 경우가 많아서, 이름은 보조로 아래에 작게만 적는다.
    Widget pick(String side, String? name, bool isLeft) {
      return Expanded(
        child: CartoonButton(
          height: 84,
          color: isLeft ? Cartoon.blue : Cartoon.orange,
          onPressed: () => game.dragonGive(side),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isLeft
                      ? Icons.arrow_back_rounded
                      : Icons.arrow_forward_rounded,
                  color: Colors.white,
                  size: 44,
                ),
                if ((name ?? '').isNotEmpty)
                  Text(
                    name!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Cartoon.userText(size: 14, color: Colors.white),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return _buildDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.gameDragonQuestion,
            style: Cartoon.text(size: 20, height: 1.3),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              pick('left', left?.name, true),
              const SizedBox(width: 12),
              pick('right', right?.name, false),
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
        color: Cartoon.surface(Cartoon.surface(const Color(0xFFD9F3E0))),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Cartoon.ink, width: 1.8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('\u{1F409}', style: TextStyle(fontSize: 20 * _ts)),
          SizedBox(width: 8 * _s),
          Flexible(
            child: Text(message, style: Cartoon.text(size: 16 * _ts)),
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
            style: Cartoon.text(size: 20),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 6,
            runSpacing: 2,
            alignment: WrapAlignment.center,
            children: ranks.map((rank) {
              return SizedBox(
                width: 56,
                child: gameButton(
                  rank,
                  () => game.callRank(rank),
                  color: Cartoon.blue,
                  height: 44,
                  size: 19,
                  expand: true,
                  hPad: 0,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          gameButton(
            L10n.of(context).gameNoCall,
            () => game.callRank('none'),
            color: const Color(0xFFB9B1A8),
            height: 44,
            size: 17,
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

    final myTotal = state.myTeam == 'A'
        ? (state.totalScores['teamA'] ?? 0)
        : (state.totalScores['teamB'] ?? 0);
    final theirTotal = state.myTeam == 'A'
        ? (state.totalScores['teamB'] ?? 0)
        : (state.totalScores['teamA'] ?? 0);
    final myRound = state.myTeam == 'A'
        ? state.lastRoundScores['teamA']
        : state.lastRoundScores['teamB'];
    final theirRound = state.myTeam == 'A'
        ? state.lastRoundScores['teamB']
        : state.lastRoundScores['teamA'];

    return _buildDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: Cartoon.text(size: 30, height: 1.1),
          ),
          const SizedBox(height: 18),
          // 총점을 크게 두 칸으로. 결과 화면에서 눈이 먼저 가는 건 누가
          // 몇 점인가지, "총점:" 이라는 글자가 아니다.
          Row(
            children: [
              Expanded(
                child: _scoreColumn(l10n.gameScoreUs, myTotal, Cartoon.blue),
              ),
              Container(
                width: 1.5,
                height: 48,
                color: Cartoon.ink.withValues(alpha: 0.15),
              ),
              Expanded(
                child: _scoreColumn(
                  l10n.gameScoreThem,
                  theirTotal,
                  Cartoon.red,
                ),
              ),
            ],
          ),
          if (state.lastRoundScores.isNotEmpty) ...[
            const SizedBox(height: 18),
            _dialogHairline(),
            const SizedBox(height: 12),
            // 이번 라운드는 총점 아래 한 줄로. 문구의 콜론은 이 배치에서
            // 군더더기라 떼고 쓴다.
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.gameThisRound.replaceAll(RegExp(r'[:\s]+$'), ''),
                    style: Cartoon.text(
                      size: 16,
                      color: Cartoon.ink.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                Text(
                  '$myRound',
                  style: Cartoon.text(size: 19, color: Cartoon.blue),
                ),
                Text(
                  '  :  ',
                  style: Cartoon.text(
                    size: 16,
                    color: Cartoon.ink.withValues(alpha: 0.35),
                  ),
                ),
                Text(
                  '$theirRound',
                  style: Cartoon.text(size: 19, color: Cartoon.red),
                ),
              ],
            ),
          ],
          if (isGameEnd && game.isRankedRoom) ...[
            const SizedBox(height: 14),
            _buildRankedResult(game),
          ],
          const SizedBox(height: 18),
          _dialogHairline(),
          const SizedBox(height: 12),
          Text(
            isGameEnd ? l10n.gameAutoReturnLobby : l10n.gameAutoNextRound,
            textAlign: TextAlign.center,
            style: Cartoon.text(
              size: 14,
              color: Cartoon.ink.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }

  /// 결과 팝업의 점수 한 칸 — 작은 라벨 위, 큰 숫자 아래.
  Widget _scoreColumn(String label, int score, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: Cartoon.text(
            size: 15,
            color: Cartoon.ink.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '$score',
          style: Cartoon.text(size: 44, color: color, height: 1.1),
        ),
      ],
    );
  }

  /// 머리카락 굵기 구분선. 상자를 또 만들지 않고 영역만 나눈다.
  Widget _dialogHairline() =>
      Container(height: 1.5, color: Cartoon.ink.withValues(alpha: 0.12));

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

    // 테두리 없는 옅은 바탕 한 겹. 팝업 안에서 상자를 또 그리면 층이
    // 겹쳐 보인다 — 색은 티어 뱃지가 이미 들고 있다.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Cartoon.cream,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _rankBadge(tier),
          const SizedBox(width: 10),
          Text(
            L10n.of(context).gameRankedScore(seasonRating as int),
            style: Cartoon.text(size: 17),
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
          Cartoon.onSurface(const Color(0xFFC58B6B)),
          Icons.emoji_events,
        );
    }
  }

  Widget _rankPill(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Cartoon.ink, width: 1.6),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16 * _s, color: Cartoon.ink),
          SizedBox(width: 4 * _s),
          Text(label, style: Cartoon.text(size: 14 * _ts)),
        ],
      ),
    );
  }

  Widget _buildDialog({required Widget child}) {
    // 판을 검게 덮는 대신 흐리게 만든다. 아래에서 벌어진 일이 비쳐 보여야
    // 결과가 그 판의 결말로 읽히고, 검은 장막은 화면을 두 개로 갈라놨다.
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: Container(
        color: const Color(0x40000000),
        child: Center(
          child: Container(
            margin: EdgeInsets.all(32 * _s),
            padding: EdgeInsets.fromLTRB(24 * _s, 22 * _s, 24 * _s, 18 * _s),
            constraints: const BoxConstraints(maxWidth: 320),
            decoration: Cartoon.panelDecoration(radius: 28, shadowOffset: 4),
            child: child,
          ),
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
                  .min(preferredStep, (maxTotalW - 14.0) / (count - 1))
                  .clamp(minStep, preferredStep) *
              scale);
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
                color: Cartoon.ink,
                shape: BoxShape.circle,
                border: Border.all(color: Cartoon.cream, width: 1.4),
              ),
              child: Text(
                '$count',
                style: Cartoon.text(
                  size: 12 * _ts * scale,
                  color: Colors.white,
                ).copyWith(height: 1.0),
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
                    style: Cartoon.text(size: 20 * _ts),
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
                    style: Cartoon.text(
                      size: 13 * _ts,
                      color: Cartoon.ink.withValues(alpha: 0.5),
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
                  style: Cartoon.userText(
                    size: 13 * _ts,
                    color: Cartoon.ink.withValues(alpha: 0.65),
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
        bg: Cartoon.red,
        fg: Colors.white,
        border: Cartoon.ink,
      );
    }
    if (player.hasSmallTichu) {
      return _tichuBadge(
        label: L10n.of(context).gameBadgeSmall,
        bg: Cartoon.blue,
        fg: Colors.white,
        border: Cartoon.ink,
      );
    }
    return null;
  }

  int _selfFinishPosition(GameStateData state) {
    final me = _firstWhereOrNull(state.players, (p) => p.position == 'self');
    return me?.finishPosition ?? 0;
  }

  /// 패를 다 턴 사람 옆에 붙는 순위. 1~3등은 금·은·동으로 구분한다.
  Widget _finishBadge(int rank) {
    // 꼴찌(4등)는 3명이 털면 저절로 정해져서 알릴 거리가 아니다.
    if (rank >= 4) return const SizedBox.shrink();
    // 바탕은 등수를 뜻하는 색이라 팔레트를 따라가지 않는다(금·은·동).
    // 그래서 글자색은 ink 가 아니라 그 바탕에서 끌어내야 한다 — 그대로
    // 두면 어두운 테마에서 노란 1등 뱃지에 밝은 글자가 얹힌다.
    final (Color bg, Color border) = switch (rank) {
      1 => (Cartoon.yellow, Cartoon.ink),
      2 => (Cartoon.surface(const Color(0xFFE3E3E3)), Cartoon.ink),
      3 => (const Color(0xFFE0A877), Cartoon.ink),
      _ => (const Color(0xFFBDBDBD), Cartoon.ink),
    };
    final fg = Cartoon.inkOn(bg);
    // 처음 나타날 때만 통통 튀어나온다. 같은 값으로 다시 그려질 땐 가만히 있다.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 600),
      curve: Curves.elasticOut,
      builder: (context, v, child) =>
          Transform.scale(scale: v.clamp(0.0, 1.4), child: child),
      child: _tichuBadge(
        label: L10n.of(context).gameFinishRank(rank),
        bg: bg,
        fg: fg,
        border: border,
      ),
    );
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Cartoon.ink, width: 1.6),
      ),
      child: Text(
        label,
        style: Cartoon.text(size: 14 * _ts, color: fg),
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
        const horizontalMargin = 4.0;
        final availableWidth = constraints.maxWidth - (horizontalMargin * 2);
        final perRow = cards.length <= 6
            ? cards.length
            : (cards.length / 2).ceil();
        final dense = cards.length >= 13;
        final cardPadding = dense ? 1.5 : 2.5;
        final totalPadding = perRow * cardPadding * 2;
        // Scaled with the board — these were the only card sizes left in
        // absolute pixels, so on a large screen the hand stayed phone-sized
        // while the table around it grew.
        final maxWidth = (dense ? 54.0 : 58.0) * _s;
        final minWidth = (dense ? 34.0 : 38.0) * _s;
        var cardWidth = ((availableWidth - totalPadding) / perRow).clamp(
          minWidth,
          maxWidth,
        );
        final ratio = dense ? 1.35 : 1.4;
        var cardHeight = (cardWidth * ratio).clamp(
          (dense ? 50.0 : 55.0) * _s,
          (dense ? 76.0 : 82.0) * _s,
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

/// 개 카드가 낸 사람 자리에서 선공을 받는 자리로 포물선을 그리며 날아가고,
/// 도착한 자리에는 파동이 퍼진다. 어디서 어디로 갔는지, 그래서 누구 차례인지를
/// 눈으로 바로 보여주기 위한 연출.
class _DogFlight extends StatefulWidget {
  final Offset from;
  final Offset to;
  final double cardWidth;
  final double cardHeight;

  const _DogFlight({
    super.key,
    required this.from,
    required this.to,
    required this.cardWidth,
    required this.cardHeight,
  });

  @override
  State<_DogFlight> createState() => _DogFlightState();
}

class _DogFlightState extends State<_DogFlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        // 0~0.2 제자리에서 떠오름, 0.2~0.75 비행, 이후 도착 파동 + 사라짐.
        final fly = Curves.easeInOutCubic.transform(
          ((t - 0.2) / 0.55).clamp(0.0, 1.0),
        );
        final base = Offset.lerp(widget.from, widget.to, fly)!;
        final arc = -math.sin(fly * math.pi) * 36;
        final pos = base + Offset(0, arc);
        final pop = t < 0.2 ? Curves.easeOutBack.transform(t / 0.2) : 1.0;
        final scale = 0.6 + 0.4 * pop + math.sin(fly * math.pi) * 0.25;
        final opacity = t > 0.85 ? (1 - (t - 0.85) / 0.15) : 1.0;
        final ripple = ((t - 0.7) / 0.3).clamp(0.0, 1.0);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (ripple > 0)
              Positioned(
                left: widget.to.dx - 40,
                top: widget.to.dy - 40,
                width: 80,
                height: 80,
                child: Opacity(
                  opacity: (1 - ripple) * 0.8,
                  child: Transform.scale(
                    scale: 0.5 + ripple * 1.1,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFE6A800),
                          width: 4,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: pos.dx - widget.cardWidth / 2,
              top: pos.dy - widget.cardHeight / 2,
              child: Opacity(
                opacity: opacity.clamp(0.0, 1.0),
                child: Transform.rotate(
                  angle: (1 - fly) * -0.25 + fly * 0.1,
                  child: Transform.scale(
                    scale: scale,
                    // 날아가는 것은 카드가 아니라 강아지다. 선을 넘기는
                    // 동작이라 "패가 테이블로 간다" 가 아니라 "강아지가
                    // 저쪽으로 뛰어간다" 로 보여야 한다. 배경을 지운
                    // 그림이라 판 위를 그대로 가로지른다.
                    //
                    // 그림은 server/tools/make_sk_creature_art.js 가
                    // 카드에서 뽑는다(dog_art.webp).
                    child: Image.asset(
                      'assets/cards/dog_art.webp',
                      height: widget.cardHeight * 1.25,
                      fit: BoxFit.contain,
                      // 그림이 없으면 예전처럼 카드가 날아간다 — 연출이
                      // 통째로 사라지면 선이 누구에게 갔는지 안 보인다.
                      errorBuilder: (_, _, _) => PlayingCard(
                        cardId: 'special_dog',
                        width: widget.cardWidth,
                        height: widget.cardHeight,
                        isInteractive: false,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
