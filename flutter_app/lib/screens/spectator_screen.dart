import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/game_service.dart';
import '../widgets/playing_card.dart';
import 'lobby_screen.dart';

class SpectatorScreen extends StatefulWidget {
  const SpectatorScreen({super.key});

  @override
  State<SpectatorScreen> createState() => _SpectatorScreenState();
}

class _SpectatorScreenState extends State<SpectatorScreen> {
  bool _isLeaving = false;

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
    return Scaffold(
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
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                );
              }

              return _buildSpectatorView(context, game, state);
            },
          ),
        ),
      ),
    );
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

    return Column(
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

  Widget _buildTrickArea(List currentTrick) {
    if (currentTrick.isEmpty) {
      return const Center(
        child: Text(
          '새 트릭 시작',
          style: TextStyle(color: Colors.white38, fontSize: 14),
        ),
      );
    }

    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: currentTrick.map((play) {
          final playerName = play['playerName'] ?? '';
          final cards = (play['cards'] as List?) ?? [];
          final combo = play['combo'] ?? '';

          return Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  playerName,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: cards.map((cardId) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: SizedBox(
                        width: 36,
                        height: 54,
                        child: PlayingCard(
                          cardId: cardId.toString(),
                          width: 36,
                          height: 54,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                if (combo.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      combo,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 8,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
