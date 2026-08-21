'use strict';
/**
 * 출석 알림에 실을 문구.
 *
 * 이 알림은 광고성 정보다. 무료 재화를 받으라는 권유이므로 정보통신망법이
 * 말하는 영리목적 광고성 정보로 보는 게 안전하고, 그래서 이벤트·혜택 알림
 * (마케팅 동의) 안에 넣었다. 그 대가로 제목의 (광고) 표기와 본문 끝의
 * 수신거부 안내를 매번 달고 나간다 — 캠페인과 같은 규칙이다.
 *
 * server.js 가 아니라 여기 있는 이유는 테스트다. server.js 를 require 하면
 * 웹소켓 서버가 뜬다. 그러면 문구를 확인하려고 서버를 세워야 하고, 결국
 * 아무도 확인하지 않게 된다.
 */

const { t } = require('./i18n');

/// 오늘 받으면 며칠째가 되는지에 따라 할 말이 다르다.
///
/// 7일차를 앞둔 사람에게 특별히 다른 말을 하는 이유는, 거기서 하루를 놓치면
/// 연속이 끊겨 1,000골드가 날아가기 때문이다. 그 손실이 이 알림의 값어치다.
function attendancePushKind(nextStreak) {
  if (nextStreak === 7) return 'finale';
  return nextStreak > 1 ? 'streak' : 'new';
}

function attendancePushText(locale, nextStreak) {
  const kind = attendancePushKind(nextStreak);
  const params = { days: nextStreak };
  return {
    kind,
    title: `${t(locale, 'push_ad_label')} `
      + t(locale, `push_attendance_title_${kind}`, params),
    body: t(locale, `push_attendance_body_${kind}`, params)
      + t(locale, 'push_marketing_opt_out'),
  };
}

module.exports = { attendancePushText, attendancePushKind };
