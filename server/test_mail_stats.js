'use strict';
/**
 * 받는 사람이 우편을 지워도 "몇 명에게 보냈는가" 는 그대로여야 한다.
 *
 * 예전에는 지우면 recipient 행이 사라지고, 어드민 목록은 남은 행을 세서
 * 통계를 만들었다 — 받은 사람이 자기 우편함을 정리했다는 이유로 지난
 * 발송의 숫자가 줄었다. 특히 보상 없는 우편은 읽자마자 지울 수 있어서
 * 바로 줄어든다.
 */
const db = require('./db/database.js');
const RUN = Date.now().toString(36).slice(-5);
let fail = 0;
const check = (label, cond, detail = '') => {
  console.log(`${cond ? '  ok  ' : '  FAIL'} ${label}${!cond && detail ? ` — ${detail}` : ''}`);
  if (!cond) fail++;
};

(async () => {
  const names = [`통계A${RUN}`, `통계B${RUN}`];
  for (const n of names) {
    await db.pool.query(
      `INSERT INTO tc_users (username, nickname) VALUES ($1,$2)
       ON CONFLICT DO NOTHING`, [`stat_${n}`, n]);
  }
  const sent = await db.sendMail({
    title: '통계 확인', body: '보상 없는 우편', targetKind: 'user',
    nicknames: names, createdBy: 'test',
  });
  check('두 명에게 보냈다', sent.success && sent.sent === 2, JSON.stringify(sent));

  const before = (await db.listMail({ limit: 50 })).rows.find((r) => r.id === sent.id);
  check('발송 직후 2명으로 보인다', before.recipients === 2, `${before.recipients}`);

  await db.markMailRead(names[0], sent.id);
  const del = await db.deleteMailForUser(names[0], sent.id);
  check('읽고 나서 지울 수 있다', del.success === true, JSON.stringify(del));

  const box = await db.getMailbox(names[0]);
  check('지운 사람 우편함에서는 사라진다',
    !(box.mail || []).some((m) => m.id === sent.id));
  const other = await db.getMailbox(names[1]);
  check('다른 사람 우편함에는 그대로 있다',
    (other.mail || []).some((m) => m.id === sent.id));

  const after = (await db.listMail({ limit: 50 })).rows.find((r) => r.id === sent.id);
  check('지운 뒤에도 발송 인원은 2명', after.recipients === 2, `${after.recipients}`);
  check('읽음 수도 남는다', after.read_count === 1, `${after.read_count}`);

  for (const n of names) await db.pool.query('DELETE FROM tc_users WHERE nickname = $1', [n]);
  await db.pool.query('DELETE FROM tc_mail WHERE id = $1', [sent.id]);
})().then(() => {
  console.log(fail === 0 ? '\nPASS' : `\n${fail} FAILURE(S)`);
  process.exit(fail === 0 ? 0 : 1);
}).catch((e) => { console.error('ERROR', e.message); process.exit(1); });
