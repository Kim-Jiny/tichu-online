import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/game_service.dart';
import '../services/network_service.dart';
import '../models/ll_game_state.dart';
import '../widgets/love_letter_card.dart';
import '../widgets/connection_overlay.dart';
import '../l10n/app_localizations.dart';

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
          if (gs.isSpectator && gs.spectatorGameState != null) {
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

        // Clear stale selections when effect state changes
        if (llState.phase != 'effect_resolve' || llState.pendingEffect == null) {
          _selectedTarget = null;
          _selectedGuess = null;
          _selectedCard = null;
        }

        return Scaffold(
          backgroundColor: const Color(0xFF1A0A2E),
          body: SafeArea(
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
    return Scaffold(
      backgroundColor: const Color(0xFF1A0A2E),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.visibility, color: Colors.white54, size: 48),
              const SizedBox(height: 16),
              Text(
                L10n.of(context).spectatorWaiting,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => gs.leaveRoom(),
                child: Text(L10n.of(context).skGameLeaveButton),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ====================== TOP BAR ======================

  Widget _buildTopBar(BuildContext context, GameService gs, LLGameStateData state) {
    final l10n = L10n.of(context);
    final unread = gs.chatMessages.length - _readChatCount;

    return Container(
      color: const Color(0xFF2D1B4E),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          // Round info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${l10n.llRound} ${state.round}',
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          // Draw pile count
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.style, color: Colors.white70, size: 14),
                const SizedBox(width: 4),
                Text(
                  '${state.drawPileCount}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Timer
          if (_remainingSeconds > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _remainingSeconds <= 5 ? Colors.red.shade900 : Colors.white10,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$_remainingSeconds',
                style: TextStyle(
                  color: _remainingSeconds <= 5 ? Colors.redAccent : Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          const SizedBox(width: 4),
          // Chat button
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.chat_bubble_outline, color: Colors.white70, size: 20),
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
            icon: const Icon(Icons.exit_to_app, color: Colors.white70, size: 20),
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
          _buildPlayersArea(context, gs, state),
          const SizedBox(height: 8),
          if (state.phase == 'effect_resolve' && state.pendingEffect != null)
            _buildEffectResolve(context, gs, state),
          if (state.faceUpCards.isNotEmpty) _buildFaceUpCards(state),
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
            ? Colors.amber.withValues(alpha: 0.15)
            : isEffectTarget
                ? Colors.red.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: isCurrent
            ? Border.all(color: Colors.amber.withValues(alpha: 0.4))
            : isEffectTarget
                ? Border.all(color: Colors.red.withValues(alpha: 0.4))
                : null,
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
                        color: player.eliminated ? Colors.white38 : Colors.white,
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
                        color: i < player.tokens ? const Color(0xFFE91E63) : Colors.white24,
                        size: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Card count
          if (!player.eliminated)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.style, color: Colors.white54, size: 12),
                  const SizedBox(width: 2),
                  Text('${player.cardCount}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                ],
              ),
            ),
          const SizedBox(width: 8),
          // Discard pile
          if (player.discardPile.isNotEmpty)
            SizedBox(
              height: 40,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: player.discardPile.reversed.take(4).map((cardId) => Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: LoveLetterCard(
                    cardId: cardId,
                    width: 28,
                    height: 40,
                    compact: true,
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

    // Waiting for action
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            _getEffectDescription(effect.type, actorName, l10n),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber),
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
        color: const Color(0xFF2D1B4E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Text(
            l10n.llGuardSelectTarget,
            style: const TextStyle(color: Colors.amber, fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          // Target buttons
          Wrap(
            spacing: 8,
            children: effect.validTargets.map((targetId) {
              final player = state.players.firstWhere(
                (p) => p.id == targetId,
                orElse: () => LLPlayer(id: targetId, name: targetId),
              );
              final isSelected = _selectedTarget == targetId;
              return ChoiceChip(
                label: Text(player.name),
                selected: isSelected,
                onSelected: (_) => setState(() => _selectedTarget = targetId),
                selectedColor: Colors.amber,
                backgroundColor: Colors.white12,
                labelStyle: TextStyle(color: isSelected ? Colors.black : Colors.white70),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.llGuardGuessCard,
            style: const TextStyle(color: Colors.amber, fontSize: 13),
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
                    color: isSelected ? color : Colors.white10,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: isSelected ? color : Colors.white24),
                  ),
                  child: Text(
                    '$value $name',
                    style: TextStyle(
                      color: isSelected ? (type == 'princess' ? Colors.black87 : Colors.white) : Colors.white70,
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

  Widget _buildTargetSelection(
    BuildContext context, GameService gs, LLGameStateData state, LLPendingEffect effect,
  ) {
    final l10n = L10n.of(context);
    final effectName = _getCardTypeName(effect.type, l10n);

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2D1B4E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Text(
            '${l10n.llSelectTargetFor} $effectName',
            style: const TextStyle(color: Colors.amber, fontSize: 14, fontWeight: FontWeight.bold),
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
                  backgroundColor: Colors.amber.withValues(alpha: 0.2),
                  foregroundColor: Colors.amber,
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
                child: Text('vs', style: TextStyle(color: Colors.white54, fontSize: 12)),
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
        color: Colors.deepPurple.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Text(
            resultText,
            style: const TextStyle(color: Colors.white, fontSize: 14),
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
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
              child: Text(l10n.llOk),
            ),
          ] else ...[
            const SizedBox(height: 8),
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54)),
          ],
        ],
      ),
    );
  }

  Widget _buildFaceUpCards(LLGameStateData state) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            L10n.of(context).llSetAsideFaceUp,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: state.faceUpCards.map((cardId) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: LoveLetterCard(cardId: cardId, width: 40, height: 56, compact: true, isInteractive: false),
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
          color: const Color(0xFF2D1B4E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.llRoundEnd,
              style: const TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (lastRound != null) ...[
              const SizedBox(height: 12),
              Text(
                '${l10n.llRoundWinner}: ${lastRound.winnerName ?? "?"}',
                style: const TextStyle(color: Colors.white, fontSize: 16),
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
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
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
                    child: Text(p.name, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ),
                  ...List.generate(state.targetTokens, (i) => Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: Icon(
                      Icons.favorite,
                      color: i < p.tokens ? const Color(0xFFE91E63) : Colors.white24,
                      size: 14,
                    ),
                  )),
                ],
              ),
            )),
            const SizedBox(height: 8),
            Text(
              l10n.llNextRoundAuto,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
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
          color: const Color(0xFF2D1B4E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.llGameEnd,
              style: const TextStyle(color: Colors.amber, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (winner != null)
              Text(
                '${winner.name} ${l10n.llWins}!',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            const SizedBox(height: 16),
            ...sorted.asMap().entries.map((entry) {
              final i = entry.key;
              final p = entry.value;
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 2),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: i == 0 ? Colors.amber.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '#${i + 1} ',
                      style: TextStyle(
                        color: i == 0 ? Colors.amber : Colors.white54,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(
                      width: 80,
                      child: Text(p.name, style: const TextStyle(color: Colors.white, fontSize: 14)),
                    ),
                    ...List.generate(state.targetTokens, (j) => Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Icon(
                        Icons.favorite,
                        color: j < p.tokens ? const Color(0xFFE91E63) : Colors.white24,
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
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
          ],
        ),
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

    return Container(
      color: const Color(0xFF2D1B4E),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        children: [
          // Self info bar
          Row(
            children: [
              Text(
                selfPlayer.name,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
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
              const Spacer(),
              // Tokens
              ...List.generate(state.targetTokens, (i) => Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Icon(
                  Icons.favorite,
                  color: i < selfPlayer.tokens ? const Color(0xFFE91E63) : Colors.white24,
                  size: 14,
                ),
              )),
            ],
          ),
          const SizedBox(height: 8),
          // My discard pile (small)
          if (selfPlayer.discardPile.isNotEmpty) ...[
            SizedBox(
              height: 36,
              child: Row(
                children: [
                  Text(L10n.of(context).llPlayed, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  ...selfPlayer.discardPile.map((cardId) => Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: LoveLetterCard(cardId: cardId, width: 24, height: 34, compact: true, isInteractive: false),
                  )),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],
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
                  disabledBackgroundColor: Colors.white12,
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
    final messages = gs.chatMessages;
    if (messages.length != _lastChatMessageCount) {
      _lastChatMessageCount = messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_chatScrollController.hasClients) {
          _chatScrollController.jumpTo(_chatScrollController.position.maxScrollExtent);
        }
      });
    }

    return Positioned(
      right: 8,
      top: 50,
      bottom: 120,
      width: 240,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xF0201038),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _chatScrollController,
                padding: const EdgeInsets.all(8),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final msg = messages[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '${msg['sender']}: ',
                            style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          TextSpan(
                            text: msg['message'],
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.all(6),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _chatController,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: InputDecoration(
                        hintText: L10n.of(context).skGameMessageHint,
                        hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.white24),
                        ),
                      ),
                      onSubmitted: (_) => _sendChat(gs),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.send, color: Colors.amber, size: 18),
                    onPressed: () => _sendChat(gs),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _sendChat(GameService gs) {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    gs.sendChatMessage(text);
    _chatController.clear();
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
}
