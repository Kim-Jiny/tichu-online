import type { ClientMessage, ServerMessage } from './types';

/**
 * The single WebSocket to the game server.
 *
 * Mirrors the Flutter client's transport behaviour (network_service.dart:44-47):
 * an application-level `ping` every 5s, socket declared dead after 15s without a
 * `pong`. That matters because the server's own ws-level ping/pong (15s, 2
 * misses) is far slower to notice a half-open connection, and a half-open
 * socket during a turn reads to the player as the game freezing.
 *
 * Auto-reconnect is transport-level only. Re-authentication is the session
 * layer's job (see session.ts) because the server keeps no session token — auth
 * lives on the server's `ws` object and dies with the socket.
 */

const PING_INTERVAL_MS = 5000;
const PONG_TIMEOUT_MS = 15000;
const RECONNECT_DELAYS_MS = [500, 1000, 2000, 4000, 8000];

export type ConnectionState =
  | 'idle'
  | 'connecting'
  | 'open'
  | 'reconnecting'
  | 'closed';

export type MessageHandler = (msg: ServerMessage) => void;
export type StateHandler = (state: ConnectionState) => void;

function defaultUrl(): string {
  const configured = import.meta.env.VITE_WS_URL;
  if (configured) return configured;
  // Same-origin deployment: the app is served from /play/ on the very host that
  // terminates the WebSocket at `/`.
  const scheme = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  return `${scheme}//${window.location.host}`;
}

export class GameSocket {
  private ws: WebSocket | null = null;
  private url: string;
  private state: ConnectionState = 'idle';
  private messageHandlers = new Set<MessageHandler>();
  private stateHandlers = new Set<StateHandler>();
  private pingTimer: number | null = null;
  private pongDeadline = 0;
  private reconnectTimer: number | null = null;
  private reconnectAttempt = 0;
  /** Set when the caller asked to stop; suppresses auto-reconnect. */
  private intentionallyClosed = false;

  constructor(url: string = defaultUrl()) {
    this.url = url;
  }

  getState(): ConnectionState {
    return this.state;
  }

  onMessage(handler: MessageHandler): () => void {
    this.messageHandlers.add(handler);
    return () => this.messageHandlers.delete(handler);
  }

  onStateChange(handler: StateHandler): () => void {
    this.stateHandlers.add(handler);
    return () => this.stateHandlers.delete(handler);
  }

  connect(): void {
    if (this.ws && (this.state === 'open' || this.state === 'connecting')) return;
    this.intentionallyClosed = false;
    this.openSocket();
  }

  close(): void {
    this.intentionallyClosed = true;
    this.clearTimers();
    this.ws?.close();
    this.ws = null;
    this.setState('closed');
  }

  /**
   * Fire-and-forget. Messages sent while the socket is down are dropped rather
   * than queued: the server rebuilds full state on reconnect anyway, so a
   * replayed action would at best be redundant and at worst be a double play.
   */
  send(msg: ClientMessage): boolean {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) return false;
    this.ws.send(JSON.stringify(msg));
    return true;
  }

  private openSocket(): void {
    this.setState(this.reconnectAttempt > 0 ? 'reconnecting' : 'connecting');
    const ws = new WebSocket(this.url);
    this.ws = ws;

    ws.onopen = () => {
      if (this.ws !== ws) return;
      this.reconnectAttempt = 0;
      this.setState('open');
      this.startHeartbeat();
    };

    ws.onmessage = (event) => {
      if (this.ws !== ws) return;
      let data: ServerMessage;
      try {
        data = JSON.parse(event.data as string) as ServerMessage;
      } catch {
        return;
      }
      if (data.type === 'pong') {
        this.pongDeadline = Date.now() + PONG_TIMEOUT_MS;
        return;
      }
      for (const handler of this.messageHandlers) handler(data);
    };

    ws.onerror = () => {
      // `onclose` always follows; reconnect is handled there so the two paths
      // can't both schedule a retry.
    };

    ws.onclose = () => {
      if (this.ws !== ws) return;
      this.clearTimers();
      this.ws = null;
      if (this.intentionallyClosed) {
        this.setState('closed');
        return;
      }
      this.scheduleReconnect();
    };
  }

  private startHeartbeat(): void {
    this.pongDeadline = Date.now() + PONG_TIMEOUT_MS;
    this.pingTimer = window.setInterval(() => {
      if (Date.now() > this.pongDeadline) {
        // Half-open: the socket looks fine to the browser but nothing is coming
        // back. Force it closed so the reconnect path runs.
        this.ws?.close();
        return;
      }
      this.send({ type: 'ping' });
    }, PING_INTERVAL_MS);
  }

  private scheduleReconnect(): void {
    const delay =
      RECONNECT_DELAYS_MS[Math.min(this.reconnectAttempt, RECONNECT_DELAYS_MS.length - 1)];
    this.reconnectAttempt += 1;
    this.setState('reconnecting');
    this.reconnectTimer = window.setTimeout(() => this.openSocket(), delay);
  }

  private clearTimers(): void {
    if (this.pingTimer !== null) {
      window.clearInterval(this.pingTimer);
      this.pingTimer = null;
    }
    if (this.reconnectTimer !== null) {
      window.clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
  }

  private setState(next: ConnectionState): void {
    if (this.state === next) return;
    this.state = next;
    for (const handler of this.stateHandlers) handler(next);
  }
}
