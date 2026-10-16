import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n_helpers.dart';
import '../services/game_service.dart';
import '../theme/cartoon.dart';
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
                // Header
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
                              border: Border.all(color: Cartoon.ink, width: 2),
                              boxShadow: const [
                                BoxShadow(
                                  color: Cartoon.ink,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.arrow_back_rounded,
                              color: Cartoon.ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Cartoon.outlinedText(
                            l10n.noticeTitle,
                            size: 28,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Content
                Expanded(
                  child: Consumer<GameService>(
                    builder: (context, game, _) {
                      Widget content;
                      if (game.noticesLoading) {
                        content = _fillScrollable(
                          const CircularProgressIndicator(
                            color: Cartoon.orange,
                            strokeWidth: 4,
                          ),
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
                                style: const TextStyle(
                                  color: Color(0xFFCC6666),
                                ),
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
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CartoonFloat(
                                amplitude: 8,
                                child: Image.asset(
                                  'assets/dragon_icon.webp',
                                  width: 90,
                                  height: 90,
                                  color: Colors.white.withValues(alpha: 0.35),
                                  colorBlendMode: BlendMode.modulate,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                l10n.noticeEmpty,
                                style: Cartoon.userText(
                                  size: 16,
                                  color: Cartoon.ink.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ),
                        );
                      } else {
                        content = ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(
                            16,
                            4,
                            16,
                            24 + MediaQuery.viewPaddingOf(context).bottom,
                          ),
                          itemCount: game.notices.length,
                          separatorBuilder: (_, _) => const SizedBox.shrink(),
                          itemBuilder: (context, index) {
                            final item = game.notices[index];
                            return CartoonEntrance(
                              key: ValueKey('notice-${item['id']}'),
                              delay: Duration(
                                milliseconds: 40 * index.clamp(0, 7),
                              ),
                              from: const Offset(0, 18),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildNoticeItem(item, l10n),
                                  Divider(
                                    height: 1,
                                    thickness: 1.5,
                                    indent: 10,
                                    endIndent: 10,
                                    color: Cartoon.ink.withValues(alpha: 0.12),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      }
                      return RefreshIndicator(
                        onRefresh: () async {
                          game.requestNotices();
                          await Future.delayed(
                            const Duration(milliseconds: 500),
                          );
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
    // 기한이 지났거나 꺼졌거나 소진된 쿠폰은 표시를 떼 — 서버가 coupon_dead 로 알린다
    // (옛 서버는 이 필드를 안 보내므로 없으면 살아 있는 것으로 본다).
    final hasCoupon =
        (item['coupon_code']?.toString() ?? '').isNotEmpty &&
        item['coupon_dead'] != true;
    final publishedAt = _formatShortDate(item['published_at']);
    final titleColor = noticeTitleColor(item['title_color']);
    final noticeId = item['id'];
    final isNew =
        noticeId is int &&
        widget.unreadIds.contains(noticeId) &&
        !_openedThisVisit.contains(noticeId);

    // 위 줄: 꼬리표(NEW · 분류 · 쿠폰)와 날짜. 아래 줄: 제목이 카드 폭을 통째로.
    // 예전엔 꼬리표를 제목 왼쪽에 줄줄이 세웠더니 제목이 몇 글자 못 들어갔다.
    final card = Container(
      // 상자 없이 한 줄 — 안 읽은 글만 연한 노란 바탕. 아래 구분선은 바깥에서.
      padding: EdgeInsets.fromLTRB(14, isPinned ? 18 : 12, 10, 12),
      decoration: BoxDecoration(
        color: isNew ? const Color(0xFFFFF3D0) : null,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 5,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (isNew)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Cartoon.red,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Cartoon.ink, width: 1.5),
                        ),
                        child: const Text(
                          'NEW',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _categoryBgColor(category),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Cartoon.ink, width: 1.5),
                      ),
                      child: Text(
                        _categoryLabel(l10n, category),
                        style: Cartoon.text(
                          size: 12.5,
                          color: _categoryTextColor(category),
                        ),
                      ),
                    ),
                    // Shown on every platform: knowing which post carries a
                    // coupon is worth as much on iOS, where the code itself is
                    // withheld and the reader has to ask.
                    if (hasCoupon) const CouponTag(),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                publishedAt,
                style: Cartoon.userText(
                  size: 11.5,
                  weight: FontWeight.w500,
                  color: Cartoon.ink.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Cartoon.userText(
                    size: 16,
                    weight: isNew ? FontWeight.w900 : FontWeight.w700,
                    height: 1.3,
                    // 운영자가 고른 색이 있으면 그 색으로. 목록과 상세가 같아야
                    // 눌렀을 때 "다른 글인가" 하지 않는다.
                    color: titleColor ?? Cartoon.ink,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 26,
                color: Cartoon.ink,
              ),
            ],
          ),
        ],
      ),
    );

    return CartoonPressable(
      scale: 0.97,
      onTap: () {
        if (noticeId is int) {
          context.read<GameService>().markNoticeRead(noticeId);
          setState(() => _openedThisVisit.add(noticeId));
        }
        _showNoticeDetail(item, l10n);
      },
      // 고정 글은 카드 모서리에 압정이 꽂혀 있다 — 줄 안의 작은 아이콘 대신.
      child: isPinned
          ? Stack(
              clipBehavior: Clip.none,
              children: [
                card,
                Positioned(
                  top: -8,
                  left: 12,
                  child: Transform.rotate(
                    angle: -0.35,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Cartoon.red,
                        shape: BoxShape.circle,
                        border: Border.all(color: Cartoon.ink, width: 1.6),
                      ),
                      child: const Icon(
                        Icons.push_pin_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            )
          : card,
    );
  }

  void _showNoticeDetail(Map<String, dynamic> item, L10n l10n) {
    final title = item['title']?.toString() ?? '';
    final content = item['content']?.toString() ?? '';
    final category = item['category']?.toString() ?? 'general';
    final publishedAt = _formatShortDate(item['published_at']);
    // Shown everywhere now: the ticket prints the code on every platform and
    // only its redeem stub is gated.
    final couponCode = item['coupon_dead'] == true
        ? ''
        : (item['coupon_code']?.toString() ?? '');

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _NoticeDetailPage(
          title: title,
          content: content,
          category: category,
          publishedAt: publishedAt,
          couponCode: couponCode,
          titleColor: noticeTitleColor(item['title_color']),
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
  final Color? titleColor;
  final String category;
  final String publishedAt;

  /// The coupon this notice hands out, if any.
  final String couponCode;

  const _NoticeDetailPage({
    required this.title,
    required this.content,
    this.titleColor,
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
                // Header
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
                              border: Border.all(color: Cartoon.ink, width: 2),
                              boxShadow: const [
                                BoxShadow(
                                  color: Cartoon.ink,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.arrow_back_rounded,
                              color: Cartoon.ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: categoryBg,
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(color: Cartoon.ink, width: 1.6),
                          ),
                          child: Text(
                            categoryLabel,
                            style: Cartoon.text(size: 14, color: categoryText),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Cartoon.userText(
                              size: 19,
                              weight: FontWeight.w900,
                              color: titleColor ?? Cartoon.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Content
                Expanded(
                  child: Container(
                    margin: EdgeInsets.fromLTRB(
                      16,
                      0,
                      16,
                      20 + MediaQuery.viewPaddingOf(context).bottom,
                    ),
                    padding: const EdgeInsets.all(18),
                    decoration: Cartoon.panelDecoration(radius: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          publishedAt,
                          style: Cartoon.text(
                            size: 14,
                            color: Cartoon.ink.withValues(alpha: 0.6),
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
      ),
    );
  }
}
