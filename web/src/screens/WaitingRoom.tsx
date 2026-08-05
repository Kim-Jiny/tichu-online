import { useState } from 'react';
import type { RoomSeat, RoomState } from '../protocol/types';
import { ChatPanel } from '../components/ChatPanel';
import { useAppState, useStore } from '../state/useStore';

/**
 * Waiting room, following the app's in-room view (lobby_screen.dart:2496).
 *
 * Flat header bar rather than a floating card — the app deliberately avoids
 * stacking three elevations on one screen (lobby_screen.dart:2891) — then the
 * two team columns of seat slots, then chat, with the host's start button last.
 *
 * Seats are a fixed-length array with `null` for empty slots
 * (GameRoom.js:870). Teams are positional: 0 and 2 are Team A, 1 and 3 Team B,
 * so switching sides means moving to a slot via `change_team {targetSlot}`.
 */
export function WaitingRoom() {
  const state = useAppState();
  const store = useStore();
  const room = state.room;

  if (!room) {
    return (
      <main className="screen screen--waiting">
        <p className="empty">방 정보를 불러오는 중…</p>
      </main>
    );
  }

  const myId = state.auth?.playerId;
  const isHost = room.hostId === myId;
  const seats = room.players;
  const occupied = seats.filter((s): s is RoomSeat => s !== null);
  const me = occupied.find((s) => s.id === myId) ?? null;
  const full = occupied.length >= room.effectiveMaxPlayers;

  // Mirrors GameRoom.areAllReady(): every seat filled, bots count as ready, and
  // the host is exempt — `toggle_ready` is a no-op for the host
  // (server.js:4858), so requiring their flag would disable Start forever.
  const canStart =
    occupied.length === room.maxPlayers &&
    occupied.every((seat) => seat.isBot || seat.id === room.hostId || seat.isReady);

  return (
    <main className="screen screen--waiting">
      <header className="room-bar">
        <button
          type="button"
          className="room-bar__back"
          aria-label="나가기"
          onClick={() => store.leaveRoom()}
        >
          <BackIcon />
        </button>
        <div className="room-bar__title">
          <h1>{room.name}</h1>
          <p>
            {room.turnTimeLimit}초 · {room.targetScore}점
            <span className="room-bar__dot"> · </span>
            <span className={full ? 'room-bar__count--full' : 'room-bar__count'}>
              {occupied.length}/{room.effectiveMaxPlayers}
            </span>
          </p>
        </div>
      </header>

      <div className="waiting-body">
        <div className="teams">
          <TeamColumn label="TEAM A" slots={[0, 2]} seats={seats} room={room} myId={myId} isHost={isHost} />
          <TeamColumn label="TEAM B" slots={[1, 3]} seats={seats} room={room} myId={myId} isHost={isHost} />
        </div>

        {isHost && !full ? (
          <button
            type="button"
            className="fill-bots"
            onClick={() => {
              // One add_bot per empty seat, targeted by slot — a bare add_bot
              // only takes the first free seat.
              seats.forEach((seat, slot) => {
                if (seat === null && !room.blockedSlots.includes(slot)) {
                  store.addBot(slot, 'normal');
                }
              });
            }}
          >
            빈 자리 봇으로 채우기
          </button>
        ) : null}

        <ChatPanel />
      </div>

      <footer className="room-footer">
        {isHost ? (
          <>
            <button
              type="button"
              className="btn-create"
              disabled={!canStart}
              onClick={() => store.startGame()}
            >
              게임 시작
            </button>
            {!canStart ? (
              <span className="muted">
                {occupied.length < room.maxPlayers
                  ? `4명이 모여야 시작할 수 있습니다 (${occupied.length}/${room.maxPlayers})`
                  : '아직 준비하지 않은 플레이어가 있습니다'}
              </span>
            ) : null}
          </>
        ) : (
          <button
            type="button"
            className={me?.isReady ? 'btn' : 'btn-create'}
            onClick={() => store.toggleReady()}
          >
            {me?.isReady ? '준비 해제' : '준비'}
          </button>
        )}
      </footer>
    </main>
  );
}

function TeamColumn({
  label,
  slots,
  seats,
  room,
  myId,
  isHost,
}: {
  label: string;
  slots: number[];
  seats: (RoomSeat | null)[];
  room: RoomState;
  myId: string | undefined;
  isHost: boolean;
}) {
  return (
    <div className="team">
      <h2 className={label === 'TEAM A' ? 'team__label team__label--a' : 'team__label team__label--b'}>
        {label}
      </h2>
      {slots.map((slot) => (
        <SeatCard
          key={slot}
          slot={slot}
          seat={seats[slot] ?? null}
          hostId={room.hostId}
          blocked={room.blockedSlots.includes(slot)}
          myId={myId}
          isHost={isHost}
        />
      ))}
    </div>
  );
}

function SeatCard({
  slot,
  seat,
  hostId,
  blocked,
  myId,
  isHost,
}: {
  slot: number;
  seat: RoomSeat | null;
  hostId: string;
  blocked: boolean;
  myId: string | undefined;
  isHost: boolean;
}) {
  const store = useStore();
  const [botMenuOpen, setBotMenuOpen] = useState(false);

  if (blocked) {
    return <div className="slot slot--blocked">차단된 자리</div>;
  }

  if (!seat) {
    return (
      <div className="slot slot--empty">
        <button
          type="button"
          className="slot__move"
          onClick={() => store.changeTeam(slot)}
          title="이 자리로 이동"
        >
          빈 자리
        </button>
        {isHost ? (
          <span className="bot-add">
            <button
              type="button"
              className="btn btn--sm"
              onClick={() => setBotMenuOpen((v) => !v)}
            >
              봇
            </button>
            {botMenuOpen ? (
              <span className="bot-add__menu">
                {(['slow', 'normal', 'fast'] as const).map((speed) => (
                  <button
                    key={speed}
                    type="button"
                    className="btn btn--sm btn--ghost"
                    onClick={() => {
                      store.addBot(slot, speed);
                      setBotMenuOpen(false);
                    }}
                  >
                    {speed === 'slow' ? '느림' : speed === 'normal' ? '보통' : '빠름'}
                  </button>
                ))}
              </span>
            ) : null}
          </span>
        ) : null}
      </div>
    );
  }

  const isMe = seat.id === myId;
  const isHostSeat = seat.id === hostId;

  return (
    <div
      className={[
        'slot',
        isMe ? 'slot--me' : '',
        !isHostSeat && !seat.isBot && seat.isReady ? 'slot--ready' : '',
      ]
        .filter(Boolean)
        .join(' ')}
    >
      {seat.photoUrl ? (
        <img className="slot__avatar" src={seat.photoUrl} alt="" />
      ) : (
        <span className="slot__avatar slot__avatar--empty" aria-hidden="true" />
      )}
      <span className="slot__body">
        <span className="slot__name">
          {seat.name}
          {isHostSeat ? <span className="badge">방장</span> : null}
          {seat.isBot ? <span className="badge badge--bot">봇</span> : null}
          {!seat.connected ? <span className="badge badge--warn">끊김</span> : null}
        </span>
        <span className="slot__status">
          {/* The host never readies, so "waiting" would read as a blocker. */}
          {isHostSeat ? '시작 대기' : seat.isReady ? '준비 완료' : '대기 중'}
        </span>
      </span>
      {isHost && !isMe ? (
        <button
          type="button"
          className="slot__kick"
          aria-label="내보내기"
          onClick={() => store.kickPlayer(seat.id)}
        >
          ×
        </button>
      ) : null}
    </div>
  );
}

function BackIcon() {
  return (
    <svg viewBox="0 0 24 24" width="1em" height="1em" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M19 12H5" />
      <path d="M11 18l-6-6 6-6" />
    </svg>
  );
}
