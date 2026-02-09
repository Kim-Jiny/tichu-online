import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/game_service.dart';
import '../services/network_service.dart';
import '../models/player.dart';
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

  // 채팅
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final game = context.read<GameService>();
      game.requestRoomList();
      game.requestSpectatableRooms();
      game.requestBlockedUsers();
    });
  }

  @override
  void dispose() {
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
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

  void _showInquiryDialog() {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    String selectedCategory = 'bug';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.help_outline, color: Color(0xFFBA68C8)),
              SizedBox(width: 8),
              Text('문의하기'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('카테고리', style: TextStyle(fontSize: 13, color: Color(0xFF8A8A8A))),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFDDD0CC)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedCategory,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(value: 'bug', child: Text('버그 신고')),
                        DropdownMenuItem(value: 'suggestion', child: Text('건의사항')),
                        DropdownMenuItem(value: 'other', child: Text('기타')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => selectedCategory = v);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('제목', style: TextStyle(fontSize: 13, color: Color(0xFF8A8A8A))),
                const SizedBox(height: 4),
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(
                    hintText: '제목을 입력해주세요',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('내용', style: TextStyle(fontSize: 13, color: Color(0xFF8A8A8A))),
                const SizedBox(height: 4),
                TextField(
                  controller: contentController,
                  maxLines: 5,
                  decoration: InputDecoration(
                    hintText: '내용을 입력해주세요',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () {
                final title = titleController.text.trim();
                final content = contentController.text.trim();
                if (title.isEmpty || content.isEmpty) return;
                final game = this.context.read<GameService>();
                game.submitInquiry(selectedCategory, title, content);
                Navigator.pop(context);
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(content: Text('문의가 접수되었습니다')),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFBA68C8),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('제출'),
            ),
          ],
        ),
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

  void _logout() async {
    final network = context.read<NetworkService>();
    final game = context.read<GameService>();
    network.disconnect();
    game.reset();
    // Clear saved credentials
    await LoginScreen.clearSavedCredentials();
    if (!mounted) return;
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

  String _generateRandomRoomName() {
    final adjectives = ['즐거운', '신나는', '열정의', '화끈한', '행운의', '전설의', '최강', '무적'];
    final nouns = ['티츄방', '카드판', '승부', '한판', '게임', '대결', '도전', '파티'];
    final random = DateTime.now().millisecondsSinceEpoch;
    final adj = adjectives[random % adjectives.length];
    final noun = nouns[(random ~/ 8) % nouns.length];
    return '$adj $noun';
  }

  void _showCreateRoomDialog() {
    final randomName = _generateRandomRoomName();
    final controller = TextEditingController();
    final passwordController = TextEditingController();
    bool isPrivate = false;
    bool isRanked = false;
    String? errorText;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.home_filled, color: Color(0xFF6A5A52)),
            SizedBox(width: 8),
            Text('방 만들기'),
          ],
        ),
        content: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: randomName,
                    filled: true,
                    fillColor: const Color(0xFFF7F2F0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE0D6D1)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE0D6D1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFB9A8A1)),
                    ),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('비공개', style: TextStyle(fontWeight: FontWeight.w600)),
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
                    decoration: InputDecoration(
                      hintText: '비밀번호 (4자 이상)',
                      filled: true,
                      fillColor: const Color(0xFFF7F2F0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE0D6D1)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE0D6D1)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFB9A8A1)),
                      ),
                    ),
                    obscureText: true,
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('랭크전', style: TextStyle(fontWeight: FontWeight.w600)),
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
                if (errorText != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      errorText!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFCC6666),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
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
              final name = controller.text.trim().isEmpty
                  ? randomName
                  : controller.text.trim();
              final password = passwordController.text.trim();
              if (name.isEmpty) {
                setState(() => errorText = '방 이름을 입력해줘.');
                return;
              }
              if (isPrivate && password.length < 4) {
                setState(() => errorText = '비밀번호는 4자 이상이야.');
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
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC7E6D0),
              foregroundColor: const Color(0xFF3A5A40),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
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
                    icon: Icons.help_outline,
                    color: const Color(0xFFBA68C8),
                    onTap: _showInquiryDialog,
                  ),
                  const SizedBox(width: 8),
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
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Column(
        children: [
          // Top bar with player count
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    game.currentRoomName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF5A4038),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Player count badge (non-null count)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: game.playerCount >= 4
                        ? const Color(0xFFE8F5E9)
                        : const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${game.playerCount}/4',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: game.playerCount >= 4
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFFFF9800),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Error message banner
          if (game.errorMessage != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Color(0xFFC62828), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      game.errorMessage!,
                      style: const TextStyle(color: Color(0xFFC62828), fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

          // Scrollable content area
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  // Player slots section
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFD9CCC8).withOpacity(0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        if (game.isRankedRoom) ...[
                          // Ranked room badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF3E0),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('🏆', style: TextStyle(fontSize: 14)),
                                SizedBox(width: 6),
                                Text(
                                  '랭크전 - 팀 랜덤 배정',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFE65100),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          for (int i = 0; i < 4; i++) ...[
                            _buildPlayerSlot(
                              game.roomPlayers[i]?.name,
                              index: i + 1,
                            ),
                            if (i < 3) const SizedBox(height: 8),
                          ],
                        ] else ...[
                          // Normal room: Team A and Team B side by side
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Team A (slots 0, 2)
                              Expanded(
                                child: Column(
                                  children: [
                                    const Text(
                                      'TEAM A',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF6A9BD1),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    _buildClickablePlayerSlot(
                                      game.roomPlayers[0],
                                      slotIndex: 0,
                                      game: game,
                                    ),
                                    const SizedBox(height: 6),
                                    _buildClickablePlayerSlot(
                                      game.roomPlayers[2],
                                      slotIndex: 2,
                                      game: game,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Team B (slots 1, 3)
                              Expanded(
                                child: Column(
                                  children: [
                                    const Text(
                                      'TEAM B',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFF5B8C0),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    _buildClickablePlayerSlot(
                                      game.roomPlayers[1],
                                      slotIndex: 1,
                                      game: game,
                                    ),
                                    const SizedBox(height: 6),
                                    _buildClickablePlayerSlot(
                                      game.roomPlayers[3],
                                      slotIndex: 3,
                                      game: game,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                        // Start button inside player section
                        if (game.isHost && game.playerCount >= 4) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              onPressed: () => game.startGame(),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFDEDBFA),
                                foregroundColor: const Color(0xFF4A4080),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                '🎮 게임 시작',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Chat section with fixed height
                  Container(
                    height: 280,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFD9CCC8).withOpacity(0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: _buildRoomChat(game),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomChat(GameService game) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F6F4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0D8D4)),
      ),
      child: Column(
        children: [
          // 채팅 헤더
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFE8E0DC),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(11),
                topRight: Radius.circular(11),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.chat_bubble_outline, size: 16, color: Color(0xFF6A5A52)),
                SizedBox(width: 6),
                Text(
                  '채팅',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF6A5A52),
                  ),
                ),
              ],
            ),
          ),
          // 메시지 목록
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
                final isBlockedUser = game.isBlocked(sender);

                if (isBlockedUser) return const SizedBox.shrink();

                return _buildChatMessage(sender, message, isMe, game);
              },
            ),
          ),
          // 입력창
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFE0D8D4))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    decoration: const InputDecoration(
                      hintText: '메시지 입력...',
                      hintStyle: TextStyle(fontSize: 13, color: Color(0xFFAA9A92)),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 13),
                    onSubmitted: (_) => _sendRoomChatMessage(game),
                  ),
                ),
                GestureDetector(
                  onTap: () => _sendRoomChatMessage(game),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF64B5F6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.send, color: Colors.white, size: 16),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatMessage(String sender, String message, bool isMe, GameService game) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: isMe ? null : () => _showUserActionSheet(sender, game),
        child: Row(
          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe) ...[
              CircleAvatar(
                radius: 12,
                backgroundColor: const Color(0xFFE0D8D4),
                child: Text(
                  sender.isNotEmpty ? sender[0] : '?',
                  style: const TextStyle(fontSize: 10, color: Color(0xFF5A4038)),
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
                        style: const TextStyle(fontSize: 10, color: Color(0xFF8A8A8A)),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isMe ? const Color(0xFF64B5F6) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: isMe ? null : Border.all(color: const Color(0xFFE0D8D4)),
                    ),
                    child: Text(
                      message,
                      style: TextStyle(
                        fontSize: 13,
                        color: isMe ? Colors.white : const Color(0xFF333333),
                      ),
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

  void _sendRoomChatMessage(GameService game) {
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

  void _showUserActionSheet(String nickname, GameService game) {
    final isBlockedUser = game.isBlocked(nickname);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              nickname,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF5A4038),
              ),
            ),
            const SizedBox(height: 20),
            _buildUserActionBtn(
              icon: Icons.person_search,
              label: '프로필 보기',
              color: const Color(0xFF64B5F6),
              onTap: () {
                Navigator.pop(ctx);
                _showUserProfileDialog(nickname, game);
              },
            ),
            const SizedBox(height: 10),
            _buildUserActionBtn(
              icon: Icons.person_add,
              label: '친구 추가',
              color: const Color(0xFF81C784),
              onTap: () {
                Navigator.pop(ctx);
                game.addFriendAction(nickname);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('친구 요청을 보냈습니다')),
                );
              },
            ),
            const SizedBox(height: 10),
            _buildUserActionBtn(
              icon: isBlockedUser ? Icons.check_circle : Icons.block,
              label: isBlockedUser ? '차단 해제' : '차단하기',
              color: isBlockedUser ? const Color(0xFF64B5F6) : const Color(0xFFFF8A65),
              onTap: () {
                Navigator.pop(ctx);
                if (isBlockedUser) {
                  game.unblockUserAction(nickname);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('차단이 해제되었습니다')),
                  );
                } else {
                  game.blockUserAction(nickname);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('차단되었습니다')),
                  );
                }
              },
            ),
            const SizedBox(height: 10),
            _buildUserActionBtn(
              icon: Icons.flag,
              label: '신고하기',
              color: const Color(0xFFE57373),
              onTap: () {
                Navigator.pop(ctx);
                _showReportUserDialog(nickname, game);
              },
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserActionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  void _showReportUserDialog(String nickname, GameService game) {
    final reasonController = TextEditingController();
    final reasons = [
      '욕설/비방',
      '도배/스팸',
      '부적절한 닉네임',
      '게임 방해',
      '기타',
    ];
    String? selectedReason;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.flag, color: Color(0xFFE57373)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$nickname 신고',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: Column(
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
                  child: const Text(
                    '신고는 운영팀이 확인합니다.\n허위 신고는 제재될 수 있어요.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF9A4A4A),
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '사유 선택',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: reasons.map((r) {
                    final isSelected = selectedReason == r;
                    return InkWell(
                      onTap: () => setState(() => selectedReason = r),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFDDECF7)
                              : const Color(0xFFF6F2F0),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF9EC5E6)
                                : const Color(0xFFE2D8D4),
                          ),
                        ),
                        child: Text(
                          r,
                          style: TextStyle(
                            fontSize: 12,
                            color: isSelected
                                ? const Color(0xFF3E6D8E)
                                : const Color(0xFF6A5A52),
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: '상세 사유를 입력해주세요 (선택)',
                    filled: true,
                    fillColor: const Color(0xFFF7F2F0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE0D6D1)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE0D6D1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFB9A8A1)),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: selectedReason == null
                    ? null
                    : () {
                        final detail = reasonController.text.trim();
                        final reason = detail.isEmpty
                            ? selectedReason!
                            : '${selectedReason!} / $detail';
                        Navigator.pop(ctx);
                        game.reportUserAction(nickname, reason);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('신고가 접수되었습니다')),
                        );
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE57373),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('신고하기'),
              ),
            ],
          );
        },
      ),
    );
  }

  // Show user profile dialog with stats
  void _showUserProfileDialog(String nickname, GameService game) {
    game.requestProfile(nickname);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Consumer<GameService>(
              builder: (ctx, game, _) {
                final profile = game.profileData;
                final isLoading = profile == null || profile['nickname'] != nickname;

                return AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  title: Row(
                    children: [
                      const Icon(Icons.person, color: Color(0xFF64B5F6)),
                      const SizedBox(width: 8),
                      Text(nickname),
                    ],
                  ),
                  content: isLoading
                      ? const SizedBox(
                          height: 100,
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : _buildProfileContent(profile, game),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('닫기'),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildProfileContent(Map<String, dynamic> data, GameService game) {
    final profile = data['profile'] as Map<String, dynamic>?;
    final nickname = data['nickname'] as String? ?? '';
    // Use live blockedUsers set for real-time updates
    final isBlockedUser = game.blockedUsers.contains(nickname);

    if (profile == null) {
      return const Text('프로필을 찾을 수 없습니다');
    }

    final totalGames = profile['totalGames'] ?? 0;
    final wins = profile['wins'] ?? 0;
    final losses = profile['losses'] ?? 0;
    final rating = profile['rating'] ?? 1000;
    final winRate = profile['winRate'] ?? 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Stats
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem('전적', '$totalGames전 ${wins}승 ${losses}패'),
                  _buildStatItem('승률', '$winRate%'),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.star, color: Color(0xFFFFB74D), size: 18),
                  const SizedBox(width: 4),
                  Text(
                    '레이팅: $rating',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF5A4038),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Block/Unblock toggle
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              if (isBlockedUser) {
                game.unblockUserAction(nickname);
              } else {
                game.blockUserAction(nickname);
              }
            },
            icon: Icon(isBlockedUser ? Icons.check_circle : Icons.block, size: 18),
            label: Text(isBlockedUser ? '차단 해제' : '차단하기'),
            style: ElevatedButton.styleFrom(
              backgroundColor: isBlockedUser ? const Color(0xFF64B5F6) : const Color(0xFFFF8A65),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF8A8A8A)),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF5A4038),
          ),
        ),
      ],
    );
  }

  Widget _buildClickablePlayerSlot(Player? player, {
    required int slotIndex,
    required GameService game,
  }) {
    // Find my current slot
    final myIndex = game.roomPlayers.indexWhere((p) => p != null && p.id == game.playerId);
    final isMySlot = myIndex == slotIndex;
    final isEmpty = player == null;
    final isBlockedPlayer = !isEmpty && !isMySlot && game.blockedUsers.contains(player.name);
    // Can only move to empty slots (no swapping)
    final canMove = !isMySlot && isEmpty && myIndex != -1;

    return GestureDetector(
      onTap: () {
        if (canMove) {
          // Move to empty slot
          game.changeTeam(slotIndex);
        } else if (!isEmpty && !isMySlot) {
          // Tapping a filled slot: show player profile
          _showUserProfileDialog(player.name, game);
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: isMySlot
              ? const Color(0xFFE8F0E8)
              : isBlockedPlayer
                  ? const Color(0xFFFAF0F0)
                  : const Color(0xFFFAF6F4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isMySlot
                ? const Color(0xFFA8D4A8)
                : isBlockedPlayer
                    ? const Color(0xFFE0B0B0)
                    : const Color(0xFFDDD0CC),
          ),
        ),
        child: Row(
          children: [
            // Blocked indicator
            if (isBlockedPlayer)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.block, size: 14, color: Color(0xFFE57373)),
              ),
            Expanded(
              child: Text(
                player?.name ?? '[빈 자리]',
                style: TextStyle(
                  fontSize: 16,
                  color: isBlockedPlayer
                      ? const Color(0xFFBB8888)
                      : player != null
                          ? const Color(0xFF5A4038)
                          : const Color(0xFFAA9A92),
                  fontWeight: isMySlot ? FontWeight.bold : FontWeight.normal,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            // Kick button: show only for host, on other players' occupied slots
            if (game.isHost && !isEmpty && !isMySlot)
              GestureDetector(
                onTap: () {
                  _showKickConfirmDialog(player.name, player.id, game);
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFCDD2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.close, size: 16, color: Color(0xFFC62828)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showKickConfirmDialog(String playerName, String playerId, GameService game) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('강퇴'),
        content: Text('$playerName 님을 강퇴하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              game.kickPlayer(playerId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
              foregroundColor: Colors.white,
            ),
            child: const Text('강퇴'),
          ),
        ],
      ),
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
