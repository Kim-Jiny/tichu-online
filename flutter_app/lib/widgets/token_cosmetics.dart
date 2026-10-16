import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/cartoon.dart';

/// 토큰 상점에서 파는 꾸미기의 모양. 서버는 키만 주고받고, 어떻게 생겼는지는
/// 전부 여기서 정한다 — 새 모양은 이 파일에 한 줄 더하면 된다.

// ───────────────────────────── 말풍선 스타일 ─────────────────────────────

class BubbleStyle {
  const BubbleStyle({
    required this.fill,
    this.fillEnd,
    required this.border,
    this.text = Cartoon.ink,
    required this.badge,
    required this.badgeColor,
  });

  final Color fill;

  /// 있으면 fill → fillEnd 로 비스듬히 번지는 바탕.
  final Color? fillEnd;
  final Color border;
  final Color text;

  /// 말풍선 모서리에 붙는 작은 표식.
  final IconData badge;
  final Color badgeColor;

  /// 꼬리(말풍선 아래 삼각형)가 맞춰 칠할 색.
  Color get tailFill => fillEnd ?? fill;

  Decoration decoration({double radius = 14, double borderWidth = 1.8}) =>
      BoxDecoration(
        color: fillEnd == null ? fill : null,
        gradient: fillEnd == null
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [fill, fillEnd!],
              ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border, width: borderWidth),
      );
}

const Map<String, BubbleStyle> _bubbleStyles = {
  // 기본 3종
  'bubble_basic_1': BubbleStyle(
    fill: Color(0xFFFFE1EC),
    border: Color(0xFFD63B78),
    badge: Icons.favorite_rounded,
    badgeColor: Color(0xFFE5457F),
  ),
  'bubble_basic_2': BubbleStyle(
    fill: Color(0xFFDDF7EE),
    border: Color(0xFF2BA37F),
    badge: Icons.cloud_rounded,
    badgeColor: Color(0xFF39B58E),
  ),
  'bubble_basic_3': BubbleStyle(
    fill: Color(0xFFFFF3B0),
    border: Color(0xFFD99A00),
    badge: Icons.star_rounded,
    badgeColor: Color(0xFFFFB300),
  ),
  // 상위 3종 — 바탕이 번지고 글자색도 바뀐다.
  'bubble_premium_1': BubbleStyle(
    fill: Color(0xFFFFB347),
    fillEnd: Color(0xFFFF5A5F),
    border: Color(0xFF8A2B10),
    text: Colors.white,
    badge: Icons.local_fire_department_rounded,
    badgeColor: Color(0xFFFFD43B),
  ),
  'bubble_premium_2': BubbleStyle(
    fill: Color(0xFFFFE9F3),
    fillEnd: Color(0xFFFFB7D5),
    border: Color(0xFFB03A74),
    badge: Icons.local_florist_rounded,
    badgeColor: Color(0xFFE5457F),
  ),
  'bubble_premium_3': BubbleStyle(
    fill: Color(0xFF3B2A6B),
    fillEnd: Color(0xFF6A47C4),
    border: Color(0xFFFFD43B),
    text: Colors.white,
    badge: Icons.bolt_rounded,
    badgeColor: Color(0xFFFFD43B),
  ),
};

/// 서버가 준 키에 해당하는 말풍선 모양. 모르는 키(새 모양을 못 받은 옛 앱)나 null 이면 null.
BubbleStyle? bubbleStyleFor(String? key) => key == null ? null : _bubbleStyles[key];

// ───────────────────────────── 방 목록 강조 ─────────────────────────────

class RoomHighlightStyle {
  const RoomHighlightStyle({
    required this.fill,
    required this.border,
    required this.badge,
    required this.badgeColor,
    this.badgeOnRight = true,
  });

  final Color fill;
  final Color border;
  final IconData badge;
  final Color badgeColor;
  final bool badgeOnRight;
}

const Map<String, RoomHighlightStyle> _roomHighlights = {
  'room_highlight_1': RoomHighlightStyle(
    fill: Color(0xFFFFF4C9),
    border: Color(0xFFE0A800),
    badge: Icons.workspace_premium_rounded,
    badgeColor: Color(0xFFE0A800),
  ),
  'room_highlight_2': RoomHighlightStyle(
    fill: Color(0xFFFFF9E3),
    border: Color(0xFFFFB300),
    badge: Icons.auto_awesome_rounded,
    badgeColor: Color(0xFFFF9A1F),
  ),
  'room_highlight_3': RoomHighlightStyle(
    fill: Color(0xFFFFE9F2),
    border: Color(0xFFE8689A),
    badge: Icons.bookmark_rounded,
    badgeColor: Color(0xFFE8457F),
    badgeOnRight: false,
  ),
};

RoomHighlightStyle? roomHighlightFor(String? key) =>
    key == null ? null : _roomHighlights[key];

// ───────────────────────────── 이름 ─────────────────────────────

/// 상품 키 → 보여 줄 이름(종류 + 모양).
String tokenProductName(L10n l10n, String key) {
  switch (key) {
    case 'room_highlight_1':
      return l10n.tokenVariantRoomHighlight1;
    case 'room_highlight_2':
      return l10n.tokenVariantRoomHighlight2;
    case 'room_highlight_3':
      return l10n.tokenVariantRoomHighlight3;
    case 'bubble_basic_1':
      return l10n.tokenVariantBubbleBasic1;
    case 'bubble_basic_2':
      return l10n.tokenVariantBubbleBasic2;
    case 'bubble_basic_3':
      return l10n.tokenVariantBubbleBasic3;
    case 'bubble_premium_1':
      return l10n.tokenVariantBubblePremium1;
    case 'bubble_premium_2':
      return l10n.tokenVariantBubblePremium2;
    case 'bubble_premium_3':
      return l10n.tokenVariantBubblePremium3;
  }
  return key;
}

String tokenKindName(L10n l10n, String kind) {
  switch (kind) {
    case 'room_highlight':
      return l10n.tokenShopKindRoomHighlight;
    case 'bubble_basic':
      return l10n.tokenShopKindBubble;
    case 'bubble_premium':
      return l10n.tokenShopKindBubblePremium;
  }
  return kind;
}

// ───────────────────────────── 미리보기 ─────────────────────────────

/// 상점에서 보여 주는 말풍선 미리보기(꼬리 없이 몸통과 표식만).
class BubblePreview extends StatelessWidget {
  const BubblePreview({super.key, required this.styleKey, required this.text});

  final String styleKey;
  final String text;

  @override
  Widget build(BuildContext context) {
    final style = bubbleStyleFor(styleKey);
    if (style == null) return const SizedBox.shrink();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: style.decoration(),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Cartoon.userText(
              size: 13,
              weight: FontWeight.w800,
              color: style.text,
            ),
          ),
        ),
        Positioned(left: -7, top: -9, child: BubbleBadge(style: style)),
      ],
    );
  }
}

/// 말풍선 모서리 표식.
class BubbleBadge extends StatelessWidget {
  const BubbleBadge({super.key, required this.style, this.size = 18});
  final BubbleStyle style;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Cartoon.paper,
        shape: BoxShape.circle,
        border: Border.all(color: style.border, width: 1.4),
      ),
      child: Icon(style.badge, size: size * 0.66, color: style.badgeColor),
    );
  }
}

/// 상점에서 보여 주는 방 목록 줄 미리보기.
class RoomHighlightPreview extends StatelessWidget {
  const RoomHighlightPreview({
    super.key,
    required this.styleKey,
    required this.name,
  });

  final String styleKey;
  final String name;

  @override
  Widget build(BuildContext context) {
    final style = roomHighlightFor(styleKey);
    if (style == null) return const SizedBox.shrink();
    return RoomHighlightFrame(
      style: style,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Cartoon.userText(size: 15),
        ),
      ),
    );
  }
}

/// 방 목록 줄에 씌우는 강조 틀 — 바탕색·테두리·모서리 표식.
class RoomHighlightFrame extends StatelessWidget {
  const RoomHighlightFrame({super.key, required this.style, required this.child});

  final RoomHighlightStyle style;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            color: style.fill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: style.border, width: 2.4),
            boxShadow: [
              BoxShadow(
                color: style.border.withValues(alpha: 0.35),
                blurRadius: 8,
              ),
            ],
          ),
          child: child,
        ),
        Positioned(
          top: -7,
          left: style.badgeOnRight ? null : 10,
          right: style.badgeOnRight ? 10 : null,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: Cartoon.paper,
              shape: BoxShape.circle,
              border: Border.all(color: style.border, width: 1.6),
            ),
            child: Icon(style.badge, size: 15, color: style.badgeColor),
          ),
        ),
      ],
    );
  }
}

/// 강조 모양이 없으면 그대로, 있으면 틀을 씌운다.
class MaybeRoomHighlight extends StatelessWidget {
  const MaybeRoomHighlight({super.key, required this.style, required this.child});

  final RoomHighlightStyle? style;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      style == null ? child : RoomHighlightFrame(style: style!, child: child);
}
