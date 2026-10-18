'use strict';
/**
 * 마케팅 캠페인 한 건을 실제로 발송하는 절차.
 *
 * 손으로 누르는 발송(admin.js 의 /campaigns/:id/send)과 예약 발송(server.js
 * 의 틱)이 같은 코드를 쓰기 위해 여기 있다. 두 벌로 두면 한쪽에만 야간 금지가
 * 들어가거나, 한쪽만 수신자를 먼저 기록하는 식으로 갈라진다 — 그 차이는 수천
 * 명에게 푸시가 나간 뒤에야 드러난다.
 *
 * 순서에 의미가 있다:
 *   1. 야간이면 보내지 않는다 (정보통신망법 §50 ⑤ — 야간 수신동의 없음)
 *   2. 수신동의 대상을 발송 직전에 DB 에서 읽는다 (철회가 즉시 반영됨)
 *   3. 수신자를 먼저 기록한다 — 푸시는 회수할 수 없고 DB 쓰기는 재시도할 수 있다
 *   4. 보낸다
 *   5. 하나라도 전달됐으면 캠페인을 열어 보상 수령을 허용한다
 *   6. 1인분씩 집계한다 (여기서 죽어도 통계만 틀리고 수령은 멀쩡하다)
 *
 * 의존성을 인자로 받는 이유는 sendBroadcastPush 가 server.js 안에 있다는
 * 것뿐이다. require 하면 웹소켓 서버가 뜬다.
 */

const { withMarketingOptOut } = require('./marketing_rules');
const { renderPushTemplate, templateVarsUsed } = require('./push_template');

/// 발송하지 않은 이유들. 호출한 쪽이 사람에게 보여줄 문장을 고르는 데 쓴다.
const REFUSED = {
  ALREADY_SENT: 'already_sent',
  NIGHT: 'night',
  BUSY: 'busy',
  NO_AUDIENCE: 'no_audience',
  RESERVE_FAILED: 'reserve_failed',
  SEND_THREW: 'send_threw',
  ALL_FAILED: 'all_failed',
};

const REFUSED_TEXT = {
  [REFUSED.ALREADY_SENT]: '이미 발송한 캠페인입니다.',
  [REFUSED.NIGHT]: '야간(21~08시 KST)에는 광고성 푸시를 보내지 않습니다.',
  [REFUSED.BUSY]: '다른 곳에서 이미 발송을 시작했습니다. 잠시 뒤 목록을 새로고침해 보세요.',
  [REFUSED.NO_AUDIENCE]: '수신동의한 대상이 없습니다.',
  [REFUSED.RESERVE_FAILED]:
    '수신자 기록에 실패해 발송하지 않았습니다. 아무에게도 안 갔으니 다시 시도하세요.',
  [REFUSED.SEND_THREW]: '발송 중 오류가 났습니다. 수신자 목록을 확인한 뒤 다시 시도하세요.',
  // ALL_FAILED 의 문장은 실패 사유를 담아 호출 지점에서 만든다.
};

/// 캠페인 하나를 보낸다.
///
/// 돌려주는 값:
///   { sent: false, refused: <REFUSED 값>, message }            — 보내지 않음
///   { sent: true, successCount, failCount, problem }           — 보냄
///
/// [problem] 은 "나갔지만 뒤처리가 덜 됐다"는 뜻이다. 두 가지뿐인데 심각도가
/// 다르다 — 캠페인을 열지 못하면 아무도 보상을 못 받고, 집계만 실패했으면
/// 숫자만 틀리다. 뭉뚱그리면 둘 중 어느 쪽인지 모르는 채로 손을 떼게 된다.
async function sendCampaign(campaign, deps) {
  const {
    getMarketingAudience, reserveCampaignRecipients, sendBroadcastPush,
    markFcmTokensInvalid, openCampaignForClaims, recordCampaignSend, isKstNight,
    claimCampaignForSend, failCampaignSend,
  } = deps;

  const refuse = (reason) => ({ sent: false, refused: reason, message: REFUSED_TEXT[reason] });
  /// 집어둔 캠페인을 놓아주며 이유를 남긴다. 'scheduled' 로 돌리지 않는
  /// 이유는 failCampaignSend 의 머리말에 있다 — 같은 사유로 매 틱 재시도하면
  /// 로그만 쌓인다.
  const giveUp = async (reason) => {
    await failCampaignSend(campaign.id, REFUSED_TEXT[reason]);
    return refuse(reason);
  };

  if (campaign.status === 'sent') {
    // 두 번 보내도 돈이 두 번 나가지는 않는다(수신자 행이 UNIQUE). 대신 전원이
    // 알림을 한 번 더 받고 집계가 초기화되므로 막는다.
    return refuse(REFUSED.ALREADY_SENT);
  }
  // 야간 판정은 claim 전에. 뒤에 두면 claim 이 예약을 초안으로 떨어뜨려서,
  // "야간이라 못 보냈다"가 "예약이 사라졌다"로 바뀐다.
  if (isKstNight()) return refuse(REFUSED.NIGHT);

  // 여기가 두 번 발송을 막는 유일한 문이다. 손으로 누른 발송과 예약 틱이
  // 같은 순간 들어와도 한쪽만 행을 받는다.
  const claimed = await claimCampaignForSend(campaign.id);
  if (!claimed) return refuse(REFUSED.BUSY);

  const audience = await getMarketingAudience(claimed.target_filter || 'all');
  if (audience.length === 0) return giveUp(REFUSED.NO_AUDIENCE);

  // 수신자를 먼저 기록한다. 이 순서가 거꾸로면 "알림은 받았는데 서버는 네
  // 것이 아니라고 한다"는 세 번째 결과가 생긴다.
  const reserved = await reserveCampaignRecipients(
    claimed.id, audience.map((u) => u.nickname));
  if (!reserved.success) return giveUp(REFUSED.RESERVE_FAILED);

  // 치환할 게 없으면 문자열 그대로 넘긴다. 그래야 FCM 호출이
  // sendEachForMulticast 로 남는다 — 500명이 HTTP 요청 1건이다. 함수로
  // 넘기면 sendEach 가 되어 1인 1건이 되므로, 필요할 때만 그 값을 치른다.
  const bodyTemplate = withMarketingOptOut(claimed.body);
  const personalize = templateVarsUsed(claimed.title).length > 0
    || templateVarsUsed(bodyTemplate).length > 0;
  const titleArg = personalize
    ? (row) => renderPushTemplate(claimed.title, { nickname: row.nickname })
    : claimed.title;
  const bodyArg = personalize
    ? (row) => renderPushTemplate(bodyTemplate, { nickname: row.nickname })
    : bodyTemplate;

  let push;
  try {
    push = await sendBroadcastPush(
      audience.map((u) => ({ id: u.id, fcm_token: u.fcm_token, nickname: u.nickname })),
      titleArg, bodyArg,
      { type: 'campaign', campaignId: claimed.id },
    );
  } catch (err) {
    // 여기서 던지면 상태가 'sending' 에 갇힌다. 그 상태로는 보상 수령도
    // 막혀 있고 틱도 다시 집지 않으므로, 사람이 볼 수 있는 곳에 내려놓는다.
    // 일부에게 이미 나갔을 수 있다는 건 수신자 목록으로 확인한다.
    console.error(`[campaign] send threw for #${claimed.id}:`, err.message);
    return giveUp(REFUSED.SEND_THREW);
  }
  // 하나라도 전달됐으면 바로 연다. 뒤의 1인분 집계는 전체를 훑어 가장 잘
  // 죽는 구간이고, 보상 수령 게이트가 읽는 건 이 플래그 하나다.
  let opened = { success: true };
  if (push.successCount > 0) opened = await openCampaignForClaims(claimed.id);

  // 죽은 FCM 토큰 정리. 여는 일보다 뒤에 두고, 실패해도 넘어간다.
  //
  // 전에는 이 줄이 위에 있었다. 푸시는 이미 나갔는데 여기서 DB 가 한 번
  // 흔들리면 그대로 던져서, 캠페인이 'sending' 에 갇히고 멀쩡히 푸시를
  // 받은 사람들까지 보상을 못 받았다 — 알림을 열어 보니 받을 게 없는
  // 상태다. 이건 다음 발송을 조금 비효율적으로 만들 뿐인 뒷정리이지,
  // 보상을 막을 만한 일이 아니다.
  try {
    await markFcmTokensInvalid(push.invalidUserIds || []);
  } catch (err) {
    console.error(`[campaign] token cleanup failed for #${claimed.id}:`, err.message);
  }

  const byId = new Map(audience.map((u) => [u.id, u.nickname]));
  const recorded = await recordCampaignSend(claimed.id,
    (push.results || [])
      .map((r) => ({ nickname: byId.get(r.userId), success: r.success }))
      .filter((r) => r.nickname));

  // 한 명에게도 닿지 못했다 — Firebase 설정이 빠졌거나 연결이 안 되는 상황.
  //
  // recordCampaignSend 는 이걸 'draft' 로 내려놓아 발송 버튼을 되살려 주지만
  // 이유는 남기지 않는다. 그 이유를 여기서 적는다. 예약 발송은 보는 사람이
  // 없는 시간에 돌기 때문에, 이 한 줄이 "왜 안 나갔는지"의 유일한 단서다.
  if (push.successCount === 0) {
    const why = push.error
      ? `전송에 실패했습니다: ${push.error}`
      : `대상 ${audience.length}명 전원에게 전송이 실패했습니다.`;
    await failCampaignSend(claimed.id, `${why} 초안으로 되돌렸습니다.`);
    return {
      sent: false,
      refused: REFUSED.ALL_FAILED,
      message: why,
      failCount: push.failCount,
    };
  }

  const problem = !opened.success
    ? ' — 다만 캠페인을 여는 데 실패해서 지금은 보상 수령이 막혀 있습니다. 다시 시도하세요.'
    : !recorded.success
      ? ' — 다만 발송 결과 집계에 실패했습니다. 보상 수령에는 영향이 없고, 통계만 부정확할 수 있습니다.'
      : '';

  return {
    sent: true,
    personalized: personalize,
    audienceSize: audience.length,
    successCount: push.successCount,
    failCount: push.failCount,
    problem,
  };
}

module.exports = { sendCampaign, REFUSED, REFUSED_TEXT };
