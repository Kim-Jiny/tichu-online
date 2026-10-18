'use strict';
/**
 * 푸시가 나간 뒤의 뒤처리 순서.
 *
 * 푸시는 되돌릴 수 없다. 그래서 나간 뒤에 하는 일들은 "실패해도 보상
 * 수령을 막지 않는" 순서여야 한다. 실제로 죽은 FCM 토큰을 정리하는 줄이
 * 캠페인을 여는 줄보다 앞에 있어서, 거기서 DB 가 한 번 흔들리면 멀쩡히
 * 푸시를 받은 사람들까지 보상을 못 받았다 — 알림을 열어 보니 받을 게
 * 없는 상태다.
 *
 * sendCampaign 은 바깥 일을 전부 주입받으므로, 실패를 심어 순서를 직접
 * 확인할 수 있다.
 *
 *   node test_push_campaign_order.js
 */
const { sendCampaign } = require('./push_campaign_send.js');

let ok = true;
const chk = (n, c, d = '') => {
  console.log(c ? '  ok  ' : '  FAIL', n + (!c && d ? ` — ${d}` : ''));
  if (!c) ok = false;
};

/// 기본 의존성. 필요한 것만 덮어쓴다.
function deps(over = {}) {
  const calls = [];
  const base = {
    calls,
    isKstNight: () => false,
    // 실제 함수는 집어든 캠페인 '행' 을 그대로 돌려준다(없으면 null).
    // 모양이 다르면 claimed.id 가 undefined 가 되어, 로그와 분기가
    // 현실과 다르게 돈다.
    claimCampaignForSend: async () => ({
      id: 7, status: 'sending', title: '제목', body: '본문',
      target_filter: 'all', reward_gold: 0,
    }),
    getMarketingAudience: async () => ([
      { id: 1, nickname: 'a', fcm_token: 't1' },
      { id: 2, nickname: 'b', fcm_token: 't2' },
    ]),
    reserveCampaignRecipients: async () => ({ success: true }),
    sendBroadcastPush: async () => ({
      successCount: 1,
      failCount: 1,
      invalidUserIds: [2],
      results: [{ userId: 1, success: true }, { userId: 2, success: false }],
    }),
    markFcmTokensInvalid: async () => { calls.push('cleanup'); },
    openCampaignForClaims: async () => { calls.push('open'); return { success: true }; },
    recordCampaignSend: async () => { calls.push('record'); return { success: true }; },
    failCampaignSend: async () => { calls.push('fail'); },
  };
  return { ...base, ...over, calls };
}

(async () => {
  console.log('[보상 수령을 먼저 연다]');
  {
    const d = deps();
    const r = await sendCampaign({ id: 7, status: 'scheduled' }, d);
    chk('보냈다', r.sent === true, JSON.stringify(r));
    const open = d.calls.indexOf('open');
    const cleanup = d.calls.indexOf('cleanup');
    chk('여는 일이 토큰 정리보다 먼저', open >= 0 && open < cleanup,
      d.calls.join(' → '));
  }

  console.log('\n[토큰 정리가 실패해도 보상은 열린다]');
  {
    // 푸시는 이미 나갔다. 여기서 던진다고 되돌릴 수 없고, 죽은 토큰
    // 정리는 다음 발송을 조금 비효율적으로 만들 뿐이다.
    const d = deps({
      markFcmTokensInvalid: async () => { throw new Error('일시적 DB 오류'); },
    });
    let threw = null;
    let r = null;
    try {
      r = await sendCampaign({ id: 7, status: 'scheduled' }, d);
    } catch (e) {
      threw = e;
    }
    chk('던지지 않는다', threw === null, threw && threw.message);
    chk('보냈다고 답한다', r && r.sent === true, JSON.stringify(r));
    chk('캠페인이 열렸다', d.calls.includes('open'), d.calls.join(' → '));
    chk('집계도 돌았다', d.calls.includes('record'), d.calls.join(' → '));
  }

  console.log('\n[아무에게도 못 갔으면 열지 않는다]');
  {
    const d = deps({
      sendBroadcastPush: async () => ({
        successCount: 0, failCount: 2, invalidUserIds: [], results: [],
        error: 'firebase down',
      }),
    });
    const r = await sendCampaign({ id: 7, status: 'scheduled' }, d);
    chk('열지 않는다', !d.calls.includes('open'), d.calls.join(' → '));
    chk('이유를 남긴다', d.calls.includes('fail'), d.calls.join(' → '));
    chk('보냈다고 하지 않는다', r.sent !== true || r.successCount === 0,
      JSON.stringify(r));
  }

  console.log(ok ? '\n전부 통과' : '\n실패 있음');
  process.exit(ok ? 0 : 1);
})().catch((e) => { console.error(e); process.exit(1); });
