import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/game_service.dart';
import '../services/network_service.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _appVersion = '${info.version}+${info.buildNumber}');
    } catch (_) {}
  }
  void _logout() async {
    final network = context.read<NetworkService>();
    final game = context.read<GameService>();
    network.disconnect();
    game.reset();
    await LoginScreen.clearSavedCredentials();
    await AuthService.signOut();
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
                final game = context.read<GameService>();
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

  void _showLinkDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('소셜 계정 연동'),
        content: const Text('연동할 소셜 계정을 선택하세요'),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await AuthService.signOutGoogle();
                final result = await AuthService.signInWithGoogle();
                if (result.cancelled || !mounted) return;
                context.read<GameService>().linkSocial(result.provider, result.token);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('연동 실패: $e')),
                  );
                }
              }
            },
            child: const Text('Google', style: TextStyle(color: Color(0xFF4285F4), fontWeight: FontWeight.bold)),
          ),
          if (Platform.isIOS)
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  final result = await AuthService.signInWithApple();
                  if (result.cancelled || !mounted) return;
                  context.read<GameService>().linkSocial(result.provider, result.token);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('연동 실패: $e')),
                    );
                  }
                }
              },
              child: const Text('Apple', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final result = await AuthService.signInWithKakao();
                if (result.cancelled || !mounted) return;
                context.read<GameService>().linkSocial(result.provider, result.token);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('연동 실패: $e')),
                  );
                }
              }
            },
            child: const Text('Kakao', style: TextStyle(color: Color(0xFF3C1E1E), fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
        ],
      ),
    );
  }

  void _showUnlinkDialog(GameService game) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('연동 해제'),
        content: Text('${game.linkedSocialProvider?.toUpperCase()} 연동을 해제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              game.unlinkSocial();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
              foregroundColor: Colors.white,
            ),
            child: const Text('해제'),
          ),
        ],
      ),
    );
  }

  Widget _buildRow({
    required IconData icon,
    required String title,
    Color? iconColor,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    bool enabled = true,
  }) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: iconColor ?? const Color(0xFF8A7A72)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: enabled ? const Color(0xFF5A4038) : const Color(0xFFB0A8A4),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: enabled ? const Color(0xFF8A7A72) : const Color(0xFFBDB5B1),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
    if (onTap == null || !enabled) return content;
    return InkWell(
      onTap: onTap,
      child: content,
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF8A7A72),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.95),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE0D8D4)),
            ),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeColors = context.watch<GameService>().themeGradient;
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
                if (game.socialLinkResultSuccess != null) {
                  final success = game.socialLinkResultSuccess!;
                  final message = game.socialLinkResultMessage ?? '';
                  game.socialLinkResultSuccess = null;
                  game.socialLinkResultMessage = null;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success ? '연동이 완료되었습니다' : message),
                      backgroundColor: success ? Colors.green : Colors.red,
                    ),
                  );
                }
              });
              return Column(
                children: [
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.95),
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
                          '설정',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF5A4038),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        children: [
                          _buildSection(
                            '알림',
                            [
                              _buildRow(
                                icon: Icons.notifications,
                                iconColor: const Color(0xFF64B5F6),
                                title: '푸시 알림',
                                subtitle: '전체 알림을 켜고 끕니다',
                                trailing: Switch(
                                  value: game.pushEnabled,
                                  onChanged: (v) => game.setPushEnabled(v),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildSection(
                            '계정',
                            [
                              _buildRow(
                                icon: Icons.account_circle,
                                iconColor: const Color(0xFF64B5F6),
                                title: '닉네임',
                                subtitle: game.playerName,
                              ),
                              const Divider(height: 1, color: Color(0xFFEAE2DE)),
                              _buildRow(
                                icon: Icons.link,
                                iconColor: const Color(0xFF7E57C2),
                                title: '소셜 연동',
                                subtitle: game.authProvider != 'local'
                                    ? '${game.authProvider.toUpperCase()} 연동됨'
                                    : (game.linkedSocialProvider != null && game.linkedSocialProvider != 'local')
                                        ? '${game.linkedSocialProvider!.toUpperCase()} 연동됨'
                                        : '연동된 계정 없음 (랭크전 이용 불가)',
                                trailing: game.authProvider == 'local' &&
                                        (game.linkedSocialProvider == null || game.linkedSocialProvider == 'local')
                                    ? TextButton(
                                        onPressed: () => _showLinkDialog(),
                                        child: const Text('연동', style: TextStyle(color: Color(0xFF7E57C2), fontSize: 12)),
                                      )
                                    : null,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildSection(
                            '앱 정보',
                            [
                              _buildRow(
                                icon: Icons.info_outline,
                                iconColor: const Color(0xFF7E57C2),
                                title: '앱 버전',
                                subtitle: _appVersion.isEmpty ? '-' : _appVersion,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildSection(
                            '문의',
                            [
                              _buildRow(
                                icon: Icons.help_outline,
                                iconColor: const Color(0xFFBA68C8),
                                title: '문의하기',
                                onTap: _showInquiryDialog,
                                trailing: const Icon(Icons.chevron_right, color: Color(0xFFB0A8A4)),
                              ),
                              const Divider(height: 1, color: Color(0xFFEAE2DE)),
                              _buildRow(
                                icon: Icons.mark_email_read,
                                iconColor: const Color(0xFF1E88E5),
                                title: '문의 내역',
                                onTap: _showInquiryHistoryDialog,
                                trailing: const Icon(Icons.chevron_right, color: Color(0xFFB0A8A4)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildSection(
                            '계정 관리',
                            [
                              _buildRow(
                                icon: Icons.logout,
                                iconColor: const Color(0xFF8A7A72),
                                title: '로그아웃',
                                onTap: _logout,
                                trailing: const Icon(Icons.chevron_right, color: Color(0xFFB0A8A4)),
                              ),
                              const Divider(height: 1, color: Color(0xFFEAE2DE)),
                              _buildRow(
                                icon: Icons.delete_forever,
                                iconColor: const Color(0xFFC62828),
                                title: '회원탈퇴',
                                onTap: _showDeleteAccountDialog,
                                trailing: const Icon(Icons.chevron_right, color: Color(0xFFB0A8A4)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
