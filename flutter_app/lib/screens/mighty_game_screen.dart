import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/game_service.dart';
import '../services/network_service.dart';
import '../models/mighty_game_state.dart';
import '../models/player.dart';
import '../widgets/playing_card.dart';
import '../widgets/connection_overlay.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n_helpers.dart';

class MightyGameScreen extends StatefulWidget {
  const MightyGameScreen({super.key});

  @override
  State<MightyGameScreen> createState() => _MightyGameScreenState();
}

class _MightyGameScreenState extends State<MightyGameScreen> {
  // Bidding state
  int _bidPoints = 13;
  String _bidSuit = 'spade';

  // Kitty exchange state
  final Set<String> _discardSelection = {};
  String _friendCardSelection = '';
  String _friendMode = ''; // 'no_friend', 'first_trick', 'card'
  String _friendSuit = 'spade';
  String _friendRank = 'A';
  String? _selectedTrumpSuit; // null = no change
  String? _lastKnownTrumpSuit; // tracks the last trumpSuit we rendered for; used to resync _selectedTrumpSuit when the server confirms a change

  // Play state
  String? _selectedCard;
  String? _jokerSuitChoice;
  bool _jokerCallChoice = true; // default Yes for joker call

  // Timer
  Timer? _countdownTimer;
  int _remainingSeconds = 0;

  // Game end
  Timer? _gameEndCountdownTimer;
  int _gameEndCountdown = 3;
  bool _gameEndCountdownActive = false;

  // Phase tracking for clearing stale state
  String _lastPhase = '';

  // Track whether the local player was excluded last frame so we can clear
  // pseudo-spectator state (approved peeks, pending requests, viewing target)
  // when they rejoin the table next round.
  bool _wasSelfExcluded = false;

  // Track the number of completed tricks so we can clear a pre-selection when
  // a new trick starts (lead suit changes).
  int _lastTrickCount = -1;

  // Deal-miss reveal: user can dismiss; keyed by "round-playerId" so a new event re-shows
  String? _dismissedDealMissKey;

  // Kill reveal: same pattern — keyed by "round-targetCardId" so it only shows once
  String? _dismissedKillKey;
  String? _selectedKillCard;
  // Kill target picker: currently browsed suit panel (null = joker tab).
  String _killSuitTab = 'spade';

  // Spectator card view
  Timer? _cardViewRequestTimer;
  String? _viewingPlayerId;

  // Chat
  bool _chatOpen = false;
  int _readChatCount = 0;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  int _lastChatMessageCount = 0;

  // Network
  bool _wasDisconnected = false;
  GameService? _gameService;
  NetworkService? _networkService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gameService = context.read<GameService>();
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
    _networkService?.removeListener(_onNetworkChanged);
    _chatController.dispose();
    _chatScrollController.dispose();
    _countdownTimer?.cancel();
    _gameEndCountdownTimer?.cancel();
    _cardViewRequestTimer?.cancel();
    super.dispose();
  }

  void _updateCountdown() {
    if (!mounted) return;
    final state = _gameService?.mightyGameState;
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
      _gameEndCountdownTimer =
          Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        if (_gameEndCountdown <= 1) {
          timer.cancel();
          _gameEndCountdownActive = false;
          setState(() => _gameEndCountdown = 0);
          _gameService?.returnToRoom();
        } else {
          setState(() => _gameEndCountdown--);
        }
      });
    } else {
      _gameEndCountdownActive = false;
      _gameEndCountdownTimer?.cancel();
    }
  }

  String _displayCardId(String id) {
    if (id == 'mighty_joker') return 'joker';
    return id.replaceFirst('mighty_', '');
  }

  @override
  Widget build(BuildContext context) {
    final themeColors = context.watch<GameService>().themeGradient;

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
              child: Consumer<GameService>(
                builder: (context, game, _) {
                  final state = game.mightyGameState;
                  if (state == null) {
                    if (game.isSpectator && game.hasRoom && !game.hasActiveGame) {
                      return _buildSpectatorWaiting(game);
                    }
                    return const Center(child: CircularProgressIndicator());
                  }
                  // Clear stale pseudo-spectator state when the local player
                  // stops being killed (i.e. next round started and they
                  // rejoined the table). Server-side permissions are already
                  // wiped by pruneCardViewPermissions.
                  {
                    final myId = game.playerId;
                    final isSelfExcluded = myId.isNotEmpty && state.excludedPlayers.contains(myId);
                    if (_wasSelfExcluded && !isSelfExcluded) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        setState(() {
                          game.approvedCardViews.clear();
                          game.pendingCardViewRequests.clear();
                          _viewingPlayerId = null;
                          _cardViewRequestTimer?.cancel();
                        });
                      });
                    }
                    if (_wasSelfExcluded != isSelfExcluded) {
                      _wasSelfExcluded = isSelfExcluded;
                    }
                  }
                  // Clear any pre-selection at trick boundaries: the lead suit
                  // changes every trick, so whatever the user queued up before
                  // may no longer be legal on the new trick.
                  if (_lastTrickCount != state.tricks.length) {
                    if (_lastTrickCount != -1 && _selectedCard != null) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        setState(() => _selectedCard = null);
                      });
                    }
                    _lastTrickCount = state.tricks.length;
                  }
                  // Clear stale state on phase change
                  if (_lastPhase != state.phase) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      _syncGameEndCountdown(state.phase);
                      setState(() {
                        _lastPhase = state.phase;
                        _selectedCard = null;
                        _jokerSuitChoice = null;
                        _jokerCallChoice = true;
                        if (state.phase == 'bidding') {
                          _bidPoints = state.mode == '6p' ? 14 : 13;
                          _bidSuit = 'spade';
                          _discardSelection.clear();
                          _friendCardSelection = '';
                          _friendMode = '';
                          _friendSuit = 'spade';
                          _friendRank = 'A';
                          _selectedTrumpSuit = null;
                          _lastKnownTrumpSuit = null;
                        }
                        if (state.phase == 'kitty_exchange') {
                          _discardSelection.clear();
                          _selectedTrumpSuit = null;
                          _lastKnownTrumpSuit = null;
                          // Smart default: mighty → trump A → joker → spade A
                          final myCards = state.myCards;
                          final mightyCard = state.mightyCard;
                          final trump = state.trumpSuit ?? 'spade';
                          final trumpAce = 'mighty_${trump}_A';
                          if (mightyCard != null && !myCards.contains(mightyCard)) {
                            final parts = mightyCard.replaceFirst('mighty_', '').split('_');
                            _friendMode = 'card';
                            _friendSuit = parts.isNotEmpty ? parts[0] : 'spade';
                            _friendRank = parts.length > 1 ? parts[1] : 'A';
                            _friendCardSelection = 'mighty_${_friendSuit}_$_friendRank';
                          } else if (!myCards.contains(trumpAce)) {
                            _friendMode = 'card';
                            _friendSuit = trump;
                            _friendRank = 'A';
                            _friendCardSelection = 'mighty_${_friendSuit}_$_friendRank';
                          } else if (!myCards.contains('mighty_joker')) {
                            _friendMode = 'joker';
                            _friendCardSelection = 'mighty_joker';
                          } else {
                            _friendMode = 'card';
                            _friendSuit = 'spade';
                            _friendRank = 'A';
                            _friendCardSelection = 'mighty_${_friendSuit}_$_friendRank';
                          }
                        }
                      });
                    });
                  }

                  // Clear selected card if it's no longer in hand
                  if (_selectedCard != null && !state.myCards.contains(_selectedCard)) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _selectedCard = null);
                    });
                  }

                  return Stack(
                    children: [
                      Column(
                        children: [
                          _buildTopBar(state, game),
                          _buildScoreboard(state, game),
                          if (state.phase == 'playing' || state.phase == 'trick_end' || state.phase == 'round_end')
                            _buildOppositionPointBar(state),
                          if (state.phase == 'playing' || state.phase == 'trick_end')
                            _buildPlayedCardsRow(state),
                          if (state.phase == 'bidding') ...[
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: SingleChildScrollView(child: _buildBiddingUI(state, game)),
                              ),
                            ),
                            _buildHandArea(state, game),
                          ],
                          if (state.phase == 'kill_select') ...[
                            Expanded(child: _buildKillSelectUI(state, game)),
                            _buildHandArea(state, game),
                          ],
                          if (state.phase == 'kitty_exchange') ...[
                            Expanded(child: _buildKittyUI(game, state)),
                            if (!state.isMyTurn)
                              _buildHandArea(state, game),
                          ],
                          if (state.phase == 'playing')
                            Expanded(
                              child: Column(
                                children: [
                                  const Spacer(),
                                  _buildTrickArea(state, game),
                                  const Spacer(),
                                ],
                              ),
                            ),
                          if (state.phase == 'playing')
                            _buildHandArea(state, game),
                          if (state.phase == 'trick_end')
                            Expanded(child: _buildTrickEndArea(state)),
                          if (state.phase == 'trick_end')
                            _buildHandArea(state, game),
                          if (state.phase == 'round_end')
                            Expanded(child: SingleChildScrollView(child: _buildRoundEndUI(state))),
                          if (state.phase == 'game_end')
                            Expanded(child: SingleChildScrollView(child: _buildGameEndUI(state, game))),
                        ],
                      ),
                      if (_chatOpen) _buildChatPanel(game),
                      if (game.hasIncomingCardViewRequests)
                        _buildCardViewRequestPopup(game),
                      if (game.timeoutPlayerName != null)
                        _buildTimeoutBanner(game.timeoutPlayerName!),
                      if (game.errorMessage != null)
                        _buildErrorBanner(game.errorMessage!),
                      if (state.lastDealMissEvent != null &&
                          _dismissedDealMissKey !=
                              '${state.lastDealMissEvent!.round}-${state.lastDealMissEvent!.playerId}')
                        _buildDealMissRevealOverlay(state.lastDealMissEvent!),
                      if (state.lastKillEvent != null &&
                          _dismissedKillKey !=
                              '${state.round}-${state.lastKillEvent!.targetCardId}')
                        _buildKillRevealOverlay(state, state.lastKillEvent!),
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

  // ── Spectator Waiting Room ──
  Widget _buildSpectatorWaiting(GameService game) {
    final slots = game.roomPlayers;
    final l10n = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      child: Column(
        children: [
          // Header
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
                  onPressed: () => game.leaveRoom(),
                  icon: const Icon(Icons.arrow_back, color: Color(0xFF5A4038)),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    l10n.spectatorWatching,
                    style: const TextStyle(
                      color: Color(0xFF2E7D32),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    game.currentRoomName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF5A4038),
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _buildTopActionButton(
                  icon: Icons.chat_bubble_outline,
                  active: _chatOpen,
                  badgeCount: _chatOpen ? 0 : (game.chatMessages.length - _readChatCount).clamp(0, 99),
                  onTap: () {
                    setState(() {
                      _chatOpen = !_chatOpen;
                      if (_chatOpen) _readChatCount = game.chatMessages.length;
                    });
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Slot grid
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
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth > 620;
                          return GridView.builder(
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: wide ? 2 : 1,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 12,
                              childAspectRatio: wide ? 2.4 : 4.0,
                            ),
                            itemCount: slots.length,
                            itemBuilder: (context, index) {
                              return _buildWaitingSlot(game, slots[index], index);
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      l10n.spectatorWaitingForGame,
                      style: const TextStyle(color: Color(0xFF8A8A8A), fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_chatOpen) ...[
            const SizedBox(height: 8),
            SizedBox(height: 200, child: _buildChatPanel(game)),
          ],
        ],
      ),
    );
  }

  Widget _buildWaitingSlot(GameService game, Player? player, int slotIndex) {
    final isBlocked = game.roomBlockedSlots.contains(slotIndex);
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
          ],
        ),
      );
    }
    if (player == null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => game.switchToPlayer(slotIndex),
          borderRadius: BorderRadius.circular(16),
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
                  style: const TextStyle(color: Color(0xFF9AA7B0), fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final isReady = player.isReady;
    return GestureDetector(
      onTap: () => _showPlayerProfileDialog(player.name, game, isBot: player.id.startsWith('bot_')),
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
                color: player.isHost ? const Color(0xFFFFF2B3) : const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                player.isHost ? Icons.star : Icons.person,
                color: player.isHost ? const Color(0xFFE6A800) : const Color(0xFF2E7D32),
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                player.name,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF3E312A)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isReady)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('READY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF4CAF50))),
              ),
          ],
        ),
      ),
    );
  }

  // ── Top Bar (SK-style) ──
  Widget _buildTopBar(MightyGameStateData state, GameService game) {
    final trumpLabel = state.trumpSuit != null
        ? (state.trumpSuit == 'no_trump' ? 'NT' : _suitSymbol(state.trumpSuit!))
        : '';
    final hasCurrentBidder = state.currentBid['bidder'] != null;
    final showContractInfo = (state.declarer != null &&
            state.phase != 'bidding' && state.phase != 'dealing') ||
        (state.phase == 'bidding' && (hasCurrentBidder || state.dealMissPool > 0));

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFCCCCCC)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.style, size: 14, color: Color(0xFF5A4038)),
                    const SizedBox(width: 5),
                    Text(
                      state.phase == 'round_end'
                          ? 'R${state.round}'
                          : L10n.of(context).mtRoundPhase(state.round.toString(), _phaseLabel(state.phase)),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF5A4038),
                      ),
                    ),
                    if (trumpLabel.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF8E1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          trumpLabel,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: state.trumpSuit == null || state.trumpSuit == 'no_trump'
                                ? const Color(0xFF7B1FA2)
                                : (PlayingCard.suitColors[state.trumpSuit!] ?? const Color(0xFF5A4038)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Spacer(),
              if (state.scoreHistory.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _buildTopActionButton(
                    icon: Icons.history,
                    active: false,
                    onTap: () => _showScoreHistoryDialog(state, game),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _buildTopActionButton(
                  icon: Icons.people_alt,
                  active: false,
                  badgeCount: game.spectators.length,
                  onTap: () => _showSpectatorListDialog(game),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _buildTopActionButton(
                  icon: Icons.chat_bubble_outline,
                  active: _chatOpen,
                  badgeCount: _chatOpen ? 0 : (game.chatMessages.length - _readChatCount).clamp(0, 99),
                  onTap: () {
                    setState(() {
                      _chatOpen = !_chatOpen;
                      if (_chatOpen) {
                        _readChatCount = game.chatMessages.length;
                        _scrollChatToBottom();
                      }
                    });
                  },
                ),
              ),
              _buildTopActionButton(
                icon: Icons.exit_to_app,
                active: false,
                iconColor: const Color(0xFFE53935),
                onTap: () => _showExitConfirmDialog(game),
              ),
            ],
          ),
        ),
        if (showContractInfo)
          _buildContractInfoBar(state, game),
      ],
    );
  }

  Widget _buildContractInfoBar(MightyGameStateData state, GameService game) {
    final isBidding = state.phase == 'bidding';
    final leaderId = isBidding ? state.currentBid['bidder'] as String? : state.declarer;
    final leaderName = leaderId == null
        ? ''
        : (state.players.where((p) => p.id == leaderId).map((p) => p.name).firstOrNull ?? '');
    final bidPoints = state.currentBid['points'];
    final bidSuit = state.currentBid['suit'];
    final suitLabel = bidSuit != null ? _suitSymbol(bidSuit.toString()) : '';
    final hasBid = bidPoints != null && (bidPoints is num) && bidPoints > 0;

    String friendLabel = '';
    if (!isBidding) {
      if (state.friendCard != null) {
        if (state.friendRevealed && state.partner != null) {
          final partnerName = state.players
              .where((p) => p.id == state.partner)
              .map((p) => p.name)
              .firstOrNull ?? '';
          friendLabel = '${_friendCardLabel(state.friendCard!)} \u2192 $partnerName';
        } else {
          friendLabel = _friendCardLabel(state.friendCard!);
        }
      } else {
        friendLabel = L10n.of(context).mtSolo;
      }
    }

    final showTrumpCounter = state.remainingTrumps != null && game.hasMightyTrumpCounter;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Row(
        children: [
          if (showTrumpCounter) ...[
            _buildTrumpCounterLabel(state),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (leaderName.isNotEmpty)
                  Text(
                    leaderName,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF5A4038)),
                  ),
                if (leaderName.isNotEmpty && hasBid) const SizedBox(width: 6),
                if (hasBid)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1565C0),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$suitLabel $bidPoints',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                if (!isBidding && !state.friendRevealed) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      friendLabel,
                      style: const TextStyle(fontSize: 10, color: Color(0xFF8A7A72)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (state.dealMissPool > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFFFAB91)),
              ),
              child: Text(
                L10n.of(context).mtDealMissPool(state.dealMissPool.toString()),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  color: Color(0xFFD84315),
                ),
              ),
            ),
          ] else if (showTrumpCounter)
            const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildTrumpCounterLabel(MightyGameStateData state) {
    final trumps = state.remainingTrumps!;
    final count = (trumps['count'] as num?)?.toInt() ?? 0;
    final suit = trumps['suit']?.toString() ?? '';
    final isZero = count == 0;
    return Text(
      '${_suitSymbol(suit)}$count',
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: isZero ? const Color(0xFFE53935) : const Color(0xFF1565C0),
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
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: active
                  ? const Color(0xFF5A4038).withValues(alpha: 0.92)
                  : Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 6,
                ),
              ],
            ),
            child: Icon(
              icon,
              size: 19,
              color: active
                  ? Colors.white
                  : (iconColor ?? const Color(0xFF5A4038)),
            ),
          ),
          if (badgeCount > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white, width: 1.2),
                ),
                child: Text(
                  badgeCount > 99 ? '99+' : '$badgeCount',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
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

  void _sendChatMessage(GameService game) {
    final message = _chatController.text.trim();
    if (message.isEmpty) return;
    game.sendChatMessage(message);
    _chatController.clear();
    _scrollChatToBottom();
  }

  Widget _buildChatPanel(GameService game) {
    if (game.chatMessages.length != _lastChatMessageCount) {
      _lastChatMessageCount = game.chatMessages.length;
      _readChatCount = game.chatMessages.length;
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF5A4038),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    L10n.of(context).mtChat,
                    style: TextStyle(
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
                  final isBlocked = sender.isNotEmpty && game.isBlocked(sender);
                  if (isBlocked) return const SizedBox.shrink();
                  return _buildChatBubble(sender, message, isMe);
                },
              ),
            ),
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
                        hintText: L10n.of(context).mtTypeMessage,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      style: const TextStyle(fontSize: 14),
                      onSubmitted: (_) => _sendChatMessage(game),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _sendChatMessage(game),
                    icon: const Icon(Icons.send, color: Color(0xFF8D6E63)),
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
          if (!isMe && sender.isNotEmpty) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: const Color(0xFFE0E0E0),
              child: Text(
                sender[0],
                style: const TextStyle(fontSize: 12, color: Color(0xFF5A4038)),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe && sender.isNotEmpty)
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
                    color: isMe ? const Color(0xFF5A4038) : const Color(0xFFF0F0F0),
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
    );
  }

  void _showExitConfirmDialog(GameService game) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.of(context).mtLeaveGame),
        content: Text(L10n.of(context).mtLeaveConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(L10n.of(context).mtCancel)),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              game.leaveRoom();
            },
            child: Text(L10n.of(context).mtLeave, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // Build the compact pass / bid chip shown on a scoreboard tile during the
  // bidding phase. p.bid is either the string 'pass' or a Map {points, suit}.
  Widget? _bidScoreboardBadge(dynamic bid) {
    if (bid == 'pass') {
      return const Text(
        'PASS',
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF9E9E9E), letterSpacing: 0.5),
      );
    }
    if (bid is Map) {
      final points = bid['points'];
      final suit = bid['suit']?.toString() ?? '';
      final sym = _suitSymbol(suit);
      return Text(
        '$sym$points',
        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF1565C0)),
      );
    }
    return null;
  }

  // ── Scoreboard (SK-style) ──
  Widget _buildScoreboard(MightyGameStateData state, GameService game) {
    final isSpectator = game.isSpectator;
    final myId = game.playerId;
    final isSelfExcluded = myId.isNotEmpty && state.excludedPlayers.contains(myId);
    // Killed-mighty player acts as pseudo-spectator for the rest of the round.
    final canRequestCardView = isSpectator || isSelfExcluded;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      margin: EdgeInsets.zero,
      child: Row(
        children: state.players.map((p) {
          final isCurrentTurn = p.id == state.currentPlayer;
          final isSelf = p.position == 'self';
          final isDeclarer = p.id == state.declarer;
          final isPartner = state.friendRevealed && p.id == state.partner;
          final isExcluded = state.excludedPlayers.contains(p.id);
          // Card-view state: real spectator OR killed-mighty player peeking.
          final isPending = canRequestCardView && game.pendingCardViewRequests.contains(p.id);
          final isApproved = canRequestCardView && game.approvedCardViews.contains(p.id) && p.canViewCards;

          // Opposition = not declarer and not revealed partner → can show pointCards
          final isGovt = p.id == state.declarer || (state.friendRevealed && p.id == state.partner);
          final hasPointCards = !isGovt && p.pointCards.isNotEmpty;

          return Expanded(
            child: Opacity(
              opacity: isExcluded ? 0.45 : 1.0,
              child: GestureDetector(
              onTap: () {
                // Self-tile always shows own profile (no request flow).
                if (isSelf) {
                  _showPlayerProfileDialog(p.name, game, isBot: p.id.startsWith('bot_'));
                  return;
                }
                if (canRequestCardView) {
                  if (isApproved) {
                    setState(() => _viewingPlayerId = p.id);
                  } else if (!isPending) {
                    _cardViewRequestTimer?.cancel();
                    game.requestCardView(p.id);
                    setState(() => _viewingPlayerId = p.id);
                    _cardViewRequestTimer = Timer(const Duration(seconds: 5), () {
                      if (!mounted) return;
                      game.expireCardViewRequest(p.id);
                    });
                  }
                } else if (hasPointCards && (state.phase == 'playing' || state.phase == 'trick_end' || state.phase == 'round_end')) {
                  _showPointCardsDialog(p);
                } else {
                  _showPlayerProfileDialog(p.name, game, isBot: p.id.startsWith('bot_'));
                }
              },
              child: SizedBox(
                width: double.infinity,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelf
                            ? Colors.white.withValues(alpha: 0.95)
                            : isCurrentTurn
                                ? const Color(0xFFFFF2B3)
                                : Colors.white.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(12),
                        border: isCurrentTurn
                            ? Border.all(color: const Color(0xFFE6C86A), width: 2)
                            : isDeclarer
                                ? Border.all(color: const Color(0xFFFF8A00), width: 2)
                                : isPartner
                                    ? Border.all(color: const Color(0xFF4CAF50), width: 2)
                                    : Border.all(color: const Color(0xFFE0D8D4)),
                        boxShadow: isSelf
                            ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4)]
                            : null,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Role badge — during bidding show the pass/bid
                          // chip, after bidding show the declarer/friend role.
                          SizedBox(
                            height: 14,
                            child: isExcluded
                                ? Text(L10n.of(context).mtKillExcluded, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFFD84315)))
                                : isDeclarer
                                    ? Text(L10n.of(context).mtDeclarer, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFFFF8A00)))
                                    : isPartner
                                        ? Text(L10n.of(context).mtFriend, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF4CAF50)))
                                        : (state.phase == 'bidding' && p.bid != null)
                                            ? _bidScoreboardBadge(p.bid)
                                            : null,
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (isCurrentTurn)
                                Container(
                                  width: 6, height: 6,
                                  margin: const EdgeInsets.only(right: 3),
                                  decoration: const BoxDecoration(color: Color(0xFFE6A800), shape: BoxShape.circle),
                                ),
                              Flexible(
                                child: Text(
                                  p.name,
                                  style: TextStyle(
                                    color: const Color(0xFF5A4038),
                                    fontSize: 10,
                                    fontWeight: isSelf ? FontWeight.w800 : FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${state.scores[p.id] ?? 0}',
                            style: const TextStyle(
                              color: Color(0xFF5A4038),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(
                            height: 14,
                            child: p.timeoutCount > 0
                                ? Text(
                                    '⏱ ${p.timeoutCount}/3',
                                    style: const TextStyle(
                                      color: Color(0xFFE65100),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(height: 2),
                        ],
                      ),
                    ),
                    // Card view badges for spectators AND killed-mighty peekers
                    if (canRequestCardView && !isSelf && isPending)
                      Positioned(
                        right: 2, top: -4,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFE0D8D4)),
                          ),
                          child: const Icon(Icons.schedule, size: 12, color: Color(0xFFFFB74D)),
                        ),
                      )
                    else if (canRequestCardView && !isSelf && isApproved)
                      Positioned(
                        right: 2, top: -4,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF64B5F6)),
                          ),
                          child: const Icon(Icons.visibility, size: 12, color: Color(0xFF64B5F6)),
                        ),
                      )
                    else if (canRequestCardView && !isSelf)
                      Positioned(
                        right: 2, top: -4,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFE0D8D4)),
                          ),
                          child: Icon(Icons.visibility_outlined, size: 12, color: const Color(0xFF8A7A72).withValues(alpha: 0.6)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPlayedCardsRow(MightyGameStateData state) {
    final isEnd = state.phase == 'trick_end';
    final tricks = isEnd ? state.lastTrickCards : state.currentTrick;
    final winnerId = isEnd ? state.lastTrickWinner : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      margin: const EdgeInsets.only(top: 8),
      height: 60,
      child: Row(
        children: state.players.map((p) {
          final trickPlay = tricks.cast<MightyTrickPlay?>().firstWhere(
              (play) => play?.playerId == p.id, orElse: () => null);
          final isWinner = winnerId != null && p.id == winnerId;

          return Expanded(
            child: Center(
              child: trickPlay != null
                  ? Container(
                      decoration: isWinner
                          ? BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: [BoxShadow(color: const Color(0xFF4CAF50).withValues(alpha: 0.4), blurRadius: 8)],
                            )
                          : null,
                      child: PlayingCard(
                        cardId: _displayCardId(trickPlay.cardId),
                        width: 38,
                        height: 53,
                        isInteractive: false,
                        borderColor: (state.trumpSuit != null && state.trumpSuit != 'no_trump' && _getCardSuit(trickPlay.cardId) == state.trumpSuit)
                            ? PlayingCard.suitColors[_getCardSuit(trickPlay.cardId)]
                            : null,
                        badgeIcon: trickPlay.cardId == state.mightyCard ? Icons.star
                            : (state.jokerCallActive && trickPlay.cardId == state.jokerCallCard) ? Icons.gps_fixed
                            : null,
                        badgeColor: trickPlay.cardId == state.mightyCard ? const Color(0xFFFFB300)
                            : (state.jokerCallActive && trickPlay.cardId == state.jokerCallCard) ? const Color(0xFFE53935)
                            : null,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildOppositionPointBar(MightyGameStateData state) {
    // Collect all opposition point cards
    final oppCards = <String>[];
    int oppPoints = 0;
    for (final p in state.players) {
      final isGovt = p.id == state.declarer || (state.friendRevealed && p.id == state.partner);
      if (!isGovt) {
        oppCards.addAll(p.pointCards);
        oppPoints += p.pointCount;
      }
    }
    final bidPoints = (state.currentBid['points'] is num)
        ? (state.currentBid['points'] as num).toInt()
        : 13;
    // Opposition needs (20 - bidPoints + 1) to defeat declarer
    final oppTarget = 20 - bidPoints + 1;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0D8D4)),
      ),
      child: Row(
        children: [
          // Label with opposition points
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: oppPoints >= oppTarget
                  ? const Color(0xFFE53935)
                  : const Color(0xFF8A7A72),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              L10n.of(context).mtOpposition,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          const SizedBox(width: 6),
          // Scrollable card list
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: oppCards.map((cardId) => Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: PlayingCard(
                    cardId: _displayCardId(cardId),
                    width: 24,
                    height: 34,
                    isInteractive: false,
                  ),
                )).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPointCardsDialog(MightyPlayer p) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.of(context).mtPointCardsTitle(p.name, p.pointCount), style: const TextStyle(fontSize: 15)),
        content: p.pointCards.isEmpty
            ? Text(L10n.of(context).mtNoPointCards)
            : Wrap(
                spacing: 6,
                runSpacing: 6,
                children: p.pointCards.map((cardId) => PlayingCard(
                  cardId: _displayCardId(cardId),
                  width: 42,
                  height: 59,
                  isInteractive: false,
                )).toList(),
              ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(L10n.of(context).mtClose)),
        ],
      ),
    );
  }

  // ── Trick Area ──
  Widget _buildTrickArea(MightyGameStateData state, GameService game) {
    if (state.currentTrick.isEmpty) {
      return Center(
        child: Container(
          width: 200,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.style, size: 20, color: Color(0xFF8A7A72)),
              const SizedBox(height: 4),
              Text(
                state.isMyTurn ? L10n.of(context).mtYourTurn : L10n.of(context).mtWaiting,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF5A4038),
                ),
              ),
              if (_remainingSeconds > 0 && state.isMyTurn)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${_remainingSeconds}s',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _remainingSeconds <= 5 ? const Color(0xFFE53935) : const Color(0xFF8A7A72),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    // Lead suit from first card in trick
    String? leadSuit;
    if (state.currentTrick.isNotEmpty) {
      final leadCardId = state.currentTrick.first.cardId;
      if (leadCardId == 'mighty_joker') {
        leadSuit = state.jokerSuitDeclared;
      } else {
        leadSuit = _getCardSuit(leadCardId);
      }
    }

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  L10n.of(context).mtPlayed(state.currentTrick.length, state.players.length),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF5A4038),
                  ),
                ),
                if (leadSuit != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F0EB),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFE0D8D4)),
                    ),
                    child: Text(
                      _suitSymbol(leadSuit),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: PlayingCard.suitColors[leadSuit] ?? const Color(0xFF5A4038),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (_remainingSeconds > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${_remainingSeconds}s',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _remainingSeconds <= 5 ? const Color(0xFFE53935) : const Color(0xFF8A7A72),
                  ),
                ),
              ),
            if (state.friendCard != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  state.friendRevealed && state.partner != null
                      ? L10n.of(context).mtFriendRevealed(_friendCardLabel(state.friendCard!), state.players.where((p) => p.id == state.partner).map((p) => p.name).firstOrNull ?? '')
                      : L10n.of(context).mtFriendHidden(_friendCardLabel(state.friendCard!)),
                  style: const TextStyle(fontSize: 11, color: Color(0xFF8A7A72)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Trick End Area ──
  Widget _buildTrickEndArea(MightyGameStateData state) {
    final winnerName = state.players
        .where((p) => p.id == state.lastTrickWinner)
        .map((p) => p.name)
        .firstOrNull ?? '';
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                L10n.of(context).mtWins(winnerName),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF4CAF50),
                ),
              ),
            ),
            if (state.friendCard != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  state.friendRevealed && state.partner != null
                      ? L10n.of(context).mtFriendRevealed(_friendCardLabel(state.friendCard!), state.players.where((p) => p.id == state.partner).map((p) => p.name).firstOrNull ?? '')
                      : L10n.of(context).mtFriendHidden(_friendCardLabel(state.friendCard!)),
                  style: const TextStyle(fontSize: 11, color: Color(0xFF8A7A72)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Bidding UI ──
  Widget _buildBiddingUI(MightyGameStateData state, GameService game) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0D8D4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_remainingSeconds > 0) ...[
            Text(
              '${_remainingSeconds}s',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: _remainingSeconds <= 5 ? const Color(0xFFE53935) : const Color(0xFF8A7A72),
              ),
            ),
            const SizedBox(height: 6),
          ],
          // Current bid display
          if (state.currentBid['bidder'] != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFE082)),
              ),
              child: Text(
                L10n.of(context).mtCurrentBid(state.currentBid['points'].toString(), _suitLabel(state.currentBid['suit'])),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF5A4038)),
              ),
            ),
          // Bid history
          if (state.bids.isNotEmpty) ...[
            ...state.bids.entries.map((e) {
              final name = state.players
                  .where((p) => p.id == e.key)
                  .map((p) => p.name)
                  .firstOrNull ?? e.key;
              final bidText = e.value == 'pass'
                  ? L10n.of(context).mtPass
                  : e.value is Map
                    ? '${e.value['points']} ${_suitLabel(e.value['suit'])}'
                    : '${e.value}';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  children: [
                    Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF5A4038))),
                    const SizedBox(width: 8),
                    Text(bidText, style: TextStyle(fontSize: 12, color: e.value == 'pass' ? const Color(0xFF8A7A72) : const Color(0xFF1565C0))),
                  ],
                ),
              );
            }),
            const Divider(height: 16),
          ],
          // Bid controls
          if (state.isMyTurn) ...[
            // Points row
            Builder(builder: (context) {
              final currentBidPoints = (state.currentBid['points'] as num?)?.toInt() ?? 0;
              final currentBidSuit = state.currentBid['suit'] as String?;
              // Minimum bid depends on the effective mode: 5p=13, 6p kill-mighty=14.
              final modeMin = state.mode == '6p' ? 14 : 13;
              // Same points allowed if bidding no_trump over a suited bid
              final canBidSamePoints = currentBidSuit != null && currentBidSuit != 'no_trump' && _bidSuit == 'no_trump';
              final minBid = canBidSamePoints
                  ? currentBidPoints.clamp(modeMin, 20)
                  : (currentBidPoints + 1).clamp(modeMin, 20);
              if (_bidPoints < minBid) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _bidPoints = minBid);
                });
              }
              if (minBid >= 20) {
                // Max bid reached - show fixed value, no slider
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _bidPoints != 20) setState(() => _bidPoints = 20);
                });
                return Row(
                  children: [
                    Text(L10n.of(context).mtPoints, style: const TextStyle(fontSize: 12, color: Color(0xFF5A4038))),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE3F2FD),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('20', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1565C0))),
                    ),
                  ],
                );
              }
              return Row(
              children: [
                Text(L10n.of(context).mtPoints, style: const TextStyle(fontSize: 12, color: Color(0xFF5A4038))),
                Expanded(
                  child: Slider(
                    value: _bidPoints.toDouble().clamp(minBid.toDouble(), 20),
                    min: minBid.toDouble(),
                    max: 20,
                    divisions: 20 - minBid,
                    label: '${_bidPoints.clamp(minBid, 20)}',
                    onChanged: (v) => setState(() => _bidPoints = v.toInt()),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3F2FD),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$_bidPoints', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1565C0))),
                ),
              ],
            );
            }),
            // Suit selection
            Builder(builder: (context) {
              final cbPoints = (state.currentBid['points'] as num?)?.toInt() ?? 0;
              final cbSuit = state.currentBid['suit'] as String?;
              bool suitEnabled(String suit) {
                if (cbPoints == 0) return true;
                if (_bidPoints > cbPoints) return true;
                if (_bidPoints == cbPoints && suit == 'no_trump' && cbSuit != 'no_trump') return true;
                if (_bidPoints < cbPoints) return false;
                return false;
              }
              // Auto-switch to no_trump if current suit is invalid
              if (!suitEnabled(_bidSuit) && suitEnabled('no_trump')) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _bidSuit = 'no_trump');
                });
              }
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildSuitChip('spade', '\u2660', const Color(0xFF2B2B2B), enabled: suitEnabled('spade')),
                    _buildSuitChip('heart', '\u2665', const Color(0xFFD24B4B), enabled: suitEnabled('heart')),
                    _buildSuitChip('diamond', '\u2666', const Color(0xFF6FB6E5), enabled: suitEnabled('diamond')),
                    _buildSuitChip('club', '\u2663', const Color(0xFF4BAA6A), enabled: suitEnabled('club')),
                    _buildSuitChip('no_trump', 'NT', const Color(0xFF7B1FA2), enabled: suitEnabled('no_trump')),
                  ],
                ),
              );
            }),
            const SizedBox(height: 6),
            // Bid / Pass / Deal miss
            Builder(builder: (context) {
              final currentBidPoints = (state.currentBid['points'] as num?)?.toInt() ?? 0;
              final isMaxBid = currentBidPoints >= 20;
              return Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: isMaxBid ? null : () => game.mightySubmitBid(_bidPoints, _bidSuit),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        disabledBackgroundColor: const Color(0xFFBDBDBD),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(L10n.of(context).mtBid(_bidPoints, _suitLabel(_bidSuit))),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => game.mightyPass(),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(L10n.of(context).mtPass),
                  ),
                  if (state.canDeclareDealMiss) ...[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => _confirmDealMiss(game),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFD84315),
                        side: const BorderSide(color: Color(0xFFFF7043)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(L10n.of(context).mtDealMiss),
                    ),
                  ],
                ],
              );
            }),
          ] else
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                L10n.of(context).mtWaitingFor(state.players.where((p) => p.id == state.currentPlayer).map((p) => p.name).firstOrNull ?? '...'),
                style: const TextStyle(fontSize: 13, color: Color(0xFF8A7A72)),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmDealMiss(GameService game) async {
    final l10n = L10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.mtDealMiss, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        content: const Text(
          '딜미스를 선언하시겠습니까?\n\n본인 점수에서 5점이 차감되고, 다음에 성공하는 주공이 적립된 딜미스 점수를 모두 가져갑니다.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.mtCancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD84315)),
            child: Text(l10n.mtDealMiss),
          ),
        ],
      ),
    );
    if (ok == true) {
      game.mightyDeclareDealMiss();
    }
  }

  Widget _buildSuitChip(String suit, String label, Color color, {bool enabled = true}) {
    final isSelected = _bidSuit == suit;
    final effectiveColor = enabled ? color : const Color(0xFFBDBDBD);
    return GestureDetector(
      onTap: enabled ? () => setState(() => _bidSuit = suit) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected && enabled ? color.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected && enabled ? color : const Color(0xFFE0D8D4),
            width: isSelected && enabled ? 2 : 1,
          ),
        ),
        child: suit == 'no_trump'
            ? Text(
                label,
                style: TextStyle(
                  fontSize: 18,
                  color: effectiveColor,
                  fontWeight: isSelected && enabled ? FontWeight.bold : FontWeight.normal,
                ),
              )
            : SuitIcon(suit: suit, size: 20, color: effectiveColor),
      ),
    );
  }

  // ── Kitty Exchange ──
  Widget _buildKittyUI(GameService game, MightyGameStateData state) {
    if (!state.isMyTurn) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            L10n.of(context).mtExchangingKitty,
            style: TextStyle(fontSize: 14, color: Color(0xFF5A4038)),
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE0D8D4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.swap_horiz, size: 18, color: Color(0xFF5A4038)),
                      const SizedBox(width: 6),
                      Text(
                        L10n.of(context).mtDiscard3,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF5A4038)),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _discardSelection.length == 3 ? const Color(0xFFE8F5E9) : const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${_discardSelection.length}/3',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _discardSelection.length == 3 ? const Color(0xFF4CAF50) : const Color(0xFF8A7A72),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(L10n.of(context).mtFriendColon, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF5A4038))),
                  const SizedBox(height: 6),
                  // Step 1: Friend mode
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _buildFriendModeChip('no_friend', L10n.of(context).mtNoFriend),
                      _buildFriendModeChip('first_trick', L10n.of(context).mt1stTrick),
                      _buildFriendModeChip('joker', L10n.of(context).mtJoker),
                      _buildFriendModeChip('card', L10n.of(context).mtCard),
                    ],
                  ),
                  // Step 2: If card mode, pick suit + rank
                  if (_friendMode == 'card') ...[
                    const SizedBox(height: 8),
                    // Suit row
                    Row(
                      children: [
                        for (final suit in ['spade', 'heart', 'diamond', 'club'])
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() {
                                _friendSuit = suit;
                                _syncFriendCardSelection(state);
                              }),
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 2),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: _friendSuit == suit ? const Color(0xFFE3F2FD) : const Color(0xFFF5F5F5),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: _friendSuit == suit ? const Color(0xFF1565C0) : const Color(0xFFE0D8D4),
                                    width: _friendSuit == suit ? 2 : 1,
                                  ),
                                ),
                                child: Center(
                                  child: SuitIcon(suit: suit, size: 18),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Rank row
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final rank in ['A', 'K', 'Q', 'J', '10', '9', '8', '7', '6', '5', '4', '3', '2'])
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _friendRank = rank;
                                _syncFriendCardSelection(state);
                              });
                            },
                            child: Container(
                              width: 36,
                              height: 30,
                              decoration: BoxDecoration(
                                color: _friendRank == rank
                                    ? const Color(0xFFE3F2FD)
                                    : const Color(0xFFF5F5F5),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: _friendRank == rank
                                      ? const Color(0xFF1565C0)
                                      : const Color(0xFFE0D8D4),
                                  width: _friendRank == rank ? 2 : 1,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  rank,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: _friendRank == rank ? FontWeight.bold : FontWeight.normal,
                                    color: const Color(0xFF5A4038),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    // Show selected card label
                    if (_friendCardSelection.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        _friendCardLabel(_friendCardSelection),
                        style: const TextStyle(fontSize: 11, color: Color(0xFF1565C0), fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: FilledButton(
                      onPressed: _discardSelection.length == 3 && _friendCardSelection.isNotEmpty
                          ? () {
                              game.mightyDiscardKitty(_discardSelection.toList(), _friendCardSelection);
                              setState(() => _discardSelection.clear());
                            }
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(L10n.of(context).mtConfirm),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // ── Trump change panel (above hand) ──
        _buildTrumpChangePanel(state, game),
        // Hand for kitty selection
        _buildHandArea(state, game),
      ],
    );
  }

  void _syncFriendCardSelection(MightyGameStateData state) {
    if (_friendMode == 'card') {
      final cardId = 'mighty_${_friendSuit}_$_friendRank';
      _friendCardSelection = cardId;
      _discardSelection.remove(cardId);
    }
  }

  Widget _buildFriendModeChip(String mode, String label) {
    final isSelected = _friendMode == mode;
    return GestureDetector(
      onTap: () => setState(() {
        _friendMode = mode;
        if (mode == 'no_friend') {
          _friendCardSelection = 'no_friend';
        } else if (mode == 'first_trick') {
          _friendCardSelection = 'first_trick';
        } else if (mode == 'joker') {
          _friendCardSelection = 'mighty_joker';
        } else {
          // card mode: compose from suit + rank
          _friendCardSelection = 'mighty_${_friendSuit}_$_friendRank';
        }
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE3F2FD) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF1565C0) : const Color(0xFFE0D8D4),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? const Color(0xFF1565C0) : const Color(0xFF5A4038),
          ),
        ),
      ),
    );
  }

  // ── Bid / Trump Adjustment Panel (floats above hand during kitty exchange) ──
  Widget _buildTrumpChangePanel(MightyGameStateData state, GameService game) {
    if (!state.isMyTurn) return const SizedBox.shrink();
    final bidPoints = state.currentBid['points'] as int? ?? 13;
    final isAtCap = bidPoints >= 20;

    final trumpSuit = state.trumpSuit ?? 'no_trump';
    // Whenever the server confirms a trump change, resync our selection so
    // the new suit is highlighted instead of the stale pre-change one.
    if (_lastKnownTrumpSuit != null && _lastKnownTrumpSuit != trumpSuit) {
      _selectedTrumpSuit = trumpSuit;
    }
    _lastKnownTrumpSuit = trumpSuit;
    _selectedTrumpSuit ??= trumpSuit;
    final isSameTrump = _selectedTrumpSuit == trumpSuit;
    final nextBid = math.min(20, bidPoints + 2);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0D8D4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: current bid + raise bid button (hide at cap)
          if (!isAtCap)
            Row(
              children: [
                Text(
                  L10n.of(context).mtTrumpPenalty(2),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF5A4038)),
                ),
                const Spacer(),
                Text(
                  '$bidPoints',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF5A4038)),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  height: 30,
                  child: FilledButton(
                    onPressed: () => game.mightyRaiseBid(),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text('→ $nextBid', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          if (!isAtCap) const SizedBox(height: 6),
          // Trump change: suit chips + confirm
          Row(
            children: [
              for (final entry in [
                ('spade', '\u2660', const Color(0xFF2B2B2B)),
                ('heart', '\u2665', const Color(0xFFD24B4B)),
                ('diamond', '\u2666', const Color(0xFF6FB6E5)),
                ('club', '\u2663', const Color(0xFF4BAA6A)),
                ('no_trump', 'NT', const Color(0xFF7B1FA2)),
              ])
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _selectedTrumpSuit = entry.$1;
                    }),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      decoration: BoxDecoration(
                        color: _selectedTrumpSuit == entry.$1
                            ? entry.$3.withValues(alpha: 0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _selectedTrumpSuit == entry.$1
                              ? entry.$3
                              : entry.$1 == trumpSuit
                                  ? entry.$3.withValues(alpha: 0.5)
                                  : const Color(0xFFE0D8D4),
                          width: _selectedTrumpSuit == entry.$1 ? 2 : 1,
                        ),
                      ),
                      child: Center(
                        child: entry.$1 == 'no_trump'
                            ? Text(
                                entry.$2,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: entry.$3,
                                  fontWeight: _selectedTrumpSuit == entry.$1 || entry.$1 == trumpSuit
                                      ? FontWeight.bold : FontWeight.normal,
                                ),
                              )
                            : SuitIcon(suit: entry.$1, size: 18, color: entry.$3),
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              SizedBox(
                height: 34,
                child: FilledButton(
                  onPressed: isSameTrump && isAtCap ? null : () {
                    if (isSameTrump) {
                      game.mightyRaiseBid();
                    } else {
                      game.mightyChangeTrump(_selectedTrumpSuit!);
                    }
                    setState(() => _selectedTrumpSuit = null);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: isSameTrump ? const Color(0xFF1565C0) : const Color(0xFFE65100),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(
                    isAtCap
                        ? L10n.of(context).mtChangeTrump
                        : (isSameTrump ? '→ $nextBid' : L10n.of(context).mtChangeTrump),
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Spectator Hand View ──
  Widget _buildSpectatorHandArea(MightyGameStateData state, GameService game) {
    final viewingPlayer = _viewingPlayerId == null
        ? null
        : state.players.cast<MightyPlayer?>().firstWhere(
              (p) => p?.id == _viewingPlayerId,
              orElse: () => null,
            );
    final isApproved = viewingPlayer != null &&
        game.approvedCardViews.contains(viewingPlayer.id) &&
        viewingPlayer.canViewCards;
    final isPending = viewingPlayer != null &&
        game.pendingCardViewRequests.contains(viewingPlayer.id);

    final baseDeco = BoxDecoration(
      color: Colors.white.withValues(alpha: 0.85),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      border: const Border(top: BorderSide(color: Color(0xFFE0D8D4))),
    );

    if (viewingPlayer == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: baseDeco,
        child: Text(
          L10n.of(context).skGameTapToRequestCards,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF8A7A72), fontSize: 13, fontWeight: FontWeight.w600),
        ),
      );
    }

    if (isPending && !isApproved) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: baseDeco,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFFB74D))),
            const SizedBox(width: 8),
            Text(
              L10n.of(context).skGameRequestingCardView(viewingPlayer.name),
              style: const TextStyle(color: Color(0xFF8A7A72), fontSize: 13, fontWeight: FontWeight.w600),
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
              child: Text(
                L10n.of(context).skGamePlayerHand(viewingPlayer.name),
                style: const TextStyle(color: Color(0xFF5A4038), fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
            if (viewingPlayer.cards.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  L10n.of(context).skGameNoCards,
                  style: const TextStyle(color: Color(0xFF8A7A72), fontSize: 12),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _buildHandRows(viewingPlayer.cards, legalCards: const {}, isPlaying: false, isKitty: false, state: state),
              ),
          ],
        ),
      );
    }

    // Rejected
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: baseDeco,
      child: Text(
        L10n.of(context).skGameCardViewRejected(viewingPlayer.name),
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFF8A7A72), fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }

  // ── Hand Area (SK-style) ──
  Widget _buildHandArea(MightyGameStateData state, GameService game) {
    // Spectator card view
    if (game.isSpectator) {
      return _buildSpectatorHandArea(state, game);
    }
    // Killed-mighty player — reuse the spectator-style peek panel so they can
    // view any opponents they've been granted card-view permission for.
    final myId = game.playerId;
    if (myId.isNotEmpty && state.excludedPlayers.contains(myId)) {
      return _buildSpectatorHandArea(state, game);
    }
    final cards = state.myCards;
    if (cards.isEmpty) return const SizedBox(height: 20);

    final isPlaying = state.phase == 'playing' && state.isMyTurn;
    final isKitty = state.phase == 'kitty_exchange' && state.isMyTurn;
    // Pre-selection: during playing phase while it isn't our turn yet, we can
    // compute which cards WOULD be legal (based on the already-known lead
    // suit) and let the user queue one up. When the turn arrives, the server
    // will confirm legality via state.legalCards.
    final canPreselect = state.phase == 'playing'
        && !state.isMyTurn
        && state.currentTrick.isNotEmpty;
    final legalCards = state.isMyTurn
        ? state.legalCards.toSet()
        : (canPreselect ? _previewLegalCards(state) : <String>{});
    final selectedCard = _selectedCard;
    final isSelectedLegal = selectedCard != null && legalCards.contains(selectedCard);

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      decoration: BoxDecoration(
        color: (isPlaying && state.isMyTurn)
            ? const Color(0xFFFFF6D8).withValues(alpha: 0.96)
            : Colors.white.withValues(alpha: 0.92),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(
            color: (isPlaying && state.isMyTurn)
                ? const Color(0xFFE6C86A)
                : const Color(0xFFE0D8D4),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (game.myTimeoutCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _buildTimeoutResetChip(game),
            ),
          // Play button
          if (isPlaying && selectedCard != null && isSelectedLegal)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 8, right: 8),
              child: SizedBox(
                width: double.infinity,
                height: 42,
                child: FilledButton.icon(
                  onPressed: () {
                    final isJokerCallCard = selectedCard == state.jokerCallCard;
                    game.mightyPlayCard(
                      selectedCard,
                      jokerSuit: selectedCard == 'mighty_joker'
                          ? (_jokerSuitChoice ?? (state.trumpSuit != null && state.trumpSuit != 'no_trump' ? state.trumpSuit! : 'spade'))
                          : null,
                      jokerCall: isJokerCallCard && state.currentTrick.isEmpty && _jokerCallChoice,
                    );
                    setState(() {
                      _selectedCard = null;
                      _jokerSuitChoice = null;
                      _jokerCallChoice = true;
                    });
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE6F1FF),
                    foregroundColor: const Color(0xFF355D89),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.play_arrow, size: 20),
                  label: Text(
                    _remainingSeconds > 0 ? L10n.of(context).mtPlayTimer(_remainingSeconds) : L10n.of(context).mtPlay,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
            )
          else if (isPlaying)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    L10n.of(context).mtSelectCard,
                    style: TextStyle(color: Color(0xFF5A4038), fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  if (_remainingSeconds > 0) ...[
                    const SizedBox(width: 8),
                    Text(
                      '(${_remainingSeconds}s)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _remainingSeconds <= 5 ? const Color(0xFFE53935) : const Color(0xFF8A7A72),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          // Joker weak warning (first/last trick)
          if (isPlaying && _selectedCard == 'mighty_joker') ...[
            if (state.tricks.isEmpty || state.tricks.length == (50 ~/ state.players.length) - 1)
              Container(
                margin: const EdgeInsets.only(bottom: 6, left: 8, right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFFB74D)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFE65100)),
                    const SizedBox(width: 6),
                    Text(
                      state.tricks.isEmpty ? L10n.of(context).mtJokerLoses1st : L10n.of(context).mtJokerLosesLast,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFE65100)),
                    ),
                  ],
                ),
              ),
          ],
          // Joker suit selector
          if (isPlaying && _selectedCard == 'mighty_joker' && state.currentTrick.isEmpty)
            _buildJokerSuitSelector(),
          // Joker call toggle
          if (isPlaying && _selectedCard == state.jokerCallCard && state.currentTrick.isEmpty)
            _buildJokerCallToggle(),
          // Card rows
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _buildHandRows(cards, legalCards: legalCards, isPlaying: isPlaying || canPreselect, isKitty: isKitty, state: state),
          ),
        ],
      ),
    );
  }

  Widget _buildHandRows(List<String> cards, {required Set<String> legalCards, required bool isPlaying, required bool isKitty, MightyGameStateData? state}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth - 24;
        final perRow = cards.length <= 7 ? cards.length : (cards.length / 2).ceil();
        final cardPadding = cards.length >= 8 ? 1.5 : 3.0;
        final totalPadding = perRow * cardPadding * 2;
        final cardWidth = ((availableWidth - totalPadding) / perRow).clamp(0.0, 52.0);
        final cardHeight = (cardWidth * 1.4).clamp(52.0, 73.0);

        Widget buildCard(String cardId) {
          final isLegal = !isPlaying || legalCards.isEmpty || legalCards.contains(cardId);
          // Kitty: block mighty, joker, and friend card from discard
          final isKittyBlocked = isKitty && _isKittyBlockedCard(cardId, state);
          final isSelected = isPlaying
              ? _selectedCard == cardId
              : isKitty
                  ? _discardSelection.contains(cardId)
                  : false;

          // Badge: mighty card, joker call card, friend card, or kitty card
          final isMightyCard = state?.mightyCard != null && cardId == state!.mightyCard;
          final isJokerCallCard = !isMightyCard && state?.jokerCallCard != null && cardId == state!.jokerCallCard;
          final isFriendCard = !isMightyCard && !isJokerCallCard && state?.friendCard != null && cardId == state!.friendCard;
          final isKittyCard = !isMightyCard && !isJokerCallCard && !isFriendCard && isKitty && (state?.kittyCards.contains(cardId) ?? false);
          // Post-kill/suicide: cards received via redistribution get the move_up badge
          // for the receiving player (similar to declarer's kitty-pickup highlight).
          final isRedistCard = !isMightyCard && !isJokerCallCard && !isFriendCard && !isKittyCard
              && (state?.newlyReceivedCards.contains(cardId) ?? false);
          // Trump suit border
          Color? trumpBorder;
          if (state?.trumpSuit != null && state!.trumpSuit != 'no_trump') {
            final cardSuit = _getCardSuit(cardId);
            if (cardSuit == state.trumpSuit) {
              trumpBorder = PlayingCard.suitColors[cardSuit];
            }
          }

          return GestureDetector(
            onTap: () {
              setState(() {
                if (isPlaying) {
                  if (!isLegal) return;
                  _selectedCard = _selectedCard == cardId ? null : cardId;
                  // Auto-select trump suit when joker is selected for leading
                  if (_selectedCard == 'mighty_joker' && state != null) {
                    final ts = state.trumpSuit;
                    _jokerSuitChoice = (ts != null && ts != 'no_trump') ? ts : 'spade';
                  }
                } else if (isKitty) {
                  if (isKittyBlocked) return;
                  if (_discardSelection.contains(cardId)) {
                    _discardSelection.remove(cardId);
                  } else if (_discardSelection.length < 3) {
                    _discardSelection.add(cardId);
                  }
                }
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              transform: Matrix4.translationValues(0, isSelected ? -12 : 0, 0),
              child: Opacity(
                opacity: (isLegal && !isKittyBlocked) ? 1.0 : 0.4,
                child: Container(
                  decoration: isSelected
                      ? BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF355D89).withValues(alpha: 0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        )
                      : null,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: cardPadding),
                    child: PlayingCard(
                      cardId: _displayCardId(cardId),
                      width: cardWidth,
                      height: cardHeight,
                      isSelected: isSelected,
                      isInteractive: false,
                      badgeIcon: isMightyCard ? Icons.star : isJokerCallCard ? Icons.gps_fixed : isFriendCard ? Icons.people : isKittyCard ? Icons.move_up : isRedistCard ? Icons.move_up : null,
                      badgeColor: isMightyCard ? const Color(0xFFFFB300) : isJokerCallCard ? const Color(0xFFE53935) : isFriendCard ? const Color(0xFF4CAF50) : isKittyCard ? const Color(0xFF7B1FA2) : isRedistCard ? const Color(0xFF7B1FA2) : null,
                      borderColor: trumpBorder,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        if (cards.length <= 7) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: cards.map(buildCard).toList(),
            ),
          );
        }

        final half = (cards.length / 2).ceil();
        final firstRow = cards.take(half).toList();
        final secondRow = cards.skip(half).toList();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: firstRow.map(buildCard).toList()),
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: secondRow.map(buildCard).toList()),
            ],
          ),
        );
      },
    );
  }

  Widget _buildJokerSuitSelector() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(L10n.of(context).mtJokerSuit, style: const TextStyle(fontSize: 12, color: Color(0xFF5A4038))),
          ...[
            ('spade', '\u2660', const Color(0xFF2B2B2B)),
            ('heart', '\u2665', const Color(0xFFD24B4B)),
            ('diamond', '\u2666', const Color(0xFF6FB6E5)),
            ('club', '\u2663', const Color(0xFF4BAA6A)),
          ].map((s) {
            final selected = _jokerSuitChoice == s.$1;
            return GestureDetector(
              onTap: () => setState(() => _jokerSuitChoice = s.$1),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: selected ? s.$3.withValues(alpha: 0.12) : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: selected ? s.$3 : const Color(0xFFE0D8D4), width: selected ? 2 : 1),
                ),
                child: Text(s.$2, style: TextStyle(fontSize: 16, color: s.$3)),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Round End (SK-style) ──
  Widget _buildRoundEndUI(MightyGameStateData state) {
    final result = state.roundResult;
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0D8D4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F1EC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE7DBD4)),
            ),
            child: Text(
              L10n.of(context).mtRoundResult(state.round),
              style: const TextStyle(color: Color(0xFF5A4038), fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 8),
          if (result != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: result['success'] == true ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                result['success'] == true ? L10n.of(context).mtDeclarerWins(result['declarerPoints']) : L10n.of(context).mtDeclarerFails(result['declarerPoints']),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: result['success'] == true ? const Color(0xFF4CAF50) : const Color(0xFFE53935),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          const Divider(height: 8),
          ...state.players.map((p) {
            final roundScore = (result?['scores']?[p.id] as num?)?.toInt();
            final totalScore = state.scores[p.id] ?? 0;
            final isDeclarer = p.id == state.declarer;
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: p.position == 'self' ? const Color(0xFFF7F1EC) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  if (isDeclarer) const Text('\u2605 ', style: TextStyle(fontSize: 12, color: Color(0xFFFF8A00))),
                  Expanded(
                    child: Text(p.name, style: TextStyle(
                      fontSize: 13,
                      fontWeight: p.position == 'self' ? FontWeight.bold : FontWeight.normal,
                      color: const Color(0xFF5A4038),
                    )),
                  ),
                  if (roundScore != null)
                    Text(
                      '${roundScore > 0 ? '+' : ''}$roundScore',
                      style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold,
                        color: roundScore > 0 ? const Color(0xFF4CAF50) : roundScore < 0 ? const Color(0xFFE53935) : const Color(0xFF5A4038),
                      ),
                    ),
                  const SizedBox(width: 12),
                  Text('$totalScore', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF5A4038))),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          Text(L10n.of(context).mtNextRound, style: const TextStyle(color: Color(0xFF8A7A72), fontSize: 12)),
        ],
      ),
    );
  }

  // ── Game End (SK-style) ──
  Widget _buildGameEndUI(MightyGameStateData state, GameService game) {
    final sorted = List<MightyPlayer>.from(state.players)
      ..sort((a, b) => (state.scores[b.id] ?? 0).compareTo(state.scores[a.id] ?? 0));

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0D8D4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F1EC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE7DBD4)),
            ),
            child: Text(L10n.of(context).mtGameOver, style: const TextStyle(color: Color(0xFF5A4038), fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 16),
          ...sorted.asMap().entries.map((entry) {
            final rank = entry.key + 1;
            final p = entry.value;
            final score = state.scores[p.id] ?? 0;
            final isWinner = rank == 1;
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: isWinner ? const Color(0xFFFFF8E1) : Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(10),
                border: isWinner ? Border.all(color: const Color(0xFFFFD700)) : null,
              ),
              child: Row(
                children: [
                  Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      color: isWinner ? const Color(0xFFFFD700) : const Color(0xFFF5F5F5),
                      shape: BoxShape.circle,
                      border: Border.all(color: isWinner ? const Color(0xFFFFB300) : const Color(0xFFE0D8D4)),
                    ),
                    child: Center(child: Text('$rank', style: TextStyle(
                      color: isWinner ? Colors.black : const Color(0xFF5A4038), fontWeight: FontWeight.bold, fontSize: 14,
                    ))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(p.name, style: TextStyle(
                    color: const Color(0xFF5A4038), fontSize: isWinner ? 16 : 14, fontWeight: isWinner ? FontWeight.bold : FontWeight.normal,
                  ))),
                  Text('$score', style: TextStyle(color: const Color(0xFF5A4038), fontSize: isWinner ? 18 : 15, fontWeight: FontWeight.bold)),
                ],
              ),
            );
          }),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFC7DCF8)),
            ),
            child: Text(
              _gameEndCountdown > 0 ? L10n.of(context).mtReturningIn(_gameEndCountdown) : L10n.of(context).mtReturningToRoom,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF355D89), fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  // ── Card View Request Popup ──
  Widget _buildCardViewRequestPopup(GameService game) {
    final request = game.firstIncomingCardViewRequest;
    if (request == null) return const SizedBox.shrink();
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
                    onPressed: () => game.rejectAllCardViewRequests(),
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

  // ── Error Banner ──
  Widget _buildTimeoutResetChip(GameService game) {
    return GestureDetector(
      onTap: () => game.resetTimeout(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E0),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFFB74D)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.timer_off_outlined, size: 15, color: Color(0xFFE65100)),
            const SizedBox(width: 5),
            Text(
              '${game.myTimeoutCount}/3',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFFE65100)),
            ),
            const SizedBox(width: 4),
            Text(
              L10n.of(context).gameReset,
              style: const TextStyle(fontSize: 11, color: Color(0xFFE65100), fontWeight: FontWeight.w700),
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
        ),
        child: Row(
          children: [
            const Icon(Icons.timer_off, color: Color(0xFFE65100)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                L10n.of(context).gameTimeout(playerName),
                style: const TextStyle(color: Color(0xFFE65100), fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDealMissRevealOverlay(MightyDealMissEvent event) {
    final l10n = L10n.of(context);
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() {
          _dismissedDealMissKey = '${event.round}-${event.playerId}';
        }),
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: Colors.black.withValues(alpha: 0.5),
          alignment: Alignment.center,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8F2),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFFFAB91), width: 2),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 12, offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 20, color: Color(0xFFD84315)),
                    const SizedBox(width: 6),
                    Text(
                      l10n.mtDealMiss,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFFD84315)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.mtDealMissReveal(event.playerName, _formatHandScore(event.handScore)),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF5A4038)),
                ),
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 4,
                  runSpacing: 4,
                  children: event.cards
                      .map((cardId) => PlayingCard(
                            cardId: _displayCardId(cardId),
                            width: 38,
                            height: 54,
                            isInteractive: false,
                          ))
                      .toList(),
                ),
                const SizedBox(height: 10),
                Text(
                  l10n.mtDealMissTapToClose,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF8A7A72)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatHandScore(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }

  // ── Kill Phase UI ──
  Widget _buildKillSelectUI(MightyGameStateData state, GameService game) {
    final l10n = L10n.of(context);
    final isDeclarer = state.isMyTurn;
    if (!isDeclarer) {
      final declarerName = state.players
          .where((p) => p.id == state.declarer)
          .map((p) => p.name)
          .firstOrNull ?? '...';
      return Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.gps_fixed, size: 28, color: Color(0xFFD84315)),
              const SizedBox(height: 8),
              Text(
                l10n.mtKillPhaseWait(declarerName),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF5A4038)),
              ),
            ],
          ),
        ),
      );
    }

    // Declarer's selection grid: every card in the deck except cards in own hand.
    // To keep the panel readable in a single viewport we split it into a
    // dedicated joker chip plus a suit-tabbed rank row, instead of rendering
    // all 53 cards at once.
    final ownHand = state.myCards.toSet();
    const suits = ['spade', 'heart', 'diamond', 'club'];
    const ranks = ['A', 'K', 'Q', 'J', '10', '9', '8', '7', '6', '5', '4', '3', '2'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFAB91)),
            ),
            child: Row(
              children: [
                const Icon(Icons.gps_fixed, size: 18, color: Color(0xFFD84315)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.mtKillPhasePrompt,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFD84315)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Joker — always a separate chip so it can't be hidden behind a tab.
          _buildKillCardChip(ownHand, 'mighty_joker'),
          const SizedBox(height: 10),
          // Suit tabs
          Row(
            children: [
              for (final suit in suits) ...[
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _killSuitTab = suit),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _killSuitTab == suit
                            ? (PlayingCard.suitColors[suit] ?? const Color(0xFF5A4038)).withValues(alpha: 0.12)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _killSuitTab == suit
                              ? (PlayingCard.suitColors[suit] ?? const Color(0xFF5A4038))
                              : const Color(0xFFE0D8D4),
                          width: _killSuitTab == suit ? 2 : 1,
                        ),
                      ),
                      child: Center(
                        child: SuitIcon(suit: suit, size: 22),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          // Rank grid for the selected suit — 13 chips fit on two rows.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              for (final rank in ranks) _buildKillCardChip(ownHand, 'mighty_${_killSuitTab}_$rank'),
            ],
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _selectedKillCard == null
                ? null
                : () {
                    game.mightyDeclareKill(_selectedKillCard!);
                    setState(() => _selectedKillCard = null);
                  },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD84315),
              disabledBackgroundColor: const Color(0xFFBDBDBD),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: Text(l10n.mtKillConfirm, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
        ],
      ),
    );
  }

  Widget _buildKillCardChip(Set<String> ownHand, String cardId) {
    final inHand = ownHand.contains(cardId);
    final isSelected = _selectedKillCard == cardId;
    final isJoker = cardId == 'mighty_joker';

    String? rank;
    String? suit;
    Color textColor;
    if (isJoker) {
      textColor = const Color(0xFF7B1FA2);
    } else {
      final parts = cardId.replaceFirst('mighty_', '').split('_');
      suit = parts[0];
      rank = parts[1];
      textColor = PlayingCard.suitColors[suit] ?? const Color(0xFF1A1A1A);
    }

    return GestureDetector(
      onTap: inHand ? null : () => setState(() => _selectedKillCard = cardId),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: isJoker ? double.infinity : 52,
        padding: EdgeInsets.symmetric(horizontal: isJoker ? 12 : 4, vertical: isJoker ? 12 : 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: inHand
              ? const Color(0xFFECEFF1)
              : isSelected
                  ? const Color(0xFFFFEBEE)
                  : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFFD84315) : const Color(0xFFE0D8D4),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: isJoker
            ? Text(
                'JOKER',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: inHand ? const Color(0xFFBDBDBD) : textColor,
                  decoration: inHand ? TextDecoration.lineThrough : TextDecoration.none,
                  letterSpacing: 1.5,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SuitIcon(
                    suit: suit!,
                    size: 14,
                    color: inHand ? const Color(0xFFBDBDBD) : textColor,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    rank!,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: inHand ? const Color(0xFFBDBDBD) : textColor,
                      decoration: inHand ? TextDecoration.lineThrough : TextDecoration.none,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildKillRevealOverlay(MightyGameStateData state, MightyKillEvent event) {
    final l10n = L10n.of(context);
    String cardLabel;
    if (event.targetCardId == 'mighty_joker') {
      cardLabel = 'JOKER';
    } else {
      final parts = event.targetCardId.replaceFirst('mighty_', '').split('_');
      cardLabel = '${_suitSymbol(parts[0])}${parts[1]}';
    }
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() {
          _dismissedKillKey = '${state.round}-${event.targetCardId}';
        }),
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: Colors.black.withValues(alpha: 0.55),
          alignment: Alignment.center,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8F2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFFF7043), width: 2),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 14, offset: const Offset(0, 5)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.gps_fixed, size: 22, color: Color(0xFFD84315)),
                    const SizedBox(width: 6),
                    Text(
                      l10n.mtKillPhase,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: Color(0xFFD84315)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  event.wasKitty
                      ? l10n.mtKillResultSuicide(event.declarerName, cardLabel)
                      : l10n.mtKillResultKilled(event.declarerName, cardLabel, event.victimName ?? '?'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF5A4038)),
                ),
                const SizedBox(height: 10),
                Text(
                  l10n.mtDealMissTapToClose,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF8A7A72)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Positioned(
      top: 60,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFEBEE),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE53935)),
        ),
        child: Text(message, style: const TextStyle(color: Color(0xFFE53935), fontWeight: FontWeight.bold, fontSize: 13)),
      ),
    );
  }

  // ── Helpers ──
  String _phaseLabel(String phase) {
    final l10n = L10n.of(context);
    switch (phase) {
      case 'bidding': return l10n.mtPhaseBidding;
      case 'kill_select': return l10n.mtKillPhase;
      case 'kitty_exchange': return l10n.mtPhaseKitty;
      case 'playing': return l10n.mtPhasePlaying;
      case 'trick_end': return l10n.mtPhasePlaying;
      case 'round_end': return l10n.mtPhaseRoundEnd;
      case 'game_end': return l10n.mtPhaseGameEnd;
      default: return phase;
    }
  }

  String _suitSymbol(String suit) {
    switch (suit) {
      case 'spade': return '\u2660';
      case 'heart': return '\u2665';
      case 'diamond': return '\u2666';
      case 'club': return '\u2663';
      case 'no_trump': return 'NT';
      default: return suit;
    }
  }

  String _suitLabel(dynamic suit) {
    if (suit == null) return '';
    return _suitSymbol(suit.toString());
  }

  String _friendCardLabel(String cardId) {
    final l10n = L10n.of(context);
    if (cardId == 'mighty_joker') return l10n.mtFriendCardJoker;
    if (cardId == 'no_friend') return l10n.mtFriendCardSolo;
    if (cardId == 'first_trick') return l10n.mtFriendCard1st;
    final parts = cardId.replaceFirst('mighty_', '').split('_');
    if (parts.length == 2) return '${_suitSymbol(parts[0])}${parts[1]}';
    return cardId;
  }

  String? _getCardSuit(String cardId) {
    if (cardId == 'mighty_joker') return null;
    final stripped = cardId.replaceFirst('mighty_', '');
    final parts = stripped.split('_');
    if (parts.length >= 2) return parts[0];
    return null;
  }

  /// Client-side mirror of the server's trick-play legality so users can
  /// pre-select a card while waiting for their turn. Honours the "must
  /// follow lead suit when possible" rule; mighty and joker are always
  /// playable. Joker-call-forced-joker corner case is deliberately skipped
  /// — the server will still validate the actual play.
  Set<String> _previewLegalCards(MightyGameStateData state) {
    final hand = state.myCards;
    final trick = state.currentTrick;
    if (hand.isEmpty) return <String>{};
    if (trick.isEmpty) return hand.toSet();

    final leadCardId = trick[0].cardId;
    final leadSuit = leadCardId == 'mighty_joker'
        ? (state.jokerSuitDeclared)
        : _getCardSuit(leadCardId);
    if (leadSuit == null) return hand.toSet();

    final suitCards = hand.where((c) {
      if (c == 'mighty_joker') return false;
      return _getCardSuit(c) == leadSuit;
    }).toList();

    if (suitCards.isEmpty) return hand.toSet();
    // Must follow suit; mighty and joker can always be substituted.
    final legal = <String>{...suitCards};
    if (hand.contains('mighty_joker')) legal.add('mighty_joker');
    final mighty = state.mightyCard;
    if (mighty != null && hand.contains(mighty)) legal.add(mighty);
    return legal;
  }


  bool _isKittyBlockedCard(String cardId, MightyGameStateData? state) {
    if (state == null) return false;
    // Block mighty card
    if (state.mightyCard != null && cardId == state.mightyCard) return true;
    // Block joker
    if (cardId == 'mighty_joker') return true;
    // Block friend card (unless it's a special value)
    if (_friendCardSelection.isNotEmpty &&
        _friendCardSelection != 'no_friend' &&
        _friendCardSelection != 'first_trick' &&
        cardId == _friendCardSelection) {
      return true;
    }
    return false;
  }

  Widget _buildJokerCallToggle() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(L10n.of(context).mtJokerCall, style: const TextStyle(fontSize: 12, color: Color(0xFF5A4038))),
          GestureDetector(
            onTap: () => setState(() => _jokerCallChoice = true),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: _jokerCallChoice ? const Color(0xFFE8F5E9) : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _jokerCallChoice ? const Color(0xFF4CAF50) : const Color(0xFFE0D8D4),
                  width: _jokerCallChoice ? 2 : 1,
                ),
              ),
              child: Text(L10n.of(context).mtYes, style: TextStyle(
                fontSize: 13,
                fontWeight: _jokerCallChoice ? FontWeight.bold : FontWeight.normal,
                color: _jokerCallChoice ? const Color(0xFF4CAF50) : const Color(0xFF5A4038),
              )),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _jokerCallChoice = false),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: !_jokerCallChoice ? const Color(0xFFFFEBEE) : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: !_jokerCallChoice ? const Color(0xFFE53935) : const Color(0xFFE0D8D4),
                  width: !_jokerCallChoice ? 2 : 1,
                ),
              ),
              child: Text(L10n.of(context).mtNo, style: TextStyle(
                fontSize: 13,
                fontWeight: !_jokerCallChoice ? FontWeight.bold : FontWeight.normal,
                color: !_jokerCallChoice ? const Color(0xFFE53935) : const Color(0xFF5A4038),
              )),
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
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
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
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF5A4038)),
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

  void _showScoreHistoryDialog(MightyGameStateData state, GameService game) {
    final suitSymbol = {
      'spade': '♠', 'heart': '♥', 'diamond': '♦', 'club': '♣', 'no_trump': 'NT',
    };

    final cumulativeScores = <String, int>{for (final p in state.players) p.id: 0};

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: const Color(0xFFFBFCFE),
        titlePadding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
        contentPadding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        title: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF2FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.table_chart_rounded, size: 16, color: Color(0xFF295EA8)),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '점수 기록',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF233142)),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF2FF),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFFC9DCF7)),
                    ),
                    child: Text(
                      '/${game.roomTargetScore}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF295EA8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${state.scoreHistory.length}R',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF6B7A90)),
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
                  Color color = const Color(0xFF5A4038),
                  double fontSize = 10,
                  EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
                }) {
                  return Padding(
                    padding: padding,
                    child: Text(
                      text,
                      textAlign: align,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: fontWeight,
                        color: color,
                      ),
                    ),
                  );
                }

                final border = TableBorder.symmetric(
                  inside: const BorderSide(color: Color(0xFFDCE4EE), width: 0.6),
                  outside: const BorderSide(color: Color(0xFFDCE4EE), width: 0.8),
                );

                return Table(
                  columnWidths: {
                    0: const FlexColumnWidth(0.7),
                    1: const FlexColumnWidth(1.5),
                    for (int i = 0; i < state.players.length; i++) i + 2: const FlexColumnWidth(1),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  border: border,
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(color: Color(0xFFEAF2FF)),
                      children: [
                        cell('R', fontWeight: FontWeight.w800, fontSize: 10.5, color: const Color(0xFF295EA8)),
                        cell('비딩', fontWeight: FontWeight.w800, fontSize: 10.5, color: const Color(0xFF295EA8)),
                        ...state.players.map((p) => cell(
                              p.name.length > 2 ? p.name.substring(0, 2) : p.name,
                              fontWeight: FontWeight.w800,
                              fontSize: 9.5,
                              color: const Color(0xFF295EA8),
                            )),
                      ],
                    ),
                    ...state.scoreHistory.map((entry) {
                      final trump = suitSymbol[entry.trumpSuit] ?? entry.trumpSuit ?? '?';
                      for (final p in state.players) {
                        cumulativeScores[p.id] = (cumulativeScores[p.id] ?? 0) + (entry.scores[p.id] ?? 0);
                      }
                      final rowTint = entry.dealMiss
                          ? const Color(0xFFFFF4E5)
                          : (entry.success ? const Color(0xFFF4FBF6) : const Color(0xFFFFF6F7));
                      final bidText = entry.dealMiss
                          ? L10n.of(context).mtDealMiss
                          : '$trump${entry.bid}${entry.success ? '✓' : '✗'}';
                      return TableRow(
                        decoration: BoxDecoration(color: rowTint),
                        children: [
                          cell('${entry.round}', fontWeight: FontWeight.w700),
                          cell(
                            bidText,
                            align: TextAlign.left,
                            fontWeight: FontWeight.w700,
                            color: entry.dealMiss ? const Color(0xFFB56A1D) : const Color(0xFF233142),
                          ),
                          ...state.players.map((p) {
                            final diff = entry.scores[p.id] ?? 0;
                            final isDeclTeam = !entry.dealMiss && (p.id == entry.declarer || p.id == entry.partner);
                            return cell(
                              diff == 0 ? '0' : (diff > 0 ? '+$diff' : '$diff'),
                              fontSize: 9.5,
                              fontWeight: isDeclTeam || diff != 0 ? FontWeight.w700 : FontWeight.w500,
                              color: diff > 0
                                  ? const Color(0xFF1F8B4C)
                                  : diff < 0
                                      ? const Color(0xFFD04A5B)
                                      : const Color(0xFF425466),
                            );
                          }),
                        ],
                      );
                    }),
                    TableRow(
                      decoration: const BoxDecoration(color: Color(0xFFF0F4F8)),
                      children: [
                        cell('', fontWeight: FontWeight.w800),
                        cell('합계', align: TextAlign.left, fontWeight: FontWeight.w800, color: const Color(0xFF233142)),
                        ...state.players.map((p) {
                          final total = cumulativeScores[p.id] ?? 0;
                          return cell(
                            '$total',
                            fontWeight: FontWeight.w800,
                            color: total >= 0 ? const Color(0xFF1F8B4C) : const Color(0xFFD04A5B),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(L10n.of(context).mtClose)),
        ],
      ),
    );
  }

  // ── Player Profile Dialog ──
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
            final l10n = L10n.of(context);

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
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.person_outline, color: Color(0xFF2E7D32)),
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
                                isMe ? l10n.gameMyProfile : l10n.gamePlayerProfile,
                                style: const TextStyle(fontSize: 12, color: Color(0xFF84766E)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (!isMe && !isBot) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (game.friends.contains(nickname))
                            _buildProfileIconBtn(Icons.check, const Color(0xFFBDBDBD), l10n.gameAlreadyFriend, () {})
                          else if (game.sentFriendRequests.contains(nickname))
                            _buildProfileIconBtn(Icons.hourglass_top, const Color(0xFFBDBDBD), l10n.gameRequestPending, () {})
                          else
                            _buildProfileIconBtn(Icons.person_add, const Color(0xFF81C784), l10n.gameAddFriend, () {
                              game.addFriendAction(nickname);
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.gameFriendRequestSent)));
                            }),
                          _buildProfileIconBtn(
                            isBlockedUser ? Icons.block : Icons.shield_outlined,
                            isBlockedUser ? const Color(0xFF64B5F6) : const Color(0xFFFF8A65),
                            isBlockedUser ? l10n.gameUnblock : l10n.gameBlock,
                            () {
                              if (isBlockedUser) {
                                game.unblockUserAction(nickname);
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.gameUnblocked)));
                              } else {
                                game.blockUserAction(nickname);
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.gameBlocked)));
                              }
                            },
                          ),
                          _buildProfileIconBtn(Icons.flag, const Color(0xFFE57373), l10n.gameReport, () {
                            Navigator.pop(ctx);
                            _showReportDialog(nickname, game);
                          }),
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
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.gameClose)),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildProfileIconBtn(IconData icon, Color color, String tooltip, VoidCallback onTap) {
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

  Widget _buildProfileContent(Map<String, dynamic> data) {
    final profile = data['profile'] as Map<String, dynamic>?;
    if (profile == null) return Text(L10n.of(context).gameProfileNotFound);

    final l10n = L10n.of(context);
    final level = profile['level'] ?? 1;
    final expTotal = profile['expTotal'] ?? 0;
    final leaveCount = profile['leaveCount'] ?? 0;
    final reportCount = profile['reportCount'] ?? 0;
    final totalGames = profile['totalGames'] ?? 0;
    final bannerKey = profile['bannerKey']?.toString();

    // Mighty stats
    final mightyTotalGames = profile['mightyTotalGames'] ?? 0;
    final mightyWins = profile['mightyWins'] ?? 0;
    final mightyLosses = profile['mightyLosses'] ?? 0;
    final mightyWinRate = profile['mightyWinRate'] ?? 0;
    final mightySeasonRating = profile['mightySeasonRating'] ?? 1000;
    final mightySeasonGames = profile['mightySeasonGames'] ?? 0;
    final mightySeasonWins = profile['mightySeasonWins'] ?? 0;
    final mightySeasonLosses = profile['mightySeasonLosses'] ?? 0;
    final mightySeasonWinRate = profile['mightySeasonWinRate'] ?? 0;

    final recentMatches = (data['recentMatches'] as List<dynamic>? ?? [])
        .where((m) => m['gameType'] == 'mighty')
        .toList();
    final profileNickname = data['nickname']?.toString() ?? '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildProfileHeader(level as int, expTotal as int, bannerKey),
        const SizedBox(height: 8),
        _buildMannerLeaveRow(totalGames: totalGames as int, reportCount: reportCount as int, leaveCount: leaveCount as int),
        const SizedBox(height: 10),
        _buildProfileSection(
          title: l10n.rankingMightySeasonRanked,
          accent: const Color(0xFF2E7D32),
          background: const Color(0xFFE8F5E9),
          icon: Icons.emoji_events,
          iconColor: const Color(0xFFFFD54F),
          mainText: '$mightySeasonRating',
          chips: [
            _buildStatChip(l10n.gameStatRecord, l10n.gameRecordFormat(mightySeasonGames as int, mightySeasonWins as int, mightySeasonLosses as int)),
            _buildStatChip(l10n.gameStatWinRate, '$mightySeasonWinRate%'),
          ],
        ),
        const SizedBox(height: 10),
        _buildProfileSection(
          title: l10n.rankingMightyRecord,
          accent: const Color(0xFF1B5E20),
          background: const Color(0xFFF1F8E9),
          icon: Icons.military_tech,
          iconColor: const Color(0xFF4CAF50),
          mainText: '',
          chips: [
            _buildStatChip(l10n.gameStatRecord, l10n.gameRecordFormat(mightyTotalGames as int, mightyWins as int, mightyLosses as int)),
            _buildStatChip(l10n.gameStatWinRate, '$mightyWinRate%'),
          ],
        ),
        const SizedBox(height: 12),
        _buildRecentMatchesList(recentMatches, profileNickname),
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
                  child: LinearProgressIndicator(
                    value: expPercent,
                    minHeight: 6,
                    backgroundColor: const Color(0xFFEFE7E3),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF64B5F6)),
                  ),
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

  static int _calcMannerScore(int totalGames, int leaveCount, int reportCount) {
    int score = 1000;
    score -= leaveCount * 5;
    score -= reportCount * 3;
    score += (totalGames ~/ 10) * 5;
    return score.clamp(0, 1000);
  }

  Widget _buildMannerLeaveRow({required int totalGames, required int reportCount, required int leaveCount}) {
    final manner = _calcMannerScore(totalGames, leaveCount, reportCount);
    final Color color;
    final IconData icon;
    if (manner >= 800) { color = const Color(0xFF4CAF50); icon = Icons.sentiment_very_satisfied; }
    else if (manner >= 500) { color = const Color(0xFFFF9800); icon = Icons.sentiment_neutral; }
    else { color = const Color(0xFFE53935); icon = Icons.sentiment_very_dissatisfied; }
    final l10n = L10n.of(context);
    final boxDeco = BoxDecoration(
      color: Colors.white.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE0D8D4)),
    );
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: boxDeco,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Flexible(child: Text('${l10n.rankingMannerScore} $manner', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color), overflow: TextOverflow.ellipsis)),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: boxDeco,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFE57373), size: 16),
              const SizedBox(width: 6),
              Flexible(child: Text(l10n.gameDesertions(leaveCount), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF9A6A6A)), overflow: TextOverflow.ellipsis)),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileSection({
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
              Text(title, style: TextStyle(fontSize: 12, color: accent, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (mainText.isNotEmpty)
                Text(mainText, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: accent)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: chips),
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
          Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF8A8A8A))),
          const SizedBox(width: 4),
          Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF5A4038))),
        ],
      ),
    );
  }

  Widget _buildRecentMatchesList(List<dynamic> matches, String profileNickname) {
    final l10n = L10n.of(context);
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
          Text(l10n.gameRecentMatchesThree, style: const TextStyle(fontSize: 12, color: Color(0xFF8A8A8A))),
          const SizedBox(height: 8),
          if (matches.isEmpty)
            Text(l10n.gameNoRecentMatches, style: const TextStyle(fontSize: 12, color: Color(0xFF9A8E8A)))
          else
            Column(
              children: matches.take(3).map<Widget>((match) => _buildMatchRow(match)).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildMatchRow(dynamic match) {
    final l10n = L10n.of(context);
    final isDesertionLoss = match['isDesertionLoss'] == true;
    final won = match['won'] == true;

    String badge;
    Color badgeColor;
    if (isDesertionLoss) {
      badge = l10n.rankingBadgeDesertion;
      badgeColor = const Color(0xFFFF8A65);
    } else if (won) {
      badge = 'W';
      badgeColor = const Color(0xFF81C784);
    } else {
      badge = 'L';
      badgeColor = const Color(0xFFE57373);
    }

    final myRank = match['myRank'] ?? '-';
    final myScore = match['myScore'] ?? 0;
    final date = _formatShortDate(match['createdAt']);
    final isRanked = match['isRanked'] == true;
    final players = match['players'] as List<dynamic>? ?? [];
    final playerText = players.map((p) => p['nickname'] ?? '?').join(', ');
    final scoreText = isDesertionLoss
        ? ''
        : l10n.lobbyRankAndScore(myRank.toString(), (myScore as num?)?.toInt() ?? 0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 24, height: 24, alignment: Alignment.center,
            decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
            child: Text(badge, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: isRanked ? const Color(0xFFFFF3E0) : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              isRanked ? l10n.lobbyMatchTypeRanked : l10n.lobbyMatchTypeNormal,
              style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: isRanked ? const Color(0xFFE65100) : const Color(0xFF9E9E9E)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(date, style: const TextStyle(fontSize: 11, color: Color(0xFF8A8A8A))),
                const SizedBox(height: 2),
                Text(
                  playerText,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF5A4038)),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (scoreText.isNotEmpty)
            Text(scoreText, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF5A4038))),
        ],
      ),
    );
  }

  String _formatShortDate(dynamic value) {
    try {
      final dt = DateTime.parse(value.toString()).toLocal();
      return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return '-';
    }
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
                    child: Text(l10n.gameReportTitle(nickname), style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 420, maxHeight: media.size.height * 0.55),
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
                        child: Text(l10n.gameReportWarning, style: const TextStyle(fontSize: 12, color: Color(0xFF9A4A4A), height: 1.4)),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(l10n.gameSelectReason, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: reasons.map((r) {
                          final isSelected = selectedReason == r;
                          return ChoiceChip(
                            label: Text(r, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : const Color(0xFF5A4038))),
                            selected: isSelected,
                            selectedColor: const Color(0xFFE57373),
                            backgroundColor: const Color(0xFFF5F0EB),
                            onSelected: (_) => setState(() => selectedReason = r),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: reasonController,
                        maxLines: 3,
                        maxLength: 200,
                        decoration: InputDecoration(
                          hintText: l10n.gameReportDetailHint,
                          hintStyle: const TextStyle(fontSize: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.gameClose)),
                ElevatedButton(
                  onPressed: selectedReason == null
                      ? null
                      : () {
                          final detail = reasonController.text.trim();
                          final reason = detail.isEmpty ? selectedReason! : '${selectedReason!} / $detail';
                          Navigator.pop(ctx);
                          game.reportUserAction(nickname, reason);
                        },
                  child: Text(l10n.gameReportSubmit),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
