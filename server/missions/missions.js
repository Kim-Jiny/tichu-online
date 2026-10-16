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

// ───────────────────────────── 관리자 조정(켜기/끄기·보상·가격) ─────────────────────────────

const OVERRIDE_TTL_MS = 30000;
const overrides = { missions: new Map(), products: new Map(), loadedAt: 0 };

/** 조정값을 짧게 캐시해 둔다. 관리자가 바꾸면 곧바로 다시 읽는다. */
async function loadOverrides(force = false, db = pool) {
  if (!force && Date.now() - overrides.loadedAt < OVERRIDE_TTL_MS) return;
  const [m, p] = await Promise.all([
    db.query('SELECT mission_key, enabled, tokens FROM tc_mission_overrides'),
    db.query('SELECT product_key, enabled, price FROM tc_token_product_overrides'),
  ]);
  overrides.missions = new Map(m.rows.map((r) => [r.mission_key, r]));
  overrides.products = new Map(p.rows.map((r) => [r.product_key, r]));
  overrides.loadedAt = Date.now();
}

/** 기본 정의 위에 관리자 조정을 얹은 값. */
function effectiveMission(key) {
  const def = defs.MISSION_BY_KEY.get(key);
  if (!def) return null;
  const o = overrides.missions.get(key);
  return {
    ...def,
    enabled: o ? o.enabled !== false : true,
    tokens: o && o.tokens != null ? o.tokens : def.tokens,
    defaultTokens: def.tokens,
  };
}

function effectiveProduct(key) {
  const def = defs.PRODUCT_BY_KEY.get(key);
  if (!def) return null;
  const o = overrides.products.get(key);
  return {
    ...def,
    enabled: o ? o.enabled !== false : true,
    price: o && o.price != null ? o.price : def.price,
    defaultPrice: def.price,
  };
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

  // 관리자가 켜고 끄거나 보상·가격을 바꾼 것. 행이 없으면 defs.js 의 기본값 그대로다.
  await client.query(`
    CREATE TABLE IF NOT EXISTS tc_mission_overrides (
      mission_key VARCHAR(40) PRIMARY KEY,
      enabled BOOLEAN NOT NULL DEFAULT TRUE,
      tokens INT,
      updated_by VARCHAR(50),
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  `);
  await client.query(`
    CREATE TABLE IF NOT EXISTS tc_token_product_overrides (
      product_key VARCHAR(40) PRIMARY KEY,
      enabled BOOLEAN NOT NULL DEFAULT TRUE,
      price INT,
      updated_by VARCHAR(50),
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
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
  const pool = defs.MISSIONS.filter((m) => m.game === game && effectiveMission(m.key).enabled);
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

/**
 * 내 토큰 내역(최신순). before 는 이전 페이지 마지막 id — 그보다 오래된 것만 준다.
 * 한 장 더 읽어 다음 장이 있는지(hasMore)를 알려 준다.
 */
async function getHistory(nickname, { before = null, limit = 30 } = {}) {
  const lim = Math.max(1, Math.min(parseInt(limit, 10) || 30, 100));
  const params = [nickname, lim + 1];
  let cond = '';
  if (before != null && Number.isFinite(Number(before))) {
    params.push(Number(before));
    cond = 'AND id < $3';
  }
  const r = await pool.query(
    // 시각은 DB 가 UTC 문자열로 만들어 준다 — node-pg 가 timestamp 를 서버 지역 시간으로
    // 해석해 호스트 시간대에 따라 어긋나는 걸 피한다.
    `SELECT id, delta, reason, ref,
            to_char(created_at, 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS created_utc
       FROM tc_token_ledger
      WHERE nickname = $1 ${cond}
      ORDER BY id DESC LIMIT $2`,
    params
  );
  const rows = r.rows.slice(0, lim).map((x) => ({
    id: x.id,
    delta: x.delta,
    reason: x.reason,
    // 관리자 지급·회수의 ref 는 '운영자 계정: 메모' 라서 유저에게 그대로 보이지 않게 뺀다.
    ref: x.reason === 'mission' || x.reason === 'shop' ? x.ref : null,
    createdAt: x.created_utc,
  }));
  return { rows, hasMore: r.rows.length > lim };
}

/** 여러 유저의 토큰 잔액(관리자 목록용) — { nickname → balance } 맵. */
async function getBalances(nicknames) {
  const out = new Map();
  if (!nicknames || !nicknames.length) return out;
  const r = await pool.query(
    'SELECT nickname, balance FROM tc_token_balance WHERE nickname = ANY($1)',
    [nicknames]
  );
  for (const row of r.rows) out.set(row.nickname, row.balance);
  return out;
}

/** 오늘(KST) 이미 고른 미션 수. 포기한 것도 센다. */
async function picksToday(nickname, db = pool) {
  const r = await db.query(
    `SELECT COUNT(*)::int AS n FROM tc_user_missions
      WHERE nickname = $1 AND picked_day = DATE(timezone('Asia/Seoul', NOW()))`,
    [nickname]
  );
  return r.rows[0].n;
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
  const def = effectiveMission(row.mission_key);
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
  await loadOverrides();
  await expireOld(nickname);
  const { day, resetAtUtc } = await kstToday();
  const [balance, picked, activeRes, rerollRes, streakRes] = await Promise.all([
    getBalance(nickname),
    picksToday(nickname),
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
        const d = effectiveMission(key);
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
    picksToday: picked,
    dailyPicks: defs.DAILY_PICKS,
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
  await loadOverrides();
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
    if ((await picksToday(nickname, client)) >= defs.DAILY_PICKS) {
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
  await loadOverrides();
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
      const def = effectiveMission(row.mission_key);
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

async function grantMissionTokens(client, nickname, tokens, ref) {
  if (tokens > 0) await addTokens(client, nickname, tokens, 'mission', ref);
  return tokens;
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
    // 연속 달성에 대한 보상이라 reason 을 따로 남긴다.
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
  await loadOverrides();
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
    // 판매를 끈 상품은 목록에서 빠진다(이미 가진 건 계속 보인다).
    products: defs.PRODUCTS.map((p) => effectiveProduct(p.key))
      .filter((p) => p.enabled || owned.has(p.key))
      .map((p) => ({
        key: p.key,
        kind: p.kind,
        variant: p.variant,
        price: p.price,
        days: p.days,
        ownedUntil: owned.has(p.key) ? owned.get(p.key).toISOString() : null,
        equipped: equipped[p.slot] === p.key,
        canBuy: p.enabled,
      })),
  };
}

async function buy(nickname, productKey) {
  if (!defs.PRODUCT_BY_KEY.has(productKey)) return { success: false, reason: 'unknown_product' };
  await loadOverrides();
  const p = effectiveProduct(productKey);
  if (!p.enabled) return { success: false, reason: 'not_for_sale' };
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

// ───────────────────────────── 관리자 ─────────────────────────────

async function nicknameExists(nickname) {
  const r = await pool.query(
    'SELECT 1 FROM tc_users WHERE nickname = $1 AND is_deleted IS NOT TRUE LIMIT 1',
    [nickname]
  );
  return r.rowCount > 0;
}

/**
 * 토큰을 지급(+)하거나 회수(-)한다. 운영자가 직접 하는 일이라 다른 제한은 없다.
 * 회수는 잔액 아래로 내려가지 않는다. 장부에는 누가 왜 했는지 남긴다.
 */
async function adminGrant(nickname, delta, memo, adminName) {
  const amount = Math.trunc(Number(delta));
  if (!Number.isFinite(amount) || amount === 0) return { success: false, reason: 'bad_amount' };
  if (Math.abs(amount) > 100000) return { success: false, reason: 'too_large' };
  if (!(await nicknameExists(nickname))) return { success: false, reason: 'no_user' };
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query('SELECT pg_advisory_xact_lock($1)', [hash32(`mission|${nickname}`)]);
    const bal = await client.query(
      'SELECT balance FROM tc_token_balance WHERE nickname = $1 FOR UPDATE',
      [nickname]
    );
    const balance = bal.rows[0] ? bal.rows[0].balance : 0;
    if (amount < 0 && balance + amount < 0) {
      await client.query('ROLLBACK');
      return { success: false, reason: 'insufficient', balance };
    }
    const ref = `${adminName || 'admin'}${memo ? `: ${String(memo).slice(0, 50)}` : ''}`.slice(0, 80);
    await addTokens(client, nickname, amount, amount > 0 ? 'admin_grant' : 'admin_revoke', ref);
    await client.query('COMMIT');
    return { success: true, balance: balance + amount };
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('admin token grant error:', err.message);
    return { success: false, reason: 'error' };
  } finally {
    client.release();
  }
}

async function adminSetMission(key, { enabled, tokens }, adminName) {
  const def = defs.MISSION_BY_KEY.get(key);
  if (!def) return { success: false, reason: 'unknown_mission' };
  const t = tokens === '' || tokens == null ? null : Math.trunc(Number(tokens));
  if (t != null && (!Number.isFinite(t) || t < 0 || t > 100)) return { success: false, reason: 'bad_tokens' };
  await pool.query(
    `INSERT INTO tc_mission_overrides (mission_key, enabled, tokens, updated_by)
     VALUES ($1, $2, $3, $4)
     ON CONFLICT (mission_key) DO UPDATE
       SET enabled = EXCLUDED.enabled, tokens = EXCLUDED.tokens,
           updated_by = EXCLUDED.updated_by, updated_at = NOW()`,
    [key, enabled !== false, t, adminName || 'admin']
  );
  await loadOverrides(true);
  return { success: true };
}

async function adminSetProduct(key, { enabled, price }, adminName) {
  if (!defs.PRODUCT_BY_KEY.has(key)) return { success: false, reason: 'unknown_product' };
  const pr = price === '' || price == null ? null : Math.trunc(Number(price));
  if (pr != null && (!Number.isFinite(pr) || pr < 1 || pr > 100000)) return { success: false, reason: 'bad_price' };
  await pool.query(
    `INSERT INTO tc_token_product_overrides (product_key, enabled, price, updated_by)
     VALUES ($1, $2, $3, $4)
     ON CONFLICT (product_key) DO UPDATE
       SET enabled = EXCLUDED.enabled, price = EXCLUDED.price,
           updated_by = EXCLUDED.updated_by, updated_at = NOW()`,
    [key, enabled !== false, pr, adminName || 'admin']
  );
  await loadOverrides(true);
  return { success: true };
}

/** 관리자 화면: 미션별 고른/완료한 수와 오늘·누적 토큰. */
async function adminOverview() {
  await loadOverrides();
  const [perMission, today, totals, holders, shop] = await Promise.all([
    pool.query(
      `SELECT mission_key,
              COUNT(*)::int AS picked,
              COUNT(*) FILTER (WHERE status = 'done')::int AS done,
              COUNT(*) FILTER (WHERE status = 'active')::int AS active,
              COUNT(*) FILTER (WHERE status = 'expired')::int AS expired,
              COUNT(*) FILTER (WHERE status = 'dropped')::int AS dropped
         FROM tc_user_missions GROUP BY mission_key`
    ),
    pool.query(
      `SELECT
         COUNT(*) FILTER (WHERE picked_day = DATE(timezone('Asia/Seoul', NOW())))::int AS picked_today,
         COUNT(*) FILTER (WHERE status = 'done'
           AND DATE(timezone('Asia/Seoul', done_at::timestamptz)) = DATE(timezone('Asia/Seoul', NOW())))::int AS done_today,
         COUNT(DISTINCT nickname) FILTER (WHERE picked_day = DATE(timezone('Asia/Seoul', NOW())))::int AS pickers_today
       FROM tc_user_missions`
    ),
    pool.query(
      `SELECT
         COALESCE(SUM(delta) FILTER (WHERE kst_day = DATE(timezone('Asia/Seoul', NOW())) AND delta > 0), 0)::int AS issued_today,
         COALESCE(SUM(delta) FILTER (WHERE delta > 0), 0)::int AS issued_total,
         COALESCE(-SUM(delta) FILTER (WHERE reason = 'shop'), 0)::int AS spent_shop
       FROM tc_token_ledger`
    ),
    pool.query(`SELECT COUNT(*)::int AS holders, COALESCE(SUM(balance),0)::int AS outstanding FROM tc_token_balance WHERE balance > 0`),
    pool.query(
      `SELECT ref AS product_key, COUNT(*)::int AS buys, COALESCE(-SUM(delta), 0)::int AS spent
         FROM tc_token_ledger WHERE reason = 'shop' GROUP BY ref`
    ),
  ]);
  const by = new Map(perMission.rows.map((r) => [r.mission_key, r]));
  const shopBy = new Map(shop.rows.map((r) => [r.product_key, r]));
  return {
    today: today.rows[0],
    totals: totals.rows[0],
    holders: holders.rows[0],
    missions: defs.MISSIONS.map((m) => {
      const e = effectiveMission(m.key);
      const s = by.get(m.key) || { picked: 0, done: 0, active: 0, expired: 0, dropped: 0 };
      return { ...m, enabled: e.enabled, effectiveTokens: e.tokens, ...s };
    }),
    products: defs.PRODUCTS.map((p) => {
      const e = effectiveProduct(p.key);
      const s = shopBy.get(p.key) || { buys: 0, spent: 0 };
      return { ...p, enabled: e.enabled, effectivePrice: e.price, buys: s.buys, spent: s.spent };
    }),
  };
}

/** 토큰 장부 조회(닉네임·사유로 거른다). */
async function adminLedger({ nickname, reason, page = 1, limit = 50 } = {}) {
  const where = [];
  const params = [];
  if (nickname) { params.push(`%${nickname}%`); where.push(`nickname ILIKE $${params.length}`); }
  if (reason) { params.push(reason); where.push(`reason = $${params.length}`); }
  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
  const lim = Math.max(1, Math.min(parseInt(limit, 10) || 50, 200));
  const pg = Math.max(1, parseInt(page, 10) || 1);
  const [rows, count] = await Promise.all([
    pool.query(
      `SELECT id, nickname, delta, reason, ref, created_at
         FROM tc_token_ledger ${whereSql}
        ORDER BY id DESC LIMIT ${lim} OFFSET ${(pg - 1) * lim}`,
      params
    ),
    pool.query(`SELECT COUNT(*)::int AS n FROM tc_token_ledger ${whereSql}`, params),
  ]);
  return { rows: rows.rows, total: count.rows[0].n, page: pg, limit: lim };
}

/** 한 유저의 토큰 현황(잔액·누적·진행 중 미션·보유 상품). */
async function adminUserSummary(nickname) {
  const [bal, active, owned] = await Promise.all([
    pool.query('SELECT balance, total_earned FROM tc_token_balance WHERE nickname = $1', [nickname]),
    pool.query(
      `SELECT mission_key, progress, target, status, to_char(expires_day,'YYYY-MM-DD') AS expires_day
         FROM tc_user_missions WHERE nickname = $1 AND status = 'active' ORDER BY id`,
      [nickname]
    ),
    pool.query(
      `SELECT product_key, expires_at FROM tc_token_owned WHERE nickname = $1 AND expires_at > NOW() ORDER BY product_key`,
      [nickname]
    ),
  ]);
  return {
    balance: bal.rows[0] ? bal.rows[0].balance : 0,
    totalEarned: bal.rows[0] ? bal.rows[0].total_earned : 0,
    active: active.rows,
    owned: owned.rows,
  };
}

module.exports = {
  init,
  loadOverrides,
  effectiveMission,
  effectiveProduct,
  adminGrant,
  adminSetMission,
  adminSetProduct,
  adminOverview,
  adminLedger,
  adminUserSummary,
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
  getBalances,
  getHistory,
  offersFor,
  defs,
};
