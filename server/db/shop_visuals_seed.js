// Visual backfill data for tc_shop_items.metadata.visual.
//
// Schema (versioned for forward compat — includes a `kind: 'gradient' | 'solid'
// | 'image'` discriminator so admin-uploaded images can slot into the same
// background field without breaking parsers later):
//
// {
//   "version": 1,
//   "thumbnail": {                        // shop card preview
//     "icon": "auto_awesome",             // Material icon name (Flutter Icons.<name>)
//     "iconColor": "#D4A0C0",
//     "borderColor": "#F8BBD0",
//     "background": Background
//   },
//   "preview": {                           // optional: in-game render override
//     "background": Background
//   },
//   "text": {                              // optional: titles
//     "color": "#FFFFFF"
//   }
// }
//
// Background =
//   { "kind": "gradient", "angle": 0, "stops": [{"color": "#xxx", "at": 0.0}, ...] }
//   | { "kind": "solid", "color": "#xxx" }
//   | { "kind": "image", "url": "https://...", "fit": "cover" }   // future
//
// Values below are extracted verbatim from the Flutter hardcoded switches
// (shop_screen.dart _thumbnailStyleByKey, game_screen.dart _bannerStyle).
// Once admin can edit visuals (Phase 2), this file becomes a one-shot seed:
// it only runs for rows whose metadata.visual is missing, so admin edits
// are never overwritten.

const linear = (c1, c2) => ({
  kind: 'gradient',
  angle: 0,
  stops: [
    { color: c1, at: 0.0 },
    { color: c2, at: 1.0 },
  ],
});

const thumb = (icon, iconColor, c1, c2, borderColor) => ({
  icon,
  iconColor,
  borderColor,
  background: linear(c1, c2),
});

const preview = (c1, c2) => ({ background: linear(c1, c2) });

const VISUAL_BACKFILL = {
  // ===== Banners =====
  banner_pastel: {
    version: 1,
    thumbnail: thumb('auto_awesome', '#D4A0C0', '#FCE4EC', '#F3E5F5', '#F8BBD0'),
    preview: preview('#F6C1C9', '#F3E7EA'),
  },
  banner_blossom: {
    version: 1,
    thumbnail: thumb('local_florist', '#E91E63', '#FCE4EC', '#F8BBD0', '#F48FB1'),
    preview: preview('#F7D6D0', '#F3E9E6'),
  },
  banner_mint: {
    version: 1,
    thumbnail: thumb('spa', '#26A69A', '#E0F2F1', '#B2DFDB', '#80CBC4'),
    preview: preview('#CDEBD8', '#EFF8F2'),
  },
  banner_sunset_7d: {
    version: 1,
    thumbnail: thumb('wb_twilight', '#FF6F00', '#FFE0B2', '#FFCC80', '#FFB74D'),
    preview: preview('#FFC3A0', '#FFE5B4'),
  },
  banner_season_gold: {
    version: 1,
    thumbnail: thumb('emoji_events', '#FF8F00', '#FFF8E1', '#FFECB3', '#FFD54F'),
    preview: preview('#FFE082', '#FFF3C0'),
  },
  banner_season_silver: {
    version: 1,
    thumbnail: thumb('emoji_events', '#78909C', '#ECEFF1', '#CFD8DC', '#B0BEC5'),
    preview: preview('#CFD8DC', '#F1F3F4'),
  },
  banner_season_bronze: {
    version: 1,
    thumbnail: thumb('emoji_events', '#8D6E63', '#EFEBE9', '#D7CCC8', '#BCAAA4'),
    preview: preview('#D7B59A', '#F4E8DC'),
  },

  // ===== Titles =====
  title_sweet:    { version: 1, thumbnail: thumb('cake',                     '#EC407A', '#FCE4EC', '#F8BBD0', '#F48FB1') },
  title_steady:   { version: 1, thumbnail: thumb('shield',                   '#5C6BC0', '#E8EAF6', '#C5CAE9', '#9FA8DA') },
  title_flash_30d:{ version: 1, thumbnail: thumb('flash_on',                 '#FFA000', '#FFF8E1', '#FFECB3', '#FFD54F') },
  title_dragon:   { version: 1, thumbnail: thumb('local_fire_department',    '#D32F2F', '#FFEBEE', '#FFCDD2', '#EF9A9A') },
  title_phoenix:  { version: 1, thumbnail: thumb('local_fire_department',    '#FF6F00', '#FFF3E0', '#FFE0B2', '#FFCC80') },
  title_pirate:   { version: 1, thumbnail: thumb('anchor',                   '#37474F', '#ECEFF1', '#CFD8DC', '#90A4AE') },
  title_tactician:{ version: 1, thumbnail: thumb('psychology',               '#00695C', '#E0F2F1', '#B2DFDB', '#80CBC4') },
  title_lucky:    { version: 1, thumbnail: thumb('star',                     '#FFD600', '#FFFDE7', '#FFF9C4', '#FFF176') },
  title_bluffer:  { version: 1, thumbnail: thumb('theater_comedy',           '#6A1B9A', '#F3E5F5', '#E1BEE7', '#CE93D8') },
  title_ace:      { version: 1, thumbnail: thumb('military_tech',            '#C62828', '#FFEBEE', '#FFCDD2', '#EF9A9A') },
  title_king:     { version: 1, thumbnail: thumb('workspace_premium',        '#FF8F00', '#FFF8E1', '#FFE082', '#FFD54F') },
  title_rookie:   { version: 1, thumbnail: thumb('emoji_nature',             '#66BB6A', '#E8F5E9', '#C8E6C9', '#A5D6A7') },
  title_veteran:  { version: 1, thumbnail: thumb('security',                 '#1565C0', '#E3F2FD', '#BBDEFB', '#90CAF9') },
  title_sensitive:{ version: 1, thumbnail: thumb('sentiment_very_dissatisfied','#E91E63', '#FCE4EC', '#F8BBD0', '#F48FB1') },
  title_shadow:   { version: 1, thumbnail: thumb('visibility_off',           '#424242', '#F5F5F5', '#E0E0E0', '#BDBDBD') },
  title_flame:    { version: 1, thumbnail: thumb('whatshot',                 '#FF5722', '#FBE9E7', '#FFCCBC', '#FF8A65') },
  title_ice:      { version: 1, thumbnail: thumb('ac_unit',                  '#0288D1', '#E1F5FE', '#B3E5FC', '#81D4FA') },
  title_crown:    { version: 1, thumbnail: thumb('diamond',                  '#E65100', '#FFF3E0', '#FFE0B2', '#FFB74D') },
  title_diamond:  { version: 1, thumbnail: thumb('diamond',                  '#00BCD4', '#E0F7FA', '#B2EBF2', '#80DEEA') },
  title_ghost:    { version: 1, thumbnail: thumb('blur_on',                  '#78909C', '#ECEFF1', '#CFD8DC', '#B0BEC5') },
  title_thunder:  { version: 1, thumbnail: thumb('bolt',                     '#FFAB00', '#FFF8E1', '#FFECB3', '#FFD54F') },
  title_topcard:  { version: 1, thumbnail: thumb('style',                    '#00897B', '#E0F2F1', '#B2DFDB', '#80CBC4') },
  title_legend:   { version: 1, thumbnail: thumb('auto_awesome',             '#FF6D00', '#FFF3E0', '#FFE0B2', '#FFAB40') },
  title_boomer:   { version: 1, thumbnail: thumb('elderly',                  '#795548', '#EFEBE9', '#D7CCC8', '#BCAAA4') },

  // ===== Themes =====
  theme_cotton:       { version: 1, thumbnail: thumb('cloud',          '#90A4AE', '#F5F5F5', '#E0E0E0', '#BDBDBD') },
  theme_sky:          { version: 1, thumbnail: thumb('wb_sunny',       '#42A5F5', '#E3F2FD', '#BBDEFB', '#90CAF9') },
  theme_mocha_30d:    { version: 1, thumbnail: thumb('coffee',         '#6D4C41', '#EFEBE9', '#D7CCC8', '#BCAAA4') },
  theme_lavender:     { version: 1, thumbnail: thumb('local_florist',  '#9C27B0', '#F3E5F5', '#E1BEE7', '#CE93D8') },
  theme_cherry:       { version: 1, thumbnail: thumb('filter_vintage', '#E91E63', '#FCE4EC', '#F8BBD0', '#F48FB1') },
  theme_midnight:     { version: 1, thumbnail: thumb('nights_stay',    '#303F9F', '#E8EAF6', '#C5CAE9', '#9FA8DA') },
  theme_sunset:       { version: 1, thumbnail: thumb('wb_twilight',    '#F57C00', '#FFF3E0', '#FFE0B2', '#FFCC80') },
  theme_forest:       { version: 1, thumbnail: thumb('park',           '#2E7D32', '#E8F5E9', '#C8E6C9', '#A5D6A7') },
  theme_rose:         { version: 1, thumbnail: thumb('spa',            '#D4A08A', '#FBE9E7', '#FFCCBC', '#FFAB91') },
  theme_ocean:        { version: 1, thumbnail: thumb('waves',          '#0097A7', '#E0F7FA', '#B2EBF2', '#80DEEA') },
  theme_aurora:       { version: 1, thumbnail: thumb('auto_awesome',   '#26A69A', '#E0F7FA', '#E8F5E9', '#80CBC4') },
  theme_mintchoco_30d:{ version: 1, thumbnail: thumb('icecream',       '#00897B', '#E0F2F1', '#B2DFDB', '#80CBC4') },
  theme_peach_30d:    { version: 1, thumbnail: thumb('brightness_7',   '#FF8A65', '#FFF3E0', '#FFCCBC', '#FFAB91') },

  // ===== Utility (shop card visual only; effect logic unchanged) =====
  leave_reduce_1:            { version: 1, thumbnail: thumb('healing',          '#66BB6A', '#E8F5E9', '#C8E6C9', '#A5D6A7') },
  leave_reduce_3:            { version: 1, thumbnail: thumb('local_hospital',   '#43A047', '#E8F5E9', '#A5D6A7', '#81C784') },
  leave_reset:               { version: 1, thumbnail: thumb('handyman',         '#B46B00', '#FFF3E0', '#FFE0B2', '#FFB74D') },
  nickname_change:           { version: 1, thumbnail: thumb('handyman',         '#B46B00', '#FFF3E0', '#FFE0B2', '#FFB74D') },
  top_card_counter_7d:       { version: 1, thumbnail: thumb('analytics',        '#5C6BC0', '#E8EAF6', '#C5CAE9', '#9FA8DA') },
  stats_reset:               { version: 1, thumbnail: thumb('restart_alt',      '#757575', '#F5F5F5', '#E0E0E0', '#BDBDBD') },
  season_stats_reset:        { version: 1, thumbnail: thumb('emoji_events',     '#7B1FA2', '#F3E5F5', '#CE93D8', '#BA68C8') },
  tichu_season_stats_reset:  { version: 1, thumbnail: thumb('emoji_events',     '#355D89', '#E3F2FD', '#BBDEFB', '#90CAF9') },
  sk_season_stats_reset:     { version: 1, thumbnail: thumb('emoji_events',     '#424242', '#ECEFF1', '#B0BEC5', '#90A4AE') },
  mighty_season_stats_reset: { version: 1, thumbnail: thumb('emoji_events',     '#1565C0', '#E1F5FE', '#B3E5FC', '#81D4FA') },
  mighty_trump_counter_7d:   { version: 1, thumbnail: thumb('analytics',        '#5C6BC0', '#E8EAF6', '#C5CAE9', '#9FA8DA') },
  mighty_prev_trick_7d:      { version: 1, thumbnail: thumb('analytics',        '#5C6BC0', '#E8EAF6', '#C5CAE9', '#9FA8DA') },
};

// Default visual per category — used as a render fallback when an item has
// no metadata.visual at all. Mirrors shop_screen.dart's category fallback.
const CATEGORY_DEFAULTS = {
  banner:  { version: 1, thumbnail: thumb('flag',     '#B24B5A', '#F6C1C9', '#F3E7EA', '#E6DDD8') },
  title:   { version: 1, thumbnail: thumb('badge',    '#6B5CA5', '#D9D0F2', '#F1ECFA', '#E6DDD8') },
  theme:   { version: 1, thumbnail: thumb('palette',  '#3A7D5C', '#CDEBD8', '#EFF8F2', '#E6DDD8') },
  utility: { version: 1, thumbnail: thumb('handyman', '#B46B00', '#FFF3E0', '#FFE0B2', '#FFB74D') },
};

module.exports = { VISUAL_BACKFILL, CATEGORY_DEFAULTS };
