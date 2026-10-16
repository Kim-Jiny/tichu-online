import 'package:flutter/material.dart';

import '../services/game_service.dart';
import '../theme/cartoon.dart';
import 'token_cosmetics.dart';
import 'profile_avatar.dart';

/// One chat line: sender avatar, name, and the message bubble.
///
/// Five screens drew this — the four game screens, the spectator screen, and
/// the lobby — and once whitespace is normalised four of them are 96-98%
/// identical. What actually differed was styling (the lobby is a size smaller
/// and outlines other people's bubbles) and whether tapping a line opens the
/// user menu. Both are parameters now, so the next change to a chat line —
/// like putting the profile photo in it — lands once instead of five times.
class ChatBubble extends StatelessWidget {
  final String sender;
  final String message;
  final bool isMe;
  final GameService game;

  /// Tapping the line. Null makes it inert — the spectator and Love Letter
  /// panels have no user menu to open.
  final VoidCallback? onTap;

  final double bottomSpacing;
  final double avatarRadius;
  final Color avatarBackground;
  final double senderFontSize;
  final double messageFontSize;
  final double bubbleRadius;
  final Color mineColor;
  final Color theirsColor;

  /// The lobby outlines other people's bubbles because they sit on a white
  /// panel and would otherwise have no edge.
  final BoxBorder? theirsBorder;

  final EdgeInsets bubblePadding;

  const ChatBubble({
    super.key,
    required this.sender,
    required this.message,
    required this.isMe,
    required this.game,
    this.onTap,
    this.bottomSpacing = 8,
    this.avatarRadius = 14,
    this.avatarBackground = const Color(0xFFE0E0E0),
    this.senderFontSize = 11,
    this.messageFontSize = 14,
    this.bubbleRadius = 16,
    this.mineColor = const Color(0xFF64B5F6),
    this.theirsColor = const Color(0xFFF0F0F0),
    this.theirsBorder,
    this.bubblePadding = const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 8,
    ),
  });

  /// 말풍선 몸통. 토큰 상점 모양이 있으면 그 색·테두리·표식, 없으면 기본 카툰 모양.
  Widget _bubble(BubbleStyle? style) {
    final textColor = style?.text ?? (isMe ? Colors.white : Cartoon.ink);
    final body = Container(
      padding: bubblePadding,
      // 카툰: 내 말풍선과 남의 말풍선 모두 진한 테두리 + 작은 단색 그림자.
      decoration: style != null
          ? style.decoration(radius: bubbleRadius, borderWidth: 1.8)
          : BoxDecoration(
              color: isMe ? mineColor : Colors.white,
              borderRadius: BorderRadius.circular(bubbleRadius),
              border: Border.all(
                color: isMe ? Cartoon.ink : Cartoon.ink.withValues(alpha: 0.45),
                width: isMe ? 1.8 : 1.4,
              ),
            ),
      child: Text(
        message,
        style: Cartoon.userText(
          size: messageFontSize,
          weight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
    if (style == null) return body;
    // 좌석 말풍선과 같은 모서리 표식.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        body,
        Positioned(
          left: -5,
          top: -7,
          child: BubbleBadge(style: style, size: 16),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // System lines arrive with an empty sender; they get no avatar and no menu.
    final hasSender = sender.isNotEmpty;
    // 보낸 사람이 장착한 말풍선 모양(없으면 null).
    final style = hasSender ? bubbleStyleFor(game.chatBubbleFor(sender)) : null;

    final row = Row(
      mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isMe && hasSender) ...[
          // Chat lines carry only a nickname, so the photo comes from whatever
          // roster is loaded. No photo → the same default-avatar silhouette the
          // seats use, rather than an initial letter, so one person looks like
          // one person everywhere.
          ProfileAvatar(
            photoUrl: game.chatPhotoUrlFor(sender),
            size: avatarRadius * 2,
            blocked: game.blockedUsers.contains(sender),
            fallback: Container(
              width: avatarRadius * 2,
              height: avatarRadius * 2,
              decoration: BoxDecoration(
                color: avatarBackground,
                borderRadius: BorderRadius.circular(
                  avatarCornerRadius(avatarRadius * 2),
                ),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.person,
                size: avatarRadius * 1.15,
                color: const Color(0xFF9C8B84),
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Column(
            crossAxisAlignment: isMe
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              if (!isMe && hasSender)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    sender,
                    style: Cartoon.userText(
                      size: senderFontSize + 1,
                      weight: FontWeight.w800,
                      color: Cartoon.ink.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              _bubble(style),
            ],
          ),
        ),
      ],
    );

    return Padding(
      padding: EdgeInsets.only(bottom: bottomSpacing),
      child: onTap == null ? row : GestureDetector(onTap: onTap, child: row),
    );
  }
}
