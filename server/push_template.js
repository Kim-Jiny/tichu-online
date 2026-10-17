'use strict';
/**
 * 푸시 문구에 받는 사람의 값을 끼워 넣는 규칙.
 *
 * 캠페인 본문은 한 번 써서 수천 명에게 나간다. 그래서 "{nickname}님, 주말
 * 이벤트 열렸어요" 처럼 한 줄만 적어두고 받는 사람마다 다르게 렌더해서
 * 보낸다. 치환은 발송하는 순간 1인분씩 일어나고, DB 에 저장되는 본문은
 * 언제나 치환 전 원문이다 — 그래야 캠페인을 다시 보거나 템플릿으로
 * 되쓸 때 "티츄왕님" 같은 특정인의 이름이 박혀 있지 않다.
 *
 * admin.js 가 아니라 여기 있는 이유는 marketing_rules.js 와 같다: 문구가
 * 제대로 렌더되는지 확인하려고 HTTP 서버와 DB 를 세워야 한다면, 결국
 * 아무도 확인하지 않게 된다.
 */

/// 쓸 수 있는 변수. UI 의 도움말과 미리보기가 이 목록을 그대로 읽는다.
///
/// 하나뿐인 건 의도다. 골드 잔액이나 연속 출석일처럼 계정에서 읽어오는 값은
/// 발송 쿼리에 컬럼을 더 붙여야 하고, 그러면 "보내는 시점의 값"과 "푸시를
/// 눌러 들어온 시점의 값"이 어긋난 문구가 나간다. 닉네임은 그 틈이 없다.
const PUSH_TEMPLATE_VARS = [
  {
    name: 'nickname',
    label: '받는 사람 닉네임',
    sample: '티츄왕',
    help: '수신자마다 자기 닉네임으로 바뀝니다',
  },
];

const VAR_NAMES = new Set(PUSH_TEMPLATE_VARS.map((v) => v.name));

/// 같은 변수를 가리키는 다른 표기.
///
/// 화면은 변수를 "{nickname} — 받는 사람 닉네임" 으로 안내한다. 그래서
/// 한글 쪽 설명만 보고 {닉네임} 이라고 적는 일이 생기는데, 그건 틀린 이름이
/// 아니라 같은 것을 가리키는 다른 표기다. 막아서 다시 쓰게 하기보다 받는 쪽이
/// 맞다 — 막아도 결국 맞는 표기를 찾아 다시 저장할 뿐이고, 그 사이에 오타로
/// 발송될 기회만 한 번 더 생긴다.
const VAR_ALIASES = new Map([
  ['닉네임', 'nickname'],
  ['nickName', 'nickname'],
  ['nick_name', 'nickname'],
  ['NICKNAME', 'nickname'],
]);

/// 이 표기가 가리키는 변수 이름. 모르면 null.
function resolveVarName(raw) {
  const name = String(raw || '').trim();
  if (VAR_NAMES.has(name)) return name;
  return VAR_ALIASES.get(name) || null;
}

/// 닉네임을 못 읽었을 때 들어갈 말.
///
/// 발송 대상 쿼리는 닉네임이 있는 계정만 고르므로 평소엔 쓰이지 않는다.
/// 그래도 두는 이유는 이게 비었을 때의 결과가 "안녕하세요 님," 이라는
/// 깨진 문장이고, 그건 수천 명에게 한꺼번에 나가기 때문이다.
const NICKNAME_FALLBACK = '회원님';

/// 중괄호로 묶인 것은 전부 "변수를 쓰려 한 자리"로 본다.
///
/// `{nickname}` 과 `{{nickname}}` 을 모두 받는다 — 한 쪽만 받으면 다른
/// 표기로 쓴 사람이 중괄호가 박힌 푸시를 보내게 되고, 어느 쪽이 맞는지는
/// 발송 후에야 알게 된다.
///
/// 이름 부분을 영문 식별자로 제한하지 않는 게 중요하다. 제한하면 {닉네임}
/// 이나 {nick-name} 처럼 생긴 것이 "변수가 아닌 그냥 글자"로 취급되어
/// 검사를 통과하고, 중괄호째로 수신자 전원에게 나간다. 화면이 약속하는
/// "틀린 변수 이름은 저장되지 않습니다" 가 거기서 깨진다.
///
/// 중괄호를 장식으로 쓰려던 경우까지 걸리지만, 그쪽이 맞다 — 푸시 본문의
/// 중괄호는 거의 언제나 변수를 쓰려던 자리이고, 잘못 보낸 푸시는 되돌릴 수
/// 없다. 저장이 막히면 문장을 고칠 기회가 남는다.
const PLACEHOLDER_RE = /\{\{?\s*([^{}\s][^{}]{0,38})\s*\}\}?/g;

/// 문구에 적힌 변수들을 등장 순서대로. 중복은 한 번만.
///
/// 별칭은 가리키는 이름으로 정규화해 돌려준다. 이 값을 쓰는 쪽(발송 경로)이
/// 묻는 것은 "치환할 것이 있나" 이고, {닉네임} 도 치환할 것이기 때문이다.
function templateVarsUsed(text) {
  const found = [];
  for (const m of String(text || '').matchAll(PLACEHOLDER_RE)) {
    const name = resolveVarName(m[1]) || String(m[1]).trim();
    if (!found.includes(name)) found.push(name);
  }
  return found;
}

/// 우리가 모르는 변수 이름들.
///
/// 저장할 때 이걸 막는 게 이 파일에서 가장 중요한 일이다. `{nickanme}` 처럼
/// 한 글자 틀린 오타는 렌더에서 조용히 통과해 중괄호째로 발송되고, 그때는
/// 이미 되돌릴 수 없다.
function unknownTemplateVars(text) {
  const found = [];
  for (const m of String(text || '').matchAll(PLACEHOLDER_RE)) {
    const raw = String(m[1]).trim();
    if (resolveVarName(raw)) continue;
    if (!found.includes(raw)) found.push(raw);
  }
  return found;
}

/// 치환. 모르는 변수는 건드리지 않고 그대로 둔다.
///
/// 지우지 않는 이유: 저장 때 이미 막혀 있으므로 여기까지 온 미지의 변수는
/// 코드 쪽 실수다. 조용히 사라지면 "왜 문장이 이상한가"를 찾게 되고, 남아
/// 있으면 어디가 틀렸는지 푸시 본문에서 바로 보인다.
function renderPushTemplate(text, vars = {}) {
  const nickname = String(vars.nickname || '').trim() || NICKNAME_FALLBACK;
  const values = { nickname };
  return String(text || '').replace(PLACEHOLDER_RE, (whole, raw) => {
    const name = resolveVarName(raw);
    return name && Object.prototype.hasOwnProperty.call(values, name)
      ? values[name] : whole;
  });
}

/// 관리자 화면의 미리보기가 쓸 정규식 소스 — 닉네임 자리를 집는다.
///
/// 브라우저 쪽에서 따로 쓰지 않고 여기서 만들어 넘기는 이유: 두 벌로 두면
/// 별칭을 하나 더할 때 한쪽만 고치게 되고, 그러면 미리보기와 실제 발송이
/// 달라진다. 미리보기가 실제와 다르면 아무도 믿지 않고, 믿지 않는 미리보기는
/// 없는 것과 같다.
const NICKNAME_PREVIEW_RE_SOURCE = (() => {
  const words = ['nickname', ...VAR_ALIASES.keys()]
    // 정규식에서 뜻을 갖는 문자를 막아둔다. 지금 별칭은 전부 식별자라
    // 걸릴 것이 없지만, 나중에 추가하는 사람이 알 이유는 없다.
    .map((w) => w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
  return `\\{\\{?\\s*(?:${words.join('|')})\\s*\\}\\}?`;
})();

/// 관리자 화면 미리보기용 — 샘플 값으로 렌더한다.
function previewPushTemplate(text) {
  const vars = {};
  for (const v of PUSH_TEMPLATE_VARS) vars[v.name] = v.sample;
  return renderPushTemplate(text, vars);
}

/// 저장 전 검사. 통과하면 null, 아니면 사람이 읽을 이유 한 줄.
function templateTextError(text) {
  const unknown = unknownTemplateVars(text);
  if (unknown.length === 0) return null;
  const known = PUSH_TEMPLATE_VARS.map((v) => `{${v.name}}`).join(', ');
  return `쓸 수 없는 변수입니다: ${unknown.map((n) => `{${n}}`).join(', ')}`
    + ` — 쓸 수 있는 것은 ${known} 입니다.`;
}

module.exports = {
  PUSH_TEMPLATE_VARS,
  VAR_ALIASES,
  NICKNAME_PREVIEW_RE_SOURCE,
  resolveVarName,
  NICKNAME_FALLBACK,
  templateVarsUsed,
  unknownTemplateVars,
  renderPushTemplate,
  previewPushTemplate,
  templateTextError,
};
