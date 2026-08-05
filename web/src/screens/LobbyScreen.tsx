import { useEffect, useMemo, useState } from 'react';
import type { RoomListEntry } from '../protocol/types';
import { useAppState, useStore } from '../state/useStore';

const GAME_LABELS: Record<string, string> = {
  tichu: '티츄',
  skull_king: '스컬킹',
  love_letter: '러브레터',
  mighty: '마이티',
};

export function LobbyScreen() {
  const state = useAppState();
  const store = useStore();
  const [creating, setCreating] = useState(false);
  const [showOtherGames, setShowOtherGames] = useState(false);

  useEffect(() => {
    store.refreshRooms();
  }, [store]);

  const [tichuRooms, otherRooms] = useMemo(() => {
    const tichu: RoomListEntry[] = [];
    const other: RoomListEntry[] = [];
    for (const room of state.rooms) {
      (room.gameType === 'tichu' ? tichu : other).push(room);
    }
    return [tichu, other];
  }, [state.rooms]);

  return (
    <main className="screen screen--lobby">
      <header className="lobby-header">
        <div>
          <h1>로비</h1>
          <p className="muted">{state.auth?.nickname}님 환영합니다</p>
        </div>
        <div className="lobby-header__actions">
          <button type="button" className="btn" onClick={() => store.refreshRooms()}>
            새로고침
          </button>
          <button type="button" className="btn btn--primary" onClick={() => setCreating(true)}>
            방 만들기
          </button>
          <button type="button" className="btn btn--ghost" onClick={() => store.logout()}>
            로그아웃
          </button>
        </div>
      </header>

      <section className="room-list">
        {tichuRooms.length === 0 ? (
          <p className="empty">열려 있는 티츄 방이 없습니다. 방을 만들어 보세요.</p>
        ) : (
          tichuRooms.map((room) => <RoomRow key={room.id} room={room} />)
        )}
      </section>

      {otherRooms.length > 0 ? (
        <section className="room-list room-list--muted">
          <button
            type="button"
            className="disclosure"
            onClick={() => setShowOtherGames((v) => !v)}
            aria-expanded={showOtherGames}
          >
            {showOtherGames ? '▾' : '▸'} 다른 게임 방 {otherRooms.length}개 (앱 전용)
          </button>
          {showOtherGames
            ? otherRooms.map((room) => (
                <div key={room.id} className="room-row room-row--disabled">
                  <span className="room-row__name">{room.name}</span>
                  <span className="badge">{GAME_LABELS[room.gameType] ?? room.gameType}</span>
                  <span className="muted">
                    {room.playerCount}/{room.effectiveMaxPlayers}
                  </span>
                  <span className="muted">웹 미지원</span>
                </div>
              ))
            : null}
        </section>
      ) : null}

      {creating ? <CreateRoomDialog onClose={() => setCreating(false)} /> : null}
    </main>
  );
}

function RoomRow({ room }: { room: RoomListEntry }) {
  const store = useStore();
  const [password, setPassword] = useState('');
  const [askingPassword, setAskingPassword] = useState(false);

  const full = room.playerCount >= room.effectiveMaxPlayers;
  const canJoin = !full && !room.gameInProgress;

  function join() {
    if (room.isPrivate && !askingPassword) {
      setAskingPassword(true);
      return;
    }
    store.joinRoom(room.id, room.isPrivate ? password : undefined);
    setAskingPassword(false);
    setPassword('');
  }

  return (
    <div className="room-row">
      <span className="room-row__name">
        {room.name}
        {room.isPrivate ? <span className="badge badge--lock">비공개</span> : null}
        {room.isRanked ? <span className="badge badge--ranked">랭크</span> : null}
      </span>
      <span className="muted">방장 {room.hostName}</span>
      <span className="muted">
        {room.playerCount}/{room.effectiveMaxPlayers}
      </span>
      <span className="muted">{room.turnTimeLimit}초 · {room.targetScore}점</span>

      {askingPassword ? (
        <span className="room-row__password">
          <input
            type="password"
            placeholder="비밀번호"
            value={password}
            autoFocus
            onChange={(e) => setPassword(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') join();
              if (e.key === 'Escape') setAskingPassword(false);
            }}
          />
          <button type="button" className="btn btn--primary btn--sm" onClick={join}>
            입장
          </button>
        </span>
      ) : (
        <button
          type="button"
          className="btn btn--primary btn--sm"
          disabled={!canJoin}
          onClick={join}
        >
          {room.gameInProgress ? '게임 중' : full ? '가득 참' : '입장'}
        </button>
      )}
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
