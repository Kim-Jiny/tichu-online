import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../config/social_config.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../theme/cartoon.dart';
import 'rules_screen.dart';
import '../l10n/l10n_helpers.dart';
import '../services/game_service.dart';
import '../widgets/coupon_redeem.dart';
import '../widgets/choice_pill.dart';
import '../widgets/legal_text_dialog.dart';
import '../widgets/social_logo.dart';
import '../widgets/notice_body.dart';
import '../widgets/player_profile_header.dart';
import '../widgets/profile_avatar.dart';
import '../services/auth_service.dart';
import '../services/locale_service.dart';
import '../services/session_service.dart';
import '../services/ad_service.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'admin_center_screen.dart';
import 'mailbox_screen.dart';
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
    // AdMob has no web implementation at all, so this can only fail there.
    // Leaving it to fail was working — the load callbacks null the banner
    // out — but it is a plugin exception per screen to get to the same
    // place. Web ads would be AdSense / H5 Games Ads, a separate product.
    _bannerAd = kIsWeb
        ? null
        : AdService.createBannerAd(
            AdService.settingsBannerId,
            onAdLoaded: (_) {
              if (mounted) setState(() => _bannerAdLoaded = true);
            },
            onAdFailedToLoad: (_, _) {
              if (mounted) {
                setState(() {
                  _bannerAd = null;
                  _bannerAdLoaded = false;
                });
              }
            },
          );
    _bannerAd?.load();
    _loadAppVersion();
    // The profile card shows level and exp, which only arrive with a fetch.
    // Deferred: requestProfile notifies listeners synchronously.
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
    // Never on the web. What is being served IS the current build — a reload
    // is all it takes — so "not the latest version" with a store button below
    // it was telling people to fix something that isn't broken. latestVersion
    // tracks the store release, which the web build has no reason to match.
    if (kIsWeb) return false;
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

  /// 팝업 제목: 색 입힌 아이콘 칩 + 제목.
  Widget _dialogTitle(IconData icon, Color tone, String text) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Cartoon.tint(tone, 0.75),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: Cartoon.ink, width: 1.6),
          ),
          child: Icon(icon, size: 22, color: tone),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: Cartoon.text(size: 20),
          ),
        ),
      ],
    );
  }

  void _showLanguageDialog(
    BuildContext ctx,
    LocaleService localeService,
    L10n l10n,
  ) {
    showDialog(
      context: ctx,
      builder: (dialogCtx) => SimpleDialog(
        title: _dialogTitle(
          Icons.language_rounded,
          Cartoon.onSurface(const Color(0xFF42A5F5)),
          l10n.settingsLanguage,
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      onPressed: () {
        localeService.setLocale(locale);
        final effectiveCode =
            (locale ?? localeService.effectiveLocale).languageCode;
        context.read<GameService>().sendLocale(effectiveCode);
        Navigator.pop(dialogCtx);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Cartoon.blue : Cartoon.surface(Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Cartoon.ink, width: 1.6),
          boxShadow: [
            BoxShadow(
              color: Cartoon.ink,
              offset: Offset(0, isSelected ? 3 : 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Cartoon.userText(
                  size: 16,
                  weight: FontWeight.w800,
                  color: isSelected ? Colors.white : Cartoon.ink,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_rounded, color: Colors.white, size: 22),
          ],
        ),
      ),
    );
  }

  Future<void> _openStore() async {
    final uri = Uri.parse(
      (!kIsWeb && Platform.isIOS)
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
    final nickname = context.read<GameService>().playerName;
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setState) {
          // 현재 닉네임을 똑같이 쳐야만 탈퇴 버튼이 켜진다 — 실수 탈퇴 방지.
          final matches =
              nickname.isNotEmpty && controller.text.trim() == nickname;
          return AlertDialog(
            title: _dialogTitle(
              Icons.warning_amber_rounded,
              Cartoon.onSurface(const Color(0xFFC62828)),
              l10n.settingsDeleteAccount,
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.settingsDeleteAccountConfirm),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Cartoon.surface(
                        Cartoon.surface(const Color(0xFFFFE3E3)),
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Cartoon.ink, width: 1.6),
                    ),
                    child: Text(
                      l10n.settingsDeleteTypeNickname(nickname),
                      style: Cartoon.userText(
                        size: 13.5,
                        weight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: controller,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: Cartoon.userText(size: 16),
                    onChanged: (_) => setState(() {}),
                    decoration: formFieldDecoration(
                      l10n.settingsDeleteNicknameHint,
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
              CartoonButton(
                expand: false,
                height: 46,
                color: Cartoon.onSurface(const Color(0xFFE5484D)),
                onPressed: matches
                    ? () {
                        Navigator.pop(dialogCtx);
                        _deleteAccount();
                      }
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: CartoonButton.label(
                    l10n.settingsDeleteAccountWithdraw,
                    size: 17,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ).whenComplete(controller.dispose);
  }

  /// 탈퇴. 서버가 지웠다고 답할 때만 로그아웃한다.
  ///
  /// 전에는 결과와 무관하게 로그아웃해서, 지워지지 않았는데도 사용자는
  /// 탈퇴된 줄 알고 떠났다 — 개인정보 삭제 요청이 조용히 실패하는 건
  /// 그냥 버그가 아니라 약속을 못 지킨 것이다.
  Future<void> _deleteAccount() async {
    final game = context.read<GameService>();
    final l10n = L10n.of(context);
    final r = await game.deleteAccount();
    if (!mounted) return;
    if (r.ok) {
      _logout();
      return;
    }
    // 실패했으면 로그인 상태를 유지한다. 다시 시도하거나 문의할 수 있어야 한다.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          r.message == null || r.message!.isEmpty
              ? l10n.settingsDeleteAccountFailed
              : localizeServiceMessage(r.message!, l10n),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _openMailbox() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MailboxScreen()),
    );
  }

  void _openNoticesPage() {
    final game = context.read<GameService>();
    // Capture unread IDs before marking as read, so we can show "NEW" badges.
    // 판정은 GameService.isNoticeNew 하나로 모은다 — 목록의 NEW 와 로비
    // 배지 숫자가 다른 규칙을 쓰면 "1개라는데 열어보면 없다" 가 된다.
    final unreadIds = <int>{};
    for (final n in game.notices) {
      final id = n['id'];
      if (id is int && game.isNoticeNew(n)) unreadIds.add(id);
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
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          title: _dialogTitle(
            Icons.help_rounded,
            Cartoon.onSurface(const Color(0xFFBA68C8)),
            l10n.inquiryTitle,
          ),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  formFieldLabel(l10n.inquiryCategory),
                  // One pill style for the four categories. Material's
                  // ChoiceChip drew its own outline and a check mark, so the
                  // selected one grew wider than the rest and the row reflowed
                  // as you tapped.
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in <MapEntry<String, String>>[
                        MapEntry('bug', l10n.inquiryCategoryBug),
                        MapEntry('suggestion', l10n.inquiryCategorySuggestion),
                        MapEntry('payment', l10n.inquiryCategoryPayment),
                        MapEntry('other', l10n.inquiryCategoryOther),
                      ])
                        ChoicePill(
                          label: entry.value,
                          selected: selectedCategory == entry.key,
                          onTap: () =>
                              setState(() => selectedCategory = entry.key),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  formFieldLabel(l10n.inquiryFieldTitle),
                  TextField(
                    controller: _inquiryTitleController,
                    maxLength: 60,
                    style: const TextStyle(fontSize: 14),
                    decoration: formFieldDecoration(l10n.inquiryFieldTitleHint),
                  ),
                  const SizedBox(height: 16),
                  formFieldLabel(l10n.inquiryFieldContent),
                  TextField(
                    controller: _inquiryContentController,
                    maxLines: 6,
                    maxLength: 1000,
                    style: const TextStyle(fontSize: 14),
                    decoration: formFieldDecoration(
                      l10n.inquiryFieldContentHint,
                    ),
                  ),
                ],
              ),
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
                  context,
                ).showSnackBar(SnackBar(content: Text(l10n.inquirySubmitted)));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFBA68C8),
                foregroundColor: Colors.white,
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
        title: _dialogTitle(
          Icons.mark_email_read_rounded,
          Cartoon.onSurface(const Color(0xFF1E88E5)),
          l10n.inquiryHistoryTitle,
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
                          style: TextStyle(
                            color: Cartoon.onSurface(const Color(0xFFCC6666)),
                          ),
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
                      style: TextStyle(
                        color: Cartoon.onSurface(const Color(0xFF9A8E8A)),
                      ),
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
                          color: Cartoon.paper,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Cartoon.ink, width: 1.6),
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
                                    ? Cartoon.surface(const Color(0xFFD8F5DF))
                                    : Cartoon.surface(const Color(0xFFFFE9B8)),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Cartoon.ink,
                                  width: 1.4,
                                ),
                              ),
                              child: Text(
                                isResolved
                                    ? l10n.inquiryStatusResolved
                                    : l10n.inquiryStatusPending,
                                style: Cartoon.text(
                                  size: 12.5,
                                  color: isResolved
                                      ? Cartoon.onSurface(
                                          const Color(0xFF2E8B57),
                                        )
                                      : Cartoon.onSurface(
                                          const Color(0xFFE5791A),
                                        ),
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
                                    style: Cartoon.userText(
                                      size: 14,
                                      weight: FontWeight.w800,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$category · $createdAt',
                                    style: Cartoon.userText(
                                      size: 11.5,
                                      weight: FontWeight.w500,
                                      color: Cartoon.ink.withValues(alpha: 0.6),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: Cartoon.ink,
                              size: 26,
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
        title: Text(
          title,
          style: Cartoon.userText(size: 19, weight: FontWeight.w900),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$category · $createdAt',
                style: Cartoon.userText(
                  size: 12,
                  weight: FontWeight.w500,
                  color: Cartoon.ink.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                content,
                style: Cartoon.userText(size: 13, weight: FontWeight.w500),
              ),
              const SizedBox(height: 16),
              if (status == 'resolved' && adminNote.isNotEmpty) ...[
                Text(
                  l10n.inquiryAnswerLabel,
                  style: Cartoon.text(
                    size: 12,
                    color: Cartoon.onSurface(const Color(0xFF4CAF50)),
                  ),
                ),
                const SizedBox(height: 6),
                NoticeBody(content: adminNote),
                const SizedBox(height: 8),
                Text(
                  l10n.inquiryAnswerDate(resolvedAt),
                  style: Cartoon.userText(
                    size: 11,
                    weight: FontWeight.w500,
                    color: Cartoon.ink.withValues(alpha: 0.6),
                  ),
                ),
              ] else if (status != 'resolved') ...[
                Text(
                  l10n.inquiryNoAnswer,
                  style: Cartoon.userText(
                    size: 12,
                    weight: FontWeight.w500,
                    color: Cartoon.ink.withValues(alpha: 0.5),
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
              return Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: CartoonPressable(
                  scale: 0.97,
                  onTap: () {
                    game.setCardViewPref(value);
                    setDialogState(() {});
                    Navigator.pop(ctx);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? Cartoon.tint(color, 0.8)
                          : Cartoon.surface(Colors.white),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Cartoon.ink, width: 1.6),
                      boxShadow: [
                        BoxShadow(
                          color: Cartoon.ink,
                          offset: Offset(0, selected ? 3 : 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(icon, size: 24, color: color),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(label, style: Cartoon.text(size: 16)),
                        ),
                        if (selected)
                          Icon(
                            Icons.check_circle_rounded,
                            color: color,
                            size: 24,
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return Dialog(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _dialogTitle(
                      Icons.visibility_rounded,
                      Cartoon.onSurface(const Color(0xFF6A6090)),
                      l10n.settingsCardViewPolicy,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.settingsCardViewPolicyDescription,
                      style: Cartoon.userText(
                        size: 12.5,
                        weight: FontWeight.w500,
                        color: Cartoon.ink.withValues(alpha: 0.6),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    option(
                      value: 'ask',
                      label: l10n.gameCardViewPolicyAsk,
                      icon: Icons.help_outline,
                      color: Cartoon.onSurface(const Color(0xFF6A6090)),
                    ),
                    option(
                      value: 'always_allow',
                      label: l10n.gameCardViewPolicyAllow,
                      icon: Icons.check_circle,
                      color: Cartoon.onSurface(const Color(0xFF4CAF50)),
                    ),
                    option(
                      value: 'always_deny',
                      label: l10n.gameCardViewPolicyDeny,
                      icon: Icons.block,
                      color: Cartoon.onSurface(const Color(0xFFE53935)),
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
    if (content == null || content.isEmpty) {
      // Fetch from server if not loaded yet. Pass the current UI locale so
      // the server returns the matching-language EULA/privacy.
      final locale = context.read<LocaleService>().effectiveLocale.languageCode;
      game.requestAppConfig(locale: locale);
    }
    showLegalTextDialog(
      context,
      title: title,
      isTermsOfService: isTermsOfService,
    );
  }

  /// 선택한 소셜 계정으로 로그인 토큰을 받아 연동 요청을 보낸다.
  Future<void> _linkWith(String provider) async {
    final l10n = L10n.of(context);
    try {
      late final dynamic result;
      switch (provider) {
        case 'google':
          await AuthService.signOutGoogle();
          result = await AuthService.signInWithGoogle();
        case 'apple':
          result = await AuthService.signInWithApple();
        default:
          result = await AuthService.signInWithKakao();
      }
      if (result.cancelled || !mounted) return;
      context.read<GameService>().linkSocial(result.provider, result.token);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.settingsLinkFailed(e.toString()))),
        );
      }
    }
  }

  /// 연동 팝업: 쓸 수 있는 소셜 계정을 큰 버튼으로 세로로 나열한다. 예전엔
  /// 글자만 있는 작은 버튼이 하단에 한 줄로 붙어 있어서 로고도 없고 어느 게 어느
  /// 계정인지 한 번 읽어야 했다.
  void _showLinkDialog() {
    final l10n = L10n.of(context);
    Widget provider({
      required String name,
      required String key,
      required Color bg,
      required Color fg,
      required Widget logo,
      required BuildContext ctx,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: CartoonPressable(
          scale: 0.96,
          onTap: () {
            Navigator.pop(ctx);
            _linkWith(key);
          },
          child: Container(
            height: 58,
            margin: const EdgeInsets.only(bottom: 3),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Cartoon.ink, width: 2),
              boxShadow: [BoxShadow(color: Cartoon.ink, offset: Offset(0, 2))],
            ),
            child: Row(
              children: [
                SizedBox(width: 30, height: 30, child: Center(child: logo)),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    name,
                    style: Cartoon.userText(
                      size: 18,
                      weight: FontWeight.w900,
                      color: fg,
                    ),
                  ),
                ),
                Text(
                  l10n.commonLink,
                  style: Cartoon.text(
                    size: 15,
                    color: fg.withValues(alpha: 0.8),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: fg, size: 24),
              ],
            ),
          ),
        ),
      );
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: _dialogTitle(
          Icons.link_rounded,
          Cartoon.onSurface(const Color(0xFF7E57C2)),
          l10n.linkDialogTitle,
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.linkDialogContent),
              const SizedBox(height: 16),
              if (SocialConfig.googleEnabled)
                provider(
                  ctx: ctx,
                  name: 'Google',
                  key: 'google',
                  bg: Colors.white,
                  fg: Cartoon.ink,
                  logo: Image.asset('assets/icons/google_logo.webp'),
                ),
              if (SocialConfig.appleEnabled)
                provider(
                  ctx: ctx,
                  name: 'Apple',
                  key: 'apple',
                  bg: Colors.black,
                  fg: Colors.white,
                  logo: const Icon(Icons.apple, color: Colors.white, size: 28),
                ),
              if (SocialConfig.kakaoEnabled)
                provider(
                  ctx: ctx,
                  name: 'Kakao',
                  key: 'kakao',
                  bg: const Color(0xFFFEE500),
                  fg: Cartoon.onSurface(const Color(0xFF3C1E1E)),
                  logo: const KakaoLogo(size: 26),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.commonCancel),
          ),
        ],
      ),
    );
  }

  /// Avatar, nickname and level as a row inside the 계정 section, tappable into
  /// the profile popup.
  ///
  /// Lives in the section rather than as a card above it: it is account
  /// information, and a second card with its own margins above the first
  /// section read as a different page element.
  Widget _buildProfileRow(BuildContext context, GameService game) {
    final inner = game.playerName.isEmpty
        ? null
        : game.profileFor(game.playerName)?['profile'] as Map?;
    final level = (inner?['level'] as int?) ?? 1;
    final expTotal = (inner?['expTotal'] as int?) ?? 0;
    final photo = game.resolvePhotoUrl(game.myPhotoUrl);

    return InkWell(
      onTap: widget.onShowMyProfile == null
          ? null
          : () => widget.onShowMyProfile!(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Cartoon.ink, width: 2),
                boxShadow: [
                  BoxShadow(color: Cartoon.ink, offset: Offset(0, 2)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: ProfileAvatar(
                  photoUrl: photo,
                  size: 54,
                  borderRadius: 16,
                  fallback: Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Cartoon.cream,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.person,
                      size: 26,
                      color: Cartoon.onSurface(const Color(0xFF9C8B84)),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    game.playerName.isEmpty ? '-' : game.playerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Cartoon.userText(size: 18, weight: FontWeight.w900),
                  ),
                  const SizedBox(height: 5),
                  // The same level/exp strip the profile popup draws, so the two
                  // never disagree about how far along you are.
                  profileLevelStrip(level, expTotal),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: Cartoon.ink, size: 26),
          ],
        ),
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

    /// Drawn in place of [icon] when a row wants artwork rather than a glyph.
    /// [icon] stays required so every row still declares a sensible fallback.
    Widget? leading,
  }) {
    final tone = iconColor ?? Cartoon.ink;
    final chip = leading != null
        ? SizedBox(width: 42, height: 42, child: Center(child: leading))
        : Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Cartoon.tint(tone, 0.78),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: enabled
                    ? Cartoon.ink
                    : Cartoon.ink.withValues(alpha: 0.3),
                width: 2.2,
              ),
            ),
            child: Icon(icon, color: tone, size: 23),
          );
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          chip,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Cartoon.text(
                    size: 16.5,
                    color: enabled
                        ? Cartoon.ink
                        : Cartoon.ink.withValues(alpha: 0.35),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: Cartoon.userText(
                      size: 12.5,
                      weight: FontWeight.w500,
                      color: Cartoon.ink.withValues(alpha: enabled ? 0.6 : 0.3),
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null)
            trailing
          else if (onTap != null && enabled)
            Icon(Icons.chevron_right_rounded, color: Cartoon.ink, size: 26),
        ],
      ),
    );
    if (onTap == null || !enabled) return content;
    return InkWell(onTap: onTap, child: content);
  }

  int _sectionIndex = 0;

  Widget _buildSection(String title, List<Widget> children) {
    final index = _sectionIndex++;
    return CartoonEntrance(
      key: ValueKey('settings-$title'),
      delay: Duration(milliseconds: 50 * index.clamp(0, 8)),
      from: const Offset(0, 18),
      pop: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 9),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: Cartoon.cream,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Cartoon.ink, width: 1.6),
                ),
                child: Text(title, style: Cartoon.text(size: 14)),
              ),
            ),
            Container(
              margin: const EdgeInsets.only(bottom: 3),
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: Cartoon.panelDecoration(
                radius: 22,
                shadowOffset: 2.5,
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(children: children),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final themeColors = context.watch<GameService>().themeGradient;
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
            child: Consumer<GameService>(
              builder: (context, game, _) {
                _sectionIndex = 0;
                // 출석 알림이 실제로 나갈 수 있는 상태인가. 푸시 자체가 꺼져
                // 있거나 이벤트·혜택 알림에 동의하지 않았으면 이 스위치를
                // 켜 둬도 아무것도 안 온다 — 서버가 셋 다 보기 때문이다.
                // 그래서 스위치를 끄는 대신 비활성으로 둔다. 끄는 것은
                // 사용자가 한 적 없는 선택이고, 나중에 동의를 켰을 때 조용히
                // 되살아나는 것도 곤란하다.
                final attendancePushActive =
                    game.pushEnabled && game.marketingPushEnabled;
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
                        backgroundColor: success ? Cartoon.green : Cartoon.red,
                      ),
                    );
                  }
                });
                return Column(
                  children: [
                    CartoonEntrance(
                      from: const Offset(0, -30),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
                        child: Row(
                          children: [
                            CartoonPressable(
                              scale: 0.88,
                              onTap: () => Navigator.pop(context),
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: Cartoon.paper,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Cartoon.ink,
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Cartoon.ink,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.arrow_back_rounded,
                                  color: Cartoon.ink,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Cartoon.outlinedText(
                                l10n.settingsHeaderTitle,
                                size: 28,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.only(
                          bottom: 24 + MediaQuery.viewPaddingOf(context).bottom,
                        ),
                        child: Column(
                          children: [
                            _buildSection(l10n.settingsAccountSection, [
                              // Avatar, nickname and level as the first row of the
                              // account section — it says who this account is,
                              // which is what a "닉네임" row was doing with less.
                              _buildProfileRow(context, game),
                              Divider(
                                height: 1,
                                color: Cartoon.surface(const Color(0xFFEAE2DE)),
                              ),
                              _buildRow(
                                icon: Icons.link,
                                iconColor: Cartoon.onSurface(
                                  const Color(0xFF7E57C2),
                                ),
                                title: l10n.settingsSocialLink,
                                subtitle: game.authProvider != 'local'
                                    ? l10n.settingsSocialLinked(
                                        game.authProvider.toUpperCase(),
                                      )
                                    : (game.linkedSocialProvider != null &&
                                          game.linkedSocialProvider != 'local')
                                    ? l10n.settingsSocialLinked(
                                        game.linkedSocialProvider!
                                            .toUpperCase(),
                                      )
                                    : l10n.settingsNoLinkedAccount,
                                trailing:
                                    game.authProvider == 'local' &&
                                        (game.linkedSocialProvider == null ||
                                            game.linkedSocialProvider ==
                                                'local')
                                    ? TextButton(
                                        onPressed: () => _showLinkDialog(),
                                        child: Text(
                                          l10n.commonLink,
                                          style: Cartoon.userText(
                                            size: 12,
                                            weight: FontWeight.w500,
                                            color: Cartoon.onSurface(
                                              Cartoon.onSurface(
                                                const Color(0xFF7E57C2),
                                              ),
                                            ),
                                          ),
                                        ),
                                      )
                                    : null,
                              ),
                            ]),
                            const SizedBox(height: 12),
                            _buildSection(L10n.of(context).settingsNotices, [
                              _buildRow(
                                icon: Icons.campaign,
                                iconColor: Cartoon.onSurface(
                                  const Color(0xFF42A5F5),
                                ),
                                title: L10n.of(context).settingsNotices,
                                onTap: _openNoticesPage,
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
                                        decoration: BoxDecoration(
                                          color: Cartoon.onSurface(
                                            const Color(0xFFE53935),
                                          ),
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
                                          style: Cartoon.text(
                                            size: 10,
                                            color: Colors.white,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      color: Cartoon.ink,
                                      size: 26,
                                    ),
                                  ],
                                ),
                              ),
                              Divider(
                                height: 1,
                                color: Cartoon.surface(const Color(0xFFEAE2DE)),
                              ),
                              // 운영자 우편함. Sits with notices rather than with
                              // support: both are things the team sent that are
                              // waiting to be read, and a player looking for
                              // "did they get back to me" checks the same place.
                              _buildRow(
                                icon: Icons.mark_email_unread,
                                iconColor: Cartoon.onSurface(
                                  const Color(0xFFEF6C00),
                                ),
                                title: L10n.of(context).mailboxTitle,
                                onTap: _openMailbox,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (game.unreadMailCount > 0)
                                      Container(
                                        margin: const EdgeInsets.only(right: 8),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Cartoon.onSurface(
                                            const Color(0xFFE53935),
                                          ),
                                          borderRadius: BorderRadius.all(
                                            Radius.circular(999),
                                          ),
                                        ),
                                        constraints: const BoxConstraints(
                                          minWidth: 18,
                                          minHeight: 18,
                                        ),
                                        child: Text(
                                          game.unreadMailCount > 9
                                              ? '9+'
                                              : '${game.unreadMailCount}',
                                          style: Cartoon.text(
                                            size: 10,
                                            color: Colors.white,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      color: Cartoon.ink,
                                      size: 26,
                                    ),
                                  ],
                                ),
                              ),
                            ]),
                            // 웹에는 푸시가 없다. FCM 등록을 아예 건너뛰므로 토큰이 없고,
                            // 여기서 무엇을 켜든 브라우저로는 아무것도 오지 않는다. 켤 수는
                            // 있는데 오지 않는 스위치는 고장으로 읽힌다 — 그래서 통째로
                            // 감춘다. 설정 자체는 계정에 남아 있어서, 앱을 깔면 그 기기에서
                            // 예전에 정해 둔 대로 동작한다.
                            if (!kIsWeb) ...[
                              const SizedBox(height: 12),
                              _buildSection(l10n.settingsNotificationsSection, [
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
                                Divider(
                                  height: 1,
                                  color: Cartoon.surface(
                                    const Color(0xFFEAE2DE),
                                  ),
                                ),
                                // Separate from the switch above on purpose. That
                                // one is "notify me at all"; this one is consent to
                                // advertising, which is a legal record and has to
                                // be withdrawable on its own.
                                //
                                // With notifications off it goes inactive rather
                                // than off. The server already requires both
                                // (getMarketingAudience), so an enabled-looking
                                // switch here promised something that could not
                                // happen. Turning it off instead would be worse:
                                // that is a withdrawal of consent, and it would
                                // silently come back when notifications were
                                // re-enabled — consent nobody gave a second time.
                                _buildRow(
                                  icon: Icons.campaign_outlined,
                                  iconColor: game.pushEnabled
                                      ? Cartoon.onSurface(
                                          const Color(0xFFE08A1E),
                                        )
                                      : const Color(0xFFC9BFB9),
                                  title: l10n.settingsMarketingPush,
                                  subtitle: game.pushEnabled
                                      ? l10n.settingsMarketingPushHint
                                      : l10n.settingsMarketingPushBlocked,
                                  enabled: game.pushEnabled,
                                  trailing: Switch(
                                    value:
                                        game.marketingPushEnabled &&
                                        game.pushEnabled,
                                    onChanged: game.pushEnabled
                                        ? (v) => game.setMarketingConsent(v)
                                        : null,
                                  ),
                                ),
                                Divider(
                                  height: 1,
                                  color: Cartoon.surface(
                                    const Color(0xFFEAE2DE),
                                  ),
                                ),
                                // 이벤트·혜택 알림에 딸린 하위 스위치. 출석
                                // 알림도 무료 재화를 받으라는 권유라 광고성으로
                                // 보는 게 안전하고, 그래서 같은 동의 아래 둔다.
                                //
                                // 그러면서도 따로 끌 수 있어야 한다 — 매일 오는
                                // 게 성가시다는 이유로 마케팅 동의 자체를
                                // 철회하면 되돌리는 데 다시 동의를 받아야 한다.
                                _buildRow(
                                  icon: Icons.event_available_outlined,
                                  iconColor: attendancePushActive
                                      ? Cartoon.onSurface(
                                          const Color(0xFF66A15E),
                                        )
                                      : const Color(0xFFC9BFB9),
                                  title: l10n.settingsAttendancePush,
                                  subtitle: attendancePushActive
                                      ? l10n.settingsAttendancePushHint
                                      : l10n.settingsAttendancePushBlocked,
                                  enabled: attendancePushActive,
                                  trailing: Switch(
                                    value:
                                        game.pushAttendanceEnabled &&
                                        attendancePushActive,
                                    onChanged: attendancePushActive
                                        ? (v) =>
                                              game.setPushAttendanceEnabled(v)
                                        : null,
                                  ),
                                ),
                                if (game.isAdminUser) ...[
                                  Divider(
                                    height: 1,
                                    color: Cartoon.surface(
                                      const Color(0xFFEAE2DE),
                                    ),
                                  ),
                                  _buildRow(
                                    icon: Icons.support_agent,
                                    iconColor: Cartoon.onSurface(
                                      const Color(0xFFAB47BC),
                                    ),
                                    title: l10n.settingsInquiryNotifications,
                                    subtitle:
                                        l10n.settingsInquiryNotificationsDesc,
                                    trailing: Switch(
                                      value: game.pushAdminInquiryEnabled,
                                      onChanged: (v) =>
                                          game.setAdminAlertPush(inquiry: v),
                                    ),
                                  ),
                                  Divider(
                                    height: 1,
                                    color: Cartoon.surface(
                                      const Color(0xFFEAE2DE),
                                    ),
                                  ),
                                  _buildRow(
                                    icon: Icons.report_gmailerrorred,
                                    iconColor: Cartoon.onSurface(
                                      const Color(0xFFEF5350),
                                    ),
                                    title: l10n.settingsReportNotifications,
                                    subtitle:
                                        l10n.settingsReportNotificationsDesc,
                                    trailing: Switch(
                                      value: game.pushAdminReportEnabled,
                                      onChanged: (v) =>
                                          game.setAdminAlertPush(report: v),
                                    ),
                                  ),
                                  Divider(
                                    height: 1,
                                    color: Cartoon.surface(
                                      const Color(0xFFEAE2DE),
                                    ),
                                  ),
                                  _buildRow(
                                    icon: Icons.payments_outlined,
                                    iconColor: Cartoon.onSurface(
                                      const Color(0xFF26A69A),
                                    ),
                                    title: l10n.settingsPaymentNotifications,
                                    subtitle:
                                        l10n.settingsPaymentNotificationsDesc,
                                    trailing: Switch(
                                      value: game.pushAdminPaymentEnabled,
                                      onChanged: (v) =>
                                          game.setAdminAlertPush(payment: v),
                                    ),
                                  ),
                                ],
                              ]),
                            ],
                            const SizedBox(height: 12),
                            _buildSection(l10n.settingsCardViewPolicy, [
                              _buildRow(
                                icon: Icons.visibility_outlined,
                                iconColor: Cartoon.onSurface(
                                  const Color(0xFF6A6090),
                                ),
                                title: l10n.settingsCardViewPolicy,
                                subtitle: _cardViewPrefLabel(
                                  l10n,
                                  game.cardViewPref,
                                ),
                                trailing: Icon(
                                  Icons.chevron_right_rounded,
                                  color: Cartoon.ink,
                                  size: 26,
                                ),
                                onTap: () => _showCardViewPrefDialog(
                                  context,
                                  game,
                                  l10n,
                                ),
                              ),
                            ]),
                            const SizedBox(height: 12),
                            Builder(
                              builder: (context) {
                                final l10n = L10n.of(context);
                                final localeService = context
                                    .watch<LocaleService>();
                                final currentLabel =
                                    localeService.userSelectedLocale == null
                                    ? l10n.languageAuto
                                    : _localeDisplayName(
                                        l10n,
                                        localeService.userSelectedLocale!,
                                      );
                                return _buildSection(l10n.settingsLanguage, [
                                  _buildRow(
                                    icon: Icons.language,
                                    iconColor: Cartoon.onSurface(
                                      const Color(0xFF42A5F5),
                                    ),
                                    title: l10n.settingsLanguage,
                                    subtitle: currentLabel,
                                    onTap: () => _showLanguageDialog(
                                      context,
                                      localeService,
                                      l10n,
                                    ),
                                    trailing: Icon(
                                      Icons.chevron_right_rounded,
                                      color: Cartoon.ink,
                                      size: 26,
                                    ),
                                  ),
                                ]);
                              },
                            ),
                            const SizedBox(height: 12),
                            // Moved here from the lobby header. The rulebook is
                            // read once when a game is new to you and then never
                            // again, so it does not earn a permanent slot next
                            // to the lobby's everyday actions — the profile
                            // button took that spot.
                            _buildSection(L10n.of(context).rulesTitle, [
                              _buildRow(
                                icon: Icons.menu_book_rounded,
                                iconColor: const Color(0xFFFF8A65),
                                title: L10n.of(context).rulesTitle,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const RulesScreen(),
                                  ),
                                ),
                                trailing: Icon(
                                  Icons.chevron_right_rounded,
                                  color: Cartoon.ink,
                                  size: 26,
                                ),
                              ),
                            ]),
                            const SizedBox(height: 12),
                            _buildSection(l10n.settingsInquirySection, [
                              // Coupons sit with the support rows because that is
                              // where someone goes when they have a code and no
                              // idea what to do with it. Absent on the iOS app —
                              // see couponRedeemAllowed.
                              if (couponRedeemAllowed) ...[
                                _buildRow(
                                  icon: Icons.confirmation_number_outlined,
                                  iconColor: Cartoon.onSurface(
                                    const Color(0xFFB07B2E),
                                  ),
                                  leading: couponIcon(size: 22),
                                  title: l10n.couponRedeemTitle,
                                  onTap: () => showCouponRedeemDialog(context),
                                  trailing: Icon(
                                    Icons.chevron_right_rounded,
                                    color: Cartoon.ink,
                                    size: 26,
                                  ),
                                ),
                                Divider(
                                  height: 1,
                                  color: Cartoon.surface(
                                    const Color(0xFFEAE2DE),
                                  ),
                                ),
                              ],
                              _buildRow(
                                icon: Icons.help_outline,
                                iconColor: Cartoon.onSurface(
                                  const Color(0xFFBA68C8),
                                ),
                                title: l10n.settingsSubmitInquiry,
                                onTap: _showInquiryDialog,
                                trailing: Icon(
                                  Icons.chevron_right_rounded,
                                  color: Cartoon.ink,
                                  size: 26,
                                ),
                              ),
                              Divider(
                                height: 1,
                                color: Cartoon.surface(const Color(0xFFEAE2DE)),
                              ),
                              _buildRow(
                                icon: Icons.mark_email_read,
                                iconColor: Cartoon.onSurface(
                                  const Color(0xFF1E88E5),
                                ),
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
                                          margin: const EdgeInsets.only(
                                            right: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Cartoon.onSurface(
                                              const Color(0xFFE53935),
                                            ),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        color: Cartoon.ink,
                                        size: 26,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ]),
                            const SizedBox(height: 12),
                            Builder(
                              builder: (context) {
                                final l10n = L10n.of(context);
                                return _buildSection(l10n.settingsAppInfo, [
                                  Builder(
                                    builder: (context) {
                                      final outdated = _isOutdated(
                                        game.latestVersion,
                                      );
                                      return _buildRow(
                                        icon: Icons.info_outline,
                                        iconColor: outdated
                                            ? Cartoon.onSurface(
                                                const Color(0xFFE53935),
                                              )
                                            : Cartoon.onSurface(
                                                const Color(0xFF7E57C2),
                                              ),
                                        // "앱 버전" is wrong in a browser — there
                                        // is no app to have a version, just the
                                        // build being served.
                                        title: kIsWeb
                                            ? l10n.settingsCurrentVersion
                                            : l10n.settingsAppVersion,
                                        subtitle: _appVersion.isEmpty
                                            ? '-'
                                            : (outdated
                                                  ? '$_appVersion · ${l10n.settingsNotLatestVersion}'
                                                  : _appVersion),
                                        trailing: outdated
                                            ? ElevatedButton(
                                                onPressed: _openStore,
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(
                                                    0xFFE53935,
                                                  ),
                                                  foregroundColor: Colors.white,
                                                  elevation: 0,
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 14,
                                                        vertical: 6,
                                                      ),
                                                  minimumSize: const Size(
                                                    0,
                                                    32,
                                                  ),
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                  ),
                                                ),
                                                child: Text(
                                                  l10n.settingsUpdate,
                                                  style: Cartoon.text(size: 12),
                                                ),
                                              )
                                            : null,
                                      );
                                    },
                                  ),
                                  Divider(
                                    height: 1,
                                    color: Cartoon.surface(
                                      const Color(0xFFEAE2DE),
                                    ),
                                  ),
                                  _buildRow(
                                    icon: Icons.description_outlined,
                                    iconColor: Cartoon.onSurface(
                                      const Color(0xFF8A7A72),
                                    ),
                                    title: l10n.settingsTermsOfService,
                                    onTap: () => _showTextViewDialog(
                                      l10n.settingsTermsOfService,
                                      game.eulaContent,
                                      isTermsOfService: true,
                                    ),
                                    trailing: Icon(
                                      Icons.chevron_right_rounded,
                                      color: Cartoon.ink,
                                      size: 26,
                                    ),
                                  ),
                                  Divider(
                                    height: 1,
                                    color: Cartoon.surface(
                                      const Color(0xFFEAE2DE),
                                    ),
                                  ),
                                  _buildRow(
                                    icon: Icons.privacy_tip_outlined,
                                    iconColor: Cartoon.onSurface(
                                      const Color(0xFF8A7A72),
                                    ),
                                    title: l10n.settingsPrivacyPolicy,
                                    onTap: () => _showTextViewDialog(
                                      l10n.settingsPrivacyPolicy,
                                      game.privacyPolicy,
                                    ),
                                    trailing: Icon(
                                      Icons.chevron_right_rounded,
                                      color: Cartoon.ink,
                                      size: 26,
                                    ),
                                  ),
                                ]);
                              },
                            ),
                            if (game.isAdminUser) ...[
                              const SizedBox(height: 12),
                              _buildSection(l10n.settingsAdminSection, [
                                _buildRow(
                                  icon: Icons.admin_panel_settings_outlined,
                                  iconColor: Cartoon.onSurface(
                                    const Color(0xFF7E57C2),
                                  ),
                                  title: l10n.settingsAdminCenter,
                                  subtitle: l10n.settingsAdminCenterDesc,
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const AdminCenterScreen(),
                                      ),
                                    );
                                  },
                                ),
                              ]),
                            ],
                            const SizedBox(height: 12),
                            _buildSection(l10n.settingsAccountManagement, [
                              _buildRow(
                                icon: Icons.logout,
                                iconColor: Cartoon.onSurface(
                                  const Color(0xFF8A7A72),
                                ),
                                title: l10n.settingsLogout,
                                onTap: _logout,
                                trailing: Icon(
                                  Icons.chevron_right_rounded,
                                  color: Cartoon.ink,
                                  size: 26,
                                ),
                              ),
                              Divider(
                                height: 1,
                                color: Cartoon.surface(const Color(0xFFEAE2DE)),
                              ),
                              _buildRow(
                                icon: Icons.delete_forever,
                                iconColor: Cartoon.onSurface(
                                  const Color(0xFFC62828),
                                ),
                                title: l10n.settingsDeleteAccount,
                                onTap: _showDeleteAccountDialog,
                                trailing: Icon(
                                  Icons.chevron_right_rounded,
                                  color: Cartoon.ink,
                                  size: 26,
                                ),
                              ),
                            ]),
                            const SizedBox(height: 12),
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
      ),
    );
  }
}
