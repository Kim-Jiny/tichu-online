/**
 * 통계 화면의 모든 탭을 데이터가 있는 상태로 열어 본다.
 * (쓰고 버리는 DB, 8095 포트)
 *   node server/test_stats_tabs.js
 *
 * 빈 DB 로 여는 것만으로는 부족하다. 숫자가 0 일 때는 분모가 0 인 나눗셈도
 * 비어 있는 배열도 조용히 지나가고, 실제로 깨지는 건 값이 들어온 뒤다.
 * 그래서 유저·접속기록·미션·토큰을 심어 두고 연다.
 *
 * 보는 것:
 *  - 모든 탭이 200 이고, undefined / NaN / [object Object] 가 글자로 새지 않는다
 *  - 리텐션이 "아직 오지 않은 날짜"를 0% 로 채우지 않는다
 *  - DAU 가 어림값 구간과 정확한 구간을 구분해 말한다
 *  - 시간대 히트맵이 비트마스크에서 제대로 풀린다
 *  - 옛 주소(?tab=acquisition)가 유저 탭으로 이어진다
 */
const { Pool } = require('pg');
const { spawn } = require('child_process');
const http = require('http');

const ADMIN_URL = process.env.TEST_PG_ADMIN || 'postgresql://jiny@localhost:5432/postgres';
const DB = 'tichu_stats_tabs';
const PORT = 8095;
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

/// 스크립트와 스타일을 뺀 본문에서만 찾는다. 차트 데이터로 들어간 JSON 안의
/// NaN 은 별개 문제이고, 여기서 보려는 건 사람이 읽는 글자다.
const leaks = (body) => {
  const text = body.replace(/<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>/g, '');
  const m = text.match(/.{0,40}(undefined|\[object Object\]|NaN).{0,40}/);
  return m ? m[0].replace(/\s+/g, ' ') : null;
};

const TABS = ['users', 'games', 'missions', 'economy', 'shop', 'payment', 'attendance'];

async function seed(pool) {
  const day = (n) => `(DATE(timezone('Asia/Seoul', NOW())) - ${n})`;
  // 가입일을 벌려 심는다. 리텐션 코호트는 가입일 단위이고, 전부 오늘이면
  // "아직 오지 않은 날짜" 쪽만 타서 비율 계산을 못 본다.
  for (let i = 1; i <= 6; i++) {
    await pool.query(
      `INSERT INTO tc_users (username, nickname, gold, level, total_games,
                             device_platform, auth_provider, created_at, last_seen_at)
       VALUES ($1, $2, 1000, 5, 10, $3, $4,
               (NOW() AT TIME ZONE 'UTC') - ($5 || ' days')::interval,
               (NOW() AT TIME ZONE 'UTC'))
       ON CONFLICT (nickname) DO NOTHING`,
      [`st_u${i}`, `통계유저${i}`, i % 2 ? 'ios' : 'android',
        ['local', 'kakao', 'google', 'apple'][i % 4], String(i * 5)],
    );
  }
  // 접속 기록 — 시간대 비트를 서로 다르게 켜서 히트맵이 풀리는지 본다.
  for (let i = 1; i <= 6; i++) {
    for (let d = 0; d < 5; d++) {
      // 유저마다 다른 시간대. 1<<9 = 9시, 1<<21 = 21시.
      const mask = (1 << ((i * 3) % 24)) | (1 << 21);
      await pool.query(
        `INSERT INTO tc_daily_active (nickname, kst_day, sessions, hours_mask)
         VALUES ($1, ${day(d)}, $2, $3)
         ON CONFLICT (nickname, kst_day) DO NOTHING`,
        [`통계유저${i}`, d + 1, mask],
      );
    }
  }
  // 가입 다음 날 복귀 — D+1 이 0 이 아니어야 비율 칸이 실제로 계산된다.
  for (let i = 1; i <= 3; i++) {
    await pool.query(
      `INSERT INTO tc_daily_active (nickname, kst_day, sessions, hours_mask)
       SELECT $1::varchar, DATE(timezone('Asia/Seoul', u.created_at)) + 1, 1, (1 << 14)
         FROM tc_users u WHERE u.nickname = $1::varchar
       ON CONFLICT (nickname, kst_day) DO NOTHING`,
      [`통계유저${i}`],
    );
  }
  // 골드 기록 — 어림 집계(소급) 경로가 도는지 확인하는 용도.
  await pool.query(
    `INSERT INTO tc_gold_history (nickname, gold_delta, source, title, created_at)
     SELECT '통계유저1', 100, 'attendance', '출석',
            (NOW() AT TIME ZONE 'UTC') - (g || ' days')::interval
       FROM generate_series(1, 4) g`);
  // 미션 — 완료/만료/진행중을 섞어 완료율과 평균 소요가 계산되게.
  const keys = ['tichu_play', 'tichu_win', 'mighty_play'];
  for (let i = 1; i <= 6; i++) {
    for (const [k, key] of keys.entries()) {
      const status = i % 3 === 0 ? 'expired' : i % 3 === 1 ? 'done' : 'active';
      await pool.query(
        `INSERT INTO tc_user_missions
           (nickname, mission_key, picked_day, expires_day, progress, target,
            status, tokens_awarded, done_at)
         VALUES ($1, $2, ${day(k + 1)}, ${day(k)}, $3, 5, $4::varchar, $5,
                 CASE WHEN $4::varchar = 'done'
                      THEN (NOW() AT TIME ZONE 'UTC') - ($6 || ' hours')::interval
                      ELSE NULL END)`,
        [`통계유저${i}`, key, status === 'done' ? 5 : 2, status,
          status === 'done' ? 1 : 0, String(k * 6 + 2)],
      );
    }
  }
  // 토큰 — 발행과 사용 양쪽. 한쪽만 심으면 비율 칸이 안 돈다.
  for (let d = 0; d < 4; d++) {
    await pool.query(
      `INSERT INTO tc_token_ledger (nickname, delta, reason, ref, kst_day, created_at)
       VALUES ('통계유저1', 3, 'mission', 'tichu_play', ${day(d)}, NOW()),
              ('통계유저2', -2, 'shop', 'bubble', ${day(d)}, NOW())`);
  }
  await pool.query(
    `INSERT INTO tc_token_balance (nickname, balance, total_earned)
     VALUES ('통계유저1', 12, 30), ('통계유저2', 4, 20)
     ON CONFLICT (nickname) DO NOTHING`);
  await pool.query(
    `INSERT INTO tc_mission_streak (nickname, last_day, streak)
     VALUES ('통계유저1', DATE(timezone('Asia/Seoul', NOW())), 9),
            ('통계유저2', DATE(timezone('Asia/Seoul', NOW())), 2)
     ON CONFLICT (nickname) DO NOTHING`);
  await pool.query(
    `INSERT INTO tc_mission_rerolls (nickname, kst_day, game, used)
     VALUES ('통계유저1', DATE(timezone('Asia/Seoul', NOW())), 'tichu', 1)
     ON CONFLICT DO NOTHING`);
}

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
  for (let i = 0; i < 120 && !/listening|running|8095/i.test(log); i++) await sleep(200);
  await sleep(900);

  try {
    const bcrypt = require(require.resolve('bcrypt', { paths: [__dirname] }));
    await pool.query(
      `INSERT INTO admin_accounts (username, password) VALUES ('stats_admin', $1)
       ON CONFLICT (username) DO UPDATE SET password = EXCLUDED.password`,
      [await bcrypt.hash('adminpass1!', 4)],
    );
    const login = await req('POST', '/tc-backstage/login',
      { username: 'stats_admin', password: 'adminpass1!' });
    const cookie = (login.headers['set-cookie'] || [])[0]?.split(';')[0];
    check('로그인', login.status === 302 && !!cookie);

    console.log('\n[데이터가 없을 때 — 분모 0 과 빈 배열]');
    for (const tab of TABS) {
      const r = await req('GET', `/tc-backstage/stats?tab=${tab}&preset=last30`, null, cookie);
      const leak = leaks(r.body);
      check(`${tab} (빈 DB)`, r.status === 200 && !leak, `status=${r.status} ${leak || ''}`);
    }

    await seed(pool);

    console.log('\n[데이터가 있을 때]');
    for (const tab of TABS) {
      const r = await req('GET', `/tc-backstage/stats?tab=${tab}&preset=last30`, null, cookie);
      const leak = leaks(r.body);
      check(`${tab}`, r.status === 200 && !leak, `status=${r.status} ${leak || ''}`);
    }

    console.log('\n[시간대별 집계 단위로도 깨지지 않는다]');
    for (const tab of TABS) {
      const r = await req('GET', `/tc-backstage/stats?tab=${tab}&preset=today&bucket=hour`, null, cookie);
      const leak = leaks(r.body);
      check(`${tab} (시간대별)`, r.status === 200 && !leak, `status=${r.status} ${leak || ''}`);
    }

    console.log('\n[탭 구성]');
    const users = await req('GET', '/tc-backstage/stats?tab=users&preset=last30', null, cookie);
    check('기본 탭이 유저', (await req('GET', '/tc-backstage/stats', null, cookie))
      .body.includes('subtab-link active'));
    // 옛 주소를 지워버리면 북마크한 사람이 엉뚱한 탭을 본다.
    const aliased = await req('GET', '/tc-backstage/stats?tab=acquisition', null, cookie);
    check('옛 ?tab=acquisition 이 유저 탭으로', aliased.status === 200
      && aliased.body.includes('고착도'), '유저 탭 내용이 안 보임');
    check('미션 탭이 목록에 있다', users.body.includes('미션·토큰'));
    check('유입 분석 탭은 사라졌다', !users.body.includes('>유입 분석<'));

    console.log('\n[유저 탭이 실제로 말하는 것]');
    check('DAU·WAU·MAU 가 있다', users.body.includes('DAU') && users.body.includes('WAU') && users.body.includes('MAU'));
    check('고착도를 보여준다', users.body.includes('고착도'));
    check('리텐션 코호트 표', users.body.includes('D+1') && users.body.includes('D+30'));
    check('접속 빈도 분포', users.body.includes('1일만') && users.body.includes('15일 이상'));
    check('시간대 히트맵', users.body.includes('요일 × 시(KST)'));
    // 비트마스크가 풀렸는지. 심을 때 전원 21시 비트를 켰으므로 그 칸에
    // 숫자가 있어야 한다. 안 풀리면 표가 전부 빈 칸이다.
    check('히트맵에 21시 접속이 잡힌다', /21시 · [1-9]/.test(users.body), '비트마스크가 안 풀렸을 수 있음');
    check('자주 오는 유저 명단', users.body.includes('자주 오는 유저'));
    check('유입 경로(가입 수단)', users.body.includes('유입 경로'));
    check('어림값 구간을 밝힌다', users.body.includes('어림한 값'));
    // 아직 30일이 지나지 않은 코호트를 0% 로 채우면 전부 실패로 보인다.
    check('아직 오지 않은 날짜는 비워둔다', users.body.includes('아직'));

    console.log('\n[미션 탭이 실제로 말하는 것]');
    const mtab = await req('GET', '/tc-backstage/stats?tab=missions&preset=last30', null, cookie);
    check('미션별 난이도 표', mtab.body.includes('미션별 난이도'));
    check('완료율이 계산됐다', /완료율/.test(mtab.body) && /[1-9]\d?%/.test(mtab.body));
    check('토큰 경제', mtab.body.includes('토큰 경제') && mtab.body.includes('쌓여 있는 양'));
    check('발행÷사용 비율', mtab.body.includes('토큰 발행 ÷ 사용'));
    check('참여와 잠김', mtab.body.includes('참여와 잠김'));
    check('연속 달성 분포', mtab.body.includes('7일 이상'));
    check('새로고침 사용', mtab.body.includes('미션 새로고침'));
    // 켜져 있는데 한 번도 안 뽑힌 미션은 알아야 할 사실이다.
    check('발행 안 된 미션을 알려준다', mtab.body.includes('한 번도 발행되지 않은 미션'));
    check('심은 미션이 표에 보인다', mtab.body.includes('tichu_play'));
    // 이름표가 다른 미션 화면과 같아야 한다. 존재하지 않는 라벨 함수를
    // try/catch 로 감싸 두면 이 표만 조용히 raw 키를 보여준다.
    const L = require('./missions/labels.js');
    check('미션 이름이 한글 라벨로 나온다',
      mtab.body.includes(L.MISSION_LABEL_KO.tichu_play.split(' (')[0]),
      '라벨 대신 키만 보이는 중일 수 있음');
    // 차트 x축 날짜 라벨이 날짜순이어야 한다. String(Date) 를 정렬하면
    // 요일 약어순(Fri → Mon → Sat …)이 되어 추세가 거짓으로 보인다.
    const labelsJson = (mtab.body.match(/labels:\s*(\[[^\]]*\])/g) || [])
      .map((m) => m.replace(/^labels:\s*/, ''));
    let orderOk = true;
    for (const raw of labelsJson) {
      let arr; try { arr = JSON.parse(raw); } catch (_) { continue; }
      if (!arr.every((x) => typeof x === 'string' && /^\d{2}\/\d{2}$/.test(x))) continue;
      const sorted = [...arr].sort();
      if (arr.join() !== sorted.join()) orderOk = false;
    }
    check('차트 x축 날짜가 날짜순으로 정렬된다', orderOk,
      JSON.stringify(labelsJson).slice(0, 160));

    console.log('\n[정리 — 같은 말을 두 번 하지 않는다]');
    for (const tab of TABS) {
      const r = await req('GET', `/tc-backstage/stats?tab=${tab}&preset=last30`, null, cookie);
      check(`${tab} 에 "보조 지표" 카드가 없다`, !r.body.includes('보조 지표'));
    }
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
