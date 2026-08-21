import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n_helpers.dart';
import '../services/game_service.dart';
import '../widgets/coupon_redeem.dart';
import '../widgets/notice_body.dart';

class NoticesScreen extends StatefulWidget {
  final Set<int> unreadIds;

  const NoticesScreen({super.key, required this.unreadIds});

  @override
  State<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends State<NoticesScreen> {
  // IDs the user has opened during this screen visit. We dim their NEW
  // badge immediately after backing out of the detail view, even though
  // the global read-set was already updated in initState — widget.unreadIds
  // is the snapshot we display NEW from, so we mask off opened ones here.
  final Set<int> _openedThisVisit = <int>{};

  @override
  void initState() {
    super.initState();
    final game = context.read<GameService>();
    // Both of these call notifyListeners(), and initState runs inside the
    // build phase — a Provider rebuild from here trips "setState() called
    // during build". The read-marking was already deferred; requestNotices
    // was left behind and threw the same assertion the moment this screen
    // opened. They go together.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      game.markCurrentNoticesAsRead();
      game.requestNotices(markReadOnReceive: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeColors = context.watch<GameService>().themeGradient;
    final l10n = L10n.of(context);

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
          child: Column(
            children: [
              // Header
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                    const Icon(Icons.campaign, color: Color(0xFF42A5F5)),
                    const SizedBox(width: 8),
                    Text(
                      l10n.noticeTitle,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF5A4038),
                      ),
                    ),
                  ],
                ),
              ),
              // Content
              Expanded(
                child: Consumer<GameService>(
                  builder: (context, game, _) {
                    Widget content;
                    if (game.noticesLoading) {
                      content = _fillScrollable(
                        const CircularProgressIndicator(),
                      );
                    } else if (game.noticesError != null) {
                      content = _fillScrollable(
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              localizeServiceMessage(
                                game.noticesError!,
                                L10n.of(context),
                              ),
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
                      );
                    } else if (game.notices.isEmpty) {
                      content = _fillScrollable(
                        Text(
                          l10n.noticeEmpty,
                          style: const TextStyle(color: Color(0xFF9A8E8A)),
                        ),
                      );
                    } else {
                      content = ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: game.notices.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = game.notices[index];
                          return _buildNoticeItem(item, l10n);
                        },
                      );
                    }
                    return RefreshIndicator(
                      onRefresh: () async {
                        game.requestNotices();
                        await Future.delayed(const Duration(milliseconds: 500));
                      },
                      child: content,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Scrollable wrapper so RefreshIndicator can pull on non-list states too.
  Widget _fillScrollable(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(padding: const EdgeInsets.all(24), child: child),
          ),
        ),
      ),
    );
  }

  Widget _buildNoticeItem(Map<String, dynamic> item, L10n l10n) {
    final title = item['title']?.toString() ?? '';
    final category = item['category']?.toString() ?? 'general';
    final isPinned = item['is_pinned'] == true;
    final hasCoupon = (item['coupon_code']?.toString() ?? '').isNotEmpty;
    final publishedAt = _formatShortDate(item['published_at']);
    final noticeId = item['id'];
    final isNew =
        noticeId is int &&
        widget.unreadIds.contains(noticeId) &&
        !_openedThisVisit.contains(noticeId);

    return InkWell(
      onTap: () {
        if (noticeId is int) {
          context.read<GameService>().markNoticeRead(noticeId);
          setState(() => _openedThisVisit.add(noticeId));
        }
        _showNoticeDetail(item, l10n);
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isNew
              ? Colors.white.withValues(alpha: 0.98)
              : Colors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isNew ? const Color(0xFFFFCC80) : const Color(0xFFE0D8D4),
          ),
        ),
        child: Row(
          children: [
            if (isNew)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'NEW',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            if (isPinned)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.push_pin, size: 16, color: Color(0xFFFF8F00)),
              ),
            // Shown on every platform: knowing which post carries a coupon is
            // worth as much on iOS, where the code itself is withheld and the
            // reader has to ask.
            if (hasCoupon)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: couponIcon(size: 18),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _categoryBgColor(category),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _categoryLabel(l10n, category),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _categoryTextColor(category),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isNew ? FontWeight.w700 : FontWeight.w500,
                      color: const Color(0xFF5A4038),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    publishedAt,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9A8E8A),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFB0A8A4)),
          ],
        ),
      ),
    );
  }

  void _showNoticeDetail(Map<String, dynamic> item, L10n l10n) {
    final title = item['title']?.toString() ?? '';
    final content = item['content']?.toString() ?? '';
    final category = item['category']?.toString() ?? 'general';
    final publishedAt = _formatShortDate(item['published_at']);
    // Shown everywhere now: the ticket prints the code on every platform and
    // only its redeem stub is gated.
    final couponCode = item['coupon_code']?.toString() ?? '';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _NoticeDetailPage(
          title: title,
          content: content,
          category: category,
          publishedAt: publishedAt,
          couponCode: couponCode,
        ),
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

  String _categoryLabel(L10n l10n, String value) {
    switch (value) {
      case 'release':
        return l10n.noticeCategoryRelease;
      case 'update':
        return l10n.noticeCategoryUpdate;
      case 'preview':
        return l10n.noticeCategoryPreview;
      default:
        return l10n.noticeCategoryGeneral;
    }
  }

  Color _categoryBgColor(String value) {
    switch (value) {
      case 'release':
        return const Color(0xFFE3F2FD);
      case 'update':
        return const Color(0xFFE8F5E9);
      case 'preview':
        return const Color(0xFFFFF3E0);
      default:
        return const Color(0xFFECEFF1);
    }
  }

  Color _categoryTextColor(String value) {
    switch (value) {
      case 'release':
        return const Color(0xFF1565C0);
      case 'update':
        return const Color(0xFF2E7D32);
      case 'preview':
        return const Color(0xFFE65100);
      default:
        return const Color(0xFF546E7A);
    }
  }
}

class _NoticeDetailPage extends StatelessWidget {
  final String title;
  final String content;
  final String category;
  final String publishedAt;

  /// The coupon this notice hands out, if any.
  final String couponCode;

  const _NoticeDetailPage({
    required this.title,
    required this.content,
    required this.category,
    required this.publishedAt,
    this.couponCode = '',
  });

  @override
  Widget build(BuildContext context) {
    final themeColors = context.watch<GameService>().themeGradient;
    final l10n = L10n.of(context);

    String categoryLabel;
    Color categoryBg;
    Color categoryText;
    switch (category) {
      case 'release':
        categoryLabel = l10n.noticeCategoryRelease;
        categoryBg = const Color(0xFFE3F2FD);
        categoryText = const Color(0xFF1565C0);
      case 'update':
        categoryLabel = l10n.noticeCategoryUpdate;
        categoryBg = const Color(0xFFE8F5E9);
        categoryText = const Color(0xFF2E7D32);
      case 'preview':
        categoryLabel = l10n.noticeCategoryPreview;
        categoryBg = const Color(0xFFFFF3E0);
        categoryText = const Color(0xFFE65100);
      default:
        categoryLabel = l10n.noticeCategoryGeneral;
        categoryBg = const Color(0xFFECEFF1);
        categoryText = const Color(0xFF546E7A);
    }

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
          child: Column(
            children: [
              // Header
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: categoryBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        categoryLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: categoryText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF5A4038),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              // Content
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        publishedAt,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF9A8E8A),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 14),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 마크다운 몇 가지를 알아본다 — 운영자가 이미
                              // **굵게** 를 쓰고 있었는데 별표째로 보였다.
                              NoticeBody(content: content),
                              // Below the text, not above it: the post says
                              // what the coupon is for, and the code is what
                              // you act on once you have read that.
                              if (couponCode.isNotEmpty) ...[
                                const SizedBox(height: 18),
                                NoticeCouponBlock(code: couponCode),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
