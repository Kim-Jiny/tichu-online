'use strict';

/**
 * Admin-created "filler" rooms: a room whose every seat is taken, playing itself
 * forever until an admin dismantles it.
 *
 * Why: an empty lobby looks dead. This lets an operator put a few visibly-active
 * rooms in the list — one per game type — that anyone can spectate.
 *
 * How the seats work: seat 0 is a synthetic host with no socket, and the rest are
 * ordinary bots. The host is what keeps the room alive — both the auto-return
 * cleanup and the zombie sweep keep any room that still has a non-bot seat marked
 * connected — and it is what this module plays for, by asking the game itself
 * what a timed-out player would do (`getAutoTimeoutAction`). That call is
 * implemented by every game class, which is the only reason this works for all
 * four games without a line of game-specific code here.
 *
 * The host never has a socket, so nothing is ever sent to it: the broadcast loop
 * looks the recipient up with findWsByPlayerId and skips misses.
 *
 * Nobody can take a seat (join is refused elsewhere — every seat is filled by
 * design), and their results are never saved: no real player is in them, so a
 * record would be noise in the rankings. Spectating is on by default and can be
 * switched off per room, which leaves the room as pure lobby decoration.
 *
 * State is in memory: a restart drops the rooms, and the admin re-adds them.
 */

let deps = null;

/**
 * @param {object} d
 *  - lobby, broadcastRoomState, broadcastRoomList, sendGameStateToAll
 *  - broadcastGameEvent, playerStillNeedsToAct, scheduleBotCheck
 */
function init(d) {
  deps = d;
}

/** roomId -> { roomId, hostId, nickname, gameType, botSpeed, createdAt } */
const active = new Map();

let nextId = 1;

/** How often each room is nudged. Slow enough to look like a person thinking. */
const TICK_MS = 900;
let ticker = null;

// 게임별 정원 상한. 마이티만 5/6인 모두 지원해서 하한/상한이 다르다 —
// 그래서 상한(6)을 여기 두고, 기본값은 DEFAULT_PLAYERS 에서 따로 잡는다.
const MAX_PLAYERS = {
  tichu: 4,
  skull_king: 6,
  love_letter: 4,
  mighty: 6,
};
const MIN_PLAYERS = {
  tichu: 4,
  skull_king: 6,
  love_letter: 4,
  mighty: 5,
};
const DEFAULT_PLAYERS = {
  tichu: 4,
  skull_king: 6,
  love_letter: 4,
  mighty: 5,
};

const BOT_STRATEGY = {
  tichu: 'winrate',
  mighty: 'mixoracle',
  skull_king: 'heuristic',
  love_letter: 'heuristic',
};

function isFillerRoom(roomId) {
  return active.has(roomId);
}

function isFillerHost(playerId) {
  for (const info of active.values()) {
    if (info.hostId === playerId) return true;
  }
  return false;
}

/**
 * Is this nickname one of the synthetic hosts?
 *
 * The host seat has no account behind it, so a profile lookup for it finds
 * nothing — callers use this to answer with "private profile" instead of
 * "user not found", which is what a seat with no account should look like from
 * the outside.
 */
function isFillerNickname(nickname) {
  if (!nickname) return false;
  for (const info of active.values()) {
    if (info.nickname === nickname) return true;
  }
  return false;
}

function list() {
  return [...active.values()].map((info) => {
    const room = deps.lobby.getRoom(info.roomId);
    return {
      ...info,
      exists: !!room,
      roomName: room ? room.name : null,
      inGame: !!(room && room.game),
      phase: room && room.game ? room.game.state : null,
      spectators: room ? room.spectators.length : 0,
      // Read from the room, not a stored copy — the admin can flip it live.
      allowSpectators: room ? room.allowSpectators !== false : false,
      isPrivate: room ? !!room.isPrivate : false,
    };
  });
}

/**
 * @returns {{success: boolean, message?: string, roomId?: string}}
 */
function create({
  nickname,
  gameType = 'tichu',
  botSpeed = 'normal',
  roomName,
  allowSpectators = true,
  password = '',
  maxPlayers,
}) {
  if (!deps) return { success: false, message: 'filler rooms not initialised' };
  const name = (nickname || '').trim();
  if (name.length < 2 || name.length > 10) {
    return { success: false, message: '닉네임은 2~10자여야 합니다' };
  }
  if (!MAX_PLAYERS[gameType]) {
    return { success: false, message: `알 수 없는 게임 타입: ${gameType}` };
  }
  if (!['fast', 'normal', 'slow'].includes(botSpeed)) {
    return { success: false, message: `알 수 없는 봇 속도: ${botSpeed}` };
  }
  // Same cap the room-create path applies. Empty means a public room.
  const roomPassword = (password || '').trim().slice(0, 20);

  const hostId = `filler_${nextId++}`;
  const resolvedMax = maxPlayers || DEFAULT_PLAYERS[gameType];
  if (
    resolvedMax < MIN_PLAYERS[gameType] ||
    resolvedMax > MAX_PLAYERS[gameType]
  ) {
    return {
      success: false,
      message: `${gameType} 방은 ${MIN_PLAYERS[gameType]}~${MAX_PLAYERS[gameType]}인만 지원합니다`,
    };
  }
  const room = deps.lobby.createRoom(
    (roomName || name).slice(0, 20),
    hostId,
    name,
    // A password makes the room private. Spectators are then asked for it too
    // (addSpectator validates it), which is the point — a locked filler room
    // is one only people who were given the password can watch or enter.
    roomPassword,
    false,   // never ranked
    30,
    1000,
    gameType,
    resolvedMax,
    [],
    allowSpectators !== false,
  );

  // The constructor seats the host as an ordinary un-ready player. Mark it so the
  // rest of the server can recognise it, and pre-ready it so startGame passes.
  room.players[0] = {
    ...room.players[0],
    connected: true,
    ready: true,
    isFiller: true,
  };

  const strategy = BOT_STRATEGY[gameType] || 'heuristic';
  let guard = 0;
  while (room.getPlayerCount() < room.getEffectiveMaxPlayers() && guard++ < 12) {
    const added = room.addBot(null, 'ko', botSpeed, strategy);
    if (!added.success) {
      deps.lobby.removeRoom(room.id);
      return { success: false, message: `봇 추가 실패: ${added.messageKey}` };
    }
  }

  active.set(room.id, {
    roomId: room.id,
    hostId,
    nickname: name,
    gameType,
    botSpeed,
    createdAt: Date.now(),
  });

  deps.broadcastRoomState(room.id);
  deps.broadcastRoomList();
  ensureTicker();
  console.log(
    `[filler] created ${room.id} "${name}" type=${gameType} bots=${botSpeed}`
    + ` spectators=${allowSpectators !== false ? 'on' : 'off'}`
    + (roomPassword ? ' private' : ''),
  );
  return { success: true, roomId: room.id };
}

/**
 * Flip spectating for a running filler room.
 *
 * Applies to people trying to come in: anyone already watching stays, the same
 * way changing any room setting does not evict whoever is already seated.
 */
function setAllowSpectators(roomId, allow) {
  const info = active.get(roomId);
  if (!info) return { success: false, message: '없는 채움 방입니다' };
  const room = deps.lobby.getRoom(roomId);
  if (!room) return { success: false, message: '방이 이미 사라졌습니다' };
  room.allowSpectators = allow !== false;
  deps.broadcastRoomState(roomId);
  deps.broadcastRoomList();
  console.log(`[filler] ${roomId} allowSpectators=${room.allowSpectators}`);
  return { success: true };
}

function dismantle(roomId) {
  const info = active.get(roomId);
  if (!info) return { success: false, message: '없는 채움 방입니다' };
  active.delete(roomId);
  const room = deps.lobby.getRoom(roomId);
  if (room) {
    // Spectators are watching this; the lobby broadcast tells their client the
    // room is gone (same path as a room closing normally).
    deps.lobby.removeRoom(roomId);
  }
  deps.broadcastRoomList();
  console.log(`[filler] dismantled ${roomId} "${info.nickname}"`);
  if (active.size === 0) stopTicker();
  return { success: true };
}

function dismantleAll() {
  for (const roomId of [...active.keys()]) dismantle(roomId);
}

/**
 * One nudge for one room: start a game if idle, otherwise act if it is the
 * host's turn.
 */
function tickRoom(info) {
  const room = deps.lobby.getRoom(info.roomId);
  if (!room) {
    // Something else removed it (drain, sweep). Forget it rather than resurrect
    // a room the rest of the server has already let go.
    active.delete(info.roomId);
    return;
  }

  if (!room.game) {
    if (room.getPlayerCount() < room.getEffectiveMaxPlayers()) return;
    if (!room.areAllReady()) {
      // Bots come back ready; the host is ours to re-ready after a round reset.
      const host = room.players.find((p) => p && p.id === info.hostId);
      if (host) host.ready = true;
      if (!room.areAllReady()) return;
    }
    if (room.startGame() !== false) {
      deps.broadcastRoomState(room.id);
      deps.broadcastRoomList();
      deps.sendGameStateToAll(room.id);
    }
    return;
  }

  // Only act when the game genuinely wants this seat to move. Same guard the
  // turn-timeout path uses, so we never fire into a state where the action would
  // no-op.
  if (!deps.playerStillNeedsToAct(room.gameType, room.game, info.hostId)) return;

  const action = room.game.getAutoTimeoutAction(info.hostId);
  if (!action) return;
  const result = room.game.handleAction(info.hostId, action);
  if (!result || !result.success) return;
  if (result.broadcast) deps.broadcastGameEvent(room.id, result.broadcast);
  deps.sendGameStateToAll(room.id);
}

function ensureTicker() {
  if (ticker) return;
  ticker = setInterval(() => {
    for (const info of [...active.values()]) {
      try {
        tickRoom(info);
      } catch (err) {
        console.error(`[filler] tick failed for ${info.roomId}:`, err.message);
      }
    }
    if (active.size === 0) stopTicker();
  }, TICK_MS);
  if (ticker.unref) ticker.unref();
}

function stopTicker() {
  if (!ticker) return;
  clearInterval(ticker);
  ticker = null;
}

module.exports = {
  init,
  create,
  setAllowSpectators,
  dismantle,
  dismantleAll,
  list,
  isFillerRoom,
  isFillerHost,
  isFillerNickname,
  MAX_PLAYERS,
};
