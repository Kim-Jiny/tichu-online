import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/game_service.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../widgets/playing_card.dart';
import 'lobby_screen.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final Set<String> _selectedCards = {};

  void _toggleCard(String cardId) {
    setState(() {
      if (_selectedCards.contains(cardId)) {
        _selectedCards.remove(cardId);
      } else {
        _selectedCards.add(cardId);
      }
    });
  }

  void _playCards() {
    if (_selectedCards.isEmpty) return;
    context.read<GameService>().playCards(_selectedCards.toList());
    setState(() => _selectedCards.clear());
  }

  void _passTurn() {
    context.read<GameService>().passTurn();
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
              Color(0xFFF8F4F6),
              Color(0xFFEDE6F0),
              Color(0xFFE0ECF6),
            ],
          ),
        ),
        child: SafeArea(
          child: Consumer<GameService>(
            builder: (context, game, _) {
              final state = game.gameState;
              if (state == null) {
                return const Center(child: CircularProgressIndicator());
              }

              return Stack(
                children: [
                  Column(
                    children: [
                      // Top area - partner
                      _buildPartnerArea(state),

                      // Middle area - opponents + center
                      Expanded(
                        child: _buildMiddleArea(state, game),
                      ),

                      // Bottom area - my hand
                      _buildBottomArea(state, game),
                    ],
                  ),

                  // Dialogs/Panels
                  if (state.phase == 'large_tichu_phase' &&
                      !state.largeTichuResponded)
                    _buildLargeTichuDialog(game),

                  if (state.phase == 'card_exchange' && !state.exchangeDone)
                    _buildExchangeDialog(state, game),

                  if (state.dragonPending) _buildDragonDialog(game),

                  if (state.phase == 'round_end' || state.phase == 'game_end')
                    _buildRoundEndDialog(state, game),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPartnerArea(GameStateData state) {
    final partner =
        state.players.where((p) => p.position == 'partner').firstOrNull;

    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Text(
            partner?.name ?? '파트너',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF5A4038),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _getPlayerInfo(partner),
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF8A7A72),
            ),
          ),
          const SizedBox(height: 8),
          // Card backs
          SizedBox(
            height: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                partner?.cardCount ?? 0,
                (i) => Transform.translate(
                  offset: Offset(-8.0 * i, 0),
                  child: const PlayingCard(
                    cardId: '',
                    isFaceUp: false,
                    width: 28,
                    height: 40,
                    isInteractive: false,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiddleArea(GameStateData state, GameService game) {
    final left = state.players.where((p) => p.position == 'left').firstOrNull;
    final right =
        state.players.where((p) => p.position == 'right').firstOrNull;

    return Row(
      children: [
        // Left player
        SizedBox(
          width: 70,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                left?.name ?? '좌측',
                style: const TextStyle(fontSize: 12, color: Color(0xFF5A4038)),
              ),
              Text(
                _getPlayerInfo(left),
                style: const TextStyle(fontSize: 10, color: Color(0xFF8A7A72)),
              ),
            ],
          ),
        ),

        // Center area
        Expanded(
          child: _buildCenterArea(state, game),
        ),

        // Right player
        SizedBox(
          width: 70,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                right?.name ?? '우측',
                style: const TextStyle(fontSize: 12, color: Color(0xFF5A4038)),
              ),
              Text(
                _getPlayerInfo(right),
                style: const TextStyle(fontSize: 10, color: Color(0xFF8A7A72)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCenterArea(GameStateData state, GameService game) {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // Phase & Turn info
          Text(
            _getPhaseName(state.phase),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF5A4038),
            ),
          ),
          if (state.phase == 'playing') ...[
            const SizedBox(height: 4),
            Text(
              state.isMyTurn ? '내 턴!' : '${_getCurrentPlayerName(state)}의 턴',
              style: TextStyle(
                fontSize: 12,
                color:
                    state.isMyTurn ? const Color(0xFFE6A800) : const Color(0xFF8A7A72),
                fontWeight: state.isMyTurn ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],

          // Call rank display
          if (state.callRank != null && state.callRank!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '콜: ${state.callRank}',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFFCC6666),
              ),
            ),
          ],

          const SizedBox(height: 8),

          // Trick display
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: state.currentTrick.map((play) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 60,
                          child: Text(
                            '${play.playerName}:',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF6A5A52),
                            ),
                          ),
                        ),
                        ...play.cards.map((cardId) => Padding(
                              padding: const EdgeInsets.only(left: 2),
                              child: PlayingCard(
                                cardId: cardId,
                                width: 36,
                                height: 50,
                                isInteractive: false,
                              ),
                            )),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // Score display
          Text(
            '팀A: ${state.totalScores['teamA']} | 팀B: ${state.totalScores['teamB']}',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF6A5A52),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomArea(GameStateData state, GameService game) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          // My name
          Text(
            game.playerName,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF5A4038),
            ),
          ),
          const SizedBox(height: 8),

          // My hand
          SizedBox(
            height: 100,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: state.myCards.map((cardId) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: PlayingCard(
                      cardId: cardId,
                      isSelected: _selectedCards.contains(cardId),
                      onTap: () => _toggleCard(cardId),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (state.phase == 'playing' && state.isMyTurn) ...[
                ElevatedButton(
                  onPressed: _selectedCards.isNotEmpty ? _playCards : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC7E6D0),
                    foregroundColor: const Color(0xFF3A5A40),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('내기'),
                ),
                const SizedBox(width: 12),
                if (state.currentTrick.isNotEmpty)
                  ElevatedButton(
                    onPressed: _passTurn,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE8E0DC),
                      foregroundColor: const Color(0xFF6A5A52),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text('패스'),
                  ),
              ],
              if (state.canDeclareSmallTichu) ...[
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () => game.declareSmallTichu(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFE4B5),
                    foregroundColor: const Color(0xFF8B6914),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('스몰티츄'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLargeTichuDialog(GameService game) {
    return _buildDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '라지티츄를 선언하시겠습니까?',
            style: TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () => game.declareLargeTichu(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                ),
                child: const Text('선언!'),
              ),
              const SizedBox(width: 16),
              OutlinedButton(
                onPressed: () => game.passLargeTichu(),
                child: const Text('패스'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExchangeDialog(GameStateData state, GameService game) {
    return _buildDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '3장의 카드를 선택하여 교환하세요\n(좌측, 파트너, 우측 순서)',
            style: TextStyle(fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            '선택: ${_selectedCards.length}/3',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _selectedCards.length == 3
                ? () {
                    final cards = _selectedCards.toList();
                    game.exchangeCards(cards[0], cards[1], cards[2]);
                    setState(() => _selectedCards.clear());
                  }
                : null,
            child: const Text('카드 교환'),
          ),
        ],
      ),
    );
  }

  Widget _buildDragonDialog(GameService game) {
    return _buildDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '용 트릭을 누구에게 주시겠습니까?',
            style: TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () => game.dragonGive('left'),
                child: const Text('좌측 상대'),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: () => game.dragonGive('right'),
                child: const Text('우측 상대'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRoundEndDialog(GameStateData state, GameService game) {
    final isGameEnd = state.phase == 'game_end';
    String title = isGameEnd ? '게임 종료!' : '라운드 종료!';

    if (isGameEnd) {
      final teamA = state.totalScores['teamA'] ?? 0;
      final teamB = state.totalScores['teamB'] ?? 0;
      title = teamA > teamB ? '팀A 승리!' : '팀B 승리!';
    }

    return _buildDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          if (state.lastRoundScores.isNotEmpty)
            Text(
              '이번 라운드: 팀A ${state.lastRoundScores['teamA']} | 팀B ${state.lastRoundScores['teamB']}',
              style: const TextStyle(fontSize: 14),
            ),
          const SizedBox(height: 8),
          Text(
            '총점: 팀A ${state.totalScores['teamA']} | 팀B ${state.totalScores['teamB']}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              if (isGameEnd) {
                game.leaveRoom();
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LobbyScreen()),
                );
              } else {
                game.nextRound();
              }
            },
            child: Text(isGameEnd ? '로비로 돌아가기' : '다음 라운드'),
          ),
        ],
      ),
    );
  }

  Widget _buildDialog({required Widget child}) {
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
          child: child,
        ),
      ),
    );
  }

  String _getPlayerInfo(Player? player) {
    if (player == null) return '';
    if (player.hasFinished) return '${player.finishPosition}등!';

    String info = '${player.cardCount}장';
    if (player.hasLargeTichu) info += ' [LT]';
    else if (player.hasSmallTichu) info += ' [ST]';
    return info;
  }

  String _getPhaseName(String phase) {
    switch (phase) {
      case 'large_tichu_phase':
        return '라지티츄 선언';
      case 'dealing_remaining_6':
        return '카드 분배 중';
      case 'card_exchange':
        return '카드 교환';
      case 'playing':
        return '게임 진행 중';
      case 'round_end':
        return '라운드 종료';
      case 'game_end':
        return '게임 종료';
      default:
        return phase;
    }
  }

  String _getCurrentPlayerName(GameStateData state) {
    if (state.currentPlayer == null) return '';
    final player =
        state.players.where((p) => p.id == state.currentPlayer).firstOrNull;
    return player?.name ?? '';
  }
}
