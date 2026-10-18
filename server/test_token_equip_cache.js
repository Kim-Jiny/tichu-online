'use strict';
/**
 * 꾸미기 장착 캐시는 식으면 버리지 않고 다시 읽는다.
 *
 * 전에는 5분이 지나면 캐시에서 지웠고, 다시 채우는 곳은 로그인·장착
 * 변경·닉네임 변경뿐이었다. 그래서 유효기간이 한참 남은 '방 목록 강조' 가
 * 접속 5분 뒤 사라졌다 — 돈을 내고 산 효과가 가만히 있다가 없어졌다.
 *
 * 반대쪽도 본다. 말풍선은 소켓에 담긴 값을 읽어, 접속 중에 아이템이
 * 만료되어도 효과가 남았다. 이제 같은 캐시를 보므로 TTL 안에 반영된다.
 *
 * server.js 를 require 하면 포트와 DB 를 잡으므로, 그 조각만 떼어
 * 가짜 missions 모듈과 함께 평가한다.
 *
 *   node test_token_equip_cache.js
 */
const fs = require('fs');
const path = require('path');
const vm = require('vm');

let ok = true;
const chk = (n, c, d = '') => {
  console.log(c ? '  ok  ' : '  FAIL', n + (!c && d ? ` — ${d}` : ''));
  if (!c) ok = false;
};
const eq = (n, got, want) =>
  chk(n, got === want, `got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const src = fs.readFileSync(path.join(__dirname, 'server.js'), 'utf8');
function extract(name, kind = 'function') {
  const needle = kind === 'function' ? `function ${name}(` : `const ${name} = `;
  let start = src.indexOf(needle);
  if (start < 0) throw new Error(`server.js 에서 ${name} 을 찾지 못했다`);
  // async 를 빼고 자르면 안의 await 가 구문 오류가 된다.
  if (kind === 'function' && src.slice(start - 6, start) === 'async ') start -= 6;
  if (kind === 'const') {
    // 한 줄짜리 선언만 이 방식으로 뽑는다.
    return src.slice(start, src.indexOf('\n', start) + 1);
  }
  let i = src.indexOf('{', start), depth = 0;
  for (; i < src.length; i++) {
    if (src[i] === '{') depth++;
    else if (src[i] === '}' && --depth === 0) break;
  }
  return src.slice(start, i + 1);
}

/// 몇 번 물어봤는지 세는 가짜 missions.
///
/// 평소에는 바로 답하지만, hold 를 켜면 답을 붙들고 있는다. 경쟁 상태는
/// "느린 조회가 돌아오는 시점" 이 전부라서, 그 시점을 테스트가 쥐어야
/// 순서를 확실히 만들 수 있다 — sleep 으로 맞추면 가끔만 재현된다.
let queries = 0;
let equipped = { roomHighlight: 'glow', bubble: 'bubble_a' };
let hold = null;   // { release(value) }
const missions = {
  getEquippedKeys: async (_nick) => {
    queries++;
    if (!hold) return equipped;
    const snapshot = equipped;
    return new Promise((resolve) => { hold.release = () => resolve(snapshot); });
  },
};

const ctx = {
  missions, console, Date, Map, Set, setTimeout, Promise,
  module: { exports: {} },
};
vm.createContext(ctx);
vm.runInContext([
  // TTL 은 테스트에서 짧게 덮는다. 5분을 기다릴 수는 없다.
  'const TOKEN_EQUIP_TTL_MS = 40;',
  'const tokenEquipsByNick = new Map();',
  'const tokenEquipAt = new Map();',
  extract('forgetTokenEquips'),
  extract('tokenEquipRefreshing', 'const'),
  'let tokenEquipSeq = 0;',
  extract('tokenEquipGen', 'const'),
  extract('putTokenEquips'),
  extract('revalidateTokenEquips'),
  extract('cachedTokenEquips'),
  extract('equippedBubble'),
  extract('refreshTokenEquips'),
  `module.exports = { tokenEquipsByNick, tokenEquipAt, tokenEquipGen,
     cachedTokenEquips, equippedBubble, forgetTokenEquips, refreshTokenEquips };`,
].join('\n'), ctx);
const M = ctx.module.exports;

(async () => {
  const NICK = '꾸미기';
  // 로그인 시점처럼 캐시를 채운다.
  M.tokenEquipsByNick.set(NICK, equipped);
  M.tokenEquipAt.set(NICK, Date.now());

  console.log('[식기 전]');
  chk('강조가 보인다', M.cachedTokenEquips(NICK)?.roomHighlight === 'glow');
  chk('질의하지 않았다', queries === 0, `queries=${queries}`);

  console.log('\n[식은 뒤 — 사라지지 않는다]');
  await sleep(60);
  const stale = M.cachedTokenEquips(NICK);
  chk('식어도 강조가 그대로 보인다', stale?.roomHighlight === 'glow',
    JSON.stringify(stale));
  chk('뒤에서 다시 읽기를 시작했다', queries === 1, `queries=${queries}`);

  console.log('\n[같은 사람 몫을 한꺼번에 여러 번 묻지 않는다]');
  const before = queries;
  for (let i = 0; i < 20; i++) M.cachedTokenEquips(NICK);
  chk('연달아 읽어도 질의가 늘지 않는다', queries === before,
    `${before} -> ${queries}`);

  console.log('\n[만료는 TTL 안에 반영된다]');
  await sleep(10);                   // 위 갱신이 끝날 틈
  equipped = { roomHighlight: null, bubble: null };   // 아이템이 만료됐다
  await sleep(60);                   // 다시 식는다
  M.cachedTokenEquips(NICK);         // 갱신 시작
  await sleep(20);
  chk('강조가 없어진다', !M.cachedTokenEquips(NICK)?.roomHighlight);
  chk('말풍선도 없어진다', M.equippedBubble({ nickname: NICK }) === null);

  console.log('\n[늦게 끝난 조회가 최신 장착을 덮지 않는다]');
  {
    // 1) 식은 캐시를 읽어 백그라운드 조회를 시작시킨다(옛 상태를 들고 간다).
    // 2) 그 사이 장착을 바꾼다(재접속·장착 변경에 해당).
    // 3) 그 다음에 느린 조회가 끝난다.
    // 3 의 결과를 담으면 방금 바꾼 장착이 옛것으로 되돌아간다.
    equipped = { roomHighlight: 'old', bubble: 'bubble_old' };
    M.tokenEquipsByNick.set('늦참', equipped);
    M.tokenEquipAt.set('늦참', Date.now() - 1000);   // 식은 상태
    M.tokenEquipGen.set('늦참', 1);

    hold = {};
    M.cachedTokenEquips('늦참');        // 조회 시작 — 'old' 를 들고 간다
    chk('느린 조회가 시작됐다', typeof hold.release === 'function');

    // 장착 변경이 먼저 끝난다.
    equipped = { roomHighlight: 'new', bubble: 'bubble_new' };
    const ws = { nickname: '늦참' };
    const prevHold = hold;
    hold = null;                         // 이번 조회는 즉시 답하게
    await M.refreshTokenEquips(ws);
    eq('바꾼 장착이 담겼다', M.cachedTokenEquips('늦참')?.roomHighlight, 'new');

    // 이제 아까 붙들어 둔 느린 조회가 끝난다.
    prevHold.release();
    await sleep(20);
    eq('늦게 끝난 조회가 덮지 않았다',
      M.cachedTokenEquips('늦참')?.roomHighlight, 'new');
    eq('말풍선도 최신 그대로', M.equippedBubble(ws), 'bubble_new');
  }

  console.log('\n[접속이 끊긴 사람은 되살리지 않는다]');
  // 닉네임은 재사용된다. 떠난 사람의 장착이 다음 사람에게 넘어가면 안 된다.
  equipped = { roomHighlight: 'glow', bubble: 'bubble_a' };
  M.tokenEquipAt.set(NICK, Date.now() - 1000);  // 식은 상태로 만든다
  M.cachedTokenEquips(NICK);                    // 갱신 시작
  M.forgetTokenEquips(NICK);                    // 그 사이 접속 종료
  await sleep(30);
  chk('캐시가 비어 있다', M.cachedTokenEquips(NICK) === null,
    JSON.stringify(M.tokenEquipsByNick.get(NICK)));

  console.log(ok ? '\n전부 통과' : '\n실패 있음');
  process.exit(ok ? 0 : 1);
})();
