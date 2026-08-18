'use strict';
/**
 * 재사용된 닉네임이 이전 주인의 우편을 건드리지 못해야 한다.
 *
 * 닉네임은 탈퇴 후 다시 쓰일 수 있다. 조회·수령은 r.created_at >= u.created_at
 * 로 이미 막고 있었지만 읽음·삭제는 mail_id + nickname 만 봤다. 새 주인이
 * mailId 만 알아내면 읽지도 못하는 사본을 읽음·삭제 상태로 바꿔놓을 수 있었다.
 *
 * Run: node test_mail_recycle.js
 */
const db = require('./db/database.js');
const RUN = Date.now().toString(36).slice(-5);
const NICK = `재사용${RUN}`;
let failures = 0;
const check = (label, cond, detail = '') => {
  console.log(`${cond ? '  ok  ' : '  FAIL'} ${label}${!cond && detail ? ` — ${detail}` : ''}`);
  if (!cond) failures++;
};

(async () => {
  // 이전 주인 — 가입 시각을 과거로 밀어둔다.
  await db.pool.query(
    `INSERT INTO tc_users (username, nickname, created_at)
     VALUES ($1, $2, (NOW() AT TIME ZONE 'UTC') - INTERVAL '10 days')`,
    [`old_${RUN}`, NICK]);

  const sent = await db.sendMail({
    title: `재사용확인${RUN}`, body: '이전 주인 앞으로 간 편지',
    targetKind: 'user', nicknames: [NICK], createdBy: 'test',
  });
  check('이전 주인에게 편지가 갔다', sent.success === true, JSON.stringify(sent));

  // 그 사람이 나가고, 같은 닉네임으로 새 계정이 들어온다.
  await db.pool.query('DELETE FROM tc_users WHERE nickname = $1', [NICK]);
  await db.pool.query(
    `INSERT INTO tc_users (username, nickname) VALUES ($1, $2)`,
    [`new_${RUN}`, NICK]);

  const box = await db.getMailbox(NICK);
  check('새 주인 우편함에는 안 보인다',
    !(box.mail || []).some((m) => m.id === sent.id));

  await db.markMailRead(NICK, sent.id);
  const afterRead = (await db.pool.query(
    'SELECT read_at FROM tc_mail_recipients WHERE mail_id = $1', [sent.id])).rows[0];
  check('새 주인이 읽음으로 바꾸지 못한다', afterRead.read_at === null,
    `read_at=${afterRead.read_at}`);

  const del = await db.deleteMailForUser(NICK, sent.id);
  const afterDel = (await db.pool.query(
    'SELECT deleted_at FROM tc_mail_recipients WHERE mail_id = $1', [sent.id])).rows[0];
  check('새 주인이 지우지 못한다',
    del.success === false && afterDel.deleted_at === null,
    `${JSON.stringify(del)} deleted_at=${afterDel.deleted_at}`);

  await db.pool.query('DELETE FROM tc_mail_recipients WHERE mail_id = $1', [sent.id]);
  await db.pool.query('DELETE FROM tc_mail WHERE id = $1', [sent.id]);
  await db.pool.query('DELETE FROM tc_users WHERE nickname = $1', [NICK]);
})().then(() => {
  console.log(failures === 0 ? '\nPASS' : `\n${failures} FAILURE(S)`);
  process.exit(failures === 0 ? 0 : 1);
}).catch((e) => { console.error('\nERROR', e.message); process.exit(1); });
