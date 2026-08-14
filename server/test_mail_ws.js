'use strict';
/**
 * 우편함, 소켓 너머에서.
 *
 * The unit test drives the database directly. This drives what the app
 * actually does: log in, ask for the mailbox, open a letter, claim what is in
 * it — and checks the two things only the wire can show, that the reward
 * arrives with a fresh wallet behind it and that a second tap on the same
 * letter is refused rather than paid.
 *
 * Run (server must be listening): node server/test_mail_ws.js
 */
const WebSocket = require('ws');
const db = require('./db/database.js');

const SERVER_URL = process.argv[2] || 'ws://localhost:8080';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const RUN = Date.now().toString(36).slice(-5);

let failures = 0;
const check = (label, cond, detail = '') => {
  console.log(`${cond ? '  ok  ' : '  FAIL'} ${label}${!cond && detail ? ` — ${detail}` : ''}`);
  if (!cond) failures++;
};

function client() {
  const c = { last: {}, seen: [] };
  c.ws = new WebSocket(SERVER_URL);
  c.ws.on('message', (raw) => {
    const d = JSON.parse(raw.toString());
    c.seen.push(d.type);
    c.last[d.type] = d;
  });
  c.send = (m) => c.ws.send(JSON.stringify(m));
  c.forget = (t) => delete c.last[t];
  c.wait = (type, ms = 6000) => new Promise((resolve, reject) => {
    if (c.last[type]) return resolve(c.last[type]);
    const deadline = setTimeout(() => reject(new Error(`no ${type}`)), ms);
    const tick = setInterval(() => {
      if (c.last[type]) { clearTimeout(deadline); clearInterval(tick); resolve(c.last[type]); }
    }, 40);
  });
  return new Promise((resolve, reject) => {
    c.ws.on('open', () => resolve(c));
    c.ws.on('error', reject);
  });
}

(async () => {
  const NICK = `우편WS${RUN}`;
  const acct = { username: `mailws_${RUN}`, password: 'mailtest1234!', nickname: NICK };
  const c = await client();
  c.send({ type: 'register', ...acct });
  await sleep(900);
  c.send({ type: 'login', username: acct.username, password: acct.password,
    deviceInfo: { appVersion: '99.0.0', locale: 'ko' } });
  const login = await c.wait('login_success');
  const goldAtLogin = Number(login.gold ?? 0);

  console.log('\n[빈 우편함]');
  c.send({ type: 'get_mailbox' });
  const empty = await c.wait('mailbox_result');
  check('빈 우편함도 성공으로 답한다', empty.success === true && empty.mail.length === 0,
    JSON.stringify(empty).slice(0, 120));

  console.log('\n[운영진이 편지를 보낸다]');
  const mail = await db.sendMail({
    title: `보상 안내 ${RUN}`, body: '불편을 드려 죄송합니다. 소정의 보상을 드립니다.',
    rewardGold: 300, targetKind: 'list', nicknames: [NICK], createdBy: 'tester',
  });
  check('발송된다', mail.success === true, JSON.stringify(mail));

  c.forget('mailbox_result');
  c.send({ type: 'get_mailbox' });
  const box = await c.wait('mailbox_result');
  check('우편함에 도착한다', box.mail.length === 1 && box.mail[0].id === mail.id);
  check('안 읽음으로 온다', box.unread === 1 && box.mail[0].read_at === null);
  check('본문과 보상이 실려 온다',
    box.mail[0].reward_gold === 300 && String(box.mail[0].body).includes('죄송'));

  console.log('\n[읽고, 받는다]');
  c.send({ type: 'read_mail', mailId: mail.id });
  await sleep(300);
  c.forget('mailbox_result');
  c.send({ type: 'get_mailbox' });
  const afterRead = await c.wait('mailbox_result');
  check('읽음이 반영된다', afterRead.unread === 0 && afterRead.mail[0].read_at !== null);

  c.send({ type: 'claim_mail', mailId: mail.id });
  const claim = await c.wait('mail_claim_result');
  check('수령에 성공한다', claim.success === true, JSON.stringify(claim));
  check('무엇을 받았는지 알려준다',
    claim.reward?.type === 'gold' && claim.reward.gold === 300, JSON.stringify(claim.reward));
  const wallet = await c.wait('wallet_result');
  check('지갑이 새로 내려온다', Number(wallet.wallet?.gold) === goldAtLogin + 300,
    `${goldAtLogin} → ${wallet.wallet?.gold}`);

  console.log('\n[두 번은 안 된다]');
  c.forget('mail_claim_result');
  c.send({ type: 'claim_mail', mailId: mail.id });
  const again = await c.wait('mail_claim_result');
  check('거절된다', again.success === false, JSON.stringify(again));
  check('사람이 읽을 수 있는 이유가 온다',
    typeof again.message === 'string' && again.message.length > 0, again.message);
  const goldNow = Number((await db.pool.query(
    'SELECT gold FROM tc_users WHERE nickname = $1', [NICK])).rows[0].gold);
  check('골드는 한 번만 들어왔다', goldNow === goldAtLogin + 300, `${goldNow}`);

  console.log('\n[남의 편지]');
  // Mail ids are small integers, so guessing one is trivial. A letter
  // addressed to somebody else must not pay out to whoever asks for it.
  const OTHER = `우편남${RUN}`;
  await db.pool.query(
    `INSERT INTO tc_users (username, nickname, gold) VALUES ($1, $2, 0)
     ON CONFLICT (nickname) DO NOTHING`, [`mailws2_${RUN}`, OTHER]);
  const other = await db.sendMail({
    title: `남의 것 ${RUN}`, body: 'x', rewardGold: 999,
    targetKind: 'list', nicknames: [OTHER], createdBy: 'tester',
  });
  check('다른 사람 앞으로 보내진다', other.success === true, JSON.stringify(other));
  c.forget('mailbox_result');
  c.send({ type: 'get_mailbox' });
  const box2 = await c.wait('mailbox_result');
  check('내 우편함에는 안 보인다', !box2.mail.some((m) => m.id === other.id));
  c.forget('mail_claim_result');
  c.send({ type: 'claim_mail', mailId: other.id });
  const stolen = await c.wait('mail_claim_result');
  check('id 를 알아도 수령은 거절된다', stolen.success === false, JSON.stringify(stolen));
  check('골드는 그대로', Number((await db.pool.query(
    'SELECT gold FROM tc_users WHERE nickname = $1', [NICK])).rows[0].gold) === goldAtLogin + 300);
  await db.deleteMail(other.id);
  await db.pool.query('DELETE FROM tc_users WHERE nickname = $1', [OTHER]);

  await db.deleteMail(mail.id);
  await db.pool.query('DELETE FROM tc_gold_history WHERE nickname = $1', [NICK]);
  await db.pool.query('DELETE FROM tc_users WHERE nickname = $1', [NICK]);
  c.ws.close();
})()
  .then(() => {
    console.log(failures === 0 ? '\nPASS' : `\n${failures} FAILURE(S)`);
    process.exit(failures === 0 ? 0 : 1);
  })
  .catch((e) => { console.error('\nERROR', e.message); process.exit(1); });
