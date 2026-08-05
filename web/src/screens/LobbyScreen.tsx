import { useEffect, useMemo, useState } from 'react';
import { AppHeader } from '../components/AppHeader';
import { EyeIcon, RefreshIcon } from '../components/Icons';
import type { GameType, RoomListEntry } from '../protocol/types';
import { useAppState, useStore } from '../state/useStore';

/**
 * Lobby, following lobby_screen.dart:1466.
 *
 * Same three bands as the app: header card, then the filter chips + refresh
 * row, then the room list, with the create-room button pinned to the bottom.
 * Colours are the app's — each game owns one hue used by both its filter chip
 * and the left strip and badge of its rows (lobby_screen.dart:2137).
 */

const GAMES: { type: GameType; label: string; color: string }[] = [
  { type: 'tichu', label: '티츄', color: '#64B5F6' },
  { type: 'mighty', label: '마이티', color: '#5C6BC0' },
  { type: 'skull_king', label: '스컬킹', color: '#21455F' },
  { type: 'love_letter', label: '러브레터', color: '#E91E63' },
];

const GAME_BY_TYPE = new Map(GAMES.map((g) => [g.type, g]));

export function LobbyScreen() {
  const state = useAppState();
  const store = useStore();
  const [creating, setCreating] = useState(false);
  const [hidden, setHidden] = useState<Set<GameType>>(new Set());

  useEffect(() => {
    store.refreshRooms();
  }, [store]);

  const rooms = useMemo(
    () => state.rooms.filter((room) => !hidden.has(room.gameType)),
    [state.rooms, hidden],
  );

  function toggleFilter(type: GameType) {
    setHidden((prev) => {
      const next = new Set(prev);
      if (next.has(type)) {
        next.delete(type);
        return next;
      }
      // The app keeps the last chip on: turning everything off can only ever
      // produce an empty list (lobby_screen.dart:2040).
      if (next.size < GAMES.length - 1) next.add(type);
      return next;
    });
  }

  return (
    <main className="screen screen--lobby">
      <AppHeader />

      {state.maintenance?.notice && state.maintenance.message ? (
        <p className="banner banner--maintenance">{state.maintenance.message}</p>
      ) : null}

      <section className="room-panel">
        <div className="room-panel__toolbar">
          <div className="filters">
            {GAMES.map(({ type, label, color }) => {
              const off = hidden.has(type);
              return (
                <button
                  key={type}
                  type="button"
                  className={off ? 'chip chip--off' : 'chip'}
                  style={{ '--tint': color } as React.CSSProperties}
                  aria-pressed={!off}
                  onClick={() => toggleFilter(type)}
                >
                  {label}
                </button>
              );
            })}
          </div>
          <button
            type="button"
            className="icon-plain"
            aria-label="새로고침"
            onClick={() => store.refreshRooms()}
          >
            <RefreshIcon />
          </button>
        </div>

        <div className="room-list">
          {rooms.length === 0 ? (
            <div className="room-list__empty">
              <span className="room-list__empty-mark" aria-hidden="true" />
              <p>열려 있는 방이 없습니다.</p>
            </div>
          ) : (
            rooms.map((room) => <RoomRow key={room.id} room={room} />)
          )}
        </div>

        <button type="button" className="btn-create" onClick={() => setCreating(true)}>
          방 만들기
        </button>
      </section>

      {creating ? <CreateRoomDialog onClose={() => setCreating(false)} /> : null}
    </main>
  );
}

function RoomRow({ room }: { room: RoomListEntry }) {
  const store = useStore();
  const [password, setPassword] = useState('');
  const [askingPassword, setAskingPassword] = useState(false);

  const game = GAME_BY_TYPE.get(room.gameType) ?? GAMES[0];
  const webPlayable = room.gameType === 'tichu';
  const full = room.playerCount >= room.effectiveMaxPlayers;

  function activate() {
    if (!webPlayable) {
      store.notImplemented(game.label);
      return;
    }
    if (room.gameInProgress) {
      store.notImplemented('관전');
      return;
    }
    if (full) return;
    if (room.isPrivate && !askingPassword) {
      setAskingPassword(true);
      return;
    }
    store.joinRoom(room.id, room.isPrivate ? password : undefined);
    setAskingPassword(false);
    setPassword('');
  }

  return (
    <div
      className={webPlayable ? 'room-row' : 'room-row room-row--other'}
      style={{ '--tint': game.color } as React.CSSProperties}
    >
      <span className="room-row__strip" aria-hidden="true" />
      <div className="room-row__body">
        <div className="room-row__main">
          <div className="room-row__title">
            <span className="room-badge">{game.label}</span>
            <span className="room-row__name">
              {room.isPrivate ? '🔒 ' : ''}
              {room.isRanked ? '🏆 ' : ''}
              {room.name}
            </span>
          </div>
          <div className="room-row__sub">
            {room.gameType === 'skull_king' || room.gameType === 'love_letter'
              ? `${room.turnTimeLimit}초`
              : `${room.turnTimeLimit}초 · ${room.targetScore}점`}
          </div>
        </div>

        {room.gameInProgress ? <span className="room-chip">게임중</span> : null}

        {room.allowSpectators ? (
          <button
            type="button"
            className="room-eye"
            aria-label="관전"
            onClick={() => store.notImplemented('관전')}
          >
            <EyeIcon />
            {room.spectatorCount > 0 ? <span>{room.spectatorCount}</span> : null}
          </button>
        ) : null}

        {askingPassword ? (
          <span className="room-row__password">
            <input
              type="password"
              placeholder="비밀번호"
              value={password}
              autoFocus
              onChange={(e) => setPassword(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') activate();
                if (e.key === 'Escape') setAskingPassword(false);
              }}
            />
            <button type="button" className="btn btn--primary btn--sm" onClick={activate}>
              입장
            </button>
          </span>
        ) : (
          <button
            type="button"
            className={full ? 'room-count room-count--full' : 'room-count'}
            onClick={activate}
          >
            {room.playerCount}/{room.effectiveMaxPlayers}
          </button>
        )}
      </div>
    </div>
  );
}

function CreateRoomDialog({ onClose }: { onClose: () => void }) {
  const store = useStore();
  const state = useAppState();
  const [roomName, setRoomName] = useState(`${state.auth?.nickname ?? ''}의 방`);
  const [password, setPassword] = useState('');
  const [turnTimeLimit, setTurnTimeLimit] = useState(30);
  const [targetScore, setTargetScore] = useState(1000);

  function submit(event: React.FormEvent) {
    event.preventDefault();
    store.createRoom({
      roomName: roomName.slice(0, 20),
      password,
      turnTimeLimit,
      targetScore,
    });
    onClose();
  }

  return (
    <div className="modal-backdrop" onClick={onClose} role="presentation">
      <div className="modal" onClick={(e) => e.stopPropagation()} role="dialog" aria-modal="true">
        <h2>티츄 방 만들기</h2>
        <form className="form" onSubmit={submit}>
          <label className="field">
            <span>방 이름 (최대 20자)</span>
            <input
              type="text"
              value={roomName}
              maxLength={20}
              onChange={(e) => setRoomName(e.target.value)}
              required
            />
          </label>
          <label className="field">
            <span>비밀번호 (선택)</span>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="비워두면 공개방"
            />
          </label>
          <label className="field">
            <span>턴 제한 {turnTimeLimit}초</span>
            <input
              type="range"
              min={10}
              max={120}
              step={5}
              value={turnTimeLimit}
              onChange={(e) => setTurnTimeLimit(Number(e.target.value))}
            />
          </label>
          <label className="field">
            <span>목표 점수</span>
            <select value={targetScore} onChange={(e) => setTargetScore(Number(e.target.value))}>
              {[400, 600, 800, 1000, 1500, 2000].map((score) => (
                <option key={score} value={score}>
                  {score}점
                </option>
              ))}
            </select>
          </label>
          <div className="modal__actions">
            <button type="button" className="btn btn--ghost" onClick={onClose}>
              취소
            </button>
            <button type="submit" className="btn btn--primary">
              만들기
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
