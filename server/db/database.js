const { Pool } = require('pg');
const bcrypt = require('bcrypt');

const SALT_ROUNDS = 10;

// PostgreSQL connection pool
const isProduction = process.env.NODE_ENV === 'production';
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
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

module.exports = {
  initDatabase,
  registerUser,
  loginUser,
  checkNickname,
  pool,
};
