import '../widgets/spectator_bottom_fill.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import '../theme/cartoon.dart';
import '../services/game_service.dart';
import '../services/session_service.dart';
import '../models/sk_game_state.dart';
import '../widgets/afk_kick_badge.dart';
import '../widgets/turn_name_pill.dart';
import '../widgets/connection_overlay.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/seat_chat_bubble.dart';
import '../widgets/bot_avatar.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/player_profile_dialog.dart';
import '../widgets/draggable_chat_panel.dart';
import '../widgets/game_chrome.dart';
import '../widgets/spectator_controls.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n_helpers.dart';
import '../widgets/mid_game_join.dart';
import '../widgets/sk_card_highlight.dart';
import '../widgets/sk_number_card.dart';
import '../widgets/sk_pirate_ability_panel.dart';
import '../widgets/sk_expansion_guide.dart';
import 'sk_board_layout.dart';

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

  // 해적 능력: 방금 쓴 능력을 모두에게 잠깐 알리는 띠(abilitySeq 가 바뀔 때 한 번).
  int _lastAbilitySeq = -1;
  String? _abilityToast;
  Timer? _abilityToastTimer;

  /// 트릭 결과(승자 표시·카드 강조)를 보여 주는 단계 — 능력을 쓰는 동안에도 그대로 둔다.
  bool _trickShown(SKGameStateData state) =>
      state.phase == 'trick_end' || state.phase == 'pirate_ability';

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
    _seatChat.dispose();
    _chatController.dispose();
    _chatScrollController.dispose();
    _countdownTimer?.cancel();
    _gameEndCountdownTimer?.cancel();
    _cardViewRequestTimer?.cancel();
    _abilityToastTimer?.cancel();
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
            child: Stack(
              children: [
                // 손패 창 아래의 안전 영역(홈 바 자리)을 창과 같은 색으로
                // 채운다. 안 채우면 그 띠에 배경 그라데이션이 비쳐 창이
                // 거기서 잘린 것처럼 보인다.
                //
                // 관전자뿐 아니라 플레이어에게도 필요하다 — 아래에 창을
                // 그리는 건 둘 다 같다. 색은 손패 창을 따라간다: 내 차례면
                // 노랗고 아니면 종이색이라, 고정 색으로 채우면 차례가 올
                // 때마다 이음새가 생긴다.
                SpectatorBottomFill(
                  when: (g) => const [
                    'bidding',
                    'playing',
                    'trick_end',
                    'pirate_ability',
                  ].contains(g.skGameState?.phase),
                  color: (g) =>
                      !g.isSpectator && g.skGameState?.isMyTurn == true
                      ? Cartoon.myTurn
                      : Cartoon.paper,
                ),
                Positioned.fill(
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
                        // A spectator with no game is routed to the shared waiting
                        // room before this screen is ever built; from here on it is
                        // only ever the board, watched or played.
                        final isSpectating = game.isSpectator;
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
                          if (_lastSkTrickNumber != -1 &&
                              _selectedCard != null) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              setState(() => _selectedCard = null);
                            });
                          }
                          _lastSkTrickNumber = state.trickNumber;
                        }

                        // 방금 쓴 해적 능력을 모두에게 한 번만 알린다(처음 들어온 화면에서는 건너뜀).
                        if (_lastAbilitySeq != state.abilitySeq) {
                          final firstLook = _lastAbilitySeq == -1;
                          _lastAbilitySeq = state.abilitySeq;
                          final ev = state.lastAbility;
                          if (!firstLook && ev != null) {
                            final text = _abilityEventText(state, ev);
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) _showAbilityToast(text);
                            });
                          }
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
                                    'pirate_ability',
                                  ].contains(state.phase))
                                    _buildBoardStage(
                                      board: _buildSpectatorScoreboard(
                                        state,
                                        game,
                                      ),
                                      bottomOverlay:
                                          _buildSpectatorBottomOverlay(
                                            _buildSpectatorHandArea(
                                              state,
                                              game,
                                            ),
                                          ),
                                    ),
                                  if (state.phase == 'round_end')
                                    _buildBoardStage(
                                      board: _buildSpectatorScoreboard(
                                        state,
                                        game,
                                      ),
                                      // Marker 로 감싸서 좌석 영역(bottomPadding) 이
                                      // playing 상태와 동일하게 50dp 유지 — 라운드
                                      // 결과가 뜰 때마다 좌석이 밀리던 문제 해소.
                                      bottomOverlay:
                                          _buildSpectatorBottomOverlay(
                                            _buildRoundEndUI(state),
                                          ),
                                    ),
                                  if (state.phase == 'game_end')
                                    _buildBoardStage(
                                      board: _buildSpectatorScoreboard(
                                        state,
                                        game,
                                      ),
                                      bottomOverlay:
                                          _buildSpectatorBottomOverlay(
                                            _buildGameEndUI(state, game),
                                          ),
                                    ),
                                ],
                              ),
                              if (state.phase == 'pirate_ability')
                                _buildAbilityWaitingBanner(state),
                              if (_abilityToast != null)
                                _buildAbilityToastBanner(_abilityToast!),
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
                                    state.phase == 'trick_end' ||
                                    state.phase == 'pirate_ability')
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
                            if (state.phase == 'pirate_ability')
                              state.isMyAbilityTurn
                                  ? _buildAbilityPanelLayer(state, game)
                                  : _buildAbilityWaitingBanner(state),
                            if (_abilityToast != null)
                              _buildAbilityToastBanner(_abilityToast!),
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBoardStage({required Widget board, Widget? bottomOverlay}) {
    // 보드가 비우는 높이는 130 으로 둔다(좌석 크기와 위치가 여기서 나온다).
    //
    // 잰 손패 높이로 이 값을 늘리면 보드가 통째로 줄어, 손패가 두 줄인
    // 라운드마다 좌석이 작아지고 위로 몰린다. 손패에 가리는 문제는 보드를
    // 줄여서가 아니라 내가 낸 카드의 위치를 제한해서 푼다
    // (_bottomOverlayHeight 를 쓰는 곳은 거기 한 곳이다).
    return Expanded(
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 130),
              child: board,
            ),
          ),
          if (bottomOverlay != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: double.infinity,
                child: _MeasureHeight(
                  onChange: (h) {
                    if (!mounted) return;
                    // 1dp 미만 변화는 무시한다 — 애니메이션 중에 매 프레임
                    // setState 하면 보드가 떨린다.
                    if ((h - _bottomOverlayHeight).abs() < 1) return;
                    setState(() => _bottomOverlayHeight = h);
                  },
                  child: bottomOverlay,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 아래 창(손패·입찰·라운드 결과)이 실제로 차지하는 높이.
  double _bottomOverlayHeight = 130;

  Widget _buildSpectatorBottomOverlay(Widget child) {
    return _SKSpectatorHandAreaMarker(child: child);
  }

  Widget _buildRecoveryLoading({required String title}) {
    return Center(child: CartoonLoadingCard(title: title));
  }

  /// Avatar for a waiting-room seat: photo, bot art, or the default
  /// silhouette, with the level as a corner badge. The level used to be drawn
  /// AS the avatar for photo-less players, which put a number where every other
  /// screen puts a face — and the bot tag went missing with it.

  /// Wraps a board seat so a chat bubble can hang above it.
  ///
  /// Drawn on the overlay, not inside the seat's own Stack — otherwise the
  /// next seat or the played-card layer paints over it and the line is lost.
  Widget _withSeatBubble(String nickname, Widget seat) {
    return SeatBubbleAnchor(
      text: _seatChat.textFor(nickname),
      styleKey: _seatChat.styleFor(nickname),
      suppressed: _chatOpen,
      child: seat,
    );
  }

  /// The last thing each player said, over their waiting-room seat.
  late final SeatChatBubbles _seatChat = SeatChatBubbles(() {
    if (mounted) setState(() {});
  });

  // ── Top Bar ──
  Widget _buildTopBar(SKGameStateData state, GameService game) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          // Round/Trick info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: gamePillDecoration(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.anchor_rounded, size: 17, color: Cartoon.ink),
                const SizedBox(width: 6),
                Text(
                  L10n.of(
                    context,
                  ).skGameRoundTrick(state.round, state.trickNumber),
                  style: Cartoon.text(size: 16),
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
            icon: Icons.leaderboard_outlined,
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
    final l10n = L10n.of(context);
    // Shared flat header (see SpectatorHeader): this used to be a dark navy
    // pill card unlike any other game's spectator bar.
    return SpectatorHeader(
      game: game,
      statusLine:
          '${l10n.skGameRoundTrick(state.round, state.trickNumber)} · '
          '${state.phase == 'bidding' ? l10n.skGameBiddingInProgress(currentPlayerName) : l10n.skGamePlayerTurn(currentPlayerName)}',
      // On the status line, in the slot Tichu uses for its tappable score
      // chips — the icon-only button in the title row was easy to overlook.
      statusTrailing: SpectatorStatusChip(
        icon: Icons.leaderboard_outlined,
        label: l10n.gameScoreHistory,
        onTap: () => _showScoreHistoryDialog(state),
      ),
      actions: [
        if (state.expansions.isNotEmpty) ...[
          _buildTopActionButton(
            icon: Icons.help_outline,
            active: false,
            onTap: () => _showExpansionGuide(state),
          ),
          const SizedBox(width: 6),
        ],
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
    );
  }

  Widget _buildMoreMenu(GameService game) {
    final hasViewers = game.cardViewers.isNotEmpty;
    return Positioned(
      top: game.isSpectator ? 96 : 58,
      right: 8,
      child: Container(
        // Players see 4 actions (incl. card-view); spectators have no cards so
        // the card-view button is hidden and the menu is narrower.
        width: game.isSpectator ? 158 : 210,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: Cartoon.panelDecoration(radius: 18, shadowOffset: 3),
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
                showSpectatorListDialog(context, game);
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
              iconColor: Cartoon.onSurface(const Color(0xFFE53935)),
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
    return Positioned(
      top: 122,
      right: 8,
      child: SpectatorSoundPanel(game: game, width: 190),
    );
  }

  Widget _buildSpectatorScoreboard(SKGameStateData state, GameService game) {
    _seatChat.consume(game);
    final isLandscape =
        !kIsWeb && MediaQuery.of(context).orientation == Orientation.landscape;
    // 118 wide could not clear the 180-wide trick panel: at 4 opponents the two
    // side seats sit at 172°/368°, i.e. at full X radius and at the panel's own
    // height, and half-seat + half-panel exceeds half the board on a 360dp
    // phone. Narrower box + the avatar moved onto its own row (where it no
    // longer competes with the name for width) buys the clearance and a bigger
    // avatar at the same time.
    // 크기는 sk_board_layout 의 kSkSeatWidthBase /
    // kSkSpectatorSeatHeightBase 에 있다(관전 자리가 더 높은 이유도 거기에).

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          // 플레이어 보드와 같은 계산을 쓴다 — 관전이라고 자리가 더 작아야
          // 할 이유는 없고, 표가 두 벌이면 한쪽만 손보게 된다.
          final playerCount = state.players.length;
          final board = solveSkBoardLayout(
            size: Size(width, height),
            opponentCount: playerCount,
            isLandscape: isLandscape,
            spectator: true,
          );
          final seatWidth = board.seatWidth;
          final seatHeight = board.seatHeight;
          final playedCardHeight = board.playedCardHeight;
          final playedCardW = board.playedCardWidth;
          final centerX = width / 2;
          // 인원별로 링 중심을 아래로 조금씩 내려서 세로 반경 여유를 확보.
          // 예전엔 6인 만 특별 케이스였는데, 3~5인도 상·하단 좌석 간격이
          // 뭉쳐 보인다는 지적을 받아 함께 조정.
          final centerY = playerCount >= 6
              ? height * (isLandscape ? 0.50 : 0.53)
              : playerCount >= 4
              ? height * (isLandscape ? 0.46 : 0.49)
              : height * (isLandscape ? 0.42 : 0.45);
          final maxSeatRadiusX = math.max(0.0, centerX - seatWidth / 2 - 10);
          final seatRadiusX = math.min(
            width * _seatRadiusXFactor(playerCount),
            math.min(
              _seatRadiusXCap(width, playerCount, spectator: true),
              maxSeatRadiusX,
            ),
          );
          final maxSeatRadiusY = math.max(0.0, centerY - seatHeight / 2 - 6);
          // 인원별 세로 반경 비율 — 상·하단 좌석 사이 간격이 결정된다.
          final radiusYRatio = playerCount >= 6
              ? (isLandscape ? 0.42 : 0.45)
              : playerCount >= 4
              ? (isLandscape ? 0.40 : 0.42)
              : (isLandscape ? 0.36 : 0.38);
          final seatRadiusY = math.min(
            height * radiusYRatio,
            math.min(_seatRadiusYCap(height, spectator: true), maxSeatRadiusY),
          );

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Align(
                  // 인원과 상관없이 한자리. 예전에는 2~6인이 세 갈래로
                  // 흩어져 있어서, 방 인원이 바뀔 때마다 트릭을 눈으로 다시
                  // 찾아야 했다. 링 한가운데는 어느 인원에서도 비어 있는
                  // 자리라 6인 기준을 그대로 쓰면 된다.
                  alignment: Alignment(0, isLandscape ? -0.12 : -0.10),
                  child: IgnorePointer(child: _buildTrickArea(state)),
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
                    child: _withSeatBubble(
                      p.name,
                      _buildSpectatorSeat(state, game, p),
                    ),
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
                  final cardLeft = seatLeft + (seatWidth - playedCardW) / 2;
                  // Per seat: a stacked-timeout row pushes that seat's photo
                  // down, so a board-wide offset put the card off the photo on
                  // exactly the seats that had one.
                  final cardTop =
                      seatTop +
                      _skSeatMetrics(
                        seatWidth,
                        seatHeight,
                        hasTimeoutRow: p.timeoutCount > 0,
                        spectator: true,
                      ).photoCentre -
                      playedCardHeight / 2;
                  final trickPlay = state.currentTrick
                      .cast<SKTrickPlay?>()
                      .firstWhere(
                        (play) => play?.playerId == p.id,
                        orElse: () => null,
                      );
                  // 무효 트릭에는 이긴 사람이 없다. lastTrickWinner 는
                  // 그때 "다음 선을 잡을 사람" 을 담고 있을 뿐이라,
                  // 그대로 읽으면 크라켄으로 무효가 된 트릭에서 승리
                  // 표식이 뜬다.
                  final isTrickWinner =
                      _trickShown(state) &&
                      !state.lastTrickVoided &&
                      state.lastTrickWinner == p.id;

                  if (trickPlay == null) return const SizedBox.shrink();
                  return Positioned(
                    left: cardLeft,
                    top: cardTop,
                    child: _buildPlayedCardBadge(
                      trickPlay,
                      highlighted: isTrickWinner,
                      size: playedCardHeight,
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
          color: Cartoon.paper,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          border: Border(top: BorderSide(color: Cartoon.ink, width: 2.2)),
        ),
        child: Text(
          L10n.of(context).skGameTapToRequestCards,
          textAlign: TextAlign.center,
          style: Cartoon.userText(
            size: 14,
            color: Cartoon.ink.withValues(alpha: 0.78),
          ),
        ),
      );
    }

    // Pending — waiting for response
    if (isPending && !isApproved) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Cartoon.paper,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          border: Border(top: BorderSide(color: Cartoon.ink, width: 2.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: Cartoon.orange,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              L10n.of(context).skGameRequestingCardView(viewingPlayer.name),
              style: Cartoon.userText(
                size: 14,
                color: Cartoon.ink.withValues(alpha: 0.78),
              ),
            ),
          ],
        ),
      );
    }

    // Approved — show hand
    if (isApproved) {
      return SpectatorHandWithChip(
        label: L10n.of(context).skGamePlayerHand(viewingPlayer.name),
        onClose: () => setState(() => _viewingPlayerId = null),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          decoration: BoxDecoration(
            color: Cartoon.paper,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            border: Border(top: BorderSide(color: Cartoon.ink, width: 2.2)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (viewingPlayer.cards.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    L10n.of(context).skGameNoCards,
                    style: Cartoon.text(
                      size: 13,
                      color: Cartoon.ink.withValues(alpha: 0.78),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: _buildHandRows(
                    viewingPlayer.cards,
                    interactive: false,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    // Not pending, not approved — rejected or timed out, show hint
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Cartoon.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(top: BorderSide(color: Cartoon.ink, width: 2.2)),
      ),
      child: Text(
        L10n.of(context).skGameCardViewRejected(viewingPlayer.name),
        textAlign: TextAlign.center,
        style: Cartoon.userText(
          size: 14,
          color: Cartoon.ink.withValues(alpha: 0.78),
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
    final primaryColor = urgent ? Cartoon.red : Cartoon.ink;
    final timerText = L10n.of(context).skGameSecondsShort(_remainingSeconds);

    final boxDecoration = gamePillDecoration(
      radius: 16,
      color: urgent ? Cartoon.surface(const Color(0xFFFFD9D6)) : Cartoon.cream,
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
                style: Cartoon.text(
                  size: 13,
                  color: urgent
                      ? Cartoon.red
                      : Cartoon.ink.withValues(alpha: 0.78),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                currentPlayerName,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Cartoon.userText(size: 17, color: primaryColor),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.schedule, size: 13, color: primaryColor),
                  const SizedBox(width: 4),
                  Text(
                    timerText,
                    style: Cartoon.text(size: 16, color: primaryColor),
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
                style: Cartoon.userText(size: 15, color: primaryColor),
              ),
            ),
            const SizedBox(width: 4),
            Text(timerText, style: Cartoon.text(size: 16, color: primaryColor)),
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

  /// 이 방에 들어간 확장팩 카드 안내. 방 대기실과 같은 시트를 쓴다
  /// (widgets/sk_expansion_guide.dart) — 설명이 두 벌이면 한쪽만 고쳐진다.
  ///
  /// 카드 그림은 이 화면의 것을 넘긴다. 테두리·그림자·이름표가 붙은
  /// 모양이라 게임 중에 보던 것과 같아야 한다.
  void _showExpansionGuide(SKGameStateData state) {
    showSkExpansionGuide(
      context,
      state.expansions,
      cardBuilder: (cardId, size) =>
          _buildCard(cardId, size: size, showName: true),
    );
  }

  void _showExitConfirmDialog(GameService game) {
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
          L10n.of(context).skGameLeaveTitle,
          style: Cartoon.text(size: 22),
        ),
        // A mid-game-join room hands the seat to a bot instead of ending
        // the match; say so rather than warning about the wrong outcome.
        content: Text(
          game.canLeaveInProgress
              ? L10n.of(
                  context,
                ).midLeaveConfirmBody(kMidGameJoinCooldownMinutes)
              : L10n.of(context).skGameLeaveConfirm,
          style: Cartoon.text(size: 16.5, height: 1.4),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(foregroundColor: Cartoon.ink),
            child: Text(
              L10n.of(context).commonCancel,
              style: Cartoon.text(size: 17),
            ),
          ),
          gameButton(L10n.of(context).skGameLeaveButton, () {
            Navigator.pop(ctx);
            game.leaveGame();
          }, color: Cartoon.red),
        ],
      ),
    );
  }

  // ── Scoreboard ──
  Widget _buildScoreboard(SKGameStateData state, GameService game) {
    _seatChat.consume(game);
    final isLandscape =
        !kIsWeb && MediaQuery.of(context).orientation == Orientation.landscape;
    // 118 wide could not clear the 180-wide trick panel: at 4 opponents the two
    // side seats sit at 172°/368°, i.e. at full X radius and at the panel's own
    // height, and half-seat + half-panel exceeds half the board on a 360dp
    // phone. Narrower box + the avatar moved onto its own row (where it no
    // longer competes with the name for width) buys the clearance and a bigger
    // avatar at the same time.
    // 크기는 sk_board_layout 의 kSkSeatWidthBase / kSkSeatHeightBase 에 있다.
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
    // 무효 트릭에는 이긴 사람이 없다 — 위 상대 자리와 같은 이유.
    final isSelfTrickWinner =
        _trickShown(state) &&
        !state.lastTrickVoided &&
        state.lastTrickWinner == selfPlayer?.id;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          // 자리·카드 크기와 링 반지름은 sk_board_layout 이 정한다.
          //
          // 전에는 여기서 상수를 곱해 썼는데, 그러면 "조금 키우기" 가
          // 인원수마다 다른 작업이 된다 — 2~3인에서 알맞은 크기가 5~6인
          // 에서는 겹친다. solve 가 그 화면·그 인원에서 겹치지 않는 가장
          // 큰 값을 찾아 준다(테스트: sk_board_layout_test.dart).
          final opponentCount = opponents.length;
          final board = solveSkBoardLayout(
            size: Size(width, height),
            opponentCount: opponentCount,
            isLandscape: isLandscape,
            spectator: false,
          );
          final seatWidth = board.seatWidth;
          final seatHeight = board.seatHeight;
          final playedCardHeight = board.playedCardHeight;
          final playedCardW = board.playedCardWidth;
          final centerX = board.center.dx;
          final centerY = board.center.dy;
          final seatRadiusX = board.radiusX;
          final seatRadiusY = board.radiusY;
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
          // 내가 낸 카드는 손패 위에 머물러야 한다.
          //
          // 보드는 아래 130 만 비우는데 손패는 카드가 두 줄이면 그보다
          // 높아진다(라운드가 올라가면 10장까지 간다). 그 차이만큼 카드가
          // 덮였다 — "간혹" 이던 이유도 이것이다. 장수가 적은 라운드에서는
          // 130 안에 들어가 가려지지 않는다.
          //
          // 보드를 줄이는 대신 카드만 올린다. 보드를 줄이면 좌석 크기와
          // 자리가 손에 든 장수에 따라 흔들린다.
          const boardBottomPad = 130.0;
          final handTopInBoard =
              height +
              boardBottomPad -
              math.max(boardBottomPad, _bottomOverlayHeight);
          final selfCardCeiling = math.min(
            height - playedCardHeight - 4,
            handTopInBoard - playedCardHeight - 6,
          );
          final selfCardTop = math.min(
            selfCardCeiling,
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
                  // 상대 2~3명은 상단에 몰리므로 트릭을 -0.15 로 올리고,
                  // 4명(5인 게임) 도 옆 두 자리(172°/368°) 가 mid-side 라
                  // 트릭이 링 아래에 붙어 보이던 것을 -0.05 로 조금 올린다.
                  //
                  // 5명(6인 게임)은 자리가 아래까지 내려와 트릭이 링 바닥에
                  // 붙었다. 0.46 → 0.30 으로 올린다. 좌석이 커지면서 링도
                  // 함께 넓어져 아래쪽 여유가 줄어든 탓이 크다.
                  alignment: Alignment(
                    0,
                    opponents.length <= 3
                        ? (isLandscape ? -0.18 : -0.15)
                        : opponents.length == 4
                        ? (isLandscape ? -0.08 : -0.05)
                        : (isLandscape ? 0.22 : 0.30),
                  ),
                  child: Transform.translate(
                    offset: Offset(
                      0,
                      opponents.length <= 4
                          ? 0
                          : (isLandscape ? -34 : -42) + twoOpponentTrickDrop,
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
                    child: _withSeatBubble(
                      p.name,
                      _buildPlayerSeat(state, game, p, isSelf: false),
                    ),
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
                  final cardLeft = seatLeft + (seatWidth - playedCardW) / 2;
                  final cardTop =
                      seatTop +
                      _skSeatMetrics(
                        seatWidth,
                        seatHeight,
                        hasTimeoutRow: p.timeoutCount > 0,
                      ).photoCentre -
                      playedCardHeight / 2;
                  final trickPlay = state.currentTrick
                      .cast<SKTrickPlay?>()
                      .firstWhere(
                        (play) => play?.playerId == p.id,
                        orElse: () => null,
                      );
                  // 무효 트릭에는 이긴 사람이 없다. lastTrickWinner 는
                  // 그때 "다음 선을 잡을 사람" 을 담고 있을 뿐이라,
                  // 그대로 읽으면 크라켄으로 무효가 된 트릭에서 승리
                  // 표식이 뜬다.
                  final isTrickWinner =
                      _trickShown(state) &&
                      !state.lastTrickVoided &&
                      state.lastTrickWinner == p.id;

                  if (trickPlay == null) return const SizedBox.shrink();
                  return Positioned(
                    left: cardLeft,
                    top: cardTop,
                    child: _buildPlayedCardBadge(
                      trickPlay,
                      highlighted: isTrickWinner,
                      size: playedCardHeight,
                    ),
                  );
                }(),
              ],
              if (selfTrickPlay != null)
                Positioned(
                  left: centerX - playedCardW / 2,
                  top: selfCardTop,
                  child: _buildPlayedCardBadge(
                    selfTrickPlay,
                    highlighted: isSelfTrickWinner,
                    size: playedCardHeight,
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

  /// 자리 각도 표는 sk_board_layout.dart 에 한 벌만 둔다.
  ///
  /// 보드 크기를 정하는 계산(solveSkBoardLayout)과 자리를 그리는 이쪽이
  /// 다른 표를 쓰면, 겹치지 않는다고 계산해 놓고 화면에서는 겹친다.
  List<double>? _customSeatAnglesDeg(int count) =>
      skSeatAnglesDeg(count, spectator: false);

  List<double>? _customSpectatorSeatAnglesDeg(int count) =>
      skSeatAnglesDeg(count, spectator: true);

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

  /// Where the photo's centre sits inside a seat box, measured from its top,
  /// and how big the photo is. The board places the played card from this and
  /// the seat sizes its avatar from it — one source, so they cannot drift.
  /// SK 좌석 안의 아바타 반경 + 사진 중심의 실제 렌더 y (좌석 top 기준).
  ///
  /// 좌석 카드의 Column 은 FittedBox(scaleDown) 에 감싸져 있어 seatHeight
  /// 를 넘으면 축소된다. 낸 카드는 좌석 밖 별도 Positioned 로 그려지므로
  /// 위치가 실제 사진 중심과 일치하려면 FittedBox 의 축소 비율을 반영해서
  /// 계산해야 한다 (마이티와 동일 규칙).
  static ({double avatar, double photoCentre}) _skSeatMetrics(
    double seatWidth,
    double seatHeight, {
    bool hasTimeoutRow = false,
    bool spectator = false,
  }) {
    final compact = spectator
        ? (seatHeight <= 72 || seatWidth <= 90)
        : (seatHeight <= 70 || seatWidth <= 96);
    final seatScale = (seatWidth / 116.0).clamp(0.9, 1.5);
    final timeoutHeight = hasTimeoutRow
        ? (compact ? (spectator ? 12.0 : 11.0) : (spectator ? 16.0 : 12.0))
        : 0.0;
    final spacing = compact ? 1.0 : 2.0;
    // _buildSpectatorSeat / _buildPlayerSeat 의 값과 동일해야 사진 위치가
    // 계산과 어긋나지 않는다.
    final nameFontSize = spectator
        ? (compact ? 11.5 : 13.0) * seatScale
        : (compact ? 11.5 : 13.0) * seatScale;
    final scoreFontSize = spectator
        ? (compact ? 15.0 : 17.0) * seatScale
        : (compact ? 15.0 : 17.0) * seatScale;
    final bidHeight = (compact ? 20.0 : 24.0) * seatScale;
    final avatar = kIsWeb
        ? math
              .min(seatHeight * 0.72, seatWidth * 0.74)
              .clamp(52.0, 180.0)
              .toDouble()
        : (seatHeight * 0.72).clamp(52.0, 124.0).toDouble();
    // Column 자연 높이. (timeout row 는 hasTimeoutRow 로 반영, 나머지는 항상
    // 노출된다.)
    final scoreRowHeight = math.max(scoreFontSize * 1.35, bidHeight);
    final intrinsicHeight =
        timeoutHeight +
        avatar +
        spacing +
        nameFontSize * 1.35 +
        spacing +
        scoreRowHeight;
    final fittedScale = intrinsicHeight <= seatHeight
        ? 1.0
        : seatHeight / intrinsicHeight;
    final unscaledPhotoCentre = timeoutHeight + avatar / 2;
    return (avatar: avatar, photoCentre: unscaledPhotoCentre * fittedScale);
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
      // Tapping a seat asks to see that player's cards, which left a spectator
      // with no way to open a profile at all — so no way to block or report
      // someone whose nickname or photo is the problem. Long-press is the only
      // free gesture here; the tap has to stay on card view.
      onLongPress: () => _showPlayerProfileDialog(p.name, game, isBot: p.isBot),
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
          // 90, not 98: the seat box is exactly 98 wide, so `<= 98` was always
          // true and every spectator seat silently took the compact sizes.
          final compact =
              constraints.maxHeight <= 72 || constraints.maxWidth <= 90;
          final horizontalPadding = compact ? 5.0 : 6.0;
          final timeoutHeight = compact ? 12.0 : 16.0;
          final offlineIconSize = compact ? 10.0 : 12.0;
          // Sized against the name it sits beside; the seat is inside a
          // FittedBox, so this scales down with everything else on a tight
          // board rather than pushing the name out.
          // Same source as the board's card placement, and the same rule the
          // player seats use — this used to be its own `maxHeight * 0.5`, which
          // both disagreed with where the board put the played card and came
          // out ~40dp once the FittedBox scaled the label down.
          final avatarSize = _skSeatMetrics(
            constraints.maxWidth,
            constraints.maxHeight,
            hasTimeoutRow: p.timeoutCount > 0,
            spectator: true,
          ).avatar;
          final seatScale = (constraints.maxWidth / 116.0).clamp(0.9, 1.5);
          final nameFontSize = (compact ? 11.5 : 13.0) * seatScale;
          final scoreFontSize = (compact ? 15.0 : 17.0) * seatScale;
          final bidHeight = (compact ? 20.0 : 24.0) * seatScale;
          final bidFontSize = (compact ? 10.5 : 11.5) * seatScale;
          final bidHorizontalPadding = compact ? 4.0 : 6.0;
          final spacing = compact ? 1.0 : 2.0;
          // Hugs the photo — 좌석 컨테이너의 배경/패딩을 없애서 사진 자체가
          // 좌석의 가장자리다. 이름/점수는 아래로 흐른다.
          final contentWidth = math.max(
            avatarSize + 6,
            math.min(
              (constraints.maxWidth - horizontalPadding * 2) * 0.7,
              avatarSize + 20,
            ),
          );

          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.zero,
            decoration: const BoxDecoration(),
            // Top-aligned, not centred: the board positions the played card
            // from the seat's top edge, so a label that floats vertically makes
            // the card sit slightly off the photo.
            child: Align(
              alignment: Alignment.topCenter,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: contentWidth,
                  child: Opacity(
                    opacity: p.connected ? 1.0 : 0.45,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (p.timeoutCount > 0)
                          SizedBox(
                            height: timeoutHeight,
                            child: Text(
                              '⏱ ${p.timeoutCount}/3',
                              style: Cartoon.text(
                                size: compact ? 9.5 : 11,
                                color: Cartoon.orangeDeep,
                              ),
                            ),
                          ),
                        // 프로필 사진에 뱃지(관전 눈)를 바로 붙인다 —
                        // 좌석 컨테이너의 코너에 걸어놓던 방식은 이름/
                        // 점수 위쪽 여백에 뜬 것처럼 보였다.
                        Padding(
                          padding: EdgeInsets.only(bottom: spacing),
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: [
                              ProfileAvatar(
                                photoUrl: game.resolvePhotoUrl(p.photoUrl),
                                size: avatarSize,
                                blocked: game.blockedUsers.contains(p.name),
                                border: Border.all(
                                  color: isViewing
                                      ? Cartoon.blue
                                      : isCurrentTurn
                                      ? Cartoon.orange
                                      : Cartoon.ink,
                                  width: (isCurrentTurn || isViewing)
                                      ? 3.0
                                      : 2.0,
                                ),
                                fallback: p.isBot
                                    ? BotAvatar(size: avatarSize, name: p.name)
                                    : DefaultAvatar(size: avatarSize),
                              ),
                              Positioned(
                                right: -4,
                                top: -4,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: Cartoon.cream,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Cartoon.ink,
                                      width: 1.6,
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
                                        ? Cartoon.orangeDeep
                                        : isApproved
                                        ? Cartoon.blue
                                        : Cartoon.ink.withValues(alpha: 0.55),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // 지금 차례면 이름에 노란 알약 — 티츄 판과 같은 표시.
                        TurnNamePill(
                          isTurn: isCurrentTurn,
                          horizontal: compact ? 5 : 7,
                          vertical: 1,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!p.connected)
                                Padding(
                                  padding: EdgeInsets.only(
                                    right: compact ? 2 : 3,
                                  ),
                                  child: Icon(
                                    Icons.wifi_off,
                                    size: offlineIconSize,
                                    color: Cartoon.red,
                                  ),
                                ),
                              Flexible(
                                child: Text(
                                  p.name,
                                  style: Cartoon.userText(
                                    size: nameFontSize,
                                    color: p.connected
                                        ? Cartoon.ink
                                        : Cartoon.red,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: spacing),
                        // Score and bid chip on one row. The chip used to
                        // sit on its own row below the score, and that
                        // row came straight out of the photo's height.
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${p.totalScore}',
                              style: Cartoon.text(size: scoreFontSize),
                            ),
                            SizedBox(
                              height: bidHeight,
                              child: Center(
                                child: p.hasBid && p.bid != null
                                    ? _skBidChip(
                                        '${p.tricks}/${p.bid}',
                                        p.tricks == p.bid
                                            ? Cartoon.surface(
                                                const Color(0xFFCDEFD6),
                                              )
                                            : p.tricks > p.bid!
                                            ? Cartoon.surface(
                                                const Color(0xFFFFE0B8),
                                              )
                                            : Cartoon.cream,
                                        bidFontSize + 1.5,
                                        bidHorizontalPadding,
                                      )
                                    : p.hasBid && p.bid == null
                                    ? _skBidChip(
                                        null,
                                        Cartoon.cream,
                                        bidFontSize + 1.5,
                                        bidHorizontalPadding,
                                      )
                                    : null,
                              ),
                            ),
                          ],
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
          final timeoutHeight = compact ? 12.0 : 16.0;
          final offlineIconSize = compact ? 10.0 : 12.0;
          final seatScale = (constraints.maxWidth / 116.0).clamp(0.9, 1.5);
          final nameFontSize = isSelf
              ? 14.0
              : (compact ? 11.5 : 13.0) * seatScale;
          final scoreFontSize = isSelf
              ? 18.0
              : (compact ? 15.0 : 17.0) * seatScale;
          final bidHeight = (compact ? 20.0 : 24.0) * seatScale;
          final bidFontSize = (compact ? 10.5 : 11.5) * seatScale;
          final bidHorizontalPadding = compact ? 4.0 : 6.0;
          final spacing = compact ? 1.0 : 2.0;
          // Same source as the board's card placement — see _skSeatMetrics.
          final avatarDiameter = _skSeatMetrics(
            constraints.maxWidth,
            constraints.maxHeight,
          ).avatar;
          // Hugs the photo — 좌석 배경/패딩을 없애서 사진 자체가 좌석의
          // 가장자리. 이름/점수/입찰 뱃지는 아래로 흐른다.
          final contentWidth = math.max(
            avatarDiameter + 6,
            math.min(
              (constraints.maxWidth - horizontalPadding * 2) * 0.7,
              avatarDiameter + 20,
            ),
          );

          return AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: EdgeInsets.zero,
            decoration: const BoxDecoration(),
            // Top-aligned, not centred: the board positions the played card
            // from the seat's top edge, so a label that floats vertically makes
            // the card sit slightly off the photo.
            child: Align(
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
                      if (p.timeoutCount > 0)
                        SizedBox(
                          height: timeoutHeight,
                          child: Text(
                            '⏱ ${p.timeoutCount}/3',
                            style: Cartoon.text(
                              size: compact ? 10 : 12,
                              color: Cartoon.orangeDeep,
                            ),
                          ),
                        ),
                      // 현재턴 테두리는 ProfileAvatar 에 직접 넘겨 사진의
                      // 라운드 코너와 정확히 같은 곡률로 감싼다.
                      Padding(
                        padding: EdgeInsets.only(bottom: spacing),
                        child: AfkKickBadge(
                          game: game,
                          nickname: p.name,
                          avatarSize: avatarDiameter,
                          child: ProfileAvatar(
                            photoUrl: game.resolvePhotoUrl(p.photoUrl),
                            size: avatarDiameter,
                            blocked: game.blockedUsers.contains(p.name),
                            border: isCurrentTurn
                                ? Border.all(color: Cartoon.orange, width: 3)
                                : Border.all(color: Cartoon.ink, width: 2),
                            fallback: p.isBot
                                ? BotAvatar(size: avatarDiameter, name: p.name)
                                : DefaultAvatar(size: avatarDiameter),
                          ),
                        ),
                      ),
                      // 지금 차례면 이름에 노란 알약 — 티츄 판과 같은 표시.
                      TurnNamePill(
                        isTurn: isCurrentTurn,
                        horizontal: compact ? 5 : 7,
                        vertical: 1,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!p.connected)
                              Padding(
                                padding: EdgeInsets.only(
                                  right: compact ? 2 : 3,
                                ),
                                child: Icon(
                                  Icons.wifi_off,
                                  size: offlineIconSize,
                                  color: Cartoon.onSurface(
                                    Cartoon.onSurface(const Color(0xFFE53935)),
                                  ),
                                ),
                              ),
                            Flexible(
                              child: Text(
                                p.name,
                                style: Cartoon.userText(
                                  size: nameFontSize + 1,
                                  color: p.connected
                                      ? Cartoon.ink
                                      : Cartoon.red,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: spacing),
                      Text(
                        '${p.totalScore}',
                        style: Cartoon.text(size: scoreFontSize + 3),
                      ),
                      SizedBox(
                        height: bidHeight,
                        // Center 로 감싸야 칩이 내용 크기로 가운데에 놓인다. 안 감싸면
                        // SizedBox 의 꽉 찬 높이를 받아 글자가 왼쪽 위로 쏠린다.
                        child: Center(
                          child: p.hasBid && p.bid != null
                              ? _skBidChip(
                                  '${p.tricks}/${p.bid}',
                                  p.tricks == p.bid
                                      ? Cartoon.surface(const Color(0xFFCDEFD6))
                                      : p.tricks > p.bid!
                                      ? Cartoon.surface(const Color(0xFFFFE0B8))
                                      : Cartoon.cream,
                                  bidFontSize + 1.5,
                                  bidHorizontalPadding,
                                )
                              : p.hasBid && p.bid == null
                              ? _skBidChip(
                                  null,
                                  Cartoon.cream,
                                  bidFontSize + 1.5,
                                  bidHorizontalPadding,
                                )
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// [size] is the card's height, and must be the same value the board used to
  /// place it. It used to be hardcoded at 72 while the board positioned the
  /// card from `72 * boardScale`, so on any screen where boardScale wasn't
  /// exactly 1 the card landed off the photo's centre — right of it in game
  /// (scale > 1), left of it while spectating (scale < 1).
  Widget _buildPlayedCardBadge(
    SKTrickPlay play, {
    required bool highlighted,
    double size = 72,
  }) {
    final isTigressChoice =
        play.tigressChoice == 'pirate' || play.tigressChoice == 'escape';
    // 낸 티그리스는 고른 모양의 그림으로 그린다(_buildCard 의 playedAs).
    // 티그리스였다는 사실은 이름표와 아래 모서리 표식이 말해 준다.
    final l10n = L10n.of(context);
    final card = _buildCard(
      play.cardId,
      size: size,
      highlighted: highlighted,
      showName: true,
      playedAs: play.tigressChoice,
      nameOverride: play.tigressChoice == 'pirate'
          ? '${l10n.skCardTigress}·${l10n.skCardPirate}'
          : play.tigressChoice == 'escape'
          ? '${l10n.skCardTigress}·${l10n.skCardEscape}'
          : null,
    );
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
              color: Cartoon.onSurface(const Color(0xFF7E57C2)),
              shape: BoxShape.circle,
              border: Border.all(color: Cartoon.ink, width: 1.6),
            ),
            child: Icon(
              Icons.check,
              size: 13,
              color: Cartoon.surface(Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  // ── 해적 능력 ──

  String _abilityPlayerName(SKGameStateData state, String id) {
    for (final p in state.players) {
      if (p.id == id) return p.name;
    }
    return id;
  }

  /// 능력을 다 쓴 뒤 띄우는 알림.
  ///
  /// 해적 이름을 반드시 넣는다. 결과만 적으면("○○님이 △△님을 다음 선으로
  /// 골랐어요") 능력을 처음 보는 사람은 왜 선이 바뀌었는지 알 수 없다.
  String _abilityEventText(SKGameStateData state, SKAbilityEvent ev) {
    final l10n = L10n.of(context);
    final name = _abilityPlayerName(state, ev.playerId);
    final pirate = skPirateName(l10n, ev.pirate);
    switch (ev.pirate) {
      case 'rosie':
        return l10n.skAbilityEventRosie(
          name,
          _abilityPlayerName(state, ev.targetId ?? ''),
          pirate,
        );
      case 'bendt':
        return l10n.skAbilityEventBendt(name, ev.count ?? 2, pirate);
      case 'rascal':
        return (ev.wager ?? 0) > 0
            ? l10n.skAbilityEventRascal(name, ev.wager!, pirate)
            : l10n.skAbilityEventRascalNone(name, pirate);
      case 'harry':
        return (ev.delta ?? 0) != 0
            ? l10n.skAbilityEventHarry(name, ev.bid ?? 0, pirate)
            : l10n.skAbilityEventHarryKeep(name, pirate);
      default:
        return l10n.skAbilityEventJuanita(name, pirate);
    }
  }

  void _showAbilityToast(String text) {
    _abilityToastTimer?.cancel();
    setState(() => _abilityToast = text);
    _abilityToastTimer = Timer(const Duration(milliseconds: 3200), () {
      if (mounted) setState(() => _abilityToast = null);
    });
  }

  Widget _buildAbilityToastBanner(String text) {
    // 대기 안내(top: 64)와 겹치지 않게 그 아래에 띄운다.
    return Positioned(
      top: 124,
      left: 20,
      right: 20,
      child: IgnorePointer(
        child: CartoonEntrance(
          from: const Offset(0, -10),
          child: GameNoticeBar(
            icon: Icons.sailing_rounded,
            color: Cartoon.yellow,
            text: text,
          ),
        ),
      ),
    );
  }

  /// 다른 사람이 능력을 고르는 동안 보여 주는 안내(관전자도 같다).
  Widget _buildAbilityWaitingBanner(SKGameStateData state) {
    final ab = state.pendingAbility;
    if (ab == null) return const SizedBox.shrink();
    final l10n = L10n.of(context);
    return Positioned(
      top: 64,
      left: 20,
      right: 20,
      child: IgnorePointer(
        child: GameNoticeBar(
          icon: Icons.sailing_rounded,
          color: Cartoon.yellow,
          text: l10n.skAbilityWaiting(
            _abilityPlayerName(state, ab.playerId),
            skPirateName(l10n, ab.pirate),
          ),
        ),
      ),
    );
  }

  /// 내가 능력을 쓸 차례 — 화면을 살짝 어둡게 하고 선택 패널을 띄운다.
  Widget _buildAbilityPanelLayer(SKGameStateData state, GameService game) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.45),
        alignment: Alignment.center,
        child: SkAbilityPanel(
          state: state,
          buildCard: (id, {size = 60, highlight = SkCardHighlight.none}) =>
              _buildCard(
                id,
                size: size,
                highlightKind: highlight,
                showName: true,
              ),
          // 로지로 다음 선을 고를 때 테이블과 같은 자리에 놓기 위해,
          // 좌석 각도 계산을 그대로 넘긴다. 관전자는 자기 자리가 없어
          // 각도 표가 다르므로 그쪽 계산을 쓴다.
          seatAngle: (i, count) => game.isSpectator
              ? _spectatorSeatAngleForIndex(i, count)
              : _topSeatAngleForIndex(i, count),
          onUse: ({leaderId, discard, wager, delta}) => game.skUsePirateAbility(
            leaderId: leaderId,
            discard: discard,
            wager: wager,
            delta: delta,
          ),
        ),
      ),
    );
  }

  Widget _buildSKErrorBanner(String message) {
    return Positioned(
      bottom: 200,
      left: 20,
      right: 20,
      child: GameNoticeBar(
        icon: Icons.warning_rounded,
        text: localizeServiceMessage(message, L10n.of(context)),
      ),
    );
  }

  Widget _buildSKTimeoutBanner(String playerName) {
    return Positioned(
      bottom: 240,
      left: 20,
      right: 20,
      child: GameNoticeBar(
        icon: Icons.timer_off_rounded,
        color: Cartoon.yellow,
        text: L10n.of(context).skGameTimeout(playerName),
      ),
    );
  }

  Widget _buildSKDesertionBanner(String playerName, String reason) {
    return Positioned(
      bottom: 240,
      left: 20,
      right: 20,
      child: GameNoticeBar(
        icon: Icons.person_off_rounded,
        text: reason == 'timeout'
            ? L10n.of(context).skGameDesertionTimeout(playerName)
            : L10n.of(context).skGameDesertionLeave(playerName),
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
                      L10n.of(context).skGameCardViewRequest(spectatorNickname),
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
                      L10n.of(context).skGameReject,
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
                      L10n.of(context).skGameAllow,
                      () => game.respondCardViewRequest(spectatorId, true),
                      color: Cartoon.blue,
                      height: 44,
                      size: 16,
                      expand: true,
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
      accentColor: Cartoon.onSurface(const Color(0xFF21455F)),
      // Skull King's own navy, not Tichu's blue — this panel sits on the SK
      // board and the send icon was the one thing on it wearing another game's
      // colour.
      sendIconColor: Cartoon.onSurface(const Color(0xFF21455F)),
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
      top: game.isSpectator ? 96 : 58,
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
                    L10n.of(context).skGameViewingMyHand,
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
                L10n.of(context).skGameNoViewers,
                style: Cartoon.text(
                  size: 13,
                  color: Cartoon.ink.withValues(alpha: 0.78),
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
      mineColor: Cartoon.onSurface(const Color(0xFF21455F)),
    );
  }

  void _showScoreHistoryDialog(SKGameStateData state) {
    final cumulativeScores = <String, int>{
      for (final p in state.players) p.id: 0,
    };

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: BorderSide(color: Cartoon.ink, width: 2.5),
        ),
        backgroundColor: Cartoon.paper,
        surfaceTintColor: Colors.transparent,
        titlePadding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
        contentPadding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        title: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Cartoon.yellow,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Cartoon.inkOn(Cartoon.yellow),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      Icons.emoji_events_rounded,
                      size: 23,
                      color: Cartoon.inkOn(Cartoon.yellow),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    L10n.of(context).skGameScoreHistory,
                    style: Cartoon.text(size: 22),
                  ),
                ],
              ),
            ),
            Text(
              '${state.scoreHistory.length}R',
              style: Cartoon.text(
                size: 15,
                color: Cartoon.ink.withValues(alpha: 0.78),
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
                  Color? color,
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
                      style: Cartoon.userText(
                        size: fontSize + 2,
                        color: color ?? Cartoon.ink,
                        weight: fontWeight,
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
                      decoration: BoxDecoration(
                        color: Cartoon.cream,
                        border: Border(
                          bottom: BorderSide(
                            color: Cartoon.ink.withValues(alpha: 0.2),
                            width: 1,
                          ),
                        ),
                      ),
                      children: [
                        cell(
                          'R',
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: Cartoon.orangeDeep,
                        ),
                        ...state.players.map(
                          (p) => cell(
                            p.name.length > 4 ? p.name.substring(0, 4) : p.name,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            color: p.position == 'self'
                                ? Cartoon.blue
                                : Cartoon.orangeDeep,
                          ),
                        ),
                      ],
                    ),
                    ...state.scoreHistory.asMap().entries.map((mapEntry) {
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
                        decoration: BoxDecoration(color: null),
                        children: [
                          cell(
                            '${entry['round']}',
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: Cartoon.ink.withValues(alpha: 0.55),
                          ),
                          ...state.players.map((p) {
                            final pScore =
                                scores[p.id] as Map<String, dynamic>?;
                            if (pScore == null) {
                              return cell(
                                '-',
                                color: Cartoon.ink.withValues(alpha: 0.3),
                              );
                            }
                            final roundScore =
                                (pScore['roundScore'] as num?)?.toInt() ?? 0;
                            final scoreColor = roundScore < 0
                                ? Cartoon.red
                                : Cartoon.ink;

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
                      decoration: BoxDecoration(
                        color: Cartoon.cream,
                        border: Border(
                          top: BorderSide(
                            color: Cartoon.ink.withValues(alpha: 0.2),
                            width: 1.5,
                          ),
                        ),
                      ),
                      children: [
                        cell(
                          L10n.of(context).commonTotal,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: Cartoon.ink,
                        ),
                        ...state.players.map((p) {
                          final total = cumulativeScores[p.id] ?? 0;
                          return cell(
                            '$total',
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            color: total < 0 ? Cartoon.red : Cartoon.ink,
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
            style: TextButton.styleFrom(foregroundColor: Cartoon.ink),
            child: Text(
              L10n.of(context).commonClose,
              style: Cartoon.text(size: 17),
            ),
          ),
        ],
      ),
    );
  }

  // ── Trick Area ──
  Widget _buildTrickArea(SKGameStateData state) {
    if (state.currentTrick.isEmpty) {
      // Center 감싸면 부모 Align 이 자식을 무한 크기로 받아 alignment 가
      // 무효화된다 — 내용만큼만 차지하도록 Container 를 직접 return.
      // 배경 없이 아이콘·텍스트만 얹는다 — 좌석 링 안에 흰 상자가 떠 있는
      // 모양이 무거워 보였다.
      return Container(
        width: 164,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.anchor_rounded,
              size: 26,
              color: Cartoon.ink.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 4),
            Text(
              state.phase == 'bidding'
                  ? L10n.of(context).skGameBiddingPhase
                  : L10n.of(context).skGamePlayCard,
              style: Cartoon.text(
                size: 17,
                color: Cartoon.ink.withValues(alpha: 0.78),
              ),
            ),
            _buildCenterTimerBadge(state),
          ],
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
    //
    // 무효 사유 문구는 만들지 않는다. 배너는 설명 글을 그리지 않고(카드
    // 그림과 제목이 그 역할을 한다) 어느 카드였는지는 isKraken 으로 고른다.
    final detail = state.lastTrickBonusDetail;
    String? whaleNullifyLabel;
    int lootBonusPoints = 0;
    bool isKraken = false;
    bool hasWhiteWhaleEffect = false;
    for (final entry in detail) {
      final type = entry['type'];
      if (type == 'kraken_void') {
        isKraken = true;
      } else if (type == 'white_whale_void') {
        hasWhiteWhaleEffect = true;
      } else if (type == 'white_whale_nullify') {
        whaleNullifyLabel = L10n.of(context).skGameWhiteWhaleNullify;
        hasWhiteWhaleEffect = true;
      } else if (type == 'loot_bonus') {
        lootBonusPoints = (entry['winnerPoints'] as num?)?.toInt() ?? 0;
      }
    }
    // 크라켄이 있으면 크라켄 배너가 이긴다 — 둘이 같이 나온 트릭에서
    // 흰고래 연출로 보이면 왜 무효가 됐는지 읽을 수 없다.
    if (isKraken) hasWhiteWhaleEffect = false;
    final isVoided = state.lastTrickVoided;

    // Voided trick → distinct banner
    if (isVoided && _trickShown(state)) {
      return _skEffectPanel(
        cardId: isKraken ? 'sk_kraken' : 'sk_white_whale',
        cardSize: 62,
        color: isKraken
            ? Cartoon.surface(const Color(0xFFE2D4F7))
            : Cartoon.surface(const Color(0xFFD3ECFF)),
        title: L10n.of(context).skGameTrickVoided,
        footer: L10n.of(context).skGameLeadPlayer(winnerName),
        timer: _buildCenterTimerBadge(state),
      );
    }

    if (!isKraken && hasWhiteWhaleEffect && _trickShown(state)) {
      return _skEffectPanel(
        cardId: 'sk_white_whale',
        cardSize: 62,
        color: Cartoon.surface(const Color(0xFFD3ECFF)),
        title: L10n.of(context).skGameTrickWinner(winnerName),
        bonusText: _skBonusText(context, bonus, lootBonusPoints),
        timer: _buildCenterTimerBadge(state),
      );
    }

    final ended = _trickShown(state);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 트릭이 끝나면 승자를 노란 알약으로, 카드를 확인하는 동안은 조용한 글자로.
          if (ended)
            CartoonEntrance(
              from: const Offset(0, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                decoration: gamePillDecoration(color: Cartoon.yellow),
                child: Text(
                  L10n.of(context).skGameTrickWinner(winnerName),
                  style: Cartoon.userText(
                    size: 17,
                    color: Cartoon.inkOn(Cartoon.yellow),
                  ),
                ),
              ),
            )
          else
            Text(
              L10n.of(context).skGameCheckingCards,
              style: Cartoon.text(
                size: 16,
                color: Cartoon.ink.withValues(alpha: 0.78),
              ),
            ),
          // 선 무늬 — 따라 내야 하는 무늬를 가운데에 늘 보여 준다.
          if (!ended && _skLeadSuit(state.currentTrick) != null) ...[
            const SizedBox(height: 6),
            Builder(
              builder: (_) {
                final lead = _skLeadSuit(state.currentTrick)!;
                return Container(
                  padding: const EdgeInsets.all(7),
                  decoration: gamePillDecoration(radius: 99),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CustomPaint(
                      painter: SkSuitPainter(
                        suit: lead,
                        color: skSuitColors[lead] ?? Cartoon.ink,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
          if (whaleNullifyLabel != null && ended) ...[
            const SizedBox(height: 6),
            _skInfoChip(
              whaleNullifyLabel,
              Cartoon.surface(const Color(0xFFD3ECFF)),
            ),
          ],
          if (ended && bonus > 0) ...[
            const SizedBox(height: 6),
            _skInfoChip(
              L10n.of(context).skGameBonus(bonus),
              Cartoon.surface(const Color(0xFFCDEFD6)),
            ),
          ],
          // 루트는 라운드 끝에 동맹 양쪽이 공약을 맞혀야 들어온다. 받은
          // 점수와 같은 칩에 더해 버리면 확정된 것처럼 보이므로 따로,
          // 조건을 적어 보여준다.
          if (ended && lootBonusPoints > 0) ...[
            const SizedBox(height: 6),
            _skInfoChip(
              L10n.of(context).skGameLootPending(lootBonusPoints),
              Cartoon.surface(const Color(0xFFFFE9C7)),
            ),
          ],
          _buildCenterTimerBadge(state),
        ],
      ),
    );
  }

  /// 좌석 아래의 "획득/목표" 칩. text 가 null 이면 비드만 마친 상태(체크).
  Widget _skBidChip(String? text, Color color, double size, double hPad) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Cartoon.ink, width: 1.4),
      ),
      child: text == null
          ? Icon(Icons.check_rounded, size: size + 2, color: Cartoon.ink)
          : Text(
              text,
              maxLines: 1,
              style: Cartoon.userText(size: size, weight: FontWeight.w800),
            ),
    );
  }

  /// 트릭 보너스 칩에 적을 글. 확정된 점수만 적는다.
  ///
  /// 루트는 라운드 끝에 동맹 양쪽이 공약을 맞혀야 지급되므로(서버
  /// SkullKingGame.endRound) 여기 더하지 않는다. 더하면 자주 못 받는
  /// +20/+40 을 받은 것처럼 광고하게 된다. 루트만 있고 확정 보너스가
  /// 없으면 조건을 적어 그 사실을 알린다.
  String? _skBonusText(BuildContext context, int bonus, int lootPoints) {
    final l10n = L10n.of(context);
    if (bonus > 0 && lootPoints > 0) {
      return '${l10n.skGameBonus(bonus)} · ${l10n.skGameLootPending(lootPoints)}';
    }
    if (bonus > 0) return l10n.skGameBonus(bonus);
    if (lootPoints > 0) return l10n.skGameLootPending(lootPoints);
    return null;
  }

  Widget _skInfoChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: gamePillDecoration(color: color),
      child: Text(text, style: Cartoon.text(size: 14)),
    );
  }

  /// 크라켄·흰고래 같은 특수 카드 효과: 설명 글 없이 연출만.
  /// 카드가 쾅 하고 커지며 흔들리고, 뒤에서 색종이가 터진다. 글자는 짧은 제목
  /// 알약 하나(와 있으면 보너스 칩)뿐이다 — 설명은 읽기 전에 사라진다.
  // subtitle 파라미터는 없다. 위 주석대로 설명 글을 일부러 그리지 않는데,
  // required 로 받아 두면 호출하는 쪽은 그 글이 화면에 나온다고 믿고 문구를
  // 만들어 넘긴다 — 크라켄 사유와 흰고래 무효 라벨이 그렇게 조용히 버려지고
  // 있었다. 받지 않으면 넘길 수 없다.
  /// 크라켄·흰고래 연출에 쓰는 '배경 없는 캐릭터' 그림.
  ///
  /// 카드 그림(sk_kraken.webp)은 카드 틀과 그라데이션 배경이 들어 있어서,
  /// 효과 연출의 둥근 빛 번짐 위에 얹으면 배경이 두 겹으로 보인다.
  /// art/cards 의 원본에서 배경만 지워 따로 뽑은 그림을 쓴다.
  Widget _skCreatureArt(String cardId, double size) {
    const art = {
      'sk_kraken': 'assets/cards/sk_kraken_art.webp',
      'sk_white_whale': 'assets/cards/sk_white_whale_art.webp',
    };
    final path = art[cardId];
    if (path == null) return _buildCard(cardId, size: size);
    return Image.asset(
      path,
      height: size * 1.15,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => _buildCard(cardId, size: size),
    );
  }

  Widget _skEffectPanel({
    required String cardId,
    required double cardSize,
    required Color color,
    required String title,
    String? footer,
    String? bonusText,
    Widget? timer,
  }) {
    final isKraken = cardId == 'sk_kraken';
    final big = cardSize * 1.35;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: big * 2.2,
            height: big * 1.45,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // 카드 뒤 둥근 빛 번짐(번지지 않는 단색 원 두 겹)
                Container(
                  width: big * 1.5,
                  height: big * 1.5,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CartoonConfetti(seed: isKraken ? 7 : 3, count: 36),
                  ),
                ),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 750),
                  curve: Curves.linear,
                  builder: (context, t, child) {
                    // 앞 40%: 작게→크게 튀어나옴, 이후: 좌우로 빠르게 흔들리다 가라앉음.
                    final pop = Curves.elasticOut.transform(
                      (t / 0.55).clamp(0.0, 1.0),
                    );
                    final shake = t < 0.4
                        ? 0.0
                        : math.sin((t - 0.4) * 40) * 0.09 * (1 - t);
                    return Transform.rotate(
                      angle: shake,
                      child: Transform.scale(
                        scale: 0.2 + 0.8 * pop,
                        child: child,
                      ),
                    );
                  },
                  // 카드가 아니라 캐릭터만 띄운다. 배경을 지운 그림이라
                  // 뒤의 둥근 빛 번짐 위에 바로 얹힌다 — 카드 틀과 그
                  // 안의 배경색이 겹쳐 보이던 것이 사라진다.
                  //
                  // 그림이 없으면(구버전 번들) 카드로 돌아간다. 효과 연출이
                  // 통째로 비는 것보다는 예전 모양이 낫다.
                  child: _skCreatureArt(cardId, big),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          CartoonEntrance(
            delay: const Duration(milliseconds: 250),
            from: const Offset(0, 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: gamePillDecoration(color: Cartoon.yellow),
              child: Text(
                title,
                style: Cartoon.userText(
                  size: 19,
                  color: Cartoon.inkOn(Cartoon.yellow),
                ),
              ),
            ),
          ),
          if (bonusText != null) ...[
            const SizedBox(height: 6),
            _skInfoChip(bonusText, Cartoon.surface(const Color(0xFFCDEFD6))),
          ],
          if (footer != null) ...[
            const SizedBox(height: 6),
            _skInfoChip(footer, Colors.white),
          ],
          ?timer,
        ],
      ),
    );
  }

  // ── Bidding UI ──
  Widget _buildBiddingUI(SKGameStateData state, GameService game) {
    final isLandscape =
        !kIsWeb && MediaQuery.of(context).orientation == Orientation.landscape;
    final selfPlayer = state.players.firstWhere(
      (p) => p.position == 'self',
      orElse: () => state.players.first,
    );
    final isMyBidTurn = !selfPlayer.hasBid;

    if (selfPlayer.hasBid) {
      return Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: Cartoon.panelDecoration(radius: 22, shadowOffset: 3),
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
              style: Cartoon.text(size: 20),
            ),
            const SizedBox(height: 4),
            Text(
              L10n.of(context).skGameWaitingOthers,
              style: Cartoon.text(
                size: 14,
                color: Cartoon.ink.withValues(alpha: 0.78),
              ),
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
        color: isMyBidTurn ? Cartoon.myTurn : Cartoon.paper,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(
          top: BorderSide(color: Cartoon.ink, width: isMyBidTurn ? 3.2 : 2.2),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildSelfStatusRow(selfPlayer, game, compact: isLandscape),
          ),
          Text(
            L10n.of(context).skGameBidPrompt,
            style: Cartoon.text(size: isLandscape ? 16 : 18),
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
            alignment: WrapAlignment.center,
            children: List.generate(state.round + 1, (i) {
              final selected = _selectedBid == i;
              return CartoonPressable(
                scale: 0.9,
                onTap: () => setState(() => _selectedBid = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: isLandscape ? 42 : 46,
                  height: isLandscape ? 42 : 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? Cartoon.orange
                        : Cartoon.surface(Colors.white),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Cartoon.ink,
                      width: selected ? 2.6 : 1.8,
                    ),
                  ),
                  child: Text(
                    '$i',
                    style: Cartoon.text(
                      size: isLandscape ? 19 : 22,
                      color: selected ? Colors.white : Cartoon.ink,
                    ),
                  ),
                ),
              );
            }),
          ),
          SizedBox(height: isLandscape ? 6 : 8),
          gameButton(
            _selectedBid != null
                ? L10n.of(context).skGameBidSubmit(_selectedBid!)
                : L10n.of(context).skGameSelectNumber,
            _selectedBid != null
                ? () {
                    game.submitBid(_selectedBid!);
                    setState(() => _selectedBid = null);
                  }
                : null,
            color: Cartoon.green,
            height: isLandscape ? 46 : 52,
            size: isLandscape ? 18 : 20,
            expand: true,
          ),
        ],
      ),
    );
  }

  // ── Hand Area ──
  Widget _buildHandArea(SKGameStateData state, GameService game) {
    final isLandscape =
        !kIsWeb && MediaQuery.of(context).orientation == Orientation.landscape;
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
        color: state.isMyTurn ? _handMyTurn : _handPaper,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(
          top: BorderSide(
            color: Cartoon.ink,
            width: state.isMyTurn ? 3.2 : 2.2,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
            child: _buildSelfStatusRow(selfPlayer, game, compact: isLandscape),
          ),
          // Play button above cards
          if (state.isMyTurn && selectedCard != null && isSelectedLegal)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 8, right: 8),
              child: gameButton(
                L10n.of(context).skGamePlayCardButton,
                () {
                  if (selectedCard.startsWith('sk_tigress')) {
                    _showTigressDialog(game, selectedCard);
                  } else {
                    game.playCard(selectedCard);
                    setState(() => _selectedCard = null);
                  }
                },
                color: Cartoon.green,
                height: isLandscape ? 40 : 44,
                size: isLandscape ? 17 : 19,
                expand: true,
              ),
            )
          else if (state.isMyTurn)
            // 버튼과 같은 높이로 맞춰, 카드를 고르는 순간 보드가 밀리지 않게.
            Container(
              height: isLandscape ? 40 : 44,
              alignment: Alignment.center,
              margin: const EdgeInsets.only(bottom: 6),
              child: Text(
                L10n.of(context).skGameSelectCard,
                style: Cartoon.text(size: isLandscape ? 16 : 18),
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
        ? Cartoon.surface(const Color(0xFFCDEFD6))
        : exceeds
        ? Cartoon.surface(const Color(0xFFFFE0B8))
        : Cartoon.surface(const Color(0xFFD6EAFF));
    final trickBidFg = Cartoon.ink;

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
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: Cartoon.ink, width: 1.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: compact ? 16 : 18, color: fg),
            const SizedBox(width: 4),
            Text(
              value,
              style: Cartoon.text(size: compact ? 16 : 18, color: fg),
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
              bg: Cartoon.cream,
              fg: Cartoon.ink,
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
          color: Cartoon.yellow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Cartoon.inkOn(Cartoon.yellow), width: 1.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.timer_off_rounded,
              size: 16,
              color: Cartoon.inkOn(Cartoon.yellow),
            ),
            const SizedBox(width: 5),
            Text(
              '${game.myTimeoutCount}/3',
              style: Cartoon.text(
                size: 14,
                color: Cartoon.inkOn(Cartoon.yellow),
              ),
            ),
            const SizedBox(width: 4),
            Text(L10n.of(context).skGameReset, style: Cartoon.text(size: 13)),
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
        child: _buildCard(
          cardId,
          size: cardHeight,
          highlighted: isSelected,
          highlightKind: isSelected
              ? SkCardHighlight.selected
              : SkCardHighlight.none,
          showName: true,
        ),
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
            transform: Matrix4.translationValues(0, isSelected ? -18 : 0, 0),
            child: Opacity(
              opacity: !isMyTurn || isLegal ? 1.0 : 0.4,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: padding),
                child: _buildCard(
                  cardId,
                  size: cardHeight,
                  highlighted: isSelected,
                  highlightKind: isSelected
                      ? SkCardHighlight.selected
                      : SkCardHighlight.none,
                  showName: true,
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
        final dense = compact || cards.length >= 8;
        final cardPadding = dense ? (compact ? 1.0 : 1.5) : 3.0;
        // These caps are phone sizes, so on a browser window the hand stayed
        // small no matter how much room there was. Grow them with the viewport
        // — same 400pt design width the other boards scale against — and only
        // on web, so the app itself renders exactly as before.
        final media = MediaQuery.of(context);
        // 1.3, not 1.6: at 1.6 the whole board read as a magnified phone.
        // Matches the Tichu board's ceiling so the games look like one app.
        final scale = kIsWeb
            ? (media.size.shortestSide / 400).clamp(1.0, 1.3)
            : 1.0;

        final maxCardWidth =
            (interactive ? (compact ? 42.0 : 55.0) : (compact ? 34.0 : 46.0)) *
            scale;

        // One row while the cards can stay full size, two the moment a single
        // line would force them to shrink — the last round deals ten and a
        // wide window has room for all of them side by side.
        final oneRowWidth =
            (availableWidth - cards.length * cardPadding * 2) / cards.length;
        final perRow =
            (compact || cards.length <= 6 || oneRowWidth >= maxCardWidth)
            ? cards.length
            : (cards.length / 2).ceil();
        final totalPadding = perRow * cardPadding * 2;
        // Fill available width, only cap at max
        var cardWidth = ((availableWidth - totalPadding) / perRow).clamp(
          0.0,
          maxCardWidth,
        );
        var cardHeight = (cardWidth * 1.4).clamp(
          (interactive ? (compact ? 42.0 : 52.0) : (compact ? 34.0 : 42.0)) *
              scale,
          (interactive ? (compact ? 60.0 : 77.0) : (compact ? 50.0 : 64.0)) *
              scale,
        );

        // Width alone decided the size, and a desktop window has plenty — the
        // hand would grow until it covered the table. Cap the rows at a share
        // of the screen and walk the width back to match if it bites. Only the
        // player's own hand needs this; the smaller read-only strips never get
        // near it.
        if (interactive) {
          final rows = perRow >= cards.length ? 1 : 2;
          final maxCardHeight = (media.size.height * 0.26) / rows;
          if (cardHeight > maxCardHeight) {
            cardHeight = maxCardHeight;
            cardWidth = cardHeight / 1.4;
          }
        }

        List<Widget> rowWidgets(List<String> row) {
          return row
              .map(
                (cardId) =>
                    buildCardWidget(cardId, cardWidth, cardHeight, cardPadding),
              )
              .toList();
        }

        // Follows perRow rather than re-deciding: in Mighty the same pair had
        // drifted apart, so the width calculation said one row while the
        // assembly kept splitting at a fixed count.
        if (perRow >= cards.length) {
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalMargin),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: rowWidgets(cards),
            ),
          );
        }

        final half = perRow;
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
        backgroundColor: Cartoon.paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: BorderSide(color: Cartoon.ink, width: 2.5),
        ),
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
                          color: Cartoon.paper,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Cartoon.ink, width: 2),
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
                              style: Cartoon.text(size: 18),
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
                          color: Cartoon.surface(
                            Cartoon.surface(const Color(0xFFFFE3E0)),
                          ),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Cartoon.ink, width: 2),
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
                              style: Cartoon.text(size: 18, color: Cartoon.red),
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
        !kIsWeb && MediaQuery.of(context).orientation == Orientation.landscape;
    final lastHistory = state.scoreHistory.isNotEmpty
        ? state.scoreHistory.last
        : null;
    final scores = lastHistory?['scores'] as Map<String, dynamic>?;

    return Container(
      padding: EdgeInsets.all(isLandscape ? 12 : 16),
      margin: EdgeInsets.all(isLandscape ? 12 : 16),
      decoration: Cartoon.panelDecoration(radius: 24, shadowOffset: 3),
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
                  color: Cartoon.yellow,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: Cartoon.inkOn(Cartoon.yellow),
                    width: 1.8,
                  ),
                ),
                child: Text(
                  L10n.of(context).skGameRoundResult(state.round),
                  style: Cartoon.userText(
                    size: isLandscape ? 16 : 18,
                    color: Cartoon.inkOn(Cartoon.yellow),
                  ),
                ),
              ),
              SizedBox(height: isLandscape ? 8 : 12),
              // Table header — rank # / name / bid·tricks / bonus / round / total
              Row(
                children: [
                  SizedBox(
                    width: isLandscape ? 20 : 24,
                    child: Text(
                      '#',
                      textAlign: TextAlign.center,
                      style: Cartoon.userText(
                        size: isLandscape ? 11 : 12,
                        color: Cartoon.ink.withValues(alpha: 0.78),
                      ),
                    ),
                  ),
                  const Expanded(flex: 3, child: SizedBox.shrink()),
                  Expanded(
                    flex: 2,
                    child: Text(
                      L10n.of(context).skGameBidTricks,
                      textAlign: TextAlign.center,
                      style: Cartoon.userText(
                        size: isLandscape ? 11 : 12,
                        color: Cartoon.ink.withValues(alpha: 0.78),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: isLandscape ? 34 : 38,
                    child: Text(
                      L10n.of(context).skGameBonusHeader,
                      textAlign: TextAlign.center,
                      style: Cartoon.userText(
                        size: isLandscape ? 11 : 12,
                        color: Cartoon.ink.withValues(alpha: 0.78),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: isLandscape ? 42 : 46,
                    child: Text(
                      L10n.of(context).skGameScoreHeader,
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      softWrap: false,
                      style: Cartoon.userText(
                        size: isLandscape ? 11 : 12,
                        color: Cartoon.ink.withValues(alpha: 0.78),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: isLandscape ? 44 : 48,
                    child: Text(
                      L10n.of(context).skGameTotalScoreHeader,
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      softWrap: false,
                      style: Cartoon.userText(
                        size: isLandscape ? 11 : 12,
                        color: Cartoon.ink.withValues(alpha: 0.78),
                      ),
                    ),
                  ),
                ],
              ),
              Divider(
                height: 8,
                thickness: 1.5,
                color: Cartoon.ink.withValues(alpha: 0.15),
              ),
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
                    final wager = (pScore['wager'] as num?)?.toInt() ?? 0;
                    final success = bid == 0 ? tricks == 0 : tricks == bid;
                    final rankColor = rank == 1
                        ? const Color(0xFFD4A24A)
                        : rank == 2
                        ? Cartoon.onSurface(const Color(0xFF9A9A9A))
                        : rank == 3
                        ? Cartoon.onSurface(const Color(0xFFB07A4A))
                        : Cartoon.onSurface(const Color(0xFFA89A92));
                    return Container(
                      padding: EdgeInsets.symmetric(
                        vertical: isLandscape ? 3 : 4,
                      ),
                      decoration: BoxDecoration(
                        color: p.position == 'self'
                            ? Cartoon.cream
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: isLandscape ? 20 : 24,
                            child: Text(
                              '$rank',
                              textAlign: TextAlign.center,
                              style: Cartoon.userText(
                                size: isLandscape ? 14 : 15,
                                color: rankColor,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: Cartoon.userText(
                                    size: isLandscape ? 14 : 15,
                                    color: Cartoon.ink,
                                  ),
                                ),
                                // Rascal 의 내기: 입찰을 맞히면 +, 못 맞히면 −(점수에 이미 반영됨).
                                if (wager > 0)
                                  Text(
                                    '🏴‍☠️ ${success ? '+' : '-'}$wager',
                                    style: Cartoon.userText(
                                      size: 11,
                                      color: success
                                          ? Cartoon.orangeDeep
                                          : Cartoon.red,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    success
                                        ? Icons.check_circle_rounded
                                        : Icons.cancel_rounded,
                                    size: 15,
                                    color: success
                                        ? Cartoon.green
                                        : Cartoon.red,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$tricks/$bid',
                                    style: Cartoon.userText(
                                      size: 12 + 2,
                                      color: Cartoon.ink,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(
                            width: isLandscape ? 34 : 38,
                            child: bonus > 0
                                ? Text(
                                    '+$bonus',
                                    style: Cartoon.userText(
                                      size: isLandscape ? 12 : 13,
                                      color: Cartoon.orangeDeep,
                                    ),
                                    textAlign: TextAlign.center,
                                  )
                                : const SizedBox.shrink(),
                          ),
                          SizedBox(
                            width: isLandscape ? 42 : 46,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                '${roundScore > 0 ? '+' : ''}$roundScore',
                                style: Cartoon.userText(
                                  size: isLandscape ? 14 : 16,
                                  color: roundScore >= 0
                                      ? Cartoon.green
                                      : Cartoon.red,
                                ),
                                textAlign: TextAlign.end,
                                maxLines: 1,
                                softWrap: false,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: isLandscape ? 44 : 48,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                '${p.totalScore}',
                                style: Cartoon.userText(
                                  size: isLandscape ? 14 : 16,
                                  color: Cartoon.ink,
                                ),
                                textAlign: TextAlign.end,
                                maxLines: 1,
                                softWrap: false,
                              ),
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
                style: Cartoon.userText(
                  size: isLandscape ? 13 : 14,
                  color: Cartoon.ink.withValues(alpha: 0.78),
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
      decoration: Cartoon.panelDecoration(radius: 24, shadowOffset: 3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Cartoon.yellow,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: Cartoon.inkOn(Cartoon.yellow),
                width: 1.8,
              ),
            ),
            child: Text(
              L10n.of(context).skGameGameOver,
              style: Cartoon.userText(
                size: 18 + 2,
                color: Cartoon.inkOn(Cartoon.yellow),
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
                color: isWinner ? Cartoon.myTurn : Cartoon.cream,
                borderRadius: BorderRadius.circular(14),
                border: isWinner
                    ? Border.all(color: Cartoon.ink, width: 1.8)
                    : null,
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: isWinner
                          ? Cartoon.yellow
                          : Cartoon.surface(Colors.white),
                      shape: BoxShape.circle,
                      border: Border.all(color: Cartoon.ink, width: 1.8),
                    ),
                    child: Center(
                      child: Text('$rank', style: Cartoon.text(size: 17)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      p.name,
                      style: Cartoon.userText(
                        size: isWinner ? 18 : 16,
                        color: Cartoon.ink,
                      ),
                    ),
                  ),
                  Text(
                    '${p.totalScore}',
                    style: Cartoon.userText(
                      size: isWinner ? 20 : 17,
                      color: Cartoon.ink,
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
              color: Cartoon.surface(Cartoon.surface(const Color(0xFFD6EAFF))),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              _gameEndCountdown > 0
                  ? L10n.of(
                      context,
                    ).skGameAutoReturnCountdown(_gameEndCountdown)
                  : L10n.of(context).skGameReturningToRoom,
              textAlign: TextAlign.center,
              style: Cartoon.userText(size: 14 + 2, color: Cartoon.ink),
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
    showPlayerProfileDialog(
      context,
      nickname,
      game,
      initialGame: 'skull_king',
      subtitle: L10n.of(context).skGamePlayerProfile,
      isBot: isBot,
      maxHeight: 400,
      dismissWhen: (g) =>
          g.skGameState == null || g.skGameState!.phase == 'game_end',
    );
  }

  // Special card asset mapping
  static const _specialAssets = {
    'skull_king': 'assets/cards/sk_skull_king.webp',
    // 번호 없는 해적 = 이름 없는 일반 해적. 티그리스를 해적으로 냈을 때
    // 이 그림이 쓰인다(이름 있는 다섯 장과 섞이면 안 된다).
    'pirate': 'assets/cards/sk_pirate.webp',
    'mermaid': 'assets/cards/sk_mermaid.webp',
    'escape': 'assets/cards/sk_escape.webp',
    'tigress': 'assets/cards/sk_tigress.webp',
    'kraken': 'assets/cards/sk_kraken.webp',
    'white_whale': 'assets/cards/sk_white_whale.webp',
    'loot': 'assets/cards/sk_loot.webp',
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

  /// 손패 창의 바탕색. 내 차례면 노랗다.
  ///
  /// 창 아래 안전 영역을 채우는 띠(SpectatorBottomFill)가 같은 값을 써야
  /// 한다 — 두 곳에 숫자를 적어 두면 한쪽만 고쳐져 이음새가 생긴다.
  // 팔레트가 바뀌면 같이 바뀌어야 하므로 getter 다.
  static Color get _handPaper => Cartoon.paper;
  static Color get _handMyTurn => Cartoon.myTurn;

  static final _specialBgColors = {
    'skull_king': Cartoon.onSurface(Color(0xFF1A1A1A)),
    'pirate': Cartoon.onSurface(Color(0xFF8B1A1A)),
    'mermaid': Cartoon.onSurface(Color(0xFF0D5E7A)),
    'escape': Cartoon.onSurface(Color(0xFF757575)),
    'tigress': Cartoon.onSurface(Color(0xFF5E35B1)),
    'kraken': Cartoon.onSurface(Color(0xFF2B1E3F)),
    'white_whale': Cartoon.onSurface(Color(0xFF3A6B8F)),
    'loot': Cartoon.onSurface(const Color(0xFF8B6F22)),
  };

  /// 특수 카드 그림에는 글자가 없어서, 어떤 카드인지 이름표를 카드 아래쪽에 살짝 걸쳐 단다.
  String _skCardLabel(String cardId, _CardInfo info) {
    final l10n = L10n.of(context);
    switch (info.type) {
      case 'skull_king':
        return l10n.skCardSkullKing;
      case 'pirate':
        // 이름표에는 "해적 · 라스칼" 로 적는다. 이름만 적으면 처음 보는
        // 사람에게 라스칼이 해적 다섯 중 하나라는 게 안 보인다.
        //
        // 능력 창 제목이나 알림에는 쓰지 않는다. "해적 · 라스칼의 능력으로"
        // 는 읽기 나쁘고, 거기서는 이미 해적 카드 그림이 같이 보인다.
        //
        // 번호가 없거나 모르는 번호면 이름 없이 "해적" 이다. 티그리스를
        // 해적으로 낸 카드가 그렇고, 구버전 앱에게 5번 해적을 번호 없이
        // 내려 보낼 때도 그 경로를 탄다(server.js serializeForClient).
        final key = skPirateByNumber[info.number];
        return key == null
            ? l10n.skCardPirate
            : l10n.skCardPirateNamed(skPirateName(l10n, key));
      case 'mermaid':
        return l10n.skCardMermaid;
      case 'escape':
        return l10n.skCardEscape;
      case 'tigress':
        return l10n.skCardTigress;
      case 'kraken':
        return l10n.skCardKraken;
      case 'white_whale':
        return l10n.skCardWhiteWhale;
      case 'loot':
        return l10n.skCardLoot;
      default:
        return '';
    }
  }

  /// 이긴 카드 표식. 테두리 대신 카드 위에 얹는다.
  ///
  /// 색 테두리로는 눈에 띄지 않았다 — 카드 그림이 대부분 파랑·보라·크림
  /// 계열이라 어떤 색을 써도 그림에 묻힌다. 그래서 그림 밖으로 나오는
  /// 금색 뱃지와 움직임을 쓴다.
  ///
  /// 손패에서 고른 카드에는 뱃지를 붙이지 않는다. 그쪽은 카드가 위로
  /// 들리고 그림자가 주황으로 바뀌는 것만으로 충분하고, 열 장이 늘어선
  /// 줄에 뱃지가 끼면 오히려 어수선하다.
  ///
  /// 뱃지는 카드 밖(위 모서리)으로 나가므로 감싸는 쪽이 clipBehavior 를
  /// 잘라서는 안 된다. Stack 은 Clip.none 으로 둔다.
  Widget _withCardHighlight(Widget card, SkCardHighlight kind, double size) {
    if (kind != SkCardHighlight.winner && kind != SkCardHighlight.drawn) {
      return card;
    }
    final isWin = kind == SkCardHighlight.winner;
    final badge = size * 0.34;
    // 이긴 카드는 노랑, 가져온 카드는 초록. 뜻이 다른 두 표식이라 색과
    // 그림을 모두 다르게 둔다 — 모양만 다르면 작은 화면에서 구분이 안 된다.
    final badgeFill = isWin
        ? const Color(0xFFFFC21A)
        : Cartoon.onSurface(const Color(0xFF4CAF50));
    final marker = Container(
      width: badge,
      height: badge,
      decoration: BoxDecoration(
        // 이긴 카드는 노랑, 가져온 카드는 초록. 뜻이 다른 두 표식이라
        // 색과 그림을 모두 다르게 둔다 — 모양만 다르면 작은 화면에서
        // 구분이 안 된다.
        color: badgeFill,
        shape: BoxShape.circle,
        border: Border.all(color: Cartoon.ink, width: 1.8),
        boxShadow: [BoxShadow(color: Cartoon.ink, offset: Offset(0, 1.6))],
      ),
      child: Icon(
        isWin ? Icons.emoji_events_rounded : Icons.south_rounded,
        size: badge * 0.62,
        // 뱃지 바탕은 뜻을 가진 색이라 팔레트를 따라가지 않는다. 그림은
        // 그 바탕에서 끌어내야 어두운 테마에서도 보인다.
        color: Cartoon.inkOn(badgeFill),
      ),
    );
    final marked = Stack(
      clipBehavior: Clip.none,
      children: [
        card,
        Positioned(top: -badge * 0.3, right: -badge * 0.28, child: marker),
      ],
    );
    // 가져온 카드는 띄우지도 키우지도 않는다. 손패가 늘어선 줄에서 "어느
    // 게 새로 온 카드인가" 만 알려 주면 되는 자리이고, 그 줄의 카드는
    // 눌러서 버릴 대상이라 흔들리면 누르기 어렵다.
    if (!isWin) return marked;
    return CartoonFloat(
      amplitude: 3,
      child: Transform.scale(scale: 1.06, child: marked),
    );
  }

  Widget _withNameTag(Widget card, String label, double size) {
    if (label.isEmpty) return card;
    final w = size * 0.7;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        card,
        Positioned(
          left: -w * 0.05,
          right: -w * 0.05,
          bottom: -size * 0.075,
          child: Center(
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: size * 0.07,
                vertical: size * 0.012,
              ),
              decoration: BoxDecoration(
                color: Cartoon.cream,
                borderRadius: BorderRadius.circular(size * 0.1),
                border: Border.all(color: Cartoon.ink, width: 1.3),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: Cartoon.userText(
                    size: (size * 0.15).clamp(8.0, 13.0),
                    weight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// [playedAs] 는 이미 낸 티그리스가 고른 모양('pirate' / 'escape').
  /// 손패의 티그리스는 null 이다 — 아직 고르지 않았으므로.
  Widget _buildCard(
    String cardId, {
    double size = 60,
    bool highlighted = false,
    bool showName = false,
    String? nameOverride,
    String? playedAs,

    /// 강조의 뜻. 넘기지 않으면 [highlighted] 로 정한다 — 이긴 카드 쪽이
    /// 기본값인 이유는 그게 먼저 있던 용도여서다.
    SkCardHighlight? highlightKind,
  }) {
    final highlight =
        highlightKind ??
        (highlighted ? SkCardHighlight.winner : SkCardHighlight.none);
    var info = _parseCardId(cardId);
    // 낸 티그리스는 고른 모양의 그림으로 보여 준다. 손패에서만 티그리스
    // 그림(칼+백기)이고, 테이블에 놓이는 순간부터는 해적이거나 탈출이다 —
    // 그게 그 카드가 그 트릭에서 하는 일이다.
    //
    // 예전에는 낸 뒤에도 티그리스 그림을 유지했다. 해적 그림으로 바꾸면
    // 이름 있는 해적을 낸 것으로 오해한다는 이유였는데, 그때는 해적 그림이
    // 이름 있는 다섯 장뿐이었다. 지금은 아무 이름도 없는 일반 해적
    // 그림(sk_pirate)이 따로 있어서 그 오해가 생기지 않는다.
    //
    // 티그리스였다는 사실은 그대로 보인다 — 호출하는 쪽이 이름표를
    // '티그리스·해적' 으로 덮고, 모서리에 표식을 얹는다.
    if (info.type == 'tigress' && playedAs != null) {
      info = _CardInfo(type: playedAs == 'pirate' ? 'pirate' : 'escape');
    }
    final w = size * 0.7;
    final h = size;
    final radius = BorderRadius.circular((size * 0.09).clamp(5.0, 9.0));

    // 입체감: 진한 테두리 + 아래로 어긋난 단색 그림자.
    //
    // 강조는 두 가지인데 뜻이 다르다 — 내가 고른 카드(손패)와 트릭을 이긴
    // 카드(테이블). 전에는 둘 다 같은 파란 테두리였고, 카드 그림이 대부분
    // 파랑·보라 계열이라 거기 묻혔다.
    //
    // 고른 카드는 주황, 이긴 카드는 노랑으로 나눈다. 둘 다 카드 그림에
    // 거의 쓰이지 않는 색이라 눈에 걸리고, 색만으로 어느 쪽인지 읽힌다.
    // 테두리도 2.6 → 3.6 으로 올리고 그림자를 같은 색으로 맞춰 띄운다.
    final isWinner = highlight == SkCardHighlight.winner;
    final isPicked = highlight == SkCardHighlight.selected;
    final isDrawn = highlight == SkCardHighlight.drawn;
    // 테두리는 평소 그대로 둔다. 색만 바꾸면 카드 그림(대부분 파랑·보라·
    // 크림)에 묻혀 눈에 띄지 않는다 — 강조는 카드 위에 얹는 표식과
    // 움직임이 맡는다(_withCardHighlight).
    final border = Border.all(
      color: Cartoon.onSurface(const Color(0xFF3B2A20)).withValues(alpha: 0.7),
      width: 1.5,
    );
    final shadow = [
      BoxShadow(
        color: isWinner
            ? Cartoon.onSurface(const Color(0xFFB07A00))
            : isPicked
            ? Cartoon.onSurface(const Color(0xFFB0470A))
            : isDrawn
            ? Cartoon.onSurface(const Color(0xFF2E7D32))
            : Cartoon.onSurface(const Color(0xFF8C7B6C)),
        offset: Offset(0, isWinner || isPicked || isDrawn ? 4.5 : 2.5),
      ),
    ];

    // ── Number card: playing-card style ──
    if (info.type == 'number') {
      return _withCardHighlight(
        SkNumberCard(
          suit: info.suit,
          rank: info.rank,
          size: size,
          border: border,
          shadow: shadow,
        ),
        highlight,
        size,
      );
    }

    // ── Special card: image with fallback ──
    final bgColor =
        _specialBgColors[info.type] ??
        Cartoon.onSurface(const Color(0xFF424242));
    // Pirates use per-card artwork (sk_pirate1..4.png) so each of the 4
    // pirates looks distinct. Non-pirate specials (and pirate with no number)
    // fall back to the default asset from _specialAssets.
    String? assetPath;
    if (info.type == 'pirate' && info.number.isNotEmpty) {
      assetPath = 'assets/cards/sk_pirate${info.number}.webp';
    } else {
      assetPath = _specialAssets[info.type];
    }
    final fallbackLabel = _specialLabels[info.type] ?? '?';

    final specialCard = Container(
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
    if (!showName) return _withCardHighlight(specialCard, highlight, size);
    return _withCardHighlight(
      _withNameTag(
        specialCard,
        nameOverride ?? _skCardLabel(cardId, info),
        size,
      ),
      highlight,
      size,
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

  /// Preview the set of legal cards for SK follow-suit rules, used to let
  /// the user pre-select a card while it isn't their turn yet. Mirrors the
  /// server's SkullKingGame.getLegalCards: if no numbered card has been
  /// led yet, anything is legal; otherwise must follow the lead suit if
  /// possible, and special (non-number) cards are always legal.
  /// 지금 트릭의 리드 무늬. 없으면 null.
  String? _skLeadSuit(List<SKTrickPlay> trick) {
    for (final play in trick) {
      final info = _parseCardId(play.cardId);
      var type = info.type;
      if (type == 'tigress') {
        type = play.tigressChoice == 'pirate' ? 'pirate' : 'escape';
      }
      // 탈출·약탈은 투명하다 — 다음 숫자 카드가 리드 색을 정한다. 해적·인어·
      // 스컬킹·크라켄·흰고래가 먼저 나왔다면 리드 색은 없고, 그 뒤의 숫자도
      // 리드를 만들지 못한다.
      if (type == 'escape' || type == 'loot') continue;
      return type == 'number' ? info.suit : null;
    }
    return null;
  }

  Set<String> _previewSkLegalCards(SKGameStateData state) {
    final hand = state.myCards;
    final trick = state.currentTrick;
    if (hand.isEmpty) return const <String>{};
    if (trick.isEmpty) return hand.toSet();
    // Mirrors SkullKingGame.getLeadSuit.
    // Tigress counts as pirate or escape based on the player's choice, so
    // it never sets the lead suit.
    final leadSuit = _skLeadSuit(trick);
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

/// 자식이 실제로 차지한 높이를 알려준다.
///
/// 보드가 아래 창(손패)만큼을 비우기 위해 쓴다. 창 높이는 손에 든 장수에
/// 따라 바뀌어서(두 줄이 되면 크게 는다) 상수로는 맞출 수 없다.
class _MeasureHeight extends SingleChildRenderObjectWidget {
  const _MeasureHeight({required this.onChange, required Widget super.child});

  final ValueChanged<double> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureHeight(onChange);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasureHeight ro) {
    ro.onChange = onChange;
  }
}

class _RenderMeasureHeight extends RenderProxyBox {
  _RenderMeasureHeight(this.onChange);

  ValueChanged<double> onChange;
  double? _last;

  @override
  void performLayout() {
    super.performLayout();
    final h = size.height;
    if (_last == h) return;
    _last = h;
    // 레이아웃 도중에 setState 를 부를 수 없다. 한 프레임 뒤로 미룬다.
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(h));
  }
}

class _SKSpectatorHandAreaMarker extends StatelessWidget {
  const _SKSpectatorHandAreaMarker({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
