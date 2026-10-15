import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/game_service.dart';
import '../models/ll_game_state.dart';
import '../widgets/afk_kick_badge.dart';
import '../theme/cartoon.dart';
import '../widgets/game_chrome.dart';
import '../widgets/turn_name_pill.dart';
import '../widgets/love_letter_card.dart';
import '../widgets/connection_overlay.dart';
import '../widgets/draggable_chat_panel.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/seat_chat_bubble.dart';
import '../widgets/bot_avatar.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/player_profile_dialog.dart';
import '../widgets/spectator_controls.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n_helpers.dart';
import '../widgets/mid_game_join.dart';

class LLGameScreen extends StatefulWidget {
  const LLGameScreen({super.key});

  @override
  State<LLGameScreen> createState() => _LLGameScreenState();
}

class _LLGameScreenState extends State<LLGameScreen> {
  String? _selectedCard;
  String? _selectedTarget;
  String? _selectedGuess;
  String? _viewingPlayerId;
  bool _guardPeekActive = false;
  bool _viewersOpen = false;
  bool _chatOpen = false;
  bool _soundPanelOpen = false;
  bool _moreOpen = false;
  int _readChatCount = 0;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  int _lastChatMessageCount = 0;

  Timer? _countdownTimer;
  Timer? _gameEndCountdownTimer;
  Timer? _cardViewRequestTimer;
  int _remainingSeconds = 0;
  int _gameEndCountdown = 3;
  bool _gameEndCountdownActive = false;
  bool _waitingForRoomRecovery = false;
  GameService? _gameService;

  // Rolling log of recent center-board status lines so the latest
  // action stays visible after the effect resolves — feels like the
  // text stacks instead of disappearing. Cleared on round change.
  final List<List<_EffectStatusSegment>> _llCenterLog = [];
  final List<String> _llCenterLogHashes = [];
  int _llCenterLogRound = -1;

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

  @override
  void dispose() {
    _seatChat.dispose();
    _cardViewRequestTimer?.cancel();
    _countdownTimer?.cancel();
    _gameEndCountdownTimer?.cancel();
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _updateCountdown() {
    final gs = _gameService;
    if (gs == null) return;
    final llState = gs.llGameState;
    if (llState == null) return;
    final deadline = llState.turnDeadline;
    if (deadline != null && deadline > 0) {
      final remaining =
          ((deadline - DateTime.now().millisecondsSinceEpoch) / 1000).ceil();
      if (remaining != _remainingSeconds) {
        setState(() => _remainingSeconds = remaining.clamp(0, 999));
      }
    } else if (_remainingSeconds != 0) {
      setState(() => _remainingSeconds = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Consumer<GameService>(
        builder: (context, gs, _) {
          final llState = gs.llGameState;

          // Waiting room or no game state yet
          if (llState == null) {
            // A spectator with no game is routed to the shared waiting
            // room before this screen is ever built.
            if (_waitingForRoomRecovery) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _recoverRoomState();
            });
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          // Game end countdown
          if (llState.phase == 'game_end' && !_gameEndCountdownActive) {
            _gameEndCountdownActive = true;
            _gameEndCountdown = 5;
            _gameEndCountdownTimer?.cancel();
            _gameEndCountdownTimer = Timer.periodic(
              const Duration(seconds: 1),
              (_) {
                if (!mounted) return;
                setState(() => _gameEndCountdown--);
                if (_gameEndCountdown <= 0) {
                  _gameEndCountdownTimer?.cancel();
                }
              },
            );
          }
          if (llState.phase != 'game_end') {
            _gameEndCountdownActive = false;
            _gameEndCountdownTimer?.cancel();
          }

          // Clear stale selections when leaving effect_resolve
          if (llState.phase != 'effect_resolve' ||
              llState.pendingEffect == null) {
            _selectedTarget = null;
            _selectedGuess = null;
          }
          // Clear card selection when it's no longer in hand
          if (_selectedCard != null &&
              !llState.myCards.contains(_selectedCard)) {
            _selectedCard = null;
          }

          final themeColors = gs.themeGradient;

          return Scaffold(
            // Pinned like the other three boards: the table must not jump
            // when the chat keyboard opens, and on the web the engine has
            // already shrunk the canvas by then anyway.
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
                child: ConnectionOverlay(
                  child: Stack(
                    children: [
                      Column(
                        children: [
                          _buildTopBar(context, gs, llState),
                          Expanded(child: _buildGameArea(context, gs, llState)),
                          if (gs.isSpectator &&
                              llState.phase != 'game_end' &&
                              llState.phase != 'round_end')
                            const SizedBox(height: 100)
                          else
                            _buildBottomArea(context, gs, llState),
                        ],
                      ),
                      if (gs.isSpectator &&
                          llState.phase != 'game_end' &&
                          llState.phase != 'round_end')
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildLLEventLog(llState, gs, L10n.of(context)),
                              _buildBottomArea(context, gs, llState),
                            ],
                          ),
                        ),
                      if (llState.phase == 'effect_resolve' &&
                          llState.pendingEffect != null &&
                          _isEffectInteractive(llState.pendingEffect!, gs))
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: _buildEffectResolve(context, gs, llState),
                        ),
                      if (gs.hasIncomingCardViewRequests)
                        _buildCardViewRequestPopup(gs),
                      if (_viewersOpen) _buildViewersPanel(gs),
                      if (_moreOpen) _buildMoreMenu(gs),
                      if (_soundPanelOpen) _buildSoundPanel(gs),
                      if (_chatOpen) _buildChatPanel(context, gs),
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

  Future<void> _recoverRoomState() async {
    if (_waitingForRoomRecovery) return;
    _waitingForRoomRecovery = true;
    await context.read<GameService>().checkRoomAndWait();
    if (!mounted) return;
    setState(() => _waitingForRoomRecovery = false);
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
      suppressed: _chatOpen,
      child: seat,
    );
  }

  /// The last thing each player said, over their waiting-room seat.
  late final SeatChatBubbles _seatChat = SeatChatBubbles(() {
    if (mounted) setState(() {});
  });

  // ====================== TOP BAR ======================

  Widget _buildTopBar(
    BuildContext context,
    GameService gs,
    LLGameStateData state,
  ) {
    final l10n = L10n.of(context);
    final unread = gs.chatMessages.length - _readChatCount;

    // Spectators get the shared flat header (see SpectatorHeader) so all four
    // games' spectator bars look alike; this one had no room name and no sign
    // that you were spectating at all.
    if (gs.isSpectator) {
      return SpectatorHeader(
        game: gs,
        statusLine: '${l10n.llRound} ${state.round}',
        // The score history goes on the status line, in the slot Tichu uses for
        // its tappable score chips — the same move Skull King and Mighty made,
        // which Love Letter missed. The draw-pile count keeps its place beside
        // it; it is the one number this game reads off the header.
        statusTrailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.style,
              color: Cartoon.ink.withValues(alpha: 0.55),
              size: 14,
            ),
            const SizedBox(width: 6),
            Text(
              '${state.drawPileCount}',
              style: Cartoon.text(
                size: 13,
                color: Cartoon.ink.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(width: 8),
            SpectatorStatusChip(
              icon: Icons.leaderboard_outlined,
              label: l10n.gameScoreHistory,
              onTap: () => showLLScoreHistoryDialog(
                context,
                roundHistory: state.roundHistory,
                players: state.players,
                targetTokens: state.targetTokens,
              ),
            ),
          ],
        ),
        actions: [
          _buildTopActionButton(
            icon: Icons.help_outline,
            active: false,
            onTap: () {
              setState(() => _soundPanelOpen = false);
              _showCardGuide(context);
            },
          ),
          const SizedBox(width: 6),
          _buildTopActionButton(
            icon: Icons.chat_bubble_outline_rounded,
            active: _chatOpen,
            badgeCount: _chatOpen ? 0 : unread.clamp(0, 99),
            onTap: () {
              setState(() {
                _chatOpen = !_chatOpen;
                if (_chatOpen) {
                  _readChatCount = gs.chatMessages.length;
                  _soundPanelOpen = false;
                  _viewersOpen = false;
                  _moreOpen = false;
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
                }
              });
            },
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: gamePillDecoration(),
                    child: Text(
                      '${l10n.llRound} ${state.round}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Cartoon.text(size: 15),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: gamePillDecoration(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.style, color: Cartoon.ink, size: 15),
                      const SizedBox(width: 4),
                      Text(
                        '${state.drawPileCount}',
                        style: Cartoon.text(size: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _buildTopActionButton(
            icon: Icons.leaderboard_outlined,
            active: false,
            onTap: () => showLLScoreHistoryDialog(
              context,
              roundHistory: state.roundHistory,
              players: state.players,
              targetTokens: state.targetTokens,
            ),
          ),
          const SizedBox(width: 6),
          _buildTopActionButton(
            icon: Icons.help_outline,
            active: false,
            onTap: () {
              setState(() => _soundPanelOpen = false);
              _showCardGuide(context);
            },
          ),
          const SizedBox(width: 6),
          _buildTopActionButton(
            icon: Icons.chat_bubble_outline_rounded,
            active: _chatOpen,
            badgeCount: _chatOpen ? 0 : unread.clamp(0, 99),
            onTap: () {
              setState(() {
                _chatOpen = !_chatOpen;
                if (_chatOpen) {
                  _readChatCount = gs.chatMessages.length;
                  _soundPanelOpen = false;
                  _viewersOpen = false;
                  _moreOpen = false;
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
                }
              });
            },
          ),
        ],
      ),
    );
  }

  // Overflow menu: groups sound / spectators (or card-view) / exit so the
  // top bar never overflows when many actions are present.
  Widget _buildMoreMenu(GameService gs) {
    final hasMuted = gs.sfxVolume <= 0.01;
    final hasViewers = gs.cardViewers.isNotEmpty;
    return Positioned(
      top: gs.isSpectator ? 96 : 54,
      right: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: Cartoon.panelDecoration(radius: 18, shadowOffset: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Everyone gets the spectator list, the way Skull King and Mighty
            // do it. Love Letter gave it to spectators only, so a player had no
            // way to see who was watching — or to open a watcher's profile to
            // block or report them.
            _buildTopActionButton(
              icon: Icons.people_alt,
              active: false,
              badgeCount: gs.spectators.length,
              onTap: () {
                setState(() => _moreOpen = false);
                showSpectatorListDialog(context, gs);
              },
            ),
            const SizedBox(width: 6),
            if (!gs.isSpectator)
              _buildTopActionButton(
                icon: Icons.visibility,
                active: _viewersOpen,
                badgeCount: gs.cardViewers.length,
                iconColor: hasViewers ? Cartoon.blue : Cartoon.ink,
                onTap: () {
                  setState(() {
                    _viewersOpen = !_viewersOpen;
                    _moreOpen = false;
                    if (_viewersOpen) {
                      _chatOpen = false;
                      _soundPanelOpen = false;
                    }
                  });
                },
              ),
            const SizedBox(width: 6),
            _buildTopActionButton(
              icon: hasMuted ? Icons.volume_off : Icons.volume_up,
              active: _soundPanelOpen,
              onTap: () {
                setState(() {
                  _soundPanelOpen = !_soundPanelOpen;
                  _moreOpen = false;
                  if (_soundPanelOpen) {
                    _chatOpen = false;
                    _viewersOpen = false;
                  }
                });
              },
            ),
            const SizedBox(width: 6),
            _buildTopActionButton(
              icon: Icons.exit_to_app,
              active: false,
              iconColor: Cartoon.red,
              onTap: () {
                setState(() {
                  _moreOpen = false;
                  _soundPanelOpen = false;
                  _viewersOpen = false;
                });
                // Spectators leave immediately: the confirm exists to stop a
                // player abandoning a live game (team damage, desertion), and
                // a spectator loses nothing by leaving. The other games'
                // spectator views leave without asking.
                if (gs.isSpectator) {
                  gs.leaveRoom();
                } else {
                  _showExitDialog(context, gs);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopActionButton({
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
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

  Widget _buildSoundPanel(GameService gs) {
    return Positioned(
      top: gs.isSpectator ? 96 : 54,
      right: 8,
      child: SpectatorSoundPanel(game: gs, width: 190),
    );
  }

  Widget _buildViewersPanel(GameService game) {
    return Positioned(
      top: game.isSpectator ? 96 : 54,
      right: 8,
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(12),
        decoration: Cartoon.panelDecoration(radius: 18, shadowOffset: 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.visibility_rounded,
                  size: 18,
                  color: Cartoon.blue,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    L10n.of(context).gameViewingMyCards,
                    style: Cartoon.text(size: 15),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _viewersOpen = false),
                  child: const Icon(
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
                            color: const Color(0xFFFFD9D6),
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
                color: selected
                    ? Color.lerp(color, Colors.white, 0.8)
                    : Cartoon.cream,
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

  // ====================== GAME AREA ======================

  Widget _buildGameArea(
    BuildContext context,
    GameService gs,
    LLGameStateData state,
  ) {
    _seatChat.consume(gs);
    if (state.phase == 'game_end') {
      return _buildGameEnd(context, gs, state);
    }
    if (state.phase == 'round_end') {
      return _buildRoundEnd(context, gs, state);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final visiblePlayers = gs.isSpectator
              ? state.players
              : state.players.where((p) => p.position != 'self').toList();
          final isThreeOpponentPlayLayout =
              !gs.isSpectator && visiblePlayers.length == 3;
          final isOneOpponentPlayLayout =
              !gs.isSpectator && visiblePlayers.length == 1;
          final isFourSpectatorLayout =
              gs.isSpectator && visiblePlayers.length == 4;
          final mq = MediaQuery.of(context);
          final safeH = mq.size.height - mq.padding.top - mq.padding.bottom;
          final isSmallDevice = safeH < 700;
          // Card size scales with screen width (reference: iPhone 14 ~390pt).
          final cardScale = (mq.size.width / 390.0).clamp(0.88, 1.55);

          // Stable layout height — independent of BottomArea size, so trick box
          // and seat positions don't jitter when the hand grows/shrinks.
          const topBarRefH = 48.0;
          const gameAreaPadH = 8.0;
          const bottomAreaRefH = 240.0;
          final stableLayoutH = math.max(
            0.0,
            safeH - topBarRefH - bottomAreaRefH - gameAreaPadH * 2,
          );
          final trickBoxAlignmentY = gs.isSpectator
              ? (visiblePlayers.length == 3
                    ? 0.56
                    : isFourSpectatorLayout
                    ? -0.04
                    : visiblePlayers.length == 2
                    ? 0.52
                    : 0.08)
              : (isThreeOpponentPlayLayout
                    ? (isSmallDevice ? 0.52 : 0.36)
                    : isOneOpponentPlayLayout
                    ? (isSmallDevice ? 0.30 : 0.12)
                    : 0.12);
          final centerX = width / 2;
          final centerY = gs.isSpectator
              ? stableLayoutH * 0.50
              : stableLayoutH * 0.45;
          // Seats follow the device, like the Mighty and Skull King boards: a
          // fixed box meant a 6" phone and a tablet drew the same small photo
          // with the extra room going to empty felt.
          final boardScale = math
              .min(width / 360.0, stableLayoutH / 420.0)
              .clamp(0.72, 1.30);
          final seatWidth = (gs.isSpectator ? 116.0 : 126.0) * boardScale;
          final seatHeight = (gs.isSpectator ? 118.0 : 128.0) * boardScale;
          final maxSeatRadiusX = math.max(0.0, centerX - seatWidth / 2 - 10);
          final seatRadiusX = math.min(
            width * (gs.isSpectator ? 0.41 : 0.39),
            maxSeatRadiusX,
          );
          final maxSeatRadiusY = math.max(0.0, centerY - seatHeight / 2 - 8);
          final seatRadiusY = math.min(
            stableLayoutH * (gs.isSpectator ? 0.35 : 0.32),
            maxSeatRadiusY,
          );
          final seatLayouts = <_LLSeatLayout>[];

          for (int i = 0; i < visiblePlayers.length; i++) {
            final player = visiblePlayers[i];
            final angle = gs.isSpectator
                ? _llSpectatorSeatAngleForIndex(i, visiblePlayers.length)
                : _llSeatAngleForIndex(i, visiblePlayers.length);
            final seatLeft =
                centerX + seatRadiusX * math.cos(angle) - seatWidth / 2;
            final sideSeatDrop =
                !gs.isSpectator && visiblePlayers.length == 3 && i != 1
                ? 44.0
                : 0.0;
            final isTwoSpectatorLayout =
                gs.isSpectator && visiblePlayers.length == 2;
            final spectatorSeatLift = isFourSpectatorLayout
                ? 28.0
                : (isTwoSpectatorLayout ? 36.0 : 0.0);
            final bottomSpectatorLift =
                isFourSpectatorLayout && math.sin(angle) > 0 ? 16.0 : 0.0;
            final seatTop =
                centerY +
                seatRadiusY * math.sin(angle) -
                seatHeight / 2 +
                sideSeatDrop -
                spectatorSeatLift -
                bottomSpectatorLift;
            final baseDiscardH = gs.isSpectator
                ? (isFourSpectatorLayout ? 80.0 : 72.0)
                : 78.0;
            // Follows the board, not just the window width. cardScale bottoms
            // out at 0.88, so on a narrow board the piles stayed full size
            // while the seats shrank around them and each pile ended up
            // covering the neighbouring player's photo.
            final discardCardHeight =
                (baseDiscardH * cardScale * boardScale * 0.9).clamp(
                  48.0,
                  100.0,
                );
            seatLayouts.add(
              _LLSeatLayout(
                player: player,
                left: seatLeft,
                top: seatTop,
                width: seatWidth,
                height: seatHeight,
                discardCardWidth: discardCardHeight * 0.7,
                discardCardHeight: discardCardHeight,
                compact: gs.isSpectator,
              ),
            );
          }

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: stableLayoutH,
                child: IgnorePointer(
                  child: Align(
                    alignment: Alignment(0, trickBoxAlignmentY),
                    child: _buildCenterBoard(context, state),
                  ),
                ),
              ),
              for (final seat in seatLayouts)
                Positioned(
                  left: seat.left,
                  top: seat.top,
                  width: seat.width,
                  height: seat.height,
                  child: gs.isSpectator
                      ? _buildSpectatorSeat(state, gs, seat)
                      // Tappable: this was the one in-game view of Love Letter
                      // with no way into a profile at all — so no way to block
                      // or report from the table.
                      : GestureDetector(
                          onTap: () => _showPlayerProfileDialog(
                            seat.player.name,
                            gs,
                            isBot: seat.player.isBot,
                          ),
                          child: _withSeatBubble(
                            seat.player.name,
                            _buildPlayerSeatCard(
                              context,
                              state,
                              seat.player,
                              compact: seat.compact,
                            ),
                          ),
                        ),
                ),
              for (final seat in seatLayouts)
                if (seat.player.discardPile.isNotEmpty)
                  () {
                    final previewRect = _getSeatDiscardPreviewRect(
                      seat: seat,
                      boardCenterX: centerX,
                      boardCenterY: centerY,
                    );
                    return Positioned(
                      left: previewRect.left,
                      top: previewRect.top,
                      width: previewRect.width,
                      height: previewRect.height,
                      child: _buildSeatDiscardPreview(
                        context: context,
                        playerName: seat.player.name,
                        cards: seat.player.discardPile.toList(),
                        availableWidth: previewRect.width,
                        cardWidth: seat.discardCardWidth,
                        cardHeight: seat.discardCardHeight,
                        borderRadius: 8,
                        gapTight: isThreeOpponentPlayLayout,
                      ),
                    );
                  }(),
              // Player only — spectators render the log above their hand
              // overlay (see the spectator bottom area in build) so it is not
              // hidden behind it.
              if (!gs.isSpectator)
                _buildLLEventLogOverlay(state, gs, L10n.of(context)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCenterBoard(BuildContext context, LLGameStateData state) {
    final currentPlayer = state.players.cast<LLPlayer?>().firstWhere(
      (p) => p?.id == state.currentPlayer,
      orElse: () => null,
    );

    // 배경 상자 없이 내용만 올린다 — Mighty/SK 톤과 통일. 안쪽의
    // "드로우 카운트", "현재 플레이어" 알약은 각자 배경을 갖고 있어
    // 그대로 읽힌다.
    return Container(
      constraints: const BoxConstraints(maxWidth: 252),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: gamePillDecoration(radius: 99),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.style, size: 14, color: Cartoon.ink),
                    const SizedBox(width: 3),
                    Text(
                      '${state.drawPileCount}',
                      style: Cartoon.text(size: 13),
                    ),
                  ],
                ),
              ),
              if (currentPlayer != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: gamePillDecoration(
                    radius: 99,
                    color: Cartoon.yellow,
                  ),
                  child: Text(
                    currentPlayer.name,
                    style: Cartoon.userText(size: 13, weight: FontWeight.w800),
                  ),
                ),
              ],
            ],
          ),
          if (state.faceUpCards.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              L10n.of(context).llSetAsideFaceUp,
              style: Cartoon.text(
                size: 12,
                color: Cartoon.ink.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 5),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 5,
              runSpacing: 5,
              children: state.faceUpCards
                  .map(
                    (cardId) => LoveLetterCard(
                      cardId: cardId,
                      width: 44,
                      height: 63,
                      borderRadius: 10,
                      isInteractive: false,
                    ),
                  )
                  .toList(),
            ),
          ],
          // Event log is rendered as a bottom-left overlay in the game area
          // (see _buildLLEventLogOverlay). Center board stays clean.
        ],
      ),
    );
  }

  Widget _buildCardViewRequestPopup(GameService game) {
    final request = game.firstIncomingCardViewRequest;
    if (request == null) return const SizedBox.shrink();

    final spectatorId = request['spectatorId'] ?? '';
    final spectatorNickname = request['spectatorNickname'] ?? '?';

    return Positioned(
      left: 16,
      right: 16,
      top: 72,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: Cartoon.panelDecoration(radius: 22, shadowOffset: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.visibility_rounded, color: Cartoon.blue),
                  const SizedBox(width: 6),
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

  Widget _buildSpectatorSeat(
    LLGameStateData state,
    GameService game,
    _LLSeatLayout seat,
  ) {
    final p = seat.player;
    final isPending = game.pendingCardViewRequests.contains(p.id);
    final isApproved = game.approvedCardViews.contains(p.id) && p.canViewCards;
    final isViewing = _viewingPlayerId == p.id && isApproved;

    return GestureDetector(
      // The tap belongs to card view, so — as in the Skull King spectator
      // seats — profiles ride on long-press. Without it a spectator had no way
      // to block or report anyone.
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
      child: _withSeatBubble(
        p.name,
        _buildPlayerSeatCard(
          context,
          state,
          p,
          compact: seat.compact,
          highlighted: isViewing,
        ),
      ),
    );
  }

  Widget _buildPlayerSeatCard(
    BuildContext context,
    LLGameStateData state,
    LLPlayer player, {
    required bool compact,
    bool highlighted = false,
  }) {
    final isCurrent = player.id == state.currentPlayer;

    return LayoutBuilder(
      builder: (context, constraints) {
        final ultraTight =
            constraints.maxHeight <= 100 || constraints.maxWidth <= 104;
        final tight =
            ultraTight ||
            constraints.maxHeight <= 104 ||
            constraints.maxWidth <= 108;
        // 좌석 컨테이너의 외곽 padding 은 0 — 사진이 좌석의 가장자리다.
        // ultraTight/tight/compact 는 폰트 크기 결정에만 계속 쓴다.
        final horizontalPadding = ultraTight
            ? 4.0
            : (tight ? 5.0 : (compact ? 7.0 : 8.0));
        final verticalPadding = 0.0;
        // 마이티/스컬킹과 같은 톤으로 폰트 상향, seatScale 로 감쌈.
        final seatScale = (constraints.maxWidth / 116.0).clamp(0.85, 1.5);
        final nameFontSize =
            (ultraTight ? 10.0 : (tight ? 11.5 : (compact ? 13.0 : 14.0))) *
            seatScale;
        final tokenSize =
            (ultraTight ? 10.0 : (tight ? 12.5 : (compact ? 13.5 : 15.0))) *
            seatScale;
        final spacing = ultraTight ? 1.0 : (tight ? 2.0 : 4.0);
        final chipFontSize =
            (ultraTight ? 9.0 : (tight ? 10.0 : 11.5)) * seatScale;
        final statusIconSize =
            (ultraTight ? 11.0 : (tight ? 12.5 : 13.5)) * seatScale;
        final labelPadding = 0.0;
        // The photo takes whatever height the rest of the label leaves, rather
        // than a fraction of the box. A fraction did nothing visible: the label
        // is inside a scaleDown FittedBox, so asking for a bigger photo than
        // the box could hold just scaled the whole label back down — the photo
        // stayed ~44dp however large the fraction was.
        // 탈락은 이제 사진 위 오버레이로 그리니 Column 높이에서 뺀다.
        // 타임아웃 카운터는 여전히 Column 에 남아 있어서 계산에 포함.
        final fixedRows =
            spacing + // under the photo
            nameFontSize * 1.35 + // name
            (!player.eliminated && player.timeoutCount > 0
                ? (ultraTight ? 11.0 : 12.0)
                : 0.0) + // ⏱ line only (탈락 은 사진 위 배지)
            spacing +
            math.max(tokenSize, chipFontSize * 1.9) + // hearts + turn chip
            labelPadding * 2;
        final avatarDiameter =
            (constraints.maxHeight - verticalPadding * 2 - fixedRows).clamp(
              24.0,
              96.0,
            );
        // Hugs the photo instead of taking a fixed 70% of the box.
        final contentWidth = math.max(
          avatarDiameter + 6,
          math.min(
            (constraints.maxWidth - horizontalPadding * 2) * 0.7,
            avatarDiameter + 20,
          ),
        );
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          // Padding zero, decoration empty — 사진이 좌석의 가장자리.
          padding: EdgeInsets.zero,
          decoration: const BoxDecoration(),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: contentWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 현재턴/하이라이트 테두리는 ProfileAvatar 에 직접 넘겨
                  // 사진 라운드 코너와 같은 곡률로 감싼다. 탈락 표시는
                  // 사진 위에 반투명 밴드로 얹어 아바타 크기를 유지한다.
                  Padding(
                    padding: EdgeInsets.only(bottom: spacing),
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.bottomCenter,
                      children: [
                        Opacity(
                          // 탈락한 플레이어는 사진 자체도 흐리게 —
                          // 아래 탈락 밴드와 함께 눈에 덜 걸린다.
                          opacity: player.eliminated ? 0.35 : 1.0,
                          child: AfkKickBadge(
                            game: _gameService,
                            nickname: player.name,
                            avatarSize: avatarDiameter,
                            child: _withProtectBadge(
                              player,
                              avatarDiameter,
                              ProfileAvatar(
                                photoUrl: _gameService?.resolvePhotoUrl(
                                  player.photoUrl,
                                ),
                                size: avatarDiameter,
                                blocked:
                                    _gameService?.blockedUsers.contains(
                                      player.name,
                                    ) ??
                                    false,
                                border: Border.all(
                                  color:
                                      (isCurrent || highlighted) &&
                                          !player.eliminated
                                      ? (highlighted
                                            ? Cartoon.blue
                                            : Cartoon.yellow)
                                      : (player.protected && !player.eliminated)
                                      ? Cartoon.blue
                                      : Cartoon.ink,
                                  width:
                                      ((isCurrent || highlighted) &&
                                              !player.eliminated) ||
                                          (player.protected &&
                                              !player.eliminated)
                                      ? 3.5
                                      : 2.0,
                                ),
                                fallback: player.isBot
                                    ? BotAvatar(
                                        size: avatarDiameter,
                                        name: player.name,
                                      )
                                    : DefaultAvatar(size: avatarDiameter),
                              ),
                            ),
                          ),
                        ),
                        if (player.eliminated)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: ClipRRect(
                              borderRadius: BorderRadius.only(
                                bottomLeft: Radius.circular(
                                  avatarDiameter * 17 / 60,
                                ),
                                bottomRight: Radius.circular(
                                  avatarDiameter * 17 / 60,
                                ),
                              ),
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  vertical: ultraTight ? 1.0 : 2.0,
                                ),
                                color: Cartoon.ink.withValues(alpha: 0.75),
                                child: Text(
                                  L10n.of(context).llEliminated,
                                  textAlign: TextAlign.center,
                                  style: Cartoon.text(
                                    size:
                                        (ultraTight ? 10.0 : 11.5) * seatScale,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // 지금 차례면 이름에 노란 알약 — 티츄 판과 같은 표시.
                  TurnNamePill(
                    isTurn: isCurrent && !player.eliminated,
                    horizontal: 6,
                    vertical: 1,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            player.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style:
                                Cartoon.userText(
                                  size: nameFontSize,
                                  color: player.eliminated
                                      ? Cartoon.ink.withValues(alpha: 0.4)
                                      : Cartoon.ink,
                                  weight: isCurrent
                                      ? FontWeight.w800
                                      : FontWeight.w700,
                                ).copyWith(
                                  decoration: player.eliminated
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                          ),
                        ),
                        if (!player.connected)
                          Padding(
                            padding: const EdgeInsets.only(left: 3),
                            child: Icon(
                              Icons.wifi_off,
                              color: Cartoon.red,
                              size: statusIconSize,
                            ),
                          ),
                        if (player.protected)
                          Padding(
                            padding: const EdgeInsets.only(left: 3),
                            child: Icon(
                              Icons.shield_rounded,
                              color: Cartoon.blue,
                              size: statusIconSize,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (player.timeoutCount > 0 && !player.eliminated)
                    Padding(
                      padding: EdgeInsets.only(top: ultraTight ? 1 : 2),
                      child: Text(
                        '⏱ ${player.timeoutCount}/3',
                        style: Cartoon.text(
                          size: ultraTight ? 10 : 11,
                          color: Cartoon.orangeDeep,
                        ),
                      ),
                    ),
                  SizedBox(height: spacing),
                  // Hearts and the turn countdown share one row. The chip
                  // used to own a row below them, and that row cost the
                  // photo the same height whether or not it was that
                  // player's turn.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int i = 0; i < state.targetTokens; i++)
                        Padding(
                          padding: EdgeInsets.only(right: ultraTight ? 1 : 2),
                          child: Icon(
                            Icons.favorite_rounded,
                            color: i < player.tokens
                                ? player.eliminated
                                      ? const Color(0xFFB98B95)
                                      : Cartoon.red
                                : Cartoon.ink.withValues(alpha: 0.18),
                            size: tokenSize,
                          ),
                        ),
                      if (isCurrent && _remainingSeconds > 0)
                        Container(
                          margin: EdgeInsets.only(left: ultraTight ? 2 : 3),
                          padding: EdgeInsets.symmetric(
                            horizontal: ultraTight ? 4 : 5,
                            vertical: ultraTight ? 1 : 2,
                          ),
                          decoration: gamePillDecoration(
                            radius: 99,
                            color: _remainingSeconds <= 5
                                ? const Color(0xFFFFD9D6)
                                : Cartoon.cream,
                          ),
                          child: Text(
                            '${_remainingSeconds}s',
                            style: Cartoon.text(
                              size: chipFontSize + 1,
                              color: _remainingSeconds <= 5
                                  ? Cartoon.red
                                  : Cartoon.ink,
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
      },
    );
  }

  /// 시녀로 보호받는 사람의 사진 모서리에 붙는 방패. 이름 옆 작은 아이콘만으로는
  /// 누구에게 카드를 못 쓰는지 한눈에 안 들어온다.
  Widget _withProtectBadge(LLPlayer player, double d, Widget avatar) {
    if (!player.protected || player.eliminated) return avatar;
    final badge = (d * 0.36).clamp(16.0, 30.0);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          left: -badge * 0.25,
          bottom: -badge * 0.15,
          child: Container(
            width: badge,
            height: badge,
            decoration: BoxDecoration(
              color: Cartoon.blue,
              shape: BoxShape.circle,
              border: Border.all(color: Cartoon.ink, width: 1.8),
            ),
            child: Icon(
              Icons.shield_rounded,
              size: badge * 0.62,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  /// 대상 선택에 보여 줄 사람들: 고를 수 있는 사람 + 시녀로 보호 중이라 못 고르는
  /// 사람(흐리게). 서버가 보호 중인 사람을 validTargets 에서 빼므로 그대로 두면
  /// "왜 그 사람이 없지?"가 된다.
  List<({LLPlayer player, bool enabled})> _targetCandidates(
    LLGameStateData state,
    LLPendingEffect effect,
  ) {
    final valid = effect.validTargets.toSet();
    return [
      for (final p in state.players)
        if (valid.contains(p.id))
          (player: p, enabled: true)
        else if (p.protected && !p.eliminated && p.id != effect.playerId)
          (player: p, enabled: false),
    ];
  }

  Widget _buildSeatDiscardPreview({
    required BuildContext context,
    required String playerName,
    required List<String> cards,
    required double availableWidth,
    required double cardWidth,
    required double cardHeight,
    required double borderRadius,
    bool gapTight = false,
  }) {
    if (cards.isEmpty) return const SizedBox.shrink();

    final count = cards.length;
    final usableWidth = math.max(cardWidth, availableWidth);
    final step = count <= 1
        ? 0.0
        : ((usableWidth - cardWidth) / (count - 1)).clamp(
            gapTight ? 8.0 : 6.0,
            cardWidth * 0.72,
          );
    final stackWidth = count <= 1 ? cardWidth : cardWidth + step * (count - 1);
    final leftInset = math.max(0.0, (usableWidth - stackWidth) / 2);

    return GestureDetector(
      onTap: () => _showDiscardPileDialog(context, playerName, cards),
      child: SizedBox(
        width: usableWidth,
        height: cardHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < count; i++)
              Positioned(
                left: leftInset + step * i,
                child: LoveLetterCard(
                  cardId: cards[i],
                  width: cardWidth,
                  height: cardHeight,
                  borderRadius: borderRadius,
                  compact: true,
                  isInteractive: false,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Rect _getSeatDiscardPreviewRect({
    required _LLSeatLayout seat,
    required double boardCenterX,
    required double boardCenterY,
  }) {
    // The pile fans out to a quarter wider than the seat, but only where the
    // board has the room for it: on a narrow board three fanned piles are wider
    // than the screen, so they hug their own seat instead.
    final previewWidthScale = seat.width < 112 ? 1.05 : 1.25;
    final previewWidth = seat.width * previewWidthScale;
    final previewLeft = seat.left - (previewWidth - seat.width) / 2;
    // 아래 하트 줄을 덮지 않도록 좌석 바로 밑에서 시작한다.
    const gap = 2.0;
    final top = seat.top + seat.height + gap;
    return Rect.fromLTWH(
      previewLeft,
      top,
      previewWidth,
      seat.discardCardHeight,
    );
  }

  void _showDiscardPileDialog(
    BuildContext context,
    String playerName,
    List<String> cards,
  ) {
    if (cards.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Cartoon.paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: const BorderSide(color: Cartoon.ink, width: 2.5),
        ),
        title: Text(
          L10n.of(context).llDiscardedCardsTitle(playerName),
          style: Cartoon.userText(size: 18, weight: FontWeight.w800),
        ),
        content: SizedBox(
          width: 320,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: cards
                .map(
                  (cardId) => LoveLetterCard(
                    cardId: cardId,
                    width: 54,
                    height: 78,
                    borderRadius: 10,
                    compact: true,
                    isInteractive: false,
                  ),
                )
                .toList(),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          gameButton(
            L10n.of(context).llOk,
            () => Navigator.of(ctx).pop(),
            height: 42,
            size: 16,
          ),
        ],
      ),
    );
  }

  double _llSeatAngleForIndex(int index, int count) {
    final custom = _llSeatAnglesDeg(count);
    if (custom != null) return custom[index] * math.pi / 180;
    if (count <= 1) return math.pi * 1.5;
    const startDeg = 210.0;
    const endDeg = 330.0;
    final progress = index / (count - 1);
    return (startDeg + (endDeg - startDeg) * progress) * math.pi / 180;
  }

  double _llSpectatorSeatAngleForIndex(int index, int count) {
    final custom = _llSpectatorSeatAnglesDeg(count);
    if (custom != null) return custom[index] * math.pi / 180;
    if (count <= 1) return math.pi * 1.5;
    const startDeg = 165.0;
    const endDeg = 375.0;
    final progress = index / (count - 1);
    return (startDeg + (endDeg - startDeg) * progress) * math.pi / 180;
  }

  List<double>? _llSeatAnglesDeg(int count) {
    switch (count) {
      case 1:
        return const [270];
      case 2:
        return const [228, 312];
      case 3:
        return const [210, 270, 330];
      case 4:
        return const [176, 235, 305, 364];
      case 5:
        return const [150, 205, 270, 335, 390];
      default:
        return null;
    }
  }

  List<double>? _llSpectatorSeatAnglesDeg(int count) {
    switch (count) {
      case 2:
        return const [220, 320];
      case 3:
        return const [195, 270, 345];
      case 4:
        return const [128, 228, 312, 52];
      case 5:
        return const [152, 208, 270, 332, 388];
      case 6:
        return const [142, 188, 236, 304, 352, 398];
      default:
        return null;
    }
  }

  // ====================== EFFECT RESOLVE ======================

  Widget _buildEffectResolve(
    BuildContext context,
    GameService gs,
    LLGameStateData state,
  ) {
    final effect = state.pendingEffect!;
    final l10n = L10n.of(context);
    final isMyEffect = effect.playerId == gs.playerId;

    // Find actor name
    final actorName = state.players
        .firstWhere(
          (p) => p.id == effect.playerId,
          orElse: () => LLPlayer(id: '', name: '?'),
        )
        .name;

    Widget content;

    // If effect is resolved, show result
    if (effect.resolved && effect.result != null) {
      content = _buildEffectResult(context, gs, state, effect, actorName);
    }
    // Needs target selection
    else if (isMyEffect && effect.needsTarget) {
      if (effect.type == 'guard' && effect.needsGuess) {
        content = _buildGuardTargetAndGuess(context, gs, state, effect);
      } else {
        content = _buildTargetSelection(context, gs, state, effect);
      }
    }
    // Guard with auto-selected target: only needs guess
    else if (isMyEffect && effect.type == 'guard' && effect.needsGuess) {
      content = _buildGuardGuessOnly(context, gs, state, effect);
    }
    // Waiting for action
    else {
      content = Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(16),
        decoration: Cartoon.panelDecoration(radius: 22, shadowOffset: 4),
        child: Column(
          children: [
            Text(
              _getEffectDescription(effect.type, actorName, l10n),
              style: Cartoon.userText(size: 15),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.6,
                color: Cartoon.orange,
              ),
            ),
          ],
        ),
      );
    }

    final isGuardActionPanel =
        isMyEffect && effect.type == 'guard' && effect.needsGuess;
    return Container(
      color: Colors.black.withValues(
        alpha: isGuardActionPanel ? (_guardPeekActive ? 0.02 : 0.10) : 0.3,
      ),
      padding: const EdgeInsets.only(bottom: 8),
      child: CartoonEntrance(
        key: ValueKey('eff-${effect.type}-${effect.resolved}'),
        from: const Offset(0, 22),
        child: content,
      ),
    );
  }

  Widget _buildGuardTargetAndGuess(
    BuildContext context,
    GameService gs,
    LLGameStateData state,
    LLPendingEffect effect,
  ) {
    final l10n = L10n.of(context);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 120),
      opacity: _guardPeekActive ? 0.34 : 1.0,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(12),
        decoration: Cartoon.panelDecoration(radius: 22, shadowOffset: 4),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.llGuardSelectTarget,
                    style: Cartoon.text(size: 16, color: Cartoon.red),
                  ),
                ),
                if (_remainingSeconds > 0)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: gamePillDecoration(
                      radius: 99,
                      color: _remainingSeconds <= 5
                          ? const Color(0xFFFFD9D6)
                          : Cartoon.cream,
                    ),
                    child: Text(
                      '${_remainingSeconds}s',
                      style: Cartoon.text(
                        size: 13,
                        color: _remainingSeconds <= 5
                            ? Cartoon.red
                            : Cartoon.ink,
                      ),
                    ),
                  ),
                _buildGuardPeekButton(context),
              ],
            ),
            const SizedBox(height: 8),
            // Target buttons
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _targetCandidates(state, effect).map((c) {
                final player = c.player;
                final targetId = player.id;
                final isSelected = c.enabled && _selectedTarget == targetId;
                return GestureDetector(
                  onTap: c.enabled
                      ? () => setState(() => _selectedTarget = targetId)
                      : null,
                  child: Opacity(
                    opacity: c.enabled ? 1.0 : 0.45,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration:
                          gamePillDecoration(
                            radius: 20,
                            color: isSelected ? Cartoon.yellow : Cartoon.cream,
                          ).copyWith(
                            border: Border.all(
                              color: isSelected
                                  ? Cartoon.ink
                                  : Cartoon.ink.withValues(alpha: 0.4),
                              width: isSelected ? 2.6 : 1.8,
                            ),
                          ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!c.enabled) ...[
                            const Icon(
                              Icons.shield_rounded,
                              size: 15,
                              color: Cartoon.blue,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            player.name,
                            style: Cartoon.userText(
                              size: 14,
                              weight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.llGuardGuessCard,
              style: Cartoon.text(size: 15, color: Cartoon.red),
            ),
            const SizedBox(height: 8),
            _buildGuardGuessGrid(context, state),
            const SizedBox(height: 12),
            gameButton(
              l10n.llConfirm,
              (_selectedTarget != null && _selectedGuess != null)
                  ? () {
                      gs.llGuardGuess(_selectedTarget!, _selectedGuess!);
                      _selectedTarget = null;
                      _selectedGuess = null;
                    }
                  : null,
              color: Cartoon.orange,
              height: 46,
              size: 17,
              expand: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuardGuessOnly(
    BuildContext context,
    GameService gs,
    LLGameStateData state,
    LLPendingEffect effect,
  ) {
    final l10n = L10n.of(context);
    final targetName = state.players
        .firstWhere(
          (p) => p.id == effect.targetId,
          orElse: () => LLPlayer(id: '', name: '?'),
        )
        .name;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 120),
      opacity: _guardPeekActive ? 0.34 : 1.0,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(12),
        decoration: Cartoon.panelDecoration(radius: 22, shadowOffset: 4),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${l10n.llGuardGuessCard} ($targetName)',
                    style: Cartoon.text(size: 16, color: Cartoon.red),
                  ),
                ),
                if (_remainingSeconds > 0)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: gamePillDecoration(
                      radius: 99,
                      color: _remainingSeconds <= 5
                          ? const Color(0xFFFFD9D6)
                          : Cartoon.cream,
                    ),
                    child: Text(
                      '${_remainingSeconds}s',
                      style: Cartoon.text(
                        size: 13,
                        color: _remainingSeconds <= 5
                            ? Cartoon.red
                            : Cartoon.ink,
                      ),
                    ),
                  ),
                _buildGuardPeekButton(context),
              ],
            ),
            const SizedBox(height: 8),
            _buildGuardGuessGrid(context, state),
            const SizedBox(height: 12),
            gameButton(
              l10n.llConfirm,
              _selectedGuess != null
                  ? () {
                      gs.llGuardGuess(effect.targetId!, _selectedGuess!);
                      _selectedGuess = null;
                    }
                  : null,
              color: Cartoon.orange,
              height: 46,
              size: 17,
              expand: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuardPeekButton(BuildContext context) {
    return Listener(
      onPointerDown: (_) => setState(() => _guardPeekActive = true),
      onPointerUp: (_) => setState(() => _guardPeekActive = false),
      onPointerCancel: (_) => setState(() => _guardPeekActive = false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: gamePillDecoration(radius: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.visibility_rounded, size: 15, color: Cartoon.ink),
            const SizedBox(width: 6),
            Text(L10n.of(context).llGuardPeek, style: Cartoon.text(size: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildGuardGuessGrid(BuildContext context, LLGameStateData state) {
    final l10n = L10n.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: state.guessableCards.map((type) {
        final isSelected = _selectedGuess == type;
        final color = LoveLetterCard.cardColors[type] ?? Colors.grey;
        final value = LoveLetterCard.cardValues[type] ?? 0;
        final name = _getCardTypeName(type, l10n);
        final selectedTextColor = type == 'princess'
            ? Colors.black87
            : Colors.white;
        return GestureDetector(
          onTap: () => setState(() => _selectedGuess = type),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 76,
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 7),
            decoration:
                gamePillDecoration(
                  radius: 14,
                  color: isSelected ? color : Cartoon.cream,
                ).copyWith(
                  border: Border.all(
                    color: isSelected
                        ? Cartoon.ink
                        : Cartoon.ink.withValues(alpha: 0.4),
                    width: isSelected ? 2.8 : 1.8,
                  ),
                ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LoveLetterCard(
                  cardId: 'll_$type',
                  width: 42,
                  height: 60,
                  borderRadius: 9,
                  compact: true,
                  isInteractive: false,
                ),
                const SizedBox(height: 6),
                Text(
                  '$value',
                  style: Cartoon.text(
                    size: 13,
                    color: isSelected
                        ? selectedTextColor
                        : Cartoon.ink.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Cartoon.userText(
                    size: 12,
                    color: isSelected ? selectedTextColor : Cartoon.ink,
                    weight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTargetSelection(
    BuildContext context,
    GameService gs,
    LLGameStateData state,
    LLPendingEffect effect,
  ) {
    final l10n = L10n.of(context);
    final effectName = _getCardTypeName(effect.type, l10n);

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: Cartoon.panelDecoration(radius: 22, shadowOffset: 4),
      child: Column(
        children: [
          Text(
            '${l10n.llSelectTargetFor} $effectName',
            style: Cartoon.text(size: 16, color: Cartoon.red),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _targetCandidates(state, effect).map((c) {
              final player = c.player;
              final button = CartoonButton(
                expand: false,
                height: 46,
                color: c.enabled ? Cartoon.red : const Color(0xFF9A8F86),
                onPressed: c.enabled
                    ? () => gs.llSelectTarget(player.id)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!c.enabled) ...[
                        const Icon(
                          Icons.shield_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: Text(
                          player.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Cartoon.userText(
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
              return c.enabled ? button : Opacity(opacity: 0.6, child: button);
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEffectResult(
    BuildContext context,
    GameService gs,
    LLGameStateData state,
    LLPendingEffect effect,
    String actorName,
  ) {
    final l10n = L10n.of(context);
    final isMyEffect = effect.playerId == gs.playerId;
    final targetName = effect.targetId != null
        ? state.players
              .firstWhere(
                (p) => p.id == effect.targetId,
                orElse: () => LLPlayer(id: '', name: '?'),
              )
              .name
        : '';

    String resultText = '';
    Widget? extraWidget;

    switch (effect.type) {
      case 'guard':
        final correct = effect.result?['correct'] == true;
        resultText = correct
            ? l10n.llGuardCorrect(actorName, targetName)
            : l10n.llGuardWrong(actorName, targetName);
        break;
      case 'spy':
        if (isMyEffect && effect.result?['revealedCard'] != null) {
          resultText = l10n.llSpyReveal(targetName);
          extraWidget = LoveLetterCard(
            cardId: effect.result!['revealedCard'],
            width: 56,
            height: 80,
            isInteractive: false,
          );
        } else if (effect.targetId == gs.playerId &&
            effect.result?['revealedCard'] != null) {
          resultText = l10n.llSpySawYour(actorName);
        } else {
          resultText = l10n.llSpyPeeked(actorName, targetName);
        }
        break;
      case 'baron':
        final loser = effect.result?['loser'];
        if (loser == null) {
          resultText = l10n.llBaronTie(actorName, targetName);
        } else {
          final loserIsActor = loser == effect.playerId;
          final loserName = loserIsActor ? actorName : targetName;
          final winnerName = loserIsActor ? targetName : actorName;
          resultText = l10n.llBaronLose(loserName, winnerName);
        }
        // Show cards if available
        if (effect.result?['myCard'] != null &&
            effect.result?['targetCard'] != null &&
            (isMyEffect || effect.targetId == gs.playerId)) {
          extraWidget = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              LoveLetterCard(
                cardId: effect.result!['myCard'],
                width: 48,
                height: 68,
                compact: true,
                isInteractive: false,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'vs',
                  style: Cartoon.text(
                    size: 15,
                    color: Cartoon.ink.withValues(alpha: 0.55),
                  ),
                ),
              ),
              LoveLetterCard(
                cardId: effect.result!['targetCard'],
                width: 48,
                height: 68,
                compact: true,
                isInteractive: false,
              ),
            ],
          );
        }
        break;
      case 'prince':
        final discarded = effect.result?['discardedCard'];
        final eliminated = effect.result?['eliminated'] == true;
        if (eliminated) {
          resultText = l10n.llPrinceEliminated(targetName);
        } else {
          resultText = l10n.llPrinceDiscard(targetName);
        }
        if (discarded != null) {
          extraWidget = LoveLetterCard(
            cardId: discarded,
            width: 48,
            height: 68,
            compact: true,
            isInteractive: false,
          );
        }
        break;
      case 'king':
        resultText = l10n.llKingSwap(actorName, targetName);
        break;
    }

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: Cartoon.panelDecoration(radius: 22, shadowOffset: 4),
      child: Column(
        children: [
          Text(
            resultText,
            style: Cartoon.userText(size: 15),
            textAlign: TextAlign.center,
          ),
          if (extraWidget != null) ...[const SizedBox(height: 12), extraWidget],
          if (isMyEffect) ...[
            const SizedBox(height: 12),
            gameButton(
              l10n.llOk,
              () => gs.llEffectAck(),
              color: Cartoon.orange,
              height: 44,
              size: 17,
            ),
          ] else ...[
            const SizedBox(height: 8),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.6,
                color: Cartoon.orange,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ====================== ROUND END ======================

  // Shared "last round details" widgets used by both round end and game end.
  // Contains: winner line, set-aside / face-up cards box, per-player final hand
  // + discards rows. Caller wraps with surrounding header/standings UI.
  List<Widget> _buildRoundDetailsContent(
    BuildContext context,
    LLGameStateData state,
    LLRoundHistory lastRound,
    L10n l10n,
  ) {
    final winnerLabel = lastRound.isShared
        ? l10n.llRoundSharedWinners
        : l10n.llRoundWinner;
    final winnerText = lastRound.winnerNames.isNotEmpty
        ? lastRound.winnerNames.join(', ')
        : (lastRound.winnerName ?? '?');
    return [
      const SizedBox(height: 12),
      Text(
        '$winnerLabel: $winnerText',
        style: Cartoon.userText(
          size: 17,
          weight: lastRound.isShared ? FontWeight.w800 : FontWeight.w700,
        ),
      ),
      if (lastRound.setAside != null || lastRound.faceUpCards.isNotEmpty) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Cartoon.cream,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (lastRound.setAside != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        l10n.llSetAsideHidden,
                        style: Cartoon.text(
                          size: 13,
                          color: Cartoon.ink.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    LoveLetterCard(
                      cardId: lastRound.setAside!,
                      width: 38,
                      height: 54,
                      borderRadius: 6,
                      compact: true,
                      isInteractive: false,
                    ),
                  ],
                ),
              if (lastRound.setAside != null &&
                  lastRound.faceUpCards.isNotEmpty)
                const SizedBox(height: 6),
              if (lastRound.faceUpCards.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        l10n.llSetAsideFaceUp,
                        style: Cartoon.text(
                          size: 13,
                          color: Cartoon.ink.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    for (final cardId in lastRound.faceUpCards)
                      Padding(
                        padding: const EdgeInsets.only(right: 3),
                        child: LoveLetterCard(
                          cardId: cardId,
                          width: 38,
                          height: 54,
                          borderRadius: 6,
                          compact: true,
                          isInteractive: false,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 12),
      ...state.players.map((p) {
        final lastHand = lastRound.finalHands[p.id];
        final discards = p.discardPile;
        if (lastHand == null && discards.isEmpty) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 76,
                child: Text(
                  '${p.name}:',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style:
                      Cartoon.userText(
                        size: 14,
                        color: p.eliminated
                            ? Cartoon.ink.withValues(alpha: 0.35)
                            : Cartoon.ink.withValues(alpha: 0.75),
                      ).copyWith(
                        decoration: p.eliminated
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                ),
              ),
              const SizedBox(width: 6),
              if (lastHand != null)
                LoveLetterCard(
                  cardId: lastHand,
                  width: 44,
                  height: 62,
                  borderRadius: 8,
                  compact: true,
                  isInteractive: false,
                )
              else
                const SizedBox(width: 44, height: 62),
              if (discards.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  width: 2,
                  height: 48,
                  color: Cartoon.ink.withValues(alpha: 0.15),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final cardId in discards)
                          Padding(
                            padding: const EdgeInsets.only(right: 3),
                            child: LoveLetterCard(
                              cardId: cardId,
                              width: 38,
                              height: 54,
                              borderRadius: 6,
                              compact: true,
                              isInteractive: false,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      }),
    ];
  }

  Widget _buildRoundEnd(
    BuildContext context,
    GameService gs,
    LLGameStateData state,
  ) {
    final l10n = L10n.of(context);
    final lastRound = state.roundHistory.isNotEmpty
        ? state.roundHistory.last
        : null;

    return Center(
      child: CartoonEntrance(
        from: const Offset(0, 28),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(20),
          decoration: Cartoon.panelDecoration(radius: 26, shadowOffset: 4),
          // SingleChildScrollView lets the panel scroll on short screens
          // where the round details + token rows + next-round notice would
          // otherwise overflow the available height by a hair.
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  decoration: gamePillDecoration(
                    radius: 16,
                    color: Cartoon.yellow,
                  ),
                  child: Text(l10n.llRoundEnd, style: Cartoon.text(size: 19)),
                ),
                if (lastRound != null)
                  ..._buildRoundDetailsContent(context, state, lastRound, l10n),
                const SizedBox(height: 16),
                // Token status
                ...state.players.map(
                  (p) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 80,
                          child: Text(
                            p.name,
                            style: Cartoon.userText(
                              size: 14,
                              color: Cartoon.ink.withValues(alpha: 0.75),
                            ),
                          ),
                        ),
                        ...List.generate(
                          state.targetTokens,
                          (i) => Padding(
                            padding: const EdgeInsets.only(right: 2),
                            child: Icon(
                              Icons.favorite_rounded,
                              color: i < p.tokens
                                  ? Cartoon.red
                                  : Cartoon.ink.withValues(alpha: 0.18),
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.llNextRoundAuto,
                  style: Cartoon.text(
                    size: 12,
                    color: Cartoon.ink.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ====================== GAME END ======================

  Widget _buildGameEnd(
    BuildContext context,
    GameService gs,
    LLGameStateData state,
  ) {
    final l10n = L10n.of(context);
    final sorted = [...state.players]
      ..sort((a, b) => b.tokens.compareTo(a.tokens));
    final winner = sorted.isNotEmpty ? sorted.first : null;
    final lastRound = state.roundHistory.isNotEmpty
        ? state.roundHistory.last
        : null;

    return Stack(
      children: [
        const Positioned.fill(child: CartoonConfetti(seed: 9, count: 48)),
        _buildGameEndCard(context, gs, state, l10n, sorted, winner, lastRound),
      ],
    );
  }

  Widget _buildGameEndCard(
    BuildContext context,
    GameService gs,
    LLGameStateData state,
    L10n l10n,
    List<LLPlayer> sorted,
    LLPlayer? winner,
    LLRoundHistory? lastRound,
  ) {
    return Center(
      child: SingleChildScrollView(
        child: CartoonEntrance(
          from: const Offset(0, 28),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 380),
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(20),
            decoration: Cartoon.panelDecoration(radius: 26, shadowOffset: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 7,
                  ),
                  decoration: gamePillDecoration(
                    radius: 18,
                    color: Cartoon.yellow,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.emoji_events_rounded,
                        size: 22,
                        color: Cartoon.orangeDeep,
                      ),
                      const SizedBox(width: 6),
                      Text(l10n.llGameEnd, style: Cartoon.text(size: 20)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (winner != null)
                  Text(
                    '${winner.name} ${l10n.llWins}!',
                    style: Cartoon.userText(size: 19, weight: FontWeight.w800),
                  ),
                if (lastRound != null)
                  ..._buildRoundDetailsContent(context, state, lastRound, l10n),
                const SizedBox(height: 16),
                ...sorted.asMap().entries.map((entry) {
                  final i = entry.key;
                  final p = entry.value;
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: i == 0
                        ? gamePillDecoration(
                            radius: 14,
                            color: const Color(0xFFFFF1B8),
                          )
                        : BoxDecoration(
                            color: Cartoon.cream,
                            borderRadius: BorderRadius.circular(14),
                          ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '#${i + 1} ',
                          style: Cartoon.text(
                            size: 16,
                            color: i == 0
                                ? Cartoon.orangeDeep
                                : Cartoon.ink.withValues(alpha: 0.55),
                          ),
                        ),
                        SizedBox(
                          width: 80,
                          child: Text(
                            p.name,
                            style: Cartoon.userText(size: 15),
                          ),
                        ),
                        ...List.generate(
                          state.targetTokens,
                          (j) => Padding(
                            padding: const EdgeInsets.only(right: 2),
                            child: Icon(
                              Icons.favorite_rounded,
                              color: j < p.tokens
                                  ? Cartoon.red
                                  : Cartoon.ink.withValues(alpha: 0.18),
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 16),
                if (_gameEndCountdown > 0)
                  Text(
                    '${l10n.llReturnIn} $_gameEndCountdown...',
                    style: Cartoon.text(
                      size: 13,
                      color: Cartoon.ink.withValues(alpha: 0.55),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCardGuide(BuildContext context) {
    final l10n = L10n.of(context);
    final cards = [
      ('guard', 1, 5, l10n.llDescGuard),
      ('spy', 2, 2, l10n.llDescSpy),
      ('baron', 3, 2, l10n.llDescBaron),
      ('handmaid', 4, 2, l10n.llDescHandmaid),
      ('prince', 5, 2, l10n.llDescPrince),
      ('king', 6, 1, l10n.llDescKing),
      ('countess', 7, 1, l10n.llDescCountess),
      ('princess', 8, 1, l10n.llDescPrincess),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Cartoon.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        side: BorderSide(color: Cartoon.ink, width: 2.5),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Cartoon.ink.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Text(l10n.llCardGuideTitle, style: Cartoon.text(size: 19)),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: cards.length,
                  separatorBuilder: (context, index) => Container(
                    height: 2,
                    color: Cartoon.ink.withValues(alpha: 0.12),
                  ),
                  itemBuilder: (context, i) {
                    final (type, value, count, desc) = cards[i];
                    final color =
                        LoveLetterCard.cardColors[type] ?? Colors.grey;
                    final name = _getCardTypeName(type, l10n);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LoveLetterCard(
                            cardId: 'll_$type',
                            width: 36,
                            height: 52,
                            compact: true,
                            isInteractive: false,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$name ($value) ×$count',
                                  style: Cartoon.text(
                                    size: 15,
                                    color: Color.lerp(
                                      color,
                                      Cartoon.ink,
                                      0.25,
                                    )!,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  desc,
                                  style: Cartoon.userText(
                                    size: 13,
                                    color: Cartoon.ink.withValues(alpha: 0.8),
                                    weight: FontWeight.w600,
                                    height: 1.4,
                                  ),
                                ),
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

  String? _getCardDescription(BuildContext context, String cardId) {
    final type = LoveLetterCard.getCardType(cardId);
    if (type == null) return null;
    final l10n = L10n.of(context);
    switch (type) {
      case 'guard':
        return l10n.llDescGuard;
      case 'spy':
        return l10n.llDescSpy;
      case 'baron':
        return l10n.llDescBaron;
      case 'handmaid':
        return l10n.llDescHandmaid;
      case 'prince':
        return l10n.llDescPrince;
      case 'king':
        return l10n.llDescKing;
      case 'countess':
        return l10n.llDescCountess;
      case 'princess':
        return l10n.llDescPrincess;
      default:
        return null;
    }
  }

  Widget _buildCardDescription(BuildContext context) {
    final desc = _getCardDescription(context, _selectedCard!);
    if (desc == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: gamePillDecoration(radius: 14),
      child: Text(
        desc,
        style: Cartoon.userText(
          size: 12.5,
          weight: FontWeight.w600,
          height: 1.3,
        ),
      ),
    );
  }

  // ====================== BOTTOM (MY HAND) ======================

  Widget _buildBottomArea(
    BuildContext context,
    GameService gs,
    LLGameStateData state,
  ) {
    if (state.phase == 'game_end' || state.phase == 'round_end') {
      return const SizedBox.shrink();
    }
    if (gs.isSpectator) return _buildSpectatorHandArea(state, gs);

    final selfPlayer = state.players.firstWhere(
      (p) => p.position == 'self',
      orElse: () => LLPlayer(id: '', name: ''),
    );

    final isMyTurn = state.isMyTurn;

    return Container(
      // 내 차례엔 노란 바탕과 두꺼운 윗줄, 아니면 크림 바탕(티츄와 같은 규칙).
      decoration: BoxDecoration(
        color: isMyTurn ? const Color(0xFFFFF1B8) : Cartoon.paper,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(
          top: BorderSide(color: Cartoon.ink, width: isMyTurn ? 3.2 : 2.2),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        children: [
          // Self info bar
          Row(
            children: [
              Text(
                selfPlayer.name,
                style: Cartoon.userText(size: 14, weight: FontWeight.w800),
              ),
              if (selfPlayer.protected)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.shield_rounded,
                    color: Cartoon.blue,
                    size: 16,
                  ),
                ),
              if (selfPlayer.eliminated)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    'OUT',
                    style: Cartoon.text(size: 12, color: Cartoon.red),
                  ),
                ),
              if (state.isMyTurn && _remainingSeconds > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: gamePillDecoration(
                      radius: 99,
                      color: _remainingSeconds <= 5
                          ? const Color(0xFFFFD9D6)
                          : Cartoon.cream,
                    ),
                    child: Text(
                      '${_remainingSeconds}s',
                      style: Cartoon.text(
                        size: 13,
                        color: _remainingSeconds <= 5
                            ? Cartoon.red
                            : Cartoon.ink,
                      ),
                    ),
                  ),
                ),
              if (gs.myTimeoutCount > 0) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => gs.resetTimeout(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: gamePillDecoration(
                      radius: 12,
                      color: Cartoon.yellow,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${gs.myTimeoutCount}/3',
                          style: Cartoon.text(size: 13),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          L10n.of(context).gameNotAfk,
                          style: Cartoon.text(size: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const Spacer(),
              // Tokens
              ...List.generate(
                state.targetTokens,
                (i) => Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: Icon(
                    Icons.favorite_rounded,
                    color: i < selfPlayer.tokens
                        ? Cartoon.red
                        : Cartoon.ink.withValues(alpha: 0.18),
                    size: 17,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // My discard pile
          if (selfPlayer.discardPile.isNotEmpty) ...[
            SizedBox(
              height: 60,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      L10n.of(context).llPlayed,
                      style: Cartoon.text(
                        size: 12,
                        color: Cartoon.ink.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: selfPlayer.discardPile
                            .map(
                              (cardId) => Padding(
                                padding: const EdgeInsets.only(right: 3),
                                child: LoveLetterCard(
                                  cardId: cardId,
                                  width: 42,
                                  height: 60,
                                  isInteractive: false,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          // Card description
          if (_selectedCard != null) _buildCardDescription(context),
          // My cards
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ...state.myCards.map((cardId) {
                final isSelected = _selectedCard == cardId;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: LoveLetterCard(
                    cardId: cardId,
                    width: 80,
                    height: 115,
                    isSelected: isSelected,
                    isInteractive: state.isMyTurn && state.phase == 'playing',
                    onTap: () {
                      if (state.isMyTurn && state.phase == 'playing') {
                        setState(() {
                          _selectedCard = isSelected ? null : cardId;
                        });
                      }
                    },
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 8),
          // Play button
          if (state.isMyTurn && state.phase == 'playing')
            gameButton(
              L10n.of(context).llPlay,
              _selectedCard != null
                  ? () {
                      gs.llPlayCard(_selectedCard!);
                      setState(() => _selectedCard = null);
                    }
                  : null,
              color: Cartoon.blue,
              height: 48,
              size: 18,
              expand: true,
            ),
        ],
      ),
    );
  }

  Widget _buildSpectatorHandArea(LLGameStateData state, GameService game) {
    final viewingPlayer = _viewingPlayerId == null
        ? null
        : state.players.cast<LLPlayer?>().firstWhere(
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

    if (viewingPlayer == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(
          color: Cartoon.paper,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          border: Border(top: BorderSide(color: Cartoon.ink, width: 2.2)),
        ),
        child: Text(
          L10n.of(context).skGameTapToRequestCards,
          textAlign: TextAlign.center,
          style: Cartoon.userText(
            size: 14,
            color: Cartoon.ink.withValues(alpha: 0.6),
          ),
        ),
      );
    }

    if (isPending && !isApproved) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(
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
            const SizedBox(width: 6),
            Text(
              L10n.of(context).skGameRequestingCardView(viewingPlayer.name),
              style: Cartoon.userText(
                size: 14,
                color: Cartoon.ink.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      );
    }

    if (isApproved) {
      return Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
        decoration: const BoxDecoration(
          color: Cartoon.paper,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          border: Border(top: BorderSide(color: Cartoon.ink, width: 2.2)),
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
                      style: Cartoon.userText(size: 14),
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
                        Icons.close_rounded,
                        size: 20,
                        color: Cartoon.ink,
                      ),
                      onPressed: () => setState(() => _viewingPlayerId = null),
                    ),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: viewingPlayer.cards
                    .map(
                      (cardId) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: LoveLetterCard(
                          cardId: cardId,
                          width: 52,
                          height: 74,
                          borderRadius: 11,
                          compact: true,
                          isInteractive: false,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  // ====================== CHAT ======================

  Widget _buildChatPanel(BuildContext context, GameService gs) {
    if (gs.chatMessages.length != _lastChatMessageCount) {
      _lastChatMessageCount = gs.chatMessages.length;
      _readChatCount = gs.chatMessages.length;
      _scrollChatToBottom();
    }

    return DraggableChatPanel(
      accentColor: const Color(0xFFE91E63),
      sendIconColor: const Color(0xFFE91E63),
      title: L10n.of(context).spectatorChat,
      hintText: L10n.of(context).spectatorMessageHint,
      controller: _chatController,
      scrollController: _chatScrollController,
      onSend: () => _sendChatMessage(gs),
      onClose: () => setState(() => _chatOpen = false),
      itemCount: gs.chatMessages.length,
      itemBuilder: (context, index) {
        final msg = gs.chatMessages[gs.chatMessages.length - 1 - index];
        final sender = msg['sender'] as String? ?? '';
        String message = msg['message'] as String? ?? '';
        if (message == 'chat_banned') {
          final mins = msg['remainingMinutes'] as int? ?? 0;
          message = localizeChatBanned(mins, L10n.of(context));
        }
        final isMe = sender == gs.playerName;
        final isBlocked = sender.isNotEmpty && gs.isBlocked(sender);
        if (isBlocked) return const SizedBox.shrink();
        return _buildChatBubble(sender, message, isMe);
      },
    );
  }

  Widget _buildChatBubble(String sender, String message, bool isMe) {
    return ChatBubble(
      sender: sender,
      message: message,
      isMe: isMe,
      game: _gameService!,
      // Love Letter's pink, like the panel around it — the shared bubble
      // defaults to Tichu blue.
      mineColor: const Color(0xFFE91E63),
      onTap: sender.isEmpty
          ? null
          : () => _showPlayerProfileDialog(sender, _gameService!),
    );
  }

  void _scrollChatToBottom() {
    // ListView is reverse:true so offset 0 == bottom.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScrollController.hasClients) return;
      _chatScrollController.jumpTo(0);
    });
  }

  void _sendChatMessage(GameService gs) {
    final message = _chatController.text.trim();
    if (message.isEmpty) return;
    gs.sendChatMessage(message);
    _chatController.clear();
    _scrollChatToBottom();
  }

  // ====================== HELPERS ======================

  void _showExitDialog(BuildContext context, GameService gs) {
    final l10n = L10n.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Cartoon.paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: const BorderSide(color: Cartoon.ink, width: 2.5),
        ),
        title: Text(l10n.skGameLeaveTitle, style: Cartoon.text(size: 22)),
        // A mid-game-join room hands the seat to a bot instead of ending
        // the match; say so rather than warning about the wrong outcome.
        content: Text(
          gs.canLeaveInProgress
              ? l10n.midLeaveConfirmBody(kMidGameJoinCooldownMinutes)
              : l10n.skGameLeaveConfirm,
          style: Cartoon.text(size: 16.5, height: 1.4),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(foregroundColor: Cartoon.ink),
            child: Text(l10n.commonCancel, style: Cartoon.text(size: 17)),
          ),
          gameButton(l10n.skGameLeaveButton, () {
            Navigator.pop(ctx);
            gs.leaveRoom();
          }, color: Cartoon.red),
        ],
      ),
    );
  }

  // True only when the current player needs to act on the effect
  // (pick target, guess, or click OK). For non-interactive cases we show
  // the description in the trick box instead of a popup over the hand.
  bool _isEffectInteractive(LLPendingEffect effect, GameService gs) {
    return effect.playerId == gs.playerId;
  }

  // Split text into segments, emphasizing each occurrence of any name.
  List<_EffectStatusSegment> _splitNamesIntoSegments(
    String text,
    List<String> names,
  ) {
    final segs = <_EffectStatusSegment>[];
    String remaining = text;
    while (remaining.isNotEmpty) {
      int earliestIdx = -1;
      String? earliestName;
      for (final name in names) {
        if (name.isEmpty) continue;
        final idx = remaining.indexOf(name);
        if (idx != -1 && (earliestIdx == -1 || idx < earliestIdx)) {
          earliestIdx = idx;
          earliestName = name;
        }
      }
      if (earliestName == null || earliestIdx == -1) {
        segs.add(_EffectStatusSegment(remaining));
        break;
      }
      if (earliestIdx > 0) {
        segs.add(_EffectStatusSegment(remaining.substring(0, earliestIdx)));
      }
      segs.add(_EffectStatusSegment(earliestName, emphasized: true));
      remaining = remaining.substring(earliestIdx + earliestName.length);
    }
    return segs;
  }

  // Bottom-left overlay log of recent center-board events (sits just above
  // the player's hand). Updates the rolling log from the current effect
  // resolution, then renders it left-aligned with the newest line at the
  // bottom (slightly larger for emphasis).
  // Positioned wrapper for the player layout — the log sits at the bottom of
  // the game area, just above the in-flow hand.
  Widget _buildLLEventLogOverlay(
    LLGameStateData state,
    GameService gs,
    L10n l10n,
  ) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: _buildLLEventLog(state, gs, l10n),
    );
  }

  // Rolling event-log content (no Positioned). Spectators stack this directly
  // above their hand overlay so it is never hidden behind it.
  Widget _buildLLEventLog(LLGameStateData state, GameService gs, L10n l10n) {
    if (state.round != _llCenterLogRound) {
      _llCenterLog.clear();
      _llCenterLogHashes.clear();
      _llCenterLogRound = state.round;
    }
    if (state.pendingEffect != null && state.phase == 'effect_resolve') {
      final fresh = _getEffectStatusLines(state, gs, l10n);
      for (final line in fresh) {
        final hash = line.map((s) => s.text).join('|');
        if (_llCenterLogHashes.contains(hash)) continue;
        _llCenterLog.add(line);
        _llCenterLogHashes.add(hash);
        while (_llCenterLog.length > 4) {
          _llCenterLog.removeAt(0);
          _llCenterLogHashes.removeAt(0);
        }
      }
    }
    if (_llCenterLog.isEmpty) return const SizedBox.shrink();
    // _llCenterLog is oldest-first; render in natural order so the newest
    // line lands at the bottom (just above the hand).
    final lines = _llCenterLog;
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < lines.length; i++) ...[
              if (i > 0) const SizedBox(height: 2),
              RichText(
                textAlign: TextAlign.left,
                text: TextSpan(
                  style: Cartoon.userText(
                    size: i == lines.length - 1 ? 14 : 12,
                    weight: i == lines.length - 1
                        ? FontWeight.w800
                        : FontWeight.w600,
                  ),
                  children: [
                    for (final seg in lines[i])
                      TextSpan(
                        text: seg.text,
                        style: seg.emphasized
                            ? const TextStyle(
                                color: Cartoon.red,
                                fontWeight: FontWeight.w800,
                              )
                            : null,
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Build 1-2 lines of styled status segments for the trick box.
  List<List<_EffectStatusSegment>> _getEffectStatusLines(
    LLGameStateData state,
    GameService gs,
    L10n l10n,
  ) {
    final effect = state.pendingEffect;
    if (effect == null || state.phase != 'effect_resolve') return const [];

    final actor = state.players
        .firstWhere(
          (p) => p.id == effect.playerId,
          orElse: () => LLPlayer(id: '', name: '?'),
        )
        .name;
    final targetName = effect.targetId != null
        ? state.players
              .firstWhere(
                (p) => p.id == effect.targetId,
                orElse: () => LLPlayer(id: '', name: '?'),
              )
              .name
        : '';

    final names = <String>[actor, if (targetName.isNotEmpty) targetName];
    final lines = <List<_EffectStatusSegment>>[];

    // 'blocked' is a synthetic effect emitted when a Guard/Spy/Baron/King
    // play fizzles (all opponents protected). originalType tells which
    // card was played; show "X's <card> was blocked by Handmaid".
    if (effect.type == 'blocked') {
      final cardName = _getCardTypeName(effect.originalType ?? '', l10n);
      lines.add(
        _splitNamesIntoSegments(
          l10n.llBlockedByHandmaid(actor, cardName),
          names,
        ),
      );
      return lines;
    }

    lines.add(
      _splitNamesIntoSegments(
        _getEffectDescription(effect.type, actor, l10n),
        names,
      ),
    );

    if (effect.resolved) {
      final isMyEffect = effect.playerId == gs.playerId;
      String result = '';
      switch (effect.type) {
        case 'guard':
          if (effect.result != null) {
            final correct = effect.result?['correct'] == true;
            result = correct
                ? l10n.llGuardCorrect(actor, targetName)
                : l10n.llGuardWrong(actor, targetName);
          }
          break;
        case 'spy':
          // Server omits result for observers, but targetId is set.
          if (effect.targetId != null) {
            if (effect.targetId == gs.playerId && !isMyEffect) {
              result = l10n.llSpySawYour(actor);
            } else {
              result = l10n.llSpyPeeked(actor, targetName);
            }
          }
          break;
        case 'baron':
          if (effect.result != null) {
            final loser = effect.result?['loser'];
            if (loser == null) {
              result = l10n.llBaronTie(actor, targetName);
            } else {
              // Loser is one of actor/target; the other one is the
              // comparison opponent (winner of the swap).
              final loserIsActor = loser == effect.playerId;
              final loserName = loserIsActor ? actor : targetName;
              final winnerName = loserIsActor ? targetName : actor;
              result = l10n.llBaronLose(loserName, winnerName);
            }
          }
          break;
        case 'prince':
          if (effect.result != null) {
            final eliminated = effect.result?['eliminated'] == true;
            result = eliminated
                ? l10n.llPrinceEliminated(targetName)
                : l10n.llPrinceDiscard(targetName);
          }
          break;
        case 'king':
          result = l10n.llKingSwap(actor, targetName);
          break;
      }
      if (result.isNotEmpty) {
        lines.add(_splitNamesIntoSegments(result, names));
      }
    }

    return lines;
  }

  String _getEffectDescription(String type, String actorName, L10n l10n) {
    switch (type) {
      case 'guard':
        return l10n.llGuardEffect(actorName);
      case 'spy':
        return l10n.llSpyEffect(actorName);
      case 'baron':
        return l10n.llBaronEffect(actorName);
      case 'prince':
        return l10n.llPrinceEffect(actorName);
      case 'king':
        return l10n.llKingEffect(actorName);
      case 'handmaid':
        return l10n.llHandmaidEffect(actorName);
      default:
        return actorName;
    }
  }

  String _getCardTypeName(String type, L10n l10n) {
    switch (type) {
      case 'guard':
        return l10n.llCardGuard;
      case 'spy':
        return l10n.llCardSpy;
      case 'baron':
        return l10n.llCardBaron;
      case 'handmaid':
        return l10n.llCardHandmaid;
      case 'prince':
        return l10n.llCardPrince;
      case 'king':
        return l10n.llCardKing;
      case 'countess':
        return l10n.llCardCountess;
      case 'princess':
        return l10n.llCardPrincess;
      default:
        return type;
    }
  }

  // ====================== PROFILE DIALOG ======================

  void _showPlayerProfileDialog(
    String nickname,
    GameService game, {
    bool isBot = false,
  }) {
    showPlayerProfileDialog(
      context,
      nickname,
      game,
      initialGame: 'love_letter',
      subtitle: L10n.of(context).gamePlayerProfile,
      isBot: isBot,
      dismissWhen: (g) =>
          g.llGameState == null || g.llGameState!.phase == 'game_end',
    );
  }
}

class _EffectStatusSegment {
  final String text;
  final bool emphasized;
  const _EffectStatusSegment(this.text, {this.emphasized = false});
}

class _LLSeatLayout {
  final LLPlayer player;
  final double left;
  final double top;
  final double width;
  final double height;
  final double discardCardWidth;
  final double discardCardHeight;
  final bool compact;

  const _LLSeatLayout({
    required this.player,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.discardCardWidth,
    required this.discardCardHeight,
    required this.compact,
  });
}
