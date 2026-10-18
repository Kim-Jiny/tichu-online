import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/game_service.dart';
import '../theme/cartoon.dart';
import 'notice_body.dart';

/// 이용약관 / 개인정보처리방침 팝업.
///
/// 예전엔 400px 상자에 글자 한 덩어리였다. 약관은 길고 "그중 한 조항" 을 찾으러
/// 여는 일이 많아서, 조항(제N조 / Article N / # 제목)을 알아보면 위에 목차 칩을
/// 달아 바로 점프하게 하고, 읽은 만큼 차오르는 막대를 둔다. 조항 표시가 없는
/// 글이면 목차 없이 본문만 보여 준다. 서버에서 받은 글자는 건드리지 않는다.
void showLegalTextDialog(
  BuildContext context, {
  required String title,
  required bool isTermsOfService,
}) {
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
        child: _LegalBody(
          title: title,
          isTermsOfService: isTermsOfService,
          dialogContext: ctx,
        ),
      ),
    ),
  );
}

class _Section {
  _Section(this.heading, this.body) : key = GlobalKey();
  final String? heading;
  final String body;
  final GlobalKey key;
}

final RegExp _headingRe = RegExp(
  r'^(?:#{1,3}\s+.+|제\s*\d+\s*조.*|Article\s+\d+.*|Artikel\s+\d+.*|§\s*\d+.*)$',
);

List<_Section> _split(String text) {
  final sections = <_Section>[];
  String? heading;
  final buf = StringBuffer();
  void flush() {
    final body = buf.toString().trim();
    if (heading != null || body.isNotEmpty) {
      sections.add(_Section(heading, body));
    }
    buf.clear();
  }

  for (final line in text.split('\n')) {
    final t = line.trim();
    if (_headingRe.hasMatch(t)) {
      flush();
      heading = t.replaceFirst(RegExp(r'^#{1,3}\s+'), '');
    } else {
      buf.writeln(line);
    }
  }
  flush();
  return sections;
}

class _LegalBody extends StatefulWidget {
  const _LegalBody({
    required this.title,
    required this.isTermsOfService,
    required this.dialogContext,
  });

  final String title;
  final bool isTermsOfService;
  final BuildContext dialogContext;

  @override
  State<_LegalBody> createState() => _LegalBodyState();
}

class _LegalBodyState extends State<_LegalBody> {
  final ScrollController _scroll = ScrollController();
  double _progress = 0;
  String? _splitFor;
  List<_Section> _sections = const [];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_syncProgress);
    // 내용이 화면보다 짧으면 스크롤이 생기지 않아 리스너가 한 번도 불리지
    // 않는다. 그러면 다 읽었는데도 진행바가 0 에 머문다 — 첫 레이아웃
    // 뒤에 한 번 맞춰 준다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncProgress());
  }

  void _syncProgress() {
    if (!mounted || !_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    final p = max <= 0 ? 1.0 : (_scroll.offset / max).clamp(0.0, 1.0);
    if ((p - _progress).abs() > 0.004) setState(() => _progress = p);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _jump(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      alignment: 0.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final game = context.watch<GameService>();
    final text = widget.isTermsOfService
        ? game.eulaContent
        : game.privacyPolicy;

    if (text != null && text.isNotEmpty && text != _splitFor) {
      _splitFor = text;
      _sections = _split(text);
    }
    final headings = [
      for (final s in _sections)
        if (s.heading != null) s,
    ];

    Widget bodyArea;
    if (text == null) {
      bodyArea = const Center(
        child: CircularProgressIndicator(color: Cartoon.orange, strokeWidth: 4),
      );
    } else if (text.isEmpty) {
      bodyArea = Center(
        child: Text(
          l10n.textViewLoadFailed,
          style: Cartoon.userText(
            size: 15,
            color: Cartoon.ink.withValues(alpha: 0.6),
          ),
        ),
      );
    } else {
      bodyArea = SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final s in _sections)
              Padding(
                key: s.key,
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (s.heading != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Cartoon.cream,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Cartoon.ink, width: 1.6),
                        ),
                        child: Text(
                          s.heading!,
                          style: Cartoon.userText(
                            size: 15.5,
                            weight: FontWeight.w900,
                          ),
                        ),
                      ),
                    if (s.body.isNotEmpty) NoticeBody(content: s.body),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Color.lerp(
                    const Color(0xFF42A5F5),
                    Colors.white,
                    0.75,
                  ),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Cartoon.ink, width: 2),
                  boxShadow: [
                    BoxShadow(color: Cartoon.ink, offset: Offset(0, 2)),
                  ],
                ),
                child: Icon(
                  widget.isTermsOfService
                      ? Icons.description_rounded
                      : Icons.privacy_tip_rounded,
                  color: Cartoon.onSurface(const Color(0xFF1E88E5)),
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.title,
                  style: Cartoon.text(size: 21),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              CartoonPressable(
                scale: 0.88,
                onTap: () => Navigator.pop(widget.dialogContext),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Cartoon.paper,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: Cartoon.ink, width: 2),
                    boxShadow: [
                      BoxShadow(color: Cartoon.ink, offset: Offset(0, 2)),
                    ],
                  ),
                  child: Icon(Icons.close_rounded, color: Cartoon.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 읽은 만큼 차오르는 막대
          Container(
            height: 12,
            decoration: BoxDecoration(
              color: Cartoon.paper,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Cartoon.ink, width: 1.5),
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: _progress,
              child: Container(color: Cartoon.green),
            ),
          ),
          if (headings.length >= 2) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final s in headings)
                    Padding(
                      padding: const EdgeInsets.only(right: 8, bottom: 3),
                      child: CartoonPressable(
                        scale: 0.92,
                        onTap: () => _jump(s.key),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Cartoon.paper,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Cartoon.ink, width: 1.5),
                          ),
                          child: Text(
                            s.heading!,
                            maxLines: 1,
                            style: Cartoon.userText(size: 13),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Expanded(child: bodyArea),
          const SizedBox(height: 10),
          CartoonButton(
            height: 50,
            color: Cartoon.orange,
            onPressed: () => Navigator.pop(widget.dialogContext),
            child: CartoonButton.label(l10n.commonClose, size: 18),
          ),
        ],
      ),
    );
  }
}
