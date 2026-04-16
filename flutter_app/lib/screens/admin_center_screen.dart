import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n_helpers.dart';
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
    final isCompact = MediaQuery.sizeOf(context).width < 600;
    final l = L10n.of(context);
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
                    final message = localizeServiceMessage(game.adminActionMessage ?? (success ? 'admin_action_success' : 'admin_action_failed'), L10n.of(context));
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
                    _buildTopBar(context, isCompact),
                    _buildDashboard(game, isCompact),
                    Container(
                      margin: EdgeInsets.symmetric(horizontal: isCompact ? 12 : 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: TabBar(
                        isScrollable: isCompact,
                        tabAlignment: isCompact ? TabAlignment.start : TabAlignment.fill,
                        labelColor: const Color(0xFF5A4038),
                        unselectedLabelColor: const Color(0xFF9A8E8A),
                        indicatorColor: const Color(0xFFB9A8A1),
                        tabs: [
                          Tab(text: l.adminTabInquiries),
                          Tab(text: l.adminTabReports),
                          Tab(text: l.adminTabUsers),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildInquiriesTab(game, isCompact),
                          _buildReportsTab(game, isCompact),
                          _buildUsersTab(game, isCompact),
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

  Widget _buildTopBar(BuildContext context, bool isCompact) {
    return Container(
      margin: EdgeInsets.all(isCompact ? 12 : 16),
      padding: EdgeInsets.all(isCompact ? 8 : 12),
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
            visualDensity: isCompact ? VisualDensity.compact : VisualDensity.standard,
          ),
          SizedBox(width: isCompact ? 2 : 4),
          Expanded(
            child: Text(
              L10n.of(context).adminCenterTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: isCompact ? 18 : 20,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF5A4038),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard(GameService game, bool isCompact) {
    final l = L10n.of(context);
    final dash = game.adminDashboard ?? const <String, dynamic>{};
    final List<({String label, String value, Color color, IconData icon})> cards = [
      (l.adminActiveUsers, '${dash['activeUsers'] ?? 0}', const Color(0xFF42A5F5), Icons.wifi_tethering),
      (l.adminPendingInquiries, '${dash['pendingInquiries'] ?? 0}', const Color(0xFFAB47BC), Icons.mail_outline),
      (l.adminPendingReports, '${dash['pendingReports'] ?? 0}', const Color(0xFFEF5350), Icons.report_outlined),
      (l.adminTotalUsers, '${dash['totalUsers'] ?? 0}', const Color(0xFFFFA726), Icons.groups_2_outlined),
    ].map((item) => (label: item.$1, value: item.$2, color: item.$3, icon: item.$4)).toList();
    return Container(
      height: isCompact ? 104 : 112,
      margin: EdgeInsets.symmetric(horizontal: isCompact ? 12 : 16),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (context, separatorIndex) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final item = cards[index];
          return Container(
            width: isCompact ? 116 : 132,
            padding: EdgeInsets.all(isCompact ? 12 : 14),
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
                    fontSize: isCompact ? 20 : 22,
                    fontWeight: FontWeight.w900,
                    color: item.color,
                  ),
                ),
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: isCompact ? 11 : 12,
                    color: const Color(0xFF8A7A72),
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

  Widget _buildInquiriesTab(GameService game, bool isCompact) {
    if (game.adminInquiriesLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (game.adminInquiriesError != null) {
      return Center(child: Text(localizeServiceMessage(game.adminInquiriesError!, L10n.of(context))));
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(isCompact ? 12 : 16, 6, isCompact ? 12 : 16, 16),
      itemCount: game.adminInquiries.length,
      separatorBuilder: (context, separatorIndex) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = game.adminInquiries[index];
        final status = item['status']?.toString() ?? '-';
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
                  if (isCompact) ...[
                    Text(
                      item['title']?.toString() ?? '-',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: _inkColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildStatusChip(status, _statusColor(status)),
                  ] else
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
                        _buildStatusChip(status, _statusColor(status)),
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

  Widget _buildReportsTab(GameService game, bool isCompact) {
    final l = L10n.of(context);
    if (game.adminReportsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (game.adminReportsError != null) {
      return Center(child: Text(localizeServiceMessage(game.adminReportsError!, L10n.of(context))));
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(isCompact ? 12 : 16, 6, isCompact ? 12 : 16, 16),
      itemCount: game.adminReports.length,
      separatorBuilder: (context, separatorIndex) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = game.adminReports[index];
        final status = item['group_status']?.toString() ?? '-';
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
                  if (isCompact) ...[
                    Text(
                      item['reported_nickname']?.toString() ?? '-',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: _inkColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildStatusChip(status, _statusColor(status)),
                  ] else
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
                        _buildStatusChip(status, _statusColor(status)),
                      ],
                    ),
                  const SizedBox(height: 8),
                  Text(
                    '${l.adminReportCount((item['report_count'] as num?)?.toInt() ?? 0)} · ${l.adminReportRoom(item['room_id']?.toString() ?? '-')}',
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

  Widget _buildUsersTab(GameService game, bool isCompact) {
    final l = L10n.of(context);
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(isCompact ? 12 : 16, 6, isCompact ? 12 : 16, 10),
          child: isCompact
              ? Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: l.adminSearchHint,
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
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => game.requestAdminUsers(search: _searchController.text.trim()),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF8A7A72),
                        ),
                        child: Text(l.adminSearch),
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: l.adminSearchHint,
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
                      child: Text(l.adminSearch),
                    ),
                  ],
                ),
        ),
        Expanded(
          child: game.adminUsersLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(isCompact ? 12 : 16, 0, isCompact ? 12 : 16, 16),
                  itemCount: game.adminUsers.length,
                  separatorBuilder: (context, separatorIndex) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = game.adminUsers[index];
                    final online = item['isOnline'] == true;
                    final platform = _platformLabel(item['device_platform']?.toString());
                    final appVersion = item['app_version']?.toString().trim();
                    final statusText = online ? l.adminOnline : l.adminOffline;
                    final roomName = item['roomName']?.toString();
                    return Material(
                      color: Colors.white.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => _showUserDetail(item['nickname']?.toString() ?? ''),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        if (platform != null)
                                          Text(
                                            platform,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFF1565C0),
                                            ),
                                          ),
                                        Text(
                                          item['nickname']?.toString() ?? '-',
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            color: _inkColor,
                                          ),
                                        ),
                                        if (item['is_admin'] == true)
                                          const Padding(
                                            padding: EdgeInsets.only(left: 2),
                                            child: Icon(
                                              Icons.verified,
                                              color: Color(0xFF7E57C2),
                                              size: 18,
                                            ),
                                          ),
                                        _buildStatusChip(
                                          statusText,
                                          _statusColor(online ? 'online' : 'offline'),
                                        ),
                                      ],
                                    ),
                                    if ((appVersion != null && appVersion.isNotEmpty) || (roomName != null && roomName.isNotEmpty))
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          [
                                            if (appVersion != null && appVersion.isNotEmpty) 'v$appVersion',
                                            if (roomName != null && roomName.isNotEmpty) roomName,
                                          ].join(' · '),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12, color: _mutedColor),
                                        ),
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
    final l = L10n.of(context);
    final noteController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.adminInquiryTitle((item['id'] as num?)?.toInt() ?? 0)),
        content: SizedBox(
          width: _dialogWidth(ctx, 420),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${l.adminUser}: ${item['user_nickname'] ?? '-'}'),
                const SizedBox(height: 8),
                Text('${l.adminSubject}: ${item['title'] ?? '-'}'),
                const SizedBox(height: 8),
                Text(item['content']?.toString() ?? '-'),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: l.adminNote,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.commonClose)),
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
            child: Text(l.adminResolved),
          ),
        ],
      ),
    );
  }

  void _showReportDetail(String target, String roomId) {
    final l = L10n.of(context);
    final game = context.read<GameService>();
    game.requestAdminReportGroup(target, roomId);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.adminReportTitle(target)),
        content: SizedBox(
          width: _dialogWidth(ctx, 440),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.commonClose)),
          TextButton(
            onPressed: () {
              game.updateAdminReportStatus(target, roomId, 'reviewed');
              Navigator.pop(ctx);
            },
            child: Text(l.adminReviewed),
          ),
          FilledButton(
            onPressed: () {
              game.updateAdminReportStatus(target, roomId, 'resolved');
              Navigator.pop(ctx);
            },
            child: Text(l.adminResolved),
          ),
        ],
      ),
    );
  }

  void _showUserDetail(String nickname) {
    final l = L10n.of(context);
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
            width: _dialogWidth(ctx, 420),
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
                        title: l.adminBasicInfo,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDetailRow(l.adminUsername, '${user['username'] ?? '-'}'),
                            _buildDetailRow(l.adminRating, '${user['rating'] ?? 0}'),
                            _buildDetailRow(l.adminGold, '${user['gold'] ?? 0}'),
                            _buildDetailRow(l.adminRecord, l.adminWinLoss((user['wins'] as num?)?.toInt() ?? 0, (user['losses'] as num?)?.toInt() ?? 0)),
                            _buildDetailRow(l.adminStatus, '${user['onlineStatus'] ?? 'offline'}'),
                            if (user['roomName'] != null)
                              _buildDetailRow(l.adminCurrentRoom, '${user['roomName']}'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildSectionCard(
                        title: l.adminGoldAdjust,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: goldController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: l.adminGoldAmount,
                                hintText: l.adminGoldHint,
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
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final isNarrow = constraints.maxWidth < 340;
                                final grantButton = OutlinedButton.icon(
                                  onPressed: () {
                                    final amount = int.tryParse(goldController.text.trim());
                                    if (amount == null || amount <= 0) {
                                      setState(() => goldError = l.adminGoldValidation);
                                      return;
                                    }
                                    setState(() => goldError = null);
                                    game.adjustAdminGold(nickname, amount);
                                    goldController.clear();
                                  },
                                  icon: const Icon(Icons.add_circle_outline),
                                  label: Text(l.adminGrant),
                                );
                                final deductButton = FilledButton.tonalIcon(
                                  onPressed: () {
                                    final amount = int.tryParse(goldController.text.trim());
                                    if (amount == null || amount <= 0) {
                                      setState(() => goldError = l.adminGoldValidation);
                                      return;
                                    }
                                    setState(() => goldError = null);
                                    game.adjustAdminGold(nickname, -amount);
                                    goldController.clear();
                                  },
                                  icon: const Icon(Icons.remove_circle_outline),
                                  label: Text(l.adminDeduct),
                                );
                                if (isNarrow) {
                                  return Column(
                                    children: [
                                      SizedBox(width: double.infinity, child: grantButton),
                                      const SizedBox(height: 8),
                                      SizedBox(width: double.infinity, child: deductButton),
                                    ],
                                  );
                                }
                                return Row(
                                  children: [
                                    Expanded(child: grantButton),
                                    const SizedBox(width: 10),
                                    Expanded(child: deductButton),
                                  ],
                                );
                              },
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
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.commonClose)),
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

  double _dialogWidth(BuildContext context, double maxWidth) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    return screenWidth < 520 ? screenWidth - 48 : maxWidth;
  }

  String? _platformLabel(String? raw) {
    switch (raw?.toLowerCase()) {
      case 'ios':
        return 'iOS';
      case 'android':
        return 'AOS';
      default:
        return null;
    }
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

}
