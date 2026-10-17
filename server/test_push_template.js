/**
 * 푸시 문구의 치환 — 무엇이 바뀌고, 무엇이 저장에서 막히는가.
 *
 * 이 파일이 지키는 사고는 하나다: 한 번 적은 문구가 수천 명에게 나가고,
 * 나간 뒤에는 되돌릴 수 없다. 그래서
 *
 *  - 오타난 변수({nickanme})는 저장에서 막혀야 한다. 렌더는 모르는 변수를
 *    그냥 통과시키므로, 막지 않으면 중괄호째로 발송된다.
 *  - 닉네임이 비어도 "안녕하세요 님," 같은 깨진 문장이 나가서는 안 된다.
 *  - {nickname} 과 {{nickname}} 둘 다 받아야 한다. 어느 표기로 쓸지는
 *    적는 사람 마음이고, 틀린 쪽은 발송 후에야 드러난다.
 *
 * DB·서버 없이 돈다.
 *
 * Run: node server/test_push_template.js
 */
const {
  PUSH_TEMPLATE_VARS, NICKNAME_FALLBACK,
  renderPushTemplate, previewPushTemplate,
  templateVarsUsed, unknownTemplateVars, templateTextError,
} = require('./push_template');
const { withMarketingOptOut } = require('./marketing_rules');

let failures = 0;
const check = (label, cond, detail = '') => {
  console.log(`${cond ? '  ok  ' : '  FAIL'} ${label}${!cond && detail ? ` — ${detail}` : ''}`);
  if (!cond) failures++;
};
const eq = (label, got, want) => check(label, got === want, `got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);

console.log('\n[치환]');
eq('{nickname} 이 닉네임으로 바뀐다',
  renderPushTemplate('{nickname}님 안녕하세요', { nickname: '지니' }), '지니님 안녕하세요');
eq('{{nickname}} 도 같이 받는다',
  renderPushTemplate('{{nickname}}님 안녕하세요', { nickname: '지니' }), '지니님 안녕하세요');
eq('중괄호 안 공백을 허용한다',
  renderPushTemplate('{ nickname }님', { nickname: '지니' }), '지니님');
eq('한 문구에 여러 번 나와도 모두 바뀐다',
  renderPushTemplate('{nickname}님, {nickname}님!', { nickname: '지니' }), '지니님, 지니님!');
eq('변수가 없으면 원문 그대로',
  renderPushTemplate('주말 이벤트 안내', { nickname: '지니' }), '주말 이벤트 안내');

console.log('\n[닉네임이 성치 않을 때 — 깨진 문장이 수천 명에게 나가는 자리]');
eq('빈 문자열이면 대체어', renderPushTemplate('{nickname}님', { nickname: '' }), `${NICKNAME_FALLBACK}님`);
eq('공백뿐이어도 대체어', renderPushTemplate('{nickname}님', { nickname: '   ' }), `${NICKNAME_FALLBACK}님`);
eq('null 이어도 대체어', renderPushTemplate('{nickname}님', { nickname: null }), `${NICKNAME_FALLBACK}님`);
eq('vars 를 아예 안 줘도 대체어', renderPushTemplate('{nickname}님'), `${NICKNAME_FALLBACK}님`);
eq('본문이 비어도 던지지 않는다', renderPushTemplate(null, { nickname: '지니' }), '');

console.log('\n[모르는 변수는 저장에서 막는다]');
check('{nickanme} 오타를 집어낸다', unknownTemplateVars('{nickanme}님').length === 1);
check('오타에는 사유가 붙는다', (templateTextError('{nickanme}님') || '').includes('{nickanme}'));
check('쓸 수 있는 변수가 뭔지 알려준다', (templateTextError('{gold}님') || '').includes('{nickname}'));
eq('올바른 변수는 통과', templateTextError('{nickname}님 안녕'), null);
eq('변수가 없어도 통과', templateTextError('주말 이벤트'), null);
// 막는 건 저장뿐이다. 렌더까지 지워버리면 문장이 조용히 이상해지고, 남아
// 있으면 어디가 틀렸는지 푸시 본문에서 바로 보인다.
eq('렌더는 모르는 변수를 지우지 않는다',
  renderPushTemplate('{gold}원 보유', { nickname: '지니' }), '{gold}원 보유');

console.log('\n[목록 — UI 도움말과 미리보기가 읽는 값]');
check('변수는 닉네임 하나뿐', PUSH_TEMPLATE_VARS.length === 1 && PUSH_TEMPLATE_VARS[0].name === 'nickname');
check('샘플 값이 있다', !!PUSH_TEMPLATE_VARS[0].sample);
eq('사용된 변수를 등장 순서대로', templateVarsUsed('{nickname} {gold} {nickname}').join(','), 'nickname,gold');
eq('미리보기는 샘플로 렌더',
  previewPushTemplate('{nickname}님 안녕'), `${PUSH_TEMPLATE_VARS[0].sample}님 안녕`);

console.log('\n[수신거부 안내와 함께 — 발송되는 본문의 최종 모양]');
// 발송 경로는 수신거부 안내를 붙인 뒤 치환한다. 두 변환이 서로를 망치지
// 않아야 한다 — 안내문에 중괄호가 없으므로 순서는 결과를 바꾸지 않는다.
const bodyOut = renderPushTemplate(withMarketingOptOut('{nickname}님 50골드!'), { nickname: '지니' });
check('치환되고', bodyOut.startsWith('지니님 50골드!'));
check('수신거부 안내가 붙어 있다', bodyOut.includes('수신거부'));
eq('순서를 바꿔도 같은 결과',
  withMarketingOptOut(renderPushTemplate('{nickname}님 50골드!', { nickname: '지니' })), bodyOut);

console.log(failures === 0 ? '\n전부 통과\n' : `\n${failures}건 실패\n`);
process.exit(failures === 0 ? 0 : 1);
