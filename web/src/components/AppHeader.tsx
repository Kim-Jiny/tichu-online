import { useState } from 'react';
import {
  BookIcon,
  LeaderboardIcon,
  PeopleIcon,
  SettingsIcon,
  StoreIcon,
} from './Icons';
import { useAppState, useStore } from '../state/useStore';

/**
 * The lobby header, matching lobby_screen.dart:1567 — a white rounded card with
 * the logo on the left and the same five tinted icon buttons on the right, in
 * the same order and colours.
 *
 * Shop / friends / ranking / rules are not built on the web yet. They are still
 * rendered, because leaving holes in the row would make the two clients read as
 * different products; tapping one says so rather than doing nothing.
 */

const ACTIONS = [
  { key: 'shop', label: '상점', color: '#FFB74D', Icon: StoreIcon },
  { key: 'friends', label: '친구', color: '#7E57C2', Icon: PeopleIcon },
  { key: 'ranking', label: '랭킹', color: '#81C784', Icon: LeaderboardIcon },
  { key: 'rules', label: '규칙', color: '#FF8A65', Icon: BookIcon },
] as const;

export function AppHeader() {
  const store = useStore();
  const state = useAppState();
  const [settingsOpen, setSettingsOpen] = useState(false);

  return (
    <header className="app-header">
      <img className="app-header__logo" src="logo2.png" alt="티츄 온라인" />

      <div className="app-header__actions">
        {ACTIONS.map(({ key, label, color, Icon }) => (
          <button
            key={key}
            type="button"
            className="icon-btn"
            style={{ '--tint': color } as React.CSSProperties}
            aria-label={label}
            title={label}
            onClick={() => store.notImplemented(label)}
          >
            <Icon />
          </button>
        ))}

        <span className="icon-btn-wrap">
          <button
            type="button"
            className="icon-btn"
            style={{ '--tint': '#9E9E9E' } as React.CSSProperties}
            aria-label="설정"
            title="설정"
            aria-expanded={settingsOpen}
            onClick={() => setSettingsOpen((v) => !v)}
          >
            <SettingsIcon />
          </button>
          {settingsOpen ? (
            <span className="popover">
              <span className="popover__title">{state.auth?.nickname}</span>
              <button
                type="button"
                className="btn btn--sm"
                onClick={() => {
                  setSettingsOpen(false);
                  store.logout();
                }}
              >
                로그아웃
              </button>
            </span>
          ) : null}
        </span>
      </div>
    </header>
  );
}
