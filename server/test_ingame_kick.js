'use strict';
/**
 * 게임 중 강퇴을 언제 허용하는가.
 *
 * 이 기능에서 위험한 쪽은 "강퇴가 안 되는 것" 이 아니라 "되면 안 되는데
 * 되는 것" 이다. 방장이 지고 있다고 강한 상대를 봇으로 바꾸거나, 잠깐
 * 끊겼다 돌아와 두고 있는 사람이 잘리면 그건 기능이 아니라 사고다.
 *
 * 그래서 막는 조건 하나하나가 실제로 막는지 본다. 조건을 지웠을 때 여기가
 * 빨개지지 않으면 그 조건은 없는 것과 같다.
 */

const { kickableReason, kickBlockedBy, KICK_BLOCKED } = require('./ingame_kick');

let failures = 0;
function check(cond, msg) {
  if (cond) console.log(`  ok   ${msg}`);
  else { failures++; console.log(`  FAIL ${msg}`); }
}

const HOST = 'p_host';
const AFK = 'p_afk';

function room(over = {}) {
  return {
    id: 'r1',
    hostId: HOST,
    isRanked: false,
    players: [
      { id: HOST, isBot: false },
      { id: AFK, isBot: false },
      { id: 'bot_1', isBot: true },
      null,
    ],
    game: { state: 'playing', deserted: false, playerNames: { [HOST]: '방장', [AFK]: '잠수' } },
    ...over,
  };
}
// 붙어는 있는데 한 번 넘겼고 지금도 그 사람을 기다리는 중 — 자를 수 있는 상태
const STALLING = { connected: true, missedTurns: 1, waitingOn: [AFK], isFillerHost: false };
const GONE = { connected: false, missedTurns: 0, waitingOn: [], isFillerHost: false };

console.log('자를 수 있는 경우');
check(kickableReason(room(), AFK, STALLING) === 'stalling',
  '턴을 넘겼고 지금도 그 사람을 기다리는 중');
check(kickableReason(room(), AFK, GONE) === 'disconnected',
  '접속이 끊겼다 — 턴을 넘긴 적이 없어도 된다');
check(kickableReason(room(), AFK,
  { ...STALLING, missedTurns: 3 }) === 'stalling', '여러 번 넘긴 사람도 당연히');

console.log('\n막아야 하는 경우');
const blocked = [
  ['방장 자신은 못 자른다', room(), HOST, STALLING, KICK_BLOCKED.self],
  ['랭크전에서는 못 자른다', room({ isRanked: true }), AFK, STALLING, KICK_BLOCKED.ranked],
  ['판이 끝났으면 못 자른다',
    room({ game: { ...room().game, state: 'game_end' } }), AFK, STALLING, KICK_BLOCKED.gameOver],
  ['이미 탈주 처리 중이면 못 자른다',
    room({ game: { ...room().game, deserted: true } }), AFK, STALLING, KICK_BLOCKED.gameOver],
  ['게임이 없으면(대기실) 못 자른다', room({ game: null }), AFK, STALLING, KICK_BLOCKED.noGame],
  ['봇은 자르는 게 아니다', room(), 'bot_1', STALLING, KICK_BLOCKED.bot],
  ['앉아 있지 않은 사람(관전자)은 못 자른다', room(), 'p_ghost', STALLING, KICK_BLOCKED.notSeated],
  ['운영이 세운 채우기 방 주인은 못 자른다',
    room(), AFK, { ...STALLING, isFillerHost: true }, KICK_BLOCKED.filler],
  ['한 번도 안 넘긴 사람은 못 자른다 — 이제 막 차례가 온 것뿐이다',
    room(), AFK, { ...STALLING, missedTurns: 0 }, KICK_BLOCKED.playing],
  ['지금 그 사람 차례가 아니면 못 자른다 — 아까 놓쳤어도 지금은 두고 있다',
    room(), AFK, { ...STALLING, waitingOn: [HOST] }, KICK_BLOCKED.playing],
  ['아무도 안 기다리는 중이면 못 자른다 (연출·정산 대기)',
    room(), AFK, { ...STALLING, waitingOn: [] }, KICK_BLOCKED.playing],
];
for (const [msg, r, target, facts, want] of blocked) {
  const why = kickBlockedBy(r, target, facts);
  check(kickableReason(r, target, facts) === null && why === want,
    `${msg} (${why || '안 막힘!'})`);
}

console.log('\n이번 판에서 이미 빠진 사람');
// 마이티에서 죽었거나, 러브레터에서 탈락했거나, 티츄에서 손을 다 털었다.
// 판은 이 사람 없이 굴러가고 있으므로 접속이 끊겼어도 자를 이유가 없다 —
// 기다림이 줄어드는 게 아니라 탈주 기록만 하나 남는다.
check(kickBlockedBy(room(), AFK, { ...GONE, outOfRound: true })
        === KICK_BLOCKED.outOfRound,
  '빠진 사람은 접속이 끊겨도 못 자른다');
check(kickableReason(room(), AFK, { ...GONE, outOfRound: true }) === null,
  '그 경우 버튼도 안 뜬다');
check(kickableReason(room(), AFK, { ...STALLING, outOfRound: true }) === null,
  '빠진 사람은 붙어 있어도 못 자른다');
// 다음 판이 시작되면 다시 대상이 된다 — 그때는 이 사람 차례를 실제로 기다린다.
check(kickableReason(room(), AFK, { ...GONE, outOfRound: false }) === 'disconnected',
  '다음 판에서는 다시 자를 수 있다');

console.log('\n복귀 판정');
// 버튼이 뜬 뒤 대상이 돌아와 한 수 두면, 타이머는 다음 사람을 기다린다.
// 그 순간부터 강퇴는 실패해야 한다 — 화면에 버튼이 남아 있어도.
const returned = { ...STALLING, waitingOn: ['p_next'] };
check(kickableReason(room(), AFK, returned) === null,
  '돌아와서 한 수 두면 그 즉시 못 자른다');
// 끊긴 사람이 돌아와 붙으면, 아직 한 번도 안 넘겼으므로 못 자른다.
check(kickableReason(room(), AFK,
  { connected: true, missedTurns: 0, waitingOn: [AFK] }) === null,
  '끊겼다가 돌아오면 넘긴 기록이 없는 한 못 자른다');

console.log(failures === 0 ? '\n전부 통과' : `\n${failures}건 실패`);
process.exit(failures === 0 ? 0 : 1);
