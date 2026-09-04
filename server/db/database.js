const { Pool, types: pgTypes } = require('pg');
const bcrypt = require('bcrypt');
const { VISUAL_BACKFILL } = require('./shop_visuals_seed');

const SALT_ROUNDS = 10;

// Approx KRW list price per gold product. The store (not us) controls the real
// charged price/currency, so this is ONLY for the admin "오늘 순매출(추정)"
// estimate — base KRW list price, before store cut / FX / foreign currency.
const GOLD_PRODUCT_KRW = {
  'jiny.tichu.gold1': 1200,
  'jiny.tichu.gold2': 3900,
  'jiny.tichu.gold3': 9900,
  'jiny.tichu.gold4': 29000,
  'jiny.tichu.gold5': 99000,
};

// Store commission per platform, used ONLY for the admin "정산추정액" estimate.
// Defaults assume Apple Small Business Program (15%) and Google Play reduced
// service fee for the first $1M/yr (15%). Adjust if the program status changes.
const APPLE_FEE_RATE = 0.15;
const GOOGLE_FEE_RATE = 0.15;
const platformFeeRate = (p) => (p === 'ios' ? APPLE_FEE_RATE : GOOGLE_FEE_RATE);

// Interpret TIMESTAMP WITHOUT TIME ZONE (oid 1114) as UTC wall-clock instead
// of letting node-pg apply the Node process's local TZ. The DB session is
// pinned to UTC (see pool 'connect' handler), so every value coming out of a
// naked TIMESTAMP column was already written as UTC; without this override,
// running the server on a non-UTC host (e.g. an Asia/Seoul dev machine) makes
// pg produce Date objects shifted by the host's UTC offset, and downstream
// JSON serialization then sends an ISO string that's hours off. Affects gold
// history, match history, admin time formatters — anything reading
// created_at-style columns.
pgTypes.setTypeParser(pgTypes.builtins.TIMESTAMP, (val) => {
  if (val == null) return null;
  return new Date(`${val}Z`);
});

// Idempotent backfill of tc_shop_items.metadata.visual. Skips any row that
// already has a `visual` key under metadata, so admin-authored edits remain
// the source of truth. New items added by admin start with their own visual
// and are never touched here.
async function backfillShopVisuals(client) {
  const entries = Object.entries(VISUAL_BACKFILL);
  if (entries.length === 0) return;
  for (const [itemKey, visual] of entries) {
    await client.query(
      `UPDATE tc_shop_items
         SET metadata = jsonb_set(COALESCE(metadata, '{}'::jsonb), '{visual}', $2::jsonb, true)
       WHERE item_key = $1
         AND (metadata IS NULL OR metadata->'visual' IS NULL)`,
      [itemKey, JSON.stringify(visual)]
    );

    // Per-field patch: if the row already had metadata.visual from a prior
    // seed run, the UPDATE above no-ops. Splice in newer top-level fields
    // (text/preview/thumbnail) only when the existing visual is missing
    // that field, so admin's saved edits stay the source of truth. Currently
    // exercised by adding text.color to banners that shipped without one.
    if (visual.text) {
      await client.query(
        `UPDATE tc_shop_items
           SET metadata = jsonb_set(metadata, '{visual,text}', $2::jsonb, true)
         WHERE item_key = $1
           AND metadata IS NOT NULL
           AND metadata->'visual' IS NOT NULL
           AND metadata->'visual'->'text' IS NULL`,
        [itemKey, JSON.stringify(visual.text)]
      );
    }
  }
}

// PostgreSQL connection pool
const isProduction = process.env.NODE_ENV === 'production';
const DEFAULT_LOCAL_URL = 'postgresql://jiny@localhost:5432/minigame';
const pool = new Pool({
  connectionString: process.env.DATABASE_URL || DEFAULT_LOCAL_URL,
  ssl: isProduction ? { rejectUnauthorized: false } : false,
});

// Pin every session to UTC so naked TIMESTAMP columns (e.g. created_at)
// are written/read as UTC wall-clock no matter what the host PG default is.
// All admin KST conversions assume this; without it, a host configured to
// Asia/Seoul stores KST wall-clock and the conversions shift by 9h.
pool.on('connect', (client) => {
  client.query("SET TIME ZONE 'UTC'").catch(() => {});
});

// Initialize database tables (tc_ prefix for tichu)
/**
 * 마이그레이션은 실패하면 부팅을 멈춘다(아래 initDatabase 참고). 그래서 잠깐의
 * DB 끊김으로 컨테이너가 크래시 루프에 빠지지 않도록, 여기서 몇 번 다시 해
 * 본다. 진짜로 깨진 마이그레이션은 몇 번을 해도 같은 곳에서 실패하므로
 * 결국 부팅이 멈춘다 — 구분은 "다시 해서 되느냐" 하나로 충분하다.
 */
async function initDatabase(attempt = 1) {
  const MAX_ATTEMPTS = 4;
  try {
    return await runMigrations();
  } catch (err) {
    if (attempt >= MAX_ATTEMPTS) throw err;
    const waitMs = attempt * 2000;
    console.error(
      `[migration] ${attempt}번째 시도 실패 (${err.message}) — ${waitMs / 1000}초 후 재시도`,
    );
    await new Promise((r) => setTimeout(r, waitMs));
    return initDatabase(attempt + 1);
  }
}

async function runMigrations() {
  const client = await pool.connect();
  // 배포는 블루/그린이라 새 슬롯이 뜨는 동안 옛 슬롯이 최대 15분 더 산다.
  // 두 인스턴스가 CREATE TABLE/INDEX IF NOT EXISTS 를 동시에 던지면 포스트그레스
  // 카탈로그에서 부딪혀 한쪽이 에러를 받는다. 자문 잠금으로 한 번에 하나만
  // 지나가게 한다 — 뒤에 온 쪽은 앞의 결과를 보고 전부 no-op 으로 끝난다.
  const MIGRATION_LOCK_KEY = 848213771;
  let lockHeld = false;
  try {
    await client.query('SELECT pg_advisory_lock($1)', [MIGRATION_LOCK_KEY]);
    lockHeld = true;
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_users (
        id SERIAL PRIMARY KEY,
        username VARCHAR(50) UNIQUE NOT NULL,
        password_hash VARCHAR(255) NOT NULL,
        nickname VARCHAR(50) UNIQUE NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        last_login TIMESTAMP
      )
    `);

    // Blocked users table
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_blocked_users (
        id SERIAL PRIMARY KEY,
        blocker_nickname VARCHAR(50) NOT NULL,
        blocked_nickname VARCHAR(50) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(blocker_nickname, blocked_nickname)
      )
    `);

    // Reports table
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_reports (
        id SERIAL PRIMARY KEY,
        reporter_nickname VARCHAR(50) NOT NULL,
        reported_nickname VARCHAR(50) NOT NULL,
        reason TEXT,
        room_id VARCHAR(100),
        chat_context TEXT,
        status VARCHAR(20) DEFAULT 'pending',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    // Add chat_context column if not exists (for existing tables)
    await client.query(`
      ALTER TABLE tc_reports ADD COLUMN IF NOT EXISTS chat_context TEXT
    `);

    // Unique index: same reporter + same target + same room + same reason = no duplicate
    await client.query(`
      CREATE UNIQUE INDEX IF NOT EXISTS idx_report_unique
      ON tc_reports (reporter_nickname, reported_nickname, room_id, reason)
    `);

    // Inquiries table
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_inquiries (
        id SERIAL PRIMARY KEY,
        user_nickname VARCHAR(50) NOT NULL,
        category VARCHAR(20) NOT NULL,
        title VARCHAR(200) NOT NULL,
        content TEXT NOT NULL,
        status VARCHAR(20) DEFAULT 'pending',
        admin_note TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        resolved_at TIMESTAMP
      )
    `);

    // Add user_read column to tc_inquiries if not exists
    await client.query(`
      ALTER TABLE tc_inquiries ADD COLUMN IF NOT EXISTS user_read BOOLEAN DEFAULT FALSE
    `);

    // Friends table
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_friends (
        id SERIAL PRIMARY KEY,
        user_nickname VARCHAR(50) NOT NULL,
        friend_nickname VARCHAR(50) NOT NULL,
        status VARCHAR(20) DEFAULT 'pending',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(user_nickname, friend_nickname)
      )
    `);

    // Match history table
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_match_history (
        id SERIAL PRIMARY KEY,
        winner_team VARCHAR(10),
        team_a_score INT,
        team_b_score INT,
        player_a1 VARCHAR(50),
        player_a2 VARCHAR(50),
        player_b1 VARCHAR(50),
        player_b2 VARCHAR(50),
        is_ranked BOOLEAN DEFAULT FALSE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    // Match history: end reason tracking
    await client.query(`ALTER TABLE tc_match_history ADD COLUMN IF NOT EXISTS end_reason VARCHAR(20) DEFAULT 'normal'`);
    await client.query(`ALTER TABLE tc_match_history ADD COLUMN IF NOT EXISTS deserter_nickname VARCHAR(50) DEFAULT NULL`);

    // Walking out of a match that KEEPS RUNNING (mid-game-join rooms: a bot
    // inherits the seat). None of the per-game match tables can hold this:
    // they get one row when a match ends, carry a single deserter_nickname,
    // and list the roster as it stood at the end — which no longer includes
    // whoever left. So the departure had no home and simply vanished from the
    // leaver's history. One row per departure, written the moment it happens,
    // which is also what makes leaving three times in one match show up three
    // times instead of collapsing into the match's single deserter slot.
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_midleave_log (
        id SERIAL PRIMARY KEY,
        nickname VARCHAR(50) NOT NULL,
        game_type VARCHAR(20) NOT NULL,
        reason VARCHAR(20) NOT NULL DEFAULT 'leave',
        room_name VARCHAR(60),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);
    await client.query(
      `CREATE INDEX IF NOT EXISTS idx_tc_midleave_log_nickname_created
         ON tc_midleave_log (nickname, created_at DESC)`,
    );
    // Who was at the table when they walked. Stored on the row rather than
    // looked up later: the match keeps running and the seats keep changing, so
    // by the time anyone reads this the roster is a different one. JSON text,
    // not a comma-joined string — nicknames are user input and may contain
    // commas.
    await client.query(`ALTER TABLE tc_midleave_log ADD COLUMN IF NOT EXISTS players TEXT`);

    // ── Coupons ──────────────────────────────────────────────────────────
    // A code handed out in a notice or on a blog, redeemed once per account
    // for gold or a shop item.
    //
    // `redeemed_count` is denormalised on purpose. The honest count is a
    // COUNT(*) over the redemption table, but the cap has to be enforced
    // inside the same transaction that inserts the redemption — and counting
    // rows under a lock is the slow way to do what one locked integer does.
    // The redemption table stays the source of truth for *who*; this column is
    // the source of truth for *how many are left*.
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_coupons (
        code VARCHAR(40) PRIMARY KEY,
        reward_type VARCHAR(20) NOT NULL,
        reward_gold INT,
        reward_item_key VARCHAR(80),
        reward_days INT,
        max_redemptions INT,
        redeemed_count INT NOT NULL DEFAULT 0,
        expires_at TIMESTAMP,
        is_active BOOLEAN NOT NULL DEFAULT TRUE,
        memo TEXT,
        created_by VARCHAR(50),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);
    // One per account, enforced by the database rather than by a check-then-
    // insert. Two taps that arrive together both pass a check; only one can
    // win a unique index.
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_coupon_redemptions (
        id SERIAL PRIMARY KEY,
        code VARCHAR(40) NOT NULL,
        nickname VARCHAR(50) NOT NULL,
        reward_summary TEXT,
        redeemed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE (code, nickname)
      )
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_tc_coupon_redemptions_code
        ON tc_coupon_redemptions (code, redeemed_at DESC)
    `);
    // User stats columns
    // Snapshot of the target's profile photo at the moment of the report.
    // Report-side hiding keys off this (a NEW photo shows again), and the
    // object with this key is kept in storage as evidence even if the owner
    // deletes or replaces it.
    await client.query(`ALTER TABLE tc_reports ADD COLUMN IF NOT EXISTS reported_photo_key TEXT DEFAULT NULL`);
    // What the report was actually about. Hiding follows the complaint: a photo
    // report hides that photo, a title report hides that title, and a report
    // about someone's behaviour hides neither — before this, every report hid
    // the reported user's photo from the reporter.
    await client.query(`ALTER TABLE tc_reports ADD COLUMN IF NOT EXISTS reason_code VARCHAR(20)`);
    await client.query(`ALTER TABLE tc_reports ADD COLUMN IF NOT EXISTS reported_title TEXT`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS total_games INT DEFAULT 0`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS wins INT DEFAULT 0`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS losses INT DEFAULT 0`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS rating INT DEFAULT 1000`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS gold INT DEFAULT 0`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS leave_count INT DEFAULT 0`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS season_rating INT DEFAULT 1000`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS season_games INT DEFAULT 0`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS season_wins INT DEFAULT 0`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS season_losses INT DEFAULT 0`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS exp_total INT DEFAULT 0`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS level INT DEFAULT 1`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS ranked_ban_until TIMESTAMP`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS chat_ban_until TIMESTAMP`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS admin_memo TEXT`);

    // Profile photo (UGC) columns — see server/deploy/PROFILE_PHOTO_PLAN.md
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS profile_photo_key VARCHAR(255)`);        // minio object key (NULL = default avatar)
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS profile_photo_expires_at TIMESTAMP`);    // 7-day item expiry (NULL = inactive)
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS profile_photo_status VARCHAR(20) DEFAULT 'none'`); // none | active

    // Photos rejected by SafeSearch screening on upload. Before this, a
    // reject just threw image_rejected and the buffer was dropped — the only
    // trace was a console log line, so an admin could see "who got rejected"
    // but never what the image actually was. Kept in the same bucket as
    // active profile photos, under a rejected/ prefix, so publicUrl() works
    // unchanged.
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_photo_rejections (
        id SERIAL PRIMARY KEY,
        user_id INTEGER NOT NULL,
        nickname VARCHAR(50) NOT NULL,
        image_key VARCHAR(255) NOT NULL,
        worst VARCHAR(20),
        adult_score VARCHAR(20),
        racy_score VARCHAR(20),
        violence_score VARCHAR(20),
        labels TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_photo_rejections_created
      ON tc_photo_rejections (created_at DESC)
    `);
    // Profile privacy: the entitlement itself is an ordinary feature item in
    // tc_user_items (effect_type 'profile_private'); only the owner's choice of
    // how far it reaches lives here.
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS profile_private_hide_photo BOOLEAN DEFAULT FALSE`);
    // Custom title: the entitlement is an ordinary feature item in
    // tc_user_items; the text and its palette colour are the user's own and
    // live here so they survive a lapsed pass and come back on re-purchase.
    // Feature passes the owner has switched off. Presence = off; the pass keeps
    // running to its expiry either way — this only decides whether it applies.
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_user_feature_off (
        nickname VARCHAR(50) NOT NULL,
        effect_type VARCHAR(40) NOT NULL,
        PRIMARY KEY (nickname, effect_type)
      )
    `);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS custom_title_text VARCHAR(24)`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS custom_title_color VARCHAR(16)`);


    // Device info columns
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS fcm_token TEXT`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS push_enabled BOOLEAN DEFAULT true`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS push_friend_invite BOOLEAN DEFAULT true`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS is_admin BOOLEAN DEFAULT false`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS push_admin_inquiry BOOLEAN DEFAULT true`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS push_admin_report BOOLEAN DEFAULT true`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS push_admin_payment BOOLEAN DEFAULT true`);
    // Marketing consent. Unlike every other push preference above, this one
    // defaults to FALSE: 정보통신망법 requires opt-in for 광고성 정보, so an
    // account that has never been asked must not be in the audience. The
    // timestamp is the record of when they said yes (or no) — the column alone
    // cannot tell "declined" from "never asked", and that is the thing you have
    // to be able to show.
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS marketing_push_enabled BOOLEAN DEFAULT false`);
    // 출석 알림. 이벤트·혜택 알림(마케팅 동의) 안에 딸린 스위치라 기본이
    // 켬이다 — 이미 동의한 사람이 아무것도 안 해도 받는다는 뜻이고, 그게
    // 이 기능을 마케팅 동의에 얹은 이유다. 동의 자체가 없으면 이 값이 켬
    // 이어도 아무것도 안 나간다(보내는 쪽에서 둘 다 본다).
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS push_attendance BOOLEAN DEFAULT true`);
    // 기기의 UTC 오프셋(분). 저녁 7시에 보내려면 누구의 7시인지 알아야 하고,
    // 그건 서버가 알 수 없다. 인도(+330)·네팔(+345)처럼 시가 아닌 오프셋이
    // 있으므로 분 단위로 받는다. 안 보낸 클라이언트는 NULL 로 남는다.
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS tz_offset_minutes SMALLINT`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS marketing_consent_at TIMESTAMP`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS marketing_asked_at TIMESTAMP`);
    // When we last told them they are still opted in. 정보통신망법 §50 ⑧ wants
    // that confirmation every two years from the date consent was given, and
    // 시행령 §62-3 says it must carry the sender's name, the date and fact of
    // consent, and how to keep or withdraw it.
    //
    // Separate from marketing_consent_at, which must not move: the two-year
    // clock runs from the original consent, and overwriting that date would
    // restart the clock every time we confirmed.
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS marketing_confirmed_at TIMESTAMP`);
    // When FCM last told us this device's token is dead — the app was
    // uninstalled, or the token was replaced and the old one retired. Stamped
    // rather than nulling the token: the account stays, and "had a device,
    // lost it on this date" is a different fact from "never had one", which is
    // what an empty column would say.
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS fcm_token_invalid_at TIMESTAMP`);
    // When they were last connected — stamped on login AND on disconnect.
    // Distinct from last_login, which only moves at sign-in: someone who
    // logged in on Monday and played until last night reads as "3일 전" from
    // last_login alone, which is the opposite of what a friends list is for.
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMP`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN DEFAULT false`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS device_platform VARCHAR(20)`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS device_model VARCHAR(100)`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS os_version VARCHAR(50)`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS app_version VARCHAR(50)`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS last_ip VARCHAR(45)`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS locale VARCHAR(5)`);

    // Social login columns
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS auth_provider VARCHAR(20) DEFAULT 'local'`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS provider_uid VARCHAR(255)`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS email VARCHAR(255)`);
    await client.query(`ALTER TABLE tc_users ALTER COLUMN password_hash DROP NOT NULL`);
    await client.query(`
      DROP INDEX IF EXISTS idx_social_provider_uid
    `);
    await client.query(`
      CREATE UNIQUE INDEX idx_social_provider_uid
      ON tc_users (auth_provider, provider_uid) WHERE auth_provider IS NOT NULL AND auth_provider NOT LIKE 'del_%' AND is_deleted IS NOT TRUE
    `);

    // Shop items table
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_shop_items (
        id SERIAL PRIMARY KEY,
        item_key VARCHAR(80) UNIQUE NOT NULL,
        name VARCHAR(100) NOT NULL DEFAULT '',
        name_ko VARCHAR(100) NOT NULL DEFAULT '',
        name_en VARCHAR(100) NOT NULL DEFAULT '',
        name_de VARCHAR(100) NOT NULL DEFAULT '',
        category VARCHAR(30) NOT NULL,
        price INT DEFAULT 0,
        is_season BOOLEAN DEFAULT FALSE,
        is_permanent BOOLEAN DEFAULT TRUE,
        duration_days INT,
        is_purchasable BOOLEAN DEFAULT TRUE,
        effect_type VARCHAR(30),
        effect_value INT,
        metadata JSONB,
        sale_start TIMESTAMP,
        sale_end TIMESTAMP,
        new_until TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    // Add sale_start/sale_end columns if not exists (for existing tables)
    await client.query(`ALTER TABLE tc_shop_items ADD COLUMN IF NOT EXISTS sale_start TIMESTAMP`);
    await client.query(`ALTER TABLE tc_shop_items ADD COLUMN IF NOT EXISTS sale_end TIMESTAMP`);
    // "NEW" badge + top-of-list sort, admin-set with an expiry so it doesn't
    // need to be manually turned off later.
    await client.query(`ALTER TABLE tc_shop_items ADD COLUMN IF NOT EXISTS new_until TIMESTAMP`);

    // Add name_ko/name_en/name_de columns; keep original 'name' column for rollback safety
    await client.query(`ALTER TABLE tc_shop_items ADD COLUMN IF NOT EXISTS name_ko VARCHAR(100) NOT NULL DEFAULT ''`);
    await client.query(`ALTER TABLE tc_shop_items ADD COLUMN IF NOT EXISTS name_en VARCHAR(100) NOT NULL DEFAULT ''`);
    await client.query(`ALTER TABLE tc_shop_items ADD COLUMN IF NOT EXISTS name_de VARCHAR(100) NOT NULL DEFAULT ''`);
    await client.query(`ALTER TABLE tc_shop_items ADD COLUMN IF NOT EXISTS description_ko TEXT NOT NULL DEFAULT ''`);
    await client.query(`ALTER TABLE tc_shop_items ADD COLUMN IF NOT EXISTS description_en TEXT NOT NULL DEFAULT ''`);
    await client.query(`ALTER TABLE tc_shop_items ADD COLUMN IF NOT EXISTS description_de TEXT NOT NULL DEFAULT ''`);
    // Restore 'name' column if it was previously renamed away (rollback safety)
    await client.query(`ALTER TABLE tc_shop_items ADD COLUMN IF NOT EXISTS name VARCHAR(100) NOT NULL DEFAULT ''`);
    // Copy name → name_ko for existing rows where name_ko is empty
    await client.query(`
      DO $body$ BEGIN
        UPDATE tc_shop_items SET name_ko = name WHERE name_ko = '' AND name IS NOT NULL AND name <> '';
        UPDATE tc_shop_items SET name = name_ko WHERE (name IS NULL OR name = '') AND name_ko <> '';
      END $body$
    `);

    // User owned items
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_user_items (
        id SERIAL PRIMARY KEY,
        nickname VARCHAR(50) NOT NULL,
        item_key VARCHAR(80) NOT NULL,
        acquired_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        expires_at TIMESTAMP,
        is_active BOOLEAN DEFAULT FALSE,
        source VARCHAR(30) DEFAULT 'shop'
      )
    `);
    // Every lookup here filters by nickname (often plus item_key) — profile
    // fetches, ownership checks, cleanupExpiredItems — and without this it's
    // a full-table scan on every one of them, scaling with total items ever
    // sold rather than one player's own row count.
    await client.query(`CREATE INDEX IF NOT EXISTS idx_tc_user_items_nickname ON tc_user_items (nickname, item_key)`);

    // User equipped cosmetics
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_user_equips (
        nickname VARCHAR(50) PRIMARY KEY,
        banner_key VARCHAR(80),
        title_key VARCHAR(80),
        theme_key VARCHAR(80),
        card_skin_key VARCHAR(80),
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    // Seasons and rewards
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_seasons (
        id SERIAL PRIMARY KEY,
        name VARCHAR(50) NOT NULL,
        start_at TIMESTAMP NOT NULL,
        end_at TIMESTAMP NOT NULL,
        status VARCHAR(20) DEFAULT 'active',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_season_rewards (
        id SERIAL PRIMARY KEY,
        season_id INT NOT NULL,
        nickname VARCHAR(50) NOT NULL,
        rank INT NOT NULL,
        gold_reward INT DEFAULT 0,
        banner_key VARCHAR(80),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    // Per-season reward tiers. season_id NULL is the default set every season
    // inherits, so a season that was never configured behaves exactly as the
    // hard-coded table did before this existed.
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_season_reward_config (
        id SERIAL PRIMARY KEY,
        season_id INT,
        game_type VARCHAR(20) NOT NULL,
        rank INT NOT NULL,
        gold INT NOT NULL DEFAULT 0,
        banner_key VARCHAR(80),
        banner_days INT DEFAULT 30,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);
    // NULL season_id can't participate in a plain UNIQUE, so the default set
    // gets its own partial index.
    await client.query(`
      CREATE UNIQUE INDEX IF NOT EXISTS idx_season_reward_cfg
        ON tc_season_reward_config (season_id, game_type, rank)
        WHERE season_id IS NOT NULL
    `);
    await client.query(`
      CREATE UNIQUE INDEX IF NOT EXISTS idx_season_reward_cfg_default
        ON tc_season_reward_config (game_type, rank)
        WHERE season_id IS NULL
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_season_rankings (
        id SERIAL PRIMARY KEY,
        season_id INT NOT NULL,
        rank INT NOT NULL,
        nickname VARCHAR(50) NOT NULL,
        rating INT DEFAULT 0,
        wins INT DEFAULT 0,
        losses INT DEFAULT 0,
        total_games INT DEFAULT 0,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE (season_id, rank)
      )
    `);

    // Gold IAP products — real-money → in-game gold. Server is the single
    // source of truth for which product_ids are active and how much gold each
    // grants; the actual money price/currency comes from the store at runtime.
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_gold_products (
        id SERIAL PRIMARY KEY,
        product_id VARCHAR(80) UNIQUE NOT NULL,
        gold_amount INT NOT NULL DEFAULT 0,
        bonus_gold INT NOT NULL DEFAULT 0,
        platform VARCHAR(10) NOT NULL DEFAULT 'both',
        label_ko VARCHAR(100) NOT NULL DEFAULT '',
        label_en VARCHAR(100) NOT NULL DEFAULT '',
        label_de VARCHAR(100) NOT NULL DEFAULT '',
        sort_order INT NOT NULL DEFAULT 0,
        is_active BOOLEAN NOT NULL DEFAULT FALSE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    // Won price, for the web client only. On iOS/Android the store owns the
    // price and we must not show our own (and store policy forbids paying
    // anywhere but the store anyway) — but the web build has no store to ask,
    // so a bank transfer needs a number to put on screen. Admin-editable.
    await client.query(
      `ALTER TABLE tc_gold_products ADD COLUMN IF NOT EXISTS price_krw INT NOT NULL DEFAULT 0`
    );

    // IAP receipt ledger. transaction_id is the idempotency key: a verified
    // store transaction grants gold exactly once even if the client retries.
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_iap_receipts (
        id SERIAL PRIMARY KEY,
        nickname VARCHAR(50) NOT NULL,
        product_id VARCHAR(80) NOT NULL,
        platform VARCHAR(10) NOT NULL,
        transaction_id VARCHAR(255) UNIQUE NOT NULL,
        gold_granted INT NOT NULL,
        environment VARCHAR(12) NOT NULL DEFAULT 'production',
        status VARCHAR(20) NOT NULL DEFAULT 'granted',
        refunded_at TIMESTAMP,
        refund_admin VARCHAR(100),
        verified_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        raw_payload JSONB
      )
    `);
    // Idempotent guards for dev DBs that already had the pre-refund schema.
    // production table is created fresh so these are no-ops there.
    await client.query(`ALTER TABLE tc_iap_receipts ADD COLUMN IF NOT EXISTS environment VARCHAR(12) NOT NULL DEFAULT 'production'`);
    await client.query(`ALTER TABLE tc_iap_receipts ADD COLUMN IF NOT EXISTS status VARCHAR(20) NOT NULL DEFAULT 'granted'`);
    await client.query(`ALTER TABLE tc_iap_receipts ADD COLUMN IF NOT EXISTS refunded_at TIMESTAMP`);
    await client.query(`ALTER TABLE tc_iap_receipts ADD COLUMN IF NOT EXISTS refund_admin VARCHAR(100)`);
    // status: 'granted' | 'refunded' | 'refund_failed'. refund_failed = store
    // refunded the money but we could NOT claw back gold (user spent it) →
    // lands in the admin triage queue. refund_detected_at = when the store
    // refund was seen/processed; refunded_at = when gold was actually pulled.
    await client.query(`ALTER TABLE tc_iap_receipts ADD COLUMN IF NOT EXISTS refund_source VARCHAR(20)`);
    await client.query(`ALTER TABLE tc_iap_receipts ADD COLUMN IF NOT EXISTS refund_reason VARCHAR(160)`);
    await client.query(`ALTER TABLE tc_iap_receipts ADD COLUMN IF NOT EXISTS refund_detected_at TIMESTAMP`);
    // 'refund_failed' is 13 characters and the column was 12, so the one write
    // that matters most — parking a store refund we could not claw back — threw
    // 22001 and rolled back, every 30 minutes, forever: the Voided Purchases
    // poll re-listed the same purchase, failed to mark it, and the row never
    // reached the admin triage queue. Widening is a catalog-only change for
    // varchar, so it costs nothing on a live table. refund_source goes with it:
    // 'admin_google' already sits exactly on its 12-character limit, which is
    // the same accident waiting for the next source name.
    // Only when it is actually narrower: ALTER COLUMN TYPE takes an exclusive
    // lock, and this runs on every boot.
    const narrow = await client.query(
      `SELECT column_name FROM information_schema.columns
        WHERE table_name = 'tc_iap_receipts'
          AND column_name IN ('status', 'refund_source')
          AND character_maximum_length < 20`
    );
    for (const row of narrow.rows) {
      await client.query(
        `ALTER TABLE tc_iap_receipts ALTER COLUMN ${row.column_name} TYPE VARCHAR(20)`
      );
      console.log(`[migration] tc_iap_receipts.${row.column_name} → VARCHAR(20)`);
    }

    // Every verify_iap_purchase attempt is appended here regardless of outcome
    // (granted / already_granted / rejected / error). No idempotency key — this
    // is an audit trail, one row per attempt. Lets the operator diagnose why a
    // sandbox/live purchase failed verification from the admin web.
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_iap_attempts (
        id SERIAL PRIMARY KEY,
        nickname VARCHAR(50),
        platform VARCHAR(10),
        product_id VARCHAR(80),
        environment VARCHAR(12),
        outcome VARCHAR(20) NOT NULL,
        reason VARCHAR(80),
        transaction_id VARCHAR(255),
        raw_payload JSONB,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_iap_attempts_created ON tc_iap_attempts (created_at DESC)`);

    // (match-history indexes are created later, AFTER the sk/ll/mighty match
    // tables exist — see "Recent-matches lookup indexes" below.)

    // Apple CONSUMPTION_REQUEST log. Apple asks for consumption info when a
    // user requests a consumable refund; we record every request (idempotent
    // on notification_uuid — Apple retries) and our response outcome.
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_iap_consumption_requests (
        id SERIAL PRIMARY KEY,
        notification_uuid VARCHAR(64) UNIQUE NOT NULL,
        transaction_id VARCHAR(255),
        product_id VARCHAR(80),
        nickname VARCHAR(50),
        environment VARCHAR(12),
        request_reason VARCHAR(40),
        consumption_status INT,
        refund_preference INT,
        account_tenure_days INT,
        response_status VARCHAR(16) NOT NULL DEFAULT 'received',
        response_detail VARCHAR(160),
        snapshot JSONB,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        responded_at TIMESTAMP
      )
    `);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_iap_consumption_created ON tc_iap_consumption_requests (created_at DESC)`);

    // Daily attendance reward (7-day streak: 50/50/50/50/50/50/1000 gold).
    // last_claim_date is the KST date of the last successful claim; that's
    // also the per-day idempotency key (one row per user). When today's KST
    // date == last_claim_date we refuse a second claim.
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_attendance (
        nickname VARCHAR(50) PRIMARY KEY,
        last_claim_date DATE,
        current_streak INT NOT NULL DEFAULT 0,
        total_claims INT NOT NULL DEFAULT 0,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    // 출석 알림을 보낸 기록. 하루 한 번을 넘기지 않기 위한 것이면서,
    // 반응 없는 사람에게 매일 보내지 않기 위한 것이기도 하다.
    //   push_last_date    : 마지막으로 보낸 날 (받는 사람의 현지 날짜)
    //   push_ignored      : 보냈는데 그날 출석 안 한 횟수, 연속
    //   push_muted_until  : 이 KST 날짜까지 쉰다
    await client.query(`ALTER TABLE tc_attendance ADD COLUMN IF NOT EXISTS push_last_date DATE`);
    await client.query(`ALTER TABLE tc_attendance ADD COLUMN IF NOT EXISTS push_ignored SMALLINT NOT NULL DEFAULT 0`);
    await client.query(`ALTER TABLE tc_attendance ADD COLUMN IF NOT EXISTS push_muted_until DATE`);

    // Seed the 5 agreed tiers, inactive by default. ON CONFLICT DO NOTHING so
    // re-runs never clobber admin-edited gold/bonus/active values.
    await client.query(`
      INSERT INTO tc_gold_products
        (product_id, gold_amount, bonus_gold, platform, label_ko, sort_order, is_active)
      VALUES
        ('jiny.tichu.gold1', 2000,   0,     'both', '골드 2,000',          1, FALSE),
        ('jiny.tichu.gold2', 6500,   500,   'both', '골드 7,000 (+8%)',    2, FALSE),
        ('jiny.tichu.gold3', 16500,  3500,   'both', '골드 20,000 (+21%)',  3, FALSE),
        ('jiny.tichu.gold4', 48300,  16700,  'both', '골드 65,000 (+35%)',  4, FALSE),
        ('jiny.tichu.gold5', 165000, 135000, 'both', '골드 300,000 (+82%)', 5, FALSE)
      ON CONFLICT (product_id) DO NOTHING
    `);

    // Backfill the agreed won prices onto the seeded tiers. Guarded on
    // price_krw = 0 so this only ever fills a blank — an admin who edits a
    // price keeps it across restarts, same contract as the ON CONFLICT above.
    await client.query(`
      UPDATE tc_gold_products AS p SET price_krw = v.price
        FROM (VALUES
          ('jiny.tichu.gold1', 1200),
          ('jiny.tichu.gold2', 3900),
          ('jiny.tichu.gold3', 9900),
          ('jiny.tichu.gold4', 29000),
          ('jiny.tichu.gold5', 99000)
        ) AS v(product_id, price)
       WHERE p.product_id = v.product_id AND p.price_krw = 0
    `);

    // Bank-transfer deposit claims (web shop). A player says they have
    // transferred the money; an admin checks the bank statement and approves
    // or rejects. Nothing here moves gold on its own.
    //
    // A table rather than the tc_inquiries row this used to write: the admin
    // needs a queue with a status and one-click approval, and parsing the
    // product and amount back out of a Korean sentence to grant the right
    // gold would be its own bug source. gold_amount is snapshotted at request
    // time so editing a product later cannot change what an old claim pays.
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_bank_deposits (
        id SERIAL PRIMARY KEY,
        nickname VARCHAR(50) NOT NULL,
        product_id VARCHAR(80) NOT NULL,
        price_krw INT NOT NULL DEFAULT 0,
        gold_amount INT NOT NULL DEFAULT 0,
        depositor VARCHAR(40) NOT NULL,
        status VARCHAR(10) NOT NULL DEFAULT 'pending',
        admin_note TEXT,
        handled_by VARCHAR(50),
        handled_at TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);
    // The admin list is "pending first, newest first"; the user-facing check
    // is "does this player already have one open".
    await client.query(
      `CREATE INDEX IF NOT EXISTS idx_bank_deposits_status
         ON tc_bank_deposits (status, created_at DESC)`
    );

    // App config table (EULA, etc.)
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_config (
        key VARCHAR(100) PRIMARY KEY,
        value TEXT,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    // Seed default EULA content
    await client.query(`
      INSERT INTO tc_config (key, value)
      VALUES ('eula_content', '티추 온라인 이용약관

제 1 조 (목적)
본 약관은 티추 온라인(이하 "서비스")의 이용과 관련하여 서비스 제공자와 이용자 간의 권리, 의무 및 책임사항을 규정함을 목적으로 합니다.

제 2 조 (정의)
1. "서비스"란 티추 온라인에서 제공하는 모든 게임 및 관련 기능을 말합니다.
2. "이용자"란 본 약관에 따라 서비스를 이용하는 자를 말합니다.
3. "콘텐츠"란 이용자가 서비스 내에서 생성, 공유하는 텍스트, 닉네임, 채팅 메시지 등을 말합니다.

제 3 조 (약관의 효력 및 변경)
1. 본 약관은 서비스 화면에 게시하거나 기타의 방법으로 이용자에게 공지함으로써 효력을 발생합니다.
2. 서비스 제공자는 필요한 경우 약관을 변경할 수 있으며, 변경된 약관은 공지 후 효력을 발생합니다.

제 4 조 (이용자의 의무)
1. 이용자는 다음 행위를 하여서는 안 됩니다:
  - 타인의 정보를 도용하는 행위
  - 서비스의 운영을 방해하는 행위
  - 타인에 대한 욕설, 비방, 차별, 혐오 발언
  - 음란하거나 폭력적인 콘텐츠를 게시하는 행위
  - 불법적이거나 부정한 목적으로 서비스를 이용하는 행위
  - 게임 내 버그를 악용하거나 비정상적인 방법으로 게임을 진행하는 행위
2. 이용자가 위 의무를 위반한 경우, 서비스 이용이 제한될 수 있습니다.

제 5 조 (서비스의 제공 및 변경)
1. 서비스 제공자는 서비스의 내용을 변경하거나 중단할 수 있습니다.
2. 서비스 제공자는 서비스 변경 시 사전에 공지합니다.

제 6 조 (게시물 관리)
1. 이용자가 작성한 게시물(채팅 메시지, 닉네임 등)의 저작권은 해당 이용자에게 있습니다.
2. 서비스 제공자는 다음에 해당하는 게시물을 사전 통보 없이 삭제하거나 이용을 제한할 수 있습니다:
  - 다른 이용자를 비방하거나 명예를 훼손하는 내용
  - 공공질서 및 미풍양속에 위반되는 내용
  - 범죄와 관련된 내용
  - 서비스 제공자의 저작권 등 지적재산권을 침해하는 내용

제 7 조 (개인정보 보호)
서비스 제공자는 이용자의 개인정보를 보호하기 위해 노력하며, 관련 법령에 따라 개인정보를 처리합니다.

제 8 조 (면책)
1. 서비스 제공자는 천재지변, 전쟁 등 불가항력으로 인해 서비스를 제공할 수 없는 경우 책임을 지지 않습니다.
2. 서비스 제공자는 이용자의 귀책사유로 인한 서비스 이용 장애에 대해 책임을 지지 않습니다.

제 9 조 (분쟁 해결)
본 약관과 관련된 분쟁은 대한민국 법령에 따라 해결합니다.

부칙
본 약관은 2025년 1월 1일부터 시행합니다.')
      ON CONFLICT (key) DO NOTHING
    `);

    // Seed default privacy policy
    await client.query(`
      INSERT INTO tc_config (key, value)
      VALUES ('privacy_policy', '개인정보처리방침

1. 수집하는 개인정보 항목
서비스는 회원가입 및 서비스 이용을 위해 다음의 정보를 수집합니다:
- 필수: 아이디, 닉네임, 비밀번호
- 선택: 소셜 로그인 시 이메일, 소셜 계정 식별자
- 자동 수집: 기기 정보(모델, OS 버전), 앱 버전, IP 주소

2. 개인정보의 수집 및 이용 목적
- 회원 식별 및 서비스 제공
- 게임 매칭 및 전적 관리
- 부정 이용 방지 및 신고 처리
- 푸시 알림 발송 (사용자 동의 시)
- 서비스 개선 및 통계 분석

3. 개인정보의 보유 및 이용 기간
- 회원 탈퇴 시 즉시 삭제
- 관련 법령에 따라 보존이 필요한 경우 해당 기간 동안 보관

4. 개인정보의 제3자 제공
서비스는 이용자의 개인정보를 제3자에게 제공하지 않습니다.
다만, 법령에 의해 요구되는 경우는 예외로 합니다.

5. 개인정보의 파기
회원 탈퇴 또는 보유 기간 만료 시, 전자적 파일 형태의 정보는 복구할 수 없는 방법으로 삭제합니다.

6. 이용자의 권리
이용자는 언제든지 자신의 개인정보를 조회, 수정, 삭제할 수 있으며, 회원 탈퇴를 통해 처리를 요청할 수 있습니다.

7. 개인정보 보호를 위한 기술적 조치
- 비밀번호 암호화 저장
- SSL/TLS 암호화 통신
- 접근 권한 관리

8. 개인정보 보호 책임자
서비스 운영자에게 문의하기를 통해 연락할 수 있습니다.

시행일: 2025년 1월 1일')
      ON CONFLICT (key) DO NOTHING
    `);

    // Migrate legacy Korean-only EULA/privacy into locale-suffixed keys.
    // The legacy key (eula_content / privacy_policy) is preserved as the
    // last-resort fallback. Admin fills in _en and _de via backstage; _ko
    // seeds from the legacy Korean content so it shows up ready to edit.
    await client.query(`
      INSERT INTO tc_config (key, value)
      SELECT 'eula_content_ko', value FROM tc_config WHERE key = 'eula_content'
      ON CONFLICT (key) DO NOTHING
    `);
    await client.query(`
      INSERT INTO tc_config (key, value)
      SELECT 'privacy_policy_ko', value FROM tc_config WHERE key = 'privacy_policy'
      ON CONFLICT (key) DO NOTHING
    `);

    // Admin accounts table
    await client.query(`
      CREATE TABLE IF NOT EXISTS admin_accounts (
        id SERIAL PRIMARY KEY,
        username VARCHAR(50) UNIQUE NOT NULL,
        password VARCHAR(255) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    // Seed default admin account if none exists
    const adminCount = await client.query('SELECT COUNT(*) FROM admin_accounts');
    if (parseInt(adminCount.rows[0].count) === 0) {
      const defaultPassword = await bcrypt.hash('admin1234', SALT_ROUNDS);
      await client.query(
        'INSERT INTO admin_accounts (username, password) VALUES ($1, $2)',
        ['admin', defaultPassword]
      );
      console.log('Default admin account created (admin / admin1234)');
    }

    // Seed the default reward tiers — the exact table that used to be written
    // into grantSeasonRewards, so an untouched install grants what it always
    // did.
    //
    // 딱 한 번만 넣는다. "비어 있으면 넣는다" 였을 때는, 보상을 주지 않기로
    // 하고 기본값을 비워둔 운영자의 선택이 다음 부팅에 조용히 되살아났다.
    // 되돌리고 싶으면 관리 화면에서 다시 채우면 된다.
    const seededFlag = await client.query(
      `SELECT value FROM tc_config WHERE key = 'season_reward_defaults_seeded'`,
    );
    const cfgCount = await client.query(
      'SELECT COUNT(*) FROM tc_season_reward_config WHERE season_id IS NULL',
    );
    const alreadySeeded = seededFlag.rows.length > 0;
    if (!alreadySeeded && parseInt(cfgCount.rows[0].count, 10) > 0) {
      // 이 표시가 생기기 전부터 돌던 설치. 기본값은 이미 들어 있으니 넣지 말고
      // 표시만 남긴다 — 안 그러면 나중에 운영자가 비웠을 때 딱 한 번 되살아난다.
      await client.query(
        `INSERT INTO tc_config (key, value, updated_at) VALUES ('season_reward_defaults_seeded', '1', NOW())
         ON CONFLICT (key) DO NOTHING`,
      );
    }
    if (!alreadySeeded && parseInt(cfgCount.rows[0].count, 10) === 0) {
      await client.query(`
        INSERT INTO tc_season_reward_config (season_id, game_type, rank, gold, banner_key, banner_days)
        VALUES
          (NULL, 'tichu', 1, 1000, 'banner_season_gold', 30),
          (NULL, 'tichu', 2, 500, 'banner_season_silver', 30),
          (NULL, 'tichu', 3, 200, 'banner_season_bronze', 30),
          (NULL, 'skull_king', 1, 1000, 'banner_sk_season_gold', 30),
          (NULL, 'skull_king', 2, 500, 'banner_sk_season_silver', 30),
          (NULL, 'skull_king', 3, 200, 'banner_sk_season_bronze', 30),
          (NULL, 'mighty', 1, 1000, 'banner_mighty_season_gold', 30),
          (NULL, 'mighty', 2, 500, 'banner_mighty_season_silver', 30),
          (NULL, 'mighty', 3, 200, 'banner_mighty_season_bronze', 30)
      `);
      await client.query(
        `INSERT INTO tc_config (key, value, updated_at) VALUES ('season_reward_defaults_seeded', '1', NOW())
         ON CONFLICT (key) DO NOTHING`,
      );
    }

    // Seed shop items (safe upsert)
    await client.query(
      `
      INSERT INTO tc_shop_items
        (item_key, name, name_ko, name_en, name_de, category, price, is_season, is_permanent, duration_days, is_purchasable, effect_type, effect_value, metadata)
      VALUES
        ('banner_pastel', '파스텔 배너', '파스텔 배너', 'Pastel Banner', 'Pastell-Banner', 'banner', 300, FALSE, FALSE, 30, TRUE, NULL, NULL, '{}'::jsonb),
        ('banner_blossom', '블라썸 배너', '블라썸 배너', 'Blossom Banner', 'Blüten-Banner', 'banner', 280, FALSE, FALSE, 30, TRUE, NULL, NULL, '{}'::jsonb),
        ('banner_mint', '민트 배너', '민트 배너', 'Mint Banner', 'Minz-Banner', 'banner', 260, FALSE, FALSE, 30, TRUE, NULL, NULL, '{}'::jsonb),
        ('banner_sunset_7d', '노을 배너', '노을 배너', 'Sunset Banner', 'Sonnenuntergang-Banner', 'banner', 120, FALSE, FALSE, 30, TRUE, NULL, NULL, '{}'::jsonb),
        ('banner_ocean', '오션 배너', '오션 배너', 'Ocean Banner', 'Ozean-Banner', 'banner', 280, FALSE, FALSE, 30, TRUE, NULL, NULL, '{}'::jsonb),
        ('banner_forest', '포레스트 배너', '포레스트 배너', 'Forest Banner', 'Wald-Banner', 'banner', 280, FALSE, FALSE, 30, TRUE, NULL, NULL, '{}'::jsonb),
        ('banner_lavender', '라벤더 배너', '라벤더 배너', 'Lavender Banner', 'Lavendel-Banner', 'banner', 290, FALSE, FALSE, 30, TRUE, NULL, NULL, '{}'::jsonb),
        ('banner_aurora', '오로라 배너', '오로라 배너', 'Aurora Banner', 'Polarlicht-Banner', 'banner', 320, FALSE, FALSE, 30, TRUE, NULL, NULL, '{}'::jsonb),
        ('banner_galaxy', '갤럭시 배너', '갤럭시 배너', 'Galaxy Banner', 'Galaxie-Banner', 'banner', 320, FALSE, FALSE, 30, TRUE, NULL, NULL, '{}'::jsonb),
        ('banner_sakura', '벚꽃 배너', '벚꽃 배너', 'Sakura Banner', 'Sakura-Banner', 'banner', 290, FALSE, FALSE, 30, TRUE, NULL, NULL, '{}'::jsonb),
        ('banner_coral', '코랄 배너', '코랄 배너', 'Coral Banner', 'Korallen-Banner', 'banner', 260, FALSE, FALSE, 30, TRUE, NULL, NULL, '{}'::jsonb),
        ('banner_moonlight', '문라이트 배너', '문라이트 배너', 'Moonlight Banner', 'Mondlicht-Banner', 'banner', 290, FALSE, FALSE, 30, TRUE, NULL, NULL, '{}'::jsonb),
        ('banner_ember', '잔불 배너', '잔불 배너', 'Ember Banner', 'Glut-Banner', 'banner', 270, FALSE, FALSE, 30, TRUE, NULL, NULL, '{}'::jsonb),
        ('banner_emerald', '에메랄드 배너', '에메랄드 배너', 'Emerald Banner', 'Smaragd-Banner', 'banner', 310, FALSE, FALSE, 30, TRUE, NULL, NULL, '{}'::jsonb),
        ('title_sweet', '존맛탱', '존맛탱', 'Yummy', 'Lecker', 'title', 200, FALSE, FALSE, 10, TRUE, NULL, NULL, '{}'::jsonb),
        ('title_steady', '찐고수', '찐고수', 'True Pro', 'Echte:r Profi', 'title', 240, FALSE, FALSE, 10, TRUE, NULL, NULL, '{}'::jsonb),
        ('title_flash_30d', '광속러', '광속러', 'Speed Demon', 'Blitzschnell', 'title', 180, FALSE, FALSE, 10, TRUE, NULL, NULL, '{}'::jsonb),
        ('title_dragon', '갓벽한', '갓벽한', 'Flawless', 'Makellos', 'title', 300, FALSE, FALSE, 10, TRUE, NULL, NULL, '{}'::jsonb),
        ('title_phoenix', '불죽러', '불죽러', 'Undying', 'Unsterblich', 'title', 300, FALSE, FALSE, 10, TRUE, NULL, NULL, '{}'::jsonb),
        ('title_pirate', '야르', '야르', 'Yarr', 'Yarr', 'title', 280, FALSE, FALSE, 10, TRUE, NULL, NULL, '{}'::jsonb),
        ('title_tactician', '뇌섹러', '뇌섹러', 'Tactician', 'Taktiker:in', 'title', 320, FALSE, FALSE, 10, TRUE, NULL, NULL, '{}'::jsonb),
        ('title_lucky', '럭키비키', '럭키비키', 'Lucky Star', 'Glückspilz', 'title', 200, FALSE, FALSE, 10, TRUE, NULL, NULL, '{}'::jsonb),
        ('title_bluffer', '쿨쿨잠', '쿨쿨잠', 'Sleepyhead', 'Schlafmütze', 'title', 260, FALSE, FALSE, 10, TRUE, NULL, NULL, '{}'::jsonb),
        ('title_ace', '존잘러', '존잘러', 'Ace Player', 'Ass-Spieler:in', 'title', 280, FALSE, FALSE, 10, TRUE, NULL, NULL, '{}'::jsonb),
        ('title_king', '킹왕짱', '킹왕짱', 'King of Kings', 'König:in', 'title', 350, FALSE, FALSE, 10, TRUE, NULL, NULL, '{}'::jsonb),
        ('title_rookie', '뉴비임', '뉴비임', 'Newbie', 'Neuling', 'title', 150, FALSE, FALSE, 10, TRUE, NULL, NULL, '{}'::jsonb),
        ('title_veteran', '만렙러', '만렙러', 'Max Level', 'Max-Level', 'title', 300, FALSE, FALSE, 10, TRUE, NULL, NULL, '{}'::jsonb),
        ('title_sensitive', '예민해', '예민해', 'Sensitive', 'Empfindlich', 'title', 280, FALSE, FALSE, 10, TRUE, NULL, NULL, '{}'::jsonb),
        ('title_shadow', '숨쉬듯이', '숨쉬듯이', 'Like Breathing', 'Wie Atmen', 'title', 260, FALSE, FALSE, 10, TRUE, NULL, NULL, '{}'::jsonb),
        ('title_flame', '존버왕', '존버왕', 'HODL King', 'Durchhalter:in', 'title', 240, FALSE, FALSE, 10, TRUE, NULL, NULL, '{}'::jsonb),
        ('title_ice', '갓생러', '갓생러', 'Go-Getter', 'Macher:in', 'title', 240, FALSE, FALSE, 10, TRUE, NULL, NULL, '{}'::jsonb),
        ('title_crown', '레게노', '레게노', 'Legend', 'Legende', 'title', 400, FALSE, FALSE, 10, TRUE, NULL, NULL, '{}'::jsonb),
        ('title_diamond', '개꿀', '개꿀', 'Sweet Deal', 'Volltreffer', 'title', 350, FALSE, FALSE, 10, TRUE, NULL, NULL, '{}'::jsonb),
        ('title_ghost', '투명드래곤', '투명드래곤', 'Invisible Dragon', 'Unsichtbarer Drache', 'title', 220, FALSE, FALSE, 10, TRUE, NULL, NULL, '{}'::jsonb),
        ('title_thunder', '겜잘알', '겜잘알', 'Game Guru', 'Spiel-Guru', 'title', 180, FALSE, FALSE, 10, TRUE, NULL, NULL, '{}'::jsonb),
        ('title_topcard', '그게탑패', '그게탑패', 'Top Card', 'Trumpfkarte', 'title', 280, FALSE, FALSE, 10, TRUE, NULL, NULL, '{}'::jsonb),
        ('title_legend', '찐레전드', '찐레전드', 'True Legend', 'Echte Legende', 'title', 500, FALSE, FALSE, 10, TRUE, NULL, NULL, '{}'::jsonb),
        ('title_boomer', '꼰대', '꼰대', 'Boomer', 'Boomer', 'title', 260, FALSE, FALSE, 10, TRUE, NULL, NULL, '{}'::jsonb),
        ('theme_cotton', '코튼 테마', '코튼 테마', 'Cotton Theme', 'Baumwoll-Thema', 'theme', 500, FALSE, FALSE, 30, TRUE, NULL, NULL, '{"includesCardSkin": true}'::jsonb),
        ('theme_sky', '스카이 테마', '스카이 테마', 'Sky Theme', 'Himmel-Thema', 'theme', 550, FALSE, FALSE, 30, TRUE, NULL, NULL, '{"includesCardSkin": true}'::jsonb),
        ('theme_mocha_30d', '모카 테마', '모카 테마', 'Mocha Theme', 'Mokka-Thema', 'theme', 300, FALSE, FALSE, 30, TRUE, NULL, NULL, '{"includesCardSkin": true}'::jsonb),
        ('theme_lavender', '라벤더 테마', '라벤더 테마', 'Lavender Theme', 'Lavendel-Thema', 'theme', 500, FALSE, FALSE, 30, TRUE, NULL, NULL, '{"includesCardSkin": true}'::jsonb),
        ('theme_cherry', '체리블라썸 테마', '체리블라썸 테마', 'Cherry Blossom Theme', 'Kirschblüten-Thema', 'theme', 550, FALSE, FALSE, 30, TRUE, NULL, NULL, '{"includesCardSkin": true}'::jsonb),
        ('theme_midnight', '미드나잇 테마', '미드나잇 테마', 'Midnight Theme', 'Mitternacht-Thema', 'theme', 600, FALSE, FALSE, 30, TRUE, NULL, NULL, '{"includesCardSkin": true}'::jsonb),
        ('theme_sunset', '선셋 테마', '선셋 테마', 'Sunset Theme', 'Sonnenuntergang-Thema', 'theme', 500, FALSE, FALSE, 30, TRUE, NULL, NULL, '{"includesCardSkin": true}'::jsonb),
        ('theme_forest', '포레스트 테마', '포레스트 테마', 'Forest Theme', 'Wald-Thema', 'theme', 520, FALSE, FALSE, 30, TRUE, NULL, NULL, '{"includesCardSkin": true}'::jsonb),
        ('theme_rose', '로즈골드 테마', '로즈골드 테마', 'Rose Gold Theme', 'Roségold-Thema', 'theme', 550, FALSE, FALSE, 30, TRUE, NULL, NULL, '{"includesCardSkin": true}'::jsonb),
        ('theme_ocean', '오션 테마', '오션 테마', 'Ocean Theme', 'Ozean-Thema', 'theme', 500, FALSE, FALSE, 30, TRUE, NULL, NULL, '{"includesCardSkin": true}'::jsonb),
        ('theme_aurora', '오로라 테마', '오로라 테마', 'Aurora Theme', 'Aurora-Thema', 'theme', 600, FALSE, FALSE, 30, TRUE, NULL, NULL, '{"includesCardSkin": true}'::jsonb),
        ('theme_mintchoco_30d', '민트초코 테마', '민트초코 테마', 'Mint Choco Theme', 'Minzschoko-Thema', 'theme', 300, FALSE, FALSE, 30, TRUE, NULL, NULL, '{"includesCardSkin": true}'::jsonb),
        ('theme_peach_30d', '피치 테마', '피치 테마', 'Peach Theme', 'Pfirsich-Thema', 'theme', 280, FALSE, FALSE, 30, TRUE, NULL, NULL, '{"includesCardSkin": true}'::jsonb),
        ('leave_reduce_1', '탈주 카운트 -1', '탈주 카운트 -1', 'Leave Count -1', 'Flucht-Zähler -1', 'utility', 150, FALSE, TRUE, NULL, TRUE, 'leave_count_reduce', 1, '{}'::jsonb),
        ('leave_reduce_3', '탈주 카운트 -3', '탈주 카운트 -3', 'Leave Count -3', 'Flucht-Zähler -3', 'utility', 400, FALSE, TRUE, NULL, TRUE, 'leave_count_reduce', 3, '{}'::jsonb),
        ('nickname_change', '닉네임 변경권', '닉네임 변경권', 'Nickname Change', 'Nickname-Änderung', 'utility', 500, FALSE, TRUE, NULL, TRUE, 'nickname_change', NULL, '{}'::jsonb),
        ('top_card_counter_7d', '티츄 탑패 카운터(7일)', '티츄 탑패 카운터(7일)', 'Tichu Top Card Counter (7d)', 'Tichu-Trumpfzähler (7T)', 'utility', 1000, FALSE, FALSE, 7, TRUE, 'top_card_counter', NULL, '{}'::jsonb),
        ('top_card_counter_30d', '티츄 탑패 카운터(30일)', '티츄 탑패 카운터(30일)', 'Tichu Top Card Counter (30d)', 'Tichu-Trumpfzähler (30T)', 'utility', 3000, FALSE, FALSE, 30, TRUE, 'top_card_counter', NULL, '{}'::jsonb),
        ('stats_reset', '전적 초기화권', '전적 초기화권', 'Stats Reset', 'Statistik-Reset', 'utility', 2000, FALSE, TRUE, NULL, TRUE, 'stats_reset', NULL, '{}'::jsonb),
        ('season_stats_reset', '전체 랭킹전적 초기화권', '전체 랭킹전적 초기화권', 'All Ranked Stats Reset', 'Alle-Ranglistenstatistik-Reset', 'utility', 1500, FALSE, TRUE, NULL, TRUE, 'season_stats_reset', NULL, '{}'::jsonb),
        ('tichu_season_stats_reset', '티츄 랭킹전적 초기화권', '티츄 랭킹전적 초기화권', 'Tichu Ranked Stats Reset', 'Tichu-Ranglistenstatistik-Reset', 'utility', 700, FALSE, TRUE, NULL, TRUE, 'tichu_season_stats_reset', NULL, '{}'::jsonb),
        ('sk_season_stats_reset', '스컬킹 랭킹전적 초기화권', '스컬킹 랭킹전적 초기화권', 'Skull King Ranked Stats Reset', 'Skull-King-Ranglistenstatistik-Reset', 'utility', 700, FALSE, TRUE, NULL, TRUE, 'sk_season_stats_reset', NULL, '{}'::jsonb),
        ('mighty_season_stats_reset', '마이티 랭킹전적 초기화권', '마이티 랭킹전적 초기화권', 'Mighty Ranked Stats Reset', 'Mighty-Ranglistenstatistik-Reset', 'utility', 700, FALSE, TRUE, NULL, TRUE, 'mighty_season_stats_reset', NULL, '{}'::jsonb),
        ('leave_reset', '탈주 카운트 초기화', '탈주 카운트 초기화', 'Leave Count Reset', 'Flucht-Zähler-Reset', 'utility', 2000, FALSE, TRUE, NULL, TRUE, 'leave_count_reset', NULL, '{}'::jsonb),
        ('mighty_trump_counter_7d', '마이티 기루다 카운터(7일)', '마이티 기루다 카운터(7일)', 'Mighty Trump Counter (7d)', 'Mighty-Trumpfzähler (7T)', 'utility', 1000, FALSE, FALSE, 7, TRUE, 'mighty_trump_counter', NULL, '{}'::jsonb),
        ('mighty_trump_counter_30d', '마이티 기루다 카운터(30일)', '마이티 기루다 카운터(30일)', 'Mighty Trump Counter (30d)', 'Mighty-Trumpfzähler (30T)', 'utility', 3000, FALSE, FALSE, 30, TRUE, 'mighty_trump_counter', NULL, '{}'::jsonb),
        ('mighty_prev_trick_7d', '마이티 이전 트릭 확인(7일)', '마이티 이전 트릭 확인(7일)', 'Mighty Previous Trick Viewer (7d)', 'Mighty-Vorheriger-Stich-Anzeige (7T)', 'utility', 1000, FALSE, FALSE, 7, TRUE, 'mighty_prev_trick', NULL, '{}'::jsonb),
        ('mighty_prev_trick_30d', '마이티 이전 트릭 확인(30일)', '마이티 이전 트릭 확인(30일)', 'Mighty Previous Trick Viewer (30d)', 'Mighty-Vorheriger-Stich-Anzeige (30T)', 'utility', 3000, FALSE, FALSE, 30, TRUE, 'mighty_prev_trick', NULL, '{}'::jsonb),
        ('profile_photo_7d', '프로필 사진(7일)', '프로필 사진(7일)', 'Profile Photo (7d)', 'Profilbild (7T)', 'feature', 1000, FALSE, FALSE, 7, FALSE, 'profile_photo', NULL, '{}'::jsonb),
        ('profile_photo_30d', '프로필 사진(30일)', '프로필 사진(30일)', 'Profile Photo (30d)', 'Profilbild (30T)', 'feature', 3000, FALSE, FALSE, 30, FALSE, 'profile_photo', NULL, '{}'::jsonb),
        -- The five feature items below ship is_purchasable = FALSE on purpose.
        -- A deploy swaps servers blue/green, so the OLD server serves this new
        -- catalog for up to 15 minutes with no version gate for these effect
        -- types, and the app build that can use them is not in the stores on
        -- deploy day either. Turn them on in admin once the client is live —
        -- is_purchasable is not in the ON CONFLICT update list below, so the
        -- switch survives every later boot.
        ('custom_title_7d', '커스텀 칭호(7일)', '커스텀 칭호(7일)', 'Custom Title (7d)', 'Eigener Titel (7T)', 'feature', 500, FALSE, FALSE, 7, FALSE, 'custom_title', NULL, '{}'::jsonb),
        ('profile_private_7d', '프로필 비공개(7일)', '프로필 비공개(7일)', 'Private Profile (7d)', 'Privates Profil (7T)', 'feature', 1000, FALSE, FALSE, 7, FALSE, 'profile_private', NULL, '{}'::jsonb),
        ('profile_private_30d', '프로필 비공개(30일)', '프로필 비공개(30일)', 'Private Profile (30d)', 'Privates Profil (30T)', 'feature', 3000, FALSE, FALSE, 30, FALSE, 'profile_private', NULL, '{}'::jsonb),
        ('banner_season_gold', '티츄 시즌 골드 배너', '티츄 시즌 골드 배너', 'Tichu Season Gold Banner', 'Tichu-Saison-Gold-Banner', 'banner', 0, TRUE, FALSE, 30, FALSE, NULL, NULL, '{}'::jsonb),
        ('banner_season_silver', '티츄 시즌 실버 배너', '티츄 시즌 실버 배너', 'Tichu Season Silver Banner', 'Tichu-Saison-Silber-Banner', 'banner', 0, TRUE, FALSE, 30, FALSE, NULL, NULL, '{}'::jsonb),
        ('banner_season_bronze', '티츄 시즌 브론즈 배너', '티츄 시즌 브론즈 배너', 'Tichu Season Bronze Banner', 'Tichu-Saison-Bronze-Banner', 'banner', 0, TRUE, FALSE, 30, FALSE, NULL, NULL, '{}'::jsonb),
        ('banner_sk_season_gold', '스컬킹 시즌 골드 배너', '스컬킹 시즌 골드 배너', 'Skull King Season Gold Banner', 'Skull-King-Saison-Gold-Banner', 'banner', 0, TRUE, FALSE, 30, FALSE, NULL, NULL, '{}'::jsonb),
        ('banner_sk_season_silver', '스컬킹 시즌 실버 배너', '스컬킹 시즌 실버 배너', 'Skull King Season Silver Banner', 'Skull-King-Saison-Silber-Banner', 'banner', 0, TRUE, FALSE, 30, FALSE, NULL, NULL, '{}'::jsonb),
        ('banner_sk_season_bronze', '스컬킹 시즌 브론즈 배너', '스컬킹 시즌 브론즈 배너', 'Skull King Season Bronze Banner', 'Skull-King-Saison-Bronze-Banner', 'banner', 0, TRUE, FALSE, 30, FALSE, NULL, NULL, '{}'::jsonb),
        ('banner_mighty_season_gold', '마이티 시즌 골드 배너', '마이티 시즌 골드 배너', 'Mighty Season Gold Banner', 'Mighty-Saison-Gold-Banner', 'banner', 0, TRUE, FALSE, 30, FALSE, NULL, NULL, '{}'::jsonb),
        ('banner_mighty_season_silver', '마이티 시즌 실버 배너', '마이티 시즌 실버 배너', 'Mighty Season Silver Banner', 'Mighty-Saison-Silber-Banner', 'banner', 0, TRUE, FALSE, 30, FALSE, NULL, NULL, '{}'::jsonb),
        ('banner_mighty_season_bronze', '마이티 시즌 브론즈 배너', '마이티 시즌 브론즈 배너', 'Mighty Season Bronze Banner', 'Mighty-Saison-Bronze-Banner', 'banner', 0, TRUE, FALSE, 30, FALSE, NULL, NULL, '{}'::jsonb),

        -- 개척자 배너: 초기 이용자에게 쿠폰으로 주는 영구 배너.
        --
        -- is_purchasable = FALSE 로 나가고 그대로 둔다. 상점에서 파는 물건이
        -- 아니라는 것이 이 배너의 전부다 — 팔리는 순간 "초기부터 있었다"는
        -- 뜻이 사라진다. is_season 은 FALSE 다: 시즌 보상이 아니고, TRUE 면
        -- 시즌 지급 로직이 후보로 집어간다.
        --
        -- 영구(is_permanent = TRUE, duration_days = NULL)라서 쿠폰으로 주면
        -- expires_at 이 비어 들어간다 — redeemCoupon 이 그렇게 처리한다.
        --
        -- 열 개를 다 넣는 것은 어느 것을 뿌릴지 나중에 고르기 위해서다.
        -- 상점에 안 뜨므로 이용자에게는 존재하지 않는 것과 같고, 안 쓸 것은
        -- 그냥 안 주면 된다.
        ('banner_pio_champagne', '개척자 · 샴페인', '개척자 · 샴페인', 'Pioneer · Champagne', 'Pioneer · Champagne', 'banner', 0, FALSE, TRUE, NULL, FALSE, NULL, NULL, '{}'::jsonb),
        ('banner_pio_dawn', '개척자 · 여명', '개척자 · 여명', 'Pioneer · First Light', 'Pioneer · First Light', 'banner', 0, FALSE, TRUE, NULL, FALSE, NULL, NULL, '{}'::jsonb),
        ('banner_pio_haze', '개척자 · 아침안개', '개척자 · 아침안개', 'Pioneer · Morning Haze', 'Pioneer · Morning Haze', 'banner', 0, FALSE, TRUE, NULL, FALSE, NULL, NULL, '{}'::jsonb),
        ('banner_pio_pearl', '개척자 · 진주', '개척자 · 진주', 'Pioneer · Pearl', 'Pioneer · Pearl', 'banner', 0, FALSE, TRUE, NULL, FALSE, NULL, NULL, '{}'::jsonb),
        ('banner_pio_sage', '개척자 · 린넨과 세이지', '개척자 · 린넨과 세이지', 'Pioneer · Linen and Sage', 'Pioneer · Linen and Sage', 'banner', 0, FALSE, TRUE, NULL, FALSE, NULL, NULL, '{}'::jsonb),
        ('banner_pioneer_deep', '개척자 · 심해', '개척자 · 심해', 'Pioneer · Deep Current', 'Pioneer · Deep Current', 'banner', 0, FALSE, TRUE, NULL, FALSE, NULL, NULL, '{}'::jsonb),
        ('banner_pioneer_gilt', '개척자 · 먹과 금테', '개척자 · 먹과 금테', 'Pioneer · Ink and Gilt', 'Pioneer · Ink and Gilt', 'banner', 0, FALSE, TRUE, NULL, FALSE, NULL, NULL, '{}'::jsonb),
        ('banner_pioneer_iris', '개척자 · 오일슬릭', '개척자 · 오일슬릭', 'Pioneer · Oil Slick', 'Pioneer · Oil Slick', 'banner', 0, FALSE, TRUE, NULL, FALSE, NULL, NULL, '{}'::jsonb),
        ('banner_pioneer_iris2', '개척자 · 네뷸라', '개척자 · 네뷸라', 'Pioneer · Nebula', 'Pioneer · Nebula', 'banner', 0, FALSE, TRUE, NULL, FALSE, NULL, NULL, '{}'::jsonb),
        ('banner_pioneer_iris3', '개척자 · 오로라나이트', '개척자 · 오로라나이트', 'Pioneer · Aurora Night', 'Pioneer · Aurora Night', 'banner', 0, FALSE, TRUE, NULL, FALSE, NULL, NULL, '{}'::jsonb),

        -- 개척자 테마: 위 배너와 짝을 이루는 색. 같이 걸면 세트로 보인다.
        --
        -- 배너와 달리 테마 색은 클라이언트에 하드코딩돼 있다
        -- (game_service.dart 의 themeGradientFor / cardBackColorsFor). 그래서
        -- 이 행만 있고 앱이 구버전이면 기본 그라디언트로 떨어진다 — 앱이
        -- 나간 뒤에 지급해야 한다.
        --
        -- includesCardSkin: 기존 테마와 같다. 테마는 배경과 카드 뒷면을
        -- 함께 바꾼다.
        ('theme_pio_deep', '개척자 · 심해 테마', '개척자 · 심해 테마', 'Pioneer · Deep Current Theme', 'Pioneer · Deep Current Theme', 'theme', 0, FALSE, TRUE, NULL, FALSE, NULL, NULL, '{"includesCardSkin": true}'::jsonb),
        ('theme_pio_gilt', '개척자 · 먹과 금테 테마', '개척자 · 먹과 금테 테마', 'Pioneer · Ink and Gilt Theme', 'Pioneer · Ink and Gilt Theme', 'theme', 0, FALSE, TRUE, NULL, FALSE, NULL, NULL, '{"includesCardSkin": true}'::jsonb),
        ('theme_pio_oilslick', '개척자 · 오일슬릭 테마', '개척자 · 오일슬릭 테마', 'Pioneer · Oil Slick Theme', 'Pioneer · Oil Slick Theme', 'theme', 0, FALSE, TRUE, NULL, FALSE, NULL, NULL, '{"includesCardSkin": true}'::jsonb),
        ('theme_pio_nebula', '개척자 · 네뷸라 테마', '개척자 · 네뷸라 테마', 'Pioneer · Nebula Theme', 'Pioneer · Nebula Theme', 'theme', 0, FALSE, TRUE, NULL, FALSE, NULL, NULL, '{"includesCardSkin": true}'::jsonb),
        ('theme_pio_aurora', '개척자 · 오로라나이트 테마', '개척자 · 오로라나이트 테마', 'Pioneer · Aurora Night Theme', 'Pioneer · Aurora Night Theme', 'theme', 0, FALSE, TRUE, NULL, FALSE, NULL, NULL, '{"includesCardSkin": true}'::jsonb),
        ('theme_pio_pearl', '개척자 · 진주 테마', '개척자 · 진주 테마', 'Pioneer · Pearl Theme', 'Pioneer · Pearl Theme', 'theme', 0, FALSE, TRUE, NULL, FALSE, NULL, NULL, '{"includesCardSkin": true}'::jsonb),
        ('theme_pio_champagne', '개척자 · 샴페인 테마', '개척자 · 샴페인 테마', 'Pioneer · Champagne Theme', 'Pioneer · Champagne Theme', 'theme', 0, FALSE, TRUE, NULL, FALSE, NULL, NULL, '{"includesCardSkin": true}'::jsonb),
        ('theme_pio_haze', '개척자 · 아침안개 테마', '개척자 · 아침안개 테마', 'Pioneer · Morning Haze Theme', 'Pioneer · Morning Haze Theme', 'theme', 0, FALSE, TRUE, NULL, FALSE, NULL, NULL, '{"includesCardSkin": true}'::jsonb),
        ('theme_pio_sage', '개척자 · 린넨과 세이지 테마', '개척자 · 린넨과 세이지 테마', 'Pioneer · Linen and Sage Theme', 'Pioneer · Linen and Sage Theme', 'theme', 0, FALSE, TRUE, NULL, FALSE, NULL, NULL, '{"includesCardSkin": true}'::jsonb),
        ('theme_pio_dawn', '개척자 · 여명 테마', '개척자 · 여명 테마', 'Pioneer · First Light Theme', 'Pioneer · First Light Theme', 'theme', 0, FALSE, TRUE, NULL, FALSE, NULL, NULL, '{"includesCardSkin": true}'::jsonb),

        -- 시즌 이벤트 배너·테마 6종(설날/추석/연말/개천절/한글날/크리스마스).
        -- 배너와 테마는 짝을 이루는 색이지만
        -- 밝기 기준이 다르다: 배너는 진하게(위 개척자 세트처럼), 테마는
        -- 앱 전체 배경이라 반드시 밝게 — 실제 그라디언트 값은
        -- game_service.dart 의 themeGradientFor/cardBackColorsFor 에 있다.
        -- is_purchasable = FALSE 로 나가고 그대로 둔다 (custom_title_7d 등
        -- 위 feature 5종과 같은 이유): 그라디언트가 클라이언트에 하드코딩돼
        -- 있어서, 이 행이 배포된 뒤에도 앱이 구버전이면 기본 그라디언트로
        -- 떨어진다. 이 항목들을 쓸 수 있는 앱 빌드가 스토어에 올라간 뒤
        -- 어드민에서 켠다 — is_purchasable 은 ON CONFLICT 갱신 목록에 없어서
        -- 그 스위치는 이후 재부팅에도 살아남는다. 한글날 세트는 추가로
        -- sale_start/sale_end 를 걸어 판매 기간까지 좁힐 수 있다.
        ('banner_seollal', '설날 배너', '설날 배너', 'Lunar New Year Banner', 'Neujahrsfest-Banner', 'banner', 350, FALSE, FALSE, 30, FALSE, NULL, NULL, '{"visual": {"version":1,"thumbnail":{"icon":"card_giftcard","iconColor":"#E7B94C","borderColor":"#8E1F2B","background":{"kind":"gradient","angle":0,"stops":[{"color":"#8E1F2B","at":0.0},{"color":"#E7B94C","at":1.0}]}},"preview":{"background":{"kind":"gradient","angle":120,"stops":[{"color":"#7A1B27","at":0.0},{"color":"#C6303E","at":0.5},{"color":"#E7B94C","at":1.0}]}},"text":{"color":"#FFFFFF"}}}'::jsonb),
        ('theme_seollal', '설날 테마', '설날 테마', 'Lunar New Year Theme', 'Neujahrsfest-Thema', 'theme', 550, FALSE, FALSE, 30, FALSE, NULL, NULL, '{"includesCardSkin": true, "visual": {"version":1,"thumbnail":{"icon":"celebration","iconColor":"#C6303E","borderColor":"#E7B94C","background":{"kind":"gradient","angle":0,"stops":[{"color":"#FFE3DE","at":0.0},{"color":"#FCE0A8","at":1.0}]}}}}'::jsonb),
        ('banner_chuseok', '추석 배너', '추석 배너', 'Chuseok Banner', 'Chuseok-Banner', 'banner', 350, FALSE, FALSE, 30, FALSE, NULL, NULL, '{"visual": {"version":1,"thumbnail":{"icon":"park","iconColor":"#E0A83E","borderColor":"#B23A2E","background":{"kind":"gradient","angle":135,"stops":[{"color":"#B23A2E","at":0.0},{"color":"#4C8C4A","at":1.0}]}},"preview":{"background":{"kind":"gradient","angle":135,"stops":[{"color":"#B23A2E","at":0.0},{"color":"#E0A83E","at":0.5},{"color":"#4C8C4A","at":1.0}]}},"text":{"color":"#FFFFFF"}}}'::jsonb),
        ('theme_chuseok', '추석 테마', '추석 테마', 'Chuseok Theme', 'Chuseok-Thema', 'theme', 550, FALSE, FALSE, 30, FALSE, NULL, NULL, '{"includesCardSkin": true, "visual": {"version":1,"thumbnail":{"icon":"park","iconColor":"#C97A3D","borderColor":"#A9D18E","background":{"kind":"gradient","angle":135,"stops":[{"color":"#FFD6C7","at":0.0},{"color":"#FFEDAD","at":0.5},{"color":"#D7EAC0","at":1.0}]}}}}'::jsonb),
        ('banner_yearend', '연말 배너', '연말 배너', 'Year-End Banner', 'Jahresend-Banner', 'banner', 380, FALSE, FALSE, 30, FALSE, NULL, NULL, '{"visual": {"version":1,"thumbnail":{"icon":"ac_unit","iconColor":"#D4AF37","borderColor":"#123829","background":{"kind":"gradient","angle":0,"stops":[{"color":"#123829","at":0.0},{"color":"#D4AF37","at":1.0}]}},"preview":{"background":{"kind":"gradient","angle":120,"stops":[{"color":"#0F3D2E","at":0.0},{"color":"#1B4332","at":0.5},{"color":"#D4AF37","at":1.0}]}},"text":{"color":"#FFFFFF"}}}'::jsonb),
        ('theme_yearend', '연말 테마', '연말 테마', 'Year-End Theme', 'Jahresend-Thema', 'theme', 580, FALSE, FALSE, 30, FALSE, NULL, NULL, '{"includesCardSkin": true, "visual": {"version":1,"thumbnail":{"icon":"ac_unit","iconColor":"#2E7D52","borderColor":"#D4AF37","background":{"kind":"gradient","angle":0,"stops":[{"color":"#D7ECDC","at":0.0},{"color":"#EBDCA0","at":1.0}]}}}}'::jsonb),
        ('banner_gaecheonjeol', '개천절 배너', '개천절 배너', 'National Foundation Day Banner', 'Banner zum Tag der Staatsgründung', 'banner', 400, FALSE, FALSE, 30, FALSE, NULL, NULL, '{"visual": {"version":1,"thumbnail":{"icon":"auto_awesome","iconColor":"#2FD9C4","borderColor":"#1A1330","background":{"kind":"gradient","angle":0,"stops":[{"color":"#1A1330","at":0.0},{"color":"#2FD9C4","at":1.0}]}},"preview":{"background":{"kind":"gradient","angle":120,"stops":[{"color":"#1A1330","at":0.0},{"color":"#241B3A","at":0.5},{"color":"#2FD9C4","at":1.0}]}},"text":{"color":"#FFFFFF"}}}'::jsonb),
        ('theme_gaecheonjeol', '개천절 테마', '개천절 테마', 'National Foundation Day Theme', 'Thema zum Tag der Staatsgründung', 'theme', 650, FALSE, FALSE, 30, FALSE, NULL, NULL, '{"includesCardSkin": true, "visual": {"version":1,"thumbnail":{"icon":"auto_awesome","iconColor":"#5B4B9E","borderColor":"#2FD9C4","background":{"kind":"gradient","angle":0,"stops":[{"color":"#E6DAF8","at":0.0},{"color":"#C3EFE6","at":1.0}]}}}}'::jsonb),
        ('banner_christmas', '크리스마스 배너', '크리스마스 배너', 'Christmas Banner', 'Weihnachts-Banner', 'banner', 380, FALSE, FALSE, 30, FALSE, NULL, NULL, '{"visual": {"version":1,"thumbnail":{"icon":"star","iconColor":"#F4D03F","borderColor":"#7A1F2B","background":{"kind":"gradient","angle":135,"stops":[{"color":"#7A1F2B","at":0.0},{"color":"#F4D03F","at":1.0}]}},"preview":{"background":{"kind":"gradient","angle":135,"stops":[{"color":"#7A1F2B","at":0.0},{"color":"#C62828","at":0.55},{"color":"#F4D03F","at":1.0}]}},"text":{"color":"#FFFFFF"}}}'::jsonb),
        ('theme_christmas', '크리스마스 테마', '크리스마스 테마', 'Christmas Theme', 'Weihnachts-Thema', 'theme', 600, FALSE, FALSE, 30, FALSE, NULL, NULL, '{"includesCardSkin": true, "visual": {"version":1,"thumbnail":{"icon":"star","iconColor":"#C62828","borderColor":"#F4D03F","background":{"kind":"gradient","angle":135,"stops":[{"color":"#FCE4E1","at":0.0},{"color":"#FFF6EC","at":0.5},{"color":"#F5E3B8","at":1.0}]}}}}'::jsonb),
        ('banner_hangeul', '한글날 배너', '한글날 배너', 'Hangeul Day Banner', 'Hangeul-Tag-Banner', 'banner', 450, FALSE, FALSE, 30, FALSE, NULL, NULL, '{"visual": {"version":1,"thumbnail":{"icon":"workspace_premium","iconColor":"#C23B22","borderColor":"#14161F","background":{"kind":"gradient","angle":0,"stops":[{"color":"#14161F","at":0.0},{"color":"#C23B22","at":1.0}]}},"preview":{"background":{"kind":"gradient","angle":120,"stops":[{"color":"#14161F","at":0.0},{"color":"#20263D","at":0.5},{"color":"#C23B22","at":1.0}]}},"text":{"color":"#F5E9D8"}}}'::jsonb),
        ('theme_hangeul', '한글날 테마', '한글날 테마', 'Hangeul Day Theme', 'Hangeul-Tag-Thema', 'theme', 700, FALSE, FALSE, 30, FALSE, NULL, NULL, '{"includesCardSkin": true, "visual": {"version":1,"thumbnail":{"icon":"workspace_premium","iconColor":"#20263D","borderColor":"#C23B22","background":{"kind":"gradient","angle":0,"stops":[{"color":"#EDE7D8","at":0.0},{"color":"#F0C8BE","at":1.0}]}}}}'::jsonb)
      ON CONFLICT (item_key) DO UPDATE SET
        name = EXCLUDED.name_ko,
        name_ko = EXCLUDED.name_ko,
        name_en = EXCLUDED.name_en,
        name_de = EXCLUDED.name_de,
        price = EXCLUDED.price,
        is_permanent = EXCLUDED.is_permanent,
        duration_days = EXCLUDED.duration_days,
        category = EXCLUDED.category,
        effect_type = EXCLUDED.effect_type,
        effect_value = EXCLUDED.effect_value
      `
    );

    // 한글날 세트 판매기간: 10/1~10/16(양력 고정 10/9 앞뒤 2주). sale_start
    // 가 비어있을 때만 채워서, 어드민이 나중에 직접 바꾼 값이 재시작마다
    // 되돌아가지 않게 한다.
    await client.query(`
      UPDATE tc_shop_items SET sale_start = '2026-10-01 00:00:00', sale_end = '2026-10-16 23:59:59'
      WHERE item_key IN ('banner_hangeul', 'theme_hangeul') AND sale_start IS NULL
    `);

    // Shop copy. Every item needs a line saying what it actually does — an
    // empty description leaves the detail sheet with a name and a price and
    // nothing to decide on. Filled by category for the cosmetic families (they
    // differ only in the picture) and by effect_type for the functional ones.
    // Only writes where the description is blank, so admin edits stand.
    const SHOP_DESCRIPTIONS = [
      // [predicate SQL, params, ko, en, de]
      [
        `category = 'banner'`,
        [],
        '대기실과 게임 화면, 그리고 다른 사람이 보는 내 프로필 팝업의 배경으로 적용됩니다. 닉네임과 칭호 색도 배너에 맞춰 자동으로 조정됩니다.',
        'Applied as the background of your name slot in the waiting room and in game, and behind your profile popup when someone opens it. Nickname and title colours adjust to the banner automatically.',
        'Wird als Hintergrund deines Namensfelds im Warteraum und im Spiel angezeigt sowie hinter deinem Profil-Popup, wenn es jemand öffnet. Nickname- und Titelfarbe passen sich dem Banner automatisch an.',
        // The line this replaces. Without it the 33 banners already carrying
        // the old copy would keep it forever — the update below only fills
        // blanks, so that admin edits survive.
        '대기실과 게임 화면에서 내 이름 칸의 배경으로 적용됩니다. 닉네임 색도 배너에 맞춰 자동으로 조정됩니다.',
      ],
      [
        `category = 'title'`,
        [],
        '닉네임 위에 표시되는 칭호입니다. 대기실·게임·프로필 어디서나 함께 보입니다.',
        'A title shown above your nickname — in the waiting room, in game and on your profile.',
        'Ein Titel über deinem Nickname — im Warteraum, im Spiel und in deinem Profil.',
      ],
      [
        `category = 'theme'`,
        [],
        '앱 전체의 배경색과 카드 뒷면 색이 바뀝니다.',
        'Changes the app background and the card backs.',
        'Ändert den App-Hintergrund und die Kartenrückseiten.',
      ],
      [
        `effect_type = 'profile_photo'`,
        [],
        '기간 동안 내 사진을 프로필로 쓸 수 있습니다. 횟수 제한 없이 언제든 바꾸거나 삭제할 수 있고, 대기실·게임·프로필 어디서나 다른 사람에게 보입니다. (업로드한 사진은 자동 검수를 거칩니다)',
        'Use your own photo as your profile picture for the duration. Change or remove it as often as you like; it is shown to other players in the waiting room, in game and on your profile. (Uploads are screened automatically.)',
        'Nutze für die Laufzeit dein eigenes Foto als Profilbild. Beliebig oft änder- oder löschbar; es wird anderen im Warteraum, im Spiel und im Profil gezeigt. (Uploads werden automatisch geprüft.)',
      ],
      [
        `effect_type = 'custom_title'`,
        [],
        '닉네임 위에 붙는 칭호를 직접 씁니다. 한글·영문·숫자 4자까지, 색은 8가지 중에서 고를 수 있습니다. (아이콘 없이 글자만 표시되며, 부적절한 칭호는 신고를 받아 삭제될 수 있습니다)',
        'Write your own title above your nickname — up to 4 letters or digits, in one of 8 colours. (Text only, no icon; titles reported as inappropriate can be removed.)',
        'Schreibe deinen eigenen Titel über deinem Nickname — bis zu 4 Zeichen in einer von 8 Farben. (Nur Text, kein Symbol; gemeldete Titel können entfernt werden.)',
      ],
      [
        `effect_type = 'top_card_counter'`,
        [],
        '티츄 플레이 중 화면 위에 남은 A·K 장수와 용·봉황이 아직 안 나왔는지를 표시합니다.',
        'While playing Tichu, shows how many Aces and Kings are left and whether the Dragon and Phoenix are still out.',
        'Zeigt während einer Tichu-Partie, wie viele Asse und Könige noch übrig sind und ob Drache und Phönix noch im Spiel sind.',
      ],
      [
        `effect_type = 'mighty_trump_counter'`,
        [],
        '마이티 플레이 중 기루다(으뜸패) 13장 가운데 몇 장이 남았는지 표시합니다.',
        'While playing Mighty, shows how many of the 13 trump cards are still unplayed.',
        'Zeigt während einer Mighty-Partie, wie viele der 13 Trumpfkarten noch nicht gespielt wurden.',
      ],
      [
        `effect_type = 'mighty_prev_trick'`,
        [],
        '마이티에서 직전 트릭에 누가 어떤 카드를 냈는지 다시 볼 수 있습니다.',
        'In Mighty, lets you look back at who played what in the previous trick.',
        'In Mighty kannst du nachsehen, wer im vorherigen Stich was gespielt hat.',
      ],
      [
        `effect_type = 'nickname_change'`,
        [],
        '닉네임을 원하는 이름으로 한 번 바꿉니다. 친구·전적·보유 아이템은 그대로 유지됩니다.',
        'Change your nickname once. Friends, records and owned items all stay with you.',
        'Ändere deinen Nickname einmalig. Freunde, Statistiken und Gegenstände bleiben erhalten.',
      ],
      [
        `effect_type = 'leave_count_reduce'`,
        [],
        '탈주 횟수를 줄입니다. 탈주 기록은 프로필에 표시되므로 관리해 두면 좋습니다.',
        'Reduces your desertion count. The count is shown on your profile, so it is worth keeping down.',
        'Verringert deine Flucht-Zählung. Sie wird in deinem Profil angezeigt.',
      ],
      [
        `effect_type = 'leave_count_reset'`,
        [],
        '탈주 횟수를 0으로 되돌립니다.',
        'Resets your desertion count to zero.',
        'Setzt deine Flucht-Zählung auf null zurück.',
      ],
      [
        `effect_type = 'stats_reset'`,
        [],
        '모든 게임의 일반전 전적(판수·승패)을 0으로 되돌립니다. 랭킹 점수와 레벨은 그대로입니다.',
        'Resets your casual records (games, wins, losses) for every game to zero. Ranked rating and level are untouched.',
        'Setzt deine Freundschaftsspiel-Statistiken (Spiele, Siege, Niederlagen) aller Spiele auf null. Ranglistenwertung und Level bleiben.',
      ],
      [
        `effect_type IN ('season_stats_reset', 'tichu_season_stats_reset', 'sk_season_stats_reset', 'mighty_season_stats_reset')`,
        [],
        '해당 게임의 이번 시즌 랭킹 전적을 초기화하고 점수를 시작값으로 되돌립니다.',
        "Clears this season's ranked record for that game and returns the rating to its starting value.",
        'Löscht die Ranglisten-Bilanz dieser Saison für das jeweilige Spiel und setzt die Wertung zurück.',
      ],
    ];
    for (const [predicate, params, ko, en, de, supersedes] of SHOP_DESCRIPTIONS) {
      // Blank descriptions always get filled. `supersedes` additionally
      // replaces one specific older default — the way to correct copy that has
      // already shipped without trampling anything an admin wrote, since
      // anything else in the column is by definition not the old default.
      await client.query(
        `UPDATE tc_shop_items
         SET description_ko = $1, description_en = $2, description_de = $3
         WHERE ${predicate}
           AND (description_ko IS NULL OR description_ko = ''
                OR ($4::text IS NOT NULL AND description_ko = $4))`,
        [ko, en, de, supersedes ?? null, ...params],
      );
    }

    // What the pass does belongs on the shop page, where someone decides
    // whether to buy it — not crammed into the profile panel afterwards.
    // Only fills a blank description, so an admin edit is never overwritten.
    await client.query(`
      UPDATE tc_shop_items SET
        description_ko = '친구가 아닌 사람에게는 전적·레벨·매너지수 등 프로필 정보가 보이지 않습니다. 프로필 사진은 그대로 공개되며, 내 프로필에서 ''사진 비공개''를 켜면 대기실과 게임 화면에 보이는 사진까지 숨겨집니다.',
        description_en = 'People who are not your friends cannot see your records, level or manner score. Your profile photo stays visible; turn on "Hide photo" in your profile and it is hidden too, in the waiting room and in game.',
        description_de = 'Nicht-Freunde sehen weder Statistiken noch Level oder Manier-Punkte. Dein Profilbild bleibt sichtbar; aktiviere „Foto verbergen“ in deinem Profil, und es wird auch im Warteraum und im Spiel verborgen.'
      WHERE item_key IN ('profile_private_7d', 'profile_private_30d')
        AND (description_ko IS NULL OR description_ko = ''
             OR description_ko LIKE '%사진까지 숨길 수 있습니다%')`);

    // Backfill metadata.visual for items shipped without it. Only writes when
    // metadata.visual is missing, so admin edits made later are never
    // clobbered on subsequent boots.
    await backfillShopVisuals(client);

    // Tiered level curve. Replaces the old linear formula
    // (level = floor(exp / 100) + 1) with a per-tier progression:
    //   Lv 1–9   cost = 100 + (L-1)*5    (100, 105, ..., 140)
    //   Lv 10–19 cost = 150 + (L-10)*10  (150, ..., 240)
    //   Lv 20–29 cost = 260 + (L-20)*20  (260, ..., 440)
    //   Lv 30–39 cost = 480 + (L-30)*40  (480, ..., 840)
    //   Lv 40+   cost = 920 + (L-40)*80
    // CREATE OR REPLACE so updates to the curve redeploy without a migration.
    // Marked IMMUTABLE so PostgreSQL can fold it inside UPDATE expressions.
    await client.query(`
      CREATE OR REPLACE FUNCTION tc_compute_level(p_exp INT) RETURNS INT AS $$
      DECLARE
        v_level INT := 1;
        v_remaining INT := GREATEST(0, COALESCE(p_exp, 0));
        v_cost INT;
      BEGIN
        LOOP
          IF v_level BETWEEN 1 AND 9 THEN v_cost := 100 + (v_level - 1) * 5;
          ELSIF v_level BETWEEN 10 AND 19 THEN v_cost := 150 + (v_level - 10) * 10;
          ELSIF v_level BETWEEN 20 AND 29 THEN v_cost := 260 + (v_level - 20) * 20;
          ELSIF v_level BETWEEN 30 AND 39 THEN v_cost := 480 + (v_level - 30) * 40;
          ELSE v_cost := 920 + (v_level - 40) * 80;
          END IF;
          EXIT WHEN v_remaining < v_cost;
          v_remaining := v_remaining - v_cost;
          v_level := v_level + 1;
        END LOOP;
        RETURN v_level;
      END;
      $$ LANGUAGE plpgsql IMMUTABLE;
    `);

    // One-shot backfill: rederive every user's level from their current
    // exp_total. Cheap (single UPDATE, no migration row). The function is
    // IMMUTABLE so PG can compute it per row efficiently. Safe to run on
    // every boot — converges to the same answer.
    await client.query(`UPDATE tc_users SET level = tc_compute_level(exp_total) WHERE level IS DISTINCT FROM tc_compute_level(exp_total)`);

    // Ad rewards table
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_ad_rewards (
        id SERIAL PRIMARY KEY,
        nickname VARCHAR(50) NOT NULL,
        claimed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_gold_history (
        id SERIAL PRIMARY KEY,
        nickname VARCHAR(50) NOT NULL,
        gold_delta INT NOT NULL,
        source VARCHAR(30) NOT NULL,
        title VARCHAR(100) NOT NULL,
        description TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    // DM messages table
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_dm_messages (
        id SERIAL PRIMARY KEY,
        sender_nickname VARCHAR(50) NOT NULL,
        receiver_nickname VARCHAR(50) NOT NULL,
        message TEXT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        read_at TIMESTAMP
      )
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_dm_participants
      ON tc_dm_messages (sender_nickname, receiver_nickname, created_at DESC)
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_dm_unread
      ON tc_dm_messages (receiver_nickname, read_at) WHERE read_at IS NULL
    `);
    // idx_dm_participants leads with sender_nickname, so a query asking
    // "everything involving this person" — sender = $1 OR receiver = $1 —
    // could only use it for half the OR and scanned the table for the other
    // half. The backstage's conversation list does exactly that, and it runs
    // on every user detail page.
    //
    // idx_dm_unread cannot stand in: it is partial (WHERE read_at IS NULL) and
    // so is unusable for a general receiver lookup.
    //
    // One column is enough. Measured at 50k rows: the partner list goes from a
    // 7.4 ms sequential scan to 0.3 ms, and widening this to
    // (receiver, sender, created_at) bought nothing over it while costing
    // three times the index.
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_dm_by_receiver
      ON tc_dm_messages (receiver_nickname)
    `);

    // ===== Skull King Tables =====
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_sk_match_history (
        id SERIAL PRIMARY KEY,
        player_count INT NOT NULL,
        is_ranked BOOLEAN DEFAULT FALSE,
        end_reason VARCHAR(20) DEFAULT 'normal',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_sk_match_players (
        id SERIAL PRIMARY KEY,
        match_id INT NOT NULL REFERENCES tc_sk_match_history(id),
        nickname VARCHAR(50) NOT NULL,
        score INT NOT NULL,
        rank INT NOT NULL,
        is_winner BOOLEAN DEFAULT FALSE,
        is_bot BOOLEAN DEFAULT FALSE
      )
    `);

    await client.query(`ALTER TABLE tc_sk_match_history ADD COLUMN IF NOT EXISTS deserter_nickname VARCHAR(50)`);

    // ===== Love Letter Tables =====
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_ll_match_history (
        id SERIAL PRIMARY KEY,
        player_count INT NOT NULL,
        is_ranked BOOLEAN DEFAULT FALSE,
        end_reason VARCHAR(20) DEFAULT 'normal',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_ll_match_players (
        id SERIAL PRIMARY KEY,
        match_id INT NOT NULL REFERENCES tc_ll_match_history(id),
        nickname VARCHAR(50) NOT NULL,
        score INT NOT NULL,
        rank INT NOT NULL,
        is_winner BOOLEAN DEFAULT FALSE,
        is_bot BOOLEAN DEFAULT FALSE
      )
    `);

    await client.query(`ALTER TABLE tc_ll_match_history ADD COLUMN IF NOT EXISTS deserter_nickname VARCHAR(50)`);

    // ===== Mighty Tables =====
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_mighty_match_history (
        id SERIAL PRIMARY KEY,
        player_count INT NOT NULL,
        is_ranked BOOLEAN DEFAULT FALSE,
        end_reason VARCHAR(20) DEFAULT 'normal',
        declarer_nickname VARCHAR(50),
        partner_nickname VARCHAR(50),
        declarer_team_success BOOLEAN,
        declarer_team_points INT DEFAULT 0,
        bid_points INT DEFAULT 0,
        trump_suit VARCHAR(20),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_mighty_match_players (
        id SERIAL PRIMARY KEY,
        match_id INT NOT NULL REFERENCES tc_mighty_match_history(id),
        nickname VARCHAR(50) NOT NULL,
        score INT NOT NULL,
        rank INT NOT NULL,
        is_winner BOOLEAN DEFAULT FALSE,
        is_bot BOOLEAN DEFAULT FALSE
      )
    `);

    await client.query(`ALTER TABLE tc_mighty_match_history ADD COLUMN IF NOT EXISTS deserter_nickname VARCHAR(50)`);

    // Recent-matches lookup indexes. MUST be here — after ALL match tables
    // (tichu/sk/ll/mighty) exist — or CREATE INDEX errors on a missing table
    // and aborts initDatabase before server.listen() (boot failure).
    // Without these, "WHERE player=$1 ORDER BY created_at DESC LIMIT 20"
    // full-scans history every profile open and degrades as data grows.
    // Non-concurrent (matches existing pattern); one-time, IF NOT EXISTS no-ops.
    await client.query(`CREATE INDEX IF NOT EXISTS idx_mh_a1_created ON tc_match_history (player_a1, created_at DESC)`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_mh_a2_created ON tc_match_history (player_a2, created_at DESC)`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_mh_b1_created ON tc_match_history (player_b1, created_at DESC)`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_mh_b2_created ON tc_match_history (player_b2, created_at DESC)`);
    for (const g of ['sk', 'll', 'mighty']) {
      await client.query(`CREATE INDEX IF NOT EXISTS idx_${g}mh_created ON tc_${g}_match_history (created_at DESC)`);
      await client.query(`CREATE INDEX IF NOT EXISTS idx_${g}mp_nick_match ON tc_${g}_match_players (nickname, match_id)`);
      await client.query(`CREATE INDEX IF NOT EXISTS idx_${g}mp_match ON tc_${g}_match_players (match_id)`);
    }

    // LL user stats columns
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS ll_total_games INT DEFAULT 0`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS ll_wins INT DEFAULT 0`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS ll_losses INT DEFAULT 0`);

    // Mighty user stats columns
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS mighty_total_games INT DEFAULT 0`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS mighty_wins INT DEFAULT 0`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS mighty_losses INT DEFAULT 0`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS mighty_rating INT DEFAULT 1000`);

    // Mighty season stats columns
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS mighty_season_rating INT DEFAULT 1000`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS mighty_season_games INT DEFAULT 0`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS mighty_season_wins INT DEFAULT 0`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS mighty_season_losses INT DEFAULT 0`);

    // SK user stats columns
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS sk_total_games INT DEFAULT 0`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS sk_wins INT DEFAULT 0`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS sk_losses INT DEFAULT 0`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS sk_rating INT DEFAULT 1000`);

    // SK season stats columns
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS sk_season_rating INT DEFAULT 1000`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS sk_season_games INT DEFAULT 0`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS sk_season_wins INT DEFAULT 0`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS sk_season_losses INT DEFAULT 0`);

    // Persistent card-view policy: how the user's cards may be shown to
    // spectators. 'ask' (default) prompts each time. 'always_allow' /
    // 'always_deny' bypass the prompt across games/sessions.
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS card_view_pref VARCHAR(20) NOT NULL DEFAULT 'ask'`);

    // Add game_type to season rankings for SK support
    await client.query(`ALTER TABLE tc_season_rankings ADD COLUMN IF NOT EXISTS game_type VARCHAR(20) DEFAULT 'tichu'`);
    // Drop old unique constraint and add new one with game_type
    await client.query(`
      DO $$ BEGIN
        IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'tc_season_rankings_season_id_rank_key') THEN
          ALTER TABLE tc_season_rankings DROP CONSTRAINT tc_season_rankings_season_id_rank_key;
        END IF;
      END $$
    `);
    await client.query(`
      CREATE UNIQUE INDEX IF NOT EXISTS tc_season_rankings_season_game_rank_idx
      ON tc_season_rankings (season_id, game_type, rank)
    `);

    // 같은 달 시즌이 두 번 만들어지지 않게.
    //
    // createSeason 은 평범한 INSERT 였고 tc_seasons 에는 유니크 제약이 없었다.
    // ensureSeasonCycle 은 _seasonCycleRunning 으로 프로세스 안에서만 잠기므로,
    // 부팅과 시간별 타이머가 겹치거나 배포 교체로 인스턴스가 잠깐 둘이 되면
    // 같은 이름의 'active' 시즌이 그대로 여러 줄 쌓인다.
    //
    // 유니크 인덱스가 본체다. 이미 중복이 있는 DB에서는 인덱스를 만들 수 없어
    // 부팅이 깨지므로, 그 경우에만 여분을 'closed' 로 내려 인덱스를 만들 수
    // 있게 한다 — 지우지는 않는다. 어느 줄에 랭킹·지급이 붙어 있을지 여기서
    // 판단할 일이 아니고, 남은 줄은 관리 화면에서 눈으로 확인하면 된다.
    const dupSeasons = await client.query(
      `SELECT name, COUNT(*)::int AS n FROM tc_seasons GROUP BY name HAVING COUNT(*) > 1`,
    );
    if (dupSeasons.rows.length > 0) {
      console.warn('[season] 이름이 겹치는 시즌 발견:',
        dupSeasons.rows.map((r) => `${r.name}×${r.n}`).join(', '),
        '— 가장 오래된 것만 진행 중으로 두고 나머지는 종료 처리합니다.');
      await client.query(`
        WITH dup AS (
          SELECT id, ROW_NUMBER() OVER (PARTITION BY name ORDER BY id) AS rn
          FROM tc_seasons WHERE status = 'active'
        )
        UPDATE tc_seasons SET status = 'closed'
        FROM dup WHERE tc_seasons.id = dup.id AND dup.rn > 1
      `);
    } else {
      await client.query(
        `CREATE UNIQUE INDEX IF NOT EXISTS tc_seasons_name_idx ON tc_seasons (name)`,
      );
    }

    // Notices table
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_notices (
        id SERIAL PRIMARY KEY,
        category VARCHAR(20) DEFAULT 'general',
        title VARCHAR(200) NOT NULL,
        content TEXT NOT NULL,
        is_pinned BOOLEAN DEFAULT FALSE,
        status VARCHAR(20) DEFAULT 'draft',
        published_at TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);
    // A notice can carry a coupon: the post announces it and the reader
    // redeems from the same screen. Has to sit here rather than up with the
    // coupon tables — on a database that already has tc_notices the order
    // makes no difference, but on an empty one the ALTER ran first and threw,
    // which aborts the whole migration and the server never starts.
    await client.query(`ALTER TABLE tc_notices ADD COLUMN IF NOT EXISTS coupon_code VARCHAR(40)`);
    // 제목 글씨색. 자유 입력이 아니라 팔레트 id 를 담는다(moderation/customTitle
    // 의 TITLE_COLORS) — 임의의 hex 를 받으면 배경과 같은 색이나 읽을 수 없는
    // 색이 들어올 수 있고, 그걸 막는 검사를 또 만들어야 한다.
    // NULL = 기본 색.
    await client.query(`ALTER TABLE tc_notices ADD COLUMN IF NOT EXISTS title_color VARCHAR(16)`);

    // Maintenance history table
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_maintenance_history (
        id SERIAL PRIMARY KEY,
        action VARCHAR(20) NOT NULL,
        notice_start TIMESTAMP,
        notice_end TIMESTAMP,
        maintenance_start TIMESTAMP,
        maintenance_end TIMESTAMP,
        message_ko TEXT,
        message_en TEXT,
        message_de TEXT,
        admin_user VARCHAR(50),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    // Push notification history table
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_push_history (
        id SERIAL PRIMARY KEY,
        admin_username VARCHAR(50) NOT NULL,
        title VARCHAR(200) NOT NULL,
        body TEXT NOT NULL,
        target_filter VARCHAR(20) DEFAULT 'all',
        total_sent INTEGER DEFAULT 0,
        success_count INTEGER DEFAULT 0,
        fail_count INTEGER DEFAULT 0,
        invalid_tokens INTEGER DEFAULT 0,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    // Push notification recipients table
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_push_recipients (
        id SERIAL PRIMARY KEY,
        push_history_id INTEGER NOT NULL REFERENCES tc_push_history(id),
        user_id INTEGER NOT NULL,
        nickname VARCHAR(50) NOT NULL,
        status VARCHAR(20) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_push_recipients_history ON tc_push_recipients(push_history_id)`);

    // 운영자 우편함. A message the staff send to a player — with a reward
    // attached if they want one — that waits in the app until it is read.
    //
    // Not the inquiry table: an inquiry is a thread the PLAYER opened and it
    // has no notion of a payout. Not a notice either: a notice is the same
    // text for everybody with no per-person state. What is per-person here is
    // exactly what makes it a mailbox — read, and claimed.
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_mail (
        id SERIAL PRIMARY KEY,
        title VARCHAR(200) NOT NULL,
        body TEXT NOT NULL,
        reward_gold INTEGER DEFAULT 0,
        reward_item_key VARCHAR(80),
        reward_days INT,
        -- Claim deadline, stored UTC. NULL = no deadline. After it passes the
        -- letter still reads; only the reward is closed.
        expires_at TIMESTAMP,
        -- Who it reads as. NULL = the app's own localized default ("티츄
        -- 온라인 운영팀" / "Tichu Online Team" / …), which is what almost
        -- every letter wants; a value here overrides it for one letter, for
        -- when the sender is a person or an event rather than the team.
        sender_name VARCHAR(60),
        target_kind VARCHAR(10) DEFAULT 'user',
        target_note VARCHAR(200),
        created_by VARCHAR(50),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);
    // One row per addressee, written at send time even for a mail to everyone
    // (a few hundred rows). The alternative — deriving the audience at read
    // time — cannot answer "who has read it" and would silently widen the
    // audience as new accounts appear.
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_mail_recipients (
        id SERIAL PRIMARY KEY,
        mail_id INTEGER NOT NULL REFERENCES tc_mail(id) ON DELETE CASCADE,
        nickname VARCHAR(50) NOT NULL,
        read_at TIMESTAMP,
        claimed_at TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE (mail_id, nickname)
      )
    `);
    await client.query(`ALTER TABLE tc_mail ADD COLUMN IF NOT EXISTS sender_name VARCHAR(60)`);
    // Filled in when the addressee rows are purged (see purgeOldMail), so the
    // backstage still knows how far a letter got after the copies are gone.
    await client.query(`ALTER TABLE tc_mail ADD COLUMN IF NOT EXISTS final_recipients INT`);
    await client.query(`ALTER TABLE tc_mail ADD COLUMN IF NOT EXISTS final_read INT`);
    await client.query(`ALTER TABLE tc_mail ADD COLUMN IF NOT EXISTS final_claimed INT`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_mail_recipient_box
      ON tc_mail_recipients (nickname, created_at DESC)`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_mail_recipient_unread
      ON tc_mail_recipients (nickname) WHERE read_at IS NULL`);
    // 사용자가 우편을 지워도 배달 기록은 남긴다. 행을 지우면 어드민의
    // "보낸 편지" 통계가 시간이 갈수록 줄어든다 — 받은 사람이 자기 우편함을
    // 정리했다는 이유로 "몇 명에게 갔는지" 가 바뀌면 안 된다.
    await client.query(
      `ALTER TABLE tc_mail_recipients ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP`);

    // Every push that goes to ONE user: a friend request, an inquiry reply, a
    // gold grant, an admin's one-off message. None of these were recorded
    // anywhere, so "did the notification actually go out?" had no answer.
    //
    // One row per notification, unlike the two broadcast tables which keep one
    // row per SEND and count their recipients separately. Individual pushes
    // are low volume by nature (they follow a human action), and the row is
    // what makes the unified history page able to show them at all.
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_push_log (
        id SERIAL PRIMARY KEY,
        -- 'system' = the server sent it off the back of an event,
        -- 'admin_direct' = a person typed it on the user detail page.
        kind VARCHAR(20) NOT NULL DEFAULT 'system',
        event VARCHAR(40),
        nickname VARCHAR(50),
        title VARCHAR(200),
        body TEXT,
        success BOOLEAN,
        error TEXT,
        actor VARCHAR(50),
        opened_at TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_push_log_created ON tc_push_log (created_at DESC)`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_push_log_nickname ON tc_push_log (nickname, created_at DESC)`);
    // Taps, for the broadcast side. The per-recipient row carries the tap and
    // the summary carries the count, because the recipient rows are the ones
    // that get purged (see purgePushLogs) and the number has to outlive them.
    await client.query(`ALTER TABLE tc_push_recipients ADD COLUMN IF NOT EXISTS opened_at TIMESTAMP`);
    await client.query(`ALTER TABLE tc_push_history ADD COLUMN IF NOT EXISTS opened_count INTEGER DEFAULT 0`);

    // Marketing campaigns: a push that pays out when it is tapped.
    //
    // Separate from tc_push_history, which records an admin broadcast and
    // nothing else. A campaign has to survive the send — the reward is claimed
    // minutes or days later, by a client that only knows the campaign id.
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_push_campaigns (
        id SERIAL PRIMARY KEY,
        title VARCHAR(200) NOT NULL,
        body TEXT NOT NULL,
        reward_gold INTEGER DEFAULT 0,
        reward_item_key VARCHAR(80),
        reward_days INT,
        -- After this, taps still open the app but pay nothing. Stored UTC.
        claim_deadline TIMESTAMP,
        status VARCHAR(20) DEFAULT 'draft',
        target_filter VARCHAR(20) DEFAULT 'all',
        sent_at TIMESTAMP,
        sent_count INTEGER DEFAULT 0,
        fail_count INTEGER DEFAULT 0,
        created_by VARCHAR(50),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    // One row per person the campaign was sent to.
    //
    // This is what makes the reward safe: a claim is only honoured if the
    // claimer has a row here. Without it, anyone who learned a campaign id
    // could collect. It is also the only way to count opens and claims, which
    // a topic send cannot do at all.
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_push_campaign_recipients (
        id SERIAL PRIMARY KEY,
        campaign_id INTEGER NOT NULL REFERENCES tc_push_campaigns(id) ON DELETE CASCADE,
        nickname VARCHAR(50) NOT NULL,
        status VARCHAR(20) NOT NULL,
        opened_at TIMESTAMP,
        claimed_at TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE (campaign_id, nickname)
      )
    `);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_campaign_recipients_campaign
      ON tc_push_campaign_recipients(campaign_id)`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_campaign_recipients_nickname
      ON tc_push_campaign_recipients(nickname)`);

    console.log('Database initialized (tc_ tables)');
  } catch (err) {
    // 예전에는 로그만 찍고 계속 떴다. 그러면 실패한 문장 뒤의 마이그레이션이
    // 통째로 건너뛰어진 채 서버가 "정상"으로 보이고, 빠진 것이 무엇인지는
    // 그 기능을 실제로 쓸 때(예: 시즌 종료일)에야 드러난다.
    //
    // 여기서 죽으면 /health 가 초록이 되지 않아 배포가 스왑을 포기하고 옛
    // 슬롯이 그대로 서비스한다. 반쪽 스키마로 트래픽을 받는 것보다 낫다.
    console.error('[FATAL] 데이터베이스 마이그레이션 실패 — 부팅을 중단합니다.');
    console.error(err);
    throw err;
  } finally {
    if (lockHeld) {
      await client.query('SELECT pg_advisory_unlock($1)', [MIGRATION_LOCK_KEY])
        .catch(() => {});
    }
    client.release();
  }
}

// Register a new user
async function registerUser(username, password, nickname) {
  // Validate username
  if (!username || username.length < 2) {
    return { success: false, messageKey: 'db_username_too_short' };
  }
  if (/\s/.test(username)) {
    return { success: false, messageKey: 'db_username_no_space' };
  }

  // Validate password
  if (!password || password.length < 4) {
    return { success: false, messageKey: 'db_password_too_short' };
  }

  // Validate nickname
  if (!nickname || nickname.trim().length < 1) {
    return { success: false, messageKey: 'db_nickname_required' };
  }
  const trimmedNickname = nickname.trim();
  if (trimmedNickname.length < 2 || trimmedNickname.length > 10) {
    return { success: false, messageKey: 'db_nickname_length' };
  }
  if (/\s/.test(trimmedNickname)) {
    return { success: false, messageKey: 'db_nickname_no_space' };
  }

  const client = await pool.connect();
  try {
    // Check if username exists
    const usernameCheck = await client.query(
      'SELECT id FROM tc_users WHERE username = $1',
      [username.toLowerCase()]
    );
    if (usernameCheck.rows.length > 0) {
      return { success: false, messageKey: 'db_username_taken' };
    }

    // Check if nickname exists
    const nicknameCheck = await client.query(
      'SELECT id FROM tc_users WHERE nickname = $1',
      [trimmedNickname]
    );
    if (nicknameCheck.rows.length > 0) {
      return { success: false, messageKey: 'db_nickname_taken' };
    }

    // Hash password and insert
    const passwordHash = await bcrypt.hash(password, SALT_ROUNDS);
    await client.query(
      'INSERT INTO tc_users (username, password_hash, nickname) VALUES ($1, $2, $3)',
      [username.toLowerCase(), passwordHash, trimmedNickname]
    );

    return { success: true, messageKey: 'db_register_success' };
  } catch (err) {
    console.error('Registration error:', err);
    return { success: false, messageKey: 'db_register_error' };
  } finally {
    client.release();
  }
}

// Login user
async function loginUser(username, password) {
  if (!username || !password) {
    return { success: false, messageKey: 'db_login_required_fields' };
  }

  const client = await pool.connect();
  try {
    const result = await client.query(
      'SELECT id, password_hash, nickname, is_admin, is_deleted, push_enabled, push_friend_invite, push_attendance, push_admin_inquiry, push_admin_report, push_admin_payment, marketing_push_enabled, marketing_asked_at, marketing_consent_at, marketing_confirmed_at FROM tc_users WHERE username = $1',
      [username.toLowerCase()]
    );

    if (result.rows.length === 0) {
      return { success: false, messageKey: 'db_username_not_found' };
    }

    const user = result.rows[0];

    if (user.is_deleted) {
      return { success: false, messageKey: 'db_account_deleted' };
    }

    const passwordMatch = await bcrypt.compare(password, user.password_hash);

    if (!passwordMatch) {
      return { success: false, messageKey: 'db_wrong_password' };
    }

    // Update last login
    await client.query(
      `UPDATE tc_users
       SET last_login = CURRENT_TIMESTAMP,
           last_seen_at = (NOW() AT TIME ZONE 'UTC')
       WHERE id = $1`,
      [user.id]
    );

    return {
      success: true,
      userId: user.id,
      nickname: user.nickname,
      isAdmin: user.is_admin === true,
      pushEnabled: user.push_enabled !== false,
      pushFriendInvite: user.push_friend_invite !== false,
      pushAttendance: user.push_attendance !== false,
      pushAdminInquiry: user.push_admin_inquiry !== false,
      pushAdminReport: user.push_admin_report !== false,
      pushAdminPayment: user.push_admin_payment !== false,
      marketingPushEnabled: user.marketing_push_enabled === true,
      // Never asked is not the same as declined, and only the first of those
      // should raise the consent popup.
      marketingAsked: user.marketing_asked_at != null,
      // 정보통신망법 §50 ⑧: confirm the subscription every two years.
      marketingConfirmDue:
        user.marketing_push_enabled === true
        && _marketingConfirmOverdue(
          user.marketing_confirmed_at || user.marketing_consent_at),
      marketingConsentAt: user.marketing_consent_at || null,
    };
  } catch (err) {
    console.error('Login error:', err);
    return { success: false, messageKey: 'db_login_error' };
  } finally {
    client.release();
  }
}

// Check if nickname is available
async function checkNickname(nickname) {
  if (!nickname || nickname.trim().length < 1) {
    return { available: false, messageKey: 'db_nickname_required' };
  }
  const trimmedNickname = nickname.trim();
  if (trimmedNickname.length < 2 || trimmedNickname.length > 10) {
    return { available: false, messageKey: 'db_nickname_length' };
  }
  if (/\s/.test(trimmedNickname)) {
    return { available: false, messageKey: 'db_nickname_no_space' };
  }

  const client = await pool.connect();
  try {
    const result = await client.query(
      'SELECT id FROM tc_users WHERE nickname = $1',
      [trimmedNickname]
    );
    const available = result.rows.length === 0;
    return {
      available,
      messageKey: available ? 'db_nickname_available' : 'db_nickname_taken',
    };
  } catch (err) {
    console.error('Nickname check error:', err);
    return { available: false, messageKey: 'db_nickname_check_error' };
  } finally {
    client.release();
  }
}

// Delete user account
// The profile photo object has to be deleted from storage too, and only this
// function knows its key — so hand it back and let the caller (which has the
// storage client) remove it. Without that the image outlives the account: the
// row goes, the key with it, and a picture of someone who asked to be deleted
// sits in a publicly readable bucket forever.
async function deleteUser(nickname) {
  if (!nickname) {
    return { success: false, messageKey: 'db_nickname_needed' };
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const check = await client.query('SELECT id FROM tc_users WHERE nickname = $1', [nickname]);
    if (check.rowCount === 0) {
      await client.query('ROLLBACK');
      return { success: false, messageKey: 'db_user_not_found' };
    }

    // Soft delete: rename nickname, mark as deleted
    // Keep match history, reports, inquiries for data integrity
    const ts = Date.now().toString(36); // short timestamp (base36)
    const suffix = `_del_${ts}`;
    const deletedNickname = (nickname + suffix).slice(0, 50);

    // Clean up personal relationship data only
    const photoRow = await client.query(
      'SELECT profile_photo_key FROM tc_users WHERE nickname = $1',
      [nickname],
    );
    const photoKey = photoRow.rows[0]?.profile_photo_key || null;

    await client.query('DELETE FROM tc_blocked_users WHERE blocker_nickname = $1 OR blocked_nickname = $1', [nickname]);
    await client.query('DELETE FROM tc_friends WHERE user_nickname = $1 OR friend_nickname = $1', [nickname]);
    await client.query('DELETE FROM tc_dm_messages WHERE sender_nickname = $1 OR receiver_nickname = $1', [nickname]);
    await client.query('DELETE FROM tc_user_equips WHERE nickname = $1', [nickname]);
    await client.query('DELETE FROM tc_user_items WHERE nickname = $1', [nickname]);
    // The nickname becomes available again, and these rows are keyed by it —
    // whoever takes it next would inherit this account's switched-off passes.
    await client.query('DELETE FROM tc_user_feature_off WHERE nickname = $1', [nickname]);
    await client.query('DELETE FROM tc_ad_rewards WHERE nickname = $1', [nickname]);
    await client.query('DELETE FROM tc_season_rewards WHERE nickname = $1', [nickname]);

    // Rename nickname in user record and mark deleted
    await client.query(
      `UPDATE tc_users SET nickname = $2, is_deleted = true, deleted_at = NOW(),
       username = SUBSTRING('del_' || username || $3 FROM 1 FOR 50),
       password_hash = '',
       -- The object is deleted by the caller, so leaving the pointer behind
       -- would only describe a file that no longer exists — and it kept the
       -- row showing up in the moderation gallery as a broken thumbnail.
       profile_photo_key = NULL,
       profile_photo_status = 'none',
       auth_provider = CASE WHEN auth_provider IS NOT NULL THEN SUBSTRING('del_' || auth_provider FROM 1 FOR 20) ELSE NULL END,
       provider_uid = CASE WHEN provider_uid IS NOT NULL THEN SUBSTRING('del_' || provider_uid || $3 FROM 1 FOR 100) ELSE NULL END,
       fcm_token = NULL
       WHERE nickname = $1`,
      [nickname, deletedNickname, suffix]
    );

    // Preserved records keep the ORIGINAL nickname for clean display:
    // tc_match_history, tc_sk_match_players, tc_sk_match_history,
    // tc_season_rankings, tc_gold_history, tc_reports, tc_inquiries

    await client.query('COMMIT');
    return { success: true, messageKey: 'db_account_deleted_success', photoKey };
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Delete user error:', err);
    return { success: false, messageKey: 'db_delete_account_error' };
  } finally {
    client.release();
  }
}

// Block user
async function blockUser(blockerNickname, blockedNickname) {
  const client = await pool.connect();
  try {
    await client.query(
      'INSERT INTO tc_blocked_users (blocker_nickname, blocked_nickname) VALUES ($1, $2) ON CONFLICT DO NOTHING',
      [blockerNickname, blockedNickname]
    );
    return { success: true };
  } catch (err) {
    console.error('Block user error:', err);
    return { success: false };
  } finally {
    client.release();
  }
}

// Unblock user
async function unblockUser(blockerNickname, blockedNickname) {
  const client = await pool.connect();
  try {
    await client.query(
      'DELETE FROM tc_blocked_users WHERE blocker_nickname = $1 AND blocked_nickname = $2',
      [blockerNickname, blockedNickname]
    );
    return { success: true };
  } catch (err) {
    console.error('Unblock user error:', err);
    return { success: false };
  } finally {
    client.release();
  }
}

// Get blocked users list
async function getBlockedUsers(nickname) {
  const client = await pool.connect();
  try {
    const result = await client.query(
      'SELECT blocked_nickname FROM tc_blocked_users WHERE blocker_nickname = $1',
      [nickname]
    );
    return result.rows.map(r => r.blocked_nickname);
  } catch (err) {
    console.error('Get blocked users error:', err);
    return [];
  } finally {
    client.release();
  }
}

// Report user
// Everyone this user has reported. Their profile photos are hidden from the
// reporter on sight — a UGC image someone has just flagged must not keep
// showing up in front of them while the report sits in a queue.
async function getReportedNicknames(reporterNickname) {
  const client = await pool.connect();
  try {
    const result = await client.query(
      'SELECT DISTINCT reported_nickname FROM tc_reports WHERE reporter_nickname = $1',
      [reporterNickname],
    );
    return result.rows.map((r) => r.reported_nickname);
  } finally {
    client.release();
  }
}

// Every photo key this reporter has reported. The hide follows the key: a new
// upload has a new key and shows again.
async function getReportedPhotoKeys(reporterNickname) {
  // reason_code = 'photo' only: the key is snapshotted on every report as
  // evidence for the admin queue, but a report about someone's chat should not
  // take their picture away from the reporter.
  const result = await pool.query(
    `SELECT DISTINCT reported_photo_key FROM tc_reports
      WHERE reporter_nickname = $1 AND reported_photo_key IS NOT NULL
        AND reason_code = 'photo'`,
    [reporterNickname]
  );
  return result.rows.map((r) => r.reported_photo_key);
}

/**
 * Titles this reporter objected to, as `nickname\u0000title` pairs.
 *
 * Keyed to the text, not the person, exactly like photos: write a different
 * title and it shows again.
 */
async function getReportedTitles(reporterNickname) {
  const result = await pool.query(
    `SELECT DISTINCT reported_nickname, reported_title FROM tc_reports
      WHERE reporter_nickname = $1 AND reported_title IS NOT NULL`,
    [reporterNickname],
  );
  return result.rows.map((r) => `${r.reported_nickname}\u0000${r.reported_title}`);
}

// Is this object referenced by any report? If so it is evidence and must not be
// deleted from storage, no matter who asks (owner, expiry sweep, admin clear).
async function isPhotoKeyReported(key) {
  if (!key) return false;
  const result = await pool.query(
    `SELECT 1 FROM tc_reports WHERE reported_photo_key = $1 LIMIT 1`,
    [key]
  );
  return result.rows.length > 0;
}

async function reportUser(
  reporterNickname,
  reportedNickname,
  reason,
  roomId,
  chatContext = [],
  reasonCode = null,
) {
  const client = await pool.connect();
  try {
    // Check for duplicate report (same reporter + target + room + reason)
    const existing = await client.query(
      'SELECT id FROM tc_reports WHERE reporter_nickname = $1 AND reported_nickname = $2 AND room_id = $3 AND reason = $4',
      [reporterNickname, reportedNickname, roomId, reason]
    );
    if (existing.rows.length > 0) {
      return { success: false, messageKey: 'db_report_duplicate' };
    }

    const chatContextJson = JSON.stringify(chatContext);
    // Snapshot whatever photo the target is showing right now. The report is
    // about THIS image: hiding follows the key (not the person), and the admin
    // can still see the reported image after the owner swaps or deletes it.
    const snap = await client.query(
      `SELECT u.profile_photo_key, u.custom_title_text, e.title_key
       FROM tc_users u
       LEFT JOIN tc_user_equips e ON e.nickname = u.nickname
       WHERE u.nickname = $1`,
      [reportedNickname]
    );
    const photoKey = snap.rows[0]?.profile_photo_key || null;
    // Only a user-written title is reportable content; a catalog title is ours.
    const wornCustom = (snap.rows[0]?.title_key || '').startsWith('custom:');
    const titleText = wornCustom
      ? (snap.rows[0]?.custom_title_text || null)
      : null;
    await client.query(
      `INSERT INTO tc_reports
        (reporter_nickname, reported_nickname, reason, room_id, chat_context,
         reported_photo_key, reason_code, reported_title)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [
        reporterNickname, reportedNickname, reason, roomId, chatContextJson,
        photoKey, reasonCode, reasonCode === 'title' ? titleText : null,
      ],
    );
    // The caller hides only what the report named.
    return {
      success: true,
      messageKey: 'db_report_success',
      photoKey: reasonCode === 'photo' ? photoKey : null,
      titleText: reasonCode === 'title' ? titleText : null,
    };
  } catch (err) {
    console.error('Report user error:', err);
    return { success: false, messageKey: 'db_report_failed' };
  } finally {
    client.release();
  }
}

// Add friend
async function addFriend(userNickname, friendNickname) {
  const client = await pool.connect();
  try {
    // Check if already friends or pending
    const existing = await client.query(
      'SELECT * FROM tc_friends WHERE (user_nickname = $1 AND friend_nickname = $2) OR (user_nickname = $2 AND friend_nickname = $1)',
      [userNickname, friendNickname]
    );

    if (existing.rows.length > 0) {
      const row = existing.rows[0];
      if (row.status === 'accepted') {
        return { success: false, messageKey: 'db_already_friend' };
      }
      // If they sent us a request, accept it
      if (row.user_nickname === friendNickname && row.status === 'pending') {
        await client.query(
          'UPDATE tc_friends SET status = $1 WHERE id = $2',
          ['accepted', row.id]
        );
        return { success: true, messageKey: 'db_now_friends', autoAccepted: true };
      }
      return { success: false, messageKey: 'db_friend_request_already_sent' };
    }

    await client.query(
      'INSERT INTO tc_friends (user_nickname, friend_nickname, status) VALUES ($1, $2, $3)',
      [userNickname, friendNickname, 'pending']
    );
    return { success: true, messageKey: 'db_friend_request_sent', autoAccepted: false };
  } catch (err) {
    console.error('Add friend error:', err);
    return { success: false, messageKey: 'db_add_friend_failed' };
  } finally {
    client.release();
  }
}

// Get friends list
async function getFriends(nickname) {
  const client = await pool.connect();
  try {
    const result = await client.query(
      `SELECT
        CASE WHEN user_nickname = $1 THEN friend_nickname ELSE user_nickname END as friend,
        status
       FROM tc_friends
       WHERE (user_nickname = $1 OR friend_nickname = $1) AND status = 'accepted'`,
      [nickname]
    );
    return result.rows.map(r => r.friend);
  } catch (err) {
    console.error('Get friends error:', err);
    return [];
  } finally {
    client.release();
  }
}

/// Who this account has exchanged DMs with, for the backstage.
///
/// Deliberately only the partner list: a name, a count, and when it last
/// moved. Reading someone's private messages is a real step, so the content
/// sits behind a second click rather than unfolding on a page an admin opens
/// for unrelated reasons.
///
/// Counts both directions — a conversation is one thing, not two.
async function getAdminDmPartners(nickname) {
  const r = await pool.query(
    `SELECT partner,
            COUNT(*)::int AS messages,
            COUNT(*) FILTER (WHERE sender = $1)::int AS sent,
            MAX(created_at) AS last_at
     FROM (
       SELECT CASE WHEN sender_nickname = $1 THEN receiver_nickname
                   ELSE sender_nickname END AS partner,
              sender_nickname AS sender,
              created_at
       FROM tc_dm_messages
       WHERE sender_nickname = $1 OR receiver_nickname = $1
     ) t
     GROUP BY partner
     ORDER BY last_at DESC`,
    [nickname],
  );
  return r.rows;
}

/// One conversation, oldest first so it reads as a conversation.
///
/// Paged from the END: a report is almost always about something recent, and
/// starting an admin at the first message of a thousand-message thread means
/// scrolling to find it. Page 1 is the latest page.
async function getAdminDmThread(nickname, partner, limit = 100, offset = 0) {
  const total = (await pool.query(
    `SELECT COUNT(*)::int n FROM tc_dm_messages
     WHERE (sender_nickname = $1 AND receiver_nickname = $2)
        OR (sender_nickname = $2 AND receiver_nickname = $1)`,
    [nickname, partner],
  )).rows[0].n;
  // Walk back from the end; the last page is whatever is left over at the
  // front, so it can be shorter than `limit`.
  const start = Math.max(0, total - offset - limit);
  const take = Math.min(limit, Math.max(0, total - offset));
  const r = await pool.query(
    `SELECT id, sender_nickname, receiver_nickname, message, created_at, read_at
     FROM tc_dm_messages
     WHERE (sender_nickname = $1 AND receiver_nickname = $2)
        OR (sender_nickname = $2 AND receiver_nickname = $1)
     ORDER BY created_at ASC, id ASC
     LIMIT $3 OFFSET $4`,
    [nickname, partner, take, start],
  );
  return { rows: r.rows, total, hasMore: start > 0 };
}

/// Friends, with everything the list needs to draw each of them: when they
/// were last connected, plus the photo, banner, title and level the rest of
/// the app shows a player by.
///
/// Separate from getFriends, which five call sites use as a plain list of
/// nicknames — widening that return type to reach one screen would touch
/// friend broadcasts and room invites for no reason.
///
/// The timestamp is joined here rather than looked up per friend: the caller
/// builds one row per friend and would otherwise run a query inside that loop.
/// COALESCE onto last_login so accounts that predate last_seen_at show their
/// sign-in rather than nothing at all.
async function getFriendsWithLastSeen(nickname, locale = 'ko') {
  const client = await pool.connect();
  try {
    // Whitelisted, the same way searchUsers does it — the locale reaches here
    // from session state, but a column name is not a place to find out.
    const titleCol = locale === 'en' ? 'name_en'
      : locale === 'de' ? 'name_de'
      : 'name_ko';
    const result = await client.query(
      `SELECT f.friend,
              COALESCE(u.last_seen_at, u.last_login) AS last_seen_at,
              u.level,
              u.profile_photo_key, u.profile_photo_status,
              u.profile_photo_expires_at, u.profile_private_hide_photo,
              u.custom_title_text,
              e.banner_key, e.title_key,
              si.${titleCol} AS title_name,
              EXISTS (
                SELECT 1 FROM tc_user_items ui
                JOIN tc_shop_items s2 ON s2.item_key = ui.item_key
                WHERE ui.nickname = u.nickname AND s2.effect_type = 'custom_title'
                  AND (ui.expires_at IS NULL OR ui.expires_at >= NOW())
              ) AS has_custom_title
       FROM (
         SELECT CASE WHEN user_nickname = $1 THEN friend_nickname
                     ELSE user_nickname END AS friend
         FROM tc_friends
         WHERE (user_nickname = $1 OR friend_nickname = $1)
           AND status = 'accepted'
       ) f
       LEFT JOIN tc_users u ON u.nickname = f.friend
       LEFT JOIN tc_user_equips e ON e.nickname = f.friend
       LEFT JOIN tc_shop_items si ON si.item_key = e.title_key`,
      [nickname],
    );
    return result.rows.map((r) => {
      // Same rule as getUserProfile and searchUsers: a `custom:` title only
      // shows while the pass is live and something is written, and it never
      // falls back to a catalog name.
      const wearingCustom = (r.title_key || '').startsWith('custom:');
      const customActive =
        wearingCustom && r.has_custom_title && !!r.custom_title_text;
      return {
        nickname: r.friend,
        lastSeenAt: r.last_seen_at || null,
        level: r.level,
        bannerKey: r.banner_key || null,
        titleKey: wearingCustom && !customActive ? null : (r.title_key || null),
        titleName: customActive ? r.custom_title_text : (r.title_name || null),
        profilePhotoKey: r.profile_photo_key || null,
        profilePhotoStatus: r.profile_photo_status || 'none',
        profilePhotoExpiresAt: r.profile_photo_expires_at || null,
        profilePrivateHidePhoto: r.profile_private_hide_photo === true,
      };
    });
  } catch (err) {
    console.error('Get friends with last seen error:', err);
    return [];
  } finally {
    client.release();
  }
}

/// Stamp the moment a session ends. Called on disconnect, so an offline friend
/// reads as "last here an hour ago" rather than "signed in three days ago".
async function touchLastSeen(nickname) {
  if (!nickname) return;
  try {
    await pool.query(
      `UPDATE tc_users SET last_seen_at = (NOW() AT TIME ZONE 'UTC')
       WHERE nickname = $1`,
      [nickname],
    );
  } catch (err) {
    // A missed stamp costs a slightly stale line in a friends list. Never
    // worth failing a disconnect over.
    console.error('touchLastSeen error:', err.message);
  }
}

// Accept friend request (update pending → accepted)
async function acceptFriendRequest(userNickname, friendNickname) {
  const client = await pool.connect();
  try {
    const result = await client.query(
      `UPDATE tc_friends SET status = 'accepted'
       WHERE user_nickname = $2 AND friend_nickname = $1 AND status = 'pending'`,
      [userNickname, friendNickname]
    );
    if (result.rowCount === 0) {
      return { success: false, messageKey: 'db_friend_request_not_found' };
    }
    return { success: true, messageKey: 'db_now_friends' };
  } catch (err) {
    console.error('Accept friend request error:', err);
    return { success: false, messageKey: 'db_friend_accept_failed' };
  } finally {
    client.release();
  }
}

// Reject friend request (delete pending row)
async function rejectFriendRequest(userNickname, friendNickname) {
  const client = await pool.connect();
  try {
    const result = await client.query(
      `DELETE FROM tc_friends
       WHERE user_nickname = $2 AND friend_nickname = $1 AND status = 'pending'`,
      [userNickname, friendNickname]
    );
    if (result.rowCount === 0) {
      return { success: false, messageKey: 'db_friend_request_not_found' };
    }
    return { success: true, messageKey: 'db_friend_rejected' };
  } catch (err) {
    console.error('Reject friend request error:', err);
    return { success: false, messageKey: 'db_friend_reject_failed' };
  } finally {
    client.release();
  }
}

// Cancel a request I sent (delete pending row I own as the requester —
// mirrors rejectFriendRequest, which deletes the same row from the other
// side's perspective).
async function cancelFriendRequest(userNickname, friendNickname) {
  const client = await pool.connect();
  try {
    const result = await client.query(
      `DELETE FROM tc_friends
       WHERE user_nickname = $1 AND friend_nickname = $2 AND status = 'pending'`,
      [userNickname, friendNickname]
    );
    if (result.rowCount === 0) {
      return { success: false, messageKey: 'db_friend_request_not_found' };
    }
    return { success: true, messageKey: 'db_friend_request_cancelled' };
  } catch (err) {
    console.error('Cancel friend request error:', err);
    return { success: false, messageKey: 'db_friend_cancel_failed' };
  } finally {
    client.release();
  }
}

// Remove friend (delete accepted row, both directions)
async function removeFriend(userNickname, friendNickname) {
  const client = await pool.connect();
  try {
    const result = await client.query(
      `DELETE FROM tc_friends
       WHERE ((user_nickname = $1 AND friend_nickname = $2) OR (user_nickname = $2 AND friend_nickname = $1))
         AND status = 'accepted'`,
      [userNickname, friendNickname]
    );
    if (result.rowCount === 0) {
      return { success: false, messageKey: 'db_friend_not_found' };
    }
    return { success: true, messageKey: 'db_friend_removed' };
  } catch (err) {
    console.error('Remove friend error:', err);
    return { success: false, messageKey: 'db_friend_remove_failed' };
  } finally {
    client.release();
  }
}

// Get pending friend requests
async function getPendingFriendRequests(nickname) {
  const client = await pool.connect();
  try {
    const result = await client.query(
      `SELECT user_nickname as from_user FROM tc_friends
       WHERE friend_nickname = $1 AND status = 'pending'`,
      [nickname]
    );
    return result.rows.map(r => r.from_user);
  } catch (err) {
    console.error('Get pending requests error:', err);
    return [];
  } finally {
    client.release();
  }
}

/// Same photo/level/banner/title join as getFriendsWithLastSeen, just keyed
/// off an arbitrary `SELECT nickname[, created_at]` subquery instead of the
/// friends CTE. A friend-request row deserves the same profile summary a
/// friends-list row gets — the Requests tab used to draw a bare initial
/// letter because these two functions returned nothing more than a name.
async function _enrichRequestRows(client, baseSql, params, locale) {
  const titleCol = locale === 'en' ? 'name_en'
    : locale === 'de' ? 'name_de'
    : 'name_ko';
  const result = await client.query(
    `WITH base AS (${baseSql})
     SELECT base.*, u.level,
            u.profile_photo_key, u.profile_photo_status,
            u.profile_photo_expires_at, u.profile_private_hide_photo,
            u.custom_title_text,
            e.banner_key, e.title_key,
            si.${titleCol} AS title_name,
            EXISTS (
              SELECT 1 FROM tc_user_items ui
              JOIN tc_shop_items s2 ON s2.item_key = ui.item_key
              WHERE ui.nickname = u.nickname AND s2.effect_type = 'custom_title'
                AND (ui.expires_at IS NULL OR ui.expires_at >= NOW())
            ) AS has_custom_title
     FROM base
     LEFT JOIN tc_users u ON u.nickname = base.nickname
     LEFT JOIN tc_user_equips e ON e.nickname = base.nickname
     LEFT JOIN tc_shop_items si ON si.item_key = e.title_key`,
    params,
  );
  return result.rows.map((r) => {
    const wearingCustom = (r.title_key || '').startsWith('custom:');
    const customActive = wearingCustom && r.has_custom_title && !!r.custom_title_text;
    return {
      nickname: r.nickname,
      createdAt: r.created_at || null,
      level: r.level,
      bannerKey: r.banner_key || null,
      titleKey: wearingCustom && !customActive ? null : (r.title_key || null),
      titleName: customActive ? r.custom_title_text : (r.title_name || null),
      profilePhotoKey: r.profile_photo_key || null,
      profilePhotoStatus: r.profile_photo_status || 'none',
      profilePhotoExpiresAt: r.profile_photo_expires_at || null,
      profilePrivateHidePhoto: r.profile_private_hide_photo === true,
    };
  });
}

// getPendingFriendRequests, with the same profile summary a friends-list row
// carries. Separate function (rather than changing getPendingFriendRequests
// itself) because that one's plain string-array shape is relied on elsewhere
// (searchUsers' pendingIncoming.includes(nick) check).
async function getPendingFriendRequestsDetailed(nickname, locale = 'ko') {
  const client = await pool.connect();
  try {
    return await _enrichRequestRows(
      client,
      `SELECT user_nickname AS nickname, created_at FROM tc_friends
       WHERE friend_nickname = $1 AND status = 'pending'
       ORDER BY created_at DESC`,
      [nickname],
      locale,
    );
  } catch (err) {
    console.error('Get pending requests detailed error:', err);
    return [];
  } finally {
    client.release();
  }
}

// Requests I sent that are still waiting on the other side — the mirror of
// getPendingFriendRequestsDetailed. Includes the same profile summary plus
// created_at, so the Requests tab can show how long ago each was sent (also
// what tells someone it might be worth cancelling a stale one).
async function getSentFriendRequests(nickname, locale = 'ko') {
  const client = await pool.connect();
  try {
    return await _enrichRequestRows(
      client,
      `SELECT friend_nickname AS nickname, created_at FROM tc_friends
       WHERE user_nickname = $1 AND status = 'pending'
       ORDER BY created_at DESC`,
      [nickname],
      locale,
    );
  } catch (err) {
    console.error('Get sent requests detailed error:', err);
    return [];
  } finally {
    client.release();
  }
}

// Save match result
async function saveMatchResult(matchData) {
  const client = await pool.connect();
  try {
    await client.query(
      `INSERT INTO tc_match_history
       (winner_team, team_a_score, team_b_score, player_a1, player_a2, player_b1, player_b2, is_ranked, end_reason, deserter_nickname)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
      [
        matchData.winnerTeam,
        matchData.teamAScore,
        matchData.teamBScore,
        matchData.playerA1,
        matchData.playerA2,
        matchData.playerB1,
        matchData.playerB2,
        matchData.isRanked || false,
        matchData.endReason || 'normal',
        matchData.deserterNickname || null,
      ]
    );
    return { success: true };
  } catch (err) {
    console.error('Save match result error:', err);
    return { success: false };
  } finally {
    client.release();
  }
}

// Update user stats after a game
async function updateUserStats(nickname, won, isRanked = false) {
  const client = await pool.connect();
  try {
    const ratingChange = isRanked ? (won ? 25 : -20) : 0;
    const goldChange = won ? 10 : 3;
    const expChange = isRanked ? (won ? 15 : 8) : (won ? 10 : 5);
    if (won) {
      await client.query(
        `UPDATE tc_users
         SET total_games = total_games + 1,
             wins = wins + 1,
             rating = GREATEST(0, rating + $2),
             gold = gold + $3,
             season_games = season_games + $4,
             season_wins = season_wins + $4,
             season_rating = GREATEST(0, season_rating + $5),
             exp_total = exp_total + $6,
             level = tc_compute_level(exp_total + $6)
         WHERE nickname = $1`,
        [
          nickname,
          ratingChange,
          goldChange,
          isRanked ? 1 : 0,
          isRanked ? ratingChange : 0,
          expChange,
        ]
      );
    } else {
      await client.query(
        `UPDATE tc_users
         SET total_games = total_games + 1,
             losses = losses + 1,
             rating = GREATEST(0, rating + $2),
             gold = gold + $3,
             season_games = season_games + $4,
             season_losses = season_losses + $4,
             season_rating = GREATEST(0, season_rating + $5),
             exp_total = exp_total + $6,
             level = tc_compute_level(exp_total + $6)
         WHERE nickname = $1`,
        [
          nickname,
          ratingChange,
          goldChange,
          isRanked ? 1 : 0,
          isRanked ? ratingChange : 0,
          expChange,
        ]
      );
    }
    return { success: true };
  } catch (err) {
    console.error('Update user stats error:', err);
    return { success: false };
  } finally {
    client.release();
  }
}

// ELO rating calculation
function calcElo(myRating, opponentRating, won, K = 40) {
  const expected = 1 / (1 + Math.pow(10, (opponentRating - myRating) / 400));
  const actual = won ? 1 : 0;
  return Math.round(K * (actual - expected));
}

async function saveMatchResultWithStats(matchData, players) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(
      `INSERT INTO tc_match_history
       (winner_team, team_a_score, team_b_score, player_a1, player_a2, player_b1, player_b2, is_ranked, end_reason, deserter_nickname)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
      [
        matchData.winnerTeam,
        matchData.teamAScore,
        matchData.teamBScore,
        matchData.playerA1,
        matchData.playerA2,
        matchData.playerB1,
        matchData.playerB2,
        matchData.isRanked || false,
        matchData.endReason || 'normal',
        matchData.deserterNickname || null,
      ]
    );

    // Fetch current ratings for ELO calculation
    const humanPlayers = players.filter(p => p.nickname && !p.isBot);
    const ratingMap = {};
    if (humanPlayers.length > 0) {
      const nicknames = humanPlayers.map(p => p.nickname);
      const ratingRes = await client.query(
        `SELECT nickname, rating FROM tc_users WHERE nickname = ANY($1)`,
        [nicknames]
      );
      for (const row of ratingRes.rows) {
        ratingMap[row.nickname] = row.rating || 1000;
      }
    }

    // Calculate team average ratings
    const teamARatings = players.filter(p => p.team === 'A' && !p.isBot).map(p => ratingMap[p.nickname] || 1000);
    const teamBRatings = players.filter(p => p.team === 'B' && !p.isBot).map(p => ratingMap[p.nickname] || 1000);
    const teamAAvg = teamARatings.length > 0 ? teamARatings.reduce((a, b) => a + b, 0) / teamARatings.length : 1000;
    const teamBAvg = teamBRatings.length > 0 ? teamBRatings.reduce((a, b) => a + b, 0) / teamBRatings.length : 1000;

    for (const player of humanPlayers) {
      const isDeserter =
        ['leave', 'timeout'].includes(matchData.endReason || 'normal') &&
        matchData.deserterNickname === player.nickname;
      const isDraw = player.isDraw === true;

      if (isDraw) {
        const expChange = 3;
        await client.query(
          `UPDATE tc_users
           SET total_games = total_games + 1,
               exp_total = exp_total + $2,
               level = tc_compute_level(exp_total + $2)
           WHERE nickname = $1`,
          [player.nickname, expChange]
        );
      } else if (player.won) {
        const myTeamAvg = player.team === 'A' ? teamAAvg : teamBAvg;
        const oppTeamAvg = player.team === 'A' ? teamBAvg : teamAAvg;
        const ratingChange = player.isRanked ? calcElo(myTeamAvg, oppTeamAvg, true) : 0;
        const baseGoldChange = 10;
        const goldChange = player.isRanked ? baseGoldChange * 2 : baseGoldChange;
        const expChange = player.isRanked ? 15 : 10;
        await client.query(
          `UPDATE tc_users
           SET total_games = total_games + 1,
               wins = wins + 1,
               rating = GREATEST(0, rating + $2),
               gold = gold + $3,
               season_games = season_games + $4,
               season_wins = season_wins + $4,
               season_rating = GREATEST(0, season_rating + $5),
               exp_total = exp_total + $6,
               level = tc_compute_level(exp_total + $6)
           WHERE nickname = $1`,
          [
            player.nickname,
            ratingChange,
            goldChange,
            player.isRanked ? 1 : 0,
            player.isRanked ? ratingChange : 0,
            expChange,
          ]
        );
      } else {
        const myTeamAvg = player.team === 'A' ? teamAAvg : teamBAvg;
        const oppTeamAvg = player.team === 'A' ? teamBAvg : teamAAvg;
        const ratingChange = player.isRanked ? calcElo(myTeamAvg, oppTeamAvg, false) : 0;
        const goldChange = isDeserter ? 0 : (player.isRanked ? 6 : 3);
        const expChange = isDeserter ? 0 : (player.isRanked ? 8 : 5);
        await client.query(
          `UPDATE tc_users
           SET total_games = total_games + 1,
               losses = losses + 1,
               rating = GREATEST(0, rating + $2),
               gold = gold + $3,
               season_games = season_games + $4,
               season_losses = season_losses + $4,
               season_rating = GREATEST(0, season_rating + $5),
               exp_total = exp_total + $6,
               level = tc_compute_level(exp_total + $6)
           WHERE nickname = $1`,
          [
            player.nickname,
            ratingChange,
            goldChange,
            player.isRanked ? 1 : 0,
            player.isRanked ? ratingChange : 0,
            expChange,
          ]
        );
      }
    }

    await client.query('COMMIT');
    return { success: true };
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('saveMatchResultWithStats error:', err);
    return { success: false, message: err.message };
  } finally {
    client.release();
  }
}

// Get user profile. `locale` picks the display name column for the equipped
// title; defaults to Korean for legacy callers that don't yet pass one.
async function getUserProfile(nickname, locale = 'ko') {
  const client = await pool.connect();
  try {
    // Reconnecting is exactly the case cleanupExpiredItems was written for
    // but wasn't wired into: an item can expire while nobody has opened the
    // shop/inventory since, and the periodic sweep runs only every 6h — so
    // without this, a freshly-expired banner keeps showing on this player's
    // own reconnect (and everyone who views their profile) until one of
    // those two catches up. See cleanupExpiredItems' own comment.
    await cleanupExpiredItems(client, nickname);

    // Whitelist the locale-specific column to stay safe against accidental
    // injection even though the locale only comes from server-side state.
    const titleCol = locale === 'en' ? 'name_en'
      : locale === 'de' ? 'name_de'
      : 'name_ko';
    const result = await client.query(
      `SELECT u.nickname, u.total_games, u.wins, u.losses, u.rating, u.gold, u.leave_count,
              u.season_rating, u.season_games, u.season_wins, u.season_losses,
              u.exp_total, u.level, u.created_at,
              u.sk_total_games, u.sk_wins, u.sk_losses, u.sk_rating,
              u.sk_season_rating, u.sk_season_games, u.sk_season_wins, u.sk_season_losses,
              u.ll_total_games, u.ll_wins, u.ll_losses,
              u.mighty_total_games, u.mighty_wins, u.mighty_losses, u.mighty_rating,
              u.mighty_season_rating, u.mighty_season_games, u.mighty_season_wins, u.mighty_season_losses,
              u.card_view_pref,
              u.profile_photo_key, u.profile_photo_status, u.profile_photo_expires_at,
              u.profile_private_hide_photo,
              u.custom_title_text, u.custom_title_color,
              e.banner_key, e.theme_key, e.title_key,
              si.${titleCol} AS title_name
       FROM tc_users u
       LEFT JOIN tc_user_equips e ON e.nickname = u.nickname
       LEFT JOIN tc_shop_items si ON si.item_key = e.title_key
       WHERE u.nickname = $1`,
      [nickname]
    );
    if (result.rows.length === 0) {
      return null;
    }
    const user = result.rows[0];
    const winRate = user.total_games > 0
      ? Math.round((user.wins / user.total_games) * 100)
      : 0;
    const seasonWinRate = user.season_games > 0
      ? Math.round((user.season_wins / user.season_games) * 100)
      : 0;

    // Report count in last 6 months — and never from before this account
    // existed, since reports outlive a deleted account under its old nickname
    // and the next owner of that nickname must not inherit the record.
    // 가입 시각은 SQL 안에서 다시 읽는다. 컬럼에서 읽은 값을 JS Date 로
    // 들고 있다가 파라미터로 되돌려 넣으면 timestamp 컬럼과 비교될 때 9시간
    // 앞으로 밀린다(노드 쪽이 로컬시간으로 직렬화한다). 그 결과 가입 후
    // 아홉 시간 안에 들어온 신고는 프로필에서 아예 세어지지 않았다.
    const reportRes = await client.query(
      `SELECT COUNT(*) FROM tc_reports
       WHERE reported_nickname = $1 AND created_at >= NOW() - INTERVAL '6 months'
         AND created_at >= (SELECT created_at FROM tc_users WHERE nickname = $1)`,
      [nickname]
    );
    const reportCount = parseInt(reportRes.rows[0].count, 10) || 0;

    // Feature gates are keyed by effect_type (the feature), not a single
    // item_key, so any duration tier (7d / 30d / future) enables the feature.
    const featureActive = async (effectType) => {
      const r = await client.query(
        `SELECT 1 FROM tc_user_items ui
         JOIN tc_shop_items si ON si.item_key = ui.item_key
         WHERE ui.nickname = $1 AND si.effect_type = $2
           AND (ui.expires_at IS NULL OR ui.expires_at >= NOW()) LIMIT 1`,
        [nickname, effectType],
      );
      return r.rows.length > 0;
    };
    const offRes = await client.query(
      `SELECT effect_type FROM tc_user_feature_off WHERE nickname = $1`,
      [nickname],
    );
    const disabledFeatures = offRes.rows.map((r) => r.effect_type);
    const isOff = (effectType) => disabledFeatures.includes(effectType);
    // Owned AND switched on. Owning it is what the shop sells; using it is the
    // owner's call, and they can turn it off without losing the days.
    const hasTopCardCounter =
      (await featureActive('top_card_counter')) && !isOff('top_card_counter');
    const hasMightyTrumpCounter =
      (await featureActive('mighty_trump_counter'))
      && !isOff('mighty_trump_counter');
    const hasMightyPrevTrick =
      (await featureActive('mighty_prev_trick')) && !isOff('mighty_prev_trick');
    // Privacy needs the expiry too, not just a boolean: the owner's own popup
    // shows how long it runs, and the visibility cache re-checks it rather than
    // querying on every broadcast.
    const privateRow = await client.query(
      `SELECT COUNT(*)::int AS n, MAX(ui.expires_at) AS expires_at
       FROM tc_user_items ui
       JOIN tc_shop_items si ON si.item_key = ui.item_key
       WHERE ui.nickname = $1 AND si.effect_type = 'profile_private'
         AND (ui.expires_at IS NULL OR ui.expires_at >= NOW())`,
      [nickname],
    );
    const hasProfilePrivate =
      (privateRow.rows[0]?.n || 0) > 0 && !isOff('profile_private');
    const hasCustomTitle = await featureActive('custom_title');
    const profilePrivateExpiresAt = hasProfilePrivate
      ? (privateRow.rows[0].expires_at || null)
      : null;

    const wearingCustomTitle = (user.title_key || '').startsWith('custom:');
    const customTitleActive =
      wearingCustomTitle && hasCustomTitle && !!user.custom_title_text;

    const skWinRate = user.sk_total_games > 0
      ? Math.round((user.sk_wins / user.sk_total_games) * 100)
      : 0;
    const skSeasonWinRate = user.sk_season_games > 0
      ? Math.round((user.sk_season_wins / user.sk_season_games) * 100)
      : 0;
    const llWinRate = user.ll_total_games > 0
      ? Math.round((user.ll_wins / user.ll_total_games) * 100)
      : 0;
    const mightyWinRate = user.mighty_total_games > 0
      ? Math.round((user.mighty_wins / user.mighty_total_games) * 100)
      : 0;
    const mightySeasonWinRate = user.mighty_season_games > 0
      ? Math.round((user.mighty_season_wins / user.mighty_season_games) * 100)
      : 0;

    return {
      nickname: user.nickname,
      totalGames: user.total_games,
      wins: user.wins,
      losses: user.losses,
      rating: user.rating,
      gold: user.gold,
      leaveCount: user.leave_count,
      reportCount,
      winRate,
      seasonRating: user.season_rating,
      seasonGames: user.season_games,
      seasonWins: user.season_wins,
      seasonLosses: user.season_losses,
      seasonWinRate,
      expTotal: user.exp_total,
      level: user.level,
      bannerKey: user.banner_key,
      themeKey: user.theme_key,
      titleKey: wearingCustomTitle && !customTitleActive
          ? null
          : user.title_key,
      titleName: customTitleActive
        ? user.custom_title_text
        : (user.title_name || null),
      createdAt: user.created_at,
      hasTopCardCounter,
      hasMightyTrumpCounter,
      hasMightyPrevTrick,
      skTotalGames: user.sk_total_games,
      skWins: user.sk_wins,
      skLosses: user.sk_losses,
      skRating: user.sk_rating,
      skWinRate,
      skSeasonRating: user.sk_season_rating,
      skSeasonGames: user.sk_season_games,
      skSeasonWins: user.sk_season_wins,
      skSeasonLosses: user.sk_season_losses,
      skSeasonWinRate,
      llTotalGames: user.ll_total_games,
      llWins: user.ll_wins,
      llLosses: user.ll_losses,
      llWinRate,
      mightyTotalGames: user.mighty_total_games,
      mightyWins: user.mighty_wins,
      mightyLosses: user.mighty_losses,
      mightyRating: user.mighty_rating,
      mightyWinRate,
      mightySeasonRating: user.mighty_season_rating,
      mightySeasonGames: user.mighty_season_games,
      mightySeasonWins: user.mighty_season_wins,
      mightySeasonLosses: user.mighty_season_losses,
      mightySeasonWinRate,
      cardViewPref: user.card_view_pref || 'ask',
      profilePhotoKey: user.profile_photo_key || null,
      profilePhotoStatus: user.profile_photo_status || 'none',
      profilePhotoExpiresAt: user.profile_photo_expires_at || null,
      hasProfilePrivate,
      profilePrivateExpiresAt,
      profilePrivateHidePhoto: user.profile_private_hide_photo === true,
      hasCustomTitle,
      customTitleText: user.custom_title_text || null,
      customTitleColor: user.custom_title_color || null,
      disabledFeatures,
    };
  } catch (err) {
    console.error('Get user profile error:', err);
    return null;
  } finally {
    client.release();
  }
}

/**
 * Store the user's own title text and wear it.
 *
 * The text lives on tc_users and the equip slot holds `custom:<colour>` — the
 * colour rides in the key so every payload that already carries titleKey/
 * titleName (room state, game state, profile) shows a custom title without a
 * new field on any of them.
 *
 * Ownership is checked here rather than trusted from the client: this is the
 * only path that writes a title nobody reviewed.
 */
async function setCustomTitle(nickname, text, colorId) {
  const client = await pool.connect();
  try {
    const active = await client.query(
      `SELECT 1 FROM tc_user_items ui
       JOIN tc_shop_items si ON si.item_key = ui.item_key
       WHERE ui.nickname = $1 AND si.effect_type = 'custom_title'
         AND (ui.expires_at IS NULL OR ui.expires_at >= NOW()) LIMIT 1`,
      [nickname],
    );
    if (active.rows.length === 0) {
      return { success: false, messageKey: 'db_item_not_owned' };
    }
    await client.query(
      `UPDATE tc_users SET custom_title_text = $2, custom_title_color = $3
       WHERE nickname = $1`,
      [nickname, text, colorId],
    );
    const titleKey = `custom:${colorId}`;
    await client.query(
      `INSERT INTO tc_user_equips (nickname, title_key, updated_at)
       VALUES ($1, $2, NOW())
       ON CONFLICT (nickname)
       DO UPDATE SET title_key = EXCLUDED.title_key, updated_at = NOW()`,
      [nickname, titleKey],
    );
    // Catalog titles are mutually exclusive with this one, same as with each
    // other — the equip slot holds exactly one.
    await client.query(
      `UPDATE tc_user_items SET is_active = FALSE
       WHERE nickname = $1 AND item_key IN (
         SELECT item_key FROM tc_shop_items WHERE category = 'title'
       )`,
      [nickname],
    );
    return { success: true, titleKey, titleName: text, color: colorId };
  } catch (err) {
    console.error('Set custom title error:', err);
    return { success: false, messageKey: 'db_update_failed' };
  } finally {
    client.release();
  }
}

/**
 * Switch a feature pass on or off for its owner.
 *
 * The pass keeps running to its expiry either way — this is "don't apply it for
 * now", not a pause button. Stored as a row per switched-off feature.
 */
async function setFeatureEnabled(nickname, effectType, enabled) {
  const ALLOWED = new Set([
    'top_card_counter',
    'mighty_trump_counter',
    'mighty_prev_trick',
    'profile_private',
  ]);
  if (!ALLOWED.has(effectType)) {
    return { success: false, messageKey: 'db_item_not_found' };
  }
  try {
    if (enabled) {
      await pool.query(
        `DELETE FROM tc_user_feature_off WHERE nickname = $1 AND effect_type = $2`,
        [nickname, effectType],
      );
    } else {
      await pool.query(
        `INSERT INTO tc_user_feature_off (nickname, effect_type) VALUES ($1, $2)
         ON CONFLICT DO NOTHING`,
        [nickname, effectType],
      );
    }
    return { success: true, effectType, enabled: enabled === true };
  } catch (err) {
    console.error('Set feature enabled error:', err);
    return { success: false, messageKey: 'db_update_failed' };
  }
}

/** Admin/report path: wipe the text and take it off. */
/**
 * Write a title onto an account from the admin console.
 *
 * Two things differ from the player path. The entitlement is not required —
 * an operator title is a label the operator puts on, not something bought — so
 * one is granted alongside it (source 'admin', no expiry) rather than the write
 * being refused. And the grant is what makes it show: every display path asks
 * "is a custom_title pass live?", so without it the text would sit in the row
 * and appear nowhere.
 */
async function setCustomTitleByAdmin(nickname, text, colorId) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const exists = await client.query(
      'SELECT 1 FROM tc_users WHERE nickname = $1', [nickname],
    );
    if (exists.rowCount === 0) {
      await client.query('ROLLBACK');
      return { success: false, messageKey: 'db_user_not_found' };
    }
    await client.query(
      `UPDATE tc_users SET custom_title_text = $2, custom_title_color = $3
       WHERE nickname = $1`,
      [nickname, text, colorId],
    );
    // Only when they don't already own one: a player who bought the pass keeps
    // their own expiry, and re-running this must not quietly extend it.
    const owned = await client.query(
      `SELECT 1 FROM tc_user_items ui
       JOIN tc_shop_items si ON si.item_key = ui.item_key
       WHERE ui.nickname = $1 AND si.effect_type = 'custom_title'
         AND (ui.expires_at IS NULL OR ui.expires_at >= NOW()) LIMIT 1`,
      [nickname],
    );
    if (owned.rowCount === 0) {
      const item = await client.query(
        `SELECT item_key FROM tc_shop_items
         WHERE effect_type = 'custom_title' ORDER BY price ASC LIMIT 1`,
      );
      const itemKey = item.rows[0]?.item_key;
      if (!itemKey) {
        await client.query('ROLLBACK');
        return { success: false, messageKey: 'db_item_not_found' };
      }
      await client.query(
        `INSERT INTO tc_user_items (nickname, item_key, expires_at, is_active, source)
         VALUES ($1, $2, NULL, TRUE, 'admin')`,
        [nickname, itemKey],
      );
    }
    // A switched-off pass would keep the operator title hidden.
    await client.query(
      `DELETE FROM tc_user_feature_off WHERE nickname = $1 AND effect_type = 'custom_title'`,
      [nickname],
    );
    const titleKey = `custom:${colorId}`;
    await client.query(
      `INSERT INTO tc_user_equips (nickname, title_key, updated_at)
       VALUES ($1, $2, NOW())
       ON CONFLICT (nickname)
       DO UPDATE SET title_key = EXCLUDED.title_key, updated_at = NOW()`,
      [nickname, titleKey],
    );
    await client.query(
      `UPDATE tc_user_items SET is_active = FALSE
       WHERE nickname = $1 AND item_key IN (
         SELECT item_key FROM tc_shop_items WHERE category = 'title'
       )`,
      [nickname],
    );
    await client.query('COMMIT');
    return { success: true, titleKey, titleName: text, color: colorId };
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('Set custom title (admin) error:', err);
    return { success: false, messageKey: 'db_update_failed' };
  } finally {
    client.release();
  }
}

async function clearCustomTitle(nickname) {
  const client = await pool.connect();
  try {
    await client.query(
      `UPDATE tc_users SET custom_title_text = NULL WHERE nickname = $1`,
      [nickname],
    );
    await client.query(
      `UPDATE tc_user_equips SET title_key = NULL, updated_at = NOW()
       WHERE nickname = $1 AND title_key LIKE 'custom:%'`,
      [nickname],
    );
    return { success: true };
  } catch (err) {
    console.error('Clear custom title error:', err);
    return { success: false, messageKey: 'db_update_failed' };
  } finally {
    client.release();
  }
}

/**
 * The owner's choice of how far their privacy reaches: records only (default)
 * or the profile photo as well.
 *
 * Stored regardless of whether the entitlement is currently active — it is a
 * preference, and it must survive a lapsed pass so re-buying does not silently
 * come back with a different setting than the user left it on.
 */
async function setProfilePrivateHidePhoto(nickname, hide) {
  try {
    const r = await pool.query(
      `UPDATE tc_users SET profile_private_hide_photo = $2 WHERE nickname = $1`,
      [nickname, hide === true],
    );
    if (r.rowCount === 0) return { success: false, messageKey: 'db_user_not_found' };
    return { success: true, hidePhoto: hide === true };
  } catch (err) {
    console.error('Set profile private hide photo error:', err);
    return { success: false, messageKey: 'db_update_failed' };
  }
}

// Get recent matches for a player
// Depth guard. Each source is asked for offset+limit rows, so a caller that
// keeps paging would eventually ask every table for its whole history.
const MATCH_HISTORY_MAX_DEPTH = 500;

/**
 * Recent matches for a profile.
 *
 * Two shapes, on purpose:
 *
 * - No `opts` — the profile popup's first load. Every game type is capped at
 *   `limit` and the results merge WITHOUT a global slice, because the popup
 *   filters by the selected tab and a global slice would let the most-played
 *   mode crowd every other tab out.
 * - With `opts` — one page of the full history, for the "더보기" list. That
 *   list shows one tab at a time, so the starvation problem does not apply and
 *   a real page can be cut: every relevant source is asked for offset+limit
 *   rows, merged by time, then sliced. Anything inside the global top N is
 *   inside its own source's top N, so the page is exact.
 */
async function getRecentMatches(nickname, limit = 5, opts = null) {
  const paged = opts != null;
  const offset = paged ? Math.max(0, opts.offset || 0) : 0;
  // 'all' and null both mean every game type.
  const onlyGame =
    paged && opts.gameType && opts.gameType !== 'all' ? opts.gameType : null;
  const wants = (gameType) => onlyGame == null || onlyGame === gameType;
  // Walk-outs are an event, not a result, and a client that cannot draw them
  // must not be paged through them either. Dropped at the query rather than
  // after the slice: filtering a finished page would leave `hasMore` and the
  // row count disagreeing, and a page that came back empty would stop the
  // caller's scroll early.
  const withMidLeave = opts?.includeMidLeave !== false;
  // How deep each source has to reach for this page to be correct.
  const need = paged
    ? Math.min(offset + limit, MATCH_HISTORY_MAX_DEPTH)
    : limit;
  const client = await pool.connect();
  // One batched players fetch per game type instead of one query per match
  // (was N+1). `table` is a hardcoded internal constant, never user input.
  const fetchPlayersByMatch = async (table, ids) => {
    const map = new Map();
    if (ids.length === 0) return map;
    const r = await client.query(
      `SELECT match_id, nickname, score, rank, is_winner, is_bot
         FROM ${table} WHERE match_id = ANY($1) ORDER BY match_id, rank`,
      [ids]
    );
    for (const p of r.rows) {
      if (!map.has(p.match_id)) map.set(p.match_id, []);
      map.get(p.match_id).push({
        nickname: p.nickname, score: p.score, rank: p.rank,
        isWinner: p.is_winner, isBot: p.is_bot,
      });
    }
    return map;
  };
  try {
    // Match rows are keyed by nickname, and a nickname comes free again when
    // its owner deletes the account (the soft delete renames the account row
    // but keeps the history under the original name, on purpose). Whoever
    // registers that nickname next would otherwise open their profile and find
    // a stranger's games sitting in it. Bound every lookup to this account's
    // own lifetime; a nickname with no live account (someone inspecting a
    // deleted user) keeps the old, unbounded behaviour.
    //
    // Sent as a text timestamp, not a JS Date. These columns are `timestamp
    // without time zone` holding UTC, and node-pg serializes a Date using the
    // *process* timezone — `...T12:02+09:00` for a 03:02 UTC value — which the
    // cast to timestamp then truncates to 12:02, moving the bound nine hours
    // forward and hiding every match newer than it. Invisible on a UTC host,
    // which is why it survived; anything east of Greenwich loses its history.
    // toISOString() is already UTC and carries no offset for the cast to eat.
    const sinceDate = (await client.query(
      `SELECT created_at FROM tc_users WHERE nickname = $1`, [nickname]
    )).rows[0]?.created_at || new Date(0);
    const since = new Date(sinceDate).toISOString().replace('T', ' ').replace('Z', '');

    // Tichu matches
    const tichuResult = !wants('tichu')
      ? { rows: [] }
      : await client.query(
      `SELECT *, 'tichu'::text as game_type FROM tc_match_history
       WHERE (player_a1 = $1 OR player_a2 = $1 OR player_b1 = $1 OR player_b2 = $1)
         AND created_at >= $3
       ORDER BY created_at DESC
       LIMIT $2`,
      [nickname, need, since]
    );
    const tichuMatches = tichuResult.rows.map(row => {
      const isTeamA = row.player_a1 === nickname || row.player_a2 === nickname;
      const isDraw = row.winner_team === 'draw';
      const won = !isDraw && ((isTeamA && row.winner_team === 'A') || (!isTeamA && row.winner_team === 'B'));
      const deserterNickname = row.deserter_nickname || null;
      return {
        id: row.id,
        gameType: 'tichu',
        won,
        isDraw,
        isDesertionLoss: deserterNickname === nickname,
        myTeam: isTeamA ? 'A' : 'B',
        teamAScore: row.team_a_score,
        teamBScore: row.team_b_score,
        playerA1: row.player_a1,
        playerA2: row.player_a2,
        playerB1: row.player_b1,
        playerB2: row.player_b2,
        isRanked: row.is_ranked,
        endReason: row.end_reason || 'normal',
        deserterNickname,
        createdAt: row.created_at,
      };
    });

    // Skull King matches
    const skResult = !wants('skull_king')
      ? { rows: [] }
      : await client.query(
      `SELECT h.*, p.score as my_score, p.rank as my_rank, p.is_winner as my_winner
       FROM tc_sk_match_history h
       JOIN tc_sk_match_players p ON p.match_id = h.id AND p.nickname = $1
       WHERE h.created_at >= $3
       ORDER BY h.created_at DESC
       LIMIT $2`,
      [nickname, need, since]
    );
    const skPlayers = await fetchPlayersByMatch(
      'tc_sk_match_players', skResult.rows.map(r => r.id));
    const skMatches = [];
    for (const row of skResult.rows) {
      const deserterNickname = row.deserter_nickname || null;
      const isDesertionLoss = deserterNickname === nickname;
      const isDraw = deserterNickname != null && deserterNickname !== nickname;
      skMatches.push({
        id: row.id,
        gameType: 'skull_king',
        won: isDraw ? false : row.my_winner,
        isDraw,
        isDesertionLoss,
        deserterNickname,
        myScore: row.my_score,
        myRank: row.my_rank,
        playerCount: row.player_count,
        isRanked: row.is_ranked,
        endReason: row.end_reason || 'normal',
        players: skPlayers.get(row.id) || [],
        createdAt: row.created_at,
      });
    }

    // Love Letter matches
    const llResult = !wants('love_letter')
      ? { rows: [] }
      : await client.query(
      `SELECT h.*, p.score as my_score, p.rank as my_rank, p.is_winner as my_winner
       FROM tc_ll_match_history h
       JOIN tc_ll_match_players p ON p.match_id = h.id AND p.nickname = $1
       WHERE h.created_at >= $3
       ORDER BY h.created_at DESC
       LIMIT $2`,
      [nickname, need, since]
    );
    const llPlayers = await fetchPlayersByMatch(
      'tc_ll_match_players', llResult.rows.map(r => r.id));
    const llMatches = [];
    for (const row of llResult.rows) {
      const deserterNickname = row.deserter_nickname || null;
      const isDesertionLoss = deserterNickname === nickname;
      const isDraw = deserterNickname != null && deserterNickname !== nickname;
      llMatches.push({
        id: row.id,
        gameType: 'love_letter',
        won: isDraw ? false : row.my_winner,
        isDraw,
        isDesertionLoss,
        deserterNickname,
        myScore: row.my_score,
        myRank: row.my_rank,
        playerCount: row.player_count,
        isRanked: row.is_ranked,
        endReason: row.end_reason || 'normal',
        players: llPlayers.get(row.id) || [],
        createdAt: row.created_at,
      });
    }

    // Mighty matches
    const mightyResult = !wants('mighty')
      ? { rows: [] }
      : await client.query(
      `SELECT h.*, p.score as my_score, p.rank as my_rank, p.is_winner as my_winner
       FROM tc_mighty_match_history h
       JOIN tc_mighty_match_players p ON p.match_id = h.id AND p.nickname = $1
       WHERE h.created_at >= $3
       ORDER BY h.created_at DESC
       LIMIT $2`,
      [nickname, need, since]
    );
    const mightyPlayers = await fetchPlayersByMatch(
      'tc_mighty_match_players', mightyResult.rows.map(r => r.id));
    const mightyMatches = [];
    for (const row of mightyResult.rows) {
      const deserterNickname = row.deserter_nickname || null;
      const isDesertionLoss = deserterNickname === nickname;
      // When someone else deserts a Mighty match, remaining players are saved
      // as isDraw:true / isWinner:false (no rating or W/L change). The DB
      // only persists is_winner, so we reconstruct the draw state the same
      // way the SK / LL queries do.
      const isDraw = deserterNickname != null && deserterNickname !== nickname;
      mightyMatches.push({
        id: row.id,
        gameType: 'mighty',
        won: isDraw ? false : row.my_winner === true,
        isDraw,
        isDesertionLoss,
        deserterNickname,
        myScore: row.my_score,
        myRank: row.my_rank,
        playerCount: row.player_count,
        isRanked: row.is_ranked,
        endReason: row.end_reason || 'normal',
        declarerNickname: row.declarer_nickname,
        partnerNickname: row.partner_nickname,
        declarerTeamSuccess: row.declarer_team_success,
        declarerTeamPoints: row.declarer_team_points,
        bidPoints: row.bid_points,
        trumpSuit: row.trump_suit,
        players: mightyPlayers.get(row.id) || [],
        createdAt: row.created_at,
      });
    }

    // Merge and sort by date. Whether a global slice follows depends on the
    // caller — see the header: the popup's first load must not be sliced, a
    // page of one tab's history must.
    // Walk-outs from matches that kept running. They have no match row of
    // their own — the match may still be in progress, and when it does end the
    // leaver is not on the roster — so they come from their own log and are
    // merged in by time like any other entry. Marked isMidGameLeave so the
    // client renders them as an event ("walked out of a Tichu game") rather
    // than trying to read a score off them.
    // A walk-out is filed under the game it happened in, so a page for one
    // game keeps its own and drops the rest.
    const midLeaveResult = !withMidLeave ? { rows: [] } : await client.query(
      `SELECT id, game_type, reason, room_name, players, created_at
         FROM tc_midleave_log
        WHERE nickname = $1 AND created_at >= $3
          AND ($4::text IS NULL OR game_type = $4)
        ORDER BY created_at DESC
        LIMIT $2`,
      [nickname, need, since, onlyGame],
    );
    const midLeaves = midLeaveResult.rows.map((row) => ({
      id: row.id,
      gameType: row.game_type,
      isMidGameLeave: true,
      // It is a desertion on your record; it just didn't decide a match.
      isDesertionLoss: true,
      won: false,
      isDraw: false,
      endReason: row.reason === 'timeout' ? 'mid_leave_timeout' : 'mid_leave',
      deserterNickname: nickname,
      roomName: row.room_name,
      // Shaped like the other game types' rosters so the history row can be
      // rendered the same way: a list of who you were playing with.
      players: parseMidLeavePlayers(row.players),
      // Seat fields for renderers that pick by gameType and know nothing about
      // walk-outs: the Tichu one reads these four seats plus two scores, and
      // without them draws "0 : 0" and "-·- : -·-".
      //
      // No app needs this any more — handleGetProfile withholds walk-out rows
      // from clients below MID_LEAVE_HISTORY_MIN_VERSION, and newer ones take
      // the isMidGameLeave branch. It stays for the admin dashboard, which
      // renders these rows server-side from this same function and has no
      // walk-out branch of its own. Delete it when that renderer grows one.
      ...tichuSeatsForMidLeave(nickname, parseMidLeavePlayers(row.players)),
      createdAt: row.created_at,
    }));

    const all = [
      ...tichuMatches, ...skMatches, ...llMatches, ...mightyMatches, ...midLeaves,
    ];
    all.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
    if (!paged) return all;
    // `hasMore` cannot be read off the slice alone: when the merged list ends
    // exactly at the page boundary it may still be a source that filled its
    // own LIMIT and has more behind it.
    const sourceFilled = [
      tichuResult, skResult, llResult, mightyResult, midLeaveResult,
    ].some((r) => r.rows.length >= need);
    // Ends at `need`, not at offset+limit: those differ only on the page that
    // runs into MATCH_HISTORY_MAX_DEPTH, and there the cap has to win or the
    // last page reads past the depth every source was fetched to.
    const page = all.slice(offset, need);
    return {
      matches: page,
      hasMore:
        need < MATCH_HISTORY_MAX_DEPTH &&
        (all.length > offset + limit || (page.length === limit && sourceFilled)),
    };
  } catch (err) {
    console.error('Get recent matches error:', err);
    return paged ? { matches: [], hasMore: false } : [];
  } finally {
    client.release();
  }
}

// Wallet
async function getWallet(nickname) {
  const client = await pool.connect();
  try {
    const result = await client.query(
      `SELECT gold, leave_count FROM tc_users WHERE nickname = $1`,
      [nickname]
    );
    if (result.rows.length === 0) {
      return { success: false, messageKey: 'db_user_not_found' };
    }
    return { success: true, wallet: result.rows[0] };
  } catch (err) {
    console.error('Get wallet error:', err);
    return { success: false, messageKey: 'db_wallet_fetch_failed' };
  } finally {
    client.release();
  }
}

/// [offset] pages the ledger for the backstage's full-history page. The
/// player-facing callers never pass it and keep the old single-page behaviour.
async function getGoldHistory(nickname, limit = 30, offset = 0) {
  const client = await pool.connect();
  try {
    // Same nickname-recycling guard as getRecentMatches: match rows and
    // tc_gold_history survive an account deletion under the original nickname,
    // so the next owner of that nickname must not inherit the ledger. Passed
    // as UTC text for the same reason as there — a JS Date would be sent with
    // the process's offset and lose nine hours to the timestamp cast.
    const sinceDate = (await client.query(
      `SELECT created_at FROM tc_users WHERE nickname = $1`, [nickname]
    )).rows[0]?.created_at || new Date(0);
    const since = new Date(sinceDate).toISOString().replace('T', ' ').replace('Z', '');
    const result = await client.query(
      `
      SELECT *
      FROM (
        SELECT
          mh.created_at,
          CASE
            WHEN mh.end_reason IN ('leave', 'timeout') AND mh.deserter_nickname = $1 THEN 0
            WHEN mh.end_reason IN ('leave', 'timeout') THEN 0
            WHEN (
              (mh.winner_team = 'A' AND $1 IN (mh.player_a1, mh.player_a2)) OR
              (mh.winner_team = 'B' AND $1 IN (mh.player_b1, mh.player_b2))
            ) THEN CASE WHEN mh.is_ranked THEN 20 ELSE 10 END
            WHEN mh.winner_team = 'draw' THEN 0
            ELSE CASE WHEN mh.is_ranked THEN 6 ELSE 3 END
          END AS gold_delta,
          'match' AS source,
          CASE
            WHEN mh.end_reason IN ('leave', 'timeout') AND mh.deserter_nickname = $1 THEN 'leave_defeat'
            WHEN (
              (mh.winner_team = 'A' AND $1 IN (mh.player_a1, mh.player_a2)) OR
              (mh.winner_team = 'B' AND $1 IN (mh.player_b1, mh.player_b2))
            ) THEN CASE WHEN mh.is_ranked THEN 'ranked_win' ELSE 'casual_win' END
            WHEN mh.winner_team = 'draw' THEN 'draw'
            ELSE CASE WHEN mh.is_ranked THEN 'ranked_loss' ELSE 'casual_loss' END
          END AS title,
          CONCAT(COALESCE(mh.team_a_score, 0), ':', COALESCE(mh.team_b_score, 0)) AS description
        FROM tc_match_history mh
        WHERE $1 IN (mh.player_a1, mh.player_a2, mh.player_b1, mh.player_b2)

        UNION ALL

        SELECT
          ar.claimed_at AS created_at,
          50 AS gold_delta,
          'ad_reward' AS source,
          'ad_reward' AS title,
          '' AS description
        FROM tc_ad_rewards ar
        WHERE ar.nickname = $1

        UNION ALL

        SELECT
          sr.created_at,
          sr.gold_reward AS gold_delta,
          'season_reward' AS source,
          'season_reward' AS title,
          sr.rank::text AS description
        FROM tc_season_rewards sr
        WHERE sr.nickname = $1

        UNION ALL

        SELECT
          h.created_at,
          CASE
            WHEN h.end_reason IN ('leave', 'timeout') AND h.deserter_nickname = $1 THEN 0
            WHEN p.is_winner THEN CASE WHEN h.is_ranked THEN 20 ELSE 10 END
            ELSE CASE WHEN h.is_ranked THEN 6 ELSE 3 END
          END AS gold_delta,
          'sk_match' AS source,
          CASE
            WHEN h.end_reason IN ('leave', 'timeout') AND h.deserter_nickname = $1 THEN 'sk_leave_defeat'
            WHEN p.is_winner THEN CASE WHEN h.is_ranked THEN 'sk_ranked_win' ELSE 'sk_casual_win' END
            ELSE CASE WHEN h.is_ranked THEN 'sk_ranked_loss' ELSE 'sk_casual_loss' END
          END AS title,
          CONCAT(p.rank, ':', p.score) AS description
        FROM tc_sk_match_players p
        JOIN tc_sk_match_history h ON h.id = p.match_id
        WHERE p.nickname = $1

        UNION ALL

        SELECT
          h.created_at,
          CASE
            WHEN h.end_reason IN ('leave', 'timeout') AND h.deserter_nickname = $1 THEN 0
            WHEN p.is_winner THEN 10
            ELSE 3
          END AS gold_delta,
          'll_match' AS source,
          CASE
            WHEN h.end_reason IN ('leave', 'timeout') AND h.deserter_nickname = $1 THEN 'll_leave_defeat'
            WHEN p.is_winner THEN 'll_win'
            ELSE 'll_loss'
          END AS title,
          CONCAT(p.rank, ':', p.score) AS description
        FROM tc_ll_match_players p
        JOIN tc_ll_match_history h ON h.id = p.match_id
        WHERE p.nickname = $1

        UNION ALL

        SELECT
          ui.acquired_at AS created_at,
          -si.price AS gold_delta,
          'shop_purchase' AS source,
          CONCAT(si.name_ko, '|', si.name_en, '|', si.name_de) AS title,
          'shop_purchase' AS description
        FROM tc_user_items ui
        JOIN tc_shop_items si ON si.item_key = ui.item_key
        WHERE ui.nickname = $1
          AND ui.source = 'shop'

        UNION ALL

        SELECT
          gh.created_at,
          gh.gold_delta,
          gh.source,
          gh.title,
          gh.description
        FROM tc_gold_history gh
        WHERE gh.nickname = $1
      ) history
      WHERE history.gold_delta <> 0
        AND history.created_at >= $3
      ORDER BY history.created_at DESC
      LIMIT $2 OFFSET $4
      `,
      [nickname, limit, since, Math.max(0, offset)]
    );

    return {
      success: true,
      history: result.rows.map((row) => ({
        createdAt: row.created_at,
        goldDelta: parseInt(row.gold_delta, 10) || 0,
        source: row.source,
        title: row.title,
        description: row.description,
      })),
    };
  } catch (err) {
    console.error('Get gold history error:', err);
    return { success: false, messageKey: 'db_gold_history_failed' };
  } finally {
    client.release();
  }
}

async function getAdminGoldHistory(nickname, limit = 50, offset = 0) {
  return getGoldHistory(nickname, limit, offset);
}

/// How long a marketing consent stands before it has to be confirmed.
/// 정보통신망법 §50 ⑧ — every two years from the date it was given.
const MARKETING_CONFIRM_INTERVAL = '2 years';
const MARKETING_CONFIRM_MS = 2 * 365 * 24 * 60 * 60 * 1000;

/// Same rule as the SQL above, for the login payload — that one row is already
/// in hand and a second round trip to ask the database a date question would
/// be on the critical path of every login.
function _marketingConfirmOverdue(since) {
  if (!since) return false;
  return Date.now() - new Date(since).getTime() >= MARKETING_CONFIRM_MS;
}

/// Is this account due the biennial "you are still subscribed" notice?
///
/// Counted from the last confirmation, or from the original consent if there
/// has never been one. Only opted-in accounts are due it — there is nothing to
/// confirm to someone who declined.
async function isMarketingConfirmDue(nickname) {
  const r = await pool.query(
    `SELECT marketing_push_enabled AS enabled,
            marketing_consent_at AS consented,
            COALESCE(marketing_confirmed_at, marketing_consent_at)
              < (NOW() AT TIME ZONE 'UTC') - INTERVAL '${MARKETING_CONFIRM_INTERVAL}'
              AS due
     FROM tc_users WHERE nickname = $1`,
    [nickname],
  );
  const row = r.rows[0];
  if (!row || row.enabled !== true) return { due: false, consentAt: null };
  return { due: row.due === true, consentAt: row.consented };
}

/// Record that the notice was shown and answered.
///
/// [keep] false is a withdrawal made in response to the notice, which is
/// exactly what the notice has to offer — so it goes through the same path any
/// other withdrawal does.
async function confirmMarketingConsent(nickname, keep) {
  if (!keep) {
    const off = await setMarketingConsent(nickname, false);
    // Stamped even on a withdrawal: it closes out this cycle, and if they opt
    // back in later the clock restarts from that new consent anyway.
    await pool.query(
      `UPDATE tc_users SET marketing_confirmed_at = (NOW() AT TIME ZONE 'UTC')
       WHERE nickname = $1`, [nickname]);
    return { success: off.success === true, enabled: false };
  }
  const r = await pool.query(
    `UPDATE tc_users SET marketing_confirmed_at = (NOW() AT TIME ZONE 'UTC')
     WHERE nickname = $1 RETURNING marketing_push_enabled`,
    [nickname],
  );
  if (r.rows.length === 0) return { success: false, messageKey: 'db_user_not_found' };
  return { success: true, enabled: r.rows[0].marketing_push_enabled === true };
}

/// How many opted-in accounts are overdue their confirmation, for the
/// backstage. A number that climbs means the notice is not reaching people —
/// it only shows on launch, and someone who has not opened the app cannot be
/// told anything.
async function getMarketingConfirmStats() {
  const r = await pool.query(
    `SELECT
       COUNT(*) FILTER (WHERE marketing_push_enabled)::int AS opted_in,
       COUNT(*) FILTER (
         WHERE marketing_push_enabled
           AND COALESCE(marketing_confirmed_at, marketing_consent_at)
               < (NOW() AT TIME ZONE 'UTC') - INTERVAL '${MARKETING_CONFIRM_INTERVAL}'
       )::int AS due
     FROM tc_users WHERE is_deleted IS NOT TRUE`,
  );
  return r.rows[0];
}

async function getAllFcmTokenRows() {
  const r = await pool.query(
    `SELECT id, nickname, fcm_token, fcm_token_invalid_at
     FROM tc_users
     WHERE is_deleted IS NOT TRUE
       AND fcm_token IS NOT NULL AND fcm_token <> ''
       AND fcm_token_invalid_at IS NULL
     ORDER BY id`,
  );
  return r.rows;
}

/// Mark a batch of tokens dead in one statement.
async function markFcmTokensInvalid(userIds) {
  if (!userIds.length) return 0;
  const r = await pool.query(
    `UPDATE tc_users SET fcm_token_invalid_at = (NOW() AT TIME ZONE 'UTC')
     WHERE id = ANY($1) AND fcm_token_invalid_at IS NULL`,
    [userIds],
  );
  return r.rowCount;
}

/// How many devices are reachable, and how many have gone away.
async function getFcmTokenStats() {
  const r = await pool.query(
    `SELECT
       COUNT(*) FILTER (
         WHERE fcm_token IS NOT NULL AND fcm_token <> ''
           AND fcm_token_invalid_at IS NULL)::int AS live,
       COUNT(*) FILTER (WHERE fcm_token_invalid_at IS NOT NULL)::int AS dead,
       MAX(fcm_token_invalid_at) AS last_death
     FROM tc_users WHERE is_deleted IS NOT TRUE`,
  );
  return r.rows[0];
}

/// Give someone an item that was not bought — a coupon reward or a campaign
/// payout — with the same ownership rules the shop uses.
///
/// buyItem refuses a permanent item you already own and extends a time-limited
/// one. A gift cannot refuse: the coupon is already spent, the notification is
/// already tapped. So the equivalent behaviour here is
///   - permanent and already owned → leave it alone, report it
///   - time-limited and still running → push the expiry out
///   - otherwise → insert
/// rather than stacking a second row. Duplicate rows would inflate the
/// backstage inventory and the "쓰는 중" holder counts, and there is no way to
/// own a permanent banner twice.
///
/// [days] overrides the shop's own duration (a coupon can hand out a week of
/// something the shop sells by the month). Runs on the caller's client so it
/// joins their transaction.
/**
 * Hand an item to a user from a coupon, a campaign, or a letter.
 *
 * [days] decides the shape of the grant, NOT the item's catalogue flag. A
 * permanent item given with days is a trial — a pioneer theme for a day, a
 * one-shot ticket that has to be used this week — which is a thing the staff
 * want to be able to do, and the reason days is honoured here even for
 * is_permanent rows. Without days it is permanent, whatever the item is.
 *
 * The one thing a timed grant must never do is take permanence away. Someone
 * who already owns the theme outright and then gets handed a one-day trial of
 * it keeps the theme: the trial is a no-op, not a downgrade.
 */
async function grantItemToUser(client, nickname, item, days, source) {
  const n = parseInt(days, 10);
  const timed = Number.isFinite(n) && n > 0;
  if (timed) {
    // Already held forever? Nothing a trial can add.
    const forever = await client.query(
      `SELECT 1 FROM tc_user_items
        WHERE nickname = $1 AND item_key = $2 AND expires_at IS NULL LIMIT 1`,
      [nickname, item.item_key],
    );
    if (forever.rows.length > 0) {
      return { itemKey: item.item_key, expiresAt: null, alreadyOwned: true };
    }
  }
  const permanent = !timed;
  if (permanent) {
    // Same split as buyItem: a permanent cosmetic is one entitlement (a
    // second grant has nothing to add), but a permanent *utility* item is a
    // one-shot consumable — holding several unused copies is normal, so a
    // mail/coupon/campaign grant must not no-op just because one is already
    // held.
    if (item.category !== 'utility') {
      const owned = await client.query(
        'SELECT 1 FROM tc_user_items WHERE nickname = $1 AND item_key = $2 LIMIT 1',
        [nickname, item.item_key],
      );
      if (owned.rows.length > 0) {
        return { itemKey: item.item_key, expiresAt: null, alreadyOwned: true };
      }
    }
    await client.query(
      `INSERT INTO tc_user_items (nickname, item_key, expires_at, is_active, source)
       VALUES ($1, $2, NULL, FALSE, $3)`,
      [nickname, item.item_key, source],
    );
    return { itemKey: item.item_key, expiresAt: null, alreadyOwned: false };
  }

  // Time-limited. Extend from now when it has already lapsed, the same rule
  // buyItem and the backstage's extend button use — adding days to a date in
  // the past hands over nothing.
  const existing = await client.query(
    `SELECT id FROM tc_user_items
      WHERE nickname = $1 AND item_key = $2 AND expires_at IS NOT NULL LIMIT 1`,
    [nickname, item.item_key],
  );
  if (existing.rows.length > 0) {
    const r = await client.query(
      `UPDATE tc_user_items
       SET expires_at = CASE
         WHEN expires_at < (NOW() AT TIME ZONE 'UTC')
           THEN (NOW() AT TIME ZONE 'UTC') + ($2 || ' days')::interval
         ELSE expires_at + ($2 || ' days')::interval END
       WHERE id = $1
       RETURNING expires_at`,
      [existing.rows[0].id, n],
    );
    return {
      itemKey: item.item_key,
      expiresAt: r.rows[0].expires_at,
      extended: true,
    };
  }
  const r = await client.query(
    `INSERT INTO tc_user_items (nickname, item_key, expires_at, is_active, source)
     VALUES ($1, $2, (NOW() AT TIME ZONE 'UTC') + ($3 || ' days')::interval,
             FALSE, $4)
     RETURNING expires_at`,
    [nickname, item.item_key, n, source],
  );
  return { itemKey: item.item_key, expiresAt: r.rows[0].expires_at };
}

// ===== Marketing push campaigns =====

/// Whether [when] falls in the window 광고성 정보 may not be sent in — 21:00 to
/// 08:00 Korean time.
///
/// The rule is about the RECIPIENT's local night, and the overwhelming
/// majority of players are in Korea, so KST is the yardstick. Computed from
/// the UTC instant rather than the host clock: production runs UTC and a
/// developer's machine does not, and a guard that only holds on one of them is
/// not a guard.
function isKstNight(when = new Date()) {
  const kstHour = Math.floor(
    (((when.getTime() + 9 * 3600 * 1000) % 86400000) + 86400000) % 86400000
    / 3600000,
  );
  return kstHour >= 21 || kstHour < 8;
}

/// Who a marketing push may go to right now.
///
/// Consent is read here, at send time, from the database. That is the whole
/// argument against FCM topics for this: with a topic, consent lives in a
/// subscription the device has to remember to cancel, so a withdrawal that
/// fails to reach FCM keeps delivering ads to someone who said stop. Here a
/// withdrawal is one UPDATE and the next send simply does not include them.
async function getMarketingAudience(targetFilter = 'all') {
  const params = [];
  let q = `SELECT id, nickname, fcm_token
           FROM tc_users
           WHERE marketing_push_enabled = TRUE
             AND push_enabled = TRUE
             AND is_deleted IS NOT TRUE
             AND fcm_token IS NOT NULL AND fcm_token <> ''
             AND fcm_token_invalid_at IS NULL
             -- Overdue the two-yearly confirmation means the consent is no
             -- longer good enough to send on (정보통신망법 §50 ⑧). They come
             -- back into the audience the moment they answer the notice, which
             -- is raised on their next launch. Leaving them in is the exact
             -- thing the rule exists to stop, and the backstage's "2년 재확인
             -- 대기" count is how you see it happening.
             AND COALESCE(marketing_confirmed_at, marketing_consent_at)
                 >= (NOW() AT TIME ZONE 'UTC')
                    - INTERVAL '${MARKETING_CONFIRM_INTERVAL}'`;
  if (targetFilter === 'ios' || targetFilter === 'android') {
    params.push(targetFilter);
    q += ` AND device_platform = $1`;
  }
  const r = await pool.query(q, params);
  return r.rows;
}

/// Record a yes or no, and when. Returns the stored state.
async function setMarketingConsent(nickname, enabled) {
  const r = await pool.query(
    `UPDATE tc_users
     SET marketing_push_enabled = $2,
         marketing_asked_at = (NOW() AT TIME ZONE 'UTC'),
         -- Only a yes stamps the consent time; a withdrawal leaves the
         -- original date in place, since "consented on X, withdrew on Y" is
         -- the pair you have to be able to show.
         marketing_consent_at = CASE WHEN $2 THEN (NOW() AT TIME ZONE 'UTC')
                                     ELSE marketing_consent_at END,
         -- A fresh yes restarts the two-year clock. Without this, someone who
         -- withdrew and later opted back in would be immediately overdue on a
         -- confirmation date left over from their previous subscription.
         marketing_confirmed_at = CASE WHEN $2 THEN NULL
                                       ELSE marketing_confirmed_at END
     WHERE nickname = $1
     RETURNING marketing_push_enabled, marketing_consent_at`,
    [nickname, !!enabled],
  );
  if (r.rows.length === 0) return { success: false, messageKey: 'db_user_not_found' };
  return {
    success: true,
    enabled: r.rows[0].marketing_push_enabled === true,
    consentAt: r.rows[0].marketing_consent_at,
  };
}

/// Has this account been asked yet? The client shows the consent popup once,
/// and "never asked" is not the same as "said no".
async function getMarketingConsentState(nickname) {
  const r = await pool.query(
    `SELECT marketing_push_enabled, marketing_asked_at FROM tc_users WHERE nickname = $1`,
    [nickname],
  );
  if (r.rows.length === 0) return null;
  return {
    enabled: r.rows[0].marketing_push_enabled === true,
    asked: r.rows[0].marketing_asked_at != null,
  };
}

async function createPushCampaign(data, actor = 'admin') {
  const r = await pool.query(
    `INSERT INTO tc_push_campaigns
       (title, body, reward_gold, reward_item_key, reward_days,
        claim_deadline, target_filter, created_by)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING id`,
    [
      String(data.title || '').slice(0, 200),
      String(data.body || ''),
      parseInt(data.rewardGold, 10) || 0,
      data.rewardItemKey || null,
      data.rewardDays ? parseInt(data.rewardDays, 10) : null,
      data.claimDeadline ? toUtcTimestampText(data.claimDeadline) : null,
      data.targetFilter || 'all',
      actor,
    ],
  );
  return { success: true, id: r.rows[0].id };
}

async function listPushCampaigns(limit = 50) {
  const r = await pool.query(
    `SELECT c.*,
            (SELECT COUNT(*) FROM tc_push_campaign_recipients cr
              WHERE cr.campaign_id = c.id AND cr.status = 'sent')::int AS sent,
            (SELECT COUNT(*) FROM tc_push_campaign_recipients cr
              WHERE cr.campaign_id = c.id AND cr.opened_at IS NOT NULL)::int AS opened,
            (SELECT COUNT(*) FROM tc_push_campaign_recipients cr
              WHERE cr.campaign_id = c.id AND cr.claimed_at IS NOT NULL)::int AS claimed
     FROM tc_push_campaigns c
     ORDER BY c.created_at DESC LIMIT $1`,
    [limit],
  );
  return r.rows;
}

async function getPushCampaign(id) {
  const r = await pool.query('SELECT * FROM tc_push_campaigns WHERE id = $1', [id]);
  return r.rows[0] || null;
}

async function deletePushCampaign(id) {
  await pool.query('DELETE FROM tc_push_campaigns WHERE id = $1', [id]);
  return { success: true };
}

/// Put the audience on record BEFORE anything is sent.
///
/// The recipient row is what entitles someone to the reward, and a push cannot
/// be recalled. Writing the rows first means the only two outcomes are "no
/// notification and no rows" (retry it) or "notification and rows" (works).
/// Doing it the other way round has a third: the notification lands, the write
/// fails, and everyone who taps is told the reward is not theirs.
///
/// Rows start as 'pending'; recordCampaignSend settles them to sent/failed
/// once FCM has answered. claimPushCampaign also checks the campaign itself is
/// open, so a reserved row is not enough to claim before any delivery happened.
async function reserveCampaignRecipients(campaignId, nicknames) {
  if (!nicknames.length) return { success: true, reserved: 0 };
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    for (const nickname of nicknames) {
      await client.query(
        `INSERT INTO tc_push_campaign_recipients (campaign_id, nickname, status)
         VALUES ($1, $2, 'pending')
         ON CONFLICT (campaign_id, nickname) DO NOTHING`,
        [campaignId, nickname],
      );
    }
    await client.query('COMMIT');
    return { success: true, reserved: nicknames.length };
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Reserve campaign recipients error:', err);
    return { success: false, message: err.message };
  } finally {
    client.release();
  }
}

/// Open a campaign for claims. Called the moment FCM reports a delivery.
///
/// Deliberately one small UPDATE, separate from the per-recipient tally. The
/// tally loops over the whole audience and is the part most likely to fail
/// halfway; if opening the campaign were bundled into it, a failure there
/// would leave everyone holding a notification the server refuses to pay out
/// on. Opening first means the worst case is wrong statistics.
async function openCampaignForClaims(campaignId) {
  try {
    await pool.query(
      `UPDATE tc_push_campaigns
       SET status = 'sent',
           sent_at = COALESCE(sent_at, (NOW() AT TIME ZONE 'UTC'))
       WHERE id = $1`,
      [campaignId],
    );
    return { success: true };
  } catch (err) {
    console.error('Open campaign error:', err);
    return { success: false, message: err.message };
  }
}

/// Write the audience down and mark the campaign sent.
///
/// [results] is what sendBroadcastPush reports per token. Failures are stored
/// too, with their status: an audience of 1,000 that reached 400 is a delivery
/// problem, and a table that only holds the 400 hides it.
async function recordCampaignSend(campaignId, results) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    let sent = 0;
    let failed = 0;
    for (const r of results) {
      if (r.success) sent++; else failed++;
      await client.query(
        `INSERT INTO tc_push_campaign_recipients (campaign_id, nickname, status)
         VALUES ($1, $2, $3)
         ON CONFLICT (campaign_id, nickname) DO UPDATE
           -- A retry after a partial failure must be able to turn a failed row
           -- into a sent one. Never the other way round: once it reached them,
           -- a later attempt that fails does not un-deliver it, and the row is
           -- what entitles them to the reward.
           SET status = CASE WHEN tc_push_campaign_recipients.status = 'sent'
                             THEN 'sent' ELSE EXCLUDED.status END`,
        [campaignId, r.nickname, r.success ? 'sent' : 'failed'],
      );
    }
    // Only a send that reached somebody counts as sent. A total failure is
    // Firebase being unreachable or misconfigured, and burning the campaign
    // for it would mean rebuilding it by hand to try again — so it stays a
    // draft and the button stays available.
    const delivered = sent > 0;
    await client.query(
      `UPDATE tc_push_campaigns
       -- Cast once: without it Postgres deduces one type for the assignment
       -- and another for the comparison and refuses the statement.
       SET status = $4::varchar,
           sent_at = CASE WHEN $4::varchar = 'sent' THEN (NOW() AT TIME ZONE 'UTC')
                          ELSE sent_at END,
           sent_count = $2, fail_count = $3
       WHERE id = $1`,
      [campaignId, sent, failed, delivered ? 'sent' : 'draft'],
    );
    await client.query('COMMIT');
    return { success: delivered, sent, failed };
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Record campaign send error:', err);
    return { success: false, message: err.message };
  } finally {
    client.release();
  }
}

/// Tapping the notification: mark the open, and pay out once.
///
/// Every refusal is a real case, not defensive padding:
///  - no recipient row → this account was not sent the campaign. Campaign ids
///    are small integers that travel to the client, so without this check
///    anyone could guess one and collect.
///  - already claimed → the tap handler can fire twice (cold start plus the
///    resume callback), and a retry after a dropped reply is normal.
///  - past the deadline → the notification stays on the phone for days.
///
/// The open is recorded even when the reward is refused. "500 sent, 300
/// opened, 12 claimed" is the shape of a deadline that was too short, and you
/// cannot see it if a late tap leaves no trace.
// ─── 운영자 우편함 ──────────────────────────────────────────────────────────

/**
 * Send one letter to one, several, or every player.
 *
 * Addressees are written as rows at send time even for "everyone". Deriving
 * the audience at read time instead would keep silently adding people — an
 * account made next month would find a letter about last month's incident in
 * its mailbox — and could never answer how many have read it.
 *
 * Unknown nicknames are reported back rather than skipped: sending a
 * compensation letter to a name with a typo in it should not look like it
 * worked.
 */
async function sendMail({
  title, body, rewardGold = 0, rewardItemKey = null, rewardDays = null,
  expiresAt = null, targetKind = 'user', nicknames = [], createdBy = 'admin',
  senderName = null,
}) {
  const cleanTitle = (title || '').trim();
  const cleanBody = (body || '').trim();
  if (!cleanTitle || !cleanBody) {
    return { success: false, message: '제목과 내용을 입력해 주세요.' };
  }
  const gold = Math.max(0, parseInt(rewardGold, 10) || 0);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    if (rewardItemKey) {
      const item = await client.query(
        'SELECT 1 FROM tc_shop_items WHERE item_key = $1', [rewardItemKey]);
      if (item.rows.length === 0) {
        await client.query('ROLLBACK');
        return { success: false, message: '없는 아이템입니다.' };
      }
    }

    let targets = [];
    let missing = [];
    if (targetKind === 'all') {
      targets = (await client.query(
        `SELECT nickname FROM tc_users WHERE is_deleted IS NOT TRUE`)).rows.map((r) => r.nickname);
    } else {
      const wanted = [...new Set((nicknames || [])
        .map((n) => String(n || '').trim()).filter(Boolean))];
      if (wanted.length === 0) {
        await client.query('ROLLBACK');
        return { success: false, message: '받는 사람을 지정해 주세요.' };
      }
      const found = (await client.query(
        `SELECT nickname FROM tc_users
          WHERE nickname = ANY($1) AND is_deleted IS NOT TRUE`, [wanted])).rows.map((r) => r.nickname);
      targets = found;
      missing = wanted.filter((n) => !found.includes(n));
      if (found.length === 0) {
        await client.query('ROLLBACK');
        return { success: false, message: `받는 사람을 찾을 수 없습니다: ${missing.join(', ')}` };
      }
    }

    const mail = await client.query(
      `INSERT INTO tc_mail
         (title, body, reward_gold, reward_item_key, reward_days, expires_at,
          target_kind, target_note, created_by, sender_name)
       VALUES ($1, $2, $3, $4, $5, $6::timestamp, $7, $8, $9, $10)
       RETURNING id`,
      [cleanTitle, cleanBody, gold, rewardItemKey || null,
        rewardDays != null ? parseInt(rewardDays, 10) : null,
        expiresAt ? toUtcTimestampText(expiresAt) : null, targetKind,
        targetKind === 'all' ? '전체' : targets.slice(0, 5).join(', ')
          + (targets.length > 5 ? ` 외 ${targets.length - 5}명` : ''),
        createdBy,
        // Blank stays NULL rather than becoming an empty string: the client
        // decides between "a name was given" and "use the default" by null.
        (senderName || '').trim().slice(0, 60) || null],
    );
    const mailId = mail.rows[0].id;
    // One statement rather than a loop: 500 round trips for a mail to
    // everybody is the difference between instant and a visible stall.
    await client.query(
      `INSERT INTO tc_mail_recipients (mail_id, nickname)
       SELECT $1, UNNEST($2::varchar[])
       ON CONFLICT (mail_id, nickname) DO NOTHING`,
      [mailId, targets],
    );
    // "몇 명에게 보냈는가" 는 보낸 순간에 정해지는 사실이다. 세어서 구하면
    // 나중에 누가 우편함을 정리했을 때 지난 발송의 숫자가 바뀐다.
    await client.query(
      `UPDATE tc_mail SET final_recipients =
         (SELECT COUNT(*)::int FROM tc_mail_recipients WHERE mail_id = $1)
        WHERE id = $1`, [mailId]);
    await client.query('COMMIT');
    return { success: true, id: mailId, sent: targets.length, missing, targets };
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('sendMail error:', err);
    return { success: false, message: err.message };
  } finally {
    client.release();
  }
}

/**
 * How long a letter stays in a mailbox.
 *
 * Told to the player on the mailbox screen, so it is a promise: after this the
 * letter is gone from their app AND unclaimable, not merely hidden. The rows
 * are swept on the same schedule (purgeOldMail) — the filter is what makes the
 * promise true the moment it passes, without waiting for the sweep.
 */
const MAIL_RETENTION_DAYS = 14;

/** One player's mailbox, newest first. */
async function getMailbox(nickname, limit = 50) {
  try {
    const res = await pool.query(
      `SELECT m.id, m.title, m.body, m.reward_gold, m.reward_item_key, m.reward_days,
              m.expires_at, m.created_at, m.sender_name, r.read_at, r.claimed_at,
              si.name_ko AS item_name_ko, si.name_en AS item_name_en, si.name_de AS item_name_de,
              si.is_permanent AS item_permanent
         FROM tc_mail_recipients r
         JOIN tc_mail m ON m.id = r.mail_id
         JOIN tc_users u ON u.nickname = r.nickname
         LEFT JOIN tc_shop_items si ON si.item_key = m.reward_item_key
        WHERE r.nickname = $1
          AND r.deleted_at IS NULL
          -- A recycled nickname must not inherit the previous owner's post.
          AND r.created_at >= u.created_at
          AND r.created_at >= (NOW() AT TIME ZONE 'UTC') - ($3 || ' days')::interval
        ORDER BY m.created_at DESC
        LIMIT $2`,
      [nickname, Math.max(1, Math.min(parseInt(limit, 10) || 50, 200)), MAIL_RETENTION_DAYS],
    );
    return { success: true, mail: res.rows, retentionDays: MAIL_RETENTION_DAYS };
  } catch (err) {
    console.error('getMailbox error:', err);
    return { success: false, mail: [], message: err.message };
  }
}

/**
 * Letters still wanting something from the player.
 *
 * Unread ones, and read ones whose reward is still sitting there. Reading is
 * not the point of a letter that has gold in it — a badge that clears on open
 * lets someone read it, mean to claim later, and never see a reminder again.
 * The mark comes off when the reward does.
 *
 * A reward past its deadline stops counting: there is nothing left to collect,
 * so keeping the badge would only be nagging about something already lost.
 */
async function getUnreadMailCount(nickname) {
  try {
    const r = await pool.query(
      `SELECT COUNT(*)::int AS n
         FROM tc_mail_recipients r
         JOIN tc_mail m ON m.id = r.mail_id
         JOIN tc_users u ON u.nickname = r.nickname
        WHERE r.nickname = $1 AND r.deleted_at IS NULL
          AND r.created_at >= u.created_at
          AND r.created_at >= (NOW() AT TIME ZONE 'UTC') - ($2 || ' days')::interval
          AND (
            r.read_at IS NULL
            OR (r.claimed_at IS NULL
                AND (m.reward_gold > 0 OR m.reward_item_key IS NOT NULL)
                AND (m.expires_at IS NULL
                     OR m.expires_at >= (NOW() AT TIME ZONE 'UTC')))
          )`,
      [nickname, MAIL_RETENTION_DAYS]);
    return r.rows[0].n;
  } catch (err) {
    console.error('getUnreadMailCount error:', err.message);
    return 0;
  }
}

async function markMailRead(nickname, mailId) {
  try {
    await pool.query(
      // 조회·수령과 같은 조건으로 막는다. 닉네임은 재사용되므로 mail_id 와
      // 닉네임만 보면, 새 주인이 mailId 를 알아내 이전 주인의 사본을 읽음으로
      // 바꿔놓을 수 있다 — 읽지는 못해도 상태는 건드려진다. 보존 기간이 지난
      // 사본도 마찬가지로 손대지 않는다.
      `UPDATE tc_mail_recipients r
          SET read_at = COALESCE(r.read_at, (NOW() AT TIME ZONE 'UTC'))
         FROM tc_users u
        WHERE r.mail_id = $1 AND r.nickname = $2 AND r.deleted_at IS NULL
          AND u.nickname = r.nickname
          AND r.created_at >= u.created_at
          AND r.created_at >= (NOW() AT TIME ZONE 'UTC') - ($3 || ' days')::interval`,
      [parseInt(mailId, 10), nickname, MAIL_RETENTION_DAYS]);
    return { success: true };
  } catch (err) {
    console.error('markMailRead error:', err.message);
    return { success: false };
  }
}

/**
 * Take the reward out of a letter.
 *
 * Same discipline as the campaign claim below, for the same reasons: the row
 * is locked before anything is granted, an already-claimed row answers so
 * without paying twice, and the nickname must have belonged to this account
 * when the letter was sent.
 */
async function claimMail(nickname, mailId) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const rec = await client.query(
      `SELECT r.id, r.claimed_at FROM tc_mail_recipients r
         JOIN tc_users u ON u.nickname = r.nickname
        WHERE r.mail_id = $1 AND r.nickname = $2 AND r.deleted_at IS NULL
          AND r.created_at >= u.created_at
          AND r.created_at >= (NOW() AT TIME ZONE 'UTC') - ($3 || ' days')::interval
        FOR UPDATE OF r`,
      [parseInt(mailId, 10), nickname, MAIL_RETENTION_DAYS]);
    if (rec.rows.length === 0) {
      await client.query('ROLLBACK');
      return { success: false, messageKey: 'mail_not_yours' };
    }
    await client.query(
      `UPDATE tc_mail_recipients SET read_at = COALESCE(read_at, (NOW() AT TIME ZONE 'UTC'))
        WHERE id = $1`, [rec.rows[0].id]);
    if (rec.rows[0].claimed_at) {
      await client.query('COMMIT');
      return { success: false, messageKey: 'mail_already_claimed' };
    }
    const mail = (await client.query('SELECT * FROM tc_mail WHERE id = $1', [mailId])).rows[0];
    if (!mail) {
      await client.query('ROLLBACK');
      return { success: false, messageKey: 'mail_not_found' };
    }
    const expired = (await client.query(
      `SELECT $1::timestamp IS NOT NULL
              AND $1::timestamp < (NOW() AT TIME ZONE 'UTC') AS expired`,
      [mail.expires_at])).rows[0].expired;
    if (expired) {
      await client.query('COMMIT'); // it still counts as read
      return { success: false, messageKey: 'mail_expired' };
    }

    let reward = null;
    if (mail.reward_gold > 0) {
      const updated = await client.query(
        'UPDATE tc_users SET gold = gold + $2 WHERE nickname = $1 RETURNING gold',
        [nickname, mail.reward_gold]);
      if (updated.rows.length === 0) {
        await client.query('ROLLBACK');
        return { success: false, messageKey: 'db_user_not_found' };
      }
      await client.query(
        `INSERT INTO tc_gold_history (nickname, gold_delta, source, title, description)
         VALUES ($1, $2, 'mail', $3, $4)`,
        [nickname, mail.reward_gold, mail.title, `mail:${mail.id}`]);
      reward = { type: 'gold', gold: mail.reward_gold, newGold: updated.rows[0].gold };
    } else if (mail.reward_item_key) {
      const item = (await client.query(
        `SELECT item_key, category, is_permanent, duration_days FROM tc_shop_items WHERE item_key = $1`,
        [mail.reward_item_key])).rows[0];
      if (!item) {
        await client.query('ROLLBACK');
        return { success: false, messageKey: 'db_item_not_found' };
      }
      const days = mail.reward_days != null ? mail.reward_days : item.duration_days;
      const granted = await grantItemToUser(client, nickname, item, days, 'mail');
      reward = {
        type: 'item', itemKey: granted.itemKey, days: days ?? null,
        alreadyOwned: granted.alreadyOwned === true,
      };
    }

    await client.query(
      `UPDATE tc_mail_recipients SET claimed_at = (NOW() AT TIME ZONE 'UTC') WHERE id = $1`,
      [rec.rows[0].id]);
    await client.query('COMMIT');
    return { success: true, reward, title: mail.title };
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('claimMail error:', err);
    return { success: false, messageKey: 'mail_claim_failed' };
  } finally {
    client.release();
  }
}

/**
 * A player throwing away a letter they are done with.
 *
 * Only their own copy goes; the letter itself and everyone else's copy stay.
 * Refused while a reward is still sitting in it — deleting is a tidy-up
 * gesture, and a tidy-up that silently costs you 500 gold is a trap. Once the
 * reward is claimed (or its deadline has passed, so there is nothing left to
 * lose) it can go.
 */
async function deleteMailForUser(nickname, mailId) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const rec = await client.query(
      `SELECT r.id, r.read_at, r.claimed_at,
              m.reward_gold, m.reward_item_key, m.expires_at,
              (m.expires_at IS NOT NULL
                AND m.expires_at < (NOW() AT TIME ZONE 'UTC')) AS reward_closed
         FROM tc_mail_recipients r
         JOIN tc_mail m ON m.id = r.mail_id
         JOIN tc_users u ON u.nickname = r.nickname
        WHERE r.mail_id = $1 AND r.nickname = $2 AND r.deleted_at IS NULL
          -- 읽음 처리와 같은 이유 — 재사용된 닉네임이 이전 주인의 사본을
          -- 지워버리지 못하게.
          AND r.created_at >= u.created_at
          AND r.created_at >= (NOW() AT TIME ZONE 'UTC') - ($3 || ' days')::interval
        FOR UPDATE OF r`,
      [parseInt(mailId, 10), nickname, MAIL_RETENTION_DAYS]);
    if (rec.rows.length === 0) {
      await client.query('ROLLBACK');
      return { success: false, messageKey: 'mail_not_yours' };
    }
    const row = rec.rows[0];
    const hasReward = row.reward_gold > 0 || !!row.reward_item_key;
    if (hasReward && !row.claimed_at && !row.reward_closed) {
      await client.query('ROLLBACK');
      return { success: false, messageKey: 'mail_claim_first' };
    }
    // 지우는 게 아니라 감춘다 — 위 deleted_at 주석 참고.
    await client.query(
      `UPDATE tc_mail_recipients SET deleted_at = (NOW() AT TIME ZONE 'UTC')
        WHERE id = $1`, [row.id]);
    await client.query('COMMIT');
    return { success: true };
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('deleteMailForUser error:', err);
    return { success: false, messageKey: 'mail_delete_failed' };
  } finally {
    client.release();
  }
}

/**
 * Drop addressee rows past the retention window.
 *
 * The counts are written onto the letter first. The backstage's "how many read
 * it, how many claimed" is derived from these rows, so deleting them without a
 * snapshot would quietly rewrite history to zero a month after every send.
 *
 * The letter row itself is kept — it is the record that it was sent at all.
 */
async function purgeOldMail(days = MAIL_RETENTION_DAYS) {
  const n = Math.max(1, parseInt(days, 10) || MAIL_RETENTION_DAYS);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(
      `UPDATE tc_mail m
          SET final_recipients = COALESCE(m.final_recipients, c.total),
              final_read       = COALESCE(m.final_read, c.read_n),
              final_claimed    = COALESCE(m.final_claimed, c.claimed_n)
         FROM (SELECT mail_id,
                      COUNT(*)::int AS total,
                      COUNT(*) FILTER (WHERE read_at IS NOT NULL)::int AS read_n,
                      COUNT(*) FILTER (WHERE claimed_at IS NOT NULL)::int AS claimed_n
                 FROM tc_mail_recipients
                WHERE created_at < (NOW() AT TIME ZONE 'UTC') - ($1 || ' days')::interval
                GROUP BY mail_id) c
        WHERE m.id = c.mail_id`,
      [n]);
    const gone = await client.query(
      `DELETE FROM tc_mail_recipients
        WHERE created_at < (NOW() AT TIME ZONE 'UTC') - ($1 || ' days')::interval`,
      [n]);
    await client.query('COMMIT');
    if (gone.rowCount) console.log(`[mail] purged ${gone.rowCount} letter copies older than ${n}d`);
    return { success: true, purged: gone.rowCount };
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('purgeOldMail error:', err.message);
    return { success: false, message: err.message };
  } finally {
    client.release();
  }
}

/** Sent mail with how far it got, for the backstage list. */
async function listMail({ page = 1, limit = 25 } = {}) {
  const lim = Math.max(1, Math.min(parseInt(limit, 10) || 25, 100));
  const off = (Math.max(1, parseInt(page, 10) || 1) - 1) * lim;
  try {
    const total = parseInt((await pool.query('SELECT COUNT(*) FROM tc_mail')).rows[0].count, 10);
    const rows = await pool.query(
      `SELECT m.*,
              -- Snapshot first: after the copies are purged it is all that is
              -- left, and a live count would read as nobody having got it.
              COALESCE(m.final_recipients,
                (SELECT COUNT(*) FROM tc_mail_recipients r WHERE r.mail_id = m.id)::int) AS recipients,
              COALESCE(m.final_read,
                (SELECT COUNT(*) FROM tc_mail_recipients r
                  WHERE r.mail_id = m.id AND r.read_at IS NOT NULL)::int) AS read_count,
              COALESCE(m.final_claimed,
                (SELECT COUNT(*) FROM tc_mail_recipients r
                  WHERE r.mail_id = m.id AND r.claimed_at IS NOT NULL)::int) AS claimed_count,
              si.name_ko AS item_name_ko
         FROM tc_mail m
         LEFT JOIN tc_shop_items si ON si.item_key = m.reward_item_key
        ORDER BY m.created_at DESC LIMIT $1 OFFSET $2`,
      [lim, off]);
    return { success: true, rows: rows.rows, total, page: Math.max(1, parseInt(page, 10) || 1), limit: lim };
  } catch (err) {
    console.error('listMail error:', err);
    return { success: false, rows: [], total: 0, page: 1, limit: lim, message: err.message };
  }
}

async function getMailDetail(id, { limit = 200 } = {}) {
  try {
    const mail = (await pool.query('SELECT * FROM tc_mail WHERE id = $1', [id])).rows[0];
    if (!mail) return null;
    const recipients = await pool.query(
      `SELECT nickname, read_at, claimed_at FROM tc_mail_recipients
        WHERE mail_id = $1 ORDER BY claimed_at DESC NULLS LAST, read_at DESC NULLS LAST, nickname
        LIMIT $2`, [id, limit]);
    return { mail, recipients: recipients.rows };
  } catch (err) {
    console.error('getMailDetail error:', err);
    return null;
  }
}

/**
 * Delete a letter and everyone's copy of it (ON DELETE CASCADE).
 *
 * Rewards go with it: a claimed row disappearing is only safe because the
 * letter it belonged to is gone too, so there is nothing left to claim from.
 */
async function deleteMail(id) {
  try {
    await pool.query('DELETE FROM tc_mail WHERE id = $1', [id]);
    return { success: true };
  } catch (err) {
    console.error('deleteMail error:', err);
    return { success: false, message: err.message };
  }
}

async function claimPushCampaign(nickname, campaignId) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    // The recipient row must predate nothing and postdate the account. A
    // deleted account frees its nickname (deleteUser renames the old row), so
    // without the created_at floor the next person to take that nickname
    // inherits its unclaimed rewards — the same guard getRecentMatches and the
    // gold ledger already apply for the same reason.
    const rec = await client.query(
      `SELECT r.id, r.claimed_at FROM tc_push_campaign_recipients r
       JOIN tc_users u ON u.nickname = r.nickname
       WHERE r.campaign_id = $1 AND r.nickname = $2
         AND r.status <> 'failed'
         AND r.created_at >= u.created_at
       FOR UPDATE OF r`,
      [campaignId, nickname],
    );
    if (rec.rows.length === 0) {
      await client.query('ROLLBACK');
      return { success: false, messageKey: 'push_reward_not_yours' };
    }
    await client.query(
      `UPDATE tc_push_campaign_recipients
       SET opened_at = COALESCE(opened_at, (NOW() AT TIME ZONE 'UTC'))
       WHERE id = $1`,
      [rec.rows[0].id],
    );
    if (rec.rows[0].claimed_at) {
      await client.query('COMMIT');
      return { success: false, messageKey: 'push_reward_already_claimed' };
    }
    const camp = (await client.query(
      `SELECT * FROM tc_push_campaigns WHERE id = $1`, [campaignId])).rows[0];
    if (!camp) {
      await client.query('ROLLBACK');
      return { success: false, messageKey: 'push_reward_not_found' };
    }
    // The recipient rows are written BEFORE the push goes out, so that a
    // failed write can never strand a delivered notification. That leaves a
    // window where rows exist and nothing has been sent — and campaign ids are
    // small integers a client could simply guess. So existence of the row is
    // not enough: the campaign has to have been opened by an actual delivery.
    if (camp.status !== 'sent') {
      await client.query('ROLLBACK');
      return { success: false, messageKey: 'push_reward_not_yours' };
    }
    const expired = (await client.query(
      `SELECT claim_deadline IS NOT NULL
              AND claim_deadline < (NOW() AT TIME ZONE 'UTC') AS expired
         FROM tc_push_campaigns
        WHERE id = $1`,
      [campaignId])).rows[0]?.expired === true;
    if (expired) {
      await client.query('COMMIT'); // the open still counts
      return { success: false, messageKey: 'push_reward_expired' };
    }

    let reward = null;
    if (camp.reward_gold > 0) {
      const updated = await client.query(
        'UPDATE tc_users SET gold = gold + $2 WHERE nickname = $1 RETURNING gold',
        [nickname, camp.reward_gold],
      );
      if (updated.rows.length === 0) {
        await client.query('ROLLBACK');
        return { success: false, messageKey: 'db_user_not_found' };
      }
      await client.query(
        `INSERT INTO tc_gold_history (nickname, gold_delta, source, title, description)
         VALUES ($1, $2, 'push_campaign', $3, $4)`,
        [nickname, camp.reward_gold, camp.title, `campaign:${campaignId}`],
      );
      reward = { type: 'gold', gold: camp.reward_gold, newGold: updated.rows[0].gold };
    } else if (camp.reward_item_key) {
      const item = (await client.query(
        `SELECT item_key, category, is_permanent, duration_days FROM tc_shop_items
         WHERE item_key = $1`, [camp.reward_item_key])).rows[0];
      if (!item) {
        await client.query('ROLLBACK');
        return { success: false, messageKey: 'db_item_not_found' };
      }
      const days = camp.reward_days != null ? camp.reward_days : item.duration_days;
      const granted = await grantItemToUser(
        client, nickname, item, days, 'push_campaign',
      );
      reward = {
        type: 'item',
        itemKey: granted.itemKey,
        days: days ?? null,
        alreadyOwned: granted.alreadyOwned === true,
      };
    } else {
      // A campaign with no reward is a plain announcement; the tap is still
      // worth recording, and the client is told there is nothing to show.
      await client.query(
        `UPDATE tc_push_campaign_recipients SET claimed_at = (NOW() AT TIME ZONE 'UTC')
         WHERE id = $1`, [rec.rows[0].id]);
      await client.query('COMMIT');
      return { success: true, reward: null };
    }

    await client.query(
      `UPDATE tc_push_campaign_recipients SET claimed_at = (NOW() AT TIME ZONE 'UTC')
       WHERE id = $1`, [rec.rows[0].id]);
    await client.query('COMMIT');
    return { success: true, reward, title: camp.title };
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Claim push campaign error:', err);
    return { success: false, messageKey: 'push_reward_failed' };
  } finally {
    client.release();
  }
}

async function getCampaignRecipients(campaignId, limit = 200, offset = 0) {
  const r = await pool.query(
    `SELECT nickname, status, opened_at, claimed_at, created_at
     FROM tc_push_campaign_recipients
     WHERE campaign_id = $1
     ORDER BY claimed_at DESC NULLS LAST, opened_at DESC NULLS LAST, nickname
     LIMIT $2 OFFSET $3`,
    [campaignId, limit + 1, offset],
  );
  return { rows: r.rows.slice(0, limit), hasMore: r.rows.length > limit };
}

/// Every shop purchase, newest first — who bought what, when, for how much.
///
/// Two sources, because a renewal is not a row. buyItem INSERTs a
/// tc_user_items row for a first purchase but UPDATEs the expiry for a repeat
/// one, writing a tc_gold_history row instead. A log built on tc_user_items
/// alone silently omits every renewal, which is most of the revenue on an item
/// people keep. Both are unioned here, and each row says which it was.
///
/// The ledger side only stores the item's display names ("ko|en|de"), not its
/// key, so the key and category are looked up by Korean name in a scalar
/// subquery. A scalar subquery rather than a join: two items sharing a name
/// would multiply the row instead of just picking one.
///
/// [opts] — { itemKey, nickname, limit, offset }. Both filters are optional
/// and combine.
async function getShopPurchaseLog(opts = {}) {
  const limit = Math.min(200, Math.max(1, opts.limit || 50));
  const offset = Math.max(0, opts.offset || 0);
  const itemKey = opts.itemKey || null;
  const nickname = opts.nickname ? `%${opts.nickname}%` : null;
  const client = await pool.connect();
  try {
    const result = await client.query(
      `SELECT * FROM (
         SELECT ui.acquired_at AS at,
                ui.nickname,
                ui.item_key,
                si.name_ko AS item_name,
                si.category,
                si.price,
                si.is_permanent,
                si.duration_days,
                'new' AS kind
         FROM tc_user_items ui
         JOIN tc_shop_items si ON si.item_key = ui.item_key
         WHERE ui.source = 'shop'

         UNION ALL

         SELECT gh.created_at AS at,
                gh.nickname,
                (SELECT si2.item_key FROM tc_shop_items si2
                  WHERE si2.name_ko = split_part(gh.title, '|', 1) LIMIT 1) AS item_key,
                split_part(gh.title, '|', 1) AS item_name,
                (SELECT si2.category FROM tc_shop_items si2
                  WHERE si2.name_ko = split_part(gh.title, '|', 1) LIMIT 1) AS category,
                -gh.gold_delta AS price,
                FALSE AS is_permanent,
                (SELECT si2.duration_days FROM tc_shop_items si2
                  WHERE si2.name_ko = split_part(gh.title, '|', 1) LIMIT 1) AS duration_days,
                'extend' AS kind
         FROM tc_gold_history gh
         WHERE gh.source = 'shop_purchase'
       ) log
       WHERE ($1::text IS NULL OR log.item_key = $1)
         AND ($2::text IS NULL OR log.nickname ILIKE $2)
       ORDER BY log.at DESC
       LIMIT $3 OFFSET $4`,
      [itemKey, nickname, limit + 1, offset],
    );
    const rows = result.rows.slice(0, limit);
    return {
      success: true,
      rows: rows.map((r) => ({
        at: r.at,
        nickname: r.nickname,
        itemKey: r.item_key,
        itemName: r.item_name,
        category: r.category,
        price: parseInt(r.price, 10) || 0,
        isPermanent: r.is_permanent === true,
        durationDays: r.duration_days,
        kind: r.kind,
      })),
      hasMore: result.rows.length > limit,
    };
  } catch (err) {
    console.error('Get shop purchase log error:', err);
    return { success: false, rows: [], hasMore: false, message: err.message };
  } finally {
    client.release();
  }
}

/// Totals for the same log, over the same filters but the whole range — the
/// figures at the top of the page must be about every matching purchase, not
/// about the fifty rows on screen.
async function getShopPurchaseLogSummary(opts = {}) {
  const itemKey = opts.itemKey || null;
  const nickname = opts.nickname ? `%${opts.nickname}%` : null;
  const client = await pool.connect();
  try {
    const r = await client.query(
      `SELECT COUNT(*)::int AS purchases,
              COALESCE(SUM(log.price), 0)::bigint AS spent,
              COUNT(DISTINCT log.nickname)::int AS buyers,
              COUNT(*) FILTER (WHERE log.kind = 'extend')::int AS extends,
              MAX(log.at) AS last_at
       FROM (
         SELECT ui.acquired_at AS at, ui.nickname, ui.item_key, si.price, 'new' AS kind
         FROM tc_user_items ui
         JOIN tc_shop_items si ON si.item_key = ui.item_key
         WHERE ui.source = 'shop'
         UNION ALL
         SELECT gh.created_at, gh.nickname,
                (SELECT si2.item_key FROM tc_shop_items si2
                  WHERE si2.name_ko = split_part(gh.title, '|', 1) LIMIT 1),
                -gh.gold_delta, 'extend'
         FROM tc_gold_history gh
         WHERE gh.source = 'shop_purchase'
       ) log
       WHERE ($1::text IS NULL OR log.item_key = $1)
         AND ($2::text IS NULL OR log.nickname ILIKE $2)`,
      [itemKey, nickname],
    );
    const a = r.rows[0];
    return {
      success: true,
      purchases: a.purchases,
      spent: Number(a.spent) || 0,
      buyers: a.buyers,
      extends: a.extends,
      lastAt: a.last_at,
    };
  } catch (err) {
    console.error('Get shop purchase log summary error:', err);
    return { success: false, purchases: 0, spent: 0, buyers: 0, extends: 0, lastAt: null };
  } finally {
    client.release();
  }
}

/// How many people are actually holding each shop item right now, for the
/// backstage's item list.
///
/// Three numbers because "쓰고 있다" means two different things depending on
/// the item. A pass is being used if its days have not run out; a banner is
/// being used if it is also equipped — plenty of people own five and wear one.
/// `total` includes lapsed holders, which is what says whether an item ever
/// sold at all versus is merely between renewals.
///
/// The equipped count only counts people whose entitlement is still live. An
/// equip row is not cleared when the item lapses, so counting the equips table
/// alone reports banners nobody can actually see.
async function getShopItemHolderCounts() {
  const client = await pool.connect();
  try {
    const held = await client.query(
      `SELECT item_key,
              COUNT(*) FILTER (
                WHERE expires_at IS NULL
                   OR expires_at >= (NOW() AT TIME ZONE 'UTC')
              )::int AS active,
              COUNT(*)::int AS total
       FROM tc_user_items
       GROUP BY item_key`,
    );
    const worn = await client.query(
      `SELECT ui.item_key, COUNT(*)::int AS equipped
       FROM tc_user_items ui
       JOIN tc_user_equips e ON e.nickname = ui.nickname
       WHERE (ui.expires_at IS NULL
              OR ui.expires_at >= (NOW() AT TIME ZONE 'UTC'))
         AND ui.item_key IN (e.banner_key, e.title_key, e.theme_key, e.card_skin_key)
       GROUP BY ui.item_key`,
    );
    const byKey = {};
    for (const r of held.rows) {
      byKey[r.item_key] = { active: r.active, total: r.total, equipped: 0 };
    }
    for (const r of worn.rows) {
      if (byKey[r.item_key]) byKey[r.item_key].equipped = r.equipped;
    }

    // The profile-photo pass is on tc_users, not tc_user_items, so it would
    // read as zero holders forever. Both duration tiers extend one expiry, so
    // this is a count of the capability — the caller attributes it to every
    // profile_photo tier and says so.
    const photo = await client.query(
      `SELECT COUNT(*)::int AS n FROM tc_users
       WHERE profile_photo_status = 'active'
         AND (profile_photo_expires_at IS NULL
              OR profile_photo_expires_at >= (NOW() AT TIME ZONE 'UTC'))`,
    );
    return { success: true, byKey, profilePhotoActive: photo.rows[0]?.n || 0 };
  } catch (err) {
    console.error('Get shop item holder counts error:', err);
    return { success: false, byKey: {}, profilePhotoActive: 0 };
  } finally {
    client.release();
  }
}

/// Everything this account holds right now, for the admin's inventory panel.
///
/// Deliberately NOT getUserItems: that one is the player's own inventory and
/// deletes expired rows on the way past (cleanupExpiredItems). A support view
/// must not change what it is reporting on, and an expired row is exactly the
/// one an admin is most likely to be asked about — "my pass ran out while I
/// couldn't play". It survives until the owner next opens their inventory, and
/// until then it can be extended back to life.
///
/// The profile-photo pass is appended as a synthetic row. It lives on tc_users
/// rather than tc_user_items (the upload gate reads it there), so an inventory
/// built from tc_user_items alone silently omits the one entitlement people
/// pay real attention to.
async function getAdminUserInventory(nickname) {
  const client = await pool.connect();
  try {
    const res = await client.query(
      `SELECT ui.id, ui.item_key, ui.acquired_at, ui.expires_at, ui.source,
              si.name_ko, si.category, si.is_permanent, si.duration_days,
              si.effect_type, si.price, si.is_season,
              (e.banner_key = ui.item_key OR e.title_key = ui.item_key
                OR e.theme_key = ui.item_key OR e.card_skin_key = ui.item_key)
                AS equipped
       FROM tc_user_items ui
       JOIN tc_shop_items si ON si.item_key = ui.item_key
       LEFT JOIN tc_user_equips e ON e.nickname = ui.nickname
       WHERE ui.nickname = $1
       ORDER BY
         -- Live and running out soonest at the top: that is what a support
         -- question is about. Permanents and expired rows sink.
         (ui.expires_at IS NOT NULL
           AND ui.expires_at >= (NOW() AT TIME ZONE 'UTC')) DESC,
         ui.expires_at ASC NULLS LAST,
         ui.acquired_at DESC`,
      [nickname],
    );
    const items = res.rows.map((r) => ({ ...r, kind: 'item' }));

    const photo = await client.query(
      `SELECT profile_photo_status, profile_photo_expires_at
       FROM tc_users WHERE nickname = $1`,
      [nickname],
    );
    const p = photo.rows[0];
    if (p && (p.profile_photo_status === 'active' || p.profile_photo_expires_at)) {
      items.unshift({
        kind: 'profile_photo',
        id: null,
        item_key: 'profile_photo',
        name_ko: '프로필 사진',
        category: 'profile',
        is_permanent: false,
        duration_days: null,
        effect_type: 'profile_photo',
        source: 'tc_users',
        acquired_at: null,
        expires_at: p.profile_photo_expires_at,
        equipped: false,
        price: null,
        is_season: false,
      });
    }
    return { success: true, items };
  } catch (err) {
    console.error('Get admin user inventory error:', err);
    return { success: false, items: [], message: err.message };
  } finally {
    client.release();
  }
}

/// Move a time-limited entitlement's expiry by [days]. Negative shortens it.
///
/// Extends from NOW when the pass has already lapsed, rather than from the old
/// expiry — the same rule buyItem uses. Adding seven days to something that ran
/// out two months ago otherwise buys the player nothing, which is the opposite
/// of what an admin typing "+7" is trying to do.
///
/// The arithmetic stays in SQL and against UTC. The columns are `timestamp
/// without time zone` holding UTC, and reading one into JS to add days puts the
/// result back through node-pg in the process timezone — nine hours out on a
/// KST host.
/**
 * Take an item back off a user.
 *
 * The mirror of adminExtendUserItem, and it has to know the same three homes:
 * the profile-photo pass lives on tc_users, everything else is a tc_user_items
 * row, and whichever slot it is equipped in has to be cleared or the seat keeps
 * drawing a banner the user no longer owns.
 *
 * [refundGold] pays back the shop price of the item. Off by default: most
 * revocations are a correction (a mis-issued coupon, a duplicate grant), and
 * handing gold over for an item they never should have had is the opposite of
 * the intent. It exists because the other case — "sorry, we're taking this
 * back" — reads badly without it.
 */
async function adminRevokeUserItem(nickname, itemKey, { refundGold = false, adminActor = 'admin' } = {}) {
  if (!nickname || !itemKey) {
    return { success: false, message: '유저와 아이템을 확인해 주세요.' };
  }
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    if (itemKey === 'profile_photo') {
      const r = await client.query(
        `UPDATE tc_users
            SET profile_photo_status = 'none', profile_photo_expires_at = NULL
          WHERE nickname = $1
          RETURNING profile_photo_key`,
        [nickname],
      );
      if (r.rows.length === 0) {
        await client.query('ROLLBACK');
        return { success: false, message: '유저를 찾을 수 없습니다.' };
      }
      await client.query('COMMIT');
      console.log(`[admin] ${adminActor} revoked profile_photo from ${nickname}`);
      // The uploaded file itself is left alone — the pass is what was revoked,
      // and deleting someone's photo is a separate, louder decision.
      return { success: true, refunded: 0, photoKey: r.rows[0].profile_photo_key || null };
    }

    const owned = await client.query(
      `SELECT ui.id, si.name_ko, si.price, si.effect_type
         FROM tc_user_items ui
         JOIN tc_shop_items si ON si.item_key = ui.item_key
        WHERE ui.nickname = $1 AND ui.item_key = $2
        FOR UPDATE OF ui`,
      [nickname, itemKey],
    );
    if (owned.rows.length === 0) {
      await client.query('ROLLBACK');
      return { success: false, message: '이 유저가 가지고 있지 않은 아이템입니다.' };
    }

    // Every row, not just the newest: duplicates exist (an extension that
    // inserted instead of extending, a coupon granted twice), and leaving one
    // behind means the revoke visibly did nothing.
    const del = await client.query(
      `DELETE FROM tc_user_items WHERE nickname = $1 AND item_key = $2`,
      [nickname, itemKey],
    );

    // Unequip wherever it sat. Each slot is checked by key rather than by the
    // item's category, so a mis-categorised item cannot survive in a slot.
    await client.query(
      `UPDATE tc_user_equips
          SET banner_key    = CASE WHEN banner_key    = $2 THEN NULL ELSE banner_key END,
              title_key     = CASE WHEN title_key     = $2 THEN NULL ELSE title_key END,
              theme_key     = CASE WHEN theme_key     = $2 THEN NULL ELSE theme_key END,
              card_skin_key = CASE WHEN card_skin_key = $2 THEN NULL ELSE card_skin_key END,
              updated_at    = (NOW() AT TIME ZONE 'UTC')
        WHERE nickname = $1`,
      [nickname, itemKey],
    );

    // Feature passes (top-card counter and friends) are gated by an items row
    // plus an on/off preference. The row is gone; drop the stale preference so
    // a re-purchase starts from the default instead of an old "off".
    const effectType = owned.rows[0].effect_type;
    if (effectType) {
      await client.query(
        `DELETE FROM tc_user_feature_off WHERE nickname = $1 AND effect_type = $2`,
        [nickname, effectType],
      );
    }

    let refunded = 0;
    if (refundGold) {
      const price = parseInt(owned.rows[0].price, 10) || 0;
      // One item's price, not one per duplicate row: the duplicates are the
      // bug being cleaned up, and paying for each would reward it.
      if (price > 0) {
        await client.query(
          `UPDATE tc_users SET gold = gold + $2 WHERE nickname = $1`,
          [nickname, price],
        );
        await client.query(
          `INSERT INTO tc_gold_history (nickname, gold_delta, source, title, description)
           VALUES ($1, $2, 'admin', 'item_revoke_refund', $3)`,
          [nickname, price, `${owned.rows[0].name_ko || itemKey} 회수 환불 (${adminActor})`],
        );
        refunded = price;
      }
    }

    await client.query('COMMIT');
    console.log(`[admin] ${adminActor} revoked ${itemKey} x${del.rowCount} from ${nickname}`
      + (refunded ? ` (refunded ${refunded}g)` : ''));
    return { success: true, removed: del.rowCount, refunded, name: owned.rows[0].name_ko || itemKey };
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Admin revoke user item error:', err);
    return { success: false, message: err.message };
  } finally {
    client.release();
  }
}

/**
 * Move a user's item expiry from the backstage.
 *
 * Deliberately does NOT check is_purchasable or is_season, unlike buyItem.
 * The shop refuses both — a player cannot buy or extend a season reward or a
 * withdrawn item at any price, including the 0 they are priced at — and that
 * is the door that has to stay shut. This is the other side: support fixing a
 * season banner that ended a day early, or topping up something that is no
 * longer sold. Closing it here would only mean editing the row by hand.
 */
async function adminExtendUserItem(nickname, itemKey, days, adminActor = 'admin') {
  const n = Math.trunc(Number(days));
  if (!Number.isFinite(n) || n === 0) {
    return { success: false, message: '일수를 확인해 주세요.' };
  }
  if (Math.abs(n) > 3650) {
    return { success: false, message: '한 번에 3650일까지만 조정할 수 있습니다.' };
  }
  const client = await pool.connect();
  try {
    // The profile-photo pass is not a tc_user_items row; same rule, other home.
    if (itemKey === 'profile_photo') {
      const r = await client.query(
        `UPDATE tc_users
         SET profile_photo_status = 'active',
             profile_photo_expires_at = CASE
               WHEN profile_photo_expires_at IS NULL
                 OR profile_photo_expires_at < (NOW() AT TIME ZONE 'UTC')
                 THEN (NOW() AT TIME ZONE 'UTC') + ($2 || ' days')::interval
               ELSE profile_photo_expires_at + ($2 || ' days')::interval
             END
         WHERE nickname = $1
         RETURNING profile_photo_expires_at`,
        [nickname, n],
      );
      if (r.rows.length === 0) {
        return { success: false, message: '유저를 찾을 수 없습니다.' };
      }
      console.log(`[admin] ${adminActor} extended profile_photo for ${nickname} by ${n}d`);
      return { success: true, expiresAt: r.rows[0].profile_photo_expires_at };
    }

    const owned = await client.query(
      `SELECT ui.id, ui.expires_at, si.is_permanent
       FROM tc_user_items ui
       JOIN tc_shop_items si ON si.item_key = ui.item_key
       WHERE ui.nickname = $1 AND ui.item_key = $2
       ORDER BY ui.expires_at DESC NULLS FIRST
       LIMIT 1`,
      [nickname, itemKey],
    );
    if (owned.rows.length === 0) {
      return { success: false, message: '이 유저가 가지고 있지 않은 아이템입니다.' };
    }
    // A permanent item and a non-permanent one with no expiry both already run
    // forever. Writing a date onto either would take something away.
    if (owned.rows[0].is_permanent) {
      return { success: false, message: '영구 아이템이라 연장할 것이 없습니다.' };
    }
    if (owned.rows[0].expires_at === null) {
      return { success: false, message: '만료일이 없는 아이템이라 연장할 것이 없습니다.' };
    }
    const r = await client.query(
      `UPDATE tc_user_items
       SET expires_at = CASE
         WHEN expires_at < (NOW() AT TIME ZONE 'UTC')
           THEN (NOW() AT TIME ZONE 'UTC') + ($2 || ' days')::interval
         ELSE expires_at + ($2 || ' days')::interval
       END
       WHERE id = $1
       RETURNING expires_at`,
      [owned.rows[0].id, n],
    );
    console.log(`[admin] ${adminActor} extended ${itemKey} for ${nickname} by ${n}d`);
    return { success: true, expiresAt: r.rows[0].expires_at };
  } catch (err) {
    console.error('Admin extend user item error:', err);
    return { success: false, message: err.message };
  } finally {
    client.release();
  }
}

/// One page of a user's shop purchases, plus a summary of ALL of them.
///
/// The summary is its own aggregate rather than a reduce over the page. It
/// feeds the "누적 구매 / 총 N 골드 사용" figures at the top of the user's
/// detail page, and those have to be about the account, not about however many
/// rows this call happened to fetch — which is now five.
async function getAdminPurchaseHistory(nickname, limit = 30, offset = 0) {
  const client = await pool.connect();
  try {
    const result = await client.query(
      `
      SELECT
        ui.item_key,
        ui.acquired_at,
        ui.expires_at,
        ui.is_active,
        ui.source,
        si.name_ko,
        si.category,
        si.price,
        si.is_permanent,
        si.duration_days,
        si.is_season
      FROM tc_user_items ui
      JOIN tc_shop_items si ON si.item_key = ui.item_key
      WHERE ui.nickname = $1
        AND ui.source = 'shop'
      ORDER BY ui.acquired_at DESC
      LIMIT $2 OFFSET $3
      `,
      [nickname, limit + 1, Math.max(0, offset)]
    );

    // One row past the page: the cheapest "is there a next page", and cheaper
    // than a second COUNT on a table this one already scanned.
    const rows = result.rows.slice(0, limit);
    const hasMore = result.rows.length > limit;

    const agg = await client.query(
      `SELECT COUNT(*)::int AS purchases,
              COALESCE(SUM(si.price), 0)::int AS spent,
              COUNT(*) FILTER (WHERE si.is_permanent)::int AS permanent,
              COUNT(*) FILTER (WHERE NOT si.is_permanent)::int AS temporary,
              COUNT(*) FILTER (WHERE ui.is_active)::int AS active
       FROM tc_user_items ui
       JOIN tc_shop_items si ON si.item_key = ui.item_key
       WHERE ui.nickname = $1 AND ui.source = 'shop'`,
      [nickname],
    );
    const a = agg.rows[0];
    const summary = {
      totalSpent: a.spent,
      totalPurchases: a.purchases,
      permanentCount: a.permanent,
      temporaryCount: a.temporary,
      activeCount: a.active,
    };

    return {
      success: true,
      summary,
      hasMore,
      purchases: rows.map((row) => ({
        itemKey: row.item_key,
        acquiredAt: row.acquired_at,
        expiresAt: row.expires_at,
        isActive: row.is_active,
        source: row.source,
        name: row.name_ko,
        category: row.category,
        price: parseInt(row.price, 10) || 0,
        isPermanent: row.is_permanent,
        durationDays: row.duration_days,
        isSeason: row.is_season,
      })),
    };
  } catch (err) {
    console.error('Get admin purchase history error:', err);
    return { success: false, messageKey: 'db_purchase_history_failed', summary: null, purchases: [] };
  } finally {
    client.release();
  }
}

// Ad reward claim (max 5 per day, 50 gold each)
async function claimAdReward(nickname) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    // Lock the user row first so concurrent ad-reward claims for the same user
    // serialize. Without this the daily-cap COUNT below is a read-then-write
    // race: two claims can both read cnt=4, both pass the < 5 check, and both
    // grant — exceeding the 5/day cap (mirrors claimAttendance / buyItem locks).
    await client.query('SELECT 1 FROM tc_users WHERE nickname = $1 FOR UPDATE', [nickname]);
    // Count today's claims
    const countResult = await client.query(
      `SELECT COUNT(*) as cnt FROM tc_ad_rewards
       WHERE nickname = $1 AND claimed_at::date = CURRENT_DATE`,
      [nickname]
    );
    const todayCount = parseInt(countResult.rows[0].cnt, 10);
    if (todayCount >= 5) {
      await client.query('ROLLBACK');
      return { success: false, messageKey: 'db_ad_reward_exhausted', remaining: 0 };
    }
    // Grant 50 gold
    await client.query(
      `UPDATE tc_users SET gold = gold + 50 WHERE nickname = $1`,
      [nickname]
    );
    // Record claim
    await client.query(
      `INSERT INTO tc_ad_rewards (nickname) VALUES ($1)`,
      [nickname]
    );
    await client.query('COMMIT');
    // Get updated gold
    const walletResult = await client.query(
      `SELECT gold FROM tc_users WHERE nickname = $1`,
      [nickname]
    );
    const gold = walletResult.rows[0]?.gold ?? 0;
    return { success: true, gold, remaining: 5 - todayCount - 1 };
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Claim ad reward error:', err);
    return { success: false, messageKey: 'db_reward_grant_failed' };
  } finally {
    client.release();
  }
}

// Shop items
// Returns every shop item that has a visual config under metadata->visual,
// regardless of category, purchasable, or season flag. Used by the client
// to render banners/titles/themes consistently with whatever the admin set
// in the shop tab (gradient angle, stops, icon overrides). Kept lightweight
// — only the columns needed for rendering.
async function getVisualCatalog() {
  const client = await pool.connect();
  try {
    const result = await client.query(
      `
      SELECT item_key, category, metadata
      FROM tc_shop_items
      WHERE metadata IS NOT NULL AND metadata->'visual' IS NOT NULL
      `
    );
    return { success: true, items: result.rows };
  } catch (err) {
    console.error('Get visual catalog error:', err);
    return { success: false, messageKey: 'db_shop_fetch_failed' };
  } finally {
    client.release();
  }
}

async function getShopItems() {
  const client = await pool.connect();
  try {
    const result = await client.query(
      `
      SELECT item_key, name_ko, name_ko AS name, name_en, name_de,
             description_ko, description_en, description_de,
             category, price, is_season, is_permanent,
             duration_days, is_purchasable, effect_type, effect_value, metadata,
             sale_start, sale_end, new_until
      FROM tc_shop_items
      WHERE is_purchasable = TRUE AND is_season = FALSE
        AND (sale_start IS NULL OR sale_start <= NOW())
        AND (sale_end IS NULL OR sale_end >= NOW())
      -- Still-fresh NEW items float to the very top of the whole list,
      -- ahead of the normal category grouping; once new_until passes they
      -- fall back into category/price order with everything else.
      ORDER BY (new_until IS NOT NULL AND new_until >= NOW()) DESC,
               category ASC, price ASC, name_ko ASC
      `
    );
    return { success: true, items: result.rows };
  } catch (err) {
    console.error('Get shop items error:', err);
    return { success: false, messageKey: 'db_shop_fetch_failed' };
  } finally {
    client.release();
  }
}

/**
 * Drop this user's lapsed items — and take off whatever they were wearing.
 *
 * Deleting the row alone was not enough: tc_user_equips still pointed at the
 * key, and every display path reads the equip slot without checking ownership,
 * so an expired banner kept being drawn on the seat forever. The item was gone
 * from the inventory and still on the player's face.
 *
 * The title slot is special. A custom title lives there as `custom:<colour>`
 * with its text on tc_users and no tc_user_items row behind it, so matching it
 * against the inventory would strip a title the user is entitled to wear.
 */
async function cleanupExpiredItems(client, nickname) {
  const removed = await client.query(
    `
    DELETE FROM tc_user_items
    WHERE nickname = $1 AND expires_at IS NOT NULL AND expires_at < (NOW() AT TIME ZONE 'UTC')
    RETURNING item_key
    `,
    [nickname]
  );
  if (removed.rowCount === 0) return;
  await clearEquipsNotOwned(client, nickname);
}

/**
 * Blank any equip slot holding something the user no longer has.
 *
 * Written against the inventory rather than against a list of just-expired
 * keys so it also repairs slots left behind by anything else — an admin
 * revoke, a hand-edited row, an older build that expired an item without
 * unequipping it.
 */
async function clearEquipsNotOwned(client, nickname) {
  await client.query(
    `
    UPDATE tc_user_equips e
       SET banner_key    = CASE WHEN e.banner_key    IS NULL OR owned.banner    THEN e.banner_key    ELSE NULL END,
           theme_key     = CASE WHEN e.theme_key     IS NULL OR owned.theme     THEN e.theme_key     ELSE NULL END,
           card_skin_key = CASE WHEN e.card_skin_key IS NULL OR owned.card_skin THEN e.card_skin_key ELSE NULL END,
           -- 'custom:…' has no inventory row by design; leave it alone.
           title_key     = CASE WHEN e.title_key IS NULL
                                  OR e.title_key LIKE 'custom:%'
                                  OR owned.title THEN e.title_key ELSE NULL END,
           updated_at    = (NOW() AT TIME ZONE 'UTC')
      FROM (SELECT
              EXISTS (SELECT 1 FROM tc_user_items i WHERE i.nickname = $1 AND i.item_key = eq.banner_key)    AS banner,
              EXISTS (SELECT 1 FROM tc_user_items i WHERE i.nickname = $1 AND i.item_key = eq.theme_key)     AS theme,
              EXISTS (SELECT 1 FROM tc_user_items i WHERE i.nickname = $1 AND i.item_key = eq.card_skin_key) AS card_skin,
              EXISTS (SELECT 1 FROM tc_user_items i WHERE i.nickname = $1 AND i.item_key = eq.title_key)     AS title
            FROM tc_user_equips eq WHERE eq.nickname = $1) AS owned
     WHERE e.nickname = $1
    `,
    [nickname]
  );
}

/**
 * The same repair for everyone, on a timer.
 *
 * Per-user cleanup only runs when that user opens their inventory or equips
 * something — but the face other players see is read from their profile, which
 * anyone can pull up at any time. Someone who never opens the shop again would
 * otherwise wear a lapsed banner indefinitely.
 */
async function sweepExpiredCosmetics() {
  const client = await pool.connect();
  try {
    const removed = await client.query(
      `DELETE FROM tc_user_items
        WHERE expires_at IS NOT NULL AND expires_at < (NOW() AT TIME ZONE 'UTC')
        RETURNING nickname`);
    const touched = [...new Set(removed.rows.map((r) => r.nickname))];
    for (const nickname of touched) {
      await clearEquipsNotOwned(client, nickname);
    }
    if (touched.length > 0) {
      console.log(`[items] expired ${removed.rowCount} row(s), unequipped for ${touched.length} user(s)`);
    }
    return { success: true, expired: removed.rowCount, users: touched.length };
  } catch (err) {
    console.error('sweepExpiredCosmetics error:', err.message);
    return { success: false, message: err.message };
  } finally {
    client.release();
  }
}

// Inventory
async function getUserItems(nickname) {
  const client = await pool.connect();
  try {
    await cleanupExpiredItems(client, nickname);
    const result = await client.query(
      `
      SELECT ui.item_key, ui.acquired_at, ui.expires_at, ui.is_active,
             si.name_ko, si.name_ko AS name, si.name_en, si.name_de,
             si.description_ko, si.description_en, si.description_de,
             si.category, si.is_season, si.is_permanent, si.price,
             si.duration_days, si.effect_type, si.effect_value, si.metadata
      FROM tc_user_items ui
      JOIN tc_shop_items si ON si.item_key = ui.item_key
      WHERE ui.nickname = $1
      ORDER BY ui.acquired_at DESC
      `,
      [nickname]
    );
    const items = result.rows;
    // Each row says whether its feature is currently switched on, so the
    // inventory can draw the toggle without a second round trip.
    const off = await client.query(
      `SELECT effect_type FROM tc_user_feature_off WHERE nickname = $1`,
      [nickname],
    );
    const disabled = new Set(off.rows.map((r) => r.effect_type));
    for (const it of items) {
      it.feature_disabled = disabled.has(it.effect_type);
    }

    // The profile-photo entitlement does not live in tc_user_items — the upload
    // gate reads it off tc_users, so buyItem writes it there. Nothing else
    // knows that, which left it invisible: it never showed in the inventory,
    // the shop never displayed an expiry for it, and the shop offered "buy"
    // instead of "extend" because it decides both from this list. Surface it
    // here as a row so all three follow from one place.
    const photo = await client.query(
      `SELECT profile_photo_status, profile_photo_expires_at, profile_photo_key
       FROM tc_users WHERE nickname = $1`,
      [nickname],
    );
    const row = photo.rows[0];
    const photoActive = row
      && row.profile_photo_status === 'active'
      && (!row.profile_photo_expires_at || new Date(row.profile_photo_expires_at) > new Date());
    if (photoActive) {
      // Any tier key will do — the shop groups the tiers and matches on the
      // first one it finds — but the display name must be the capability, not
      // a tier: the two tiers cross-extend one expiry, so "프로필 사진(7일)"
      // would be a lie about what they hold.
      const tier = await client.query(
        `SELECT * FROM tc_shop_items WHERE effect_type = 'profile_photo'
         ORDER BY duration_days ASC LIMIT 1`,
      );
      const t = tier.rows[0];
      if (t) {
        const baseName = (n) => (n || '').replace(/\s*\([^)]*\)\s*$/, '').trim();
        items.unshift({
          ...t,
          name_ko: baseName(t.name_ko),
          name: baseName(t.name_ko),
          name_en: baseName(t.name_en),
          name_de: baseName(t.name_de),
          acquired_at: null,
          expires_at: row.profile_photo_expires_at,
          is_active: !!row.profile_photo_key,
        });
      }
    }
    return { success: true, items };
  } catch (err) {
    console.error('Get user items error:', err);
    return { success: false, messageKey: 'db_inventory_fetch_failed' };
  } finally {
    client.release();
  }
}

// Buy item
async function buyItem(nickname, itemKey) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const itemRes = await client.query(
      `SELECT * FROM tc_shop_items WHERE item_key = $1`,
      [itemKey]
    );
    if (itemRes.rows.length === 0) {
      await client.query('ROLLBACK');
      return { success: false, messageKey: 'db_item_not_found' };
    }
    const item = itemRes.rows[0];
    if (!item.is_purchasable) {
      await client.query('ROLLBACK');
      return { success: false, messageKey: 'db_item_not_purchasable' };
    }
    // sale_start/sale_end are deliberately not checked here. They gate
    // discovery — getShopItems() hides the item outside that window so a new
    // buyer can't start one late — but someone who already owns it can keep
    // extending past the window on the same terms they bought in on. Only
    // is_purchasable being switched off in admin cuts that off for everyone.
    // Season items are reward-only — never purchasable or extendable through
    // the shop, even if a stale client sends a buy request for one already in
    // the user's inventory.
    if (item.is_season) {
      await client.query('ROLLBACK');
      return { success: false, messageKey: 'db_item_not_purchasable' };
    }

    const walletRes = await client.query(
      `SELECT gold FROM tc_users WHERE nickname = $1 FOR UPDATE`,
      [nickname]
    );
    if (walletRes.rows.length === 0) {
      await client.query('ROLLBACK');
      return { success: false, messageKey: 'db_user_not_found' };
    }
    const gold = walletRes.rows[0].gold || 0;
    if (gold < item.price) {
      await client.query('ROLLBACK');
      return { success: false, messageKey: 'db_insufficient_gold' };
    }

    // ── Feature items: capability-for-N-days grouped by effect_type so tiers
    // (7d / 30d) cross-extend a single expiry instead of stacking rows. ──────
    // Profile photo lives on tc_users (the upload gate reads it there).
    if (item.effect_type === 'profile_photo') {
      const days = item.duration_days || 30;
      await client.query(
        `UPDATE tc_users
         SET gold = gold - $2,
             profile_photo_status = 'active',
             profile_photo_expires_at = CASE
               WHEN profile_photo_expires_at IS NULL OR profile_photo_expires_at < NOW()
                 THEN NOW() + ($3 || ' days')::interval
               ELSE profile_photo_expires_at + ($3 || ' days')::interval
             END
         WHERE nickname = $1`,
        [nickname, item.price, days],
      );
      await client.query(
        `INSERT INTO tc_gold_history (nickname, gold_delta, source, title, description)
         VALUES ($1, $2, 'shop_purchase', $3, 'shop_purchase')`,
        [nickname, -item.price, `${item.name_ko}|${item.name_en}|${item.name_de}`],
      );
      await client.query('COMMIT');
      return { success: true, profilePhoto: true };
    }
    // Gameplay counters/viewers: extend any active tier of the same feature.
    const FEATURE_EFFECTS = new Set(['top_card_counter', 'mighty_trump_counter', 'mighty_prev_trick', 'profile_private', 'custom_title']);
    if (FEATURE_EFFECTS.has(item.effect_type)) {
      const days = item.duration_days || 30;
      const existing = await client.query(
        `SELECT ui.item_key FROM tc_user_items ui
         JOIN tc_shop_items si ON si.item_key = ui.item_key
         WHERE ui.nickname = $1 AND si.effect_type = $2
           AND (ui.expires_at IS NULL OR ui.expires_at >= NOW())
         ORDER BY ui.expires_at DESC NULLS LAST LIMIT 1`,
        [nickname, item.effect_type],
      );
      const isExtend = existing.rows.length > 0;
      if (isExtend) {
        await client.query(
          `UPDATE tc_user_items
           SET expires_at = CASE
             WHEN expires_at IS NULL OR expires_at < NOW() THEN NOW() + ($2 || ' days')::interval
             ELSE expires_at + ($2 || ' days')::interval
           END
           WHERE nickname = $1 AND item_key = $3`,
          [nickname, days, existing.rows[0].item_key],
        );
      } else {
        await client.query(
          `INSERT INTO tc_user_items (nickname, item_key, expires_at, is_active, source)
           VALUES ($1, $2, NOW() + ($3 || ' days')::interval, FALSE, 'shop')`,
          [nickname, itemKey, days],
        );
      }
      await client.query(`UPDATE tc_users SET gold = gold - $2 WHERE nickname = $1`, [nickname, item.price]);
      // Gold-history: only record an explicit row on EXTEND. A fresh purchase
      // already surfaces in getGoldHistory via the tc_user_items.acquired_at
      // UNION branch, so writing an explicit row too would double-list the same
      // buy (extends don't move acquired_at, so they need the explicit row to
      // appear at the right time — matching the legacy temp-item path).
      if (isExtend) {
        await client.query(
          `INSERT INTO tc_gold_history (nickname, gold_delta, source, title, description)
           VALUES ($1, $2, 'shop_purchase', $3, 'shop_purchase')`,
          [nickname, -item.price, `${item.name_ko}|${item.name_en}|${item.name_de}`],
        );
      }
      await client.query('COMMIT');
      return { success: true, extended: isExtend };
    }

    // Prevent duplicate ownership / extend duration for temp items.
    //
    // A permanent *cosmetic* (banner_pioneer_*, theme_pio_*, …) is one
    // entitlement — own it once, equip it forever, buying a second is
    // meaningless. A permanent *utility* item (탈주 카운트 -1/-3, 전적
    // 초기화권, 닉네임 변경권, …) is a one-shot consumable instead: each
    // purchase is a separate use that gets deleted from tc_user_items the
    // moment it's used, so holding several unused copies at once is the
    // normal case, not a duplicate.
    if (item.is_permanent && item.category !== 'utility') {
      const owned = await client.query(
        `SELECT 1 FROM tc_user_items WHERE nickname = $1 AND item_key = $2 LIMIT 1`,
        [nickname, itemKey]
      );
      if (owned.rows.length > 0) {
        await client.query('ROLLBACK');
        return { success: false, messageKey: 'db_item_already_owned' };
      }
    } else if (!item.is_permanent) {
      const ownedActive = await client.query(
        `SELECT 1 FROM tc_user_items
         WHERE nickname = $1 AND item_key = $2
           AND (expires_at IS NULL OR expires_at >= NOW())
         LIMIT 1`,
        [nickname, itemKey]
      );
      if (ownedActive.rows.length > 0) {
        if (!item.duration_days) {
          await client.query('ROLLBACK');
          return { success: false, messageKey: 'db_duration_not_found' };
        }
        await client.query(
          `
          UPDATE tc_user_items
          SET expires_at = CASE
            WHEN expires_at IS NULL OR expires_at < NOW()
              THEN NOW() + ($2 || ' days')::interval
            ELSE expires_at + ($2 || ' days')::interval
          END
          WHERE nickname = $1 AND item_key = $3
          `,
          [nickname, item.duration_days, itemKey]
        );

        await client.query(
          `UPDATE tc_users SET gold = gold - $2 WHERE nickname = $1`,
          [nickname, item.price]
        );

        // Record the extend as its own gold-history entry so it shows up at
        // the correct timestamp. Without this, the history view derives shop
        // purchases from tc_user_items.acquired_at which is never updated on
        // extend — so an extend would silently appear at the original buy
        // time, off by however long ago the item was first acquired.
        await client.query(
          `INSERT INTO tc_gold_history (nickname, gold_delta, source, title, description)
           VALUES ($1, $2, 'shop_purchase', $3, 'shop_purchase')`,
          [nickname, -item.price, `${item.name_ko}|${item.name_en}|${item.name_de}`]
        );

        await client.query('COMMIT');
        return { success: true, extended: true };
      }
    }

    const expiresAt = item.is_permanent
      ? null
      : (item.duration_days
          ? new Date(Date.now() + item.duration_days * 24 * 60 * 60 * 1000)
          : null);

    await client.query(
      `INSERT INTO tc_user_items (nickname, item_key, expires_at, is_active, source)
       VALUES ($1, $2, $3, $4, 'shop')`,
      [nickname, itemKey, expiresAt, false]
    );

    await client.query(
      `UPDATE tc_users SET gold = gold - $2 WHERE nickname = $1`,
      [nickname, item.price]
    );

    await client.query('COMMIT');
    return { success: true };
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Buy item error:', err);
    return { success: false, messageKey: 'db_purchase_error' };
  } finally {
    client.release();
  }
}

// Equip item
async function equipItem(nickname, itemKey, locale = 'ko') {
  const client = await pool.connect();
  try {
    await cleanupExpiredItems(client, nickname);
    const itemRes = await client.query(
      `SELECT category, name_ko, name_en, name_de FROM tc_shop_items WHERE item_key = $1`,
      [itemKey]
    );
    if (itemRes.rows.length === 0) {
      return { success: false, messageKey: 'db_item_not_found' };
    }
    const category = itemRes.rows[0].category;
    const row = itemRes.rows[0];
    const itemName = locale === 'en' ? (row.name_en || row.name_ko)
      : locale === 'de' ? (row.name_de || row.name_ko)
      : row.name_ko;

    const owned = await client.query(
      `SELECT 1 FROM tc_user_items
       WHERE nickname = $1 AND item_key = $2
         AND (expires_at IS NULL OR expires_at >= NOW())
       LIMIT 1`,
      [nickname, itemKey]
    );
    if (owned.rows.length === 0) {
      return { success: false, messageKey: 'db_item_not_owned' };
    }

    const fieldMap = {
      banner: 'banner_key',
      title: 'title_key',
      theme: 'theme_key',
      card_skin: 'card_skin_key',
    };
    const field = fieldMap[category];
    if (!field) {
      return { success: false, messageKey: 'db_item_not_equippable' };
    }

    await client.query(
      `
      INSERT INTO tc_user_equips (nickname, ${field}, updated_at)
      VALUES ($1, $2, NOW())
      ON CONFLICT (nickname)
      DO UPDATE SET ${field} = EXCLUDED.${field}, updated_at = NOW()
      `,
      [nickname, itemKey]
    );

    await client.query(
      `UPDATE tc_user_items SET is_active = FALSE
       WHERE nickname = $1 AND item_key IN (
         SELECT item_key FROM tc_shop_items WHERE category = $2
       )`,
      [nickname, category]
    );
    await client.query(
      `UPDATE tc_user_items SET is_active = TRUE
       WHERE nickname = $1 AND item_key = $2`,
      [nickname, itemKey]
    );

    return { success: true, category, itemName };
  } catch (err) {
    console.error('Equip item error:', err);
    return { success: false, messageKey: 'db_equip_error' };
  } finally {
    client.release();
  }
}

/**
 * Take off whatever is equipped in [category] (banner / title / theme / …).
 *
 * By category, not by item key: the point is "wear nothing", and the caller
 * knows which slot it is clearing. Owning the item is not required — an expired
 * banner still sitting in the equip row must be removable.
 */
async function unequipCategory(nickname, category) {
  const fieldMap = {
    banner: 'banner_key',
    title: 'title_key',
    theme: 'theme_key',
    card_skin: 'card_skin_key',
  };
  const field = fieldMap[category];
  if (!field) return { success: false, messageKey: 'db_item_not_equippable' };
  const client = await pool.connect();
  try {
    await client.query(
      `UPDATE tc_user_equips SET ${field} = NULL, updated_at = NOW()
       WHERE nickname = $1`,
      [nickname],
    );
    // is_active drives the inventory's "활성화됨" mark, so it has to come off
    // with the equip itself or the row keeps claiming to be in use.
    await client.query(
      `UPDATE tc_user_items SET is_active = FALSE
       WHERE nickname = $1 AND item_key IN (
         SELECT item_key FROM tc_shop_items WHERE category = $2
       )`,
      [nickname, category],
    );
    return { success: true, category };
  } catch (err) {
    console.error('Unequip item error:', err);
    return { success: false, messageKey: 'db_equip_error' };
  } finally {
    client.release();
  }
}

// Use consumable item
async function useItem(nickname, itemKey) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const itemRes = await client.query(
      `SELECT effect_type, effect_value FROM tc_shop_items WHERE item_key = $1`,
      [itemKey]
    );
    if (itemRes.rows.length === 0) {
      await client.query('ROLLBACK');
      return { success: false, messageKey: 'db_item_not_found' };
    }
    const { effect_type: effectType, effect_value: effectValue } = itemRes.rows[0];
    const allowedEffects = [
      'leave_count_reduce', 'leave_count_reset', 'stats_reset',
      'season_stats_reset',
      'tichu_season_stats_reset', 'sk_season_stats_reset', 'mighty_season_stats_reset',
    ];
    if (!allowedEffects.includes(effectType)) {
      await client.query('ROLLBACK');
      return { success: false, messageKey: 'db_item_not_usable' };
    }

    const owned = await client.query(
      `SELECT id FROM tc_user_items
       WHERE nickname = $1 AND item_key = $2
         AND (expires_at IS NULL OR expires_at >= NOW())
       LIMIT 1`,
      [nickname, itemKey]
    );
    if (owned.rows.length === 0) {
      await client.query('ROLLBACK');
      return { success: false, messageKey: 'db_item_not_owned' };
    }

    if (effectType === 'leave_count_reduce') {
      await client.query(
        `UPDATE tc_users SET leave_count = GREATEST(0, leave_count - $2)
         WHERE nickname = $1`,
        [nickname, effectValue || 1]
      );
    } else if (effectType === 'leave_count_reset') {
      await client.query(
        `UPDATE tc_users SET leave_count = 0 WHERE nickname = $1`,
        [nickname]
      );
    } else if (effectType === 'stats_reset') {
      await client.query(
        `UPDATE tc_users SET total_games = 0, wins = 0, losses = 0
         WHERE nickname = $1`,
        [nickname]
      );
    } else if (effectType === 'season_stats_reset') {
      // Legacy "all ranked" reset — wipes every game's season stats. Users who
      // purchased this before the per-game split still redeem it as intended,
      // now correctly including the mighty columns the old query missed.
      await client.query(
        `UPDATE tc_users SET season_games = 0, season_wins = 0, season_losses = 0,
           sk_season_games = 0, sk_season_wins = 0, sk_season_losses = 0,
           mighty_season_games = 0, mighty_season_wins = 0, mighty_season_losses = 0
         WHERE nickname = $1`,
        [nickname]
      );
    } else if (effectType === 'tichu_season_stats_reset') {
      await client.query(
        `UPDATE tc_users SET season_games = 0, season_wins = 0, season_losses = 0
         WHERE nickname = $1`,
        [nickname]
      );
    } else if (effectType === 'sk_season_stats_reset') {
      await client.query(
        `UPDATE tc_users SET sk_season_games = 0, sk_season_wins = 0, sk_season_losses = 0
         WHERE nickname = $1`,
        [nickname]
      );
    } else if (effectType === 'mighty_season_stats_reset') {
      await client.query(
        `UPDATE tc_users SET mighty_season_games = 0, mighty_season_wins = 0, mighty_season_losses = 0
         WHERE nickname = $1`,
        [nickname]
      );
    }

    await client.query(
      `DELETE FROM tc_user_items WHERE id = $1`,
      [owned.rows[0].id]
    );

    await client.query('COMMIT');
    return { success: true };
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Use item error:', err);
    return { success: false, messageKey: 'db_use_item_error' };
  } finally {
    client.release();
  }
}

// Change nickname using nickname_change item
async function changeNickname(oldNickname, newNickname) {
  if (!newNickname || typeof newNickname !== 'string') {
    return { success: false, messageKey: 'db_nickname_required' };
  }
  const trimmed = newNickname.trim();
  if (trimmed.length < 2 || trimmed.length > 10) {
    return { success: false, messageKey: 'db_nickname_length' };
  }
  if (/\s/.test(trimmed)) {
    return { success: false, messageKey: 'db_nickname_no_space' };
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Check duplicate nickname
    const dupCheck = await client.query(
      `SELECT nickname FROM tc_users WHERE nickname = $1`,
      [trimmed]
    );
    if (dupCheck.rows.length > 0) {
      await client.query('ROLLBACK');
      return { success: false, messageKey: 'db_nickname_taken' };
    }

    // Check ownership of nickname_change item
    const owned = await client.query(
      `SELECT id FROM tc_user_items
       WHERE nickname = $1 AND item_key = 'nickname_change'
         AND (expires_at IS NULL OR expires_at >= NOW())
       LIMIT 1`,
      [oldNickname]
    );
    if (owned.rows.length === 0) {
      await client.query('ROLLBACK');
      return { success: false, messageKey: 'db_no_nickname_change_ticket' };
    }

    // Update nickname in tc_users
    await client.query(
      `UPDATE tc_users SET nickname = $2 WHERE nickname = $1`,
      [oldNickname, trimmed]
    );

    // Update nickname in tc_user_items
    await client.query(
      `UPDATE tc_user_items SET nickname = $2 WHERE nickname = $1`,
      [oldNickname, trimmed]
    );

    // Update nickname in tc_user_equips
    await client.query(
      `UPDATE tc_user_equips SET nickname = $2 WHERE nickname = $1`,
      [oldNickname, trimmed]
    );

    // Update nickname in tc_user_feature_off. Left behind, a switched-off pass
    // would quietly switch itself back on the moment someone renames.
    await client.query(
      `UPDATE tc_user_feature_off SET nickname = $2 WHERE nickname = $1`,
      [oldNickname, trimmed]
    );

    // Update nickname in tc_friends (both columns)
    await client.query(
      `UPDATE tc_friends SET user_nickname = $2 WHERE user_nickname = $1`,
      [oldNickname, trimmed]
    );
    await client.query(
      `UPDATE tc_friends SET friend_nickname = $2 WHERE friend_nickname = $1`,
      [oldNickname, trimmed]
    );

    // Update nickname in tc_blocked_users (both columns)
    await client.query(
      `UPDATE tc_blocked_users SET blocker_nickname = $2 WHERE blocker_nickname = $1`,
      [oldNickname, trimmed]
    );
    await client.query(
      `UPDATE tc_blocked_users SET blocked_nickname = $2 WHERE blocked_nickname = $1`,
      [oldNickname, trimmed]
    );

    // Update nickname in tc_inquiries
    await client.query(
      `UPDATE tc_inquiries SET user_nickname = $2 WHERE user_nickname = $1`,
      [oldNickname, trimmed]
    );

    // Update nickname in tc_dm_messages (both columns)
    await client.query(
      `UPDATE tc_dm_messages SET sender_nickname = $2 WHERE sender_nickname = $1`,
      [oldNickname, trimmed]
    );
    await client.query(
      `UPDATE tc_dm_messages SET receiver_nickname = $2 WHERE receiver_nickname = $1`,
      [oldNickname, trimmed]
    );

    // Update nickname in tc_reports (both columns)
    await client.query(
      `UPDATE tc_reports SET reporter_nickname = $2 WHERE reporter_nickname = $1`,
      [oldNickname, trimmed]
    );
    await client.query(
      `UPDATE tc_reports SET reported_nickname = $2 WHERE reported_nickname = $1`,
      [oldNickname, trimmed]
    );

    // Update nickname in tc_match_history (all 4 player columns)
    await client.query(
      `UPDATE tc_match_history SET player_a1 = $2 WHERE player_a1 = $1`,
      [oldNickname, trimmed]
    );
    await client.query(
      `UPDATE tc_match_history SET player_a2 = $2 WHERE player_a2 = $1`,
      [oldNickname, trimmed]
    );
    await client.query(
      `UPDATE tc_match_history SET player_b1 = $2 WHERE player_b1 = $1`,
      [oldNickname, trimmed]
    );
    await client.query(
      `UPDATE tc_match_history SET player_b2 = $2 WHERE player_b2 = $1`,
      [oldNickname, trimmed]
    );

    // Update nickname in tc_match_history deserter_nickname
    await client.query(
      `UPDATE tc_match_history SET deserter_nickname = $2 WHERE deserter_nickname = $1`,
      [oldNickname, trimmed]
    );

    // Update nickname in tc_sk_match_players
    await client.query(
      `UPDATE tc_sk_match_players SET nickname = $2 WHERE nickname = $1`,
      [oldNickname, trimmed]
    );

    // Update nickname in tc_sk_match_history deserter_nickname
    await client.query(
      `UPDATE tc_sk_match_history SET deserter_nickname = $2 WHERE deserter_nickname = $1`,
      [oldNickname, trimmed]
    );

    // Update nickname in tc_ll_match_players
    await client.query(
      `UPDATE tc_ll_match_players SET nickname = $2 WHERE nickname = $1`,
      [oldNickname, trimmed]
    );

    // Update nickname in tc_ll_match_history deserter_nickname
    await client.query(
      `UPDATE tc_ll_match_history SET deserter_nickname = $2 WHERE deserter_nickname = $1`,
      [oldNickname, trimmed]
    );

    // Update nickname in tc_mighty_match_players
    await client.query(
      `UPDATE tc_mighty_match_players SET nickname = $2 WHERE nickname = $1`,
      [oldNickname, trimmed]
    );

    // Update nickname in tc_mighty_match_history
    await client.query(
      `UPDATE tc_mighty_match_history
       SET deserter_nickname = CASE WHEN deserter_nickname = $1 THEN $2 ELSE deserter_nickname END,
           declarer_nickname = CASE WHEN declarer_nickname = $1 THEN $2 ELSE declarer_nickname END,
           partner_nickname = CASE WHEN partner_nickname = $1 THEN $2 ELSE partner_nickname END`,
      [oldNickname, trimmed]
    );

    // Update nickname in tc_ad_rewards
    await client.query(
      `UPDATE tc_ad_rewards SET nickname = $2 WHERE nickname = $1`,
      [oldNickname, trimmed]
    );

    // Update nickname in tc_season_rewards
    await client.query(
      `UPDATE tc_season_rewards SET nickname = $2 WHERE nickname = $1`,
      [oldNickname, trimmed]
    );

    // Update nickname in tc_gold_history
    await client.query(
      `UPDATE tc_gold_history SET nickname = $2 WHERE nickname = $1`,
      [oldNickname, trimmed]
    );

    // Update nickname in tc_season_rankings
    await client.query(
      `UPDATE tc_season_rankings SET nickname = $2 WHERE nickname = $1`,
      [oldNickname, trimmed]
    );

    // Delete one nickname_change item
    await client.query(
      `DELETE FROM tc_user_items WHERE id = $1`,
      [owned.rows[0].id]
    );

    await client.query('COMMIT');
    return { success: true, newNickname: trimmed };
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Change nickname error:', err);
    return { success: false, messageKey: 'db_nickname_change_error' };
  } finally {
    client.release();
  }
}

// Set ranked ban (1 hour from now)
async function setRankedBan(nickname) {
  const client = await pool.connect();
  try {
    await client.query(
      `UPDATE tc_users SET ranked_ban_until = NOW() + INTERVAL '1 hour' WHERE nickname = $1`,
      [nickname]
    );
    return { success: true };
  } catch (err) {
    console.error('Set ranked ban error:', err);
    return { success: false };
  } finally {
    client.release();
  }
}

// Get ranked ban remaining minutes (null if not banned)
async function getRankedBan(nickname) {
  const client = await pool.connect();
  try {
    const result = await client.query(
      `SELECT ranked_ban_until FROM tc_users WHERE nickname = $1`,
      [nickname]
    );
    if (result.rows.length === 0) return null;
    const banUntil = result.rows[0].ranked_ban_until;
    if (!banUntil) return null;
    const remaining = new Date(banUntil) - new Date();
    if (remaining <= 0) return null;
    return Math.ceil(remaining / 60000); // minutes
  } catch (err) {
    console.error('Get ranked ban error:', err);
    return null;
  } finally {
    client.release();
  }
}

// Set chat ban (admin-controlled, duration in minutes)
// Set admin memo for a user
async function setAdminMemo(nickname, memo) {
  const client = await pool.connect();
  try {
    await client.query(
      `UPDATE tc_users SET admin_memo = $2 WHERE nickname = $1`,
      [nickname, memo || null]
    );
    return { success: true };
  } catch (err) {
    console.error('Set admin memo error:', err);
    return { success: false };
  } finally {
    client.release();
  }
}

// Admin force-removal of a profile photo (moderation). Clears the row so
// serialize() stops surfacing it and returns the old object key so the caller
// can delete it from storage. Keeps the paid duration expiry so the user can
// re-upload a compliant photo within their remaining window.
// Every profile photo currently on display, newest first.
//
// Moderation cannot only be report-driven: nobody reports the photo they never
// see, and a report queue tells you nothing about what is already out there.
// This is the browse-everything view.
//
// Reported users float to the top — a photo somebody has already objected to is
// the one worth looking at first.
async function listActiveProfilePhotos({ page = 1, limit = 24 } = {}) {
  const client = await pool.connect();
  try {
    const offset = (page - 1) * limit;
    const where = `
      WHERE u.profile_photo_status = 'active'
        AND u.profile_photo_key IS NOT NULL
        AND COALESCE(u.is_deleted, false) = false
        AND (u.profile_photo_expires_at IS NULL OR u.profile_photo_expires_at > NOW())`;
    const totalRes = await client.query(`SELECT COUNT(*) FROM tc_users u ${where}`);
    const rows = await client.query(
      `SELECT u.nickname, u.profile_photo_key, u.profile_photo_expires_at,
              (SELECT COUNT(*) FROM tc_reports r
                WHERE r.reported_nickname = u.nickname) AS report_count
       FROM tc_users u
       ${where}
       ORDER BY report_count DESC, u.profile_photo_expires_at ASC NULLS LAST
       LIMIT $1 OFFSET $2`,
      [limit, offset],
    );
    return {
      success: true,
      photos: rows.rows,
      total: parseInt(totalRes.rows[0].count, 10),
      page,
      limit,
    };
  } catch (err) {
    console.error('List active profile photos error:', err);
    return { success: false, photos: [], total: 0, page, limit };
  } finally {
    client.release();
  }
}

// Best-effort — a screening record is diagnostic, never worth failing the
// upload response (which has already sent image_rejected) over.
async function recordPhotoRejection({ userId, nickname, imageKey, worst, scores, labels }) {
  try {
    await pool.query(
      `INSERT INTO tc_photo_rejections
         (user_id, nickname, image_key, worst, adult_score, racy_score, violence_score, labels)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [
        userId, nickname, imageKey, worst || null,
        scores?.adult || null, scores?.racy || null, scores?.violence || null,
        (labels && labels.length) ? labels.join(', ') : null,
      ],
    );
  } catch (err) {
    console.error('Record photo rejection error:', err);
  }
}

// Rejected-photo history for admin review, newest first.
async function getPhotoRejections({ page = 1, limit = 24 } = {}) {
  const client = await pool.connect();
  try {
    const offset = (page - 1) * limit;
    const totalRes = await client.query('SELECT COUNT(*) FROM tc_photo_rejections');
    const rows = await client.query(
      `SELECT id, user_id, nickname, image_key, worst,
              adult_score, racy_score, violence_score, labels, created_at
       FROM tc_photo_rejections
       ORDER BY created_at DESC
       LIMIT $1 OFFSET $2`,
      [limit, offset],
    );
    return {
      success: true,
      rejections: rows.rows,
      total: parseInt(totalRes.rows[0].count, 10),
      page,
      limit,
    };
  } catch (err) {
    console.error('Get photo rejections error:', err);
    return { success: false, rejections: [], total: 0, page, limit };
  } finally {
    client.release();
  }
}

// Drop one rejection record — the reviewer has seen what it was, no reason
// to keep the image and its scores around after that. Returns the image_key
// so the caller can also remove the object from storage.
async function deletePhotoRejection(id) {
  try {
    const result = await pool.query(
      `DELETE FROM tc_photo_rejections WHERE id = $1 RETURNING image_key`,
      [id],
    );
    if (result.rowCount === 0) return { success: false };
    return { success: true, imageKey: result.rows[0].image_key };
  } catch (err) {
    console.error('Delete photo rejection error:', err);
    return { success: false };
  }
}

async function adminClearProfilePhoto(nickname) {
  const client = await pool.connect();
  try {
    const before = await client.query(
      `SELECT profile_photo_key FROM tc_users WHERE nickname = $1`,
      [nickname],
    );
    if (before.rows.length === 0) return { success: false, oldKey: null };
    // Only drop the photo (key), NOT the paid item status: isPhotoEligible
    // requires status='active', so setting 'none' here would block the user from
    // re-uploading a compliant photo within their remaining paid window. Expiry
    // still gates eligibility, and the hourly cleanup flips status to 'none' when
    // the window actually ends.
    await client.query(
      `UPDATE tc_users SET profile_photo_key = NULL WHERE nickname = $1`,
      [nickname],
    );
    return { success: true, oldKey: before.rows[0].profile_photo_key || null };
  } catch (err) {
    console.error('Admin clear profile photo error:', err);
    return { success: false, oldKey: null };
  } finally {
    client.release();
  }
}

async function setChatBan(nickname, minutes) {
  const client = await pool.connect();
  try {
    if (minutes <= 0) {
      await client.query(
        `UPDATE tc_users SET chat_ban_until = NULL WHERE nickname = $1`,
        [nickname]
      );
    } else {
      await client.query(
        `UPDATE tc_users SET chat_ban_until = NOW() + INTERVAL '1 minute' * $2 WHERE nickname = $1`,
        [nickname, minutes]
      );
    }
    return { success: true };
  } catch (err) {
    console.error('Set chat ban error:', err);
    return { success: false };
  } finally {
    client.release();
  }
}

// Get chat ban remaining minutes (null if not banned)
async function getChatBan(nickname) {
  const client = await pool.connect();
  try {
    const result = await client.query(
      `SELECT chat_ban_until FROM tc_users WHERE nickname = $1`,
      [nickname]
    );
    if (result.rows.length === 0) return null;
    const banUntil = result.rows[0].chat_ban_until;
    if (!banUntil) return null;
    const remaining = new Date(banUntil) - new Date();
    if (remaining <= 0) return null;
    return Math.ceil(remaining / 60000); // minutes
  } catch (err) {
    console.error('Get chat ban error:', err);
    return null;
  } finally {
    client.release();
  }
}

// Increment leave count (ranked quit)
/**
 * Tichu seat fields for a mid-leave row, for the benefit of older clients.
 *
 * Their Tichu renderer reads playerA1/A2/B1/B2 and the two team scores. There
 * are no scores to report — the match was still running — so those stay 0 and
 * the seats carry the four names, leaver first. Purely cosmetic: it turns
 * "0 : 0  -·- : -·-" into the names of the people who were there.
 */
function tichuSeatsForMidLeave(leaver, roster) {
  const names = [leaver, ...roster.map((p) => p.nickname)].filter(Boolean);
  return {
    teamAScore: 0,
    teamBScore: 0,
    playerA1: names[0] ?? null,
    playerA2: names[1] ?? null,
    playerB1: names[2] ?? null,
    playerB2: names[3] ?? null,
  };
}

/**
 * Roster stored on a mid-leave row, in the shape every other game type sends.
 *
 * Stored as bare nicknames, but emitted as `[{ nickname }]` — clients already
 * in the wild render a Skull King / Love Letter / Mighty row with
 * `players.map((p) => p['nickname'])`, and indexing a String with a String
 * throws in Dart ("type 'String' is not a subtype of type 'int'"), taking the
 * whole profile popup down. They cannot be updated, so the payload matches
 * what they expect.
 *
 * [] for rows written before the column existed.
 */
function parseMidLeavePlayers(raw) {
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed
      .map((entry) => (
        // Tolerate either shape on the way in: older rows hold plain strings.
        typeof entry === 'string' ? { nickname: entry } : entry
      ))
      .filter((entry) => entry && typeof entry.nickname === 'string');
  } catch {
    return [];
  }
}

/**
 * Log a walk-out from a match that carried on without the leaver.
 *
 * Separate from incrementLeaveCount (the running tally) because this is the
 * evidence behind the tally — the tally alone can't say which game, when, or
 * whether it was a deliberate exit or three timeouts.
 */
async function logMidGameLeave({ nickname, gameType, reason, roomName, players }) {
  if (!nickname) return { success: false };
  const client = await pool.connect();
  try {
    await client.query(
      `INSERT INTO tc_midleave_log (nickname, game_type, reason, room_name, players)
       VALUES ($1, $2, $3, $4, $5)`,
      [
        nickname, gameType || 'tichu', reason || 'leave', roomName || null,
        Array.isArray(players) && players.length > 0
          ? JSON.stringify(players)
          : null,
      ],
    );
    return { success: true };
  } catch (err) {
    console.error('Log mid-game leave error:', err);
    return { success: false };
  } finally {
    client.release();
  }
}

async function incrementLeaveCount(nickname) {
  const client = await pool.connect();
  try {
    await client.query(
      `UPDATE tc_users SET leave_count = leave_count + 1 WHERE nickname = $1`,
      [nickname]
    );
    return { success: true };
  } catch (err) {
    console.error('Increment leave count error:', err);
    return { success: false };
  } finally {
    client.release();
  }
}

// Seasons
async function getActiveSeason() {
  const client = await pool.connect();
  try {
    const result = await client.query(
      `SELECT id, name, start_at, end_at, status
       FROM tc_seasons
       WHERE status = 'active'
       ORDER BY start_at DESC
       LIMIT 1`
    );
    return result.rows[0] || null;
  } catch (err) {
    console.error('Get active season error:', err);
    return null;
  } finally {
    client.release();
  }
}

async function createSeason(name, startAt, endAt) {
  const client = await pool.connect();
  try {
    // ON CONFLICT: 같은 이름의 시즌은 하나뿐이다. 롤오버가 겹쳐 돌아도
    // (부팅 + 시간별 타이머, 또는 인스턴스 두 개) 두 번째부터는 조용히
    // 기존 시즌을 돌려받는다.
    const result = await client.query(
      `INSERT INTO tc_seasons (name, start_at, end_at, status)
       VALUES ($1, $2, $3, 'active')
       ON CONFLICT (name) DO NOTHING
       RETURNING id, name, start_at, end_at, status`,
      [name, startAt, endAt]
    );
    if (result.rows[0]) return result.rows[0];
    const existing = await client.query(
      `SELECT id, name, start_at, end_at, status FROM tc_seasons WHERE name = $1`,
      [name],
    );
    return existing.rows[0] || null;
  } catch (err) {
    console.error('Create season error:', err);
    return null;
  } finally {
    client.release();
  }
}

async function getSeasons() {
  const client = await pool.connect();
  try {
    const result = await client.query(
      `SELECT id, name, start_at, end_at, status
       FROM tc_seasons
       ORDER BY start_at DESC`
    );
    return { success: true, seasons: result.rows };
  } catch (err) {
    console.error('Get seasons error:', err);
    return { success: false, messageKey: 'db_season_list_failed' };
  } finally {
    client.release();
  }
}

async function getCurrentSeasonRankings(limit = 50) {
  const client = await pool.connect();
  try {
    const result = await client.query(
      `
      SELECT u.nickname,
             u.season_rating AS rating,
             u.season_wins AS wins,
             u.season_losses AS losses,
             u.season_games AS total_games,
             CASE
               WHEN u.season_games > 0 THEN ROUND((u.season_wins::FLOAT / u.season_games) * 100)
               ELSE 0
             END AS win_rate,
             e.banner_key
      FROM tc_users u
      LEFT JOIN tc_user_equips e ON e.nickname = u.nickname
      WHERE u.is_deleted IS NOT TRUE AND u.season_games > 0
      ORDER BY u.season_rating DESC, u.season_wins DESC, u.season_games DESC, u.nickname ASC
      LIMIT $1
      `,
      [limit]
    );
    return { success: true, rankings: result.rows };
  } catch (err) {
    console.error('Get current season rankings error:', err);
    return { success: false, messageKey: 'db_season_rankings_failed' };
  } finally {
    client.release();
  }
}

async function getSeasonRankings(seasonId, limit = 50) {
  const client = await pool.connect();
  try {
    const result = await client.query(
      `
      SELECT r.nickname, r.rating, r.wins, r.losses, r.total_games,
             CASE
               WHEN r.total_games > 0 THEN ROUND((r.wins::FLOAT / r.total_games) * 100)
               ELSE 0
             END AS win_rate,
             e.banner_key
      FROM tc_season_rankings r
      LEFT JOIN tc_user_equips e ON e.nickname = r.nickname
      WHERE r.season_id = $1 AND r.game_type = 'tichu'
      ORDER BY r.rank ASC
      LIMIT $2
      `,
      [seasonId, limit]
    );
    return { success: true, rankings: result.rows };
  } catch (err) {
    console.error('Get season rankings error:', err);
    return { success: false, messageKey: 'db_season_rankings_failed' };
  } finally {
    client.release();
  }
}

async function resetSeasonStats() {
  const client = await pool.connect();
  try {
    await client.query(
      `UPDATE tc_users
       SET season_rating = 1000,
           season_games = 0,
           season_wins = 0,
           season_losses = 0,
           sk_season_rating = 1000,
           sk_season_games = 0,
           sk_season_wins = 0,
           sk_season_losses = 0,
           mighty_season_rating = 1000,
           mighty_season_games = 0,
           mighty_season_wins = 0,
           mighty_season_losses = 0`
    );
    return { success: true };
  } catch (err) {
    console.error('Reset season stats error:', err);
    return { success: false };
  } finally {
    client.release();
  }
}

const SEASON_GAME_TYPES = ['tichu', 'skull_king', 'mighty'];

/**
 * Reward tiers for one season, falling back to the default set.
 *
 * A season is either configured or it isn't — there is no per-game-type mixing
 * of the two, because "이 시즌은 티츄만 다르게" reads as an accident far more
 * often than as an intent.
 */
async function getSeasonRewardConfig(seasonId) {
  const client = await pool.connect();
  try {
    if (seasonId != null) {
      const own = await client.query(
        `SELECT game_type, rank, gold, banner_key, banner_days
         FROM tc_season_reward_config WHERE season_id = $1
         ORDER BY game_type, rank`,
        [seasonId],
      );
      if (own.rows.length > 0) return { custom: true, rows: own.rows };
    }
    const def = await client.query(
      `SELECT game_type, rank, gold, banner_key, banner_days
       FROM tc_season_reward_config WHERE season_id IS NULL
       ORDER BY game_type, rank`,
    );
    return { custom: false, rows: def.rows };
  } catch (err) {
    console.error('Get season reward config error:', err);
    return { custom: false, rows: [] };
  } finally {
    client.release();
  }
}

/**
 * Replace the tiers for one season (or the default set when seasonId is null).
 *
 * Replace, not merge: the editor shows every row it is about to save, so
 * deleting a rank there has to delete it here.
 */
async function saveSeasonRewardConfig(seasonId, rows) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    if (seasonId == null) {
      await client.query('DELETE FROM tc_season_reward_config WHERE season_id IS NULL');
    } else {
      await client.query('DELETE FROM tc_season_reward_config WHERE season_id = $1', [seasonId]);
    }
    for (const r of rows) {
      const rank = parseInt(r.rank, 10);
      if (!Number.isFinite(rank) || rank < 1) continue;
      if (!SEASON_GAME_TYPES.includes(r.game_type)) continue;
      await client.query(
        `INSERT INTO tc_season_reward_config
           (season_id, game_type, rank, gold, banner_key, banner_days, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, NOW())`,
        [
          seasonId, r.game_type, rank,
          Math.max(0, parseInt(r.gold, 10) || 0),
          r.banner_key ? String(r.banner_key).trim() : null,
          Math.max(1, parseInt(r.banner_days, 10) || 30),
        ],
      );
    }
    await client.query('COMMIT');
    return { success: true };
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('Save season reward config error:', err);
    return { success: false, messageKey: 'db_update_failed' };
  } finally {
    client.release();
  }
}

/** Drop a season's own tiers so it goes back to inheriting the defaults. */
async function clearSeasonRewardConfig(seasonId) {
  const client = await pool.connect();
  try {
    await client.query('DELETE FROM tc_season_reward_config WHERE season_id = $1', [seasonId]);
    return { success: true };
  } catch (err) {
    console.error('Clear season reward config error:', err);
    return { success: false, messageKey: 'db_update_failed' };
  } finally {
    client.release();
  }
}

/**
 * Everything needed to answer "did this season pay out what it should have?"
 * in one read: the ranking snapshot, the tiers that were configured, what was
 * actually written to tc_season_rewards, and whether the banner item really
 * landed on the account.
 *
 * The grant itself is one transaction, so there is no such thing as a
 * half-paid season — what this is for is the failures that succeed quietly:
 * a rank nobody qualified for (the loop just skips it), a banner_key that is
 * not in the catalog (the item row is written anyway and shows as nothing),
 * or a winner whose account is gone since.
 *
 * tc_season_rewards has no game_type column, so a row is attributed by its
 * banner_key first (they are game-specific) and by nickname+gold second.
 * Anything still unattributable comes back in `unmatched` rather than being
 * guessed at.
 */
async function getSeasonRewardAudit(seasonId) {
  const client = await pool.connect();
  try {
    const seasonRes = await client.query(
      `SELECT id, name, status, start_at, end_at FROM tc_seasons WHERE id = $1`,
      [seasonId],
    );
    if (seasonRes.rows.length === 0) return null;
    const season = seasonRes.rows[0];

    const own = await client.query(
      `SELECT game_type, rank, gold, banner_key, banner_days
       FROM tc_season_reward_config WHERE season_id = $1 ORDER BY game_type, rank`,
      [seasonId],
    );
    const configCustom = own.rows.length > 0;
    const configRows = configCustom ? own.rows : (await client.query(
      `SELECT game_type, rank, gold, banner_key, banner_days
       FROM tc_season_reward_config WHERE season_id IS NULL ORDER BY game_type, rank`,
    )).rows;

    const rankRes = await client.query(
      `SELECT game_type, rank, nickname, rating, wins, losses, total_games
       FROM tc_season_rankings WHERE season_id = $1 ORDER BY game_type, rank`,
      [seasonId],
    );
    const grantedRes = await client.query(
      `SELECT nickname, rank, gold_reward, banner_key, created_at
       FROM tc_season_rewards WHERE season_id = $1 ORDER BY rank, created_at`,
      [seasonId],
    );

    const nicknames = [...new Set([
      ...rankRes.rows.map((r) => r.nickname),
      ...grantedRes.rows.map((r) => r.nickname),
    ])];
    const bannerKeys = [...new Set([
      ...configRows.map((r) => r.banner_key),
      ...grantedRes.rows.map((r) => r.banner_key),
    ].filter(Boolean))];

    const liveRes = nicknames.length === 0 ? { rows: [] } : await client.query(
      `SELECT nickname FROM tc_users WHERE nickname = ANY($1) AND is_deleted IS NOT TRUE`,
      [nicknames],
    );
    const live = new Set(liveRes.rows.map((r) => r.nickname));

    const catalogRes = bannerKeys.length === 0 ? { rows: [] } : await client.query(
      `SELECT item_key FROM tc_shop_items WHERE item_key = ANY($1)`,
      [bannerKeys],
    );
    const catalog = new Set(catalogRes.rows.map((r) => r.item_key));

    // The banner the grant handed out, if it is still on the account. Season
    // items are inserted with source 'season', so this does not confuse a
    // banner the player simply bought.
    const itemsRes = (nicknames.length === 0 || bannerKeys.length === 0)
      ? { rows: [] }
      : await client.query(
        `SELECT nickname, item_key, expires_at, is_active
         FROM tc_user_items
         WHERE source = 'season' AND nickname = ANY($1) AND item_key = ANY($2)`,
        [nicknames, bannerKeys],
      );
    const itemAt = new Map(
      itemsRes.rows.map((r) => [`${r.nickname}\u0000${r.item_key}`, r]),
    );

    const bannerGame = new Map();
    for (const c of configRows) {
      if (c.banner_key) bannerGame.set(c.banner_key, c.game_type);
    }
    const rankedAt = new Map(
      rankRes.rows.map((r) => [`${r.game_type}\u0000${r.rank}`, r]),
    );

    const used = new Set();
    const claim = (gameType, rank, cfg) => {
      const snapshot = rankedAt.get(`${gameType}\u0000${rank}`);
      for (let i = 0; i < grantedRes.rows.length; i++) {
        if (used.has(i)) continue;
        const g = grantedRes.rows[i];
        if (g.rank !== rank) continue;
        const byBanner = g.banner_key && bannerGame.get(g.banner_key) === gameType;
        const byNickname = snapshot
          && g.nickname === snapshot.nickname
          && Number(g.gold_reward || 0) === Number(cfg.gold || 0);
        if (byBanner || byNickname) { used.add(i); return g; }
      }
      return null;
    };

    let totalGold = 0;
    let issueCount = 0;
    const games = SEASON_GAME_TYPES.map((gameType) => {
      const tiers = configRows
        .filter((c) => c.game_type === gameType)
        .sort((a, b) => a.rank - b.rank);
      const rows = tiers.map((cfg) => {
        const snapshot = rankedAt.get(`${gameType}\u0000${cfg.rank}`) || null;
        const granted = claim(gameType, cfg.rank, cfg);
        const nickname = granted?.nickname || snapshot?.nickname || null;
        const item = granted?.banner_key && nickname
          ? itemAt.get(`${nickname}\u0000${granted.banner_key}`) || null
          : null;
        const issues = [];
        const gone = nickname != null && !live.has(nickname);
        if (!snapshot) issues.push('no_recipient');
        // A deleted account takes its reward rows with it (deleteUser wipes
        // tc_season_rewards), so a missing row there is the deletion, not a
        // grant that never happened.
        else if (!granted && !gone) issues.push('not_granted');
        if (granted && Number(granted.gold_reward || 0) !== Number(cfg.gold || 0)) {
          issues.push('gold_mismatch');
        }
        if (granted?.banner_key && !catalog.has(granted.banner_key)) {
          issues.push('unknown_banner');
        }
        // Expired items are deleted outright (cleanupExpiredItems), so a
        // missing row is only suspicious while the banner should still be
        // running. Duration comes from the current config — the grant does not
        // record its own, so a later edit shifts this estimate.
        const bannerDue = granted?.created_at && cfg.banner_days
          ? new Date(new Date(granted.created_at).getTime()
            + Number(cfg.banner_days) * 86400000)
          : null;
        const bannerLapsed = bannerDue != null && bannerDue <= new Date();
        if (granted?.banner_key && !item && !bannerLapsed) {
          issues.push('banner_missing');
        }
        if (gone) issues.push('account_gone');
        if (granted) totalGold += Number(granted.gold_reward || 0);
        // "Nobody qualified for this rank" is information, not something to
        // act on — a young season legitimately has fewer ranked players than
        // configured tiers, and counting it as a problem would paint the
        // whole page red on day one.
        // Neither an empty rank nor a since-deleted account is something an
        // operator can act on; they are shown but not counted, so the number
        // means "look at this".
        issueCount += issues.filter(
          (i) => i !== 'no_recipient' && i !== 'account_gone',
        ).length;
        return {
          rank: cfg.rank,
          nickname,
          rating: snapshot ? Number(snapshot.rating || 0) : null,
          wins: snapshot ? Number(snapshot.wins || 0) : null,
          losses: snapshot ? Number(snapshot.losses || 0) : null,
          totalGames: snapshot ? Number(snapshot.total_games || 0) : null,
          expected: {
            gold: Number(cfg.gold || 0),
            bannerKey: cfg.banner_key || null,
            bannerDays: Number(cfg.banner_days || 0),
          },
          granted: granted
            ? {
              gold: Number(granted.gold_reward || 0),
              bannerKey: granted.banner_key || null,
              createdAt: granted.created_at,
            }
            : null,
          bannerItem: item
            ? { expiresAt: item.expires_at, isActive: item.is_active === true }
            : null,
          bannerLapsed,
          issues,
        };
      });
      const rankedCount = rankRes.rows.filter((r) => r.game_type === gameType).length;
      return { gameType, rankedCount, rows };
    });

    const unmatched = grantedRes.rows
      .filter((_, i) => !used.has(i))
      .map((g) => ({
        nickname: g.nickname,
        rank: g.rank,
        gold: Number(g.gold_reward || 0),
        bannerKey: g.banner_key || null,
        createdAt: g.created_at,
      }));
    issueCount += unmatched.length;
    for (const u of unmatched) totalGold += u.gold;

    return {
      season,
      configCustom,
      games,
      unmatched,
      summary: {
        totalGold,
        recipients: new Set(grantedRes.rows.map((r) => r.nickname)).size,
        grantedRows: grantedRes.rows.length,
        issueCount,
      },
    };
  } catch (err) {
    console.error('Get season reward audit error:', err);
    return null;
  } finally {
    client.release();
  }
}

/** What a closed season actually paid out, for the read-only view. */
async function getSeasonRewardsGranted(seasonId) {
  const client = await pool.connect();
  try {
    const res = await client.query(
      `SELECT nickname, rank, gold_reward, banner_key, created_at
       FROM tc_season_rewards WHERE season_id = $1
       ORDER BY rank ASC, created_at ASC`,
      [seasonId],
    );
    return res.rows;
  } catch (err) {
    console.error('Get granted season rewards error:', err);
    return [];
  } finally {
    client.release();
  }
}

// Grant season rewards (top3 + banners + gold)
async function grantSeasonRewards(seasonId) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // FOR UPDATE: 배포 교체 중에는 인스턴스가 둘이고, 양쪽 다 부팅과 시간별
    // 타이머에서 롤오버를 돌린다. 잠그지 않으면 둘 다 'active' 를 읽고 골드와
    // 배너를 두 번 지급한다 — 8월 시즌이 다섯 개 생긴 것과 같은 레이스다.
    const seasonRes = await client.query(
      `SELECT id, status FROM tc_seasons WHERE id = $1 FOR UPDATE`,
      [seasonId]
    );
    if (seasonRes.rows.length === 0) {
      await client.query('ROLLBACK');
      return { success: false, messageKey: 'db_season_not_found' };
    }
    if (seasonRes.rows[0].status === 'closed') {
      await client.query('ROLLBACK');
      return { success: false, messageKey: 'db_season_already_ended' };
    }

    const topRes = await client.query(
      `
      SELECT nickname, season_rating AS rating
      FROM tc_users
      WHERE season_games > 0 AND is_deleted IS NOT TRUE
      ORDER BY season_rating DESC, season_wins DESC, season_games DESC, nickname ASC
      LIMIT 100
      `
    );
    const top = topRes.rows;
    // Tiers come from the console now (per season, or the default set). Read
    // inside the transaction so a mid-close edit can't land halfway.
    const cfgRes = await client.query(
      `SELECT game_type, rank, gold, banner_key, banner_days
       FROM tc_season_reward_config
       WHERE season_id = $1
       ORDER BY game_type, rank`,
      [seasonId],
    );
    const cfgRows = cfgRes.rows.length > 0 ? cfgRes.rows : (await client.query(
      `SELECT game_type, rank, gold, banner_key, banner_days
       FROM tc_season_reward_config WHERE season_id IS NULL
       ORDER BY game_type, rank`,
    )).rows;
    // 티어가 하나도 없으면 아무에게도 주지 않고 시즌만 닫는다. 이걸 실패로
    // 막아둔 적이 있었는데, 그러면 "이번 시즌은 보상 없이 넘어간다"는 운영
    // 판단을 시스템이 거부하게 된다. 설정이 빠진 게 사고라면 그건 마이그레이션
    // 단계에서 잡을 일이다(테이블이 없으면 여기서 예외가 나고 롤백된다).
    // 대신 조용히 지나가지는 않게 기록은 남긴다.
    if (cfgRows.length === 0) {
      console.warn('[season] 보상 티어가 없어 지급 없이 시즌을 닫습니다. season_id =', seasonId);
    }
    const tiersFor = (gameType) => cfgRows
      .filter((r) => r.game_type === gameType)
      .sort((a, b) => a.rank - b.rank);

    const topFullRes = await client.query(
      `
      SELECT nickname,
             season_rating AS rating,
             season_wins AS wins,
             season_losses AS losses,
             season_games AS total_games
      FROM tc_users
      WHERE season_games > 0 AND is_deleted IS NOT TRUE
      ORDER BY season_rating DESC, season_wins DESC, season_games DESC, nickname ASC
      LIMIT 100
      `
    );
    const topFull = topFullRes.rows;
    for (let i = 0; i < topFull.length; i++) {
      const u = topFull[i];
      await client.query(
        `INSERT INTO tc_season_rankings (season_id, rank, nickname, rating, wins, losses, total_games, game_type)
         VALUES ($1, $2, $3, $4, $5, $6, $7, 'tichu')
         ON CONFLICT DO NOTHING`,
        [seasonId, i + 1, u.nickname, u.rating, u.wins, u.losses, u.total_games]
      );
    }

    // Save SK season rankings
    const skTopRes = await client.query(
      `SELECT nickname,
             sk_season_rating AS rating,
             sk_season_wins AS wins,
             sk_season_losses AS losses,
             sk_season_games AS total_games
      FROM tc_users
      WHERE sk_season_games > 0 AND is_deleted IS NOT TRUE
      ORDER BY sk_season_rating DESC, sk_season_wins DESC, sk_season_games DESC, nickname ASC
      LIMIT 100`
    );
    for (let i = 0; i < skTopRes.rows.length; i++) {
      const u = skTopRes.rows[i];
      await client.query(
        `INSERT INTO tc_season_rankings (season_id, rank, nickname, rating, wins, losses, total_games, game_type)
         VALUES ($1, $2, $3, $4, $5, $6, $7, 'skull_king')
         ON CONFLICT DO NOTHING`,
        [seasonId, i + 1, u.nickname, u.rating, u.wins, u.losses, u.total_games]
      );
    }

    // Save Mighty season rankings
    const mightyTopRes = await client.query(
      `SELECT nickname,
             mighty_season_rating AS rating,
             mighty_season_wins AS wins,
             mighty_season_losses AS losses,
             mighty_season_games AS total_games
      FROM tc_users
      WHERE mighty_season_games > 0 AND is_deleted IS NOT TRUE
      ORDER BY mighty_season_rating DESC, mighty_season_wins DESC, mighty_season_games DESC, nickname ASC
      LIMIT 100`
    );
    for (let i = 0; i < mightyTopRes.rows.length; i++) {
      const u = mightyTopRes.rows[i];
      await client.query(
        `INSERT INTO tc_season_rankings (season_id, rank, nickname, rating, wins, losses, total_games, game_type)
         VALUES ($1, $2, $3, $4, $5, $6, $7, 'mighty')
         ON CONFLICT DO NOTHING`,
        [seasonId, i + 1, u.nickname, u.rating, u.wins, u.losses, u.total_games]
      );
    }

    // Per-game-type reward sets. Tichu/SK/Mighty all award the same gold
    // tier (1000/500/200) and a 30-day banner; only the banner item key
    // differs so the winner gets a game-themed badge.
    const rewardSets = [
      { gameType: 'tichu', topRows: top },
      { gameType: 'skull_king', topRows: skTopRes.rows },
      { gameType: 'mighty', topRows: mightyTopRes.rows },
    ];

    for (const set of rewardSets) {
      for (const tier of tiersFor(set.gameType)) {
        const user = set.topRows[tier.rank - 1];
        if (!user) continue;

        if (tier.gold > 0) {
          await client.query(
            `UPDATE tc_users SET gold = gold + $2 WHERE nickname = $1`,
            [user.nickname, tier.gold]
          );
        }

        // A tier can be gold-only: an operator who clears the banner key is
        // saying "no badge for this rank", not "give them an empty item".
        if (tier.banner_key) {
          await client.query(
            `INSERT INTO tc_user_items (nickname, item_key, expires_at, is_active, source)
             VALUES ($1, $2, NOW() + ($3 || ' days')::INTERVAL, FALSE, 'season')`,
            [user.nickname, tier.banner_key, String(tier.banner_days || 30)]
          );
        }

        await client.query(
          `INSERT INTO tc_season_rewards (season_id, nickname, rank, gold_reward, banner_key)
           VALUES ($1, $2, $3, $4, $5)`,
          [seasonId, user.nickname, tier.rank, tier.gold, tier.banner_key]
        );
      }
    }

    await client.query(
      `UPDATE tc_seasons SET status = 'closed' WHERE id = $1`,
      [seasonId]
    );

    await client.query('COMMIT');
    return { success: true };
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Grant season rewards error:', err);
    return { success: false, messageKey: 'db_season_reward_failed' };
  } finally {
    client.release();
  }
}

// Submit inquiry
async function submitInquiry(nickname, category, title, content) {
  const client = await pool.connect();
  try {
    await client.query(
      'INSERT INTO tc_inquiries (user_nickname, category, title, content) VALUES ($1, $2, $3, $4)',
      [nickname, category, title, content]
    );
    return { success: true, messageKey: 'db_inquiry_submitted' };
  } catch (err) {
    console.error('Submit inquiry error:', err);
    return { success: false, messageKey: 'db_inquiry_submit_failed' };
  } finally {
    client.release();
  }
}

// Get inquiries for a user
async function getUserInquiries(nickname, limit = 30) {
  const client = await pool.connect();
  try {
    const result = await client.query(
      `SELECT id, category, status, title, content, admin_note, user_read, created_at, resolved_at
       FROM tc_inquiries
       WHERE user_nickname = $1
       ORDER BY created_at DESC
       LIMIT $2`,
      [nickname, limit]
    );
    return { success: true, inquiries: result.rows };
  } catch (err) {
    console.error('Get user inquiries error:', err);
    return { success: false, messageKey: 'db_inquiry_list_failed', inquiries: [] };
  } finally {
    client.release();
  }
}

// Mark resolved inquiries as read for a user
async function markInquiriesRead(nickname) {
  const client = await pool.connect();
  try {
    await client.query(
      `UPDATE tc_inquiries SET user_read = TRUE WHERE user_nickname = $1 AND status = 'resolved' AND user_read = FALSE`,
      [nickname]
    );
    return { success: true };
  } catch (err) {
    console.error('Mark inquiries read error:', err);
    return { success: false };
  } finally {
    client.release();
  }
}

// ===== Admin query functions =====

// Get inquiries with pagination
async function getInquiries(page = 1, limit = 20) {
  const client = await pool.connect();
  try {
    const offset = (page - 1) * limit;
    const countResult = await client.query('SELECT COUNT(*) FROM tc_inquiries');
    const total = parseInt(countResult.rows[0].count);
    const result = await client.query(
      'SELECT * FROM tc_inquiries ORDER BY created_at DESC LIMIT $1 OFFSET $2',
      [limit, offset]
    );
    return { rows: result.rows, total, page, limit };
  } catch (err) {
    console.error('Get inquiries error:', err);
    return { rows: [], total: 0, page, limit };
  } finally {
    client.release();
  }
}

// Get single inquiry by ID
async function getInquiryById(id) {
  const client = await pool.connect();
  try {
    const result = await client.query('SELECT * FROM tc_inquiries WHERE id = $1', [id]);
    return result.rows[0] || null;
  } catch (err) {
    console.error('Get inquiry error:', err);
    return null;
  } finally {
    client.release();
  }
}

// Resolve inquiry
async function resolveInquiry(id, adminNote) {
  const client = await pool.connect();
  try {
    await client.query(
      `UPDATE tc_inquiries SET status = 'resolved', admin_note = $2, resolved_at = CURRENT_TIMESTAMP WHERE id = $1`,
      [id, adminNote]
    );
    const result = await client.query(
      `SELECT user_nickname, title FROM tc_inquiries WHERE id = $1`,
      [id]
    );
    return { success: true, inquiry: result.rows[0] || null };
  } catch (err) {
    console.error('Resolve inquiry error:', err);
    return { success: false };
  } finally {
    client.release();
  }
}

// Get reports grouped by (reported_nickname, room_id)
async function getReports(page = 1, limit = 20) {
  const client = await pool.connect();
  try {
    const offset = (page - 1) * limit;
    const countResult = await client.query(
      'SELECT COUNT(*) FROM (SELECT 1 FROM tc_reports GROUP BY reported_nickname, room_id) sub'
    );
    const total = parseInt(countResult.rows[0].count);
    const result = await client.query(
      `SELECT
        reported_nickname,
        room_id,
        COUNT(*) AS report_count,
        array_agg(DISTINCT reporter_nickname) AS reporters,
        MAX(created_at) AS latest_date,
        CASE WHEN bool_or(status = 'pending') THEN 'pending'
             WHEN bool_or(status = 'reviewed') THEN 'reviewed'
             ELSE 'resolved' END AS group_status
       FROM tc_reports
       GROUP BY reported_nickname, room_id
       ORDER BY MAX(created_at) DESC
       LIMIT $1 OFFSET $2`,
      [limit, offset]
    );
    return { rows: result.rows, total, page, limit };
  } catch (err) {
    console.error('Get reports error:', err);
    return { rows: [], total: 0, page, limit };
  } finally {
    client.release();
  }
}

// Get all reports for a (reported_nickname, room_id) group
async function getReportGroup(reportedNickname, roomId) {
  const client = await pool.connect();
  try {
    const result = await client.query(
      `SELECT * FROM tc_reports
       WHERE reported_nickname = $1 AND room_id = $2
       ORDER BY created_at DESC`,
      [reportedNickname, roomId]
    );
    return result.rows;
  } catch (err) {
    console.error('Get report group error:', err);
    return [];
  } finally {
    client.release();
  }
}

// Update report status for all reports in a group
async function updateReportGroupStatus(reportedNickname, roomId, status) {
  const client = await pool.connect();
  try {
    await client.query(
      'UPDATE tc_reports SET status = $3 WHERE reported_nickname = $1 AND room_id = $2',
      [reportedNickname, roomId, status]
    );
    return { success: true };
  } catch (err) {
    console.error('Update report group status error:', err);
    return { success: false };
  } finally {
    client.release();
  }
}

/// 실제로 접속한 적 있는 앱 버전 목록 — 관리자 필터의 선택지.
///
/// 하드코딩하지 않는 이유는 릴리스마다 손대야 하기 때문이다. 최신순으로
/// 돌려주되 숫자.숫자.숫자(+빌드번호)? 꼴만 담는다 — 클라이언트는 항상
/// "3.1.3+53" 처럼 빌드번호를 붙여 보내므로(device_info_service.dart) 그것도
/// 받아줘야 한다. 그 외 이상한 값(옛 클라이언트, NULL)이 목록을 채우면
/// 고를 게 아니라 치울 게 된다.
async function getAppVersionsInUse() {
  const client = await pool.connect();
  try {
    const res = await client.query(
      `SELECT app_version, COUNT(*)::int AS users
         FROM tc_users
        WHERE app_version ~ '^[0-9]+[.][0-9]+[.][0-9]+([+][0-9]+)?$'
          AND is_deleted IS NOT TRUE
        GROUP BY app_version
        ORDER BY string_to_array(split_part(app_version, '+', 1), '.')::int[] DESC,
                 CASE WHEN app_version ~ '[+][0-9]+$' THEN split_part(app_version, '+', 2)::int ELSE 0 END DESC
        LIMIT 40`
    );
    return res.rows;
  } catch (err) {
    console.error('getAppVersionsInUse error:', err);
    return [];
  } finally {
    client.release();
  }
}

// Get users with search and pagination
async function getUsers(search = '', page = 1, limit = 20, options = {}) {
  const client = await pool.connect();
  try {
    const offset = (page - 1) * limit;
    const conditions = [];
    const countParams = [];
    let paramIdx = 1;

    if (options.excludeDeleted) {
      conditions.push('is_deleted IS NOT TRUE');
    }

    if (search) {
      conditions.push(`(nickname ILIKE $${paramIdx} OR username ILIKE $${paramIdx})`);
      countParams.push(`%${search}%`);
      paramIdx++;
    }
    if (options.minRating) {
      conditions.push(`rating >= $${paramIdx}`);
      countParams.push(parseInt(options.minRating));
      paramIdx++;
    }
    if (options.minGames) {
      conditions.push(
        `(COALESCE(total_games,0) + COALESCE(sk_total_games,0)`
        + ` + COALESCE(ll_total_games,0) + COALESCE(mighty_total_games,0)) >= $${paramIdx}`,
      );
      countParams.push(parseInt(options.minGames));
      paramIdx++;
    }
    if (options.minLeaves) {
      conditions.push(`leave_count >= $${paramIdx}`);
      countParams.push(parseInt(options.minLeaves));
      paramIdx++;
    }
    if (options.platform && ['ios', 'android', 'web'].includes(String(options.platform).toLowerCase())) {
      conditions.push(`LOWER(device_platform) = $${paramIdx}`);
      countParams.push(String(options.platform).toLowerCase());
      paramIdx++;
    }
    if (options.ipQuery) {
      conditions.push(`last_ip ILIKE $${paramIdx}`);
      countParams.push(`%${options.ipQuery}%`);
      paramIdx++;
    }
    // 앱 버전. 정확히 일치로 본다 — "3.1.0 인 사람" 을 찾는 용도지 "3.1 로
    // 시작하는" 을 찾는 용도가 아니다. 고르는 목록을 실제로 들어와 있는 값에서
    // 뽑으므로 오타로 빈 결과가 나올 일이 없다.
    if (options.appVersion) {
      conditions.push(`app_version = $${paramIdx}`);
      countParams.push(String(options.appVersion));
      paramIdx++;
    }

    const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

    // Sort options
    const sortOptions = {
      'rating_desc': 'rating DESC',
      'rating_asc': 'rating ASC',
      'games_desc': '(COALESCE(total_games,0) + COALESCE(sk_total_games,0)'
        + ' + COALESCE(ll_total_games,0) + COALESCE(mighty_total_games,0)) DESC',
      'games_asc': '(COALESCE(total_games,0) + COALESCE(sk_total_games,0)'
        + ' + COALESCE(ll_total_games,0) + COALESCE(mighty_total_games,0)) ASC',
      'gold_desc': 'gold DESC',
      'gold_asc': 'gold ASC',
      'level_desc': 'level DESC',
      'level_asc': 'level ASC',
      'leaves_desc': 'leave_count DESC',
      'leaves_asc': 'leave_count ASC',
      'login_desc': 'last_login DESC NULLS LAST',
      'login_asc': 'last_login ASC NULLS LAST',
      'joined_desc': 'created_at DESC',
      'joined_asc': 'created_at ASC',
      'nickname_asc': 'nickname ASC',
      'nickname_desc': 'nickname DESC',
      // 앱 버전을 문자열로 정렬하면 3.1.10 이 3.1.9 앞에 온다. 점으로 쪼개
      // 숫자 배열로 비교한다. 클라이언트는 항상 "3.1.3+53" 처럼 빌드번호를
      // 붙여 보내므로(device_info_service.dart) 그 뒤에 오는 +빌드번호는
      // 떼어내고 비교하되, 같은 버전(핫픽스로 버전은 안 올리고 빌드만 올린
      // 경우, 예: 2.4.0+30/31/32)의 순서를 가르는 2차 기준으로 빌드번호를
      // 그대로 쓴다. 숫자.숫자.숫자(+숫자)? 꼴이 아닌 값(옛 클라이언트, NULL)은
      // 맨 뒤로 보낸다.
      'version_desc': "CASE WHEN app_version ~ '^[0-9]+[.][0-9]+[.][0-9]+([+][0-9]+)?$' THEN string_to_array(split_part(app_version, '+', 1), '.')::int[] ELSE NULL END DESC NULLS LAST, "
        + "CASE WHEN app_version ~ '[+][0-9]+$' THEN split_part(app_version, '+', 2)::int ELSE 0 END DESC",
      'version_asc': "CASE WHEN app_version ~ '^[0-9]+[.][0-9]+[.][0-9]+([+][0-9]+)?$' THEN string_to_array(split_part(app_version, '+', 1), '.')::int[] ELSE NULL END ASC NULLS LAST, "
        + "CASE WHEN app_version ~ '[+][0-9]+$' THEN split_part(app_version, '+', 2)::int ELSE 0 END ASC",
    };
    const orderBy = sortOptions[options.sort] || 'last_login DESC NULLS LAST';

    const countQuery = `SELECT COUNT(*) FROM tc_users ${whereClause}`;
    const countResult = await client.query(countQuery, countParams);
    const total = parseInt(countResult.rows[0].count);

    const dataParams = [...countParams, limit, offset];
    // total_games is the Tichu counter. The admin list wants "how much has
    // this person played", which is all four games — computed here so the
    // sort can use it too.
    const dataQuery = `SELECT id, username, nickname, total_games, wins, losses, rating, gold, level, leave_count, season_rating, created_at, last_login, device_platform, app_version, last_ip, is_admin, is_deleted,
                          (COALESCE(total_games,0) + COALESCE(sk_total_games,0)
                           + COALESCE(ll_total_games,0) + COALESCE(mighty_total_games,0)) AS games_all
                   FROM tc_users ${whereClause}
                   ORDER BY ${orderBy} LIMIT $${paramIdx} OFFSET $${paramIdx + 1}`;
    const result = await client.query(dataQuery, dataParams);
    return { rows: result.rows, total, page, limit };
  } catch (err) {
    console.error('Get users error:', err);
    return { rows: [], total: 0, page, limit };
  } finally {
    client.release();
  }
}

// Get user detail with report/inquiry counts
async function getUserDetail(nickname) {
  const client = await pool.connect();
  try {
    const userResult = await client.query(
      `SELECT id, username, nickname, total_games, wins, losses, rating, created_at, last_login, chat_ban_until, leave_count, gold, level, exp_total, season_rating, admin_memo,
              fcm_token, push_enabled, push_admin_inquiry, push_admin_report, is_admin, is_deleted, deleted_at, device_platform, device_model, os_version, app_version, last_ip, locale,
              sk_total_games, sk_wins, sk_losses, ll_total_games, ll_wins, ll_losses,
              mighty_total_games, mighty_wins, mighty_losses, mighty_rating,
              profile_photo_key, profile_photo_status, profile_photo_expires_at,
              custom_title_text, custom_title_color
       FROM tc_users WHERE nickname = $1`,
      [nickname]
    );
    if (userResult.rows.length === 0) return null;
    const user = userResult.rows[0];

    const equip = await client.query(
      `SELECT title_key FROM tc_user_equips WHERE nickname = $1`,
      [nickname],
    );
    user.title_key = equip.rows[0]?.title_key || null;

    const reportCount = await client.query(
      'SELECT COUNT(*) FROM tc_reports WHERE reported_nickname = $1',
      [nickname]
    );
    const inquiryCount = await client.query(
      'SELECT COUNT(*) FROM tc_inquiries WHERE user_nickname = $1',
      [nickname]
    );
    const adRewardCount = await client.query(
      `SELECT COUNT(*) as total,
              COUNT(*) FILTER (
                WHERE DATE((claimed_at) AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Seoul')
                    = DATE(timezone('Asia/Seoul', NOW()))
              ) as today
       FROM tc_ad_rewards WHERE nickname = $1`,
      [nickname]
    );
    return {
      ...user,
      report_count: parseInt(reportCount.rows[0].count),
      inquiry_count: parseInt(inquiryCount.rows[0].count),
      ad_reward_total: parseInt(adRewardCount.rows[0].total),
      ad_reward_today: parseInt(adRewardCount.rows[0].today),
    };
  } catch (err) {
    console.error('Get user detail error:', err);
    return null;
  } finally {
    client.release();
  }
}

function normalizeDashboardActivityFilters(activityPeriod = 'week', activityGame = 'all') {
  return {
    period: ['today', 'week', 'month'].includes(activityPeriod) ? activityPeriod : 'week',
    game: ['all', 'tichu', 'skull_king', 'love_letter', 'mighty'].includes(activityGame) ? activityGame : 'all',
  };
}

async function queryDashboardActivityTopPlayers(client, activityPeriod = 'week', activityGame = 'all') {
  const { period: safeActivityPeriod, game: safeActivityGame } = normalizeDashboardActivityFilters(activityPeriod, activityGame);
  const kstTodayExpr = `DATE(timezone('Asia/Seoul', NOW()))`;
  // created_at is TIMESTAMP (no tz) stored as UTC wall-clock by the prod
  // PG session (timezone=UTC). Tag it as UTC first, then convert to KST —
  // the older `timezone('Asia/Seoul', ts)` form interpreted the naked value
  // as already-Seoul and shifted rows into the wrong KST day.
  const kstCreatedDate = (column = 'created_at') => `DATE((${column}) AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Seoul')`;
  const activityStartExpr = safeActivityPeriod === 'today'
    ? kstTodayExpr
    : safeActivityPeriod === 'month'
      ? `${kstTodayExpr} - INTERVAL '29 days'`
      : `${kstTodayExpr} - INTERVAL '6 days'`;
  const activityRankExpr = safeActivityGame === 'all'
    ? 'p.activity_games'
    : safeActivityGame === 'tichu'
      ? 'p.tichu_games'
      : safeActivityGame === 'skull_king'
        ? 'p.sk_games'
        : safeActivityGame === 'love_letter'
          ? 'p.ll_games'
          : 'p.mighty_games';

  return client.query(`
    WITH activity AS (
      SELECT nickname, game_type, COUNT(*)::int AS games
      FROM (
        SELECT p.nickname, 'tichu'::text AS game_type
        FROM tc_match_history h
        CROSS JOIN LATERAL (VALUES (h.player_a1), (h.player_a2), (h.player_b1), (h.player_b2)) AS p(nickname)
        WHERE ${kstCreatedDate('h.created_at')} >= ${activityStartExpr}
          AND p.nickname IS NOT NULL
          AND p.nickname <> ''
        UNION ALL
        SELECT p.nickname, 'skull_king'::text AS game_type
        FROM tc_sk_match_history h
        JOIN tc_sk_match_players p ON p.match_id = h.id
        WHERE ${kstCreatedDate('h.created_at')} >= ${activityStartExpr}
          AND p.nickname IS NOT NULL
          AND p.nickname <> ''
          AND p.is_bot IS NOT TRUE
        UNION ALL
        SELECT p.nickname, 'love_letter'::text AS game_type
        FROM tc_ll_match_history h
        JOIN tc_ll_match_players p ON p.match_id = h.id
        WHERE ${kstCreatedDate('h.created_at')} >= ${activityStartExpr}
          AND p.nickname IS NOT NULL
          AND p.nickname <> ''
          AND p.is_bot IS NOT TRUE
        UNION ALL
        SELECT p.nickname, 'mighty'::text AS game_type
        FROM tc_mighty_match_history h
        JOIN tc_mighty_match_players p ON p.match_id = h.id
        WHERE ${kstCreatedDate('h.created_at')} >= ${activityStartExpr}
          AND p.nickname IS NOT NULL
          AND p.nickname <> ''
          AND p.is_bot IS NOT TRUE
      ) raw_activity
      GROUP BY nickname, game_type
    ),
    pivot AS (
      SELECT
        nickname,
        COALESCE(SUM(games), 0)::int AS activity_games,
        COALESCE(SUM(games) FILTER (WHERE game_type = 'tichu'), 0)::int AS tichu_games,
        COALESCE(SUM(games) FILTER (WHERE game_type = 'skull_king'), 0)::int AS sk_games,
        COALESCE(SUM(games) FILTER (WHERE game_type = 'love_letter'), 0)::int AS ll_games,
        COALESCE(SUM(games) FILTER (WHERE game_type = 'mighty'), 0)::int AS mighty_games
      FROM activity
      GROUP BY nickname
    )
    SELECT
      u.nickname,
      u.rating,
      u.total_games,
      u.sk_total_games,
      u.ll_total_games,
      u.mighty_total_games,
      u.level,
      COALESCE(p.activity_games, 0) AS activity_games,
      COALESCE(p.tichu_games, 0) AS tichu_games,
      COALESCE(p.sk_games, 0) AS sk_games,
      COALESCE(p.ll_games, 0) AS ll_games,
      COALESCE(p.mighty_games, 0) AS mighty_games
    FROM pivot p
    JOIN tc_users u ON u.nickname = p.nickname
    WHERE u.is_deleted IS NOT TRUE
      AND ${activityRankExpr} > 0
    ORDER BY ${activityRankExpr} DESC, p.activity_games DESC, p.tichu_games DESC NULLS LAST, p.sk_games DESC NULLS LAST, p.ll_games DESC NULLS LAST, p.mighty_games DESC NULLS LAST, u.nickname ASC
    LIMIT 10
  `);
}

async function getDashboardActivityTopPlayers(activityPeriod = 'week', activityGame = 'all') {
  const client = await pool.connect();
  const { period, game } = normalizeDashboardActivityFilters(activityPeriod, activityGame);
  try {
    const result = await queryDashboardActivityTopPlayers(client, period, game);
    return { rows: result.rows, period, game };
  } catch (err) {
    console.error('Get dashboard activity top players error:', err);
    return { rows: [], period, game };
  } finally {
    client.release();
  }
}

// Get dashboard stats
/** Today's matches across all game types, optionally filtered by ranked-ness. */
async function getTodayMatches(options = {}) {
  const client = await pool.connect();
  try {
    const kstTodayExpr = `DATE(timezone('Asia/Seoul', NOW()))`;
    const kstCreatedDate = `DATE((created_at) AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Seoul')`;
    const rankedFilter = options.ranked === true
      ? 'AND is_ranked = TRUE'
      : options.ranked === false
        ? 'AND (is_ranked IS NOT TRUE)'
        : '';
    const limit = Math.max(1, Math.min(parseInt(options.limit, 10) || 100, 500));
    const result = await client.query(`
      (SELECT id, 'tichu'::text as game_type, winner_team, team_a_score, team_b_score,
        player_a1, player_a2, player_b1, player_b2, is_ranked, end_reason, deserter_nickname, created_at
       FROM tc_match_history
       WHERE ${kstCreatedDate} = ${kstTodayExpr} ${rankedFilter})
      UNION ALL
      (SELECT h.id, 'skull_king'::text as game_type, NULL as winner_team, NULL::int as team_a_score, NULL::int as team_b_score,
        (SELECT string_agg(p.nickname || '(' || p.score || '점)', ', ' ORDER BY p.rank)
         FROM tc_sk_match_players p WHERE p.match_id = h.id) as player_a1,
        h.player_count::text as player_a2, NULL as player_b1, NULL as player_b2,
        h.is_ranked, h.end_reason, h.deserter_nickname, h.created_at
       FROM tc_sk_match_history h
       WHERE DATE((h.created_at) AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Seoul') = ${kstTodayExpr} ${rankedFilter.replace(/is_ranked/g, 'h.is_ranked')})
      UNION ALL
      (SELECT h.id, 'love_letter'::text as game_type, NULL as winner_team, NULL::int as team_a_score, NULL::int as team_b_score,
        (SELECT string_agg(p.nickname || '(' || p.score || '점)', ', ' ORDER BY p.rank)
         FROM tc_ll_match_players p WHERE p.match_id = h.id) as player_a1,
        h.player_count::text as player_a2, NULL as player_b1, NULL as player_b2,
        h.is_ranked, h.end_reason, h.deserter_nickname, h.created_at
       FROM tc_ll_match_history h
       WHERE DATE((h.created_at) AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Seoul') = ${kstTodayExpr} ${rankedFilter.replace(/is_ranked/g, 'h.is_ranked')})
      UNION ALL
      (SELECT h.id, 'mighty'::text as game_type, NULL as winner_team, NULL::int as team_a_score, NULL::int as team_b_score,
        (SELECT string_agg(p.nickname || '(' || p.score || '점)', ', ' ORDER BY p.rank)
         FROM tc_mighty_match_players p WHERE p.match_id = h.id) as player_a1,
        h.player_count::text as player_a2, NULL as player_b1, NULL as player_b2,
        h.is_ranked, h.end_reason, h.deserter_nickname, h.created_at
       FROM tc_mighty_match_history h
       WHERE DATE((h.created_at) AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Seoul') = ${kstTodayExpr} ${rankedFilter.replace(/is_ranked/g, 'h.is_ranked')})
      ORDER BY created_at DESC LIMIT ${limit}
    `);
    return { rows: result.rows };
  } catch (err) {
    console.error('Get today matches error:', err);
    return { rows: [] };
  } finally {
    client.release();
  }
}

// Today's (KST) IAP receipts for the in-app admin "오늘 순매출" drill-down.
// All environments so testers see sandbox buys; UI tags env/status. Each row
// gets an estimated KRW price (store-set price isn't stored) for display.
async function getTodayPayments(options = {}) {
  const client = await pool.connect();
  try {
    const kstTodayExpr = `DATE(timezone('Asia/Seoul', NOW()))`;
    const kstDate = (col) => `DATE((${col}) AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Seoul')`;
    const limit = Math.max(1, Math.min(parseInt(options.limit, 10) || 100, 500));
    const result = await client.query(`
      SELECT nickname, product_id, gold_granted, platform, environment,
             status, refunded_at, verified_at
      FROM tc_iap_receipts
      WHERE ${kstDate('verified_at')} = ${kstTodayExpr}
      ORDER BY verified_at DESC
      LIMIT ${limit}
    `);
    const rows = result.rows.map((r) => ({
      ...r,
      est_krw: GOLD_PRODUCT_KRW[r.product_id] || 0,
    }));
    return { rows };
  } catch (err) {
    console.error('Get today payments error:', err);
    return { rows: [] };
  } finally {
    client.release();
  }
}

async function getDashboardStats(activityPeriod = 'week', activityGame = 'all') {
  const client = await pool.connect();
  try {
    const kstTodayExpr = `DATE(timezone('Asia/Seoul', NOW()))`;
    const kstCreatedDate = (column = 'created_at') => `DATE((${column}) AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Seoul')`;
    const { period: safeActivityPeriod, game: safeActivityGame } = normalizeDashboardActivityFilters(activityPeriod, activityGame);
    // Basic counts
    const totalUsers = await client.query('SELECT COUNT(*) FROM tc_users WHERE is_deleted IS NOT TRUE');
    const pendingInquiries = await client.query(`SELECT COUNT(*) FROM tc_inquiries WHERE status = 'pending'`);
    const pendingReports = await client.query(`SELECT COUNT(*) FROM tc_reports WHERE status = 'pending'`);
    const totalInquiries = await client.query(`SELECT COUNT(*) FROM tc_inquiries`);
    const totalReports = await client.query(`SELECT COUNT(*) FROM tc_reports`);
    const todayGames = await client.query(`
      SELECT
        (SELECT COUNT(*) FROM tc_match_history WHERE ${kstCreatedDate()} = ${kstTodayExpr}) as tichu,
        (SELECT COUNT(*) FROM tc_sk_match_history WHERE ${kstCreatedDate()} = ${kstTodayExpr}) as sk,
        (SELECT COUNT(*) FROM tc_ll_match_history WHERE ${kstCreatedDate()} = ${kstTodayExpr}) as ll,
        (SELECT COUNT(*) FROM tc_mighty_match_history WHERE ${kstCreatedDate()} = ${kstTodayExpr}) as mighty
    `);
    const recentMatches = await client.query(`
      (SELECT id, 'tichu'::text as game_type, winner_team, team_a_score, team_b_score,
        player_a1, player_a2, player_b1, player_b2, is_ranked, end_reason, deserter_nickname, created_at
       FROM tc_match_history ORDER BY created_at DESC LIMIT 10)
      UNION ALL
      (SELECT h.id, 'skull_king'::text as game_type, NULL as winner_team, NULL::int as team_a_score, NULL::int as team_b_score,
        (SELECT string_agg(p.nickname || '(' || p.score || '점)', ', ' ORDER BY p.rank) FROM tc_sk_match_players p WHERE p.match_id = h.id) as player_a1,
        h.player_count::text as player_a2, NULL as player_b1, NULL as player_b2,
        h.is_ranked, h.end_reason, h.deserter_nickname, h.created_at
       FROM tc_sk_match_history h ORDER BY h.created_at DESC LIMIT 10)
      UNION ALL
      (SELECT h.id, 'love_letter'::text as game_type, NULL as winner_team, NULL::int as team_a_score, NULL::int as team_b_score,
        (SELECT string_agg(p.nickname || '(' || p.score || '점)', ', ' ORDER BY p.rank) FROM tc_ll_match_players p WHERE p.match_id = h.id) as player_a1,
        h.player_count::text as player_a2, NULL as player_b1, NULL as player_b2,
        h.is_ranked, h.end_reason, h.deserter_nickname, h.created_at
       FROM tc_ll_match_history h ORDER BY h.created_at DESC LIMIT 10)
      UNION ALL
      (SELECT h.id, 'mighty'::text as game_type, NULL as winner_team, NULL::int as team_a_score, NULL::int as team_b_score,
        (SELECT string_agg(p.nickname || '(' || p.score || '점)', ', ' ORDER BY p.rank) FROM tc_mighty_match_players p WHERE p.match_id = h.id) as player_a1,
        h.player_count::text as player_a2, NULL as player_b1, NULL as player_b2,
        h.is_ranked, h.end_reason, h.deserter_nickname, h.created_at
       FROM tc_mighty_match_history h ORDER BY h.created_at DESC LIMIT 10)
      ORDER BY created_at DESC LIMIT 10
    `);

    // New users today
    const newUsersToday = await client.query(
      `SELECT COUNT(*) FROM tc_users WHERE ${kstCreatedDate()} = ${kstTodayExpr} AND is_deleted IS NOT TRUE`
    );

    // Active users (logged in within 24h / 7d)
    const activeUsers24h = await client.query(
      `SELECT COUNT(*) FROM tc_users WHERE last_login >= NOW() - INTERVAL '24 hours' AND is_deleted IS NOT TRUE`
    );
    const activeUsers7d = await client.query(
      `SELECT COUNT(*) FROM tc_users WHERE last_login >= NOW() - INTERVAL '7 days' AND is_deleted IS NOT TRUE`
    );

    // Total matches + ranked matches (tichu + skull king)
    const totalMatches = await client.query(
      `SELECT (SELECT COUNT(*) FROM tc_match_history) + (SELECT COUNT(*) FROM tc_sk_match_history) + (SELECT COUNT(*) FROM tc_ll_match_history) + (SELECT COUNT(*) FROM tc_mighty_match_history) as count`
    );
    const rankedMatchesToday = await client.query(
      `SELECT (SELECT COUNT(*) FROM tc_match_history WHERE ${kstCreatedDate()} = ${kstTodayExpr} AND is_ranked = true) + (SELECT COUNT(*) FROM tc_sk_match_history WHERE ${kstCreatedDate()} = ${kstTodayExpr} AND is_ranked = true) + (SELECT COUNT(*) FROM tc_ll_match_history WHERE ${kstCreatedDate()} = ${kstTodayExpr} AND is_ranked = true) + (SELECT COUNT(*) FROM tc_mighty_match_history WHERE ${kstCreatedDate()} = ${kstTodayExpr} AND is_ranked = true) as count`
    );

    // Games per day (last 7 days) - tichu + skull king combined
    const dailyGames = await client.query(`
      SELECT day, SUM(cnt) as cnt, SUM(ranked_cnt) as ranked_cnt, SUM(tichu_cnt) as tichu_cnt, SUM(sk_cnt) as sk_cnt, SUM(ll_cnt) as ll_cnt, SUM(mighty_cnt) as mighty_cnt FROM (
        SELECT ${kstCreatedDate()} as day, COUNT(*) as cnt,
               SUM(CASE WHEN is_ranked THEN 1 ELSE 0 END) as ranked_cnt,
               COUNT(*) as tichu_cnt, 0::bigint as sk_cnt, 0::bigint as ll_cnt, 0::bigint as mighty_cnt
        FROM tc_match_history
        WHERE ${kstCreatedDate()} >= ${kstTodayExpr} - INTERVAL '6 days'
        GROUP BY ${kstCreatedDate()}
        UNION ALL
        SELECT ${kstCreatedDate()} as day, COUNT(*) as cnt,
               SUM(CASE WHEN is_ranked THEN 1 ELSE 0 END) as ranked_cnt,
               0::bigint as tichu_cnt, COUNT(*) as sk_cnt, 0::bigint as ll_cnt, 0::bigint as mighty_cnt
        FROM tc_sk_match_history
        WHERE ${kstCreatedDate()} >= ${kstTodayExpr} - INTERVAL '6 days'
        GROUP BY ${kstCreatedDate()}
        UNION ALL
        SELECT ${kstCreatedDate()} as day, COUNT(*) as cnt,
               SUM(CASE WHEN is_ranked THEN 1 ELSE 0 END) as ranked_cnt,
               0::bigint as tichu_cnt, 0::bigint as sk_cnt, COUNT(*) as ll_cnt, 0::bigint as mighty_cnt
        FROM tc_ll_match_history
        WHERE ${kstCreatedDate()} >= ${kstTodayExpr} - INTERVAL '6 days'
        GROUP BY ${kstCreatedDate()}
        UNION ALL
        SELECT ${kstCreatedDate()} as day, COUNT(*) as cnt,
               SUM(CASE WHEN is_ranked THEN 1 ELSE 0 END) as ranked_cnt,
               0::bigint as tichu_cnt, 0::bigint as sk_cnt, 0::bigint as ll_cnt, COUNT(*) as mighty_cnt
        FROM tc_mighty_match_history
        WHERE ${kstCreatedDate()} >= ${kstTodayExpr} - INTERVAL '6 days'
        GROUP BY ${kstCreatedDate()}
      ) combined GROUP BY day ORDER BY day
    `);

    // New users per day (last 7 days)
    const dailySignups = await client.query(`
      SELECT ${kstCreatedDate()} as day, COUNT(*) as cnt
      FROM tc_users
      WHERE ${kstCreatedDate()} >= ${kstTodayExpr} - INTERVAL '6 days' AND is_deleted IS NOT TRUE
      GROUP BY ${kstCreatedDate()}
      ORDER BY day
    `);

    // Top 10 players by activity in the selected KST period
    const topPlayers = await queryDashboardActivityTopPlayers(client, safeActivityPeriod, safeActivityGame);

    // Gold economy
    const goldStats = await client.query(`
      SELECT SUM(gold) as total_gold, AVG(gold) as avg_gold, MAX(gold) as max_gold
      FROM tc_users WHERE is_deleted IS NOT TRUE
    `);

    // Shop revenue (total items purchased)
    const shopStats = await client.query(`
      SELECT COUNT(*) as total_purchased,
             COUNT(DISTINCT nickname) as unique_buyers
      FROM tc_user_items WHERE source = 'shop'
    `);

    // Leave stats
    const leaveStats = await client.query(`
      SELECT SUM(leave_count) as total_leaves,
             COUNT(CASE WHEN leave_count >= 3 THEN 1 END) as problem_users
      FROM tc_users WHERE is_deleted IS NOT TRUE
    `);

    // Report stats (last 30 days)
    const reportStats30d = await client.query(`
      SELECT COUNT(*) as total_reports,
             COUNT(DISTINCT reported_nickname) as unique_reported
      FROM tc_reports WHERE created_at >= NOW() - INTERVAL '30 days'
    `);

    // Ad reward stats
    const kstClaimedDate = `DATE((claimed_at) AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Seoul')`;
    const adRewardStats = await client.query(`
      SELECT COUNT(*) as total_claims,
             COUNT(DISTINCT nickname) as unique_users,
             COUNT(*) FILTER (WHERE ${kstClaimedDate} = ${kstTodayExpr}) as today_claims,
             COUNT(DISTINCT nickname) FILTER (WHERE ${kstClaimedDate} = ${kstTodayExpr}) as today_users
      FROM tc_ad_rewards
    `);

    // Daily ad rewards (last 7 days)
    const dailyAdRewards = await client.query(`
      SELECT ${kstClaimedDate} as day, COUNT(*) as cnt, COUNT(DISTINCT nickname) as users
      FROM tc_ad_rewards
      WHERE ${kstClaimedDate} >= ${kstTodayExpr} - INTERVAL '6 days'
      GROUP BY ${kstClaimedDate}
      ORDER BY day
    `);

    // Today's IAP revenue (production only — sandbox/test buys are not money).
    // Price isn't stored (store-controlled), so estimate from GOLD_PRODUCT_KRW.
    const iapPaidToday = await client.query(`
      SELECT product_id, COUNT(*) AS cnt
      FROM tc_iap_receipts
      WHERE environment = 'production'
        AND ${kstCreatedDate('verified_at')} = ${kstTodayExpr}
      GROUP BY product_id
    `);
    const iapRefundToday = await client.query(`
      SELECT product_id, COUNT(*) AS cnt
      FROM tc_iap_receipts
      WHERE environment = 'production'
        AND refunded_at IS NOT NULL
        AND ${kstCreatedDate('refunded_at')} = ${kstTodayExpr}
      GROUP BY product_id
    `);
    const krwOf = (pid) => GOLD_PRODUCT_KRW[pid] || 0;
    let todayPaidCount = 0;
    let todayGrossRevenue = 0;
    for (const r of iapPaidToday.rows) {
      const c = parseInt(r.cnt, 10) || 0;
      todayPaidCount += c;
      todayGrossRevenue += krwOf(r.product_id) * c;
    }
    let todayRefundCount = 0;
    let todayRefundRevenue = 0;
    for (const r of iapRefundToday.rows) {
      const c = parseInt(r.cnt, 10) || 0;
      todayRefundCount += c;
      todayRefundRevenue += krwOf(r.product_id) * c;
    }

    return {
      todayPaidCount,
      todayRefundCount,
      todayGrossRevenue,
      todayRefundRevenue,
      todayNetRevenue: todayGrossRevenue - todayRefundRevenue,
      totalUsers: parseInt(totalUsers.rows[0].count),
      pendingInquiries: parseInt(pendingInquiries.rows[0].count),
      pendingReports: parseInt(pendingReports.rows[0].count),
      totalInquiries: parseInt(totalInquiries.rows[0].count),
      totalReports: parseInt(totalReports.rows[0].count),
      todayGames: parseInt(todayGames.rows[0].tichu) + parseInt(todayGames.rows[0].sk) + parseInt(todayGames.rows[0].ll) + parseInt(todayGames.rows[0].mighty),
      todayTichuGames: parseInt(todayGames.rows[0].tichu),
      todaySKGames: parseInt(todayGames.rows[0].sk),
      todayLLGames: parseInt(todayGames.rows[0].ll),
      todayMightyGames: parseInt(todayGames.rows[0].mighty),
      recentMatches: recentMatches.rows,
      newUsersToday: parseInt(newUsersToday.rows[0].count),
      activeUsers24h: parseInt(activeUsers24h.rows[0].count),
      activeUsers7d: parseInt(activeUsers7d.rows[0].count),
      totalMatches: parseInt(totalMatches.rows[0].count),
      rankedMatchesToday: parseInt(rankedMatchesToday.rows[0].count),
      dailyGames: dailyGames.rows,
      dailySignups: dailySignups.rows,
      topPlayers: topPlayers.rows,
      topPlayersPeriod: safeActivityPeriod,
      topPlayersGame: safeActivityGame,
      goldStats: goldStats.rows[0],
      shopStats: shopStats.rows[0],
      leaveStats: leaveStats.rows[0],
      reportStats30d: reportStats30d.rows[0],
      adRewardStats: adRewardStats.rows[0],
      dailyAdRewards: dailyAdRewards.rows,
    };
  } catch (err) {
    console.error('Get dashboard stats error:', err);
    return {
      totalUsers: 0, pendingInquiries: 0, pendingReports: 0, totalInquiries: 0, totalReports: 0, todayGames: 0, todayTichuGames: 0, todaySKGames: 0, todayLLGames: 0, todayMightyGames: 0,
      recentMatches: [], newUsersToday: 0, activeUsers24h: 0, activeUsers7d: 0,
      totalMatches: 0, rankedMatchesToday: 0, dailyGames: [], dailySignups: [],
      topPlayers: [], topPlayersPeriod: 'week', topPlayersGame: 'all', goldStats: {}, shopStats: {}, leaveStats: {}, reportStats30d: {},
      adRewardStats: {}, dailyAdRewards: [],
    };
  } finally {
    client.release();
  }
}

async function getAdminRecentMatches(page = 1, limit = 30) {
  const client = await pool.connect();
  try {
    const safePage = Math.max(1, parseInt(page, 10) || 1);
    const safeLimit = Math.min(100, Math.max(1, parseInt(limit, 10) || 30));
    const offset = (safePage - 1) * safeLimit;

    const countResult = await client.query(
      `SELECT
         (SELECT COUNT(*) FROM tc_match_history) +
         (SELECT COUNT(*) FROM tc_sk_match_history) +
         (SELECT COUNT(*) FROM tc_ll_match_history) +
         (SELECT COUNT(*) FROM tc_mighty_match_history) AS total`
    );

    const result = await client.query(
      `SELECT * FROM (
        SELECT id, 'tichu'::text AS game_type, winner_team, team_a_score, team_b_score,
               player_a1, player_a2, player_b1, player_b2,
               is_ranked, end_reason, deserter_nickname, created_at
        FROM tc_match_history
        UNION ALL
        SELECT h.id, 'skull_king'::text AS game_type, NULL AS winner_team, NULL::int AS team_a_score, NULL::int AS team_b_score,
               (SELECT string_agg(p.nickname || '(' || p.score || '점)', ', ' ORDER BY p.rank) FROM tc_sk_match_players p WHERE p.match_id = h.id) AS player_a1,
               h.player_count::text AS player_a2, NULL AS player_b1, NULL AS player_b2,
               h.is_ranked, h.end_reason, h.deserter_nickname, h.created_at
        FROM tc_sk_match_history h
        UNION ALL
        SELECT h.id, 'love_letter'::text AS game_type, NULL AS winner_team, NULL::int AS team_a_score, NULL::int AS team_b_score,
               (SELECT string_agg(p.nickname || '(' || p.score || '점)', ', ' ORDER BY p.rank) FROM tc_ll_match_players p WHERE p.match_id = h.id) AS player_a1,
               h.player_count::text AS player_a2, NULL AS player_b1, NULL AS player_b2,
               h.is_ranked, h.end_reason, h.deserter_nickname, h.created_at
        FROM tc_ll_match_history h
        UNION ALL
        SELECT h.id, 'mighty'::text AS game_type, NULL AS winner_team, NULL::int AS team_a_score, NULL::int AS team_b_score,
               (SELECT string_agg(p.nickname || '(' || p.score || '점)', ', ' ORDER BY p.rank) FROM tc_mighty_match_players p WHERE p.match_id = h.id) AS player_a1,
               h.player_count::text AS player_a2, NULL AS player_b1, NULL AS player_b2,
               h.is_ranked, h.end_reason, h.deserter_nickname, h.created_at
        FROM tc_mighty_match_history h
      ) matches
      ORDER BY created_at DESC
      LIMIT $1 OFFSET $2`,
      [safeLimit, offset]
    );

    return {
      rows: result.rows,
      total: parseInt(countResult.rows[0].total, 10) || 0,
      page: safePage,
      limit: safeLimit,
    };
  } catch (err) {
    console.error('Get admin recent matches error:', err);
    return { rows: [], total: 0, page, limit };
  } finally {
    client.release();
  }
}

async function getDetailedAdminStats(dateFrom, dateTo, bucket = 'day', options = {}) {
  const client = await pool.connect();
  const groupUnit = bucket === 'hour' ? 'hour' : 'day';
  const from = dateFrom || new Date(Date.now() - 6 * 24 * 60 * 60 * 1000).toISOString();
  const to = dateTo || new Date().toISOString();
  // Truncate to the KST wall-clock boundary, then re-attach the Seoul tz so
  // the value comes back to JS as a timestamptz pointing at the correct UTC
  // instant. Without the trailing AT TIME ZONE, pg-node would receive a
  // naked timestamp and parse it as UTC, shifting chart labels by 9h.
  const kstBucketExpr = (column) => `(DATE_TRUNC('${groupUnit}', (${column}) AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Seoul')) AT TIME ZONE 'Asia/Seoul'`;
  const platform = ['ios', 'android'].includes(String(options.platform || '').toLowerCase())
    ? String(options.platform).toLowerCase()
    : '';
  try {
    const gameSeries = await client.query(`
      WITH tichu AS (
        SELECT ${kstBucketExpr('created_at')} AS bucket_time,
               COUNT(DISTINCT mh.id) AS total_cnt,
               COUNT(DISTINCT mh.id) FILTER (WHERE mh.is_ranked = TRUE) AS ranked_cnt
        FROM tc_match_history mh
        WHERE mh.created_at >= $1 AND mh.created_at < $2
          AND (
            $3 = '' OR EXISTS (
              SELECT 1
              FROM tc_users u
              WHERE LOWER(u.device_platform) = $3
                AND u.nickname IN (mh.player_a1, mh.player_a2, mh.player_b1, mh.player_b2)
            )
          )
        GROUP BY 1
      ),
      skull AS (
        SELECT ${kstBucketExpr('h.created_at')} AS bucket_time,
               COUNT(DISTINCT h.id) AS total_cnt,
               COUNT(DISTINCT h.id) FILTER (WHERE h.is_ranked = TRUE) AS ranked_cnt
        FROM tc_sk_match_history h
        WHERE h.created_at >= $1 AND h.created_at < $2
          AND (
            $3 = '' OR EXISTS (
              SELECT 1
              FROM tc_sk_match_players p
              JOIN tc_users u ON u.nickname = p.nickname
              WHERE p.match_id = h.id
                AND p.is_bot = FALSE
                AND LOWER(u.device_platform) = $3
            )
          )
        GROUP BY 1
      ),
      love AS (
        SELECT ${kstBucketExpr('h.created_at')} AS bucket_time,
               COUNT(DISTINCT h.id) AS total_cnt,
               COUNT(DISTINCT h.id) FILTER (WHERE h.is_ranked = TRUE) AS ranked_cnt
        FROM tc_ll_match_history h
        WHERE h.created_at >= $1 AND h.created_at < $2
          AND (
            $3 = '' OR EXISTS (
              SELECT 1
              FROM tc_ll_match_players p
              JOIN tc_users u ON u.nickname = p.nickname
              WHERE p.match_id = h.id
                AND p.is_bot = FALSE
                AND LOWER(u.device_platform) = $3
            )
          )
        GROUP BY 1
      ),
      mighty AS (
        SELECT ${kstBucketExpr('h.created_at')} AS bucket_time,
               COUNT(DISTINCT h.id) AS total_cnt,
               COUNT(DISTINCT h.id) FILTER (WHERE h.is_ranked = TRUE) AS ranked_cnt
        FROM tc_mighty_match_history h
        WHERE h.created_at >= $1 AND h.created_at < $2
          AND (
            $3 = '' OR EXISTS (
              SELECT 1
              FROM tc_mighty_match_players p
              JOIN tc_users u ON u.nickname = p.nickname
              WHERE p.match_id = h.id
                AND p.is_bot = FALSE
                AND LOWER(u.device_platform) = $3
            )
          )
        GROUP BY 1
      ),
      buckets AS (
        SELECT bucket_time FROM tichu
        UNION
        SELECT bucket_time FROM skull
        UNION
        SELECT bucket_time FROM love
        UNION
        SELECT bucket_time FROM mighty
      )
      SELECT b.bucket_time,
             COALESCE(tichu.total_cnt, 0) AS tichu_cnt,
             COALESCE(skull.total_cnt, 0) AS skull_cnt,
             COALESCE(love.total_cnt, 0) AS ll_cnt,
             COALESCE(mighty.total_cnt, 0) AS mighty_cnt,
             COALESCE(tichu.total_cnt, 0) + COALESCE(skull.total_cnt, 0) + COALESCE(love.total_cnt, 0) + COALESCE(mighty.total_cnt, 0) AS total_cnt,
             COALESCE(tichu.ranked_cnt, 0) + COALESCE(skull.ranked_cnt, 0) + COALESCE(love.ranked_cnt, 0) + COALESCE(mighty.ranked_cnt, 0) AS ranked_cnt
      FROM buckets b
      LEFT JOIN tichu ON tichu.bucket_time = b.bucket_time
      LEFT JOIN skull ON skull.bucket_time = b.bucket_time
      LEFT JOIN love ON love.bucket_time = b.bucket_time
      LEFT JOIN mighty ON mighty.bucket_time = b.bucket_time
      ORDER BY b.bucket_time ASC
    `, [from, to, platform]);

    const goldSeries = await client.query(`
      WITH gold_events AS (
        SELECT ${kstBucketExpr('mh.created_at')} AS bucket_time,
               CASE
                 WHEN mh.winner_team = 'draw' THEN 0
                 WHEN mh.end_reason IN ('leave', 'timeout') AND mh.deserter_nickname = p.nickname THEN 0
                 WHEN (
                   (p.team_code = 'A' AND mh.winner_team = 'A') OR
                   (p.team_code = 'B' AND mh.winner_team = 'B')
                 ) THEN CASE WHEN mh.is_ranked THEN 20 ELSE 10 END
                 ELSE CASE WHEN mh.is_ranked THEN 6 ELSE 3 END
               END AS gold_delta
        FROM tc_match_history mh
        CROSS JOIN LATERAL (
          VALUES
            (mh.player_a1, 'A'),
            (mh.player_a2, 'A'),
            (mh.player_b1, 'B'),
            (mh.player_b2, 'B')
        ) AS p(nickname, team_code)
        WHERE mh.created_at >= $1 AND mh.created_at < $2
          AND p.nickname IS NOT NULL
          AND EXISTS (
            SELECT 1 FROM tc_users u
            WHERE u.nickname = p.nickname
              AND ($3 = '' OR LOWER(u.device_platform) = $3)
          )

        UNION ALL

        SELECT ${kstBucketExpr('h.created_at')} AS bucket_time,
               CASE
                 WHEN h.end_reason IN ('leave', 'timeout') AND h.deserter_nickname = p.nickname THEN 0
                 WHEN p.is_winner THEN CASE WHEN h.is_ranked THEN 20 ELSE 10 END
                 ELSE CASE WHEN h.is_ranked THEN 6 ELSE 3 END
               END AS gold_delta
        FROM tc_sk_match_history h
        JOIN tc_sk_match_players p ON p.match_id = h.id
        WHERE h.created_at >= $1 AND h.created_at < $2
          AND p.is_bot = FALSE
          AND EXISTS (
            SELECT 1 FROM tc_users u
            WHERE u.nickname = p.nickname
              AND ($3 = '' OR LOWER(u.device_platform) = $3)
          )

        UNION ALL

        SELECT ${kstBucketExpr('h.created_at')} AS bucket_time,
               CASE
                 WHEN h.end_reason IN ('leave', 'timeout') AND h.deserter_nickname = p.nickname THEN 0
                 WHEN p.is_winner THEN CASE WHEN h.is_ranked THEN 20 ELSE 10 END
                 ELSE CASE WHEN h.is_ranked THEN 6 ELSE 3 END
               END AS gold_delta
        FROM tc_ll_match_history h
        JOIN tc_ll_match_players p ON p.match_id = h.id
        WHERE h.created_at >= $1 AND h.created_at < $2
          AND p.is_bot = FALSE
          AND EXISTS (
            SELECT 1 FROM tc_users u
            WHERE u.nickname = p.nickname
              AND ($3 = '' OR LOWER(u.device_platform) = $3)
          )

        UNION ALL

        SELECT ${kstBucketExpr('h.created_at')} AS bucket_time,
               CASE
                 WHEN h.end_reason IN ('leave', 'timeout') AND h.deserter_nickname = p.nickname THEN 0
                 WHEN p.is_winner THEN CASE WHEN h.is_ranked THEN 20 ELSE 10 END
                 ELSE CASE WHEN h.is_ranked THEN 6 ELSE 3 END
               END AS gold_delta
        FROM tc_mighty_match_history h
        JOIN tc_mighty_match_players p ON p.match_id = h.id
        WHERE h.created_at >= $1 AND h.created_at < $2
          AND p.is_bot = FALSE
          AND EXISTS (
            SELECT 1 FROM tc_users u
            WHERE u.nickname = p.nickname
              AND ($3 = '' OR LOWER(u.device_platform) = $3)
          )

        UNION ALL

        SELECT ${kstBucketExpr('ar.claimed_at')} AS bucket_time,
               50 AS gold_delta
        FROM tc_ad_rewards ar
        JOIN tc_users u ON u.nickname = ar.nickname
        WHERE ar.claimed_at >= $1 AND ar.claimed_at < $2
          AND ($3 = '' OR LOWER(u.device_platform) = $3)

        UNION ALL

        SELECT ${kstBucketExpr('ui.acquired_at')} AS bucket_time,
               -COALESCE(si.price, 0) AS gold_delta
        FROM tc_user_items ui
        LEFT JOIN tc_shop_items si ON si.item_key = ui.item_key
        JOIN tc_users u ON u.nickname = ui.nickname
        WHERE ui.source = 'shop'
          AND ui.acquired_at >= $1 AND ui.acquired_at < $2
          AND ($3 = '' OR LOWER(u.device_platform) = $3)

        UNION ALL

        SELECT ${kstBucketExpr('gh.created_at')} AS bucket_time,
               gh.gold_delta
        FROM tc_gold_history gh
        JOIN tc_users u ON u.nickname = gh.nickname
        WHERE gh.created_at >= $1 AND gh.created_at < $2
          AND ($3 = '' OR LOWER(u.device_platform) = $3)
      )
      SELECT bucket_time,
             COALESCE(SUM(CASE WHEN gold_delta > 0 THEN gold_delta ELSE 0 END), 0) AS earned,
             COALESCE(SUM(CASE WHEN gold_delta < 0 THEN -gold_delta ELSE 0 END), 0) AS spent,
             COALESCE(SUM(gold_delta), 0) AS net
      FROM gold_events
      GROUP BY bucket_time
      ORDER BY bucket_time ASC
    `, [from, to, platform]);

    const shopSalesSeries = await client.query(`
      SELECT
        ${kstBucketExpr('ui.acquired_at')} AS bucket_time,
        COUNT(*) AS purchase_count,
        COUNT(DISTINCT ui.nickname) AS buyer_count,
        COALESCE(SUM(si.price), 0) AS gold_spent
      FROM tc_user_items ui
      LEFT JOIN tc_shop_items si ON si.item_key = ui.item_key
      JOIN tc_users u ON u.nickname = ui.nickname
      WHERE ui.source = 'shop'
        AND ui.acquired_at >= $1 AND ui.acquired_at < $2
        AND ($3 = '' OR LOWER(u.device_platform) = $3)
      GROUP BY 1
      ORDER BY 1 ASC
    `, [from, to, platform]);

    const topShopItems = await client.query(`
      SELECT
        ui.item_key,
        COALESCE(si.name_ko, ui.item_key) AS item_name,
        COALESCE(si.category, '-') AS category,
        COUNT(*) AS purchase_count,
        COUNT(DISTINCT ui.nickname) AS buyer_count,
        COALESCE(SUM(si.price), 0) AS gold_spent,
        MIN(ui.acquired_at) AS first_sold_at,
        MAX(ui.acquired_at) AS last_sold_at
      FROM tc_user_items ui
      LEFT JOIN tc_shop_items si ON si.item_key = ui.item_key
      JOIN tc_users u ON u.nickname = ui.nickname
      WHERE ui.source = 'shop'
        AND ui.acquired_at >= $1 AND ui.acquired_at < $2
        AND ($3 = '' OR LOWER(u.device_platform) = $3)
      GROUP BY ui.item_key, si.name_ko, si.category
      ORDER BY purchase_count DESC, gold_spent DESC, item_name ASC
      LIMIT 15
    `, [from, to, platform]);

    const signupSeries = await client.query(`
      SELECT
        ${kstBucketExpr('created_at')} AS bucket_time,
        COUNT(*) AS total_cnt,
        COUNT(*) FILTER (WHERE LOWER(device_platform) = 'ios') AS ios_cnt,
        COUNT(*) FILTER (WHERE LOWER(device_platform) = 'android') AS android_cnt
      FROM tc_users
      WHERE created_at >= $1 AND created_at < $2
        AND is_deleted IS NOT TRUE
        AND ($3 = '' OR LOWER(device_platform) = $3)
      GROUP BY 1
      ORDER BY 1 ASC
    `, [from, to, platform]);

    const gameSummary = await client.query(`
      SELECT
        (
          SELECT COUNT(*)
          FROM tc_match_history mh
          WHERE mh.created_at >= $1 AND mh.created_at < $2
            AND (
              $3 = '' OR EXISTS (
                SELECT 1 FROM tc_users u
                WHERE LOWER(u.device_platform) = $3
                  AND u.nickname IN (mh.player_a1, mh.player_a2, mh.player_b1, mh.player_b2)
              )
            )
        ) AS tichu_games,
        (
          SELECT COUNT(*)
          FROM tc_sk_match_history h
          WHERE h.created_at >= $1 AND h.created_at < $2
            AND (
              $3 = '' OR EXISTS (
                SELECT 1
                FROM tc_sk_match_players p
                JOIN tc_users u ON u.nickname = p.nickname
                WHERE p.match_id = h.id
                  AND p.is_bot = FALSE
                  AND LOWER(u.device_platform) = $3
              )
            )
        ) AS skull_games,
        (
          SELECT COUNT(*)
          FROM tc_ll_match_history h
          WHERE h.created_at >= $1 AND h.created_at < $2
            AND (
              $3 = '' OR EXISTS (
                SELECT 1
                FROM tc_ll_match_players p
                JOIN tc_users u ON u.nickname = p.nickname
                WHERE p.match_id = h.id
                  AND p.is_bot = FALSE
                  AND LOWER(u.device_platform) = $3
              )
            )
        ) AS ll_games,
        (
          SELECT COUNT(*)
          FROM tc_mighty_match_history h
          WHERE h.created_at >= $1 AND h.created_at < $2
            AND (
              $3 = '' OR EXISTS (
                SELECT 1
                FROM tc_mighty_match_players p
                JOIN tc_users u ON u.nickname = p.nickname
                WHERE p.match_id = h.id
                  AND p.is_bot = FALSE
                  AND LOWER(u.device_platform) = $3
              )
            )
        ) AS mighty_games,
        (
          SELECT COUNT(*)
          FROM tc_match_history mh
          WHERE mh.created_at >= $1 AND mh.created_at < $2
            AND mh.is_ranked = TRUE
            AND (
              $3 = '' OR EXISTS (
                SELECT 1 FROM tc_users u
                WHERE LOWER(u.device_platform) = $3
                  AND u.nickname IN (mh.player_a1, mh.player_a2, mh.player_b1, mh.player_b2)
              )
            )
        ) +
        (
          SELECT COUNT(*)
          FROM tc_sk_match_history h
          WHERE h.created_at >= $1 AND h.created_at < $2
            AND h.is_ranked = TRUE
            AND (
              $3 = '' OR EXISTS (
                SELECT 1
                FROM tc_sk_match_players p
                JOIN tc_users u ON u.nickname = p.nickname
                WHERE p.match_id = h.id
                  AND p.is_bot = FALSE
                  AND LOWER(u.device_platform) = $3
              )
            )
        ) +
        (
          SELECT COUNT(*)
          FROM tc_ll_match_history h
          WHERE h.created_at >= $1 AND h.created_at < $2
            AND h.is_ranked = TRUE
            AND (
              $3 = '' OR EXISTS (
                SELECT 1
                FROM tc_ll_match_players p
                JOIN tc_users u ON u.nickname = p.nickname
                WHERE p.match_id = h.id
                  AND p.is_bot = FALSE
                AND LOWER(u.device_platform) = $3
              )
            )
        ) +
        (
          SELECT COUNT(*)
          FROM tc_mighty_match_history h
          WHERE h.created_at >= $1 AND h.created_at < $2
            AND h.is_ranked = TRUE
            AND (
              $3 = '' OR EXISTS (
                SELECT 1
                FROM tc_mighty_match_players p
                JOIN tc_users u ON u.nickname = p.nickname
                WHERE p.match_id = h.id
                  AND p.is_bot = FALSE
                  AND LOWER(u.device_platform) = $3
              )
            )
        ) AS ranked_games
    `, [from, to, platform]);

    const shopSummary = await client.query(`
      SELECT
        COUNT(*) AS total_purchases,
        COUNT(DISTINCT ui.nickname) AS unique_buyers,
        COALESCE(SUM(si.price), 0) AS total_gold_spent,
        COUNT(DISTINCT ui.item_key) AS unique_items_sold
      FROM tc_user_items ui
      LEFT JOIN tc_shop_items si ON si.item_key = ui.item_key
      JOIN tc_users u ON u.nickname = ui.nickname
      WHERE ui.source = 'shop'
        AND ui.acquired_at >= $1 AND ui.acquired_at < $2
        AND ($3 = '' OR LOWER(u.device_platform) = $3)
    `, [from, to, platform]);

    const goldSummary = await client.query(`
      WITH gold_events AS (
        SELECT CASE
                 WHEN mh.winner_team = 'draw' THEN 0
                 WHEN mh.end_reason IN ('leave', 'timeout') AND mh.deserter_nickname = p.nickname THEN 0
                 WHEN (
                   (p.team_code = 'A' AND mh.winner_team = 'A') OR
                   (p.team_code = 'B' AND mh.winner_team = 'B')
                 ) THEN CASE WHEN mh.is_ranked THEN 20 ELSE 10 END
                 ELSE CASE WHEN mh.is_ranked THEN 6 ELSE 3 END
               END AS gold_delta
        FROM tc_match_history mh
        CROSS JOIN LATERAL (
          VALUES
            (mh.player_a1, 'A'),
            (mh.player_a2, 'A'),
            (mh.player_b1, 'B'),
            (mh.player_b2, 'B')
        ) AS p(nickname, team_code)
        WHERE mh.created_at >= $1 AND mh.created_at < $2
          AND p.nickname IS NOT NULL
          AND EXISTS (
            SELECT 1 FROM tc_users u
            WHERE u.nickname = p.nickname
              AND ($3 = '' OR LOWER(u.device_platform) = $3)
          )

        UNION ALL

        SELECT CASE
                 WHEN h.end_reason IN ('leave', 'timeout') AND h.deserter_nickname = p.nickname THEN 0
                 WHEN p.is_winner THEN CASE WHEN h.is_ranked THEN 20 ELSE 10 END
                 ELSE CASE WHEN h.is_ranked THEN 6 ELSE 3 END
               END AS gold_delta
        FROM tc_sk_match_history h
        JOIN tc_sk_match_players p ON p.match_id = h.id
        WHERE h.created_at >= $1 AND h.created_at < $2
          AND p.is_bot = FALSE
          AND EXISTS (
            SELECT 1 FROM tc_users u
            WHERE u.nickname = p.nickname
              AND ($3 = '' OR LOWER(u.device_platform) = $3)
          )

        UNION ALL

        SELECT CASE
                 WHEN h.end_reason IN ('leave', 'timeout') AND h.deserter_nickname = p.nickname THEN 0
                 WHEN p.is_winner THEN CASE WHEN h.is_ranked THEN 20 ELSE 10 END
                 ELSE CASE WHEN h.is_ranked THEN 6 ELSE 3 END
               END AS gold_delta
        FROM tc_ll_match_history h
        JOIN tc_ll_match_players p ON p.match_id = h.id
        WHERE h.created_at >= $1 AND h.created_at < $2
          AND p.is_bot = FALSE
          AND EXISTS (
            SELECT 1 FROM tc_users u
            WHERE u.nickname = p.nickname
              AND ($3 = '' OR LOWER(u.device_platform) = $3)
          )

        UNION ALL

        SELECT CASE
                 WHEN h.end_reason IN ('leave', 'timeout') AND h.deserter_nickname = p.nickname THEN 0
                 WHEN p.is_winner THEN CASE WHEN h.is_ranked THEN 20 ELSE 10 END
                 ELSE CASE WHEN h.is_ranked THEN 6 ELSE 3 END
               END AS gold_delta
        FROM tc_mighty_match_history h
        JOIN tc_mighty_match_players p ON p.match_id = h.id
        WHERE h.created_at >= $1 AND h.created_at < $2
          AND p.is_bot = FALSE
          AND EXISTS (
            SELECT 1 FROM tc_users u
            WHERE u.nickname = p.nickname
              AND ($3 = '' OR LOWER(u.device_platform) = $3)
          )

        UNION ALL

        SELECT 50 AS gold_delta
        FROM tc_ad_rewards ar
        JOIN tc_users u ON u.nickname = ar.nickname
        WHERE ar.claimed_at >= $1 AND ar.claimed_at < $2
          AND ($3 = '' OR LOWER(u.device_platform) = $3)

        UNION ALL

        SELECT -COALESCE(si.price, 0) AS gold_delta
        FROM tc_user_items ui
        LEFT JOIN tc_shop_items si ON si.item_key = ui.item_key
        JOIN tc_users u ON u.nickname = ui.nickname
        WHERE ui.source = 'shop'
          AND ui.acquired_at >= $1 AND ui.acquired_at < $2
          AND ($3 = '' OR LOWER(u.device_platform) = $3)

        UNION ALL

        SELECT gh.gold_delta
        FROM tc_gold_history gh
        WHERE gh.created_at >= $1 AND gh.created_at < $2
          AND EXISTS (
            SELECT 1 FROM tc_users u
            WHERE u.nickname = gh.nickname
              AND ($3 = '' OR LOWER(u.device_platform) = $3)
          )
      )
      SELECT
        COALESCE(SUM(CASE WHEN gold_delta > 0 THEN gold_delta ELSE 0 END), 0) AS earned,
        COALESCE(SUM(CASE WHEN gold_delta < 0 THEN -gold_delta ELSE 0 END), 0) AS spent,
        COALESCE(SUM(gold_delta), 0) AS net
      FROM gold_events
    `, [from, to, platform]);

    const signupSummary = await client.query(`
      SELECT
        COUNT(*) AS total_signups,
        COUNT(*) FILTER (WHERE LOWER(device_platform) = 'ios') AS ios_signups,
        COUNT(*) FILTER (WHERE LOWER(device_platform) = 'android') AS android_signups
      FROM tc_users
      WHERE created_at >= $1 AND created_at < $2
        AND is_deleted IS NOT TRUE
        AND ($3 = '' OR LOWER(device_platform) = $3)
    `, [from, to, platform]);

    // ---- IAP payment stats (production only; price estimated, store-set) ----
    const iapPaidRows = await client.query(`
      SELECT platform, product_id,
             ${kstBucketExpr('verified_at')} AS bucket_time,
             COUNT(*) AS cnt
      FROM tc_iap_receipts
      WHERE environment = 'production'
        AND verified_at >= $1 AND verified_at < $2
        AND ($3 = '' OR LOWER(platform) = $3)
      GROUP BY 1, 2, 3
    `, [from, to, platform]);
    const iapRefundRows = await client.query(`
      SELECT platform, product_id,
             ${kstBucketExpr('refunded_at')} AS bucket_time,
             COUNT(*) AS cnt
      FROM tc_iap_receipts
      WHERE environment = 'production'
        AND refunded_at IS NOT NULL
        AND refunded_at >= $1 AND refunded_at < $2
        AND ($3 = '' OR LOWER(platform) = $3)
      GROUP BY 1, 2, 3
    `, [from, to, platform]);

    const krwOf = (pid) => GOLD_PRODUCT_KRW[pid] || 0;
    const blankPlat = () => ({ count: 0, gross: 0, refundCount: 0, refundAmount: 0 });
    const byPlatform = { ios: blankPlat(), android: blankPlat() };
    const seriesMap = new Map(); // bucketISO -> {paidCount,gross,refundCount,refundAmount}
    const seriesRow = (k) => {
      if (!seriesMap.has(k)) seriesMap.set(k, { bucket_time: k, paidCount: 0, gross: 0, refundCount: 0, refundAmount: 0 });
      return seriesMap.get(k);
    };
    for (const r of iapPaidRows.rows) {
      const plat = String(r.platform || '').toLowerCase() === 'ios' ? 'ios' : 'android';
      const c = parseInt(r.cnt, 10) || 0;
      const amt = krwOf(r.product_id) * c;
      byPlatform[plat].count += c;
      byPlatform[plat].gross += amt;
      const sr = seriesRow(new Date(r.bucket_time).toISOString());
      sr.paidCount += c; sr.gross += amt;
    }
    for (const r of iapRefundRows.rows) {
      const plat = String(r.platform || '').toLowerCase() === 'ios' ? 'ios' : 'android';
      const c = parseInt(r.cnt, 10) || 0;
      const amt = krwOf(r.product_id) * c;
      byPlatform[plat].refundCount += c;
      byPlatform[plat].refundAmount += amt;
      const sr = seriesRow(new Date(r.bucket_time).toISOString());
      sr.refundCount += c; sr.refundAmount += amt;
    }
    const settleOf = (p, plat) => Math.round((p.gross - p.refundAmount) * (1 - platformFeeRate(plat)));
    for (const plat of ['ios', 'android']) {
      const p = byPlatform[plat];
      p.feeRate = platformFeeRate(plat);
      p.net = p.gross - p.refundAmount;
      p.fee = Math.round(p.net * p.feeRate);
      p.settlement = settleOf(p, plat);
    }
    const iapTotal = {
      count: byPlatform.ios.count + byPlatform.android.count,
      gross: byPlatform.ios.gross + byPlatform.android.gross,
      refundCount: byPlatform.ios.refundCount + byPlatform.android.refundCount,
      refundAmount: byPlatform.ios.refundAmount + byPlatform.android.refundAmount,
      net: byPlatform.ios.net + byPlatform.android.net,
      fee: byPlatform.ios.fee + byPlatform.android.fee,
      settlement: byPlatform.ios.settlement + byPlatform.android.settlement,
    };
    const iapSeries = [...seriesMap.values()]
      .map((s) => ({ ...s, net: s.gross - s.refundAmount }))
      .sort((a, b) => new Date(a.bucket_time) - new Date(b.bucket_time));

    // ---- Attendance daily series ------------------------------------------
    // Daily check-ins (distinct users) + 7-day completions + gold granted.
    const attendanceSeries = await client.query(`
      SELECT ${kstBucketExpr('created_at')} AS bucket_time,
             COUNT(DISTINCT nickname) AS unique_claims,
             COUNT(*) FILTER (WHERE description = 'day_7') AS finales,
             COALESCE(SUM(gold_delta), 0) AS gold
      FROM tc_gold_history
      WHERE source = 'attendance'
        AND created_at >= $1 AND created_at < $2
      GROUP BY 1
      ORDER BY 1
    `, [from, to]);
    const attendanceSummary = await client.query(`
      SELECT COUNT(DISTINCT nickname) AS unique_claims,
             COUNT(*) AS total_claims,
             COUNT(*) FILTER (WHERE description = 'day_7') AS finales,
             COALESCE(SUM(gold_delta), 0) AS gold
      FROM tc_gold_history
      WHERE source = 'attendance'
        AND created_at >= $1 AND created_at < $2
    `, [from, to]);

    const summaryRow = gameSummary.rows[0] || {};
    const goldRow = goldSummary.rows[0] || {};
    const shopRow = shopSummary.rows[0] || {};
    const signupRow = signupSummary.rows[0] || {};
    return {
      iapSummary: { byPlatform, total: iapTotal, feeRates: { ios: APPLE_FEE_RATE, android: GOOGLE_FEE_RATE } },
      iapSeries,
      success: true,
      summary: {
        totalGames: (parseInt(summaryRow.tichu_games || 0, 10) + parseInt(summaryRow.skull_games || 0, 10) + parseInt(summaryRow.ll_games || 0, 10) + parseInt(summaryRow.mighty_games || 0, 10)),
        tichuGames: parseInt(summaryRow.tichu_games || 0, 10),
        skullGames: parseInt(summaryRow.skull_games || 0, 10),
        llGames: parseInt(summaryRow.ll_games || 0, 10),
        mightyGames: parseInt(summaryRow.mighty_games || 0, 10),
        rankedGames: parseInt(summaryRow.ranked_games || 0, 10),
        totalSignups: parseInt(signupRow.total_signups || 0, 10),
        iosSignups: parseInt(signupRow.ios_signups || 0, 10),
        androidSignups: parseInt(signupRow.android_signups || 0, 10),
        goldEarned: parseInt(goldRow.earned || 0, 10),
        goldSpent: parseInt(goldRow.spent || 0, 10),
        goldNet: parseInt(goldRow.net || 0, 10),
        shopPurchases: parseInt(shopRow.total_purchases || 0, 10),
        shopBuyers: parseInt(shopRow.unique_buyers || 0, 10),
        shopGoldSpent: parseInt(shopRow.total_gold_spent || 0, 10),
        shopUniqueItems: parseInt(shopRow.unique_items_sold || 0, 10),
      },
      gameSeries: gameSeries.rows,
      signupSeries: signupSeries.rows,
      goldSeries: goldSeries.rows,
      shopSalesSeries: shopSalesSeries.rows,
      topShopItems: topShopItems.rows,
      attendanceSeries: attendanceSeries.rows,
      attendanceSummary: attendanceSummary.rows[0] || {},
      range: { from, to, bucket: groupUnit, platform },
    };
  } catch (err) {
    console.error('Get detailed admin stats error:', err);
    return {
      success: false,
      messageKey: 'db_stats_failed',
      summary: {},
      gameSeries: [],
      signupSeries: [],
      goldSeries: [],
      shopSalesSeries: [],
      topShopItems: [],
      attendanceSeries: [],
      attendanceSummary: {},
      iapSummary: {
        byPlatform: {
          ios: { count: 0, gross: 0, refundCount: 0, refundAmount: 0, net: 0, fee: 0, settlement: 0, feeRate: APPLE_FEE_RATE },
          android: { count: 0, gross: 0, refundCount: 0, refundAmount: 0, net: 0, fee: 0, settlement: 0, feeRate: GOOGLE_FEE_RATE },
        },
        total: { count: 0, gross: 0, refundCount: 0, refundAmount: 0, net: 0, fee: 0, settlement: 0 },
        feeRates: { ios: APPLE_FEE_RATE, android: GOOGLE_FEE_RATE },
      },
      iapSeries: [],
      range: { from, to, bucket: groupUnit, platform },
    };
  } finally {
    client.release();
  }
}

// Verify admin credentials
async function verifyAdmin(username, password) {
  const client = await pool.connect();
  try {
    const result = await client.query(
      'SELECT username, password FROM admin_accounts WHERE username = $1',
      [username]
    );
    if (result.rows.length === 0) return null;
    const admin = result.rows[0];
    const match = await bcrypt.compare(password, admin.password);
    if (!match) return null;
    return { username: admin.username };
  } catch (err) {
    console.error('Verify admin error:', err);
    return null;
  } finally {
    client.release();
  }
}

async function isUserAdmin(nickname) {
  const client = await pool.connect();
  try {
    const result = await client.query(
      'SELECT is_admin FROM tc_users WHERE nickname = $1',
      [nickname]
    );
    if (result.rows.length === 0) return false;
    return result.rows[0].is_admin === true;
  } catch (err) {
    console.error('Is user admin error:', err);
    return false;
  } finally {
    client.release();
  }
}

// Get rankings (top players by rating)
async function getRankings(limit = 50) {
  const client = await pool.connect();
  try {
    const result = await client.query(
      `
      SELECT
        nickname,
        rating,
        wins,
        losses,
        total_games,
        CASE
          WHEN total_games > 0 THEN ROUND((wins::FLOAT / total_games) * 100)
          ELSE 0
        END AS win_rate
      FROM tc_users
      WHERE is_deleted IS NOT TRUE
      ORDER BY rating DESC, wins DESC, total_games DESC, nickname ASC
      LIMIT $1
      `,
      [limit]
    );
    return { success: true, rankings: result.rows };
  } catch (err) {
    console.error('Get rankings error:', err);
    return { success: false, messageKey: 'db_rankings_failed' };
  } finally {
    client.release();
  }
}

// ===== Admin shop management =====

// Get all shop items (admin, no filter)
async function getAllShopItemsAdmin() {
  const client = await pool.connect();
  try {
    const result = await client.query(
      `SELECT * FROM tc_shop_items ORDER BY category ASC, id ASC`
    );
    return result.rows;
  } catch (err) {
    console.error('Get all shop items admin error:', err);
    return [];
  } finally {
    client.release();
  }
}

// Add new shop item. `data.visual` (object or null) populates metadata.visual
// so the admin form can attach visual config without touching other metadata
// keys; pass `data.metadata` to set arbitrary metadata directly.
async function addShopItem(data) {
  const client = await pool.connect();
  try {
    let metaObj = null;
    if (data.metadata && typeof data.metadata === 'object') {
      metaObj = { ...data.metadata };
    }
    if (data.visual !== undefined && data.visual !== null) {
      metaObj = { ...(metaObj || {}), visual: data.visual };
    }
    const metadata = metaObj ? JSON.stringify(metaObj) : null;
    const result = await client.query(
      `INSERT INTO tc_shop_items
        (item_key, name, name_ko, name_en, name_de,
         description_ko, description_en, description_de,
         category, price, is_permanent, duration_days, is_purchasable, is_season,
         effect_type, effect_value, sale_start, sale_end, new_until, metadata)
       VALUES ($1, $2, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19::jsonb)
       RETURNING *`,
      [
        data.item_key, data.name_ko || '', data.name_en || '', data.name_de || '',
        data.description_ko || '', data.description_en || '', data.description_de || '',
        data.category, data.price || 0,
        data.is_permanent !== false, data.duration_days || null,
        data.is_purchasable !== false, data.is_season || false,
        data.effect_type || null, data.effect_value || null,
        data.sale_start || null, data.sale_end || null, data.new_until || null,
        metadata,
      ]
    );
    return { success: true, item: result.rows[0] };
  } catch (err) {
    console.error('Add shop item error:', err);
    if (err.code === '23505') {
      return { success: false, messageKey: 'db_item_key_exists' };
    }
    return { success: false, messageKey: 'db_item_add_failed' };
  } finally {
    client.release();
  }
}

// Update shop item. When `data.visual` is supplied, only the metadata.visual
// subkey is rewritten via jsonb_set so unrelated metadata (e.g. theme's
// includesCardSkin flag) survives. Pass `data.visual = null` to clear it.
async function updateShopItem(id, data) {
  const client = await pool.connect();
  try {
    // Only the keys the caller actually sent are written. What an item IS —
    // its category, the effect it grants, whether it is permanent or seasonal —
    // is edited rarely and behind a lock in the console, so an edit that never
    // mentions those fields must leave them alone. The old version defaulted
    // every missing field (category fell back to 'banner', effect_type to
    // NULL), which silently re-filed the profile passes as banners and stripped
    // the effect that gates them.
    const sets = [];
    const params = [id];
    const put = (col, value) => {
      params.push(value);
      sets.push(`${col} = $${params.length}`);
    };
    const has = (key) => Object.prototype.hasOwnProperty.call(data, key)
      && data[key] !== undefined;

    if (has('name_ko')) {
      put('name', data.name_ko || '');
      put('name_ko', data.name_ko || '');
    }
    if (has('name_en')) put('name_en', data.name_en || '');
    if (has('name_de')) put('name_de', data.name_de || '');
    if (has('description_ko')) put('description_ko', data.description_ko || '');
    if (has('description_en')) put('description_en', data.description_en || '');
    if (has('description_de')) put('description_de', data.description_de || '');
    if (has('price')) put('price', data.price || 0);
    if (has('is_purchasable')) put('is_purchasable', data.is_purchasable !== false);
    if (has('sale_start')) put('sale_start', data.sale_start || null);
    if (has('sale_end')) put('sale_end', data.sale_end || null);
    if (has('new_until')) put('new_until', data.new_until || null);
    // Structural — see above.
    if (has('category')) put('category', data.category);
    if (has('effect_type')) put('effect_type', data.effect_type || null);
    if (has('effect_value')) put('effect_value', data.effect_value ?? null);
    if (has('is_permanent')) put('is_permanent', data.is_permanent !== false);
    if (has('duration_days')) put('duration_days', data.duration_days || null);
    if (has('is_season')) put('is_season', data.is_season || false);

    if (Object.prototype.hasOwnProperty.call(data, 'visual')) {
      if (data.visual === null) {
        sets.push(`metadata = COALESCE(metadata, '{}'::jsonb) #- '{visual}'`);
      } else {
        params.push(JSON.stringify(data.visual));
        sets.push(
          `metadata = jsonb_set(COALESCE(metadata, '{}'::jsonb), '{visual}', $${params.length}::jsonb, true)`,
        );
      }
    }
    if (sets.length === 0) {
      const current = await client.query('SELECT * FROM tc_shop_items WHERE id = $1', [id]);
      if (current.rows.length === 0) return { success: false, messageKey: 'db_item_not_found' };
      return { success: true, item: current.rows[0] };
    }

    const result = await client.query(
      `UPDATE tc_shop_items SET ${sets.join(', ')} WHERE id = $1 RETURNING *`,
      params,
    );
    if (result.rows.length === 0) {
      return { success: false, messageKey: 'db_item_not_found' };
    }
    return { success: true, item: result.rows[0] };
  } catch (err) {
    console.error('Update shop item error:', err);
    return { success: false, messageKey: 'db_item_update_failed' };
  } finally {
    client.release();
  }
}

// Delete shop item (+ cascade delete user items)
async function deleteShopItem(id) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    // Get item_key first
    const itemRes = await client.query('SELECT item_key FROM tc_shop_items WHERE id = $1', [id]);
    if (itemRes.rows.length === 0) {
      await client.query('ROLLBACK');
      return { success: false, messageKey: 'db_item_not_found' };
    }
    const itemKey = itemRes.rows[0].item_key;
    // Delete related user items
    await client.query('DELETE FROM tc_user_items WHERE item_key = $1', [itemKey]);
    // Delete the shop item
    await client.query('DELETE FROM tc_shop_items WHERE id = $1', [id]);
    await client.query('COMMIT');
    return { success: true };
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Delete shop item error:', err);
    return { success: false, messageKey: 'db_item_delete_failed' };
  } finally {
    client.release();
  }
}

// Get single shop item by ID
async function getShopItemById(id) {
  const client = await pool.connect();
  try {
    const result = await client.query('SELECT * FROM tc_shop_items WHERE id = $1', [id]);
    return result.rows[0] || null;
  } catch (err) {
    console.error('Get shop item by id error:', err);
    return null;
  } finally {
    client.release();
  }
}

// Social login: find user by provider + provider_uid
async function loginSocial(provider, providerUid) {
  const client = await pool.connect();
  try {
    const result = await client.query(
      'SELECT id, nickname, is_admin, is_deleted, push_enabled, push_friend_invite, push_attendance, push_admin_inquiry, push_admin_report, push_admin_payment, marketing_push_enabled, marketing_asked_at, marketing_consent_at, marketing_confirmed_at FROM tc_users WHERE auth_provider = $1 AND provider_uid = $2',
      [provider, providerUid]
    );
    if (result.rows.length === 0) {
      return { found: false };
    }
    const user = result.rows[0];
    if (user.is_deleted) {
      return { found: false, errorKey: 'db_account_deleted' };
    }
    await client.query(
      'UPDATE tc_users SET last_login = CURRENT_TIMESTAMP WHERE id = $1',
      [user.id]
    );
    return {
      found: true,
      userId: user.id,
      nickname: user.nickname,
      isAdmin: user.is_admin === true,
      pushEnabled: user.push_enabled !== false,
      pushFriendInvite: user.push_friend_invite !== false,
      pushAttendance: user.push_attendance !== false,
      pushAdminInquiry: user.push_admin_inquiry !== false,
      pushAdminReport: user.push_admin_report !== false,
      pushAdminPayment: user.push_admin_payment !== false,
      marketingPushEnabled: user.marketing_push_enabled === true,
      // Never asked is not the same as declined, and only the first of those
      // should raise the consent popup.
      marketingAsked: user.marketing_asked_at != null,
      // 정보통신망법 §50 ⑧: confirm the subscription every two years.
      marketingConfirmDue:
        user.marketing_push_enabled === true
        && _marketingConfirmOverdue(
          user.marketing_confirmed_at || user.marketing_consent_at),
      marketingConsentAt: user.marketing_consent_at || null,
    };
  } catch (err) {
    console.error('Social login error:', err);
    return { found: false, errorKey: 'db_social_login_error' };
  } finally {
    client.release();
  }
}

// Social register: create user with provider info
async function registerSocial(provider, providerUid, email, nickname) {
  if (!nickname || nickname.trim().length < 1) {
    return { success: false, messageKey: 'db_nickname_required' };
  }
  const trimmedNickname = nickname.trim();
  if (trimmedNickname.length < 2 || trimmedNickname.length > 10) {
    return { success: false, messageKey: 'db_nickname_length' };
  }
  if (/\s/.test(trimmedNickname)) {
    return { success: false, messageKey: 'db_nickname_no_space' };
  }

  const client = await pool.connect();
  try {
    // Check nickname duplicate
    const nicknameCheck = await client.query(
      'SELECT id FROM tc_users WHERE nickname = $1',
      [trimmedNickname]
    );
    if (nicknameCheck.rows.length > 0) {
      return { success: false, messageKey: 'db_nickname_taken' };
    }

    // Check provider_uid duplicate
    const providerCheck = await client.query(
      'SELECT id FROM tc_users WHERE auth_provider = $1 AND provider_uid = $2',
      [provider, providerUid]
    );
    if (providerCheck.rows.length > 0) {
      return { success: false, messageKey: 'db_social_account_exists' };
    }

    // Auto-generate username
    const username = `${provider}_${providerUid.substring(0, 20)}`;

    const result = await client.query(
      `INSERT INTO tc_users (username, password_hash, nickname, auth_provider, provider_uid, email)
       VALUES ($1, NULL, $2, $3, $4, $5) RETURNING id`,
      [username, trimmedNickname, provider, providerUid, email || null]
    );

    return { success: true, userId: result.rows[0].id, nickname: trimmedNickname };
  } catch (err) {
    console.error('Social register error:', err);
    return { success: false, messageKey: 'db_social_register_error' };
  } finally {
    client.release();
  }
}

// Link social account to existing user
async function linkSocial(userId, provider, providerUid, email) {
  const client = await pool.connect();
  try {
    // Check if this social account is already linked to another user
    const existing = await client.query(
      'SELECT id FROM tc_users WHERE auth_provider = $1 AND provider_uid = $2',
      [provider, providerUid]
    );
    if (existing.rows.length > 0 && existing.rows[0].id !== userId) {
      return { success: false, messageKey: 'db_social_account_taken' };
    }

    await client.query(
      'UPDATE tc_users SET auth_provider = $1, provider_uid = $2, email = $3 WHERE id = $4',
      [provider, providerUid, email || null, userId]
    );
    return { success: true, provider };
  } catch (err) {
    console.error('Link social error:', err);
    return { success: false, messageKey: 'db_social_link_error' };
  } finally {
    client.release();
  }
}

// Unlink social account (only if password exists)
async function unlinkSocial(userId) {
  const client = await pool.connect();
  try {
    const userRes = await client.query(
      'SELECT password_hash FROM tc_users WHERE id = $1',
      [userId]
    );
    if (userRes.rows.length === 0) {
      return { success: false, messageKey: 'db_user_not_found' };
    }
    if (!userRes.rows[0].password_hash) {
      return { success: false, messageKey: 'db_password_not_set' };
    }

    await client.query(
      "UPDATE tc_users SET auth_provider = 'local', provider_uid = NULL WHERE id = $1",
      [userId]
    );
    return { success: true };
  } catch (err) {
    console.error('Unlink social error:', err);
    return { success: false, messageKey: 'db_social_unlink_error' };
  } finally {
    client.release();
  }
}

// Get linked social info for a user
async function getLinkedSocial(userId) {
  const client = await pool.connect();
  try {
    const result = await client.query(
      'SELECT auth_provider, email FROM tc_users WHERE id = $1',
      [userId]
    );
    if (result.rows.length === 0) {
      return { provider: 'local', email: null };
    }
    return { provider: result.rows[0].auth_provider, email: result.rows[0].email };
  } catch (err) {
    console.error('Get linked social error:', err);
    return { provider: 'local', email: null };
  } finally {
    client.release();
  }
}

// Update device info on login
/// deviceInfo.tzOffsetMinutes 를 저장할 수 있는 값으로. 못 믿을 값이면 null.
function parseTzOffsetMinutes(raw) {
  if (raw === null || raw === undefined || raw === '') return null;
  const n = Number(raw);
  if (!Number.isFinite(n) || Math.abs(n) > 14 * 60) return null;
  return Math.trunc(n);
}

async function updateDeviceInfo(nickname, deviceInfo) {
  const client = await pool.connect();
  try {
    if (deviceInfo.fcmToken) {
      // A token identifies one physical device's current install, not an
      // account. Logging out and into a different account on the same phone
      // reuses the same token, so whoever held it before must be cleared here
      // — otherwise a broadcast still matches their row too and the one
      // device gets the same push twice.
      await client.query(
        `UPDATE tc_users SET fcm_token = NULL, fcm_token_invalid_at = NULL
         WHERE fcm_token = $1 AND nickname <> $2`,
        [deviceInfo.fcmToken, nickname]
      );
    }
    await client.query(
      `UPDATE tc_users
       SET fcm_token = COALESCE($2, fcm_token),
           -- A token arriving from a live app clears the death mark. This is
           -- the reinstall path: same account, new install, new token. Only
           -- when a token is actually supplied — a login that sends none must
           -- not resurrect a device that is gone.
           fcm_token_invalid_at = CASE WHEN $2::text IS NULL
                                       THEN fcm_token_invalid_at ELSE NULL END,
           device_platform = COALESCE($3, device_platform),
           device_model = COALESCE($4, device_model),
           os_version = COALESCE($5, os_version),
           app_version = COALESCE($6, app_version),
           last_ip = COALESCE($7, last_ip),
           locale = COALESCE($8, locale),
           tz_offset_minutes = COALESCE($9, tz_offset_minutes)
       WHERE nickname = $1`,
      [
        nickname,
        deviceInfo.fcmToken || null,
        deviceInfo.devicePlatform || null,
        deviceInfo.deviceModel || null,
        deviceInfo.osVersion || null,
        deviceInfo.appVersion || null,
        deviceInfo.lastIp || null,
        deviceInfo.locale || null,
        // 클라이언트는 deviceInfo 를 통째로 문자열 맵으로 보내므로 숫자로
        // 되돌린다. 0 은 유효한 값(UTC)이라 `||` 로 걸러지면 안 되고,
        // 실재하지 않는 값은 버린다 — 실제 오프셋은 -12:00 ~ +14:00 이다.
        parseTzOffsetMinutes(deviceInfo.tzOffsetMinutes),
      ]
    );
  } catch (err) {
    console.error('Update device info error:', err);
  } finally {
    client.release();
  }
}

/// 출석 알림 켬/끔.
///
/// 이벤트·혜택 알림(마케팅 동의)과 따로 두는 이유는, 매일 오는 게 부담스러운
/// 사람이 그것 하나 때문에 마케팅 동의 전체를 철회하지 않게 하기 위해서다.
/// 동의 철회는 법적 기록이라 되돌리려면 다시 물어봐야 한다 — 알림 하나가
/// 성가시다는 이유로 치르기에는 큰 값이다.
async function setAttendancePush(nickname, enabled) {
  try {
    await pool.query(
      `UPDATE tc_users SET push_attendance = $2 WHERE nickname = $1`,
      [nickname, enabled === true],
    );
    return { success: true, enabled: enabled === true };
  } catch (err) {
    console.error('Set attendance push error:', err.message);
    return { success: false, messageKey: 'db_push_setting_save_failed' };
  }
}

async function setPushEnabled(nickname, enabled) {
  const client = await pool.connect();
  try {
    await client.query(
      `UPDATE tc_users SET push_enabled = $2 WHERE nickname = $1`,
      [nickname, enabled === true]
    );
    return { success: true };
  } catch (err) {
    console.error('Set push enabled error:', err);
    return { success: false, messageKey: 'db_push_setting_save_failed' };
  } finally {
    client.release();
  }
}

async function setPushFriendInvite(nickname, enabled) {
  const client = await pool.connect();
  try {
    await client.query(
      `UPDATE tc_users SET push_friend_invite = $2 WHERE nickname = $1`,
      [nickname, enabled === true]
    );
    return { success: true };
  } catch (err) {
    console.error('Set push friend invite error:', err);
    return { success: false, messageKey: 'db_push_setting_save_failed' };
  } finally {
    client.release();
  }
}

async function setUserAdmin(nickname, isAdmin) {
  const client = await pool.connect();
  try {
    const result = await client.query(
      `UPDATE tc_users
       SET is_admin = $2
       WHERE nickname = $1
       RETURNING nickname, is_admin, push_admin_inquiry, push_admin_report, push_admin_payment`,
      [nickname, isAdmin]
    );
    if (result.rows.length === 0) {
      return { success: false, messageKey: 'db_user_not_found' };
    }
    return { success: true, user: result.rows[0] };
  } catch (err) {
    console.error('Set user admin error:', err);
    return { success: false, messageKey: 'db_admin_set_failed' };
  } finally {
    client.release();
  }
}

async function setAdminAlertSettings(nickname, inquiryEnabled, reportEnabled, paymentEnabled) {
  const client = await pool.connect();
  try {
    const result = await client.query(
      `UPDATE tc_users
       SET push_admin_inquiry = $2,
           push_admin_report = $3,
           push_admin_payment = $4
       WHERE nickname = $1
       RETURNING push_admin_inquiry, push_admin_report, push_admin_payment`,
      [nickname, inquiryEnabled, reportEnabled, paymentEnabled]
    );
    if (result.rows.length === 0) {
      return { success: false, messageKey: 'db_user_not_found' };
    }
    return {
      success: true,
      settings: {
        pushAdminInquiry: result.rows[0].push_admin_inquiry !== false,
        pushAdminReport: result.rows[0].push_admin_report !== false,
        pushAdminPayment: result.rows[0].push_admin_payment !== false,
      },
    };
  } catch (err) {
    console.error('Set admin alert settings error:', err);
    return { success: false, messageKey: 'db_admin_notify_save_failed' };
  } finally {
    client.release();
  }
}

async function getAdminPushRecipients(kind) {
  const client = await pool.connect();
  try {
    const column = { report: 'push_admin_report', payment: 'push_admin_payment' }[kind]
      || 'push_admin_inquiry';
    const result = await client.query(
      `SELECT nickname, fcm_token
       FROM tc_users
       WHERE is_admin = TRUE
         AND push_enabled = TRUE
         AND ${column} = TRUE
         AND fcm_token IS NOT NULL
         AND fcm_token != ''`
    );
    return result.rows;
  } catch (err) {
    console.error('Get admin push recipients error:', err);
    return [];
  } finally {
    client.release();
  }
}

// Admin: adjust user gold (positive = add, negative = deduct)
// ═══════════════════════════════════════════════════════════
//  COUPONS
// ═══════════════════════════════════════════════════════════

/**
 * A JS Date as UTC text for a `timestamp without time zone` column.
 *
 * node-pg serializes a Date using the *process* timezone, so on a KST host a
 * value nine hours off is what lands in the column. Every timestamp this file
 * writes by hand goes through here or the same `.replace` pair inline.
 */
function toUtcTimestampText(value) {
  if (!value) return null;
  const d = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(d.getTime())) return null;
  return d.toISOString().replace('T', ' ').replace('Z', '');
}

/** Codes are typed by hand off a blog post: case and spacing must not matter. */
function normalizeCouponCode(raw) {
  return String(raw || '').trim().toUpperCase().replace(/\s+/g, '');
}

/**
 * Redeem a coupon for `nickname`.
 *
 * Everything that decides the outcome happens inside one transaction, and the
 * coupon row is locked before the cap is read. Without the lock, two players
 * redeeming the last seat of a 100-person coupon both read 99 and both write
 * 100 — the cap is exactly the kind of number that only breaks under the load
 * a giveaway creates.
 *
 * The per-account rule is left to the UNIQUE index rather than a SELECT: a
 * check-then-insert has the same race one layer up, and a double-tap is the
 * common case, not the exotic one.
 */
async function redeemCoupon(nickname, rawCode) {
  const code = normalizeCouponCode(rawCode);
  if (!code) return { success: false, messageKey: 'coupon_not_found' };

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const couponRes = await client.query(
      'SELECT * FROM tc_coupons WHERE code = $1 FOR UPDATE',
      [code],
    );
    const coupon = couponRes.rows[0];
    if (!coupon) {
      await client.query('ROLLBACK');
      return { success: false, messageKey: 'coupon_not_found' };
    }
    if (!coupon.is_active) {
      await client.query('ROLLBACK');
      return { success: false, messageKey: 'coupon_inactive' };
    }
    // Compared in SQL, against the same clock the column is written from.
    // These are `timestamp without time zone` holding UTC, and reading one
    // into a JS Date makes it a local time — so a coupon that expired an hour
    // ago looked eight hours away from expiring on a KST host. Same trap the
    // match-history lower bound fell into; see the `since` text conversions.
    const expiredRes = await client.query(
      `SELECT (expires_at IS NOT NULL
               AND expires_at < (NOW() AT TIME ZONE 'UTC')) AS expired
         FROM tc_coupons WHERE code = $1`,
      [code],
    );
    if (expiredRes.rows[0]?.expired) {
      await client.query('ROLLBACK');
      return { success: false, messageKey: 'coupon_expired' };
    }
    if (coupon.max_redemptions != null
        && coupon.redeemed_count >= coupon.max_redemptions) {
      await client.query('ROLLBACK');
      return { success: false, messageKey: 'coupon_exhausted' };
    }

    const user = await client.query(
      'SELECT 1 FROM tc_users WHERE nickname = $1', [nickname],
    );
    if (user.rowCount === 0) {
      await client.query('ROLLBACK');
      return { success: false, messageKey: 'db_user_not_found' };
    }

    // Claim the seat first. If this account already has one the unique index
    // raises 23505 and nothing below runs — no double reward.
    let summary;
    try {
      if (coupon.reward_type === 'gold') {
        summary = `gold:${coupon.reward_gold || 0}`;
      } else {
        summary = `item:${coupon.reward_item_key}`;
      }
      await client.query(
        `INSERT INTO tc_coupon_redemptions (code, nickname, reward_summary)
         VALUES ($1, $2, $3)`,
        [code, nickname, summary],
      );
    } catch (e) {
      await client.query('ROLLBACK');
      if (e.code === '23505') {
        return { success: false, messageKey: 'coupon_already_used' };
      }
      throw e;
    }

    await client.query(
      'UPDATE tc_coupons SET redeemed_count = redeemed_count + 1 WHERE code = $1',
      [code],
    );

    let reward;
    if (coupon.reward_type === 'gold') {
      const amount = coupon.reward_gold || 0;
      const updated = await client.query(
        'UPDATE tc_users SET gold = gold + $2 WHERE nickname = $1 RETURNING gold',
        [nickname, amount],
      );
      await client.query(
        `INSERT INTO tc_gold_history (nickname, gold_delta, source, title, description)
         VALUES ($1, $2, 'coupon', $3, $4)`,
        [nickname, amount, 'coupon', code],
      );
      reward = { type: 'gold', gold: amount, newGold: updated.rows[0].gold };
    } else {
      const itemRes = await client.query(
        'SELECT item_key, category, is_permanent, duration_days FROM tc_shop_items WHERE item_key = $1',
        [coupon.reward_item_key],
      );
      const item = itemRes.rows[0];
      if (!item) {
        await client.query('ROLLBACK');
        return { success: false, messageKey: 'db_item_not_found' };
      }
      // reward_days overrides the shop's own duration — the same item can be
      // given for a week in one campaign and a month in another.
      const days = coupon.reward_days != null
        ? coupon.reward_days
        : item.duration_days;
      // Shared with the campaign payout: same ownership rules the shop uses,
      // so a permanent item nobody can own twice does not stack a second row.
      const granted = await grantItemToUser(
        client, nickname, item, days, 'coupon',
      );
      reward = {
        type: 'item',
        itemKey: granted.itemKey,
        expiresAt: granted.expiresAt
          ? new Date(granted.expiresAt).toISOString()
          : null,
        alreadyOwned: granted.alreadyOwned === true,
      };
    }

    await client.query('COMMIT');
    return { success: true, code, reward };
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Redeem coupon error:', err);
    return { success: false, messageKey: 'coupon_failed' };
  } finally {
    client.release();
  }
}

/** Admin: create or overwrite a coupon. */
/// One coupon by code, or null. Used to check a code exists before a notice
/// starts advertising it.
async function getCouponByCode(code) {
  const r = await pool.query('SELECT * FROM tc_coupons WHERE code = $1',
    [normalizeCouponCode(code)]);
  return r.rows[0] || null;
}

async function upsertCoupon(data, adminActor = 'admin') {
  const code = normalizeCouponCode(data.code);
  if (!code) return { success: false, message: '코드를 입력하세요' };
  const rewardType = data.rewardType === 'item' ? 'item' : 'gold';
  if (rewardType === 'gold' && !(Number(data.rewardGold) > 0)) {
    return { success: false, message: '골드는 1 이상이어야 합니다' };
  }
  if (rewardType === 'item' && !data.rewardItemKey) {
    return { success: false, message: '아이템을 선택하세요' };
  }
  try {
    await pool.query(
      `INSERT INTO tc_coupons
         (code, reward_type, reward_gold, reward_item_key, reward_days,
          max_redemptions, expires_at, is_active, memo, created_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
       ON CONFLICT (code) DO UPDATE SET
         reward_type = EXCLUDED.reward_type,
         reward_gold = EXCLUDED.reward_gold,
         reward_item_key = EXCLUDED.reward_item_key,
         reward_days = EXCLUDED.reward_days,
         max_redemptions = EXCLUDED.max_redemptions,
         expires_at = EXCLUDED.expires_at,
         is_active = EXCLUDED.is_active,
         memo = EXCLUDED.memo`,
      [
        code,
        rewardType,
        rewardType === 'gold' ? Number(data.rewardGold) : null,
        rewardType === 'item' ? data.rewardItemKey : null,
        data.rewardDays ? Number(data.rewardDays) : null,
        data.maxRedemptions ? Number(data.maxRedemptions) : null,
        toUtcTimestampText(data.expiresAt),
        data.isActive !== false,
        data.memo || null,
        adminActor,
      ],
    );
    return { success: true, code };
  } catch (err) {
    console.error('Upsert coupon error:', err);
    return { success: false, message: err.message };
  }
}

async function listCoupons() {
  try {
    const res = await pool.query(
      `SELECT c.*,
              (SELECT COUNT(*) FROM tc_coupon_redemptions r WHERE r.code = c.code)
                AS actual_redeemed
         FROM tc_coupons c
        ORDER BY c.created_at DESC`,
    );
    return res.rows;
  } catch (err) {
    console.error('List coupons error:', err);
    return [];
  }
}

async function getCouponRedemptions(code, limit = 100) {
  try {
    const res = await pool.query(
      `SELECT nickname, reward_summary, redeemed_at
         FROM tc_coupon_redemptions
        WHERE code = $1 ORDER BY redeemed_at DESC LIMIT $2`,
      [normalizeCouponCode(code), limit],
    );
    return res.rows;
  } catch (err) {
    console.error('Coupon redemptions error:', err);
    return [];
  }
}

/// Delete a coupon and the record of who used it.
///
/// Both, in one transaction. tc_coupon_redemptions has no foreign key, so the
/// rows used to outlive the coupon — and codes get reused. `WELCOME2026`
/// recreated after a cleanup would hit UNIQUE (code, nickname) for everyone
/// who redeemed the old one and turn them away with "이미 등록한 쿠폰입니다",
/// on a coupon they have never seen. The admin's redemption list would mix the
/// two runs together as well.
///
/// The audit does not disappear with them: every grant is written to
/// tc_gold_history (source 'coupon') or tc_user_items (source 'coupon'), which
/// is where "what did this account actually receive" is answered.
async function deleteCoupon(code) {
  const normalized = normalizeCouponCode(code);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query('DELETE FROM tc_coupon_redemptions WHERE code = $1',
      [normalized]);
    await client.query('DELETE FROM tc_coupons WHERE code = $1', [normalized]);
    await client.query('COMMIT');
    return { success: true };
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Delete coupon error:', err);
    return { success: false, message: err.message };
  } finally {
    client.release();
  }
}

async function adminAdjustGold(nickname, amount, adminActor = 'admin') {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await client.query(
      `UPDATE tc_users SET gold = GREATEST(0, gold + $2) WHERE nickname = $1 RETURNING gold`,
      [nickname, amount]
    );
    if (result.rows.length === 0) {
      await client.query('ROLLBACK');
      return { success: false, message: 'User not found' };
    }
    await client.query(
      `INSERT INTO tc_gold_history (nickname, gold_delta, source, title, description)
       VALUES ($1, $2, 'admin_adjust', $3, $4)`,
      [
        nickname,
        amount,
        amount >= 0 ? 'admin_grant' : 'admin_deduct',
        adminActor,
      ]
    );
    await client.query('COMMIT');
    return { success: true, newGold: result.rows[0].gold };
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Admin adjust gold error:', err);
    return { success: false, message: err.message };
  } finally {
    client.release();
  }
}

// Admin-only XP adjustment. Routes the recomputed level through
// tc_compute_level so it stays consistent with the tiered curve used by
// every other EXP-granting flow.
async function adminAdjustExp(nickname, amount, adminActor = 'admin') {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await client.query(
      `UPDATE tc_users
         SET exp_total = GREATEST(0, exp_total + $2),
             level = tc_compute_level(GREATEST(0, exp_total + $2))
         WHERE nickname = $1
         RETURNING exp_total, level`,
      [nickname, amount]
    );
    if (result.rows.length === 0) {
      await client.query('ROLLBACK');
      return { success: false, message: 'User not found' };
    }
    await client.query('COMMIT');
    return {
      success: true,
      newExpTotal: result.rows[0].exp_total,
      newLevel: result.rows[0].level,
      adminActor,
    };
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Admin adjust exp error:', err);
    return { success: false, message: err.message };
  } finally {
    client.release();
  }
}

async function getConfig(key) {
  const client = await pool.connect();
  try {
    const result = await client.query('SELECT value FROM tc_config WHERE key = $1', [key]);
    return result.rows.length > 0 ? result.rows[0].value : null;
  } finally {
    client.release();
  }
}

// Fetch a locale-aware config value (EULA / privacy policy).
// Rule:
//   - ko client → Korean
//   - de client → German
//   - any other known locale (en, fr, ja, ...) → English
//   - locale null/undefined (legacy clients that never sent locale) → Korean
//     (preserves pre-i18n behavior; these are overwhelmingly KR users).
// If the chosen version is empty, falls back through en → ko → legacy key.
async function getLocalizedConfig(baseKey, locale) {
  let primary;
  if (locale === 'ko' || locale === 'de') primary = locale;
  else if (!locale) primary = 'ko';
  else primary = 'en';
  const candidates = [`${baseKey}_${primary}`];
  if (primary !== 'en') candidates.push(`${baseKey}_en`);
  if (primary !== 'ko') candidates.push(`${baseKey}_ko`);
  candidates.push(baseKey);
  for (const key of candidates) {
    const val = await getConfig(key);
    if (val) return val;
  }
  return null;
}

async function updateConfig(key, value) {
  const client = await pool.connect();
  try {
    await client.query(
      `INSERT INTO tc_config (key, value, updated_at) VALUES ($1, $2, NOW())
       ON CONFLICT (key) DO UPDATE SET value = $2, updated_at = NOW()`,
      [key, value]
    );
    return { success: true };
  } catch (err) {
    console.error('Update config error:', err);
    return { success: false, message: err.message };
  } finally {
    client.release();
  }
}

// === DM Functions ===

/**
 * Friend search results, with enough of each account to draw them as the
 * player they are — photo, banner, title, level — instead of a name on a grey
 * circle. One query for all 20 rather than a profile fetch per hit; the
 * per-viewer filtering (privacy pass, reported photos and titles) happens in
 * the caller, which is the only place that knows who is looking.
 */
async function searchUsers(query, requesterNickname, locale = 'ko') {
  const client = await pool.connect();
  try {
    const titleCol = locale === 'en' ? 'name_en'
      : locale === 'de' ? 'name_de'
      : 'name_ko';
    const result = await client.query(
      `SELECT u.nickname, u.level,
              u.profile_photo_key, u.profile_photo_status, u.profile_photo_expires_at,
              u.custom_title_text,
              e.banner_key, e.title_key,
              si.${titleCol} AS title_name,
              u.profile_private_hide_photo,
              EXISTS (
                SELECT 1 FROM tc_user_items ui
                JOIN tc_shop_items s2 ON s2.item_key = ui.item_key
                WHERE ui.nickname = u.nickname AND s2.effect_type = 'custom_title'
                  AND (ui.expires_at IS NULL OR ui.expires_at >= NOW())
              ) AS has_custom_title,
              -- Privacy is read from the row, not from the broadcast cache:
              -- that cache only knows people who have logged in since the
              -- server started, and a search hit is usually offline.
              EXISTS (
                SELECT 1 FROM tc_user_items ui
                JOIN tc_shop_items s3 ON s3.item_key = ui.item_key
                WHERE ui.nickname = u.nickname AND s3.effect_type = 'profile_private'
                  AND (ui.expires_at IS NULL OR ui.expires_at >= NOW())
              ) AND NOT EXISTS (
                SELECT 1 FROM tc_user_feature_off f
                WHERE f.nickname = u.nickname AND f.effect_type = 'profile_private'
              ) AS has_private
       FROM tc_users u
       LEFT JOIN tc_user_equips e ON e.nickname = u.nickname
       LEFT JOIN tc_shop_items si ON si.item_key = e.title_key
       WHERE u.nickname ILIKE $1 AND u.nickname != $2 AND u.is_deleted IS NOT TRUE
       ORDER BY u.nickname
       LIMIT 20`,
      [`%${query}%`, requesterNickname]
    );
    return result.rows.map((r) => {
      // Same rule as getUserProfile: a `custom:` title only shows while the
      // pass is live and something is written, and it never falls back to a
      // catalog name.
      const wearingCustom = (r.title_key || '').startsWith('custom:');
      const customActive = wearingCustom && r.has_custom_title && !!r.custom_title_text;
      return {
        nickname: r.nickname,
        level: r.level,
        bannerKey: r.banner_key || null,
        titleKey: wearingCustom && !customActive ? null : (r.title_key || null),
        titleName: customActive ? r.custom_title_text : (r.title_name || null),
        profilePhotoKey: r.profile_photo_key || null,
        profilePhotoStatus: r.profile_photo_status || 'none',
        profilePhotoExpiresAt: r.profile_photo_expires_at || null,
        hasProfilePrivate: r.has_private === true,
        profilePrivateHidePhoto: r.profile_private_hide_photo === true,
      };
    });
  } catch (err) {
    console.error('Search users error:', err);
    return [];
  } finally {
    client.release();
  }
}

async function sendDm(sender, receiver, message) {
  const client = await pool.connect();
  try {
    const result = await client.query(
      `INSERT INTO tc_dm_messages (sender_nickname, receiver_nickname, message)
       VALUES ($1, $2, $3)
       RETURNING id, created_at`,
      [sender, receiver, message]
    );
    return { success: true, id: result.rows[0].id, createdAt: result.rows[0].created_at };
  } catch (err) {
    console.error('Send DM error:', err);
    return { success: false, messageKey: 'db_dm_send_failed' };
  } finally {
    client.release();
  }
}

async function getDmHistory(nick1, nick2, beforeId, limit = 50) {
  const client = await pool.connect();
  try {
    let query, params;
    if (beforeId) {
      query = `SELECT id, sender_nickname, receiver_nickname, message, created_at, read_at
               FROM tc_dm_messages
               WHERE ((sender_nickname = $1 AND receiver_nickname = $2)
                  OR (sender_nickname = $2 AND receiver_nickname = $1))
                 AND id < $3
               ORDER BY id DESC
               LIMIT $4`;
      params = [nick1, nick2, beforeId, limit];
    } else {
      query = `SELECT id, sender_nickname, receiver_nickname, message, created_at, read_at
               FROM tc_dm_messages
               WHERE ((sender_nickname = $1 AND receiver_nickname = $2)
                  OR (sender_nickname = $2 AND receiver_nickname = $1))
               ORDER BY id DESC
               LIMIT $3`;
      params = [nick1, nick2, limit];
    }
    const result = await client.query(query, params);
    return result.rows.reverse(); // oldest first
  } catch (err) {
    console.error('Get DM history error:', err);
    return [];
  } finally {
    client.release();
  }
}

async function markDmRead(receiver, sender) {
  const client = await pool.connect();
  try {
    await client.query(
      `UPDATE tc_dm_messages SET read_at = NOW()
       WHERE receiver_nickname = $1 AND sender_nickname = $2 AND read_at IS NULL`,
      [receiver, sender]
    );
    return { success: true };
  } catch (err) {
    console.error('Mark DM read error:', err);
    return { success: false };
  } finally {
    client.release();
  }
}

async function getDmConversations(nickname) {
  const client = await pool.connect();
  try {
    const result = await client.query(
      `WITH partners AS (
         SELECT DISTINCT
           CASE WHEN sender_nickname = $1 THEN receiver_nickname ELSE sender_nickname END AS partner
         FROM tc_dm_messages
         WHERE sender_nickname = $1 OR receiver_nickname = $1
       ),
       latest AS (
         SELECT DISTINCT ON (p.partner)
           p.partner,
           m.id, m.message, m.created_at, m.sender_nickname
         FROM partners p
         JOIN tc_dm_messages m
           ON ((m.sender_nickname = $1 AND m.receiver_nickname = p.partner)
            OR (m.sender_nickname = p.partner AND m.receiver_nickname = $1))
         ORDER BY p.partner, m.created_at DESC
       ),
       unread AS (
         SELECT sender_nickname AS partner, COUNT(*) AS unread_count
         FROM tc_dm_messages
         WHERE receiver_nickname = $1 AND read_at IS NULL
         GROUP BY sender_nickname
       )
       SELECT l.partner, l.message AS last_message, l.created_at AS last_message_at,
              l.sender_nickname AS last_sender,
              COALESCE(u.unread_count, 0)::int AS unread_count
       FROM latest l
       LEFT JOIN unread u ON l.partner = u.partner
       ORDER BY l.created_at DESC`,
      [nickname]
    );
    return result.rows;
  } catch (err) {
    console.error('Get DM conversations error:', err);
    return [];
  } finally {
    client.release();
  }
}

async function getTotalUnreadDmCount(nickname) {
  const client = await pool.connect();
  try {
    const result = await client.query(
      `SELECT COUNT(*)::int AS count FROM tc_dm_messages
       WHERE receiver_nickname = $1 AND read_at IS NULL`,
      [nickname]
    );
    return result.rows[0].count;
  } catch (err) {
    console.error('Get total unread DM count error:', err);
    return 0;
  } finally {
    client.release();
  }
}

// ===== Skull King DB Functions =====

async function getSKRecentMatches(nickname, limit = 20) {
  const client = await pool.connect();
  try {
    const result = await client.query(
      `SELECT h.id, h.player_count, h.is_ranked, h.end_reason, h.deserter_nickname, h.created_at,
              p.score, p.rank, p.is_winner
       FROM tc_sk_match_players p
       JOIN tc_sk_match_history h ON h.id = p.match_id
       WHERE p.nickname = $1
       ORDER BY h.created_at DESC
       LIMIT $2`,
      [nickname, limit]
    );
    // For each match, get all players
    const matches = [];
    for (const row of result.rows) {
      const players = await client.query(
        `SELECT nickname, score, rank, is_winner, is_bot
         FROM tc_sk_match_players WHERE match_id = $1 ORDER BY rank`,
        [row.id]
      );
      const deserterNickname = row.deserter_nickname || null;
      const isDesertionLoss = deserterNickname === nickname;
      const isDraw = deserterNickname != null && deserterNickname !== nickname;
      matches.push({
        id: row.id,
        gameType: 'skull_king',
        won: isDraw ? false : row.is_winner,
        isDraw,
        isDesertionLoss,
        deserterNickname,
        myScore: row.score,
        myRank: row.rank,
        playerCount: row.player_count,
        isRanked: row.is_ranked,
        endReason: row.end_reason || 'normal',
        players: players.rows.map(p => ({
          nickname: p.nickname,
          score: p.score,
          rank: p.rank,
          isWinner: p.is_winner,
          isBot: p.is_bot,
        })),
        createdAt: row.created_at,
      });
    }
    return matches;
  } catch (err) {
    console.error('getSKRecentMatches error:', err);
    return [];
  } finally {
    client.release();
  }
}

async function saveSKMatchResult(data) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const matchRes = await client.query(
      `INSERT INTO tc_sk_match_history (player_count, is_ranked, end_reason, deserter_nickname)
       VALUES ($1, $2, $3, $4) RETURNING id`,
      [data.playerCount, data.isRanked, data.endReason || 'normal', data.deserterNickname || null]
    );
    const matchId = matchRes.rows[0].id;

    for (const p of data.players) {
      await client.query(
        `INSERT INTO tc_sk_match_players (match_id, nickname, score, rank, is_winner, is_bot)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [matchId, p.nickname, p.score, p.rank, p.isWinner, p.isBot]
      );
    }
    await client.query('COMMIT');
    return { success: true, matchId };
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('saveSKMatchResult error:', err);
    return { success: false, message: err.message };
  } finally {
    client.release();
  }
}

async function updateSKUserStats(nickname, won, isRanked) {
  const client = await pool.connect();
  try {
    const ratingChange = won ? 25 : -20;
    const goldReward = won ? 10 : 3;
    const expGain = won ? 15 : 5;
    await client.query(
      `UPDATE tc_users SET
        sk_total_games = sk_total_games + 1,
        sk_wins = sk_wins + CASE WHEN $2 THEN 1 ELSE 0 END,
        sk_losses = sk_losses + CASE WHEN $2 THEN 0 ELSE 1 END,
        sk_rating = GREATEST(0, sk_rating + $3),
        sk_season_games = sk_season_games + CASE WHEN $6 THEN 1 ELSE 0 END,
        sk_season_wins = sk_season_wins + CASE WHEN $6 AND $2 THEN 1 ELSE 0 END,
        sk_season_losses = sk_season_losses + CASE WHEN $6 AND NOT $2 THEN 1 ELSE 0 END,
        sk_season_rating = GREATEST(0, sk_season_rating + $3),
        gold = gold + $4,
        exp_total = exp_total + $5,
        level = tc_compute_level(exp_total + $5)
       WHERE nickname = $1`,
      [nickname, won, isRanked ? ratingChange : 0, goldReward, expGain, isRanked]
    );
    return { success: true };
  } catch (err) {
    console.error('updateSKUserStats error:', err);
    return { success: false, message: err.message };
  } finally {
    client.release();
  }
}

async function saveSKMatchResultWithStats(data) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const matchRes = await client.query(
      `INSERT INTO tc_sk_match_history (player_count, is_ranked, end_reason, deserter_nickname)
       VALUES ($1, $2, $3, $4) RETURNING id`,
      [data.playerCount, data.isRanked, data.endReason || 'normal', data.deserterNickname || null]
    );
    const matchId = matchRes.rows[0].id;

    for (const p of data.players) {
      await client.query(
        `INSERT INTO tc_sk_match_players (match_id, nickname, score, rank, is_winner, is_bot)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [matchId, p.nickname, p.score, p.rank, p.isWinner, p.isBot]
      );
    }

    // Fetch current SK ratings for ELO calculation
    const humanPlayers = data.players.filter(p => p.nickname && !p.isBot);
    const skRatingMap = {};
    if (humanPlayers.length > 0) {
      const nicknames = humanPlayers.map(p => p.nickname);
      const ratingRes = await client.query(
        `SELECT nickname, sk_rating FROM tc_users WHERE nickname = ANY($1)`,
        [nicknames]
      );
      for (const row of ratingRes.rows) {
        skRatingMap[row.nickname] = row.sk_rating || 1000;
      }
    }

    // Average rating of all players (including bots at 1000)
    const allRatings = data.players.map(p => p.isBot ? 1000 : (skRatingMap[p.nickname] || 1000));
    const totalAvg = allRatings.reduce((a, b) => a + b, 0) / allRatings.length;

    for (const p of humanPlayers) {
      const won = p.isWinner === true;
      const isDraw = p.isDraw === true;
      const isDeserter =
        ['leave', 'timeout'].includes(data.endReason || 'normal') &&
        data.deserterNickname === p.nickname;

      if (isDraw) {
        const expGain = 3;
        await client.query(
          `UPDATE tc_users SET
            sk_total_games = sk_total_games + 1,
            sk_season_games = sk_season_games + CASE WHEN $3 THEN 1 ELSE 0 END,
            exp_total = exp_total + $2,
            level = tc_compute_level(exp_total + $2)
           WHERE nickname = $1`,
          [p.nickname, expGain, data.isRanked]
        );
      } else {
        const myRating = skRatingMap[p.nickname] || 1000;
        // Compare against average of all other players
        const othersRatings = data.players.filter(o => o.nickname !== p.nickname).map(o => o.isBot ? 1000 : (skRatingMap[o.nickname] || 1000));
        const oppAvg = othersRatings.length > 0 ? othersRatings.reduce((a, b) => a + b, 0) / othersRatings.length : 1000;
        const ratingChange = calcElo(myRating, oppAvg, won);
        const baseGoldReward = won ? 10 : 3;
        const goldReward = isDeserter
            ? 0
            : (data.isRanked ? baseGoldReward * 2 : baseGoldReward);
        const expGain = isDeserter ? 0 : (won ? 15 : 5);
        await client.query(
          `UPDATE tc_users SET
            sk_total_games = sk_total_games + 1,
            sk_wins = sk_wins + CASE WHEN $2 THEN 1 ELSE 0 END,
            sk_losses = sk_losses + CASE WHEN $2 THEN 0 ELSE 1 END,
            sk_rating = GREATEST(0, sk_rating + $3),
            sk_season_games = sk_season_games + CASE WHEN $6 THEN 1 ELSE 0 END,
            sk_season_wins = sk_season_wins + CASE WHEN $6 AND $2 THEN 1 ELSE 0 END,
            sk_season_losses = sk_season_losses + CASE WHEN $6 AND NOT $2 THEN 1 ELSE 0 END,
            sk_season_rating = GREATEST(0, sk_season_rating + $3),
            gold = gold + $4,
            exp_total = exp_total + $5,
            level = tc_compute_level(exp_total + $5)
           WHERE nickname = $1`,
          [p.nickname, won, data.isRanked ? ratingChange : 0, goldReward, expGain, data.isRanked]
        );
      }
    }

    await client.query('COMMIT');
    return { success: true, matchId };
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('saveSKMatchResultWithStats error:', err);
    return { success: false, message: err.message };
  } finally {
    client.release();
  }
}

// ===== Love Letter DB Functions =====

async function saveLLMatchResultWithStats(data) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const matchRes = await client.query(
      `INSERT INTO tc_ll_match_history (player_count, is_ranked, end_reason, deserter_nickname)
       VALUES ($1, $2, $3, $4) RETURNING id`,
      [data.playerCount, data.isRanked, data.endReason || 'normal', data.deserterNickname || null]
    );
    const matchId = matchRes.rows[0].id;

    for (const p of data.players) {
      await client.query(
        `INSERT INTO tc_ll_match_players (match_id, nickname, score, rank, is_winner, is_bot)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [matchId, p.nickname, p.score, p.rank, p.isWinner, p.isBot]
      );
    }

    const humanPlayers = data.players.filter(p => p.nickname && !p.isBot);
    for (const p of humanPlayers) {
      const won = p.isWinner === true;
      const isDraw = p.isDraw === true;
      const isDeserter =
        ['leave', 'timeout'].includes(data.endReason || 'normal') &&
        data.deserterNickname === p.nickname;

      if (isDraw) {
        const expGain = 3;
        await client.query(
          `UPDATE tc_users SET
            ll_total_games = ll_total_games + 1,
            exp_total = exp_total + $2,
            level = tc_compute_level(exp_total + $2)
           WHERE nickname = $1`,
          [p.nickname, expGain]
        );
      } else {
        const goldReward = isDeserter ? 0 : (won ? 10 : 3);
        const expGain = isDeserter ? 0 : (won ? 15 : 5);
        await client.query(
          `UPDATE tc_users SET
            ll_total_games = ll_total_games + 1,
            ll_wins = ll_wins + CASE WHEN $2 THEN 1 ELSE 0 END,
            ll_losses = ll_losses + CASE WHEN $2 THEN 0 ELSE 1 END,
            gold = gold + $3,
            exp_total = exp_total + $4,
            level = tc_compute_level(exp_total + $4)
           WHERE nickname = $1`,
          [p.nickname, won, goldReward, expGain]
        );
      }
    }

    await client.query('COMMIT');
    return { success: true, matchId };
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('saveLLMatchResultWithStats error:', err);
    return { success: false, message: err.message };
  } finally {
    client.release();
  }
}

// ===== Mighty DB Functions =====

async function saveMightyMatchResultWithStats(data) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const matchRes = await client.query(
      `INSERT INTO tc_mighty_match_history (
         player_count, is_ranked, end_reason, deserter_nickname,
         declarer_nickname, partner_nickname, declarer_team_success,
         declarer_team_points, bid_points, trump_suit
       )
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
       RETURNING id`,
      [
        data.playerCount,
        data.isRanked,
        data.endReason || 'normal',
        data.deserterNickname || null,
        data.declarerNickname || null,
        data.partnerNickname || null,
        data.declarerTeamSuccess === true,
        data.declarerTeamPoints || 0,
        data.bidPoints || 0,
        data.trumpSuit || null,
      ]
    );
    const matchId = matchRes.rows[0].id;

    for (const p of data.players) {
      await client.query(
        `INSERT INTO tc_mighty_match_players (match_id, nickname, score, rank, is_winner, is_bot)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [matchId, p.nickname, p.score, p.rank, p.isWinner, p.isBot]
      );
    }

    // Fetch current Mighty ratings for ELO calculation
    const humanPlayers = data.players.filter(p => p.nickname && !p.isBot);
    const mightyRatingMap = {};
    if (humanPlayers.length > 0) {
      const nicknames = humanPlayers.map(p => p.nickname);
      const ratingRes = await client.query(
        `SELECT nickname, mighty_rating FROM tc_users WHERE nickname = ANY($1)`,
        [nicknames]
      );
      for (const row of ratingRes.rows) {
        mightyRatingMap[row.nickname] = row.mighty_rating || 1000;
      }
    }

    // Average rating of all players (including bots at 1000)
    const allRatings = data.players.map(p => p.isBot ? 1000 : (mightyRatingMap[p.nickname] || 1000));
    const totalAvg = allRatings.reduce((a, b) => a + b, 0) / allRatings.length;

    for (const p of humanPlayers) {
      const won = p.isWinner === true;
      const isDraw = p.isDraw === true;
      const isDeserter =
        ['leave', 'timeout'].includes(data.endReason || 'normal') &&
        data.deserterNickname === p.nickname;

      if (isDraw) {
        const expGain = 3;
        await client.query(
          `UPDATE tc_users SET
            mighty_total_games = mighty_total_games + 1,
            mighty_season_games = mighty_season_games + CASE WHEN $3 THEN 1 ELSE 0 END,
            exp_total = exp_total + $2,
            level = tc_compute_level(exp_total + $2)
           WHERE nickname = $1`,
          [p.nickname, expGain, data.isRanked]
        );
      } else {
        const myRating = mightyRatingMap[p.nickname] || 1000;
        const othersRatings = data.players.filter(o => o.nickname !== p.nickname).map(o => o.isBot ? 1000 : (mightyRatingMap[o.nickname] || 1000));
        const oppAvg = othersRatings.length > 0 ? othersRatings.reduce((a, b) => a + b, 0) / othersRatings.length : 1000;
        // Rating change scales with the final session score, not just binary
        // win/loss. A big-swing round (+60 / −50) moves rating more than a
        // squeaker (+5 / −5). Standard ELO provides the rating-sensitivity
        // baseline; we multiply by |score| / 25, clamped to [0.3, 2.5] so
        // neither a barely-positive winner nor a runaway blowout gets an
        // extreme rating change.
        const finalScore = p.score || 0;
        const baseElo = calcElo(myRating, oppAvg, won);
        const scoreMultiplier = Math.max(0.3, Math.min(2.5, Math.abs(finalScore) / 25));
        const ratingChange = Math.round(baseElo * scoreMultiplier);
        const baseGoldReward = won ? 10 : 3;
        const goldReward = isDeserter
            ? 0
            : (data.isRanked ? baseGoldReward * 2 : baseGoldReward);
        const expGain = isDeserter ? 0 : (won ? 15 : 5);
        await client.query(
          `UPDATE tc_users SET
            mighty_total_games = mighty_total_games + 1,
            mighty_wins = mighty_wins + CASE WHEN $2 THEN 1 ELSE 0 END,
            mighty_losses = mighty_losses + CASE WHEN $2 THEN 0 ELSE 1 END,
            mighty_rating = GREATEST(0, mighty_rating + $3),
            mighty_season_games = mighty_season_games + CASE WHEN $6 THEN 1 ELSE 0 END,
            mighty_season_wins = mighty_season_wins + CASE WHEN $6 AND $2 THEN 1 ELSE 0 END,
            mighty_season_losses = mighty_season_losses + CASE WHEN $6 AND NOT $2 THEN 1 ELSE 0 END,
            mighty_season_rating = GREATEST(0, mighty_season_rating + $3),
            gold = gold + $4,
            exp_total = exp_total + $5,
            level = tc_compute_level(exp_total + $5)
           WHERE nickname = $1`,
          [p.nickname, won, data.isRanked ? ratingChange : 0, goldReward, expGain, data.isRanked]
        );
      }
    }

    await client.query('COMMIT');
    return { success: true, matchId };
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('saveMightyMatchResultWithStats error:', err);
    return { success: false, message: err.message };
  } finally {
    client.release();
  }
}

async function getSKRankings(limit = 50) {
  const client = await pool.connect();
  try {
    const res = await client.query(
      `SELECT u.nickname, u.sk_rating AS rating, u.sk_wins AS wins,
              u.sk_losses AS losses, u.sk_total_games AS total_games,
              CASE WHEN u.sk_total_games > 0
                THEN ROUND((u.sk_wins::FLOAT / u.sk_total_games) * 100)
                ELSE 0 END AS win_rate,
              e.banner_key
       FROM tc_users u
       LEFT JOIN tc_user_equips e ON e.nickname = u.nickname
       WHERE u.sk_total_games > 0 AND u.is_deleted IS NOT TRUE
       ORDER BY u.sk_rating DESC, u.sk_wins DESC
       LIMIT $1`,
      [limit]
    );
    return { success: true, rankings: res.rows };
  } catch (err) {
    console.error('getSKRankings error:', err);
    return { success: false, rankings: [] };
  } finally {
    client.release();
  }
}

async function getCurrentSKSeasonRankings(limit = 50) {
  const client = await pool.connect();
  try {
    const res = await client.query(
      `SELECT u.nickname, u.sk_season_rating AS rating,
              u.sk_season_wins AS wins, u.sk_season_losses AS losses,
              u.sk_season_games AS total_games,
              CASE WHEN u.sk_season_games > 0
                THEN ROUND((u.sk_season_wins::FLOAT / u.sk_season_games) * 100)
                ELSE 0 END AS win_rate,
              e.banner_key
       FROM tc_users u
       LEFT JOIN tc_user_equips e ON e.nickname = u.nickname
       WHERE u.is_deleted IS NOT TRUE AND u.sk_season_games > 0
       ORDER BY u.sk_season_rating DESC, u.sk_season_wins DESC, u.sk_season_games DESC, u.nickname ASC
       LIMIT $1`,
      [limit]
    );
    return { success: true, rankings: res.rows };
  } catch (err) {
    console.error('getCurrentSKSeasonRankings error:', err);
    return { success: false, rankings: [] };
  } finally {
    client.release();
  }
}

async function getSKSeasonRankings(seasonId, limit = 50) {
  const client = await pool.connect();
  try {
    const res = await client.query(
      `SELECT r.nickname, r.rating, r.wins, r.losses, r.total_games,
              CASE WHEN r.total_games > 0
                THEN ROUND((r.wins::FLOAT / r.total_games) * 100)
                ELSE 0 END AS win_rate,
              e.banner_key
       FROM tc_season_rankings r
       LEFT JOIN tc_user_equips e ON e.nickname = r.nickname
       WHERE r.season_id = $1 AND r.game_type = 'skull_king'
       ORDER BY r.rank ASC
       LIMIT $2`,
      [seasonId, limit]
    );
    return { success: true, rankings: res.rows };
  } catch (err) {
    console.error('getSKSeasonRankings error:', err);
    return { success: false, rankings: [] };
  } finally {
    client.release();
  }
}

async function getMightyRankings(limit = 50) {
  const client = await pool.connect();
  try {
    const res = await client.query(
      `SELECT u.nickname, u.mighty_rating AS rating, u.mighty_wins AS wins,
              u.mighty_losses AS losses, u.mighty_total_games AS total_games,
              CASE WHEN u.mighty_total_games > 0
                THEN ROUND((u.mighty_wins::FLOAT / u.mighty_total_games) * 100)
                ELSE 0 END AS win_rate,
              e.banner_key
       FROM tc_users u
       LEFT JOIN tc_user_equips e ON e.nickname = u.nickname
       WHERE u.mighty_total_games > 0 AND u.is_deleted IS NOT TRUE
       ORDER BY u.mighty_rating DESC, u.mighty_wins DESC
       LIMIT $1`,
      [limit]
    );
    return { success: true, rankings: res.rows };
  } catch (err) {
    console.error('getMightyRankings error:', err);
    return { success: false, rankings: [] };
  } finally {
    client.release();
  }
}

async function getCurrentMightySeasonRankings(limit = 50) {
  const client = await pool.connect();
  try {
    const res = await client.query(
      `SELECT u.nickname, u.mighty_season_rating AS rating,
              u.mighty_season_wins AS wins, u.mighty_season_losses AS losses,
              u.mighty_season_games AS total_games,
              CASE WHEN u.mighty_season_games > 0
                THEN ROUND((u.mighty_season_wins::FLOAT / u.mighty_season_games) * 100)
                ELSE 0 END AS win_rate,
              e.banner_key
       FROM tc_users u
       LEFT JOIN tc_user_equips e ON e.nickname = u.nickname
       WHERE u.is_deleted IS NOT TRUE AND u.mighty_season_games > 0
       ORDER BY u.mighty_season_rating DESC, u.mighty_season_wins DESC, u.mighty_season_games DESC, u.nickname ASC
       LIMIT $1`,
      [limit]
    );
    return { success: true, rankings: res.rows };
  } catch (err) {
    console.error('getCurrentMightySeasonRankings error:', err);
    return { success: false, rankings: [] };
  } finally {
    client.release();
  }
}

async function getMightySeasonRankings(seasonId, limit = 50) {
  const client = await pool.connect();
  try {
    const res = await client.query(
      `SELECT r.nickname, r.rating, r.wins, r.losses, r.total_games,
              CASE WHEN r.total_games > 0
                THEN ROUND((r.wins::FLOAT / r.total_games) * 100)
                ELSE 0 END AS win_rate,
              e.banner_key
       FROM tc_season_rankings r
       LEFT JOIN tc_user_equips e ON e.nickname = r.nickname
       WHERE r.season_id = $1 AND r.game_type = 'mighty'
       ORDER BY r.rank ASC
       LIMIT $2`,
      [seasonId, limit]
    );
    return { success: true, rankings: res.rows };
  } catch (err) {
    console.error('getMightySeasonRankings error:', err);
    return { success: false, rankings: [] };
  } finally {
    client.release();
  }
}

// ===== Notices CRUD =====

async function getPublishedNotices() {
  const client = await pool.connect();
  try {
    const res = await client.query(
      `SELECT id, category, title, content, is_pinned, published_at, coupon_code,
              title_color
       FROM tc_notices
       WHERE status = 'published'
       ORDER BY is_pinned DESC, published_at DESC
       LIMIT 50`
    );
    return { success: true, notices: res.rows };
  } catch (err) {
    console.error('getPublishedNotices error:', err);
    return { success: false, notices: [] };
  } finally {
    client.release();
  }
}

async function getNotices(page = 1, limit = 20) {
  const client = await pool.connect();
  try {
    const offset = (page - 1) * limit;
    const countRes = await client.query('SELECT COUNT(*) FROM tc_notices');
    const total = parseInt(countRes.rows[0].count);
    const res = await client.query(
      `SELECT * FROM tc_notices ORDER BY is_pinned DESC, created_at DESC LIMIT $1 OFFSET $2`,
      [limit, offset]
    );
    return { rows: res.rows, total, page, limit };
  } catch (err) {
    console.error('getNotices error:', err);
    return { rows: [], total: 0, page, limit };
  } finally {
    client.release();
  }
}

async function getNoticeById(id) {
  const client = await pool.connect();
  try {
    const res = await client.query('SELECT * FROM tc_notices WHERE id = $1', [id]);
    return res.rows[0] || null;
  } catch (err) {
    console.error('getNoticeById error:', err);
    return null;
  } finally {
    client.release();
  }
}

async function createNotice(category, title, content, isPinned, status, couponCode = null, titleColor = null) {
  const client = await pool.connect();
  try {
    // UTC text, not a JS Date: this column is `timestamp without time zone`
    // and node-pg would serialize the Date in the process timezone, filing
    // every notice nine hours out on a KST host.
    const publishedAt = status === 'published'
      ? toUtcTimestampText(new Date())
      : null;
    const res = await client.query(
      `INSERT INTO tc_notices
         (category, title, content, is_pinned, status, published_at, coupon_code)
       VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id`,
      [category, title, content, isPinned, status, publishedAt,
        couponCode ? normalizeCouponCode(couponCode) : null]
    );
    return { success: true, id: res.rows[0].id };
  } catch (err) {
    console.error('createNotice error:', err);
    return { success: false };
  } finally {
    client.release();
  }
}

async function updateNotice(id, category, title, content, isPinned, status, couponCode = null, titleColor = null) {
  const client = await pool.connect();
  try {
    const existing = await client.query('SELECT status, published_at FROM tc_notices WHERE id = $1', [id]);
    if (existing.rows.length === 0) return { success: false };
    const oldStatus = existing.rows[0].status;
    const oldPublishedAt = existing.rows[0].published_at;
    const publishedAt = (status === 'published' && oldStatus !== 'published')
      ? toUtcTimestampText(new Date())
      : oldPublishedAt;
    await client.query(
      `UPDATE tc_notices SET category=$1, title=$2, content=$3, is_pinned=$4,
              status=$5, published_at=$6, coupon_code=$7, updated_at=NOW()
       WHERE id=$8`,
      [category, title, content, isPinned, status, publishedAt,
        couponCode ? normalizeCouponCode(couponCode) : null, id]
    );
    return { success: true };
  } catch (err) {
    console.error('updateNotice error:', err);
    return { success: false };
  } finally {
    client.release();
  }
}

async function deleteNotice(id) {
  const client = await pool.connect();
  try {
    await client.query('DELETE FROM tc_notices WHERE id = $1', [id]);
    return { success: true };
  } catch (err) {
    console.error('deleteNotice error:', err);
    return { success: false };
  } finally {
    client.release();
  }
}

// ===== Maintenance History =====

async function insertMaintenanceHistory({ action, config = {}, adminUser = null }) {
  await pool.query(
    `INSERT INTO tc_maintenance_history
       (action, notice_start, notice_end, maintenance_start, maintenance_end, message_ko, message_en, message_de, admin_user)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
    [
      action,
      config.noticeStart || null,
      config.noticeEnd || null,
      config.maintenanceStart || null,
      config.maintenanceEnd || null,
      config.message_ko || null,
      config.message_en || null,
      config.message_de || null,
      adminUser,
    ]
  );
}

async function getMaintenanceHistory(limit = 50) {
  const result = await pool.query(
    `SELECT * FROM tc_maintenance_history ORDER BY created_at DESC LIMIT $1`,
    [limit]
  );
  return result.rows;
}

// Get FCM tokens for broadcast push
async function getBroadcastFcmTokens(targetFilter = 'all') {
  let query = `SELECT id, fcm_token, nickname FROM tc_users
    WHERE push_enabled = true AND is_deleted IS NOT TRUE
      AND fcm_token IS NOT NULL AND fcm_token != ''
      AND fcm_token_invalid_at IS NULL`;
  const params = [];
  if (targetFilter === 'ios') {
    query += ` AND device_platform = $1`;
    params.push('ios');
  } else if (targetFilter === 'android') {
    query += ` AND device_platform = $1`;
    params.push('android');
  }
  const result = await pool.query(query, params);
  return result.rows;
}

/**
 * Tokens for the people a letter just went to.
 *
 * Same filter as a broadcast (a device that can receive, an account that
 * exists) but restricted to the addressees. Marketing consent is deliberately
 * NOT consulted: a letter from the staff is a service message — a reply, a
 * correction, a disciplinary notice — not advertising, and the marketing flag
 * covers advertising.
 */
async function getMailPushTokens(nicknames) {
  const list = (nicknames || []).filter(Boolean);
  if (list.length === 0) return [];
  try {
    const r = await pool.query(
      `SELECT id, fcm_token, nickname FROM tc_users
        WHERE nickname = ANY($1)
          AND push_enabled = true AND is_deleted IS NOT TRUE
          AND fcm_token IS NOT NULL AND fcm_token != ''
          AND fcm_token_invalid_at IS NULL`, [list]);
    return r.rows;
  } catch (err) {
    console.error('getMailPushTokens error:', err.message);
    return [];
  }
}

/**
 * Record one push to one user.
 *
 * Written BEFORE the send so the row's id can ride along in the notification's
 * data payload — that id is what comes back when the user taps it. The outcome
 * lands in a second write (finishPushLog), which is also why `success` is
 * nullable: a row with success still null is a send that never reported back.
 */
async function startPushLog({ kind = 'system', event, nickname, title, body, actor = null }) {
  try {
    const r = await pool.query(
      `INSERT INTO tc_push_log (kind, event, nickname, title, body, actor)
       VALUES ($1, $2, $3, $4, $5, $6) RETURNING id`,
      [kind, event || null, nickname || null, (title || '').slice(0, 200), body || '', actor],
    );
    return r.rows[0].id;
  } catch (err) {
    // Logging must never be the reason a notification does not go out.
    console.error('startPushLog error:', err.message);
    return null;
  }
}

async function finishPushLog(id, success, error = null) {
  if (!id) return;
  try {
    await pool.query(
      `UPDATE tc_push_log SET success = $2, error = $3 WHERE id = $1`,
      [id, !!success, error ? String(error).slice(0, 300) : null],
    );
  } catch (err) {
    console.error('finishPushLog error:', err.message);
  }
}

/**
 * A user tapped a notification.
 *
 * [kind] says which table the id belongs to — the three push sources number
 * their rows independently, so an id alone is ambiguous. Idempotent: the first
 * tap wins, and a second one (two devices, or a re-open) must not inflate the
 * count.
 */
async function markPushOpened(kind, id, nickname) {
  const numeric = parseInt(id, 10);
  if (!Number.isFinite(numeric)) return { success: false };
  try {
    if (kind === 'log') {
      await pool.query(
        `UPDATE tc_push_log
            SET opened_at = COALESCE(opened_at, (NOW() AT TIME ZONE 'UTC'))
          WHERE id = $1 AND ($2::varchar IS NULL OR nickname = $2)`,
        [numeric, nickname || null],
      );
      return { success: true };
    }
    if (kind === 'broadcast') {
      // Bump the summary only when this recipient had not already opened it.
      const r = await pool.query(
        `UPDATE tc_push_recipients
            SET opened_at = (NOW() AT TIME ZONE 'UTC')
          WHERE push_history_id = $1 AND nickname = $2 AND opened_at IS NULL
          RETURNING id`,
        [numeric, nickname],
      );
      if (r.rowCount > 0) {
        await pool.query(
          `UPDATE tc_push_history SET opened_count = COALESCE(opened_count, 0) + 1 WHERE id = $1`,
          [numeric],
        );
      }
      return { success: true };
    }
    return { success: false };
  } catch (err) {
    console.error('markPushOpened error:', err.message);
    return { success: false };
  }
}

/**
 * Everything that was ever pushed, newest first, from all three sources.
 *
 * A UNION rather than one table: the broadcast and campaign rows already live
 * in tables that own their own semantics (a campaign's row has to survive for
 * its reward to be claimable), and copying them into a spine would give two
 * places to disagree. The cost is this query; the benefit is that no writer
 * has to remember to write twice.
 */
async function getUnifiedPushHistory({ kind = 'all', search = '', page = 1, limit = 30 } = {}) {
  const lim = Math.max(1, Math.min(parseInt(limit, 10) || 30, 200));
  const off = (Math.max(1, parseInt(page, 10) || 1) - 1) * lim;
  const like = search ? `%${search}%` : null;
  // $1 = kind filter, $2 = search
  const union = `
    SELECT 'broadcast'::text AS kind, id, created_at, title, body,
           admin_username AS actor, NULL::varchar AS nickname,
           target_filter AS target, NULL::text AS event,
           success_count AS sent, fail_count AS failed,
           COALESCE(opened_count, 0) AS opened, NULL::int AS claimed
      FROM tc_push_history
    UNION ALL
    SELECT 'marketing'::text, c.id, COALESCE(c.sent_at, c.created_at), c.title, c.body,
           c.created_by, NULL, c.target_filter, c.status,
           c.sent_count, c.fail_count,
           (SELECT COUNT(*) FROM tc_push_campaign_recipients r
             WHERE r.campaign_id = c.id AND r.opened_at IS NOT NULL)::int,
           (SELECT COUNT(*) FROM tc_push_campaign_recipients r
             WHERE r.campaign_id = c.id AND r.claimed_at IS NOT NULL)::int
      FROM tc_push_campaigns c
     WHERE c.status = 'sent'
    UNION ALL
    SELECT CASE WHEN kind = 'admin_direct' THEN 'direct' ELSE 'system' END,
           id, created_at, title, body, actor, nickname,
           nickname, event,
           CASE WHEN success THEN 1 ELSE 0 END,
           CASE WHEN success = FALSE THEN 1 ELSE 0 END,
           CASE WHEN opened_at IS NOT NULL THEN 1 ELSE 0 END, NULL
      FROM tc_push_log`;
  // Placeholders are numbered as the filters are added rather than reserved
  // up front: an unused parameter has no type for Postgres to infer and the
  // whole query is rejected (42P18).
  const where = [];
  const params = [];
  if (kind && kind !== 'all') {
    params.push(kind);
    where.push(`kind = $${params.length}`);
  }
  if (like) {
    params.push(like);
    const i = params.length;
    where.push(`(title ILIKE $${i} OR body ILIKE $${i} OR COALESCE(nickname, '') ILIKE $${i})`);
  }
  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
  try {
    const countRes = await pool.query(
      `SELECT COUNT(*) FROM (${union}) u ${whereSql}`, params);
    const total = parseInt(countRes.rows[0].count, 10) || 0;
    const rows = await pool.query(
      `SELECT * FROM (${union}) u ${whereSql}
       ORDER BY created_at DESC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`,
      [...params, lim, off],
    );
    return { success: true, rows: rows.rows, total, page: Math.max(1, parseInt(page, 10) || 1), limit: lim };
  } catch (err) {
    console.error('getUnifiedPushHistory error:', err);
    return { success: false, rows: [], total: 0, page: 1, limit: lim, message: err.message };
  }
}

/** Counts per source, for the filter chips. */
async function getPushHistoryCounts() {
  try {
    const r = await pool.query(`
      SELECT 'broadcast' AS kind, COUNT(*)::int AS n FROM tc_push_history
      UNION ALL SELECT 'marketing', COUNT(*)::int FROM tc_push_campaigns WHERE status = 'sent'
      UNION ALL SELECT 'direct', COUNT(*)::int FROM tc_push_log WHERE kind = 'admin_direct'
      UNION ALL SELECT 'system', COUNT(*)::int FROM tc_push_log WHERE kind <> 'admin_direct'`);
    const out = {};
    for (const row of r.rows) out[row.kind] = row.n;
    out.all = Object.values(out).reduce((a, b) => a + b, 0);
    return out;
  } catch (err) {
    console.error('getPushHistoryCounts error:', err.message);
    return { all: 0 };
  }
}

/**
 * Retention. The summary rows are a handful per month and stay forever; what
 * grows without bound is the per-recipient and per-notification detail.
 *
 * Campaign recipients are deliberately NOT touched: their rows carry whether
 * the reward was claimed, and deleting one would let the same person claim
 * again the next time they tap an old notification.
 */
const PUSH_LOG_RETENTION_DAYS = 90;
async function purgePushLogs(days = PUSH_LOG_RETENTION_DAYS) {
  const n = Math.max(1, parseInt(days, 10) || PUSH_LOG_RETENTION_DAYS);
  try {
    const log = await pool.query(
      `DELETE FROM tc_push_log
        WHERE created_at < (NOW() AT TIME ZONE 'UTC') - ($1 || ' days')::interval`, [n]);
    const recips = await pool.query(
      `DELETE FROM tc_push_recipients
        WHERE created_at < (NOW() AT TIME ZONE 'UTC') - ($1 || ' days')::interval`, [n]);
    if (log.rowCount || recips.rowCount) {
      console.log(`[push] purged ${log.rowCount} log + ${recips.rowCount} recipient rows older than ${n}d`);
    }
    return { success: true, log: log.rowCount, recipients: recips.rowCount };
  } catch (err) {
    console.error('purgePushLogs error:', err.message);
    return { success: false, message: err.message };
  }
}

// Insert push history record
async function insertPushHistory({ adminUsername, title, body, targetFilter, totalSent, successCount, failCount, invalidTokens }) {
  const result = await pool.query(
    `INSERT INTO tc_push_history (admin_username, title, body, target_filter, total_sent, success_count, fail_count, invalid_tokens)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING id`,
    [adminUsername, title, body, targetFilter, totalSent, successCount, failCount, invalidTokens]
  );
  return result.rows[0].id;
}

/** Fill in a broadcast's outcome after the send (the row is created empty). */
async function updatePushHistoryCounts(id, { successCount, failCount, invalidTokens }) {
  try {
    await pool.query(
      `UPDATE tc_push_history
          SET success_count = $2, fail_count = $3, invalid_tokens = $4
        WHERE id = $1`,
      [id, successCount || 0, failCount || 0, invalidTokens || 0],
    );
    return { success: true };
  } catch (err) {
    console.error('updatePushHistoryCounts error:', err.message);
    return { success: false };
  }
}

// Get push history with pagination
async function getPushHistory(page = 1, limit = 20) {
  const offset = (page - 1) * limit;
  const countRes = await pool.query('SELECT COUNT(*) FROM tc_push_history');
  const total = parseInt(countRes.rows[0].count);
  const result = await pool.query(
    `SELECT * FROM tc_push_history ORDER BY created_at DESC LIMIT $1 OFFSET $2`,
    [limit, offset]
  );
  return { rows: result.rows, total, page, limit };
}

// Clear invalid FCM token for a user

// Insert push recipients
async function insertPushRecipients(historyId, recipients) {
  for (const r of recipients) {
    await pool.query(
      `INSERT INTO tc_push_recipients (push_history_id, user_id, nickname, status) VALUES ($1, $2, $3, $4)`,
      [historyId, r.userId, r.nickname, r.status]
    );
  }
}

// Get push history detail with recipients (paginated)
/**
 * Load every title item's localized names into a single map so broadcast
 * paths can localize a peer's equipped title per-recipient without an
 * extra DB round-trip on each send. Returns { titleKey: {ko, en, de} }.
 */
async function loadTitleTranslations() {
  const res = await pool.query(
    `SELECT item_key, name_ko, name_en, name_de
     FROM tc_shop_items WHERE category = 'title'`
  );
  const map = {};
  for (const row of res.rows) {
    map[row.item_key] = {
      ko: row.name_ko || '',
      en: row.name_en || row.name_ko || '',
      de: row.name_de || row.name_ko || '',
    };
  }
  return map;
}

async function updateCardViewPref(nickname, pref) {
  const valid = new Set(['ask', 'always_allow', 'always_deny']);
  if (!valid.has(pref)) {
    return { success: false, message: 'invalid card view pref' };
  }
  const client = await pool.connect();
  try {
    await client.query(
      `UPDATE tc_users SET card_view_pref = $1 WHERE nickname = $2`,
      [pref, nickname]
    );
    return { success: true, pref };
  } catch (err) {
    console.error('updateCardViewPref error:', err);
    return { success: false, message: 'db error' };
  } finally {
    client.release();
  }
}

async function getPushHistoryDetail(id, page = 1, limit = 50) {
  const historyRes = await pool.query(`SELECT * FROM tc_push_history WHERE id = $1`, [id]);
  if (historyRes.rows.length === 0) return null;
  const offset = (page - 1) * limit;
  const countRes = await pool.query(`SELECT COUNT(*) FROM tc_push_recipients WHERE push_history_id = $1`, [id]);
  const total = countRes.rows[0] ? parseInt(countRes.rows[0].count) : 0;
  const recipientsRes = await pool.query(
    `SELECT user_id, nickname, status FROM tc_push_recipients WHERE push_history_id = $1 ORDER BY id ASC LIMIT $2 OFFSET $3`,
    [id, limit, offset]
  );
  return { history: historyRes.rows[0], recipients: recipientsRes.rows, total, page, limit };
}

// Active gold IAP products for a platform. 'both' rows always match.
async function getActiveGoldProducts(platform) {
  try {
    const result = await pool.query(
      `SELECT product_id, gold_amount, bonus_gold, platform, price_krw,
              label_ko, label_en, label_de, sort_order
         FROM tc_gold_products
        WHERE is_active = TRUE
          AND (platform = 'both' OR platform = $1)
        ORDER BY sort_order ASC, id ASC`,
      [platform]
    );
    return { success: true, products: result.rows };
  } catch (err) {
    console.error('Get active gold products error:', err);
    return { success: false, products: [] };
  }
}

// Single active product by id — used server-side to decide the gold amount
// to grant. The client never tells us how much gold it should receive.
async function getGoldProductByProductId(productId) {
  try {
    const result = await pool.query(
      `SELECT product_id, gold_amount, bonus_gold, platform, is_active, price_krw,
              label_ko, label_en, label_de
         FROM tc_gold_products WHERE product_id = $1`,
      [productId]
    );
    return result.rows[0] || null;
  } catch (err) {
    console.error('Get gold product error:', err);
    return null;
  }
}

// Idempotently grant IAP gold. transaction_id is the dedupe key: the receipt
// insert with ON CONFLICT DO NOTHING decides whether this is the first time
// we've seen the transaction. Gold/history only move on the first insert, so
// client retries (or store re-delivery) never double-credit.
async function grantIapGold({ nickname, productId, platform, transactionId, environment, goldTotal, rawPayload, historyTitle }) {
  const env = environment === 'sandbox' ? 'sandbox' : 'production';
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const ins = await client.query(
      `INSERT INTO tc_iap_receipts
         (nickname, product_id, platform, transaction_id, gold_granted, environment, raw_payload)
       VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb)
       ON CONFLICT (transaction_id) DO NOTHING
       RETURNING id`,
      [nickname, productId, platform, transactionId, goldTotal, env,
       rawPayload ? JSON.stringify(rawPayload) : null]
    );
    if (ins.rows.length === 0) {
      // Already processed this transaction — no-op, report current balance.
      await client.query('ROLLBACK');
      const cur = await pool.query(
        `SELECT gold FROM tc_users WHERE nickname = $1`, [nickname]
      );
      return {
        success: true,
        alreadyGranted: true,
        newGold: cur.rows[0] ? cur.rows[0].gold : null,
      };
    }
    const upd = await client.query(
      `UPDATE tc_users SET gold = gold + $2 WHERE nickname = $1 RETURNING gold`,
      [nickname, goldTotal]
    );
    if (upd.rows.length === 0) {
      await client.query('ROLLBACK');
      return { success: false, message: 'User not found' };
    }
    await client.query(
      `INSERT INTO tc_gold_history (nickname, gold_delta, source, title, description)
       VALUES ($1, $2, 'iap', $3, $4)`,
      // title is the localized product name in "ko|en|de" form (same scheme
      // as shop_purchase, resolved client-side). Fall back to the legacy
      // marker if a label is somehow missing so the row stays renderable.
      [nickname, goldTotal,
       (historyTitle && historyTitle.replace(/\|/g, '').trim())
         ? historyTitle : 'iap_purchase',
       productId]
    );
    await client.query('COMMIT');
    return { success: true, alreadyGranted: false, newGold: upd.rows[0].gold };
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Grant IAP gold error:', err);
    return { success: false, message: err.message };
  } finally {
    client.release();
  }
}

// ---- Gold product admin CRUD ----

async function getAllGoldProductsAdmin() {
  try {
    const result = await pool.query(
      `SELECT * FROM tc_gold_products ORDER BY sort_order ASC, id ASC`
    );
    return result.rows;
  } catch (err) {
    console.error('Get all gold products admin error:', err);
    return [];
  }
}

async function getGoldProductById(id) {
  try {
    const result = await pool.query(
      `SELECT * FROM tc_gold_products WHERE id = $1`, [id]
    );
    return result.rows[0] || null;
  } catch (err) {
    console.error('Get gold product by id error:', err);
    return null;
  }
}

async function addGoldProduct(data) {
  try {
    const result = await pool.query(
      `INSERT INTO tc_gold_products
        (product_id, gold_amount, bonus_gold, platform,
         label_ko, label_en, label_de, sort_order, is_active)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
       RETURNING *`,
      [
        data.product_id, data.gold_amount || 0, data.bonus_gold || 0,
        data.platform || 'both',
        data.label_ko || '', data.label_en || '', data.label_de || '',
        data.sort_order || 0, data.is_active === true,
      ]
    );
    return { success: true, product: result.rows[0] };
  } catch (err) {
    console.error('Add gold product error:', err);
    if (err.code === '23505') {
      return { success: false, messageKey: 'db_product_id_exists' };
    }
    return { success: false, messageKey: 'db_product_add_failed' };
  }
}

async function updateGoldProduct(id, data) {
  try {
    const result = await pool.query(
      `UPDATE tc_gold_products
       SET product_id = $2, gold_amount = $3, bonus_gold = $4, platform = $5,
           label_ko = $6, label_en = $7, label_de = $8,
           sort_order = $9, is_active = $10
       WHERE id = $1
       RETURNING *`,
      [
        id, data.product_id, data.gold_amount || 0, data.bonus_gold || 0,
        data.platform || 'both',
        data.label_ko || '', data.label_en || '', data.label_de || '',
        data.sort_order || 0, data.is_active === true,
      ]
    );
    if (result.rows.length === 0) {
      return { success: false, messageKey: 'db_product_not_found' };
    }
    return { success: true, product: result.rows[0] };
  } catch (err) {
    console.error('Update gold product error:', err);
    if (err.code === '23505') {
      return { success: false, messageKey: 'db_product_id_exists' };
    }
    return { success: false, messageKey: 'db_product_update_failed' };
  }
}

async function deleteGoldProduct(id) {
  try {
    const result = await pool.query(
      `DELETE FROM tc_gold_products WHERE id = $1`, [id]
    );
    if (result.rowCount === 0) {
      return { success: false, messageKey: 'db_product_not_found' };
    }
    return { success: true };
  } catch (err) {
    console.error('Delete gold product error:', err);
    return { success: false, messageKey: 'db_product_delete_failed' };
  }
}

// ---- IAP receipt ledger (admin) ----

// Paginated receipt list with optional filters, plus a global summary strip
// (computed over the whole table, not the filtered view, so the operator
// always sees true totals regardless of the current filter).
async function getIapReceipts({ environment, status, platform, search, page = 1, limit = 50 } = {}) {
  try {
    const where = [];
    const params = [];
    if (environment === 'sandbox' || environment === 'production') {
      params.push(environment); where.push(`environment = $${params.length}`);
    }
    if (status === 'granted' || status === 'refunded') {
      params.push(status); where.push(`status = $${params.length}`);
    }
    if (platform === 'ios' || platform === 'android') {
      params.push(platform); where.push(`platform = $${params.length}`);
    }
    if (search) {
      params.push(`%${search}%`);
      where.push(`(nickname ILIKE $${params.length} OR product_id ILIKE $${params.length} OR transaction_id ILIKE $${params.length})`);
    }
    const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';

    const countRes = await pool.query(`SELECT COUNT(*) FROM tc_iap_receipts ${whereSql}`, params);
    const total = parseInt(countRes.rows[0].count, 10) || 0;

    const lim = Math.max(1, Math.min(parseInt(limit, 10) || 50, 200));
    const pg = Math.max(1, parseInt(page, 10) || 1);
    const offset = (pg - 1) * lim;
    const rowsRes = await pool.query(
      `SELECT id, nickname, product_id, platform, transaction_id, gold_granted,
              environment, status, refunded_at, refund_admin, verified_at
         FROM tc_iap_receipts ${whereSql}
        ORDER BY verified_at DESC, id DESC
        LIMIT ${lim} OFFSET ${offset}`,
      params
    );

    const sumRes = await pool.query(`
      SELECT
        COUNT(*)                                                              AS total,
        COUNT(*) FILTER (WHERE environment = 'production')                     AS prod_cnt,
        COUNT(*) FILTER (WHERE environment = 'sandbox')                        AS sandbox_cnt,
        COUNT(*) FILTER (WHERE status = 'refunded')                            AS refunded_cnt,
        COALESCE(SUM(gold_granted) FILTER (WHERE status = 'granted' AND environment = 'production'), 0) AS prod_gold
      FROM tc_iap_receipts`);
    const s = sumRes.rows[0] || {};
    return {
      rows: rowsRes.rows,
      total,
      page: pg,
      limit: lim,
      summary: {
        total: parseInt(s.total, 10) || 0,
        prodCount: parseInt(s.prod_cnt, 10) || 0,
        sandboxCount: parseInt(s.sandbox_cnt, 10) || 0,
        refundedCount: parseInt(s.refunded_cnt, 10) || 0,
        prodGold: parseInt(s.prod_gold, 10) || 0,
      },
    };
  } catch (err) {
    console.error('Get IAP receipts error:', err);
    return { rows: [], total: 0, page: 1, limit: 50, summary: { total: 0, prodCount: 0, sandboxCount: 0, refundedCount: 0, prodGold: 0 } };
  }
}

// Claw back IAP-granted gold. This does NOT move money — Apple/Google decide
// and execute the cash refund (especially for consumables). This only reverses
// the gold we credited and records who/when. By default we REFUSE if the user
// Best-effort audit log of a single verify attempt. Never throws — a logging
// failure must not break the purchase flow.
async function logIapAttempt({ nickname, platform, productId, environment, outcome, reason, transactionId, rawPayload }) {
  try {
    await pool.query(
      `INSERT INTO tc_iap_attempts
         (nickname, platform, product_id, environment, outcome, reason, transaction_id, raw_payload)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb)`,
      [
        nickname || null,
        platform || null,
        productId || null,
        environment || null,
        String(outcome || 'unknown').slice(0, 20),
        reason ? String(reason).slice(0, 80) : null,
        transactionId ? String(transactionId).slice(0, 255) : null,
        rawPayload ? JSON.stringify(rawPayload) : null,
      ]
    );
  } catch (err) {
    console.error('Log IAP attempt error:', err.message);
  }
}

// Build the Apple ConsumptionRequest data snapshot for a transaction. All
// values are best-effort estimates from our own records (no store price).
async function getConsumptionSnapshot(transactionId) {
  const KRW_PER_USD = 1350; // rough; only used to pick Apple's $ buckets
  const usdBucket = (krw) => {
    const usd = (Number(krw) || 0) / KRW_PER_USD;
    if (usd <= 0) return 1;            // $0
    if (usd < 50) return 2;            // $0.01–49.99
    if (usd < 100) return 3;
    if (usd < 500) return 4;
    if (usd < 1000) return 5;
    if (usd < 2000) return 6;
    return 7;                          // $2000+
  };
  const tenureEnum = (days) => {
    if (days == null) return 0;
    if (days <= 3) return 1;
    if (days <= 10) return 2;
    if (days <= 30) return 3;
    if (days <= 90) return 4;
    if (days <= 180) return 5;
    if (days <= 365) return 6;
    return 7;
  };
  const playTimeEnum = (games) => {
    const g = Number(games) || 0;
    if (g === 0) return 1;
    if (g < 10) return 2;
    if (g < 50) return 3;
    if (g < 200) return 4;
    return 5;
  };
  try {
    const recRes = await pool.query(
      `SELECT nickname, product_id, gold_granted, environment
         FROM tc_iap_receipts WHERE transaction_id = $1`,
      [String(transactionId)]
    );
    const rec = recRes.rows[0] || null;
    const nickname = rec ? rec.nickname : null;

    let accountTenureDays = null;
    let userStatus = 0;          // undeclared
    let playTime = 0;
    let currentGold = null;
    if (nickname) {
      const u = await pool.query(
        `SELECT created_at, gold, is_deleted, total_games
           FROM tc_users WHERE nickname = $1`,
        [nickname]
      );
      if (u.rows[0]) {
        const usr = u.rows[0];
        if (usr.created_at) {
          accountTenureDays = Math.max(
            0,
            Math.floor((Date.now() - new Date(usr.created_at).getTime()) / 86400000)
          );
        }
        userStatus = usr.is_deleted === true ? 3 : 1; // terminated / active
        playTime = playTimeEnum(usr.total_games);
        currentGold = parseInt(usr.gold, 10);
      }
    }

    // Lifetime IAP totals for this account (production money only).
    let lifetimeKrw = 0;
    let lifetimeRefundKrw = 0;
    let refundCount = 0;
    if (nickname) {
      const agg = await pool.query(
        `SELECT product_id, status FROM tc_iap_receipts
          WHERE nickname = $1 AND environment = 'production'`,
        [nickname]
      );
      for (const r of agg.rows) {
        const krw = GOLD_PRODUCT_KRW[r.product_id] || 0;
        lifetimeKrw += krw;
        if (r.status === 'refunded') { lifetimeRefundKrw += krw; refundCount += 1; }
      }
    }

    // consumptionStatus: did they still hold the granted gold? Heuristic —
    // current balance below this grant ⇒ treat as fully consumed.
    let consumptionStatus = 0; // undeclared
    if (rec && currentGold != null) {
      consumptionStatus = currentGold >= (parseInt(rec.gold_granted, 10) || 0) ? 1 : 3;
    }

    // Smart anti-abuse refund preference (Apple only weighs this, decides).
    let refundPreference = 3; // no preference
    const shortTenure = accountTenureDays != null && accountTenureDays < 7;
    if ((consumptionStatus === 3 && shortTenure) || refundCount >= 2) {
      refundPreference = 2; // prefer decline
    }

    return {
      found: !!rec,
      nickname,
      productId: rec ? rec.product_id : null,
      environment: rec ? rec.environment : null,
      accountTenureDays,
      fields: {
        accountTenure: tenureEnum(accountTenureDays),
        consumptionStatus,
        customerConsented: true,        // covered by ToS / privacy policy
        deliveryStatus: 0,              // delivered & working
        lifetimeDollarsPurchased: usdBucket(lifetimeKrw),
        lifetimeDollarsRefunded: usdBucket(lifetimeRefundKrw),
        platform: 1,                    // Apple
        playTime,
        refundPreference,
        sampleContentProvided: false,
        userStatus,
      },
      debug: { lifetimeKrw, lifetimeRefundKrw, refundCount, currentGold },
    };
  } catch (err) {
    console.error('Get consumption snapshot error:', err.message);
    return { found: false, nickname: null, fields: null };
  }
}

// Idempotent on notification_uuid (Apple retries the same notification).
async function recordConsumptionRequest({
  notificationUUID, transactionId, productId, nickname, environment,
  requestReason, snapshot, responseStatus, responseDetail,
}) {
  try {
    const f = snapshot && snapshot.fields ? snapshot.fields : {};
    await pool.query(
      `INSERT INTO tc_iap_consumption_requests
        (notification_uuid, transaction_id, product_id, nickname, environment,
         request_reason, consumption_status, refund_preference,
         account_tenure_days, response_status, response_detail, snapshot,
         responded_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12::jsonb,
         CASE WHEN $10 IN ('responded','failed','skipped') THEN NOW() ELSE NULL END)
       ON CONFLICT (notification_uuid) DO UPDATE SET
         response_status = EXCLUDED.response_status,
         response_detail = EXCLUDED.response_detail,
         snapshot = EXCLUDED.snapshot,
         consumption_status = EXCLUDED.consumption_status,
         refund_preference = EXCLUDED.refund_preference,
         account_tenure_days = EXCLUDED.account_tenure_days,
         responded_at = CASE WHEN EXCLUDED.response_status IN ('responded','failed','skipped')
                              THEN NOW() ELSE tc_iap_consumption_requests.responded_at END`,
      [
        String(notificationUUID).slice(0, 64),
        transactionId ? String(transactionId).slice(0, 255) : null,
        productId ? String(productId).slice(0, 80) : null,
        nickname ? String(nickname).slice(0, 50) : null,
        environment ? String(environment).slice(0, 12) : null,
        requestReason ? String(requestReason).slice(0, 40) : null,
        f.consumptionStatus != null ? f.consumptionStatus : null,
        f.refundPreference != null ? f.refundPreference : null,
        snapshot && snapshot.accountTenureDays != null ? snapshot.accountTenureDays : null,
        String(responseStatus || 'received').slice(0, 16),
        responseDetail ? String(responseDetail).slice(0, 160) : null,
        snapshot ? JSON.stringify(snapshot) : null,
      ]
    );
  } catch (err) {
    console.error('Record consumption request error:', err.message);
  }
}

async function listConsumptionRequests({ status, search, page = 1, limit = 50 } = {}) {
  try {
    const where = [];
    const params = [];
    if (status) { params.push(status); where.push(`response_status = $${params.length}`); }
    if (search) {
      params.push(`%${search}%`);
      where.push(`(nickname ILIKE $${params.length} OR product_id ILIKE $${params.length} OR transaction_id ILIKE $${params.length})`);
    }
    const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
    const lim = Math.max(1, Math.min(parseInt(limit, 10) || 50, 200));
    const pg = Math.max(1, parseInt(page, 10) || 1);
    const countRes = await pool.query(`SELECT COUNT(*) FROM tc_iap_consumption_requests ${whereSql}`, params);
    const total = parseInt(countRes.rows[0].count, 10);
    const rowsRes = await pool.query(
      `SELECT id, notification_uuid, transaction_id, product_id, nickname,
              environment, request_reason, consumption_status, refund_preference,
              account_tenure_days, response_status, response_detail,
              created_at, responded_at
         FROM tc_iap_consumption_requests ${whereSql}
        ORDER BY created_at DESC
        LIMIT ${lim} OFFSET ${(pg - 1) * lim}`,
      params
    );
    const summaryRes = await pool.query(
      `SELECT response_status, COUNT(*) FROM tc_iap_consumption_requests GROUP BY response_status`
    );
    const summary = {};
    for (const r of summaryRes.rows) summary[r.response_status] = parseInt(r.count, 10);
    return { rows: rowsRes.rows, total, page: pg, limit: lim, summary };
  } catch (err) {
    console.error('List consumption requests error:', err.message);
    return { rows: [], total: 0, page: 1, limit: 50, summary: {} };
  }
}

// ---- Daily attendance reward (7-day streak) ---------------------------------
// Day 1..6: 50G each, Day 7: 1000G. After day 7 the next claim starts a new
// cycle at day 1. Missing a day (last claim ≠ today−1) resets the streak.
const ATTENDANCE_REWARDS = [50, 50, 50, 50, 50, 50, 1000];

// State for the client UI (no DB writes). All "today/yesterday" logic uses
// KST (server authority); the client renders the reset clock in device-local
// time using `resetAtUtc`.
async function getAttendanceState(nickname) {
  try {
    const r = await pool.query(
      `SELECT
         a.last_claim_date,
         COALESCE(a.current_streak, 0) AS current_streak,
         COALESCE(a.total_claims, 0)  AS total_claims,
         DATE(timezone('Asia/Seoul', NOW())) AS kst_today,
         ((DATE(timezone('Asia/Seoul', NOW())) + 1)::timestamp
            AT TIME ZONE 'Asia/Seoul') AS reset_at_utc,
         (a.last_claim_date = DATE(timezone('Asia/Seoul', NOW())))::bool
            AS claimed_today,
         (a.last_claim_date = DATE(timezone('Asia/Seoul', NOW())) - 1)::bool
            AS continues_streak
       FROM (SELECT 1) _
       LEFT JOIN tc_attendance a ON a.nickname = $1`,
      [nickname]
    );
    const row = r.rows[0] || {};
    const streak = parseInt(row.current_streak, 10) || 0;
    const claimedToday = row.claimed_today === true;
    const continuesStreak = row.continues_streak === true;
    let cycleClaimedDays, todayDay;
    if (claimedToday) {
      // Already claimed today; current cycle stands at `streak` boxes filled.
      cycleClaimedDays = streak;
      todayDay = streak;
    } else if (continuesStreak) {
      // Yesterday was day `streak`; today extends it (or starts new cycle
      // if yesterday completed day 7).
      cycleClaimedDays = streak >= 7 ? 0 : streak;
      todayDay = streak >= 7 ? 1 : streak + 1;
    } else {
      // Missed a day OR first-time user → cycle resets visually too.
      cycleClaimedDays = 0;
      todayDay = 1;
    }
    return {
      claimedToday,
      cycleClaimedDays,
      todayDay,
      todayRewardGold: ATTENDANCE_REWARDS[todayDay - 1],
      weekRewards: ATTENDANCE_REWARDS,
      resetAtUtc: row.reset_at_utc
        ? new Date(row.reset_at_utc).toISOString() : null,
      totalClaims: parseInt(row.total_claims, 10) || 0,
    };
  } catch (err) {
    console.error('Get attendance state error:', err.message);
    return null;
  }
}

// Idempotent on (nickname, KST today). Returns the granted reward + new state.
// Caller is expected to gate the call on a watched rewarded-ad completion;
// double-claim is still impossible because of the DATE check inside the tx.
async function claimAttendance(nickname) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    // All KST date math is done in Postgres and returned as booleans +
    // pre-formatted text. This sidesteps node-pg's DATE → new Date(y,m,d)
    // (local-TZ midnight) parser: on a non-UTC host, the resulting
    // .toISOString().slice(0,10) is off by one day and the JS
    // `lastStr === today` idempotency check breaks (server silently grants
    // every same-day claim). PG-side comparison is timezone-correct.
    const sel = await client.query(
      `SELECT
         u.gold,
         COALESCE(a.current_streak, 0) AS current_streak,
         (a.last_claim_date IS NOT NULL
          AND a.last_claim_date = DATE(timezone('Asia/Seoul', NOW())))::bool
            AS claimed_today,
         (a.last_claim_date IS NOT NULL
          AND a.last_claim_date = DATE(timezone('Asia/Seoul', NOW())) - 1)::bool
            AS continues_streak,
         DATE(timezone('Asia/Seoul', NOW()))::text AS today_str
       FROM tc_users u
       LEFT JOIN tc_attendance a ON a.nickname = u.nickname
       WHERE u.nickname = $1
       FOR UPDATE OF u`,
      [nickname]
    );
    if (sel.rows.length === 0) {
      await client.query('ROLLBACK');
      return { success: false, reason: 'user_not_found' };
    }
    const row = sel.rows[0];
    if (row.claimed_today === true) {
      await client.query('ROLLBACK');
      return { success: false, reason: 'already_claimed' };
    }
    const streak = parseInt(row.current_streak, 10) || 0;
    const continues = row.continues_streak === true;
    const newStreak = nextAttendanceStreak(streak, continues);
    const reward = ATTENDANCE_REWARDS[newStreak - 1];
    // today_str is already 'YYYY-MM-DD' formatted by PG, TZ-safe.
    const today = row.today_str;

    await client.query(
      `INSERT INTO tc_attendance
         (nickname, last_claim_date, current_streak, total_claims, updated_at)
       VALUES ($1, $2::date, $3, 1, CURRENT_TIMESTAMP)
       ON CONFLICT (nickname) DO UPDATE SET
         last_claim_date = EXCLUDED.last_claim_date,
         current_streak  = EXCLUDED.current_streak,
         total_claims    = tc_attendance.total_claims + 1,
         updated_at      = CURRENT_TIMESTAMP`,
      [nickname, today, newStreak]
    );
    const upd = await client.query(
      `UPDATE tc_users SET gold = gold + $2 WHERE nickname = $1 RETURNING gold`,
      [nickname, reward]
    );
    const newGold = upd.rows[0] ? upd.rows[0].gold : null;
    // source='attendance', title='attendance' (client localizer maps this).
    // description holds the streak day for ops/debug.
    await client.query(
      `INSERT INTO tc_gold_history (nickname, gold_delta, source, title, description)
       VALUES ($1, $2, 'attendance', 'attendance', $3)`,
      [nickname, reward, `day_${newStreak}`]
    );
    await client.query('COMMIT');
    return {
      success: true,
      goldGranted: reward,
      newStreak,
      newGold,
      claimedDate: today,
    };
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Claim attendance error:', err.message);
    return { success: false, reason: 'error', message: err.message };
  } finally {
    client.release();
  }
}

// ---- Attendance: the evening reminder ---------------------------------------

/// 저녁 7시에 알림을 보낼 사람들.
///
/// "7시" 는 받는 사람의 시계 기준이다. 서버는 UTC 한 곳에서 도는데 사용자는
/// 전 세계에 있으므로, 기기가 올려 준 오프셋(`tz_offset_minutes`)을 더해
/// 각자의 현지 시각을 만들어 비교한다.
///
/// 오프셋을 안 올린 옛 클라이언트는 **한국어 사용자만** KST(+540)로 친다.
/// 한국 사용자가 절대다수라 그 추정은 거의 맞고, 틀려도 시차가 없다. 반대로
/// 지역을 모르는 해외 사용자에게 추정으로 보내면 새벽 세 시에 울릴 수 있다 —
/// 그건 알림을 아예 못 보내는 것보다 나쁘다. 그 사람들은 앱을 한 번
/// 업데이트하면 자동으로 대상이 된다.
///
/// 한 시간(19:00~19:59) 통째로 창을 열어 두고 보낸 날짜로 중복을 막는다.
/// 10분마다 도는 스케줄러가 한두 번 걸러져도(재시작, 지연) 그 시간 안에
/// 따라잡을 수 있어야 하기 때문이다.
const ATTENDANCE_PUSH_HOUR = 19;

/// 연속 몇 번을 무시하면 쉬는가, 그리고 얼마나 쉬는가.
///
/// 반응 없는 사람에게 매일 보내는 것은 이 알림 하나를 끄게 만드는 게 아니라
/// 알림 전체를 끄게 만든다. 세 번 보내고 세 번 다 안 왔으면 일주일 쉰다.
const ATTENDANCE_PUSH_IGNORE_LIMIT = 3;
const ATTENDANCE_PUSH_MUTE_DAYS = 7;

/// 오늘 받으면 며칠째가 되는가.
///
/// 출석 처리(claimAttendance)와 알림 문구가 각각 계산하면 언젠가 어긋난다.
/// 어긋나면 "6일째예요, 내일 1,000골드" 라고 불러 놓고 들어가 보니 1일차인
/// 일이 벌어진다 — 그 거짓말은 알림을 끄게 만든다.
function nextAttendanceStreak(streak, continues) {
  if (!continues) return 1;
  return streak >= 7 ? 1 : streak + 1;
}

/// [hour] 는 테스트용. 기본값은 저녁 7시이고, 실제 발송은 그대로 쓴다.
/// 하루 중 언제 돌려도 같은 답이 나와야 검증이 되기 때문에 열어 둔다.
async function getAttendancePushTargets({ hour = ATTENDANCE_PUSH_HOUR } = {}) {
  try {
    const r = await pool.query(
      `WITH u AS (
         SELECT
           nickname, fcm_token, locale,
           COALESCE(tz_offset_minutes,
                    CASE WHEN locale = 'ko' THEN 540 ELSE NULL END) AS tz
         FROM tc_users
         WHERE fcm_token IS NOT NULL
           AND fcm_token_invalid_at IS NULL
           AND is_deleted IS NOT TRUE
           AND push_enabled IS NOT FALSE
           AND marketing_push_enabled = TRUE
           AND push_attendance IS NOT FALSE
       )
       SELECT
         u.nickname, u.fcm_token, u.locale, u.tz,
         (timezone('UTC', NOW()) + (u.tz || ' minutes')::interval)::date AS local_date,
         COALESCE(a.current_streak, 0) AS current_streak,
         a.push_last_date,
         COALESCE(a.push_ignored, 0) AS push_ignored,
         -- 지난번에 보냈는데 그날 이후로 출석을 안 했는가.
         -- 보낸 적이 없으면 무시한 것도 없다 — 이걸 빼면 첫 알림부터
         -- 무시 횟수가 1로 시작해서 예정보다 일찍 쉬게 된다.
         (a.push_last_date IS NOT NULL
            AND (a.last_claim_date IS NULL
                 OR a.last_claim_date < a.push_last_date))
           AS ignored_last,
         (a.last_claim_date = DATE(timezone('Asia/Seoul', NOW())) - 1) AS continues_streak
       FROM u
       LEFT JOIN tc_attendance a ON a.nickname = u.nickname
       WHERE u.tz IS NOT NULL
         -- 받는 사람의 시계로 저녁 7시대인가
         AND EXTRACT(HOUR FROM timezone('UTC', NOW()) + (u.tz || ' minutes')::interval) = $1
         -- 오늘 아직 안 보냈는가 (그 사람의 현지 날짜 기준)
         AND (a.push_last_date IS NULL
              OR a.push_last_date <> (timezone('UTC', NOW()) + (u.tz || ' minutes')::interval)::date)
         -- 오늘 아직 출석 안 했는가 (출석 리셋은 KST 자정 고정)
         AND (a.last_claim_date IS NULL
              OR a.last_claim_date <> DATE(timezone('Asia/Seoul', NOW())))
         -- 쉬는 중이 아닌가
         AND (a.push_muted_until IS NULL
              OR a.push_muted_until < DATE(timezone('Asia/Seoul', NOW())))`,
      [hour],
    );
    return r.rows.map(row => ({
      nickname: row.nickname,
      fcmToken: row.fcm_token,
      locale: row.locale,
      localDate: row.local_date,
      // 오늘 받으면 며칠째가 되는가. claimAttendance 의 계산과 **똑같아야**
      // 한다 — 어제 받았으면 이어지고, 7일을 채웠으면 새 주기의 1일차로
      // 돌아가고, 하루라도 빠졌으면 1일차다. 여기가 어긋나면 "6일째예요"
      // 라고 불러 놓고 들어가 보면 1일차인 알림이 나간다.
      nextStreak: nextAttendanceStreak(
        parseInt(row.current_streak, 10) || 0,
        row.continues_streak === true,
      ),
      ignoredLast: row.ignored_last === true,
      pushIgnored: parseInt(row.push_ignored, 10) || 0,
    }));
  } catch (err) {
    console.error('Get attendance push targets error:', err.message);
    return [];
  }
}

/// 이 사람에게 보낼 권리를 집는다. 집었으면 true.
///
/// 보내고 나서 적는 게 아니라 **적고 나서 보낸다.** 그리고 적는 일을 조건부
/// UPDATE 한 방으로 해서, 이미 오늘 적힌 행이면 아무것도 안 바꾸고 빈손으로
/// 돌아온다. 그 경우 보내지 않는다.
///
/// 이렇게까지 하는 이유는 배포 방식 때문이다. 블루/그린이라 새 슬롯을 띄운
/// 뒤 옛 슬롯을 최대 15분 드레인하는데, 그동안 두 프로세스가 같이 돌고 둘 다
/// 10분 타이머를 갖고 있다. 목록을 읽고 나서 적는 순서였으면 둘 다 "아직 안
/// 보냈네" 를 보고 각자 보낸다 — 사용자에게는 같은 알림이 두 번 온다.
/// 배포는 하루에도 여러 번 하고, 사용자가 여러 시간대에 흩어져 있으니
/// 어느 시간대인가는 늘 저녁 7시다. 드문 사고가 아니다.
///
/// 못 보낸 것보다 두 번 보낸 게 나쁘다고 본 판단은 그대로다 — 그래서 먼저
/// 적는다. 다만 "먼저 적는다" 가 한 프로세스 안에서만 통하던 것을 프로세스
/// 사이에서도 통하게 만든 것이다.
async function claimAttendancePush(nickname, localDate, ignoredLast) {
  try {
    // 이번 건까지 세었을 때의 무시 횟수. 한도를 넘겼는지 보고, 안 넘겼으면
    // 그대로 저장한다 — 두 번 쓰기 때문에 한 번만 적고 이름을 붙인다.
    const ignored = `CASE WHEN $3::bool
                          THEN COALESCE(tc_attendance.push_ignored, 0) + 1
                          ELSE 0 END`;
    const r = await pool.query(
      `INSERT INTO tc_attendance (nickname, push_last_date, push_ignored)
       VALUES ($1, $2::date, CASE WHEN $3::bool THEN 1 ELSE 0 END)
       ON CONFLICT (nickname) DO UPDATE SET
         push_last_date = $2::date,
         -- 한도를 넘겼으면 0 으로 되돌린다. 쉬고 돌아왔을 때 첫 알림에
         -- 곧바로 다시 걸리면 영영 못 벗어난다.
         push_ignored = CASE WHEN ${ignored} >= $4 THEN 0 ELSE ${ignored} END,
         push_muted_until = CASE
           WHEN ${ignored} >= $4
             THEN DATE(timezone('Asia/Seoul', NOW())) + $5::int
           ELSE tc_attendance.push_muted_until END,
         updated_at = CURRENT_TIMESTAMP
       WHERE tc_attendance.push_last_date IS DISTINCT FROM $2::date
       RETURNING nickname`,
      [nickname, localDate, ignoredLast === true,
       ATTENDANCE_PUSH_IGNORE_LIMIT, ATTENDANCE_PUSH_MUTE_DAYS],
    );
    return r.rowCount > 0;
  } catch (err) {
    console.error('Claim attendance push error:', err.message);
    // 적지 못했으면 보내지 않는다. 적히지 않은 채로 보내면 다음 틱에 또 보낸다.
    return false;
  }
}

// ---- Attendance: admin queries ---------------------------------------------
// Today's headline numbers for the dashboard card. KST-anchored; counts users
// whose last_claim_date is today, plus 7-day completions and gold granted.
async function getAttendanceDashboardStats() {
  try {
    const r = await pool.query(`
      SELECT
        COUNT(*) FILTER (
          WHERE last_claim_date = DATE(timezone('Asia/Seoul', NOW()))
        ) AS today_claims,
        COUNT(*) FILTER (
          WHERE last_claim_date = DATE(timezone('Asia/Seoul', NOW()))
            AND current_streak = 7
        ) AS today_finales
      FROM tc_attendance
    `);
    const g = await pool.query(`
      SELECT COALESCE(SUM(gold_delta), 0) AS gold_today
      FROM tc_gold_history
      WHERE source = 'attendance'
        AND DATE((created_at) AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Seoul')
          = DATE(timezone('Asia/Seoul', NOW()))
    `);
    return {
      todayClaims: parseInt(r.rows[0].today_claims, 10) || 0,
      todayFinales: parseInt(r.rows[0].today_finales, 10) || 0,
      todayGold: parseInt(g.rows[0].gold_today, 10) || 0,
    };
  } catch (err) {
    console.error('Get attendance dashboard stats error:', err.message);
    return { todayClaims: 0, todayFinales: 0, todayGold: 0 };
  }
}

// Paginated attendance log for ops. Sources tc_gold_history rows so we get the
// exact streak day (description='day_N') and per-claim timestamp. Defaults to
// today (KST) when `date` is not supplied.
async function listAttendanceLog({ date, search, page = 1, limit = 50 } = {}) {
  try {
    const lim = Math.max(1, Math.min(parseInt(limit, 10) || 50, 200));
    const pg = Math.max(1, parseInt(page, 10) || 1);
    const where = [`h.source = 'attendance'`];
    const params = [];
    if (date) {
      params.push(date);
      where.push(`DATE((h.created_at) AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Seoul')
                    = $${params.length}::date`);
    } else {
      where.push(`DATE((h.created_at) AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Seoul')
                    = DATE(timezone('Asia/Seoul', NOW()))`);
    }
    if (search) {
      params.push(`%${search}%`);
      where.push(`h.nickname ILIKE $${params.length}`);
    }
    const whereSql = `WHERE ${where.join(' AND ')}`;
    const countRes = await pool.query(
      `SELECT COUNT(*) FROM tc_gold_history h ${whereSql}`, params);
    const total = parseInt(countRes.rows[0].count, 10) || 0;
    const rowsRes = await pool.query(
      `SELECT h.id, h.nickname, h.gold_delta, h.description AS day_key,
              h.created_at,
              a.current_streak, a.total_claims
         FROM tc_gold_history h
         LEFT JOIN tc_attendance a ON a.nickname = h.nickname
         ${whereSql}
         ORDER BY h.created_at DESC
         LIMIT ${lim} OFFSET ${(pg - 1) * lim}`,
      params
    );
    return { rows: rowsRes.rows, total, page: pg, limit: lim };
  } catch (err) {
    console.error('List attendance log error:', err.message);
    return { rows: [], total: 0, page: 1, limit: 50 };
  }
}

// Attendance breakdown for the stats page: weekly / monthly rollups (KST-bucketed,
// COUNT(DISTINCT nickname) so a user counts once per week/month) plus the users who
// attended within the range, ranked by claim count. dateFrom/dateTo are ISO strings.
async function getAttendanceBreakdown(dateFrom, dateTo, { topLimit = 50 } = {}) {
  const from = dateFrom || new Date(Date.now() - 29 * 24 * 60 * 60 * 1000).toISOString();
  const to = dateTo || new Date().toISOString();
  const lim = Math.max(1, Math.min(parseInt(topLimit, 10) || 50, 200));
  try {
    // DATE_TRUNC on the KST wall clock, re-attaching Seoul tz so pg returns the
    // correct UTC instant (same trick as getDetailedAdminStats' kstBucketExpr).
    const seriesSql = (unit) => `
      SELECT (DATE_TRUNC('${unit}', (created_at) AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Seoul')) AT TIME ZONE 'Asia/Seoul' AS bucket_time,
             COUNT(DISTINCT nickname) AS unique_claims,
             COUNT(*) AS total_claims,
             COUNT(*) FILTER (WHERE description = 'day_7') AS finales,
             COALESCE(SUM(gold_delta), 0) AS gold
      FROM tc_gold_history
      WHERE source = 'attendance'
        AND created_at >= $1 AND created_at < $2
      GROUP BY 1 ORDER BY 1`;
    const [weekly, monthly, topUsers] = await Promise.all([
      pool.query(seriesSql('week'), [from, to]),
      pool.query(seriesSql('month'), [from, to]),
      pool.query(`
        SELECT h.nickname,
               COUNT(*) AS claims,
               COUNT(*) FILTER (WHERE h.description = 'day_7') AS finales,
               COALESCE(SUM(h.gold_delta), 0) AS gold,
               MAX(h.created_at) AS last_claim,
               COALESCE(a.current_streak, 0) AS current_streak,
               COALESCE(a.total_claims, 0) AS total_claims
        FROM tc_gold_history h
        LEFT JOIN tc_attendance a ON a.nickname = h.nickname
        WHERE h.source = 'attendance'
          AND h.created_at >= $1 AND h.created_at < $2
        GROUP BY h.nickname, a.current_streak, a.total_claims
        ORDER BY claims DESC, last_claim DESC
        LIMIT ${lim}`, [from, to]),
    ]);
    return { weekly: weekly.rows, monthly: monthly.rows, topUsers: topUsers.rows };
  } catch (err) {
    console.error('Get attendance breakdown error:', err.message);
    return { weekly: [], monthly: [], topUsers: [] };
  }
}

// Single-user attendance summary for the user detail page.
async function getAttendanceForNickname(nickname) {
  try {
    const r = await pool.query(
      `SELECT
         a.last_claim_date,
         COALESCE(a.current_streak, 0)::int AS current_streak,
         COALESCE(a.total_claims, 0)::int AS total_claims,
         a.updated_at,
         (a.last_claim_date = DATE(timezone('Asia/Seoul', NOW())))::bool
           AS claimed_today
       FROM tc_attendance a
       WHERE a.nickname = $1`,
      [nickname]
    );
    if (r.rows.length === 0) {
      return { exists: false, currentStreak: 0, totalClaims: 0,
        lastClaimDate: null, claimedToday: false };
    }
    const row = r.rows[0];
    return {
      exists: true,
      currentStreak: row.current_streak,
      totalClaims: row.total_claims,
      lastClaimDate: row.last_claim_date,
      claimedToday: row.claimed_today === true,
      updatedAt: row.updated_at,
    };
  } catch (err) {
    console.error('Get attendance for nickname error:', err.message);
    return { exists: false, currentStreak: 0, totalClaims: 0,
      lastClaimDate: null, claimedToday: false };
  }
}

// Paginated attempt log with optional filters + global outcome summary.
async function getIapAttempts({ outcome, environment, platform, search, page = 1, limit = 50 } = {}) {
  try {
    const where = [];
    const params = [];
    if (outcome) { params.push(outcome); where.push(`outcome = $${params.length}`); }
    if (environment === 'sandbox' || environment === 'production') {
      params.push(environment); where.push(`environment = $${params.length}`);
    }
    if (platform === 'ios' || platform === 'android') {
      params.push(platform); where.push(`platform = $${params.length}`);
    }
    if (search) {
      params.push(`%${search}%`);
      where.push(`(nickname ILIKE $${params.length} OR product_id ILIKE $${params.length} OR reason ILIKE $${params.length} OR transaction_id ILIKE $${params.length})`);
    }
    const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';

    const countRes = await pool.query(`SELECT COUNT(*) FROM tc_iap_attempts ${whereSql}`, params);
    const total = parseInt(countRes.rows[0].count, 10) || 0;

    const lim = Math.max(1, Math.min(parseInt(limit, 10) || 50, 200));
    const pg = Math.max(1, parseInt(page, 10) || 1);
    const offset = (pg - 1) * lim;
    const rowsRes = await pool.query(
      `SELECT id, nickname, platform, product_id, environment, outcome, reason,
              transaction_id, created_at
         FROM tc_iap_attempts ${whereSql}
        ORDER BY created_at DESC, id DESC
        LIMIT ${lim} OFFSET ${offset}`,
      params
    );

    const sumRes = await pool.query(`
      SELECT
        COUNT(*)                                                   AS total,
        COUNT(*) FILTER (WHERE outcome = 'granted')                AS granted_cnt,
        COUNT(*) FILTER (WHERE outcome = 'already_granted')        AS dup_cnt,
        COUNT(*) FILTER (WHERE outcome = 'rejected')               AS rejected_cnt,
        COUNT(*) FILTER (WHERE outcome = 'error')                  AS error_cnt,
        COUNT(*) FILTER (WHERE outcome = 'flagged')                AS flagged_cnt
      FROM tc_iap_attempts`);
    const s = sumRes.rows[0] || {};
    return {
      rows: rowsRes.rows,
      total,
      page: pg,
      limit: lim,
      summary: {
        total: parseInt(s.total, 10) || 0,
        granted: parseInt(s.granted_cnt, 10) || 0,
        dup: parseInt(s.dup_cnt, 10) || 0,
        rejected: parseInt(s.rejected_cnt, 10) || 0,
        error: parseInt(s.error_cnt, 10) || 0,
        flagged: parseInt(s.flagged_cnt, 10) || 0,
      },
    };
  } catch (err) {
    console.error('Get IAP attempts error:', err);
    return { rows: [], total: 0, page: 1, limit: 50, summary: { total: 0, granted: 0, dup: 0, rejected: 0, error: 0, flagged: 0 } };
  }
}

async function getIapAttemptById(id) {
  try {
    const r = await pool.query(`SELECT * FROM tc_iap_attempts WHERE id = $1`, [id]);
    return r.rows[0] || null;
  } catch (err) {
    console.error('Get IAP attempt by id error:', err);
    return null;
  }
}

// Full single receipt incl. raw_payload — for the admin detail/audit view.
async function getIapReceiptById(id) {
  try {
    const r = await pool.query(`SELECT * FROM tc_iap_receipts WHERE id = $1`, [id]);
    return r.rows[0] || null;
  } catch (err) {
    console.error('Get IAP receipt by id error:', err);
    return null;
  }
}

// Shared refund core. `rec` is a FOR UPDATE-locked tc_iap_receipts row.
// Money is NOT moved here — Apple/Google decide/execute the cash refund. This
// only claws back the gold we granted and records who/when/why.
//
// autoMode (store webhook/poll triggered): if the user already spent the gold
// we DON'T silently go negative — we park the row as 'refund_failed' so it
// surfaces in the admin triage queue. allowNegative (admin "force") overrides
// and pulls the balance negative on purpose (use when the store already
// refunded the cash and eating the gold loss is worse).
async function _refundCore(client, rec, { allowNegative, autoMode, source, reason, actor }) {
  const id = rec.id;
  const granted = parseInt(rec.gold_granted, 10) || 0;

  const userRes = await client.query(
    `SELECT gold FROM tc_users WHERE nickname = $1 FOR UPDATE`, [rec.nickname]
  );
  const userExists = userRes.rows.length > 0;
  const currentGold = userExists ? (parseInt(userRes.rows[0].gold, 10) || 0) : 0;

  if (userExists && currentGold < granted && !allowNegative) {
    if (!autoMode) {
      // Manual click: keep the receipt as-is, let admin decide (force or skip).
      await client.query('ROLLBACK');
      return { success: false, reason: 'insufficient', currentGold, granted, nickname: rec.nickname };
    }
    // Auto path: park in the triage queue, do NOT touch the balance.
    await client.query(
      `UPDATE tc_iap_receipts
          SET status = 'refund_failed', refund_detected_at = CURRENT_TIMESTAMP,
              refund_source = $2, refund_reason = $3, refund_admin = $4
        WHERE id = $1`,
      [id, source || null, (reason || 'insufficient_balance').slice(0, 160), actor || null]
    );
    await client.query('COMMIT');
    return { success: true, marked: 'refund_failed', currentGold, granted, nickname: rec.nickname };
  }

  let newGold = null;
  if (userExists) {
    const upd = await client.query(
      `UPDATE tc_users SET gold = gold - $2 WHERE nickname = $1 RETURNING gold`,
      [rec.nickname, granted]
    );
    newGold = upd.rows[0] ? upd.rows[0].gold : null;
    await client.query(
      `INSERT INTO tc_gold_history (nickname, gold_delta, source, title, description)
       VALUES ($1, $2, 'iap_refund', 'iap_refund', $3)`,
      [rec.nickname, -granted, rec.product_id]
    );
  }
  await client.query(
    `UPDATE tc_iap_receipts
        SET status = 'refunded', refunded_at = CURRENT_TIMESTAMP,
            refund_detected_at = COALESCE(refund_detected_at, CURRENT_TIMESTAMP),
            refund_source = COALESCE(refund_source, $2), refund_reason = COALESCE(refund_reason, $3),
            refund_admin = $4
      WHERE id = $1`,
    [id, source || null, reason ? String(reason).slice(0, 160) : null, actor || null]
  );
  await client.query('COMMIT');
  return { success: true, newGold, granted, nickname: rec.nickname, userExists };
}

// Admin manual refund (by receipt id). Accepts 'granted' rows and, with
// allowNegative, 'refund_failed' rows from the triage queue (force-minus).
async function refundIapReceipt({ id, adminUser, allowNegative = false }) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const recRes = await client.query(
      `SELECT id, nickname, product_id, gold_granted, status
         FROM tc_iap_receipts WHERE id = $1 FOR UPDATE`,
      [id]
    );
    if (recRes.rows.length === 0) {
      await client.query('ROLLBACK');
      return { success: false, reason: 'not_found' };
    }
    const rec = recRes.rows[0];
    if (rec.status === 'refunded') {
      await client.query('ROLLBACK');
      return { success: false, reason: 'already_refunded' };
    }
    if (rec.status === 'refund_failed' && !allowNegative) {
      // Triage rows can only be cleared via the explicit force-minus action.
      await client.query('ROLLBACK');
      return { success: false, reason: 'needs_force' };
    }
    return await _refundCore(client, rec, {
      allowNegative, autoMode: false, source: 'manual',
      reason: rec.status === 'refund_failed' ? 'admin_force' : 'admin_manual',
      actor: adminUser || 'admin',
    });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Refund IAP receipt error:', err);
    return { success: false, reason: 'error', message: err.message };
  } finally {
    client.release();
  }
}

// Store-triggered auto refund (Apple webhook / Google voided-purchases poll),
// keyed by the store transaction id. Idempotent: re-delivery of the same
// refund is a no-op once the row is refunded/refund_failed.
async function autoRefundByTransaction({ transactionId, source, reason, onRefunded }) {
  if (!transactionId) return { success: false, reason: 'missing_transaction_id' };
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const recRes = await client.query(
      `SELECT id, nickname, product_id, gold_granted, status
         FROM tc_iap_receipts WHERE transaction_id = $1 FOR UPDATE`,
      [String(transactionId)]
    );
    if (recRes.rows.length === 0) {
      await client.query('ROLLBACK');
      // Store confirmed a refund for a transaction we have no grant for (e.g.
      // a purchase whose verify failed, or an id-format mismatch). Surface in
      // the 검증로그 once so ops can investigate — but DON'T re-log each
      // time the Google Voided poll hits the same txn inside its 1h overlap
      // window (which is structurally required to avoid missing voids during
      // downtime). One alert per txn is enough.
      try {
        const dup = await pool.query(
          `SELECT 1 FROM tc_iap_attempts
             WHERE transaction_id = $1
               AND reason LIKE 'refund_unmatched:%'
             LIMIT 1`,
          [String(transactionId)]
        );
        if (dup.rows.length === 0) {
          await logIapAttempt({
            nickname: null,
            platform: source === 'apple' ? 'ios' : (source === 'google' ? 'android' : null),
            productId: null,
            environment: null,
            outcome: 'error',
            reason: `refund_unmatched:${source || 'store'}`,
            transactionId: String(transactionId),
            rawPayload: { reason },
          });
        }
      } catch (_) { /* dedup check is best-effort; never block refund path */ }
      return { success: false, reason: 'receipt_not_found' };
    }
    const rec = recRes.rows[0];
    if (rec.status === 'refunded' || rec.status === 'refund_failed') {
      await client.query('ROLLBACK');
      return { success: true, idempotent: true, status: rec.status };
    }
    const refundResult = await _refundCore(client, rec, {
      allowNegative: false, autoMode: true,
      source: source || 'store', reason: reason || 'store_refund',
      actor: `system:${source || 'store'}`,
    });
    // Newly applied refund (idempotent already-refunded case returned above).
    // Fire-and-forget admin notify; never let it break the refund result.
    if (refundResult && refundResult.success && typeof onRefunded === 'function') {
      try {
        await onRefunded({
          nickname: rec.nickname,
          productId: rec.product_id,
          goldGranted: rec.gold_granted,
          source: source || 'store',
        });
      } catch (_) { /* notify is best-effort */ }
    }
    return refundResult;
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Auto refund error:', err);
    return { success: false, reason: 'error', message: err.message };
  } finally {
    client.release();
  }
}

// Triage queue: store refunded the cash but we couldn't claw back gold.
async function getRefundIssues({ page = 1, limit = 50 } = {}) {
  try {
    const lim = Math.max(1, Math.min(parseInt(limit, 10) || 50, 200));
    const pg = Math.max(1, parseInt(page, 10) || 1);
    const offset = (pg - 1) * lim;
    const countRes = await pool.query(`SELECT COUNT(*) FROM tc_iap_receipts WHERE status = 'refund_failed'`);
    const total = parseInt(countRes.rows[0].count, 10) || 0;
    const rows = await pool.query(
      `SELECT id, nickname, product_id, platform, environment, gold_granted,
              transaction_id, refund_source, refund_reason, refund_detected_at, verified_at
         FROM tc_iap_receipts
        WHERE status = 'refund_failed'
        ORDER BY refund_detected_at DESC NULLS LAST, id DESC
        LIMIT ${lim} OFFSET ${offset}`
    );
    return { rows: rows.rows, total, page: pg, limit: lim };
  } catch (err) {
    console.error('Get refund issues error:', err);
    return { rows: [], total: 0, page: 1, limit: 50 };
  }
}

// ---------------------------------------------------------------------------
// Bank-transfer deposits (web shop)
// ---------------------------------------------------------------------------

async function createBankDeposit({ nickname, productId, priceKrw, goldAmount, depositor }) {
  try {
    const res = await pool.query(
      `INSERT INTO tc_bank_deposits
         (nickname, product_id, price_krw, gold_amount, depositor)
       VALUES ($1, $2, $3, $4, $5) RETURNING id`,
      [nickname, productId, priceKrw, goldAmount, depositor]
    );
    return { success: true, id: res.rows[0].id };
  } catch (err) {
    console.error('createBankDeposit error:', err);
    return { success: false, message: err.message };
  }
}

/** Open claims for one player — used to refuse a duplicate while one is queued. */
async function countPendingBankDeposits(nickname) {
  try {
    const res = await pool.query(
      `SELECT COUNT(*)::int AS n FROM tc_bank_deposits
        WHERE nickname = $1 AND status = 'pending'`,
      [nickname]
    );
    return res.rows[0].n;
  } catch (err) {
    console.error('countPendingBankDeposits error:', err);
    return 0;
  }
}

async function getBankDeposits({ status = 'pending', limit = 100 } = {}) {
  try {
    const all = status === 'all';
    const res = await pool.query(
      `SELECT d.*, u.gold AS current_gold
         FROM tc_bank_deposits d
         LEFT JOIN tc_users u ON u.nickname = d.nickname
        ${all ? '' : 'WHERE d.status = $2'}
        ORDER BY (d.status = 'pending') DESC, d.created_at DESC
        LIMIT $1`,
      all ? [limit] : [limit, status]
    );
    return res.rows;
  } catch (err) {
    console.error('getBankDeposits error:', err);
    return [];
  }
}

async function countPendingBankDepositsAll() {
  try {
    const res = await pool.query(
      `SELECT COUNT(*)::int AS n FROM tc_bank_deposits WHERE status = 'pending'`
    );
    return res.rows[0].n;
  } catch {
    return 0;
  }
}

/**
 * Approve a claim and pay out, in one transaction.
 *
 * The status flip is guarded on `status = 'pending'` inside the same
 * transaction as the credit, so two admins clicking Approve at the same
 * moment cannot pay the same claim twice — the second UPDATE matches no row
 * and the whole thing rolls back.
 *
 * The history row is deliberately NOT 'admin_adjust'. A confirmed bank
 * transfer is a purchase the player made, and their gold history should say
 * so rather than reading like a hand-out.
 */
async function approveBankDeposit(id, adminActor = 'admin') {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const claim = await client.query(
      `UPDATE tc_bank_deposits
          SET status = 'approved', handled_by = $2, handled_at = NOW()
        WHERE id = $1 AND status = 'pending'
        RETURNING nickname, product_id, gold_amount, price_krw`,
      [id, adminActor]
    );
    if (claim.rows.length === 0) {
      await client.query('ROLLBACK');
      return { success: false, message: 'already_handled' };
    }
    const { nickname, product_id: productId, gold_amount: gold } = claim.rows[0];

    const paid = await client.query(
      `UPDATE tc_users SET gold = gold + $2 WHERE nickname = $1 RETURNING gold`,
      [nickname, gold]
    );
    if (paid.rows.length === 0) {
      await client.query('ROLLBACK');
      return { success: false, message: 'user_not_found' };
    }

    await client.query(
      `INSERT INTO tc_gold_history (nickname, gold_delta, source, title, description)
       VALUES ($1, $2, 'bank_deposit', 'bank_deposit_grant', $3)`,
      [nickname, gold, productId]
    );
    await client.query('COMMIT');
    return { success: true, nickname, gold, newGold: paid.rows[0].gold };
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('approveBankDeposit error:', err);
    return { success: false, message: err.message };
  } finally {
    client.release();
  }
}

async function rejectBankDeposit(id, adminActor = 'admin', note = '') {
  try {
    const res = await pool.query(
      `UPDATE tc_bank_deposits
          SET status = 'rejected', handled_by = $2, handled_at = NOW(),
              admin_note = $3
        WHERE id = $1 AND status = 'pending'
        RETURNING nickname`,
      [id, adminActor, String(note || '').slice(0, 500)]
    );
    if (res.rows.length === 0) return { success: false, message: 'already_handled' };
    return { success: true, nickname: res.rows[0].nickname };
  } catch (err) {
    console.error('rejectBankDeposit error:', err);
    return { success: false, message: err.message };
  }
}

module.exports = {
  initDatabase,
  registerUser,
  loginUser,
  checkNickname,
  deleteUser,
  blockUser,
  unblockUser,
  getBlockedUsers,
  reportUser,
  addFriend,
  getFriends,
  getFriendsWithLastSeen,
  getAdminDmPartners,
  getAdminDmThread,
  touchLastSeen,
  setProfilePrivateHidePhoto,
  unequipCategory,
  setCustomTitle,
  clearCustomTitle,
  setCustomTitleByAdmin,
  setFeatureEnabled,
  getPendingFriendRequests,
  getPendingFriendRequestsDetailed,
  getSentFriendRequests,
  acceptFriendRequest,
  rejectFriendRequest,
  cancelFriendRequest,
  removeFriend,
  saveMatchResult,
  saveMatchResultWithStats,
  updateUserStats,
  getUserProfile,
  loadTitleTranslations,
  getRecentMatches,
  MATCH_HISTORY_MAX_DEPTH,
  getWallet,
  getGoldHistory,
  getAdminGoldHistory,
  getAdminPurchaseHistory,
  getAdminUserInventory,
  getShopItemHolderCounts,
  isKstNight,
  MARKETING_CONFIRM_INTERVAL,
  isMarketingConfirmDue,
  confirmMarketingConsent,
  getMarketingConfirmStats,
  getAllFcmTokenRows,
  markFcmTokensInvalid,
  getFcmTokenStats,
  getMarketingAudience,
  setMarketingConsent,
  getMarketingConsentState,
  createPushCampaign,
  listPushCampaigns,
  getPushCampaign,
  deletePushCampaign,
  reserveCampaignRecipients,
  openCampaignForClaims,
  recordCampaignSend,
  claimPushCampaign,
  sendMail,
  getMailbox,
  getMailPushTokens,
  getUnreadMailCount,
  markMailRead,
  claimMail,
  deleteMailForUser,
  purgeOldMail,
  MAIL_RETENTION_DAYS,
  listMail,
  getMailDetail,
  deleteMail,
  getCampaignRecipients,
  getShopPurchaseLog,
  getShopPurchaseLogSummary,
  adminExtendUserItem,
  adminRevokeUserItem,
  getShopItems,
  getUserItems,
  sweepExpiredCosmetics,
  grantItemToUser,
  buyItem,
  equipItem,
  useItem,
  changeNickname,
  incrementLeaveCount,
  logMidGameLeave,
  getReportedNicknames,
  setRankedBan,
  getRankedBan,
  setChatBan,
  getChatBan,
  setAdminMemo,
  adminClearProfilePhoto,
  getReportedPhotoKeys,
  getReportedTitles,
  isPhotoKeyReported,
  listActiveProfilePhotos,
  recordPhotoRejection,
  getPhotoRejections,
  deletePhotoRejection,
  getActiveSeason,
  createSeason,
  getSeasons,
  getCurrentSeasonRankings,
  getSeasonRankings,
  resetSeasonStats,
  grantSeasonRewards,
  getSeasonRewardConfig,
  saveSeasonRewardConfig,
  clearSeasonRewardConfig,
  getSeasonRewardsGranted,
  getSeasonRewardAudit,
  SEASON_GAME_TYPES,
  submitInquiry,
  getUserInquiries,
  markInquiriesRead,
  getInquiries,
  getInquiryById,
  resolveInquiry,
  getReports,
  getReportGroup,
  updateReportGroupStatus,
  getUsers,
  getAppVersionsInUse,
  getUserDetail,
  getDashboardStats,
  getTodayMatches,
  getTodayPayments,
  getDashboardActivityTopPlayers,
  getAdminRecentMatches,
  getDetailedAdminStats,
  getRankings,
  verifyAdmin,
  isUserAdmin,
  getAllShopItemsAdmin,
  addShopItem,
  updateShopItem,
  deleteShopItem,
  getShopItemById,
  loginSocial,
  registerSocial,
  linkSocial,
  unlinkSocial,
  getLinkedSocial,
  updateDeviceInfo,
  parseTzOffsetMinutes,
  setPushEnabled,
  setAttendancePush,
  setPushFriendInvite,
  setUserAdmin,
  setAdminAlertSettings,
  getAdminPushRecipients,
  getConfig,
  getLocalizedConfig,
  updateConfig,
  adminAdjustGold,
  redeemCoupon,
  upsertCoupon,
  getCouponByCode,
  listCoupons,
  getCouponRedemptions,
  deleteCoupon,
  normalizeCouponCode,
  createBankDeposit,
  countPendingBankDeposits,
  countPendingBankDepositsAll,
  getBankDeposits,
  approveBankDeposit,
  rejectBankDeposit,
  adminAdjustExp,
  getVisualCatalog,
  claimAdReward,
  searchUsers,
  sendDm,
  getDmHistory,
  markDmRead,
  getDmConversations,
  getTotalUnreadDmCount,
  getSKRecentMatches,
  saveSKMatchResult,
  saveSKMatchResultWithStats,
  updateSKUserStats,
  getSKRankings,
  getCurrentSKSeasonRankings,
  getSKSeasonRankings,
  saveLLMatchResultWithStats,
  saveMightyMatchResultWithStats,
  getMightyRankings,
  getCurrentMightySeasonRankings,
  getMightySeasonRankings,
  getPublishedNotices,
  getNotices,
  getNoticeById,
  createNotice,
  updateNotice,
  deleteNotice,
  insertMaintenanceHistory,
  getMaintenanceHistory,
  getBroadcastFcmTokens,
  insertPushHistory,
  updatePushHistoryCounts,
  startPushLog,
  finishPushLog,
  markPushOpened,
  getUnifiedPushHistory,
  getPushHistoryCounts,
  purgePushLogs,
  PUSH_LOG_RETENTION_DAYS,
  getPushHistory,
  insertPushRecipients,
  getPushHistoryDetail,
  updateCardViewPref,
  getActiveGoldProducts,
  getGoldProductByProductId,
  grantIapGold,
  getAllGoldProductsAdmin,
  getGoldProductById,
  addGoldProduct,
  updateGoldProduct,
  deleteGoldProduct,
  getIapReceipts,
  getIapReceiptById,
  refundIapReceipt,
  autoRefundByTransaction,
  getRefundIssues,
  logIapAttempt,
  getIapAttempts,
  getConsumptionSnapshot,
  recordConsumptionRequest,
  listConsumptionRequests,
  getAttendanceState,
  claimAttendance,
  getAttendanceDashboardStats,
  nextAttendanceStreak,
  getAttendancePushTargets,
  claimAttendancePush,
  ATTENDANCE_PUSH_HOUR,
  ATTENDANCE_PUSH_IGNORE_LIMIT,
  ATTENDANCE_PUSH_MUTE_DAYS,
  listAttendanceLog,
  getAttendanceBreakdown,
  getAttendanceForNickname,
  getIapAttemptById,
  pool,
};
