import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../services/game_service.dart';
import '../services/auth_service.dart';
import '../services/session_service.dart';
import '../services/locale_service.dart';
import '../services/ad_service.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'admin_center_screen.dart';

class SettingsScreen extends StatefulWidget {
  /// Callback invoked when the user taps "내 프로필". The callback receives
  /// the Settings screen's own [BuildContext] so it can open the profile
  /// dialog on top of Settings rather than popping back to the lobby.
  final void Function(BuildContext settingsContext)? onShowMyProfile;

  const SettingsScreen({super.key, this.onShowMyProfile});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _appVersion = '';
  BannerAd? _bannerAd;
  bool _bannerAdLoaded = false;

  @override
  void initState() {
    super.initState();
    _bannerAd = AdService.createBannerAd(
      AdService.settingsBannerId,
      onAdLoaded: (_) { if (mounted) setState(() => _bannerAdLoaded = true); },
      onAdFailedToLoad: (_, _) { if (mounted) setState(() { _bannerAd = null; _bannerAdLoaded = false; }); },
    );
    _bannerAd!.load();
    _loadAppVersion();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _appVersion = info.version);
    } catch (_) {}
  }

  /// Returns negative if a < b, 0 if equal, positive if a > b.
  /// Accepts "2.1.0" or "2.1.0+18" — build metadata after '+' is ignored.
  int _compareVersions(String a, String b) {
    final partsA = a.split('+').first.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final partsB = b.split('+').first.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final len = partsA.length > partsB.length ? partsA.length : partsB.length;
    for (int i = 0; i < len; i++) {
      final va = i < partsA.length ? partsA[i] : 0;
      final vb = i < partsB.length ? partsB[i] : 0;
      if (va != vb) return va - vb;
    }
    return 0;
  }

  bool _isOutdated(String? latestVersion) {
    if (_appVersion.isEmpty) return false;
    if (latestVersion == null || latestVersion.isEmpty) return false;
    return _compareVersions(_appVersion, latestVersion) < 0;
  }

  String _localeDisplayName(L10n l10n, Locale locale) {
    switch (locale.languageCode) {
      case 'en': return l10n.languageEnglish;
      case 'ko': return l10n.languageKorean;
      case 'de': return l10n.languageGerman;
      default: return locale.languageCode;
    }
  }

  void _showLanguageDialog(BuildContext ctx, LocaleService localeService, L10n l10n) {
    showDialog(
      context: ctx,
      builder: (dialogCtx) => SimpleDialog(
        title: Text(l10n.settingsLanguage),
        children: [
          _languageOption(dialogCtx, localeService, null, l10n.languageAuto),
          _languageOption(dialogCtx, localeService, const Locale('en'), 'English'),
          _languageOption(dialogCtx, localeService, const Locale('ko'), '한국어'),
          _languageOption(dialogCtx, localeService, const Locale('de'), 'Deutsch'),
        ],
      ),
    );
  }

  Widget _languageOption(BuildContext dialogCtx, LocaleService localeService, Locale? locale, String label) {
    final isSelected = localeService.userSelectedLocale == locale;
    return SimpleDialogOption(
      onPressed: () {
        localeService.setLocale(locale);
        final effectiveCode = (locale ?? localeService.effectiveLocale).languageCode;
        context.read<GameService>().sendLocale(effectiveCode);
        Navigator.pop(dialogCtx);
      },
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
                color: isSelected ? const Color(0xFF42A5F5) : const Color(0xFF3E312A),
              ),
            ),
          ),
          if (isSelected)
            const Icon(Icons.check, color: Color(0xFF42A5F5), size: 20),
        ],
      ),
    );
  }

  Future<void> _openStore() async {
    final uri = Uri.parse(Platform.isIOS
        ? 'https://apps.apple.com/app/tichu-online/id6759035151'
        : 'https://play.google.com/store/apps/details?id=com.jiny.tichuOnline');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      await launchUrl(uri);
    }
  }
  void _logout() async {
    await context.read<SessionService>().logout();
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
    game.deleteAccount().whenComplete(_logout);
  }

  String _noticeCategoryLabel(dynamic value) {
    switch (value?.toString()) {
      case 'release': return '릴리즈';
      case 'update': return '업데이트';
      case 'preview': return '업데이트 예고';
      case 'general': return '공지';
      default: return '공지';
    }
  }

  Color _noticeCategoryBgColor(dynamic value) {
    switch (value?.toString()) {
      case 'release': return const Color(0xFFE3F2FD);
      case 'update': return const Color(0xFFE8F5E9);
      case 'preview': return const Color(0xFFFFF3E0);
      case 'general': return const Color(0xFFECEFF1);
      default: return const Color(0xFFECEFF1);
    }
  }

  Color _noticeCategoryTextColor(dynamic value) {
    switch (value?.toString()) {
      case 'release': return const Color(0xFF1565C0);
      case 'update': return const Color(0xFF2E7D32);
      case 'preview': return const Color(0xFFE65100);
      case 'general': return const Color(0xFF546E7A);
      default: return const Color(0xFF546E7A);
    }
  }

  void _showNoticesDialog() {
    final game = context.read<GameService>();
    // Mark all (existing + freshly fetched) notices as read — opening the
    // dialog counts as "seeing" them, which clears the red badges.
    game.markCurrentNoticesAsRead();
    game.requestNotices(markReadOnReceive: true);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.campaign, color: Color(0xFF42A5F5)),
            SizedBox(width: 8),
            Text('공지사항'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Consumer<GameService>(
            builder: (context, game, _) {
              if (game.noticesLoading) {
                return const SizedBox(
                  height: 160,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (game.noticesError != null) {
                return SizedBox(
                  height: 160,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          game.noticesError!,
                          style: const TextStyle(color: Color(0xFFCC6666)),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: () => game.requestNotices(),
                          child: const Text('다시 시도'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (game.notices.isEmpty) {
                return const SizedBox(
                  height: 140,
                  child: Center(
                    child: Text(
                      '등록된 공지사항이 없습니다',
                      style: TextStyle(color: Color(0xFF9A8E8A)),
                    ),
                  ),
                );
              }
              return SizedBox(
                height: 360,
                child: ListView.separated(
                  itemCount: game.notices.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = game.notices[index];
                    final title = item['title']?.toString() ?? '';
                    final category = item['category']?.toString() ?? 'general';
                    final isPinned = item['is_pinned'] == true;
                    final publishedAt = _formatShortDate(item['published_at']);
                    return InkWell(
                      onTap: () => _showNoticeDetailDialog(item),
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
                            if (isPinned)
                              const Padding(
                                padding: EdgeInsets.only(right: 6),
                                child: Icon(Icons.push_pin, size: 16, color: Color(0xFFFF8F00)),
                              ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _noticeCategoryBgColor(category),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _noticeCategoryLabel(category),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _noticeCategoryTextColor(category),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              publishedAt,
                              style: const TextStyle(fontSize: 11, color: Color(0xFF9A8E8A)),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFB0A8A4)),
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

  void _showNoticeDetailDialog(Map<String, dynamic> item) {
    final title = item['title']?.toString() ?? '';
    final content = item['content']?.toString() ?? '';
    final category = item['category']?.toString() ?? 'general';
    final publishedAt = _formatShortDate(item['published_at']);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _noticeCategoryBgColor(category),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _noticeCategoryLabel(category),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _noticeCategoryTextColor(category),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                publishedAt,
                style: const TextStyle(fontSize: 12, color: Color(0xFF9A8E8A)),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Text(
                content,
                style: const TextStyle(fontSize: 14, height: 1.6),
              ),
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
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
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

  void _showTextViewDialog(String title, String? content) {
    final game = context.read<GameService>();
    if (content == null || content.isEmpty) {
      // Fetch from server if not loaded yet
      game.requestAppConfig();
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: Consumer<GameService>(
            builder: (context, game, _) {
              final text = title == '이용약관' ? game.eulaContent : game.privacyPolicy;
              if (text == null) {
                return const Center(child: CircularProgressIndicator());
              }
              if (text.isEmpty) {
                return const Center(
                  child: Text('내용을 불러올 수 없습니다.', style: TextStyle(color: Color(0xFF9A8E8A))),
                );
              }
              return SingleChildScrollView(
                child: Text(
                  text,
                  style: const TextStyle(fontSize: 13, height: 1.6, color: Color(0xFF5A4038)),
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
          ...?trailing == null ? null : [trailing],
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
              color: Colors.white.withValues(alpha: 0.95),
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
                              if (game.isAdminUser) ...[
                                const Divider(height: 1, color: Color(0xFFEAE2DE)),
                                _buildRow(
                                  icon: Icons.support_agent,
                                  iconColor: const Color(0xFFAB47BC),
                                  title: '문의 알림',
                                  subtitle: '새 문의가 들어오면 푸시를 받습니다',
                                  trailing: Switch(
                                    value: game.pushAdminInquiryEnabled,
                                    onChanged: (v) => game.setAdminAlertPush(inquiry: v),
                                  ),
                                ),
                                const Divider(height: 1, color: Color(0xFFEAE2DE)),
                                _buildRow(
                                  icon: Icons.report_gmailerrorred,
                                  iconColor: const Color(0xFFEF5350),
                                  title: '신고 알림',
                                  subtitle: '새 신고가 들어오면 푸시를 받습니다',
                                  trailing: Switch(
                                    value: game.pushAdminReportEnabled,
                                    onChanged: (v) => game.setAdminAlertPush(report: v),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (game.isAdminUser) ...[
                            const SizedBox(height: 12),
                            _buildSection(
                              '관리자',
                              [
                                _buildRow(
                                  icon: Icons.admin_panel_settings_outlined,
                                  iconColor: const Color(0xFF7E57C2),
                                  title: '관리자 센터',
                                  subtitle: '문의, 신고, 유저, 활성 유저를 확인합니다',
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const AdminCenterScreen(),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 12),
                          _buildSection(
                            '계정',
                            [
                              _buildRow(
                                icon: Icons.person,
                                iconColor: const Color(0xFF64B5F6),
                                title: '내 프로필',
                                subtitle: '레벨, 전적, 최근 매치 보기',
                                onTap: widget.onShowMyProfile == null
                                    ? null
                                    : () => widget.onShowMyProfile!(context),
                                trailing: const Icon(Icons.chevron_right, color: Color(0xFFB0A8A4)),
                              ),
                              const Divider(height: 1, color: Color(0xFFEAE2DE)),
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
                          Builder(
                            builder: (context) {
                              final l10n = L10n.of(context);
                              final localeService = context.watch<LocaleService>();
                              final currentLabel = localeService.userSelectedLocale == null
                                  ? l10n.languageAuto
                                  : _localeDisplayName(l10n, localeService.userSelectedLocale!);
                              return _buildSection(
                                l10n.settingsLanguage,
                                [
                                  _buildRow(
                                    icon: Icons.language,
                                    iconColor: const Color(0xFF42A5F5),
                                    title: l10n.settingsLanguage,
                                    subtitle: currentLabel,
                                    onTap: () => _showLanguageDialog(context, localeService, l10n),
                                    trailing: const Icon(Icons.chevron_right, color: Color(0xFFB0A8A4)),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          Builder(
                            builder: (context) {
                              final l10n = L10n.of(context);
                              return _buildSection(
                                l10n.settingsAppInfo,
                                [
                                  Builder(
                                    builder: (context) {
                                      final outdated = _isOutdated(game.latestVersion);
                                      return _buildRow(
                                        icon: Icons.info_outline,
                                        iconColor: outdated
                                            ? const Color(0xFFE53935)
                                            : const Color(0xFF7E57C2),
                                        title: l10n.settingsAppVersion,
                                        subtitle: _appVersion.isEmpty
                                            ? '-'
                                            : (outdated
                                                ? '$_appVersion · ${l10n.settingsNotLatestVersion}'
                                                : _appVersion),
                                        trailing: outdated
                                            ? ElevatedButton(
                                                onPressed: _openStore,
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(0xFFE53935),
                                                  foregroundColor: Colors.white,
                                                  elevation: 0,
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 14,
                                                    vertical: 6,
                                                  ),
                                                  minimumSize: const Size(0, 32),
                                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(10),
                                                  ),
                                                ),
                                                child: Text(
                                                  l10n.settingsUpdate,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              )
                                            : null,
                                      );
                                    },
                                  ),
                                  const Divider(height: 1, color: Color(0xFFEAE2DE)),
                                  _buildRow(
                                    icon: Icons.description_outlined,
                                    iconColor: const Color(0xFF8A7A72),
                                    title: l10n.settingsTermsOfService,
                                    onTap: () => _showTextViewDialog(l10n.settingsTermsOfService, game.eulaContent),
                                    trailing: const Icon(Icons.chevron_right, color: Color(0xFFB0A8A4)),
                                  ),
                                  const Divider(height: 1, color: Color(0xFFEAE2DE)),
                                  _buildRow(
                                    icon: Icons.privacy_tip_outlined,
                                    iconColor: const Color(0xFF8A7A72),
                                    title: l10n.settingsPrivacyPolicy,
                                    onTap: () => _showTextViewDialog(l10n.settingsPrivacyPolicy, game.privacyPolicy),
                                    trailing: const Icon(Icons.chevron_right, color: Color(0xFFB0A8A4)),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          _buildSection(
                            L10n.of(context).settingsNotices,
                            [
                              _buildRow(
                                icon: Icons.campaign,
                                iconColor: const Color(0xFF42A5F5),
                                title: L10n.of(context).settingsNotices,
                                onTap: _showNoticesDialog,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (game.unreadNoticeCount > 0)
                                      Container(
                                        margin: const EdgeInsets.only(right: 8),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2,
                                        ),
                                        decoration: const BoxDecoration(
                                          color: Color(0xFFE53935),
                                          borderRadius: BorderRadius.all(
                                            Radius.circular(999),
                                          ),
                                        ),
                                        constraints: const BoxConstraints(
                                          minWidth: 18,
                                          minHeight: 18,
                                        ),
                                        child: Text(
                                          game.unreadNoticeCount > 9
                                              ? '9+'
                                              : '${game.unreadNoticeCount}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    const Icon(
                                      Icons.chevron_right,
                                      color: Color(0xFFB0A8A4),
                                    ),
                                  ],
                                ),
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
                          const SizedBox(height: 12),
                          if (_bannerAd != null && _bannerAdLoaded)
                            Center(
                              child: SizedBox(
                                height: _bannerAd!.size.height.toDouble(),
                                width: _bannerAd!.size.width.toDouble(),
                                child: AdWidget(ad: _bannerAd!, key: ValueKey(_bannerAd!.hashCode)),
                              ),
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
