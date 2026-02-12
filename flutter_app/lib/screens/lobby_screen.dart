import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/game_service.dart';
import '../services/network_service.dart';
import '../services/auth_service.dart';
import '../models/player.dart';
import '../models/room.dart';
import 'game_screen.dart';
import 'ranking_screen.dart';
import 'shop_screen.dart';
import 'spectator_screen.dart';
import 'login_screen.dart';
import 'settings_screen.dart';
import '../widgets/connection_overlay.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  bool _inRoom = false;
  bool _navigatingToGame = false;
  bool _wasDisconnected = false;
  NetworkService? _networkService; // C6: Cache for safe dispose

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
      // Reconnected - check if room still exists
      if (_inRoom) {
        context.read<GameService>().checkRoom();
      }
    }
  }

  @override
  void dispose() {
    // C6: Use cached reference instead of context.read in dispose
    _networkService?.removeListener(_onNetworkChanged);
    _chatController.dispose();
    _chatScrollController.dispose();
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
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
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
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
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
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('버그 신고'),
                      selected: selectedCategory == 'bug',
                      onSelected: (_) => setState(() => selectedCategory = 'bug'),
                      selectedColor: const Color(0xFFEDE7F6),
                      labelStyle: TextStyle(
                        color: selectedCategory == 'bug'
                            ? const Color(0xFF6A4FA3)
                            : const Color(0xFF5A4038),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    ChoiceChip(
                      label: const Text('건의사항'),
                      selected: selectedCategory == 'suggestion',
                      onSelected: (_) => setState(() => selectedCategory = 'suggestion'),
                      selectedColor: const Color(0xFFEDE7F6),
                      labelStyle: TextStyle(
                        color: selectedCategory == 'suggestion'
                            ? const Color(0xFF6A4FA3)
                            : const Color(0xFF5A4038),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    ChoiceChip(
                      label: const Text('기타'),
                      selected: selectedCategory == 'other',
                      onSelected: (_) => setState(() => selectedCategory = 'other'),
                      selectedColor: const Color(0xFFEDE7F6),
                      labelStyle: TextStyle(
                        color: selectedCategory == 'other'
                            ? const Color(0xFF6A4FA3)
                            : const Color(0xFF5A4038),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
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

  void _showInquiryHistoryDialog() {
    final game = context.read<GameService>();
    game.markInquiriesRead();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.mark_email_read, color: Color(0xFF1E88E5)),
            SizedBox(width: 8),
            Text('문의 내역'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Consumer<GameService>(
            builder: (context, game, _) {
              if (game.inquiriesLoading) {
                return const SizedBox(
                  height: 160,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (game.inquiriesError != null) {
                return SizedBox(
                  height: 160,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          game.inquiriesError!,
                          style: const TextStyle(color: Color(0xFFCC6666)),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: () => game.requestInquiries(),
                          child: const Text('다시 시도'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (game.inquiries.isEmpty) {
                return const SizedBox(
                  height: 140,
                  child: Center(
                    child: Text(
                      '등록된 문의가 없습니다',
                      style: TextStyle(color: Color(0xFF9A8E8A)),
                    ),
                  ),
                );
              }
              return SizedBox(
                height: 320,
                child: ListView.separated(
                  itemCount: game.inquiries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = game.inquiries[index];
                    final title = item['title']?.toString() ?? '';
                    final category = _inquiryCategoryLabel(item['category']);
                    final status = item['status']?.toString() ?? 'pending';
                    final createdAt = _formatShortDate(item['created_at']);
                    final isResolved = status == 'resolved';
                    return InkWell(
                      onTap: () => _showInquiryDetailDialog(item),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE0D8D4)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isResolved
                                    ? const Color(0xFFE8F5E9)
                                    : const Color(0xFFFFF8E1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                isResolved ? '답변완료' : '대기중',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isResolved
                                      ? const Color(0xFF4CAF50)
                                      : const Color(0xFFF57C00),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF5A4038),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$category · $createdAt',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF8A7A72),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right, color: Color(0xFFB0A8A4)),
                          ],
                        ),
                      ),
                    );
                  },
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

  void _showInquiryDetailDialog(Map<String, dynamic> item) {
    final title = item['title']?.toString() ?? '';
    final content = item['content']?.toString() ?? '';
    final adminNote = item['admin_note']?.toString() ?? '';
    final status = item['status']?.toString() ?? 'pending';
    final category = _inquiryCategoryLabel(item['category']);
    final createdAt = _formatShortDate(item['created_at']);
    final resolvedAt = _formatShortDate(item['resolved_at']);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$category · $createdAt',
                style: const TextStyle(fontSize: 12, color: Color(0xFF8A7A72)),
              ),
              const SizedBox(height: 12),
              Text(
                content,
                style: const TextStyle(fontSize: 13, color: Color(0xFF5A4038)),
              ),
              const SizedBox(height: 16),
              if (status == 'resolved' && adminNote.isNotEmpty) ...[
                const Text(
                  '답변',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4CAF50)),
                ),
                const SizedBox(height: 6),
                Text(
                  adminNote,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF5A4038)),
                ),
                const SizedBox(height: 8),
                Text(
                  '답변일: $resolvedAt',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF8A7A72)),
                ),
              ] else if (status != 'resolved') ...[
                const Text(
                  '아직 답변이 등록되지 않았습니다.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF9A8E8A)),
                ),
              ],
            ],
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

  void _showProfileDialog() {
    final game = context.read<GameService>();
    _showUserProfileDialog(game.playerName, game);
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.settings, color: Color(0xFF9E9E9E)),
            SizedBox(width: 8),
            Text('설정'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _showInquiryDialog();
                },
                icon: const Icon(Icons.help_outline),
                label: const Text('문의하기'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF3E5F5),
                  foregroundColor: const Color(0xFFBA68C8),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _showInquiryHistoryDialog();
                },
                icon: const Icon(Icons.mark_email_read),
                label: const Text('문의 내역'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE3F2FD),
                  foregroundColor: const Color(0xFF1E88E5),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            if (context.read<GameService>().authProvider == 'local') ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showSocialLinkDialog();
                  },
                  icon: const Icon(Icons.link),
                  label: const Text('소셜 연동'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFF3E0),
                    foregroundColor: const Color(0xFFF57C00),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
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
                  Navigator.pop(ctx);
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
            onPressed: () => Navigator.pop(ctx),
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
    // Clear saved credentials and social auth
    await LoginScreen.clearSavedCredentials();
    await AuthService.signOut();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  void _showSocialLinkDialog() {
    final game = context.read<GameService>();
    game.getLinkedSocial();

    showDialog(
      context: context,
      builder: (ctx) {
        bool isLinking = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Consumer<GameService>(
              builder: (ctx, game, _) {
                final provider = game.linkedSocialProvider;
                final isLinked = provider != null && provider != 'local';

                // Show link result
                if (game.socialLinkResultSuccess != null) {
                  final success = game.socialLinkResultSuccess!;
                  final msg = game.socialLinkResultMessage ?? '';
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    game.clearSocialLinkResult();
                    if (!success && msg.isNotEmpty) {
                      showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          title: const Text('연동 실패'),
                          content: Text(msg),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('확인'),
                            ),
                          ],
                        ),
                      );
                    }
                    setDialogState(() => isLinking = false);
                  });
                }

                String providerLabel(String p) {
                  switch (p) {
                    case 'google': return 'Google';
                    case 'apple': return 'Apple';
                    case 'kakao': return 'Kakao';
                    default: return p;
                  }
                }

                return AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  title: const Row(
                    children: [
                      Icon(Icons.link, color: Color(0xFFF57C00)),
                      SizedBox(width: 8),
                      Text('소셜 연동'),
                    ],
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isLinked) ...[
                        const Text(
                          '소셜 계정을 연동하면\n간편 로그인이 가능합니다',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                        if (isLinking)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(),
                          )
                        else ...[
                          _socialLinkButton(
                            label: 'Google 연동',
                            color: const Color(0xFFDB4437),
                            icon: Icons.g_mobiledata,
                            onTap: () async {
                              setDialogState(() => isLinking = true);
                              try {
                                final result = await AuthService.signInWithGoogle();
                                if (result.cancelled) {
                                  setDialogState(() => isLinking = false);
                                  return;
                                }
                                game.linkSocial(result.provider, result.token);
                              } catch (e) {
                                setDialogState(() => isLinking = false);
                              }
                            },
                          ),
                          if (Platform.isIOS) ...[
                            const SizedBox(height: 10),
                            _socialLinkButton(
                              label: 'Apple 연동',
                              color: Colors.black87,
                              icon: Icons.apple,
                              onTap: () async {
                                setDialogState(() => isLinking = true);
                                try {
                                  final result = await AuthService.signInWithApple();
                                  if (result.cancelled) {
                                    setDialogState(() => isLinking = false);
                                    return;
                                  }
                                  game.linkSocial(result.provider, result.token);
                                } catch (e) {
                                  setDialogState(() => isLinking = false);
                                }
                              },
                            ),
                          ],
                          const SizedBox(height: 10),
                          _socialLinkButton(
                            label: 'Kakao 연동',
                            color: const Color(0xFFFEE500),
                            textColor: const Color(0xFF3C1E1E),
                            icon: Icons.chat_bubble,
                            onTap: () async {
                              setDialogState(() => isLinking = true);
                              try {
                                final result = await AuthService.signInWithKakao();
                                if (result.cancelled) {
                                  setDialogState(() => isLinking = false);
                                  return;
                                }
                                game.linkSocial(result.provider, result.token);
                              } catch (e) {
                                setDialogState(() => isLinking = false);
                              }
                            },
                          ),
                        ],
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F5F5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              Text(
                                '현재 연동: ${providerLabel(provider!)}',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              if (game.linkedSocialEmail != null && game.linkedSocialEmail!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    game.linkedSocialEmail!,
                                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: isLinking ? null : () {
                              showDialog(
                                context: context,
                                builder: (_) => AlertDialog(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  title: const Text('연동 해제'),
                                  content: const Text('소셜 연동을 해제하시겠습니까?\nID/PW로만 로그인 가능합니다.'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('취소'),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.pop(context);
                                        setDialogState(() => isLinking = true);
                                        game.unlinkSocial();
                                      },
                                      child: const Text('해제', style: TextStyle(color: Colors.red)),
                                    ),
                                  ],
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFFCDD2),
                              foregroundColor: const Color(0xFFC62828),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('연동 해제'),
                          ),
                        ),
                      ],
                    ],
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

  Widget _socialLinkButton({
    required String label,
    required Color color,
    Color textColor = Colors.white,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: textColor,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
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
    final timeLimitController = TextEditingController(text: '30');
    String? errorText;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: null,
        contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        backgroundColor: context.read<GameService>().themeGradient.first.withValues(alpha: 0.9),
        content: StatefulBuilder(
          builder: (context, setState) {
            final themeColors = context.read<GameService>().themeGradient;
            final accent = themeColors.length > 1 ? themeColors[1] : themeColors.first;
            return SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      themeColors.first.withValues(alpha: 0.9),
                      themeColors.last.withValues(alpha: 0.7),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text('방 이름', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setState(() => controller.text = randomName),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(40, 24)),
                      child: Text(
                        '랜덤',
                        style: TextStyle(color: accent),
                      ),
                    ),
                  ],
                ),
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: randomName,
                    filled: true,
                    fillColor: themeColors.first.withValues(alpha: 0.35),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: accent.withValues(alpha: 0.35)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: accent.withValues(alpha: 0.35)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: accent),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text('비공개', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                    const Spacer(),
                    Switch(
                      value: isPrivate,
                      onChanged: isRanked ? null : (v) => setState(() => isPrivate = v),
                    ),
                  ],
                ),
                if (isPrivate)
                  TextField(
                    controller: passwordController,
                    decoration: InputDecoration(
                      hintText: '비밀번호 (4자 이상)',
                      filled: true,
                      fillColor: themeColors.first.withValues(alpha: 0.35),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: accent.withValues(alpha: 0.35)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: accent.withValues(alpha: 0.35)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: accent),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    obscureText: true,
                  )
                else
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '비공개를 켜면 비밀번호가 필요합니다',
                      style: TextStyle(fontSize: 11, color: Color(0xFF9A8E8A)),
                    ),
                  ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Text('랭크전', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
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
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '랭크전은 비공개 방을 만들 수 없습니다',
                    style: TextStyle(fontSize: 11, color: Color(0xFF9A8E8A)),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('시간 제한', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: timeLimitController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          suffixText: '초',
                          hintText: '10~300',
                          filled: true,
                          fillColor: themeColors.first.withValues(alpha: 0.35),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: accent.withValues(alpha: 0.35)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: accent.withValues(alpha: 0.35)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: accent),
                          ),
                        ),
                      ),
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
            ),
              ),
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
              final turnTimeLimit = int.tryParse(timeLimitController.text.trim()) ?? 30;
              if (turnTimeLimit < 10 || turnTimeLimit > 300) {
                setState(() => errorText = '시간 제한은 10~300초 사이로 입력해줘.');
                return;
              }
              context
                  .read<GameService>()
                  .createRoom(
                    name,
                    password: isPrivate ? password : '',
                    isRanked: isRanked,
                    turnTimeLimit: turnTimeLimit,
                  );
              Navigator.pop(context);
              setState(() => _inRoom = true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: context.read<GameService>().themeGradient[1],
              foregroundColor: const Color(0xFF3A2A1E),
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
    final themeColors = context.watch<GameService>().themeGradient;
    return ConnectionOverlay(
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
                  game.duplicateLoginKicked = false;
                  await LoginScreen.clearSavedCredentials();
                  final network = context.read<NetworkService>();
                  network.disconnect();
                  game.reset();
                  if (!mounted) return;
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('다른 기기에서 로그인되어 로그아웃되었습니다'),
                      backgroundColor: Colors.red,
                    ),
                  );
                });
              }
              // Show room invite dialog if any
              if (game.roomInvites.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted || game.roomInvites.isEmpty) return;
                  final invite = game.roomInvites.first;
                  game.roomInvites.removeAt(0);
                  game.notifyListeners();
                  _showRoomInviteDialog(invite, game);
                });
              }

              // Sync local room flag with server state
              if (game.currentRoomId.isEmpty && _inRoom) {
                _inRoom = false;
              }
              if (game.currentRoomId.isNotEmpty && !game.isSpectator && !_inRoom) {
                _inRoom = true;
              }

              // Check if spectating
              if (game.isSpectator && game.currentRoomId.isNotEmpty) {
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
                  game.gameState!.phase != 'waiting' &&
                  game.gameState!.phase != 'game_end') {
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
      ),
    );
  }

  Widget _buildLobbyView(GameService game) {
    return Column(
      children: [
        // Top bar with menu icons
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(18),
          ),
          margin: const EdgeInsets.all(16),
          clipBehavior: Clip.none,
          child: Row(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 44),
                child: Image.asset(
                  'assets/logo2.png',
                  fit: BoxFit.contain,
                ),
              ),
              const Spacer(),
              Row(
                children: [
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
                  const SizedBox(width: 8),
                  // Friends button with badge
                  Stack(
                    children: [
                      _buildIconButton(
                        icon: Icons.people,
                        color: const Color(0xFF7E57C2),
                        onTap: () {
                          game.requestFriends();
                          game.requestPendingFriendRequests();
                          _showFriendsDialog(game);
                        },
                      ),
                      if (game.pendingFriendRequestCount > 0)
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
                              '${game.pendingFriendRequestCount}',
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
                  const SizedBox(width: 8),
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
                  const SizedBox(width: 8),
                  _buildIconButton(
                    icon: Icons.person,
                    color: const Color(0xFF64B5F6),
                    onTap: _showProfileDialog,
                  ),
                  const SizedBox(width: 8),
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
                ],
              ),
            ],
          ),
        ),

        // Maintenance notice banner
        if (game.hasMaintenanceNotice)
          _buildMaintenanceBanner(game),
        if (game.inquiryBannerMessage != null)
          _buildInquiryBanner(game),

        // Room list or Friends panel
        Expanded(
          child: _buildRoomListPanel(game),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildMaintenanceBanner(GameService game) {
    String timeText = '';
    if (game.maintenanceStart != null && game.maintenanceEnd != null) {
      try {
        final start = DateTime.parse(game.maintenanceStart!).toLocal();
        final end = DateTime.parse(game.maintenanceEnd!).toLocal();
        final fmt = (DateTime d) => '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
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
    );
  }

  void _showFriendsDialog(GameService game) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Consumer<GameService>(
          builder: (context, game, _) {
            final sortedFriends = List<Map<String, dynamic>>.from(game.friendsData);
            sortedFriends.sort((a, b) {
              final aOnline = a['isOnline'] == true ? 0 : 1;
              final bOnline = b['isOnline'] == true ? 0 : 1;
              return aOnline.compareTo(bOnline);
            });

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  const Icon(Icons.people, size: 18, color: Color(0xFF7E57C2)),
                  const SizedBox(width: 6),
                  const Text(
                    '친구 목록',
                    style: TextStyle(fontSize: 16, color: Color(0xFF8A7A72)),
                  ),
                  const SizedBox(width: 8),
                  if (game.pendingFriendRequestCount > 0)
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        _showPendingRequestsDialog(game);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '요청 ${game.pendingFriendRequestCount}건',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFE53935),
                          ),
                        ),
                      ),
                    ),
                  const Spacer(),
                  IconButton(
                    onPressed: () {
                      game.requestFriends();
                      game.requestPendingFriendRequests();
                    },
                    icon: const Icon(Icons.refresh, size: 20),
                    color: const Color(0xFF8A7A72),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: sortedFriends.isEmpty
                    ? const Center(
                        child: Text(
                          '친구가 없어요!\n채팅에서 친구를 추가해보세요.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: Color(0xFF9A8E8A)),
                        ),
                      )
                    : ListView.separated(
                        itemCount: sortedFriends.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final friend = sortedFriends[index];
                          final nickname = friend['nickname'] as String? ?? '';
                          final isOnline = friend['isOnline'] == true;
                          final roomName = friend['roomName'] as String?;

                          String statusText;
                          if (isOnline && roomName != null && roomName.isNotEmpty) {
                            statusText = '$roomName에서 게임중';
                          } else if (isOnline) {
                            statusText = '온라인';
                          } else {
                            statusText = '오프라인';
                          }

                          return GestureDetector(
                            onTap: () {
                              Navigator.pop(ctx);
                              _showUserProfileDialog(nickname, game);
                            },
                            child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isOnline ? const Color(0xFFF1F8E9) : const Color(0xFFFAF6F4),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isOnline ? const Color(0xFFC8E6C9) : const Color(0xFFDDD0CC),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isOnline
                                        ? const Color(0xFF4CAF50)
                                        : const Color(0xFFBDBDBD),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        nickname,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF5A4038),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        statusText,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isOnline
                                              ? const Color(0xFF4CAF50)
                                              : const Color(0xFF9A8E8A),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Invite button (I'm in a room, friend is online & not in a room)
                                if (isOnline && friend['roomId'] == null && game.currentRoomId.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: GestureDetector(
                                      onTap: () {
                                        game.inviteToRoom(nickname);
                                        Navigator.pop(ctx);
                                        ScaffoldMessenger.of(this.context).showSnackBar(
                                          SnackBar(content: Text('$nickname님에게 초대를 보냈습니다')),
                                        );
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE3F2FD),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.send, size: 12, color: Color(0xFF1976D2)),
                                            SizedBox(width: 4),
                                            Text('초대', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1976D2))),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                // Join/Spectate button (friend is in a room, I'm not in a room)
                                if (friend['roomId'] != null && game.currentRoomId.isEmpty) ...[
                                  () {
                                    final roomId = friend['roomId'] as String;
                                    final roomInGame = friend['roomInGame'] == true;
                                    final roomPlayerCount = friend['roomPlayerCount'] as int? ?? 4;
                                    final roomPassword = friend['roomPassword'] as String? ?? '';
                                    final canJoin = !roomInGame && roomPlayerCount < 4;
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: GestureDetector(
                                        onTap: () {
                                          Navigator.pop(ctx);
                                          if (canJoin) {
                                            game.joinRoom(roomId, password: roomPassword);
                                            setState(() => _inRoom = true);
                                          } else {
                                            game.spectateRoom(roomId);
                                          }
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: canJoin ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(canJoin ? Icons.login : Icons.visibility, size: 12, color: canJoin ? const Color(0xFF388E3C) : const Color(0xFFE65100)),
                                              const SizedBox(width: 4),
                                              Text(
                                                canJoin ? '입장' : '관전',
                                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: canJoin ? const Color(0xFF388E3C) : const Color(0xFFE65100)),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  }(),
                                ],
                                GestureDetector(
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    _showRemoveFriendConfirmation(nickname, game);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFEBEE),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.person_remove, size: 14, color: Color(0xFFE57373)),
                                  ),
                                ),
                              ],
                            ),
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
        );
      },
    );
  }

  void _showPendingRequestsDialog(GameService game) {
    showDialog(
      context: context,
      builder: (ctx) => Consumer<GameService>(
        builder: (ctx, game, _) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.person_add, color: Color(0xFF7E57C2)),
                SizedBox(width: 8),
                Text('받은 친구 요청'),
              ],
            ),
            content: game.pendingFriendRequests.isEmpty
                ? const SizedBox(
                    height: 60,
                    child: Center(
                      child: Text(
                        '받은 요청이 없습니다',
                        style: TextStyle(color: Color(0xFF9A8E8A)),
                      ),
                    ),
                  )
                : SizedBox(
                    width: double.maxFinite,
                    height: 300,
                    child: ListView.separated(
                      itemCount: game.pendingFriendRequests.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final nickname = game.pendingFriendRequests[index];
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3E5F5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFCE93D8)),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: const Color(0xFFCE93D8),
                                child: Text(
                                  nickname.isNotEmpty ? nickname[0] : '?',
                                  style: const TextStyle(fontSize: 12, color: Colors.white),
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
                              // Accept
                              GestureDetector(
                                onTap: () {
                                  game.acceptFriendRequest(nickname);
                                  ScaffoldMessenger.of(this.context).showSnackBar(
                                    SnackBar(content: Text('$nickname님과 친구가 되었습니다')),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF81C784),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    '수락',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              // Reject
                              GestureDetector(
                                onTap: () {
                                  game.rejectFriendRequest(nickname);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE57373),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    '거절',
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

  void _showRemoveFriendConfirmation(String nickname, GameService game) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('친구 삭제'),
        content: Text('$nickname님을 친구 목록에서 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              game.removeFriendAction(nickname);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$nickname님을 친구 목록에서 삭제했습니다')),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE57373),
              foregroundColor: Colors.white,
            ),
            child: const Text('삭제'),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${room.isPrivate ? '🔒 ' : ''}${room.isRanked ? '🏆 ' : ''}${room.name}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF5A4038),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${room.turnTimeLimit}초',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF9A8A82),
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
              if (!isInProgress)
                GestureDetector(
                  onTap: () {
                    context.read<GameService>().spectateRoom(room.id);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8E0F8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.visibility,
                      size: 18,
                      color: Color(0xFF4A4080),
                    ),
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
                    // Turn time limit
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0EBE8),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${game.roomTurnTimeLimit}초',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF8A7A72),
                        ),
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
                const SizedBox(height: 8),
                Row(
                  children: [
                    // Invite friends button
                    GestureDetector(
                      onTap: () => _showInviteFriendsDialog(game),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3E5F5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person_add, size: 14, color: Color(0xFF7E57C2)),
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
                    const SizedBox(width: 6),
                    // Switch to spectator button
                    GestureDetector(
                      onTap: () => game.switchToSpectator(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                    const SizedBox(width: 6),
                    // Spectator list button
                    GestureDetector(
                      onTap: () => _showSpectatorListDialog(game),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEDE7F6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.visibility, size: 14, color: Color(0xFF4A4080)),
                            const SizedBox(width: 4),
                            Text(
                              '관전자 ${game.spectators.length}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF4A4080),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (game.isHost)
                      GestureDetector(
                        onTap: () => _showRoomSettingsDialog(game),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                            _buildClickablePlayerSlot(
                              game.roomPlayers[i],
                              slotIndex: i,
                              game: game,
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
                        // Ready / Start buttons
                        const SizedBox(height: 12),
                        if (game.isHost) ...[
                          if (game.playerCount >= 4)
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
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Consumer<GameService>(
              builder: (ctx, game, _) {
                final profile = game.profileData;
                final isLoading = profile == null || profile['nickname'] != nickname;

                final isMe = nickname == game.playerName;
                final isBlockedUser = game.blockedUsers.contains(nickname);
                return AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          nickname,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!isMe) ...[
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
                        const SizedBox(width: 6),
                        _buildTitleIconButton(
                          icon: isBlockedUser ? Icons.block : Icons.shield_outlined,
                          color: isBlockedUser ? const Color(0xFF64B5F6) : const Color(0xFFFF8A65),
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
                    ],
                  ),
                  content: isLoading
                      ? const SizedBox(
                          height: 100,
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : SingleChildScrollView(
                          child: _buildProfileContent(profile, game),
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

  Widget _buildProfileContent(Map<String, dynamic> data, GameService game) {
    final profile = data['profile'] as Map<String, dynamic>?;
    final nickname = data['nickname'] as String? ?? '';

    if (profile == null) {
      return const Text('프로필을 찾을 수 없습니다');
    }

    final totalGames = profile['totalGames'] ?? 0;
    final wins = profile['wins'] ?? 0;
    final losses = profile['losses'] ?? 0;
    final rating = profile['rating'] ?? 1000;
    final winRate = profile['winRate'] ?? 0;
    final seasonRating = profile['seasonRating'] ?? 1000;
    final seasonGames = profile['seasonGames'] ?? 0;
    final seasonWins = profile['seasonWins'] ?? 0;
    final seasonLosses = profile['seasonLosses'] ?? 0;
    final seasonWinRate = profile['seasonWinRate'] ?? 0;
    final level = profile['level'] ?? 1;
    final expTotal = profile['expTotal'] ?? 0;
    final gold = profile['gold'] ?? 0;
    final leaveCount = profile['leaveCount'] ?? 0;
    final reportCount = profile['reportCount'] ?? 0;
    final bannerKey = profile['bannerKey']?.toString();
    final recentMatches = data['recentMatches'] as List<dynamic>? ?? [];
    final isMe = nickname == game.playerName;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildProfileHeader(nickname, level, expTotal, bannerKey),
        const SizedBox(height: 8),
        _buildMannerLeaveRow(reportCount: reportCount as int, leaveCount: leaveCount as int),
        const SizedBox(height: 10),
        _buildProfileSectionCard(
          title: '시즌 랭킹전',
          accent: const Color(0xFF7A6A95),
          background: const Color(0xFFF6F3FA),
          icon: Icons.emoji_events,
          iconColor: const Color(0xFFFFD54F),
          mainText: '$seasonRating',
          chips: [
            _buildStatChip('전적', '$seasonGames전 ${seasonWins}승 ${seasonLosses}패'),
            _buildStatChip('승률', '$seasonWinRate%'),
          ],
        ),
        const SizedBox(height: 10),
        _buildProfileSectionCard(
          title: '전체 전적',
          accent: const Color(0xFF5A4038),
          background: const Color(0xFFF5F5F5),
          icon: Icons.star,
          iconColor: const Color(0xFFFFB74D),
          mainText: '',
          chips: [
            _buildStatChip('전적', '$totalGames전 ${wins}승 ${losses}패'),
            _buildStatChip('승률', '$winRate%'),
          ],
        ),
        const SizedBox(height: 12),
        _buildRecentMatches(recentMatches),
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
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.35)),
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
        color: banner.gradient == null ? Colors.white.withOpacity(0.95) : null,
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
        border: Border.all(color: background.withOpacity(0.6)),
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

  Widget _buildMiniStatRow({required int gold, required int leaveCount}) {
    return _buildMannerLeaveRow(reportCount: 0, leaveCount: leaveCount);
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
              color: Colors.white.withOpacity(0.95),
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
              color: Colors.white.withOpacity(0.95),
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
        color: Colors.white.withOpacity(0.9),
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

  Widget _buildRecentMatches(List<dynamic> recentMatches) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
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
                  onPressed: () => _showRecentMatchesDialog(recentMatches),
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
                return _buildMatchRow(match);
              }).toList(),
            ),
        ],
      ),
    );
  }

  void _showRecentMatchesDialog(List<dynamic> recentMatches) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('최근 전적'),
        content: SizedBox(
          width: double.maxFinite,
          height: 320,
          child: ListView.separated(
            itemCount: recentMatches.length,
            separatorBuilder: (_, __) => const Divider(height: 16),
            itemBuilder: (_, index) {
              return _buildMatchRow(recentMatches[index]);
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

  Widget _buildMatchRow(dynamic match) {
    final isDraw = match['isDraw'] == true;
    final won = !isDraw && match['won'] == true;
    final teamAScore = match['teamAScore'] ?? 0;
    final teamBScore = match['teamBScore'] ?? 0;
    final teamA = _formatTeam(match['playerA1'], match['playerA2']);
    final teamB = _formatTeam(match['playerB1'], match['playerB2']);
    final date = _formatShortDate(match['createdAt']);
    final isRanked = match['isRanked'] == true;

    final Color badgeColor;
    final String badgeText;
    if (isDraw) {
      badgeColor = const Color(0xFFBDBDBD);
      badgeText = '무';
    } else if (won) {
      badgeColor = const Color(0xFF81C784);
      badgeText = '승';
    } else {
      badgeColor = const Color(0xFFE57373);
      badgeText = '패';
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
                        color: isRanked
                            ? const Color(0xFFFFF3E0)
                            : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isRanked ? '랭크' : '일반',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: isRanked
                              ? const Color(0xFFE65100)
                              : const Color(0xFF9E9E9E),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$teamA : $teamB',
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
            '$teamAScore : $teamBScore',
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

  String _inquiryCategoryLabel(dynamic value) {
    switch (value?.toString()) {
      case 'bug':
        return '버그 신고';
      case 'suggestion':
        return '건의사항';
      case 'other':
        return '기타';
      default:
        return '기타';
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
    final canMove = !isMySlot && isEmpty && myIndex != -1;

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
                crossAxisAlignment: CrossAxisAlignment.start,
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
                  Align(
                    alignment: Alignment.center,
                    child: Text(
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
                  ),
                ],
              ),
            ),
            // Add bot button on empty slots (host only)
            if (isEmpty && game.isHost)
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
      default: return Icons.star;
    }
  }

  Color _getTitleColor(String? titleKey) {
    switch (titleKey) {
      case 'title_sweet': return const Color(0xFFEC407A);
      case 'title_steady': return const Color(0xFF5C6BC0);
      case 'title_flash_30d': return const Color(0xFFFFA000);
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
