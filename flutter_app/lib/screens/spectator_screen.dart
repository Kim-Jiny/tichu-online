import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/player.dart';
import '../services/game_service.dart';
import '../widgets/playing_card.dart';
import '../widgets/connection_overlay.dart';
import 'lobby_screen.dart';

class SpectatorScreen extends StatefulWidget {
  const SpectatorScreen({super.key});

  @override
  State<SpectatorScreen> createState() => _SpectatorScreenState();
}

class _SpectatorScreenState extends State<SpectatorScreen> {
  bool _isLeaving = false;
  bool _chatOpen = false;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  @override
  void dispose() {
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _leaveRoom(GameService game) {
    if (_isLeaving) return;
    _isLeaving = true;
    game.leaveRoom();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LobbyScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // C9: Wrap in ConnectionOverlay for reconnection support
    return ConnectionOverlay(
      child: Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF2D3436),
              Color(0xFF1E272E),
            ],
          ),
        ),
        child: SafeArea(
          child: Consumer<GameService>(
            builder: (context, game, _) {
              // Check if we left the room (e.g. disconnected)
              if (!game.isSpectator || game.currentRoomId.isEmpty) {
                if (!_isLeaving) {
                  _isLeaving = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const LobbyScreen()),
                      );
                    }
                  });
                }
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                );
              }

              final state = game.spectatorGameState;
              if (state == null) {
                return _buildWaitingRoomView(context, game);
              }

              return _buildSpectatorView(context, game, state);
            },
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildWaitingRoomView(BuildContext context, GameService game) {
    final players = game.roomPlayers;

    return Stack(
      children: [
        Column(
          children: [
            // Top bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => _leaveRoom(game),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8E0F8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.visibility, size: 14, color: Color(0xFF4A4080)),
                        SizedBox(width: 4),
                        Text(
                          '관전중',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF4A4080),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      game.currentRoomName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _buildChatButton(),
                ],
              ),
            ),

            // Player slots
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Team A header
                      const Text(
                        'Team A',
                        style: TextStyle(
                          color: Color(0xFF6A9BD1),
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildPlayerSlot(game, players[0], 0),
                          const SizedBox(width: 16),
                          _buildPlayerSlot(game, players[2], 2),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // Team B header
                      const Text(
                        'Team B',
                        style: TextStyle(
                          color: Color(0xFFF5B8C0),
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildPlayerSlot(game, players[1], 1),
                          const SizedBox(width: 16),
                          _buildPlayerSlot(game, players[3], 3),
                        ],
                      ),
                      const SizedBox(height: 32),
                      // Waiting text
                      const Text(
                        '게임 시작 대기 중...',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white38,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),

        // Chat panel overlay
        if (_chatOpen) _buildChatPanel(game),
      ],
    );
  }

  Widget _buildPlayerSlot(GameService game, Player? player, int slotIndex) {
    final bool isEmpty = player == null;
    final String name = isEmpty ? '' : player.name;
    final bool isReady = isEmpty ? false : player.isReady;
    final bool isHost = isEmpty ? false : player.isHost;

    final content = Container(
      width: 130,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: isEmpty
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isEmpty
              ? Colors.blue.withValues(alpha: 0.3)
              : isReady
                  ? Colors.greenAccent.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.2),
          width: isReady ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isEmpty ? Icons.person_add : Icons.person,
            color: isEmpty ? Colors.blue.withValues(alpha: 0.5) : Colors.white70,
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(
            isEmpty ? '착석' : name,
            style: TextStyle(
              color: isEmpty ? Colors.blue.withValues(alpha: 0.7) : Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          if (!isEmpty) ...[
            const SizedBox(height: 4),
            Text(
              isHost ? '방장' : (isReady ? '준비완료' : '대기중'),
              style: TextStyle(
                color: isHost
                    ? Colors.amber
                    : isReady
                        ? Colors.greenAccent
                        : Colors.white38,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );

    if (isEmpty) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => game.switchToPlayer(slotIndex),
          borderRadius: BorderRadius.circular(16),
          splashColor: Colors.blue.withValues(alpha: 0.2),
          child: content,
        ),
      );
    }

    return content;
  }

  Widget _buildSpectatorView(
    BuildContext context,
    GameService game,
    Map<String, dynamic> state,
  ) {
    final players = (state['players'] as List?) ?? [];
    final currentTrick = (state['currentTrick'] as List?) ?? [];
    final phase = state['phase'] ?? '';
    final totalScores = state['totalScores'] as Map<String, dynamic>? ?? {};
    final currentPlayer = state['currentPlayer'] ?? '';
    final round = state['round'] ?? 1;

    return Stack(
      children: [
        Column(
          children: [
            // Top bar
            _buildTopBar(context, game, phase, round, totalScores),

            // Game area
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    // Top player (position 2 - partner of bottom)
                    if (players.length > 2) _buildPlayerSection(game, players[2], currentPlayer),

                    // Middle row: left, center trick, right
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Left player (position 1)
                          if (players.length > 1)
                            _buildPlayerSection(game, players[1], currentPlayer, isLeft: true),

                          // Center: current trick
                          Expanded(
                            child: _buildTrickArea(currentTrick),
                          ),

                          // Right player (position 3)
                          if (players.length > 3)
                            _buildPlayerSection(game, players[3], currentPlayer, isRight: true),
                        ],
                      ),
                    ),

                    // Bottom player (position 0)
                    if (players.isNotEmpty) _buildPlayerSection(game, players[0], currentPlayer),
                  ],
                ),
              ),
            ),
          ],
        ),

        // Chat panel overlay
        if (_chatOpen) _buildChatPanel(game),

        // Bug #10: Game end overlay for spectators
        if (phase == 'game_end')
          _buildGameEndOverlay(game, totalScores),
      ],
    );
  }

  Widget _buildGameEndOverlay(GameService game, Map<String, dynamic> scores) {
    final teamA = scores['teamA'] ?? 0;
    final teamB = scores['teamB'] ?? 0;
    final winnerText = teamA > teamB ? 'Team A 승리!' : teamB > teamA ? 'Team B 승리!' : '무승부!';

    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                winnerText,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF5A4038),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Team A: $teamA | Team B: $teamB',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6A5A52),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => _leaveRoom(game),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6A9BD1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('로비로 돌아가기'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    GameService game,
    String phase,
    int round,
    Map<String, dynamic> scores,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _leaveRoom(game),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFE8E0F8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.visibility, size: 14, color: Color(0xFF4A4080)),
                SizedBox(width: 4),
                Text(
                  '관전중',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4A4080),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Text(
            'R$round | ${_getPhaseText(phase)}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF6A9BD1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'A: ${scores['teamA'] ?? 0}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF5B8C0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'B: ${scores['teamB'] ?? 0}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildChatButton(),
        ],
      ),
    );
  }

  String _getPhaseText(String phase) {
    switch (phase) {
      case 'large_tichu_phase':
        return '그랜드 티츄';
      case 'card_exchange':
        return '카드 교환';
      case 'playing':
        return '플레이 중';
      case 'round_end':
        return '라운드 종료';
      case 'game_end':
        return '게임 종료';
      default:
        return phase;
    }
  }

  Widget _buildPlayerSection(
    GameService game,
    Map<String, dynamic> player,
    String currentPlayerId, {
    bool isLeft = false,
    bool isRight = false,
  }) {
    final playerId = player['id'] ?? '';
    final name = player['name'] ?? '';
    final cards = (player['cards'] as List?) ?? [];
    final cardCount = player['cardCount'] ?? 0;
    final canSeeCards = player['canSeeCards'] == true;
    final team = player['team'] ?? '';
    final isCurrentTurn = playerId == currentPlayerId;
    final hasFinished = player['hasFinished'] ?? false;
    final finishPosition = player['finishPosition'] ?? 0;
    final hasSmallTichu = player['hasSmallTichu'] ?? false;
    final hasLargeTichu = player['hasLargeTichu'] ?? false;
    final connected = player['connected'] ?? true;
    final vertical = isLeft || isRight;

    final isPending = game.pendingCardViewRequests.contains(playerId);
    final teamColor = team == 'A' ? const Color(0xFF6A9BD1) : const Color(0xFFF5B8C0);

    return Container(
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isCurrentTurn
            ? Colors.yellow.withValues(alpha: 0.2)
            : Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: isCurrentTurn
            ? Border.all(color: Colors.yellow, width: 2)
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Player name and status
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!connected)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.wifi_off, size: 12, color: Colors.red),
                )
              else
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: teamColor,
                    shape: BoxShape.circle,
                  ),
                ),
              Text(
                name,
                style: TextStyle(
                  color: connected ? Colors.white : Colors.grey,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              if (hasLargeTichu) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'GT',
                    style: TextStyle(color: Colors.white, fontSize: 8),
                  ),
                ),
              ] else if (hasSmallTichu) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'T',
                    style: TextStyle(color: Colors.white, fontSize: 8),
                  ),
                ),
              ],
              if (hasFinished && finishPosition > 0) ...[
                const SizedBox(width: 4),
                Text(
                  '#$finishPosition',
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          // Cards or request button
          if (hasFinished && cardCount == 0)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                '완료',
                style: TextStyle(color: Colors.white54, fontSize: 10),
              ),
            )
          else if (canSeeCards && cards.isNotEmpty)
            vertical
                ? _buildRotatedCards(cards, isLeft: isLeft)
                : _buildHorizontalCards(cards)
          else
            _buildCardRequestArea(game, playerId, cardCount, isPending, vertical),
        ],
      ),
    );
  }

  Widget _buildRotatedCards(List cards, {bool isLeft = true}) {
    const cardWidth = 30.0;
    const cardHeight = 45.0;
    const overlap = 20.0; // 덜 겹치게

    final totalHeight = cardHeight + (cards.length - 1) * overlap;
    // 좌측: 90도 (pi/2), 우측: 270도 (3*pi/2 = -pi/2)
    final angle = isLeft ? 1.5708 : -1.5708;

    return SizedBox(
      width: cardHeight + 4, // 회전 후 잘림 방지
      height: totalHeight.clamp(50.0, 300.0),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < cards.length; i++)
            Positioned(
              top: i * overlap,
              left: 0,
              child: SizedBox(
                width: cardHeight,
                height: cardHeight,
                child: Center(
                  child: Transform.rotate(
                    angle: angle,
                    child: SizedBox(
                      width: cardWidth,
                      height: cardHeight,
                      child: PlayingCard(
                        cardId: cards[i].toString(),
                        width: cardWidth,
                        height: cardHeight,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCardRequestArea(GameService game, String playerId, int cardCount, bool isPending, bool vertical) {
    if (isPending) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.orange,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '요청중... ($cardCount장)',
              style: const TextStyle(color: Colors.orange, fontSize: 10),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () => game.requestCardView(playerId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.withValues(alpha: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.visibility, color: Colors.blue, size: 20),
            const SizedBox(height: 2),
            Text(
              '패 보기 요청 ($cardCount장)',
              style: const TextStyle(color: Colors.blue, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHorizontalCards(List cards) {
    const cardWidth = 30.0;
    const cardHeight = 45.0;
    const overlap = 20.0; // 약간 겹침

    final totalWidth = cardWidth + (cards.length - 1) * overlap;

    return SizedBox(
      height: cardHeight,
      width: totalWidth.clamp(50.0, 280.0),
      child: Stack(
        children: [
          for (int i = 0; i < cards.length; i++)
            Positioned(
              left: i * overlap,
              child: SizedBox(
                width: cardWidth,
                height: cardHeight,
                child: PlayingCard(
                  cardId: cards[i].toString(),
                  width: cardWidth,
                  height: cardHeight,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChatButton() {
    return GestureDetector(
      onTap: () => setState(() => _chatOpen = !_chatOpen),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _chatOpen
              ? const Color(0xFF64B5F6)
              : Colors.white.withOpacity(0.2),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.chat_bubble_outline,
          color: _chatOpen ? Colors.white : Colors.white70,
          size: 18,
        ),
      ),
    );
  }

  Widget _buildChatPanel(GameService game) {
    return Positioned(
      top: 50,
      right: 8,
      width: 280,
      height: 350,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF64B5F6),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Text(
                    '채팅',
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
            // Messages
            Expanded(
              child: ListView.builder(
                controller: _chatScrollController,
                padding: const EdgeInsets.all(8),
                itemCount: game.chatMessages.length,
                itemBuilder: (context, index) {
                  final msg = game.chatMessages[index];
                  final sender = msg['sender'] as String? ?? '';
                  final message = msg['message'] as String? ?? '';
                  final isMe = sender == game.playerName;
                  final isBlocked = game.isBlocked(sender);

                  if (isBlocked) return const SizedBox.shrink();

                  return _buildChatBubble(sender, message, isMe);
                },
              ),
            ),
            // Input
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey.withOpacity(0.2)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _chatController,
                      decoration: const InputDecoration(
                        hintText: '메시지 입력...',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12),
                      ),
                      style: const TextStyle(fontSize: 14),
                      onSubmitted: (_) => _sendChatMessage(game),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _sendChatMessage(game),
                    icon: const Icon(Icons.send, color: Color(0xFF64B5F6)),
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
              child: Text(
                sender.isNotEmpty ? sender[0] : '?',
                style: const TextStyle(fontSize: 12, color: Color(0xFF5A4038)),
              ),
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
                    child: Text(
                      sender,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF8A8A8A)),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isMe ? const Color(0xFF64B5F6) : const Color(0xFFF0F0F0),
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

  void _sendChatMessage(GameService game) {
    final message = _chatController.text.trim();
    if (message.isEmpty) return;
    game.sendChatMessage(message);
    _chatController.clear();
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildTrickArea(List currentTrick) {
    if (currentTrick.isEmpty) {
      return const Center(
        child: Text(
          '새 트릭 시작',
          style: TextStyle(color: Colors.white38, fontSize: 14),
        ),
      );
    }

    // Show only the latest play (same as game screen)
    final lastPlay = currentTrick.last;
    final playerName = lastPlay['playerName'] ?? '';
    final cards = (lastPlay['cards'] as List?) ?? [];
    final combo = lastPlay['combo'] ?? '';

    return Center(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              playerName,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: cards.map((cardId) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: SizedBox(
                    width: 40,
                    height: 60,
                    child: PlayingCard(
                      cardId: cardId.toString(),
                      width: 40,
                      height: 60,
                    ),
                  ),
                );
              }).toList(),
            ),
            if (combo.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  combo,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 9,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
