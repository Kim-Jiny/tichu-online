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
    text: { color: '#6A1B7A' },
  },
  banner_blossom: {
    version: 1,
    thumbnail: thumb('local_florist', '#E91E63', '#FCE4EC', '#F8BBD0', '#F48FB1'),
    preview: preview('#F7D6D0', '#F3E9E6'),
    text: { color: '#880E4F' },
  },
  banner_mint: {
    version: 1,
    thumbnail: thumb('spa', '#26A69A', '#E0F2F1', '#B2DFDB', '#80CBC4'),
    preview: preview('#CDEBD8', '#EFF8F2'),
    text: { color: '#004D40' },
  },
  banner_sunset_7d: {
    version: 1,
    thumbnail: thumb('wb_twilight', '#FF6F00', '#FFE0B2', '#FFCC80', '#FFB74D'),
    preview: preview('#FFC3A0', '#FFE5B4'),
    text: { color: '#BF360C' },
  },
  banner_ocean: {
    version: 1,
    thumbnail: thumb('waves', '#0277BD', '#E1F5FE', '#B3E5FC', '#4FC3F7'),
    preview: preview('#A2D2F2', '#D6EAFB'),
    text: { color: '#01579B' },
  },
  banner_forest: {
    version: 1,
    thumbnail: thumb('park', '#2E7D32', '#E8F5E9', '#C8E6C9', '#81C784'),
    preview: preview('#B4D9B0', '#E1EFD9'),
    text: { color: '#1B5E20' },
  },
  banner_lavender: {
    version: 1,
    thumbnail: thumb('local_florist', '#7B1FA2', '#F3E5F5', '#E1BEE7', '#BA68C8'),
    preview: preview('#DCC3E8', '#F1E5F5'),
    text: { color: '#4A148C' },
  },
  banner_aurora: {
    version: 1,
    thumbnail: thumb('auto_awesome', '#26A69A', '#C8E6C9', '#B2EBF2', '#90CAF9'),
    preview: preview('#C8E6C9', '#B3E5FC'),
    text: { color: '#006064' },
  },
  banner_galaxy: {
    version: 1,
    thumbnail: thumb('nights_stay', '#3F51B5', '#1A237E', '#283593', '#5C6BC0'),
    preview: preview('#3D4D8C', '#1F2A5A'),
    text: { color: '#FFFFFF' },
  },
  banner_sakura: {
    version: 1,
    thumbnail: thumb('filter_vintage', '#D81B60', '#FCE4EC', '#F8BBD0', '#F48FB1'),
    preview: preview('#F7CDD8', '#FAE6EB'),
    text: { color: '#880E4F' },
  },
  banner_coral: {
    version: 1,
    thumbnail: thumb('spa', '#FF7043', '#FFCCBC', '#FFAB91', '#FF8A65'),
    preview: preview('#FFB39A', '#FFD4C2'),
    text: { color: '#BF360C' },
  },
  banner_moonlight: {
    version: 1,
    thumbnail: thumb('ac_unit', '#5C6BC0', '#E8EAF6', '#C5CAE9', '#9FA8DA'),
    preview: preview('#C9CFE6', '#E8EBF7'),
    text: { color: '#283593' },
  },
  banner_ember: {
    version: 1,
    thumbnail: thumb('whatshot', '#D84315', '#FFCCBC', '#FF7043', '#BF360C'),
    preview: preview('#E89280', '#C25A3E'),
    text: { color: '#FFFFFF' },
  },
  banner_emerald: {
    version: 1,
    thumbnail: thumb('diamond', '#00897B', '#A7FFEB', '#64FFDA', '#1DE9B6'),
    preview: preview('#8FE5D0', '#C7F4E6'),
    text: { color: '#004D40' },
  },
  banner_season_gold: {
    version: 1,
    thumbnail: thumb('emoji_events', '#FF8F00', '#FFF8E1', '#FFECB3', '#FFD54F'),
    preview: preview('#FFE082', '#FFF3C0'),
    text: { color: '#6D4C00' },
  },
  banner_season_silver: {
    version: 1,
    thumbnail: thumb('emoji_events', '#78909C', '#ECEFF1', '#CFD8DC', '#B0BEC5'),
    preview: preview('#CFD8DC', '#F1F3F4'),
    text: { color: '#37474F' },
  },
  banner_season_bronze: {
    version: 1,
    thumbnail: thumb('emoji_events', '#8D6E63', '#EFEBE9', '#D7CCC8', '#BCAAA4'),
    preview: preview('#D7B59A', '#F4E8DC'),
    text: { color: '#4E342E' },
  },
  banner_sk_season_gold: {
    version: 1,
    thumbnail: thumb('anchor', '#FF8F00', '#FFF8E1', '#FFECB3', '#FFD54F'),
    preview: preview('#FFE082', '#FFF3C0'),
    text: { color: '#6D4C00' },
  },
  banner_sk_season_silver: {
    version: 1,
    thumbnail: thumb('anchor', '#78909C', '#ECEFF1', '#CFD8DC', '#B0BEC5'),
    preview: preview('#CFD8DC', '#F1F3F4'),
    text: { color: '#37474F' },
  },
  banner_sk_season_bronze: {
    version: 1,
    thumbnail: thumb('anchor', '#8D6E63', '#EFEBE9', '#D7CCC8', '#BCAAA4'),
    preview: preview('#D7B59A', '#F4E8DC'),
    text: { color: '#4E342E' },
  },
  banner_mighty_season_gold: {
    version: 1,
    thumbnail: thumb('military_tech', '#FF8F00', '#FFF8E1', '#FFECB3', '#FFD54F'),
    preview: preview('#FFE082', '#FFF3C0'),
    text: { color: '#6D4C00' },
  },
  banner_mighty_season_silver: {
    version: 1,
    thumbnail: thumb('military_tech', '#78909C', '#ECEFF1', '#CFD8DC', '#B0BEC5'),
    preview: preview('#CFD8DC', '#F1F3F4'),
    text: { color: '#37474F' },
  },
  banner_mighty_season_bronze: {
    version: 1,
    thumbnail: thumb('military_tech', '#8D6E63', '#EFEBE9', '#D7CCC8', '#BCAAA4'),
    preview: preview('#D7B59A', '#F4E8DC'),
    text: { color: '#4E342E' },
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

  // 개척자 배너 — 상점에 없는 영구 배너. 여러 단계의 그라디언트를 쓰므로
  // 두 색만 받는 linear()/preview() 헬퍼 대신 값을 그대로 적는다.
  // 어드민이 색을 고치면 metadata.visual 이 이미 존재하게 되어 이 값이
  // 다시 덮어쓰지 않는다 — backfillShopVisuals 참고.
  'banner_pio_champagne': {
    "text": {
      "color": "#7A5A2E"
    },
    "preview": {
      "background": {
        "kind": "gradient",
        "angle": 120,
        "stops": [
          {
            "at": 0,
            "color": "#F7EFE0"
          },
          {
            "at": 0.5,
            "color": "#EFD9B4"
          },
          {
            "at": 1,
            "color": "#F9F2E6"
          }
        ]
      }
    },
    "version": 1,
    "thumbnail": {
      "icon": "celebration",
      "iconColor": "#C9A85C",
      "background": {
        "kind": "gradient",
        "angle": 0,
        "stops": [
          {
            "at": 0,
            "color": "#F7EFE0"
          },
          {
            "at": 1,
            "color": "#EFD9B4"
          }
        ]
      },
      "borderColor": "#EFD9B4"
    }
  },
  'banner_pio_dawn': {
    "text": {
      "color": "#8A4A32"
    },
    "preview": {
      "background": {
        "kind": "gradient",
        "angle": 120,
        "stops": [
          {
            "at": 0,
            "color": "#FAE3D6"
          },
          {
            "at": 0.5,
            "color": "#FBF0DF"
          },
          {
            "at": 1,
            "color": "#E5EEF3"
          }
        ]
      }
    },
    "version": 1,
    "thumbnail": {
      "icon": "wb_twilight",
      "iconColor": "#D08A63",
      "background": {
        "kind": "gradient",
        "angle": 0,
        "stops": [
          {
            "at": 0,
            "color": "#FAE3D6"
          },
          {
            "at": 1,
            "color": "#E5EEF3"
          }
        ]
      },
      "borderColor": "#E5EEF3"
    }
  },
  'banner_pio_haze': {
    "text": {
      "color": "#3F4E7A"
    },
    "preview": {
      "background": {
        "kind": "gradient",
        "angle": 120,
        "stops": [
          {
            "at": 0,
            "color": "#E3ECF7"
          },
          {
            "at": 0.5,
            "color": "#E7E3F5"
          },
          {
            "at": 1,
            "color": "#F3EBF2"
          }
        ]
      }
    },
    "version": 1,
    "thumbnail": {
      "icon": "cloud",
      "iconColor": "#7C8CC4",
      "background": {
        "kind": "gradient",
        "angle": 0,
        "stops": [
          {
            "at": 0,
            "color": "#E3ECF7"
          },
          {
            "at": 1,
            "color": "#E7E3F5"
          }
        ]
      },
      "borderColor": "#E7E3F5"
    }
  },
  'banner_pio_pearl': {
    "text": {
      "color": "#5A4A6A"
    },
    "preview": {
      "background": {
        "kind": "gradient",
        "angle": 120,
        "stops": [
          {
            "at": 0,
            "color": "#F3E6EE"
          },
          {
            "at": 0.3333333333333333,
            "color": "#E6EEF6"
          },
          {
            "at": 0.6666666666666666,
            "color": "#E4F2EA"
          },
          {
            "at": 1,
            "color": "#F2ECDF"
          }
        ]
      }
    },
    "version": 1,
    "thumbnail": {
      "icon": "blur_on",
      "iconColor": "#9A86B0",
      "background": {
        "kind": "gradient",
        "angle": 0,
        "stops": [
          {
            "at": 0,
            "color": "#F3E6EE"
          },
          {
            "at": 1,
            "color": "#E4F2EA"
          }
        ]
      },
      "borderColor": "#E4F2EA"
    }
  },
  'banner_pio_sage': {
    "text": {
      "color": "#40573F"
    },
    "preview": {
      "background": {
        "kind": "gradient",
        "angle": 120,
        "stops": [
          {
            "at": 0,
            "color": "#F2EEE4"
          },
          {
            "at": 0.5,
            "color": "#DFE7D8"
          },
          {
            "at": 1,
            "color": "#EDF1E7"
          }
        ]
      }
    },
    "version": 1,
    "thumbnail": {
      "icon": "park",
      "iconColor": "#7A9678",
      "background": {
        "kind": "gradient",
        "angle": 0,
        "stops": [
          {
            "at": 0,
            "color": "#F2EEE4"
          },
          {
            "at": 1,
            "color": "#DFE7D8"
          }
        ]
      },
      "borderColor": "#DFE7D8"
    }
  },
  'banner_pioneer_deep': {
    "text": {
      "color": "#FFFFFF"
    },
    "preview": {
      "background": {
        "kind": "gradient",
        "angle": 120,
        "stops": [
          {
            "at": 0,
            "color": "#052E3E"
          },
          {
            "at": 0.5,
            "color": "#0E5A6B"
          },
          {
            "at": 1,
            "color": "#16897F"
          }
        ]
      }
    },
    "version": 1,
    "thumbnail": {
      "icon": "waves",
      "iconColor": "#0E5A6B",
      "background": {
        "kind": "gradient",
        "angle": 0,
        "stops": [
          {
            "at": 0,
            "color": "#052E3E"
          },
          {
            "at": 1,
            "color": "#16897F"
          }
        ]
      },
      "borderColor": "#16897F"
    }
  },
  'banner_pioneer_gilt': {
    "text": {
      "color": "#F0D9A7"
    },
    "preview": {
      "background": {
        "kind": "gradient",
        "angle": 120,
        "stops": [
          {
            "at": 0,
            "color": "#1C1C24"
          },
          {
            "at": 0.5,
            "color": "#2E2A34"
          },
          {
            "at": 1,
            "color": "#4A3B2A"
          }
        ]
      }
    },
    "version": 1,
    "thumbnail": {
      "icon": "workspace_premium",
      "iconColor": "#C9A85C",
      "background": {
        "kind": "gradient",
        "angle": 0,
        "stops": [
          {
            "at": 0,
            "color": "#1C1C24"
          },
          {
            "at": 1,
            "color": "#4A3B2A"
          }
        ]
      },
      "borderColor": "#4A3B2A"
    }
  },
  'banner_pioneer_iris': {
    "text": {
      "color": "#FFFFFF"
    },
    "preview": {
      "background": {
        "kind": "gradient",
        "angle": 120,
        "stops": [
          {
            "at": 0,
            "color": "#241B4A"
          },
          {
            "at": 0.3333333333333333,
            "color": "#6E2A7E"
          },
          {
            "at": 0.6666666666666666,
            "color": "#12707F"
          },
          {
            "at": 1,
            "color": "#B98A2E"
          }
        ]
      }
    },
    "version": 1,
    "thumbnail": {
      "icon": "auto_awesome",
      "iconColor": "#B98A2E",
      "background": {
        "kind": "gradient",
        "angle": 0,
        "stops": [
          {
            "at": 0,
            "color": "#241B4A"
          },
          {
            "at": 1,
            "color": "#B98A2E"
          }
        ]
      },
      "borderColor": "#B98A2E"
    }
  },
  'banner_pioneer_iris2': {
    "text": {
      "color": "#FFFFFF"
    },
    "preview": {
      "background": {
        "kind": "gradient",
        "angle": 120,
        "stops": [
          {
            "at": 0,
            "color": "#3A1C71"
          },
          {
            "at": 0.3333333333333333,
            "color": "#A33A9B"
          },
          {
            "at": 0.6666666666666666,
            "color": "#2E4BA8"
          },
          {
            "at": 1,
            "color": "#22A7C4"
          }
        ]
      }
    },
    "version": 1,
    "thumbnail": {
      "icon": "blur_on",
      "iconColor": "#A33A9B",
      "background": {
        "kind": "gradient",
        "angle": 0,
        "stops": [
          {
            "at": 0,
            "color": "#3A1C71"
          },
          {
            "at": 1,
            "color": "#22A7C4"
          }
        ]
      },
      "borderColor": "#22A7C4"
    }
  },
  'banner_pioneer_iris3': {
    "text": {
      "color": "#FFFFFF"
    },
    "preview": {
      "background": {
        "kind": "gradient",
        "angle": 120,
        "stops": [
          {
            "at": 0,
            "color": "#0C1E3E"
          },
          {
            "at": 0.3333333333333333,
            "color": "#14705F"
          },
          {
            "at": 0.6666666666666666,
            "color": "#2ECC9B"
          },
          {
            "at": 1,
            "color": "#7A4FBF"
          }
        ]
      }
    },
    "version": 1,
    "thumbnail": {
      "icon": "nights_stay",
      "iconColor": "#2ECC9B",
      "background": {
        "kind": "gradient",
        "angle": 0,
        "stops": [
          {
            "at": 0,
            "color": "#0C1E3E"
          },
          {
            "at": 1,
            "color": "#2ECC9B"
          }
        ]
      },
      "borderColor": "#2ECC9B"
    }
  },

  // 개척자 테마 썸네일. 색 자체는 클라이언트가 그리고, 여기는
  // 상점 카드에 보이는 아이콘과 배경만 담는다.
  theme_pio_deep: { version: 1, thumbnail: thumb('waves', '#2E7D74', '#E6F2F1', '#D3E9E6', '#2E7D74') },
  theme_pio_gilt: { version: 1, thumbnail: thumb('workspace_premium', '#8A6B2E', '#F2EFEA', '#E6DFD2', '#8A6B2E') },
  theme_pio_oilslick: { version: 1, thumbnail: thumb('auto_awesome', '#7A5A8E', '#EFE9F5', '#F5EFE2', '#7A5A8E') },
  theme_pio_nebula: { version: 1, thumbnail: thumb('blur_on', '#6A4FA8', '#EDE7F6', '#E0F2F6', '#6A4FA8') },
  theme_pio_aurora: { version: 1, thumbnail: thumb('nights_stay', '#2F8F72', '#E4F3EC', '#EDE7F6', '#2F8F72') },
  theme_pio_pearl: { version: 1, thumbnail: thumb('blur_on', '#9A86B0', '#F5EDF2', '#EDF5EF', '#9A86B0') },
  theme_pio_champagne: { version: 1, thumbnail: thumb('celebration', '#C9A85C', '#FAF3E6', '#F3E6CE', '#C9A85C') },
  theme_pio_haze: { version: 1, thumbnail: thumb('cloud', '#7C8CC4', '#EAF1F9', '#F4EEF5', '#7C8CC4') },
  theme_pio_sage: { version: 1, thumbnail: thumb('park', '#7A9678', '#F4F1E9', '#E6EDE1', '#7A9678') },
  theme_pio_dawn: { version: 1, thumbnail: thumb('wb_twilight', '#D08A63', '#FCEDE4', '#EDF3F7', '#D08A63') },
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
