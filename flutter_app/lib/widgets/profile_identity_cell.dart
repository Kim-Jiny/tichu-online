import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/game_service.dart';
import 'level_badge.dart';
import 'profile_avatar.dart';
import 'title_chip.dart';

/// One player, drawn the way the rest of the app draws a player: their banner
/// as the surface, their photo with the level on it, their title above the
/// nickname.
///
/// Friend search used to render a coloured circle with the first letter of the
/// nickname in it, which meant the one screen whose whole job is "find this
/// person" was the one screen that showed nothing about them — no photo, no
/// title, and no sign that an account is private.
class ProfileIdentityCell extends StatelessWidget {
  final GameService game;
  final String nickname;

  /// Already filtered by the server for this viewer (blocked, reported and
  /// privacy-hidden photos arrive as null).
  final String? photoUrl;
  final String? bannerKey;
  final String? titleKey;
  final String? titleName;

  /// Null for a private account — the level is part of the record.
  final int? level;

  /// Private to this viewer: shows the badge instead of the level.
  final bool isPrivate;

  /// Trailing action — the add-friend button in search, the invite/kick chips
  /// in the friends list.
  final Widget? trailing;

  /// A line under the nickname: what they are doing, or when they were last
  /// here. Search results have nothing to say there, so it is optional.
  final String? subtitle;

  /// Colour for [subtitle]. Ignored when the cell is showing a banner, whose
  /// own text colour wins — a green "online" on a dark gradient is unreadable.
  final Color? subtitleColor;

  /// Presence dot beside the avatar. Null hides it: in search, "is this
  /// stranger online" is neither known nor useful.
  final bool? isOnline;

  final VoidCallback? onTap;

  const ProfileIdentityCell({
    super.key,
    required this.game,
    required this.nickname,
    this.photoUrl,
    this.bannerKey,
    this.titleKey,
    this.titleName,
    this.level,
    this.isPrivate = false,
    this.trailing,
    this.subtitle,
    this.subtitleColor,
    this.isOnline,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    // Offline drains the banner. In a list sorted by presence the row itself
    // has to say which half you are looking at, and a full-strength banner on
    // someone who left yesterday reads as louder than a friend who is online
    // right now. Null (search results) keeps full colour — there is no
    // presence being claimed there.
    final away = isOnline == false;
    final gradient = away ? null : game.bannerGradient(bannerKey);
    final textColor = away ? null : game.bannerTextColor(bannerKey);
    final photo = game.resolvePhotoUrl(photoUrl);
    const avatarSize = 40.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            gradient: gradient,
            color: gradient == null
                ? Colors.white.withValues(alpha: away ? 0.6 : 0.85)
                : null,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE6DDD8)),
          ),
          child: Row(
            children: [
              // Its own column rather than a corner of the avatar: overlaid,
              // it covered part of the face, and the opposite corner is
              // already taken by the level badge.
              if (isOnline != null) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isOnline!
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFFC4BAB4),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              SizedBox(
                width: avatarSize,
                height: avatarSize,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ProfileAvatar(
                      photoUrl: photo,
                      size: avatarSize,
                      fallback: Container(
                        width: avatarSize,
                        height: avatarSize,
                        decoration: const BoxDecoration(
                          color: Color(0xFFF0E7E3),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.person,
                          size: 24,
                          color: Color(0xFF9C8B84),
                        ),
                      ),
                    ),
                    // A private account has no level to show, so the corner
                    // stays empty rather than claiming level 1.
                    if ((level ?? 0) > 0)
                      Positioned(
                        right: -3,
                        bottom: -3,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.2),
                          ),
                          child: LevelBadge(level: level, size: 15),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if ((titleName ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: TitleChip(
                          titleKey: titleKey,
                          titleName: titleName,
                        ),
                      ),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            nickname,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: textColor ?? const Color(0xFF5A4038),
                            ),
                          ),
                        ),
                        if (isPrivate) ...[
                          const SizedBox(width: 6),
                          _privateBadge(l10n.profilePrivateBadge),
                        ],
                      ],
                    ),
                    if ((subtitle ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            // On a banner the caller's colour would be a
                            // guess about a surface it cannot see; the
                            // banner's own text colour is the one that reads.
                            color: textColor != null
                                ? textColor.withValues(alpha: 0.85)
                                : (subtitleColor ?? const Color(0xFF9A8E8A)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ),
    );
  }

  Widget _privateBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0D8D4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline, size: 11, color: Color(0xFF8A7A72)),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFF8A7A72),
            ),
          ),
        ],
      ),
    );
  }
}
