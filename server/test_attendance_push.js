'use strict';
/**
 * 출석 알림 문구.
 *
 * 여기서 잡고 싶은 사고는 셋이다.
 *
 * 1) 키 오타. i18n 의 t() 는 없는 키를 조용히 generic_error 로 바꾼다. 그래서
 *    키를 하나 잘못 적으면 "오류가 발생했습니다" 라는 푸시가 전 세계로 나간다.
 *    실패가 실패처럼 안 보이는 종류라 반드시 막아야 한다.
 * 2) 번역 누락. ko 만 채우고 en/de 를 잊으면 같은 사고가 그 로케일에서 난다.
 * 3) 광고 표기 누락. 제목의 (광고) 와 본문의 수신거부 안내는 법이 요구한다.
 */

const assert = require('assert');
const { attendancePushText, attendancePushKind } = require('./attendance_push');
const { parseTzOffsetMinutes, nextAttendanceStreak } = require('./db/database');
const ko = require('./locales/ko.json');
const en = require('./locales/en.json');
const de = require('./locales/de.json');

const LOCALES = { ko, en, de };
const AD_LABEL = { ko: '(광고)', en: '(AD)', de: '(Werbung)' };

let failures = 0;
function check(cond, msg) {
  if (cond) console.log(`  ok   ${msg}`);
  else { failures++; console.log(`  FAIL ${msg}`); }
}

console.log('연속 일수에 따른 문구 갈래');
check(attendancePushKind(7) === 'finale', '7일차는 1,000골드를 앞둔 문구');
check(attendancePushKind(1) === 'new', '1일차는 처음 시작하는 문구');
for (const n of [2, 3, 4, 5, 6]) {
  check(attendancePushKind(n) === 'streak', `${n}일차는 이어가는 문구`);
}

console.log('\n로케일별로 실제 문구가 나오는가');
for (const [loc, catalog] of Object.entries(LOCALES)) {
  const generic = catalog.generic_error;
  for (const streak of [1, 3, 7]) {
    const { title, body } = attendancePushText(loc, streak);
    check(!title.includes(generic) && !body.includes(generic),
      `${loc}/${streak}일차: 키가 살아 있다 (generic_error 로 안 떨어짐)`);
    check(title.startsWith(AD_LABEL[loc]),
      `${loc}/${streak}일차: 제목이 ${AD_LABEL[loc]} 로 시작`);
    check(body.includes(catalog.push_marketing_opt_out.trim()),
      `${loc}/${streak}일차: 본문에 수신거부 안내`);
    check(!/\{\w+\}/.test(title + body),
      `${loc}/${streak}일차: 치환 안 된 자리표시자가 없다`);
  }
  // 이어가는 문구에는 며칠째인지가 실제로 들어가야 한다. 안 들어가면
  // 3일째 사람과 6일째 사람에게 같은 말을 하는 셈이다.
  const t3 = attendancePushText(loc, 3);
  check(t3.title.includes('3') || t3.body.includes('3'),
    `${loc}: 이어가는 문구에 일수가 들어간다`);
}

console.log('\n모르는 로케일');
const unknown = attendancePushText('fr', 3);
check(unknown.title.startsWith('(광고)'), '모르는 로케일은 ko 로 떨어진다');

console.log('\n오늘 받으면 며칠째인가');
// 출석 처리와 알림이 같은 답을 내야 한다. 다르면 알림이 거짓말을 한다.
for (const [streak, continues, want] of [
  [0, false, 1], [3, true, 4], [6, true, 7],
  [7, true, 1],   // 7일을 채웠으면 새 주기의 1일차. 8일차는 없다.
  [3, false, 1],  // 하루 빠지면 처음부터
  [0, true, 1],
]) {
  check(nextAttendanceStreak(streak, continues) === want,
    `${streak}일차 + ${continues ? '어제 받음' : '끊김'} → ${want}일차`);
}

console.log('\n기기 타임존 파싱');
for (const [raw, want] of [['540', 540], ['0', 0], ['-480', -480], ['330', 330],
  ['345', 345], ['', null], [null, null], ['abc', null], ['9999', null]]) {
  check(parseTzOffsetMinutes(raw) === want,
    `${JSON.stringify(raw)} → ${want}`);
}

console.log(failures === 0 ? '\n전부 통과' : `\n${failures}건 실패`);
process.exit(failures === 0 ? 0 : 1);
