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

int _toInt(dynamic v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

String _formatTimestamp(dynamic v) {
  if (v == null) return '-';
  DateTime? dt;
  if (v is DateTime) {
    dt = v;
  } else if (v is String && v.isNotEmpty) {
    dt = DateTime.tryParse(v);
  }
  if (dt == null) return v.toString();
  final local = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

class _AdminCenterScreenState extends State<AdminCenterScreen> {
  final TextEditingController _searchController = TextEditingController();
  static const _panelColor = Color(0xFFF9F5F3);
  static const _inkColor = Color(0xFF5A4038);
  static const _mutedColor = Color(0xFF8A7A72);
  String _selectedCard = 'active';
  static const _userCardIds = {'active', 'newToday', 'weeklyActive', 'allUsers'};

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
                  SizedBox(height: isCompact ? 10 : 14),
                  Expanded(
                    child: _buildSelectedSection(game, isCompact),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedSection(GameService game, bool isCompact) {
    if (_userCardIds.contains(_selectedCard)) {
      return _buildUsersTab(game, isCompact);
    }
    switch (_selectedCard) {
      case 'pendingInquiries':
        return _buildInquiriesTab(game, isCompact);
      case 'pendingReports':
        return _buildReportsTab(game, isCompact);
      case 'casualGames':
        return _buildMatchesList(game, isCompact, rankedOnly: false);
      case 'rankedGames':
        return _buildMatchesList(game, isCompact, rankedOnly: true);
      default:
        return _buildUsersTab(game, isCompact);
    }
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
    final activeUsers = _toInt(dash['activeUsers']);
    final newUsersToday = _toInt(dash['newUsersToday']);
    final weeklyActives = _toInt(dash['activeUsers7d']);
    final totalUsers = _toInt(dash['totalUsers']);
    final pendingInquiries = _toInt(dash['pendingInquiries']);
    final totalInquiries = _toInt(dash['totalInquiries']);
    final pendingReports = _toInt(dash['pendingReports']);
    final totalReports = _toInt(dash['totalReports']);
    final todayGames = _toInt(dash['todayGames']);
    final todayRankedGames = _toInt(dash['todayRankedGames']);
    final todayCasualGames = (todayGames - todayRankedGames).clamp(0, todayGames);

    final cards = <({String id, String label, String value, Color color, IconData icon})>[
      (id: 'active', label: l.adminActiveUsers, value: '$activeUsers', color: const Color(0xFF42A5F5), icon: Icons.wifi_tethering),
      (id: 'newToday', label: l.adminNewUsersToday, value: '$newUsersToday', color: const Color(0xFF26A69A), icon: Icons.person_add_alt_1_outlined),
      (id: 'weeklyActive', label: l.adminWeeklyActives, value: '$weeklyActives', color: const Color(0xFF66BB6A), icon: Icons.trending_up),
      (id: 'allUsers', label: l.adminTotalUsers, value: '$totalUsers', color: const Color(0xFFFFA726), icon: Icons.groups_2_outlined),
      (id: 'pendingInquiries', label: l.adminPendingInquiries, value: '$pendingInquiries / $totalInquiries', color: const Color(0xFFAB47BC), icon: Icons.mail_outline),
      (id: 'pendingReports', label: l.adminPendingReports, value: '$pendingReports / $totalReports', color: const Color(0xFFEF5350), icon: Icons.report_outlined),
      (id: 'casualGames', label: l.adminCasualGames, value: '$todayCasualGames / $todayGames', color: const Color(0xFF5C6BC0), icon: Icons.sports_esports_outlined),
      (id: 'rankedGames', label: l.adminRankedGames, value: '$todayRankedGames / $todayGames', color: const Color(0xFFFF7043), icon: Icons.emoji_events_outlined),
    ];

    final marginH = isCompact ? 12.0 : 16.0;
    final spacing = isCompact ? 8.0 : 10.0;
    final cardHeight = isCompact ? 78.0 : 86.0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: marginH),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth = ((constraints.maxWidth - spacing * 3) / 4).clamp(60.0, 200.0);
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: cards.map((item) => SizedBox(
              width: cardWidth,
              height: cardHeight,
              child: _buildDashboardCard(item, isCompact),
            )).toList(),
          );
        },
      ),
    );
  }

  Widget _buildDashboardCard(({String id, String label, String value, Color color, IconData icon}) item, bool isCompact) {
    final isSelected = _selectedCard == item.id;
    return Material(
      color: Colors.white.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          if (_selectedCard == item.id) return;
          setState(() => _selectedCard = item.id);
          final game = context.read<GameService>();
          if (item.id == 'casualGames') {
            game.requestAdminTodayMatches(ranked: false);
          } else if (item.id == 'rankedGames') {
            game.requestAdminTodayMatches(ranked: true);
          }
        },
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: isCompact ? 10 : 12, vertical: isCompact ? 8 : 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? item.color : Colors.transparent,
              width: isSelected ? 2 : 0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(item.icon, color: item.color, size: isCompact ? 16 : 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isCompact ? 10 : 11,
                        color: _mutedColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  item.value,
                  style: TextStyle(
                    fontSize: isCompact ? 18 : 20,
                    fontWeight: FontWeight.w900,
                    color: item.color,
                  ),
                ),
              ),
            ],
          ),
        ),
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
                    '${l.adminReportCount(_toInt(item['report_count']))} · ${l.adminReportRoom(item['room_id']?.toString() ?? '-')}',
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
              : Builder(builder: (context) {
                final filtered = _filterUsersBySelection(game.adminUsers);
                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      l.adminNoUsers,
                      style: const TextStyle(color: _mutedColor),
                    ),
                  );
                }
                return ListView.separated(
                  padding: EdgeInsets.fromLTRB(isCompact ? 12 : 16, 0, isCompact ? 12 : 16, 16),
                  itemCount: filtered.length,
                  separatorBuilder: (context, separatorIndex) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = filtered[index];
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
                );
              }),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _filterUsersBySelection(List<Map<String, dynamic>> users) {
    switch (_selectedCard) {
      case 'active':
        return users.where((u) => u['isOnline'] == true).toList();
      case 'newToday':
        final now = DateTime.now();
        return users.where((u) {
          final c = u['created_at'];
          if (c == null) return false;
          final dt = DateTime.tryParse(c.toString())?.toLocal();
          if (dt == null) return false;
          return dt.year == now.year && dt.month == now.month && dt.day == now.day;
        }).toList();
      case 'weeklyActive':
        final cutoff = DateTime.now().subtract(const Duration(days: 7));
        return users.where((u) {
          final v = u['last_login'];
          if (v == null) return false;
          final dt = DateTime.tryParse(v.toString())?.toLocal();
          if (dt == null) return false;
          return dt.isAfter(cutoff);
        }).toList();
      default:
        return users;
    }
  }

  Widget _buildMatchesList(GameService game, bool isCompact, {required bool rankedOnly}) {
    final l = L10n.of(context);
    if (game.adminTodayMatchesLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (game.adminTodayMatchesError != null) {
      return Center(child: Text(localizeServiceMessage(game.adminTodayMatchesError!, l)));
    }
    final filtered = game.adminTodayMatches
        .where((m) => (m['is_ranked'] == true) == rankedOnly)
        .toList();
    if (filtered.isEmpty) {
      return Center(
        child: Text(
          rankedOnly ? l.adminRankedGames : l.adminCasualGames,
          style: const TextStyle(color: _mutedColor),
        ),
      );
    }
    final counts = <String, int>{};
    for (final m in filtered) {
      final type = m['game_type']?.toString() ?? 'other';
      counts[type] = (counts[type] ?? 0) + 1;
    }
    final orderedTypes = ['tichu', 'skull_king', 'love_letter', 'mighty'];

    return Column(
      children: [
        Container(
          margin: EdgeInsets.fromLTRB(isCompact ? 12 : 16, 0, isCompact ? 12 : 16, 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Text(
                '${filtered.length}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: _inkColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: orderedTypes.map((type) {
                    final n = counts[type] ?? 0;
                    final meta = _gameTypeMeta(type);
                    final faded = n == 0;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(meta.icon, size: 13, color: faded ? _mutedColor : meta.color),
                        const SizedBox(width: 3),
                        Text(
                          '${meta.label} $n',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: faded ? FontWeight.w500 : FontWeight.w800,
                            color: faded ? _mutedColor : meta.color,
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(isCompact ? 12 : 16, 0, isCompact ? 12 : 16, 16),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _buildMatchCell(filtered[index], isCompact),
          ),
        ),
      ],
    );
  }

  Widget _buildMatchCell(Map<String, dynamic> m, bool isCompact) {
    final gameType = m['game_type']?.toString() ?? '-';
    final endReason = m['end_reason']?.toString() ?? '';
    final created = _formatTimestamp(m['created_at']);
    final isRanked = m['is_ranked'] == true;
    final deserter = m['deserter_nickname']?.toString();

    final typeMeta = _gameTypeMeta(gameType);

    Widget? body;
    if (gameType == 'tichu') {
      body = _buildTichuMatchBody(m);
    } else {
      body = _buildOtherMatchBody(m);
    }

    return Material(
      color: Colors.white.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: typeMeta.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(typeMeta.icon, size: 14, color: typeMeta.color),
                      const SizedBox(width: 4),
                      Text(
                        typeMeta.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: typeMeta.color,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isRanked) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF7043).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'RANK',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFE64A19),
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  created.split(' ').last, // HH:MM only
                  style: const TextStyle(fontSize: 12, color: _mutedColor, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            body,
            if (deserter != null && deserter.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.flag_outlined, size: 12, color: Color(0xFFE53935)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'deserter: $deserter',
                      style: const TextStyle(fontSize: 11, color: Color(0xFFE53935), fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            if (endReason.isNotEmpty && endReason != 'normal') ...[
              const SizedBox(height: 4),
              Text(
                endReason,
                style: const TextStyle(fontSize: 10, color: _mutedColor, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTichuMatchBody(Map<String, dynamic> m) {
    final teamA = [m['player_a1'], m['player_a2']]
        .where((v) => v != null && v.toString().isNotEmpty)
        .map((v) => v.toString())
        .join(' · ');
    final teamB = [m['player_b1'], m['player_b2']]
        .where((v) => v != null && v.toString().isNotEmpty)
        .map((v) => v.toString())
        .join(' · ');
    final scoreA = _toInt(m['team_a_score']);
    final scoreB = _toInt(m['team_b_score']);
    final winner = m['winner_team']?.toString();
    final aWon = winner == 'A';
    final bWon = winner == 'B';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTichuTeamRow(teamA.isEmpty ? '-' : teamA, scoreA, aWon),
        const SizedBox(height: 4),
        _buildTichuTeamRow(teamB.isEmpty ? '-' : teamB, scoreB, bWon),
      ],
    );
  }

  Widget _buildTichuTeamRow(String players, int score, bool isWinner) {
    final color = isWinner ? const Color(0xFF2E7D32) : _inkColor;
    return Row(
      children: [
        if (isWinner) ...[
          const Icon(Icons.emoji_events, size: 14, color: Color(0xFFFFA726)),
          const SizedBox(width: 4),
        ] else
          const SizedBox(width: 18),
        Expanded(
          child: Text(
            players,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isWinner ? FontWeight.w800 : FontWeight.w600,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$score',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildOtherMatchBody(Map<String, dynamic> m) {
    // For SK/LL/Mighty: player_a1 contains nickname(score) joined by ', '
    final playerSummary = m['player_a1']?.toString() ?? '';
    final playerCount = m['player_a2']?.toString();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (playerCount != null && playerCount.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF8A7A72).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${playerCount}p',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _inkColor),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            playerSummary.isEmpty ? '-' : playerSummary,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: _inkColor, fontWeight: FontWeight.w600, height: 1.4),
          ),
        ),
      ],
    );
  }

  ({String label, Color color, IconData icon}) _gameTypeMeta(String gameType) {
    switch (gameType) {
      case 'tichu':
        return (label: 'TICHU', color: const Color(0xFF42A5F5), icon: Icons.style_outlined);
      case 'skull_king':
        return (label: 'SK', color: const Color(0xFFAB47BC), icon: Icons.sailing_outlined);
      case 'love_letter':
        return (label: 'LL', color: const Color(0xFFEF5350), icon: Icons.mail_outlined);
      case 'mighty':
        return (label: 'MIGHTY', color: const Color(0xFFFFA726), icon: Icons.casino_outlined);
      default:
        return (label: gameType.toUpperCase(), color: _mutedColor, icon: Icons.help_outline);
    }
  }

  void _showInquiryDetail(Map<String, dynamic> item) {
    final l = L10n.of(context);
    final noteController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.adminInquiryTitle(_toInt(item['id']))),
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
                          _toInt(item['id']),
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
    game.requestAdminUserDetail(nickname);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
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
                child: _buildSectionCard(
                  title: l.adminBasicInfo,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDetailRow(l.adminUsername, '${user['username'] ?? '-'}'),
                      _buildDetailRow(l.adminRating, '${user['rating'] ?? 0}'),
                      _buildDetailRow(l.adminGold, '${user['gold'] ?? 0}'),
                      _buildDetailRow(l.adminRecord, l.adminWinLoss(_toInt(user['wins']), _toInt(user['losses']))),
                      _buildDetailRow(l.adminStatus, '${user['onlineStatus'] ?? 'offline'}'),
                      if (user['roomName'] != null)
                        _buildDetailRow(l.adminCurrentRoom, '${user['roomName']}'),
                      _buildDetailRow(l.adminJoinedAt, _formatTimestamp(user['created_at'])),
                      _buildDetailRow(l.adminLastLogin, _formatTimestamp(user['last_login'])),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.commonClose)),
        ],
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
