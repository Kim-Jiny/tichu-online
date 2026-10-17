/**
 * 예약 마케팅 푸시 — 언제 나가고, 언제 나가지 않는가.
 *
 * 예약 발송은 보는 사람이 없는 시간에 돌고, 보내는 것은 회수할 수 없다.
 * 그래서 여기서 확인하는 것들은 전부 "조용히 두 번 나가거나, 조용히 안
 * 나가는" 경우다:
 *
 *  - 시각이 지나야 대상이 된다. 앞선 예약을 틱이 집어가면 안 된다.
 *  - 보낼 권리는 한 번만 집힌다. 블루/그린 드레인 구간에서는 두 인스턴스가
 *    같은 틱을 돌고, 둘 다 통과하면 전원이 알림을 두 번 받는다.
 *  - 손으로 누른 발송도 같은 문을 지나야 한다. 한쪽만 claim 을 쓰면 예약
 *    시각 직전에 손으로 누른 발송과 틱이 겹친다.
 *  - 야간에는 보내지 않는다. 예약은 그 시각에 조용히 실패하지 말고 사유를
 *    남긴 채 초안으로 내려와야 한다 — 아침에 목록에서 보여야 하니까.
 *  - 'sending' 에 갇힌 캠페인은 자동 재발송하지 않는다. 죽은 시점이 FCM
 *    호출 전인지 후인지 알 수 없다.
 *  - 치환은 받는 사람마다 1인분씩 일어나고, 저장된 본문은 원문으로 남는다.
 *
 * DB 에 직접 붙는다. 서버는 띄우지 않고, FCM 대신 가짜 전송 함수를 넣어
 * "무슨 문구가 누구에게 갔는지"를 들여다본다.
 *
 * Run: node server/test_push_schedule.js
 */
const db = require('./db/database.js');
const { sendCampaign, REFUSED } = require('./push_campaign_send.js');

let failures = 0;
const check = (label, cond, detail = '') => {
  console.log(`${cond ? '  ok  ' : '  FAIL'} ${label}${!cond && detail ? ` — ${detail}` : ''}`);
  if (!cond) failures++;
};
const eq = (label, got, want) => check(label, got === want, `got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);

const run = Date.now().toString(36).slice(-5);
const nick = (i) => `예약${run}_${i}`;
const minutesFromNow = (m) => new Date(Date.now() + m * 60 * 1000).toISOString();

async function makeUser(i) {
  await db.pool.query(
    `INSERT INTO tc_users (username, nickname, gold, fcm_token, device_platform)
     VALUES ($1, $2, 0, $3, 'android')
     ON CONFLICT (nickname) DO NOTHING`,
    [`sch_${run}_${i}`, nick(i), `token_${run}_${i}`],
  );
  await db.setMarketingConsent(nick(i), true);
}

async function makeCampaign(fields = {}) {
  const r = await db.createPushCampaign({
    title: fields.title || `(광고) 예약 테스트 ${run}`,
    body: fields.body || '본문',
    rewardGold: 0,
    targetFilter: 'all',
    scheduledAt: fields.scheduledAt || null,
  }, 'test');
  return r.id;
}

/// 가짜 전송기. 받은 문구를 그대로 들고 있다가 검사에 쓴 뒤, FCM 성공처럼
/// 응답한다. [rows] 는 캠페인이 넘긴 수신자 행이다.
function fakeSender(log) {
  return async (rows, title, body) => {
    const textFor = (v, row) => (typeof v === 'function' ? v(row) : v);
    log.calls.push({
      personalized: typeof title === 'function' || typeof body === 'function',
      messages: rows.map((row) => ({
        nickname: row.nickname,
        title: textFor(title, row),
        body: textFor(body, row),
      })),
    });
    return {
      successCount: rows.length,
      failCount: 0,
      invalidUserIds: [],
      results: rows.map((r) => ({ userId: r.id, success: true, invalid: false })),
    };
  };
}

/// isKstNight 만 갈아끼운 의존성 묶음. 나머지는 전부 진짜 DB 함수다.
function deps(sender, { night = false } = {}) {
  return {
    getMarketingAudience: db.getMarketingAudience,
    reserveCampaignRecipients: db.reserveCampaignRecipients,
    sendBroadcastPush: sender,
    markFcmTokensInvalid: db.markFcmTokensInvalid,
    openCampaignForClaims: db.openCampaignForClaims,
    recordCampaignSend: db.recordCampaignSend,
    claimCampaignForSend: db.claimCampaignForSend,
    failCampaignSend: db.failCampaignSend,
    isKstNight: () => night,
  };
}

const statusOf = async (id) => (await db.getPushCampaign(id)).status;
const errorOf = async (id) => (await db.getPushCampaign(id)).last_send_error;

(async () => {
  await db.initDatabase();

  console.log('\n[예약 시각이 지나야 대상이 된다]');
  const future = await makeCampaign({ scheduledAt: minutesFromNow(60) });
  const past = await makeCampaign({ scheduledAt: minutesFromNow(-5) });
  eq('예약 시각을 넣으면 바로 예약 상태', await statusOf(future), 'scheduled');
  const dueIds = (await db.getDueCampaigns(100)).map((c) => c.id);
  check('지난 예약은 대상', dueIds.includes(past));
  check('앞선 예약은 대상이 아니다', !dueIds.includes(future));

  console.log('\n[보낼 권리는 한 번만 집힌다 — 두 인스턴스가 같은 틱을 돈다]');
  const claimMe = await makeCampaign({ scheduledAt: minutesFromNow(-5) });
  // 동시에 들어가야 의미가 있다. 순서대로 부르면 두 번째가 'sending' 을
  // 보고 물러나는 당연한 결과만 확인하게 된다.
  const both = await Promise.all([
    db.claimCampaignForSend(claimMe), db.claimCampaignForSend(claimMe),
  ]);
  eq('둘이 동시에 집으면 하나만 성공', both.filter(Boolean).length, 1);
  eq('집힌 뒤 상태는 sending', await statusOf(claimMe), 'sending');
  eq('이미 집힌 건은 다시 집히지 않는다', await db.claimCampaignForSend(claimMe), null);

  console.log('\n[예약 취소]');
  const cancelMe = await makeCampaign({ scheduledAt: minutesFromNow(30) });
  check('예약은 취소된다', (await db.cancelCampaignSchedule(cancelMe)).success);
  eq('취소하면 초안으로 남는다', await statusOf(cancelMe), 'draft');
  check('초안은 다시 취소되지 않는다', !(await db.cancelCampaignSchedule(cancelMe)).success);
  // 캠페인 자체는 남아야 한다. 취소가 삭제였다면 문구를 다시 쓰게 된다.
  check('캠페인은 지워지지 않는다', (await db.getPushCampaign(cancelMe)) !== null);

  console.log('\n[야간에는 보내지 않는다]');
  const atNight = await makeCampaign({ scheduledAt: minutesFromNow(-5) });
  const nightResult = await sendCampaign(
    await db.getPushCampaign(atNight), deps(fakeSender({ calls: [] }), { night: true }));
  eq('야간이면 거부', nightResult.refused, REFUSED.NIGHT);
  // 예약이 남아 있어야 한다. claim 을 먼저 하면 예약이 초안으로 떨어져
  // "야간이라 못 보냈다"가 "예약이 사라졌다"로 바뀐다.
  eq('예약은 그대로 남는다', await statusOf(atNight), 'scheduled');

  console.log('\n[수신 대상이 없을 때]');
  // 아직 아무 유저도 동의시키지 않았다 — 이 시점의 대상은 이 테스트가
  // 만든 유저가 아니라 DB 전체이므로, 비어 있을 때만 의미가 있다.
  const audienceNow = await db.getMarketingAudience('all');
  if (audienceNow.length === 0) {
    const noOne = await makeCampaign({ scheduledAt: minutesFromNow(-5) });
    const r = await sendCampaign(await db.getPushCampaign(noOne), deps(fakeSender({ calls: [] })));
    eq('대상이 없으면 거부', r.refused, REFUSED.NO_AUDIENCE);
    eq('초안으로 내려온다', await statusOf(noOne), 'draft');
    check('사유가 남는다', !!(await errorOf(noOne)));
  } else {
    console.log(`  skip  DB 에 이미 수신동의자 ${audienceNow.length}명이 있어 건너뜀`);
  }

  console.log('\n[발송 — 치환 없는 문구는 전원 같은 문자열로 나간다]');
  await makeUser(1);
  await makeUser(2);
  const plainLog = { calls: [] };
  const plain = await makeCampaign({ scheduledAt: minutesFromNow(-5), body: '주말 이벤트!' });
  const plainResult = await sendCampaign(await db.getPushCampaign(plain), deps(fakeSender(plainLog)));
  check('발송된다', plainResult.sent === true);
  eq('상태는 발송됨', await statusOf(plain), 'sent');
  check('치환 모드가 아니다 — multicast 로 나가야 한다', plainLog.calls[0].personalized === false);
  const plainMsg = plainLog.calls[0].messages.find((m) => m.nickname === nick(1));
  check('본문이 원문 그대로', plainMsg.body.startsWith('주말 이벤트!'));
  check('수신거부 안내가 붙는다', plainMsg.body.includes('수신거부'));

  console.log('\n[발송 — {nickname} 은 1인분씩 다르게 나간다]');
  const perLog = { calls: [] };
  const per = await makeCampaign({
    scheduledAt: minutesFromNow(-5),
    title: `(광고) {nickname}님께 ${run}`,
    body: '{nickname}님, 50골드 받아가세요!',
  });
  const perResult = await sendCampaign(await db.getPushCampaign(per), deps(fakeSender(perLog)));
  check('발송된다', perResult.sent === true);
  check('치환 모드 — sendEach 로 나가야 한다', perLog.calls[0].personalized === true);
  const mine = perLog.calls[0].messages.filter((m) => String(m.nickname || '').startsWith(`예약${run}_`));
  check('내 유저 둘에게 갔다', mine.length === 2);
  for (const m of mine) {
    check(`${m.nickname} 본문에 자기 닉네임`, m.body.startsWith(`${m.nickname}님,`), m.body);
    check(`${m.nickname} 제목에 자기 닉네임`, m.title.includes(m.nickname), m.title);
    check(`${m.nickname} 중괄호가 남지 않았다`, !m.body.includes('{'), m.body);
  }
  check('서로 다른 문구를 받았다', mine[0].body !== mine[1].body);
  // 저장된 본문은 치환 전 원문이어야 한다. 특정인의 이름이 박히면 그
  // 캠페인을 다시 보거나 템플릿으로 되쓸 때 그 이름이 따라온다.
  const perRow = await db.getPushCampaign(per);
  check('DB 에는 원문이 남는다', perRow.body.includes('{nickname}'), perRow.body);

  console.log('\n[두 번 보내지 않는다]');
  const again = await sendCampaign(await db.getPushCampaign(per), deps(fakeSender({ calls: [] })));
  eq('발송된 건은 거부', again.refused, REFUSED.ALREADY_SENT);

  console.log("\n['sending' 에 갇힌 건 — 자동 재발송하지 않는다]");
  const stuck = await makeCampaign({ scheduledAt: minutesFromNow(-5) });
  await db.claimCampaignForSend(stuck);
  // 방금 집은 건은 아직 정상 발송 중일 수 있다. 되살리면 두 번 나간다.
  check('방금 집힌 건은 건드리지 않는다', !(await db.reviveStuckCampaigns(15)).includes(stuck));
  await db.pool.query(
    `UPDATE tc_push_campaigns SET last_send_attempt_at =
       (NOW() AT TIME ZONE 'UTC') - INTERVAL '30 minutes' WHERE id = $1`, [stuck]);
  check('오래 갇힌 건은 내려온다', (await db.reviveStuckCampaigns(15)).includes(stuck));
  eq('예약이 아니라 초안으로 — 사람이 보고 결정한다', await statusOf(stuck), 'draft');
  check('왜 갇혔는지 남는다', !!(await errorOf(stuck)));
  check('초안이 된 건은 틱 대상이 아니다',
    !(await db.getDueCampaigns(100)).map((c) => c.id).includes(stuck));

  console.log('\n[실패 사유는 다음 시도에서 지워진다]');
  const retried = await makeCampaign({ scheduledAt: minutesFromNow(-5) });
  await db.failCampaignSend(retried, '지난번 실패');
  check('사유가 적혀 있다', (await errorOf(retried)) === '지난번 실패');
  await db.scheduleCampaign(retried, minutesFromNow(-1));
  eq('다시 예약하면 사유가 지워진다', await errorOf(retried), null);

  console.log('\n[템플릿]');
  const tplName = `테스트템플릿_${run}`;
  const made = await db.createPushTemplate(
    { name: tplName, title: '(광고) {nickname}님 안녕', body: '본문' }, 'test');
  check('저장된다', made.success === true);
  const dup = await db.createPushTemplate(
    { name: tplName, title: '(광고) 다른 제목', body: '다른 본문' }, 'test');
  // 덮어쓰면 기존 문구가 사라진 걸 다음 발송 때야 알게 된다.
  check('같은 이름은 거부된다', dup.success === false);
  check('거부 사유가 사람이 읽을 문장', !!dup.message);
  check('수정된다', (await db.updatePushTemplate(made.id, {
    name: tplName, title: '(광고) 바뀐 제목', body: '바뀐 본문',
  })).success);
  eq('수정이 반영된다', (await db.getPushTemplate(made.id)).title, '(광고) 바뀐 제목');
  check('목록에 보인다', (await db.listPushTemplates()).some((t) => t.id === made.id));
  check('없는 id 수정은 실패', !(await db.updatePushTemplate(-1, {
    name: `없음_${run}`, title: '(광고) x', body: 'y',
  })).success);
  await db.deletePushTemplate(made.id);
  eq('삭제된다', await db.getPushTemplate(made.id), null);

  // 정리 — 테스트가 만든 것만 지운다.
  await db.pool.query(
    `DELETE FROM tc_push_campaigns WHERE created_by = 'test' AND title LIKE $1`,
    [`%${run}%`]);
  await db.pool.query('DELETE FROM tc_push_templates WHERE name LIKE $1', [`%${run}%`]);
  await db.pool.query('DELETE FROM tc_users WHERE nickname LIKE $1', [`예약${run}_%`]);

  console.log(failures === 0 ? '\n전부 통과\n' : `\n${failures}건 실패\n`);
  await db.pool.end();
  process.exit(failures === 0 ? 0 : 1);
})().catch(async (err) => {
  console.error('\n테스트가 중단됐습니다:', err);
  process.exit(1);
});
