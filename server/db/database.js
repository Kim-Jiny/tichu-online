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
    if (won) {
      await client.query(
        `UPDATE tc_users
         SET total_games = total_games + 1,
             wins = wins + 1,
             rating = GREATEST(0, rating + $2)
         WHERE nickname = $1`,
        [nickname, ratingChange]
      );
    } else {
      await client.query(
        `UPDATE tc_users
         SET total_games = total_games + 1,
             losses = losses + 1,
             rating = GREATEST(0, rating + $2)
         WHERE nickname = $1`,
        [nickname, ratingChange]
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
      `SELECT nickname, total_games, wins, losses, rating, created_at
       FROM tc_users WHERE nickname = $1`,
      [nickname]
    );
    if (result.rows.length === 0) {
      return null;
    }
    const user = result.rows[0];
    const winRate = user.total_games > 0
      ? Math.round((user.wins / user.total_games) * 100)
      : 0;
    return {
      nickname: user.nickname,
      totalGames: user.total_games,
      wins: user.wins,
      losses: user.losses,
      rating: user.rating,
      winRate,
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
      const won = (isTeamA && row.winner_team === 'A') || (!isTeamA && row.winner_team === 'B');
      return {
        id: row.id,
        won,
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

// Get reports with pagination
async function getReports(page = 1, limit = 20) {
  const client = await pool.connect();
  try {
    const offset = (page - 1) * limit;
    const countResult = await client.query('SELECT COUNT(*) FROM tc_reports');
    const total = parseInt(countResult.rows[0].count);
    const result = await client.query(
      'SELECT * FROM tc_reports ORDER BY created_at DESC LIMIT $1 OFFSET $2',
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

// Get single report by ID
async function getReportById(id) {
  const client = await pool.connect();
  try {
    const result = await client.query('SELECT * FROM tc_reports WHERE id = $1', [id]);
    return result.rows[0] || null;
  } catch (err) {
    console.error('Get report error:', err);
    return null;
  } finally {
    client.release();
  }
}

// Update report status
async function updateReportStatus(id, status) {
  const client = await pool.connect();
  try {
    await client.query(
      'UPDATE tc_reports SET status = $2 WHERE id = $1',
      [id, status]
    );
    return { success: true };
  } catch (err) {
    console.error('Update report status error:', err);
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
      `SELECT id, username, nickname, total_games, wins, losses, rating, created_at, last_login
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
    const totalUsers = await client.query('SELECT COUNT(*) FROM tc_users');
    const pendingInquiries = await client.query(`SELECT COUNT(*) FROM tc_inquiries WHERE status = 'pending'`);
    const pendingReports = await client.query(`SELECT COUNT(*) FROM tc_reports WHERE status = 'pending'`);
    const todayGames = await client.query(
      `SELECT COUNT(*) FROM tc_match_history WHERE created_at >= CURRENT_DATE`
    );
    const recentMatches = await client.query(
      'SELECT * FROM tc_match_history ORDER BY created_at DESC LIMIT 10'
    );
    return {
      totalUsers: parseInt(totalUsers.rows[0].count),
      pendingInquiries: parseInt(pendingInquiries.rows[0].count),
      pendingReports: parseInt(pendingReports.rows[0].count),
      todayGames: parseInt(todayGames.rows[0].count),
      recentMatches: recentMatches.rows,
    };
  } catch (err) {
    console.error('Get dashboard stats error:', err);
    return { totalUsers: 0, pendingInquiries: 0, pendingReports: 0, todayGames: 0, recentMatches: [] };
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
  saveMatchResult,
  updateUserStats,
  getUserProfile,
  getRecentMatches,
  submitInquiry,
  getInquiries,
  getInquiryById,
  resolveInquiry,
  getReports,
  getReportById,
  updateReportStatus,
  getUsers,
  getUserDetail,
  getDashboardStats,
  verifyAdmin,
  pool,
};
