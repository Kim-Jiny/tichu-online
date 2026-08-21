'use strict';
/**
 * 게임 중 강퇴을 허용할지 말지.
 *
 * 문의로 들어온 요구는 "잠수 타는 사람을 기다리는 시간이 아깝다" 였다. 대응이
 * 없던 게 아니라 오래 걸렸다 — 턴 3회 초과라 기본 30초 방에서도 최소 90초,
 * 방장이 60초로 잡았으면 3분이다.
 *
 * 그래서 방장에게 "잠수가 확인된 사람만" 즉시 봇으로 바꿀 권한을 준다.
 * 기다림을 없애는 게 목적이지 방장에게 권력을 주는 게 목적이 아니다. 권한을
 * 넓게 주고 신고로 사후 처리하는 것보다, 애초에 누를 수 없게 하는 쪽을 택했다.
 *
 * server.js 가 아니라 여기 있는 이유는 테스트다. server.js 는 require 하는
 * 순간 웹소켓 서버가 뜨기 때문에, 규칙이 거기 있으면 확인하려고 서버를
 * 세워야 한다. 그러면 결국 아무도 확인하지 않는다.
 *
 * 기획: docs/PLAN_INGAME_KICK.md
 */

/// 강퇴를 막는 이유들. 화면에 그대로 쓰지는 않지만, 테스트가 "왜 막혔는지"
/// 를 구분할 수 있어야 조건을 하나 지웠을 때 그게 드러난다.
const KICK_BLOCKED = {
  noGame: 'no_game',
  gameOver: 'game_over',
  ranked: 'ranked',
  self: 'host_self',
  bot: 'already_bot',
  notSeated: 'not_seated',
  filler: 'filler_host',
  playing: 'still_playing',
};

/**
 * 지금 이 사람을 강퇴할 수 있는가.
 *
 * @param room  게임이 붙어 있는 방
 * @param playerId  자르려는 대상
 * @param facts  server.js 가 모아 주는 사실들
 *   - connected     대상의 소켓이 살아 있는가
 *   - missedTurns   이번 판에 턴을 넘긴 횟수
 *   - waitingOn     지금 타이머가 응답을 기다리는 사람들
 *   - isFillerHost  운영이 세운 채우기 방의 주인인가
 * @returns 'disconnected' | 'stalling' | null
 */
function kickableReason(room, playerId, facts = {}) {
  if (kickBlockedBy(room, playerId, facts)) return null;
  // 접속이 끊겼다. 기다릴 사람이 아예 없는 자리다.
  if (facts.connected === false) return 'disconnected';
  return 'stalling';
}

/// 못 자르는 이유. 자를 수 있으면 null. kickableReason 이 쓰지만 따로 두는
/// 이유는, 조건이 여덟 개라 어디서 막혔는지 말할 수 있어야 하기 때문이다.
function kickBlockedBy(room, playerId, facts = {}) {
  if (!room || !room.game) return KICK_BLOCKED.noGame;
  if (room.game.state === 'game_end' || room.game.deserted) return KICK_BLOCKED.gameOver;
  // 랭크는 점수가 걸려 있어 자리 교체 자체를 지금도 막고 있다. 잠수를 만나면
  // 기존대로 3회 타임아웃까지 기다린다.
  if (room.isRanked) return KICK_BLOCKED.ranked;
  // 방장 자신은 못 자른다. 방장이 잠수면 아무도 못 자르고 기존 3회 규칙이
  // 그대로 적용된다.
  if (!playerId || playerId === room.hostId) return KICK_BLOCKED.self;
  if (facts.isFillerHost) return KICK_BLOCKED.filler;

  const seat = (room.players || []).find((p) => p !== null && p && p.id === playerId);
  if (!seat) return KICK_BLOCKED.notSeated;
  if (seat.isBot) return KICK_BLOCKED.bot;

  if (facts.connected === false) return null;

  // 붙어는 있는데 안 두는 경우. 이번 판에 턴을 한 번 이상 넘겼고, **지금도**
  // 그 사람 때문에 판이 멈춰 있을 때만 자를 수 있다.
  //
  // 두 조건이 다 필요하다. 앞의 것만으로는 아까 한 번 놓친 뒤 멀쩡히 두고
  // 있는 사람이 잘리고, 뒤의 것만으로는 이제 막 차례가 온 사람이 잘린다.
  // 이 두 개가 "지고 있으니까 자른다", "강한 상대를 봇으로 바꾼다" 를 막는
  // 장치다.
  if ((facts.missedTurns || 0) < 1) return KICK_BLOCKED.playing;
  if (!(facts.waitingOn || []).includes(playerId)) return KICK_BLOCKED.playing;
  return null;
}

module.exports = { kickableReason, kickBlockedBy, KICK_BLOCKED };
