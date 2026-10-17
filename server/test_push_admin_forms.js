/**
 * 어드민 폼이 무엇을 거부하는가 — 템플릿 저장과 예약 발송.
 * (쓰고 버리는 DB, 8096 포트)
 *   node server/test_push_admin_forms.js
 *
 * 렌더가 아니라 거부를 본다. 이 화면에서 통과한 문구는 손을 거치지 않고
 * 수천 명에게 나가고, 나간 뒤에는 되돌릴 수 없다. 막아야 하는 것들:
 *
 *  - (광고) 없는 제목 — 정보통신망법 §50 ④. 템플릿에서도 막는다. 템플릿은
 *    "그대로 불러 보내는" 용도라서, 통과시켜 두면 그 제목이 캠페인 폼을
 *    거쳐 그대로 나가기를 기다리고 앉아 있는다.
 *  - 오타난 변수 — {nickanme} 는 렌더를 그냥 통과해 중괄호째로 발송된다.
 *  - 야간(21~08시 KST) 예약 — 받아두면 그 시각에 조용히 실패한다.
 *  - 이미 지난 시각 예약 — 다음 틱에 바로 나간다. 보통은 날짜를 잘못 고른 것이다.
 *  - 같은 이름의 템플릿 — 덮어쓰면 기존 문구가 사라진 걸 다음 발송 때 안다.
 */
const { Pool } = require('pg');
const { spawn } = require('child_process');
const http = require('http');

const ADMIN_URL = process.env.TEST_PG_ADMIN || 'postgresql://jiny@localhost:5432/postgres';
const DB = 'tichu_push_forms';
const PORT = 8096;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let failures = 0;
const check = (label, cond, detail = '') => {
  console.log(`${cond ? '  ok  ' : '  FAIL'} ${label}${!cond && detail ? ` — ${detail}` : ''}`);
  if (!cond) failures++;
};

const req = (method, path, body, cookie) => new Promise((resolve, reject) => {
  const data = body ? new URLSearchParams(body).toString() : null;
  const r = http.request({
    host: 'localhost', port: PORT, path, method,
    headers: {
      ...(cookie ? { Cookie: cookie } : {}),
      ...(data ? { 'Content-Type': 'application/x-www-form-urlencoded', 'Content-Length': Buffer.byteLength(data) } : {}),
    },
  }, (res) => {
    const chunks = [];
    res.on('data', (c) => chunks.push(c));
    res.on('end', () => resolve({
      status: res.statusCode, headers: res.headers,
      body: Buffer.concat(chunks).toString('utf8'),
    }));
  });
  r.on('error', reject);
  if (data) r.write(data);
  r.end();
});

/// 리다이렉트의 msg 파라미터 — 폼이 사람에게 돌려주는 문장.
const said = (r) => {
  const loc = r.headers.location || '';
  const q = loc.indexOf('?');
  if (q < 0) return '';
  return new URLSearchParams(loc.slice(q + 1)).get('msg') || '';
};
const refused = (r) => (r.headers.location || '').includes('r=fail');

/// datetime-local 이 보내는 모양(YYYY-MM-DDTHH:MM)으로, KST 벽시계 기준.
///
/// "내일"로 잡는 이유는 테스트가 몇 시에 돌든 결과가 같아야 하기 때문이다.
/// 오늘 14시는 지금이 15시면 과거다.
function kstTomorrowAt(hhmm) {
  const parts = new Intl.DateTimeFormat('sv-SE', {
    timeZone: 'Asia/Seoul', year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(new Date(Date.now() + 24 * 60 * 60 * 1000));
  return `${parts}T${hhmm}`;
}

const AD = '(광고)';

async function main() {
  const admin = new Pool({ connectionString: ADMIN_URL });
  await admin.query(`DROP DATABASE IF EXISTS ${DB}`);
  await admin.query(`CREATE DATABASE ${DB}`);
  const dbUrl = ADMIN_URL.replace(/\/postgres$/, `/${DB}`);
  const pool = new Pool({ connectionString: dbUrl });
  const srv = spawn('node', ['server.js'], {
    cwd: __dirname,
    env: { ...process.env, PORT: String(PORT), DATABASE_URL: dbUrl },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let log = '';
  srv.stdout.on('data', (d) => { log += d; });
  srv.stderr.on('data', (d) => { log += d; });
  for (let i = 0; i < 100 && !/listening|running|8096/i.test(log); i++) await sleep(200);
  await sleep(800);

  try {
    const bcrypt = require(require.resolve('bcrypt', { paths: [__dirname] }));
    await pool.query(
      `INSERT INTO admin_accounts (username, password) VALUES ('forms_admin', $1)
       ON CONFLICT (username) DO UPDATE SET password = EXCLUDED.password`,
      [await bcrypt.hash('adminpass1!', 4)],
    );
    const login = await req('POST', '/tc-backstage/login',
      { username: 'forms_admin', password: 'adminpass1!' });
    const cookie = (login.headers['set-cookie'] || [])[0]?.split(';')[0];
    check('로그인', login.status === 302 && !!cookie);

    const TPL = '/tc-backstage/campaigns/templates';
    const CAM = '/tc-backstage/campaigns';

    console.log('\n[템플릿 저장이 거부하는 것]');
    const noLabel = await req('POST', TPL,
      { name: '라벨없음', title: '주말 이벤트 안내', body: '본문' }, cookie);
    check('(광고) 없는 제목은 거부', refused(noLabel) && said(noLabel).includes(AD), said(noLabel));

    const typo = await req('POST', TPL,
      { name: '오타', title: `${AD} 안내`, body: '{nickanme}님 안녕' }, cookie);
    check('오타난 변수는 거부', refused(typo) && said(typo).includes('{nickanme}'), said(typo));

    const unknownVar = await req('POST', TPL,
      { name: '모르는변수', title: `${AD} 안내`, body: '{gold}원 보유중' }, cookie);
    check('지원하지 않는 변수는 거부', refused(unknownVar), said(unknownVar));

    const blank = await req('POST', TPL, { name: '', title: `${AD} x`, body: 'y' }, cookie);
    check('이름이 비면 거부', refused(blank), said(blank));

    console.log('\n[템플릿 저장이 받아들이는 것]');
    const ok = await req('POST', TPL,
      { name: '주말이벤트', title: `${AD} {nickname}님께`, body: '{nickname}님, 50골드!' }, cookie);
    check('(광고) 와 올바른 변수는 통과', !refused(ok), said(ok));
    const tplRow = (await pool.query(
      'SELECT * FROM tc_push_templates WHERE name = $1', ['주말이벤트'])).rows[0];
    check('DB 에 저장됐다', !!tplRow);
    // 저장되는 건 치환 전 원문이어야 한다. 특정인의 이름이 박히면 되쓸 때
    // 그 이름이 따라온다.
    check('원문이 그대로 저장된다', tplRow && tplRow.body.includes('{nickname}'), tplRow && tplRow.body);

    const dup = await req('POST', TPL,
      { name: '주말이벤트', title: `${AD} 다른제목`, body: '다른본문' }, cookie);
    check('같은 이름은 거부', refused(dup), said(dup));

    console.log('\n[확인창이 실제로 설치되는가 — 되돌릴 수 없는 버튼들]');
    // 템플릿 리터럴 안의 \n 은 출력에 생개행을 넣는다. 단일 인용 JS 문자열에
    // 생개행이 들어가면 SyntaxError 라 onsubmit 이 설치되지 않고, 폼은 확인
    // 없이 제출된다 — 발송 버튼 한 번에 전원에게 광고가 나간다. 렌더된 속성을
    // 실제로 파싱해 봐야 잡히는 결함이라 여기서 본다.
    for (const [name, path] of [['마케팅 푸시', CAM], ['푸시 템플릿', TPL]]) {
      const page = await req('GET', path, null, cookie);
      const attrs = [...page.body.matchAll(/onsubmit="([^"]*)"/g)].map((m) => m[1]);
      check(`${name}: onsubmit 이 있다`, attrs.length > 0, String(attrs.length));
      check(`${name}: 속성에 생개행이 없다`, !attrs.some((a) => /[\r\n]/.test(a)));
      let broken = 0;
      for (const raw of attrs) {
        // 브라우저는 속성을 HTML 디코드한 뒤 JS 로 파싱한다.
        const js = raw.replace(/&quot;/g, '"').replace(/&#39;/g, "'")
          .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
        try { new Function(js); } catch (e) {
          broken++;
          console.log(`      깨짐: ${JSON.stringify(js.slice(0, 80))} → ${e.message}`);
        }
      }
      check(`${name}: ${attrs.length}개 모두 유효한 JS`, broken === 0, `${broken}개 깨짐`);
    }

    console.log('\n[템플릿이 캠페인 폼에 실려 있다]');
    const campPage = await req('GET', CAM, null, cookie);
    check('드롭다운에 이름이 보인다', campPage.body.includes('주말이벤트'));
    check('미리보기 칸이 있다', campPage.body.includes('campPreview'));
    check('예약 입력 칸이 있다', campPage.body.includes('name="scheduled_at"'));
    check('변수 도움말이 있다', campPage.body.includes('{nickname}'));

    console.log('\n[템플릿 수정과 삭제]');
    const edited = await req('POST', `${TPL}/${tplRow.id}`,
      { name: '주말이벤트', title: `${AD} 바뀐제목`, body: '{nickname}님!' }, cookie);
    check('수정된다', !refused(edited), said(edited));
    check('수정이 반영된다', (await pool.query(
      'SELECT title FROM tc_push_templates WHERE id = $1', [tplRow.id])).rows[0].title.includes('바뀐제목'));
    const editBad = await req('POST', `${TPL}/${tplRow.id}`,
      { name: '주말이벤트', title: '라벨없는 제목', body: '본문' }, cookie);
    check('수정도 (광고) 를 요구한다', refused(editBad), said(editBad));

    console.log('\n[예약이 거부하는 시각]');
    const campaign = (extra) => ({
      title: `${AD} 예약 테스트`, body: '{nickname}님 안녕', reward_gold: '0',
      target_filter: 'all', ...extra,
    });
    const night = await req('POST', CAM,
      campaign({ scheduled_at: kstTomorrowAt('22:00') }), cookie);
    check('야간(22시) 예약은 거부', refused(night) && said(night).includes('21~08'), said(night));
    const dawn = await req('POST', CAM,
      campaign({ scheduled_at: kstTomorrowAt('07:30') }), cookie);
    check('새벽(7시반) 예약도 거부', refused(dawn), said(dawn));
    const pastAt = new Date(Date.now() - 2 * 60 * 60 * 1000);
    const pastLocal = new Intl.DateTimeFormat('sv-SE', {
      timeZone: 'Asia/Seoul', year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit', hour12: false,
    }).format(pastAt).replace(' ', 'T');
    const past = await req('POST', CAM, campaign({ scheduled_at: pastLocal }), cookie);
    check('지난 시각 예약은 거부', refused(past), said(past));
    const badVar = await req('POST', CAM,
      campaign({ body: '{nickanme}님', scheduled_at: kstTomorrowAt('14:00') }), cookie);
    check('캠페인도 오타난 변수를 거부', refused(badVar) && said(badVar).includes('{nickanme}'), said(badVar));

    console.log('\n[예약이 받아들이는 시각]');
    const good = await req('POST', CAM,
      campaign({ scheduled_at: kstTomorrowAt('14:00') }), cookie);
    check('주간(14시) 예약은 통과', !refused(good), said(good));
    check('언제 나가는지 알려준다', said(good).includes('예약'), said(good));
    const row = (await pool.query(
      `SELECT * FROM tc_push_campaigns ORDER BY id DESC LIMIT 1`)).rows[0];
    check('상태가 예약', row.status === 'scheduled', row.status);
    check('발송 시각이 저장됐다', !!row.scheduled_at);
    // 저장은 UTC. KST 14시는 UTC 05시다 — 이게 틀리면 9시간 어긋난 때 나간다.
    check('KST 를 UTC 로 바꿔 저장한다', new Date(`${row.scheduled_at}Z`).getUTCHours() === 5,
      String(row.scheduled_at));

    console.log('\n[예약 없이 저장하면 초안]');
    const draft = await req('POST', CAM, campaign({ scheduled_at: '' }), cookie);
    check('통과한다', !refused(draft), said(draft));
    check('예약이 아니라 저장이라고 답한다', !said(draft).includes('예약'), said(draft));
    check('상태가 초안', (await pool.query(
      `SELECT status FROM tc_push_campaigns ORDER BY id DESC LIMIT 1`)).rows[0].status === 'draft');

    console.log('\n[예약을 기다리지 않고 지금 보내기]');
    // 예약 행에도 발송 버튼이 있어야 한다. 없으면 "취소하고 다시 누르기"를
    // 거쳐야 하고, 그 사이에 예약 시각이 지나 저절로 나갈 수도 있다.
    const schedPage = await req('GET', CAM, null, cookie);
    check('예약 행에 지금 보내기 버튼', schedPage.body.includes('지금 보내기'));
    check('같은 행에 예약 취소도 있다', schedPage.body.includes(`/campaigns/${row.id}/unschedule`));
    // 발송은 claim 을 지나므로 예약 틱과 동시에 들어와도 한쪽만 나간다.
    const sendNow = await req('POST', `${CAM}/${row.id}/send`, {}, cookie);
    const afterNow = (await pool.query(
      'SELECT status, last_send_error FROM tc_push_campaigns WHERE id = $1', [row.id])).rows[0];
    check('발송 중에 갇혀 있지 않다', afterNow.status !== 'sending', afterNow.status);

    // 결과는 테스트를 돌리는 시각에 따라 갈린다. 야간(21~08 KST)이면 광고성
    // 푸시 자체가 막히므로 claim 전에 거부되고, 그게 맞는 동작이다.
    //
    // 시각을 흉내내지 않고 양쪽을 다 확인하는 이유: 실제로 중요한 건
    // "지금 이 서버에서 이 버튼을 누르면 무엇이 일어나는가" 이고, 야간
    // 분기는 그중 하나다. 한쪽만 보면 밤에 돌릴 때마다 빨간 줄이 뜬다.
    if (said(sendNow).includes('21~08')) {
      console.log('        (야간이라 발송이 막힌 경로를 확인합니다)');
      // 예약이 살아 있어야 한다. claim 을 먼저 했다면 초안으로 떨어져
      // "야간이라 못 보냈다"가 "예약이 사라졌다"로 바뀐다.
      check('야간이면 예약은 그대로 남는다', afterNow.status === 'scheduled',
        JSON.stringify(afterNow));
      check('야간 거부는 실패 사유를 남기지 않는다 — 고칠 것이 없다',
        afterNow.last_send_error === null, String(afterNow.last_send_error));
    } else {
      // 주간. FCM 이 없으므로 전원 전송 실패가 정상이고, 그때 사유가
      // 남아야 한다 — 예약 발송은 보는 사람이 없으니 유일한 기록이다.
      check('예약이라는 이유로 거부되지 않는다',
        !said(sendNow).includes('예약'), said(sendNow));
      check('전원 실패하면 사유가 남는다',
        afterNow.status === 'sent' || !!afterNow.last_send_error,
        JSON.stringify(afterNow));
      // 초안으로 내려온 예약 시각은 아무 일도 하지 않는다. 화면이 그걸
      // 말해 주지 않으면 가만히 두면 나가는 줄 알고 기다리게 된다.
      if (afterNow.status === 'draft') {
        const draftPage = await req('GET', CAM, null, cookie);
        check('초안에 남은 예약 시각은 지났다고 적는다',
          draftPage.body.includes('지금은 예약 아님'));
        check('실패 사유가 목록에 보인다', draftPage.body.includes('⚠'));
      }
    }
    // 다시 예약해 두고 취소 검사로 넘어간다.
    await pool.query(
      `UPDATE tc_push_campaigns SET status = 'scheduled', last_send_error = NULL
       WHERE id = $1`, [row.id]);

    console.log('\n[예약 취소]');
    const listPage = await req('GET', CAM, null, cookie);
    check('목록에 예약 배지가 보인다', listPage.body.includes('예약'));
    check('예약 취소 버튼이 있다', listPage.body.includes(`/campaigns/${row.id}/unschedule`));
    const cancel = await req('POST', `${CAM}/${row.id}/unschedule`, {}, cookie);
    check('취소된다', !refused(cancel), said(cancel));
    check('초안으로 남는다', (await pool.query(
      'SELECT status FROM tc_push_campaigns WHERE id = $1', [row.id])).rows[0].status === 'draft');
    const cancelAgain = await req('POST', `${CAM}/${row.id}/unschedule`, {}, cookie);
    // 예약이 아니었다는 건 보통 그 사이에 발송됐다는 뜻이다. "취소했습니다"로
    // 답하면 안 나간 줄로 알게 된다.
    check('두 번 취소하면 솔직하게 실패', refused(cancelAgain), said(cancelAgain));

    const del = await req('POST', `${TPL}/${tplRow.id}/delete`, {}, cookie);
    check('템플릿이 삭제된다', !refused(del), said(del));
    // 캠페인은 저장할 때 문구를 자기 행에 복사해 간다. 템플릿을 지워도
    // 이미 만들어 둔 캠페인이 비어서는 안 된다.
    check('지워도 캠페인 문구는 남는다', (await pool.query(
      'SELECT body FROM tc_push_campaigns WHERE id = $1', [row.id])).rows[0].body.length > 0);
  } finally {
    srv.kill();
    await sleep(500);
    await pool.end().catch(() => {});
    await admin.query(`DROP DATABASE IF EXISTS ${DB}`).catch(() => {});
    await admin.end().catch(() => {});
  }
  console.log(failures === 0 ? '\n전부 통과\n' : `\n${failures}건 실패\n`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((err) => { console.error(err); process.exit(1); });
