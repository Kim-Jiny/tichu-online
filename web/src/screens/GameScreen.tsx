import { useEffect, useMemo, useState } from 'react';
import { Card } from '../components/Card';
import { ChatPanel } from '../components/ChatPanel';
import { isBombCombo, trickPoints, RANKS } from '../protocol/cards';
import type { CardId, ExchangeSlots, GamePlayer, Rank, TichuState } from '../protocol/types';
import { useAppState, useStore } from '../state/useStore';

/**
 * The Tichu table.
 *
 * Everything rendered here comes from the latest `game_state` snapshot; the only
 * local state is the card selection and the exchange staging area, which are
 * inherently pre-submission UI. The server re-validates every action, so the
 * buttons here gate on the snapshot's own flags (`isMyTurn`, `dragonPending`,
 * `needsToCallRank`, `canDeclareSmallTichu`) rather than on re-derived rules.
 */
export function GameScreen() {
  const state = useAppState();
  const game = state.game;

  if (!game) {
    return (
      <main className="screen screen--game">
        <p className="empty">게임 상태를 불러오는 중…</p>
      </main>
    );
  }

  return <GameTable game={game} />;
}

function GameTable({ game }: { game: TichuState }) {
  const store = useStore();
  const [selected, setSelected] = useState<Set<CardId>>(new Set());
  const [exchange, setExchange] = useState<Partial<ExchangeSlots>>({});
  /** Cards staged behind the Bird wish prompt; see BirdWishDialog. */
  const [birdPlay, setBirdPlay] = useState<CardId[] | null>(null);

  // A new hand invalidates any selection made against the old one.
  const handKey = game.myCards.join(',');
  useEffect(() => {
    setSelected(new Set());
  }, [handKey]);

  useEffect(() => {
    if (game.phase !== 'card_exchange') setExchange({});
  }, [game.phase]);

  const selectedList = useMemo(
    () => game.myCards.filter((c) => selected.has(c)),
    [game.myCards, selected],
  );

  const self = game.players.find((p) => p.position === 'self');
  const bombReady = isBombCombo(selectedList);
  const canPlay = game.isMyTurn || bombReady;

  function toggleCard(cardId: CardId) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(cardId)) next.delete(cardId);
      else next.add(cardId);
      return next;
    });
  }

  return (
    <main className="screen screen--game">
      <TableHeader game={game} />

      <section className="table">
        <Opponent player={game.players.find((p) => p.position === 'partner')} slot="partner" game={game} />
        <div className="table__middle">
          <Opponent player={game.players.find((p) => p.position === 'left')} slot="left" game={game} />
          <TrickArea game={game} />
          <Opponent player={game.players.find((p) => p.position === 'right')} slot="right" game={game} />
        </div>
      </section>

      {game.phase === 'card_exchange' ? (
        <ExchangePanel
          game={game}
          selected={selectedList}
          exchange={exchange}
          onAssign={(slot, cardId) => {
            setExchange((prev) => ({
              // A card can only sit in one slot; clear it from any other.
              ...Object.fromEntries(
                Object.entries(prev).filter(([, v]) => v !== cardId),
              ),
              [slot]: cardId,
            }));
            // Drop it from the selection too — the staging area needs exactly
            // one selected card to know what to place, so a leftover selection
            // would block picking the next one.
            setSelected((prev) => {
              const next = new Set(prev);
              next.delete(cardId);
              return next;
            });
          }}
          onClear={(slot) =>
            setExchange((prev) => {
              const next = { ...prev };
              delete next[slot];
              return next;
            })
          }
          onSubmit={() => {
            store.exchangeCards(exchange as ExchangeSlots);
            setSelected(new Set());
          }}
        />
      ) : null}

      <Hand
        game={game}
        selected={selected}
        exchange={exchange}
        onToggle={toggleCard}
      />

      <ActionBar
        game={game}
        self={self}
        selectedList={selectedList}
        canPlay={canPlay}
        bombReady={bombReady}
        onPlay={() => {
          // The wish has to be decided before the play is sent, not after.
          if (selectedList.includes('special_bird')) {
            setBirdPlay(selectedList);
            return;
          }
          store.playCards(selectedList);
          setSelected(new Set());
        }}
        onClear={() => setSelected(new Set())}
      />

      {birdPlay ? (
        <BirdWishDialog
          onDecide={(rank) => {
            store.playCards(birdPlay, rank);
            setBirdPlay(null);
            setSelected(new Set());
          }}
          onCancel={() => {
            setBirdPlay(null);
            setSelected(new Set());
          }}
        />
      ) : null}
      {game.needsToCallRank ? <WishDialog /> : null}
      {game.dragonPending ? <DragonDialog game={game} /> : null}
      {game.phase === 'round_end' || game.phase === 'game_end' ? (
        <RoundSummary game={game} />
      ) : null}

      <ChatPanel compact />
    </main>
  );
}

// ---------------------------------------------------------------------------

function TableHeader({ game }: { game: TichuState }) {
  const store = useStore();
  const state = useAppState();
  const myTeam = useMemo(() => {
    const self = game.players.find((p) => p.position === 'self');
    if (!self) return 'A';
    return game.teams?.teamA?.includes(self.id) ? 'A' : 'B';
  }, [game.players, game.teams]);

  return (
    <header className="game-header">
      <span className="game-header__phase">{PHASE_LABELS[game.phase] ?? game.phase}</span>
      <span className="game-header__round">{game.round}라운드</span>
      <span className="score">
        <span className={myTeam === 'A' ? 'score__team score__team--mine' : 'score__team'}>
          A {game.totalScores.teamA}
        </span>
        <span className="score__sep">:</span>
        <span className={myTeam === 'B' ? 'score__team score__team--mine' : 'score__team'}>
          B {game.totalScores.teamB}
        </span>
      </span>
      <TurnClock deadline={game.turnDeadline ?? null} active={game.phase === 'playing'} />
      <button
        type="button"
        className="btn btn--ghost btn--sm"
        onClick={() => {
          if (window.confirm('게임에서 나가시겠습니까? 팀에 불이익이 있을 수 있습니다.')) {
            store.leaveGame();
          }
        }}
      >
        나가기
      </button>
      {state.connection !== 'open' ? <span className="badge badge--warn">오프라인</span> : null}
    </header>
  );
}

/** Counts down to the server's `turnDeadline` (epoch ms, spliced into every state). */
function TurnClock({ deadline, active }: { deadline: number | null; active: boolean }) {
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    if (!active || !deadline) return;
    const timer = window.setInterval(() => setNow(Date.now()), 250);
    return () => window.clearInterval(timer);
  }, [active, deadline]);

  if (!active || !deadline) return null;
  const remaining = Math.max(0, Math.ceil((deadline - now) / 1000));
  return (
    <span className={remaining <= 5 ? 'clock clock--urgent' : 'clock'}>{remaining}초</span>
  );
}

function Opponent({
  player,
  slot,
  game,
}: {
  player: GamePlayer | undefined;
  slot: 'left' | 'right' | 'partner';
  game: TichuState;
}) {
  if (!player) return <div className={`opponent opponent--${slot}`} />;
  const isCurrent = game.currentPlayer === player.id;

  return (
    <div className={`opponent opponent--${slot}${isCurrent ? ' opponent--turn' : ''}`}>
      <span className="opponent__name">
        {player.photoUrl ? (
          <img className="avatar" src={player.photoUrl} alt="" />
        ) : (
          <span className="avatar avatar--placeholder" aria-hidden="true" />
        )}
        {player.name}
        {player.isBot ? <span className="badge badge--bot">봇</span> : null}
        {player.connected === false ? <span className="badge badge--warn">끊김</span> : null}
      </span>
      <span className="opponent__badges">
        {player.hasLargeTichu ? <span className="badge badge--tichu">대</span> : null}
        {player.hasSmallTichu ? <span className="badge badge--tichu">소</span> : null}
        {player.hasFinished ? <span className="badge">{player.finishPosition}등</span> : null}
      </span>
      <span className="opponent__cards" aria-label={`${player.cardCount}장`}>
        {Array.from({ length: Math.min(player.cardCount, 14) }, (_, i) => (
          <span key={i} className="mini-card" />
        ))}
        <span className="opponent__count">{player.cardCount}</span>
      </span>
    </div>
  );
}

function TrickArea({ game }: { game: TichuState }) {
  const plays = game.currentTrick.length > 0 ? game.currentTrick : game.lastTrick;
  const isHistory = game.currentTrick.length === 0 && game.lastTrick.length > 0;
  const points = trickPoints(plays.flatMap((p) => p.cards));

  return (
    <div className="trick">
      {plays.length === 0 ? (
        <p className="muted">아직 낸 카드가 없습니다.</p>
      ) : (
        <>
          {isHistory ? <span className="trick__label">직전 트릭</span> : null}
          {points !== 0 ? <span className="trick__points">{points}점</span> : null}
          <div className="trick__plays">
            {plays.map((play, index) => (
              <div
                key={`${play.playerId}-${index}`}
                className={
                  index === plays.length - 1 ? 'trick__play trick__play--top' : 'trick__play'
                }
              >
                <span className="trick__player">{play.playerName}</span>
                <span className="trick__cards">
                  {play.cards.map((cardId) => (
                    <Card
                      key={cardId}
                      cardId={cardId}
                      size="sm"
                      badge={
                        // The Phoenix's played value is only knowable from the
                        // server's comboValue (e.g. 5.5 means it beat a 5).
                        cardId === 'special_phoenix' && play.combo === 'single'
                          ? String(play.comboValue)
                          : undefined
                      }
                    />
                  ))}
                </span>
              </div>
            ))}
          </div>
        </>
      )}
      {game.callRank ? (
        <p className="trick__wish">소원: {game.callRank}</p>
      ) : null}
      {game.passCount > 0 ? <p className="muted">패스 {game.passCount}</p> : null}
    </div>
  );
}

function Hand({
  game,
  selected,
  exchange,
  onToggle,
}: {
  game: TichuState;
  selected: Set<CardId>;
  exchange: Partial<ExchangeSlots>;
  onToggle: (cardId: CardId) => void;
}) {
  const staged = new Set(Object.values(exchange).filter(Boolean) as CardId[]);
  const interactive =
    game.phase === 'playing' ||
    game.phase === 'card_exchange' ||
    game.phase === 'large_tichu_phase';

  return (
    <section className="hand" aria-label="내 카드">
      {game.myCards.map((cardId) => (
        <Card
          key={cardId}
          cardId={cardId}
          selected={selected.has(cardId) || staged.has(cardId)}
          disabled={staged.has(cardId)}
          onClick={interactive && !staged.has(cardId) ? () => onToggle(cardId) : undefined}
        />
      ))}
      {game.myCards.length === 0 ? <p className="muted">손패가 없습니다.</p> : null}
    </section>
  );
}

function ActionBar({
  game,
  self,
  selectedList,
  canPlay,
  bombReady,
  onPlay,
  onClear,
}: {
  game: TichuState;
  self: GamePlayer | undefined;
  selectedList: CardId[];
  canPlay: boolean;
  bombReady: boolean;
  onPlay: () => void;
  onClear: () => void;
}) {
  const store = useStore();

  if (game.phase === 'large_tichu_phase') {
    return (
      <footer className="actions">
        {game.largeTichuResponded ? (
          <span className="muted">다른 플레이어를 기다리는 중…</span>
        ) : (
          <>
            <button
              type="button"
              className="btn btn--primary"
              onClick={() => store.declareLargeTichu()}
            >
              대 티츄 선언
            </button>
            <button type="button" className="btn" onClick={() => store.passLargeTichu()}>
              패스
            </button>
          </>
        )}
      </footer>
    );
  }

  if (game.phase !== 'playing') {
    return (
      <footer className="actions">
        <span className="muted">{PHASE_LABELS[game.phase] ?? game.phase}</span>
      </footer>
    );
  }

  return (
    <footer className="actions">
      {game.canDeclareSmallTichu ? (
        <button type="button" className="btn" onClick={() => store.declareSmallTichu()}>
          소 티츄 선언
        </button>
      ) : null}
      {self?.hasLargeTichu ? <span className="badge badge--tichu">대 티츄</span> : null}
      {self?.hasSmallTichu ? <span className="badge badge--tichu">소 티츄</span> : null}

      <span className="actions__spacer" />

      {selectedList.length > 0 ? (
        <button type="button" className="btn btn--ghost" onClick={onClear}>
          선택 해제 ({selectedList.length})
        </button>
      ) : null}

      <button
        type="button"
        className={bombReady && !game.isMyTurn ? 'btn btn--bomb' : 'btn btn--primary'}
        disabled={selectedList.length === 0 || !canPlay}
        onClick={onPlay}
      >
        {bombReady && !game.isMyTurn ? '폭탄!' : '내기'}
      </button>

      <button
        type="button"
        className="btn"
        disabled={!game.isMyTurn || game.currentTrick.length === 0}
        onClick={() => store.pass()}
      >
        패스
      </button>
    </footer>
  );
}

function ExchangePanel({
  game,
  selected,
  exchange,
  onAssign,
  onClear,
  onSubmit,
}: {
  game: TichuState;
  selected: CardId[];
  exchange: Partial<ExchangeSlots>;
  onAssign: (slot: keyof ExchangeSlots, cardId: CardId) => void;
  onClear: (slot: keyof ExchangeSlots) => void;
  onSubmit: () => void;
}) {
  if (game.exchangeDone) {
    return (
      <section className="exchange">
        <p className="muted">교환 카드를 보냈습니다. 다른 플레이어를 기다리는 중…</p>
        {game.receivedFrom ? (
          <div className="exchange__received">
            <span>받은 카드</span>
            {(['left', 'partner', 'right'] as const).map((slot) => (
              <span key={slot} className="exchange__slot">
                <span className="exchange__slot-label">{SLOT_LABELS[slot]}</span>
                <Card cardId={game.receivedFrom![slot]} size="sm" />
              </span>
            ))}
          </div>
        ) : null}
      </section>
    );
  }

  const pick = selected.length === 1 ? selected[0] : null;
  const complete = Boolean(exchange.left && exchange.partner && exchange.right);

  return (
    <section className="exchange">
      <p className="exchange__hint">
        {pick
          ? '보낼 상대를 고르세요.'
          : '카드를 하나 선택한 뒤 상대를 지정하세요. (세 명 모두 필요)'}
      </p>
      <div className="exchange__slots">
        {(['left', 'partner', 'right'] as const).map((slot) => (
          <div key={slot} className="exchange__slot">
            <span className="exchange__slot-label">{SLOT_LABELS[slot]}</span>
            {exchange[slot] ? (
              <button type="button" className="exchange__staged" onClick={() => onClear(slot)}>
                <Card cardId={exchange[slot]!} size="sm" />
                <span className="muted">되돌리기</span>
              </button>
            ) : (
              <button
                type="button"
                className="btn btn--sm"
                disabled={!pick}
                onClick={() => pick && onAssign(slot, pick)}
              >
                여기에 놓기
              </button>
            )}
          </div>
        ))}
      </div>
      <button type="button" className="btn btn--primary" disabled={!complete} onClick={onSubmit}>
        교환 확정
      </button>
    </section>
  );
}

/**
 * Asked before the Bird is played, because the wish must travel with the play
 * (the engine advances the turn as soon as the cards land). Mirrors the app's
 * dialog in flutter_app/lib/screens/game_screen.dart:242.
 */
function BirdWishDialog({
  onDecide,
  onCancel,
}: {
  onDecide: (rank: Rank | 'none') => void;
  onCancel: () => void;
}) {
  return (
    <div className="modal-backdrop">
      <div className="modal" role="dialog" aria-modal="true">
        <h2>🐦 참새 소원</h2>
        <p className="muted">원하는 숫자를 고르세요. 다른 사람은 낼 수 있다면 그 숫자를 내야 합니다.</p>
        <div className="wish-grid">
          {RANKS.map((rank: Rank) => (
            <button
              key={rank}
              type="button"
              className="btn btn--sm btn--primary"
              onClick={() => onDecide(rank)}
            >
              {rank}
            </button>
          ))}
        </div>
        <div className="modal__actions">
          <button type="button" className="btn" onClick={() => onDecide('none')}>
            소원 없이 내기
          </button>
          <button type="button" className="btn btn--ghost" onClick={onCancel}>
            다른 카드 고르기
          </button>
        </div>
      </div>
    </div>
  );
}

/**
 * Fallback for a Bird that reached the table without a wish — a turn timeout
 * auto-play, or an older client. The turn has already moved on by now, so this
 * only ever plays catch-up.
 */
function WishDialog() {
  const store = useStore();
  return (
    <div className="modal-backdrop">
      <div className="modal" role="dialog" aria-modal="true">
        <h2>소원을 말하세요</h2>
        <p className="muted">참새가 나갔습니다. 원하는 숫자를 지정하거나 넘어갈 수 있습니다.</p>
        <div className="wish-grid">
          {RANKS.map((rank: Rank) => (
            <button
              key={rank}
              type="button"
              className="btn btn--sm"
              onClick={() => store.callRank(rank)}
            >
              {rank}
            </button>
          ))}
        </div>
        <button type="button" className="btn btn--ghost" onClick={() => store.callRank(null)}>
          소원 없음
        </button>
      </div>
    </div>
  );
}

function DragonDialog({ game }: { game: TichuState }) {
  const store = useStore();
  const left = game.players.find((p) => p.position === 'left');
  const right = game.players.find((p) => p.position === 'right');

  return (
    <div className="modal-backdrop">
      <div className="modal" role="dialog" aria-modal="true">
        <h2>용 트릭을 넘기세요</h2>
        <p className="muted">용으로 트릭을 가져왔습니다. 상대 팀 중 한 명에게 줘야 합니다.</p>
        <div className="modal__actions">
          <button type="button" className="btn btn--primary" onClick={() => store.giveDragon('left')}>
            왼쪽 {left ? `(${left.name})` : ''}
          </button>
          <button type="button" className="btn btn--primary" onClick={() => store.giveDragon('right')}>
            오른쪽 {right ? `(${right.name})` : ''}
          </button>
        </div>
      </div>
    </div>
  );
}

function RoundSummary({ game }: { game: TichuState }) {
  const store = useStore();
  const isGameEnd = game.phase === 'game_end';

  return (
    <div className="modal-backdrop modal-backdrop--soft">
      <div className="modal" role="dialog" aria-modal="true">
        <h2>{isGameEnd ? '게임 종료' : `${game.round}라운드 종료`}</h2>
        {game.lastRoundScores ? (
          <p className="summary-line">
            이번 라운드 — A {game.lastRoundScores.teamA} : B {game.lastRoundScores.teamB}
          </p>
        ) : null}
        <p className="summary-line summary-line--total">
          누적 — A {game.totalScores.teamA} : B {game.totalScores.teamB}
        </p>

        {game.scoreHistory.length > 0 ? (
          <table className="score-table">
            <thead>
              <tr>
                <th>라운드</th>
                <th>A팀</th>
                <th>B팀</th>
              </tr>
            </thead>
            <tbody>
              {game.scoreHistory.map((entry) => (
                <tr key={entry.round}>
                  <td>{entry.round}</td>
                  <td>{entry.teamA}</td>
                  <td>{entry.teamB}</td>
                </tr>
              ))}
            </tbody>
          </table>
        ) : null}

        <div className="modal__actions">
          {isGameEnd ? (
            <button type="button" className="btn btn--primary" onClick={() => store.returnToRoom()}>
              대기실로
            </button>
          ) : (
            // The server advances rounds on its own 3s timer; this is the host's
            // manual override, harmless for everyone else to press.
            <button type="button" className="btn" onClick={() => store.nextRound()}>
              다음 라운드
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

const SLOT_LABELS: Record<keyof ExchangeSlots, string> = {
  left: '왼쪽',
  partner: '파트너',
  right: '오른쪽',
};

const PHASE_LABELS: Record<string, string> = {
  waiting: '대기 중',
  dealing_first_8: '8장 분배 중',
  large_tichu_phase: '대 티츄 선언',
  dealing_remaining_6: '나머지 6장 분배',
  card_exchange: '카드 교환',
  playing: '플레이',
  round_end: '라운드 종료',
  game_end: '게임 종료',
};
