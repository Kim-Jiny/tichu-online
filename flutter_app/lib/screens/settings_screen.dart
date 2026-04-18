import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n_helpers.dart';
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
    final l10n = L10n.of(context);
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(l10n.settingsDeleteAccount),
        content: Text(l10n.settingsDeleteAccountConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(l10n.commonCancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              _deleteAccount();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
              foregroundColor: Colors.white,
            ),
            child: Text(l10n.settingsDeleteAccountWithdraw),
          ),
        ],
      ),
    );
  }

  void _deleteAccount() {
    final game = context.read<GameService>();
    game.deleteAccount().whenComplete(_logout);
  }

  String _noticeCategoryLabel(L10n l10n, dynamic value) {
    switch (value?.toString()) {
      case 'release': return l10n.noticeCategoryRelease;
      case 'update': return l10n.noticeCategoryUpdate;
      case 'preview': return l10n.noticeCategoryPreview;
      case 'general': return l10n.noticeCategoryGeneral;
      default: return l10n.noticeCategoryGeneral;
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
    final l10n = L10n.of(context);
    // Mark all (existing + freshly fetched) notices as read — opening the
    // dialog counts as "seeing" them, which clears the red badges.
    game.markCurrentNoticesAsRead();
    game.requestNotices(markReadOnReceive: true);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.campaign, color: Color(0xFF42A5F5)),
            const SizedBox(width: 8),
            Flexible(child: Text(l10n.noticeTitle, overflow: TextOverflow.ellipsis)),
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
                          localizeServiceMessage(game.noticesError!, L10n.of(context)),
                          style: const TextStyle(color: Color(0xFFCC6666)),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: () => game.requestNotices(),
                          child: Text(l10n.noticeRetry),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (game.notices.isEmpty) {
                return SizedBox(
                  height: 140,
                  child: Center(
                    child: Text(
                      l10n.noticeEmpty,
                      style: const TextStyle(color: Color(0xFF9A8E8A)),
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
                                _noticeCategoryLabel(l10n, category),
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
            child: Text(l10n.commonClose),
          ),
        ],
      ),
    );
  }

  void _showNoticeDetailDialog(Map<String, dynamic> item) {
    final l10n = L10n.of(context);
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
                _noticeCategoryLabel(l10n, category),
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
            child: Text(l10n.commonClose),
          ),
        ],
      ),
    );
  }

  void _showInquiryDialog() {
    final l10n = L10n.of(context);
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    String selectedCategory = 'bug';

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.help_outline, color: Color(0xFFBA68C8)),
              const SizedBox(width: 8),
              Flexible(child: Text(l10n.inquiryTitle, overflow: TextOverflow.ellipsis)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.inquiryCategory, style: const TextStyle(fontSize: 13, color: Color(0xFF8A8A8A))),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(l10n.inquiryCategoryBug),
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
                      label: Text(l10n.inquiryCategorySuggestion),
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
                      label: Text(l10n.inquiryCategoryOther),
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
                Text(l10n.inquiryFieldTitle, style: const TextStyle(fontSize: 13, color: Color(0xFF8A8A8A))),
                const SizedBox(height: 4),
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(
                    hintText: l10n.inquiryFieldTitleHint,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 12),
                Text(l10n.inquiryFieldContent, style: const TextStyle(fontSize: 13, color: Color(0xFF8A8A8A))),
                const SizedBox(height: 4),
                TextField(
                  controller: contentController,
                  maxLines: 5,
                  decoration: InputDecoration(
                    hintText: l10n.inquiryFieldContentHint,
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
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(l10n.commonCancel),
            ),
            ElevatedButton(
              onPressed: () {
                final title = titleController.text.trim();
                final content = contentController.text.trim();
                if (title.isEmpty || content.isEmpty) return;
                final game = dialogCtx.read<GameService>();
                game.submitInquiry(selectedCategory, title, content);
                Navigator.pop(dialogCtx);
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(content: Text(l10n.inquirySubmitted)),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFBA68C8),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(l10n.inquirySubmit),
            ),
          ],
        ),
      ),
    );
  }

  void _showInquiryHistoryDialog() {
    final game = context.read<GameService>();
    final l10n = L10n.of(context);
    game.markInquiriesRead();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.mark_email_read, color: Color(0xFF1E88E5)),
            const SizedBox(width: 8),
            Flexible(child: Text(l10n.inquiryHistoryTitle, overflow: TextOverflow.ellipsis)),
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
                          localizeServiceMessage(game.inquiriesError!, L10n.of(context)),
                          style: const TextStyle(color: Color(0xFFCC6666)),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: () => game.requestInquiries(),
                          child: Text(l10n.noticeRetry),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (game.inquiries.isEmpty) {
                return SizedBox(
                  height: 140,
                  child: Center(
                    child: Text(
                      l10n.inquiryEmpty,
                      style: const TextStyle(color: Color(0xFF9A8E8A)),
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
                    final category = _inquiryCategoryLabel(l10n, item['category']);
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
                                isResolved ? l10n.inquiryStatusResolved : l10n.inquiryStatusPending,
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
            child: Text(l10n.commonClose),
          ),
        ],
      ),
    );
  }

  void _showInquiryDetailDialog(Map<String, dynamic> item) {
    final l10n = L10n.of(context);
    final title = item['title']?.toString() ?? '';
    final content = item['content']?.toString() ?? '';
    final adminNote = item['admin_note']?.toString() ?? '';
    final status = item['status']?.toString() ?? 'pending';
    final category = _inquiryCategoryLabel(l10n, item['category']);
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
                Text(
                  l10n.inquiryAnswerLabel,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4CAF50)),
                ),
                const SizedBox(height: 6),
                Text(
                  adminNote,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF5A4038)),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.inquiryAnswerDate(resolvedAt),
                  style: const TextStyle(fontSize: 11, color: Color(0xFF8A7A72)),
                ),
              ] else if (status != 'resolved') ...[
                Text(
                  l10n.inquiryNoAnswer,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF9A8E8A)),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.commonClose),
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

  String _inquiryCategoryLabel(L10n l10n, dynamic value) {
    switch (value?.toString()) {
      case 'bug':
        return l10n.inquiryCategoryBug;
      case 'suggestion':
        return l10n.inquiryCategorySuggestion;
      case 'other':
        return l10n.inquiryCategoryOther;
      default:
        return l10n.inquiryCategoryOther;
    }
  }

  void _showTextViewDialog(String title, String? content, {bool isTermsOfService = false}) {
    final game = context.read<GameService>();
    final l10n = L10n.of(context);
    if (content == null || content.isEmpty) {
      // Fetch from server if not loaded yet
      game.requestAppConfig();
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: Consumer<GameService>(
            builder: (context, game, _) {
              final text = isTermsOfService ? game.eulaContent : game.privacyPolicy;
              if (text == null) {
                return const Center(child: CircularProgressIndicator());
              }
              if (text.isEmpty) {
                return Center(
                  child: Text(l10n.textViewLoadFailed, style: const TextStyle(color: Color(0xFF9A8E8A))),
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
            child: Text(l10n.commonClose),
          ),
        ],
      ),
    );
  }

  void _showLinkDialog() {
    final l10n = L10n.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(l10n.linkDialogTitle),
        content: Text(l10n.linkDialogContent),
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
                    SnackBar(content: Text(l10n.settingsLinkFailed(e.toString()))),
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
                      SnackBar(content: Text(l10n.settingsLinkFailed(e.toString()))),
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
                    SnackBar(content: Text(l10n.settingsLinkFailed(e.toString()))),
                  );
                }
              }
            },
            child: const Text('Kakao', style: TextStyle(color: Color(0xFF3C1E1E), fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.commonCancel),
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
    final l10n = L10n.of(context);
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
                      content: Text(success ? l10n.settingsLinkComplete : message),
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
                        Flexible(
                          child: Text(
                            l10n.settingsHeaderTitle,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF5A4038),
                            ),
                            overflow: TextOverflow.ellipsis,
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
                            l10n.settingsNotificationsSection,
                            [
                              _buildRow(
                                icon: Icons.notifications,
                                iconColor: const Color(0xFF64B5F6),
                                title: l10n.settingsPushNotifications,
                                subtitle: l10n.settingsPushNotificationsDesc,
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
                                  title: l10n.settingsInquiryNotifications,
                                  subtitle: l10n.settingsInquiryNotificationsDesc,
                                  trailing: Switch(
                                    value: game.pushAdminInquiryEnabled,
                                    onChanged: (v) => game.setAdminAlertPush(inquiry: v),
                                  ),
                                ),
                                const Divider(height: 1, color: Color(0xFFEAE2DE)),
                                _buildRow(
                                  icon: Icons.report_gmailerrorred,
                                  iconColor: const Color(0xFFEF5350),
                                  title: l10n.settingsReportNotifications,
                                  subtitle: l10n.settingsReportNotificationsDesc,
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
                              l10n.settingsAdminSection,
                              [
                                _buildRow(
                                  icon: Icons.admin_panel_settings_outlined,
                                  iconColor: const Color(0xFF7E57C2),
                                  title: l10n.settingsAdminCenter,
                                  subtitle: l10n.settingsAdminCenterDesc,
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
                            l10n.settingsAccountSection,
                            [
                              _buildRow(
                                icon: Icons.person,
                                iconColor: const Color(0xFF64B5F6),
                                title: l10n.settingsMyProfile,
                                subtitle: l10n.settingsProfileSubtitle,
                                onTap: widget.onShowMyProfile == null
                                    ? null
                                    : () => widget.onShowMyProfile!(context),
                                trailing: const Icon(Icons.chevron_right, color: Color(0xFFB0A8A4)),
                              ),
                              const Divider(height: 1, color: Color(0xFFEAE2DE)),
                              _buildRow(
                                icon: Icons.account_circle,
                                iconColor: const Color(0xFF64B5F6),
                                title: l10n.settingsNickname,
                                subtitle: game.playerName,
                              ),
                              const Divider(height: 1, color: Color(0xFFEAE2DE)),
                              _buildRow(
                                icon: Icons.link,
                                iconColor: const Color(0xFF7E57C2),
                                title: l10n.settingsSocialLink,
                                subtitle: game.authProvider != 'local'
                                    ? l10n.settingsSocialLinked(game.authProvider.toUpperCase())
                                    : (game.linkedSocialProvider != null && game.linkedSocialProvider != 'local')
                                        ? l10n.settingsSocialLinked(game.linkedSocialProvider!.toUpperCase())
                                        : l10n.settingsNoLinkedAccount,
                                trailing: game.authProvider == 'local' &&
                                        (game.linkedSocialProvider == null || game.linkedSocialProvider == 'local')
                                    ? TextButton(
                                        onPressed: () => _showLinkDialog(),
                                        child: Text(l10n.commonLink, style: const TextStyle(color: Color(0xFF7E57C2), fontSize: 12)),
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
                                    onTap: () => _showTextViewDialog(l10n.settingsTermsOfService, game.eulaContent, isTermsOfService: true),
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
                            l10n.settingsInquirySection,
                            [
                              _buildRow(
                                icon: Icons.help_outline,
                                iconColor: const Color(0xFFBA68C8),
                                title: l10n.settingsSubmitInquiry,
                                onTap: _showInquiryDialog,
                                trailing: const Icon(Icons.chevron_right, color: Color(0xFFB0A8A4)),
                              ),
                              const Divider(height: 1, color: Color(0xFFEAE2DE)),
                              _buildRow(
                                icon: Icons.mark_email_read,
                                iconColor: const Color(0xFF1E88E5),
                                title: l10n.settingsInquiryHistory,
                                onTap: _showInquiryHistoryDialog,
                                trailing: const Icon(Icons.chevron_right, color: Color(0xFFB0A8A4)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildSection(
                            l10n.settingsAccountManagement,
                            [
                              _buildRow(
                                icon: Icons.logout,
                                iconColor: const Color(0xFF8A7A72),
                                title: l10n.settingsLogout,
                                onTap: _logout,
                                trailing: const Icon(Icons.chevron_right, color: Color(0xFFB0A8A4)),
                              ),
                              const Divider(height: 1, color: Color(0xFFEAE2DE)),
                              _buildRow(
                                icon: Icons.delete_forever,
                                iconColor: const Color(0xFFC62828),
                                title: l10n.settingsDeleteAccount,
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
