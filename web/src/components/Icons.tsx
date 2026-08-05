/**
 * Header icons.
 *
 * The app uses Material Icons (store / people / leaderboard / menu_book_rounded
 * / settings, lobby_screen.dart:1603-1700). Rather than pull the Material
 * Symbols webfont in for five glyphs, these are hand-drawn equivalents at the
 * same 22px optical size and the same accent colours.
 *
 * Note for later: the shop's server-driven visuals *do* name Material icons
 * (shop_visuals_seed.js:12), so a subsetted Material Symbols font will be
 * needed when the shop lands. These five stay hand-drawn either way.
 */

type IconProps = { size?: number };

function Svg({ children }: { children: React.ReactNode }) {
  return (
    <svg
      viewBox="0 0 24 24"
      width="1em"
      height="1em"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {children}
    </svg>
  );
}

export function StoreIcon(_: IconProps) {
  return (
    <Svg>
      <path d="M4 4h16l1 4a3 3 0 0 1-6 0 3 3 0 0 1-6 0 3 3 0 0 1-6 0z" />
      <path d="M5 10v10h14V10" />
    </Svg>
  );
}

export function PeopleIcon(_: IconProps) {
  return (
    <Svg>
      <circle cx="9" cy="8" r="3.2" />
      <path d="M3 20c0-3.2 2.7-5 6-5s6 1.8 6 5" />
      <path d="M16.5 6.6a3 3 0 0 1 0 5.8" />
      <path d="M17.5 15.4c2.1.6 3.5 2.1 3.5 4.6" />
    </Svg>
  );
}

export function LeaderboardIcon(_: IconProps) {
  return (
    <Svg>
      <rect x="3.5" y="12" width="4.5" height="8" rx="1.2" />
      <rect x="9.8" y="5" width="4.5" height="15" rx="1.2" />
      <rect x="16.1" y="9" width="4.5" height="11" rx="1.2" />
    </Svg>
  );
}

export function BookIcon(_: IconProps) {
  return (
    <Svg>
      <path d="M12 6.5C10.5 5 8.4 4.4 4.5 4.4V18c3.9 0 6 .6 7.5 2.1" />
      <path d="M12 6.5c1.5-1.5 3.6-2.1 7.5-2.1V18c-3.9 0-6 .6-7.5 2.1" />
      <path d="M12 6.5v13.6" />
    </Svg>
  );
}

export function SettingsIcon(_: IconProps) {
  // Teeth come from a dashed outer ring rather than eight drawn spokes —
  // spokes with round caps read as a sun, not a cog.
  return (
    <Svg>
      <circle cx="12" cy="12" r="8.4" strokeWidth="4.2" strokeDasharray="3.2 4.4" />
      <circle cx="12" cy="12" r="6.2" strokeWidth="1.8" />
      <circle cx="12" cy="12" r="2.6" strokeWidth="1.8" />
    </Svg>
  );
}

export function RefreshIcon(_: IconProps) {
  return (
    <Svg>
      <path d="M20 12a8 8 0 1 1-2.6-5.9" />
      <path d="M20 4v4.5h-4.5" />
    </Svg>
  );
}

export function EyeIcon(_: IconProps) {
  return (
    <Svg>
      <path d="M2.5 12S6 6.5 12 6.5 21.5 12 21.5 12 18 17.5 12 17.5 2.5 12 2.5 12z" />
      <circle cx="12" cy="12" r="2.6" />
    </Svg>
  );
}
