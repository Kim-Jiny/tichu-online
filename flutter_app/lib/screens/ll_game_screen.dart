import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/game_service.dart';
import '../services/network_service.dart';
import '../models/player.dart';
import '../models/ll_game_state.dart';
import '../widgets/love_letter_card.dart';
import '../widgets/connection_overlay.dart';
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
  bool _chatOpen = false;
  int _readChatCount = 0;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  int _lastChatMessageCount = 0;

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
      _readChatCount = _gameService!.chatMessages.length;
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

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _gameEndCountdownTimer?.cancel();
    _chatController.dispose();
    _chatScrollController.dispose();
    _networkService?.removeListener(_onNetworkChanged);
    super.dispose();
  }

  void _updateCountdown() {
    final gs = _gameService;
    if (gs == null) return;
    final llState = gs.llGameState;
    if (llState == null) return;
    final deadline = llState.turnDeadline;
    if (deadline != null && deadline > 0) {
      final remaining = ((deadline - DateTime.now().millisecondsSinceEpoch) / 1000).ceil();
      if (remaining != _remainingSeconds) {
        setState(() => _remainingSeconds = remaining.clamp(0, 999));
      }
    } else if (_remainingSeconds != 0) {
      setState(() => _remainingSeconds = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GameService>(
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
          _gameEndCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
            if (!mounted) return;
            setState(() => _gameEndCountdown--);
            if (_gameEndCountdown <= 0) {
              _gameEndCountdownTimer?.cancel();
            }
          });
        }
        if (llState.phase != 'game_end') {
          _gameEndCountdownActive = false;
          _gameEndCountdownTimer?.cancel();
        }

        // Clear stale selections when leaving effect_resolve
        if (llState.phase != 'effect_resolve' || llState.pendingEffect == null) {
          _selectedTarget = null;
          _selectedGuess = null;
        }
        // Clear card selection when it's no longer in hand
        if (_selectedCard != null && !llState.myCards.contains(_selectedCard)) {
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
                        _buildBottomArea(context, gs, llState),
                      ],
                    ),
                    if (_chatOpen) _buildChatPanel(context, gs),
                  ],
                ),
              ),
            ),
          ),
        );
      },
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
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.90),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE0D8D4)),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => gs.leaveRoom(),
                            icon: const Icon(Icons.arrow_back, color: Color(0xFF5A4038)),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE91E63).withValues(alpha: 0.12),
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
                            icon: Icons.chat_bubble_outline_rounded,
                            active: _chatOpen,
                            badgeCount: _chatOpen ? 0 : (gs.chatMessages.length - _readChatCount).clamp(0, 99),
                            onTap: () {
                              setState(() {
                                _chatOpen = !_chatOpen;
                                if (_chatOpen) _readChatCount = gs.chatMessages.length;
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
                                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: wide ? 2 : 1,
                                        mainAxisSpacing: 10,
                                        crossAxisSpacing: 12,
                                        childAspectRatio: wide ? 2.4 : 4.0,
                                      ),
                                      itemCount: slots.length,
                                      itemBuilder: (context, index) {
                                        return _buildLLSpectatorSlot(gs, slots[index], index);
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
              color: active ? const Color(0xFFE91E63).withValues(alpha: 0.15) : const Color(0xFFF2ECE8),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: active ? const Color(0xFFE91E63) : const Color(0xFF6A5A52)),
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
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLLSpectatorSlot(GameService game, Player? player, int slotIndex) {
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
            Text(
              '',
              style: TextStyle(color: Color(0xFFBDB5B0), fontSize: 13),
            ),
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
                const Icon(Icons.person_add, size: 24, color: Color(0xFF9AA7B0)),
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
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isReady ? const Color(0xFF9ED6A5) : const Color(0xFFE0D8D4),
            width: isReady ? 2 : 1,
          ),
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
                    p.isHost
                        ? L10n.of(context).spectatorHost
                        : (isReady ? L10n.of(context).spectatorReady : L10n.of(context).spectatorWaiting),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.isHost
                          ? const Color(0xFFE6A800)
                          : isReady
                              ? const Color(0xFF4BAA6A)
                              : const Color(0xFF9A8E8A),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
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

  // ====================== TOP BAR ======================

  Widget _buildTopBar(BuildContext context, GameService gs, LLGameStateData state) {
    final l10n = L10n.of(context);
    final unread = gs.chatMessages.length - _readChatCount;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        border: const Border(bottom: BorderSide(color: Color(0xFFE0D8D4))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          // Round info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF0EBE8),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${l10n.llRound} ${state.round}',
              style: const TextStyle(color: Color(0xFF5A4038), fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          // Draw pile count
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF0EBE8),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.style, color: Color(0xFF8A7A72), size: 14),
                const SizedBox(width: 4),
                Text(
                  '${state.drawPileCount}',
                  style: const TextStyle(color: Color(0xFF8A7A72), fontSize: 12),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Card guide button
          IconButton(
            icon: const Icon(Icons.help_outline, color: Color(0xFF8A7A72), size: 20),
            onPressed: () => _showCardGuide(context),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          // Chat button
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.chat_bubble_outline, color: Color(0xFF8A7A72), size: 20),
                onPressed: () => setState(() {
                  _chatOpen = !_chatOpen;
                  if (_chatOpen) _readChatCount = gs.chatMessages.length;
                }),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              if (unread > 0 && !_chatOpen)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 9)),
                  ),
                ),
            ],
          ),
          // Exit button
          IconButton(
            icon: const Icon(Icons.exit_to_app, color: Color(0xFF8A7A72), size: 20),
            onPressed: () => _showExitDialog(context, gs),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }

  // ====================== GAME AREA ======================

  Widget _buildGameArea(BuildContext context, GameService gs, LLGameStateData state) {
    if (state.phase == 'game_end') {
      return _buildGameEnd(context, gs, state);
    }
    if (state.phase == 'round_end') {
      return _buildRoundEnd(context, gs, state);
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 8),
          if (state.faceUpCards.isNotEmpty) _buildFaceUpCards(state),
          _buildPlayersArea(context, gs, state),
          const SizedBox(height: 8),
          if (state.phase == 'effect_resolve' && state.pendingEffect != null)
            _buildEffectResolve(context, gs, state),
        ],
      ),
    );
  }

  Widget _buildPlayersArea(BuildContext context, GameService gs, LLGameStateData state) {
    final otherPlayers = state.players.where((p) => p.position != 'self').toList();

    return Column(
      children: otherPlayers.map((player) => _buildPlayerRow(context, state, player)).toList(),
    );
  }

  Widget _buildPlayerRow(BuildContext context, LLGameStateData state, LLPlayer player) {
    final isCurrent = player.id == state.currentPlayer;
    final isEffectTarget = state.pendingEffect?.targetId == player.id;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isCurrent
            ? const Color(0xFFFFF8E1)
            : isEffectTarget
                ? const Color(0xFFFFEBEE)
                : Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrent
              ? const Color(0xFFE6C86A)
              : isEffectTarget
                  ? const Color(0xFFEF9A9A)
                  : const Color(0xFFE0D8D4),
        ),
      ),
      child: Row(
        children: [
          // Name and status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      player.name,
                      style: TextStyle(
                        color: player.eliminated ? const Color(0xFFBBAAAA) : const Color(0xFF5A4038),
                        fontSize: 13,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                        decoration: player.eliminated ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (!player.connected)
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Icon(Icons.wifi_off, color: Colors.red, size: 12),
                      ),
                    if (player.protected)
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Icon(Icons.shield, color: Colors.blueAccent, size: 14),
                      ),
                    if (player.eliminated)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          L10n.of(context).llEliminated,
                          style: TextStyle(color: Colors.red.shade300, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                // Token display
                Row(
                  children: List.generate(
                    state.targetTokens,
                    (i) => Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Icon(
                        Icons.favorite,
                        color: i < player.tokens ? const Color(0xFFE91E63) : const Color(0xFFE0D8D4),
                        size: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Timer for current player
          if (isCurrent && _remainingSeconds > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _remainingSeconds <= 5 ? Colors.red.shade900 : Colors.amber.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${_remainingSeconds}s',
                style: TextStyle(
                  color: _remainingSeconds <= 5 ? Colors.redAccent : Colors.amber,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (isCurrent && _remainingSeconds > 0)
            const SizedBox(width: 6),
          // Card count
          if (!player.eliminated)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF0EBE8),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.style, color: Color(0xFF8A7A72), size: 12),
                  const SizedBox(width: 2),
                  Text('${player.cardCount}', style: const TextStyle(color: Color(0xFF8A7A72), fontSize: 11)),
                ],
              ),
            ),
          const SizedBox(width: 8),
          // Discard pile
          if (player.discardPile.isNotEmpty)
            SizedBox(
              height: 60,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: player.discardPile.reversed.take(4).map((cardId) => Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: LoveLetterCard(
                    cardId: cardId,
                    width: 42,
                    height: 60,
                    isInteractive: false,
                  ),
                )).toList(),
              ),
            ),
        ],
      ),
    );
  }

  // ====================== EFFECT RESOLVE ======================

  Widget _buildEffectResolve(BuildContext context, GameService gs, LLGameStateData state) {
    final effect = state.pendingEffect!;
    final l10n = L10n.of(context);
    final isMyEffect = effect.playerId == gs.playerId;

    // Find actor name
    final actorName = state.players.firstWhere(
      (p) => p.id == effect.playerId,
      orElse: () => LLPlayer(id: '', name: '?'),
    ).name;

    // If effect is resolved, show result
    if (effect.resolved && effect.result != null) {
      return _buildEffectResult(context, gs, state, effect, actorName);
    }

    // Needs target selection
    if (isMyEffect && effect.needsTarget) {
      if (effect.type == 'guard' && effect.needsGuess) {
        return _buildGuardTargetAndGuess(context, gs, state, effect);
      }
      return _buildTargetSelection(context, gs, state, effect);
    }

    // Guard with auto-selected target: only needs guess
    if (isMyEffect && effect.type == 'guard' && effect.needsGuess) {
      return _buildGuardGuessOnly(context, gs, state, effect);
    }

    // Waiting for action
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
            _getEffectDescription(effect.type, actorName, l10n),
            style: const TextStyle(color: Color(0xFF5A4038), fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE91E63)),
          ),
        ],
      ),
    );
  }

  Widget _buildGuardTargetAndGuess(
    BuildContext context, GameService gs, LLGameStateData state, LLPendingEffect effect,
  ) {
    final l10n = L10n.of(context);

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
            l10n.llGuardSelectTarget,
            style: const TextStyle(color: Color(0xFFE91E63), fontSize: 14, fontWeight: FontWeight.bold),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.amber : const Color(0xFFF0EBE8),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? Colors.amber : const Color(0xFFE0D8D4),
                    ),
                  ),
                  child: Text(
                    player.name,
                    style: TextStyle(
                      color: isSelected ? Colors.black : const Color(0xFF5A4038),
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
          // Guess buttons
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: state.guessableCards.map((type) {
              final isSelected = _selectedGuess == type;
              final color = LoveLetterCard.cardColors[type] ?? Colors.grey;
              final value = LoveLetterCard.cardValues[type] ?? 0;
              final name = LoveLetterCard.cardNames[type] ?? type;
              return GestureDetector(
                onTap: () => setState(() => _selectedGuess = type),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? color : const Color(0xFFF0EBE8),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: isSelected ? color : const Color(0xFFE0D8D4)),
                  ),
                  child: Text(
                    '$value $name',
                    style: TextStyle(
                      color: isSelected ? (type == 'princess' ? Colors.black87 : Colors.white) : const Color(0xFF5A4038),
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
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
    );
  }

  Widget _buildGuardGuessOnly(
    BuildContext context, GameService gs, LLGameStateData state, LLPendingEffect effect,
  ) {
    final l10n = L10n.of(context);
    final targetName = state.players.firstWhere(
      (p) => p.id == effect.targetId,
      orElse: () => LLPlayer(id: '', name: '?'),
    ).name;

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
            '${l10n.llGuardGuessCard} ($targetName)',
            style: const TextStyle(color: Color(0xFFE91E63), fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: state.guessableCards.map((type) {
              final isSelected = _selectedGuess == type;
              final color = LoveLetterCard.cardColors[type] ?? Colors.grey;
              final value = LoveLetterCard.cardValues[type] ?? 0;
              final name = LoveLetterCard.cardNames[type] ?? type;
              return GestureDetector(
                onTap: () => setState(() => _selectedGuess = type),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? color : const Color(0xFFF0EBE8),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: isSelected ? color : const Color(0xFFE0D8D4)),
                  ),
                  child: Text(
                    '$value $name',
                    style: TextStyle(
                      color: isSelected ? (type == 'princess' ? Colors.black87 : Colors.white) : const Color(0xFF5A4038),
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
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
    );
  }

  Widget _buildTargetSelection(
    BuildContext context, GameService gs, LLGameStateData state, LLPendingEffect effect,
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
            style: const TextStyle(color: Color(0xFFE91E63), fontSize: 14, fontWeight: FontWeight.bold),
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
    BuildContext context, GameService gs, LLGameStateData state,
    LLPendingEffect effect, String actorName,
  ) {
    final l10n = L10n.of(context);
    final isMyEffect = effect.playerId == gs.playerId;
    final targetName = effect.targetId != null
        ? state.players.firstWhere(
            (p) => p.id == effect.targetId,
            orElse: () => LLPlayer(id: '', name: '?'),
          ).name
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
        } else if (effect.targetId == gs.playerId && effect.result?['revealedCard'] != null) {
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
          final loserName = state.players.firstWhere(
            (p) => p.id == loser,
            orElse: () => LLPlayer(id: '', name: '?'),
          ).name;
          resultText = l10n.llBaronLose(loserName);
        }
        // Show cards if available
        if (effect.result?['myCard'] != null && (isMyEffect || effect.targetId == gs.playerId)) {
          extraWidget = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              LoveLetterCard(cardId: effect.result!['myCard'], width: 48, height: 68, compact: true, isInteractive: false),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('vs', style: TextStyle(color: Color(0xFF8A7A72), fontSize: 12)),
              ),
              LoveLetterCard(cardId: effect.result!['targetCard'], width: 48, height: 68, compact: true, isInteractive: false),
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
          if (extraWidget != null) ...[
            const SizedBox(height: 12),
            extraWidget,
          ],
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
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF8A7A72))),
          ],
        ],
      ),
    );
  }

  Widget _buildFaceUpCards(LLGameStateData state) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0D8D4)),
      ),
      child: Column(
        children: [
          Text(
            L10n.of(context).llSetAsideFaceUp,
            style: const TextStyle(color: Color(0xFF8A7A72), fontSize: 12),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: state.faceUpCards.map((cardId) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: LoveLetterCard(cardId: cardId, width: 64, height: 90, isInteractive: false),
            )).toList(),
          ),
        ],
      ),
    );
  }

  // ====================== ROUND END ======================

  Widget _buildRoundEnd(BuildContext context, GameService gs, LLGameStateData state) {
    final l10n = L10n.of(context);
    final lastRound = state.roundHistory.isNotEmpty ? state.roundHistory.last : null;

    return Center(
      child: Container(
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
              l10n.llRoundEnd,
              style: const TextStyle(color: Color(0xFFE91E63), fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (lastRound != null) ...[
              const SizedBox(height: 12),
              Text(
                '${l10n.llRoundWinner}: ${lastRound.winnerName ?? "?"}',
                style: const TextStyle(color: Color(0xFF5A4038), fontSize: 16),
              ),
              if (lastRound.finalHands.isNotEmpty) ...[
                const SizedBox(height: 12),
                ...lastRound.finalHands.entries.map((e) {
                  final playerName = state.players.firstWhere(
                    (p) => p.id == e.key,
                    orElse: () => LLPlayer(id: e.key, name: e.key),
                  ).name;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$playerName: ',
                          style: const TextStyle(color: Color(0xFF8A7A72), fontSize: 13),
                        ),
                        if (e.value != null)
                          LoveLetterCard(
                            cardId: e.value!,
                            width: 36,
                            height: 50,
                            compact: true,
                            isInteractive: false,
                          ),
                      ],
                    ),
                  );
                }),
              ],
            ],
            const SizedBox(height: 16),
            // Token status
            ...state.players.map((p) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(p.name, style: const TextStyle(color: Color(0xFF8A7A72), fontSize: 13)),
                  ),
                  ...List.generate(state.targetTokens, (i) => Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: Icon(
                      Icons.favorite,
                      color: i < p.tokens ? const Color(0xFFE91E63) : const Color(0xFFE0D8D4),
                      size: 14,
                    ),
                  )),
                ],
              ),
            )),
            const SizedBox(height: 8),
            Text(
              l10n.llNextRoundAuto,
              style: const TextStyle(color: Color(0xFF8A7A72), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  // ====================== GAME END ======================

  Widget _buildGameEnd(BuildContext context, GameService gs, LLGameStateData state) {
    final l10n = L10n.of(context);
    final sorted = [...state.players]..sort((a, b) => b.tokens.compareTo(a.tokens));
    final winner = sorted.isNotEmpty ? sorted.first : null;

    return Center(
      child: Container(
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
              style: const TextStyle(color: Color(0xFFE91E63), fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (winner != null)
              Text(
                '${winner.name} ${l10n.llWins}!',
                style: const TextStyle(color: Color(0xFF5A4038), fontSize: 18, fontWeight: FontWeight.bold),
              ),
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
                        color: i == 0 ? Colors.amber : const Color(0xFF8A7A72),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(
                      width: 80,
                      child: Text(p.name, style: const TextStyle(color: Color(0xFF5A4038), fontSize: 14)),
                    ),
                    ...List.generate(state.targetTokens, (j) => Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Icon(
                        Icons.favorite,
                        color: j < p.tokens ? const Color(0xFFE91E63) : const Color(0xFFE0D8D4),
                        size: 14,
                      ),
                    )),
                  ],
                ),
              );
            }),
            const SizedBox(height: 16),
            if (_gameEndCountdown > 0)
              Text(
                '${l10n.llReturnIn} $_gameEndCountdown...',
                style: const TextStyle(color: Color(0xFF8A7A72), fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }

  void _showCardGuide(BuildContext context) {
    final l10n = L10n.of(context);
    final cards = [
      ('guard', l10n.llDescGuard),
      ('spy', l10n.llDescSpy),
      ('baron', l10n.llDescBaron),
      ('handmaid', l10n.llDescHandmaid),
      ('prince', l10n.llDescPrince),
      ('king', l10n.llDescKing),
      ('countess', l10n.llDescCountess),
      ('princess', l10n.llDescPrincess),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
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
                style: const TextStyle(color: Color(0xFF5A4038), fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: cards.length,
                  separatorBuilder: (context, index) => const Divider(color: Color(0xFFE0D8D4), height: 1),
                  itemBuilder: (context, i) {
                    final (type, desc) = cards[i];
                    final color = LoveLetterCard.cardColors[type] ?? Colors.grey;
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
                            child: Text(
                              desc,
                              style: TextStyle(color: color, fontSize: 12, height: 1.4),
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
      case 'guard': return l10n.llDescGuard;
      case 'spy': return l10n.llDescSpy;
      case 'baron': return l10n.llDescBaron;
      case 'handmaid': return l10n.llDescHandmaid;
      case 'prince': return l10n.llDescPrince;
      case 'king': return l10n.llDescKing;
      case 'countess': return l10n.llDescCountess;
      case 'princess': return l10n.llDescPrincess;
      default: return null;
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
        style: const TextStyle(color: Color(0xFF5A4038), fontSize: 11, height: 1.3),
      ),
    );
  }

  // ====================== BOTTOM (MY HAND) ======================

  Widget _buildBottomArea(BuildContext context, GameService gs, LLGameStateData state) {
    if (state.phase == 'game_end' || state.phase == 'round_end') return const SizedBox.shrink();
    if (gs.isSpectator) return const SizedBox.shrink();

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
            ? [BoxShadow(color: const Color(0xFFFFD54F).withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, -4))]
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
                style: const TextStyle(color: Color(0xFF5A4038), fontSize: 13, fontWeight: FontWeight.w600),
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
                    style: TextStyle(color: Colors.red.shade300, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              if (state.isMyTurn && _remainingSeconds > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _remainingSeconds <= 5 ? Colors.red.shade900 : Colors.amber.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${_remainingSeconds}s',
                      style: TextStyle(
                        color: _remainingSeconds <= 5 ? Colors.redAccent : Colors.amber,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              // Tokens
              ...List.generate(state.targetTokens, (i) => Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Icon(
                  Icons.favorite,
                  color: i < selfPlayer.tokens ? const Color(0xFFE91E63) : const Color(0xFFE0D8D4),
                  size: 14,
                ),
              )),
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
                    child: Text(L10n.of(context).llPlayed, style: const TextStyle(color: Color(0xFF8A7A72), fontSize: 11)),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: selfPlayer.discardPile.map((cardId) => Padding(
                          padding: const EdgeInsets.only(right: 3),
                          child: LoveLetterCard(cardId: cardId, width: 42, height: 60, isInteractive: false),
                        )).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          // Card description
          if (_selectedCard != null)
            _buildCardDescription(context),
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
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
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

    final media = MediaQuery.of(context);
    final keyboardHeight = media.viewInsets.bottom;
    final topInset = media.padding.top;
    final panelWidth = (media.size.width - 16).clamp(220.0, 320.0);
    final topOffset = topInset + 42;
    final bottomOffset = 8 + keyboardHeight;
    final maxHeight = media.size.height - topOffset - bottomOffset;
    final panelHeight = maxHeight.clamp(160.0, 350.0);

    return Positioned(
      right: 8,
      top: topOffset,
      width: panelWidth,
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
                color: Color(0xFFE91E63),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    L10n.of(context).spectatorChat,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
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
                itemCount: gs.chatMessages.length,
                itemBuilder: (context, index) {
                  final msg = gs.chatMessages[index];
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
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _chatController,
                      decoration: InputDecoration(
                        hintText: L10n.of(context).spectatorMessageHint,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      style: const TextStyle(fontSize: 14),
                      onSubmitted: (_) => _sendChatMessage(gs),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _sendChatMessage(gs),
                    icon: const Icon(Icons.send, color: Color(0xFFE91E63)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatBubble(String sender, String message, bool isMe) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: const Color(0xFFE0E0E0),
              child: Text(sender.isNotEmpty ? sender[0] : '?', style: const TextStyle(fontSize: 12, color: Color(0xFF5A4038))),
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
                    child: Text(sender, style: const TextStyle(fontSize: 11, color: Color(0xFF8A8A8A))),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isMe ? const Color(0xFFE91E63) : const Color(0xFFF0F0F0),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(message, style: TextStyle(fontSize: 14, color: isMe ? Colors.white : const Color(0xFF333333))),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.jumpTo(_chatScrollController.position.maxScrollExtent);
      }
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
      default:
        return actorName;
    }
  }

  String _getCardTypeName(String type, L10n l10n) {
    switch (type) {
      case 'guard': return l10n.llCardGuard;
      case 'spy': return l10n.llCardSpy;
      case 'baron': return l10n.llCardBaron;
      case 'handmaid': return l10n.llCardHandmaid;
      case 'prince': return l10n.llCardPrince;
      case 'king': return l10n.llCardKing;
      case 'countess': return l10n.llCardCountess;
      case 'princess': return l10n.llCardPrincess;
      default: return type;
    }
  }

  // ====================== PROFILE DIALOG ======================

  void _showPlayerProfileDialog(String nickname, GameService game) {
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
                          child: const Icon(Icons.person_outline, color: Color(0xFF4F6B7A)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nickname,
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF3E312A)),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isMe ? L10n.of(context).gameMyProfile : L10n.of(context).gamePlayerProfile,
                                style: const TextStyle(fontSize: 12, color: Color(0xFF84766E)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (!isMe) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (game.friends.contains(nickname))
                            _buildProfileIconButton(icon: Icons.check, color: const Color(0xFFBDBDBD), tooltip: L10n.of(context).gameAlreadyFriend, onTap: () {})
                          else if (game.sentFriendRequests.contains(nickname))
                            _buildProfileIconButton(icon: Icons.hourglass_top, color: const Color(0xFFBDBDBD), tooltip: L10n.of(context).gameRequestPending, onTap: () {})
                          else
                            _buildProfileIconButton(
                              icon: Icons.person_add,
                              color: const Color(0xFF81C784),
                              tooltip: L10n.of(context).gameAddFriend,
                              onTap: () {
                                game.addFriendAction(nickname);
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(L10n.of(context).gameFriendRequestSent)));
                              },
                            ),
                          _buildProfileIconButton(
                            icon: isBlockedUser ? Icons.block : Icons.shield_outlined,
                            color: isBlockedUser ? const Color(0xFF64B5F6) : const Color(0xFFFF8A65),
                            tooltip: isBlockedUser ? L10n.of(context).gameUnblock : L10n.of(context).gameBlock,
                            onTap: () {
                              if (isBlockedUser) {
                                game.unblockUserAction(nickname);
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(L10n.of(context).gameUnblocked)));
                              } else {
                                game.blockUserAction(nickname);
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(L10n.of(context).gameBlocked)));
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
                ),
              ),
              content: isLoading
                  ? const SizedBox(height: 140, width: 360, child: Center(child: CircularProgressIndicator()))
                  : ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
                      child: SingleChildScrollView(child: _buildProfileContent(profile)),
                    ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text(L10n.of(context).gameClose)),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildProfileIconButton({required IconData icon, required Color color, required String tooltip, required VoidCallback onTap}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 28, height: 28,
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

  Widget _buildProfileContent(Map<String, dynamic> data) {
    final profile = data['profile'] as Map<String, dynamic>?;
    if (profile == null) return Text(L10n.of(context).gameProfileNotFound);

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
        _buildMannerLeaveRow(reportCount: reportCount as int, leaveCount: leaveCount as int),
        const SizedBox(height: 10),
        _buildProfileSectionCard(
          title: L10n.of(context).gameTichuSeasonRanked,
          accent: const Color(0xFF7A6A95), background: const Color(0xFFF6F3FA),
          icon: Icons.emoji_events, iconColor: const Color(0xFFFFD54F),
          mainText: '$seasonRating',
          chips: [
            _buildStatChip(L10n.of(context).gameStatRecord, L10n.of(context).gameRecordFormat(seasonGames as int, seasonWins as int, seasonLosses as int)),
            _buildStatChip(L10n.of(context).gameStatWinRate, '$seasonWinRate%'),
          ],
        ),
        const SizedBox(height: 10),
        _buildProfileSectionCard(
          title: L10n.of(context).gameOverallRecord,
          accent: const Color(0xFF5A4038), background: const Color(0xFFF5F5F5),
          icon: Icons.star, iconColor: const Color(0xFFFFB74D),
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

  Widget _buildProfileHeader(int level, int expTotal, String? bannerKey) {
    final expInLevel = expTotal % 100;
    final expPercent = expInLevel / 100;
    final gradient = _bannerGradient(bannerKey);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: gradient,
        color: gradient == null ? Colors.white.withValues(alpha: 0.95) : null,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0D8D4)),
      ),
      child: Row(
        children: [
          Text('Lv.$level', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF5A4038))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(value: expPercent, minHeight: 6, backgroundColor: const Color(0xFFEFE7E3), valueColor: const AlwaysStoppedAnimation(Color(0xFF64B5F6))),
                ),
                const SizedBox(height: 2),
                Text('$expInLevel/100 EXP', style: const TextStyle(fontSize: 9, color: Color(0xFF9A8E8A))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  LinearGradient? _bannerGradient(String? key) {
    switch (key) {
      case 'banner_pastel': return const LinearGradient(colors: [Color(0xFFF6C1C9), Color(0xFFF3E7EA)]);
      case 'banner_blossom': return const LinearGradient(colors: [Color(0xFFF7D6D0), Color(0xFFF3E9E6)]);
      case 'banner_mint': return const LinearGradient(colors: [Color(0xFFCDEBD8), Color(0xFFEFF8F2)]);
      case 'banner_sunset_7d': return const LinearGradient(colors: [Color(0xFFFFC3A0), Color(0xFFFFE5B4)]);
      case 'banner_season_gold': return const LinearGradient(colors: [Color(0xFFFFE082), Color(0xFFFFF3C0)]);
      case 'banner_season_silver': return const LinearGradient(colors: [Color(0xFFCFD8DC), Color(0xFFF1F3F4)]);
      case 'banner_season_bronze': return const LinearGradient(colors: [Color(0xFFD7B59A), Color(0xFFF4E8DC)]);
      default: return null;
    }
  }

  Widget _buildMannerLeaveRow({required int reportCount, required int leaveCount}) {
    final l10n = L10n.of(context);
    String label; Color color; IconData icon;
    if (reportCount <= 1) { label = l10n.gameMannerGood; color = const Color(0xFF66BB6A); icon = Icons.sentiment_satisfied_alt; }
    else if (reportCount <= 3) { label = l10n.gameMannerNormal; color = const Color(0xFF8D9E56); icon = Icons.sentiment_neutral; }
    else if (reportCount <= 6) { label = l10n.gameMannerBad; color = const Color(0xFFFFA726); icon = Icons.sentiment_dissatisfied; }
    else if (reportCount <= 10) { label = l10n.gameMannerVeryBad; color = const Color(0xFFEF5350); icon = Icons.sentiment_very_dissatisfied; }
    else { label = l10n.gameMannerWorst; color = const Color(0xFFB71C1C); icon = Icons.sentiment_very_dissatisfied; }
    final compact = MediaQuery.of(context).size.width < 400;
    final boxDeco = BoxDecoration(color: Colors.white.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE0D8D4)));
    return Row(
      children: [
        Expanded(child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: boxDeco,
          child: compact
              ? Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(icon, color: color, size: 16), const SizedBox(width: 4),
                    Text(l10n.rankingMannerScore, style: const TextStyle(fontSize: 11, color: Color(0xFF8A8A8A))),
                  ]),
                  const SizedBox(height: 2),
                  Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
                ])
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icon, color: color, size: 16), const SizedBox(width: 6),
                  Text(l10n.gameManner(label), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
                ]),
        )),
        const SizedBox(width: 8),
        Expanded(child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: boxDeco,
          child: compact
              ? Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.warning_amber_rounded, color: Color(0xFFE57373), size: 16), const SizedBox(width: 4),
                    Text(l10n.gameDesertionLabel, style: const TextStyle(fontSize: 11, color: Color(0xFF8A8A8A))),
                  ]),
                  const SizedBox(height: 2),
                  Text('$leaveCount', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF9A6A6A))),
                ])
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFE57373), size: 16), const SizedBox(width: 6),
                  Text(l10n.gameDesertions(leaveCount), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF9A6A6A))),
                ]),
        )),
      ],
    );
  }

  Widget _buildProfileSectionCard({required String title, required Color accent, required Color background, required IconData icon, required Color iconColor, required String mainText, required List<Widget> chips}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12), border: Border.all(color: background.withValues(alpha: 0.6))),
      child: Column(children: [
        Row(children: [
          Icon(icon, color: iconColor, size: 16), const SizedBox(width: 6),
          Text(title, style: TextStyle(fontSize: 12, color: accent, fontWeight: FontWeight.bold)),
          const Spacer(),
          if (mainText.isNotEmpty) Text(mainText, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: accent)),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: chips),
      ]),
    );
  }

  Widget _buildStatChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE0D8D4))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF8A8A8A))),
        const SizedBox(width: 4),
        Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF5A4038))),
      ]),
    );
  }

  Widget _buildRecentMatches(List<dynamic> recentMatches, String profileNickname) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE0D8D4))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(L10n.of(context).gameRecentMatchesThree, style: const TextStyle(fontSize: 12, color: Color(0xFF8A8A8A))),
        const SizedBox(height: 8),
        if (recentMatches.isEmpty)
          Text(L10n.of(context).gameNoRecentMatches, style: const TextStyle(fontSize: 12, color: Color(0xFF9A8E8A)))
        else
          Column(children: recentMatches.take(3).map<Widget>((m) => _buildMatchRow(m, profileNickname)).toList()),
      ]),
    );
  }

  Widget _buildMatchRow(dynamic match, String profileNickname) {
    final deserterNickname = match['deserterNickname']?.toString();
    final isDesertionLoss = match['isDesertionLoss'] == true || (deserterNickname != null && deserterNickname.isNotEmpty && deserterNickname == profileNickname);
    final isDraw = match['isDraw'] == true;
    final won = !isDraw && match['won'] == true;
    final teamAScore = match['teamAScore'] ?? 0;
    final teamBScore = match['teamBScore'] ?? 0;
    final teamA = '${match['playerA1'] ?? '-'}·${match['playerA2'] ?? '-'}';
    final teamB = '${match['playerB1'] ?? '-'}·${match['playerB2'] ?? '-'}';
    final date = _formatShortDate(match['createdAt']);
    final isRanked = match['isRanked'] == true;
    final l10n = L10n.of(context);
    final Color badgeColor; final String badgeText;
    if (isDesertionLoss) { badgeColor = const Color(0xFFFFB74D); badgeText = l10n.gameMatchDesertion; }
    else if (isDraw) { badgeColor = const Color(0xFFBDBDBD); badgeText = l10n.gameMatchDraw; }
    else if (won) { badgeColor = const Color(0xFF81C784); badgeText = l10n.gameMatchWin; }
    else { badgeColor = const Color(0xFFE57373); badgeText = l10n.gameMatchLoss; }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Container(width: 24, height: 24, alignment: Alignment.center, decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
          child: Text(badgeText, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(date, style: const TextStyle(fontSize: 11, color: Color(0xFF8A8A8A))),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: isRanked ? const Color(0xFFFFF3E0) : const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(6)),
              child: Text(isRanked ? l10n.gameMatchTypeRanked : l10n.gameMatchTypeNormal,
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isRanked ? const Color(0xFFE65100) : const Color(0xFF9E9E9E))),
            ),
          ]),
          const SizedBox(height: 2),
          Text('$teamA : $teamB', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF5A4038)), overflow: TextOverflow.ellipsis),
        ])),
        Text('$teamAScore : $teamBScore', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF5A4038))),
      ]),
    );
  }

  String _formatShortDate(dynamic value) {
    try {
      final dt = DateTime.parse(value.toString()).toLocal();
      return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
    } catch (_) { return '-'; }
  }

  void _showReportDialog(String nickname, GameService game) {
    final reasonController = TextEditingController();
    final l10n = L10n.of(context);
    final reasons = [l10n.gameReportReasonAbuse, l10n.gameReportReasonSpam, l10n.gameReportReasonNickname, l10n.gameReportReasonGameplay, l10n.gameReportReasonOther];
    String? selectedReason;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (ctx, setState) {
          final media = MediaQuery.of(ctx);
          return AnimatedPadding(
            duration: const Duration(milliseconds: 180), curve: Curves.easeOut,
            padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(children: [
                const Icon(Icons.flag, color: Color(0xFFE57373)), const SizedBox(width: 8),
                Expanded(child: Text(L10n.of(context).gameReportTitle(nickname), style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
              ]),
              content: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 420, maxHeight: media.size.height * 0.55),
                child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: double.infinity, padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFFFFF1F1), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFF0C7C7))),
                    child: Text(L10n.of(context).gameReportWarning, style: const TextStyle(fontSize: 12, color: Color(0xFF9A4A4A), height: 1.4))),
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerLeft, child: Text(L10n.of(context).gameSelectReason, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700))),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 8, children: reasons.map((r) {
                    final sel = selectedReason == r;
                    return InkWell(onTap: () => setState(() => selectedReason = r), borderRadius: BorderRadius.circular(16),
                      child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: sel ? const Color(0xFFDDECF7) : const Color(0xFFF6F2F0), borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: sel ? const Color(0xFF9EC5E6) : const Color(0xFFE2D8D4))),
                        child: Text(r, style: TextStyle(fontSize: 12, color: sel ? const Color(0xFF3E6D8E) : const Color(0xFF6A5A52), fontWeight: sel ? FontWeight.bold : FontWeight.normal))));
                  }).toList()),
                  const SizedBox(height: 12),
                  TextField(controller: reasonController, maxLines: 3, decoration: InputDecoration(
                    hintText: L10n.of(context).gameReportDetailHint, filled: true, fillColor: const Color(0xFFF7F2F0),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0D6D1))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0D6D1))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFB9A8A1))))),
                ])),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text(L10n.of(context).gameCancel)),
                ElevatedButton(
                  onPressed: selectedReason == null ? null : () {
                    final detail = reasonController.text.trim();
                    final reason = detail.isEmpty ? selectedReason! : '${selectedReason!} / $detail';
                    Navigator.pop(ctx);
                    game.reportResultSuccess = null; game.reportResultMessage = null;
                    game.reportUserAction(nickname, reason);
                    late void Function() listener; Timer? cleanupTimer;
                    listener = () {
                      if (game.reportResultMessage != null) {
                        game.removeListener(listener); cleanupTimer?.cancel();
                        if (mounted) {
                          ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(
                            content: Text(game.reportResultMessage!),
                            backgroundColor: game.reportResultSuccess == true ? null : const Color(0xFFE57373)));
                        }
                        game.reportResultSuccess = null; game.reportResultMessage = null;
                      }
                    };
                    game.addListener(listener);
                    cleanupTimer = Timer(const Duration(seconds: 10), () => game.removeListener(listener));
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE57373), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: Text(L10n.of(context).gameReportSubmit),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
