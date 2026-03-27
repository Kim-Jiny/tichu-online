import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/game_service.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  // DM chat state
  String? _dmChatPartner;
  final TextEditingController _dmInputController = TextEditingController();
  final ScrollController _dmScrollController = ScrollController();
  bool _dmLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final game = context.read<GameService>();
      game.requestFriends();
      game.requestPendingFriendRequests();
      game.requestDmConversations();
      game.requestUnreadDmCount();
    });
    _dmScrollController.addListener(_onDmScroll);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    _dmInputController.dispose();
    _dmScrollController.removeListener(_onDmScroll);
    _dmScrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    if (query.trim().isEmpty) {
      context.read<GameService>().clearSearchResults();
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      context.read<GameService>().searchUsersAction(query.trim());
    });
  }

  void _onDmScroll() {
    if (_dmScrollController.position.pixels <= 0 && !_dmLoadingMore && _dmChatPartner != null) {
      final game = context.read<GameService>();
      final messages = game.dmMessages[_dmChatPartner] ?? [];
      if (messages.isNotEmpty) {
        setState(() => _dmLoadingMore = true);
        final oldestId = messages.first['id'] as int?;
        if (oldestId != null) {
          game.requestDmHistory(_dmChatPartner!, beforeId: oldestId);
        }
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) setState(() => _dmLoadingMore = false);
        });
      }
    }
  }

  void _openDmChat(String partner) {
    final game = context.read<GameService>();
    game.requestDmHistory(partner);
    game.markDmReadAction(partner);
    setState(() => _dmChatPartner = partner);
  }

  void _closeDmChat() {
    setState(() {
      _dmChatPartner = null;
      _dmInputController.clear();
    });
  }

  void _sendDm() {
    final text = _dmInputController.text.trim();
    if (text.isEmpty || _dmChatPartner == null) return;
    context.read<GameService>().sendDm(_dmChatPartner!, text);
    _dmInputController.clear();
    // Scroll to bottom after send
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_dmScrollController.hasClients) {
        _dmScrollController.animateTo(
          _dmScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeColors = context.watch<GameService>().themeGradient;

    if (_dmChatPartner != null) {
      return _buildDmChatView(themeColors);
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: themeColors,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              _buildTabBar(),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildFriendsTab(),
                    _buildSearchTab(),
                    _buildRequestsTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.arrow_back, size: 20, color: Color(0xFF5A4038)),
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            '친구',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF5A4038),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () {
              final game = context.read<GameService>();
              game.requestFriends();
              game.requestPendingFriendRequests();
              game.requestDmConversations();
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.refresh, size: 20, color: Color(0xFF8A7A72)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Consumer<GameService>(
      builder: (context, game, _) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TabBar(
            controller: _tabController,
            labelColor: const Color(0xFF7E57C2),
            unselectedLabelColor: const Color(0xFF8A7A72),
            indicatorColor: const Color(0xFF7E57C2),
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            unselectedLabelStyle: const TextStyle(fontSize: 13),
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('친구'),
                    if (game.totalUnreadDmCount > 0) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE53935),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${game.totalUnreadDmCount}',
                          style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Tab(text: '검색'),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('요청'),
                    if (game.pendingFriendRequestCount > 0) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE53935),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${game.pendingFriendRequestCount}',
                          style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // === Tab 0: Friends List ===
  Widget _buildFriendsTab() {
    return Consumer<GameService>(
      builder: (context, game, _) {
        final sorted = List<Map<String, dynamic>>.from(game.friendsData);
        sorted.sort((a, b) {
          final aOnline = a['isOnline'] == true ? 0 : 1;
          final bOnline = b['isOnline'] == true ? 0 : 1;
          return aOnline.compareTo(bOnline);
        });

        // Merge unread counts from conversations
        final unreadMap = <String, int>{};
        for (final c in game.dmConversations) {
          final partner = c['partner'] as String? ?? '';
          final count = c['unread_count'] as int? ?? 0;
          if (partner.isNotEmpty && count > 0) unreadMap[partner] = count;
        }

        if (sorted.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.people_outline, size: 48, color: Color(0xFFBDBDBD)),
                SizedBox(height: 12),
                Text(
                  '친구가 없어요!\n검색 탭에서 친구를 추가해보세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Color(0xFF9A8E8A)),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: sorted.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final friend = sorted[index];
            final nickname = friend['nickname'] as String? ?? '';
            final isOnline = friend['isOnline'] == true;
            final roomName = friend['roomName'] as String?;
            final unread = unreadMap[nickname] ?? 0;

            String statusText;
            if (isOnline && roomName != null && roomName.isNotEmpty) {
              statusText = '$roomName에서 게임중';
            } else if (isOnline) {
              statusText = '온라인';
            } else {
              statusText = '오프라인';
            }

            return GestureDetector(
              onTap: () => _openDmChat(nickname),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isOnline ? const Color(0xFFC8E6C9) : const Color(0xFFE0D6D0),
                  ),
                ),
                child: Row(
                  children: [
                    // Online indicator
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isOnline ? const Color(0xFF4CAF50) : const Color(0xFFBDBDBD),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Name & status
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  nickname,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF5A4038),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (unread > 0) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE53935),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '$unread',
                                    style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 11,
                              color: isOnline ? const Color(0xFF4CAF50) : const Color(0xFF9A8E8A),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Action buttons
                    if (isOnline && friend['roomId'] == null && game.currentRoomId.isNotEmpty)
                      _buildActionChip('초대', Icons.send, const Color(0xFF1976D2), const Color(0xFFE3F2FD), () {
                        game.inviteToRoom(nickname);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$nickname님에게 초대를 보냈습니다')),
                        );
                      }),
                    if (friend['roomId'] != null && game.currentRoomId.isEmpty)
                      _buildRoomActionChip(friend, game),
                    const SizedBox(width: 4),
                    // Remove friend
                    GestureDetector(
                      onTap: () => _showRemoveFriendConfirmation(nickname, game),
                      child: Container(
                        padding: const EdgeInsets.all(6),
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
        );
      },
    );
  }

  Widget _buildActionChip(String label, IconData icon, Color color, Color bg, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoomActionChip(Map<String, dynamic> friend, GameService game) {
    final roomId = friend['roomId'] as String;
    final roomInGame = friend['roomInGame'] == true;
    final roomPlayerCount = friend['roomPlayerCount'] as int? ?? 4;
    final roomPassword = friend['roomPassword'] as String? ?? '';
    final canJoin = !roomInGame && roomPlayerCount < 4;

    return _buildActionChip(
      canJoin ? '입장' : '관전',
      canJoin ? Icons.login : Icons.visibility,
      canJoin ? const Color(0xFF388E3C) : const Color(0xFFE65100),
      canJoin ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
      () {
        Navigator.pop(context);
        if (canJoin) {
          game.joinRoom(roomId, password: roomPassword);
        } else {
          game.spectateRoom(roomId, password: roomPassword);
        }
      },
    );
  }

  // === Tab 1: Search ===
  Widget _buildSearchTab() {
    return Consumer<GameService>(
      builder: (context, game, _) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: '닉네임으로 검색',
                  hintStyle: const TextStyle(color: Color(0xFFBDBDBD), fontSize: 14),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF8A7A72)),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            game.clearSearchResults();
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.85),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
            Expanded(
              child: game.searchResults.isEmpty
                  ? Center(
                      child: Text(
                        _searchController.text.isEmpty ? '닉네임을 입력하여 검색하세요' : '검색 결과가 없습니다',
                        style: const TextStyle(fontSize: 14, color: Color(0xFF9A8E8A)),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: game.searchResults.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final user = game.searchResults[index];
                        final nickname = user['nickname'] as String? ?? '';
                        final friendStatus = user['friendStatus'] as String? ?? 'none';

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.85),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: const Color(0xFFCE93D8),
                                child: Text(
                                  nickname.isNotEmpty ? nickname[0] : '?',
                                  style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  nickname,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF5A4038),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              _buildFriendStatusButton(nickname, friendStatus, game),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFriendStatusButton(String nickname, String status, GameService game) {
    switch (status) {
      case 'friend':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check, size: 14, color: Color(0xFF4CAF50)),
              SizedBox(width: 4),
              Text('친구', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4CAF50))),
            ],
          ),
        );
      case 'pending_incoming':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3E0),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text('요청 받음', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFE65100))),
        );
      case 'pending_outgoing':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFE3F2FD),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text('요청 보냄', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1976D2))),
        );
      default:
        return GestureDetector(
          onTap: () {
            game.addFriendAction(nickname);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$nickname님에게 친구 요청을 보냈습니다')),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF7E57C2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_add, size: 14, color: Colors.white),
                SizedBox(width: 4),
                Text('친구 추가', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
              ],
            ),
          ),
        );
    }
  }

  // === Tab 2: Friend Requests ===
  Widget _buildRequestsTab() {
    return Consumer<GameService>(
      builder: (context, game, _) {
        if (game.pendingFriendRequests.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.mail_outline, size: 48, color: Color(0xFFBDBDBD)),
                SizedBox(height: 12),
                Text(
                  '받은 요청이 없습니다',
                  style: TextStyle(fontSize: 14, color: Color(0xFF9A8E8A)),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: game.pendingFriendRequests.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final nickname = game.pendingFriendRequests[index];
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.85),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFCE93D8).withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xFFCE93D8),
                    child: Text(
                      nickname.isNotEmpty ? nickname[0] : '?',
                      style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      nickname,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF5A4038),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      game.acceptFriendRequest(nickname);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$nickname님과 친구가 되었습니다')),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF81C784),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '수락',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () {
                      game.rejectFriendRequest(nickname);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE57373),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '거절',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // === DM Chat View ===
  Widget _buildDmChatView(List<Color> themeColors) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: themeColors,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // DM header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _closeDmChat,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.arrow_back, size: 20, color: Color(0xFF5A4038)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _dmChatPartner ?? '',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF5A4038),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              // Messages
              Expanded(
                child: Consumer<GameService>(
                  builder: (context, game, _) {
                    final messages = game.dmMessages[_dmChatPartner] ?? [];
                    if (messages.isEmpty) {
                      return const Center(
                        child: Text(
                          '메시지가 없습니다.\n첫 메시지를 보내보세요!',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: Color(0xFF9A8E8A)),
                        ),
                      );
                    }
                    return ListView.builder(
                      controller: _dmScrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: messages.length + (_dmLoadingMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (_dmLoadingMore && index == 0) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(8),
                              child: SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          );
                        }
                        final msgIndex = _dmLoadingMore ? index - 1 : index;
                        final msg = messages[msgIndex];
                        final isMine = msg['sender'] == game.playerName;
                        return _buildMessageBubble(msg, isMine);
                      },
                    );
                  },
                ),
              ),
              // Input
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _dmInputController,
                        maxLength: 500,
                        maxLines: 3,
                        minLines: 1,
                        decoration: InputDecoration(
                          hintText: '메시지를 입력하세요',
                          hintStyle: const TextStyle(color: Color(0xFFBDBDBD), fontSize: 14),
                          counterText: '',
                          filled: true,
                          fillColor: const Color(0xFFF5F0ED),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        onSubmitted: (_) => _sendDm(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _sendDm,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: const BoxDecoration(
                          color: Color(0xFF7E57C2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.send, size: 18, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, bool isMine) {
    final message = msg['message'] as String? ?? '';
    final createdAt = msg['createdAt']?.toString() ?? '';
    String timeStr = '';
    if (createdAt.isNotEmpty) {
      try {
        final dt = DateTime.parse(createdAt).toLocal();
        timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isMine && timeStr.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 4, bottom: 2),
              child: Text(timeStr, style: const TextStyle(fontSize: 10, color: Color(0xFF9A8E8A))),
            ),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMine ? const Color(0xFF7E57C2) : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: isMine ? const Radius.circular(16) : const Radius.circular(4),
                  bottomRight: isMine ? const Radius.circular(4) : const Radius.circular(16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 14,
                  color: isMine ? Colors.white : const Color(0xFF5A4038),
                ),
              ),
            ),
          ),
          if (!isMine && timeStr.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(timeStr, style: const TextStyle(fontSize: 10, color: Color(0xFF9A8E8A))),
            ),
        ],
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
}
