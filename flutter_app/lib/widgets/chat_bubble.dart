import 'package:flutter/material.dart';

import '../services/game_service.dart';
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

  @override
  Widget build(BuildContext context) {
    // System lines arrive with an empty sender; they get no avatar and no menu.
    final hasSender = sender.isNotEmpty;

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
                    style: TextStyle(
                      fontSize: senderFontSize,
                      color: const Color(0xFF8A8A8A),
                    ),
                  ),
                ),
              Container(
                padding: bubblePadding,
                decoration: BoxDecoration(
                  color: isMe ? mineColor : theirsColor,
                  borderRadius: BorderRadius.circular(bubbleRadius),
                  border: isMe ? null : theirsBorder,
                ),
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: messageFontSize,
                    color: isMe ? Colors.white : const Color(0xFF333333),
                  ),
                ),
              ),
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
