import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/game_service.dart';
import '../services/network_service.dart';
import '../models/mighty_game_state.dart';
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
                    return const Center(child: CircularProgressIndicator());
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
                          _bidPoints = 13;
                          _bidSuit = 'spade';
                          _discardSelection.clear();
                          _friendCardSelection = '';
                          _friendMode = '';
                          _friendSuit = 'spade';
                          _friendRank = 'A';
                          _selectedTrumpSuit = null;
                        }
                        if (state.phase == 'kitty_exchange') {
                          _discardSelection.clear();
                          _selectedTrumpSuit = null;
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
                          if (state.phase == 'kitty_exchange')
                            Expanded(child: _buildKittyUI(game, state)),
                          if (state.phase == 'playing')
                            Expanded(
                              child: Column(
                                children: [
                                  const Spacer(),
                                  _buildTrickArea(state),
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
                      if (game.errorMessage != null)
                        _buildErrorBanner(game.errorMessage!),
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

  // ── Top Bar (SK-style) ──
  Widget _buildTopBar(MightyGameStateData state, GameService game) {
    final trumpLabel = state.trumpSuit != null
        ? (state.trumpSuit == 'no_trump' ? 'NT' : _suitSymbol(state.trumpSuit!))
        : '';
    final showContractInfo = state.declarer != null &&
        state.phase != 'bidding' && state.phase != 'dealing';

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
                      L10n.of(context).mtRoundPhase(state.round.toString(), _phaseLabel(state.phase)),
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
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Spacer(),
              if (_remainingSeconds > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _remainingSeconds <= 5
                        ? const Color(0xFFFFEBEE)
                        : Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _remainingSeconds <= 5
                          ? const Color(0xFFE53935)
                          : const Color(0xFFCCCCCC),
                    ),
                  ),
                  child: Text(
                    '${_remainingSeconds}s',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: _remainingSeconds <= 5
                          ? const Color(0xFFE53935)
                          : const Color(0xFF5A4038),
                    ),
                  ),
                ),
              if (state.scoreHistory.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _buildTopActionButton(
                    icon: Icons.history,
                    active: false,
                    onTap: () => _showScoreHistoryDialog(state),
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
    final declarerName = state.players
        .where((p) => p.id == state.declarer)
        .map((p) => p.name)
        .firstOrNull ?? '';
    final bidPoints = state.currentBid['points'];
    final bidSuit = state.currentBid['suit'];
    final suitLabel = bidSuit != null ? _suitSymbol(bidSuit.toString()) : '';

    String friendLabel = '';
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
                Text(
                  declarerName,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF5A4038)),
                ),
                const SizedBox(width: 6),
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
                if (!state.friendRevealed) ...[
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
          if (showTrumpCounter)
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

  // ── Scoreboard (SK-style) ──
  Widget _buildScoreboard(MightyGameStateData state, GameService game) {
    final isSpectator = game.isSpectator;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      margin: EdgeInsets.zero,
      child: Row(
        children: state.players.map((p) {
          final isCurrentTurn = p.id == state.currentPlayer;
          final isSelf = p.position == 'self';
          final isDeclarer = p.id == state.declarer;
          final isPartner = state.friendRevealed && p.id == state.partner;
          // Spectator card view state
          final isPending = isSpectator && game.pendingCardViewRequests.contains(p.id);
          final isApproved = isSpectator && game.approvedCardViews.contains(p.id) && p.canViewCards;

          // Opposition = not declarer and not revealed partner → can show pointCards
          final isGovt = p.id == state.declarer || (state.friendRevealed && p.id == state.partner);
          final hasPointCards = !isGovt && p.pointCards.isNotEmpty;

          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (isSpectator) {
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
                          // Role badge
                          SizedBox(
                            height: 14,
                            child: isDeclarer
                                ? Text(L10n.of(context).mtDeclarer, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFFFF8A00)))
                                : isPartner
                                    ? Text(L10n.of(context).mtFriend, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF4CAF50)))
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
                              if (isCurrentTurn && _remainingSeconds > 0) ...[
                                const SizedBox(width: 3),
                                Text(
                                  '${_remainingSeconds}s',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: _remainingSeconds <= 5 ? const Color(0xFFE53935) : const Color(0xFFE6A800),
                                  ),
                                ),
                              ],
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
                          const SizedBox(height: 16),
                          const SizedBox(height: 2),
                        ],
                      ),
                    ),
                    // Spectator card view badges
                    if (isSpectator && isPending)
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
                    else if (isSpectator && isApproved)
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
                    else if (isSpectator)
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
                            : trickPlay.cardId == state.jokerCallCard ? Icons.gps_fixed
                            : null,
                        badgeColor: trickPlay.cardId == state.mightyCard ? const Color(0xFFFFB300)
                            : trickPlay.cardId == state.jokerCallCard ? const Color(0xFFE53935)
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
              '야당',
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
  Widget _buildTrickArea(MightyGameStateData state) {
    if (state.currentTrick.isEmpty) {
      return Center(
        child: Container(
          width: 180,
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
              // Same points allowed if bidding no_trump over a suited bid
              final canBidSamePoints = currentBidSuit != null && currentBidSuit != 'no_trump' && _bidSuit == 'no_trump';
              final minBid = canBidSamePoints
                  ? currentBidPoints.clamp(13, 20)
                  : (currentBidPoints + 1).clamp(13, 20);
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
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSuitChip('spade', '\u2660', const Color(0xFF2B2B2B)),
                  _buildSuitChip('heart', '\u2665', const Color(0xFFD24B4B)),
                  _buildSuitChip('diamond', '\u2666', const Color(0xFF6FB6E5)),
                  _buildSuitChip('club', '\u2663', const Color(0xFF4BAA6A)),
                  _buildSuitChip('no_trump', 'NT', const Color(0xFF7B1FA2)),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // Bid / Pass
            Builder(builder: (context) {
              final currentBidPoints = (state.currentBid['points'] as num?)?.toInt() ?? 0;
              final currentBidSuit = state.currentBid['suit'] as String?;
              final isMaxBid = currentBidPoints >= 20 && currentBidSuit == 'no_trump';
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

  Widget _buildSuitChip(String suit, String label, Color color) {
    final isSelected = _bidSuit == suit;
    return GestureDetector(
      onTap: () => setState(() => _bidSuit = suit),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : const Color(0xFFE0D8D4),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 18,
            color: color,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
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
                                  child: Text(
                                    _suitSymbol(suit),
                                    style: TextStyle(
                                      fontSize: 18,
                                      color: (suit == 'heart' || suit == 'diamond') ? Colors.red : Colors.black,
                                    ),
                                  ),
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
    if (bidPoints >= 20) return const SizedBox.shrink(); // already at cap

    final trumpSuit = state.trumpSuit ?? 'no_trump';
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
          // Header: current bid + raise bid button
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
          const SizedBox(height: 6),
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
                        child: Text(
                          entry.$2,
                          style: TextStyle(
                            fontSize: 15,
                            color: entry.$3,
                            fontWeight: _selectedTrumpSuit == entry.$1 || entry.$1 == trumpSuit
                                ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              SizedBox(
                height: 34,
                child: FilledButton(
                  onPressed: () {
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
                    isSameTrump ? '→ $nextBid' : L10n.of(context).mtChangeTrump,
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

  // ── Hand Area (SK-style) ──
  Widget _buildHandArea(MightyGameStateData state, GameService game) {
    final cards = state.myCards;
    if (cards.isEmpty) return const SizedBox(height: 20);

    final isPlaying = state.phase == 'playing' && state.isMyTurn;
    final isKitty = state.phase == 'kitty_exchange' && state.isMyTurn;
    final legalCards = state.legalCards.toSet();
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
            child: _buildHandRows(cards, legalCards: legalCards, isPlaying: isPlaying, isKitty: isKitty, state: state),
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
                      badgeIcon: isMightyCard ? Icons.star : isJokerCallCard ? Icons.gps_fixed : isFriendCard ? Icons.people : isKittyCard ? Icons.move_up : null,
                      badgeColor: isMightyCard ? const Color(0xFFFFB300) : isJokerCallCard ? const Color(0xFFE53935) : isFriendCard ? const Color(0xFF4CAF50) : isKittyCard ? const Color(0xFF7B1FA2) : null,
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

  void _showScoreHistoryDialog(MightyGameStateData state) {
    final suitSymbol = {
      'spade': '♠', 'heart': '♥', 'diamond': '♦', 'club': '♣', 'no_trump': 'NT',
    };

    // Cumulative scores per player
    final cumScores = <String, int>{for (final p in state.players) p.id: 0};

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.of(context).mtScoreHistory, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 10,
                horizontalMargin: 4,
                headingRowHeight: 36,
                dataRowMinHeight: 32,
                dataRowMaxHeight: 40,
                headingTextStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF5A4038)),
                dataTextStyle: const TextStyle(fontSize: 11, color: Color(0xFF5A4038)),
                columns: [
                  const DataColumn(label: Text('R')),
                  const DataColumn(label: Text('공약')),
                  const DataColumn(label: Text('결과')),
                  ...state.players.map((p) => DataColumn(
                    label: Text(
                      p.name.length > 4 ? '${p.name.substring(0, 4)}..' : p.name,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  )),
                ],
                rows: [
                  ...state.scoreHistory.map((entry) {
                    final trump = suitSymbol[entry.trumpSuit] ?? entry.trumpSuit ?? '?';
                    for (final p in state.players) {
                      cumScores[p.id] = (cumScores[p.id] ?? 0) + (entry.scores[p.id] ?? 0);
                    }
                    return DataRow(
                      color: WidgetStateProperty.all(
                        entry.success ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
                      ),
                      cells: [
                        DataCell(Text('${entry.round}', style: const TextStyle(fontWeight: FontWeight.w700))),
                        DataCell(Text('$trump${entry.bid}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
                        DataCell(Text(
                          entry.success ? '${entry.declarerPoints}✓' : '${entry.declarerPoints}✗',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: entry.success ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                          ),
                        )),
                        ...state.players.map((p) {
                          final score = entry.scores[p.id] ?? 0;
                          final isDeclTeam = p.id == entry.declarer || p.id == entry.partner;
                          return DataCell(Text(
                            score >= 0 ? '+$score' : '$score',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isDeclTeam ? FontWeight.w800 : FontWeight.w500,
                              color: score >= 0 ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                            ),
                          ));
                        }),
                      ],
                    );
                  }),
                  // Total row
                  DataRow(
                    color: WidgetStateProperty.all(const Color(0xFFF5F0EB)),
                    cells: [
                      const DataCell(Text('')),
                      const DataCell(Text('')),
                      const DataCell(Text('합계', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                      ...state.players.map((p) {
                        final total = cumScores[p.id] ?? 0;
                        return DataCell(Text(
                          '$total',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: total >= 0 ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                          ),
                        ));
                      }),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(L10n.of(context).mtClose)),
        ],
      ),
    );
  }
}
