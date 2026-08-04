import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/game_service.dart';
import '../models/player.dart';
import '../models/ll_game_state.dart';
import '../widgets/love_letter_card.dart';
import '../widgets/connection_overlay.dart';
import '../widgets/draggable_chat_panel.dart';
import '../widgets/level_badge.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/seat_chat_bubble.dart';
import '../widgets/bot_avatar.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/player_profile_dialog.dart';
import '../widgets/spectator_controls.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n_helpers.dart';

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
            if (gs.isSpectator && gs.hasRoom && !gs.hasActiveGame) {
              return _buildSpectatorWaiting(context, gs);
            }
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

  Widget _buildSpectatorWaiting(BuildContext context, GameService gs) {
    final themeColors = gs.themeGradient;
    final slots = gs.roomPlayers;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: themeColors,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                child: Column(
                  children: [
                    // Header bar
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.90),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE0D8D4)),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => gs.leaveRoom(),
                            icon: const Icon(
                              Icons.arrow_back,
                              color: Color(0xFF5A4038),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFE91E63,
                              ).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              L10n.of(context).spectatorWatching,
                              style: const TextStyle(
                                color: Color(0xFFE91E63),
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              gs.currentRoomName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF5A4038),
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          _buildHeaderActionButton(
                            icon: gs.sfxVolume <= 0.01
                                ? Icons.volume_off
                                : Icons.volume_up,
                            active: _soundPanelOpen,
                            onTap: () {
                              setState(() {
                                _soundPanelOpen = !_soundPanelOpen;
                                if (_soundPanelOpen) _chatOpen = false;
                              });
                            },
                          ),
                          const SizedBox(width: 6),
                          _buildHeaderActionButton(
                            icon: Icons.chat_bubble_outline_rounded,
                            active: _chatOpen,
                            badgeCount: _chatOpen
                                ? 0
                                : (gs.chatMessages.length - _readChatCount)
                                      .clamp(0, 99),
                            onTap: () {
                              setState(() {
                                _chatOpen = !_chatOpen;
                                if (_chatOpen) {
                                  _readChatCount = gs.chatMessages.length;
                                  _soundPanelOpen = false;
                                }
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Slot list
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
                            children: [
                              Expanded(
                                child: LayoutBuilder(
                                  builder: (context, gridConstraints) {
                                    final wide = gridConstraints.maxWidth > 620;
                                    return GridView.builder(
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
                                        return _buildLLSpectatorSlot(
                                          gs,
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
              if (_soundPanelOpen) _buildSoundPanel(gs),
              if (_chatOpen) _buildChatPanel(context, gs),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderActionButton({
    required IconData icon,
    required bool active,
    int badgeCount = 0,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: active
                  ? const Color(0xFFE91E63).withValues(alpha: 0.15)
                  : const Color(0xFFF2ECE8),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 18,
              color: active ? const Color(0xFFE91E63) : const Color(0xFF6A5A52),
            ),
          ),
          if (badgeCount > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Color(0xFFE91E63),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$badgeCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
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
    return SeatBubbleAnchor(text: _seatChat.textFor(nickname), child: seat);
  }

  /// The last thing each player said, over their waiting-room seat.
  late final SeatChatBubbles _seatChat = SeatChatBubbles(() {
    if (mounted) setState(() {});
  });

  /// What [nickname] just said, or null once it has timed out.
  Widget? _seatChatBubble(String nickname) {
    final text = _seatChat.textFor(nickname);
    if (text == null) return null;
    return Positioned(
      left: 62,
      right: 10,
      top: 6,
      bottom: 6,
      child: Align(
        alignment: Alignment.centerLeft,
        child: SeatChatBubble(text: text),
      ),
    );
  }

  Widget _buildWaitingSlotAvatar(
    GameService game, {
    required String name,
    required String? photoUrl,
    required bool isBot,
    required int? level,
    String? botSpeed,
  }) {
    const size = 44.0;
    final avatar = ProfileAvatar(
      photoUrl: game.resolvePhotoUrl(photoUrl),
      size: size,
      blocked: game.blockedUsers.contains(name),
      fallback: isBot
          ? BotAvatar(size: size, name: name, showBadge: true, speed: botSpeed)
          : Container(
              width: size,
              height: size,
              decoration: const BoxDecoration(
                color: Color(0xFFF0E7E3),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.person,
                size: 26,
                color: Color(0xFF9C8B84),
              ),
            ),
    );
    if (isBot || level == null) return avatar;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            right: -3,
            bottom: -3,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.2),
              ),
              child: LevelBadge(level: level, size: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLLSpectatorSlot(
    GameService game,
    Player? player,
    int slotIndex,
  ) {
    _seatChat.consume(game);
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
      onTap: () => _showPlayerProfileDialog(p.name, game, isBot: p.isBot),
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
                _buildWaitingSlotAvatar(
                  game,
                  name: p.name,
                  photoUrl: p.photoUrl,
                  isBot: p.isBot,
                  level: p.level,
                  botSpeed: p.botSpeed,
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
              child: Text('👑', style: TextStyle(fontSize: 18, height: 1.0)),
            ),
          // What this player just said, for a couple of seconds.
          ?_seatChatBubble(p.name),
        ],
      ),
    );
  }

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
        statusTrailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.style, color: Color(0xFF8A7A72), size: 14),
            const SizedBox(width: 4),
            Text(
              '${state.drawPileCount}',
              style: const TextStyle(
                color: Color(0xFF8A7A72),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        actions: [
          _buildTopActionButton(
            icon: Icons.history,
            active: false,
            onTap: () => showLLScoreHistoryDialog(
              context,
              roundHistory: state.roundHistory,
              players: state.players,
              targetTokens: state.targetTokens,
            ),
          ),
          const SizedBox(width: 4),
          _buildTopActionButton(
            icon: Icons.help_outline,
            active: false,
            onTap: () {
              setState(() => _soundPanelOpen = false);
              _showCardGuide(context);
            },
          ),
          const SizedBox(width: 4),
          _buildTopActionButton(
            icon: Icons.chat_bubble_outline,
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
          const SizedBox(width: 4),
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0EBE8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${l10n.llRound} ${state.round}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF5A4038),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0EBE8),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.style,
                        color: Color(0xFF8A7A72),
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${state.drawPileCount}',
                        style: const TextStyle(
                          color: Color(0xFF8A7A72),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _buildTopActionButton(
            icon: Icons.history,
            active: false,
            onTap: () => showLLScoreHistoryDialog(
              context,
              roundHistory: state.roundHistory,
              players: state.players,
              targetTokens: state.targetTokens,
            ),
          ),
          const SizedBox(width: 4),
          _buildTopActionButton(
            icon: Icons.help_outline,
            active: false,
            onTap: () {
              setState(() => _soundPanelOpen = false);
              _showCardGuide(context);
            },
          ),
          const SizedBox(width: 4),
          _buildTopActionButton(
            icon: Icons.chat_bubble_outline,
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
          const SizedBox(width: 4),
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
            const SizedBox(width: 8),
            if (gs.isSpectator)
              _buildTopActionButton(
                icon: Icons.people_alt,
                active: false,
                badgeCount: gs.spectators.length,
                onTap: () {
                  setState(() => _moreOpen = false);
                  showSpectatorListDialog(context, gs.spectators);
                },
              )
            else
              _buildTopActionButton(
                icon: Icons.visibility,
                active: _viewersOpen,
                badgeCount: gs.cardViewers.length,
                iconColor: hasViewers
                    ? const Color(0xFF6A9BD1)
                    : const Color(0xFF5A4038),
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
            const SizedBox(width: 8),
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
    final l10n = L10n.of(context);
    final title = gs.isSpectator
        ? l10n.spectatorSoundEffects
        : l10n.gameSoundEffects;

    return Positioned(
      top: gs.isSpectator ? 96 : 54,
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
              value: gs.sfxVolume,
              onChanged: (value) => gs.setSfxVolume(value),
              onChangeEnd: (value) => gs.setSfxVolume(value, persist: true),
              min: 0,
              max: 1,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewersPanel(GameService game) {
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
                const Icon(
                  Icons.visibility,
                  size: 18,
                  color: Color(0xFF6A9BD1),
                ),
                const SizedBox(width: 8),
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
            final discardCardHeight = (baseDiscardH * cardScale * boardScale)
                .clamp(52.0, 108.0);
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

    return Container(
      constraints: const BoxConstraints(maxWidth: 252),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCFA).withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5EDE7).withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.style, size: 13, color: Color(0xFF8A7A72)),
                    const SizedBox(width: 3),
                    Text(
                      '${state.drawPileCount}',
                      style: const TextStyle(
                        color: Color(0xFF8A7A72),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (currentPlayer != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0CF).withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    currentPlayer.name,
                    style: const TextStyle(
                      color: Color(0xFF5A4038),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (state.faceUpCards.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              L10n.of(context).llSetAsideFaceUp,
              style: const TextStyle(
                color: Color(0xFF8A7A72),
                fontSize: 10,
                fontWeight: FontWeight.w600,
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
          decoration: BoxDecoration(
            color: const Color(0xFFF3F7FF).withValues(alpha: 0.98),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFCBDCF7)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
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
                  const Icon(Icons.visibility, color: Color(0xFF6A9BD1)),
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
        final horizontalPadding = ultraTight
            ? 4.0
            : (tight ? 5.0 : (compact ? 7.0 : 8.0));
        // Halved, like the Mighty and Skull King seats: at this photo size the
        // old padding read as a frame around the seat rather than as the seat.
        final verticalPadding = ultraTight
            ? 3.0
            : (tight ? 3.0 : (compact ? 4.0 : 4.0));
        final nameFontSize = ultraTight
            ? 9.0
            : (tight ? 10.0 : (compact ? 11.0 : 12.0));
        final tokenSize = ultraTight
            ? 9.0
            : (tight ? 11.0 : (compact ? 12.0 : 13.0));
        final spacing = ultraTight ? 1.0 : (tight ? 2.0 : 4.0);
        final chipFontSize = ultraTight ? 8.0 : (tight ? 9.0 : 10.0);
        final statusIconSize = ultraTight ? 10.0 : (tight ? 11.0 : 12.0);
        final labelPadding = ultraTight ? 2.0 : 3.0;
        // The photo takes whatever height the rest of the label leaves, rather
        // than a fraction of the box. A fraction did nothing visible: the label
        // is inside a scaleDown FittedBox, so asking for a bigger photo than
        // the box could hold just scaled the whole label back down — the photo
        // stayed ~44dp however large the fraction was.
        final fixedRows =
            spacing + // under the photo
            nameFontSize * 1.35 + // name
            (player.eliminated || player.timeoutCount > 0
                ? (ultraTight ? 11.0 : 12.0)
                : 0.0) + // 탈락 / ⏱ line
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
        final labelTint = player.eliminated
            ? const Color(0xFFE9DFDE).withValues(alpha: 0.78)
            : highlighted
            ? const Color(0xFFFFF0C9).withValues(alpha: 0.94)
            : isCurrent
            ? const Color(0xFFFFF0C9).withValues(alpha: 0.88)
            : const Color(0xFFFFFCFA).withValues(alpha: 0.62);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
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
                // Half the old padding — the frame was reading as a box around
                // the seat rather than as the seat.
                padding: EdgeInsets.symmetric(
                  horizontal: ultraTight ? 3 : 4,
                  vertical: labelPadding,
                ),
                decoration: BoxDecoration(
                  color: labelTint,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SizedBox(
                  width: contentWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Own row rather than inline before the name — same
                      // change as the Skull King seats: inline it had to stay
                      // at 13-16px to leave the name any width, which is too
                      // small to make out a face.
                      Padding(
                        padding: EdgeInsets.only(bottom: spacing),
                        child: ProfileAvatar(
                          photoUrl: _gameService?.resolvePhotoUrl(
                            player.photoUrl,
                          ),
                          size: avatarDiameter,
                          blocked:
                              _gameService?.blockedUsers.contains(
                                player.name,
                              ) ??
                              false,
                          fallback: player.isBot
                              ? BotAvatar(
                                  size: avatarDiameter,
                                  name: player.name,
                                )
                              : DefaultAvatar(size: avatarDiameter),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              player.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: player.eliminated
                                    ? const Color(0xFFBBAAAA)
                                    : const Color(0xFF5A4038),
                                fontSize: nameFontSize,
                                fontWeight: isCurrent
                                    ? FontWeight.w800
                                    : FontWeight.w700,
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
                                color: Colors.red,
                                size: statusIconSize,
                              ),
                            ),
                          if (player.protected)
                            Padding(
                              padding: const EdgeInsets.only(left: 3),
                              child: Icon(
                                Icons.shield,
                                color: Colors.blueAccent,
                                size: statusIconSize,
                              ),
                            ),
                        ],
                      ),
                      if (player.eliminated)
                        Padding(
                          padding: EdgeInsets.only(top: ultraTight ? 1 : 2),
                          child: Text(
                            L10n.of(context).llEliminated,
                            style: TextStyle(
                              color: Colors.red.shade300,
                              fontSize: ultraTight ? 9 : 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      if (player.timeoutCount > 0 && !player.eliminated)
                        Padding(
                          padding: EdgeInsets.only(top: ultraTight ? 1 : 2),
                          child: Text(
                            '⏱ ${player.timeoutCount}/3',
                            style: TextStyle(
                              color: const Color(0xFFE65100),
                              fontSize: ultraTight ? 9 : 10,
                              fontWeight: FontWeight.w800,
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
                              padding: EdgeInsets.only(
                                right: ultraTight ? 1 : 2,
                              ),
                              child: Icon(
                                Icons.favorite,
                                color: i < player.tokens
                                    ? player.eliminated
                                          ? const Color(0xFFB98B95)
                                          : const Color(0xFFE91E63)
                                    : const Color(0xFFE0D8D4),
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
                              decoration: BoxDecoration(
                                color: _remainingSeconds <= 5
                                    ? Colors.red.shade900
                                    : Colors.amber.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${_remainingSeconds}s',
                                style: TextStyle(
                                  color: _remainingSeconds <= 5
                                      ? Colors.redAccent
                                      : Colors.amber.shade900,
                                  fontSize: chipFontSize,
                                  fontWeight: FontWeight.w800,
                                ),
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
    );
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
    final gap = seat.compact ? -10.0 : -14.0;
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
        backgroundColor: const Color(0xFFFFFBF8),
        title: Text(
          L10n.of(context).llDiscardedCardsTitle(playerName),
          style: const TextStyle(
            color: Color(0xFF5A4038),
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
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
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(L10n.of(context).llOk),
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
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0D8D4)),
        ),
        child: Column(
          children: [
            Text(
              _getEffectDescription(effect.type, actorName, l10n),
              style: const TextStyle(color: Color(0xFF5A4038), fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFE91E63),
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
      child: content,
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
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0D8D4)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.llGuardSelectTarget,
                    style: const TextStyle(
                      color: Color(0xFFE91E63),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_remainingSeconds > 0)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _remainingSeconds <= 5
                          ? Colors.red.shade900
                          : Colors.amber.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${_remainingSeconds}s',
                      style: TextStyle(
                        color: _remainingSeconds <= 5
                            ? Colors.redAccent
                            : Colors.amber.shade900,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
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
              children: effect.validTargets.map((targetId) {
                final player = state.players.firstWhere(
                  (p) => p.id == targetId,
                  orElse: () => LLPlayer(id: targetId, name: targetId),
                );
                final isSelected = _selectedTarget == targetId;
                return GestureDetector(
                  onTap: () => setState(() => _selectedTarget = targetId),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.amber
                          : const Color(0xFFF0EBE8),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? Colors.amber
                            : const Color(0xFFE0D8D4),
                      ),
                    ),
                    child: Text(
                      player.name,
                      style: TextStyle(
                        color: isSelected
                            ? Colors.black
                            : const Color(0xFF5A4038),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.llGuardGuessCard,
              style: const TextStyle(color: Color(0xFFE91E63), fontSize: 13),
            ),
            const SizedBox(height: 8),
            _buildGuardGuessGrid(context, state),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: (_selectedTarget != null && _selectedGuess != null)
                  ? () {
                      gs.llGuardGuess(_selectedTarget!, _selectedGuess!);
                      _selectedTarget = null;
                      _selectedGuess = null;
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
              ),
              child: Text(l10n.llConfirm),
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
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0D8D4)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${l10n.llGuardGuessCard} ($targetName)',
                    style: const TextStyle(
                      color: Color(0xFFE91E63),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_remainingSeconds > 0)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _remainingSeconds <= 5
                          ? Colors.red.shade900
                          : Colors.amber.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${_remainingSeconds}s',
                      style: TextStyle(
                        color: _remainingSeconds <= 5
                            ? Colors.redAccent
                            : Colors.amber.shade900,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                _buildGuardPeekButton(context),
              ],
            ),
            const SizedBox(height: 8),
            _buildGuardGuessGrid(context, state),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _selectedGuess != null
                  ? () {
                      gs.llGuardGuess(effect.targetId!, _selectedGuess!);
                      _selectedGuess = null;
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
              ),
              child: Text(l10n.llConfirm),
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
        decoration: BoxDecoration(
          color: const Color(0xFFF3ECE8),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE0D8D4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.visibility_outlined,
              size: 14,
              color: Color(0xFF8A7A72),
            ),
            const SizedBox(width: 4),
            Text(
              L10n.of(context).llGuardPeek,
              style: const TextStyle(
                color: Color(0xFF8A7A72),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
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
            decoration: BoxDecoration(
              color: isSelected
                  ? color.withValues(alpha: 0.94)
                  : const Color(0xFFF7F1EE),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? color : const Color(0xFFE0D8D4),
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.24),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
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
                  style: TextStyle(
                    color: isSelected
                        ? selectedTextColor
                        : const Color(0xFF8A7A72),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isSelected
                        ? selectedTextColor
                        : const Color(0xFF5A4038),
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
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
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0D8D4)),
      ),
      child: Column(
        children: [
          Text(
            '${l10n.llSelectTargetFor} $effectName',
            style: const TextStyle(
              color: Color(0xFFE91E63),
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: effect.validTargets.map((targetId) {
              final player = state.players.firstWhere(
                (p) => p.id == targetId,
                orElse: () => LLPlayer(id: targetId, name: targetId),
              );
              return ElevatedButton(
                onPressed: () => gs.llSelectTarget(targetId),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE91E63),
                  foregroundColor: Colors.white,
                ),
                child: Text(player.name),
              );
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
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'vs',
                  style: TextStyle(color: Color(0xFF8A7A72), fontSize: 12),
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
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0D8D4)),
      ),
      child: Column(
        children: [
          Text(
            resultText,
            style: const TextStyle(color: Color(0xFF5A4038), fontSize: 14),
            textAlign: TextAlign.center,
          ),
          if (extraWidget != null) ...[const SizedBox(height: 12), extraWidget],
          if (isMyEffect) ...[
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => gs.llEffectAck(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE91E63),
                foregroundColor: Colors.white,
              ),
              child: Text(l10n.llOk),
            ),
          ] else ...[
            const SizedBox(height: 8),
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF8A7A72),
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
        style: TextStyle(
          color: const Color(0xFF5A4038),
          fontSize: 16,
          fontWeight: lastRound.isShared ? FontWeight.w800 : FontWeight.normal,
        ),
      ),
      if (lastRound.setAside != null || lastRound.faceUpCards.isNotEmpty) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFBF6F2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFEDE3DD)),
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
                        style: const TextStyle(
                          color: Color(0xFF8A7A72),
                          fontSize: 12,
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
                        style: const TextStyle(
                          color: Color(0xFF8A7A72),
                          fontSize: 12,
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
                  style: TextStyle(
                    color: p.eliminated
                        ? const Color(0xFFB0A39E)
                        : const Color(0xFF8A7A72),
                    fontSize: 13,
                    decoration: p.eliminated
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
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
                const SizedBox(width: 8),
                Container(width: 1, height: 48, color: const Color(0xFFE0D8D4)),
                const SizedBox(width: 8),
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
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0D8D4)),
        ),
        // SingleChildScrollView lets the panel scroll on short screens
        // where the round details + token rows + next-round notice would
        // otherwise overflow the available height by a hair.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.llRoundEnd,
                style: const TextStyle(
                  color: Color(0xFFE91E63),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
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
                          style: const TextStyle(
                            color: Color(0xFF8A7A72),
                            fontSize: 13,
                          ),
                        ),
                      ),
                      ...List.generate(
                        state.targetTokens,
                        (i) => Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: Icon(
                            Icons.favorite,
                            color: i < p.tokens
                                ? const Color(0xFFE91E63)
                                : const Color(0xFFE0D8D4),
                            size: 14,
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
                style: const TextStyle(color: Color(0xFF8A7A72), fontSize: 11),
              ),
            ],
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
                l10n.llGameEnd,
                style: const TextStyle(
                  color: Color(0xFFE91E63),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              if (winner != null)
                Text(
                  '${winner.name} ${l10n.llWins}!',
                  style: const TextStyle(
                    color: Color(0xFF5A4038),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
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
                  decoration: BoxDecoration(
                    color: i == 0
                        ? const Color(0xFFFFF8E1)
                        : const Color(0xFFF0EBE8),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '#${i + 1} ',
                        style: TextStyle(
                          color: i == 0
                              ? Colors.amber
                              : const Color(0xFF8A7A72),
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(
                        width: 80,
                        child: Text(
                          p.name,
                          style: const TextStyle(
                            color: Color(0xFF5A4038),
                            fontSize: 14,
                          ),
                        ),
                      ),
                      ...List.generate(
                        state.targetTokens,
                        (j) => Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: Icon(
                            Icons.favorite,
                            color: j < p.tokens
                                ? const Color(0xFFE91E63)
                                : const Color(0xFFE0D8D4),
                            size: 14,
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
                  style: const TextStyle(
                    color: Color(0xFF8A7A72),
                    fontSize: 12,
                  ),
                ),
            ],
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.llCardGuideTitle,
                style: const TextStyle(
                  color: Color(0xFF5A4038),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: cards.length,
                  separatorBuilder: (context, index) =>
                      const Divider(color: Color(0xFFE0D8D4), height: 1),
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
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  desc,
                                  style: const TextStyle(
                                    color: Color(0xFF6A5A52),
                                    fontSize: 12,
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
      decoration: BoxDecoration(
        color: const Color(0xFFF5F0ED),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        desc,
        style: const TextStyle(
          color: Color(0xFF5A4038),
          fontSize: 11,
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
      decoration: BoxDecoration(
        color: isMyTurn
            ? const Color(0xFFFFF8E1)
            : Colors.white.withValues(alpha: 0.85),
        border: Border(
          top: BorderSide(
            color: isMyTurn ? const Color(0xFFFFCA28) : const Color(0xFFE0D8D4),
            width: isMyTurn ? 2.5 : 1.0,
          ),
        ),
        boxShadow: isMyTurn
            ? [
                BoxShadow(
                  color: const Color(0xFFFFD54F).withValues(alpha: 0.4),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ]
            : null,
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        children: [
          // Self info bar
          Row(
            children: [
              Text(
                selfPlayer.name,
                style: const TextStyle(
                  color: Color(0xFF5A4038),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (selfPlayer.protected)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.shield, color: Colors.blueAccent, size: 14),
                ),
              if (selfPlayer.eliminated)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    'OUT',
                    style: TextStyle(
                      color: Colors.red.shade300,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              if (state.isMyTurn && _remainingSeconds > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _remainingSeconds <= 5
                          ? Colors.red.shade900
                          : Colors.amber.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${_remainingSeconds}s',
                      style: TextStyle(
                        color: _remainingSeconds <= 5
                            ? Colors.redAccent
                            : Colors.amber,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              if (gs.myTimeoutCount > 0) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => gs.resetTimeout(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
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
                          '${gs.myTimeoutCount}/3',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFE65100),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          L10n.of(context).gameNotAfk,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFFE65100),
                          ),
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
                    Icons.favorite,
                    color: i < selfPlayer.tokens
                        ? const Color(0xFFE91E63)
                        : const Color(0xFFE0D8D4),
                    size: 14,
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
                      style: const TextStyle(
                        color: Color(0xFF8A7A72),
                        fontSize: 11,
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
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selectedCard != null
                    ? () {
                        gs.llPlayCard(_selectedCard!);
                        setState(() => _selectedCard = null);
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: const Color(0xFFE0D8D4),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(
                  L10n.of(context).llPlay,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
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
        title: Text(l10n.skGameLeaveTitle),
        content: Text(l10n.skGameLeaveConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.commonCancel),
          ),
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
                  style: TextStyle(
                    color: const Color(0xFF5A4038),
                    fontSize: i == lines.length - 1 ? 13 : 11,
                    fontWeight: i == lines.length - 1
                        ? FontWeight.w700
                        : FontWeight.w600,
                  ),
                  children: [
                    for (final seg in lines[i])
                      TextSpan(
                        text: seg.text,
                        style: seg.emphasized
                            ? const TextStyle(
                                color: Color(0xFFE91E63),
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
