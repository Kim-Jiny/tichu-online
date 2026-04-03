const crypto = require('crypto');
const serverStartedAt = new Date();
const {
  verifyAdmin, getInquiries, getInquiryById, resolveInquiry,
  getReports, getReportGroup, updateReportGroupStatus,
  getUsers, getUserDetail, getAdminGoldHistory, getAdminPurchaseHistory, deleteUser, getDashboardStats, setChatBan, setAdminMemo, getRecentMatches, adminAdjustGold, setUserAdmin,
  getDetailedAdminStats,
  getAllShopItemsAdmin, addShopItem, updateShopItem, deleteShopItem, getShopItemById,
  getConfig, updateConfig,
} = require('./db/database');

// In-memory session store: token -> { username, createdAt }
const sessions = new Map();
const SESSION_MAX_AGE = 24 * 60 * 60 * 1000; // 24 hours
const isProduction = process.env.NODE_ENV === 'production';

// Clean up expired sessions every hour
setInterval(() => {
  const now = Date.now();
  for (const [token, session] of sessions) {
    if (now - session.createdAt > SESSION_MAX_AGE) {
      sessions.delete(token);
    }
  }
}, 60 * 60 * 1000);

function getSessionFromCookie(req) {
  const cookie = req.headers.cookie || '';
  const match = cookie.match(/tc_admin_session=([^;]+)/);
  if (!match) return null;
  const token = match[1];
  const session = sessions.get(token);
  if (!session) return null;
  if (Date.now() - session.createdAt > SESSION_MAX_AGE) {
    sessions.delete(token);
    return null;
  }
  return { token, session };
}

function setSessionCookie(res, token) {
  const expires = new Date(Date.now() + SESSION_MAX_AGE).toUTCString();
  const flags = `HttpOnly; SameSite=Strict; Path=/tc-backstage; Max-Age=${Math.floor(SESSION_MAX_AGE / 1000)}; Expires=${expires}${isProduction ? '; Secure' : ''}`;
  res.setHeader('Set-Cookie', `tc_admin_session=${token}; ${flags}`);
}

function clearSessionCookie(res) {
  const flags = `HttpOnly; SameSite=Strict; Path=/tc-backstage; Max-Age=0${isProduction ? '; Secure' : ''}`;
  res.setHeader('Set-Cookie', `tc_admin_session=; ${flags}`);
}

function parseBody(req) {
  const MAX_BODY_SIZE = 1024 * 100; // 100KB
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', chunk => {
      body += chunk;
      if (body.length > MAX_BODY_SIZE) {
        req.destroy();
        reject(new Error('Request body too large'));
      }
    });
    req.on('end', () => {
      const params = new URLSearchParams(body);
      const result = {};
      for (const [key, value] of params) {
        result[key] = value;
      }
      resolve(result);
    });
  });
}

function html(res, content, status = 200) {
  res.writeHead(status, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end(content);
}

function redirect(res, location) {
  res.writeHead(302, { Location: location });
  res.end();
}

// ===== Layout & Styles =====

function layout(title, content, activePage = '') {
  return `<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${title} - Tichu Admin</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
:root {
  --bg: #f4f1ea;
  --surface: rgba(255,255,255,0.92);
  --surface-strong: #ffffff;
  --line: rgba(32, 28, 22, 0.08);
  --text: #1f2328;
  --muted: #6c727f;
  --brand: #0f6c5c;
  --brand-soft: #d9eee7;
  --accent: #d88c38;
  --danger: #c0563f;
  --warning: #c67b2b;
  --shadow: 0 18px 40px rgba(34, 29, 21, 0.08);
}
body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
  background:
    radial-gradient(circle at top right, rgba(216,140,56,0.12), transparent 28%),
    radial-gradient(circle at top left, rgba(15,108,92,0.12), transparent 30%),
    linear-gradient(180deg, #f7f4ee 0%, #f1ede6 100%);
  color: var(--text);
  display: flex;
  min-height: 100vh;
}
.sidebar {
  width: 248px;
  background: linear-gradient(180deg, #17352f 0%, #102923 100%);
  color: #e7efe9;
  padding: 24px 0;
  position: fixed;
  height: 100vh;
  overflow-y: auto;
  z-index: 100;
  transition: transform 0.3s ease;
  box-shadow: 10px 0 30px rgba(16, 41, 35, 0.16);
}
.sidebar h2 { padding: 0 22px 18px; font-size: 18px; color: #fff; border-bottom: 1px solid rgba(255,255,255,0.08); margin-bottom: 12px; letter-spacing: 0.01em; }
.sidebar a { display: block; padding: 13px 22px; color: rgba(231,239,233,0.75); text-decoration: none; font-size: 14px; transition: all 0.2s; border-left: 3px solid transparent; }
.sidebar a:hover { background: rgba(255,255,255,0.06); color: #fff; }
.sidebar a.active { background: rgba(255,255,255,0.08); color: #fff; border-left-color: #dcb46a; }
.sidebar .logout { margin-top: 20px; border-top: 1px solid rgba(255,255,255,0.08); padding-top: 10px; }
.sidebar .logout a { color: #e57373; }
.menu-toggle { display: none; position: fixed; top: 12px; left: 12px; z-index: 200; background: #17352f; color: #fff; border: none; border-radius: 12px; width: 42px; height: 42px; font-size: 22px; cursor: pointer; align-items: center; justify-content: center; box-shadow: 0 8px 24px rgba(16,41,35,0.22); }
.sidebar-overlay { display: none; position: fixed; inset: 0; background: rgba(0,0,0,0.5); z-index: 90; }
.main { margin-left: 248px; flex: 1; padding: 28px; min-height: 100vh; }
.page-shell { max-width: 1480px; margin: 0 auto; }
.page-header { display: flex; justify-content: space-between; align-items: flex-start; gap: 16px; margin-bottom: 18px; }
.page-title { font-size: 30px; font-weight: 800; margin-bottom: 8px; color: var(--text); letter-spacing: -0.02em; }
.page-subtitle { font-size: 14px; line-height: 1.6; color: var(--muted); max-width: 760px; }
.header-actions { display: flex; gap: 10px; flex-wrap: wrap; justify-content: flex-end; }
.stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 16px; margin-bottom: 24px; }
.stat-card {
  background: linear-gradient(180deg, rgba(255,255,255,0.98), rgba(255,255,255,0.9));
  border: 1px solid var(--line);
  border-radius: 18px;
  padding: 20px;
  box-shadow: var(--shadow);
  position: relative;
  overflow: hidden;
}
.stat-card::after {
  content: "";
  position: absolute;
  inset: auto -20px -28px auto;
  width: 88px;
  height: 88px;
  border-radius: 999px;
  background: rgba(15,108,92,0.06);
}
.stat-card .label { font-size: 12px; color: var(--muted); margin-bottom: 6px; text-transform: uppercase; letter-spacing: 0.08em; }
.stat-card .value { font-size: 30px; font-weight: 800; color: var(--text); letter-spacing: -0.03em; }
.stat-card .value.purple { color: #5f62d6; }
.stat-card .value.green { color: #2e8b57; }
.stat-card .value.orange { color: var(--warning); }
.stat-card .value.red { color: var(--danger); }
.card {
  background: linear-gradient(180deg, rgba(255,255,255,0.96), rgba(255,255,255,0.9));
  border-radius: 20px;
  padding: 22px;
  border: 1px solid var(--line);
  box-shadow: var(--shadow);
  margin-bottom: 20px;
}
.card h3 { font-size: 18px; margin-bottom: 16px; color: var(--text); letter-spacing: -0.01em; }
.hero-card {
  background: linear-gradient(135deg, #17352f 0%, #1d4a41 60%, #24584d 100%);
  color: #fff;
  border-radius: 22px;
  padding: 24px;
  margin-bottom: 22px;
  box-shadow: 0 24px 50px rgba(23, 53, 47, 0.24);
}
.hero-card .eyebrow { font-size: 12px; text-transform: uppercase; letter-spacing: 0.12em; color: rgba(255,255,255,0.72); margin-bottom: 8px; }
.hero-card .headline { font-size: 30px; font-weight: 800; line-height: 1.18; max-width: 760px; letter-spacing: -0.03em; }
.hero-card .sub { margin-top: 10px; color: rgba(255,255,255,0.78); font-size: 14px; line-height: 1.6; }
.hero-meta { display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 12px; margin-top: 20px; }
.hero-meta .item { background: rgba(255,255,255,0.09); border: 1px solid rgba(255,255,255,0.08); border-radius: 16px; padding: 14px 16px; backdrop-filter: blur(8px); }
.hero-meta .item .k { font-size: 12px; color: rgba(255,255,255,0.7); margin-bottom: 6px; text-transform: uppercase; letter-spacing: 0.06em; }
.hero-meta .item .v { font-size: 22px; font-weight: 800; }
.summary-strip { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 12px; margin-bottom: 20px; }
.summary-item { background: rgba(255,255,255,0.72); border: 1px solid var(--line); border-radius: 16px; padding: 16px 18px; }
.summary-item .k { font-size: 12px; color: var(--muted); margin-bottom: 6px; text-transform: uppercase; letter-spacing: 0.06em; }
.summary-item .v { font-size: 24px; font-weight: 800; letter-spacing: -0.02em; color: var(--text); }
.summary-item .meta { margin-top: 6px; font-size: 12px; color: var(--muted); line-height: 1.5; }
.section-label { font-size: 12px; color: var(--muted); margin-bottom: 10px; text-transform: uppercase; letter-spacing: 0.08em; }
.kpi-note { font-size: 12px; color: var(--muted); margin-top: 6px; line-height: 1.5; }
.metric-inline { display: flex; align-items: center; justify-content: space-between; gap: 10px; padding: 10px 0; border-bottom: 1px dashed rgba(32,28,22,0.08); }
.metric-inline:last-child { border-bottom: none; padding-bottom: 0; }
.metric-inline .name { font-size: 13px; color: var(--muted); }
.metric-inline .num { font-weight: 700; font-size: 15px; color: var(--text); }
.card-actions { display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 14px; }
.table-wrap { overflow-x: auto; -webkit-overflow-scrolling: touch; }
table { width: 100%; border-collapse: separate; border-spacing: 0; }
th { text-align: left; padding: 12px 14px; background: #f6f3ec; color: var(--muted); font-size: 12px; font-weight: 700; border-bottom: 1px solid #e6dfd2; white-space: nowrap; text-transform: uppercase; letter-spacing: 0.05em; }
th:first-child { border-top-left-radius: 14px; }
th:last-child { border-top-right-radius: 14px; }
td { padding: 12px 14px; border-bottom: 1px solid #f0ebe2; font-size: 14px; vertical-align: top; }
tr:hover td { background: rgba(15,108,92,0.04); }
.badge { display: inline-block; padding: 3px 10px; border-radius: 12px; font-size: 12px; font-weight: 600; white-space: nowrap; }
.badge-pending { background: #fff3e0; color: #e65100; }
.badge-resolved { background: #e8f5e9; color: #2e7d32; }
.badge-reviewed { background: #e3f2fd; color: #1565c0; }
.badge-bug { background: #ffebee; color: #c62828; }
.badge-suggestion { background: #e8eaf6; color: #283593; }
.badge-other { background: #f3e5f5; color: #6a1b9a; }
.btn { display: inline-block; padding: 9px 16px; border-radius: 12px; font-size: 13px; font-weight: 700; border: none; cursor: pointer; text-decoration: none; transition: all 0.2s; }
.btn-primary { background: var(--brand); color: #fff; }
.btn-primary:hover { background: #0c594b; }
.btn-danger { background: #e53935; color: #fff; }
.btn-danger:hover { background: #c62828; }
.btn-success { background: #4caf50; color: #fff; }
.btn-success:hover { background: #388e3c; }
.btn-secondary { background: #ece5d8; color: #3d403f; }
.btn-secondary:hover { background: #e0d5c2; }
.detail-grid { display: grid; grid-template-columns: 120px 1fr; gap: 8px 16px; margin-bottom: 16px; }
.detail-grid .label { color: var(--muted); font-size: 13px; font-weight: 700; }
.detail-grid .value { font-size: 14px; word-break: break-word; }
textarea, select, input[type="date"], input[type="datetime-local"], input[type="number"] {
  width: 100%;
  padding: 10px 12px;
  border: 1px solid #dad3c7;
  border-radius: 12px;
  font-size: 14px;
  font-family: inherit;
  background: rgba(255,255,255,0.92);
  color: var(--text);
}
input[type="text"], input[type="password"] { width: 100%; padding: 10px 12px; border: 1px solid #dad3c7; border-radius: 12px; font-size: 14px; font-family: inherit; background: rgba(255,255,255,0.92); color: var(--text); }
.search-bar { display: flex; gap: 8px; margin-bottom: 16px; }
.search-bar input { flex: 1; }
.pagination { display: flex; gap: 8px; margin-top: 16px; justify-content: center; flex-wrap: wrap; }
.pagination a { padding: 7px 12px; border-radius: 10px; background: #ece5d8; color: #333; text-decoration: none; font-size: 13px; }
.pagination a.active { background: var(--brand); color: #fff; }
.chat-log { max-height: 400px; overflow-y: auto; background: #f7f4ee; border-radius: 14px; padding: 12px; margin: 12px 0; border: 1px solid #ebe3d7; }
.chat-msg { padding: 6px 0; border-bottom: 1px solid #eee; font-size: 13px; }
.chat-msg .sender { font-weight: 700; color: var(--text); }
.chat-msg .text { color: #555; }
.empty { text-align: center; padding: 40px; color: var(--muted); font-size: 15px; }
.grid-2col { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin-bottom: 20px; }
.form-grid { display: grid; grid-template-columns: 140px 1fr; gap: 12px 16px; align-items: center; max-width: 600px; }
.muted { color: var(--muted); }
.mono { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
.table-meta { display: flex; justify-content: space-between; align-items: center; gap: 12px; margin-bottom: 14px; flex-wrap: wrap; }
.progress { height: 8px; border-radius: 999px; background: #ece6dc; overflow: hidden; }
.progress > span { display: block; height: 100%; border-radius: inherit; background: linear-gradient(90deg, var(--brand), #2f9b83); }
.split-stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 14px; }
.soft-panel { background: #f7f3ea; border-radius: 16px; padding: 16px; border: 1px solid #ebe4d8; }
.soft-panel h4 { font-size: 14px; margin-bottom: 10px; color: var(--text); }

@media (max-width: 768px) {
  .menu-toggle { display: flex; }
  .sidebar { transform: translateX(-100%); }
  .sidebar.open { transform: translateX(0); }
  .sidebar-overlay.open { display: block; }
  .main { margin-left: 0; padding: 16px; padding-top: 60px; }
  .page-header { flex-direction: column; }
  .page-title { font-size: 24px; }
  .hero-card .headline { font-size: 24px; }
  .stats-grid { grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 10px; }
  .stat-card { padding: 14px; }
  .stat-card .value { font-size: 22px; }
  .card { padding: 14px; }
  .summary-strip { grid-template-columns: 1fr 1fr; }
  .grid-2col { grid-template-columns: 1fr; }
  .detail-grid { grid-template-columns: 100px 1fr; gap: 6px 12px; }
  .form-grid { grid-template-columns: 1fr; max-width: 100%; }
  .form-grid label { font-weight: 600; margin-top: 4px; }
  .search-bar { flex-direction: column; }
  .search-bar .btn { width: 100%; text-align: center; }
  .btn { padding: 10px 16px; }
  table { font-size: 13px; }
  th, td { padding: 8px; }
}
@media (max-width: 480px) {
  .stats-grid { grid-template-columns: 1fr 1fr; gap: 8px; }
  .summary-strip { grid-template-columns: 1fr; }
  .stat-card { padding: 10px; }
  .stat-card .value { font-size: 18px; }
  .hero-meta { grid-template-columns: 1fr 1fr; }
  .detail-grid { grid-template-columns: 1fr; }
  .detail-grid .label { margin-top: 8px; }
}
</style>
</head>
<body>
<button class="menu-toggle" onclick="document.querySelector('.sidebar').classList.toggle('open');document.querySelector('.sidebar-overlay').classList.toggle('open')">&#9776;</button>
<div class="sidebar-overlay" onclick="document.querySelector('.sidebar').classList.remove('open');this.classList.remove('open')"></div>
<nav class="sidebar">
  <h2>Tichu Admin</h2>
  <a href="/tc-backstage/" class="${activePage === 'home' ? 'active' : ''}" onclick="closeSidebar()">대시보드</a>
  <a href="/tc-backstage/stats" class="${activePage === 'stats' ? 'active' : ''}" onclick="closeSidebar()">통계</a>
  <a href="/tc-backstage/inquiries" class="${activePage === 'inquiries' ? 'active' : ''}" onclick="closeSidebar()">문의</a>
  <a href="/tc-backstage/shop" class="${activePage === 'shop' ? 'active' : ''}" onclick="closeSidebar()">상점</a>
  <a href="/tc-backstage/reports" class="${activePage === 'reports' ? 'active' : ''}" onclick="closeSidebar()">신고</a>
  <a href="/tc-backstage/users" class="${activePage === 'users' ? 'active' : ''}" onclick="closeSidebar()">유저</a>
  <a href="/tc-backstage/maintenance" class="${activePage === 'maintenance' ? 'active' : ''}" onclick="closeSidebar()">점검</a>
  <a href="/tc-backstage/settings" class="${activePage === 'settings' ? 'active' : ''}" onclick="closeSidebar()">설정</a>
  <div class="logout">
    <a href="/tc-backstage/logout">로그아웃</a>
  </div>
</nav>
<main class="main">
<div class="page-shell">
${content}
</div>
</main>
<script>function closeSidebar(){document.querySelector('.sidebar').classList.remove('open');document.querySelector('.sidebar-overlay').classList.remove('open')}</script>
</body>
</html>`;
}

function loginPage(error = '') {
  return `<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Admin Login - Tichu</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #1a1a2e; display: flex; align-items: center; justify-content: center; min-height: 100vh; }
.login-box { background: #fff; border-radius: 16px; padding: 40px; width: 360px; max-width: 90vw; box-shadow: 0 8px 32px rgba(0,0,0,0.3); }
.login-box h2 { text-align: center; margin-bottom: 24px; color: #1a1a2e; }
.login-box input { width: 100%; padding: 12px; border: 1px solid #ddd; border-radius: 8px; font-size: 14px; margin-bottom: 12px; }
.login-box button { width: 100%; padding: 12px; background: #6c63ff; color: #fff; border: none; border-radius: 8px; font-size: 16px; font-weight: 600; cursor: pointer; }
.login-box button:hover { background: #5a52e0; }
.error { color: #e53935; font-size: 13px; text-align: center; margin-bottom: 12px; }
</style>
</head>
<body>
<form class="login-box" method="POST" action="/tc-backstage/login">
  <h2>Tichu Admin</h2>
  ${error ? `<div class="error">${error}</div>` : ''}
  <input type="text" name="username" placeholder="아이디" required autofocus>
  <input type="password" name="password" placeholder="비밀번호" required>
  <button type="submit">로그인</button>
</form>
</body>
</html>`;
}

function categoryBadge(cat) {
  const map = { bug: '버그', suggestion: '건의', other: '기타' };
  return `<span class="badge badge-${cat}">${map[cat] || cat}</span>`;
}

function statusBadge(status) {
  const statusMap = { pending: '대기', resolved: '처리됨', reviewed: '검토됨' };
  return `<span class="badge badge-${status}">${statusMap[status] || status}</span>`;
}

function deviceBadge(platform) {
  if (!platform) return '<span style="color:#ccc">-</span>';
  const p = platform.toLowerCase();
  if (p === 'ios') return '<span class="badge" style="background:#e3f2fd;color:#1565c0;font-size:11px;padding:2px 8px">iOS</span>';
  if (p === 'android') return '<span class="badge" style="background:#e8f5e9;color:#2e7d32;font-size:11px;padding:2px 8px">AOS</span>';
  return `<span class="badge" style="background:#f5f5f5;color:#888;font-size:11px;padding:2px 8px">${escapeHtml(platform)}</span>`;
}

function formatDate(d) {
  if (!d) return '-';
  const dt = new Date(d);
  return dt.toLocaleString('ko-KR', { timeZone: 'Asia/Seoul' });
}

function formatDateInput(d) {
  if (!d) return '';
  const dt = new Date(d);
  if (isNaN(dt.getTime())) return '';
  const yyyy = dt.getFullYear();
  const mm = String(dt.getMonth() + 1).padStart(2, '0');
  const dd = String(dt.getDate()).padStart(2, '0');
  return `${yyyy}-${mm}-${dd}`;
}

function pagination(page, total, limit, baseUrl) {
  const totalPages = Math.ceil(total / limit);
  if (totalPages <= 1) return '';
  let out = '<div class="pagination">';
  for (let i = 1; i <= totalPages; i++) {
    const sep = baseUrl.includes('?') ? '&' : '?';
    out += `<a href="${baseUrl}${sep}page=${i}" class="${i === page ? 'active' : ''}">${i}</a>`;
  }
  out += '</div>';
  return out;
}

function escapeHtml(str) {
  if (!str) return '';
  return String(str).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function formatNumber(value) {
  const num = Number(value || 0);
  return Number.isFinite(num) ? num.toLocaleString('ko-KR') : '0';
}

function formatPercent(value, digits = 0) {
  const num = Number(value || 0);
  return `${num.toFixed(digits)}%`;
}

function pageHeader(title, subtitle = '', actions = '') {
  return `
    <div class="page-header">
      <div>
        <h1 class="page-title">${title}</h1>
        ${subtitle ? `<div class="page-subtitle">${subtitle}</div>` : ''}
      </div>
      ${actions ? `<div class="header-actions">${actions}</div>` : ''}
    </div>
  `;
}

function summaryStrip(items) {
  return `
    <div class="summary-strip">
      ${items.map(item => `
        <div class="summary-item">
          <div class="k">${escapeHtml(item.label)}</div>
          <div class="v"${item.valueColor ? ` style="color:${item.valueColor}"` : ''}>${item.value}</div>
          ${item.meta ? `<div class="meta">${item.meta}</div>` : ''}
        </div>
      `).join('')}
    </div>
  `;
}

function metricLine(name, value) {
  return `<div class="metric-inline"><span class="name">${escapeHtml(name)}</span><span class="num">${value}</span></div>`;
}

// ===== Shop form helpers =====

function formatDatetimeLocal(d) {
  if (!d) return '';
  const dt = new Date(d);
  if (isNaN(dt.getTime())) return '';
  const pad = n => String(n).padStart(2, '0');
  return `${dt.getFullYear()}-${pad(dt.getMonth() + 1)}-${pad(dt.getDate())}T${pad(dt.getHours())}:${pad(dt.getMinutes())}`;
}

function shopForm(action, values, isEdit = false) {
  const v = (key, def = '') => {
    const val = values[key];
    if (val === undefined || val === null) return def;
    return val;
  };
  const checked = (key, def = false) => {
    const val = values[key];
    if (val === undefined || val === null) return def ? 'checked' : '';
    if (val === 'on' || val === true || val === 't') return 'checked';
    return '';
  };
  const categories = ['banner', 'title', 'theme', 'card_skin', 'utility'];
  const categoryOptions = categories.map(c =>
    `<option value="${c}" ${v('category') === c ? 'selected' : ''}>${c}</option>`
  ).join('');

  return `<form method="POST" action="${action}">
    <div class="form-grid">
      <label>아이템 키</label>
      <input type="text" name="item_key" value="${escapeHtml(v('item_key'))}" ${isEdit ? 'readonly style="background:#f0f0f0"' : 'required'} placeholder="예: banner_new">
      <label>이름</label>
      <input type="text" name="name" value="${escapeHtml(v('name'))}" required placeholder="아이템 이름">
      <label>분류</label>
      <select name="category" style="padding:10px;border:1px solid #ddd;border-radius:8px;font-size:14px">${categoryOptions}</select>
      <label>가격</label>
      <input type="number" name="price" value="${v('price', 0)}" min="0" style="padding:10px;border:1px solid #ddd;border-radius:8px;font-size:14px">
      <label>영구</label>
      <input type="checkbox" name="is_permanent" ${checked('is_permanent', true)} style="width:20px;height:20px">
      <label>기간 (일)</label>
      <input type="number" name="duration_days" value="${v('duration_days', '')}" min="1" style="padding:10px;border:1px solid #ddd;border-radius:8px;font-size:14px" placeholder="영구 아이템이면 비워두세요">
      <label>구매 가능</label>
      <input type="checkbox" name="is_purchasable" ${checked('is_purchasable', true)} style="width:20px;height:20px">
      <label>시즌 아이템</label>
      <input type="checkbox" name="is_season" ${checked('is_season', false)} style="width:20px;height:20px">
      <label>효과 유형</label>
      <input type="text" name="effect_type" value="${escapeHtml(v('effect_type', ''))}" placeholder="예: leave_count_reduce">
      <label>효과 수치</label>
      <input type="number" name="effect_value" value="${v('effect_value', '')}" style="padding:10px;border:1px solid #ddd;border-radius:8px;font-size:14px">
      <label>판매 시작</label>
      <input type="datetime-local" name="sale_start" value="${formatDatetimeLocal(v('sale_start'))}" style="padding:10px;border:1px solid #ddd;border-radius:8px;font-size:14px">
      <label>판매 종료</label>
      <input type="datetime-local" name="sale_end" value="${formatDatetimeLocal(v('sale_end'))}" style="padding:10px;border:1px solid #ddd;border-radius:8px;font-size:14px">
    </div>
    <div style="margin-top:16px">
      <button type="submit" class="btn btn-primary">${isEdit ? '저장' : '추가'}</button>
    </div>
  </form>`;
}

function parseShopFormBody(body) {
  return {
    item_key: body.item_key || '',
    name: body.name || '',
    category: body.category || 'banner',
    price: parseInt(body.price) || 0,
    is_permanent: body.is_permanent === 'on',
    duration_days: body.duration_days ? parseInt(body.duration_days) : null,
    is_purchasable: body.is_purchasable === 'on',
    is_season: body.is_season === 'on',
    effect_type: body.effect_type || null,
    effect_value: body.effect_value ? parseInt(body.effect_value) : null,
    sale_start: body.sale_start || null,
    sale_end: body.sale_end || null,
  };
}

// ===== Route handler =====

async function handleAdminRoute(req, res, url, pathname, method, lobby, wss, maintenanceFns = {}) {
  const { getMaintenanceConfig, setMaintenanceConfig, getMaintenanceStatus, sendPushNotification } = maintenanceFns;
  // Login page (no auth required)
  if (pathname === '/tc-backstage/login') {
    if (method === 'GET') {
      return html(res, loginPage());
    }
    if (method === 'POST') {
      const body = await parseBody(req);
      const admin = await verifyAdmin(body.username || '', body.password || '');
      if (!admin) {
        return html(res, loginPage('잘못된 로그인 정보입니다'));
      }
      const token = crypto.randomBytes(32).toString('hex');
      sessions.set(token, { username: admin.username, createdAt: Date.now() });
      setSessionCookie(res, token);
      return redirect(res, '/tc-backstage/');
    }
  }

  // Logout
  if (pathname === '/tc-backstage/logout') {
    const cookie = req.headers.cookie || '';
    const match = cookie.match(/tc_admin_session=([^;]+)/);
    if (match) sessions.delete(match[1]);
    clearSessionCookie(res);
    return redirect(res, '/tc-backstage/login');
  }

  // All other routes require auth
  const sessionInfo = getSessionFromCookie(req);
  if (!sessionInfo) {
    return redirect(res, '/tc-backstage/login');
  }
  sessionInfo.session.createdAt = Date.now();
  setSessionCookie(res, sessionInfo.token);

  // Dashboard home
  if (pathname === '/tc-backstage/' || pathname === '/tc-backstage') {
    const stats = await getDashboardStats();
    // Get live data from lobby/wss
    const connectedUsers = wss ? wss.clients.size : 0;
    const allRooms = lobby ? lobby.getRoomList() : [];
    const activeRooms = allRooms.length;
    const gamingRooms = allRooms.filter(r => r.gameInProgress).length;
    const waitingRooms = activeRooms - gamingRooms;
    const totalSpectators = allRooms.reduce((s, r) => s + (r.spectatorCount || 0), 0);

    // Chart data
    const last7 = [];
    for (let i = 6; i >= 0; i--) {
      const d = new Date(); d.setDate(d.getDate() - i);
      last7.push(d.toISOString().split('T')[0]);
    }
    const gamesByDay = {};
    const rankedByDay = {};
    const signupsByDay = {};
    const tichuByDay = {};
    const skByDay = {};
    for (const d of last7) { gamesByDay[d] = 0; rankedByDay[d] = 0; signupsByDay[d] = 0; tichuByDay[d] = 0; skByDay[d] = 0; }
    for (const r of stats.dailyGames) {
      const d = new Date(r.day).toISOString().split('T')[0];
      gamesByDay[d] = parseInt(r.cnt) || 0;
      rankedByDay[d] = parseInt(r.ranked_cnt) || 0;
      tichuByDay[d] = parseInt(r.tichu_cnt) || 0;
      skByDay[d] = parseInt(r.sk_cnt) || 0;
    }
    for (const r of stats.dailySignups) {
      const d = new Date(r.day).toISOString().split('T')[0];
      signupsByDay[d] = parseInt(r.cnt) || 0;
    }
    const chartLabels = last7.map(d => d.slice(5)); // MM-DD
    const chartGames = last7.map(d => gamesByDay[d]);
    const chartTichu = last7.map(d => tichuByDay[d]);
    const chartSK = last7.map(d => skByDay[d]);
    const chartRanked = last7.map(d => rankedByDay[d]);
    const chartSignups = last7.map(d => signupsByDay[d]);
    const adRewardsByDay = {};
    for (const d of last7) { adRewardsByDay[d] = 0; }
    for (const r of (stats.dailyAdRewards || [])) {
      const d = new Date(r.day).toISOString().split('T')[0];
      adRewardsByDay[d] = parseInt(r.cnt) || 0;
    }
    const chartAdRewards = last7.map(d => adRewardsByDay[d]);
    const maxGames = Math.max(...chartGames, 1);
    const maxSignups = Math.max(...chartSignups, 1);
    const maxAdRewards = Math.max(...chartAdRewards, 1);

    function miniBar(values, max, color, label) {
      return `<div style="display:flex;align-items:flex-end;gap:6px;height:80px;padding:8px 0">
        ${values.map((v, i) => {
          const h = Math.max(v / max * 60, 2);
          return `<div style="display:flex;flex-direction:column;align-items:center;flex:1;gap:2px">
            <span style="font-size:10px;color:#666">${v}</span>
            <div style="width:100%;max-width:28px;height:${h}px;background:${color};border-radius:4px 4px 0 0;transition:height 0.3s"></div>
            <span style="font-size:9px;color:#aaa">${label[i]}</span>
          </div>`;
        }).join('')}
      </div>`;
    }
    function stackedBar(tichuVals, skVals, max, label) {
      return `<div style="display:flex;align-items:flex-end;gap:6px;height:80px;padding:8px 0">
        ${tichuVals.map((t, i) => {
          const s = skVals[i];
          const total = t + s;
          const ht = Math.max(t / max * 60, t > 0 ? 2 : 0);
          const hs = Math.max(s / max * 60, s > 0 ? 2 : 0);
          return `<div style="display:flex;flex-direction:column;align-items:center;flex:1;gap:2px">
            <span style="font-size:10px;color:#666">${total}</span>
            <div style="width:100%;max-width:28px;display:flex;flex-direction:column-reverse">
              ${t > 0 ? `<div style="height:${ht}px;background:#6c63ff;border-radius:${s > 0 ? '0' : '4px 4px'} 0 0;transition:height 0.3s" title="티츄 ${t}"></div>` : ''}
              ${s > 0 ? `<div style="height:${hs}px;background:#ff7043;border-radius:4px 4px ${t > 0 ? '0 0' : '0 0'};transition:height 0.3s" title="SK ${s}"></div>` : ''}
            </div>
            <span style="font-size:9px;color:#aaa">${label[i]}</span>
          </div>`;
        }).join('')}
      </div>`;
    }

    // Gold economy
    const totalGold = parseInt(stats.goldStats?.total_gold) || 0;
    const avgGold = Math.round(parseFloat(stats.goldStats?.avg_gold) || 0);
    const maxGold = parseInt(stats.goldStats?.max_gold) || 0;
    const totalPurchased = parseInt(stats.shopStats?.total_purchased) || 0;
    const uniqueBuyers = parseInt(stats.shopStats?.unique_buyers) || 0;
    const adTotalClaims = parseInt(stats.adRewardStats?.total_claims) || 0;
    const adUniqueUsers = parseInt(stats.adRewardStats?.unique_users) || 0;
    const adTodayClaims = parseInt(stats.adRewardStats?.today_claims) || 0;
    const adTodayUsers = parseInt(stats.adRewardStats?.today_users) || 0;
    const totalLeaves = parseInt(stats.leaveStats?.total_leaves) || 0;
    const problemUsers = parseInt(stats.leaveStats?.problem_users) || 0;
    const reports30d = parseInt(stats.reportStats30d?.total_reports) || 0;
    const uniqueReported30d = parseInt(stats.reportStats30d?.unique_reported) || 0;
    const serverStartedAtText = formatDate(serverStartedAt);
    const activeRatio24h = stats.totalUsers > 0 ? (stats.activeUsers24h / stats.totalUsers) * 100 : 0;
    const rankedShareToday = stats.todayGames > 0 ? (stats.rankedMatchesToday / stats.todayGames) * 100 : 0;
    const avgSpectatorsPerRoom = activeRooms > 0 ? totalSpectators / activeRooms : 0;
    const issueLoad = stats.totalUsers > 0 ? ((stats.pendingInquiries + stats.pendingReports) / stats.totalUsers) * 100 : 0;

    // Recent matches table
    let matchesTable = '';
    if (stats.recentMatches.length > 0) {
      matchesTable = `<div class="table-wrap"><table>
        <tr><th>ID</th><th>게임</th><th>결과</th><th>점수/플레이어</th><th>유형</th><th>종료</th><th>날짜</th></tr>
        ${stats.recentMatches.map(m => {
          const endReason = m.end_reason || 'normal';
          let endBadge = '<span class="badge" style="background:#e8f5e9;color:#2e7d32">정상</span>';
          if (endReason === 'leave') {
            endBadge = `<span class="badge" style="background:#fce4ec;color:#c62828">이탈</span>${m.deserter_nickname ? `<br><span style="font-size:11px;color:#c62828">${escapeHtml(m.deserter_nickname)}</span>` : ''}`;
          } else if (endReason === 'timeout') {
            endBadge = `<span class="badge" style="background:#fff8e1;color:#f57f17">시간초과</span>${m.deserter_nickname ? `<br><span style="font-size:11px;color:#f57f17">${escapeHtml(m.deserter_nickname)}</span>` : ''}`;
          }
          const rankedBadge = m.is_ranked ? '<span class="badge" style="background:#fff3e0;color:#e65100">랭크</span>' : '<span class="badge" style="background:#f5f5f5;color:#999">일반</span>';
          if (m.game_type === 'skull_king') {
            return `<tr>
            <td>${m.id}</td>
            <td><span class="badge" style="background:#ff7043;color:#fff">SK</span></td>
            <td><span class="badge" style="background:#fff3e0;color:#e65100">${m.player_a2 || '?'}인</span></td>
            <td colspan="1" style="font-size:12px">${m.player_a1 ? escapeHtml(m.player_a1) : '-'}</td>
            <td>${rankedBadge}</td>
            <td>${endBadge}</td>
            <td style="font-size:12px;color:#888">${formatDate(m.created_at)}</td>
          </tr>`;
          }
          const isDraw = m.team_a_score === m.team_b_score;
          const winBadge = isDraw
            ? '<span class="badge" style="background:#f5f5f5;color:#888">무승부</span>'
            : m.winner_team === 'A'
              ? '<span class="badge" style="background:#ffebee;color:#c62828">A 승</span>'
              : '<span class="badge" style="background:#e3f2fd;color:#1565c0">B 승</span>';
          const aStyle = !isDraw && m.winner_team === 'A' ? 'font-weight:700;color:#c62828' : '';
          const bStyle = !isDraw && m.winner_team === 'B' ? 'font-weight:700;color:#1565c0' : '';
          return `<tr>
          <td>${m.id}</td>
          <td><span class="badge" style="background:#6c63ff;color:#fff">티츄</span></td>
          <td>${winBadge}</td>
          <td style="font-size:12px"><span style="${aStyle}">${m.team_a_score}</span> : <span style="${bStyle}">${m.team_b_score}</span><br><span style="${aStyle}">${escapeHtml(m.player_a1)}, ${escapeHtml(m.player_a2)}</span> vs <span style="${bStyle}">${escapeHtml(m.player_b1)}, ${escapeHtml(m.player_b2)}</span></td>
          <td>${rankedBadge}</td>
          <td>${endBadge}</td>
          <td style="font-size:12px;color:#888">${formatDate(m.created_at)}</td>
        </tr>`;
        }).join('')}
      </table></div>`;
    } else {
      matchesTable = '<div class="empty">최근 매치 없음</div>';
    }

    // Top players table
    let topPlayersTable = '';
    if (stats.topPlayers.length > 0) {
      topPlayersTable = `<div class="table-wrap"><table>
        <tr><th>#</th><th>닉네임</th><th>레이팅</th><th>시즌</th><th>승/패</th><th>게임</th><th>Lv</th></tr>
        ${stats.topPlayers.map((p, i) => {
          const medal = i === 0 ? '🥇' : i === 1 ? '🥈' : i === 2 ? '🥉' : `${i + 1}`;
          const winRate = p.total_games > 0 ? Math.round(p.wins / p.total_games * 100) : 0;
          return `<tr>
            <td style="text-align:center">${medal}</td>
            <td><a href="/tc-backstage/users/${encodeURIComponent(p.nickname)}" style="color:#6c63ff;text-decoration:none;font-weight:600">${escapeHtml(p.nickname)}</a></td>
            <td style="font-weight:700">${p.rating}</td>
            <td>${p.season_rating}</td>
            <td>${p.wins}승 / ${p.losses}패 <span style="color:#888;font-size:12px">(${winRate}%)</span></td>
            <td>${p.total_games}</td>
            <td>${p.level}</td>
          </tr>`;
        }).join('')}
      </table></div>`;
    }

    // Active rooms table
    let roomsTable = '';
    if (allRooms.length > 0) {
      roomsTable = `<div class="table-wrap"><table>
        <tr><th>방</th><th>방장</th><th>인원</th><th>상태</th><th>유형</th><th>관전</th></tr>
        ${allRooms.map(r => `<tr>
          <td><a href="/tc-backstage/rooms/${encodeURIComponent(r.id)}" style="color:#6c63ff;text-decoration:none;font-weight:600">${escapeHtml(r.name)}</a></td>
          <td>${escapeHtml(r.hostName)}</td>
          <td>${r.playerCount}/4</td>
          <td>${r.gameInProgress
            ? '<span class="badge badge-resolved">게임 중</span>'
            : '<span class="badge badge-pending">대기 중</span>'}</td>
          <td>${r.isRanked ? '<span class="badge" style="background:#fff3e0;color:#e65100">랭크</span>' : '일반'}</td>
          <td>${r.spectatorCount || 0}</td>
        </tr>`).join('')}
      </table></div>`;
    } else {
      roomsTable = '<div class="empty">활성 방 없음</div>';
    }

    const content = `
      ${pageHeader(
        '대시보드',
        '실시간 운영 상태와 최근 7일 흐름을 한 화면에서 확인할 수 있도록 재구성했습니다. 급한 이슈, 활성도, 경제 지표를 먼저 보고 상세 표로 내려가는 구조입니다.',
        `
          <a href="/tc-backstage/inquiries" class="btn btn-secondary">문의 확인</a>
          <a href="/tc-backstage/reports" class="btn btn-secondary">신고 확인</a>
          <a href="/tc-backstage/users" class="btn btn-primary">유저 관리</a>
        `
      )}

      <div class="hero-card">
        <div class="eyebrow">Operations Snapshot</div>
        <div class="headline">지금은 ${connectedUsers}명이 접속 중이고, ${stats.todayGames}개의 게임이 오늘 생성되었습니다.</div>
        <div class="sub">운영 우선순위는 미처리 문의 ${stats.pendingInquiries}건, 신고 ${stats.pendingReports}건, 그리고 최근 30일 기준 문제 유저 ${uniqueReported30d}명입니다.</div>
        <div class="hero-meta">
          <div class="item"><div class="k">서버 시작</div><div class="v" style="font-size:18px">${serverStartedAtText}</div></div>
          <div class="item"><div class="k">활성 방</div><div class="v">${activeRooms}</div></div>
          <div class="item"><div class="k">신규 가입</div><div class="v">+${stats.newUsersToday}</div></div>
          <div class="item"><div class="k">랭크 비중</div><div class="v">${formatPercent(rankedShareToday)}</div></div>
        </div>
      </div>

      ${summaryStrip([
        { label: '24시간 활성률', value: formatPercent(activeRatio24h), meta: `${formatNumber(stats.activeUsers24h)} / ${formatNumber(stats.totalUsers)} 유저` },
        { label: '대기 이슈 밀도', value: formatPercent(issueLoad, 1), meta: `문의 ${formatNumber(stats.pendingInquiries)}건 · 신고 ${formatNumber(stats.pendingReports)}건`, valueColor: issueLoad > 5 ? '#c0563f' : '#1f2328' },
        { label: '관전 집중도', value: formatPercent(avgSpectatorsPerRoom * 100 / 4, 0), meta: `방당 평균 ${avgSpectatorsPerRoom.toFixed(1)}명 관전` },
        { label: '광고 참여자', value: formatNumber(adTodayUsers), meta: `오늘 ${formatNumber(adTodayClaims)}회 시청` }
      ])}

      <div class="section-label">실시간 서버 상태</div>
      <div class="stats-grid" style="grid-template-columns:repeat(auto-fit, minmax(170px, 1fr))">
        <a href="/tc-backstage/online?filter=connected" class="stat-card" style="text-decoration:none;cursor:pointer"><div class="label">접속 중</div><div class="value purple">${formatNumber(connectedUsers)}</div><div class="kpi-note">소켓 연결 기준 현재 세션</div></a>
        <a href="/tc-backstage/online?filter=ingame" class="stat-card" style="text-decoration:none;cursor:pointer"><div class="label">게임 중 방</div><div class="value green">${formatNumber(gamingRooms)}</div><div class="kpi-note">${formatNumber(activeRooms)}개 활성 방 중 진행 중</div></a>
        <a href="/tc-backstage/online?filter=waiting" class="stat-card" style="text-decoration:none;cursor:pointer"><div class="label">대기 방</div><div class="value orange">${formatNumber(waitingRooms)}</div><div class="kpi-note">매칭 전 또는 준비 단계</div></a>
        <a href="/tc-backstage/online?filter=spectators" class="stat-card" style="text-decoration:none;cursor:pointer"><div class="label">관전 유저</div><div class="value" style="color:#2878b8">${formatNumber(totalSpectators)}</div><div class="kpi-note">방당 평균 ${avgSpectatorsPerRoom.toFixed(1)}명</div></a>
      </div>

      <div class="section-label">유저와 매치 현황</div>
      <div class="stats-grid" style="grid-template-columns:repeat(auto-fit, minmax(170px, 1fr))">
        <div class="stat-card"><div class="label">전체 유저</div><div class="value">${formatNumber(stats.totalUsers)}</div><div class="kpi-note">오늘 +${formatNumber(stats.newUsersToday)} 가입</div></div>
        <div class="stat-card"><div class="label">활성 (24시간)</div><div class="value">${formatNumber(stats.activeUsers24h)}</div><div class="kpi-note">7일 활성 ${formatNumber(stats.activeUsers7d)}명</div></div>
        <div class="stat-card"><div class="label">총 매치</div><div class="value">${formatNumber(stats.totalMatches)}</div><div class="kpi-note">오늘 게임 ${formatNumber(stats.todayGames)}회</div></div>
        <div class="stat-card"><div class="label">오늘 게임</div><div class="value green">${formatNumber(stats.todayGames)}</div><div class="kpi-note"><span style="color:#5f62d6">${formatNumber(stats.todayTichuGames)} 티츄</span> · <span style="color:#ff7043">${formatNumber(stats.todaySKGames)} SK</span></div></div>
        <div class="stat-card"><div class="label">미처리 문의</div><div class="value orange">${formatNumber(stats.pendingInquiries)}</div><div class="kpi-note">사용자 응답 대기 포함</div></div>
        <div class="stat-card"><div class="label">미처리 신고</div><div class="value red">${formatNumber(stats.pendingReports)}</div><div class="kpi-note">최근 30일 ${formatNumber(reports30d)}건 누적</div></div>
      </div>

      <div class="grid-2col">
        <div class="card">
          <h3>일별 게임 (7일)</h3>
          ${stackedBar(chartTichu, chartSK, maxGames, chartLabels)}
          <div style="margin-top:4px;font-size:11px;color:#888">
            <span style="display:inline-block;width:10px;height:10px;background:#6c63ff;border-radius:2px;margin-right:4px"></span>티츄
            <span style="display:inline-block;width:10px;height:10px;background:#ff7043;border-radius:2px;margin:0 4px 0 8px"></span>SK
          </div>
          <div style="margin-top:8px">
            <h3 style="font-size:14px">일별 랭크</h3>
            ${miniBar(chartRanked, maxGames, '#ff9800', chartLabels)}
          </div>
        </div>
        <div class="card">
          <h3>일별 신규 가입 (7일)</h3>
          ${miniBar(chartSignups, maxSignups, '#4caf50', chartLabels)}
        </div>
      </div>

      <div class="grid-2col">
        <div class="card">
          <h3>경제</h3>
          <div class="split-stats">
            <div class="soft-panel"><h4>보유 자산</h4>${metricLine('총 골드', `<span style="color:#d07a16">${formatNumber(totalGold)}</span>`)}${metricLine('평균 골드', formatNumber(avgGold))}${metricLine('최대 보유', `<span style="color:#b35b19">${formatNumber(maxGold)}</span>`)}</div>
            <div class="soft-panel"><h4>구매 전환</h4>${metricLine('상점 구매', formatNumber(totalPurchased))}${metricLine('구매 유저', formatNumber(uniqueBuyers))}${metricLine('유저당 구매', uniqueBuyers > 0 ? (totalPurchased / uniqueBuyers).toFixed(1) : '0')}</div>
          </div>
        </div>
        <div class="card">
          <h3>건강도</h3>
          <div class="split-stats">
            <div class="soft-panel"><h4>플레이 이탈</h4>${metricLine('총 이탈', `<span style="color:#c0563f">${formatNumber(totalLeaves)}</span>`)}${metricLine('3회 이상 유저', `<span style="color:#a13a2f">${formatNumber(problemUsers)}</span>`)}${metricLine('고위험 비율', stats.totalUsers > 0 ? formatPercent((problemUsers / stats.totalUsers) * 100, 1) : '0%')}</div>
            <div class="soft-panel"><h4>신고 추세</h4>${metricLine('30일 신고', formatNumber(reports30d))}${metricLine('피신고 유저', formatNumber(uniqueReported30d))}${metricLine('유저당 평균', uniqueReported30d > 0 ? (reports30d / uniqueReported30d).toFixed(1) : '0')}</div>
          </div>
        </div>
      </div>

      <div class="grid-2col">
        <div class="card">
          <h3>광고 보상</h3>
          <div class="split-stats">
            <div class="soft-panel"><h4>오늘</h4>${metricLine('시청 횟수', `<span style="color:#2e8b57">${formatNumber(adTodayClaims)}</span>`)}${metricLine('참여 유저', formatNumber(adTodayUsers))}${metricLine('지급 골드', `<span style="color:#d07a16">${formatNumber(adTodayClaims * 50)}</span>`)}</div>
            <div class="soft-panel"><h4>누적</h4>${metricLine('총 시청', `<span style="color:#256b43">${formatNumber(adTotalClaims)}</span>`)}${metricLine('누적 참여 유저', formatNumber(adUniqueUsers))}${metricLine('총 지급 골드', `<span style="color:#b35b19">${formatNumber(adTotalClaims * 50)}</span>`)}</div>
          </div>
        </div>
        <div class="card">
          <h3>일별 광고 시청 (7일)</h3>
          ${miniBar(chartAdRewards, maxAdRewards, '#43a047', chartLabels)}
        </div>
      </div>

      <div class="card">
        <h3>활성 방 <span style="font-size:13px;color:#888;font-weight:400">(${activeRooms})</span></h3>
        <div class="table-meta">
          <div class="muted">진행 중 방, 대기 방, 랭크 여부와 관전 수를 함께 표시합니다.</div>
          <a href="/tc-backstage/online?filter=connected" class="btn btn-secondary">접속 유저 보기</a>
        </div>
        ${roomsTable}
      </div>

      <div class="grid-2col">
        <div class="card">
          <h3>상위 10명</h3>
          ${topPlayersTable || '<div class="empty">아직 플레이어 없음</div>'}
        </div>
        <div class="card">
          <h3>최근 매치</h3>
          ${matchesTable}
        </div>
      </div>
    `;
    return html(res, layout('대시보드', content, 'home'));
  }

  if (pathname === '/tc-backstage/stats' && method === 'GET') {
    const now = new Date();
    const defaultTo = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59);
    const defaultFrom = new Date(defaultTo);
    defaultFrom.setDate(defaultFrom.getDate() - 6);
    defaultFrom.setHours(0, 0, 0, 0);

    const fromParam = url.searchParams.get('from');
    const toParam = url.searchParams.get('to');
    const bucket = url.searchParams.get('bucket') === 'hour' ? 'hour' : 'day';
    const from = fromParam ? new Date(`${fromParam}T00:00:00+09:00`) : defaultFrom;
    const to = toParam ? new Date(`${toParam}T23:59:59+09:00`) : defaultTo;

    const stats = await getDetailedAdminStats(from.toISOString(), to.toISOString(), bucket);
    const summary = stats.summary || {};
    const gameSeries = stats.gameSeries || [];
    const goldSeries = stats.goldSeries || [];
    const shopSalesSeries = stats.shopSalesSeries || [];
    const topShopItems = stats.topShopItems || [];
    const fromValue = formatDateInput(from);
    const toValue = formatDateInput(to);

    const summaryCards = summaryStrip([
      { label: '전체 게임', value: formatNumber(summary.totalGames || 0), meta: `${fromValue} ~ ${toValue}` },
      { label: '티츄', value: formatNumber(summary.tichuGames || 0), valueColor: '#5f62d6', meta: summary.totalGames ? formatPercent((summary.tichuGames || 0) * 100 / summary.totalGames, 1) : '0%' },
      { label: '스컬킹', value: formatNumber(summary.skullGames || 0), valueColor: '#138072', meta: summary.totalGames ? formatPercent((summary.skullGames || 0) * 100 / summary.totalGames, 1) : '0%' },
      { label: '랭크전', value: formatNumber(summary.rankedGames || 0), valueColor: '#c67b2b', meta: summary.totalGames ? formatPercent((summary.rankedGames || 0) * 100 / summary.totalGames, 1) : '0%' },
      { label: '획득 골드', value: formatNumber(summary.goldEarned || 0), valueColor: '#2e8b57' },
      { label: '소모 골드', value: formatNumber(summary.goldSpent || 0), valueColor: '#c0563f' },
      { label: '순변동', value: formatNumber(summary.goldNet || 0), valueColor: (summary.goldNet || 0) >= 0 ? '#1f2328' : '#c0563f' },
      { label: '상점 구매', value: formatNumber(summary.shopPurchases || 0), meta: `구매자 ${formatNumber(summary.shopBuyers || 0)}명` },
      { label: '상점 지출', value: formatNumber(summary.shopGoldSpent || 0), valueColor: '#b35b19', meta: `판매 아이템 ${formatNumber(summary.shopUniqueItems || 0)}종` }
    ]);

    const gameTable = gameSeries.length > 0
      ? `<div class="table-wrap"><table>
          <tr><th>${bucket === 'hour' ? '시간대' : '날짜'}</th><th>전체</th><th>티추</th><th>스컬킹</th><th>랭크전</th></tr>
          ${gameSeries.map(row => `<tr>
            <td>${formatDate(row.bucket_time)}</td>
            <td>${row.total_cnt}</td>
            <td>${row.tichu_cnt}</td>
            <td>${row.skull_cnt}</td>
            <td>${row.ranked_cnt}</td>
          </tr>`).join('')}
        </table></div>`
      : '<div class="empty">게임 데이터가 없습니다</div>';

    const goldTable = goldSeries.length > 0
      ? `<div class="table-wrap"><table>
          <tr><th>${bucket === 'hour' ? '시간대' : '날짜'}</th><th>획득</th><th>소모</th><th>순변동</th></tr>
          ${goldSeries.map(row => `<tr>
            <td>${formatDate(row.bucket_time)}</td>
            <td style="color:#2e7d32;font-weight:600">${row.earned}</td>
            <td style="color:#c62828;font-weight:600">${row.spent}</td>
            <td style="font-weight:700">${row.net}</td>
          </tr>`).join('')}
        </table></div>`
      : '<div class="empty">골드 데이터가 없습니다</div>';

    const shopSalesTable = shopSalesSeries.length > 0
      ? `<div class="table-wrap"><table>
          <tr><th>${bucket === 'hour' ? '시간대' : '날짜'}</th><th>판매 수</th><th>구매자</th><th>지출 골드</th></tr>
          ${shopSalesSeries.map(row => `<tr>
            <td>${formatDate(row.bucket_time)}</td>
            <td style="font-weight:700">${formatNumber(row.purchase_count)}</td>
            <td>${formatNumber(row.buyer_count)}</td>
            <td style="color:#b35b19;font-weight:700">${formatNumber(row.gold_spent)}</td>
          </tr>`).join('')}
        </table></div>`
      : '<div class="empty">상점 판매 데이터가 없습니다</div>';

    const topShopItemsTable = topShopItems.length > 0
      ? `<div class="table-wrap"><table>
          <tr><th>아이템</th><th>분류</th><th>판매 수</th><th>구매자</th><th>지출 골드</th><th>최근 판매</th></tr>
          ${topShopItems.map(item => `<tr>
            <td>
              <div style="font-weight:700">${escapeHtml(item.item_name)}</div>
              <div class="muted mono" style="font-size:11px">${escapeHtml(item.item_key)}</div>
            </td>
            <td>${escapeHtml(item.category || '-')}</td>
            <td style="font-weight:700">${formatNumber(item.purchase_count)}</td>
            <td>${formatNumber(item.buyer_count)}</td>
            <td style="color:#b35b19;font-weight:700">${formatNumber(item.gold_spent)}</td>
            <td style="font-size:12px;color:#888">${formatDate(item.last_sold_at)}</td>
          </tr>`).join('')}
        </table></div>`
      : '<div class="empty">팔린 아이템이 없습니다</div>';

    // Prepare chart data as JSON
    const gameChartLabels = gameSeries.map(r => {
      const d = new Date(r.bucket_time);
      return bucket === 'hour'
        ? `${String(d.getMonth()+1).padStart(2,'0')}/${String(d.getDate()).padStart(2,'0')} ${String(d.getHours()).padStart(2,'0')}시`
        : `${String(d.getMonth()+1).padStart(2,'0')}/${String(d.getDate()).padStart(2,'0')}`;
    });
    const gameChartTichu = gameSeries.map(r => parseInt(r.tichu_cnt) || 0);
    const gameChartSK = gameSeries.map(r => parseInt(r.skull_cnt) || 0);
    const gameChartRanked = gameSeries.map(r => parseInt(r.ranked_cnt) || 0);
    const gameChartTotal = gameSeries.map(r => parseInt(r.total_cnt) || 0);

    const goldChartLabels = goldSeries.map(r => {
      const d = new Date(r.bucket_time);
      return bucket === 'hour'
        ? `${String(d.getMonth()+1).padStart(2,'0')}/${String(d.getDate()).padStart(2,'0')} ${String(d.getHours()).padStart(2,'0')}시`
        : `${String(d.getMonth()+1).padStart(2,'0')}/${String(d.getDate()).padStart(2,'0')}`;
    });
    const goldChartEarned = goldSeries.map(r => parseInt(r.earned) || 0);
    const goldChartSpent = goldSeries.map(r => parseInt(r.spent) || 0);
    const goldChartNet = goldSeries.map(r => parseInt(r.net) || 0);

    const shopChartLabels = shopSalesSeries.map(r => {
      const d = new Date(r.bucket_time);
      return bucket === 'hour'
        ? `${String(d.getMonth()+1).padStart(2,'0')}/${String(d.getDate()).padStart(2,'0')} ${String(d.getHours()).padStart(2,'0')}시`
        : `${String(d.getMonth()+1).padStart(2,'0')}/${String(d.getDate()).padStart(2,'0')}`;
    });
    const shopChartPurchases = shopSalesSeries.map(r => parseInt(r.purchase_count) || 0);
    const shopChartBuyers = shopSalesSeries.map(r => parseInt(r.buyer_count) || 0);
    const shopChartGoldSpent = shopSalesSeries.map(r => parseInt(r.gold_spent) || 0);

    const content = `
      <script src="https://cdn.jsdelivr.net/npm/chart.js@4/dist/chart.umd.min.js"></script>
      ${pageHeader('통계', '기간별 게임량, 골드 흐름, 그리고 상점 판매 추이까지 함께 볼 수 있게 확장했습니다. 이제 어떤 아이템이 언제 팔렸는지도 여기서 바로 확인할 수 있습니다.')}
      <div class="card">
        <h3>조회 조건</h3>
        <form method="GET" action="/tc-backstage/stats" class="search-bar" style="align-items:end;flex-wrap:wrap">
          <div style="min-width:160px">
            <div style="font-size:12px;color:#888;margin-bottom:6px">시작일</div>
            <input type="date" name="from" value="${escapeHtml(fromValue)}">
          </div>
          <div style="min-width:160px">
            <div style="font-size:12px;color:#888;margin-bottom:6px">종료일</div>
            <input type="date" name="to" value="${escapeHtml(toValue)}">
          </div>
          <div style="min-width:140px">
            <div style="font-size:12px;color:#888;margin-bottom:6px">집계 단위</div>
            <select name="bucket" style="padding:10px;border:1px solid #ddd;border-radius:8px;font-size:14px">
              <option value="day"${bucket === 'day' ? ' selected' : ''}>일별</option>
              <option value="hour"${bucket === 'hour' ? ' selected' : ''}>시간대별</option>
            </select>
          </div>
          <button type="submit" class="btn btn-primary">조회</button>
          <a href="/tc-backstage/stats" class="btn btn-secondary">초기화</a>
        </form>
      </div>

      ${summaryCards}

      <div class="grid-2col">
        <div class="card">
          <h3>게임량 추이</h3>
          <div style="position:relative;height:300px"><canvas id="gameChart"></canvas></div>
        </div>
        <div class="card">
          <h3>게임 비율</h3>
          <div style="position:relative;height:300px;display:flex;align-items:center;justify-content:center"><canvas id="gamePieChart"></canvas></div>
        </div>
      </div>

      <div class="card">
        <h3>골드 획득 / 소모</h3>
        <div style="position:relative;height:300px"><canvas id="goldChart"></canvas></div>
      </div>

      <div class="grid-2col">
        <div class="card">
          <h3>상점 판매 추이</h3>
          <div style="position:relative;height:300px"><canvas id="shopSalesChart"></canvas></div>
        </div>
        <div class="card">
          <h3>베스트셀러 아이템</h3>
          ${topShopItemsTable}
        </div>
      </div>

      <div class="grid-2col">
        <div class="card">
          <h3>게임량 상세</h3>
          ${gameTable}
        </div>
        <div class="card">
          <h3>골드 상세</h3>
          ${goldTable}
        </div>
      </div>

      <div class="card">
        <h3>상점 판매 상세</h3>
        ${shopSalesTable}
      </div>

      <script>
      (function() {
        const tooltipStyle = {
          backgroundColor: 'rgba(26,26,46,0.9)',
          titleFont: { size: 13 },
          bodyFont: { size: 12 },
          padding: 10,
          cornerRadius: 8,
        };

        // Game chart - stacked bar
        new Chart(document.getElementById('gameChart'), {
          type: 'bar',
          data: {
            labels: ${JSON.stringify(gameChartLabels)},
            datasets: [
              {
                label: '티츄',
                data: ${JSON.stringify(gameChartTichu)},
                backgroundColor: 'rgba(108,99,255,0.8)',
                borderRadius: 4,
                borderSkipped: false,
              },
              {
                label: '스컬킹',
                data: ${JSON.stringify(gameChartSK)},
                backgroundColor: 'rgba(255,112,67,0.8)',
                borderRadius: 4,
                borderSkipped: false,
              },
              {
                label: '랭크전',
                data: ${JSON.stringify(gameChartRanked)},
                type: 'line',
                borderColor: '#e65100',
                backgroundColor: 'rgba(230,81,0,0.1)',
                borderWidth: 2,
                pointRadius: 4,
                pointBackgroundColor: '#e65100',
                tension: 0.3,
                yAxisID: 'y',
              }
            ]
          },
          options: {
            responsive: true,
            maintainAspectRatio: false,
            interaction: { mode: 'index', intersect: false },
            plugins: {
              tooltip: tooltipStyle,
              legend: { position: 'top', labels: { usePointStyle: true, padding: 16 } },
            },
            scales: {
              x: { stacked: true, grid: { display: false } },
              y: {
                stacked: true,
                beginAtZero: true,
                ticks: { precision: 0 },
                grid: { color: 'rgba(0,0,0,0.05)' },
              },
            },
          }
        });

        // Game pie chart
        const totalTichu = ${JSON.stringify(gameChartTichu)}.reduce((a,b) => a+b, 0);
        const totalSK = ${JSON.stringify(gameChartSK)}.reduce((a,b) => a+b, 0);
        new Chart(document.getElementById('gamePieChart'), {
          type: 'doughnut',
          data: {
            labels: ['티츄 (' + totalTichu + ')', '스컬킹 (' + totalSK + ')'],
            datasets: [{
              data: [totalTichu, totalSK],
              backgroundColor: ['rgba(108,99,255,0.85)', 'rgba(255,112,67,0.85)'],
              borderWidth: 0,
              hoverOffset: 8,
            }]
          },
          options: {
            responsive: true,
            maintainAspectRatio: false,
            cutout: '55%',
            plugins: {
              tooltip: tooltipStyle,
              legend: { position: 'bottom', labels: { usePointStyle: true, padding: 16, font: { size: 13 } } },
            },
          }
        });

        // Gold chart - bar + line
        new Chart(document.getElementById('goldChart'), {
          type: 'bar',
          data: {
            labels: ${JSON.stringify(goldChartLabels)},
            datasets: [
              {
                label: '획득',
                data: ${JSON.stringify(goldChartEarned)},
                backgroundColor: 'rgba(76,175,80,0.7)',
                borderRadius: 4,
                borderSkipped: false,
              },
              {
                label: '소모',
                data: ${JSON.stringify(goldChartSpent)},
                backgroundColor: 'rgba(229,57,53,0.7)',
                borderRadius: 4,
                borderSkipped: false,
              },
              {
                label: '순변동',
                data: ${JSON.stringify(goldChartNet)},
                type: 'line',
                borderColor: '#1565c0',
                backgroundColor: 'rgba(21,101,192,0.1)',
                borderWidth: 2,
                pointRadius: 4,
                pointBackgroundColor: '#1565c0',
                tension: 0.3,
                fill: true,
              }
            ]
          },
          options: {
            responsive: true,
            maintainAspectRatio: false,
            interaction: { mode: 'index', intersect: false },
            plugins: {
              tooltip: tooltipStyle,
              legend: { position: 'top', labels: { usePointStyle: true, padding: 16 } },
            },
            scales: {
              x: { grid: { display: false } },
              y: {
                beginAtZero: true,
                ticks: { precision: 0 },
                grid: { color: 'rgba(0,0,0,0.05)' },
              },
            },
          }
        });

        new Chart(document.getElementById('shopSalesChart'), {
          type: 'bar',
          data: {
            labels: ${JSON.stringify(shopChartLabels)},
            datasets: [
              {
                label: '판매 수',
                data: ${JSON.stringify(shopChartPurchases)},
                backgroundColor: 'rgba(216,140,56,0.75)',
                borderRadius: 4,
                borderSkipped: false,
              },
              {
                label: '구매자 수',
                data: ${JSON.stringify(shopChartBuyers)},
                type: 'line',
                borderColor: '#0f6c5c',
                backgroundColor: 'rgba(15,108,92,0.12)',
                borderWidth: 2,
                pointRadius: 4,
                pointBackgroundColor: '#0f6c5c',
                tension: 0.3,
              },
              {
                label: '지출 골드',
                data: ${JSON.stringify(shopChartGoldSpent)},
                type: 'line',
                borderColor: '#7f4b14',
                backgroundColor: 'rgba(127,75,20,0.12)',
                borderWidth: 2,
                pointRadius: 4,
                pointBackgroundColor: '#7f4b14',
                tension: 0.3,
                yAxisID: 'y1',
              }
            ]
          },
          options: {
            responsive: true,
            maintainAspectRatio: false,
            interaction: { mode: 'index', intersect: false },
            plugins: {
              tooltip: tooltipStyle,
              legend: { position: 'top', labels: { usePointStyle: true, padding: 16 } },
            },
            scales: {
              x: { grid: { display: false } },
              y: {
                beginAtZero: true,
                ticks: { precision: 0 },
                grid: { color: 'rgba(0,0,0,0.05)' },
              },
              y1: {
                beginAtZero: true,
                position: 'right',
                ticks: { precision: 0 },
                grid: { drawOnChartArea: false },
              },
            },
          }
        });
      })();
      </script>
    `;
    return html(res, layout('통계', content, 'stats'));
  }

  // ===== Inquiries =====
  if (pathname === '/tc-backstage/inquiries' && method === 'GET') {
    const page = parseInt(url.searchParams.get('page') || '1');
    const data = await getInquiries(page, 20);
    const pendingCount = data.rows.filter(r => r.status === 'pending').length;
    const resolvedCount = data.rows.filter(r => r.status === 'resolved').length;
    const bugCount = data.rows.filter(r => r.category === 'bug').length;
    const suggestionCount = data.rows.filter(r => r.category === 'suggestion').length;

    let tableContent = '';
    if (data.rows.length > 0) {
      tableContent = `<div class="table-wrap"><table>
        <tr><th>ID</th><th>유저</th><th>분류</th><th>제목</th><th>상태</th><th>날짜</th><th></th></tr>
        ${data.rows.map(r => `<tr>
          <td>${r.id}</td>
          <td>${escapeHtml(r.user_nickname)}</td>
          <td>${categoryBadge(r.category)}</td>
          <td>${escapeHtml(r.title)}</td>
          <td>${statusBadge(r.status)}</td>
          <td>${formatDate(r.created_at)}</td>
          <td><a href="/tc-backstage/inquiries/${r.id}" class="btn btn-secondary">보기</a></td>
        </tr>`).join('')}
      </table></div>
      ${pagination(data.page, data.total, data.limit, '/tc-backstage/inquiries')}`;
    } else {
      tableContent = '<div class="empty">문의 없음</div>';
    }

    const content = `
      ${pageHeader('문의', '최근 접수된 문의를 우선순위 중심으로 살펴볼 수 있도록 상태와 카테고리 분포를 먼저 보여줍니다.')}
      ${summaryStrip([
        { label: '현재 페이지 건수', value: formatNumber(data.rows.length), meta: `전체 ${formatNumber(data.total)}건` },
        { label: '대기', value: formatNumber(pendingCount), valueColor: '#c67b2b', meta: '즉시 확인 필요' },
        { label: '처리 완료', value: formatNumber(resolvedCount), valueColor: '#2e8b57' },
        { label: '버그 문의', value: formatNumber(bugCount), meta: `건의 ${formatNumber(suggestionCount)}건` }
      ])}
      <div class="card">${tableContent}</div>
    `;
    return html(res, layout('문의', content, 'inquiries'));
  }

  // Inquiry detail
  const inquiryMatch = pathname.match(/^\/tc-backstage\/inquiries\/(\d+)$/);
  if (inquiryMatch && method === 'GET') {
    const inquiry = await getInquiryById(parseInt(inquiryMatch[1]));
    if (!inquiry) return html(res, layout('찾을 수 없음', '<div class="empty">문의를 찾을 수 없습니다</div>', 'inquiries'), 404);

    const content = `
      <h1 class="page-title">문의 #${inquiry.id}</h1>
      <div class="card">
        <div class="detail-grid">
          <div class="label">유저</div><div class="value"><a href="/tc-backstage/users/${encodeURIComponent(inquiry.user_nickname)}">${escapeHtml(inquiry.user_nickname)}</a></div>
          <div class="label">분류</div><div class="value">${categoryBadge(inquiry.category)}</div>
          <div class="label">상태</div><div class="value">${statusBadge(inquiry.status)}</div>
          <div class="label">제목</div><div class="value">${escapeHtml(inquiry.title)}</div>
          <div class="label">내용</div><div class="value" style="white-space:pre-wrap">${escapeHtml(inquiry.content)}</div>
          <div class="label">작성일</div><div class="value">${formatDate(inquiry.created_at)}</div>
          ${inquiry.resolved_at ? `<div class="label">처리일</div><div class="value">${formatDate(inquiry.resolved_at)}</div>` : ''}
          ${inquiry.admin_note ? `<div class="label">관리자 메모</div><div class="value" style="white-space:pre-wrap">${escapeHtml(inquiry.admin_note)}</div>` : ''}
        </div>
        ${inquiry.status === 'pending' ? `
        <form method="POST" action="/tc-backstage/inquiries/${inquiry.id}/resolve" style="margin-top:16px">
          <textarea name="admin_note" rows="3" placeholder="관리자 메모 (선택)"></textarea>
          <div style="margin-top:8px"><button type="submit" class="btn btn-success">처리 완료</button></div>
        </form>` : ''}
      </div>
      <a href="/tc-backstage/inquiries" class="btn btn-secondary">목록으로</a>
    `;
    return html(res, layout(`Inquiry #${inquiry.id}`, content, 'inquiries'));
  }

  // Resolve inquiry
  const resolveMatch = pathname.match(/^\/tc-backstage\/inquiries\/(\d+)\/resolve$/);
  if (resolveMatch && method === 'POST') {
    const body = await parseBody(req);
    const resolved = await resolveInquiry(parseInt(resolveMatch[1]), body.admin_note || '');
    if (resolved && resolved.success && resolved.inquiry && sendPushNotification) {
      const targetNickname = resolved.inquiry.user_nickname;
      const user = await getUserDetail(targetNickname);
      if (user && user.fcm_token && user.push_enabled !== false) {
        const title = '문의 답변이 도착했어요';
        const inquiryTitle = resolved.inquiry.title || '';
        const message = inquiryTitle ? `제목: ${inquiryTitle}` : '앱에서 확인해주세요.';
        await sendPushNotification(user.fcm_token, title, message);
      }
    }
    return redirect(res, `/tc-backstage/inquiries/${resolveMatch[1]}`);
  }

  // ===== Reports (grouped by reported_nickname + room_id) =====
  if (pathname === '/tc-backstage/reports' && method === 'GET') {
    const page = parseInt(url.searchParams.get('page') || '1');
    const data = await getReports(page, 20);
    const pendingGroups = data.rows.filter(r => r.group_status === 'pending').length;
    const reviewedGroups = data.rows.filter(r => r.group_status === 'reviewed').length;
    const totalReportsInPage = data.rows.reduce((sum, r) => sum + (parseInt(r.report_count) || 0), 0);
    const repeatedTargets = data.rows.filter(r => (parseInt(r.report_count) || 0) >= 2).length;

    let tableContent = '';
    if (data.rows.length > 0) {
      tableContent = `<div class="table-wrap"><table>
        <tr><th>피신고자</th><th>방</th><th>신고자</th><th>신고수</th><th>상태</th><th>최근</th><th></th></tr>
        ${data.rows.map(r => {
          const cnt = parseInt(r.report_count) || 1;
          const cntBadge = cnt >= 2
            ? `<span class="badge" style="background:#ffebee;color:#c62828;font-weight:700">${cnt}</span>`
            : `<span>${cnt}</span>`;
          const reporters = (r.reporters || []).map(n => escapeHtml(n)).join(', ');
          const detailUrl = `/tc-backstage/reports/group?target=${encodeURIComponent(r.reported_nickname)}&room=${encodeURIComponent(r.room_id || '')}`;
          return `<tr>
          <td><a href="/tc-backstage/users/${encodeURIComponent(r.reported_nickname)}">${escapeHtml(r.reported_nickname)}</a></td>
          <td>${escapeHtml(r.room_id) || '-'}</td>
          <td>${reporters}</td>
          <td>${cntBadge}</td>
          <td>${statusBadge(r.group_status)}</td>
          <td>${formatDate(r.latest_date)}</td>
          <td><a href="${detailUrl}" class="btn btn-secondary">보기</a></td>
        </tr>`;
        }).join('')}
      </table></div>
      ${pagination(data.page, data.total, data.limit, '/tc-backstage/reports')}`;
    } else {
      tableContent = '<div class="empty">신고 없음</div>';
    }

    const content = `
      ${pageHeader('신고', '신고는 대상 유저와 방 기준으로 묶어서 보여주며, 반복 신고와 대기 상태를 먼저 파악할 수 있게 구성했습니다.')}
      ${summaryStrip([
        { label: '그룹 수', value: formatNumber(data.rows.length), meta: `전체 ${formatNumber(data.total)}그룹` },
        { label: '대기 그룹', value: formatNumber(pendingGroups), valueColor: '#c0563f' },
        { label: '검토 중', value: formatNumber(reviewedGroups), valueColor: '#2878b8' },
        { label: '중복 신고 대상', value: formatNumber(repeatedTargets), meta: `현재 페이지 신고 합계 ${formatNumber(totalReportsInPage)}건` }
      ])}
      <div class="card">${tableContent}</div>
    `;
    return html(res, layout('신고', content, 'reports'));
  }

  // Report group detail
  if (pathname === '/tc-backstage/reports/group' && method === 'GET') {
    const target = url.searchParams.get('target') || '';
    const roomId = url.searchParams.get('room') || '';
    if (!target) return html(res, layout('찾을 수 없음', '<div class="empty">신고를 찾을 수 없습니다</div>', 'reports'), 404);

    const reports = await getReportGroup(target, roomId);
    if (reports.length === 0) return html(res, layout('찾을 수 없음', '<div class="empty">신고를 찾을 수 없습니다</div>', 'reports'), 404);

    const groupStatus = reports.some(r => r.status === 'pending') ? 'pending'
      : reports.some(r => r.status === 'reviewed') ? 'reviewed' : 'resolved';

    // Parse chat context from first report that has it
    let chatHtml = '';
    const reportWithChat = reports.find(r => r.chat_context);
    if (reportWithChat) {
      try {
        const chatMessages = JSON.parse(reportWithChat.chat_context);
        if (Array.isArray(chatMessages) && chatMessages.length > 0) {
          chatHtml = `<div class="chat-log">${chatMessages.map(m =>
            `<div class="chat-msg"><span class="sender">${escapeHtml(m.sender || m.nickname)}:</span> <span class="text">${escapeHtml(m.message)}</span></div>`
          ).join('')}</div>`;
        }
      } catch (e) {
        chatHtml = `<div class="chat-log"><pre>${escapeHtml(reportWithChat.chat_context)}</pre></div>`;
      }
    }

    // Individual reports list
    const reportsHtml = reports.map(r => `
      <div style="border:1px solid #eee;border-radius:8px;padding:12px;margin-bottom:8px">
        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:6px">
          <strong><a href="/tc-backstage/users/${encodeURIComponent(r.reporter_nickname)}">${escapeHtml(r.reporter_nickname)}</a></strong>
          <span style="color:#888;font-size:12px">${formatDate(r.created_at)}</span>
        </div>
        <div style="color:#555;font-size:14px;white-space:pre-wrap">${escapeHtml(r.reason)}</div>
      </div>
    `).join('');

    const formUrl = `/tc-backstage/reports/group/status?target=${encodeURIComponent(target)}&room=${encodeURIComponent(roomId)}`;

    const content = `
      <h1 class="page-title">${escapeHtml(target)} 신고 (${reports.length}건)</h1>
      <div class="card">
        <div class="detail-grid">
          <div class="label">피신고자</div><div class="value"><a href="/tc-backstage/users/${encodeURIComponent(target)}">${escapeHtml(target)}</a></div>
          <div class="label">방 ID</div><div class="value">${escapeHtml(roomId) || '-'}</div>
          <div class="label">상태</div><div class="value">${statusBadge(groupStatus)}</div>
          <div class="label">신고 수</div><div class="value"><strong>${reports.length}</strong>건</div>
        </div>
        <h3 style="margin-top:16px">신고자 목록</h3>
        ${reportsHtml}
        ${chatHtml ? `<h3 style="margin-top:16px">채팅 내역</h3>${chatHtml}` : ''}
        ${groupStatus !== 'resolved' ? `
        <form method="POST" action="${formUrl}" style="margin-top:16px">
          <select name="status" style="padding:8px;border-radius:8px;border:1px solid #ddd;font-size:14px">
            <option value="reviewed" ${groupStatus === 'reviewed' ? 'selected' : ''}>검토됨</option>
            <option value="resolved">처리됨</option>
          </select>
          <button type="submit" class="btn btn-primary" style="margin-left:8px">상태 변경</button>
        </form>` : ''}
      </div>
      <a href="/tc-backstage/reports" class="btn btn-secondary">목록으로</a>
    `;
    return html(res, layout(`신고: ${escapeHtml(target)}`, content, 'reports'));
  }

  // Update report group status
  if (pathname === '/tc-backstage/reports/group/status' && method === 'POST') {
    const target = url.searchParams.get('target') || '';
    const roomId = url.searchParams.get('room') || '';
    const body = await parseBody(req);
    const validStatuses = ['pending', 'reviewed', 'resolved'];
    if (target && validStatuses.includes(body.status)) {
      await updateReportGroupStatus(target, roomId, body.status);
    }
    return redirect(res, `/tc-backstage/reports/group?target=${encodeURIComponent(target)}&room=${encodeURIComponent(roomId)}`);
  }

  // ===== Users =====
  if (pathname === '/tc-backstage/users' && method === 'GET') {
    const search = url.searchParams.get('q') || '';
    const page = parseInt(url.searchParams.get('page') || '1');
    const sort = url.searchParams.get('sort') || 'joined_desc';
    const minRating = url.searchParams.get('minRating') || '';
    const minGames = url.searchParams.get('minGames') || '';
    const minLeaves = url.searchParams.get('minLeaves') || '';
    const data = await getUsers(search, page, 20, { sort, minRating, minGames, minLeaves });
    const adminCount = data.rows.filter(u => u.is_admin && !u.is_deleted).length;
    const deletedCount = data.rows.filter(u => u.is_deleted).length;
    const highRiskUsers = data.rows.filter(u => (u.leave_count || 0) >= 3).length;
    const avgRating = data.rows.length > 0 ? Math.round(data.rows.reduce((sum, u) => sum + (parseInt(u.rating) || 0), 0) / data.rows.length) : 0;

    // Build query string for pagination links
    const qs = new URLSearchParams();
    if (search) qs.set('q', search);
    if (sort && sort !== 'joined_desc') qs.set('sort', sort);
    if (minRating) qs.set('minRating', minRating);
    if (minGames) qs.set('minGames', minGames);
    if (minLeaves) qs.set('minLeaves', minLeaves);
    const qsStr = qs.toString();
    const paginationBase = `/tc-backstage/users${qsStr ? '?' + qsStr : ''}`;

    const sortOpts = [
      ['joined_desc', '최신순'],
      ['joined_asc', '오래된순'],
      ['rating_desc', '레이팅 높은순'],
      ['rating_asc', '레이팅 낮은순'],
      ['games_desc', '게임 많은순'],
      ['gold_desc', '골드 많은순'],
      ['level_desc', '레벨 높은순'],
      ['leaves_desc', '이탈 많은순'],
      ['login_desc', '최근 로그인순'],
    ];

    const searchForm = `
      <div class="search-bar">
        <form method="GET" action="/tc-backstage/users" style="display:flex;flex-wrap:wrap;gap:8px;width:100%;align-items:center">
          <input type="text" name="q" placeholder="닉네임 또는 계정명 검색..." value="${escapeHtml(search)}" style="flex:1;min-width:180px">
          <select name="sort" style="padding:8px 10px;border-radius:8px;border:1px solid #ddd;font-size:13px">
            ${sortOpts.map(([v, l]) => `<option value="${v}"${sort === v ? ' selected' : ''}>${l}</option>`).join('')}
          </select>
          <input type="number" name="minRating" placeholder="최소 레이팅" value="${escapeHtml(minRating)}" style="width:100px;padding:8px 10px;border-radius:8px;border:1px solid #ddd;font-size:13px">
          <input type="number" name="minGames" placeholder="최소 게임" value="${escapeHtml(minGames)}" style="width:100px;padding:8px 10px;border-radius:8px;border:1px solid #ddd;font-size:13px">
          <input type="number" name="minLeaves" placeholder="최소 이탈" value="${escapeHtml(minLeaves)}" style="width:100px;padding:8px 10px;border-radius:8px;border:1px solid #ddd;font-size:13px">
          <button type="submit" class="btn btn-primary">검색</button>
          ${qsStr ? `<a href="/tc-backstage/users" class="btn btn-secondary" style="font-size:12px">초기화</a>` : ''}
        </form>
      </div>
    `;

    let tableContent = '';
    if (data.rows.length > 0) {
      tableContent = `<div class="table-wrap"><table>
        <tr><th>닉네임</th><th>권한</th><th>기기</th><th>앱 버전</th><th>Lv</th><th>골드</th><th>레이팅</th><th>게임</th><th>승/패</th><th>이탈</th><th>최근 접속</th><th></th></tr>
        ${data.rows.map(u => {
          const winRate = u.total_games > 0 ? Math.round(u.wins / u.total_games * 100) : 0;
          const leaveStyle = (u.leave_count || 0) >= 3 ? 'color:#e53935;font-weight:600' : '';
          return `<tr>
          <td><a href="/tc-backstage/users/${encodeURIComponent(u.nickname)}" style="color:#6c63ff;text-decoration:none;font-weight:600">${escapeHtml(u.nickname)}</a></td>
          <td>
            ${u.is_deleted ? '<span class="badge" style="background:#ffebee;color:#c62828">탈퇴</span>' : `<span class="badge" style="background:${u.is_admin ? '#ede7f6' : '#f5f5f5'};color:${u.is_admin ? '#5e35b1' : '#888'}">${u.is_admin ? '관리자' : '일반'}</span>`}
          </td>
          <td>${deviceBadge(u.device_platform)}</td>
          <td style="font-size:12px;color:#666">${escapeHtml(u.app_version || '-')}</td>
          <td>${u.level || 1}</td>
          <td style="color:#ff9800;font-weight:600">${(u.gold || 0).toLocaleString()}
            <form method="POST" action="/tc-backstage/users/${encodeURIComponent(u.nickname)}/gold" style="display:inline-flex;gap:2px;margin-left:4px;vertical-align:middle">
              <input type="number" name="amount" placeholder="+/-" style="width:55px;padding:2px 4px;border-radius:4px;border:1px solid #ddd;font-size:11px" required>
              <button type="submit" class="btn btn-primary" style="font-size:10px;padding:2px 6px">Go</button>
            </form>
          </td>
          <td style="font-weight:600">${u.rating}</td>
          <td>${u.total_games}</td>
          <td>${u.wins}승/${u.losses}패 <span style="color:#888;font-size:11px">(${winRate}%)</span></td>
          <td style="${leaveStyle}">${u.leave_count || 0}</td>
          <td style="font-size:12px;color:#888">${u.last_login ? formatDate(u.last_login) : '-'}</td>
          <td><a href="/tc-backstage/users/${encodeURIComponent(u.nickname)}" class="btn btn-secondary" style="font-size:12px;padding:4px 10px">보기</a></td>
        </tr>`;
        }).join('')}
      </table></div>
      ${pagination(data.page, data.total, data.limit, paginationBase)}`;
    } else {
      tableContent = '<div class="empty">유저 없음</div>';
    }

    const content = `
      ${pageHeader(
        '유저',
        '검색, 정렬, 최소 조건 필터를 유지하면서 현재 페이지의 상태 분포를 바로 읽을 수 있게 정리했습니다.',
        `<span class="btn btn-secondary" style="cursor:default">총 ${formatNumber(data.total)}명</span>`
      )}
      ${summaryStrip([
        { label: '현재 페이지', value: formatNumber(data.rows.length), meta: search ? `검색어: ${escapeHtml(search)}` : '필터 결과' },
        { label: '관리자', value: formatNumber(adminCount), valueColor: '#5e35b1' },
        { label: '탈퇴 계정', value: formatNumber(deletedCount), valueColor: '#c0563f' },
        { label: '주의 유저', value: formatNumber(highRiskUsers), meta: `평균 레이팅 ${formatNumber(avgRating)}` }
      ])}
      <div class="card">
        ${searchForm}
        ${tableContent}
      </div>
    `;
    return html(res, layout('유저', content, 'users'));
  }

  // User detail
  const userDetailMatch = pathname.match(/^\/tc-backstage\/users\/([^/]+)$/);
  if (userDetailMatch && method === 'GET') {
    const nickname = decodeURIComponent(userDetailMatch[1]);
    const [user, recentMatches, goldHistory, purchaseHistory] = await Promise.all([
      getUserDetail(nickname),
      getRecentMatches(nickname, 20),
      getAdminGoldHistory(nickname, 50),
      getAdminPurchaseHistory(nickname, 30),
    ]);
    if (!user) return html(res, layout('찾을 수 없음', '<div class="empty">유저를 찾을 수 없습니다</div>', 'users'), 404);

    const winRate = user.total_games > 0 ? Math.round((user.wins / user.total_games) * 100) : 0;
    const purchaseSummary = purchaseHistory?.summary || {
      totalSpent: 0,
      totalPurchases: 0,
      permanentCount: 0,
      temporaryCount: 0,
      activeCount: 0,
    };

    // Chat ban status
    let chatBanHtml = '<span style="color:#4caf50;font-weight:600">없음</span>';
    if (user.chat_ban_until) {
      const remaining = new Date(user.chat_ban_until) - new Date();
      if (remaining > 0) {
        const mins = Math.ceil(remaining / 60000);
        const hours = Math.floor(mins / 60);
        const display = hours > 0 ? `${hours}시간 ${mins % 60}분` : `${mins}분`;
        chatBanHtml = `<span style="color:#e53935;font-weight:600">${display} 남음</span> <span style="color:#888;font-size:12px">(${formatDate(user.chat_ban_until)}까지)</span>`;
      }
    }

    const content = `
      ${pageHeader('유저 상세', '플레이 기록, 골드 흐름, 실제 구매 아이템까지 한 페이지에서 확인할 수 있게 구성했습니다.')}
      ${summaryStrip([
        { label: '현재 골드', value: formatNumber(user.gold || 0), valueColor: '#d07a16', meta: `레벨 ${formatNumber(user.level || 1)}` },
        { label: '누적 구매', value: formatNumber(purchaseSummary.totalPurchases), meta: `총 ${formatNumber(purchaseSummary.totalSpent)} 골드 사용` },
        { label: '영구 / 기간제', value: `${formatNumber(purchaseSummary.permanentCount)} / ${formatNumber(purchaseSummary.temporaryCount)}`, meta: `활성 ${formatNumber(purchaseSummary.activeCount)}개` },
        { label: '전적', value: `${formatNumber(user.wins)}승`, meta: `${formatNumber(user.losses)}패 · 승률 ${formatPercent(winRate)}` }
      ])}
      <div class="card">
        <div class="detail-grid" style="grid-template-columns:130px 1fr">
          <div class="label">닉네임</div><div class="value" style="font-weight:600">${escapeHtml(user.nickname)}${user.is_deleted ? ' <span class="badge" style="background:#ffebee;color:#c62828">탈퇴</span>' : ''}</div>
          ${user.is_deleted ? `<div class="label">탈퇴일</div><div class="value" style="color:#c62828">${formatDate(user.deleted_at)}</div>` : ''}
          <div class="label">앱 관리자</div><div class="value">
            <span class="badge" style="background:${user.is_admin ? '#ede7f6' : '#f5f5f5'};color:${user.is_admin ? '#5e35b1' : '#888'}">${user.is_admin ? '관리자' : '일반'}</span>
            <form method="POST" action="/tc-backstage/users/${encodeURIComponent(user.nickname)}/admin" style="display:inline-flex;align-items:center;gap:6px;margin-left:12px"
              onsubmit="return confirm('${escapeHtml(user.nickname)} 유저를 ${user.is_admin ? '관리자에서 해제' : '관리자로 지정'}하시겠습니까?')">
              <input type="hidden" name="is_admin" value="${user.is_admin ? '0' : '1'}">
              <button type="submit" class="btn btn-secondary" style="font-size:11px;padding:4px 10px">${user.is_admin ? '권한 해제' : '관리자 지정'}</button>
            </form>
          </div>
          <div class="label">계정명</div><div class="value">${escapeHtml(user.username)}</div>
          <div class="label">레벨</div><div class="value">${user.level || 1}</div>
          <div class="label">골드</div><div class="value" style="color:#ff9800;font-weight:600">${(user.gold || 0).toLocaleString()}
            <form method="POST" action="/tc-backstage/users/${encodeURIComponent(user.nickname)}/gold" style="display:inline-flex;align-items:center;gap:4px;margin-left:12px">
              <input type="number" name="amount" placeholder="+/-" style="width:80px;padding:4px 8px;border-radius:6px;border:1px solid #ddd;font-size:12px" required>
              <button type="submit" class="btn btn-primary" style="font-size:11px;padding:4px 10px">지급</button>
            </form>
          </div>
          <div class="label">레이팅</div><div class="value" style="font-weight:600">${user.rating}</div>
          <div class="label">시즌 레이팅</div><div class="value">${user.season_rating || 1000}</div>
          <div class="label">게임 수</div><div class="value">${user.total_games}</div>
          <div class="label">전적</div><div class="value">${user.wins}승 / ${user.losses}패 (${winRate}%)</div>
          <div class="label">이탈 수</div><div class="value" style="color:${(user.leave_count || 0) >= 3 ? '#e53935' : '#333'}">${user.leave_count || 0}</div>
          <div class="label">신고</div><div class="value">${user.report_count}</div>
          <div class="label">문의</div><div class="value">${user.inquiry_count}</div>
          <div class="label">광고 보상</div><div class="value"><span style="color:#43a047;font-weight:600">${user.ad_reward_today || 0}/5 오늘</span> <span style="color:#888;font-size:12px">(총 ${user.ad_reward_total || 0}회 / ${((user.ad_reward_total || 0) * 50).toLocaleString()}골드)</span></div>
          <div class="label">가입일</div><div class="value">${formatDate(user.created_at)}</div>
          <div class="label">최근 접속</div><div class="value">${formatDate(user.last_login)}</div>
          <div class="label">채팅 금지</div><div class="value">${chatBanHtml}</div>
        </div>
      </div>

      <div class="card">
        <h3>기기 정보</h3>
        <div class="detail-grid" style="grid-template-columns:130px 1fr">
          <div class="label">플랫폼</div><div class="value">${deviceBadge(user.device_platform)}</div>
          <div class="label">기기 모델</div><div class="value">${escapeHtml(user.device_model || '-')}</div>
          <div class="label">OS 버전</div><div class="value">${escapeHtml(user.os_version || '-')}</div>
          <div class="label">앱 버전</div><div class="value">${escapeHtml(user.app_version || '-')}</div>
          <div class="label">최근 IP</div><div class="value">${escapeHtml(user.last_ip || '-')}</div>
          <div class="label">FCM 토큰</div><div class="value" style="word-break:break-all;font-size:12px">${escapeHtml(user.fcm_token || '-')}</div>
        </div>
      </div>

      <div class="card">
        <h3>골드 히스토리 <span style="font-size:13px;color:#888;font-weight:400">(${goldHistory?.history?.length || 0})</span></h3>
        ${goldHistory?.success && goldHistory.history.length > 0 ? `
          <div class="table-wrap"><table>
            <tr><th>일시</th><th>유형</th><th>내용</th><th>설명</th><th>변동</th></tr>
            ${goldHistory.history.map(item => {
              const delta = parseInt(item.goldDelta || 0);
              const positive = delta >= 0;
              const sourceMap = {
                match: '게임',
                ad_reward: '광고',
                season_reward: '시즌',
                shop_purchase: '상점',
              };
              const sourceLabel = sourceMap[item.source] || item.source || '-';
              return `<tr>
                <td style="font-size:12px;color:#888">${formatDate(item.createdAt)}</td>
                <td><span class="badge" style="background:${positive ? '#e8f5e9' : '#fff3e0'};color:${positive ? '#2e7d32' : '#ef6c00'}">${escapeHtml(sourceLabel)}</span></td>
                <td style="font-weight:600">${escapeHtml(item.title || '-')}</td>
                <td style="font-size:12px;color:#666">${escapeHtml(item.description || '-')}</td>
                <td style="font-weight:700;color:${positive ? '#2e7d32' : '#ef6c00'}">${positive ? '+' : ''}${delta.toLocaleString()}</td>
              </tr>`;
            }).join('')}
          </table></div>
        ` : `
          <div class="empty">${escapeHtml(goldHistory?.message || '표시할 골드 내역이 없습니다')}</div>
        `}
      </div>

      <div class="card">
        <h3>상점 구매 내역 <span style="font-size:13px;color:#888;font-weight:400">(${purchaseHistory?.purchases?.length || 0})</span></h3>
        ${purchaseHistory?.success && purchaseHistory.purchases.length > 0 ? `
          <div class="table-wrap"><table>
            <tr><th>구매일</th><th>아이템</th><th>분류</th><th>가격</th><th>구분</th><th>상태</th><th>만료</th></tr>
            ${purchaseHistory.purchases.map(item => {
              const categoryColors = {
                banner: '#e3f2fd;color:#1565c0',
                title: '#fff3e0;color:#e65100',
                theme: '#e8eaf6;color:#283593',
                utility: '#fce4ec;color:#880e4f',
                card_skin: '#f1f8e9;color:#33691e',
              };
              const statusBadge = item.isActive
                ? '<span class="badge" style="background:#e8f5e9;color:#2e7d32">활성</span>'
                : '<span class="badge" style="background:#f5f5f5;color:#777">비활성</span>';
              const typeLabel = item.isPermanent ? '영구' : `${item.durationDays || '-'}일`;
              return `<tr>
                <td style="font-size:12px;color:#888">${formatDate(item.acquiredAt)}</td>
                <td>
                  <div style="font-weight:700">${escapeHtml(item.name)}</div>
                  <div class="muted mono" style="font-size:11px">${escapeHtml(item.itemKey)}</div>
                </td>
                <td><span class="badge" style="background:${categoryColors[item.category] || '#f5f5f5;color:#333'}">${escapeHtml(item.category)}</span>${item.isSeason ? ' <span class="badge" style="background:#e8f5e9;color:#2e7d32">시즌</span>' : ''}</td>
                <td style="font-weight:700;color:#d07a16">${formatNumber(item.price)}</td>
                <td>${typeLabel}</td>
                <td>${statusBadge}</td>
                <td style="font-size:12px;color:#888">${item.expiresAt ? formatDate(item.expiresAt) : '-'}</td>
              </tr>`;
            }).join('')}
          </table></div>
        ` : `
          <div class="empty">${escapeHtml(purchaseHistory?.message || '상점 구매 내역이 없습니다')}</div>
        `}
      </div>

      ${user.fcm_token ? `<div class="card">
        <h3>푸시 알림</h3>
        ${url.searchParams.get('push') === 'ok' ? '<div style="color:#4caf50;margin-bottom:12px;font-weight:600">푸시 전송 완료</div>' : ''}
        ${url.searchParams.get('push') === 'fail' ? `<div style="color:#e53935;margin-bottom:12px;font-weight:600">푸시 전송 실패: ${escapeHtml(url.searchParams.get('reason') || 'unknown')}</div>` : ''}
        <form method="POST" action="/tc-backstage/users/${encodeURIComponent(user.nickname)}/push">
          <input type="text" name="title" placeholder="제목" required style="margin-bottom:8px">
          <textarea name="body" rows="3" placeholder="내용" required></textarea>
          <div style="margin-top:8px"><button type="submit" class="btn btn-primary">푸시 전송</button></div>
        </form>
      </div>` : ''}

      <div class="card">
        <h3>채팅 금지</h3>
        <form method="POST" action="/tc-backstage/users/${encodeURIComponent(user.nickname)}/chat-ban" style="display:flex;align-items:center;gap:8px;flex-wrap:wrap">
          <select name="duration" style="padding:8px 12px;border-radius:8px;border:1px solid #ddd;font-size:14px">
            <option value="0">해제</option>
            <option value="30">30분</option>
            <option value="60">1시간</option>
            <option value="180">3시간</option>
            <option value="360">6시간</option>
            <option value="720">12시간</option>
            <option value="1440">1일</option>
            <option value="4320">3일</option>
            <option value="10080">7일</option>
            <option value="43200">30일</option>
          </select>
          <button type="submit" class="btn btn-primary">적용</button>
        </form>
      </div>

      <div class="card">
        <h3>관리자 메모</h3>
        <form method="POST" action="/tc-backstage/users/${encodeURIComponent(user.nickname)}/memo">
          <textarea name="memo" rows="3" placeholder="관리자 메모 (신고 이력, 주의사항 등)">${escapeHtml(user.admin_memo || '')}</textarea>
          <div style="margin-top:8px"><button type="submit" class="btn btn-primary">메모 저장</button></div>
        </form>
      </div>

      <div class="card">
        <h3>최근 매치 <span style="font-size:13px;color:#888;font-weight:400">(${recentMatches.length})</span></h3>
        ${recentMatches.length > 0 ? `<div class="table-wrap"><table>
          <tr><th>ID</th><th>게임</th><th>결과</th><th>점수/플레이어</th><th>유형</th><th>종료</th><th>날짜</th></tr>
          ${recentMatches.map(m => {
            const resultBadge = m.isDraw
              ? '<span class="badge" style="background:#f5f5f5;color:#888">무승부</span>'
              : m.won
                ? '<span class="badge" style="background:#e8f5e9;color:#2e7d32">승</span>'
                : '<span class="badge" style="background:#ffebee;color:#c62828">패</span>';
            let endBadge = '<span class="badge" style="background:#e8f5e9;color:#2e7d32">정상</span>';
            if (m.endReason === 'leave') {
              endBadge = '<span class="badge" style="background:#fce4ec;color:#c62828">이탈</span>' + (m.deserterNickname ? '<br><span style="font-size:11px;color:#c62828">' + escapeHtml(m.deserterNickname) + '</span>' : '');
            } else if (m.endReason === 'timeout') {
              endBadge = '<span class="badge" style="background:#fff8e1;color:#f57f17">시간초과</span>' + (m.deserterNickname ? '<br><span style="font-size:11px;color:#f57f17">' + escapeHtml(m.deserterNickname) + '</span>' : '');
            }
            const rankedBadge = m.isRanked ? '<span class="badge" style="background:#fff3e0;color:#e65100">랭크</span>' : '<span class="badge" style="background:#f5f5f5;color:#999">일반</span>';
            if (m.gameType === 'skull_king') {
              const playersText = m.players ? m.players.map(p => escapeHtml(p.nickname) + '(' + p.score + '점 #' + p.rank + ')').join(', ') : '-';
              return `<tr>
              <td>${m.id}</td>
              <td><span class="badge" style="background:#ff7043;color:#fff">SK</span></td>
              <td>${resultBadge} <span style="font-size:11px;color:#888">#${m.myRank} (${m.myScore}점)</span></td>
              <td style="font-size:12px">${playersText}</td>
              <td>${rankedBadge}</td>
              <td>${endBadge}</td>
              <td style="font-size:12px;color:#888">${formatDate(m.createdAt)}</td>
            </tr>`;
            }
            const myTeamStyle = m.myTeam === 'A' ? 'font-weight:700;color:#c62828' : 'font-weight:700;color:#1565c0';
            return `<tr>
              <td>${m.id}</td>
              <td><span class="badge" style="background:#6c63ff;color:#fff">티츄</span></td>
              <td>${resultBadge}</td>
              <td style="font-size:12px"><span style="${m.myTeam === 'A' ? myTeamStyle : ''}">${escapeHtml(m.playerA1)}, ${escapeHtml(m.playerA2)}</span> <span style="font-weight:600">${m.teamAScore}:${m.teamBScore}</span> <span style="${m.myTeam === 'B' ? myTeamStyle : ''}">${escapeHtml(m.playerB1)}, ${escapeHtml(m.playerB2)}</span></td>
              <td>${rankedBadge}</td>
              <td>${endBadge}</td>
              <td style="font-size:12px;color:#888">${formatDate(m.createdAt)}</td>
            </tr>`;
          }).join('')}
        </table></div>` : '<div class="empty">매치 기록 없음</div>'}
      </div>

      <div class="card" style="margin-top:0">
        <h3 style="color:#e53935">위험 영역</h3>
        <form method="POST" action="/tc-backstage/users/${encodeURIComponent(user.nickname)}/ban"
              onsubmit="return confirm('정말 이 유저를 차단(삭제)하시겠습니까? 되돌릴 수 없습니다.')">
          <button type="submit" class="btn btn-danger">유저 차단 (계정 삭제)</button>
        </form>
      </div>
      <a href="/tc-backstage/users" class="btn btn-secondary">목록으로</a>
    `;
    return html(res, layout(`유저: ${escapeHtml(user.nickname)}`, content, 'users'));
  }

  // Chat ban
  const chatBanMatch = pathname.match(/^\/tc-backstage\/users\/([^/]+)\/chat-ban$/);
  if (chatBanMatch && method === 'POST') {
    const nickname = decodeURIComponent(chatBanMatch[1]);
    const body = await parseBody(req);
    const duration = parseInt(body.duration) || 0;
    await setChatBan(nickname, duration);
    return redirect(res, `/tc-backstage/users/${encodeURIComponent(nickname)}`);
  }

  // Admin memo
  const memoMatch = pathname.match(/^\/tc-backstage\/users\/([^/]+)\/memo$/);
  if (memoMatch && method === 'POST') {
    const nickname = decodeURIComponent(memoMatch[1]);
    const body = await parseBody(req);
    await setAdminMemo(nickname, (body.memo || '').trim());
    return redirect(res, `/tc-backstage/users/${encodeURIComponent(nickname)}`);
  }

  // Ban user (delete account)
  const banMatch = pathname.match(/^\/tc-backstage\/users\/([^/]+)\/ban$/);
  if (banMatch && method === 'POST') {
    const nickname = decodeURIComponent(banMatch[1]);
    await deleteUser(nickname);
    return redirect(res, '/tc-backstage/users');
  }

  // Push notification
  const pushMatch = pathname.match(/^\/tc-backstage\/users\/([^/]+)\/push$/);
  if (pushMatch && method === 'POST') {
    const nickname = decodeURIComponent(pushMatch[1]);
    const body = await parseBody(req);
    const user = await getUserDetail(nickname);
    const redirectBase = `/tc-backstage/users/${encodeURIComponent(nickname)}`;
    if (!user || !user.fcm_token) {
      return redirect(res, `${redirectBase}?push=fail&reason=no+FCM+token`);
    }
    if (user.push_enabled === false) {
      return redirect(res, `${redirectBase}?push=fail&reason=${encodeURIComponent('사용자 알림이 비활성화되어 있어 전송할 수 없습니다')}`);
    }
    if (sendPushNotification) {
      const result = await sendPushNotification(user.fcm_token, body.title || '', body.body || '');
      if (result.success) {
        return redirect(res, `${redirectBase}?push=ok`);
      } else {
        return redirect(res, `${redirectBase}?push=fail&reason=${encodeURIComponent(result.message || 'unknown')}`);
      }
    }
    return redirect(res, `${redirectBase}?push=fail&reason=not+configured`);
  }

  // ===== Shop Management =====
  if (pathname === '/tc-backstage/shop' && method === 'GET') {
    const items = await getAllShopItemsAdmin();
    const now = new Date();

    function saleBadge(item) {
      if (!item.sale_start && !item.sale_end) return '<span class="badge" style="background:#e8f5e9;color:#2e7d32">상시</span>';
      const start = item.sale_start ? new Date(item.sale_start) : null;
      const end = item.sale_end ? new Date(item.sale_end) : null;
      if (start && start > now) return '<span class="badge" style="background:#e3f2fd;color:#1565c0">예정</span>';
      if (end && end < now) return '<span class="badge" style="background:#f3e5f5;color:#6a1b9a">종료</span>';
      return '<span class="badge" style="background:#e8f5e9;color:#2e7d32">판매중</span>';
    }

    function shopCategoryBadge(cat) {
      const colors = { banner: '#e3f2fd;color:#1565c0', title: '#fff3e0;color:#e65100', theme: '#e8eaf6;color:#283593', utility: '#fce4ec;color:#880e4f', card_skin: '#f1f8e9;color:#33691e' };
      return `<span class="badge" style="background:${colors[cat] || '#f5f5f5;color:#333'}">${escapeHtml(cat)}</span>`;
    }

    const activeItems = items.filter(item => {
      const start = item.sale_start ? new Date(item.sale_start) : null;
      const end = item.sale_end ? new Date(item.sale_end) : null;
      return (!start || start <= now) && (!end || end >= now);
    }).length;
    const seasonalItems = items.filter(item => item.is_season).length;
    const purchasableItems = items.filter(item => item.is_purchasable).length;
    const avgPrice = items.length > 0 ? Math.round(items.reduce((sum, item) => sum + (parseInt(item.price) || 0), 0) / items.length) : 0;

    let tableContent = '';
    if (items.length > 0) {
      tableContent = `<div class="table-wrap"><table>
        <tr><th>ID</th><th>키</th><th>이름</th><th>분류</th><th>가격</th><th>구분</th><th>판매기간</th><th>상태</th><th></th></tr>
        ${items.map(item => `<tr>
          <td>${item.id}</td>
          <td style="font-family:monospace;font-size:12px">${escapeHtml(item.item_key)}</td>
          <td>${escapeHtml(item.name)}</td>
          <td>${shopCategoryBadge(item.category)}</td>
          <td>${item.price}</td>
          <td>${item.is_permanent ? '영구' : (item.duration_days ? item.duration_days + '일' : '-')}</td>
          <td style="font-size:12px">${item.sale_start ? formatDate(item.sale_start) : '-'}<br>${item.sale_end ? '~ ' + formatDate(item.sale_end) : ''}</td>
          <td>${saleBadge(item)}</td>
          <td><a href="/tc-backstage/shop/${item.id}" class="btn btn-secondary">수정</a></td>
        </tr>`).join('')}
      </table></div>`;
    } else {
      tableContent = '<div class="empty">상점 아이템 없음</div>';
    }

    const content = `
      ${pageHeader(
        '상점 아이템',
        '판매 상태, 시즌 여부, 가격대를 빠르게 훑을 수 있도록 요약을 먼저 배치했습니다.',
        `<a href="/tc-backstage/shop/add" class="btn btn-primary">+ 아이템 추가</a>`
      )}
      ${summaryStrip([
        { label: '전체 아이템', value: formatNumber(items.length) },
        { label: '판매 가능', value: formatNumber(purchasableItems), valueColor: '#2e8b57', meta: `현재 판매중 ${formatNumber(activeItems)}개` },
        { label: '시즌 아이템', value: formatNumber(seasonalItems), valueColor: '#2878b8' },
        { label: '평균 가격', value: formatNumber(avgPrice), meta: '골드 기준' }
      ])}
      <div class="card">${tableContent}</div>
    `;
    return html(res, layout('상점', content, 'shop'));
  }

  // Shop add form
  if (pathname === '/tc-backstage/shop/add' && method === 'GET') {
    const content = `
      <h1 class="page-title">아이템 추가</h1>
      <div class="card">
        ${shopForm('/tc-backstage/shop/add', {})}
      </div>
      <a href="/tc-backstage/shop" class="btn btn-secondary" style="margin-top:12px">목록으로</a>
    `;
    return html(res, layout('아이템 추가', content, 'shop'));
  }

  // Shop add process
  if (pathname === '/tc-backstage/shop/add' && method === 'POST') {
    const body = await parseBody(req);
    const data = parseShopFormBody(body);
    const result = await addShopItem(data);
    if (!result.success) {
      const content = `
        <h1 class="page-title">아이템 추가</h1>
        <div style="color:#e53935;margin-bottom:12px">${escapeHtml(result.message)}</div>
        <div class="card">
          ${shopForm('/tc-backstage/shop/add', body)}
        </div>
        <a href="/tc-backstage/shop" class="btn btn-secondary" style="margin-top:12px">목록으로</a>
      `;
      return html(res, layout('아이템 추가', content, 'shop'));
    }
    return redirect(res, '/tc-backstage/shop');
  }

  // Shop edit form
  const shopEditMatch = pathname.match(/^\/tc-backstage\/shop\/(\d+)$/);
  if (shopEditMatch && method === 'GET') {
    const item = await getShopItemById(parseInt(shopEditMatch[1]));
    if (!item) return html(res, layout('찾을 수 없음', '<div class="empty">아이템을 찾을 수 없습니다</div>', 'shop'), 404);

    const content = `
      <h1 class="page-title">수정: ${escapeHtml(item.name)}</h1>
      <div class="card">
        ${shopForm('/tc-backstage/shop/' + item.id, item, true)}
      </div>
      <form method="POST" action="/tc-backstage/shop/${item.id}/delete"
            onsubmit="return confirm('정말 이 아이템을 삭제하시겠습니까? 보유한 유저의 아이템도 함께 삭제됩니다.')"
            style="margin-top:12px;display:inline-block">
        <button type="submit" class="btn btn-danger">아이템 삭제</button>
      </form>
      <a href="/tc-backstage/shop" class="btn btn-secondary" style="margin-top:12px;margin-left:8px">목록으로</a>
    `;
    return html(res, layout(`수정: ${escapeHtml(item.name)}`, content, 'shop'));
  }

  // Shop edit process
  if (shopEditMatch && method === 'POST') {
    const body = await parseBody(req);
    const data = parseShopFormBody(body);
    const result = await updateShopItem(parseInt(shopEditMatch[1]), data);
    if (!result.success) {
      const item = await getShopItemById(parseInt(shopEditMatch[1]));
      const content = `
        <h1 class="page-title">수정: ${escapeHtml(item ? item.name : '')}</h1>
        <div style="color:#e53935;margin-bottom:12px">${escapeHtml(result.message)}</div>
        <div class="card">
          ${shopForm('/tc-backstage/shop/' + shopEditMatch[1], body, true)}
        </div>
        <a href="/tc-backstage/shop" class="btn btn-secondary" style="margin-top:12px">목록으로</a>
      `;
      return html(res, layout('수정', content, 'shop'));
    }
    return redirect(res, '/tc-backstage/shop/' + shopEditMatch[1]);
  }

  // Shop delete
  const shopDeleteMatch = pathname.match(/^\/tc-backstage\/shop\/(\d+)\/delete$/);
  if (shopDeleteMatch && method === 'POST') {
    await deleteShopItem(parseInt(shopDeleteMatch[1]));
    return redirect(res, '/tc-backstage/shop');
  }

  // ===== Maintenance =====
  if (pathname === '/tc-backstage/maintenance' && method === 'GET') {
    const config = getMaintenanceConfig ? getMaintenanceConfig() : {};
    const status = getMaintenanceStatus ? getMaintenanceStatus() : {};

    let statusText = '<span class="badge" style="background:#e8f5e9;color:#2e7d32">비활성</span>';
    if (status.maintenance) {
      statusText = '<span class="badge badge-bug">점검 중</span>';
    } else if (status.notice) {
      statusText = '<span class="badge badge-pending">안내 중</span>';
    }

    const content = `
      <h1 class="page-title">점검</h1>
      <div class="card">
        <h3>현재 상태: ${statusText}</h3>
        <form method="POST" action="/tc-backstage/maintenance" style="margin-top:16px">
          <div class="form-grid" style="grid-template-columns:160px 1fr">
            <label>안내 시작</label>
            <input type="datetime-local" name="noticeStart" value="${formatDatetimeLocal(config.noticeStart)}" style="padding:10px;border:1px solid #ddd;border-radius:8px;font-size:14px">
            <label>안내 종료</label>
            <input type="datetime-local" name="noticeEnd" value="${formatDatetimeLocal(config.noticeEnd)}" style="padding:10px;border:1px solid #ddd;border-radius:8px;font-size:14px">
            <label>점검 시작</label>
            <input type="datetime-local" name="maintenanceStart" value="${formatDatetimeLocal(config.maintenanceStart)}" style="padding:10px;border:1px solid #ddd;border-radius:8px;font-size:14px">
            <label>점검 종료</label>
            <input type="datetime-local" name="maintenanceEnd" value="${formatDatetimeLocal(config.maintenanceEnd)}" style="padding:10px;border:1px solid #ddd;border-radius:8px;font-size:14px">
            <label>안내 메시지</label>
            <textarea name="message" rows="3" placeholder="점검 안내 메시지">${escapeHtml(config.message || '')}</textarea>
          </div>
          <div style="margin-top:16px;display:flex;gap:8px">
            <button type="submit" class="btn btn-primary">저장</button>
          </div>
        </form>
        <form method="POST" action="/tc-backstage/maintenance/clear" style="margin-top:12px">
          <button type="submit" class="btn btn-danger" onclick="return confirm('점검 설정을 초기화하시겠습니까?')">전체 초기화</button>
        </form>
      </div>
    `;
    return html(res, layout('점검', content, 'maintenance'));
  }

  if (pathname === '/tc-backstage/maintenance' && method === 'POST') {
    if (setMaintenanceConfig) {
      const body = await parseBody(req);
      setMaintenanceConfig({
        noticeStart: body.noticeStart || null,
        noticeEnd: body.noticeEnd || null,
        maintenanceStart: body.maintenanceStart || null,
        maintenanceEnd: body.maintenanceEnd || null,
        message: body.message || '',
      });
    }
    return redirect(res, '/tc-backstage/maintenance');
  }

  if (pathname === '/tc-backstage/maintenance/clear' && method === 'POST') {
    if (setMaintenanceConfig) {
      setMaintenanceConfig({
        noticeStart: null,
        noticeEnd: null,
        maintenanceStart: null,
        maintenanceEnd: null,
        message: '',
      });
    }
    return redirect(res, '/tc-backstage/maintenance');
  }

  // ===== Settings =====
  if (pathname === '/tc-backstage/settings' && method === 'GET') {
    const eulaContent = await getConfig('eula_content') || '';
    const privacyPolicy = await getConfig('privacy_policy') || '';
    const saved = url.searchParams.get('saved');

    const content = `
      <h1 class="page-title">설정</h1>
      ${saved ? '<div style="color:#4caf50;margin-bottom:12px;font-weight:600">저장되었습니다.</div>' : ''}
      <div class="card">
        <h3>EULA / 이용약관</h3>
        <form method="POST" action="/tc-backstage/settings/eula">
          <textarea name="eula_content" rows="20" style="font-size:13px;line-height:1.6">${escapeHtml(eulaContent)}</textarea>
          <div style="margin-top:12px"><button type="submit" class="btn btn-primary">저장</button></div>
        </form>
      </div>
      <div class="card">
        <h3>개인정보처리방침</h3>
        <form method="POST" action="/tc-backstage/settings/privacy">
          <textarea name="privacy_policy" rows="20" style="font-size:13px;line-height:1.6">${escapeHtml(privacyPolicy)}</textarea>
          <div style="margin-top:12px"><button type="submit" class="btn btn-primary">저장</button></div>
        </form>
      </div>
    `;
    return html(res, layout('설정', content, 'settings'));
  }

  if (pathname === '/tc-backstage/settings/eula' && method === 'POST') {
    const body = await parseBody(req);
    await updateConfig('eula_content', body.eula_content || '');
    return redirect(res, '/tc-backstage/settings?saved=1');
  }

  if (pathname === '/tc-backstage/settings/privacy' && method === 'POST') {
    const body = await parseBody(req);
    await updateConfig('privacy_policy', body.privacy_policy || '');
    return redirect(res, '/tc-backstage/settings?saved=1');
  }

  // Room detail
  const roomDetailMatch = pathname.match(/^\/tc-backstage\/rooms\/([^/]+)$/);
  if (roomDetailMatch && method === 'GET') {
    const roomId = decodeURIComponent(roomDetailMatch[1]);
    if (!lobby) return html(res, layout('방', '<div class="empty">로비를 사용할 수 없습니다</div>'), 404);
    const room = lobby.getRoom(roomId);
    if (!room) return html(res, layout('방', '<div class="empty">방을 찾을 수 없습니다 (이미 닫혔을 수 있음)</div>'), 404);

    const roomState = room.getState();
    const game = room.game;

    // Players table
    const playersHtml = roomState.players.map((p, i) => {
      if (!p) return `<tr><td>슬롯 ${i}</td><td colspan="6" style="color:#999">비어있음</td></tr>`;
      const teamLabel = (i === 0 || i === 2) ? '<span class="badge" style="background:#e3f2fd;color:#1565c0">Team A</span>' : '<span class="badge" style="background:#fce4ec;color:#c62828">Team B</span>';
      const statusBadges = [];
      if (p.isHost) statusBadges.push('<span class="badge badge-resolved">방장</span>');
      if (p.isBot) statusBadges.push('<span class="badge" style="background:#f3e5f5;color:#6a1b9a">봇</span>');
      if (!p.connected) statusBadges.push('<span class="badge badge-pending">연결 끊김</span>');
      if (p.isReady) statusBadges.push('<span class="badge" style="background:#e8f5e9;color:#2e7d32">준비</span>');

      let cardCount = '-';
      let tichu = '';
      let finished = '';
      if (game) {
        const hand = game.hands[p.id];
        cardCount = hand ? hand.length : 0;
        if (game.largeTichuDeclarations.includes(p.id)) tichu = '<span class="badge" style="background:#ffebee;color:#c62828">라지 티츄</span>';
        else if (game.smallTichuDeclarations.includes(p.id)) tichu = '<span class="badge" style="background:#fff3e0;color:#e65100">스몰 티츄</span>';
        const finishPos = game.finishOrder.indexOf(p.id);
        if (finishPos !== -1) finished = `<span class="badge badge-resolved">${finishPos + 1}${['st','nd','rd','th'][finishPos] || 'th'}</span>`;
      }

      return `<tr>
        <td>슬롯 ${i}</td>
        <td style="font-weight:600">${escapeHtml(p.name)}</td>
        <td>${teamLabel}</td>
        <td>${statusBadges.join(' ')}</td>
        <td style="font-weight:700;font-size:16px">${cardCount}</td>
        <td>${tichu || '-'}</td>
        <td>${finished || '-'}</td>
      </tr>`;
    }).join('');

    // Spectators
    const specHtml = roomState.spectators.length > 0
      ? roomState.spectators.map(s => escapeHtml(s.nickname)).join(', ')
      : '<span style="color:#999">없음</span>';

    // Game state details
    let gameHtml = '';
    if (game) {
      const phase = game.state;
      const round = game.round;
      const currentPlayerName = game.currentPlayer ? (game.playerNames[game.currentPlayer] || game.currentPlayer) : '-';

      // Phase badge
      const phaseColors = {
        'waiting': 'badge-pending',
        'dealing_first_8': 'badge-pending',
        'large_tichu_phase': 'badge-pending',
        'dealing_remaining_6': 'badge-pending',
        'card_exchange': 'badge-suggestion',
        'playing': 'badge-resolved',
        'round_end': 'badge-reviewed',
        'game_end': 'badge-bug',
      };
      const phaseBadge = `<span class="badge ${phaseColors[phase] || 'badge-other'}">${phase}</span>`;

      // Current trick
      let trickHtml = '';
      if (game.currentTrick.length > 0) {
        trickHtml = `<div class="table-wrap"><table>
          <tr><th>플레이어</th><th>카드</th><th>조합</th><th>값</th></tr>
          ${game.currentTrick.map(t => `<tr>
            <td style="font-weight:600">${escapeHtml(game.playerNames[t.playerId])}</td>
            <td><code style="background:#f0f0f0;padding:2px 6px;border-radius:4px;font-size:12px">${t.cards.join(', ')}</code></td>
            <td><span class="badge badge-reviewed">${t.combo.type}</span></td>
            <td style="font-weight:700">${t.combo.value}</td>
          </tr>`).join('')}
        </table></div>`;
      } else {
        trickHtml = '<div style="color:#999;font-size:13px">테이블에 카드 없음</div>';
      }

      // Trick piles summary (points collected per player)
      let trickPilesHtml = '';
      if (game.trickPiles) {
        const pileRows = game.playerIds.map(pid => {
          const cards = game.trickPiles[pid] || [];
          const pts = cards.reduce((s, c) => {
            const rank = c.startsWith('special_') ? c.split('_')[1] : c.split('_')[1];
            if (rank === '5') return s + 5;
            if (rank === '10' || rank === 'K') return s + 10;
            if (c === 'special_dragon') return s + 25;
            if (c === 'special_phoenix') return s - 25;
            return s;
          }, 0);
          return `<tr>
            <td style="font-weight:600">${escapeHtml(game.playerNames[pid])}</td>
            <td>${cards.length}</td>
            <td style="font-weight:700;color:${pts >= 0 ? '#4caf50' : '#e53935'}">${pts}</td>
          </tr>`;
        }).join('');
        trickPilesHtml = `<div class="table-wrap"><table>
          <tr><th>플레이어</th><th>획득 카드</th><th>점수</th></tr>
          ${pileRows}
        </table></div>`;
      }

      // Hands (card list per player)
      let handsHtml = '';
      if (game.hands) {
        const handRows = game.playerIds.map(pid => {
          const hand = game.hands[pid] || [];
          const cardDisplay = hand.length > 0
            ? hand.map(c => {
                let style = 'background:#f0f0f0;padding:2px 6px;border-radius:4px;font-size:11px;margin:1px;display:inline-block;';
                if (c.startsWith('special_')) style += 'background:#fff3e0;color:#e65100;font-weight:600;';
                else if (c.endsWith('_A') || c.endsWith('_K')) style += 'font-weight:600;';
                return `<code style="${style}">${c}</code>`;
              }).join(' ')
            : '<span style="color:#999">비어있음</span>';
          return `<tr>
            <td style="font-weight:600;white-space:nowrap">${escapeHtml(game.playerNames[pid])}</td>
            <td>${cardDisplay}</td>
          </tr>`;
        }).join('');
        handsHtml = `<div class="table-wrap"><table>
          <tr><th style="width:100px">플레이어</th><th>카드</th></tr>
          ${handRows}
        </table></div>`;
      }

      // Score history
      let scoreHistoryHtml = '';
      if (game.scoreHistory && game.scoreHistory.length > 0) {
        scoreHistoryHtml = `<div class="table-wrap"><table>
          <tr><th>라운드</th><th>팀 A</th><th>팀 B</th></tr>
          ${game.scoreHistory.map(s => `<tr>
            <td>R${s.round}</td>
            <td style="font-weight:600;color:${s.teamA > 0 ? '#4caf50' : s.teamA < 0 ? '#e53935' : '#333'}">${s.teamA > 0 ? '+' : ''}${s.teamA}</td>
            <td style="font-weight:600;color:${s.teamB > 0 ? '#4caf50' : s.teamB < 0 ? '#e53935' : '#333'}">${s.teamB > 0 ? '+' : ''}${s.teamB}</td>
          </tr>`).join('')}
          <tr style="border-top:2px solid #333;font-weight:700">
            <td>Total</td>
            <td style="color:#1565c0;font-size:16px">${game.totalScores.teamA}</td>
            <td style="color:#c62828;font-size:16px">${game.totalScores.teamB}</td>
          </tr>
        </table></div>`;
      }

      // Special states
      let specialHtml = '';
      if (game.callRank) specialHtml += `<div style="margin-bottom:8px"><strong>소원 활성:</strong> <span class="badge badge-pending">${game.callRank}</span></div>`;
      if (game.dragonPending) specialHtml += `<div style="margin-bottom:8px"><strong>용 처리 대기:</strong> <span class="badge" style="background:#ffebee;color:#c62828">${escapeHtml(game.playerNames[game.dragonDecider] || '?')} 넘겨야 함</span></div>`;
      if (game.passCount > 0) specialHtml += `<div style="margin-bottom:8px"><strong>패스 횟수:</strong> ${game.passCount}</div>`;

      gameHtml = `
        <div class="stats-grid" style="grid-template-columns:repeat(auto-fit, minmax(130px, 1fr));margin-bottom:20px">
          <div class="stat-card" style="border-left:4px solid #6c63ff"><div class="label">단계</div><div style="margin-top:4px">${phaseBadge}</div></div>
          <div class="stat-card" style="border-left:4px solid #ff9800"><div class="label">라운드</div><div class="value orange">${round}</div></div>
          <div class="stat-card" style="border-left:4px solid #4caf50"><div class="label">현재 턴</div><div style="font-weight:600;font-size:16px;margin-top:4px">${escapeHtml(currentPlayerName)}</div></div>
          <div class="stat-card" style="border-left:4px solid #1565c0"><div class="label">Team A</div><div class="value" style="color:#1565c0">${game.totalScores.teamA}</div></div>
          <div class="stat-card" style="border-left:4px solid #c62828"><div class="label">Team B</div><div class="value" style="color:#c62828">${game.totalScores.teamB}</div></div>
        </div>

        ${specialHtml ? `<div class="card"><h3>활성 상태</h3>${specialHtml}</div>` : ''}

        <div class="card">
          <h3>현재 트릭</h3>
          ${trickHtml}
        </div>

        <div class="card">
          <h3>플레이어 핸드</h3>
          ${handsHtml}
        </div>

        <div class="grid-2col">
          <div class="card">
            <h3>트릭 포인트</h3>
            ${trickPilesHtml}
          </div>
          <div class="card">
            <h3>점수 기록</h3>
            ${scoreHistoryHtml || '<div style="color:#999;font-size:13px">아직 완료된 라운드 없음</div>'}
          </div>
        </div>
      `;
    } else {
      gameHtml = '<div class="card"><div class="empty">진행 중인 게임 없음</div></div>';
    }

    // Chat history
    let chatHtml = '';
    const chatHistory = room.getChatHistory();
    if (chatHistory.length > 0) {
      chatHtml = `<div class="card">
        <h3>채팅 로그 <span style="font-size:13px;color:#888;font-weight:400">(${chatHistory.length})</span></h3>
        <div class="chat-log">
          ${chatHistory.map(m => `<div class="chat-msg">
            <span class="sender">${escapeHtml(m.sender)}</span>
            <span style="color:#aaa;font-size:11px;margin-left:6px">${new Date(m.timestamp).toLocaleTimeString('ko-KR')}</span>
            <div class="text">${escapeHtml(m.message)}</div>
          </div>`).join('')}
        </div>
      </div>`;
    }

    const content = `
      <h1 class="page-title">
        <a href="/tc-backstage/" style="color:#888;text-decoration:none;font-size:14px">대시보드</a>
        <span style="color:#ccc;margin:0 8px">/</span>
        방: ${escapeHtml(roomState.name)}
      </h1>

      <div class="card">
        <div class="detail-grid" style="grid-template-columns:120px 1fr">
          <div class="label">방 ID</div><div class="value"><code>${escapeHtml(roomId)}</code></div>
          <div class="label">방 이름</div><div class="value" style="font-weight:600">${escapeHtml(roomState.name)}</div>
          <div class="label">방장</div><div class="value">${escapeHtml(roomState.players.find(p => p && p.isHost)?.name || '-')}</div>
          <div class="label">유형</div><div class="value">${roomState.isRanked ? '<span class="badge" style="background:#fff3e0;color:#e65100">랭크</span>' : '일반'}${roomState.isPrivate ? ' <span class="badge" style="background:#ffebee;color:#c62828">비공개</span>' : ''}</div>
          <div class="label">턴 제한</div><div class="value">${roomState.turnTimeLimit}초</div>
          <div class="label">관전자</div><div class="value">${specHtml}</div>
        </div>
      </div>

      <div class="card">
        <h3>플레이어</h3>
        <div class="table-wrap"><table>
          <tr><th>슬롯</th><th>이름</th><th>팀</th><th>상태</th><th>카드</th><th>티츄</th><th>완료</th></tr>
          ${playersHtml}
        </table></div>
      </div>

      ${gameHtml}
      ${chatHtml}

      <div style="text-align:center;margin-top:20px">
        <a href="/tc-backstage/rooms/${encodeURIComponent(roomId)}" class="btn btn-secondary" style="margin-right:8px">새로고침</a>
        <a href="/tc-backstage/" class="btn btn-secondary">대시보드로</a>
      </div>
    `;
    return html(res, layout(`Room: ${room.name}`, content, 'home'));
  }

  // Online users list
  if (pathname === '/tc-backstage/online' && method === 'GET') {
    const filter = url.searchParams.get('filter') || 'connected';
    const allRooms = lobby ? lobby.getRoomList() : [];
    let users = [];
    let title = '접속 중 유저';

    if (filter === 'connected') {
      title = '접속 중 유저';
      if (wss) {
        wss.clients.forEach(ws => {
          if (ws.nickname) {
            const roomInfo = ws.roomId ? allRooms.find(r => r.id === ws.roomId) : null;
            users.push({ nickname: ws.nickname, room: roomInfo ? roomInfo.name : null, roomId: ws.roomId, status: roomInfo ? (roomInfo.gameInProgress ? '게임 중' : '대기 중') : '로비' });
          }
        });
      }
    } else if (filter === 'ingame') {
      title = '게임 중 유저';
      const gamingRoomList = allRooms.filter(r => r.gameInProgress);
      for (const r of gamingRoomList) {
        const room = lobby.getRoom(r.id);
        if (!room) continue;
        for (const p of room.players) {
          if (p && !p.isBot) users.push({ nickname: p.nickname, room: r.name, roomId: r.id, status: p.connected !== false ? '플레이 중' : '연결 끊김' });
        }
      }
    } else if (filter === 'waiting') {
      title = '대기 중 유저';
      const waitingRoomList = allRooms.filter(r => !r.gameInProgress);
      for (const r of waitingRoomList) {
        const room = lobby.getRoom(r.id);
        if (!room) continue;
        for (const p of room.players) {
          if (p && !p.isBot) users.push({ nickname: p.nickname, room: r.name, roomId: r.id, status: p.connected !== false ? '준비' : '연결 끊김' });
        }
      }
    } else if (filter === 'spectators') {
      title = '관전자';
      for (const r of allRooms) {
        const room = lobby.getRoom(r.id);
        if (!room) continue;
        for (const s of room.spectators) {
          users.push({ nickname: s.nickname, room: r.name, roomId: r.id, status: '관전 중' });
        }
      }
    }

    const filterBtns = [
      ['connected', '접속 중', '#6c63ff'],
      ['ingame', '게임 중', '#4caf50'],
      ['waiting', '대기 중', '#ff9800'],
      ['spectators', '관전자', '#42a5f5'],
    ].map(([v, l, c]) => `<a href="/tc-backstage/online?filter=${v}" class="btn" style="background:${filter === v ? c : '#f5f5f5'};color:${filter === v ? '#fff' : '#666'};font-size:13px;padding:6px 14px;border-radius:20px;text-decoration:none">${l}</a>`).join('');

    let tableHtml = '';
    if (users.length > 0) {
      tableHtml = `<div class="table-wrap"><table>
        <tr><th>닉네임</th><th>방</th><th>상태</th><th></th></tr>
        ${users.map(u => `<tr>
          <td><a href="/tc-backstage/users/${encodeURIComponent(u.nickname)}" style="color:#6c63ff;text-decoration:none;font-weight:600">${escapeHtml(u.nickname)}</a></td>
          <td>${u.room ? `<a href="/tc-backstage/rooms/${encodeURIComponent(u.roomId)}" style="color:#6c63ff;text-decoration:none">${escapeHtml(u.room)}</a>` : '<span style="color:#888">-</span>'}</td>
          <td>${escapeHtml(u.status)}</td>
          <td><a href="/tc-backstage/users/${encodeURIComponent(u.nickname)}" class="btn btn-secondary" style="font-size:12px;padding:4px 10px">보기</a></td>
        </tr>`).join('')}
      </table></div>`;
    } else {
      tableHtml = '<div class="empty">해당 카테고리에 유저 없음</div>';
    }

    const content = `
      <h1 class="page-title">${title} <span style="font-size:14px;color:#888;font-weight:400">(${users.length})</span></h1>
      <div class="card">
        <div style="display:flex;gap:8px;margin-bottom:16px;flex-wrap:wrap">${filterBtns}</div>
        ${tableHtml}
      </div>
      <a href="/tc-backstage/" class="btn btn-secondary">대시보드로</a>
    `;
    return html(res, layout(title, content, 'home'));
  }

  // Admin gold adjustment
  const goldMatch = pathname.match(/^\/tc-backstage\/users\/([^/]+)\/gold$/);
  if (goldMatch && method === 'POST') {
    const nickname = decodeURIComponent(goldMatch[1]);
    const body = await parseBody(req);
    const amount = parseInt(body.amount);
    if (!isNaN(amount) && amount !== 0) {
      await adminAdjustGold(nickname, amount, sessionInfo.session.username || 'admin');
    }
    const referer = req.headers.referer || '';
    if (referer.includes('/tc-backstage/users?') || referer.endsWith('/tc-backstage/users')) {
      return redirect(res, referer);
    }
    return redirect(res, `/tc-backstage/users/${encodeURIComponent(nickname)}`);
  }

  const userAdminMatch = pathname.match(/^\/tc-backstage\/users\/([^/]+)\/admin$/);
  if (userAdminMatch && method === 'POST') {
    const nickname = decodeURIComponent(userAdminMatch[1]);
    const body = await parseBody(req);
    const isAdmin = body.is_admin === '1';
    await setUserAdmin(nickname, isAdmin);
    const referer = req.headers.referer || '';
    if (referer.includes('/tc-backstage/users?') || referer.endsWith('/tc-backstage/users')) {
      return redirect(res, referer);
    }
    return redirect(res, `/tc-backstage/users/${encodeURIComponent(nickname)}`);
  }

  // 404
  html(res, layout('찾을 수 없음', '<div class="empty">페이지를 찾을 수 없습니다</div>'), 404);
}

module.exports = { handleAdminRoute };
