import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n_helpers.dart';
import '../services/game_service.dart';
import '../widgets/player_profile_header.dart';
import '../widgets/profile_avatar.dart';
import '../services/auth_service.dart';
import '../services/locale_service.dart';
import '../services/session_service.dart';
import '../services/ad_service.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'admin_center_screen.dart';
import 'notices_screen.dart';

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

  // Owned by the State, not the inquiry dialog: the dialog's CLOSE animation
  // keeps rebuilding its TextFields for a few frames after the route future
  // completes. Disposing in the dialog's whenComplete() therefore freed these
  // mid-transition and the next frame's addListener hit a disposed controller
  // ("used after being disposed"). State.dispose runs only after teardown, so
  // tying their lifetime to the State avoids the race. Cleared on each open.
  final TextEditingController _inquiryTitleController = TextEditingController();
  final TextEditingController _inquiryContentController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _bannerAd = AdService.createBannerAd(
      AdService.settingsBannerId,
      onAdLoaded: (_) {
        if (mounted) setState(() => _bannerAdLoaded = true);
      },
      onAdFailedToLoad: (_, _) {
        if (mounted)
          setState(() {
            _bannerAd = null;
            _bannerAdLoaded = false;
          });
      },
    );
    _bannerAd!.load();
    _loadAppVersion();
    // The header block shows level and exp, which only arrive with a profile
    // fetch. Deferred: requestProfile notifies listeners synchronously.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final game = context.read<GameService>();
      if (game.playerName.isNotEmpty) {
        game.requestProfile(game.playerName);
      }
    });
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    _inquiryTitleController.dispose();
    _inquiryContentController.dispose();
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
    final partsA = a
        .split('+')
        .first
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
    final partsB = b
        .split('+')
        .first
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
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
      case 'en':
        return l10n.languageEnglish;
      case 'ko':
        return l10n.languageKorean;
      case 'de':
        return l10n.languageGerman;
      default:
        return locale.languageCode;
    }
  }

  void _showLanguageDialog(
    BuildContext ctx,
    LocaleService localeService,
    L10n l10n,
  ) {
    showDialog(
      context: ctx,
      builder: (dialogCtx) => SimpleDialog(
        title: Text(l10n.settingsLanguage),
        children: [
          _languageOption(dialogCtx, localeService, null, l10n.languageAuto),
          _languageOption(
            dialogCtx,
            localeService,
            const Locale('en'),
            'English',
          ),
          _languageOption(dialogCtx, localeService, const Locale('ko'), '한국어'),
          _languageOption(
            dialogCtx,
            localeService,
            const Locale('de'),
            'Deutsch',
          ),
        ],
      ),
    );
  }

  Widget _languageOption(
    BuildContext dialogCtx,
    LocaleService localeService,
    Locale? locale,
    String label,
  ) {
    final isSelected = localeService.userSelectedLocale == locale;
    return SimpleDialogOption(
      onPressed: () {
        localeService.setLocale(locale);
        final effectiveCode =
            (locale ?? localeService.effectiveLocale).languageCode;
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
                color: isSelected
                    ? const Color(0xFF42A5F5)
                    : const Color(0xFF3E312A),
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
    final uri = Uri.parse(
      Platform.isIOS
          ? 'https://apps.apple.com/app/tichu-online/id6759035151'
          : 'https://play.google.com/store/apps/details?id=com.jiny.tichuOnline',
    );
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

  void _openNoticesPage() {
    final game = context.read<GameService>();
    // Capture unread IDs before marking as read, so we can show "NEW" badges
    final unreadIds = <int>{};
    for (final n in game.notices) {
      final id = n['id'];
      if (id is int && !game.readNoticeIds.contains(id)) unreadIds.add(id);
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NoticesScreen(unreadIds: unreadIds)),
    );
  }

  void _showInquiryDialog() {
    final l10n = L10n.of(context);
    // Reuse the State-owned controllers; reset their contents for a fresh form.
    _inquiryTitleController.clear();
    _inquiryContentController.clear();
    String selectedCategory = 'bug';

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              const Icon(Icons.help_outline, color: Color(0xFFBA68C8)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(l10n.inquiryTitle, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.inquiryCategory,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF8A8A8A),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(l10n.inquiryCategoryBug),
                      selected: selectedCategory == 'bug',
                      onSelected: (_) =>
                          setState(() => selectedCategory = 'bug'),
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
                      onSelected: (_) =>
                          setState(() => selectedCategory = 'suggestion'),
                      selectedColor: const Color(0xFFEDE7F6),
                      labelStyle: TextStyle(
                        color: selectedCategory == 'suggestion'
                            ? const Color(0xFF6A4FA3)
                            : const Color(0xFF5A4038),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    ChoiceChip(
                      label: Text(l10n.inquiryCategoryPayment),
                      selected: selectedCategory == 'payment',
                      onSelected: (_) =>
                          setState(() => selectedCategory = 'payment'),
                      selectedColor: const Color(0xFFEDE7F6),
                      labelStyle: TextStyle(
                        color: selectedCategory == 'payment'
                            ? const Color(0xFF6A4FA3)
                            : const Color(0xFF5A4038),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    ChoiceChip(
                      label: Text(l10n.inquiryCategoryOther),
                      selected: selectedCategory == 'other',
                      onSelected: (_) =>
                          setState(() => selectedCategory = 'other'),
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
                Text(
                  l10n.inquiryFieldTitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF8A8A8A),
                  ),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: _inquiryTitleController,
                  decoration: InputDecoration(
                    hintText: l10n.inquiryFieldTitleHint,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.inquiryFieldContent,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF8A8A8A),
                  ),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: _inquiryContentController,
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
                final title = _inquiryTitleController.text.trim();
                final content = _inquiryContentController.text.trim();
                if (title.isEmpty || content.isEmpty) return;
                final game = dialogCtx.read<GameService>();
                game.submitInquiry(selectedCategory, title, content);
                Navigator.pop(dialogCtx);
                ScaffoldMessenger.of(
                  this.context,
                ).showSnackBar(SnackBar(content: Text(l10n.inquirySubmitted)));
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
            Flexible(
              child: Text(
                l10n.inquiryHistoryTitle,
                overflow: TextOverflow.ellipsis,
              ),
            ),
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
                          localizeServiceMessage(
                            game.inquiriesError!,
                            L10n.of(context),
                          ),
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
                    final category = _inquiryCategoryLabel(
                      l10n,
                      item['category'],
                    );
                    final status = item['status']?.toString() ?? 'pending';
                    final createdAt = _formatShortDate(item['created_at']);
                    final isResolved = status == 'resolved';
                    return InkWell(
                      onTap: () => _showInquiryDetailDialog(item),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE0D8D4)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isResolved
                                    ? const Color(0xFFE8F5E9)
                                    : const Color(0xFFFFF8E1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                isResolved
                                    ? l10n.inquiryStatusResolved
                                    : l10n.inquiryStatusPending,
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
                            const Icon(
                              Icons.chevron_right,
                              color: Color(0xFFB0A8A4),
                            ),
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
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4CAF50),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  adminNote,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF5A4038),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.inquiryAnswerDate(resolvedAt),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF8A7A72),
                  ),
                ),
              ] else if (status != 'resolved') ...[
                Text(
                  l10n.inquiryNoAnswer,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9A8E8A),
                  ),
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
      case 'payment':
        return l10n.inquiryCategoryPayment;
      case 'other':
        return l10n.inquiryCategoryOther;
      default:
        return l10n.inquiryCategoryOther;
    }
  }

  String _cardViewPrefLabel(L10n l10n, String pref) {
    switch (pref) {
      case 'always_allow':
        return l10n.gameCardViewPolicyAllow;
      case 'always_deny':
        return l10n.gameCardViewPolicyDeny;
      case 'ask':
      default:
        return l10n.gameCardViewPolicyAsk;
    }
  }

  void _showCardViewPrefDialog(
    BuildContext context,
    GameService game,
    L10n l10n,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            Widget option({
              required String value,
              required String label,
              required IconData icon,
              required Color color,
            }) {
              final selected = game.cardViewPref == value;
              return InkWell(
                onTap: () {
                  game.setCardViewPref(value);
                  setDialogState(() {});
                  Navigator.pop(ctx);
                },
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(icon, size: 20, color: color),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: selected
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: const Color(0xFF5A4038),
                          ),
                        ),
                      ),
                      if (selected) Icon(Icons.check, color: color, size: 20),
                    ],
                  ),
                ),
              );
            }

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.settingsCardViewPolicy,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF5A4038),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.settingsCardViewPolicyDescription,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF8A7A72),
                      ),
                    ),
                    const SizedBox(height: 12),
                    option(
                      value: 'ask',
                      label: l10n.gameCardViewPolicyAsk,
                      icon: Icons.help_outline,
                      color: const Color(0xFF6A6090),
                    ),
                    option(
                      value: 'always_allow',
                      label: l10n.gameCardViewPolicyAllow,
                      icon: Icons.check_circle,
                      color: const Color(0xFF4CAF50),
                    ),
                    option(
                      value: 'always_deny',
                      label: l10n.gameCardViewPolicyDeny,
                      icon: Icons.block,
                      color: const Color(0xFFE53935),
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

  void _showTextViewDialog(
    String title,
    String? content, {
    bool isTermsOfService = false,
  }) {
    final game = context.read<GameService>();
    final l10n = L10n.of(context);
    if (content == null || content.isEmpty) {
      // Fetch from server if not loaded yet. Pass the current UI locale so
      // the server returns the matching-language EULA/privacy.
      final locale = context.read<LocaleService>().effectiveLocale.languageCode;
      game.requestAppConfig(locale: locale);
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
              final text = isTermsOfService
                  ? game.eulaContent
                  : game.privacyPolicy;
              if (text == null) {
                return const Center(child: CircularProgressIndicator());
              }
              if (text.isEmpty) {
                return Center(
                  child: Text(
                    l10n.textViewLoadFailed,
                    style: const TextStyle(color: Color(0xFF9A8E8A)),
                  ),
                );
              }
              return SingleChildScrollView(
                child: Text(
                  text,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    color: Color(0xFF5A4038),
                  ),
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
                context.read<GameService>().linkSocial(
                  result.provider,
                  result.token,
                );
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(l10n.settingsLinkFailed(e.toString())),
                    ),
                  );
                }
              }
            },
            child: const Text(
              'Google',
              style: TextStyle(
                color: Color(0xFF4285F4),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (Platform.isIOS)
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  final result = await AuthService.signInWithApple();
                  if (result.cancelled || !mounted) return;
                  context.read<GameService>().linkSocial(
                    result.provider,
                    result.token,
                  );
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.settingsLinkFailed(e.toString())),
                      ),
                    );
                  }
                }
              },
              child: const Text(
                'Apple',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final result = await AuthService.signInWithKakao();
                if (result.cancelled || !mounted) return;
                context.read<GameService>().linkSocial(
                  result.provider,
                  result.token,
                );
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(l10n.settingsLinkFailed(e.toString())),
                    ),
                  );
                }
              }
            },
            child: const Text(
              'Kakao',
              style: TextStyle(
                color: Color(0xFF3C1E1E),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.commonCancel),
          ),
        ],
      ),
    );
  }

  /// Avatar, nickname and level at the top, tappable into the profile popup.
  Widget _buildProfileBlock(BuildContext context, GameService game, L10n l10n) {
    final inner = game.playerName.isEmpty
        ? null
        : game.profileFor(game.playerName)?['profile'] as Map?;
    final level = (inner?['level'] as int?) ?? 1;
    final expTotal = (inner?['expTotal'] as int?) ?? 0;
    final photo = game.resolvePhotoUrl(game.myPhotoUrl);

    return Material(
      color: const Color(0xFFFFFDFC),
      child: InkWell(
        onTap: widget.onShowMyProfile == null
            ? null
            : () => widget.onShowMyProfile!(context),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: Color(0xFFEFE7E3)),
              bottom: BorderSide(color: Color(0xFFEFE7E3)),
            ),
          ),
          child: Row(
            children: [
              ProfileAvatar(
                photoUrl: photo,
                size: 52,
                borderRadius: 16,
                fallback: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0E7E3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.person,
                    size: 30,
                    color: Color(0xFF9C8B84),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      game.playerName.isEmpty ? '-' : game.playerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF4A3A33),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Same level/exp strip the profile popup uses, so the two
                    // never disagree about how far along you are.
                    profileLevelStrip(level, expTotal),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: Color(0xFFB0A8A4)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow({
    required IconData icon,
    required String title,
    Color? iconColor,
    Color? titleColor,
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
                    color: enabled
                        ? (titleColor ?? const Color(0xFF5A4038))
                        : const Color(0xFFB0A8A4),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: enabled
                          ? const Color(0xFF8A7A72)
                          : const Color(0xFFBDB5B1),
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
    return InkWell(onTap: onTap, child: content);
  }

  static const _rowDivider = Divider(
    height: 1,
    thickness: 1,
    indent: 56,
    color: Color(0xFFF2ECE9),
  );

  /// Small label above a group. Sits on the sheet, not on the background —
  /// labels on the gradient turned the page into pink and white stripes.
  Widget _buildGroupLabel(String text) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFFDFC),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF9A8E8A),
        ),
      ),
    );
  }

  Widget _buildGroup(List<Widget> children) {
    return Container(
      color: const Color(0xFFFFFDFC),
      child: Column(children: children),
    );
  }

  /// The three places people leave settings for: notices, a new inquiry, and
  /// (for staff) the admin console. They were a section heading each, one row
  /// deep. As tiles they are one tap and no scrolling.
  Widget _buildQuickTiles(BuildContext context, GameService game, L10n l10n) {
    Widget tile({
      required IconData icon,
      required Color color,
      required String label,
      required VoidCallback onTap,
      int badge = 0,
    }) {
      return Expanded(
        child: Material(
          color: const Color(0xFFFFFDFC),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(icon, color: color, size: 24),
                      if (badge > 0)
                        Positioned(
                          right: -8,
                          top: -6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: const BoxDecoration(
                              color: Color(0xFFE53935),
                              borderRadius: BorderRadius.all(
                                Radius.circular(999),
                              ),
                            ),
                            constraints: const BoxConstraints(minWidth: 16),
                            child: Text(
                              badge > 9 ? '9+' : '$badge',
                              textAlign: TextAlign.center,
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
                  const SizedBox(height: 8),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF5A4038),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      child: Row(
        children: [
          tile(
            icon: Icons.campaign,
            color: const Color(0xFF42A5F5),
            label: l10n.settingsNotices,
            onTap: _openNoticesPage,
            badge: game.unreadNoticeCount,
          ),
          const SizedBox(width: 8),
          tile(
            icon: Icons.help_outline,
            color: const Color(0xFFBA68C8),
            label: l10n.settingsSubmitInquiry,
            onTap: _showInquiryDialog,
          ),
          if (game.isAdminUser) ...[
            const SizedBox(width: 8),
            tile(
              icon: Icons.admin_panel_settings_outlined,
              color: const Color(0xFF7E57C2),
              label: l10n.settingsAdminCenter,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminCenterScreen()),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Version as a footer caption rather than a row: it is something to read
  /// once, not something to do. The update button appears only when behind.
  Widget _buildVersionFooter(L10n l10n, GameService game) {
    final outdated = _isOutdated(game.latestVersion);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      child: Column(
        children: [
          Text(
            '${l10n.settingsAppVersion} ${_appVersion.isEmpty ? '-' : _appVersion}',
            style: TextStyle(
              fontSize: 12,
              color: outdated
                  ? const Color(0xFFE53935)
                  : const Color(0xFFA89C96),
              fontWeight: outdated ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          if (outdated) ...[
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _openStore,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE53935),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                minimumSize: const Size(0, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                '${l10n.settingsNotLatestVersion} · ${l10n.settingsUpdate}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
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
                      content: Text(
                        success ? l10n.settingsLinkComplete : message,
                      ),
                      backgroundColor: success ? Colors.green : Colors.red,
                    ),
                  );
                }
              });
              return Column(
                children: [
                  // Flat header on the theme gradient, like the shop and the
                  // room list — the white used to start here as a floating card.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 2, 16, 6),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back),
                          color: const Color(0xFF8A7A72),
                          visualDensity: VisualDensity.compact,
                        ),
                        Flexible(
                          child: Text(
                            l10n.settingsHeaderTitle,
                            style: const TextStyle(
                              fontSize: 19,
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
                          // Who this is, first. It used to be one row among
                          // fifteen, three sections down — the thing people open
                          // settings to check was the hardest to find.
                          _buildProfileBlock(context, game, l10n),
                          _buildQuickTiles(context, game, l10n),
                          // Everything that is genuinely a setting: one surface,
                          // three groups. It was nine bordered cards, and the
                          // labels ("공지사항", "문의") were section headings for a
                          // single row each — a table of contents for a page you
                          // could already see.
                          _buildGroupLabel(l10n.settingsSettingsGroup),
                          _buildGroup([
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
                              _rowDivider,
                              _buildRow(
                                icon: Icons.support_agent,
                                iconColor: const Color(0xFFAB47BC),
                                title: l10n.settingsInquiryNotifications,
                                subtitle: l10n.settingsInquiryNotificationsDesc,
                                trailing: Switch(
                                  value: game.pushAdminInquiryEnabled,
                                  onChanged: (v) =>
                                      game.setAdminAlertPush(inquiry: v),
                                ),
                              ),
                              _rowDivider,
                              _buildRow(
                                icon: Icons.report_gmailerrorred,
                                iconColor: const Color(0xFFEF5350),
                                title: l10n.settingsReportNotifications,
                                subtitle: l10n.settingsReportNotificationsDesc,
                                trailing: Switch(
                                  value: game.pushAdminReportEnabled,
                                  onChanged: (v) =>
                                      game.setAdminAlertPush(report: v),
                                ),
                              ),
                              _rowDivider,
                              _buildRow(
                                icon: Icons.payments_outlined,
                                iconColor: const Color(0xFF26A69A),
                                title: l10n.settingsPaymentNotifications,
                                subtitle: l10n.settingsPaymentNotificationsDesc,
                                trailing: Switch(
                                  value: game.pushAdminPaymentEnabled,
                                  onChanged: (v) =>
                                      game.setAdminAlertPush(payment: v),
                                ),
                              ),
                            ],
                            _rowDivider,
                            _buildRow(
                              icon: Icons.visibility_outlined,
                              iconColor: const Color(0xFF6A6090),
                              title: l10n.settingsCardViewPolicy,
                              subtitle: _cardViewPrefLabel(
                                l10n,
                                game.cardViewPref,
                              ),
                              trailing: const Icon(
                                Icons.chevron_right,
                                color: Color(0xFFB0A8A4),
                              ),
                              onTap: () =>
                                  _showCardViewPrefDialog(context, game, l10n),
                            ),
                            _rowDivider,
                            Builder(
                              builder: (context) {
                                final localeService = context
                                    .watch<LocaleService>();
                                final currentLabel =
                                    localeService.userSelectedLocale == null
                                    ? l10n.languageAuto
                                    : _localeDisplayName(
                                        l10n,
                                        localeService.userSelectedLocale!,
                                      );
                                return _buildRow(
                                  icon: Icons.language,
                                  iconColor: const Color(0xFF42A5F5),
                                  title: l10n.settingsLanguage,
                                  subtitle: currentLabel,
                                  onTap: () => _showLanguageDialog(
                                    context,
                                    localeService,
                                    l10n,
                                  ),
                                  trailing: const Icon(
                                    Icons.chevron_right,
                                    color: Color(0xFFB0A8A4),
                                  ),
                                );
                              },
                            ),
                          ]),
                          _buildGroupLabel(l10n.settingsAccountSection),
                          _buildGroup([
                            _buildRow(
                              icon: Icons.link,
                              iconColor: const Color(0xFF7E57C2),
                              title: l10n.settingsSocialLink,
                              subtitle: game.authProvider != 'local'
                                  ? l10n.settingsSocialLinked(
                                      game.authProvider.toUpperCase(),
                                    )
                                  : (game.linkedSocialProvider != null &&
                                        game.linkedSocialProvider != 'local')
                                  ? l10n.settingsSocialLinked(
                                      game.linkedSocialProvider!.toUpperCase(),
                                    )
                                  : l10n.settingsNoLinkedAccount,
                              trailing:
                                  game.authProvider == 'local' &&
                                      (game.linkedSocialProvider == null ||
                                          game.linkedSocialProvider == 'local')
                                  ? TextButton(
                                      onPressed: () => _showLinkDialog(),
                                      child: Text(
                                        l10n.commonLink,
                                        style: const TextStyle(
                                          color: Color(0xFF7E57C2),
                                          fontSize: 12,
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                            _rowDivider,
                            _buildRow(
                              icon: Icons.logout,
                              iconColor: const Color(0xFF8A7A72),
                              title: l10n.settingsLogout,
                              onTap: _logout,
                            ),
                            _rowDivider,
                            // Leaving for good sits at the bottom of its group,
                            // in red, away from everything reversible.
                            _buildRow(
                              icon: Icons.delete_forever,
                              iconColor: const Color(0xFFC62828),
                              titleColor: const Color(0xFFC62828),
                              title: l10n.settingsDeleteAccount,
                              onTap: _showDeleteAccountDialog,
                            ),
                          ]),
                          _buildGroupLabel(l10n.settingsInfoGroup),
                          _buildGroup([
                            _buildRow(
                              icon: Icons.description_outlined,
                              iconColor: const Color(0xFF8A7A72),
                              title: l10n.settingsTermsOfService,
                              onTap: () => _showTextViewDialog(
                                l10n.settingsTermsOfService,
                                game.eulaContent,
                                isTermsOfService: true,
                              ),
                              trailing: const Icon(
                                Icons.chevron_right,
                                color: Color(0xFFB0A8A4),
                              ),
                            ),
                            _rowDivider,
                            _buildRow(
                              icon: Icons.privacy_tip_outlined,
                              iconColor: const Color(0xFF8A7A72),
                              title: l10n.settingsPrivacyPolicy,
                              onTap: () => _showTextViewDialog(
                                l10n.settingsPrivacyPolicy,
                                game.privacyPolicy,
                              ),
                              trailing: const Icon(
                                Icons.chevron_right,
                                color: Color(0xFFB0A8A4),
                              ),
                            ),
                            _rowDivider,
                            _buildRow(
                              icon: Icons.mark_email_read,
                              iconColor: const Color(0xFF1E88E5),
                              title: l10n.settingsInquiryHistory,
                              onTap: _showInquiryHistoryDialog,
                              trailing: Consumer<GameService>(
                                builder: (_, g, _) => Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (g.unreadInquiryReplyCount > 0)
                                      Container(
                                        width: 8,
                                        height: 8,
                                        margin: const EdgeInsets.only(right: 6),
                                        decoration: const BoxDecoration(
                                          color: Color(0xFFE53935),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    const Icon(
                                      Icons.chevron_right,
                                      color: Color(0xFFB0A8A4),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ]),
                          _buildVersionFooter(l10n, game),
                          if (_bannerAd != null && _bannerAdLoaded)
                            Center(
                              child: SizedBox(
                                height: _bannerAd!.size.height.toDouble(),
                                width: _bannerAd!.size.width.toDouble(),
                                child: AdWidget(
                                  ad: _bannerAd!,
                                  key: ValueKey(_bannerAd!.hashCode),
                                ),
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
