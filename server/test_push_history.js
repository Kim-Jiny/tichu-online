'use strict';
/**
 * The unified push history: does every kind of push actually show up in it?
 *
 * Three tables feed this list — admin broadcasts, marketing campaigns, and the
 * one-to-one notifications the server sends off the back of an event — and the
 * failure mode is silent. A push that is never logged simply does not appear,
 * and the page looks fine: it shows the ones that were.
 *
 * Also pins the two rules that are easy to break later:
 *  - a tap counts once, however many times it is reported;
 *  - retention deletes the detail rows but never a campaign recipient, whose
 *    row is what stops a reward being claimed twice.
 *
 * Run: node server/test_push_history.js
 */
const db = require('./db/database.js');

let failures = 0;
const check = (label, cond, detail = '') => {
  console.log(`${cond ? '  ok  ' : '  FAIL'} ${label}${!cond && detail ? ` — ${detail}` : ''}`);
  if (!cond) failures++;
};

const run = Date.now().toString(36).slice(-5);
const NICK = `푸시${run}`;

(async () => {
  await db.initDatabase();
  await db.pool.query(
    `INSERT INTO tc_users (username, nickname, gold) VALUES ($1, $2, 0)
     ON CONFLICT (nickname) DO NOTHING`, [`push_${run}`, NICK]);

  const mine = async (kind = 'all') => {
    const r = await db.getUnifiedPushHistory({ kind, search: run, limit: 100 });
    return r.rows;
  };

  console.log('\n[개별 알림이 기록된다]');
  const logId = await db.startPushLog({
    event: 'friend_request', nickname: NICK,
    title: `친구 요청 ${run}`, body: '누가 친구하자고 합니다', actor: '상대',
  });
  check('발송 전에 행이 생긴다', Number.isFinite(logId), String(logId));
  const pending = (await db.pool.query(
    'SELECT success FROM tc_push_log WHERE id = $1', [logId])).rows[0];
  check('결과는 아직 비어 있다 (보고 안 된 발송)', pending.success === null, `${pending.success}`);
  await db.finishPushLog(logId, true);
  check('성공이 기록된다',
    (await db.pool.query('SELECT success FROM tc_push_log WHERE id = $1', [logId])).rows[0].success === true);
  check('히스토리에 나온다', (await mine()).some((r) => r.id === logId && r.kind === 'system'));

  console.log('\n[탭 집계]');
  await db.markPushOpened('log', logId, NICK);
  const opened1 = (await db.pool.query(
    'SELECT opened_at FROM tc_push_log WHERE id = $1', [logId])).rows[0].opened_at;
  check('열람 시각이 남는다', opened1 != null);
  await db.markPushOpened('log', logId, NICK);
  const opened2 = (await db.pool.query(
    'SELECT opened_at FROM tc_push_log WHERE id = $1', [logId])).rows[0].opened_at;
  check('두 번 눌러도 시각은 그대로다 (기기 두 대·재실행)',
    String(opened1) === String(opened2));
  check('남의 알림은 못 연다',
    (await db.markPushOpened('log', logId, '엉뚱한사람')).success === true
      && String((await db.pool.query('SELECT opened_at FROM tc_push_log WHERE id = $1',
        [logId])).rows[0].opened_at) === String(opened1));

  console.log('\n[어드민 단체 발송]');
  const historyId = await db.insertPushHistory({
    adminUsername: 'tester', title: `단체공지 ${run}`, body: '전체 공지',
    targetFilter: 'all', totalSent: 2, successCount: 0, failCount: 0, invalidTokens: 0,
  });
  await db.updatePushHistoryCounts(historyId, { successCount: 2, failCount: 1, invalidTokens: 1 });
  await db.insertPushRecipients(historyId, [{ userId: 1, nickname: NICK, status: 'success' }]);
  const bcast = (await mine()).find((r) => r.kind === 'broadcast' && r.id === historyId);
  check('히스토리에 나온다', !!bcast);
  check('발송 결과가 나중에 채워진다', bcast && bcast.sent === 2 && bcast.failed === 1,
    JSON.stringify(bcast && { sent: bcast.sent, failed: bcast.failed }));
  await db.markPushOpened('broadcast', historyId, NICK);
  await db.markPushOpened('broadcast', historyId, NICK);
  const afterOpen = (await mine()).find((r) => r.kind === 'broadcast' && r.id === historyId);
  check('열람 수가 1 이다 (두 번 보고해도)', afterOpen.opened === 1, `${afterOpen.opened}`);

  console.log('\n[필터]');
  check('시스템만 고르면 단체가 안 나온다',
    (await mine('system')).every((r) => r.kind === 'system'));
  check('단체만 고르면 시스템이 안 나온다',
    (await mine('broadcast')).every((r) => r.kind === 'broadcast'));
  const searched = await db.getUnifiedPushHistory({ search: `단체공지 ${run}`, limit: 50 });
  check('제목으로 검색된다', searched.rows.length === 1 && searched.rows[0].id === historyId,
    `${searched.rows.length}건`);
  const byNick = await db.getUnifiedPushHistory({ search: NICK, limit: 50 });
  check('받은 사람 닉네임으로도 검색된다', byNick.rows.some((r) => r.id === logId));

  console.log('\n[보존]');
  // Age both detail rows past the window and check what survives.
  await db.pool.query(
    `UPDATE tc_push_log SET created_at = (NOW() AT TIME ZONE 'UTC') - INTERVAL '200 days' WHERE id = $1`,
    [logId]);
  await db.pool.query(
    `UPDATE tc_push_recipients SET created_at = (NOW() AT TIME ZONE 'UTC') - INTERVAL '200 days'
      WHERE push_history_id = $1`, [historyId]);
  const purged = await db.purgePushLogs(90);
  check('오래된 개별 알림은 지워진다', purged.log >= 1, JSON.stringify(purged));
  check('오래된 수신자 행도 지워진다', purged.recipients >= 1, JSON.stringify(purged));
  const summary = (await mine('broadcast')).find((r) => r.id === historyId);
  check('그래도 단체 발송의 요약과 열람 수는 남는다',
    summary && summary.sent === 2 && summary.opened === 1,
    JSON.stringify(summary && { sent: summary.sent, opened: summary.opened }));

  // A campaign recipient carries "already claimed"; purging one would let the
  // same person collect twice off an old notification.
  const camp = await db.createPushCampaign({ title: `(광고) 보존 ${run}`, body: 'x', rewardGold: 10 });
  await db.reserveCampaignRecipients(camp.id, [NICK]);
  await db.pool.query(
    `UPDATE tc_push_campaign_recipients SET created_at = (NOW() AT TIME ZONE 'UTC') - INTERVAL '400 days'
      WHERE campaign_id = $1`, [camp.id]);
  await db.purgePushLogs(90);
  const stillThere = await db.pool.query(
    'SELECT COUNT(*)::int AS n FROM tc_push_campaign_recipients WHERE campaign_id = $1', [camp.id]);
  check('캠페인 수신자는 아무리 오래돼도 지우지 않는다', stillThere.rows[0].n === 1,
    `${stillThere.rows[0].n}건`);

  await db.deletePushCampaign(camp.id);
  await db.pool.query('DELETE FROM tc_push_recipients WHERE push_history_id = $1', [historyId]);
  await db.pool.query('DELETE FROM tc_push_history WHERE id = $1', [historyId]);
  await db.pool.query('DELETE FROM tc_push_log WHERE nickname = $1', [NICK]);
  await db.pool.query('DELETE FROM tc_users WHERE nickname = $1', [NICK]);
})()
  .then(() => {
    console.log(failures === 0 ? '\nPASS' : `\n${failures} FAILURE(S)`);
    process.exit(failures === 0 ? 0 : 1);
  })
  .catch((e) => {
    console.error('\nERROR', e.stack);
    process.exit(1);
  });
