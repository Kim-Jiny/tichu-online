'use strict';
/**
 * 상점 표시가 옛 응답으로 되돌아가지 않는다.
 *
 * 두 가지를 본다.
 *
 * 1) 서버 — 상점을 읽는 질의가 겹치면, 먼저 시작한 읽기가 나중에 끝날 수
 *    있다. 그 응답은 구매 전 잔액을 담고도 더 큰 번호를 받아 앱에서 최신
 *    표시를 덮었다(380 → 440). 이제 한 소켓의 상점 작업은 한 줄로 서므로
 *    읽기가 겹치지 않는다.
 *
 * 2) 앱 — 번호는 연결마다 새로 세는데 앱이 그 번호를 연결보다 오래 들고
 *    있었다. 끊겼다 붙으면 서버는 1 부터 다시 세고 앱은 10 을 기억해서,
 *    새 연결의 1~10 번 응답을 전부 버렸다. 여기서는 앱 쪽 규칙(_acceptShop)
 *    을 그대로 옮겨 와, 연결이 설 때 번호를 비우면 풀린다는 것을 본다.
 *
 *   node test_shop_seq.js
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

const src = fs.readFileSync(path.join(__dirname, 'server.js'), 'utf8');
function extract(name) {
  let start = src.indexOf(`function ${name}(`);
  if (start < 0) throw new Error(`server.js 에서 ${name} 을 찾지 못했다`);
  if (src.slice(start - 6, start) === 'async ') start -= 6;
  let i = src.indexOf('{', start), depth = 0;
  for (; i < src.length; i++) {
    if (src[i] === '{') depth++;
    else if (src[i] === '}' && --depth === 0) break;
  }
  return src.slice(start, i + 1);
}

const ctx = { console, Promise, setTimeout };
vm.createContext(ctx);
vm.runInContext(extract('withShopSeq') + '\n' + extract('queueShopOp'), ctx);

// ===== 1) 서버: 겹친 읽기 =====
//
// 잔액은 구매가 끝나면 380 이 된다. 느린 조회는 '시작 시점의' 잔액을
// 돌려준다 — 실제 DB 스냅샷이 그렇게 움직인다.
(async () => {
  let balance = 440;
  const sent = [];
  const ws = {};
  const sendTo = (_ws, payload) => sent.push(payload);

  // 느린 조회: 시작할 때의 잔액을 붙들고 있다가 나중에 돌려준다.
  let release = null;
  const slowGetShop = () => {
    const snapshot = balance;
    return new Promise((r) => { release = () => r(snapshot); });
  };
  const fastBuy = async () => { balance = 380; return balance; };

  const opA = ctx.queueShopOp(ws, async () => {
    const shop = await slowGetShop();
    sendTo(ws, ctx.withShopSeq(ws, { type: 'token_shop', balance: shop }));
  });
  const opB = ctx.queueShopOp(ws, async () => {
    const shop = await fastBuy();
    sendTo(ws, ctx.withShopSeq(ws, { type: 'token_buy_result', balance: shop }));
  });

  // queueShopOp 는 마이크로태스크 뒤에 첫 작업을 시작한다. 조회가 실제로
  // 붙들릴 때까지 기다린다 — 그래야 '겹침' 상황을 확실히 만든다.
  const tick = () => new Promise((r) => setTimeout(r, 0));
  while (!release) await tick();

  // 줄을 세웠으므로 A 가 끝나기 전에는 B 가 시작도 못 한다.
  eq('줄 세우기: A 가 붙들려 있는 동안 B 는 시작 안 함', sent.length, 0);
  eq('줄 세우기: 그동안 구매도 실행되지 않음', balance, 440);
  release();
  await Promise.all([opA, opB]);

  eq('응답 두 개', sent.length, 2);
  eq('A(조회) 가 먼저, 번호 1', sent[0].shopSeq, 1);
  eq('B(구매) 가 나중, 번호 2', sent[1].shopSeq, 2);
  // 핵심: 가장 큰 번호가 가장 새 잔액을 들고 있어야 한다.
  const newest = sent.reduce((a, b) => (b.shopSeq > a.shopSeq ? b : a));
  eq('가장 큰 번호의 잔액이 최신(380)', newest.balance, 380);

  // ===== 2) 앱: 연결마다 번호를 비운다 =====
  //
  // game_service.dart 의 _acceptShop 과 같은 규칙.
  const app = { seq: 0 };
  const accept = (payload) => {
    const s = payload.shopSeq;
    if (typeof s !== 'number') return true;   // 번호 없는 옛 서버
    if (s <= app.seq) return false;
    app.seq = s;
    return true;
  };

  for (let i = 0; i < 10; i++) accept({ shopSeq: i + 1 });
  eq('첫 연결에서 번호가 10 까지 올라감', app.seq, 10);

  // 재접속: 서버는 1 부터 다시 센다.
  chk('비우지 않으면 새 연결의 1번 응답이 버려진다', accept({ shopSeq: 1 }) === false);

  app.seq = 0;  // login_success 에서 비운다
  chk('비우면 새 연결의 1번 응답이 받아들여진다', accept({ shopSeq: 1 }) === true);

  console.log(ok ? 'PASS' : 'FAIL');
  process.exit(ok ? 0 : 1);
})();
