import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Corner radius for an avatar drawn at [size].
///
/// Avatars are rounded squares, not circles. The shape was settled on the
/// profile popup — a 60px avatar with a 14px radius — and this keeps that
/// proportion at every other size, so a 24px row and a 92px seat read as the
/// same shape rather than as two different ones.
///
/// Everything that draws a face goes through here: the photo, the default
/// silhouette, and the bot art. If they disagree, a table shows round bots
/// beside square players.
double avatarCornerRadius(double size) => size * (17 / 60);

/// Circular profile avatar for a player.
///
/// Shows the paid profile photo when [photoUrl] is a non-empty absolute URL
/// and the viewer hasn't [blocked] the owner; otherwise renders [fallback]
/// (the existing default avatar — a level badge, initial, or icon). The photo
/// is cached on disk via `cached_network_image`; while loading or on any error
/// it transparently falls back so a broken/expired URL never leaves a gap.
///
/// Callers should pass an already-resolved absolute URL
/// (`game.resolvePhotoUrl(player.photoUrl)`), since a relative `/media/...`
/// path won't load on its own.
/// The default avatar: a person silhouette on the app's warm grey.
///
/// Every seat needs *something* to draw when a player has no photo — the
/// screens that passed an empty `SizedBox` instead left a hole in the seat,
/// which reads as a broken image rather than as "no photo set". Scales its
/// icon with [size] so it looks the same in a 24px list row and a 92px seat.
class DefaultAvatar extends StatelessWidget {
  final double size;

  const DefaultAvatar({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFF0E7E3),
        borderRadius: BorderRadius.circular(avatarCornerRadius(size)),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.person,
        size: size * 0.58,
        color: const Color(0xFF9C8B84),
      ),
    );
  }
}

class ProfileAvatar extends StatelessWidget {
  final String? photoUrl;
  final double size;

  /// Default avatar shown when there is no photo, it's blocked, still loading,
  /// or failed to load. Rendered at [size]×[size].
  final Widget fallback;

  /// Viewer has blocked this player — never show their photo (an offensive
  /// avatar can't be forced on someone who opted out).
  final bool blocked;

  /// Optional ring around the avatar (only drawn when a photo is shown).
  final BoxBorder? border;

  /// Corner radius. Null → [avatarCornerRadius] for this size, which is the
  /// shape everywhere; pass a value only to match a surface that has its own.
  final double? borderRadius;

  const ProfileAvatar({
    super.key,
    required this.photoUrl,
    required this.size,
    required this.fallback,
    this.blocked = false,
    this.border,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    final showPhoto =
        !blocked &&
        url != null &&
        (url.startsWith('http://') || url.startsWith('https://'));
    final outerRadius = borderRadius ?? avatarCornerRadius(size);
    // BoxDecoration.border 를 쓰면 Container 가 테두리 두께만큼 자동으로
    // 자식을 padding 시킨다. 자식(이미지) 은 그대로 outerRadius 로 클립되니
    // 코너 곡률(반경/변) 비율이 살짝 커져서 이미지 모서리가 테두리 안쪽
    // 곡선보다 안쪽으로 파고 든다 — 사진과 테두리 사이 미세한 틈. 클립
    // 반경을 (테두리 두께) 만큼 줄여서 두 곡선을 맞춘다.
    final borderWidth = border == null
        ? 0.0
        : (border!.top.width); // Border.all 이라 상하좌우 동일
    final innerRadius = math.max(0.0, outerRadius - borderWidth);
    final Widget content;
    if (!showPhoto) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(innerRadius),
        child: fallback,
      );
    } else {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(innerRadius),
        child: CachedNetworkImage(
          imageUrl: url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 150),
          placeholder: (_, _) => fallback,
          errorWidget: (_, _, _) => fallback,
        ),
      );
    }
    if (border == null) {
      return SizedBox(width: size, height: size, child: content);
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(outerRadius),
        border: border,
      ),
      child: content,
    );
  }
}
