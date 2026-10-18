'use strict';
/**
 * 5번 해적(후아니타)을 구버전 앱에게 내려 보낼 때의 id 변환.
 *
 * 공식 룰대로 기본 덱에 해적이 5장 들어간다. 그런데 후아니타의 그림은
 * 3.3.0 번들에서 처음 들어갔고, 3.2.0 은 `sk_pirate{번호}.webp` 를 찾으니
 * 5번에서 없는 에셋에 걸려 카드 자리에 색칠된 사각형을 띄운다. 그래서
 * 구버전에게만 번호 없는 id(`sk_pirate`)로 바꿔 보낸다 — 그 그림은 3.2.0
 * 번들에도 있어서, 이름만 모르는 일반 해적으로 제대로 보인다.
 *
 * 이 변환이 틀리는 방식은 두 가지뿐인데 둘 다 조용하다:
 *   - 일부 경로에서만 바뀐다 → 그 경로에서만 카드가 깨진다.
 *   - 최신 버전에게도 바뀐다 → 이름 있는 해적이 이름을 잃는다.
 * 그래서 경로가 아니라 함수 수준에서 양방향을 다 묶는다.
 *
 * 서버를 띄우지 않고 server.js 에서 함수만 꺼내 쓴다(아래 참고).
 *
 *   node test_sk_pirate_legacy_id.js
 */
const fs = require('fs');
const path = require('path');
const vm = require('vm');

let ok = true;
const chk = (n, c) => { console.log(c ? '  ok  ' : '  FAIL', n); if (!c) ok = false; };

// server.js 를 require 하면 포트를 잡고 DB 에 붙는다. 여기서 보려는 것은
// 순수 함수 네 개뿐이라, 그 조각만 떼어 평가한다. 조각을 손으로 베껼
// 수는 없다 — 그러면 테스트가 실제 코드와 따로 늙는다.
const src = fs.readFileSync(path.join(__dirname, 'server.js'), 'utf8');
function extract(name, kind = 'function') {
  const needle = kind === 'function' ? `function ${name}(` : `const ${name} = `;
  let start = src.indexOf(needle);
  if (start < 0) throw new Error(`server.js 에서 ${name} 을 찾지 못했다`);
  // async 를 빼고 자르면 안의 await 가 구문 오류가 된다.
  if (kind === 'function' && src.slice(start - 6, start) === 'async ') start -= 6;
  if (kind === 'const') {
    const end = src.indexOf('\n', start);
    return src.slice(start, end + 1);
  }
  // 중괄호 짝을 세어 함수 끝까지.
  let i = src.indexOf('{', start), depth = 0;
  for (; i < src.length; i++) {
    if (src[i] === '{') depth++;
    else if (src[i] === '}' && --depth === 0) break;
  }
  return src.slice(start, i + 1);
}

const ctx = { module: { exports: {} }, console };
vm.createContext(ctx);
vm.runInContext(
  [
    extract('SK_PIRATE_MIN_VERSION', 'const'),
    extract('LEGACY_PIRATE5_ID', 'const'),
    extract('LEGACY_PIRATE5_ALIAS', 'const'),
    extract('compareVersions'),
    extract('clientSupportsSKPirate'),
    extract('serializeForClient'),
    extract('normalizeLegacyPirateId'),
    extract('sendTo'),
    'module.exports = { serializeForClient, normalizeLegacyPirateId, sendTo, SK_PIRATE_MIN_VERSION };',
  ].join('\n'),
  ctx,
);
const { serializeForClient, normalizeLegacyPirateId, sendTo, SK_PIRATE_MIN_VERSION } = ctx.module.exports;

chk('게이트 버전은 3.3.0', SK_PIRATE_MIN_VERSION === '3.3.0');

const OLD = { appVersion: '3.2.0' };
const NEW = { appVersion: '3.3.0' };
const NEWER = { appVersion: '3.4.1' };
const NOVER = {}; // 버전을 안 보낸 아주 옛 클라이언트

console.log('\n[내려 보낼 때]');
const hand = {
  type: 'game_state',
  state: {
    myCards: ['sk_pirate_4', 'sk_pirate_5', 'sk_yellow_7'],
    currentTrick: [{ playerId: 'a', cardId: 'sk_pirate_5' }],
  },
};
const oldStr = serializeForClient(OLD, hand);
chk('구버전: 5번 해적이 번호 없는 해적으로',
  oldStr.includes('"sk_pirate"') && !oldStr.includes('"sk_pirate_5"'));
chk('구버전: 4번 해적은 그대로', oldStr.includes('"sk_pirate_4"'));
chk('구버전: 트릭에 놓인 카드도 바뀐다',
  JSON.parse(oldStr).state.currentTrick[0].cardId === 'sk_pirate');
chk('버전 미상도 구버전으로 취급', serializeForClient(NOVER, hand).includes('"sk_pirate"'));

for (const [label, ws] of [['3.3.0', NEW], ['3.4.1', NEWER]]) {
  const str = serializeForClient(ws, hand);
  chk(`${label}: 손대지 않는다`,
    str === JSON.stringify(hand) && str.includes('"sk_pirate_5"'));
}

// 카드가 없는 메시지는 그대로 나가야 한다(대부분의 메시지가 이쪽이다).
// 따옴표까지 포함해 바꾸므로 더 긴 글자의 일부는 건드리지 않는다.
const plain = { type: 'chat', message: 'sk_pirate_55 는 카드가 아니다' };
chk('카드 id 가 아닌 글자는 건드리지 않는다',
  serializeForClient(OLD, plain) === JSON.stringify(plain));

console.log('\n[되돌려 받을 때]');
const a = { type: 'play_card', cardId: 'sk_pirate' };
normalizeLegacyPirateId(OLD, a);
chk('구버전이 낸 일반 해적 = 5번 해적', a.cardId === 'sk_pirate_5');

const b = { type: 'play_card', cardId: 'sk_pirate_4' };
normalizeLegacyPirateId(OLD, b);
chk('다른 해적은 그대로', b.cardId === 'sk_pirate_4');

const c = { type: 'play_card', cardId: 'sk_pirate' };
normalizeLegacyPirateId(NEW, c);
chk('최신 버전이 보낸 것은 손대지 않는다 — 별칭을 받은 적이 없다',
  c.cardId === 'sk_pirate');

const d = { type: 'use_pirate_ability', discard: ['sk_pirate', 'sk_green_2'] };
normalizeLegacyPirateId(OLD, d);
chk('카드 목록 안에서도 되돌린다', d.discard[0] === 'sk_pirate_5');

normalizeLegacyPirateId(OLD, null); // 터지지 않아야 한다
chk('빈 메시지에도 터지지 않는다', true);

console.log('\n[왕복]');
// 내려 보낸 id 를 그대로 되돌려 받으면 원래 카드로 돌아와야 한다.
// 이 둘이 어긋나면 구버전 유저는 그 카드를 영원히 낼 수 없다.
const sent = JSON.parse(serializeForClient(OLD, {
  state: { myCards: ['sk_pirate_5'] },
})).state.myCards[0];
const back = { type: 'play_card', cardId: sent };
normalizeLegacyPirateId(OLD, back);
chk('왕복하면 제 카드로 돌아온다', back.cardId === 'sk_pirate_5');

console.log('\n[sendTo 배선]');
// 변환 함수가 맞아도 sendTo 가 그것을 쓰지 않으면 아무 효과가 없다. 실제
// 소켓 흐름 전체를 여기서 돌릴 수는 없으니, 모든 메시지가 지나가는 그
// 함수가 소켓마다 다른 문자열을 내보내는지만 확인한다.
function fakeWs(appVersion) {
  const sent = [];
  return { appVersion, readyState: 1, OPEN: 1, send: (s) => sent.push(s), sent };
}
const payload = { type: 'game_state', state: { myCards: ['sk_pirate_5'] } };
const wsOld = fakeWs('3.2.0');
const wsNew = fakeWs('3.3.0');
sendTo(wsOld, payload);
sendTo(wsNew, payload);
chk('sendTo 가 구버전에게는 바꿔 보낸다',
  wsOld.sent[0].includes('"sk_pirate"') && !wsOld.sent[0].includes('"sk_pirate_5"'));
chk('sendTo 가 최신 버전에게는 그대로 보낸다',
  wsNew.sent[0].includes('"sk_pirate_5"'));
chk('같은 객체를 두 소켓에 보내도 서로 섞이지 않는다',
  wsOld.sent[0] !== wsNew.sent[0]
  && payload.state.myCards[0] === 'sk_pirate_5');

// 닫힌 소켓에는 보내지 않는다(원래 동작을 깨지 않았는지).
const closed = fakeWs('3.2.0');
closed.readyState = 3;
sendTo(closed, payload);
chk('닫힌 소켓에는 보내지 않는다', closed.sent.length === 0);

console.log(ok ? '\n전부 통과' : '\n실패 있음');
process.exit(ok ? 0 : 1);
