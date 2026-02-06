import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/game_service.dart';
import '../models/room.dart';
import 'game_screen.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  bool _inRoom = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GameService>().requestRoomList();
    });
  }

  void _showCreateRoomDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('방 만들기'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '방 이름',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                context.read<GameService>().createRoom(name);
                Navigator.pop(context);
                setState(() => _inRoom = true);
              }
            },
            child: const Text('만들기'),
          ),
        ],
      ),
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
              Color(0xFFF8F4F6),
              Color(0xFFF0E8F0),
              Color(0xFFE8F0F8),
            ],
          ),
        ),
        child: SafeArea(
          child: Consumer<GameService>(
            builder: (context, game, _) {
              // Check if game started
              if (game.gameState != null &&
                  game.gameState!.phase.isNotEmpty &&
                  game.gameState!.phase != 'waiting') {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const GameScreen()),
                  );
                });
              }

              // Show room or lobby based on state
              if (game.currentRoomId.isNotEmpty || _inRoom) {
                _inRoom = true;
                return _buildRoomView(game);
              }
              return _buildLobbyView(game);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLobbyView(GameService game) {
    return Column(
      children: [
        // Top bar
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.95),
            borderRadius: BorderRadius.circular(18),
          ),
          margin: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Text(
                '티츄 라운지',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF5A4038),
                ),
              ),
              const Spacer(),
              Text(
                game.playerName,
                style: const TextStyle(
                  fontSize: 16,
                  color: Color(0xFF8A7A72),
                ),
              ),
            ],
          ),
        ),

        // Room list
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.95),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFD9CCC8).withOpacity(0.6),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '지금 열려있는 방',
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFF8A7A72),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => game.requestRoomList(),
                      icon: const Icon(Icons.refresh),
                      color: const Color(0xFF8A7A72),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: game.roomList.isEmpty
                      ? _buildEmptyRoomList()
                      : _buildRoomList(game.roomList),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _showCreateRoomDialog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC7E6D0),
                      foregroundColor: const Color(0xFF3A5A40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      '✨ 새 방 만들기',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildEmptyRoomList() {
    return const Center(
      child: Text(
        '방이 없어요!\n지금 바로 만들어볼까요?',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 16,
          color: Color(0xFF9A8E8A),
        ),
      ),
    );
  }

  Widget _buildRoomList(List<Room> rooms) {
    return ListView.separated(
      itemCount: rooms.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final room = rooms[index];
        return _buildRoomItem(room);
      },
    );
  }

  Widget _buildRoomItem(Room room) {
    return Material(
      color: const Color(0xFFFAF6F4),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () {
          context.read<GameService>().joinRoom(room.id);
          setState(() => _inRoom = true);
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFDDD0CC),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  room.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF5A4038),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8E0DC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${room.playerCount}/4',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF6A5A52),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoomView(GameService game) {
    return Column(
      children: [
        // Top bar
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.95),
            borderRadius: BorderRadius.circular(18),
          ),
          margin: const EdgeInsets.all(16),
          child: Row(
            children: [
              IconButton(
                onPressed: () {
                  game.leaveRoom();
                  setState(() => _inRoom = false);
                },
                icon: const Icon(Icons.arrow_back),
                color: const Color(0xFF8A7A72),
              ),
              Expanded(
                child: Text(
                  game.currentRoomName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5A4038),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),

        // Player slots
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.95),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFD9CCC8).withOpacity(0.6),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                const Text(
                  'TEAM A',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF6A9BD1),
                  ),
                ),
                const SizedBox(height: 8),
                _buildPlayerSlot(game.roomPlayers.length > 0
                    ? game.roomPlayers[0].name
                    : null),
                const SizedBox(height: 8),
                _buildPlayerSlot(game.roomPlayers.length > 2
                    ? game.roomPlayers[2].name
                    : null),
                const SizedBox(height: 24),
                const Text(
                  'TEAM B',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFF5B8C0),
                  ),
                ),
                const SizedBox(height: 8),
                _buildPlayerSlot(game.roomPlayers.length > 1
                    ? game.roomPlayers[1].name
                    : null),
                const SizedBox(height: 8),
                _buildPlayerSlot(game.roomPlayers.length > 3
                    ? game.roomPlayers[3].name
                    : null),
                const Spacer(),
                if (game.isHost && game.roomPlayers.length >= 4) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => game.startGame(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDEDBFA),
                        foregroundColor: const Color(0xFF4A4080),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        '🎮 게임 시작',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: () {
                      game.leaveRoom();
                      setState(() => _inRoom = false);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFCC6666),
                      side: const BorderSide(color: Color(0xFFCC6666)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: const Text(
                      '🚪 나가기',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildPlayerSlot(String? playerName) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF6F4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDD0CC)),
      ),
      child: Text(
        playerName ?? '[대기 중...]',
        style: TextStyle(
          fontSize: 16,
          color: playerName != null
              ? const Color(0xFF5A4038)
              : const Color(0xFFAA9A92),
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
