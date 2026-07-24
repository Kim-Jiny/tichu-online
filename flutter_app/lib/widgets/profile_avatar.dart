import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

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

  /// Corner radius. Null → a circle; a value → a rounded square (to match a
  /// host surface whose default avatar is a rounded rect).
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
    final showPhoto = !blocked
        && url != null
        && (url.startsWith('http://') || url.startsWith('https://'));
    if (!showPhoto) {
      return SizedBox(width: size, height: size, child: fallback);
    }
    final image = CachedNetworkImage(
      imageUrl: url,
      width: size,
      height: size,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 150),
      placeholder: (_, _) => fallback,
      errorWidget: (_, _, _) => fallback,
    );
    final clipped = borderRadius == null
        ? ClipOval(child: image)
        : ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius!),
            child: image,
          );
    if (border == null) {
      return SizedBox(width: size, height: size, child: clipped);
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: borderRadius == null ? BoxShape.circle : BoxShape.rectangle,
        borderRadius:
            borderRadius == null ? null : BorderRadius.circular(borderRadius!),
        border: border,
      ),
      child: clipped,
    );
  }
}
