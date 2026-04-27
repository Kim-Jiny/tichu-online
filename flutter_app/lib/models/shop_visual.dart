import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Server-driven visual config for a shop item, parsed from
/// `item['metadata']['visual']`. Schema mirrors
/// `server/db/shop_visuals_seed.js`.
///
/// Render call sites should follow a fallback chain:
///   1. ShopVisual.fromItemMap(item)        -> server config if present
///   2. existing hardcoded switch in screens (legacy items)
///   3. ShopVisual.categoryDefault(category) -> generic per-category default
///
/// New items added by admin only have (1). Items shipped with the v2.3.0+26
/// app exist in (2) and (1) — server backfill duplicates them so admin can
/// override. (3) is the safety net for unknown keys / unrecognized icon
/// names so the UI never renders blank.
class ShopVisual {
  final ShopVisualLayer? thumbnail;
  final ShopVisualLayer? preview;
  final Color? textColor;

  const ShopVisual({this.thumbnail, this.preview, this.textColor});

  static ShopVisual? fromItemMap(Map<String, dynamic>? item) {
    if (item == null) return null;
    final meta = item['metadata'];
    if (meta is! Map) return null;
    final raw = meta['visual'];
    if (raw is! Map) return null;
    return _fromVisualJson(Map<String, dynamic>.from(raw));
  }

  static ShopVisual _fromVisualJson(Map<String, dynamic> json) {
    return ShopVisual(
      thumbnail: ShopVisualLayer._fromJson(json['thumbnail']),
      preview: ShopVisualLayer._fromJson(json['preview']),
      textColor: json['text'] is Map
          ? _parseColor((json['text'] as Map)['color'])
          : null,
    );
  }

  /// Convert the thumbnail layer back to the legacy render-map shape used by
  /// the existing UI code (`{icon, iconColor, gradient: [c1, c2], borderColor}`).
  /// Returns null if no usable thumbnail config exists, so callers can fall
  /// through to the next step in the fallback chain.
  Map<String, Object>? thumbnailLegacyMap() => thumbnail?._toLegacyMap();

  /// In-game preview gradient if explicitly defined, otherwise falls back to
  /// the thumbnail gradient so banners that don't define a separate preview
  /// still render with their card colors.
  LinearGradient? previewGradient() {
    final pBg = preview?._background;
    if (pBg is _GradientBg) return pBg.toLinearGradient();
    final tBg = thumbnail?._background;
    if (tBg is _GradientBg) return tBg.toLinearGradient();
    return null;
  }

  static Map<String, Object> categoryDefault(String? category) {
    switch (category) {
      case 'banner':
        return _legacyMap(Icons.flag, const Color(0xFFB24B5A),
            const [Color(0xFFF6C1C9), Color(0xFFF3E7EA)],
            const Color(0xFFE6DDD8));
      case 'title':
        return _legacyMap(Icons.badge, const Color(0xFF6B5CA5),
            const [Color(0xFFD9D0F2), Color(0xFFF1ECFA)],
            const Color(0xFFE6DDD8));
      case 'theme':
        return _legacyMap(Icons.palette, const Color(0xFF3A7D5C),
            const [Color(0xFFCDEBD8), Color(0xFFEFF8F2)],
            const Color(0xFFE6DDD8));
      case 'utility':
      default:
        return _legacyMap(Icons.handyman, const Color(0xFFB46B00),
            const [Color(0xFFFFF3E0), Color(0xFFFFE0B2)],
            const Color(0xFFFFB74D));
    }
  }
}

class ShopVisualLayer {
  final IconData? icon;
  final Color? iconColor;
  final Color? borderColor;
  final _Background? _background;

  // ignore: library_private_types_in_public_api
  const ShopVisualLayer({this.icon, this.iconColor, this.borderColor, _Background? background})
      : _background = background;

  static ShopVisualLayer? _fromJson(dynamic json) {
    if (json is! Map) return null;
    final m = Map<String, dynamic>.from(json);
    return ShopVisualLayer(
      icon: _resolveIcon(m['icon']),
      iconColor: _parseColor(m['iconColor']),
      borderColor: _parseColor(m['borderColor']),
      background: _Background._fromJson(m['background']),
    );
  }

  Map<String, Object>? _toLegacyMap() {
    final i = icon;
    final ic = iconColor;
    final bg = _background;
    if (i == null && ic == null && bg == null) return null;
    final out = <String, Object>{};
    if (i != null) out['icon'] = i;
    if (ic != null) out['iconColor'] = ic;
    if (borderColor != null) out['borderColor'] = borderColor!;
    if (bg is _GradientBg) {
      out['gradient'] = bg.colors;
    } else if (bg is _SolidBg) {
      out['gradient'] = [bg.color, bg.color];
    }
    return out;
  }
}

abstract class _Background {
  static _Background? _fromJson(dynamic json) {
    if (json is! Map) return null;
    final m = Map<String, dynamic>.from(json);
    final kind = m['kind'];
    if (kind == 'solid') {
      final c = _parseColor(m['color']);
      if (c == null) return null;
      return _SolidBg(c);
    }
    if (kind == 'gradient') {
      final stops = m['stops'];
      if (stops is! List || stops.isEmpty) return null;
      final colors = <Color>[];
      for (final s in stops) {
        if (s is! Map) continue;
        final c = _parseColor(s['color']);
        if (c != null) colors.add(c);
      }
      if (colors.length < 2) return null;
      final angle = (m['angle'] is num) ? (m['angle'] as num).toDouble() : 0.0;
      return _GradientBg(colors, angle);
    }
    return null;
  }
}

class _SolidBg extends _Background {
  final Color color;
  _SolidBg(this.color);
}

class _GradientBg extends _Background {
  final List<Color> colors;
  final double angleDeg;
  _GradientBg(this.colors, this.angleDeg);

  LinearGradient toLinearGradient() {
    if (angleDeg == 0) {
      return LinearGradient(colors: colors);
    }
    // 0deg = top→bottom in our admin form (matches CSS-like intuition).
    final rad = angleDeg * math.pi / 180.0;
    final dx = math.sin(rad);
    final dy = -math.cos(rad);
    return LinearGradient(
      begin: Alignment(-dx, -dy),
      end: Alignment(dx, dy),
      colors: colors,
    );
  }
}

Color? _parseColor(dynamic raw) {
  if (raw is! String) return null;
  var s = raw.trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 6) s = 'FF$s';
  if (s.length != 8) return null;
  final n = int.tryParse(s, radix: 16);
  if (n == null) return null;
  return Color(n);
}

Map<String, Object> _legacyMap(IconData icon, Color iconColor, List<Color> gradient, Color borderColor) {
  return {
    'icon': icon,
    'iconColor': iconColor,
    'gradient': gradient,
    'borderColor': borderColor,
  };
}

/// Maps the icon name strings the admin UI exposes to Flutter IconData. Add
/// a new entry here whenever the admin allows-list (`SHOP_VISUAL_ICONS` in
/// `server/admin.js`) gains a new icon — otherwise the resolver returns
/// null and the screen falls through to its legacy switch / category default.
IconData? _resolveIcon(dynamic raw) {
  if (raw is! String) return null;
  switch (raw) {
    case 'auto_awesome': return Icons.auto_awesome;
    case 'local_florist': return Icons.local_florist;
    case 'spa': return Icons.spa;
    case 'wb_twilight': return Icons.wb_twilight;
    case 'emoji_events': return Icons.emoji_events;
    case 'cake': return Icons.cake;
    case 'shield': return Icons.shield;
    case 'flash_on': return Icons.flash_on;
    case 'local_fire_department': return Icons.local_fire_department;
    case 'anchor': return Icons.anchor;
    case 'psychology': return Icons.psychology;
    case 'star': return Icons.star;
    case 'theater_comedy': return Icons.theater_comedy;
    case 'military_tech': return Icons.military_tech;
    case 'workspace_premium': return Icons.workspace_premium;
    case 'emoji_nature': return Icons.emoji_nature;
    case 'security': return Icons.security;
    case 'sentiment_very_dissatisfied': return Icons.sentiment_very_dissatisfied;
    case 'visibility_off': return Icons.visibility_off;
    case 'whatshot': return Icons.whatshot;
    case 'ac_unit': return Icons.ac_unit;
    case 'diamond': return Icons.diamond;
    case 'blur_on': return Icons.blur_on;
    case 'bolt': return Icons.bolt;
    case 'style': return Icons.style;
    case 'elderly': return Icons.elderly;
    case 'cloud': return Icons.cloud;
    case 'wb_sunny': return Icons.wb_sunny;
    case 'coffee': return Icons.coffee;
    case 'filter_vintage': return Icons.filter_vintage;
    case 'nights_stay': return Icons.nights_stay;
    case 'park': return Icons.park;
    case 'waves': return Icons.waves;
    case 'icecream': return Icons.icecream;
    case 'brightness_7': return Icons.brightness_7;
    case 'healing': return Icons.healing;
    case 'local_hospital': return Icons.local_hospital;
    case 'analytics': return Icons.analytics;
    case 'restart_alt': return Icons.restart_alt;
    case 'handyman': return Icons.handyman;
    case 'flag': return Icons.flag;
    case 'badge': return Icons.badge;
    case 'palette': return Icons.palette;
    case 'card_giftcard': return Icons.card_giftcard;
    case 'celebration': return Icons.celebration;
    case 'verified': return Icons.verified;
    case 'rocket_launch': return Icons.rocket_launch;
    case 'pets': return Icons.pets;
    default: return null;
  }
}
