/**
 * Marketing pushes: who they may go to, and who may collect the reward.
 *
 * The reward is real gold handed out on the strength of a small integer that
 * travelled to a phone, so the audience and the claim rules are the whole
 * feature. Each check below is a way it pays the wrong person or annoys
 * somebody who said stop:
 *
 *  - consent is read at SEND time from the database. This is the reason for
 *    not using an FCM topic: there, consent is a subscription the device has
 *    to remember to cancel, so a withdrawal that never reaches Google keeps
 *    delivering ads.
 *  - a claim from someone who was not sent the campaign must be refused.
 *    Campaign ids are sequential and visible to clients.
 *  - a claim must pay once. The tap handler can fire twice on a cold start,
 *    and a retry after a dropped reply is ordinary.
 *  - a tap after the deadline still counts as an open. "500 sent, 300 opened,
 *    12 claimed" is what a too-short deadline looks like, and it is invisible
 *    if late taps leave no trace.
 *
 * Talks to the database directly; no server needed.
 *
 * Run: node server/test_marketing_push.js
 */
const db = require('./db/database.js');

let failures = 0;
const check = (label, cond, detail = '') => {
  console.log(`${cond ? '  ok  ' : '  FAIL'} ${label}${!cond && detail ? ` — ${detail}` : ''}`);
  if (!cond) failures++;
};

const run = Date.now().toString(36).slice(-5);
const nick = (i) => `푸시${run}_${i}`;

async function makeUser(i, { consent = false, token = true } = {}) {
  await db.pool.query(
    `INSERT INTO tc_users (username, nickname, gold, fcm_token, device_platform)
     VALUES ($1, $2, 0, $3, 'android')
     ON CONFLICT (nickname) DO NOTHING`,
    [`mk_${run}_${i}`, nick(i), token ? `token_${run}_${i}` : null],
  );
  if (consent) await db.setMarketingConsent(nick(i), true);
}

const mine = (rows) => rows.filter((r) => r.nickname.startsWith(`푸시${run}_`));

(async () => {
  await db.initDatabase();

  console.log('\n[야간 판정 — 광고를 보내면 안 되는 시간]');
  const at = (utcHour) => new Date(Date.UTC(2026, 7, 13, utcHour));
  check('20:00 KST is still daytime', db.isKstNight(at(11)) === false);
  check('21:00 KST is night', db.isKstNight(at(12)) === true);
  check('07:59 KST is still night', db.isKstNight(at(22)) === true);
  check('08:00 KST is daytime again', db.isKstNight(at(23)) === false);

  console.log('\n[누구에게 보낼 수 있는가]');
  await makeUser(1, { consent: true });
  await makeUser(2, { consent: true });
  await makeUser(3);                          // never asked
  await makeUser(4, { consent: true, token: false }); // consented, no device
  let audience = mine(await db.getMarketingAudience('all'));
  check('a fresh account is not in the audience — consent is opt-in',
    !audience.some((u) => u.nickname === nick(3)));
  check('someone who consented but has no token is skipped',
    !audience.some((u) => u.nickname === nick(4)));
  check('the two who consented are in', audience.length === 2,
    audience.map((u) => u.nickname).join(','));

  // Withdrawal. With a topic this would be a device-side unsubscribe that can
  // silently fail; here the next send simply does not see them.
  await db.setMarketingConsent(nick(2), false);
  audience = mine(await db.getMarketingAudience('all'));
  check('withdrawing removes them from the very next send',
    audience.length === 1 && audience[0].nickname === nick(1));
  const state = await db.getMarketingConsentState(nick(2));
  check('and the record still shows they were asked', state.asked === true);
  check('but are no longer opted in', state.enabled === false);
  const never = await db.getMarketingConsentState(nick(3));
  check('"never asked" is distinguishable from "said no"',
    never.asked === false && never.enabled === false);

  // The settings screen greys the marketing switch out when notifications are
  // off and tells the player nothing will be sent. That claim is only true
  // because of this clause.
  await db.pool.query(
    'UPDATE tc_users SET push_enabled = FALSE WHERE nickname = $1', [nick(1)]);
  check('turning notifications off takes them out of the audience too',
    mine(await db.getMarketingAudience('all')).length === 0);
  const stillConsented = await db.getMarketingConsentState(nick(1));
  check('without touching their marketing consent', stillConsented.enabled === true,
    'switching notifications back on must not need consent given again');
  await db.pool.query(
    'UPDATE tc_users SET push_enabled = TRUE WHERE nickname = $1', [nick(1)]);
  check('and turning them back on restores the audience',
    mine(await db.getMarketingAudience('all')).length === 1);

  console.log('\n[앱을 지운 기기]');
  // FCM answers "not registered" for a token whose app is gone. The account
  // stays; only the device is retired.
  const gone = (await db.getAllFcmTokenRows())
    .filter((r) => r.nickname === nick(1)).map((r) => r.id);
  check('the probe offers the live token for checking', gone.length === 1);
  await db.markFcmTokensInvalid(gone);
  check('a dead token drops out of the marketing audience',
    !mine(await db.getMarketingAudience('all')).some((u) => u.nickname === nick(1)));
  const kept = await db.pool.query(
    `SELECT fcm_token, fcm_token_invalid_at, marketing_push_enabled
     FROM tc_users WHERE nickname = $1`, [nick(1)]);
  check('the account is untouched', kept.rows.length === 1);
  check('and the token is kept, so "uninstalled" stays distinguishable from "never installed"',
    kept.rows[0].fcm_token != null && kept.rows[0].fcm_token_invalid_at != null);
  check('their marketing consent is not withdrawn by an uninstall',
    kept.rows[0].marketing_push_enabled === true);
  check('and it is not offered to the next probe',
    !(await db.getAllFcmTokenRows()).some((r) => r.nickname === nick(1)));

  // Reinstall: the app comes back with a new token.
  await db.updateDeviceInfo(nick(1), { fcmToken: `token_${run}_1_new` });
  check('a new token from a reinstall revives the device',
    mine(await db.getMarketingAudience('all')).some((u) => u.nickname === nick(1)));
  // A login that carries no token must not resurrect a device that is gone.
  await db.markFcmTokensInvalid(
    (await db.pool.query('SELECT id FROM tc_users WHERE nickname = $1', [nick(1)]))
      .rows.map((r) => r.id));
  await db.updateDeviceInfo(nick(1), { locale: 'ko' });
  check('a login with no token does not',
    !mine(await db.getMarketingAudience('all')).some((u) => u.nickname === nick(1)));
  await db.updateDeviceInfo(nick(1), { fcmToken: `token_${run}_1` });

  console.log('\n[보상 지급]');
  const camp = await db.createPushCampaign({
    title: '(광고) 테스트', body: '눌러서 50골드', rewardGold: 50,
  });
  check('the campaign is created', camp.success === true);
  // nick(1) and nick(2) were sent it; nick(3) never was.
  await db.recordCampaignSend(camp.id, [
    { nickname: nick(1), success: true },
    { nickname: nick(2), success: true },
    { nickname: nick(5), success: false },
  ]);

  const goldOf = async (n) => (await db.pool.query(
    'SELECT gold FROM tc_users WHERE nickname = $1', [n])).rows[0]?.gold;

  const stranger = await db.claimPushCampaign(nick(3), camp.id);
  check('someone who was not sent it cannot claim',
    stranger.success === false && stranger.messageKey === 'push_reward_not_yours',
    stranger.messageKey);

  const before = await goldOf(nick(1));
  const first = await db.claimPushCampaign(nick(1), camp.id);
  check('a recipient is paid', first.success === true, first.messageKey);
  check('the gold arrives', (await goldOf(nick(1))) === before + 50,
    `${before} → ${await goldOf(nick(1))}`);
  check('and the reward comes back so the app can show it',
    first.reward?.type === 'gold' && first.reward?.gold === 50);

  const second = await db.claimPushCampaign(nick(1), camp.id);
  check('a second tap is refused',
    second.success === false && second.messageKey === 'push_reward_already_claimed',
    second.messageKey);
  check('and pays nothing further', (await goldOf(nick(1))) === before + 50);

  console.log('\n[동시에 두 번 누른 경우]');
  // The cold-start handler and the resume handler can both fire.
  const camp2 = await db.createPushCampaign({ title: 'x', body: 'y', rewardGold: 100 });
  await db.recordCampaignSend(camp2.id, [{ nickname: nick(2), success: true }]);
  const g0 = await goldOf(nick(2));
  const both = await Promise.all([
    db.claimPushCampaign(nick(2), camp2.id),
    db.claimPushCampaign(nick(2), camp2.id),
  ]);
  check('exactly one of two simultaneous claims pays',
    both.filter((r) => r.success).length === 1,
    both.map((r) => r.success).join(','));
  check('the balance moved once, not twice', (await goldOf(nick(2))) === g0 + 100,
    `+${(await goldOf(nick(2))) - g0}`);

  console.log('\n[마감이 지난 뒤에 누른 경우]');
  const camp3 = await db.createPushCampaign({
    title: 'z', body: 'z', rewardGold: 70,
    claimDeadline: new Date(Date.now() - 3600 * 1000),
  });
  await db.recordCampaignSend(camp3.id, [{ nickname: nick(1), success: true }]);
  const g1 = await goldOf(nick(1));
  const late = await db.claimPushCampaign(nick(1), camp3.id);
  check('the reward is refused',
    late.success === false && late.messageKey === 'push_reward_expired', late.messageKey);
  check('no gold is paid', (await goldOf(nick(1))) === g1);
  const rec = await db.getCampaignRecipients(camp3.id);
  check('but the open is still recorded — a dead deadline must be visible',
    rec.rows[0]?.opened_at != null);
  check('and it is not marked as claimed', rec.rows[0]?.claimed_at == null);

  console.log('\n[아무에게도 못 간 발송]');
  // Firebase unreachable, or every token stale. Burning the campaign for that
  // would mean rebuilding it by hand to try again.
  const camp4 = await db.createPushCampaign({ title: 'f', body: 'f', rewardGold: 10 });
  const dead = await db.recordCampaignSend(camp4.id, [
    { nickname: nick(1), success: false },
  ]);
  check('the send reports failure', dead.success === false);
  let c4 = (await db.listPushCampaigns(50)).find((c) => c.id === camp4.id);
  check('the campaign stays a draft so it can be retried', c4.status === 'draft',
    c4.status);
  // The retry gets through.
  await db.recordCampaignSend(camp4.id, [{ nickname: nick(1), success: true }]);
  c4 = (await db.listPushCampaigns(50)).find((c) => c.id === camp4.id);
  check('a successful retry marks it sent', c4.status === 'sent', c4.status);
  check('and the recipient row flips from failed to sent', c4.sent === 1, `${c4.sent}`);
  // Once delivered it must not be downgraded — the row is what entitles them
  // to the reward.
  await db.recordCampaignSend(camp4.id, [{ nickname: nick(1), success: false }]);
  const after = await db.getCampaignRecipients(camp4.id);
  check('a later failed attempt does not un-deliver it',
    after.rows[0]?.status === 'sent', after.rows[0]?.status);

  console.log('\n[집계]');
  const list = await db.listPushCampaigns(50);
  const c1 = list.find((c) => c.id === camp.id);
  check('sent counts the deliveries, not the audience', c1.sent === 2, `${c1.sent}`);
  check('failures are stored too', c1.fail_count === 1, `${c1.fail_count}`);
  // Of the two it reached, only nick(1) tapped — nick(3)'s attempt was
  // refused before a row existed to mark, which is the point of that check.
  check('opened counts the recipients who tapped', c1.opened === 1, `${c1.opened}`);
  check('claimed counts who was paid', c1.claimed === 1, `${c1.claimed}`);

  for (const id of [camp.id, camp2.id, camp3.id, camp4.id]) await db.deletePushCampaign(id);
  for (let i = 1; i <= 5; i++) {
    await db.pool.query('DELETE FROM tc_gold_history WHERE nickname = $1', [nick(i)]);
    await db.pool.query('DELETE FROM tc_users WHERE nickname = $1', [nick(i)]);
  }
})()
  .then(() => {
    console.log(failures === 0 ? '\nPASS' : `\n${failures} FAILURE(S)`);
    process.exit(failures === 0 ? 0 : 1);
  })
  .catch((e) => {
    console.error('\nERROR', e.message);
    process.exit(1);
  });
