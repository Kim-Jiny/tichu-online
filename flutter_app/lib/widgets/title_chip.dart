import 'package:flutter/material.dart';

/// Compact icon + name chip for player titles (칭호). Used in waiting room
/// slots and elsewhere so the title styling stays consistent across screens.
/// Returns `SizedBox.shrink()` when titleName is null or empty.
class TitleChip extends StatelessWidget {
  final String? titleKey;
  final String? titleName;
  final double fontSize;
  final double iconSize;
  final FontWeight fontWeight;

  /// The colour that reads against whatever is behind this chip — the
  /// banner's text colour, or null on the app's normal cream.
  final Color? onInk;

  const TitleChip({
    super.key,
    required this.titleKey,
    required this.titleName,
    this.fontSize = 11,
    this.iconSize = 11,
    this.fontWeight = FontWeight.w600,
    this.onInk,
  });

  @override
  Widget build(BuildContext context) {
    final name = titleName;
    if (name == null || name.isEmpty) return const SizedBox.shrink();
    final color = titleColorFor(titleKey, onInk: onInk);
    // A user-written title carries no icon: the catalog icons say "this is one
    // of ours", and a self-chosen title must not be able to borrow that.
    final custom = isCustomTitleKey(titleKey);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!custom) Icon(titleIconFor(titleKey), size: iconSize, color: color),
        if (!custom) const SizedBox(width: 3),
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: fontSize,
              color: color,
              fontWeight: fontWeight,
            ),
          ),
        ),
      ],
    );
  }
}

IconData titleIconFor(String? titleKey) {
  switch (titleKey) {
    case 'title_sweet':
      return Icons.cake;
    case 'title_steady':
      return Icons.shield;
    case 'title_flash_30d':
      return Icons.flash_on;
    case 'title_dragon':
      return Icons.local_fire_department;
    case 'title_phoenix':
      return Icons.local_fire_department;
    case 'title_pirate':
      return Icons.anchor;
    case 'title_tactician':
      return Icons.psychology;
    case 'title_lucky':
      return Icons.star;
    case 'title_bluffer':
      return Icons.theater_comedy;
    case 'title_ace':
      return Icons.military_tech;
    case 'title_king':
      return Icons.workspace_premium;
    case 'title_rookie':
      return Icons.emoji_nature;
    case 'title_veteran':
      return Icons.security;
    case 'title_sensitive':
      return Icons.sentiment_very_dissatisfied;
    case 'title_shadow':
      return Icons.visibility_off;
    case 'title_flame':
      return Icons.whatshot;
    case 'title_ice':
      return Icons.ac_unit;
    case 'title_crown':
      return Icons.diamond;
    case 'title_diamond':
      return Icons.diamond;
    case 'title_ghost':
      return Icons.blur_on;
    case 'title_thunder':
      return Icons.bolt;
    case 'title_topcard':
      return Icons.style;
    case 'title_legend':
      return Icons.auto_awesome;
    case 'title_boomer':
      return Icons.elderly;
    default:
      return Icons.star;
  }
}

/// Custom titles are worn as `custom:<palette id>` in the same slot as catalog
/// titles, so no payload needed a new field for them.
bool isCustomTitleKey(String? titleKey) =>
    titleKey != null && titleKey.startsWith('custom:');

/// The palette the server accepts. Ids, not free colour: a free colour can be
/// the background colour, and an invisible title is not a title.
const Map<String, Color> customTitleColors = {
  'rose': Color(0xFFD64550),
  'amber': Color(0xFFC97A0B),
  'green': Color(0xFF2E7D32),
  'teal': Color(0xFF00796B),
  'blue': Color(0xFF1565C0),
  'violet': Color(0xFF6A3FB5),
  'pink': Color(0xFFC2185B),
  'slate': Color(0xFF455A64),
};

/// The colour a title is drawn in.
///
/// [onInk] is the colour that reads against whatever is behind it — pass the
/// banner's text colour, or null on the app's normal cream. Every title colour
/// was chosen against cream, so a dark banner swallows the darker half of them
/// (the near-black pirate, the deep teal tactician) while the palette itself
/// stays perfectly good on every other surface.
///
/// Lightened rather than replaced. The colour is how a title is recognised —
/// forcing them all to white would make twenty titles look like one.
Color titleColorFor(String? titleKey, {Color? onInk}) {
  final base = _titleBaseColor(titleKey);
  // onInk light means the background is dark. Anything else — including no
  // banner at all — keeps the palette as designed.
  if (onInk == null || onInk.computeLuminance() < 0.5) return base;
  return lightenForDarkBackground(base);
}

/// Raise a colour until it reads on a dark fill, keeping its hue.
///
/// The decision is made on LUMINANCE, not on HSL lightness. They disagree
/// badly on saturated hues: pure yellow has an HSL lightness of 0.5 and looks
/// dim by that measure, while being one of the brightest colours there is.
/// Judging by lightness washed the yellow lucky star out to cream for no
/// reason.
///
/// The lift itself walks HSL lightness up, because that is what preserves the
/// hue. It stops as soon as the colour is bright enough, so a title only moves
/// as far as it has to — and re-applying it changes nothing, which matters
/// because the same colour passes through here on every rebuild.
Color lightenForDarkBackground(Color base) {
  if (base.computeLuminance() >= _minLuminanceOnDark) return base;
  var hsl = HSLColor.fromColor(base);
  // Very dark colours are often near-grey; a little saturation keeps them from
  // lifting into a flat white.
  if (hsl.saturation < 0.25) hsl = hsl.withSaturation(0.25);
  for (var l = hsl.lightness; l <= 0.92; l += 0.02) {
    final candidate = hsl.withLightness(l).toColor();
    if (candidate.computeLuminance() >= _minLuminanceOnDark) return candidate;
  }
  return hsl.withLightness(0.92).toColor();
}

/// Enough to read comfortably on the darkest banner in the catalogue. Not so
/// high that everything converges on white — the colours still have to tell
/// twenty titles apart.
const double _minLuminanceOnDark = 0.35;

Color _titleBaseColor(String? titleKey) {
  if (isCustomTitleKey(titleKey)) {
    return customTitleColors[titleKey!.substring('custom:'.length)] ??
        const Color(0xFF5A4038);
  }
  switch (titleKey) {
    case 'title_sweet':
      return const Color(0xFFEC407A);
    case 'title_steady':
      return const Color(0xFF5C6BC0);
    case 'title_flash_30d':
      return const Color(0xFFFFA000);
    case 'title_dragon':
      return const Color(0xFFD32F2F);
    case 'title_phoenix':
      return const Color(0xFFFF6F00);
    case 'title_pirate':
      return const Color(0xFF37474F);
    case 'title_tactician':
      return const Color(0xFF00695C);
    case 'title_lucky':
      return const Color(0xFFFFD600);
    case 'title_bluffer':
      return const Color(0xFF6A1B9A);
    case 'title_ace':
      return const Color(0xFFC62828);
    case 'title_king':
      return const Color(0xFFFF8F00);
    case 'title_rookie':
      return const Color(0xFF66BB6A);
    case 'title_veteran':
      return const Color(0xFF1565C0);
    case 'title_sensitive':
      return const Color(0xFFE91E63);
    case 'title_shadow':
      return const Color(0xFF424242);
    case 'title_flame':
      return const Color(0xFFFF5722);
    case 'title_ice':
      return const Color(0xFF0288D1);
    case 'title_crown':
      return const Color(0xFFE65100);
    case 'title_diamond':
      return const Color(0xFF00BCD4);
    case 'title_ghost':
      return const Color(0xFF78909C);
    case 'title_thunder':
      return const Color(0xFFFFAB00);
    case 'title_topcard':
      return const Color(0xFF00897B);
    case 'title_legend':
      return const Color(0xFFFF6D00);
    case 'title_boomer':
      return const Color(0xFF795548);
    default:
      return const Color(0xFF7E57C2);
  }
}
