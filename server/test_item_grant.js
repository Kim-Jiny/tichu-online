'use strict';
/**
 * 지급의 두 가지 규칙 — 기간을 넣으면 기간제로, 그리고 영구를 빼앗지 않기.
 *
 * 쿠폰·캠페인·우편이 모두 grantItemToUser 하나를 지난다. 여기서 틀리면
 * 세 곳이 같이 틀린다.
 *
 *  - 영구 아이템에 기간을 넣으면 체험판으로 나가야 한다. 예전에는 기간을
 *    무시하고 영구로 줬다 — 1일 체험이 평생 소유가 됐다.
 *  - 반대로, 이미 영구로 가진 사람에게 체험판을 주면 아무 일도 없어야
 *    한다. 만료일을 씌우면 갖고 있던 영구가 사라진다.
 *  - 만료된 아이템은 장착까지 벗겨져야 한다. 행만 지우면 좌석에는 계속
 *    그려진다 — 인벤토리에는 없는데 얼굴에는 붙어 있는 상태.
 *
 * Run: node server/test_item_grant.js
 */
const db = require('./db/database.js');

let failures = 0;
const check = (label, cond, detail = '') => {
  console.log(`${cond ? '  ok  ' : '  FAIL'} ${label}${!cond && detail ? ` — ${detail}` : ''}`);
  if (!cond) failures++;
};

const run = Date.now().toString(36).slice(-5);
const NICK = `지급${run}`;

const held = async (key) => (await db.pool.query(
  `SELECT expires_at FROM tc_user_items WHERE nickname = $1 AND item_key = $2`,
  [NICK, key])).rows;
const daysLeft = (row) => row.expires_at == null
  ? null
  : (new Date(row.expires_at).getTime() - Date.now()) / 86400000;
const grant = async (key, days) => {
  const client = await db.pool.connect();
  try {
    const item = (await client.query(
      'SELECT item_key, is_permanent, duration_days FROM tc_shop_items WHERE item_key = $1',
      [key])).rows[0];
    return await db.grantItemToUser(client, NICK, item, days, 'test');
  } finally { client.release(); }
};
const wipe = async (key) => db.pool.query(
  'DELETE FROM tc_user_items WHERE nickname = $1 AND item_key = $2', [NICK, key]);

(async () => {
  await db.initDatabase();
  await db.pool.query(
    `INSERT INTO tc_users (username, nickname, gold) VALUES ($1, $2, 0)
     ON CONFLICT (nickname) DO NOTHING`, [`grant_${run}`, NICK]);

  const perm = (await db.pool.query(
    `SELECT item_key FROM tc_shop_items WHERE is_permanent = TRUE AND category = 'theme' LIMIT 1`
  )).rows[0].item_key;
  const timed = (await db.pool.query(
    `SELECT item_key FROM tc_shop_items
      WHERE is_permanent = FALSE AND duration_days IS NOT NULL AND category = 'banner' LIMIT 1`
  )).rows[0].item_key;

  console.log('\n[영구 아이템에 기간을 넣으면]');
  await wipe(perm);
  const trial = await grant(perm, 3);
  const rows = await held(perm);
  check('지급된다', rows.length === 1, `${rows.length}행`);
  check('영구가 아니라 3일짜리로 들어간다',
    rows[0].expires_at != null && Math.abs(daysLeft(rows[0]) - 3) < 0.1,
    `${rows[0].expires_at}`);
  check('반환값도 만료일을 알려준다', trial.expiresAt != null, JSON.stringify(trial));

  console.log('\n[체험을 한 번 더 주면]');
  const again = await grant(perm, 2);
  const rows2 = await held(perm);
  check('행이 늘지 않는다', rows2.length === 1, `${rows2.length}행`);
  check('남은 기간에 더해진다', Math.abs(daysLeft(rows2[0]) - 5) < 0.1,
    `${daysLeft(rows2[0]).toFixed(2)}일`);
  check('연장으로 표시된다', again.extended === true, JSON.stringify(again));

  console.log('\n[기간 없이 주면 예전처럼 영구]');
  await wipe(perm);
  const forever = await grant(perm, null);
  check('만료일이 없다', (await held(perm))[0].expires_at === null);
  check('영구로 표시된다', forever.expiresAt === null, JSON.stringify(forever));

  console.log('\n[이미 영구로 가진 사람에게 체험판을 주면]');
  const noop = await grant(perm, 1);
  const after = await held(perm);
  check('영구가 유지된다 — 만료일이 생기지 않는다',
    after.length === 1 && after[0].expires_at === null,
    JSON.stringify(after.map((r) => r.expires_at)));
  check('이미 가진 것으로 답한다', noop.alreadyOwned === true, JSON.stringify(noop));

  console.log('\n[기간제 아이템은 원래대로]');
  await wipe(timed);
  await grant(timed, 7);
  check('7일로 들어간다', Math.abs(daysLeft((await held(timed))[0]) - 7) < 0.1);
  await db.pool.query(
    `UPDATE tc_user_items SET expires_at = (NOW() AT TIME ZONE 'UTC') - INTERVAL '30 days'
      WHERE nickname = $1 AND item_key = $2`, [NICK, timed]);
  await grant(timed, 7);
  check('만료된 것에 주면 지금부터 7일 (과거에 더하지 않는다)',
    Math.abs(daysLeft((await held(timed))[0]) - 7) < 0.1,
    `${daysLeft((await held(timed))[0]).toFixed(2)}일`);

  console.log('\n[만료되면 장착도 벗겨진다]');
  await wipe(timed);
  await db.pool.query(
    `INSERT INTO tc_user_items (nickname, item_key, expires_at, source)
     VALUES ($1, $2, (NOW() AT TIME ZONE 'UTC') - INTERVAL '1 day', 'test')`, [NICK, timed]);
  await db.pool.query(
    `INSERT INTO tc_user_equips (nickname, banner_key, title_key)
     VALUES ($1, $2, 'custom:FF0000')
     ON CONFLICT (nickname) DO UPDATE SET banner_key = EXCLUDED.banner_key,
                                          title_key = EXCLUDED.title_key`,
    [NICK, timed]);
  const before = await db.getUserProfile(NICK, 'ko');
  check('정리 전에는 그대로 보인다', before.bannerKey === timed, `${before.bannerKey}`);
  await db.getUserItems(NICK); // 인벤토리를 여는 것이 정리 시점
  const equips = (await db.pool.query(
    'SELECT banner_key, title_key FROM tc_user_equips WHERE nickname = $1', [NICK])).rows[0];
  check('장착이 풀린다', equips.banner_key === null, `${equips.banner_key}`);
  check('커스텀 칭호는 건드리지 않는다 (인벤토리에 행이 없는 정상 상태)',
    equips.title_key === 'custom:FF0000', `${equips.title_key}`);
  const afterProfile = await db.getUserProfile(NICK, 'ko');
  check('프로필에도 더 이상 안 나온다', !afterProfile.bannerKey, `${afterProfile.bannerKey}`);

  console.log('\n[한 번도 접속 안 한 사람도 정리된다]');
  await db.pool.query(
    `INSERT INTO tc_user_items (nickname, item_key, expires_at, source)
     VALUES ($1, $2, (NOW() AT TIME ZONE 'UTC') - INTERVAL '1 day', 'test')`, [NICK, timed]);
  await db.pool.query(
    `UPDATE tc_user_equips SET banner_key = $2 WHERE nickname = $1`, [NICK, timed]);
  const swept = await db.sweepExpiredCosmetics();
  check('일괄 정리가 돈다', swept.success === true, JSON.stringify(swept));
  check('장착이 풀려 있다',
    (await db.pool.query('SELECT banner_key FROM tc_user_equips WHERE nickname = $1',
      [NICK])).rows[0].banner_key === null);

  await db.pool.query('DELETE FROM tc_user_equips WHERE nickname = $1', [NICK]);
  await db.pool.query('DELETE FROM tc_user_items WHERE nickname = $1', [NICK]);
  await db.pool.query('DELETE FROM tc_users WHERE nickname = $1', [NICK]);
})()
  .then(() => {
    console.log(failures === 0 ? '\nPASS' : `\n${failures} FAILURE(S)`);
    process.exit(failures === 0 ? 0 : 1);
  })
  .catch((e) => { console.error('\nERROR', e.stack); process.exit(1); });
