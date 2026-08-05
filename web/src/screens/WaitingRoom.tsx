import { useState } from 'react';
import type { RoomSeat } from '../protocol/types';
import { ChatPanel } from '../components/ChatPanel';
import { useAppState, useStore } from '../state/useStore';

/**
 * Waiting room.
 *
 * Seats are a fixed-length array with `null` for empty slots
 * (server/game/GameRoom.js:870). Teams are positional: slots 0 and 2 are Team A,
 * 1 and 3 are Team B — so moving team means moving to a specific slot via
 * `change_team {targetSlot}`.
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

  // Mirror GameRoom.areAllReady(): Tichu needs every seat filled, bots count as
  // ready, and the host is exempt — `toggle_ready` is a no-op for the host
  // (server.js:4858), so requiring their flag would disable Start forever.
  const canStart =
    occupied.length === room.maxPlayers &&
    occupied.every((seat) => seat.isBot || seat.id === room.hostId || seat.isReady);

  return (
    <main className="screen screen--waiting">
      <header className="room-header">
        <div>
          <h1>{room.name}</h1>
          <p className="muted">
            티츄 · {room.turnTimeLimit}초 · {room.targetScore}점
            {room.isPrivate ? ' · 비공개' : ''}
          </p>
        </div>
        <button type="button" className="btn btn--ghost" onClick={() => store.leaveRoom()}>
          나가기
        </button>
      </header>

      <div className="waiting-body">
        <section className="teams">
          <TeamColumn
            label="A팀"
            slots={[0, 2]}
            seats={seats}
            room={room}
            myId={myId}
            isHost={isHost}
          />
          <TeamColumn
            label="B팀"
            slots={[1, 3]}
            seats={seats}
            room={room}
            myId={myId}
            isHost={isHost}
          />
        </section>

        <ChatPanel />
      </div>

      <footer className="room-footer">
        {isHost ? (
          <>
            <button
              type="button"
              className="btn btn--primary"
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
            className={me?.isReady ? 'btn' : 'btn btn--primary'}
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
  room: { hostId: string; blockedSlots: number[] };
  myId: string | undefined;
  isHost: boolean;
}) {
  return (
    <div className="team">
      <h2 className="team__label">{label}</h2>
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
    return <div className="seat seat--blocked">차단된 자리</div>;
  }

  if (!seat) {
    return (
      <div className="seat seat--empty">
        <span className="muted">빈 자리</span>
        <div className="seat__actions">
          <button
            type="button"
            className="btn btn--sm"
            onClick={() => store.changeTeam(slot)}
          >
            이동
          </button>
          {isHost ? (
            <span className="bot-add">
              <button
                type="button"
                className="btn btn--sm"
                onClick={() => setBotMenuOpen((v) => !v)}
              >
                봇 추가
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
      </div>
    );
  }

  const isMe = seat.id === myId;

  return (
    <div className={`seat${isMe ? ' seat--me' : ''}${seat.isReady ? ' seat--ready' : ''}`}>
      <span className="seat__name">
        {seat.photoUrl ? (
          <img className="avatar" src={seat.photoUrl} alt="" />
        ) : (
          <span className="avatar avatar--placeholder" aria-hidden="true" />
        )}
        {seat.name}
        {seat.id === hostId ? <span className="badge">방장</span> : null}
        {seat.isBot ? <span className="badge badge--bot">봇</span> : null}
        {!seat.connected ? <span className="badge badge--warn">접속 끊김</span> : null}
      </span>
      <span className="seat__status">
        {/* The host never readies, so "waiting" would read as a blocker. */}
        {seat.id === hostId ? '시작 대기' : seat.isReady ? '준비 완료' : '대기 중'}
      </span>
      {isHost && !isMe ? (
        <button
          type="button"
          className="btn btn--sm btn--ghost"
          onClick={() => store.kickPlayer(seat.id)}
        >
          내보내기
        </button>
      ) : null}
    </div>
  );
}
