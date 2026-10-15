import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../utils/chat_day.dart';
import '../utils/friend_order.dart';
import '../utils/last_seen.dart';
import '../services/game_service.dart';
import '../widgets/player_profile_dialog.dart';
import '../theme/cartoon.dart';
import '../widgets/profile_identity_cell.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key, this.allowDmChat = true});

  final bool allowDmChat;

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  GameService? _gameService;

  // DM chat state
  String? _dmChatPartner;
  final TextEditingController _dmInputController = TextEditingController();
  final ScrollController _dmScrollController = ScrollController();
  bool _dmLoadingMore = false;
  DateTime? _lastBlockedDmNoticeAt;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final game = context.read<GameService>();
      _gameService = game;
      game.requestFriends();
      game.requestPendingFriendRequests();
      game.requestSentFriendRequests();
      game.requestDmConversations();
      game.requestUnreadDmCount();
    });
    _dmScrollController.addListener(_onDmScroll);
  }

  @override
  void dispose() {
    _gameService?.setActiveDmPartner(null);
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
    if (_dmScrollController.position.pixels <= 0 &&
        !_dmLoadingMore &&
        _dmChatPartner != null) {
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
    if (!widget.allowDmChat) {
      final now = DateTime.now();
      if (_lastBlockedDmNoticeAt == null ||
          now.difference(_lastBlockedDmNoticeAt!) >
              const Duration(seconds: 2)) {
        _lastBlockedDmNoticeAt = now;
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(content: Text(L10n.of(context).friendsDmBlockedDuringGame)),
        );
      }
      return;
    }
    final game = context.read<GameService>();
    _gameService = game;
    game.requestDmHistory(partner);
    game.markDmReadAction(partner);
    game.setActiveDmPartner(partner);
    setState(() => _dmChatPartner = partner);
  }

  void _closeDmChat() {
    _gameService?.setActiveDmPartner(null);
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
      return Theme(
        data: cartoonTheme(Theme.of(context)),
        child: _buildDmChatView(themeColors),
      );
    }

    return Theme(
      data: cartoonTheme(Theme.of(context)),
      child: Scaffold(
        // On the web the engine has already shrunk its canvas to the visual
        // viewport by the time the keyboard is up, so letting the Scaffold
        // subtract viewInsets on top of that takes the keyboard height off
        // twice and leaves an empty band above the keyboard. Native keeps the
        // default, where the inset is the only thing doing the resizing.
        resizeToAvoidBottomInset: kIsWeb ? false : null,
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: themeColors,
            ),
          ),
          child: SafeArea(
            bottom: false,
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
      ),
    );
  }

  Widget _headerChip({
    required IconData icon,
    required VoidCallback onTap,
    Color color = Cartoon.ink,
  }) {
    return CartoonPressable(
      scale: 0.88,
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Cartoon.paper,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Cartoon.ink, width: 2.5),
          boxShadow: const [
            BoxShadow(color: Cartoon.ink, offset: Offset(0, 3)),
          ],
        ),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }

  Widget _buildAppBar() {
    return CartoonEntrance(
      from: const Offset(0, -30),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            _headerChip(
              icon: Icons.arrow_back_rounded,
              onTap: () => Navigator.pop(context),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Cartoon.outlinedText(
                L10n.of(context).friendsTitle,
                size: 28,
                maxLines: 1,
              ),
            ),
            const Spacer(),
            _headerChip(icon: Icons.refresh_rounded, onTap: _refreshFriends),
          ],
        ),
      ),
    );
  }

  /// 친구 · 검색 · 요청 — 알약 세 칸 토글. 안 읽은 DM / 받은 요청 수는 칸 안 배지로.
  Widget _buildTabBar() {
    return Consumer<GameService>(
      builder: (context, game, _) {
        final l10n = L10n.of(context);
        return AnimatedBuilder(
          animation: _tabController.animation ?? _tabController,
          builder: (context, _) {
            Widget seg(int i, String label, IconData icon, int badge) {
              final on = _tabController.index == i;
              return Expanded(
                child: CartoonPressable(
                  scale: 0.95,
                  onTap: () => _tabController.animateTo(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 42,
                    decoration: BoxDecoration(
                      color: on ? Cartoon.orange : Colors.transparent,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: on ? Cartoon.ink : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          icon,
                          size: 19,
                          color: on ? Colors.white : Cartoon.ink,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: on
                              ? Cartoon.outlinedText(
                                  label,
                                  size: 15,
                                  maxLines: 1,
                                )
                              : Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Cartoon.text(size: 15),
                                ),
                        ),
                        if (badge > 0) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Cartoon.red,
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                color: Cartoon.ink,
                                width: 1.8,
                              ),
                            ),
                            child: Text(
                              badge > 99 ? '99+' : '$badge',
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Cartoon.cream,
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(color: Cartoon.ink, width: 2.5),
                ),
                child: Row(
                  children: [
                    seg(
                      0,
                      l10n.friendsTabFriends,
                      Icons.people_rounded,
                      game.totalUnreadDmCount,
                    ),
                    const SizedBox(width: 3),
                    seg(1, l10n.friendsTabSearch, Icons.search_rounded, 0),
                    const SizedBox(width: 3),
                    seg(
                      2,
                      l10n.friendsTabRequests,
                      Icons.mail_rounded,
                      game.pendingFriendRequestCount,
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

  /// 빈 화면: 졸고 있는 마스코트 + 한 줄 안내.
  Widget _emptyState(String text) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CartoonFloat(
          amplitude: 8,
          child: Image.asset(
            'assets/dragonIcon.webp',
            width: 88,
            height: 88,
            color: Colors.white.withValues(alpha: 0.35),
            colorBlendMode: BlendMode.modulate,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: Cartoon.userText(
              size: 15,
              color: Cartoon.ink.withValues(alpha: 0.7),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  // === Tab 0: Friends List ===
  Widget _buildFriendsTab() {
    return Consumer<GameService>(
      builder: (context, game, _) {
        // Unread counts first: they decide the order, not just the badge.
        final unreadMap = <String, int>{};
        for (final c in game.dmConversations) {
          final partner = c['partner'] as String? ?? '';
          final count = c['unread_count'] as int? ?? 0;
          if (partner.isNotEmpty && count > 0) unreadMap[partner] = count;
        }
        // Waiting for a reply → online → most recently seen. See sortFriends.
        final sorted = sortFriends(game.friendsData, unreadMap);

        Future<void> onRefresh() async {
          _refreshFriends();
          await Future.delayed(const Duration(milliseconds: 500));
        }

        if (sorted.isEmpty) {
          return RefreshIndicator(
            onRefresh: onRefresh,
            child: _fillScrollable(
              _emptyState(L10n.of(context).friendsEmptyList),
            ),
          );
        }

        // 접속 중 / 오프라인 머리글. 정렬은 이미 "답장 대기 → 접속 중 → 최근
        // 접속" 이라, 접속 여부가 바뀌는 지점에 글머리만 끼워 넣는다.
        final l10n = L10n.of(context);
        final onlineCount = sorted.where((f) => f['isOnline'] == true).length;
        final rows = <Object>[];
        bool? lastOnline;
        for (final f in sorted) {
          final online = f['isOnline'] == true;
          if (online != lastOnline) {
            rows.add(
              online
                  ? '${l10n.friendsStatusOnline} · $onlineCount'
                  : '${l10n.friendsStatusOffline} · ${sorted.length - onlineCount}',
            );
            lastOnline = online;
          }
          rows.add(f);
        }

        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              14,
              4,
              14,
              24 + MediaQuery.viewPaddingOf(context).bottom,
            ),
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              if (row is String) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(2, 8, 0, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Cartoon.cream,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Cartoon.ink, width: 2),
                      ),
                      child: Text(row, style: Cartoon.text(size: 14)),
                    ),
                  ),
                );
              }
              final friend = row as Map<String, dynamic>;
              final nickname = friend['nickname'] as String? ?? '';
              final isOnline = friend['isOnline'] == true;
              final roomName = friend['roomName'] as String?;
              final unread = unreadMap[nickname] ?? 0;

              String statusText;
              if (isOnline && roomName != null && roomName.isNotEmpty) {
                statusText = l10n.friendsStatusPlayingInRoom(roomName);
              } else if (isOnline) {
                statusText = l10n.friendsStatusOnline;
              } else {
                // The dot already says offline; the line beneath is better
                // spent on when they were last here.
                statusText =
                    _lastSeenText(l10n, friend['lastSeenAt'] as String?) ??
                    l10n.friendsStatusOffline;
              }

              return CartoonEntrance(
                key: ValueKey('friend-$nickname'),
                delay: Duration(milliseconds: 35 * index.clamp(0, 7)),
                from: const Offset(0, 16),
                pop: false,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: ProfileIdentityCell(
                    game: game,
                    nickname: nickname,
                    photoUrl: friend['photoUrl'] as String?,
                    bannerKey: friend['bannerKey'] as String?,
                    titleKey: friend['titleKey'] as String?,
                    titleName: friend['titleName'] as String?,
                    level: friend['level'] as int?,
                    isOnline: isOnline,
                    subtitle: statusText,
                    subtitleColor: isOnline
                        ? const Color(0xFF2E8B57)
                        : Cartoon.ink.withValues(alpha: 0.5),
                    // Tapping the row opens who they are. Talking to them is a
                    // button — a whole row that means "chat" gives the profile
                    // no way in except a small icon, and looking someone up is
                    // the more common reason to be here.
                    onTap: () =>
                        showPlayerProfileDialog(context, nickname, game),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!widget.allowDmChat)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFE9B8),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Cartoon.ink,
                                  width: 1.8,
                                ),
                              ),
                              child: Text(
                                l10n.friendsRestrictedDuringGame,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFFB45309),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        if (isOnline &&
                            friend['roomId'] == null &&
                            game.isInWaitingRoom)
                          game.isRoomInvitePending(nickname)
                              ? _buildActionChip(
                                  l10n.friendsInvited,
                                  Icons.schedule_rounded,
                                  const Color(0xFF8A8A8A),
                                  const Color(0xFFF1F1F1),
                                  () {},
                                )
                              : _buildActionChip(
                                  l10n.friendsInvite,
                                  Icons.send_rounded,
                                  Colors.white,
                                  Cartoon.blue,
                                  () {
                                    game.inviteToRoom(nickname);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          l10n.friendsInviteSent(nickname),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        if (friend['roomId'] != null &&
                            game.currentRoomId.isEmpty)
                          _buildRoomActionChip(friend, game),
                        // 채팅: 가장 자주 쓰는 동작이라 눈에 띄는 노란 칩.
                        _iconTapTarget(
                          onTap: () => _openDmChat(nickname),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: Cartoon.yellow,
                                  borderRadius: BorderRadius.circular(11),
                                  border: Border.all(
                                    color: Cartoon.ink,
                                    width: 2.2,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Cartoon.ink,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.chat_bubble_rounded,
                                  size: 17,
                                  color: Cartoon.ink,
                                ),
                              ),
                              // On the button it belongs to, not adrift in the
                              // row: the count is about messages, and messages
                              // are what that button opens.
                              if (unread > 0)
                                Positioned(
                                  right: -6,
                                  top: -7,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Cartoon.red,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Cartoon.ink,
                                        width: 1.8,
                                      ),
                                    ),
                                    child: Text(
                                      unread > 99 ? '99+' : '$unread',
                                      style: const TextStyle(
                                        fontSize: 9.5,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // 친구 삭제는 줄에 늘 떠 있던 빨간 아이콘이 아니라 ⋯ 메뉴
                        // 뒤로 — 채팅 옆에 있어서 잘못 누르기 쉬웠다.
                        PopupMenuButton<String>(
                          tooltip: '',
                          padding: EdgeInsets.zero,
                          icon: const Icon(
                            Icons.more_vert_rounded,
                            color: Cartoon.ink,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: const BorderSide(
                              color: Cartoon.ink,
                              width: 2.5,
                            ),
                          ),
                          color: Cartoon.paper,
                          onSelected: (v) {
                            if (v == 'remove') {
                              _showRemoveFriendConfirmation(nickname, game);
                            }
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'remove',
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.person_remove_rounded,
                                    color: Color(0xFFE5484D),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    l10n.friendsRemoveTitle,
                                    style: Cartoon.text(
                                      size: 15,
                                      color: const Color(0xFFE5484D),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  // 44x44 tap target around a small icon chip (visual stays compact, hit area
  // meets the 44px guideline). Nickname lives in an Expanded so this won't overflow.
  Widget _iconTapTarget({required VoidCallback onTap, required Widget child}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(width: 44, height: 44, child: Center(child: child)),
    );
  }

  void _refreshFriends() {
    final game = context.read<GameService>();
    game.requestFriends();
    game.requestPendingFriendRequests();
    game.requestSentFriendRequests();
    game.requestDmConversations();
  }

  // Scrollable wrapper so RefreshIndicator can pull on empty states too.
  Widget _fillScrollable(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: child),
        ),
      ),
    );
  }

  /// "3시간 전 접속", or null when there is nothing to say.
  ///
  /// Parsed as UTC and compared in UTC: the server sends an ISO string with no
  /// offset, and reading it as local time on a KST phone would put every
  /// friend nine hours in the future — which the bucket would then round down
  /// to "방금", hiding the bug rather than showing it.
  String? _lastSeenText(L10n l10n, String? iso) {
    if (iso == null || iso.isEmpty) return null;
    final parsed = DateTime.tryParse(iso.endsWith('Z') ? iso : '${iso}Z');
    if (parsed == null) return null;
    final seen = lastSeenBucket(parsed, DateTime.now().toUtc());
    return switch (seen.unit) {
      LastSeenUnit.justNow => l10n.friendsLastSeenJustNow,
      LastSeenUnit.minutes => l10n.friendsLastSeenMinutes(seen.amount),
      LastSeenUnit.hours => l10n.friendsLastSeenHours(seen.amount),
      LastSeenUnit.days => l10n.friendsLastSeenDays(seen.amount),
      LastSeenUnit.longAgo => l10n.friendsLastSeenLongAgo,
    };
  }

  Widget _buildActionChip(
    String label,
    IconData icon,
    Color color,
    Color bg,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: CartoonPressable(
        scale: 0.92,
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: Cartoon.ink, width: 2.2),
            boxShadow: const [
              BoxShadow(color: Cartoon.ink, offset: Offset(0, 2)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 4),
              Text(label, style: Cartoon.text(size: 13, color: color)),
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

    final l10n = L10n.of(context);
    return _buildActionChip(
      canJoin ? l10n.friendsJoinRoom : l10n.friendsSpectateRoom,
      canJoin ? Icons.login_rounded : Icons.visibility_rounded,
      Colors.white,
      canJoin ? Cartoon.green : Cartoon.orange,
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
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: Cartoon.userText(size: 16),
                decoration:
                    Cartoon.inputDecoration(
                      hint: L10n.of(context).friendsSearchHint,
                      icon: Icons.search_rounded,
                    ).copyWith(
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded, size: 20),
                              onPressed: () {
                                _searchController.clear();
                                game.clearSearchResults();
                              },
                            )
                          : null,
                    ),
              ),
            ),
            Expanded(
              child: game.searchResults.isEmpty
                  ? Center(
                      child: _emptyState(
                        _searchController.text.isEmpty
                            ? L10n.of(context).friendsSearchPrompt
                            : L10n.of(context).friendsSearchNoResults,
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.fromLTRB(
                        14,
                        2,
                        14,
                        24 + MediaQuery.viewPaddingOf(context).bottom,
                      ),
                      itemCount: game.searchResults.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 9),
                      itemBuilder: (context, index) {
                        final user = game.searchResults[index];
                        final nickname = user['nickname'] as String? ?? '';
                        final friendStatus =
                            user['friendStatus'] as String? ?? 'none';

                        return ProfileIdentityCell(
                          game: game,
                          nickname: nickname,
                          photoUrl: user['photoUrl'] as String?,
                          bannerKey: user['bannerKey'] as String?,
                          titleKey: user['titleKey'] as String?,
                          titleName: user['titleName'] as String?,
                          level: user['level'] as int?,
                          isPrivate: user['isPrivate'] == true,
                          // Capped: "Freund hinzufügen" is wide enough in
                          // German to push the nickname into an ellipsis, and
                          // the nickname is the thing being searched for.
                          trailing: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 132),
                            child: _buildFriendStatusButton(
                              nickname,
                              friendStatus,
                              game,
                            ),
                          ),
                          onTap: nickname.isEmpty
                              ? null
                              : () => showPlayerProfileDialog(
                                  context,
                                  nickname,
                                  game,
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

  Widget _buildFriendStatusButton(
    String nickname,
    String status,
    GameService game,
  ) {
    final l10n = L10n.of(context);
    // One word per state, and it yields before the nickname does: these sit in
    // a row beside the name, and the German for "add friend" is twice the
    // width of the English.
    Widget chip(
      IconData? icon,
      String text,
      Color fg,
      Color bg, {
      VoidCallback? onTap,
    }) {
      final body = Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Cartoon.ink, width: 2.2),
          boxShadow: onTap == null
              ? null
              : const [BoxShadow(color: Cartoon.ink, offset: Offset(0, 2))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Cartoon.userText(
                  size: 13,
                  weight: FontWeight.w900,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      );
      return onTap == null
          ? body
          : CartoonPressable(scale: 0.92, onTap: onTap, child: body);
    }

    switch (status) {
      case 'friend':
        return chip(
          Icons.check_rounded,
          l10n.friendsStatusFriend,
          const Color(0xFF2E8B57),
          const Color(0xFFD8F5DF),
        );
      case 'pending_incoming':
        return chip(
          null,
          l10n.friendsStatusReceivedShort,
          const Color(0xFFB45309),
          const Color(0xFFFFE9B8),
        );
      case 'pending_outgoing':
        return chip(
          Icons.close_rounded,
          l10n.friendsStatusPendingShort,
          const Color(0xFF1E6FD0),
          const Color(0xFFDCEBFF),
          onTap: () {
            game.cancelFriendRequestAction(nickname);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.gameFriendRequestCancelled)),
            );
          },
        );
      default:
        return chip(
          Icons.person_add_rounded,
          l10n.gameAddFriend,
          Colors.white,
          Cartoon.green,
          onTap: () {
            game.addFriendAction(nickname);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.friendsRequestSentSnackbar(nickname)),
              ),
            );
          },
        );
    }
  }

  // === Tab 2: Friend Requests ===
  Widget _buildRequestsTab() {
    return Consumer<GameService>(
      builder: (context, game, _) {
        final received = game.pendingFriendRequests;
        final sent = game.sentFriendRequestsDetailed;
        if (received.isEmpty && sent.isEmpty) {
          return Center(child: _emptyState(L10n.of(context).friendsNoRequests));
        }

        final l10n = L10n.of(context);
        // A section label only earns its place once there are two kinds of
        // request to tell apart — with just one list, the old unlabeled
        // layout already read fine and a header would be pure clutter.
        final showLabels = received.isNotEmpty && sent.isNotEmpty;
        return ListView(
          padding: EdgeInsets.fromLTRB(
            14,
            4,
            14,
            24 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          children: [
            if (received.isNotEmpty) ...[
              if (showLabels)
                _buildRequestsSectionLabel(l10n.friendsReceivedSection),
              for (final nickname in received) ...[
                _buildReceivedRequestCard(context, game, nickname),
                const SizedBox(height: 9),
              ],
            ],
            if (sent.isNotEmpty) ...[
              if (showLabels) ...[
                const SizedBox(height: 4),
                _buildRequestsSectionLabel(l10n.friendsSentSection),
              ],
              for (final req in sent) ...[
                _buildSentRequestCard(context, game, req),
                const SizedBox(height: 8),
              ],
            ],
          ],
        );
      },
    );
  }

  Widget _buildRequestsSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          decoration: BoxDecoration(
            color: Cartoon.cream,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Cartoon.ink, width: 2),
          ),
          child: Text(text, style: Cartoon.text(size: 14)),
        ),
      ),
    );
  }

  Widget _requestActionButton(String label, Color color, VoidCallback onTap) {
    // Its own tap target, deliberately not the row's — the row opens the
    // profile (same as everywhere else a person is listed); this is the one
    // thing on the row that does something else.
    return CartoonPressable(
      scale: 0.92,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Cartoon.ink, width: 2.2),
          boxShadow: const [
            BoxShadow(color: Cartoon.ink, offset: Offset(0, 2)),
          ],
        ),
        child: Text(label, style: Cartoon.text(size: 14, color: Colors.white)),
      ),
    );
  }

  /// Row data for one request, looked up from the server-enriched detail
  /// list by nickname. Falls back to a bare nickname-only map — the enriched
  /// fetch can lag a beat behind the plain list (e.g. right after a live
  /// friend_request_received push) and the row should still render rather
  /// than disappear or throw.
  Map<String, dynamic> _requestDetail(
    List<Map<String, dynamic>> detailed,
    String nickname,
  ) {
    return detailed.firstWhere(
      (r) => r['nickname'] == nickname,
      orElse: () => {'nickname': nickname},
    );
  }

  Widget _buildReceivedRequestCard(
    BuildContext context,
    GameService game,
    String nickname,
  ) {
    final detail = _requestDetail(game.pendingFriendRequestsDetailed, nickname);
    final l10n = L10n.of(context);
    return ProfileIdentityCell(
      game: game,
      nickname: nickname,
      photoUrl: detail['photoUrl'] as String?,
      bannerKey: detail['bannerKey'] as String?,
      titleKey: detail['titleKey'] as String?,
      titleName: detail['titleName'] as String?,
      level: detail['level'] as int?,
      onTap: () => showPlayerProfileDialog(context, nickname, game),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _requestActionButton(l10n.friendsAccept, Cartoon.green, () {
            game.acceptFriendRequest(nickname);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.friendsAccepted(nickname))),
            );
          }),
          const SizedBox(width: 6),
          _requestActionButton(l10n.friendsReject, Cartoon.red, () {
            game.rejectFriendRequest(nickname);
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(l10n.friendsRejected)));
          }),
        ],
      ),
    );
  }

  /// "3시간 전 요청" — same bucketing as _lastSeenText, different wording:
  /// this is when a request was sent, not when someone was last online.
  String _sentAgoText(L10n l10n, dynamic createdAt) {
    final iso = createdAt?.toString();
    if (iso == null || iso.isEmpty) return '';
    final parsed = DateTime.tryParse(iso.endsWith('Z') ? iso : '${iso}Z');
    if (parsed == null) return '';
    final bucket = lastSeenBucket(parsed, DateTime.now().toUtc());
    return switch (bucket.unit) {
      LastSeenUnit.justNow => l10n.friendsSentAgoJustNow,
      LastSeenUnit.minutes => l10n.friendsSentAgoMinutes(bucket.amount),
      LastSeenUnit.hours => l10n.friendsSentAgoHours(bucket.amount),
      LastSeenUnit.days => l10n.friendsSentAgoDays(bucket.amount),
      LastSeenUnit.longAgo => l10n.friendsSentAgoLongAgo,
    };
  }

  Widget _buildSentRequestCard(
    BuildContext context,
    GameService game,
    Map<String, dynamic> request,
  ) {
    final nickname = request['nickname'] as String? ?? '';
    final l10n = L10n.of(context);
    final agoText = _sentAgoText(l10n, request['createdAt']);
    return ProfileIdentityCell(
      game: game,
      nickname: nickname,
      photoUrl: request['photoUrl'] as String?,
      bannerKey: request['bannerKey'] as String?,
      titleKey: request['titleKey'] as String?,
      titleName: request['titleName'] as String?,
      level: request['level'] as int?,
      subtitle: agoText.isEmpty ? null : agoText,
      onTap: () => showPlayerProfileDialog(context, nickname, game),
      trailing: _requestActionButton(
        l10n.friendsCancelRequest,
        const Color(0xFF90A4AE),
        () {
          game.cancelFriendRequestAction(nickname);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.gameFriendRequestCancelled)),
          );
        },
      ),
    );
  }

  // === DM Chat View ===
  Widget _buildDmChatView(List<Color> themeColors) {
    return Scaffold(
      // On the web the engine has already shrunk its canvas to the visual
      // viewport by the time the keyboard is up, so letting the Scaffold
      // subtract viewInsets on top of that takes the keyboard height off
      // twice and leaves an empty band above the keyboard. Native keeps the
      // default, where the inset is the only thing doing the resizing.
      resizeToAvoidBottomInset: kIsWeb ? false : null,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: themeColors,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // DM header: 뒤로 칩 + 상대 이름
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Row(
                  children: [
                    _headerChip(
                      icon: Icons.arrow_back_rounded,
                      onTap: _closeDmChat,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        decoration: Cartoon.panelDecoration(
                          radius: 16,
                          shadowOffset: 3,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.chat_bubble_rounded,
                              size: 20,
                              color: Cartoon.orangeDeep,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _dmChatPartner ?? '',
                                style: Cartoon.userText(
                                  size: 19,
                                  weight: FontWeight.w900,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
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
                      return Center(
                        child: _emptyState(L10n.of(context).friendsDmEmpty),
                      );
                    }
                    return ListView.builder(
                      controller: _dmScrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      itemCount: messages.length + (_dmLoadingMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (_dmLoadingMore && index == 0) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(8),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  color: Cartoon.orange,
                                ),
                              ),
                            ),
                          );
                        }
                        final msgIndex = _dmLoadingMore ? index - 1 : index;
                        final msg = messages[msgIndex];
                        final isMine = msg['sender'] == game.playerName;
                        final bubble = _buildMessageBubble(msg, isMine);
                        // Bubbles carry a clock time and nothing else, so a
                        // conversation spread over weeks read as one long
                        // afternoon. The divider is what says which day you
                        // are looking at.
                        if (!needsDayDivider(messages, msgIndex, _dmSentAt)) {
                          return bubble;
                        }
                        return Column(
                          children: [_buildDayDivider(_dmSentAt(msg)!), bubble],
                        );
                      },
                    );
                  },
                ),
              ),
              // Input
              Container(
                padding: EdgeInsets.fromLTRB(
                  12,
                  10,
                  12,
                  10 + MediaQuery.viewPaddingOf(context).bottom,
                ),
                decoration: const BoxDecoration(
                  color: Cartoon.paper,
                  border: Border(
                    top: BorderSide(color: Cartoon.ink, width: 2.5),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _dmInputController,
                        maxLength: 500,
                        maxLines: 3,
                        minLines: 1,
                        style: Cartoon.userText(
                          size: 15,
                          weight: FontWeight.w500,
                        ),
                        decoration: Cartoon.inputDecoration(
                          hint: L10n.of(context).friendsDmInputHint,
                          radius: 20,
                        ).copyWith(counterText: ''),
                        onSubmitted: (_) => _sendDm(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    CartoonPressable(
                      scale: 0.88,
                      onTap: _sendDm,
                      child: Container(
                        width: 50,
                        height: 50,
                        margin: const EdgeInsets.only(bottom: 3),
                        decoration: BoxDecoration(
                          color: Cartoon.orange,
                          shape: BoxShape.circle,
                          border: Border.all(color: Cartoon.ink, width: 2.5),
                          boxShadow: const [
                            BoxShadow(color: Cartoon.ink, offset: Offset(0, 3)),
                          ],
                        ),
                        child: const Icon(
                          Icons.send_rounded,
                          size: 22,
                          color: Colors.white,
                        ),
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

  /// A message's local send time, or null when it has none.
  ///
  /// Parsed as UTC: the server sends an ISO string without an offset, and
  /// reading it as local time would put every message nine hours out on a KST
  /// phone — enough to file a late-evening message under the following day.
  DateTime? _dmSentAt(Map<String, dynamic> msg) {
    final raw = msg['createdAt']?.toString() ?? '';
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw.endsWith('Z') ? raw : '${raw}Z')?.toLocal();
  }

  /// The "오늘 / 어제 / 2026년 8월 13일" rule above a day's first message.
  Widget _buildDayDivider(DateTime day) {
    final l10n = L10n.of(context);
    final label = switch (chatDayLabel(day, DateTime.now())) {
      ChatDayLabel.today => l10n.chatToday,
      ChatDayLabel.yesterday => l10n.chatYesterday,
      ChatDayLabel.date => l10n.chatDate(day.year, day.month, day.day),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: Cartoon.ink.withValues(alpha: 0.18),
              thickness: 1.5,
              height: 1,
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            decoration: BoxDecoration(
              color: Cartoon.cream,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Cartoon.ink, width: 2),
            ),
            child: Text(label, style: Cartoon.text(size: 12.5)),
          ),
          Expanded(
            child: Divider(
              color: Cartoon.ink.withValues(alpha: 0.18),
              thickness: 1.5,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, bool isMine) {
    final message = msg['message'] as String? ?? '';
    final dt = _dmSentAt(msg);
    final timeStr = dt == null
        ? ''
        : '${dt.hour.toString().padLeft(2, '0')}'
              ':${dt.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isMine && timeStr.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 4, bottom: 2),
              child: Text(
                timeStr,
                style: TextStyle(
                  fontSize: 10.5,
                  color: Cartoon.ink.withValues(alpha: 0.5),
                ),
              ),
            ),
          Flexible(
            child: Container(
              margin: const EdgeInsets.only(bottom: 3),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMine ? Cartoon.orange : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: isMine
                      ? const Radius.circular(18)
                      : const Radius.circular(4),
                  bottomRight: isMine
                      ? const Radius.circular(4)
                      : const Radius.circular(18),
                ),
                border: Border.all(color: Cartoon.ink, width: 2.2),
                boxShadow: const [
                  BoxShadow(color: Cartoon.ink, offset: Offset(0, 2)),
                ],
              ),
              child: Text(
                message,
                style: Cartoon.userText(
                  size: 15,
                  weight: FontWeight.w600,
                  color: isMine ? Colors.white : Cartoon.ink,
                  height: 1.35,
                ),
              ),
            ),
          ),
          if (!isMine && timeStr.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(
                timeStr,
                style: TextStyle(
                  fontSize: 10.5,
                  color: Cartoon.ink.withValues(alpha: 0.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showRemoveFriendConfirmation(String nickname, GameService game) {
    final l10n = L10n.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.friendsRemoveTitle),
        content: Text(l10n.friendsRemoveConfirm(nickname)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.commonCancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              game.removeFriendAction(nickname);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.friendsRemoved(nickname))),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE57373),
              foregroundColor: Colors.white,
            ),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
  }
}
