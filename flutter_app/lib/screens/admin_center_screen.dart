import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/game_service.dart';

class AdminCenterScreen extends StatefulWidget {
  const AdminCenterScreen({super.key});

  @override
  State<AdminCenterScreen> createState() => _AdminCenterScreenState();
}

class _AdminCenterScreenState extends State<AdminCenterScreen> {
  final TextEditingController _searchController = TextEditingController();
  static const _panelColor = Color(0xFFF9F5F3);
  static const _inkColor = Color(0xFF5A4038);
  static const _mutedColor = Color(0xFF8A7A72);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final game = context.read<GameService>();
      game.requestAdminDashboard();
      game.requestAdminInquiries();
      game.requestAdminReports();
      game.requestAdminUsers();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeColors = context.watch<GameService>().themeGradient;
    return DefaultTabController(
      length: 3,
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
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  if (game.adminActionSuccess != null) {
                    final success = game.adminActionSuccess == true;
                    final message = game.adminActionMessage ?? (success ? '처리되었습니다' : '실패했습니다');
                    game.adminActionSuccess = null;
                    game.adminActionMessage = null;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(message),
                        backgroundColor: success ? Colors.green : Colors.red,
                      ),
                    );
                    game.requestAdminDashboard();
                    game.requestAdminInquiries();
                    game.requestAdminReports();
                    game.requestAdminUsers(search: _searchController.text.trim());
                  }
                });

                return Column(
                  children: [
                    _buildTopBar(context),
                    _buildDashboard(game),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const TabBar(
                        labelColor: Color(0xFF5A4038),
                        unselectedLabelColor: Color(0xFF9A8E8A),
                        indicatorColor: Color(0xFFB9A8A1),
                        tabs: [
                          Tab(text: '문의'),
                          Tab(text: '신고'),
                          Tab(text: '유저'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildInquiriesTab(game),
                          _buildReportsTab(game),
                          _buildUsersTab(game),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back),
            color: const Color(0xFF8A7A72),
          ),
          const SizedBox(width: 4),
          const Text(
            '관리자 센터',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF5A4038),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard(GameService game) {
    final dash = game.adminDashboard ?? const <String, dynamic>{};
    final serverStartedAt = _formatServerStartedAt(dash['serverStartedAt']?.toString());
    final List<({String label, String value, Color color, IconData icon})> cards = [
      ('활성 유저', '${dash['activeUsers'] ?? 0}', const Color(0xFF42A5F5), Icons.wifi_tethering),
      ('미처리 문의', '${dash['pendingInquiries'] ?? 0}', const Color(0xFFAB47BC), Icons.mail_outline),
      ('미처리 신고', '${dash['pendingReports'] ?? 0}', const Color(0xFFEF5350), Icons.report_outlined),
      ('전체 유저', '${dash['totalUsers'] ?? 0}', const Color(0xFFFFA726), Icons.groups_2_outlined),
      ('최근 시작', serverStartedAt, const Color(0xFF26A69A), Icons.schedule),
    ].map((item) => (label: item.$1, value: item.$2, color: item.$3, icon: item.$4)).toList();
    return Container(
      height: 112,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (context, separatorIndex) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final item = cards[index];
          return Container(
            width: 132,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(item.icon, color: item.color),
                const Spacer(),
                Text(
                  item.value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: item.color,
                  ),
                ),
                Text(
                  item.label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8A7A72),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildInquiriesTab(GameService game) {
    if (game.adminInquiriesLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (game.adminInquiriesError != null) {
      return Center(child: Text(game.adminInquiriesError!));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      itemCount: game.adminInquiries.length,
      separatorBuilder: (context, separatorIndex) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = game.adminInquiries[index];
        return Material(
          color: Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => _showInquiryDetail(item),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item['title']?.toString() ?? '-',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _inkColor,
                          ),
                        ),
                      ),
                      _buildStatusChip(item['status']?.toString() ?? '-', _statusColor(item['status']?.toString())),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${item['user_nickname'] ?? '-'} · ${item['category'] ?? '-'}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: _mutedColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildReportsTab(GameService game) {
    if (game.adminReportsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (game.adminReportsError != null) {
      return Center(child: Text(game.adminReportsError!));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      itemCount: game.adminReports.length,
      separatorBuilder: (context, separatorIndex) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = game.adminReports[index];
        return Material(
          color: Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => _showReportDetail(
              item['reported_nickname']?.toString() ?? '',
              item['room_id']?.toString() ?? '',
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item['reported_nickname']?.toString() ?? '-',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _inkColor,
                          ),
                        ),
                      ),
                      _buildStatusChip(
                        item['group_status']?.toString() ?? '-',
                        _statusColor(item['group_status']?.toString()),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '신고 ${item['report_count'] ?? 0}건 · 방 ${item['room_id'] ?? '-'}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: _mutedColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildUsersTab(GameService game) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: '닉네임 또는 계정명 검색',
                    prefixIcon: const Icon(Icons.search, color: _mutedColor),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.94),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  onSubmitted: (_) => game.requestAdminUsers(search: _searchController.text.trim()),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => game.requestAdminUsers(search: _searchController.text.trim()),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF8A7A72),
                ),
                child: const Text('검색'),
              ),
            ],
          ),
        ),
        Expanded(
          child: game.adminUsersLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: game.adminUsers.length,
                  separatorBuilder: (context, separatorIndex) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = game.adminUsers[index];
                    final online = item['isOnline'] == true;
                    return Material(
                      color: Colors.white.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => _showUserDetail(item['nickname']?.toString() ?? ''),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: online
                                    ? const Color(0xFFE8F5E9)
                                    : const Color(0xFFF3E5F5),
                                child: Icon(
                                  online ? Icons.wifi : Icons.person_outline,
                                  color: online ? const Color(0xFF43A047) : const Color(0xFF8A7A72),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item['nickname']?.toString() ?? '-',
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w800,
                                              color: _inkColor,
                                            ),
                                          ),
                                        ),
                                        if (item['is_admin'] == true)
                                          const Padding(
                                            padding: EdgeInsets.only(left: 8),
                                            child: Icon(
                                              Icons.verified,
                                              color: Color(0xFF7E57C2),
                                              size: 18,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      item['username']?.toString() ?? '-',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: _mutedColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${item['onlineStatus'] ?? 'offline'}${item['roomName'] != null ? ' · ${item['roomName']}' : ''}',
                                      style: const TextStyle(fontSize: 12, color: _mutedColor),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Icon(
                                Icons.chevron_right,
                                color: Colors.brown.shade300,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showInquiryDetail(Map<String, dynamic> item) {
    final noteController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('문의 #${item['id']}'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('유저: ${item['user_nickname'] ?? '-'}'),
                const SizedBox(height: 8),
                Text('제목: ${item['title'] ?? '-'}'),
                const SizedBox(height: 8),
                Text(item['content']?.toString() ?? '-'),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '관리자 메모',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기')),
          FilledButton(
            onPressed: item['status'] == 'resolved'
                ? null
                : () {
                    context.read<GameService>().resolveAdminInquiry(
                          (item['id'] as num?)?.toInt() ?? 0,
                          noteController.text.trim(),
                        );
                    Navigator.pop(ctx);
                  },
            child: const Text('처리 완료'),
          ),
        ],
      ),
    );
  }

  void _showReportDetail(String target, String roomId) {
    final game = context.read<GameService>();
    game.requestAdminReportGroup(target, roomId);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$target 신고'),
        content: SizedBox(
          width: 440,
          child: Consumer<GameService>(
            builder: (context, game, _) {
              if (game.adminReportGroupLoading) {
                return const SizedBox(height: 180, child: Center(child: CircularProgressIndicator()));
              }
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: game.adminReportGroup.map((row) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9F6F5),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${row['reporter_nickname'] ?? '-'} · ${row['status'] ?? '-'}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(row['reason']?.toString() ?? '-'),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기')),
          TextButton(
            onPressed: () {
              game.updateAdminReportStatus(target, roomId, 'reviewed');
              Navigator.pop(ctx);
            },
            child: const Text('검토됨'),
          ),
          FilledButton(
            onPressed: () {
              game.updateAdminReportStatus(target, roomId, 'resolved');
              Navigator.pop(ctx);
            },
            child: const Text('처리 완료'),
          ),
        ],
      ),
    );
  }

  void _showUserDetail(String nickname) {
    final game = context.read<GameService>();
    final goldController = TextEditingController();
    String? goldError;
    game.requestAdminUserDetail(nickname);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(nickname),
          content: SizedBox(
            width: 420,
            child: Consumer<GameService>(
              builder: (context, game, _) {
                if (game.adminUserDetailLoading || game.adminUserDetail?['nickname'] != nickname) {
                  return const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()));
                }
                final user = game.adminUserDetail ?? const <String, dynamic>{};
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionCard(
                        title: '기본 정보',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDetailRow('계정명', '${user['username'] ?? '-'}'),
                            _buildDetailRow('레이팅', '${user['rating'] ?? 0}'),
                            _buildDetailRow('골드', '${user['gold'] ?? 0}'),
                            _buildDetailRow('전적', '${user['wins'] ?? 0}승 / ${user['losses'] ?? 0}패'),
                            _buildDetailRow('활성 상태', '${user['onlineStatus'] ?? 'offline'}'),
                            if (user['roomName'] != null)
                              _buildDetailRow('현재 방', '${user['roomName']}'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildSectionCard(
                        title: '골드 지급/차감',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: goldController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: '골드 수량',
                                hintText: '예: 100',
                                errorText: goldError,
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [100, 500, 1000]
                                  .map(
                                    (amount) => ActionChip(
                                      label: Text('+$amount'),
                                      onPressed: () => goldController.text = '$amount',
                                    ),
                                  )
                                  .toList(),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      final amount = int.tryParse(goldController.text.trim());
                                      if (amount == null || amount <= 0) {
                                        setState(() => goldError = '1 이상의 숫자를 입력하세요');
                                        return;
                                      }
                                      setState(() => goldError = null);
                                      game.adjustAdminGold(nickname, amount);
                                      goldController.clear();
                                    },
                                    icon: const Icon(Icons.add_circle_outline),
                                    label: const Text('지급'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: FilledButton.tonalIcon(
                                    onPressed: () {
                                      final amount = int.tryParse(goldController.text.trim());
                                      if (amount == null || amount <= 0) {
                                        setState(() => goldError = '1 이상의 숫자를 입력하세요');
                                        return;
                                      }
                                      setState(() => goldError = null);
                                      game.adjustAdminGold(nickname, -amount);
                                      goldController.clear();
                                    },
                                    icon: const Icon(Icons.remove_circle_outline),
                                    label: const Text('차감'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기')),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _panelColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: _inkColor,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }


  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _mutedColor,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _inkColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'resolved':
      case 'online':
        return const Color(0xFF2E7D32);
      case 'reviewed':
        return const Color(0xFFEF6C00);
      case 'pending':
        return const Color(0xFF6D4C41);
      default:
        return const Color(0xFF8A7A72);
    }
  }

  String _formatServerStartedAt(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    final parsed = DateTime.tryParse(raw)?.toLocal();
    if (parsed == null) return '-';
    final month = parsed.month.toString().padLeft(2, '0');
    final day = parsed.day.toString().padLeft(2, '0');
    final hour = parsed.hour.toString().padLeft(2, '0');
    final minute = parsed.minute.toString().padLeft(2, '0');
    return '$month/$day $hour:$minute';
  }

}
