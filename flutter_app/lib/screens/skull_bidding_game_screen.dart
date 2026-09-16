import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/game_service.dart';
import '../models/skull_bidding_game_state.dart';
import '../widgets/afk_kick_badge.dart';
import '../widgets/turn_name_pill.dart';
import '../widgets/skull_disc.dart';
import '../widgets/connection_overlay.dart';
import '../widgets/draggable_chat_panel.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/seat_chat_bubble.dart';
import '../widgets/bot_avatar.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/player_profile_dialog.dart';
import '../widgets/spectator_controls.dart';
import '../l10n/app_localizations.dart';
import '../widgets/mid_game_join.dart';

const Color _kAccent = Color(0xFF6A4A42);
const Color _kTextPrimary = Color(0xFF5A4038);
const Color _kTextSubtle = Color(0xFF8A7A72);

class SkullBiddingGameScreen extends StatefulWidget {
  const SkullBiddingGameScreen({super.key});

  @override
  State<SkullBiddingGameScreen> createState() =>
      _SkullBiddingGameScreenState();
}

class _SkullBiddingGameScreenState extends State<SkullBiddingGameScreen> {
  String? _viewingPlayerId;
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
    final state = gs.skullBiddingGameState;
    if (state == null) return;
    final deadline = state.turnDeadline;
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

  Future<void> _recoverRoomState() async {
    if (_waitingForRoomRecovery) return;
    _waitingForRoomRecovery = true;
    await context.read<GameService>().checkRoomAndWait();
    if (!mounted) return;
    setState(() => _waitingForRoomRecovery = false);
  }

  late final SeatChatBubbles _seatChat = SeatChatBubbles(() {
    if (mounted) setState(() {});
  });

  Widget _withSeatBubble(String nickname, Widget seat) {
    return SeatBubbleAnchor(
      text: _seatChat.textFor(nickname),
      suppressed: _chatOpen,
      child: seat,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Consumer<GameService>(
        builder: (context, gs, _) {
          final state = gs.skullBiddingGameState;

          if (state == null) {
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

          if (state.phase == 'game_end' && !_gameEndCountdownActive) {
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
          if (state.phase != 'game_end') {
            _gameEndCountdownActive = false;
            _gameEndCountdownTimer?.cancel();
          }

          final themeColors = gs.themeGradient;

          return Scaffold(
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
                          _buildTopBar(context, gs, state),
                          Expanded(child: _buildGameArea(context, gs, state)),
                          if (gs.isSpectator &&
                              state.phase != 'game_end' &&
                              state.phase != 'round_end')
                            const SizedBox(height: 90)
                          else
                            _buildBottomArea(context, gs, state),
                        ],
                      ),
                      if (gs.isSpectator &&
                          state.phase != 'game_end' &&
                          state.phase != 'round_end')
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: _buildBottomArea(context, gs, state),
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

  // ====================== TOP BAR ======================

  String _phaseLabel(L10n l10n, String phase) {
    switch (phase) {
      case 'placing':
        return l10n.skullBiddingPhasePlacing;
      case 'bidding':
        return l10n.skullBiddingPhaseBidding;
      case 'revealing':
        return l10n.skullBiddingPhaseRevealing;
      case 'round_end':
        return l10n.skullBiddingPhaseRoundEnd;
      case 'game_end':
        return l10n.skullBiddingPhaseGameEnd;
      default:
        return phase;
    }
  }

  Widget _buildTopBar(
    BuildContext context,
    GameService gs,
    SkullBiddingGameStateData state,
  ) {
    final l10n = L10n.of(context);
    final unread = gs.chatMessages.length - _readChatCount;
    final statusLine =
        '${l10n.skullBiddingRound} ${state.round} · ${_phaseLabel(l10n, state.phase)}';

    if (gs.isSpectator) {
      return SpectatorHeader(
        game: gs,
        statusLine: statusLine,
        statusTrailing: SpectatorStatusChip(
          icon: Icons.leaderboard_outlined,
          label: l10n.gameScoreHistory,
          onTap: () => showSkullRoundHistoryDialog(
            context,
            roundHistory: state.roundHistory,
            players: state.players,
            targetSuccesses: state.targetSuccesses,
          ),
        ),
        actions: [
          _buildTopActionButton(
            icon: Icons.help_outline,
            active: false,
            onTap: () {
              setState(() => _soundPanelOpen = false);
              _showRulesSheet(context);
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
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        border: const Border(bottom: BorderSide(color: Color(0xFFE0D8D4))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF0EBE8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                statusLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _kTextPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _buildTopActionButton(
            icon: Icons.leaderboard_outlined,
            active: false,
            onTap: () => showSkullRoundHistoryDialog(
              context,
              roundHistory: state.roundHistory,
              players: state.players,
              targetSuccesses: state.targetSuccesses,
            ),
          ),
          const SizedBox(width: 6),
          _buildTopActionButton(
            icon: Icons.help_outline,
            active: false,
            onTap: () {
              setState(() => _soundPanelOpen = false);
              _showRulesSheet(context);
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

  Widget _buildMoreMenu(GameService gs) {
    final hasMuted = gs.sfxVolume <= 0.01;
    final hasViewers = gs.cardViewers.isNotEmpty;
    return Positioned(
      top: gs.isSpectator ? 96 : 54,
      right: 8,
      child: Container(
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
          mainAxisSize: MainAxisSize.min,
          children: [
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
                iconColor: hasViewers
                    ? const Color(0xFF6A9BD1)
                    : _kTextPrimary,
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
              iconColor: const Color(0xFFE53935),
              onTap: () {
                setState(() {
                  _moreOpen = false;
                  _soundPanelOpen = false;
                  _viewersOpen = false;
                });
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

  Widget _buildSoundPanel(GameService gs) {
    return Positioned(
      top: gs.isSpectator ? 96 : 54,
      right: 8,
      child: SpectatorSoundPanel(game: gs, width: 190),
    );
  }

  Widget _buildViewersPanel(GameService game) {
    final l10n = L10n.of(context);
    return Positioned(
      top: game.isSpectator ? 96 : 54,
      right: 8,
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(12),
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
          children: [
            Row(
              children: [
                const Icon(Icons.visibility, size: 18, color: Color(0xFF6A9BD1)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.gameViewingMyCards,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _kTextPrimary,
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
                l10n.skGameNoViewers,
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
              Icon(icon, size: 14, color: selected ? color : const Color(0xFF999999)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    color: selected ? color : _kTextPrimary,
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
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _kTextPrimary),
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

  // ====================== GAME AREA (SEATS) ======================

  Widget _buildGameArea(
    BuildContext context,
    GameService gs,
    SkullBiddingGameStateData state,
  ) {
    _seatChat.consume(gs);
    if (state.phase == 'game_end') return _buildGameEnd(context, gs, state);
    if (state.phase == 'round_end') return _buildRoundEnd(context, gs, state);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final visiblePlayers = gs.isSpectator
              ? state.players
              : state.players.where((p) => p.position != 'self').toList();
          final mq = MediaQuery.of(context);
          final safeH = mq.size.height - mq.padding.top - mq.padding.bottom;
          const topBarRefH = 48.0;
          const gameAreaPadH = 8.0;
          const bottomAreaRefH = 220.0;
          final stableLayoutH = math.max(
            0.0,
            safeH - topBarRefH - bottomAreaRefH - gameAreaPadH * 2,
          );
          final centerX = width / 2;
          final centerY = stableLayoutH * 0.46;
          final boardScale = math
              .min(width / 360.0, stableLayoutH / 420.0)
              .clamp(0.72, 1.30);
          // Bigger than the other games' seat card on purpose: this one also
          // carries a face-up reveal-discs row the others don't, and it read
          // cramped at the shared 122x128 baseline.
          final seatWidth = (gs.isSpectator ? 126.0 : 140.0) * boardScale;
          final seatHeight = (gs.isSpectator ? 136.0 : 150.0) * boardScale;
          final seatCount = visiblePlayers.length;
          final maxSeatRadiusX = math.max(0.0, centerX - seatWidth / 2 - 10);
          final seatRadiusX = math.min(
            math.min(
              width * _seatRadiusXFactor(seatCount),
              _seatRadiusXCap(width, seatCount, spectator: gs.isSpectator),
            ),
            maxSeatRadiusX,
          );
          final maxSeatRadiusY = math.max(0.0, centerY - seatHeight / 2 - 8);
          final seatRadiusY = math.min(
            math.min(
              stableLayoutH * 0.34,
              _seatRadiusYCap(stableLayoutH, spectator: gs.isSpectator, count: seatCount),
            ),
            maxSeatRadiusY,
          );

          final seatLayouts = <_SkullSeatLayout>[];
          for (int i = 0; i < visiblePlayers.length; i++) {
            final player = visiblePlayers[i];
            final angle = gs.isSpectator
                ? _spectatorSeatAngle(i, visiblePlayers.length)
                : _seatAngle(i, visiblePlayers.length);
            final seatLeft = centerX + seatRadiusX * math.cos(angle) - seatWidth / 2;
            final seatTop = centerY + seatRadiusY * math.sin(angle) - seatHeight / 2;
            seatLayouts.add(
              _SkullSeatLayout(
                player: player,
                left: seatLeft,
                top: seatTop,
                width: seatWidth,
                height: seatHeight,
                compact: gs.isSpectator,
              ),
            );
          }

          // Reveal-phase target picking happens by tapping the opponent's
          // seat directly (feels like picking a character), not a separate
          // list of nickname buttons — see _buildRevealingControls' hint text.
          final revealTargetMode = !gs.isSpectator &&
              state.phase == 'revealing' &&
              state.isMyTurn &&
              state.pendingDiscardPlayerId == null;
          final revealTargetIds = revealTargetMode
              ? state.players
                  .where((p) => !p.eliminated && p.id != gs.playerId && p.stackCount > 0)
                  .map((p) => p.id)
                  .toSet()
              : const <String>{};

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
                    alignment: const Alignment(0, 0.12),
                    child: _buildCenterBoard(context, gs, state),
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
                      : GestureDetector(
                          onTap: revealTargetIds.contains(seat.player.id)
                              ? () => gs.skullBiddingRevealTarget(seat.player.id)
                              : () => _showPlayerProfileDialog(
                                    seat.player.name,
                                    gs,
                                    isBot: seat.player.isBot,
                                  ),
                          child: _withSeatBubble(
                            seat.player.name,
                            _buildSeatCard(
                              context,
                              state,
                              seat.player,
                              compact: seat.compact,
                              isRevealTarget: revealTargetIds.contains(seat.player.id),
                            ),
                          ),
                        ),
                ),
            ],
          );
        },
      ),
    );
  }

  // Ported from sk_game_screen.dart's per-count hand-tuned arrangement — a
  // flat linear arc read as evenly-spaced-but-cramped for some counts and
  // oddly split for others. This is table geometry, not SK-specific, so it
  // carries over directly: custom angles for the counts Skull actually sees
  // (opponents 2-5 for the player view, 3-6 total for spectators), falling
  // back to the generic arc formula only where no custom table is needed.
  double _seatAngle(int index, int count) {
    if (count <= 1) return math.pi * 1.5;
    final custom = _customSeatAnglesDeg(count);
    if (custom != null) return custom[index] * math.pi / 180;
    final startDeg = _seatArcStartDeg(count);
    final endDeg = _seatArcEndDeg(count);
    final progress = index / (count - 1);
    return (startDeg + (endDeg - startDeg) * progress) * math.pi / 180;
  }

  double _spectatorSeatAngle(int index, int count) {
    if (count <= 1) return math.pi * 1.5;
    final custom = _customSpectatorSeatAnglesDeg(count) ?? _customSeatAnglesDeg(count);
    if (custom != null) return custom[index] * math.pi / 180;
    final startDeg = _seatArcStartDeg(count);
    final endDeg = _seatArcEndDeg(count);
    final progress = index / (count - 1);
    return (startDeg + (endDeg - startDeg) * progress) * math.pi / 180;
  }

  List<double>? _customSeatAnglesDeg(int count) {
    switch (count) {
      case 3:
        return const [200.0, 270.0, 340.0];
      case 4:
        return const [172.0, 238.0, 302.0, 368.0];
      case 5:
        // Mighty's wider spread (was ±27.5° like Skull King's, same as here
        // until this got widened): taller seat boxes need more vertical gap
        // between the two seats sharing each side's column, or they touch.
        return const [145.0, 215.0, 270.0, 325.0, 395.0];
      default:
        return null;
    }
  }

  List<double>? _customSpectatorSeatAnglesDeg(int count) {
    switch (count) {
      case 3:
        return const [155.0, 270.0, 385.0];
      case 6:
        return const [135.0, 185.0, 238.0, 302.0, 355.0, 405.0];
      default:
        return null;
    }
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

  double _seatRadiusXFactor(int count) {
    // 6 seats only happens for spectators (a ring all the way around) — it
    // needs to spread wider than 5 does, same reasoning as Mighty's.
    if (count >= 6) return 0.50;
    if (count == 5) return 0.44;
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

  double _seatRadiusYCap(double height, {required bool spectator, int count = 0}) {
    // 6 seats (spectator only) stack two per side vertically — same reasoning
    // as Mighty's, scaled to this screen's own base rather than importing
    // Mighty's absolute numbers, which belong to a differently-proportioned
    // layout.
    final base = count >= 6 ? 260.0 : (spectator ? 196.0 : 202.0);
    if (height >= 1100) return base + 90;
    if (height >= 850) return base + 50;
    if (height >= 700) return base + 24;
    return base;
  }

  Widget _buildCenterBoard(
    BuildContext context,
    GameService gs,
    SkullBiddingGameStateData state,
  ) {
    final l10n = L10n.of(context);
    String nameFor(String? id) {
      if (id == null) return '?';
      final p = state.players.cast<SkullBiddingPlayer?>().firstWhere(
            (p) => p?.id == id,
            orElse: () => null,
          );
      return p?.name ?? id;
    }

    Widget pill(String text, {Color bg = const Color(0xFFF5EDE7)}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: bg.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: const TextStyle(color: _kTextPrimary, fontSize: 11, fontWeight: FontWeight.w800),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              if (state.phase == 'bidding' || state.phase == 'revealing') ...[
                pill('${l10n.skullBiddingTableTotal}: ${state.tableTotal ?? '-'}'),
                if (state.highestBidder != null)
                  pill(
                    '${l10n.skullBiddingHighestBid}: ${state.highestBid} (${nameFor(state.highestBidder)})',
                    bg: const Color(0xFFFFF0CF),
                  ),
              ],
              if (state.phase == 'revealing' && state.challengerId != null)
                pill(
                  '${l10n.skullBiddingChallenger}: ${nameFor(state.challengerId)} (${state.flippedCount}/${state.targetFlips ?? 0})',
                  bg: const Color(0xFFFFF0CF),
                ),
            ],
          ),
          if (state.phase == 'revealing' && state.revealLog.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              runSpacing: 4,
              children: state.revealLog
                  .map((e) => SkullDisc(isSkull: e.disc == 'skull', size: 26, isInteractive: false))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSpectatorSeat(
    SkullBiddingGameStateData state,
    GameService game,
    _SkullSeatLayout seat,
  ) {
    final p = seat.player;
    return GestureDetector(
      onLongPress: () => _showPlayerProfileDialog(p.name, game, isBot: p.isBot),
      child: _withSeatBubble(
        p.name,
        _buildSeatCard(context, state, p, compact: seat.compact),
      ),
    );
  }

  Widget _buildSeatCard(
    BuildContext context,
    SkullBiddingGameStateData state,
    SkullBiddingPlayer player, {
    required bool compact,
    bool isRevealTarget = false,
  }) {
    final isCurrent = player.id == state.currentPlayer;
    final isChallenger = player.id == state.challengerId;
    final revealedHere = state.revealLog.where((e) => e.playerId == player.id).toList();
    final revealedSkullHere = revealedHere.any((e) => e.disc == 'skull');

    return LayoutBuilder(
      builder: (context, constraints) {
        final seatScale = (constraints.maxWidth / 116.0).clamp(0.85, 1.6);
        final avatarDiameter = (constraints.maxHeight * 0.46).clamp(28.0, 92.0);
        final nameFontSize = (compact ? 12.0 : 13.5) * seatScale;

        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: math.max(avatarDiameter + 20, constraints.maxWidth * 0.9),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.bottomCenter,
                  children: [
                    Opacity(
                      opacity: player.eliminated ? 0.35 : 1.0,
                      child: Container(
                        decoration: isRevealTarget
                            ? BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF4D99FF).withValues(alpha: 0.55),
                                    blurRadius: 14,
                                    spreadRadius: 2,
                                  ),
                                ],
                              )
                            : revealedSkullHere
                                ? BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFFC1553F).withValues(alpha: 0.55),
                                        blurRadius: 14,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  )
                                : null,
                        child: AfkKickBadge(
                          game: _gameService,
                          nickname: player.name,
                          avatarSize: avatarDiameter,
                          child: ProfileAvatar(
                            photoUrl: _gameService?.resolvePhotoUrl(player.photoUrl),
                            size: avatarDiameter,
                            blocked: _gameService?.blockedUsers.contains(player.name) ?? false,
                            border: isRevealTarget
                                ? Border.all(color: const Color(0xFF4D99FF), width: 2.5)
                                : revealedSkullHere
                                    ? Border.all(color: const Color(0xFFC1553F), width: 2.5)
                                    : (isCurrent || isChallenger) && !player.eliminated
                                        ? Border.all(
                                            color: isChallenger
                                                ? const Color(0xFFD24B7A)
                                                : const Color(0xFFE6C86A),
                                            width: 1.8,
                                          )
                                        : null,
                            fallback: player.isBot
                                ? BotAvatar(size: avatarDiameter, name: player.name)
                                : DefaultAvatar(size: avatarDiameter),
                          ),
                        ),
                      ),
                    ),
                    if (isRevealTarget)
                      Positioned(
                        top: -2,
                        right: -2,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: Color(0xFF4D99FF),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.touch_app, size: 12, color: Colors.white),
                        ),
                      ),
                    if (player.eliminated)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: ClipRRect(
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(avatarDiameter * 17 / 60),
                            bottomRight: Radius.circular(avatarDiameter * 17 / 60),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            color: Colors.black.withValues(alpha: 0.55),
                            child: Text(
                              L10n.of(context).skullBiddingEliminated,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10 * seatScale,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                TurnNamePill(
                  isTurn: isCurrent && !player.eliminated,
                  horizontal: 6,
                  vertical: 1,
                  child: Text(
                    player.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: player.eliminated ? const Color(0xFFBBAAAA) : _kTextPrimary,
                      fontSize: nameFontSize,
                      fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w700,
                      decoration: player.eliminated ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                SkullDiscStack(count: player.stackCount, discSize: 16 * seatScale),
                if (revealedHere.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  // The actual discs flipped from this seat's stack this
                  // round, face-up — so it reads like the coaster really
                  // got turned over here, not just an abstract log entry.
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 2,
                    children: [
                      for (final e in revealedHere)
                        SkullDisc(isSkull: e.disc == 'skull', size: 15 * seatScale, isInteractive: false),
                    ],
                  ),
                ],
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 0; i < state.targetSuccesses; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: Icon(
                          Icons.emoji_events,
                          size: 11 * seatScale,
                          color: i < player.successCount
                              ? const Color(0xFFE6A23C)
                              : const Color(0xFFE0D8D4),
                        ),
                      ),
                    const SizedBox(width: 4),
                    Icon(Icons.circle, size: 8 * seatScale, color: _kTextSubtle),
                    const SizedBox(width: 2),
                    Text(
                      '${player.poolRemaining}',
                      style: TextStyle(
                        fontSize: 10.5 * seatScale,
                        color: _kTextSubtle,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ====================== ROUND END / GAME END ======================

  List<Widget> _buildRoundSummary(
    BuildContext context,
    SkullBiddingGameStateData state,
    SkullBiddingRoundHistoryEntry entry,
  ) {
    final l10n = L10n.of(context);
    final challenger = state.players.cast<SkullBiddingPlayer?>().firstWhere(
          (p) => p?.id == entry.challengerId,
          orElse: () => null,
        );
    final success = entry.result == 'success';
    return [
      const SizedBox(height: 10),
      Text(
        success ? l10n.skullBiddingRoundSuccess : l10n.skullBiddingRoundFail,
        style: TextStyle(
          color: success ? const Color(0xFF4CAF50) : const Color(0xFFC1553F),
          fontSize: 15,
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        '${challenger?.name ?? '-'} · ${l10n.skullBiddingHighestBid} ${entry.bid} / ${l10n.skullBiddingTableTotal} ${entry.tableTotal}',
        style: const TextStyle(color: _kTextSubtle, fontSize: 12),
      ),
      if (state.revealLog.isNotEmpty) ...[
        const SizedBox(height: 12),
        // Replays the reveal in order, each disc tagged with whose stack it
        // came from — the actual sequence of flips, not just the outcome.
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 8,
          children: [
            for (final e in state.revealLog)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SkullDisc(isSkull: e.disc == 'skull', size: 34, isInteractive: false),
                  const SizedBox(height: 2),
                  Text(
                    state.players
                            .cast<SkullBiddingPlayer?>()
                            .firstWhere((p) => p?.id == e.playerId, orElse: () => null)
                            ?.name ??
                        '-',
                    style: const TextStyle(fontSize: 10, color: _kTextSubtle, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
          ],
        ),
      ],
    ];
  }

  Widget _buildRoundEnd(
    BuildContext context,
    GameService gs,
    SkullBiddingGameStateData state,
  ) {
    final l10n = L10n.of(context);
    final last = state.roundHistory.isNotEmpty ? state.roundHistory.last : null;
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0D8D4)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.skullBiddingPhaseRoundEnd,
                style: const TextStyle(color: _kAccent, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              if (last != null) ..._buildRoundSummary(context, state, last),
              const SizedBox(height: 16),
              ...state.players.map(
                (p) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 90,
                        child: Text(
                          p.name,
                          style: const TextStyle(color: _kTextSubtle, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ...List.generate(
                        state.targetSuccesses,
                        (i) => Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: Icon(
                            Icons.emoji_events,
                            color: i < p.successCount
                                ? const Color(0xFFE6A23C)
                                : const Color(0xFFE0D8D4),
                            size: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${l10n.skullBiddingPoolRemaining}: ${p.poolRemaining}',
                        style: const TextStyle(color: _kTextSubtle, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.skullBiddingNextRoundAuto,
                style: const TextStyle(color: _kTextSubtle, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGameEnd(
    BuildContext context,
    GameService gs,
    SkullBiddingGameStateData state,
  ) {
    final l10n = L10n.of(context);
    final winner = state.players.cast<SkullBiddingPlayer?>().firstWhere(
          (p) => p?.id == state.gameWinner,
          orElse: () => null,
        );
    final last = state.roundHistory.isNotEmpty ? state.roundHistory.last : null;
    final sorted = [...state.players]
      ..sort((a, b) => b.successCount.compareTo(a.successCount));

    return Center(
      child: SingleChildScrollView(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE0D8D4)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.skullBiddingPhaseGameEnd,
                style: const TextStyle(color: _kAccent, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              if (winner != null)
                Text(
                  '${winner.name} ${l10n.skullBiddingWins}!',
                  style: const TextStyle(color: _kTextPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              if (last != null) ..._buildRoundSummary(context, state, last),
              const SizedBox(height: 16),
              ...sorted.asMap().entries.map((entry) {
                final i = entry.key;
                final p = entry.value;
                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: i == 0 ? const Color(0xFFFFF8E1) : const Color(0xFFF0EBE8),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '#${i + 1} ',
                        style: TextStyle(
                          color: i == 0 ? Colors.amber.shade800 : _kTextSubtle,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(
                        width: 90,
                        child: Text(
                          p.name,
                          style: const TextStyle(color: _kTextPrimary, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(Icons.emoji_events, size: 14, color: const Color(0xFFE6A23C)),
                      const SizedBox(width: 3),
                      Text('${p.successCount}', style: const TextStyle(fontSize: 13, color: _kTextPrimary)),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 16),
              if (_gameEndCountdown > 0)
                Text(
                  '${l10n.llReturnIn} $_gameEndCountdown...',
                  style: const TextStyle(color: _kTextSubtle, fontSize: 12),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ====================== BOTTOM AREA ======================

  Widget _buildBottomArea(
    BuildContext context,
    GameService gs,
    SkullBiddingGameStateData state,
  ) {
    if (state.phase == 'game_end' || state.phase == 'round_end') {
      return const SizedBox.shrink();
    }
    if (gs.isSpectator) return _buildSpectatorBottomArea(context, state, gs);

    final l10n = L10n.of(context);
    final selfPlayer = state.players.cast<SkullBiddingPlayer?>().firstWhere(
          (p) => p?.position == 'self',
          orElse: () => null,
        );
    final isMyTurn = state.isMyTurn;

    return Container(
      decoration: BoxDecoration(
        color: isMyTurn ? const Color(0xFFFFF8E1) : Colors.white.withValues(alpha: 0.85),
        border: Border(
          top: BorderSide(
            color: isMyTurn ? const Color(0xFFFFCA28) : const Color(0xFFE0D8D4),
            width: isMyTurn ? 2.5 : 1.0,
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                selfPlayer?.name ?? '',
                style: const TextStyle(color: _kTextPrimary, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              if (state.isMyTurn && _remainingSeconds > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _remainingSeconds <= 5
                          ? Colors.red.shade900
                          : Colors.amber.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${_remainingSeconds}s',
                      style: TextStyle(
                        color: _remainingSeconds <= 5 ? Colors.redAccent : Colors.amber.shade900,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              if (gs.myTimeoutCount > 0) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => gs.resetTimeout(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFFB74D)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${gs.myTimeoutCount}/3',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFE65100)),
                        ),
                        const SizedBox(width: 6),
                        Text(l10n.gameNotAfk, style: const TextStyle(fontSize: 10, color: Color(0xFFE65100))),
                      ],
                    ),
                  ),
                ),
              ],
              const Spacer(),
              Icon(Icons.emoji_events, size: 14, color: const Color(0xFFE6A23C)),
              const SizedBox(width: 3),
              Text('${selfPlayer?.successCount ?? 0}/${state.targetSuccesses}',
                  style: const TextStyle(fontSize: 13, color: _kTextPrimary, fontWeight: FontWeight.w700)),
            ],
          ),
          if (state.myStack.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildMyStackRow(context, state),
          ],
          const SizedBox(height: 10),
          _buildPhaseControls(context, gs, state, selfPlayer),
        ],
      ),
    );
  }

  // Not secret from you — you chose them — but there's no physical pile in
  // front of you to glance at, so replay what you've placed this round, in
  // placement order. The last one is the top disc: what a challenge flips
  // off first.
  Widget _buildMyStackRow(BuildContext context, SkullBiddingGameStateData state) {
    final l10n = L10n.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          l10n.skullBiddingMyStackLabel,
          style: const TextStyle(fontSize: 11, color: _kTextSubtle, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (int i = 0; i < state.myStack.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SkullDisc(
                          isSkull: state.myStack[i] == 'skull',
                          size: 24,
                          isInteractive: false,
                          isSelected: i == state.myStack.length - 1,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '${i + 1}',
                          style: const TextStyle(fontSize: 9, color: _kTextSubtle, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPhaseControls(
    BuildContext context,
    GameService gs,
    SkullBiddingGameStateData state,
    SkullBiddingPlayer? selfPlayer,
  ) {
    final l10n = L10n.of(context);

    if (state.pendingDiscardPlayerId != null) {
      if (state.pendingDiscardPlayerId != gs.playerId) {
        return _waitingText(
          l10n.skullBiddingWaitingForDiscard(
            state.players
                    .cast<SkullBiddingPlayer?>()
                    .firstWhere((p) => p?.id == state.pendingDiscardPlayerId, orElse: () => null)
                    ?.name ??
                '',
          ),
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.skullBiddingChooseDiscard,
            style: const TextStyle(color: Color(0xFFC1553F), fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (state.myPoolRoses > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: GestureDetector(
                    onTap: () => gs.skullBiddingDiscardDisc('rose'),
                    child: const SkullDisc(isSkull: false, size: 60),
                  ),
                ),
              if (state.myPoolHasSkull)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: GestureDetector(
                    onTap: () => gs.skullBiddingDiscardDisc('skull'),
                    child: const SkullDisc(isSkull: true, size: 60),
                  ),
                ),
            ],
          ),
        ],
      );
    }

    if (!state.isMyTurn) {
      final current = state.players.cast<SkullBiddingPlayer?>().firstWhere(
            (p) => p?.id == state.currentPlayer,
            orElse: () => null,
          );
      return _waitingText(l10n.skullBiddingWaitingForTurn(current?.name ?? ''));
    }

    switch (state.phase) {
      case 'placing':
        return _buildPlacingControls(context, gs, state, selfPlayer);
      case 'bidding':
        return _buildBiddingControls(context, gs, state);
      case 'revealing':
        return _buildRevealingControls(context, gs, state);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _waitingText(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: _kTextSubtle, fontSize: 12),
      ),
    );
  }

  Widget _buildPlacingControls(
    BuildContext context,
    GameService gs,
    SkullBiddingGameStateData state,
    SkullBiddingPlayer? selfPlayer,
  ) {
    final l10n = L10n.of(context);
    final hasPlaced = (selfPlayer?.stackCount ?? 0) > 0;
    final tableTotalSoFar = state.players.fold<int>(0, (s, p) => s + p.stackCount);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.skullBiddingYourTurnPlace, style: const TextStyle(color: _kAccent, fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Text(
          l10n.skullBiddingMyDiscs,
          style: const TextStyle(color: _kTextSubtle, fontSize: 11, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (int i = 0; i < state.myRoses; i++)
              GestureDetector(
                onTap: () => gs.skullBiddingPlaceDisc('rose'),
                child: const SkullDisc(isSkull: false, size: 56),
              ),
            if (state.myHasSkull)
              GestureDetector(
                onTap: () => gs.skullBiddingPlaceDisc('skull'),
                child: const SkullDisc(isSkull: true, size: 56),
              ),
          ],
        ),
        if (hasPlaced) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => _showOpenBidSheet(context, gs, tableTotalSoFar),
            style: OutlinedButton.styleFrom(
              foregroundColor: _kAccent,
              side: const BorderSide(color: _kAccent),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
            ),
            child: Text(l10n.skullBiddingOpenBid),
          ),
        ],
      ],
    );
  }

  void _showOpenBidSheet(BuildContext context, GameService gs, int tableTotal) {
    final l10n = L10n.of(context);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.skullBiddingOpenBidTitle, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _kTextPrimary)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (int i = 1; i <= tableTotal; i++)
                    ActionChip(
                      label: Text('$i'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        gs.skullBiddingStartBid(i);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBiddingControls(
    BuildContext context,
    GameService gs,
    SkullBiddingGameStateData state,
  ) {
    final l10n = L10n.of(context);
    final tableTotal = state.tableTotal ?? 0;
    final minRaise = state.highestBid + 1;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${l10n.skullBiddingHighestBid}: ${state.highestBid} / ${l10n.skullBiddingTableTotal}: $tableTotal',
          style: const TextStyle(color: _kAccent, fontSize: 13, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        if (minRaise <= tableTotal)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (int i = minRaise; i <= tableTotal; i++)
                ActionChip(
                  label: Text('$i'),
                  backgroundColor: const Color(0xFFFFF0CF),
                  onPressed: () => gs.skullBiddingRaiseBid(i),
                ),
            ],
          ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => gs.skullBiddingPass(),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFC1553F),
            side: const BorderSide(color: Color(0xFFC1553F)),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 24),
          ),
          child: Text(l10n.skullBiddingPass),
        ),
      ],
    );
  }

  // Target picking itself happens by tapping the glowing seat on the table
  // (see revealTargetMode in _buildGameArea) — this is just the prompt.
  Widget _buildRevealingControls(
    BuildContext context,
    GameService gs,
    SkullBiddingGameStateData state,
  ) {
    final l10n = L10n.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.touch_app, size: 22, color: _kAccent),
        const SizedBox(height: 6),
        Text(
          l10n.skullBiddingChooseTarget,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _kAccent, fontSize: 13, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildSpectatorBottomArea(
    BuildContext context,
    SkullBiddingGameStateData state,
    GameService game,
  ) {
    final viewingPlayer = _viewingPlayerId == null
        ? null
        : state.players.cast<SkullBiddingPlayer?>().firstWhere(
              (p) => p?.id == _viewingPlayerId,
              orElse: () => null,
            );
    final isApproved = viewingPlayer != null &&
        game.approvedCardViews.contains(viewingPlayer.id);
    final l10n = L10n.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        border: const Border(top: BorderSide(color: Color(0xFFE0D8D4))),
      ),
      child: isApproved
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('${viewingPlayer.name}: ', style: const TextStyle(fontSize: 12, color: _kTextSubtle)),
                const SizedBox(width: 6),
                if (viewingPlayer.canViewHand)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int i = 0; i < (viewingPlayer.handRoses ?? 0); i++)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: SkullDisc(isSkull: false, size: 34, isInteractive: false),
                        ),
                      if (viewingPlayer.handHasSkull == true)
                        const SkullDisc(isSkull: true, size: 34, isInteractive: false),
                    ],
                  )
                else
                  Text(
                    l10n.skullBiddingSpectatorHandPending,
                    style: const TextStyle(fontSize: 12, color: _kTextSubtle),
                  ),
              ],
            )
          : Text(
              l10n.skullBiddingSpectatorHint,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: _kTextSubtle),
            ),
    );
  }

  // ====================== CARD VIEW REQUEST ======================

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
          decoration: BoxDecoration(
            color: const Color(0xFFF3F7FF).withValues(alpha: 0.98),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFCBDCF7)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 12, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.visibility, color: Color(0xFF6A9BD1)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      L10n.of(context).skGameCardViewRequest(spectatorNickname),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF4A4080)),
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
                  const SizedBox(width: 6),
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
            ],
          ),
        ),
      ),
    );
  }

  // ====================== CHAT ======================

  Widget _buildChatPanel(BuildContext context, GameService gs) {
    if (gs.chatMessages.length != _lastChatMessageCount) {
      _lastChatMessageCount = gs.chatMessages.length;
      _readChatCount = gs.chatMessages.length;
      _scrollChatToBottom();
    }

    return DraggableChatPanel(
      accentColor: _kAccent,
      sendIconColor: _kAccent,
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
        final message = msg['message'] as String? ?? '';
        final isMe = sender == gs.playerName;
        final isBlocked = sender.isNotEmpty && gs.isBlocked(sender);
        if (isBlocked) return const SizedBox.shrink();
        return ChatBubble(
          sender: sender,
          message: message,
          isMe: isMe,
          game: gs,
          mineColor: _kAccent,
          onTap: sender.isEmpty ? null : () => _showPlayerProfileDialog(sender, gs),
        );
      },
    );
  }

  void _scrollChatToBottom() {
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
        title: Text(l10n.skGameLeaveTitle),
        content: Text(
          gs.canLeaveInProgress
              ? l10n.midLeaveConfirmBody(kMidGameJoinCooldownMinutes)
              : l10n.skGameLeaveConfirm,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.commonCancel)),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              gs.leaveRoom();
            },
            child: Text(l10n.skGameLeaveButton),
          ),
        ],
      ),
    );
  }

  void _showRulesSheet(BuildContext context) {
    final l10n = L10n.of(context);
    final sections = [
      (Icons.emoji_events_outlined, l10n.skullBiddingRuleGoalTitle, l10n.skullBiddingRuleGoalBody),
      (Icons.style_outlined, l10n.skullBiddingRuleSetupTitle, l10n.skullBiddingRuleSetupBody),
      (Icons.add_circle_outline, l10n.skullBiddingRulePlaceTitle, l10n.skullBiddingRulePlaceBody),
      (Icons.gavel_outlined, l10n.skullBiddingRuleBidTitle, l10n.skullBiddingRuleBidBody),
      (Icons.visibility_outlined, l10n.skullBiddingRuleRevealTitle, l10n.skullBiddingRuleRevealBody),
      (Icons.dangerous_outlined, l10n.skullBiddingRuleSkullTitle, l10n.skullBiddingRuleSkullBody),
      (Icons.check_circle_outline, l10n.skullBiddingRuleSuccessTitle, l10n.skullBiddingRuleSuccessBody),
      (Icons.flag_outlined, l10n.skullBiddingRuleWinTitle, l10n.skullBiddingRuleWinBody),
    ];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (ctx, scrollController) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 12),
                Text(l10n.skullBiddingRulesTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _kTextPrimary)),
                const SizedBox(height: 6),
                Text(
                  l10n.skullBiddingRulesIntro,
                  style: const TextStyle(fontSize: 12, color: _kTextSubtle, fontStyle: FontStyle.italic, height: 1.4),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    controller: scrollController,
                    shrinkWrap: true,
                    itemCount: sections.length,
                    separatorBuilder: (context, index) => const Divider(color: Color(0xFFE0D8D4), height: 24),
                    itemBuilder: (context, i) {
                      final (icon, title, body) = sections[i];
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: _kAccent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: Icon(icon, size: 18, color: _kAccent),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _kTextPrimary),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  body,
                                  style: const TextStyle(fontSize: 12.5, color: Color(0xFF6A5A52), height: 1.45),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showPlayerProfileDialog(String nickname, GameService game, {bool isBot = false}) {
    showPlayerProfileDialog(
      context,
      nickname,
      game,
      subtitle: L10n.of(context).gamePlayerProfile,
      isBot: isBot,
      dismissWhen: (g) => g.skullBiddingGameState == null || g.skullBiddingGameState!.phase == 'game_end',
    );
  }
}

class _SkullSeatLayout {
  final SkullBiddingPlayer player;
  final double left;
  final double top;
  final double width;
  final double height;
  final bool compact;

  const _SkullSeatLayout({
    required this.player,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.compact,
  });
}
