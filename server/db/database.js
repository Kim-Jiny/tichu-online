const { Pool } = require('pg');
const bcrypt = require('bcrypt');

const SALT_ROUNDS = 10;

// PostgreSQL connection pool
const isProduction = process.env.NODE_ENV === 'production';
const DEFAULT_LOCAL_URL = 'postgresql://jiny@localhost:5432/minigame';
const pool = new Pool({
  connectionString: process.env.DATABASE_URL || DEFAULT_LOCAL_URL,
  ssl: isProduction ? { rejectUnauthorized: false } : false,
});

// Initialize database tables (tc_ prefix for tichu)
async function initDatabase() {
  const client = await pool.connect();
  try {
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

    // User stats columns
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

    // Device info columns
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS fcm_token TEXT`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS push_enabled BOOLEAN DEFAULT true`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS push_friend_invite BOOLEAN DEFAULT true`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS is_admin BOOLEAN DEFAULT false`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS push_admin_inquiry BOOLEAN DEFAULT true`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS push_admin_report BOOLEAN DEFAULT true`);
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
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    // Add sale_start/sale_end columns if not exists (for existing tables)
    await client.query(`ALTER TABLE tc_shop_items ADD COLUMN IF NOT EXISTS sale_start TIMESTAMP`);
    await client.query(`ALTER TABLE tc_shop_items ADD COLUMN IF NOT EXISTS sale_end TIMESTAMP`);

    // Add name_ko/name_en/name_de columns; keep original 'name' column for rollback safety
    await client.query(`ALTER TABLE tc_shop_items ADD COLUMN IF NOT EXISTS name_ko VARCHAR(100) NOT NULL DEFAULT ''`);
    await client.query(`ALTER TABLE tc_shop_items ADD COLUMN IF NOT EXISTS name_en VARCHAR(100) NOT NULL DEFAULT ''`);
    await client.query(`ALTER TABLE tc_shop_items ADD COLUMN IF NOT EXISTS name_de VARCHAR(100) NOT NULL DEFAULT ''`);
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
        ('top_card_counter_7d', '티츄 탑패 카운터(7일)', '티츄 탑패 카운터(7일)', 'Tichu Top Card Counter (7d)', 'Tichu-Trumpfzähler (7T)', 'utility', 1000, FALSE, FALSE, 7, TRUE, NULL, NULL, '{}'::jsonb),
        ('stats_reset', '전적 초기화권', '전적 초기화권', 'Stats Reset', 'Statistik-Reset', 'utility', 2000, FALSE, TRUE, NULL, TRUE, 'stats_reset', NULL, '{}'::jsonb),
        ('season_stats_reset', '랭킹전적 초기화권', '랭킹전적 초기화권', 'Ranked Stats Reset', 'Ranglistenstatistik-Reset', 'utility', 1000, FALSE, TRUE, NULL, TRUE, 'season_stats_reset', NULL, '{}'::jsonb),
        ('banner_season_gold', '시즌 골드 배너', '시즌 골드 배너', 'Season Gold Banner', 'Saison-Gold-Banner', 'banner', 0, TRUE, FALSE, 30, FALSE, NULL, NULL, '{}'::jsonb),
        ('banner_season_silver', '시즌 실버 배너', '시즌 실버 배너', 'Season Silver Banner', 'Saison-Silber-Banner', 'banner', 0, TRUE, FALSE, 30, FALSE, NULL, NULL, '{}'::jsonb),
        ('banner_season_bronze', '시즌 브론즈 배너', '시즌 브론즈 배너', 'Season Bronze Banner', 'Saison-Bronze-Banner', 'banner', 0, TRUE, FALSE, 30, FALSE, NULL, NULL, '{}'::jsonb)
      ON CONFLICT (item_key) DO UPDATE SET
        name = EXCLUDED.name_ko,
        name_ko = EXCLUDED.name_ko,
        name_en = EXCLUDED.name_en,
        name_de = EXCLUDED.name_de,
        price = EXCLUDED.price,
        is_permanent = EXCLUDED.is_permanent,
        duration_days = EXCLUDED.duration_days
      `
    );

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

    // LL user stats columns
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS ll_total_games INT DEFAULT 0`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS ll_wins INT DEFAULT 0`);
    await client.query(`ALTER TABLE tc_users ADD COLUMN IF NOT EXISTS ll_losses INT DEFAULT 0`);

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

    console.log('Database initialized (tc_ tables)');
  } catch (err) {
    console.error('Database initialization error:', err);
  } finally {
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
      'SELECT id, password_hash, nickname, is_admin, is_deleted, push_enabled, push_friend_invite, push_admin_inquiry, push_admin_report FROM tc_users WHERE username = $1',
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
      'UPDATE tc_users SET last_login = CURRENT_TIMESTAMP WHERE id = $1',
      [user.id]
    );

    return {
      success: true,
      userId: user.id,
      nickname: user.nickname,
      isAdmin: user.is_admin === true,
      pushEnabled: user.push_enabled !== false,
      pushFriendInvite: user.push_friend_invite !== false,
      pushAdminInquiry: user.push_admin_inquiry !== false,
      pushAdminReport: user.push_admin_report !== false,
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
    await client.query('DELETE FROM tc_blocked_users WHERE blocker_nickname = $1 OR blocked_nickname = $1', [nickname]);
    await client.query('DELETE FROM tc_friends WHERE user_nickname = $1 OR friend_nickname = $1', [nickname]);
    await client.query('DELETE FROM tc_dm_messages WHERE sender_nickname = $1 OR receiver_nickname = $1', [nickname]);
    await client.query('DELETE FROM tc_user_equips WHERE nickname = $1', [nickname]);
    await client.query('DELETE FROM tc_user_items WHERE nickname = $1', [nickname]);
    await client.query('DELETE FROM tc_ad_rewards WHERE nickname = $1', [nickname]);
    await client.query('DELETE FROM tc_season_rewards WHERE nickname = $1', [nickname]);

    // Rename nickname in user record and mark deleted
    await client.query(
      `UPDATE tc_users SET nickname = $2, is_deleted = true, deleted_at = NOW(),
       username = SUBSTRING('del_' || username || $3 FROM 1 FOR 50),
       password_hash = '',
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
    return { success: true, messageKey: 'db_account_deleted_success' };
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
async function reportUser(reporterNickname, reportedNickname, reason, roomId, chatContext = []) {
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
    await client.query(
      'INSERT INTO tc_reports (reporter_nickname, reported_nickname, reason, room_id, chat_context) VALUES ($1, $2, $3, $4, $5)',
      [reporterNickname, reportedNickname, reason, roomId, chatContextJson]
    );
    return { success: true, messageKey: 'db_report_success' };
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
             level = GREATEST(1, ((exp_total + $6) / 100) + 1)
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
             level = GREATEST(1, ((exp_total + $6) / 100) + 1)
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
               level = GREATEST(1, ((exp_total + $2) / 100) + 1)
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
               level = GREATEST(1, ((exp_total + $6) / 100) + 1)
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
        const expChange = player.isRanked ? 8 : 5;
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
               level = GREATEST(1, ((exp_total + $6) / 100) + 1)
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

// Get user profile
async function getUserProfile(nickname) {
  const client = await pool.connect();
  try {
    const result = await client.query(
      `SELECT u.nickname, u.total_games, u.wins, u.losses, u.rating, u.gold, u.leave_count,
              u.season_rating, u.season_games, u.season_wins, u.season_losses,
              u.exp_total, u.level, u.created_at,
              u.sk_total_games, u.sk_wins, u.sk_losses, u.sk_rating,
              u.sk_season_rating, u.sk_season_games, u.sk_season_wins, u.sk_season_losses,
              u.ll_total_games, u.ll_wins, u.ll_losses,
              e.banner_key, e.theme_key, e.title_key,
              si.name_ko AS title_name
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

    // Report count in last 6 months
    const reportRes = await client.query(
      `SELECT COUNT(*) FROM tc_reports
       WHERE reported_nickname = $1 AND created_at >= NOW() - INTERVAL '6 months'`,
      [nickname]
    );
    const reportCount = parseInt(reportRes.rows[0].count, 10) || 0;

    // Check active top card counter item
    const topCardRes = await client.query(
      `SELECT 1 FROM tc_user_items
       WHERE nickname = $1 AND item_key = 'top_card_counter_7d'
         AND (expires_at IS NULL OR expires_at >= NOW()) LIMIT 1`,
      [nickname]
    );
    const hasTopCardCounter = topCardRes.rows.length > 0;

    const skWinRate = user.sk_total_games > 0
      ? Math.round((user.sk_wins / user.sk_total_games) * 100)
      : 0;
    const skSeasonWinRate = user.sk_season_games > 0
      ? Math.round((user.sk_season_wins / user.sk_season_games) * 100)
      : 0;
    const llWinRate = user.ll_total_games > 0
      ? Math.round((user.ll_wins / user.ll_total_games) * 100)
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
      titleKey: user.title_key,
      titleName: user.title_name || null,
      createdAt: user.created_at,
      hasTopCardCounter,
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
    };
  } catch (err) {
    console.error('Get user profile error:', err);
    return null;
  } finally {
    client.release();
  }
}

// Get recent matches for a player
async function getRecentMatches(nickname, limit = 5) {
  const client = await pool.connect();
  try {
    // Tichu matches
    const tichuResult = await client.query(
      `SELECT *, 'tichu'::text as game_type FROM tc_match_history
       WHERE player_a1 = $1 OR player_a2 = $1 OR player_b1 = $1 OR player_b2 = $1
       ORDER BY created_at DESC
       LIMIT $2`,
      [nickname, limit]
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
    const skResult = await client.query(
      `SELECT h.*, p.score as my_score, p.rank as my_rank, p.is_winner as my_winner
       FROM tc_sk_match_history h
       JOIN tc_sk_match_players p ON p.match_id = h.id AND p.nickname = $1
       ORDER BY h.created_at DESC
       LIMIT $2`,
      [nickname, limit]
    );
    const skMatches = [];
    for (const row of skResult.rows) {
      const playersRes = await client.query(
        `SELECT nickname, score, rank, is_winner, is_bot FROM tc_sk_match_players WHERE match_id = $1 ORDER BY rank`,
        [row.id]
      );
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
        players: playersRes.rows.map(p => ({
          nickname: p.nickname,
          score: p.score,
          rank: p.rank,
          isWinner: p.is_winner,
          isBot: p.is_bot,
        })),
        createdAt: row.created_at,
      });
    }

    // Love Letter matches
    const llResult = await client.query(
      `SELECT h.*, p.score as my_score, p.rank as my_rank, p.is_winner as my_winner
       FROM tc_ll_match_history h
       JOIN tc_ll_match_players p ON p.match_id = h.id AND p.nickname = $1
       ORDER BY h.created_at DESC
       LIMIT $2`,
      [nickname, limit]
    );
    const llMatches = [];
    for (const row of llResult.rows) {
      const playersRes = await client.query(
        `SELECT nickname, score, rank, is_winner, is_bot FROM tc_ll_match_players WHERE match_id = $1 ORDER BY rank`,
        [row.id]
      );
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
        players: playersRes.rows.map(p => ({
          nickname: p.nickname,
          score: p.score,
          rank: p.rank,
          isWinner: p.is_winner,
          isBot: p.is_bot,
        })),
        createdAt: row.created_at,
      });
    }

    // Merge and sort by date
    const all = [...tichuMatches, ...skMatches, ...llMatches];
    all.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
    return all.slice(0, limit);
  } catch (err) {
    console.error('Get recent matches error:', err);
    return [];
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

async function getGoldHistory(nickname, limit = 30) {
  const client = await pool.connect();
  try {
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
      ORDER BY history.created_at DESC
      LIMIT $2
      `,
      [nickname, limit]
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

async function getAdminGoldHistory(nickname, limit = 50) {
  return getGoldHistory(nickname, limit);
}

async function getAdminPurchaseHistory(nickname, limit = 30) {
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
      LIMIT $2
      `,
      [nickname, limit]
    );

    const rows = result.rows;
    const summary = rows.reduce((acc, row) => {
      acc.totalSpent += parseInt(row.price, 10) || 0;
      acc.totalPurchases += 1;
      if (row.is_permanent) acc.permanentCount += 1;
      if (!row.is_permanent) acc.temporaryCount += 1;
      if (row.is_active) acc.activeCount += 1;
      return acc;
    }, {
      totalSpent: 0,
      totalPurchases: 0,
      permanentCount: 0,
      temporaryCount: 0,
      activeCount: 0,
    });

    return {
      success: true,
      summary,
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
async function getShopItems() {
  const client = await pool.connect();
  try {
    const result = await client.query(
      `
      SELECT item_key, name_ko, name_ko AS name, name_en, name_de, category, price, is_season, is_permanent,
             duration_days, is_purchasable, effect_type, effect_value, metadata
      FROM tc_shop_items
      WHERE is_purchasable = TRUE AND is_season = FALSE
        AND (sale_start IS NULL OR sale_start <= NOW())
        AND (sale_end IS NULL OR sale_end >= NOW())
      ORDER BY category ASC, price ASC, name_ko ASC
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

async function cleanupExpiredItems(client, nickname) {
  await client.query(
    `
    DELETE FROM tc_user_items
    WHERE nickname = $1 AND expires_at IS NOT NULL AND expires_at < NOW()
    `,
    [nickname]
  );
}

// Inventory
async function getUserItems(nickname) {
  const client = await pool.connect();
  try {
    await cleanupExpiredItems(client, nickname);
    const result = await client.query(
      `
      SELECT ui.item_key, ui.acquired_at, ui.expires_at, ui.is_active,
             si.name_ko, si.name_ko AS name, si.name_en, si.name_de, si.category, si.is_season, si.is_permanent,
             si.duration_days, si.effect_type, si.effect_value, si.metadata
      FROM tc_user_items ui
      JOIN tc_shop_items si ON si.item_key = ui.item_key
      WHERE ui.nickname = $1
      ORDER BY ui.acquired_at DESC
      `,
      [nickname]
    );
    return { success: true, items: result.rows };
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

    // Prevent duplicate ownership / extend duration for temp items
    if (item.is_permanent) {
      const owned = await client.query(
        `SELECT 1 FROM tc_user_items WHERE nickname = $1 AND item_key = $2 LIMIT 1`,
        [nickname, itemKey]
      );
      if (owned.rows.length > 0) {
        await client.query('ROLLBACK');
        return { success: false, messageKey: 'db_item_already_owned' };
      }
    } else {
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
async function equipItem(nickname, itemKey) {
  const client = await pool.connect();
  try {
    await cleanupExpiredItems(client, nickname);
    const itemRes = await client.query(
      `SELECT category, name_ko FROM tc_shop_items WHERE item_key = $1`,
      [itemKey]
    );
    if (itemRes.rows.length === 0) {
      return { success: false, messageKey: 'db_item_not_found' };
    }
    const category = itemRes.rows[0].category;
    const itemName = itemRes.rows[0].name_ko;

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
    const allowedEffects = ['leave_count_reduce', 'stats_reset', 'season_stats_reset'];
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
    } else if (effectType === 'stats_reset') {
      await client.query(
        `UPDATE tc_users SET total_games = 0, wins = 0, losses = 0
         WHERE nickname = $1`,
        [nickname]
      );
    } else if (effectType === 'season_stats_reset') {
      await client.query(
        `UPDATE tc_users SET season_games = 0, season_wins = 0, season_losses = 0,
           sk_season_games = 0, sk_season_wins = 0, sk_season_losses = 0
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
    const result = await client.query(
      `INSERT INTO tc_seasons (name, start_at, end_at, status)
       VALUES ($1, $2, $3, 'active')
       RETURNING id, name, start_at, end_at, status`,
      [name, startAt, endAt]
    );
    return result.rows[0];
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
           sk_season_losses = 0`
    );
    return { success: true };
  } catch (err) {
    console.error('Reset season stats error:', err);
    return { success: false };
  } finally {
    client.release();
  }
}

// Grant season rewards (top3 + banners + gold)
async function grantSeasonRewards(seasonId) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const seasonRes = await client.query(
      `SELECT id, status FROM tc_seasons WHERE id = $1`,
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
      LIMIT 3
      `
    );
    const top = topRes.rows;
    const rewards = [
      { rank: 1, gold: 1000, banner: 'banner_season_gold' },
      { rank: 2, gold: 500, banner: 'banner_season_silver' },
      { rank: 3, gold: 200, banner: 'banner_season_bronze' },
    ];

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

    for (let i = 0; i < rewards.length; i++) {
      const user = top[i];
      if (!user) continue;
      const reward = rewards[i];

      await client.query(
        `UPDATE tc_users SET gold = gold + $2 WHERE nickname = $1`,
        [user.nickname, reward.gold]
      );

      await client.query(
        `INSERT INTO tc_user_items (nickname, item_key, expires_at, is_active, source)
         VALUES ($1, $2, NOW() + INTERVAL '30 days', FALSE, 'season')`,
        [user.nickname, reward.banner]
      );

      await client.query(
        `INSERT INTO tc_season_rewards (season_id, nickname, rank, gold_reward, banner_key)
         VALUES ($1, $2, $3, $4, $5)`,
        [seasonId, user.nickname, reward.rank, reward.gold, reward.banner]
      );
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

// Get users with search and pagination
async function getUsers(search = '', page = 1, limit = 20, options = {}) {
  const client = await pool.connect();
  try {
    const offset = (page - 1) * limit;
    const conditions = [];
    const countParams = [];
    let paramIdx = 1;

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
      conditions.push(`total_games >= $${paramIdx}`);
      countParams.push(parseInt(options.minGames));
      paramIdx++;
    }
    if (options.minLeaves) {
      conditions.push(`leave_count >= $${paramIdx}`);
      countParams.push(parseInt(options.minLeaves));
      paramIdx++;
    }
    if (options.platform && ['ios', 'android'].includes(String(options.platform).toLowerCase())) {
      conditions.push(`LOWER(device_platform) = $${paramIdx}`);
      countParams.push(String(options.platform).toLowerCase());
      paramIdx++;
    }
    if (options.ipQuery) {
      conditions.push(`last_ip ILIKE $${paramIdx}`);
      countParams.push(`%${options.ipQuery}%`);
      paramIdx++;
    }

    const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

    // Sort options
    const sortOptions = {
      'rating_desc': 'rating DESC',
      'rating_asc': 'rating ASC',
      'games_desc': 'total_games DESC',
      'gold_desc': 'gold DESC',
      'level_desc': 'level DESC',
      'leaves_desc': 'leave_count DESC',
      'login_desc': 'last_login DESC NULLS LAST',
      'joined_desc': 'created_at DESC',
      'joined_asc': 'created_at ASC',
    };
    const orderBy = sortOptions[options.sort] || 'last_login DESC NULLS LAST';

    const countQuery = `SELECT COUNT(*) FROM tc_users ${whereClause}`;
    const countResult = await client.query(countQuery, countParams);
    const total = parseInt(countResult.rows[0].count);

    const dataParams = [...countParams, limit, offset];
    const dataQuery = `SELECT id, username, nickname, total_games, wins, losses, rating, gold, level, leave_count, season_rating, created_at, last_login, device_platform, app_version, last_ip, is_admin, is_deleted
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
      `SELECT id, username, nickname, total_games, wins, losses, rating, created_at, last_login, chat_ban_until, leave_count, gold, level, season_rating, admin_memo,
              fcm_token, push_enabled, push_admin_inquiry, push_admin_report, is_admin, is_deleted, deleted_at, device_platform, device_model, os_version, app_version, last_ip, locale,
              sk_total_games, sk_wins, sk_losses, ll_total_games, ll_wins, ll_losses
       FROM tc_users WHERE nickname = $1`,
      [nickname]
    );
    if (userResult.rows.length === 0) return null;
    const user = userResult.rows[0];

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
              COUNT(*) FILTER (WHERE claimed_at::date = CURRENT_DATE) as today
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

// Get dashboard stats
async function getDashboardStats() {
  const client = await pool.connect();
  try {
    // Basic counts
    const totalUsers = await client.query('SELECT COUNT(*) FROM tc_users WHERE is_deleted IS NOT TRUE');
    const pendingInquiries = await client.query(`SELECT COUNT(*) FROM tc_inquiries WHERE status = 'pending'`);
    const pendingReports = await client.query(`SELECT COUNT(*) FROM tc_reports WHERE status = 'pending'`);
    const todayGames = await client.query(`
      SELECT
        (SELECT COUNT(*) FROM tc_match_history WHERE created_at >= CURRENT_DATE) as tichu,
        (SELECT COUNT(*) FROM tc_sk_match_history WHERE created_at >= CURRENT_DATE) as sk,
        (SELECT COUNT(*) FROM tc_ll_match_history WHERE created_at >= CURRENT_DATE) as ll
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
      ORDER BY created_at DESC LIMIT 10
    `);

    // New users today
    const newUsersToday = await client.query(
      `SELECT COUNT(*) FROM tc_users WHERE created_at >= CURRENT_DATE AND is_deleted IS NOT TRUE`
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
      `SELECT (SELECT COUNT(*) FROM tc_match_history) + (SELECT COUNT(*) FROM tc_sk_match_history) + (SELECT COUNT(*) FROM tc_ll_match_history) as count`
    );
    const rankedMatchesToday = await client.query(
      `SELECT (SELECT COUNT(*) FROM tc_match_history WHERE created_at >= CURRENT_DATE AND is_ranked = true) + (SELECT COUNT(*) FROM tc_sk_match_history WHERE created_at >= CURRENT_DATE AND is_ranked = true) + (SELECT COUNT(*) FROM tc_ll_match_history WHERE created_at >= CURRENT_DATE AND is_ranked = true) as count`
    );

    // Games per day (last 7 days) - tichu + skull king combined
    const dailyGames = await client.query(`
      SELECT day, SUM(cnt) as cnt, SUM(ranked_cnt) as ranked_cnt, SUM(tichu_cnt) as tichu_cnt, SUM(sk_cnt) as sk_cnt, SUM(ll_cnt) as ll_cnt FROM (
        SELECT DATE(created_at) as day, COUNT(*) as cnt,
               SUM(CASE WHEN is_ranked THEN 1 ELSE 0 END) as ranked_cnt,
               COUNT(*) as tichu_cnt, 0::bigint as sk_cnt, 0::bigint as ll_cnt
        FROM tc_match_history
        WHERE created_at >= CURRENT_DATE - INTERVAL '6 days'
        GROUP BY DATE(created_at)
        UNION ALL
        SELECT DATE(created_at) as day, COUNT(*) as cnt,
               SUM(CASE WHEN is_ranked THEN 1 ELSE 0 END) as ranked_cnt,
               0::bigint as tichu_cnt, COUNT(*) as sk_cnt, 0::bigint as ll_cnt
        FROM tc_sk_match_history
        WHERE created_at >= CURRENT_DATE - INTERVAL '6 days'
        GROUP BY DATE(created_at)
        UNION ALL
        SELECT DATE(created_at) as day, COUNT(*) as cnt,
               SUM(CASE WHEN is_ranked THEN 1 ELSE 0 END) as ranked_cnt,
               0::bigint as tichu_cnt, 0::bigint as sk_cnt, COUNT(*) as ll_cnt
        FROM tc_ll_match_history
        WHERE created_at >= CURRENT_DATE - INTERVAL '6 days'
        GROUP BY DATE(created_at)
      ) combined GROUP BY day ORDER BY day
    `);

    // New users per day (last 7 days)
    const dailySignups = await client.query(`
      SELECT DATE(created_at) as day, COUNT(*) as cnt
      FROM tc_users
      WHERE created_at >= CURRENT_DATE - INTERVAL '6 days' AND is_deleted IS NOT TRUE
      GROUP BY DATE(created_at)
      ORDER BY day
    `);

    // Top 10 players by rating
    const topPlayers = await client.query(`
      SELECT nickname, rating, wins, losses, total_games, season_rating, season_games, level
      FROM tc_users WHERE is_deleted IS NOT TRUE ORDER BY rating DESC, season_games DESC LIMIT 10
    `);

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
    const adRewardStats = await client.query(`
      SELECT COUNT(*) as total_claims,
             COUNT(DISTINCT nickname) as unique_users,
             COUNT(*) FILTER (WHERE claimed_at::date = CURRENT_DATE) as today_claims,
             COUNT(DISTINCT nickname) FILTER (WHERE claimed_at::date = CURRENT_DATE) as today_users
      FROM tc_ad_rewards
    `);

    // Daily ad rewards (last 7 days)
    const dailyAdRewards = await client.query(`
      SELECT DATE(claimed_at) as day, COUNT(*) as cnt, COUNT(DISTINCT nickname) as users
      FROM tc_ad_rewards
      WHERE claimed_at >= CURRENT_DATE - INTERVAL '6 days'
      GROUP BY DATE(claimed_at)
      ORDER BY day
    `);

    return {
      totalUsers: parseInt(totalUsers.rows[0].count),
      pendingInquiries: parseInt(pendingInquiries.rows[0].count),
      pendingReports: parseInt(pendingReports.rows[0].count),
      todayGames: parseInt(todayGames.rows[0].tichu) + parseInt(todayGames.rows[0].sk) + parseInt(todayGames.rows[0].ll),
      todayTichuGames: parseInt(todayGames.rows[0].tichu),
      todaySKGames: parseInt(todayGames.rows[0].sk),
      todayLLGames: parseInt(todayGames.rows[0].ll),
      recentMatches: recentMatches.rows,
      newUsersToday: parseInt(newUsersToday.rows[0].count),
      activeUsers24h: parseInt(activeUsers24h.rows[0].count),
      activeUsers7d: parseInt(activeUsers7d.rows[0].count),
      totalMatches: parseInt(totalMatches.rows[0].count),
      rankedMatchesToday: parseInt(rankedMatchesToday.rows[0].count),
      dailyGames: dailyGames.rows,
      dailySignups: dailySignups.rows,
      topPlayers: topPlayers.rows,
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
      totalUsers: 0, pendingInquiries: 0, pendingReports: 0, todayGames: 0, todayTichuGames: 0, todaySKGames: 0, todayLLGames: 0,
      recentMatches: [], newUsersToday: 0, activeUsers24h: 0, activeUsers7d: 0,
      totalMatches: 0, rankedMatchesToday: 0, dailyGames: [], dailySignups: [],
      topPlayers: [], goldStats: {}, shopStats: {}, leaveStats: {}, reportStats30d: {},
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
         (SELECT COUNT(*) FROM tc_ll_match_history) AS total`
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
  const platform = ['ios', 'android'].includes(String(options.platform || '').toLowerCase())
    ? String(options.platform).toLowerCase()
    : '';
  try {
    const gameSeries = await client.query(`
      WITH tichu AS (
        SELECT DATE_TRUNC('${groupUnit}', created_at) AS bucket_time,
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
        SELECT DATE_TRUNC('${groupUnit}', h.created_at) AS bucket_time,
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
        SELECT DATE_TRUNC('${groupUnit}', h.created_at) AS bucket_time,
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
      buckets AS (
        SELECT bucket_time FROM tichu
        UNION
        SELECT bucket_time FROM skull
        UNION
        SELECT bucket_time FROM love
      )
      SELECT b.bucket_time,
             COALESCE(tichu.total_cnt, 0) AS tichu_cnt,
             COALESCE(skull.total_cnt, 0) AS skull_cnt,
             COALESCE(love.total_cnt, 0) AS ll_cnt,
             COALESCE(tichu.total_cnt, 0) + COALESCE(skull.total_cnt, 0) + COALESCE(love.total_cnt, 0) AS total_cnt,
             COALESCE(tichu.ranked_cnt, 0) + COALESCE(skull.ranked_cnt, 0) + COALESCE(love.ranked_cnt, 0) AS ranked_cnt
      FROM buckets b
      LEFT JOIN tichu ON tichu.bucket_time = b.bucket_time
      LEFT JOIN skull ON skull.bucket_time = b.bucket_time
      LEFT JOIN love ON love.bucket_time = b.bucket_time
      ORDER BY b.bucket_time ASC
    `, [from, to, platform]);

    const goldSeries = await client.query(`
      WITH gold_events AS (
        SELECT DATE_TRUNC('${groupUnit}', mh.created_at) AS bucket_time,
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

        SELECT DATE_TRUNC('${groupUnit}', h.created_at) AS bucket_time,
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

        SELECT DATE_TRUNC('${groupUnit}', h.created_at) AS bucket_time,
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

        SELECT DATE_TRUNC('${groupUnit}', ar.claimed_at) AS bucket_time,
               50 AS gold_delta
        FROM tc_ad_rewards ar
        JOIN tc_users u ON u.nickname = ar.nickname
        WHERE ar.claimed_at >= $1 AND ar.claimed_at < $2
          AND ($3 = '' OR LOWER(u.device_platform) = $3)

        UNION ALL

        SELECT DATE_TRUNC('${groupUnit}', ui.acquired_at) AS bucket_time,
               -COALESCE(si.price, 0) AS gold_delta
        FROM tc_user_items ui
        LEFT JOIN tc_shop_items si ON si.item_key = ui.item_key
        JOIN tc_users u ON u.nickname = ui.nickname
        WHERE ui.source = 'shop'
          AND ui.acquired_at >= $1 AND ui.acquired_at < $2
          AND ($3 = '' OR LOWER(u.device_platform) = $3)

        UNION ALL

        SELECT DATE_TRUNC('${groupUnit}', gh.created_at) AS bucket_time,
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
        DATE_TRUNC('${groupUnit}', ui.acquired_at) AS bucket_time,
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
        DATE_TRUNC('${groupUnit}', created_at) AS bucket_time,
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

    const summaryRow = gameSummary.rows[0] || {};
    const goldRow = goldSummary.rows[0] || {};
    const shopRow = shopSummary.rows[0] || {};
    const signupRow = signupSummary.rows[0] || {};
    return {
      success: true,
      summary: {
        totalGames: (parseInt(summaryRow.tichu_games || 0, 10) + parseInt(summaryRow.skull_games || 0, 10) + parseInt(summaryRow.ll_games || 0, 10)),
        tichuGames: parseInt(summaryRow.tichu_games || 0, 10),
        skullGames: parseInt(summaryRow.skull_games || 0, 10),
        llGames: parseInt(summaryRow.ll_games || 0, 10),
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

// Add new shop item
async function addShopItem(data) {
  const client = await pool.connect();
  try {
    const result = await client.query(
      `INSERT INTO tc_shop_items
        (item_key, name, name_ko, name_en, name_de, category, price, is_permanent, duration_days, is_purchasable, is_season, effect_type, effect_value, sale_start, sale_end)
       VALUES ($1, $2, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
       RETURNING *`,
      [
        data.item_key, data.name_ko || '', data.name_en || '', data.name_de || '',
        data.category, data.price || 0,
        data.is_permanent !== false, data.duration_days || null,
        data.is_purchasable !== false, data.is_season || false,
        data.effect_type || null, data.effect_value || null,
        data.sale_start || null, data.sale_end || null,
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

// Update shop item
async function updateShopItem(id, data) {
  const client = await pool.connect();
  try {
    const result = await client.query(
      `UPDATE tc_shop_items
       SET name = $2, name_ko = $2, name_en = $3, name_de = $4, category = $5, price = $6, is_permanent = $7,
           duration_days = $8, is_purchasable = $9, is_season = $10,
           effect_type = $11, effect_value = $12, sale_start = $13, sale_end = $14
       WHERE id = $1
       RETURNING *`,
      [
        id, data.name_ko || '', data.name_en || '', data.name_de || '',
        data.category, data.price || 0,
        data.is_permanent !== false, data.duration_days || null,
        data.is_purchasable !== false, data.is_season || false,
        data.effect_type || null, data.effect_value || null,
        data.sale_start || null, data.sale_end || null,
      ]
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
      'SELECT id, nickname, is_admin, is_deleted, push_enabled, push_friend_invite, push_admin_inquiry, push_admin_report FROM tc_users WHERE auth_provider = $1 AND provider_uid = $2',
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
      pushAdminInquiry: user.push_admin_inquiry !== false,
      pushAdminReport: user.push_admin_report !== false,
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
async function updateDeviceInfo(nickname, deviceInfo) {
  const client = await pool.connect();
  try {
    await client.query(
      `UPDATE tc_users
       SET fcm_token = COALESCE($2, fcm_token),
           device_platform = COALESCE($3, device_platform),
           device_model = COALESCE($4, device_model),
           os_version = COALESCE($5, os_version),
           app_version = COALESCE($6, app_version),
           last_ip = COALESCE($7, last_ip),
           locale = COALESCE($8, locale)
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
      ]
    );
  } catch (err) {
    console.error('Update device info error:', err);
  } finally {
    client.release();
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
       RETURNING nickname, is_admin, push_admin_inquiry, push_admin_report`,
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

async function setAdminAlertSettings(nickname, inquiryEnabled, reportEnabled) {
  const client = await pool.connect();
  try {
    const result = await client.query(
      `UPDATE tc_users
       SET push_admin_inquiry = $2,
           push_admin_report = $3
       WHERE nickname = $1
       RETURNING push_admin_inquiry, push_admin_report`,
      [nickname, inquiryEnabled, reportEnabled]
    );
    if (result.rows.length === 0) {
      return { success: false, messageKey: 'db_user_not_found' };
    }
    return {
      success: true,
      settings: {
        pushAdminInquiry: result.rows[0].push_admin_inquiry !== false,
        pushAdminReport: result.rows[0].push_admin_report !== false,
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
    const column = kind === 'report' ? 'push_admin_report' : 'push_admin_inquiry';
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

async function searchUsers(query, requesterNickname) {
  const client = await pool.connect();
  try {
    const result = await client.query(
      `SELECT nickname FROM tc_users
       WHERE nickname ILIKE $1 AND nickname != $2 AND is_deleted IS NOT TRUE
       ORDER BY nickname
       LIMIT 20`,
      [`%${query}%`, requesterNickname]
    );
    return result.rows.map(r => r.nickname);
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
        level = GREATEST(1, ((exp_total + $5) / 100) + 1)
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
            level = GREATEST(1, ((exp_total + $2) / 100) + 1)
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
            level = GREATEST(1, ((exp_total + $5) / 100) + 1)
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
            level = GREATEST(1, ((exp_total + $2) / 100) + 1)
           WHERE nickname = $1`,
          [p.nickname, expGain]
        );
      } else {
        const goldReward = isDeserter ? 0 : (won ? 10 : 3);
        const expGain = won ? 15 : 5;
        await client.query(
          `UPDATE tc_users SET
            ll_total_games = ll_total_games + 1,
            ll_wins = ll_wins + CASE WHEN $2 THEN 1 ELSE 0 END,
            ll_losses = ll_losses + CASE WHEN $2 THEN 0 ELSE 1 END,
            gold = gold + $3,
            exp_total = exp_total + $4,
            level = GREATEST(1, ((exp_total + $4) / 100) + 1)
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

// ===== Notices CRUD =====

async function getPublishedNotices() {
  const client = await pool.connect();
  try {
    const res = await client.query(
      `SELECT id, category, title, content, is_pinned, published_at
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

async function createNotice(category, title, content, isPinned, status) {
  const client = await pool.connect();
  try {
    const publishedAt = status === 'published' ? new Date() : null;
    const res = await client.query(
      `INSERT INTO tc_notices (category, title, content, is_pinned, status, published_at)
       VALUES ($1, $2, $3, $4, $5, $6) RETURNING id`,
      [category, title, content, isPinned, status, publishedAt]
    );
    return { success: true, id: res.rows[0].id };
  } catch (err) {
    console.error('createNotice error:', err);
    return { success: false };
  } finally {
    client.release();
  }
}

async function updateNotice(id, category, title, content, isPinned, status) {
  const client = await pool.connect();
  try {
    const existing = await client.query('SELECT status, published_at FROM tc_notices WHERE id = $1', [id]);
    if (existing.rows.length === 0) return { success: false };
    const oldStatus = existing.rows[0].status;
    const oldPublishedAt = existing.rows[0].published_at;
    const publishedAt = (status === 'published' && oldStatus !== 'published') ? new Date() : oldPublishedAt;
    await client.query(
      `UPDATE tc_notices SET category=$1, title=$2, content=$3, is_pinned=$4, status=$5, published_at=$6, updated_at=NOW()
       WHERE id=$7`,
      [category, title, content, isPinned, status, publishedAt, id]
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
  getPendingFriendRequests,
  acceptFriendRequest,
  rejectFriendRequest,
  removeFriend,
  saveMatchResult,
  saveMatchResultWithStats,
  updateUserStats,
  getUserProfile,
  getRecentMatches,
  getWallet,
  getGoldHistory,
  getAdminGoldHistory,
  getAdminPurchaseHistory,
  getShopItems,
  getUserItems,
  buyItem,
  equipItem,
  useItem,
  changeNickname,
  incrementLeaveCount,
  setRankedBan,
  getRankedBan,
  setChatBan,
  getChatBan,
  setAdminMemo,
  getActiveSeason,
  createSeason,
  getSeasons,
  getCurrentSeasonRankings,
  getSeasonRankings,
  resetSeasonStats,
  grantSeasonRewards,
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
  getUserDetail,
  getDashboardStats,
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
  setPushEnabled,
  setPushFriendInvite,
  setUserAdmin,
  setAdminAlertSettings,
  getAdminPushRecipients,
  getConfig,
  getLocalizedConfig,
  updateConfig,
  adminAdjustGold,
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
  getPublishedNotices,
  getNotices,
  getNoticeById,
  createNotice,
  updateNotice,
  deleteNotice,
  insertMaintenanceHistory,
  getMaintenanceHistory,
  pool,
};
