/**
 * Wire contracts, transliterated from the server.
 *
 * The server is authoritative and pushes a *complete* per-player snapshot on
 * every event — there is no delta protocol, no sequence number, no client-side
 * reconciliation. So these types describe exactly what arrives, and the UI is a
 * pure function of the latest snapshot.
 *
 * Sources of truth:
 *   server/game/TichuGame.js:1350   getStateForPlayer
 *   server/server.js:7212           decoratePlayerState (fields spliced on top)
 *   server/game/GameRoom.js:855     getState
 *   server/lobby/LobbyManager.js:47 getRoomList
 *   server/game/Deck.js:11          card id format
 *   server/game/CardValidator.js:4  combo type strings
 */

export type Suit = 'spade' | 'heart' | 'diamond' | 'club';

export type Rank =
  | '2' | '3' | '4' | '5' | '6' | '7' | '8' | '9' | '10' | 'J' | 'Q' | 'K' | 'A';

/** `spade_2` … `club_A`, or `special_bird|dog|phoenix|dragon`. */
export type CardId = string;

export type ComboType =
  | 'single'
  | 'pair'
  | 'triple'
  | 'straight'
  | 'full_house'
  | 'steps'
  | 'bomb_four'
  | 'bomb_straight_flush'
  | 'dog';

export type TichuPhase =
  | 'waiting'
  | 'dealing_first_8'
  | 'large_tichu_phase'
  | 'dealing_remaining_6'
  | 'card_exchange'
  | 'playing'
  | 'round_end'
  | 'game_end';

/** Seat position relative to the viewer. */
export type SeatPosition = 'self' | 'right' | 'partner' | 'left';

export interface TrickPlay {
  playerId: string;
  playerName: string;
  cards: CardId[];
  combo: ComboType;
  /** Effective rank; fractional for a Phoenix single (e.g. 5.5 beats a 5). */
  comboValue: number;
}

export interface GamePlayer {
  id: string;
  name: string;
  position: SeatPosition;
  cardCount: number;
  hasFinished: boolean;
  /** 1-based; 0 when still playing. */
  finishPosition: number;
  hasSmallTichu: boolean;
  hasLargeTichu: boolean;
  hasExchanged: boolean;
  // Spliced on by decorateSeats (server.js:7188).
  connected?: boolean;
  timeoutCount?: number;
  photoUrl?: string | null;
  isBot?: boolean;
  titleName?: string | null;
}

export interface TeamScores {
  teamA: number;
  teamB: number;
}

export interface ScoreHistoryEntry {
  round: number;
  teamA: number;
  teamB: number;
}

/** Which of the three neighbours an exchanged card goes to / came from. */
export interface ExchangeSlots {
  left: CardId;
  partner: CardId;
  right: CardId;
}

export interface RemainingSpecials {
  aces: number;
  kings: number;
  dragon: number;
  phoenix: number;
}

export interface TichuState {
  /** Absent for Tichu; present for the other three games (server omits it). */
  gameType?: 'skull_king' | 'love_letter' | 'mighty';
  phase: TichuPhase;
  round: number;
  myCards: CardId[];
  players: GamePlayer[];
  currentPlayer: string | null;
  isMyTurn: boolean;
  currentTrick: TrickPlay[];
  /** Only populated during round_end / game_end. */
  lastTrick: TrickPlay[];
  teams: { teamA: string[]; teamB: string[] };
  totalScores: TeamScores;
  lastRoundScores: TeamScores | null;
  scoreHistory: ScoreHistoryEntry[];
  finishOrder: string[];
  passCount: number;
  callRank: Rank | null;
  /** True only for the player who owes the wish. */
  needsToCallRank: boolean;
  /** True only for the player who must route the Dragon trick. */
  dragonPending: boolean;
  exchangeDone: boolean;
  exchangeGiven: ExchangeSlots | null;
  receivedFrom: ExchangeSlots | null;
  largeTichuResponded: boolean;
  canDeclareSmallTichu: boolean;
  /** Paid "top card counter" item; zeroes when the viewer doesn't own it. */
  remainingSpecials?: RemainingSpecials;
  // Spliced on by decoratePlayerState (server.js:7212).
  turnDeadline?: number | null;
  cardViewers?: unknown[];
  spectators?: { id: string; nickname: string }[];
  spectatorCount?: number;
}

// ---------------------------------------------------------------------------
// Lobby / room
// ---------------------------------------------------------------------------

export type GameType = 'tichu' | 'skull_king' | 'love_letter' | 'mighty';

export interface RoomListEntry {
  id: string;
  name: string;
  playerCount: number;
  maxPlayers: number;
  effectiveMaxPlayers: number;
  gameType: GameType;
  hostName: string;
  isPrivate: boolean;
  isRanked: boolean;
  allowSpectators: boolean;
  gameInProgress: boolean;
  spectatorCount: number;
  turnTimeLimit: number;
  targetScore: number;
  skExpansions: string[];
  randomSeating: boolean;
}

export interface RoomSeat {
  id: string;
  name: string;
  isHost: boolean;
  connected: boolean;
  isBot: boolean;
  isReady: boolean;
  titleKey: string | null;
  titleName: string | null;
  bannerKey: string | null;
  photoUrl: string | null;
  botSpeed: string | null;
  botStrategy: string | null;
  level: number | null;
  seasonRating: number | null;
}

export interface RoomState {
  id: string;
  name: string;
  isPrivate: boolean;
  isRanked: boolean;
  allowSpectators: boolean;
  gameType: GameType;
  maxPlayers: number;
  hostId: string;
  spectators: { id: string; nickname: string }[];
  spectatorCount: number;
  /** Fixed-length seat array; `null` marks an empty seat. */
  players: (RoomSeat | null)[];
  gameInProgress: boolean;
  turnTimeLimit: number;
  targetScore: number;
  skExpansions: string[];
  blockedSlots: number[];
  effectiveMaxPlayers: number;
  randomSeating: boolean;
}

export interface ChatEntry {
  sender: string;
  senderId?: string;
  message: string;
  timestamp: number;
  photoUrl?: string | null;
}

export interface MaintenanceStatus {
  maintenance?: boolean;
  notice?: boolean;
  message?: string;
  maintenanceStart?: string | null;
  maintenanceEnd?: string | null;
}

// ---------------------------------------------------------------------------
// Messages
// ---------------------------------------------------------------------------

/** Every frame in both directions is a flat object discriminated by `type`. */
export interface ServerMessage {
  type: string;
  [key: string]: unknown;
}

export interface ClientMessage {
  type: string;
  [key: string]: unknown;
}

export interface LoginSuccess {
  type: 'login_success';
  playerId: string;
  nickname: string;
  bindingToken?: string;
  photoUrl: string | null;
  themeKey: string | null;
  titleKey: string | null;
  authProvider: 'local' | 'kakao' | 'google' | 'apple';
  isAdmin: boolean;
  maintenanceStatus: MaintenanceStatus;
  cardViewPref: string;
}

/** Where `check_room` says the client belongs after a reconnect. */
export type RestoreDestination = 'lobby' | 'waiting_room' | 'game' | 'spectator';
