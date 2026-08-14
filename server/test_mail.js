'use strict';
/**
 * 운영자 우편함 — 보내고, 읽고, 받는 것.
 *
 * A letter can carry gold or an item, so it is a payout path, and every payout
 * path in here has been bitten by the same three things:
 *
 *  - claiming twice (two taps, two devices, a retry) paying twice;
 *  - a recycled nickname inheriting the previous owner's unclaimed post;
 *  - the deadline being compared in the wrong timezone, so a letter that
 *    should still be open reads as expired (or the reverse) for nine hours.
 *
 * Run: node server/test_mail.js
 */
const db = require('./db/database.js');

let failures = 0;
const check = (label, cond, detail = '') => {
  console.log(`${cond ? '  ok  ' : '  FAIL'} ${label}${!cond && detail ? ` — ${detail}` : ''}`);
  if (!cond) failures++;
};

const run = Date.now().toString(36).slice(-5);
const A = `우편A${run}`;
const B = `우편B${run}`;
const goldOf = async (n) => Number((await db.pool.query(
  'SELECT gold FROM tc_users WHERE nickname = $1', [n])).rows[0].gold);

(async () => {
  await db.initDatabase();
  for (const [i, n] of [A, B].entries()) {
    await db.pool.query(
      `INSERT INTO tc_users (username, nickname, gold) VALUES ($1, $2, 100)
       ON CONFLICT (nickname) DO NOTHING`, [`mail_${i}_${run}`, n]);
  }

  console.log('\n[한 사람에게 보내기]');
  const one = await db.sendMail({
    title: `안내 ${run}`, body: '문의 주신 건 처리했습니다.',
    targetKind: 'user', nicknames: [A], createdBy: 'tester',
  });
  check('보내진다', one.success === true && one.sent === 1, JSON.stringify(one));
  const boxA = await db.getMailbox(A);
  check('받는 사람 우편함에 있다', boxA.mail.length === 1 && boxA.mail[0].id === one.id);
  const boxB = await db.getMailbox(B);
  check('다른 사람에게는 안 간다', !boxB.mail.some((m) => m.id === one.id));
  check('안 읽음으로 센다', (await db.getUnreadMailCount(A)) === 1);
  await db.markMailRead(A, one.id);
  check('읽으면 안 읽음이 0', (await db.getUnreadMailCount(A)) === 0);

  console.log('\n[없는 닉네임이 섞이면]');
  const typo = await db.sendMail({
    title: `오타 ${run}`, body: 'x', targetKind: 'list',
    nicknames: [A, `없는사람${run}`], createdBy: 'tester',
  });
  check('있는 사람에게는 가고', typo.success === true && typo.sent === 1, JSON.stringify(typo));
  check('없는 이름은 돌려준다 (조용히 넘기지 않음)',
    typo.missing.length === 1 && typo.missing[0] === `없는사람${run}`, JSON.stringify(typo.missing));
  const allMissing = await db.sendMail({
    title: 'x', body: 'x', targetKind: 'list', nicknames: [`허공${run}`], createdBy: 'tester',
  });
  check('전부 없으면 아예 안 보낸다', allMissing.success === false, JSON.stringify(allMissing));

  console.log('\n[골드가 든 편지]');
  const gift = await db.sendMail({
    title: `보상 ${run}`, body: '불편을 드려 죄송합니다.', rewardGold: 500,
    targetKind: 'list', nicknames: [A, B], createdBy: 'tester',
  });
  check('두 명에게 간다', gift.sent === 2, JSON.stringify(gift));
  const before = await goldOf(A);
  const claim1 = await db.claimMail(A, gift.id);
  check('수령하면 골드가 들어온다',
    claim1.success === true && (await goldOf(A)) === before + 500,
    JSON.stringify(claim1));
  const claim2 = await db.claimMail(A, gift.id);
  check('두 번째 수령은 거절된다',
    claim2.success === false && claim2.messageKey === 'mail_already_claimed', JSON.stringify(claim2));
  check('골드도 두 번 들어오지 않는다', (await goldOf(A)) === before + 500);
  check('수령하면 읽음 처리도 된다',
    (await db.getMailbox(A)).mail.find((m) => m.id === gift.id).read_at != null);
  check('남의 편지는 못 받는다',
    (await db.claimMail(`엉뚱${run}`, gift.id)).messageKey === 'mail_not_yours');
  const ledger = (await db.pool.query(
    `SELECT source, gold_delta FROM tc_gold_history WHERE nickname = $1 ORDER BY id DESC LIMIT 1`,
    [A])).rows[0];
  check('골드 내역에 출처가 남는다',
    ledger.source === 'mail' && Number(ledger.gold_delta) === 500, JSON.stringify(ledger));

  console.log('\n[아이템이 든 편지]');
  const item = (await db.pool.query(
    `SELECT item_key FROM tc_shop_items WHERE is_permanent = FALSE AND duration_days IS NOT NULL LIMIT 1`
  )).rows[0].item_key;
  const itemMail = await db.sendMail({
    title: `아이템 ${run}`, body: 'x', rewardItemKey: item, rewardDays: 7,
    targetKind: 'user', nicknames: [B], createdBy: 'tester',
  });
  const itemClaim = await db.claimMail(B, itemMail.id);
  check('아이템이 지급된다', itemClaim.success === true && itemClaim.reward.type === 'item',
    JSON.stringify(itemClaim));
  const owned = await db.pool.query(
    `SELECT expires_at FROM tc_user_items WHERE nickname = $1 AND item_key = $2`, [B, item]);
  check('인벤토리에 실제로 들어간다', owned.rows.length === 1);
  const daysLeft = (new Date(owned.rows[0].expires_at) - Date.now()) / 86400000;
  check('지정한 일수만큼 들어간다', Math.abs(daysLeft - 7) < 0.2, `${daysLeft.toFixed(2)}일`);
  const badItem = await db.sendMail({
    title: 'x', body: 'x', rewardItemKey: 'no_such_item_key',
    targetKind: 'user', nicknames: [A], createdBy: 'tester',
  });
  check('없는 아이템은 발송 단계에서 막는다', badItem.success === false, JSON.stringify(badItem));

  console.log('\n[기한]');
  const expired = await db.sendMail({
    title: `만료 ${run}`, body: 'x', rewardGold: 100,
    expiresAt: '2020-01-01 00:00:00', targetKind: 'user', nicknames: [A], createdBy: 'tester',
  });
  const goldBefore = await goldOf(A);
  const expClaim = await db.claimMail(A, expired.id);
  check('지난 편지는 수령이 안 된다',
    expClaim.success === false && expClaim.messageKey === 'mail_expired', JSON.stringify(expClaim));
  check('골드도 안 들어온다', (await goldOf(A)) === goldBefore);
  check('그래도 읽은 것으로는 남는다',
    (await db.getMailbox(A)).mail.find((m) => m.id === expired.id).read_at != null);

  console.log('\n[전체 발송]');
  const all = await db.sendMail({
    title: `전체 ${run}`, body: '점검 보상입니다.', rewardGold: 50,
    targetKind: 'all', createdBy: 'tester',
  });
  const alive = Number((await db.pool.query(
    'SELECT COUNT(*)::int n FROM tc_users WHERE is_deleted IS NOT TRUE')).rows[0].n);
  check('살아있는 계정 수만큼 간다', all.sent === alive, `${all.sent} vs ${alive}`);
  check('탈퇴 계정은 빼고 간다',
    (await db.pool.query(
      `SELECT COUNT(*)::int n FROM tc_mail_recipients r
         JOIN tc_users u ON u.nickname = r.nickname
        WHERE r.mail_id = $1 AND u.is_deleted = TRUE`, [all.id])).rows[0].n === 0);
  check('둘 다에게 도착한다',
    (await db.getMailbox(A)).mail.some((m) => m.id === all.id)
      && (await db.getMailbox(B)).mail.some((m) => m.id === all.id));

  console.log('\n[닉네임을 물려받은 계정]');
  // A letter sent to the old owner must not be readable by whoever takes the
  // nickname next — the same rule the gold ledger and match history follow.
  await db.pool.query(
    `UPDATE tc_users SET created_at = (NOW() AT TIME ZONE 'UTC') + INTERVAL '1 hour'
      WHERE nickname = $1`, [B]);
  check('발송보다 늦게 생긴 계정에게는 안 보인다',
    (await db.getMailbox(B)).mail.length === 0,
    `${(await db.getMailbox(B)).mail.length}통`);
  check('수령도 거절된다',
    (await db.claimMail(B, all.id)).messageKey === 'mail_not_yours');
  await db.pool.query(
    `UPDATE tc_users SET created_at = (NOW() AT TIME ZONE 'UTC') - INTERVAL '1 day'
      WHERE nickname = $1`, [B]);

  console.log('\n[보내는 사람 이름]');
  const named = await db.sendMail({
    title: `이벤트 ${run}`, body: 'x', senderName: '여름 이벤트 운영진',
    targetKind: 'user', nicknames: [A], createdBy: 'tester',
  });
  const namedRow = (await db.getMailbox(A)).mail.find((m) => m.id === named.id);
  check('지정한 이름이 그대로 내려간다',
    namedRow.sender_name === '여름 이벤트 운영진', `${namedRow.sender_name}`);
  const blank = await db.sendMail({
    title: `기본 ${run}`, body: 'x', senderName: '   ',
    targetKind: 'user', nicknames: [A], createdBy: 'tester',
  });
  const blankRow = (await db.getMailbox(A)).mail.find((m) => m.id === blank.id);
  check('공백만 넣으면 비운 것으로 본다 (앱이 기본 이름을 쓴다)',
    blankRow.sender_name === null, `${JSON.stringify(blankRow.sender_name)}`);
  const plain = await db.sendMail({
    title: `무지정 ${run}`, body: 'x',
    targetKind: 'user', nicknames: [A], createdBy: 'tester',
  });
  check('아예 안 넣어도 비어 있다',
    (await db.getMailbox(A)).mail.find((m) => m.id === plain.id).sender_name === null);
  const long = await db.sendMail({
    title: `긴이름 ${run}`, body: 'x', senderName: '가'.repeat(200),
    targetKind: 'user', nicknames: [A], createdBy: 'tester',
  });
  check('너무 긴 이름은 잘려서 들어간다 (컬럼을 넘기지 않는다)',
    long.success === true
      && (await db.getMailbox(A)).mail.find((m) => m.id === long.id).sender_name.length === 60,
    JSON.stringify(long));
  for (const m of [named, blank, plain, long]) await db.deleteMail(m.id);

  console.log('\n[보상이 있으면 읽어도 알림이 안 사라진다]');
  // 읽었다고 배지가 사라지면 "나중에 받아야지" 하고 잊는다. 보상이 빠져나갈
  // 때까지 세어야 한다 — 클라이언트도 같은 규칙을 쓴다(mailNeedsAttention).
  const plainMail = await db.sendMail({
    title: `그냥편지 ${run}`, body: 'x', targetKind: 'user', nicknames: [B], createdBy: 'tester',
  });
  const base = await db.getUnreadMailCount(B);
  await db.markMailRead(B, plainMail.id);
  check('보상 없는 편지는 읽으면 빠진다',
    (await db.getUnreadMailCount(B)) === base - 1, `${base} → ${await db.getUnreadMailCount(B)}`);

  const rewardMail = await db.sendMail({
    title: `보상편지 ${run}`, body: 'x', rewardGold: 100,
    targetKind: 'user', nicknames: [B], createdBy: 'tester',
  });
  const withUnread = await db.getUnreadMailCount(B);
  await db.markMailRead(B, rewardMail.id);
  check('보상 있는 편지는 읽어도 그대로 센다',
    (await db.getUnreadMailCount(B)) === withUnread,
    `${withUnread} → ${await db.getUnreadMailCount(B)}`);
  await db.claimMail(B, rewardMail.id);
  check('받고 나서야 빠진다',
    (await db.getUnreadMailCount(B)) === withUnread - 1,
    `${withUnread} → ${await db.getUnreadMailCount(B)}`);

  const deadMail = await db.sendMail({
    title: `기한지난보상 ${run}`, body: 'x', rewardGold: 100,
    expiresAt: '2020-01-01 00:00:00', targetKind: 'user', nicknames: [B], createdBy: 'tester',
  });
  const beforeDead = await db.getUnreadMailCount(B);
  await db.markMailRead(B, deadMail.id);
  check('기한이 지난 보상은 읽으면 빠진다 (받을 게 없으니 재촉하지 않는다)',
    (await db.getUnreadMailCount(B)) === beforeDead - 1,
    `${beforeDead} → ${await db.getUnreadMailCount(B)}`);
  for (const m of [plainMail, rewardMail, deadMail]) await db.deleteMail(m.id);

  console.log('\n[유저가 직접 지우기]');
  const readOnly = await db.sendMail({
    title: `읽기만 ${run}`, body: 'x', targetKind: 'user', nicknames: [A], createdBy: 'tester',
  });
  const unread = await db.deleteMailForUser(A, readOnly.id);
  check('안 읽어도 지울 수 있다 (보상이 없으므로)', unread.success === true, JSON.stringify(unread));
  check('우편함에서 사라진다',
    !(await db.getMailbox(A)).mail.some((m) => m.id === readOnly.id));
  check('남의 편지는 못 지운다',
    (await db.deleteMailForUser(`엉뚱${run}`, readOnly.id)).success === false);

  const withReward = await db.sendMail({
    title: `보상있음 ${run}`, body: 'x', rewardGold: 200,
    targetKind: 'user', nicknames: [A], createdBy: 'tester',
  });
  const tooSoon = await db.deleteMailForUser(A, withReward.id);
  check('보상이 남아 있으면 거절한다',
    tooSoon.success === false && tooSoon.messageKey === 'mail_claim_first', JSON.stringify(tooSoon));
  check('거절됐으니 편지도 그대로 있다',
    (await db.getMailbox(A)).mail.some((m) => m.id === withReward.id));
  await db.claimMail(A, withReward.id);
  check('받고 나면 지울 수 있다',
    (await db.deleteMailForUser(A, withReward.id)).success === true);

  const closed = await db.sendMail({
    title: `기한지남 ${run}`, body: 'x', rewardGold: 200, expiresAt: '2020-01-01 00:00:00',
    targetKind: 'user', nicknames: [A], createdBy: 'tester',
  });
  check('기한이 지난 보상은 안 받고도 지울 수 있다 (잃을 게 없다)',
    (await db.deleteMailForUser(A, closed.id)).success === true);
  check('내가 지워도 남에게 간 사본은 남는다',
    (await db.pool.query(
      'SELECT COUNT(*)::int n FROM tc_mail WHERE id = $1', [closed.id])).rows[0].n === 1);

  console.log('\n[30일 보존]');
  const old = await db.sendMail({
    title: `오래된 ${run}`, body: 'x', rewardGold: 100,
    targetKind: 'user', nicknames: [A], createdBy: 'tester',
  });
  // 이 계정에는 앞선 단계에서 안 읽은 편지가 이미 있으므로, 절대값이 아니라
  // 이 한 통이 빠지는지를 본다.
  const unreadBefore = await db.getUnreadMailCount(A);
  await db.pool.query(
    `UPDATE tc_mail_recipients SET created_at = (NOW() AT TIME ZONE 'UTC') - INTERVAL '31 days'
      WHERE mail_id = $1`, [old.id]);
  check('31일 지난 편지는 우편함에 안 보인다',
    !(await db.getMailbox(A)).mail.some((m) => m.id === old.id));
  const unreadAfter = await db.getUnreadMailCount(A);
  check('안 읽음 수에서도 빠진다', unreadAfter === unreadBefore - 1,
    `${unreadBefore} → ${unreadAfter}`);
  const lateClaim = await db.claimMail(A, old.id);
  check('수령도 안 된다', lateClaim.success === false, JSON.stringify(lateClaim));
  const purged = await db.purgeOldMail(30);
  check('정리 작업이 사본을 지운다', purged.purged >= 1, JSON.stringify(purged));
  const snap = (await db.listMail({ limit: 200 })).rows.find((r) => r.id === old.id);
  check('그래도 어드민 통계는 남는다 (스냅샷)',
    snap && snap.recipients === 1, JSON.stringify(snap && { r: snap.recipients }));
  await db.deleteMail(old.id);
  for (const m of [readOnly, withReward, closed]) await db.deleteMail(m.id);

  console.log('\n[어드민 목록]');
  const list = await db.listMail({ limit: 100 });
  const row = list.rows.find((r) => r.id === gift.id);
  check('보낸 편지가 목록에 나온다', !!row);
  check('받은 사람 수가 맞다', row.recipients === 2, `${row.recipients}`);
  check('읽음·수령 수가 집계된다', row.read_count >= 1 && row.claimed_count === 1,
    `read=${row.read_count} claimed=${row.claimed_count}`);
  const detail = await db.getMailDetail(gift.id);
  check('상세에서 누가 받았는지 보인다',
    detail.recipients.length === 2 && detail.recipients.some((r) => r.nickname === A));

  console.log('\n[삭제]');
  await db.deleteMail(gift.id);
  check('편지가 사라진다', !(await db.listMail({ limit: 100 })).rows.some((r) => r.id === gift.id));
  check('받은 사람 행도 같이 사라진다',
    (await db.pool.query(
      'SELECT COUNT(*)::int n FROM tc_mail_recipients WHERE mail_id = $1', [gift.id])).rows[0].n === 0);
  check('우편함에서도 없어진다', !(await db.getMailbox(A)).mail.some((m) => m.id === gift.id));

  for (const id of [one.id, typo.id, itemMail.id, expired.id, all.id]) await db.deleteMail(id);
  for (const n of [A, B]) {
    await db.pool.query('DELETE FROM tc_user_items WHERE nickname = $1', [n]);
    await db.pool.query('DELETE FROM tc_gold_history WHERE nickname = $1', [n]);
    await db.pool.query('DELETE FROM tc_users WHERE nickname = $1', [n]);
  }
})()
  .then(() => {
    console.log(failures === 0 ? '\nPASS' : `\n${failures} FAILURE(S)`);
    process.exit(failures === 0 ? 0 : 1);
  })
  .catch((e) => { console.error('\nERROR', e.stack); process.exit(1); });
