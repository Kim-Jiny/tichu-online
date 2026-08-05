import { GameSocket, type ConnectionState } from '../protocol/socket';
import type {
  CardId,
  ChatEntry,
  ClientMessage,
  ExchangeSlots,
  MaintenanceStatus,
  Rank,
  RestoreDestination,
  RoomListEntry,
  RoomState,
  ServerMessage,
  TichuState,
} from '../protocol/types';

/**
 * All client state, in one observable store.
 *
 * The server pushes a full snapshot per event, so there is deliberately no
 * merging or patching here: every handler assigns what arrived. The only state
 * this file *owns* rather than mirrors is UI-local (which screen, transient
 * toasts, pending-login flags).
 */

/**
 * Feature gates key off this (server.js:533-552) and a missing value reads as
 * 0.0.0, which would lock the client out of everything past base Tichu. Bump it
 * alongside the Flutter app when the web client gains the matching feature.
 */
const CLIENT_APP_VERSION = '2.8.0';

const STORAGE_KEY = 'tichu.web.credentials';

export type Screen = 'login' | 'lobby' | 'waiting' | 'game';

export interface Toast {
  id: number;
  kind: 'error' | 'info';
  message: string;
}

export interface AuthInfo {
  playerId: string;
  nickname: string;
  authProvider: 'local' | 'kakao' | 'google' | 'apple';
  isAdmin: boolean;
  photoUrl: string | null;
}

export interface AppState {
  connection: ConnectionState;
  screen: Screen;
  auth: AuthInfo | null;
  /** True between sending credentials and hearing back. */
  loginPending: boolean;
  loginError: string | null;
  registerNotice: string | null;
  /** Set when the server kicks us (duplicate login, ban); shown on the login screen. */
  kickedReason: string | null;
  maintenance: MaintenanceStatus | null;
  rooms: RoomListEntry[];
  room: RoomState | null;
  chat: ChatEntry[];
  game: TichuState | null;
  toasts: Toast[];
  /** Last non-state gameplay event, for animation/SFX hooks. */
  lastEvent: ServerMessage | null;
}

interface StoredCredentials {
  username: string;
  password: string;
}

const INITIAL_STATE: AppState = {
  connection: 'idle',
  screen: 'login',
  auth: null,
  loginPending: false,
  loginError: null,
  registerNotice: null,
  kickedReason: null,
  maintenance: null,
  rooms: [],
  room: null,
  chat: [],
  game: null,
  toasts: [],
  lastEvent: null,
};

/** Fire-and-forget events that exist only to drive animation and sound. */
const COSMETIC_EVENTS = new Set([
  'large_tichu_declared',
  'large_tichu_passed',
  'small_tichu_declared',
  'cards_played',
  'bomb_played',
  'dog_played',
  'player_passed',
  'dragon_given',
  'call_rank',
  'turn_timeout',
  'timeout_reset',
  'player_deserted',
]);

export class GameStore {
  private state: AppState = INITIAL_STATE;
  private listeners = new Set<() => void>();
  private socket: GameSocket;
  private toastSeq = 0;
  private locale: 'ko' | 'en' | 'de' = 'ko';
  /**
   * Credentials are replayed on every socket open because the server keeps no
   * session token — authentication lives on its per-connection `ws` object and
   * is gone the moment the socket drops (server.js:3495).
   */
  private credentials: StoredCredentials | null = null;

  constructor(socket: GameSocket = new GameSocket()) {
    this.socket = socket;
    this.credentials = loadCredentials();
    this.socket.onMessage((msg) => this.handleMessage(msg));
    this.socket.onStateChange((connection) => {
      this.patch({ connection });
      if (connection === 'open') this.onSocketOpen();
    });
  }

  // -- store plumbing -------------------------------------------------------

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  getSnapshot = (): AppState => this.state;

  private patch(partial: Partial<AppState>): void {
    this.state = { ...this.state, ...partial };
    for (const listener of this.listeners) listener();
  }

  // -- lifecycle ------------------------------------------------------------

  start(): void {
    this.socket.connect();
  }

  /** Whether a saved credential exists, so the UI can show "restoring session". */
  hasSavedSession(): boolean {
    return this.credentials !== null;
  }

  private onSocketOpen(): void {
    if (this.credentials) {
      this.patch({ loginPending: true, loginError: null });
      this.sendLogin(this.credentials);
    }
  }

  private sendLogin(creds: StoredCredentials): void {
    this.socket.send({
      type: 'login',
      username: creds.username,
      password: creds.password,
      deviceInfo: {
        devicePlatform: 'web',
        appVersion: CLIENT_APP_VERSION,
        locale: this.locale,
      },
    });
  }

  // -- actions: auth --------------------------------------------------------

  login(username: string, password: string, remember: boolean): void {
    const creds = { username: username.trim(), password };
    this.patch({ loginPending: true, loginError: null, kickedReason: null });
    if (remember) {
      this.credentials = creds;
      saveCredentials(creds);
    } else {
      // Kept in memory only: still needed to re-authenticate after a drop.
      this.credentials = creds;
      clearCredentials();
    }
    this.sendLogin(creds);
  }

  register(username: string, password: string, nickname: string): void {
    this.patch({ registerNotice: null, loginError: null });
    this.socket.send({ type: 'register', username: username.trim(), password, nickname: nickname.trim() });
  }

  checkNickname(nickname: string): void {
    this.socket.send({ type: 'check_nickname', nickname: nickname.trim() });
  }

  logout(): void {
    this.credentials = null;
    clearCredentials();
    this.patch({
      ...INITIAL_STATE,
      connection: this.state.connection,
      screen: 'login',
    });
    // Drop and re-open so the server forgets the authenticated binding on its
    // side too — there is no logout message in the protocol.
    this.socket.close();
    this.socket.connect();
  }

  setLocale(locale: 'ko' | 'en' | 'de'): void {
    this.locale = locale;
    this.socket.send({ type: 'set_locale', locale });
  }

  // -- actions: lobby -------------------------------------------------------

  refreshRooms(): void {
    this.socket.send({ type: 'room_list' });
  }

  createRoom(options: {
    roomName: string;
    password?: string;
    turnTimeLimit?: number;
    targetScore?: number;
    allowSpectators?: boolean;
  }): void {
    this.socket.send({
      type: 'create_room',
      gameType: 'tichu',
      roomName: options.roomName,
      password: options.password ?? '',
      turnTimeLimit: options.turnTimeLimit ?? 30,
      targetScore: options.targetScore ?? 1000,
      allowSpectators: options.allowSpectators !== false,
      isRanked: false,
    });
  }

  joinRoom(roomId: string, password?: string): void {
    this.socket.send({ type: 'join_room', roomId, password: password ?? '' });
  }

  // -- actions: waiting room ------------------------------------------------

  toggleReady(): void {
    this.socket.send({ type: 'toggle_ready' });
  }

  addBot(targetSlot?: number, speed = 'normal'): void {
    const msg: ClientMessage = { type: 'add_bot', speed };
    if (typeof targetSlot === 'number') msg.targetSlot = targetSlot;
    this.socket.send(msg);
  }

  changeTeam(targetSlot: number): void {
    this.socket.send({ type: 'change_team', targetSlot });
  }

  kickPlayer(playerId: string): void {
    this.socket.send({ type: 'kick_player', playerId });
  }

  startGame(): void {
    this.socket.send({ type: 'start_game' });
  }

  leaveRoom(): void {
    this.socket.send({ type: 'leave_room' });
  }

  leaveGame(): void {
    this.socket.send({ type: 'leave_game' });
  }

  sendChat(message: string): void {
    const trimmed = message.trim();
    if (!trimmed) return;
    this.socket.send({ type: 'chat_message', message: trimmed });
  }

  // -- actions: gameplay ----------------------------------------------------

  declareLargeTichu(): void {
    this.socket.send({ type: 'declare_large_tichu' });
  }

  passLargeTichu(): void {
    this.socket.send({ type: 'pass_large_tichu' });
  }

  declareSmallTichu(): void {
    this.socket.send({ type: 'declare_small_tichu' });
  }

  exchangeCards(cards: ExchangeSlots): void {
    this.socket.send({ type: 'exchange_cards', cards });
  }

  /**
   * `callRank` must ride along with a Bird play, not follow it: the engine
   * calls advanceTurn() unconditionally after a play (TichuGame.js:458), so a
   * wish sent afterwards arrives a turn late. Pass the sentinel `'none'` to
   * decline the wish — the server rejects it as a rank but it is truthy, which
   * is what keeps it out of the `needsToCallRank` branch (TichuGame.js:400).
   */
  playCards(cards: CardId[], callRank?: Rank | 'none' | null): void {
    const msg: ClientMessage = { type: 'play_cards', cards };
    if (callRank) msg.callRank = callRank;
    this.socket.send(msg);
  }

  pass(): void {
    this.socket.send({ type: 'pass' });
  }

  callRank(rank: Rank | null): void {
    this.socket.send({ type: 'call_rank', rank });
  }

  giveDragon(target: string): void {
    this.socket.send({ type: 'dragon_give', target });
  }

  nextRound(): void {
    this.socket.send({ type: 'next_round' });
  }

  resetTimeout(): void {
    this.socket.send({ type: 'reset_timeout' });
  }

  returnToRoom(): void {
    this.socket.send({ type: 'return_to_room' });
  }

  // -- toasts ---------------------------------------------------------------

  dismissToast(id: number): void {
    this.patch({ toasts: this.state.toasts.filter((t) => t.id !== id) });
  }

  private pushToast(kind: Toast['kind'], message: string): void {
    const toast: Toast = { id: (this.toastSeq += 1), kind, message };
    this.patch({ toasts: [...this.state.toasts, toast].slice(-4) });
    window.setTimeout(() => this.dismissToast(toast.id), 4000);
  }

  // -- inbound --------------------------------------------------------------

  private handleMessage(msg: ServerMessage): void {
    if (COSMETIC_EVENTS.has(msg.type)) {
      // Purely decorative: an authoritative `game_state` always follows.
      this.patch({ lastEvent: msg });
      return;
    }

    switch (msg.type) {
      case 'login_success':
        this.onLoginSuccess(msg);
        break;

      case 'login_error':
        this.credentials = null;
        clearCredentials();
        this.patch({
          loginPending: false,
          loginError: String(msg.message ?? '로그인에 실패했습니다.'),
          screen: 'login',
        });
        break;

      case 'register_result':
        this.patch({
          registerNotice: String(msg.message ?? ''),
          loginError: msg.success ? null : String(msg.message ?? ''),
        });
        break;

      case 'nickname_check_result':
        this.patch({ registerNotice: String(msg.message ?? '') });
        break;

      case 'kicked':
        // Two very different situations share this type. A duplicate login
        // means another device took the account and the socket is about to be
        // closed — that has to drop us to the login screen and forget the saved
        // credentials, or the auto-login loop would fight the other device.
        // A host kick only ends the room membership.
        if (msg.reason === 'duplicate_login') {
          this.credentials = null;
          clearCredentials();
          this.patch({
            ...INITIAL_STATE,
            connection: this.state.connection,
            kickedReason: String(msg.message ?? '다른 기기에서 로그인했습니다.'),
          });
        } else {
          this.patch({ screen: 'lobby', room: null, game: null, chat: [] });
          this.pushToast('error', String(msg.message ?? '방에서 추방되었습니다.'));
        }
        break;

      case 'maintenance_status':
        this.patch({ maintenance: msg as unknown as MaintenanceStatus });
        break;

      case 'room_list':
        this.patch({ rooms: (msg.rooms ?? []) as RoomListEntry[] });
        break;

      case 'room_joined':
        this.patch({ screen: 'waiting', chat: [], game: null });
        break;

      case 'reconnected':
        this.pushToast('info', `${String(msg.roomName ?? '방')}에 다시 연결했습니다.`);
        break;

      case 'room_state': {
        const room = msg.room as RoomState;
        this.patch({
          room,
          // A game that ended returns everyone to the waiting room; the server
          // sends room_state without a game_state to say so.
          screen: room.gameInProgress && this.state.game ? this.state.screen : 'waiting',
        });
        break;
      }

      case 'game_state':
        this.patch({ game: msg.state as TichuState, screen: 'game' });
        break;

      case 'restore_complete':
        this.onRestoreComplete(msg.destination as RestoreDestination);
        break;

      case 'room_left':
      case 'room_closed':
        this.patch({ screen: 'lobby', room: null, game: null, chat: [] });
        break;

      case 'chat_history':
        this.patch({ chat: (msg.messages ?? []) as ChatEntry[] });
        break;

      case 'chat_message':
        this.patch({
          chat: [...this.state.chat, msg as unknown as ChatEntry].slice(-100),
        });
        break;

      case 'error':
        this.pushToast('error', String(msg.message ?? '오류가 발생했습니다.'));
        break;

      default:
        // The protocol has ~135 inbound types; this client subscribes to a
        // slice of it and ignores the rest by design.
        break;
    }
  }

  private onLoginSuccess(msg: ServerMessage): void {
    this.patch({
      loginPending: false,
      loginError: null,
      kickedReason: null,
      auth: {
        playerId: String(msg.playerId),
        nickname: String(msg.nickname),
        authProvider: (msg.authProvider as AuthInfo['authProvider']) ?? 'local',
        isAdmin: msg.isAdmin === true,
        photoUrl: (msg.photoUrl as string | null) ?? null,
      },
      maintenance: (msg.maintenanceStatus as MaintenanceStatus) ?? null,
      screen: this.state.screen === 'login' ? 'lobby' : this.state.screen,
    });
    if (this.credentials) saveCredentialsIfRemembered(this.credentials);
    // The server may already have restored us into a running game; check_room
    // is the authoritative answer to "where do I belong". Its reply also
    // re-sends room_state/game_state, so nothing is lost on a page reload.
    this.socket.send({ type: 'check_room' });
  }

  private onRestoreComplete(destination: RestoreDestination): void {
    switch (destination) {
      case 'game':
        this.patch({ screen: 'game' });
        break;
      case 'waiting_room':
        this.patch({ screen: 'waiting' });
        break;
      case 'spectator':
        // Spectating is not implemented in this client yet; the server put us
        // in a spectator seat, so leave and land in the lobby rather than
        // showing an empty board.
        this.socket.send({ type: 'leave_room' });
        this.patch({ screen: 'lobby' });
        break;
      case 'lobby':
      default:
        this.patch({ screen: 'lobby', room: null, game: null });
        break;
    }
  }
}

// ---------------------------------------------------------------------------
// Credential persistence
//
// Same trade-off the Flutter client makes (session_service.dart:189): the
// server offers no refresh token, so "stay logged in" means keeping the
// password. Social login (2nd phase) will replace this with a provider token
// refresh, which is the reason to keep this behind a single pair of helpers.
// ---------------------------------------------------------------------------

let rememberChoice = true;

function loadCredentials(): StoredCredentials | null {
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as StoredCredentials;
    if (!parsed.username || !parsed.password) return null;
    return parsed;
  } catch {
    return null;
  }
}

function saveCredentials(creds: StoredCredentials): void {
  rememberChoice = true;
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(creds));
  } catch {
    // Private-mode or quota failure: session simply won't survive a reload.
  }
}

function saveCredentialsIfRemembered(creds: StoredCredentials): void {
  if (rememberChoice) saveCredentials(creds);
}

function clearCredentials(): void {
  rememberChoice = false;
  try {
    window.localStorage.removeItem(STORAGE_KEY);
  } catch {
    // ignore
  }
}
