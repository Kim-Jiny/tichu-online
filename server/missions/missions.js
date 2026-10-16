'use strict';

/**
 * 미션 · 토큰 · 토큰 상점.
 *
 * pool 은 init() 으로 받는다(database.js 가 server.js 보다 먼저 만들어지고, 이
 * 모듈은 둘 어느 쪽도 거꾸로 require 하지 않는다).
 *
 * 날짜 계산은 전부 Postgres 의 KST 로 한다 — 출석과 같은 이유로, node-pg 의
 * DATE 파서가 비 UTC 호스트에서 하루씩 밀리기 때문이다.
 */

const defs = require('./defs');

let pool = null;

function init(p) {
  pool = p;
}

/** 마이그레이션에서 부른다. */
async function ensureSchema(client) {
  await client.query(`
    CREATE TABLE IF NOT EXISTS tc_token_balance (
      nickname VARCHAR(50) PRIMARY KEY,
      balance INT NOT NULL DEFAULT 0,
      total_earned INT NOT NULL DEFAULT 0,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  `);
  await client.query(`
    CREATE TABLE IF NOT EXISTS tc_token_ledger (
      id SERIAL PRIMARY KEY,
      nickname VARCHAR(50) NOT NULL,
      delta INT NOT NULL,
      reason VARCHAR(30) NOT NULL,
      ref VARCHAR(80),
      kst_day DATE NOT NULL DEFAULT DATE(timezone('Asia/Seoul', NOW())),
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  `);
  await client.query(`CREATE INDEX IF NOT EXISTS idx_tc_token_ledger_nick_day ON tc_token_ledger (nickname, kst_day)`);

  await client.query(`
    CREATE TABLE IF NOT EXISTS tc_user_missions (
      id SERIAL PRIMARY KEY,
      nickname VARCHAR(50) NOT NULL,
      mission_key VARCHAR(40) NOT NULL,
      picked_day DATE NOT NULL,
      expires_day DATE NOT NULL,
      progress INT NOT NULL DEFAULT 0,
      target INT NOT NULL,
      status VARCHAR(10) NOT NULL DEFAULT 'active',
      tokens_awarded INT NOT NULL DEFAULT 0,
      done_at TIMESTAMP
    )
  `);
  await client.query(`CREATE INDEX IF NOT EXISTS idx_tc_user_missions_nick ON tc_user_missions (nickname, status)`);

  // 하루에 게임별로 새로고침을 몇 번 썼는지.
  await client.query(`
    CREATE TABLE IF NOT EXISTS tc_mission_rerolls (
      nickname VARCHAR(50) NOT NULL,
      kst_day DATE NOT NULL,
      game VARCHAR(20) NOT NULL,
      used INT NOT NULL DEFAULT 0,
      PRIMARY KEY (nickname, kst_day, game)
    )
  `);

  // 연속 달성: 하루 1개 이상 깬 날이 이어진 일수(7일 주기).
  await client.query(`
    CREATE TABLE IF NOT EXISTS tc_mission_streak (
      nickname VARCHAR(50) PRIMARY KEY,
      last_day DATE,
      streak INT NOT NULL DEFAULT 0
    )
  `);

  // 토큰 상점 보유(기간제). 같은 상품을 또 사면 만료일이 늘어난다.
  await client.query(`
    CREATE TABLE IF NOT EXISTS tc_token_owned (
      nickname VARCHAR(50) NOT NULL,
      product_key VARCHAR(40) NOT NULL,
      expires_at TIMESTAMP NOT NULL,
      acquired_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (nickname, product_key)
    )
  `);
  // 장착: slot 마다 하나. 만료되면 조회할 때 걸러진다.
  await client.query(`
    CREATE TABLE IF NOT EXISTS tc_token_equips (
      nickname VARCHAR(50) NOT NULL,
      slot VARCHAR(20) NOT NULL,
      product_key VARCHAR(40) NOT NULL,
      PRIMARY KEY (nickname, slot)
    )
  `);
}

const NICKNAME_TABLES = [
  'tc_token_balance',
  'tc_token_ledger',
  'tc_user_missions',
  'tc_mission_rerolls',
  'tc_mission_streak',
  'tc_token_owned',
  'tc_token_equips',
];

/** 닉네임이 키라서, 이름을 바꾸면 같이 옮기고 계정을 지우면 같이 지운다. */
async function renameUser(client, oldNickname, newNickname) {
  for (const t of NICKNAME_TABLES) {
    await client.query(`UPDATE ${t} SET nickname = $2 WHERE nickname = $1`, [oldNickname, newNickname]);
  }
}

async function deleteUser(client, nickname) {
  for (const t of NICKNAME_TABLES) {
    await client.query(`DELETE FROM ${t} WHERE nickname = $1`, [nickname]);
  }
}

// ───────────────────────────── 날짜 / 시드 ─────────────────────────────

async function kstToday(db = pool) {
  const r = await db.query(
    `SELECT to_char(DATE(timezone('Asia/Seoul', NOW())), 'YYYY-MM-DD') AS d,
            ((DATE(timezone('Asia/Seoul', NOW())) + 1)::timestamp AT TIME ZONE 'Asia/Seoul') AS reset_at`
  );
  return { day: r.rows[0].d, resetAtUtc: new Date(r.rows[0].reset_at).toISOString() };
}

/** 문자열 → 32비트 해시(오퍼 후보를 유저·날짜마다 고정하려는 용도). */
function hash32(str) {
  let h = 2166136261;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}

function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/**
 * 오늘 이 게임에서 보여 줄 후보. 유저·날짜·새로고침 횟수로 고정되어 앱을 껐다
 * 켜도 같은 후보가 나온다. 쉬움·보통·어려움이 하나씩 섞이게 뽑는다.
 */
function offersFor(nickname, day, game, rerollsUsed) {
  const pool = defs.MISSIONS.filter((m) => m.game === game);
  const rnd = mulberry32(hash32(`${nickname}|${day}|${game}|${rerollsUsed}`));
  const byTier = { 1: [], 2: [], 3: [] };
  for (const m of pool) (byTier[m.tier] || (byTier[m.tier] = [])).push(m);
  const picks = [];
  const take = (list) => {
    const rest = list.filter((m) => !picks.includes(m));
    if (!rest.length) return;
    picks.push(rest[Math.floor(rnd() * rest.length)]);
  };
  take(byTier[1]);
  take(byTier[2]);
  take(byTier[3]);
  // 어느 단계가 비어 있으면(러브레터처럼 어려움이 없는 게임) 남은 것으로 채운다.
  const filler = pool.filter((m) => !picks.includes(m));
  while (picks.length < Math.min(defs.OFFERS_PER_GAME, pool.length) && filler.length) {
    picks.push(filler.splice(Math.floor(rnd() * filler.length), 1)[0]);
  }
  return picks.map((m) => m.key);
}

// ───────────────────────────── 상태 조회 ─────────────────────────────

async function getBalance(nickname, db = pool) {
  const r = await db.query('SELECT balance FROM tc_token_balance WHERE nickname = $1', [nickname]);
  return r.rows[0] ? r.rows[0].balance : 0;
}

async function todayEarned(nickname, db = pool) {
  const r = await db.query(
    `SELECT COALESCE(SUM(delta), 0) AS s FROM tc_token_ledger
      WHERE nickname = $1 AND reason = 'mission'
        AND kst_day = DATE(timezone('Asia/Seoul', NOW()))`,
    [nickname]
  );
  return parseInt(r.rows[0].s, 10) || 0;
}

async function expireOld(nickname, db = pool) {
  await db.query(
    `UPDATE tc_user_missions SET status = 'expired'
      WHERE nickname = $1 AND status = 'active'
        AND expires_day < DATE(timezone('Asia/Seoul', NOW()))`,
    [nickname]
  );
}

function missionRow(row) {
  const def = defs.MISSION_BY_KEY.get(row.mission_key);
  return {
    id: row.id,
    key: row.mission_key,
    game: def ? def.game : null,
    tier: def ? def.tier : 1,
    tokens: def ? def.tokens : 0,
    progress: row.progress,
    target: row.target,
    status: row.status,
    expiresDay: typeof row.expires_day === 'string' ? row.expires_day : row.expires_day_text,
  };
}

async function getState(nickname) {
  await expireOld(nickname);
  const { day, resetAtUtc } = await kstToday();
  const [balance, earned, activeRes, rerollRes, streakRes] = await Promise.all([
    getBalance(nickname),
    todayEarned(nickname),
    pool.query(
      `SELECT id, mission_key, progress, target, status,
              to_char(expires_day, 'YYYY-MM-DD') AS expires_day_text
         FROM tc_user_missions
        WHERE nickname = $1
          AND (status = 'active'
               OR (status = 'done'
                   AND DATE(timezone('Asia/Seoul', done_at::timestamptz))
                       = DATE(timezone('Asia/Seoul', NOW()))))
        ORDER BY id`,
      [nickname]
    ),
    pool.query(
      `SELECT game, used FROM tc_mission_rerolls
        WHERE nickname = $1 AND kst_day = $2::date`,
      [nickname, day]
    ),
    pool.query(
      `SELECT streak, to_char(last_day, 'YYYY-MM-DD') AS last_day,
              (last_day = $2::date)::bool AS done_today,
              (last_day = $2::date - 1)::bool AS continues
         FROM tc_mission_streak WHERE nickname = $1`,
      [nickname, day]
    ),
  ]);

  const rerolls = {};
  for (const r of rerollRes.rows) rerolls[r.game] = r.used;
  const active = activeRes.rows.map(missionRow);
  const activeKeys = new Set(active.filter((m) => m.status === 'active').map((m) => m.key));

  const offers = {};
  for (const game of defs.GAMES) {
    const used = rerolls[game] || 0;
    offers[game] = {
      rerollsLeft: Math.max(0, defs.DAILY_REROLLS - used),
      missions: offersFor(nickname, day, game, used).map((key) => {
        const d = defs.MISSION_BY_KEY.get(key);
        return {
          key,
          game,
          tier: d.tier,
          tokens: d.tokens,
          target: d.target,
          picked: activeKeys.has(key),
        };
      }),
    };
  }

  const s = streakRes.rows[0];
  let streak = 0;
  let doneToday = false;
  if (s) {
    doneToday = s.done_today === true;
    streak = doneToday || s.continues === true ? s.streak : 0;
  }
  return {
    balance,
    todayEarned: earned,
    dailyCap: defs.DAILY_TOKEN_CAP,
    maxActive: defs.MAX_ACTIVE,
    lifetimeDays: defs.MISSION_LIFETIME_DAYS,
    minHumans: defs.MIN_HUMANS,
    resetAtUtc,
    streak,
    streakDoneToday: doneToday,
    streakTarget: defs.STREAK_BONUS_DAYS,
    streakBonus: defs.STREAK_BONUS_TOKENS,
    active,
    offers,
  };
}

// ───────────────────────────── 선택 / 새로고침 ─────────────────────────────

async function pick(nickname, missionKey) {
  const def = defs.MISSION_BY_KEY.get(missionKey);
  if (!def) return { success: false, reason: 'unknown_mission' };
  await expireOld(nickname);
  const { day } = await kstToday();
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    // 같은 유저의 동시 선택이 한도를 넘기지 않도록 유저 단위로 잠근다.
    await client.query('SELECT pg_advisory_xact_lock($1)', [hash32(`mission|${nickname}`)]);
    const rer = await client.query(
      `SELECT used FROM tc_mission_rerolls WHERE nickname = $1 AND kst_day = $2::date AND game = $3`,
      [nickname, day, def.game]
    );
    const used = rer.rows[0] ? rer.rows[0].used : 0;
    if (!offersFor(nickname, day, def.game, used).includes(missionKey)) {
      await client.query('ROLLBACK');
      return { success: false, reason: 'not_offered' };
    }
    const act = await client.query(
      `SELECT mission_key FROM tc_user_missions WHERE nickname = $1 AND status = 'active'`,
      [nickname]
    );
    if (act.rows.some((r) => r.mission_key === missionKey)) {
      await client.query('ROLLBACK');
      return { success: false, reason: 'already_picked' };
    }
    if (act.rows.length >= defs.MAX_ACTIVE) {
      await client.query('ROLLBACK');
      return { success: false, reason: 'too_many' };
    }
    await client.query(
      `INSERT INTO tc_user_missions (nickname, mission_key, picked_day, expires_day, target)
       VALUES ($1, $2, $3::date, $3::date + $4::int, $5)`,
      [nickname, missionKey, day, defs.MISSION_LIFETIME_DAYS - 1, def.target]
    );
    await client.query('COMMIT');
    return { success: true };
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('mission pick error:', err.message);
    return { success: false, reason: 'error' };
  } finally {
    client.release();
  }
}

async function drop(nickname, missionKey) {
  const r = await pool.query(
    `UPDATE tc_user_missions SET status = 'dropped'
      WHERE nickname = $1 AND mission_key = $2 AND status = 'active'`,
    [nickname, missionKey]
  );
  return { success: r.rowCount > 0 };
}

async function reroll(nickname, game) {
  if (!defs.GAMES.includes(game)) return { success: false, reason: 'unknown_game' };
  const { day } = await kstToday();
  const r = await pool.query(
    `INSERT INTO tc_mission_rerolls (nickname, kst_day, game, used)
     VALUES ($1, $2::date, $3, 1)
     ON CONFLICT (nickname, kst_day, game)
     DO UPDATE SET used = tc_mission_rerolls.used + 1
       WHERE tc_mission_rerolls.used < $4
     RETURNING used`,
    [nickname, day, game, defs.DAILY_REROLLS]
  );
  if (!r.rows.length) return { success: false, reason: 'no_rerolls' };
  return { success: true };
}

// ───────────────────────────── 진행 / 지급 ─────────────────────────────

/**
 * 이벤트가 일어났음을 기록한다. 활성 미션 중 이 이벤트를 세는 것에 amount 를
 * 더하고, 목표에 닿으면 바로 토큰을 준다. 완료된 미션 목록을 돌려준다(알림용).
 */
async function record(nickname, event, amount = 1) {
  if (!nickname || !(amount > 0)) return [];
  const eventKeys = defs.MISSIONS.filter((m) => m.event === event).map((m) => m.key);
  if (!eventKeys.length) return [];
  const client = await pool.connect();
  const completed = [];
  try {
    await client.query('BEGIN');
    await client.query('SELECT pg_advisory_xact_lock($1)', [hash32(`mission|${nickname}`)]);
    const rows = await client.query(
      `SELECT id, mission_key, progress, target FROM tc_user_missions
        WHERE nickname = $1 AND status = 'active' AND mission_key = ANY($2)
          AND expires_day >= DATE(timezone('Asia/Seoul', NOW()))
        FOR UPDATE`,
      [nickname, eventKeys]
    );
    for (const row of rows.rows) {
      const next = Math.min(row.target, row.progress + amount);
      if (next < row.target) {
        await client.query('UPDATE tc_user_missions SET progress = $2 WHERE id = $1', [row.id, next]);
        continue;
      }
      const def = defs.MISSION_BY_KEY.get(row.mission_key);
      const granted = await grantMissionTokens(client, nickname, def.tokens, row.mission_key);
      await client.query(
        `UPDATE tc_user_missions
            SET progress = $2, status = 'done', tokens_awarded = $3, done_at = NOW()
          WHERE id = $1`,
        [row.id, next, granted]
      );
      const bonus = await bumpStreak(client, nickname);
      completed.push({ key: row.mission_key, tokens: granted, streakBonus: bonus });
    }
    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('mission record error:', err.message);
    return [];
  } finally {
    client.release();
  }
  return completed;
}

async function addTokens(client, nickname, delta, reason, ref) {
  await client.query(
    `INSERT INTO tc_token_balance (nickname, balance, total_earned)
     VALUES ($1, $2, GREATEST($2, 0))
     ON CONFLICT (nickname) DO UPDATE
       SET balance = tc_token_balance.balance + $2,
           total_earned = tc_token_balance.total_earned + GREATEST($2, 0),
           updated_at = NOW()`,
    [nickname, delta]
  );
  await client.query(
    `INSERT INTO tc_token_ledger (nickname, delta, reason, ref) VALUES ($1, $2, $3, $4)`,
    [nickname, delta, reason, ref || null]
  );
}

/** 하루 상한을 넘으면 남은 만큼만 준다. 받은 양을 돌려준다. */
async function grantMissionTokens(client, nickname, tokens, ref) {
  const earned = await todayEarned(nickname, client);
  const room = Math.max(0, defs.DAILY_TOKEN_CAP - earned);
  const granted = Math.min(tokens, room);
  if (granted > 0) await addTokens(client, nickname, granted, 'mission', ref);
  return granted;
}

/** 오늘 처음 깬 미션이면 연속 일수를 올리고, 7일째면 보너스를 준다. */
async function bumpStreak(client, nickname) {
  const r = await client.query(
    `SELECT streak,
            (last_day = DATE(timezone('Asia/Seoul', NOW())))::bool AS done_today,
            (last_day = DATE(timezone('Asia/Seoul', NOW())) - 1)::bool AS continues
       FROM tc_mission_streak WHERE nickname = $1 FOR UPDATE`,
    [nickname]
  );
  const row = r.rows[0];
  if (row && row.done_today) return 0;
  let streak = row && row.continues ? row.streak + 1 : 1;
  let bonus = 0;
  if (streak >= defs.STREAK_BONUS_DAYS) {
    // 보너스는 하루 상한과 별개다(연속 달성에 대한 보상이므로 reason 도 따로).
    await addTokens(client, nickname, defs.STREAK_BONUS_TOKENS, 'streak', null);
    bonus = defs.STREAK_BONUS_TOKENS;
    streak = 0;
  }
  await client.query(
    `INSERT INTO tc_mission_streak (nickname, last_day, streak)
     VALUES ($1, DATE(timezone('Asia/Seoul', NOW())), $2)
     ON CONFLICT (nickname) DO UPDATE
       SET last_day = DATE(timezone('Asia/Seoul', NOW())), streak = $2`,
    [nickname, streak]
  );
  return bonus;
}

// ───────────────────────────── 토큰 상점 ─────────────────────────────

async function getOwned(nickname, db = pool) {
  const r = await db.query(
    `SELECT product_key, expires_at FROM tc_token_owned
      WHERE nickname = $1 AND expires_at > NOW()`,
    [nickname]
  );
  return new Map(r.rows.map((x) => [x.product_key, new Date(x.expires_at)]));
}

async function getShop(nickname) {
  const [balance, owned, eq] = await Promise.all([
    getBalance(nickname),
    getOwned(nickname),
    pool.query('SELECT slot, product_key FROM tc_token_equips WHERE nickname = $1', [nickname]),
  ]);
  const equipped = {};
  for (const r of eq.rows) {
    if (owned.has(r.product_key)) equipped[r.slot] = r.product_key;
  }
  return {
    balance,
    products: defs.PRODUCTS.map((p) => ({
      key: p.key,
      kind: p.kind,
      variant: p.variant,
      price: p.price,
      days: p.days,
      ownedUntil: owned.has(p.key) ? owned.get(p.key).toISOString() : null,
      equipped: equipped[p.slot] === p.key,
    })),
  };
}

async function buy(nickname, productKey) {
  const p = defs.PRODUCT_BY_KEY.get(productKey);
  if (!p) return { success: false, reason: 'unknown_product' };
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query('SELECT pg_advisory_xact_lock($1)', [hash32(`mission|${nickname}`)]);
    const bal = await client.query(
      'SELECT balance FROM tc_token_balance WHERE nickname = $1 FOR UPDATE',
      [nickname]
    );
    const balance = bal.rows[0] ? bal.rows[0].balance : 0;
    if (balance < p.price) {
      await client.query('ROLLBACK');
      return { success: false, reason: 'not_enough', balance, price: p.price };
    }
    await addTokens(client, nickname, -p.price, 'shop', p.key);
    // 이미 보유 중이면 남은 기간 뒤에 30일을 더한다.
    await client.query(
      `INSERT INTO tc_token_owned (nickname, product_key, expires_at)
       VALUES ($1, $2, NOW() + make_interval(days => $3))
       ON CONFLICT (nickname, product_key) DO UPDATE
         SET expires_at = GREATEST(tc_token_owned.expires_at, NOW()) + make_interval(days => $3)`,
      [nickname, p.key, p.days]
    );
    // 그 칸에 장착된 게 없으면(또는 만료됐으면) 바로 장착해 둔다.
    await client.query(
      `INSERT INTO tc_token_equips (nickname, slot, product_key) VALUES ($1, $2, $3)
       ON CONFLICT (nickname, slot) DO UPDATE SET product_key = EXCLUDED.product_key
         WHERE NOT EXISTS (
           SELECT 1 FROM tc_token_owned o
            WHERE o.nickname = tc_token_equips.nickname
              AND o.product_key = tc_token_equips.product_key
              AND o.expires_at > NOW())`,
      [nickname, p.slot, p.key]
    );
    await client.query('COMMIT');
    return { success: true };
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('token buy error:', err.message);
    return { success: false, reason: 'error' };
  } finally {
    client.release();
  }
}

/** productKey 가 null 이면 그 칸(slot)의 장착을 푼다. */
async function equip(nickname, slot, productKey) {
  if (slot !== 'room_highlight' && slot !== 'bubble') return { success: false, reason: 'unknown_slot' };
  if (productKey == null) {
    await pool.query('DELETE FROM tc_token_equips WHERE nickname = $1 AND slot = $2', [nickname, slot]);
    return { success: true };
  }
  const p = defs.PRODUCT_BY_KEY.get(productKey);
  if (!p || p.slot !== slot) return { success: false, reason: 'unknown_product' };
  const owned = await getOwned(nickname);
  if (!owned.has(productKey)) return { success: false, reason: 'not_owned' };
  await pool.query(
    `INSERT INTO tc_token_equips (nickname, slot, product_key) VALUES ($1, $2, $3)
     ON CONFLICT (nickname, slot) DO UPDATE SET product_key = EXCLUDED.product_key`,
    [nickname, slot, productKey]
  );
  return { success: true };
}

/**
 * 다른 사람에게 보여 줄 장착 상태 — { roomHighlight: 'room_highlight_2', bubble: 'bubble_basic_1' }.
 * 만료된 건 빠진다. 로그인·장착·구매 때 소켓에 캐시해 두고 쓴다.
 */
async function getEquippedKeys(nickname) {
  const r = await pool.query(
    `SELECT e.slot, e.product_key
       FROM tc_token_equips e
       JOIN tc_token_owned o ON o.nickname = e.nickname AND o.product_key = e.product_key
      WHERE e.nickname = $1 AND o.expires_at > NOW()`,
    [nickname]
  );
  const out = { roomHighlight: null, bubble: null };
  for (const row of r.rows) {
    if (row.slot === 'room_highlight') out.roomHighlight = row.product_key;
    else if (row.slot === 'bubble') out.bubble = row.product_key;
  }
  return out;
}

module.exports = {
  init,
  ensureSchema,
  renameUser,
  deleteUser,
  getState,
  pick,
  drop,
  reroll,
  record,
  getShop,
  buy,
  equip,
  getEquippedKeys,
  getBalance,
  offersFor,
  defs,
};
