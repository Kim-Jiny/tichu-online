import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// 공지 본문을 읽기 좋게 그린다.
///
/// 예전에는 Text 하나에 통째로 넣었다. 그래서 문단이 붙어 한 덩어리로 보이고,
/// 운영자가 쓴 `**문의하기**` 는 별표까지 그대로 나왔다 — 마크다운을 쓰고
/// 있는데 읽는 쪽만 모르는 상태였다.
///
/// 마크다운 패키지를 붙이는 대신 실제로 쓰이는 것만 직접 처리한다. 공지에
/// 필요한 문법은 몇 개뿐이고, 그 몇 개를 위해 유지보수가 끊긴 패키지를
/// 들이는 것보다 낫다. 지원하지 않는 문법은 글자 그대로 보여 준다 —
/// 깨진 화면보다 그냥 글씨가 낫다.
///
/// 지원하는 것
///   # 제목 / ## 소제목 / ### 작은제목
///   - 목록 / * 목록 / 1. 번호 목록
///   --- 구분선
///   **굵게**
///   [보이는 글](https://링크)
///   빈 줄 = 문단 나눔
class NoticeBody extends StatelessWidget {
  const NoticeBody({super.key, required this.content, this.color});

  final String content;

  /// 본문 글자색. 안 주면 공지 화면의 기본 갈색.
  final Color? color;

  static const _text = Color(0xFF5A4038);
  static const _accent = Color(0xFFE0812A);

  @override
  Widget build(BuildContext context) {
    // 본문 15pt. 14 로는 폰에서 작아 보인다는 얘기가 있었다 — 공지는 길게
    // 읽는 글이라 한 단계 키우고, 제목도 같이 올려 위계를 유지한다.
    final base = TextStyle(fontSize: 15, height: 1.7, color: color ?? _text);
    final blocks = parseNoticeBlocks(content);

    final children = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      if (i > 0) children.add(SizedBox(height: b.spacingBefore));
      children.add(_buildBlock(context, b, base));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildBlock(BuildContext context, NoticeBlock b, TextStyle base) {
    switch (b.kind) {
      case NoticeBlockKind.heading1:
        return Text.rich(
          _inline(context, b.text, base),
          style: base.copyWith(
            fontSize: 19,
            height: 1.45,
            fontWeight: FontWeight.w800,
          ),
        );
      case NoticeBlockKind.heading2:
        return Text.rich(
          _inline(context, b.text, base),
          style: base.copyWith(
            fontSize: 17,
            height: 1.5,
            fontWeight: FontWeight.w800,
          ),
        );
      case NoticeBlockKind.heading3:
        // 본문과 같은 크기에 굵기만 준다. 17 과 16 은 나란히 놓으면 구분이
        // 안 가서, 세 번째 단계는 크기 대신 굵기로 나눈다.
        return Text.rich(
          _inline(context, b.text, base),
          style: base.copyWith(height: 1.5, fontWeight: FontWeight.w700),
        );
      case NoticeBlockKind.divider:
        return const Divider(height: 1, color: Color(0xFFE8DFDA));
      case NoticeBlockKind.bullet:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < b.items.length; i++) ...[
              if (i > 0) const SizedBox(height: 4),
              _listRow(context, b.marker(i), b.items[i], base),
            ],
          ],
        );
      case NoticeBlockKind.paragraph:
        return Text.rich(_inline(context, b.text, base), style: base);
    }
  }

  /// 글머리표와 본문을 나란히. 두 번째 줄부터도 본문 자리에 맞춰 들어간다 —
  /// 목록이 길어지면 그게 없을 때 글이 글머리표 밑으로 흘러 지저분해진다.
  Widget _listRow(
    BuildContext context,
    String marker,
    String text,
    TextStyle base,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 22,
          child: Text(marker, style: base.copyWith(color: _accent)),
        ),
        Expanded(child: Text.rich(_inline(context, text, base), style: base)),
      ],
    );
  }

  /// 한 줄 안의 **굵게** 와 [글](링크).
  TextSpan _inline(BuildContext context, String raw, TextStyle base) {
    final spans = <TextSpan>[];
    for (final piece in parseInline(raw)) {
      if (piece.href != null) {
        spans.add(TextSpan(
          text: piece.text,
          style: base.copyWith(
            color: _accent,
            decoration: TextDecoration.underline,
            decorationColor: _accent,
            fontWeight: piece.bold ? FontWeight.w700 : null,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              final uri = Uri.tryParse(piece.href!);
              if (uri != null) {
                launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
        ));
      } else {
        spans.add(TextSpan(
          text: piece.text,
          style: piece.bold ? base.copyWith(fontWeight: FontWeight.w800) : null,
        ));
      }
    }
    return TextSpan(children: spans);
  }
}

enum NoticeBlockKind { paragraph, heading1, heading2, heading3, bullet, divider }

class NoticeBlock {
  NoticeBlock.paragraph(this.text)
    : kind = NoticeBlockKind.paragraph,
      items = const [],
      ordered = false;
  NoticeBlock.heading(this.text, {required int level})
    : kind = level == 1
          ? NoticeBlockKind.heading1
          : level == 2
              ? NoticeBlockKind.heading2
              : NoticeBlockKind.heading3,
      items = const [],
      ordered = false;
  NoticeBlock.bullet(this.items, {this.ordered = false})
    : kind = NoticeBlockKind.bullet,
      text = '';
  NoticeBlock.divider()
    : kind = NoticeBlockKind.divider,
      text = '',
      items = const [],
      ordered = false;

  final NoticeBlockKind kind;
  final String text;
  final List<String> items;
  final bool ordered;

  String marker(int i) => ordered ? '${i + 1}.' : '•';

  /// 이 블록 앞에 둘 여백. 제목은 앞 문단과 떼어 놓아야 제목처럼 보인다.
  double get spacingBefore {
    switch (kind) {
      case NoticeBlockKind.heading1:
        return 20;
      case NoticeBlockKind.heading2:
        return 16;
      case NoticeBlockKind.heading3:
        return 14;
      case NoticeBlockKind.divider:
        return 16;
      case NoticeBlockKind.bullet:
      case NoticeBlockKind.paragraph:
        return 12;
    }
  }
}

/// 본문을 블록으로 자른다. 빈 줄이 문단 경계다.
List<NoticeBlock> parseNoticeBlocks(String content) {
  final lines = content.replaceAll('\r\n', '\n').split('\n');
  final blocks = <NoticeBlock>[];
  final para = <String>[];
  var bullets = <String>[];
  var bulletsOrdered = false;

  void flushParagraph() {
    if (para.isEmpty) return;
    blocks.add(NoticeBlock.paragraph(para.join('\n')));
    para.clear();
  }

  void flushBullets() {
    if (bullets.isEmpty) return;
    blocks.add(NoticeBlock.bullet(List.of(bullets), ordered: bulletsOrdered));
    bullets = <String>[];
  }

  for (final raw in lines) {
    final line = raw.trimRight();
    final trimmed = line.trim();

    if (trimmed.isEmpty) {
      flushParagraph();
      flushBullets();
      continue;
    }
    if (RegExp(r'^-{3,}$').hasMatch(trimmed)) {
      flushParagraph();
      flushBullets();
      blocks.add(NoticeBlock.divider());
      continue;
    }
    final heading = RegExp(r'^(#{1,3})\s+(.*)$').firstMatch(trimmed);
    if (heading != null) {
      flushParagraph();
      flushBullets();
      blocks.add(
        NoticeBlock.heading(heading.group(2)!, level: heading.group(1)!.length),
      );
      continue;
    }
    final numbered = RegExp(r'^(\d+)[.)]\s+(.*)$').firstMatch(trimmed);
    if (numbered != null) {
      flushParagraph();
      if (bullets.isNotEmpty && !bulletsOrdered) flushBullets();
      bulletsOrdered = true;
      bullets.add(numbered.group(2)!);
      continue;
    }
    final bullet = RegExp(r'^[-*•]\s+(.*)$').firstMatch(trimmed);
    if (bullet != null) {
      flushParagraph();
      if (bullets.isNotEmpty && bulletsOrdered) flushBullets();
      bulletsOrdered = false;
      bullets.add(bullet.group(1)!);
      continue;
    }
    flushBullets();
    para.add(trimmed);
  }
  flushParagraph();
  flushBullets();
  return blocks;
}

/// 한 줄을 굵게·링크 조각으로 자른다.
class InlinePiece {
  const InlinePiece(this.text, {this.bold = false, this.href});

  final String text;
  final bool bold;
  final String? href;
}

final _boldOrLink = RegExp(r'\*\*(.+?)\*\*|\[([^\]]+)\]\((https?://[^\s)]+)\)');

List<InlinePiece> parseInline(String raw) {
  final pieces = <InlinePiece>[];
  var cursor = 0;
  for (final m in _boldOrLink.allMatches(raw)) {
    if (m.start > cursor) {
      pieces.add(InlinePiece(raw.substring(cursor, m.start)));
    }
    if (m.group(1) != null) {
      pieces.add(InlinePiece(m.group(1)!, bold: true));
    } else {
      pieces.add(InlinePiece(m.group(2)!, href: m.group(3)));
    }
    cursor = m.end;
  }
  if (cursor < raw.length) pieces.add(InlinePiece(raw.substring(cursor)));
  // 아무 문법도 없으면 통짜 한 조각.
  if (pieces.isEmpty) pieces.add(InlinePiece(raw));
  return pieces;
}

/// 공지 제목에 쓸 수 있는 색.
///
/// 서버 `moderation/customTitle.js` 의 TITLE_COLORS 와 같은 값이다. 커스텀
/// 칭호가 쓰던 팔레트를 공지 제목에도 재사용한다 — 이미 가독성을 보고 고른
/// 여덟 가지라 배경에 묻히거나 눈이 아픈 색이 없다.
///
/// 서버는 id 만 내려보낸다. 모르는 id 가 오면(팔레트가 서버에서만 늘어난 경우)
/// null 을 돌려주고 화면은 기본색을 쓴다 — 색 하나 때문에 제목이 안 보이는
/// 것보다 낫다.
const Map<String, Color> noticeTitleColors = {
  'rose': Color(0xFFD64550),
  'amber': Color(0xFFC97A0B),
  'green': Color(0xFF2E7D32),
  'teal': Color(0xFF00796B),
  'blue': Color(0xFF1565C0),
  'violet': Color(0xFF6A3FB5),
  'pink': Color(0xFFC2185B),
  'slate': Color(0xFF455A64),
};

Color? noticeTitleColor(Object? id) {
  if (id == null) return null;
  return noticeTitleColors[id.toString()];
}
