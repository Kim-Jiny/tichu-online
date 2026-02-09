import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/game_service.dart';
import '../services/network_service.dart';
import '../models/room.dart';
import 'game_screen.dart';
import 'spectator_screen.dart';
import 'login_screen.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  bool _inRoom = false;
  bool _navigatingToGame = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final game = context.read<GameService>();
      game.requestRoomList();
      game.requestSpectatableRooms();
    });
  }

  void _showComingSoonDialog(String feature) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(feature),
        content: const Text('준비 중입니다!'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  void _showProfileDialog() {
    final game = context.read<GameService>();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.person, color: Color(0xFF64B5F6)),
            const SizedBox(width: 8),
            Text(game.playerName),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _logout();
                },
                icon: const Icon(Icons.logout),
                label: const Text('로그아웃'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE0E0E0),
                  foregroundColor: const Color(0xFF5A4038),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _showDeleteAccountDialog();
                },
                icon: const Icon(Icons.delete_forever),
                label: const Text('회원탈퇴'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFCDD2),
                  foregroundColor: const Color(0xFFC62828),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  void _logout() {
    final network = context.read<NetworkService>();
    final game = context.read<GameService>();
    network.disconnect();
    game.reset();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('회원탈퇴'),
        content: const Text('정말 탈퇴하시겠습니까?\n모든 데이터가 삭제됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteAccount();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
              foregroundColor: Colors.white,
            ),
            child: const Text('탈퇴'),
          ),
        ],
      ),
    );
  }

  void _deleteAccount() {
    final game = context.read<GameService>();
    game.deleteAccount();
    _logout();
  }

  Widget _buildIconButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }

  void _showCreateRoomDialog() {
    final controller = TextEditingController();
    final passwordController = TextEditingController();
    bool isPrivate = false;
    bool isRanked = false;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('방 만들기'),
        content: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    hintText: '방 이름',
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('비공개'),
                    const Spacer(),
                    Switch(
                      value: isPrivate,
                      onChanged: isRanked
                          ? null
                          : (v) => setState(() => isPrivate = v),
                    ),
                  ],
                ),
                if (isPrivate)
                  TextField(
                    controller: passwordController,
                    decoration: const InputDecoration(
                      hintText: '비밀번호 (4자 이상)',
                    ),
                    obscureText: true,
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('랭크전'),
                    const Spacer(),
                    Switch(
                      value: isRanked,
                      onChanged: (v) => setState(() {
                        isRanked = v;
                        if (isRanked) {
                          isPrivate = false;
                          passwordController.clear();
                        }
                      }),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = controller.text.trim();
              final password = passwordController.text.trim();
              if (name.isNotEmpty) {
                if (isPrivate && password.length < 4) {
                  return;
                }
                context
                    .read<GameService>()
                    .createRoom(
                      name,
                      password: isPrivate ? password : '',
                      isRanked: isRanked,
                    );
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
              // Sync local room flag with server state
              if (game.currentRoomId.isEmpty && _inRoom) {
                _inRoom = false;
              }

              // Check if spectating
              if (game.isSpectator && game.spectatorGameState != null) {
                if (!_navigatingToGame) {
                  _navigatingToGame = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const SpectatorScreen()),
                    );
                  });
                }
              }

              // Check if game started
              if (game.gameState != null &&
                  game.gameState!.phase.isNotEmpty &&
                  game.gameState!.phase != 'waiting') {
                if (!_navigatingToGame) {
                  _navigatingToGame = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const GameScreen()),
                    );
                  });
                }
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
        // Top bar with menu icons
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(18),
          ),
          margin: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Text(
                '게임 라운지',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF5A4038),
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  _buildIconButton(
                    icon: Icons.store,
                    color: const Color(0xFFFFB74D),
                    onTap: () => _showComingSoonDialog('상점'),
                  ),
                  const SizedBox(width: 8),
                  _buildIconButton(
                    icon: Icons.leaderboard,
                    color: const Color(0xFF81C784),
                    onTap: () => _showComingSoonDialog('랭킹'),
                  ),
                  const SizedBox(width: 8),
                  _buildIconButton(
                    icon: Icons.person,
                    color: const Color(0xFF64B5F6),
                    onTap: _showProfileDialog,
                  ),
                ],
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
                      '게임 방 리스트',
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFF8A7A72),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () {
                        game.requestRoomList();
                      },
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
                      '새 방 만들기',
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

  // removed separate spectate list; in-progress rooms are shown inline

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
    final isInProgress = room.gameInProgress;
    return Material(
      color: isInProgress ? const Color(0xFFE8E0F8) : const Color(0xFFFAF6F4),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () {
          if (isInProgress) {
            context.read<GameService>().spectateRoom(room.id);
            return;
          }
          if (room.isPrivate) {
            _showJoinPrivateRoomDialog(room);
            return;
          }
          context.read<GameService>().joinRoom(room.id);
          setState(() => _inRoom = true);
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isInProgress ? const Color(0xFFD0C8E8) : const Color(0xFFDDD0CC),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${room.isPrivate ? '🔒 ' : ''}${room.isRanked ? '🏆 ' : ''}${room.name}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF5A4038),
                  ),
                ),
              ),
              if (isInProgress)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD8CCF6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.visibility, size: 14, color: Color(0xFF4A4080)),
                      const SizedBox(width: 4),
                      Text(
                        '게임중 ${room.spectatorCount}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF4A4080),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isInProgress ? const Color(0xFFEDE6FF) : const Color(0xFFE8E0DC),
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

  void _showJoinPrivateRoomDialog(Room room) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('비공개 방 입장'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '비밀번호',
          ),
          obscureText: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              final password = controller.text.trim();
              if (password.isEmpty) return;
              context.read<GameService>().joinRoom(room.id, password: password);
              Navigator.pop(context);
              setState(() => _inRoom = true);
            },
            child: const Text('입장'),
          ),
        ],
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
                if (game.isRankedRoom) ...[
                  // Ranked room: simple 4-player waiting room
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('🏆', style: TextStyle(fontSize: 16)),
                        SizedBox(width: 6),
                        Text(
                          '랭크전 - 팀 랜덤 배정',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFE65100),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (int i = 0; i < 4; i++) ...[
                    _buildPlayerSlot(
                      game.roomPlayers.length > i ? game.roomPlayers[i].name : null,
                      index: i + 1,
                    ),
                    if (i < 3) const SizedBox(height: 10),
                  ],
                ] else ...[
                  // Normal room: Team A and Team B
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
                ],
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

  Widget _buildPlayerSlot(String? playerName, {int? index}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF6F4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDD0CC)),
      ),
      child: Row(
        children: [
          if (index != null) ...[
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: playerName != null
                    ? const Color(0xFFE8E0DC)
                    : const Color(0xFFF0EAE8),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$index',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: playerName != null
                        ? const Color(0xFF6A5A52)
                        : const Color(0xFFAA9A92),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              playerName ?? '[대기 중...]',
              style: TextStyle(
                fontSize: 16,
                color: playerName != null
                    ? const Color(0xFF5A4038)
                    : const Color(0xFFAA9A92),
              ),
              textAlign: index != null ? TextAlign.left : TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
