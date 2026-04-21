import 'dart:async';
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
                        }
                        if (state.phase == 'kitty_exchange') {
                          _discardSelection.clear();
                          _friendCardSelection = '';
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
                          if (state.phase == 'round_end')
                            Expanded(child: SingleChildScrollView(child: _buildRoundEndUI(state))),
                          if (state.phase == 'game_end')
                            Expanded(child: SingleChildScrollView(child: _buildGameEndUI(state, game))),
                        ],
                      ),
                      if (_chatOpen) _buildChatPanel(game),
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
                      'R${state.round} ${_phaseLabel(state.phase)}',
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
          _buildContractInfoBar(state),
      ],
    );
  }

  Widget _buildContractInfoBar(MightyGameStateData state) {
    final declarerName = state.players
        .where((p) => p.id == state.declarer)
        .map((p) => p.name)
        .firstOrNull ?? '';
    final bidPoints = state.currentBid['points'];
    final bidSuit = state.currentBid['suit'];

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
      friendLabel = 'Solo';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Text(
        '$declarerName | $bidPoints${bidSuit != null ? _suitSymbol(bidSuit.toString()) : ''} | Friend: $friendLabel',
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF5A4038)),
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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
                  const Text(
                    'Chat',
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
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12),
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
        title: const Text('Leave Game?'),
        content: const Text('Are you sure you want to leave?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              game.leaveRoom();
            },
            child: const Text('Leave', style: TextStyle(color: Colors.red)),
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
      margin: EdgeInsets.only(bottom: state.phase == 'playing' || state.phase == 'trick_end' ? 80 : 0),
      child: Row(
        children: state.players.map((p) {
          final isCurrentTurn = p.id == state.currentPlayer;
          final isSelf = p.position == 'self';
          final isDeclarer = p.id == state.declarer;
          final isPartner = state.friendRevealed && p.id == state.partner;
          // Show current trick cards during playing, lastTrickCards during trick_end
          final trickPlay = state.phase == 'trick_end'
              ? state.lastTrickCards.cast<MightyTrickPlay?>().firstWhere(
                  (play) => play?.playerId == p.id, orElse: () => null)
              : state.currentTrick.cast<MightyTrickPlay?>().firstWhere(
                  (play) => play?.playerId == p.id, orElse: () => null);
          final isTrickWinner = state.phase == 'trick_end' && p.id == state.lastTrickWinner;

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
                        color: isTrickWinner
                            ? const Color(0xFFE8F5E9)
                            : isSelf
                                ? Colors.white.withValues(alpha: 0.95)
                                : isCurrentTurn
                                    ? const Color(0xFFFFF2B3)
                                    : Colors.white.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(12),
                        border: isTrickWinner
                            ? Border.all(color: const Color(0xFF4CAF50), width: 2)
                            : isCurrentTurn
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
                                ? const Text('주공', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFFFF8A00)))
                                : isPartner
                                    ? const Text('프렌드', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF4CAF50)))
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
                          // Trick/Point info
                          SizedBox(
                            height: 16,
                            child: state.phase == 'playing' || state.phase == 'trick_end' || state.phase == 'round_end' || state.phase == 'game_end'
                                ? Text(
                                    '${p.trickCount}T ${p.pointCount}P',
                                    style: const TextStyle(fontSize: 9, color: Color(0xFF8A7A72)),
                                  )
                                : null,
                          ),
                          // Mini point card labels for opposition
                          if (hasPointCards)
                            SizedBox(
                              height: 14,
                              child: Text(
                                p.pointCards.take(5).map((c) => _miniCardLabel(c)).join(' '),
                                style: const TextStyle(fontSize: 8, color: Color(0xFF8A7A72)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Played card badge below scoreboard
                    if (trickPlay != null)
                      Positioned(
                        left: 0, right: 0, bottom: -72,
                        child: Center(
                          child: Container(
                            decoration: isTrickWinner
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
                            ),
                          ),
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

  void _showPointCardsDialog(MightyPlayer p) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${p.name} - Point Cards (${p.pointCount}P)', style: const TextStyle(fontSize: 15)),
        content: p.pointCards.isEmpty
            ? const Text('No point cards yet')
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
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
                state.isMyTurn ? 'Your turn' : 'Waiting...',
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

    // Trick cards are shown below each player in the scoreboard.
    // Center area shows info text.
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
            Text(
              '${state.currentTrick.length}/${state.players.length} played',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Color(0xFF5A4038),
              ),
            ),
            if (state.friendCard != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  state.friendRevealed && state.partner != null
                      ? 'Friend: ${_friendCardLabel(state.friendCard!)} \u2192 ${state.players.where((p) => p.id == state.partner).map((p) => p.name).firstOrNull ?? ''}'
                      : 'Friend: ${_friendCardLabel(state.friendCard!)}',
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
                '$winnerName wins!',
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
                      ? 'Friend: ${_friendCardLabel(state.friendCard!)} \u2192 ${state.players.where((p) => p.id == state.partner).map((p) => p.name).firstOrNull ?? ''}'
                      : 'Friend: ${_friendCardLabel(state.friendCard!)}',
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
                'Current bid: ${state.currentBid['points']} ${_suitLabel(state.currentBid['suit'])}',
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
                  ? 'Pass'
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
                    const Text('Points:', style: TextStyle(fontSize: 12, color: Color(0xFF5A4038))),
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
                const Text('Points:', style: TextStyle(fontSize: 12, color: Color(0xFF5A4038))),
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
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => game.mightySubmitBid(_bidPoints, _bidSuit),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Bid $_bidPoints ${_suitLabel(_bidSuit)}'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => game.mightyPass(),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Pass'),
                ),
              ],
            ),
          ] else
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'Waiting for ${state.players.where((p) => p.id == state.currentPlayer).map((p) => p.name).firstOrNull ?? "..."}',
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
          child: const Text(
            'Declarer is exchanging kitty...',
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
                      const Text(
                        'Discard 3 cards',
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
                  const Text('Friend card:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF5A4038))),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _buildFriendOption('no_friend', 'Solo'),
                      if (state.mightyCard != null)
                        _buildFriendOption(state.mightyCard!, 'Mighty'),
                      if (state.mightyCard != 'mighty_spade_A')
                        _buildFriendOption('mighty_spade_A', '\u2660A'),
                      if (state.mightyCard != 'mighty_heart_A')
                        _buildFriendOption('mighty_heart_A', '\u2665A'),
                      if (state.mightyCard != 'mighty_diamond_A')
                        _buildFriendOption('mighty_diamond_A', '\u2666A'),
                      if (state.mightyCard != 'mighty_club_A')
                        _buildFriendOption('mighty_club_A', '\u2663A'),
                      _buildFriendOption('first_trick', '1st Trick'),
                    ],
                  ),
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
                      child: const Text('Confirm'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Hand for kitty selection
        _buildHandArea(state, game),
      ],
    );
  }

  Widget _buildFriendOption(String value, String label) {
    final isSelected = _friendCardSelection == value;
    return GestureDetector(
      onTap: () => setState(() {
        _friendCardSelection = value;
        // Remove newly selected friend card from discard selection
        if (value != 'no_friend' && value != 'first_trick') {
          _discardSelection.remove(value);
        }
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                          ? (_jokerSuitChoice ?? 'spade')
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
                    _remainingSeconds > 0 ? 'Play (${_remainingSeconds}s)' : 'Play',
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
                  const Text(
                    'Select a card',
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
                      state.tricks.isEmpty ? 'Joker loses on 1st trick!' : 'Joker loses on last trick!',
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

          // Badge: mighty card or joker call card
          final isMightyCard = state?.mightyCard != null && cardId == state!.mightyCard;
          final isJokerCallCard = !isMightyCard && state?.jokerCallCard != null && cardId == state!.jokerCallCard;
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
                      badgeIcon: isMightyCard ? Icons.star : isJokerCallCard ? Icons.gps_fixed : null,
                      badgeColor: isMightyCard ? const Color(0xFFFFB300) : isJokerCallCard ? const Color(0xFFE53935) : null,
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
          const Text('Joker suit: ', style: TextStyle(fontSize: 12, color: Color(0xFF5A4038))),
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
              'Round ${state.round} Result',
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
                result['success'] == true ? 'Declarer wins! (${result['declarerPoints']}P)' : 'Declarer fails (${result['declarerPoints']}P)',
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
          const Text('Next round preparing...', style: TextStyle(color: Color(0xFF8A7A72), fontSize: 12)),
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
            child: const Text('Game Over', style: TextStyle(color: Color(0xFF5A4038), fontSize: 18, fontWeight: FontWeight.w800)),
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
              _gameEndCountdown > 0 ? 'Returning in $_gameEndCountdown...' : 'Returning to room...',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF355D89), fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
        ],
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
    switch (phase) {
      case 'bidding': return 'Bidding';
      case 'kitty_exchange': return 'Kitty';
      case 'playing': return 'Playing';
      case 'trick_end': return 'Playing';
      case 'round_end': return 'Round End';
      case 'game_end': return 'Game End';
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
    if (cardId == 'mighty_joker') return 'Joker';
    if (cardId == 'no_friend') return 'Solo';
    if (cardId == 'first_trick') return '1st Trick';
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

  String _miniCardLabel(String cardId) {
    if (cardId == 'mighty_joker') return 'JK';
    final stripped = cardId.replaceFirst('mighty_', '');
    final parts = stripped.split('_');
    if (parts.length == 2) return '${_suitSymbol(parts[0])}${parts[1]}';
    return '?';
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
          const Text('Joker Call: ', style: TextStyle(fontSize: 12, color: Color(0xFF5A4038))),
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
              child: Text('Yes', style: TextStyle(
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
              child: Text('No', style: TextStyle(
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

  void _showScoreHistoryDialog(MightyGameStateData state) {
    final suitSymbol = {
      'spade': '♠', 'heart': '♥', 'diamond': '♦', 'club': '♣', 'no_trump': 'NT',
    };

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Score History', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: state.scoreHistory.length,
            itemBuilder: (context, index) {
              final entry = state.scoreHistory[index];
              final declarerName = state.players
                  .where((p) => p.id == entry.declarer)
                  .map((p) => p.name)
                  .firstOrNull ?? entry.declarer ?? '?';
              final partnerName = entry.partner != null
                  ? state.players
                      .where((p) => p.id == entry.partner)
                      .map((p) => p.name)
                      .firstOrNull ?? entry.partner!
                  : null;
              final trump = suitSymbol[entry.trumpSuit] ?? entry.trumpSuit ?? '?';

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: entry.success
                      ? const Color(0xFFE8F5E9)
                      : const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: entry.success
                        ? const Color(0xFFA5D6A7)
                        : const Color(0xFFEF9A9A),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Round header
                    Row(
                      children: [
                        Text(
                          'R${entry.round}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF5A4038)),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1565C0),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$trump ${entry.bid}',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: entry.success ? const Color(0xFF4CAF50) : const Color(0xFFE53935),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            entry.success ? '${entry.declarerPoints}pts ✓' : '${entry.declarerPoints}pts ✗',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      partnerName != null
                          ? '$declarerName + $partnerName'
                          : '$declarerName (solo)',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF5A4038)),
                    ),
                    const SizedBox(height: 6),
                    // Per-player scores
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: state.players.map((p) {
                        final score = entry.scores[p.id] ?? 0;
                        final isDeclTeam = p.id == entry.declarer || p.id == entry.partner;
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isDeclTeam
                                  ? const Color(0xFF1565C0).withValues(alpha: 0.4)
                                  : const Color(0xFFE0D8D4),
                            ),
                          ),
                          child: Text(
                            '${p.name} ${score >= 0 ? "+$score" : "$score"}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isDeclTeam ? FontWeight.w700 : FontWeight.w500,
                              color: score >= 0 ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }
}
