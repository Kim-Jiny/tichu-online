import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/game_service.dart';
import '../services/network_service.dart';
import '../services/session_service.dart';
import '../models/player.dart';
import '../models/room.dart';
import 'ranking_screen.dart';
import 'shop_screen.dart';
import 'settings_screen.dart';
import 'friends_screen.dart';
import '../widgets/connection_overlay.dart';
import '../services/ad_service.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  bool _inRoom = false;
  bool _wasDisconnected = false;
  NetworkService? _networkService; // C6: Cache for safe dispose

  // 채팅
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  int _lastChatMessageCount = 0;

  // 배너 광고
  BannerAd? _bannerAd;
  bool _bannerAdLoaded = false;
  BannerAd? _roomBannerAd;
  bool _roomBannerLoaded = false;

  @override
  void initState() {
    super.initState();
    _bannerAd = AdService.createBannerAd(
      AdService.lobbyBannerId,
      onAdLoaded: (_) { if (mounted) setState(() => _bannerAdLoaded = true); },
      onAdFailedToLoad: (_, _) { if (mounted) setState(() { _bannerAd = null; _bannerAdLoaded = false; }); },
    );
    _bannerAd!.load();
    _roomBannerAd = AdService.createBannerAd(
      AdService.skWaitingBannerId,
      onAdLoaded: (_) { if (mounted) setState(() => _roomBannerLoaded = true); },
      onAdFailedToLoad: (_, __) { if (mounted) setState(() { _roomBannerAd = null; _roomBannerLoaded = false; }); },
    );
    _roomBannerAd!.load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final game = context.read<GameService>();
      game.requestRoomList();
      game.requestSpectatableRooms();
      game.requestBlockedUsers();
      game.requestFriends();
      game.requestPendingFriendRequests();
      game.requestInquiries();
      _networkService = context.read<NetworkService>();
      _networkService!.addListener(_onNetworkChanged);
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
      final game = context.read<GameService>();
      if (_inRoom) {
        game.checkRoom();
      } else {
        // Reload room list after reconnection
        game.requestRoomList();
        game.requestSpectatableRooms();
      }
    }
  }

  @override
  void dispose() {
    // C6: Use cached reference instead of context.read in dispose
    _networkService?.removeListener(_onNetworkChanged);
    _chatController.dispose();
    _chatScrollController.dispose();
    _bannerAd?.dispose();
    _roomBannerAd?.dispose();
    super.dispose();
  }

  void _showRoomInviteDialog(Map<String, dynamic> invite, GameService game) {
    final fromNickname = invite['fromNickname'] as String? ?? '';
    final roomName = invite['roomName'] as String? ?? '';
    final isRanked = invite['isRanked'] == true;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.mail, color: Color(0xFF7E57C2)),
            SizedBox(width: 8),
            Text('방 초대'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$fromNickname님이 방에 초대했습니다!',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF3E5F5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  if (isRanked) const Text('🏆 ', style: TextStyle(fontSize: 14)),
                  Expanded(
                    child: Text(
                      roomName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF5A4038),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('거절'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              game.acceptInvite(invite);
              setState(() => _inRoom = true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7E57C2),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('참여'),
          ),
        ],
      ),
    );
  }

  void _showInviteFriendsDialog(GameService game) {
    game.requestFriends();
    showDialog(
      context: context,
      builder: (ctx) => Consumer<GameService>(
        builder: (ctx, game, _) {
          final onlineFriends = game.friendsData
              .where((f) => f['isOnline'] == true && f['roomId'] == null)
              .toList();
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.person_add, color: Color(0xFF7E57C2)),
                SizedBox(width: 8),
                Text('친구 초대'),
              ],
            ),
            content: onlineFriends.isEmpty
                ? const SizedBox(
                    height: 60,
                    child: Center(
                      child: Text(
                        '초대 가능한 온라인 친구가 없습니다',
                        style: TextStyle(color: Color(0xFF9A8E8A)),
                      ),
                    ),
                  )
                : SizedBox(
                    width: double.maxFinite,
                    height: 250,
                    child: ListView.separated(
                      itemCount: onlineFriends.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final friend = onlineFriends[index];
                        final nickname = friend['nickname'] as String? ?? '';
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F8E9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFC8E6C9)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xFF4CAF50),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  nickname,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF5A4038),
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  game.inviteToRoom(nickname);
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(this.context).showSnackBar(
                                    SnackBar(content: Text('$nickname님에게 초대를 보냈습니다')),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF7E57C2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    '초대',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('닫기'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSpectatorListDialog(GameService game) {
    final spectators = game.spectators;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.visibility, color: Color(0xFF4A4080)),
            SizedBox(width: 8),
            Text('관전자 목록'),
          ],
        ),
        content: spectators.isEmpty
            ? const SizedBox(
                height: 60,
                child: Center(
                  child: Text(
                    '관전 중인 사람이 없습니다',
                    style: TextStyle(color: Color(0xFF9A8E8A)),
                  ),
                ),
              )
            : SizedBox(
                width: double.maxFinite,
                height: 220,
                child: ListView.separated(
                  itemCount: spectators.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final nickname = spectators[index]['nickname'] ?? '';
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEDE7F6),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFD1C4E9)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.person, size: 16, color: Color(0xFF6A5A52)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              nickname,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF5A4038),
                              ),
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  void _showRoomSettingsDialog(GameService game) {
    final controller = TextEditingController(text: game.currentRoomName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.settings, color: Color(0xFF1E88E5)),
            SizedBox(width: 8),
            Text('방 설정'),
          ],
        ),
        content: TextField(
          controller: controller,
          maxLength: 20,
          decoration: InputDecoration(
            hintText: '방 제목을 입력하세요',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              game.changeRoomName(name);
              Navigator.pop(ctx);
            },
            child: const Text('변경'),
          ),
        ],
      ),
    );
  }

  void _showProfileDialog() {
    final game = context.read<GameService>();
    _showUserProfileDialog(game.playerName, game);
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

  String _generateRandomRoomName({String gameType = 'tichu'}) {
    final random = DateTime.now().millisecondsSinceEpoch;
    if (gameType == 'skull_king') {
      final adjectives = ['무시무시한', '전설의', '무적의', '잔혹한', '탐욕의', '최강', '폭풍의', '대담한'];
      final nouns = ['해적선', '보물섬', '항해', '약탈', '선장', '해전', '모험', '크라켄'];
      final adj = adjectives[random % adjectives.length];
      final noun = nouns[(random ~/ 8) % nouns.length];
      return '$adj $noun';
    } else {
      final adjectives = ['즐거운', '신나는', '열정의', '화끈한', '행운의', '전설의', '최강', '무적'];
      final nouns = ['티츄방', '카드판', '승부', '한판', '게임', '대결', '도전', '파티'];
      final adj = adjectives[random % adjectives.length];
      final noun = nouns[(random ~/ 8) % nouns.length];
      return '$adj $noun';
    }
  }

  void _showCreateRoomDialog() {
    String randomName = _generateRandomRoomName();
    final controller = TextEditingController();
    final passwordController = TextEditingController();
    bool isPrivate = false;
    bool isRanked = false;
    final timeLimitController = TextEditingController(text: '30');
    final targetScoreController = TextEditingController(text: '1000');
    String selectedGameType = 'tichu';
    int skMaxPlayers = 4;
    String? errorText;
    void Function(void Function())? dialogSetState;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          dialogSetState = setState;
          final themeColors = context.read<GameService>().themeGradient;
          final accent = themeColors.length > 1 ? themeColors[1] : themeColors.first;
          final fillColor = Colors.white.withValues(alpha: 0.82);

          InputDecoration fieldDecoration(
            String hintText, {
            String? suffixText,
          }) {
            return InputDecoration(
              hintText: hintText,
              suffixText: suffixText,
              filled: true,
              fillColor: fillColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: accent.withValues(alpha: 0.2)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: accent.withValues(alpha: 0.2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: accent, width: 1.4),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            );
          }

          Widget sectionTitle(String title, String subtitle) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF3E312A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF7E7069),
                  ),
                ),
              ],
            );
          }

          Widget optionCard({
            required String title,
            required String description,
            required bool value,
            required ValueChanged<bool> onChanged,
            bool enabled = true,
          }) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: enabled ? 0.72 : 0.42),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: value
                      ? accent.withValues(alpha: 0.65)
                      : const Color(0xFFE0D5D0),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: enabled
                                ? const Color(0xFF4B3C35)
                                : const Color(0xFF9A8E8A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: TextStyle(
                            fontSize: 11,
                            color: enabled
                                ? const Color(0xFF7E7069)
                                : const Color(0xFFAAA09C),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Switch(
                    value: value,
                    onChanged: enabled ? onChanged : null,
                  ),
                ],
              ),
            );
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            backgroundColor: themeColors.first.withValues(alpha: 0.94),
            contentPadding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        themeColors.first.withValues(alpha: 0.92),
                        themeColors.last.withValues(alpha: 0.76),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.28),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.add_home_work_rounded,
                              color: Color(0xFF3E312A),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '새 방 만들기',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF2F241F),
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  '방 제목과 규칙을 정하면 바로 대기실이 열립니다.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF695D57),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      sectionTitle('게임 선택', '플레이할 게임을 선택합니다.'),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'tichu', label: Text('티츄'), icon: Icon(Icons.style, size: 16)),
                            ButtonSegment(value: 'skull_king', label: Text('스컬킹'), icon: Icon(Icons.anchor, size: 16)),
                          ],
                          selected: {selectedGameType},
                          onSelectionChanged: (v) => setState(() {
                            selectedGameType = v.first;
                            randomName = _generateRandomRoomName(gameType: selectedGameType);
                            if (controller.text.isEmpty) {
                              controller.clear();
                            }
                            if (selectedGameType == 'skull_king') {
                              isRanked = false;
                            }
                          }),
                          style: SegmentedButton.styleFrom(
                            selectedBackgroundColor: accent.withValues(alpha: 0.25),
                            selectedForegroundColor: const Color(0xFF3E312A),
                          ),
                        ),
                      ),
                      if (selectedGameType == 'skull_king') ...[
                        const SizedBox(height: 12),
                        const Text('최대 인원', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                        const SizedBox(height: 8),
                        Row(
                          children: List.generate(5, (i) {
                            final n = i + 2;
                            final selected = skMaxPlayers == n;
                            return Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(right: i < 4 ? 6 : 0),
                                child: GestureDetector(
                                  onTap: () => setState(() => skMaxPlayers = n),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? accent.withValues(alpha: 0.25)
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: selected
                                            ? accent
                                            : const Color(0xFFE0D8D4),
                                        width: selected ? 1.5 : 1,
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Text(
                                          '$n명',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                                            color: selected
                                                ? const Color(0xFF3E312A)
                                                : const Color(0xFF8A7A72),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ],
                      const SizedBox(height: 16),
                      sectionTitle('기본 정보', '먼저 방 이름과 공개 여부를 정합니다.'),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Text(
                            '방 이름',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => setState(() {
                              randomName = _generateRandomRoomName(gameType: selectedGameType);
                              controller.text = randomName;
                            }),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: const Size(0, 28),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              foregroundColor: accent,
                            ),
                            icon: const Icon(Icons.casino_outlined, size: 16),
                            label: const Text('랜덤'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: controller,
                        decoration: fieldDecoration(randomName),
                      ),
                      const SizedBox(height: 12),
                      optionCard(
                        title: '비공개 방',
                        description: isRanked
                            ? '랭크전에서는 비공개 방을 만들 수 없습니다.'
                            : '초대한 사람이나 비밀번호를 아는 사람만 들어올 수 있습니다.',
                        value: isPrivate,
                        enabled: !isRanked,
                        onChanged: (v) => setState(() => isPrivate = v),
                      ),
                      if (isPrivate) ...[
                        const SizedBox(height: 10),
                        TextField(
                          controller: passwordController,
                          obscureText: true,
                          decoration: fieldDecoration('비밀번호 (4자 이상)'),
                        ),
                      ],
                      if (context.read<GameService>().authProvider != 'local') ...[
                        const SizedBox(height: 12),
                        optionCard(
                          title: '랭크전',
                          description: '점수는 1000점 고정이며 비공개 설정은 자동으로 꺼집니다.',
                          value: isRanked,
                          onChanged: (v) => setState(() {
                            isRanked = v;
                            if (isRanked) {
                              isPrivate = false;
                              passwordController.clear();
                              targetScoreController.text = '1000';
                            }
                          }),
                        ),
                      ],
                      const SizedBox(height: 16),
                      sectionTitle('게임 설정', selectedGameType == 'skull_king' ? '턴 시간을 정합니다.' : '턴 시간과 목표 점수를 정합니다.'),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '시간 제한',
                                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                                ),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: timeLimitController,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(3),
                                  ],
                                  textAlign: TextAlign.center,
                                  decoration: fieldDecoration('10~999', suffixText: '초'),
                                ),
                              ],
                            ),
                          ),
                          if (selectedGameType != 'skull_king') ...[
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '목표 점수',
                                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                                  ),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: targetScoreController,
                                    enabled: !isRanked,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(5),
                                    ],
                                    textAlign: TextAlign.center,
                                    decoration: fieldDecoration(
                                      isRanked ? '1000 (고정)' : '100~20000',
                                      suffixText: '점',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          isRanked
                              ? '랭크전은 목표 점수 1000점으로 고정됩니다.'
                              : '시간 제한은 10~999초, 목표 점수는 100~20000점까지 설정할 수 있습니다.',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF6D615B),
                          ),
                        ),
                      ),
                      if (errorText != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFECEC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFF2B3B3)),
                          ),
                          child: Text(
                            errorText!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFB54A4A),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  final name = controller.text.trim().isEmpty
                      ? randomName
                      : controller.text.trim();
                  final password = passwordController.text.trim();
                  if (name.isEmpty) {
                    dialogSetState?.call(() => errorText = '방 이름을 입력해주세요.');
                    return;
                  }
                  if (isPrivate && password.length < 4) {
                    dialogSetState?.call(() => errorText = '비밀번호는 4자 이상이어야 합니다.');
                    return;
                  }
                  final turnTimeLimit =
                      (int.tryParse(timeLimitController.text.trim()) ?? 30).clamp(10, 999);
                  final targetScore = isRanked
                      ? 1000
                      : (int.tryParse(targetScoreController.text.trim()) ?? 1000)
                          .clamp(100, 20000);
                  context.read<GameService>().createRoom(
                    name,
                    password: isPrivate ? password : '',
                    isRanked: isRanked,
                    turnTimeLimit: turnTimeLimit,
                    targetScore: targetScore,
                    gameType: selectedGameType,
                    maxPlayers: selectedGameType == 'skull_king' ? skMaxPlayers : 4,
                  );
                  Navigator.pop(context);
                  setState(() => _inRoom = true);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: const Color(0xFF2A1E18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('방 만들기'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeColors = context.watch<GameService>().themeGradient;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return ConnectionOverlay(
      child: PopScope(
        canPop: false,
        child: Scaffold(
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
              // Handle duplicate login kick
              if (game.duplicateLoginKicked) {
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  if (!mounted) return;
                  if (!game.consumeDuplicateLoginKick()) return;
                  final session = context.read<SessionService>();
                  final messenger = ScaffoldMessenger.of(context);
                  await session.logout();
                  if (!mounted) return;
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('다른 기기에서 로그인되어 로그아웃되었습니다'),
                      backgroundColor: Colors.red,
                    ),
                  );
                });
              }
              // Show room invite dialog if any
              if (game.hasRoomInvites) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  final invite = game.firstRoomInvite;
                  if (invite == null) return;
                  game.dismissInvite(0);
                  _showRoomInviteDialog(invite, game);
                });
              }

              // Sync local room flag with server state
              if (!game.hasRoom && _inRoom) {
                _inRoom = false;
              }
              if (game.isInWaitingRoom && !_inRoom) {
                _inRoom = true;
              }

              final destination = game.currentDestination;

              if (destination != AppDestination.lobby || _inRoom) {
                _inRoom = true;
                return _buildRoomView(game, isLandscape: isLandscape);
              }
              return _buildLobbyView(game, isLandscape: isLandscape);
            },
          ),
        ),
      ),
      ),
      ),
    );
  }

  Widget _buildLobbyView(GameService game, {required bool isLandscape}) {
    if (isLandscape) {
      final hasTopNotices =
          game.hasMaintenanceNotice || game.inquiryBannerMessage != null;
      final hasBanner = _bannerAd != null && _bannerAdLoaded;
      return Column(
        children: [
          _buildLobbyHeader(game, isLandscape: true),
          if (hasTopNotices)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _buildLandscapeLobbyUtilityBar(game),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _buildRoomListPanel(game),
            ),
          ),
          if (hasBanner)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Center(
                child: SizedBox(
                  height: _bannerAd!.size.height.toDouble(),
                  width: _bannerAd!.size.width.toDouble(),
                  child: AdWidget(
                    ad: _bannerAd!,
                    key: ValueKey(_bannerAd!.hashCode),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return Column(
      children: [
        _buildLobbyHeader(game, isLandscape: false),

        // Maintenance notice banner
        if (game.hasMaintenanceNotice)
          _buildMaintenanceBanner(game),
        if (game.inquiryBannerMessage != null)
          _buildInquiryBanner(game),

        // Room list or Friends panel
        Expanded(
          child: _buildRoomListPanel(game),
        ),
        if (_bannerAd != null && _bannerAdLoaded)
          SizedBox(
            height: _bannerAd!.size.height.toDouble(),
            width: _bannerAd!.size.width.toDouble(),
            child: AdWidget(ad: _bannerAd!, key: ValueKey(_bannerAd!.hashCode)),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildLandscapeLobbyUtilityBar(GameService game) {
    final hasTopNotices =
        game.hasMaintenanceNotice || game.inquiryBannerMessage != null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE9DED9)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (hasTopNotices)
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (game.hasMaintenanceNotice) _buildMaintenanceBanner(game),
                  if (game.inquiryBannerMessage != null)
                    _buildInquiryBanner(game),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLobbyHeader(GameService game, {required bool isLandscape}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isLandscape ? 14 : 16,
        vertical: isLandscape ? 12 : 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(18),
      ),
      margin: EdgeInsets.all(isLandscape ? 12 : 16),
      clipBehavior: Clip.none,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: isLandscape ? 36 : 44),
            child: Image.asset(
              'assets/logo2.png',
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: _buildLobbyActionButtons(game),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildLobbyActionButtons(GameService game) {
    return [
      _buildIconButton(
        icon: Icons.store,
        color: const Color(0xFFFFB74D),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ShopScreen()),
          );
        },
      ),
      Stack(
        children: [
          _buildIconButton(
            icon: Icons.people,
            color: const Color(0xFF7E57C2),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FriendsScreen()),
              );
            },
          ),
          if ((game.pendingFriendRequestCount + game.totalUnreadDmCount) > 0)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Color(0xFFE53935),
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  '${game.pendingFriendRequestCount + game.totalUnreadDmCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      _buildIconButton(
        icon: Icons.leaderboard,
        color: const Color(0xFF81C784),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RankingScreen()),
          );
        },
      ),
      _buildIconButton(
        icon: Icons.person,
        color: const Color(0xFF64B5F6),
        onTap: _showProfileDialog,
      ),
      _buildIconButton(
        icon: Icons.settings,
        color: const Color(0xFF9E9E9E),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          );
        },
      ),
    ];
  }

  Widget _buildMaintenanceBanner(GameService game) {
    String timeText = '';
    if (game.maintenanceStart != null && game.maintenanceEnd != null) {
      try {
        final start = DateTime.parse(game.maintenanceStart!).toLocal();
        final end = DateTime.parse(game.maintenanceEnd!).toLocal();
        String fmt(DateTime d) => '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
        timeText = '${fmt(start)} ~ ${fmt(end)}';
      } catch (_) {}
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFB74D)),
      ),
      child: Row(
        children: [
          const Icon(Icons.construction, color: Color(0xFFE65100), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  game.maintenanceMessage.isNotEmpty
                      ? game.maintenanceMessage
                      : '서버 점검 예정',
                  style: const TextStyle(
                    color: Color(0xFFE65100),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (timeText.isNotEmpty)
                  Text(
                    timeText,
                    style: const TextStyle(
                      color: Color(0xFFBF360C),
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInquiryBanner(GameService game) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF90CAF9)),
      ),
      child: Row(
        children: [
          const Icon(Icons.mark_email_read, color: Color(0xFF1E88E5), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              game.inquiryBannerMessage ?? '',
              style: const TextStyle(
                color: Color(0xFF1E88E5),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: () => game.requestInquiries(),
            child: const Icon(Icons.refresh, size: 18, color: Color(0xFF1E88E5)),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomListPanel(GameService game) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD9CCC8).withValues(alpha: 0.6),
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
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final room = rooms[index];
        return _buildRoomItem(room);
      },
    );
  }

  Widget _buildRoomItem(Room room) {
    final isInProgress = room.gameInProgress;
    final isSK = room.isSkullKing;

    // Game type colors
    final Color bgColor;
    final Color borderColor;
    final Color stripColor;
    final Color badgeBgColor;
    final Color badgeTextColor;
    final String badgeText;
    final Color nameColor;
    final Color subTextColor;

    if (isSK) {
      bgColor = isInProgress ? const Color(0xFFE0E4EF) : const Color(0xFFECEFF6);
      borderColor = isInProgress ? const Color(0xFFB0B8D0) : const Color(0xFFC0C8DD);
      stripColor = const Color(0xFF2D2D3D);
      badgeBgColor = const Color(0xFF2D2D3D);
      badgeTextColor = const Color(0xFFFFD54F);
      badgeText = '☠️ 스컬킹';
      nameColor = const Color(0xFF2D2D3D);
      subTextColor = const Color(0xFF7A7A90);
    } else {
      bgColor = isInProgress ? const Color(0xFFEDE8F8) : const Color(0xFFF6F4FA);
      borderColor = isInProgress ? const Color(0xFFC4BBE0) : const Color(0xFFD8D0E8);
      stripColor = const Color(0xFF6C63FF);
      badgeBgColor = const Color(0xFF6C63FF);
      badgeTextColor = Colors.white;
      badgeText = '티츄';
      nameColor = const Color(0xFF3A3058);
      subTextColor = const Color(0xFF8A80A0);
    }

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () {
          if (isInProgress) {
            _spectateWithPasswordCheck(room);
            return;
          }
          if (room.isRanked && context.read<GameService>().authProvider == 'local') {
            _showRankedSocialRequiredDialog();
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
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              // Left color strip
              Container(
                width: 6,
                height: 64,
                decoration: BoxDecoration(
                  color: stripColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 16, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                    color: badgeBgColor,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(badgeText, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: badgeTextColor)),
                                ),
                                Expanded(
                                  child: Text(
                                    '${room.isPrivate ? '🔒 ' : ''}${room.isRanked ? '🏆 ' : ''}${room.name}',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: nameColor,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isSK
                                  ? '${room.turnTimeLimit}초'
                                  : '${room.turnTimeLimit}초 · ${room.targetScore}점',
                              style: TextStyle(
                                fontSize: 11,
                                color: subTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
              if (isInProgress)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: isSK ? const Color(0xFFCCD0DD) : const Color(0xFFD8CCF6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.visibility, size: 14, color: isSK ? const Color(0xFF3A3A50) : const Color(0xFF6C63FF)),
                      const SizedBox(width: 4),
                      Text(
                        '게임중 ${room.spectatorCount}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isSK ? const Color(0xFF3A3A50) : const Color(0xFF6C63FF),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              if (!isInProgress)
                GestureDetector(
                  onTap: () {
                    _spectateWithPasswordCheck(room);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: isSK ? const Color(0xFFD8DAE4) : const Color(0xFFE0D8F4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.visibility,
                      size: 18,
                      color: isSK ? const Color(0xFF3A3A50) : const Color(0xFF6C63FF),
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isInProgress
                      ? (isSK ? const Color(0xFFD4D8E4) : const Color(0xFFD4CCF0))
                      : (isSK ? const Color(0xFFD8DAE4) : const Color(0xFFE0D8F4)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${room.playerCount}/${room.maxPlayers}',
                  style: TextStyle(
                    fontSize: 14,
                    color: isSK ? const Color(0xFF3A3A50) : const Color(0xFF4A4070),
                  ),
                ),
              ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRankedSocialRequiredDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.lock, color: Color(0xFFF2A65A), size: 22),
            SizedBox(width: 8),
            Text('소셜 연동 필요', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: const Text(
          '랭크전은 소셜 계정 연동이 필요합니다.\n설정 > 소셜 연동에서 Google 또는 Kakao 계정을 연동해주세요.',
          style: TextStyle(fontSize: 14, color: Color(0xFF5A4038)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  void _showJoinPrivateRoomDialog(Room room) {
    _showPasswordDialog(
      title: '비공개 방 입장',
      buttonText: '입장',
      onSubmit: (password) {
        context.read<GameService>().joinRoom(room.id, password: password);
        setState(() => _inRoom = true);
      },
    );
  }

  void _spectateWithPasswordCheck(Room room) {
    if (room.isPrivate) {
      _showPasswordDialog(
        title: '비공개 방 관전',
        buttonText: '관전',
        onSubmit: (password) {
          context.read<GameService>().spectateRoom(room.id, password: password);
        },
      );
    } else {
      context.read<GameService>().spectateRoom(room.id);
    }
  }

  void _showPasswordDialog({
    required String title,
    required String buttonText,
    required void Function(String password) onSubmit,
  }) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
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
              Navigator.pop(context);
              onSubmit(password);
            },
            child: Text(buttonText),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomView(GameService game, {required bool isLandscape}) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Column(
        children: [
          _buildRoomHeader(game, isLandscape: isLandscape),

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
            child: isLandscape
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 5,
                          child: SingleChildScrollView(
                            child: _buildRoomPlayersPanel(game),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 4,
                          child: _buildRoomChatContainer(game),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      children: [
                        _buildRoomPlayersPanel(game),
                        const SizedBox(height: 12),
                        _buildRoomChatContainer(game, height: 280),
                      ],
                    ),
                  ),
          ),
          if (_roomBannerAd != null && _roomBannerLoaded)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Center(
                child: SizedBox(
                  height: _roomBannerAd!.size.height.toDouble(),
                  width: _roomBannerAd!.size.width.toDouble(),
                  child: AdWidget(ad: _roomBannerAd!, key: ValueKey(_roomBannerAd!.hashCode)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRoomHeader(GameService game, {required bool isLandscape}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(18),
      ),
      margin: EdgeInsets.all(isLandscape ? 12 : 16),
      child: Column(
        children: [
          Row(
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
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0EBE8),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  game.currentGameType == 'skull_king'
                      ? '${game.roomTurnTimeLimit}초 · ${game.playerCount}/${game.roomMaxPlayers}명'
                      : '${game.roomTurnTimeLimit}초 · ${game.roomTargetScore}점',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8A7A72),
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: game.playerCount >= game.roomMaxPlayers
                      ? const Color(0xFFE8F5E9)
                      : const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${game.playerCount}/${game.roomMaxPlayers}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: game.playerCount >= game.roomMaxPlayers
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFFFF9800),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                GestureDetector(
                  onTap: () => _showInviteFriendsDialog(game),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3E5F5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.person_add,
                          size: 14,
                          color: Color(0xFF7E57C2),
                        ),
                        SizedBox(width: 4),
                        Text(
                          '초대',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF7E57C2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => game.switchToSpectator(),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                          '관전',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF4A4080),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    GestureDetector(
                      onTap: () => _showRoomUtilitySheet(game),
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF6F3F2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.more_horiz, size: 14, color: Color(0xFF8A7A72)),
                            SizedBox(width: 4),
                            Text(
                              '더보기',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF8A7A72),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if ((game.pendingFriendRequestCount + game.totalUnreadDmCount) > 0)
                      Positioned(
                        right: -6,
                        top: -6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Color(0xFFE53935),
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                          child: Text(
                            (game.pendingFriendRequestCount + game.totalUnreadDmCount) > 9
                                ? '9+'
                                : '${game.pendingFriendRequestCount + game.totalUnreadDmCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
                if (game.isHost)
                  GestureDetector(
                    onTap: () => _showRoomSettingsDialog(game),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE3F2FD),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.settings, size: 14, color: Color(0xFF1E88E5)),
                          SizedBox(width: 4),
                          Text(
                            '방설정',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E88E5),
                            ),
                          ),
                        ],
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

  Widget _buildRoomPlayersPanel(GameService game) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD9CCC8).withValues(alpha: 0.4),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          if (game.isRankedRoom) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🏆', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Text(
                    game.currentGameType == 'skull_king'
                        ? '스컬킹 - 랭크전'
                        : '티츄 - 랭크전',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFE65100),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            for (int i = 0; i < game.roomPlayers.length; i++) ...[
              _buildClickablePlayerSlot(
                game.roomPlayers[i],
                slotIndex: i,
                game: game,
              ),
              if (i < game.roomPlayers.length - 1) const SizedBox(height: 8),
            ],
          ] else if (game.currentGameType == 'skull_king') ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D3D),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.anchor, size: 14, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    '스컬킹 · ${game.roomMaxPlayers}인',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            for (int i = 0; i < game.roomPlayers.length; i++) ...[
              _buildClickablePlayerSlot(
                game.roomPlayers[i],
                slotIndex: i,
                game: game,
              ),
              if (i < game.roomPlayers.length - 1) const SizedBox(height: 8),
            ],
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
          const SizedBox(height: 12),
          if (game.isHost) ...[
            if (game.currentGameType == 'skull_king'
                ? game.playerCount >= 2
                : game.playerCount >= game.roomMaxPlayers)
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
                    '게임 시작',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ] else
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => game.toggleReady(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isMyReady(game)
                      ? const Color(0xFFC8E6C9)
                      : const Color(0xFFF5F5F5),
                  foregroundColor: _isMyReady(game)
                      ? const Color(0xFF2E7D32)
                      : const Color(0xFF5A4038),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  _isMyReady(game) ? '준비 완료!' : '준비',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRoomChatContainer(GameService game, {double? height}) {
    final chat = Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD9CCC8).withValues(alpha: 0.4),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: _buildRoomChat(game),
    );

    if (height != null) {
      return SizedBox(height: height, child: chat);
    }

    return chat;
  }

  Widget _buildRoomChat(GameService game) {
    if (game.chatMessages.length != _lastChatMessageCount) {
      _lastChatMessageCount = game.chatMessages.length;
      _scrollChatToBottom();
    }
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
        onTap: () {
          if (isMe) {
            _showUserProfileDialog(sender, game);
          } else {
            _showUserActionSheet(sender, game);
          }
        },
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

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.jumpTo(
          _chatScrollController.position.maxScrollExtent,
        );
      }
    });
  }

  void _sendRoomChatMessage(GameService game) {
    final message = _chatController.text.trim();
    if (message.isEmpty) return;
    game.sendChatMessage(message);
    _chatController.clear();
    _scrollChatToBottom();
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

  void _showRoomUtilitySheet(GameService game) {
    final unreadCount = game.pendingFriendRequestCount + game.totalUnreadDmCount;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD8CEC8),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '대기실 도구',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF4E342E),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '게임 준비와 직접 관련 없는 기능은 여기에서 확인할 수 있어요.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: Color(0xFF8A7A72),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3E5F5),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.forum_outlined,
                        color: Color(0xFF7E57C2),
                      ),
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: const BoxDecoration(
                            color: Color(0xFFE53935),
                            borderRadius: BorderRadius.all(Radius.circular(999)),
                          ),
                          child: Text(
                            unreadCount > 9 ? '9+' : '$unreadCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                title: const Text(
                  '친구 / DM',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF4E342E),
                  ),
                ),
                subtitle: Text(
                  unreadCount > 0
                      ? '읽지 않은 요청과 DM이 $unreadCount개 있어요.'
                      : '친구 목록과 DM 대화를 확인할 수 있어요.',
                  style: const TextStyle(
                    color: Color(0xFF8A7A72),
                  ),
                ),
                trailing: const Icon(Icons.chevron_right, color: Color(0xFF8A7A72)),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const FriendsScreen()),
                  );
                },
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F3F2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.visibility_outlined,
                    color: Color(0xFF8A7A72),
                  ),
                ),
                title: const Text(
                  '관전자 목록',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF4E342E),
                  ),
                ),
                subtitle: Text(
                  '현재 관전자 ${game.spectators.length}명을 확인할 수 있어요.',
                  style: const TextStyle(
                    color: Color(0xFF8A7A72),
                  ),
                ),
                trailing: const Icon(Icons.chevron_right, color: Color(0xFF8A7A72)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showSpectatorListDialog(game);
                },
              ),
            ],
          ),
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
                        game.reportResultSuccess = null;
                        game.reportResultMessage = null;
                        game.reportUserAction(nickname, reason);
                        // C5: Add timeout to remove listener if server never responds
                        late void Function() listener;
                        Timer? cleanupTimer;
                        listener = () {
                          if (game.reportResultMessage != null) {
                            game.removeListener(listener);
                            cleanupTimer?.cancel();
                            if (mounted) {
                              final success = game.reportResultSuccess == true;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(game.reportResultMessage!),
                                  backgroundColor: success ? null : const Color(0xFFE57373),
                                ),
                              );
                            }
                            game.reportResultSuccess = null;
                            game.reportResultMessage = null;
                          }
                        };
                        game.addListener(listener);
                        cleanupTimer = Timer(const Duration(seconds: 10), () {
                          game.removeListener(listener);
                        });
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
        String profileGameTab = 'tichu';
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Consumer<GameService>(
              builder: (ctx, game, _) {
                final profile = game.profileFor(nickname);
                final isLoading = profile == null || profile['nickname'] != nickname;

                final isMe = nickname == game.playerName;
                final isBlockedUser = game.blockedUsers.contains(nickname);
                return AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  backgroundColor: const Color(0xFFF8F4F1),
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
                                color: const Color(0xFFE8F0F7),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.person_outline,
                                color: Color(0xFF4F6B7A),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    nickname,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF3E312A),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    isMe ? '내 프로필' : '플레이어 프로필',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF84766E),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (!isMe) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (game.friends.contains(nickname))
                                _buildTitleIconButton(
                                  icon: Icons.check,
                                  color: const Color(0xFFBDBDBD),
                                  tooltip: '이미 친구',
                                  onTap: () {},
                                )
                              else if (game.sentFriendRequests.contains(nickname))
                                _buildTitleIconButton(
                                  icon: Icons.hourglass_top,
                                  color: const Color(0xFFBDBDBD),
                                  tooltip: '요청중',
                                  onTap: () {},
                                )
                              else
                                _buildTitleIconButton(
                                  icon: Icons.person_add,
                                  color: const Color(0xFF81C784),
                                  tooltip: '친구 추가',
                                  onTap: () {
                                    game.addFriendAction(nickname);
                                    Navigator.pop(ctx);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('친구 요청을 보냈습니다')),
                                    );
                                  },
                                ),
                              _buildTitleIconButton(
                                icon: isBlockedUser ? Icons.block : Icons.shield_outlined,
                                color: isBlockedUser
                                    ? const Color(0xFF64B5F6)
                                    : const Color(0xFFFF8A65),
                                tooltip: isBlockedUser ? '차단 해제' : '차단하기',
                                onTap: () {
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
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  content: isLoading
                      ? const SizedBox(
                          height: 140,
                          width: 360,
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: 420,
                            maxHeight: 560,
                          ),
                          child: SingleChildScrollView(
                            child: _buildProfileContent(
                              profile, game,
                              selectedTab: profileGameTab,
                              onTabChanged: (tab) => setDialogState(() => profileGameTab = tab),
                            ),
                          ),
                        ),
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

  Widget _buildProfileContent(Map<String, dynamic> data, GameService game, {
    required String selectedTab,
    required ValueChanged<String> onTabChanged,
  }) {
    final profile = data['profile'] as Map<String, dynamic>?;
    final nickname = data['nickname'] as String? ?? '';

    if (profile == null) {
      return const Text('프로필을 찾을 수 없습니다');
    }

    final totalGames = profile['totalGames'] ?? 0;
    final wins = profile['wins'] ?? 0;
    final losses = profile['losses'] ?? 0;
    final winRate = profile['winRate'] ?? 0;
    final seasonRating = profile['seasonRating'] ?? 1000;
    final seasonGames = profile['seasonGames'] ?? 0;
    final seasonWins = profile['seasonWins'] ?? 0;
    final seasonLosses = profile['seasonLosses'] ?? 0;
    final seasonWinRate = profile['seasonWinRate'] ?? 0;
    final level = profile['level'] ?? 1;
    final expTotal = profile['expTotal'] ?? 0;
    final leaveCount = profile['leaveCount'] ?? 0;
    final reportCount = profile['reportCount'] ?? 0;
    final bannerKey = profile['bannerKey']?.toString();
    final skGames = profile['skTotalGames'] ?? 0;
    final skWins = profile['skWins'] ?? 0;
    final skLosses = profile['skLosses'] ?? 0;
    final skWinRate = profile['skWinRate'] ?? 0;
    final skSeasonRating = profile['skSeasonRating'] ?? 1000;
    final skSeasonGames = profile['skSeasonGames'] ?? 0;
    final skSeasonWins = profile['skSeasonWins'] ?? 0;
    final skSeasonLosses = profile['skSeasonLosses'] ?? 0;
    final skSeasonWinRate = profile['skSeasonWinRate'] ?? 0;
    final recentMatches = data['recentMatches'] as List<dynamic>? ?? [];
    final filteredMatches = recentMatches.where((m) {
      final gameType = m['gameType']?.toString() ?? 'tichu';
      return gameType == selectedTab;
    }).toList();
    final profileNickname = data['nickname']?.toString() ?? nickname;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildProfileHeader(nickname, level, expTotal, bannerKey),
        const SizedBox(height: 8),
        _buildMannerLeaveRow(reportCount: reportCount as int, leaveCount: leaveCount as int),
        const SizedBox(height: 10),
        // Game tab toggle
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'tichu', label: Text('티츄', style: TextStyle(fontSize: 13))),
              ButtonSegment(value: 'skull_king', label: Text('스컬킹', style: TextStyle(fontSize: 13))),
            ],
            selected: {selectedTab},
            onSelectionChanged: (s) => onTabChanged(s.first),
            style: ButtonStyle(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return selectedTab == 'tichu'
                      ? const Color(0xFF6C63FF)
                      : const Color(0xFF2D2D3D);
                }
                return Colors.white;
              }),
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return selectedTab == 'tichu'
                      ? Colors.white
                      : const Color(0xFFFFD54F);
                }
                return const Color(0xFF6A6A6A);
              }),
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              side: WidgetStateProperty.all(
                const BorderSide(color: Color(0xFFE0D8D4)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (selectedTab == 'tichu') ...[
          _buildProfileSectionCard(
            title: '티츄 시즌 랭킹전',
            accent: const Color(0xFF3A3058),
            background: const Color(0xFFF6F4FA),
            icon: Icons.emoji_events,
            iconColor: const Color(0xFFFFD54F),
            mainText: '$seasonRating',
            chips: [
              _buildStatChip('전적', '$seasonGames전 $seasonWins승 $seasonLosses패'),
              _buildStatChip('승률', '$seasonWinRate%'),
            ],
          ),
          const SizedBox(height: 10),
          _buildProfileSectionCard(
            title: '티츄 전적',
            accent: const Color(0xFF3A3058),
            background: const Color(0xFFF6F4FA),
            icon: Icons.style,
            iconColor: const Color(0xFF6C63FF),
            mainText: '',
            chips: [
              _buildStatChip('전적', '$totalGames전 $wins승 $losses패'),
              _buildStatChip('승률', '$winRate%'),
            ],
          ),
        ] else ...[
          _buildProfileSectionCard(
            title: '스컬킹 시즌 랭킹전',
            accent: const Color(0xFF2D2D3D),
            background: const Color(0xFFECEFF6),
            icon: Icons.emoji_events,
            iconColor: const Color(0xFFFFD54F),
            mainText: '$skSeasonRating',
            chips: [
              _buildStatChip('전적', '$skSeasonGames전 $skSeasonWins승 $skSeasonLosses패'),
              _buildStatChip('승률', '$skSeasonWinRate%'),
            ],
          ),
          const SizedBox(height: 10),
          _buildProfileSectionCard(
            title: '스컬킹 전적',
            accent: const Color(0xFF2D2D3D),
            background: const Color(0xFFECEFF6),
            icon: Icons.anchor,
            iconColor: const Color(0xFF2D2D3D),
            mainText: '',
            chips: [
              _buildStatChip('전적', '$skGames전 $skWins승 $skLosses패'),
              _buildStatChip('승률', '$skWinRate%'),
            ],
          ),
        ],
        const SizedBox(height: 12),
        _buildRecentMatches(filteredMatches, profileNickname),
      ],
    );
  }

  Widget _buildTitleIconButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
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



  Widget _buildProfileHeader(String nickname, int level, int expTotal, String? bannerKey) {
    final expInLevel = expTotal % 100;
    final expPercent = expInLevel / 100;
    final banner = _bannerStyle(bannerKey);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: banner.gradient,
        color: banner.gradient == null ? Colors.white.withValues(alpha: 0.95) : null,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0D8D4)),
      ),
      child: Row(
        children: [
          Text(
            'Lv.$level',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF5A4038),
            ),
          ),
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
                Text(
                  '$expInLevel/100 EXP',
                  style: const TextStyle(fontSize: 9, color: Color(0xFF9A8E8A)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  _BannerStyle _bannerStyle(String? key) {
    switch (key) {
      case 'banner_pastel':
        return const _BannerStyle(
          gradient: LinearGradient(
            colors: [Color(0xFFF6C1C9), Color(0xFFF3E7EA)],
          ),
        );
      case 'banner_blossom':
        return const _BannerStyle(
          gradient: LinearGradient(
            colors: [Color(0xFFF7D6D0), Color(0xFFF3E9E6)],
          ),
        );
      case 'banner_mint':
        return const _BannerStyle(
          gradient: LinearGradient(
            colors: [Color(0xFFCDEBD8), Color(0xFFEFF8F2)],
          ),
        );
      case 'banner_sunset_7d':
        return const _BannerStyle(
          gradient: LinearGradient(
            colors: [Color(0xFFFFC3A0), Color(0xFFFFE5B4)],
          ),
        );
      case 'banner_season_gold':
        return const _BannerStyle(
          gradient: LinearGradient(
            colors: [Color(0xFFFFE082), Color(0xFFFFF3C0)],
          ),
        );
      case 'banner_season_silver':
        return const _BannerStyle(
          gradient: LinearGradient(
            colors: [Color(0xFFCFD8DC), Color(0xFFF1F3F4)],
          ),
        );
      case 'banner_season_bronze':
        return const _BannerStyle(
          gradient: LinearGradient(
            colors: [Color(0xFFD7B59A), Color(0xFFF4E8DC)],
          ),
        );
      default:
        return const _BannerStyle();
    }
  }

  Widget _buildProfileSectionCard({
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
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (mainText.isNotEmpty)
                Text(
                  mainText,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: accent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: chips,
          ),
        ],
      ),
    );
  }

  static String _mannerLabel(int reportCount) {
    if (reportCount <= 1) return '좋음';
    if (reportCount <= 3) return '보통';
    if (reportCount <= 6) return '나쁨';
    if (reportCount <= 10) return '아주 나쁨';
    return '최악';
  }

  static Color _mannerColor(int reportCount) {
    if (reportCount <= 1) return const Color(0xFF66BB6A);
    if (reportCount <= 3) return const Color(0xFF8D9E56);
    if (reportCount <= 6) return const Color(0xFFFFA726);
    if (reportCount <= 10) return const Color(0xFFEF5350);
    return const Color(0xFFB71C1C);
  }

  static IconData _mannerIcon(int reportCount) {
    if (reportCount <= 1) return Icons.sentiment_satisfied_alt;
    if (reportCount <= 3) return Icons.sentiment_neutral;
    if (reportCount <= 6) return Icons.sentiment_dissatisfied;
    return Icons.sentiment_very_dissatisfied;
  }

  Widget _buildMannerLeaveRow({required int reportCount, required int leaveCount}) {
    final label = _mannerLabel(reportCount);
    final color = _mannerColor(reportCount);
    final icon = _mannerIcon(reportCount);
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0D8D4)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 6),
                Text(
                  '매너 $label',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0D8D4)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFE57373), size: 16),
                const SizedBox(width: 6),
                Text(
                  '탈주 $leaveCount',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF9A6A6A),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: Color(0xFF8A8A8A)),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Color(0xFF5A4038),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentMatches(
    List<dynamic> recentMatches,
    String profileNickname,
  ) {
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
          Row(
            children: [
              const Text(
                '최근 전적 (3)',
                style: TextStyle(fontSize: 12, color: Color(0xFF8A8A8A)),
              ),
              const Spacer(),
              if (recentMatches.length > 3)
                TextButton(
                  onPressed: () =>
                      _showRecentMatchesDialog(recentMatches, profileNickname),
                  child: const Text('더보기'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (recentMatches.isEmpty)
            const Text(
              '최근 전적이 없습니다',
              style: TextStyle(fontSize: 12, color: Color(0xFF9A8E8A)),
            )
          else
            Column(
              children: recentMatches.take(3).map<Widget>((match) {
                return _buildMatchRow(match, profileNickname);
              }).toList(),
            ),
        ],
      ),
    );
  }

  void _showRecentMatchesDialog(
    List<dynamic> recentMatches,
    String profileNickname,
  ) {
    showDialog(
      context: context,
      builder: (ctx) {
        final media = MediaQuery.of(ctx).size;
        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: const Color(0xFFF8F4F1),
          titlePadding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
          contentPadding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
          title: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE8DDD8)),
            ),
            child: Row(
              children: [
                const Icon(Icons.history, color: Color(0xFF6A5A52)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '최근 전적',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF3E312A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '최근 ${recentMatches.length}경기 결과를 확인할 수 있습니다.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF84766E),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          content: SizedBox(
            width: media.width > 700 ? 520 : media.width - 40,
            height: media.height * 0.5,
            child: ListView.separated(
              itemCount: recentMatches.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, index) {
                return _buildMatchRow(recentMatches[index], profileNickname);
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('닫기'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMatchRow(dynamic match, String profileNickname) {
    final gameType = match['gameType']?.toString() ?? 'tichu';
    final isSK = gameType == 'skull_king';

    final deserterNickname = match['deserterNickname']?.toString();
    final isDesertionLoss = match['isDesertionLoss'] == true ||
        (deserterNickname != null &&
            deserterNickname.isNotEmpty &&
            deserterNickname == profileNickname);
    final isDraw = match['isDraw'] == true;
    final won = !isDraw && match['won'] == true;
    final date = _formatShortDate(match['createdAt']);
    final isRanked = match['isRanked'] == true;

    final Color badgeColor;
    final String badgeText;
    if (isDesertionLoss) {
      badgeColor = const Color(0xFFFFB74D);
      badgeText = '탈';
    } else if (isDraw) {
      badgeColor = const Color(0xFFBDBDBD);
      badgeText = '무';
    } else if (won) {
      badgeColor = const Color(0xFF81C784);
      badgeText = '승';
    } else {
      badgeColor = const Color(0xFFE57373);
      badgeText = '패';
    }

    // Score / player info
    final String scoreText;
    final String playerText;
    if (isSK) {
      final players = match['players'] as List<dynamic>? ?? [];
      final myRank = match['myRank'] ?? '-';
      final myScore = match['myScore'] ?? 0;
      scoreText = '$myRank위 ($myScore점)';
      playerText = players.map((p) => p['nickname'] ?? '?').join(', ');
    } else {
      final teamAScore = match['teamAScore'] ?? 0;
      final teamBScore = match['teamBScore'] ?? 0;
      scoreText = '$teamAScore : $teamBScore';
      final teamA = _formatTeam(match['playerA1'], match['playerA2']);
      final teamB = _formatTeam(match['playerB1'], match['playerB2']);
      playerText = '$teamA : $teamB';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: badgeColor,
              shape: BoxShape.circle,
            ),
            child: Text(
              badgeText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      date,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8A8A8A),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: isSK
                            ? const Color(0xFFE8EAF6)
                            : isRanked
                                ? const Color(0xFFFFF3E0)
                                : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isSK ? '스컬킹' : (isRanked ? '랭크' : '일반'),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: isSK
                              ? const Color(0xFF3949AB)
                              : isRanked
                                  ? const Color(0xFFE65100)
                                  : const Color(0xFF9E9E9E),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  playerText,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5A4038),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            scoreText,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF5A4038),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTeam(dynamic p1, dynamic p2) {
    final a = p1?.toString() ?? '-';
    final b = p2?.toString() ?? '-';
    return '$a·$b';
  }

  String _formatShortDate(dynamic value) {
    try {
      final dt = DateTime.parse(value.toString()).toLocal();
      return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return '-';
    }
  }

  bool _isMyReady(GameService game) {
    final me = game.roomPlayers.firstWhere(
      (p) => p != null && p.id == game.playerId,
      orElse: () => null,
    );
    return me?.isReady ?? false;
  }

  Widget _buildClickablePlayerSlot(Player? player, {
    required int slotIndex,
    required GameService game,
  }) {
    // Find my current slot
    final myIndex = game.roomPlayers.indexWhere((p) => p != null && p.id == game.playerId);
    final isMySlot = myIndex == slotIndex;
    final isEmpty = player == null;
    final isBot = !isEmpty && player.id.startsWith('bot_');
    final isBlockedPlayer = !isEmpty && !isMySlot && !isBot && game.blockedUsers.contains(player.name);
    final isReady = !isEmpty && !isBot && !player.isHost && player.isReady;
    // Can only move to empty slots (no swapping)
    final canMove = game.currentGameType != 'skull_king' && !isMySlot && isEmpty && myIndex != -1;

    return GestureDetector(
      onTap: () {
        if (canMove) {
          // Move to empty slot
          game.changeTeam(slotIndex);
        } else if (!isEmpty && !isBot) {
          // Tapping a filled slot (including my slot): show player profile
          _showUserProfileDialog(player.name, game);
        }
      },
      child: Container(
        width: double.infinity,
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isReady
              ? const Color(0xFFE8F5E9)
              : isMySlot
                  ? const Color(0xFFE8F0E8)
                  : isBot
                      ? const Color(0xFFE8EAF6)
                      : isBlockedPlayer
                          ? const Color(0xFFFAF0F0)
                          : const Color(0xFFFAF6F4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isReady
                ? const Color(0xFF66BB6A)
                : isMySlot
                    ? const Color(0xFFA8D4A8)
                    : isBot
                        ? const Color(0xFFC5CAE9)
                        : isBlockedPlayer
                            ? const Color(0xFFE0B0B0)
                            : const Color(0xFFDDD0CC),
            width: isReady ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Ready check icon
            if (isReady)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.check_circle, size: 16, color: Color(0xFF43A047)),
              ),
            // Host badge
            if (player != null && player.isHost)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE082),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '방장',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF8D6E00),
                  ),
                ),
              ),
            // Bot badge
            if (isBot)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFC5CAE9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'BOT',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF3949AB),
                  ),
                ),
              ),
            // Blocked indicator
            if (isBlockedPlayer)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.block, size: 14, color: Color(0xFFE57373)),
              ),
            // Bug #8: Disconnected indicator
            if (player != null && !player.connected)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.wifi_off, size: 14, color: Color(0xFFFF8A65)),
              ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (player != null && player.titleName != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _getTitleIcon(player.titleKey),
                            size: 11,
                            color: _getTitleColor(player.titleKey),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            player.titleName!,
                            style: TextStyle(
                              fontSize: 11,
                              color: _getTitleColor(player.titleKey),
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  Text(
                      player?.name ?? '[빈 자리]',
                      style: TextStyle(
                        fontSize: 16,
                        color: isBot
                            ? const Color(0xFF3949AB)
                            : isBlockedPlayer
                                ? const Color(0xFFBB8888)
                                : (player != null && !player.connected)
                                    ? const Color(0xFFBBAAAA)
                                    : player != null
                                        ? const Color(0xFF5A4038)
                                        : const Color(0xFFAA9A92),
                        fontWeight: isMySlot ? FontWeight.bold : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Add bot button on empty slots (host only, not ranked)
            if (isEmpty && game.isHost && !game.isRankedRoom)
              GestureDetector(
                onTap: () => game.addBot(targetSlot: slotIndex),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8EAF6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.smart_toy, size: 14, color: Color(0xFF3949AB)),
                      SizedBox(width: 4),
                      Text(
                        '봇',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF3949AB),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // Kick button: show only for host, on other players' occupied slots (including bots)
            if (game.isHost && !isEmpty && !isMySlot)
              GestureDetector(
                onTap: () {
                  if (isBot) {
                    game.kickPlayer(player.id);
                  } else {
                    _showKickConfirmDialog(player.name, player.id, game);
                  }
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

  IconData _getTitleIcon(String? titleKey) {
    switch (titleKey) {
      case 'title_sweet': return Icons.cake;
      case 'title_steady': return Icons.shield;
      case 'title_flash_30d': return Icons.flash_on;
      case 'title_dragon': return Icons.local_fire_department;
      case 'title_phoenix': return Icons.local_fire_department;
      case 'title_pirate': return Icons.anchor;
      case 'title_tactician': return Icons.psychology;
      case 'title_lucky': return Icons.star;
      case 'title_bluffer': return Icons.theater_comedy;
      case 'title_ace': return Icons.military_tech;
      case 'title_king': return Icons.workspace_premium;
      case 'title_rookie': return Icons.emoji_nature;
      case 'title_veteran': return Icons.security;
      case 'title_sensitive': return Icons.sentiment_very_dissatisfied;
      case 'title_shadow': return Icons.visibility_off;
      case 'title_flame': return Icons.whatshot;
      case 'title_ice': return Icons.ac_unit;
      case 'title_crown': return Icons.diamond;
      case 'title_diamond': return Icons.diamond;
      case 'title_ghost': return Icons.blur_on;
      case 'title_thunder': return Icons.bolt;
      case 'title_topcard': return Icons.style;
      case 'title_legend': return Icons.auto_awesome;
      case 'title_boomer': return Icons.elderly;
      default: return Icons.star;
    }
  }

  Color _getTitleColor(String? titleKey) {
    switch (titleKey) {
      case 'title_sweet': return const Color(0xFFEC407A);
      case 'title_steady': return const Color(0xFF5C6BC0);
      case 'title_flash_30d': return const Color(0xFFFFA000);
      case 'title_dragon': return const Color(0xFFD32F2F);
      case 'title_phoenix': return const Color(0xFFFF6F00);
      case 'title_pirate': return const Color(0xFF37474F);
      case 'title_tactician': return const Color(0xFF00695C);
      case 'title_lucky': return const Color(0xFFFFD600);
      case 'title_bluffer': return const Color(0xFF6A1B9A);
      case 'title_ace': return const Color(0xFFC62828);
      case 'title_king': return const Color(0xFFFF8F00);
      case 'title_rookie': return const Color(0xFF66BB6A);
      case 'title_veteran': return const Color(0xFF1565C0);
      case 'title_sensitive': return const Color(0xFFE91E63);
      case 'title_shadow': return const Color(0xFF424242);
      case 'title_flame': return const Color(0xFFFF5722);
      case 'title_ice': return const Color(0xFF0288D1);
      case 'title_crown': return const Color(0xFFE65100);
      case 'title_diamond': return const Color(0xFF00BCD4);
      case 'title_ghost': return const Color(0xFF78909C);
      case 'title_thunder': return const Color(0xFFFFAB00);
      case 'title_topcard': return const Color(0xFF00897B);
      case 'title_legend': return const Color(0xFFFF6D00);
      case 'title_boomer': return const Color(0xFF795548);
      default: return const Color(0xFF7E57C2);
    }
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

}

class _BannerStyle {
  const _BannerStyle({this.gradient});
  final LinearGradient? gradient;
}
