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

    // Shop items table
    await client.query(`
      CREATE TABLE IF NOT EXISTS tc_shop_items (
        id SERIAL PRIMARY KEY,
        item_key VARCHAR(80) UNIQUE NOT NULL,
        name VARCHAR(100) NOT NULL,
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
        (item_key, name, category, price, is_season, is_permanent, duration_days, is_purchasable, effect_type, effect_value, metadata)
      VALUES
        ('banner_pastel', '파스텔 배너', 'banner', 300, FALSE, TRUE, NULL, TRUE, NULL, NULL, '{}'::jsonb),
        ('banner_blossom', '블라썸 배너', 'banner', 280, FALSE, TRUE, NULL, TRUE, NULL, NULL, '{}'::jsonb),
        ('banner_mint', '민트 배너', 'banner', 260, FALSE, TRUE, NULL, TRUE, NULL, NULL, '{}'::jsonb),
        ('banner_sunset_7d', '노을 배너(7일)', 'banner', 120, FALSE, FALSE, 7, TRUE, NULL, NULL, '{}'::jsonb),
        ('title_sweet', '달콤한 플레이어', 'title', 200, FALSE, TRUE, NULL, TRUE, NULL, NULL, '{}'::jsonb),
        ('title_steady', '꾸준한 승부사', 'title', 240, FALSE, TRUE, NULL, TRUE, NULL, NULL, '{}'::jsonb),
        ('title_flash_30d', '스피드 러너(30일)', 'title', 180, FALSE, FALSE, 30, TRUE, NULL, NULL, '{}'::jsonb),
        ('theme_cotton', '코튼 테마', 'theme', 500, FALSE, TRUE, NULL, TRUE, NULL, NULL, '{"includesCardSkin": true}'::jsonb),
        ('theme_sky', '스카이 테마', 'theme', 550, FALSE, TRUE, NULL, TRUE, NULL, NULL, '{"includesCardSkin": true}'::jsonb),
        ('theme_mocha_30d', '모카 테마(30일)', 'theme', 300, FALSE, FALSE, 30, TRUE, NULL, NULL, '{"includesCardSkin": true}'::jsonb),
        ('theme_lavender', '라벤더 테마', 'theme', 500, FALSE, TRUE, NULL, TRUE, NULL, NULL, '{"includesCardSkin": true}'::jsonb),
        ('theme_cherry', '체리블라썸 테마', 'theme', 550, FALSE, TRUE, NULL, TRUE, NULL, NULL, '{"includesCardSkin": true}'::jsonb),
        ('theme_midnight', '미드나잇 테마', 'theme', 600, FALSE, TRUE, NULL, TRUE, NULL, NULL, '{"includesCardSkin": true}'::jsonb),
        ('theme_sunset', '선셋 테마', 'theme', 500, FALSE, TRUE, NULL, TRUE, NULL, NULL, '{"includesCardSkin": true}'::jsonb),
        ('theme_forest', '포레스트 테마', 'theme', 520, FALSE, TRUE, NULL, TRUE, NULL, NULL, '{"includesCardSkin": true}'::jsonb),
        ('theme_rose', '로즈골드 테마', 'theme', 550, FALSE, TRUE, NULL, TRUE, NULL, NULL, '{"includesCardSkin": true}'::jsonb),
        ('theme_ocean', '오션 테마', 'theme', 500, FALSE, TRUE, NULL, TRUE, NULL, NULL, '{"includesCardSkin": true}'::jsonb),
        ('theme_aurora', '오로라 테마', 'theme', 600, FALSE, TRUE, NULL, TRUE, NULL, NULL, '{"includesCardSkin": true}'::jsonb),
        ('theme_mintchoco_30d', '민트초코 테마(30일)', 'theme', 300, FALSE, FALSE, 30, TRUE, NULL, NULL, '{"includesCardSkin": true}'::jsonb),
        ('theme_peach_30d', '피치 테마(30일)', 'theme', 280, FALSE, FALSE, 30, TRUE, NULL, NULL, '{"includesCardSkin": true}'::jsonb),
        ('leave_reduce_1', '탈주 카운트 -1', 'utility', 150, FALSE, TRUE, NULL, TRUE, 'leave_count_reduce', 1, '{}'::jsonb),
        ('leave_reduce_3', '탈주 카운트 -3', 'utility', 400, FALSE, TRUE, NULL, TRUE, 'leave_count_reduce', 3, '{}'::jsonb),
        ('nickname_change', '닉네임 변경권', 'utility', 500, FALSE, TRUE, NULL, TRUE, 'nickname_change', NULL, '{}'::jsonb),
        ('banner_season_gold', '시즌 골드 배너', 'banner', 0, TRUE, FALSE, 30, FALSE, NULL, NULL, '{}'::jsonb),
        ('banner_season_silver', '시즌 실버 배너', 'banner', 0, TRUE, FALSE, 30, FALSE, NULL, NULL, '{}'::jsonb),
        ('banner_season_bronze', '시즌 브론즈 배너', 'banner', 0, TRUE, FALSE, 30, FALSE, NULL, NULL, '{}'::jsonb)
      ON CONFLICT (item_key) DO NOTHING
      `
    );

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
    return { success: false, message: '아이디는 2글자 이상이어야 합니다' };
  }
  if (/\s/.test(username)) {
    return { success: false, message: '아이디에 공백을 사용할 수 없습니다' };
  }

  // Validate password
  if (!password || password.length < 4) {
    return { success: false, message: '비밀번호는 4글자 이상이어야 합니다' };
  }

  // Validate nickname
  if (!nickname || nickname.trim().length < 1) {
    return { success: false, message: '닉네임을 입력해주세요' };
  }

  const client = await pool.connect();
  try {
    // Check if username exists
    const usernameCheck = await client.query(
      'SELECT id FROM tc_users WHERE username = $1',
      [username.toLowerCase()]
    );
    if (usernameCheck.rows.length > 0) {
      return { success: false, message: '이미 사용중인 아이디입니다' };
    }

    // Check if nickname exists
    const nicknameCheck = await client.query(
      'SELECT id FROM tc_users WHERE nickname = $1',
      [nickname.trim()]
    );
    if (nicknameCheck.rows.length > 0) {
      return { success: false, message: '이미 사용중인 닉네임입니다' };
    }

    // Hash password and insert
    const passwordHash = await bcrypt.hash(password, SALT_ROUNDS);
    await client.query(
      'INSERT INTO tc_users (username, password_hash, nickname) VALUES ($1, $2, $3)',
      [username.toLowerCase(), passwordHash, nickname.trim()]
    );

    return { success: true, message: '회원가입이 완료되었습니다' };
  } catch (err) {
    console.error('Registration error:', err);
    return { success: false, message: '회원가입 중 오류가 발생했습니다' };
  } finally {
    client.release();
  }
}

// Login user
async function loginUser(username, password) {
  if (!username || !password) {
    return { success: false, message: '아이디와 비밀번호를 입력해주세요' };
  }

  const client = await pool.connect();
  try {
    const result = await client.query(
      'SELECT id, password_hash, nickname FROM tc_users WHERE username = $1',
      [username.toLowerCase()]
    );

    if (result.rows.length === 0) {
      return { success: false, message: '존재하지 않는 아이디입니다' };
    }

    const user = result.rows[0];
    const passwordMatch = await bcrypt.compare(password, user.password_hash);

    if (!passwordMatch) {
      return { success: false, message: '비밀번호가 일치하지 않습니다' };
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
    };
  } catch (err) {
    console.error('Login error:', err);
    return { success: false, message: '로그인 중 오류가 발생했습니다' };
  } finally {
    client.release();
  }
}

// Check if nickname is available
async function checkNickname(nickname) {
  if (!nickname || nickname.trim().length < 1) {
    return { available: false, message: '닉네임을 입력해주세요' };
  }

  const client = await pool.connect();
  try {
    const result = await client.query(
      'SELECT id FROM tc_users WHERE nickname = $1',
      [nickname.trim()]
    );
    return {
      available: result.rows.length === 0,
      message: result.rows.length === 0 ? '사용 가능한 닉네임입니다' : '이미 사용중인 닉네임입니다',
    };
  } catch (err) {
    console.error('Nickname check error:', err);
    return { available: false, message: '확인 중 오류가 발생했습니다' };
  } finally {
    client.release();
  }
}

// Delete user account
async function deleteUser(nickname) {
  if (!nickname) {
    return { success: false, message: '닉네임이 필요합니다' };
  }

  const client = await pool.connect();
  try {
    const result = await client.query(
      'DELETE FROM tc_users WHERE nickname = $1',
      [nickname]
    );
    if (result.rowCount === 0) {
      return { success: false, message: '사용자를 찾을 수 없습니다' };
    }
    return { success: true, message: '계정이 삭제되었습니다' };
  } catch (err) {
    console.error('Delete user error:', err);
    return { success: false, message: '계정 삭제 중 오류가 발생했습니다' };
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
      return { success: false, message: '이미 동일한 사유로 신고한 유저입니다' };
    }

    const chatContextJson = JSON.stringify(chatContext);
    await client.query(
      'INSERT INTO tc_reports (reporter_nickname, reported_nickname, reason, room_id, chat_context) VALUES ($1, $2, $3, $4, $5)',
      [reporterNickname, reportedNickname, reason, roomId, chatContextJson]
    );
    return { success: true, message: '신고가 접수되었습니다' };
  } catch (err) {
    console.error('Report user error:', err);
    return { success: false, message: '신고 접수에 실패했습니다' };
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
        return { success: false, message: '이미 친구입니다' };
      }
      // If they sent us a request, accept it
      if (row.user_nickname === friendNickname && row.status === 'pending') {
        await client.query(
          'UPDATE tc_friends SET status = $1 WHERE id = $2',
          ['accepted', row.id]
        );
        return { success: true, message: '친구가 되었습니다' };
      }
      return { success: false, message: '이미 친구 요청을 보냈습니다' };
    }

    await client.query(
      'INSERT INTO tc_friends (user_nickname, friend_nickname, status) VALUES ($1, $2, $3)',
      [userNickname, friendNickname, 'pending']
    );
    return { success: true, message: '친구 요청을 보냈습니다' };
  } catch (err) {
    console.error('Add friend error:', err);
    return { success: false, message: '친구 추가에 실패했습니다' };
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
      return { success: false, message: '요청을 찾을 수 없습니다' };
    }
    return { success: true, message: '친구가 되었습니다' };
  } catch (err) {
    console.error('Accept friend request error:', err);
    return { success: false, message: '요청 수락에 실패했습니다' };
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
      return { success: false, message: '요청을 찾을 수 없습니다' };
    }
    return { success: true, message: '요청을 거절했습니다' };
  } catch (err) {
    console.error('Reject friend request error:', err);
    return { success: false, message: '요청 거절에 실패했습니다' };
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
      return { success: false, message: '친구를 찾을 수 없습니다' };
    }
    return { success: true, message: '친구를 삭제했습니다' };
  } catch (err) {
    console.error('Remove friend error:', err);
    return { success: false, message: '친구 삭제에 실패했습니다' };
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
       (winner_team, team_a_score, team_b_score, player_a1, player_a2, player_b1, player_b2, is_ranked)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [
        matchData.winnerTeam,
        matchData.teamAScore,
        matchData.teamBScore,
        matchData.playerA1,
        matchData.playerA2,
        matchData.playerB1,
        matchData.playerB2,
        matchData.isRanked || false,
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

// Get user profile
async function getUserProfile(nickname) {
  const client = await pool.connect();
  try {
    const result = await client.query(
      `SELECT u.nickname, u.total_games, u.wins, u.losses, u.rating, u.gold, u.leave_count,
              u.season_rating, u.season_games, u.season_wins, u.season_losses,
              u.exp_total, u.level, u.created_at,
              e.banner_key, e.theme_key, e.title_key
       FROM tc_users u
       LEFT JOIN tc_user_equips e ON e.nickname = u.nickname
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
      createdAt: user.created_at,
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
    const result = await client.query(
      `SELECT * FROM tc_match_history
       WHERE player_a1 = $1 OR player_a2 = $1 OR player_b1 = $1 OR player_b2 = $1
       ORDER BY created_at DESC
       LIMIT $2`,
      [nickname, limit]
    );
    return result.rows.map(row => {
      const isTeamA = row.player_a1 === nickname || row.player_a2 === nickname;
      const isDraw = row.winner_team === 'draw';
      const won = !isDraw && ((isTeamA && row.winner_team === 'A') || (!isTeamA && row.winner_team === 'B'));
      return {
        id: row.id,
        won,
        isDraw,
        myTeam: isTeamA ? 'A' : 'B',
        teamAScore: row.team_a_score,
        teamBScore: row.team_b_score,
        playerA1: row.player_a1,
        playerA2: row.player_a2,
        playerB1: row.player_b1,
        playerB2: row.player_b2,
        isRanked: row.is_ranked,
        createdAt: row.created_at,
      };
    });
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
      return { success: false, message: '사용자를 찾을 수 없습니다' };
    }
    return { success: true, wallet: result.rows[0] };
  } catch (err) {
    console.error('Get wallet error:', err);
    return { success: false, message: '지갑 정보를 가져오지 못했습니다' };
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
      SELECT item_key, name, category, price, is_season, is_permanent,
             duration_days, is_purchasable, effect_type, effect_value, metadata
      FROM tc_shop_items
      WHERE is_purchasable = TRUE AND is_season = FALSE
        AND (sale_start IS NULL OR sale_start <= NOW())
        AND (sale_end IS NULL OR sale_end >= NOW())
      ORDER BY category ASC, price ASC, name ASC
      `
    );
    return { success: true, items: result.rows };
  } catch (err) {
    console.error('Get shop items error:', err);
    return { success: false, message: '상점 정보를 가져오지 못했습니다' };
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
             si.name, si.category, si.is_season, si.is_permanent,
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
    return { success: false, message: '인벤토리를 불러오지 못했습니다' };
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
      return { success: false, message: '아이템을 찾을 수 없습니다' };
    }
    const item = itemRes.rows[0];
    if (!item.is_purchasable) {
      await client.query('ROLLBACK');
      return { success: false, message: '구매할 수 없는 아이템입니다' };
    }

    const walletRes = await client.query(
      `SELECT gold FROM tc_users WHERE nickname = $1`,
      [nickname]
    );
    if (walletRes.rows.length === 0) {
      await client.query('ROLLBACK');
      return { success: false, message: '사용자를 찾을 수 없습니다' };
    }
    const gold = walletRes.rows[0].gold || 0;
    if (gold < item.price) {
      await client.query('ROLLBACK');
      return { success: false, message: '골드가 부족합니다' };
    }

    // Prevent duplicate ownership / extend duration for temp items
    if (item.is_permanent) {
      const owned = await client.query(
        `SELECT 1 FROM tc_user_items WHERE nickname = $1 AND item_key = $2 LIMIT 1`,
        [nickname, itemKey]
      );
      if (owned.rows.length > 0) {
        await client.query('ROLLBACK');
        return { success: false, message: '이미 보유한 아이템입니다' };
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
          return { success: false, message: '기간 정보를 찾을 수 없습니다' };
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
    return { success: false, message: '구매 중 오류가 발생했습니다' };
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
      `SELECT category FROM tc_shop_items WHERE item_key = $1`,
      [itemKey]
    );
    if (itemRes.rows.length === 0) {
      return { success: false, message: '아이템을 찾을 수 없습니다' };
    }
    const category = itemRes.rows[0].category;

    const owned = await client.query(
      `SELECT 1 FROM tc_user_items
       WHERE nickname = $1 AND item_key = $2
         AND (expires_at IS NULL OR expires_at >= NOW())
       LIMIT 1`,
      [nickname, itemKey]
    );
    if (owned.rows.length === 0) {
      return { success: false, message: '보유하지 않은 아이템입니다' };
    }

    const fieldMap = {
      banner: 'banner_key',
      title: 'title_key',
      theme: 'theme_key',
      card_skin: 'card_skin_key',
    };
    const field = fieldMap[category];
    if (!field) {
      return { success: false, message: '장착할 수 없는 아이템입니다' };
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

    return { success: true, category };
  } catch (err) {
    console.error('Equip item error:', err);
    return { success: false, message: '아이템 장착 중 오류가 발생했습니다' };
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
      return { success: false, message: '아이템을 찾을 수 없습니다' };
    }
    const { effect_type: effectType, effect_value: effectValue } = itemRes.rows[0];
    if (effectType !== 'leave_count_reduce') {
      await client.query('ROLLBACK');
      return { success: false, message: '사용할 수 없는 아이템입니다' };
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
      return { success: false, message: '보유하지 않은 아이템입니다' };
    }

    await client.query(
      `UPDATE tc_users SET leave_count = GREATEST(0, leave_count - $2)
       WHERE nickname = $1`,
      [nickname, effectValue || 1]
    );

    await client.query(
      `DELETE FROM tc_user_items WHERE id = $1`,
      [owned.rows[0].id]
    );

    await client.query('COMMIT');
    return { success: true };
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Use item error:', err);
    return { success: false, message: '아이템 사용 중 오류가 발생했습니다' };
  } finally {
    client.release();
  }
}

// Change nickname using nickname_change item
async function changeNickname(oldNickname, newNickname) {
  if (!newNickname || typeof newNickname !== 'string') {
    return { success: false, message: '닉네임을 입력해주세요' };
  }
  const trimmed = newNickname.trim();
  if (trimmed.length < 2 || trimmed.length > 10) {
    return { success: false, message: '닉네임은 2~10자여야 합니다' };
  }
  if (/\s/.test(trimmed)) {
    return { success: false, message: '닉네임에 공백을 사용할 수 없습니다' };
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
      return { success: false, message: '이미 사용 중인 닉네임입니다' };
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
      return { success: false, message: '닉네임 변경권을 보유하고 있지 않습니다' };
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
    return { success: false, message: '닉네임 변경 중 오류가 발생했습니다' };
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
    return { success: false, message: '시즌 목록을 가져오지 못했습니다' };
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
      ORDER BY u.season_rating DESC, u.season_wins DESC, u.season_games DESC, u.nickname ASC
      LIMIT $1
      `,
      [limit]
    );
    return { success: true, rankings: result.rows };
  } catch (err) {
    console.error('Get current season rankings error:', err);
    return { success: false, message: '시즌 랭킹을 가져오지 못했습니다' };
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
      WHERE r.season_id = $1
      ORDER BY r.rank ASC
      LIMIT $2
      `,
      [seasonId, limit]
    );
    return { success: true, rankings: result.rows };
  } catch (err) {
    console.error('Get season rankings error:', err);
    return { success: false, message: '시즌 랭킹을 가져오지 못했습니다' };
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
           season_losses = 0`
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
      return { success: false, message: '시즌을 찾을 수 없습니다' };
    }
    if (seasonRes.rows[0].status === 'closed') {
      await client.query('ROLLBACK');
      return { success: false, message: '이미 종료된 시즌입니다' };
    }

    const topRes = await client.query(
      `
      SELECT nickname, rating
      FROM tc_users
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
      ORDER BY season_rating DESC, season_wins DESC, season_games DESC, nickname ASC
      LIMIT 100
      `
    );
    const topFull = topFullRes.rows;
    for (let i = 0; i < topFull.length; i++) {
      const u = topFull[i];
      await client.query(
        `INSERT INTO tc_season_rankings (season_id, rank, nickname, rating, wins, losses, total_games)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         ON CONFLICT (season_id, rank) DO NOTHING`,
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
    return { success: false, message: '시즌 보상 지급 실패' };
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
    return { success: true, message: '문의가 접수되었습니다' };
  } catch (err) {
    console.error('Submit inquiry error:', err);
    return { success: false, message: '문의 접수에 실패했습니다' };
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
    return { success: true };
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
async function getUsers(search = '', page = 1, limit = 20) {
  const client = await pool.connect();
  try {
    const offset = (page - 1) * limit;
    let countQuery, dataQuery, params;
    if (search) {
      countQuery = `SELECT COUNT(*) FROM tc_users WHERE nickname ILIKE $1 OR username ILIKE $1`;
      dataQuery = `SELECT id, username, nickname, total_games, wins, losses, rating, created_at, last_login
                   FROM tc_users WHERE nickname ILIKE $1 OR username ILIKE $1
                   ORDER BY created_at DESC LIMIT $2 OFFSET $3`;
      params = [`%${search}%`, limit, offset];
    } else {
      countQuery = 'SELECT COUNT(*) FROM tc_users';
      dataQuery = `SELECT id, username, nickname, total_games, wins, losses, rating, created_at, last_login
                   FROM tc_users ORDER BY created_at DESC LIMIT $1 OFFSET $2`;
      params = [limit, offset];
    }
    const countResult = await client.query(countQuery, search ? [`%${search}%`] : []);
    const total = parseInt(countResult.rows[0].count);
    const result = await client.query(dataQuery, params);
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
      `SELECT id, username, nickname, total_games, wins, losses, rating, created_at, last_login, chat_ban_until, leave_count, gold, level, season_rating, admin_memo
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
    return {
      ...user,
      report_count: parseInt(reportCount.rows[0].count),
      inquiry_count: parseInt(inquiryCount.rows[0].count),
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
    const totalUsers = await client.query('SELECT COUNT(*) FROM tc_users');
    const pendingInquiries = await client.query(`SELECT COUNT(*) FROM tc_inquiries WHERE status = 'pending'`);
    const pendingReports = await client.query(`SELECT COUNT(*) FROM tc_reports WHERE status = 'pending'`);
    const todayGames = await client.query(
      `SELECT COUNT(*) FROM tc_match_history WHERE created_at >= CURRENT_DATE`
    );
    const recentMatches = await client.query(
      'SELECT * FROM tc_match_history ORDER BY created_at DESC LIMIT 10'
    );

    // New users today
    const newUsersToday = await client.query(
      `SELECT COUNT(*) FROM tc_users WHERE created_at >= CURRENT_DATE`
    );

    // Active users (logged in within 24h / 7d)
    const activeUsers24h = await client.query(
      `SELECT COUNT(*) FROM tc_users WHERE last_login >= NOW() - INTERVAL '24 hours'`
    );
    const activeUsers7d = await client.query(
      `SELECT COUNT(*) FROM tc_users WHERE last_login >= NOW() - INTERVAL '7 days'`
    );

    // Total matches + ranked matches
    const totalMatches = await client.query('SELECT COUNT(*) FROM tc_match_history');
    const rankedMatchesToday = await client.query(
      `SELECT COUNT(*) FROM tc_match_history WHERE created_at >= CURRENT_DATE AND is_ranked = true`
    );

    // Games per day (last 7 days)
    const dailyGames = await client.query(`
      SELECT DATE(created_at) as day, COUNT(*) as cnt,
             SUM(CASE WHEN is_ranked THEN 1 ELSE 0 END) as ranked_cnt
      FROM tc_match_history
      WHERE created_at >= CURRENT_DATE - INTERVAL '6 days'
      GROUP BY DATE(created_at)
      ORDER BY day
    `);

    // New users per day (last 7 days)
    const dailySignups = await client.query(`
      SELECT DATE(created_at) as day, COUNT(*) as cnt
      FROM tc_users
      WHERE created_at >= CURRENT_DATE - INTERVAL '6 days'
      GROUP BY DATE(created_at)
      ORDER BY day
    `);

    // Top 10 players by rating
    const topPlayers = await client.query(`
      SELECT nickname, rating, wins, losses, total_games, season_rating, level
      FROM tc_users ORDER BY rating DESC LIMIT 10
    `);

    // Gold economy
    const goldStats = await client.query(`
      SELECT SUM(gold) as total_gold, AVG(gold) as avg_gold, MAX(gold) as max_gold
      FROM tc_users
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
      FROM tc_users
    `);

    // Report stats (last 30 days)
    const reportStats30d = await client.query(`
      SELECT COUNT(*) as total_reports,
             COUNT(DISTINCT reported_nickname) as unique_reported
      FROM tc_reports WHERE created_at >= NOW() - INTERVAL '30 days'
    `);

    return {
      totalUsers: parseInt(totalUsers.rows[0].count),
      pendingInquiries: parseInt(pendingInquiries.rows[0].count),
      pendingReports: parseInt(pendingReports.rows[0].count),
      todayGames: parseInt(todayGames.rows[0].count),
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
    };
  } catch (err) {
    console.error('Get dashboard stats error:', err);
    return {
      totalUsers: 0, pendingInquiries: 0, pendingReports: 0, todayGames: 0,
      recentMatches: [], newUsersToday: 0, activeUsers24h: 0, activeUsers7d: 0,
      totalMatches: 0, rankedMatchesToday: 0, dailyGames: [], dailySignups: [],
      topPlayers: [], goldStats: {}, shopStats: {}, leaveStats: {}, reportStats30d: {},
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
      ORDER BY rating DESC, wins DESC, total_games DESC, nickname ASC
      LIMIT $1
      `,
      [limit]
    );
    return { success: true, rankings: result.rows };
  } catch (err) {
    console.error('Get rankings error:', err);
    return { success: false, message: '랭킹 정보를 가져오지 못했습니다' };
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
        (item_key, name, category, price, is_permanent, duration_days, is_purchasable, is_season, effect_type, effect_value, sale_start, sale_end)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
       RETURNING *`,
      [
        data.item_key, data.name, data.category, data.price || 0,
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
      return { success: false, message: '이미 존재하는 item_key입니다' };
    }
    return { success: false, message: '아이템 추가에 실패했습니다' };
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
       SET name = $2, category = $3, price = $4, is_permanent = $5,
           duration_days = $6, is_purchasable = $7, is_season = $8,
           effect_type = $9, effect_value = $10, sale_start = $11, sale_end = $12
       WHERE id = $1
       RETURNING *`,
      [
        id, data.name, data.category, data.price || 0,
        data.is_permanent !== false, data.duration_days || null,
        data.is_purchasable !== false, data.is_season || false,
        data.effect_type || null, data.effect_value || null,
        data.sale_start || null, data.sale_end || null,
      ]
    );
    if (result.rows.length === 0) {
      return { success: false, message: '아이템을 찾을 수 없습니다' };
    }
    return { success: true, item: result.rows[0] };
  } catch (err) {
    console.error('Update shop item error:', err);
    return { success: false, message: '아이템 수정에 실패했습니다' };
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
      return { success: false, message: '아이템을 찾을 수 없습니다' };
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
    return { success: false, message: '아이템 삭제에 실패했습니다' };
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
  updateUserStats,
  getUserProfile,
  getRecentMatches,
  getWallet,
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
  getInquiries,
  getInquiryById,
  resolveInquiry,
  getReports,
  getReportGroup,
  updateReportGroupStatus,
  getUsers,
  getUserDetail,
  getDashboardStats,
  getRankings,
  verifyAdmin,
  getAllShopItemsAdmin,
  addShopItem,
  updateShopItem,
  deleteShopItem,
  getShopItemById,
  pool,
};
