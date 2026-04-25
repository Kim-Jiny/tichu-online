const crypto = require('crypto');
const serverStartedAt = new Date();
const {
  verifyAdmin, getInquiries, getInquiryById, resolveInquiry,
  getReports, getReportGroup, updateReportGroupStatus,
  getUsers, getUserDetail, getAdminGoldHistory, getAdminPurchaseHistory, deleteUser, getDashboardStats, getDashboardActivityTopPlayers, getAdminRecentMatches, setChatBan, setAdminMemo, getRecentMatches, adminAdjustGold, setUserAdmin,
  getDetailedAdminStats,
  getAllShopItemsAdmin, addShopItem, updateShopItem, deleteShopItem, getShopItemById,
  getConfig, updateConfig,
  getNotices, getNoticeById, createNotice, updateNotice, deleteNotice,
  insertMaintenanceHistory, getMaintenanceHistory,
  getBroadcastFcmTokens, insertPushHistory, getPushHistory, clearInvalidFcmToken, insertPushRecipients, getPushHistoryDetail,
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

function json(res, payload, status = 200) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(payload));
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
html, body { width: 100%; max-width: 100%; overflow-x: hidden; }
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
.sidebar-header { padding: 0 22px 18px; border-bottom: 1px solid rgba(255,255,255,0.08); margin-bottom: 12px; }
.sidebar-header-link { display: block; color: inherit; text-decoration: none; }
.sidebar h2 { padding: 0; font-size: 18px; color: #fff; margin-bottom: 6px; letter-spacing: 0.01em; }
.sidebar-meta { font-size: 12px; color: rgba(231,239,233,0.62); line-height: 1.5; }
.nav-section { margin: 4px 0 10px; }
.nav-section-label { padding: 0 22px; margin: 14px 0 8px; font-size: 11px; color: rgba(231,239,233,0.45); text-transform: uppercase; letter-spacing: 0.12em; }
.sidebar a { display: block; padding: 13px 22px; color: rgba(231,239,233,0.75); text-decoration: none; font-size: 14px; transition: all 0.2s; border-left: 3px solid transparent; }
.sidebar a:hover { background: rgba(255,255,255,0.06); color: #fff; }
.sidebar a.active { background: rgba(255,255,255,0.08); color: #fff; border-left-color: #dcb46a; }
.sidebar .logout { margin-top: 20px; border-top: 1px solid rgba(255,255,255,0.08); padding-top: 10px; }
.sidebar .logout a { color: #e57373; }
.menu-toggle { display: none; position: fixed; top: 12px; left: 12px; z-index: 200; background: #17352f; color: #fff; border: none; border-radius: 12px; width: 42px; height: 42px; font-size: 22px; cursor: pointer; align-items: center; justify-content: center; box-shadow: 0 8px 24px rgba(16,41,35,0.22); }
.sidebar-overlay { display: none; position: fixed; inset: 0; background: rgba(0,0,0,0.5); z-index: 90; }
.main { margin-left: 248px; flex: 1; padding: 28px; min-height: 100vh; min-width: 0; width: 100%; max-width: 100%; overflow-x: hidden; }
.page-shell { max-width: 1480px; margin: 0 auto; min-width: 0; width: 100%; }
.page-header { display: flex; justify-content: space-between; align-items: flex-start; gap: 16px; margin-bottom: 18px; }
.page-title { font-size: 30px; font-weight: 800; margin-bottom: 8px; color: var(--text); letter-spacing: -0.02em; }
.page-subtitle { font-size: 14px; line-height: 1.6; color: var(--muted); max-width: 760px; }
.header-actions { display: flex; gap: 10px; flex-wrap: wrap; justify-content: flex-end; }
.stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 16px; margin-bottom: 24px; min-width: 0; }
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
  min-width: 0;
  width: 100%;
  max-width: 100%;
}
.card h3 { font-size: 18px; margin-bottom: 16px; color: var(--text); letter-spacing: -0.01em; }
.hero-card {
  background: linear-gradient(135deg, #17352f 0%, #1d4a41 60%, #24584d 100%);
  color: #fff;
  border-radius: 22px;
  padding: 24px;
  margin-bottom: 22px;
  box-shadow: 0 24px 50px rgba(23, 53, 47, 0.24);
  min-width: 0;
  max-width: 100%;
}
.hero-card .eyebrow { font-size: 12px; text-transform: uppercase; letter-spacing: 0.12em; color: rgba(255,255,255,0.72); margin-bottom: 8px; }
.hero-card .headline { font-size: 30px; font-weight: 800; line-height: 1.18; max-width: 760px; letter-spacing: -0.03em; }
.hero-card .sub { margin-top: 10px; color: rgba(255,255,255,0.78); font-size: 14px; line-height: 1.6; }
.hero-meta { display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 12px; margin-top: 20px; min-width: 0; }
.hero-meta .item { background: rgba(255,255,255,0.09); border: 1px solid rgba(255,255,255,0.08); border-radius: 16px; padding: 14px 16px; backdrop-filter: blur(8px); }
.hero-meta .item .k { font-size: 12px; color: rgba(255,255,255,0.7); margin-bottom: 6px; text-transform: uppercase; letter-spacing: 0.06em; }
.hero-meta .item .v { font-size: 22px; font-weight: 800; }
.summary-strip { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 12px; margin-bottom: 20px; min-width: 0; }
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
.table-wrap { overflow-x: auto; -webkit-overflow-scrolling: touch; border: 1px solid rgba(32,28,22,0.06); border-radius: 16px; background: rgba(255,255,255,0.68); scrollbar-width: thin; max-width: 100%; width: 100%; }
table { width: 100%; max-width: 100%; border-collapse: separate; border-spacing: 0; }
th { text-align: left; padding: 12px 14px; background: #f6f3ec; color: var(--muted); font-size: 12px; font-weight: 700; border-bottom: 1px solid #e6dfd2; white-space: nowrap; text-transform: uppercase; letter-spacing: 0.05em; position: sticky; top: 0; z-index: 1; }
th:first-child { border-top-left-radius: 14px; }
th:last-child { border-top-right-radius: 14px; }
td { padding: 12px 14px; border-bottom: 1px solid #f0ebe2; font-size: 14px; vertical-align: top; }
tr:nth-child(even) td { background: rgba(255,255,255,0.35); }
tr:hover td { background: rgba(15,108,92,0.06); }
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
.filter-card {
  padding: 16px 18px;
  border-radius: 18px;
  background: rgba(255,255,255,0.76);
  border: 1px solid rgba(32,28,22,0.06);
  box-shadow: 0 12px 28px rgba(34,29,21,0.05);
  margin-bottom: 18px;
}
.filter-title { font-size: 12px; color: var(--muted); text-transform: uppercase; letter-spacing: 0.08em; margin-bottom: 10px; }
.subtab-bar { display: flex; gap: 10px; flex-wrap: wrap; margin-bottom: 18px; }
.subtab-link {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 10px 14px;
  border-radius: 999px;
  text-decoration: none;
  color: var(--muted);
  background: rgba(255,255,255,0.72);
  border: 1px solid rgba(32,28,22,0.08);
  font-size: 13px;
  font-weight: 700;
}
.subtab-link:hover { color: var(--text); background: rgba(255,255,255,0.92); }
.subtab-link.active {
  color: #fff;
  background: linear-gradient(135deg, #17352f 0%, #24584d 100%);
  border-color: rgba(23,53,47,0.3);
  box-shadow: 0 12px 24px rgba(23,53,47,0.18);
}
.subtab-copy { font-size: 12px; color: var(--muted); margin-bottom: 14px; line-height: 1.6; }
.preset-bar { display: flex; gap: 8px; flex-wrap: wrap; margin-top: 10px; }
.preset-link {
  display: inline-flex;
  align-items: center;
  padding: 8px 12px;
  border-radius: 999px;
  text-decoration: none;
  color: var(--muted);
  background: rgba(255,255,255,0.8);
  border: 1px solid rgba(32,28,22,0.08);
  font-size: 12px;
  font-weight: 700;
}
.preset-link.active {
  color: #fff;
  background: var(--brand);
  border-color: var(--brand);
}
.sticky-kpi-rail {
  position: sticky;
  top: 12px;
  z-index: 20;
  margin-bottom: 18px;
  padding: 16px 18px;
  border-radius: 18px;
  background: rgba(255,255,255,0.9);
  border: 1px solid rgba(32,28,22,0.08);
  box-shadow: 0 14px 28px rgba(34,29,21,0.08);
  backdrop-filter: blur(10px);
}
.sticky-kpi-title { font-size: 12px; color: var(--muted); text-transform: uppercase; letter-spacing: 0.08em; margin-bottom: 10px; }
.sticky-kpi-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 10px; }
.sticky-kpi-item { padding: 12px 14px; border-radius: 14px; background: #f7f3ea; border: 1px solid #ebe4d8; }
.sticky-kpi-item .k { font-size: 11px; color: var(--muted); text-transform: uppercase; letter-spacing: 0.06em; margin-bottom: 6px; }
.sticky-kpi-item .v { font-size: 22px; font-weight: 800; color: var(--text); letter-spacing: -0.02em; }
.sticky-kpi-item .m { margin-top: 6px; font-size: 12px; color: var(--muted); line-height: 1.5; }
.status-strip { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 12px; margin-bottom: 18px; }
.status-card {
  padding: 14px 16px;
  border-radius: 16px;
  border: 1px solid rgba(32,28,22,0.08);
  background: rgba(255,255,255,0.85);
}
.status-card.warning { background: rgba(255,244,229,0.95); border-color: rgba(198,123,43,0.25); }
.status-card.danger { background: rgba(255,235,238,0.95); border-color: rgba(192,86,63,0.25); }
.status-card.good { background: rgba(232,245,233,0.95); border-color: rgba(46,125,50,0.22); }
.status-card .title { font-size: 13px; font-weight: 800; color: var(--text); margin-bottom: 6px; }
.status-card .desc { font-size: 12px; color: var(--muted); line-height: 1.55; }
.pagination { display: flex; gap: 8px; margin-top: 16px; justify-content: center; flex-wrap: wrap; }
.pagination a { padding: 7px 12px; border-radius: 10px; background: #ece5d8; color: #333; text-decoration: none; font-size: 13px; }
.pagination a.active { background: var(--brand); color: #fff; }
.chat-log { max-height: 400px; overflow-y: auto; background: #f7f4ee; border-radius: 14px; padding: 12px; margin: 12px 0; border: 1px solid #ebe3d7; }
.chat-msg { padding: 6px 0; border-bottom: 1px solid #eee; font-size: 13px; }
.chat-msg .sender { font-weight: 700; color: var(--text); }
.chat-msg .text { color: #555; }
.empty { text-align: center; padding: 40px; color: var(--muted); font-size: 15px; }
.grid-2col { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin-bottom: 20px; min-width: 0; }
.form-grid { display: grid; grid-template-columns: 140px 1fr; gap: 12px 16px; align-items: center; max-width: 600px; }
.muted { color: var(--muted); }
.mono { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
.table-meta { display: flex; justify-content: space-between; align-items: center; gap: 12px; margin-bottom: 14px; flex-wrap: wrap; }
.progress { height: 8px; border-radius: 999px; background: #ece6dc; overflow: hidden; }
.progress > span { display: block; height: 100%; border-radius: inherit; background: linear-gradient(90deg, var(--brand), #2f9b83); }
.split-stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 14px; }
.soft-panel { background: #f7f3ea; border-radius: 16px; padding: 16px; border: 1px solid #ebe4d8; }
.soft-panel h4 { font-size: 14px; margin-bottom: 10px; color: var(--text); }

@media (max-width: 1100px) {
  .main { padding: 20px; }
  .page-title { font-size: 28px; }
  .grid-2col { grid-template-columns: 1fr; }
  .sticky-kpi-rail { position: static; top: auto; }
}

@media (max-width: 768px) {
  .menu-toggle { display: flex; }
  .sidebar {
    width: min(82vw, 320px);
    transform: translateX(-100%);
    padding-top: 64px;
  }
  .sidebar.open { transform: translateX(0); }
  .sidebar-overlay.open { display: block; }
  .main { margin-left: 0; padding: 14px; padding-top: 64px; width: 100vw; max-width: 100vw; }
  .page-shell { max-width: 100%; }
  .page-header { flex-direction: column; }
  .page-title { font-size: 24px; }
  .page-subtitle { font-size: 13px; }
  .header-actions { width: 100%; }
  .header-actions .btn { width: 100%; text-align: center; }
  .hero-card .headline { font-size: 24px; }
  .hero-card { padding: 18px; border-radius: 18px; }
  .hero-card .sub { font-size: 13px; }
  .hero-meta { grid-template-columns: 1fr 1fr; gap: 10px; }
  .hero-meta .item { padding: 12px; }
  .hero-meta .item .v { font-size: 18px; }
  .stats-grid { grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 10px; }
  .stat-card { padding: 14px; }
  .stat-card .value { font-size: 22px; }
  .card { padding: 14px; border-radius: 16px; }
  .summary-strip { grid-template-columns: 1fr 1fr; }
  .summary-item { padding: 14px; }
  .summary-item .v { font-size: 20px; }
  .detail-grid { grid-template-columns: 100px 1fr; gap: 6px 12px; }
  .form-grid { grid-template-columns: 1fr; max-width: 100%; }
  .form-grid label { font-weight: 600; margin-top: 4px; }
  .search-bar { flex-direction: column; gap: 10px; }
  .search-bar > * { width: 100%; min-width: 0 !important; }
  .search-bar .btn { width: 100%; text-align: center; }
  .filter-card { padding: 14px; border-radius: 16px; }
  .subtab-bar,
  .preset-bar {
    flex-wrap: nowrap;
    overflow-x: auto;
    -webkit-overflow-scrolling: touch;
    padding-bottom: 4px;
    margin-right: -4px;
  }
  .subtab-link,
  .preset-link { white-space: nowrap; flex: 0 0 auto; }
  .subtab-link { padding: 9px 12px; font-size: 12px; }
  .subtab-link span:last-child { display: none; }
  .sticky-kpi-rail { padding: 14px; border-radius: 16px; }
  .sticky-kpi-grid { grid-template-columns: 1fr 1fr; }
  .sticky-kpi-item { padding: 12px; }
  .sticky-kpi-item .v { font-size: 18px; }
  .status-strip { grid-template-columns: 1fr; }
  .card-actions { flex-direction: column; }
  .card-actions .btn { width: 100%; text-align: center; }
  .split-stats { grid-template-columns: 1fr; }
  .soft-panel { padding: 14px; }
  .detail-grid { grid-template-columns: 1fr; }
  .detail-grid .label { margin-top: 8px; }
  .table-meta { align-items: stretch; }
  .table-meta > * { width: 100%; }
  .table-wrap { margin: 0; border-radius: 14px; width: 100%; max-width: 100%; }
  table { font-size: 13px; width: max-content; min-width: 100%; }
  th, td { padding: 9px 10px; }
  textarea, select, input[type="date"], input[type="datetime-local"], input[type="number"], input[type="text"], input[type="password"] {
    font-size: 16px;
  }
  .btn { padding: 11px 14px; }
}
@media (max-width: 480px) {
  .sidebar { width: 88vw; }
  .main { padding: 12px; padding-top: 60px; width: 100vw; max-width: 100vw; }
  .page-title { font-size: 22px; }
  .stats-grid { grid-template-columns: 1fr 1fr; gap: 8px; }
  .summary-strip { grid-template-columns: 1fr; }
  .stat-card { padding: 10px; }
  .stat-card .value { font-size: 18px; }
  .hero-card { padding: 16px; }
  .hero-card .headline { font-size: 20px; }
  .hero-meta { grid-template-columns: 1fr; }
  .sticky-kpi-grid { grid-template-columns: 1fr; }
  .subtab-link { padding: 8px 11px; }
  .preset-link { padding: 8px 10px; font-size: 11px; }
  .table-wrap { margin: 0; }
  table { width: max-content; min-width: 100%; }
}
</style>
</head>
<body>
<button class="menu-toggle" onclick="document.querySelector('.sidebar').classList.toggle('open');document.querySelector('.sidebar-overlay').classList.toggle('open')">&#9776;</button>
<div class="sidebar-overlay" onclick="document.querySelector('.sidebar').classList.remove('open');this.classList.remove('open')"></div>
<nav class="sidebar">
  <div class="sidebar-header">
    <a href="/tc-backstage/" class="sidebar-header-link" onclick="closeSidebar()">
      <h2>Tichu Admin</h2>
      <div class="sidebar-meta">운영 대시보드 · 실시간 점검 · 게임 모니터링</div>
    </a>
  </div>
  <div class="nav-section">
    <div class="nav-section-label">Overview</div>
    <a href="/tc-backstage/" class="${activePage === 'home' ? 'active' : ''}" onclick="closeSidebar()">대시보드</a>
    <a href="/tc-backstage/stats" class="${activePage === 'stats' ? 'active' : ''}" onclick="closeSidebar()">통계</a>
  </div>
  <div class="nav-section">
    <div class="nav-section-label">Operations</div>
    <a href="/tc-backstage/inquiries" class="${activePage === 'inquiries' ? 'active' : ''}" onclick="closeSidebar()">문의</a>
    <a href="/tc-backstage/reports" class="${activePage === 'reports' ? 'active' : ''}" onclick="closeSidebar()">신고</a>
    <a href="/tc-backstage/users" class="${activePage === 'users' ? 'active' : ''}" onclick="closeSidebar()">유저</a>
    <a href="/tc-backstage/shop" class="${activePage === 'shop' ? 'active' : ''}" onclick="closeSidebar()">상점</a>
  </div>
  <div class="nav-section">
    <div class="nav-section-label">Comms</div>
    <a href="/tc-backstage/notices" class="${activePage === 'notices' ? 'active' : ''}" onclick="closeSidebar()">공지사항</a>
    <a href="/tc-backstage/push" class="${activePage === 'push' ? 'active' : ''}" onclick="closeSidebar()">푸시알림</a>
  </div>
  <div class="nav-section">
    <div class="nav-section-label">System</div>
    <a href="/tc-backstage/maintenance" class="${activePage === 'maintenance' ? 'active' : ''}" onclick="closeSidebar()">점검</a>
    <a href="/tc-backstage/settings" class="${activePage === 'settings' ? 'active' : ''}" onclick="closeSidebar()">설정</a>
  </div>
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

// sv-SE locale formats dates as YYYY-MM-DD; combined with an explicit
// KST timeZone this avoids the toLocaleString→Date round-trip that was
// silently shifting day labels near the KST-midnight boundary.
const _kstDateFmt = new Intl.DateTimeFormat('sv-SE', { timeZone: 'Asia/Seoul' });

// Read KST wall-clock components for any input the JS Date constructor
// accepts. Used wherever we render KST date+time on a non-KST host (prod
// is UTC) without going through the fragile toLocaleString round-trip.
const _kstPartsFmt = new Intl.DateTimeFormat('en-GB', {
  timeZone: 'Asia/Seoul',
  year: 'numeric', month: '2-digit', day: '2-digit',
  hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false,
});
function kstParts(d) {
  const dt = new Date(d);
  if (Number.isNaN(dt.getTime())) return null;
  const out = {};
  for (const p of _kstPartsFmt.formatToParts(dt)) out[p.type] = p.value;
  if (out.hour === '24') out.hour = '00';
  return out;
}

function formatDateInput(d) {
  if (!d) return '';
  const dt = new Date(d);
  if (isNaN(dt.getTime())) return '';
  return _kstDateFmt.format(dt);
}

function kstDateKey(d) {
  return formatDateInput(d);
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

function buildDeltaMeta(currentValue, previousValue, suffix = '', digits = 1) {
  const current = Number(currentValue || 0);
  const previous = Number(previousValue || 0);
  if (!Number.isFinite(previous) || previous === 0) {
    return '비교 기준 없음';
  }
  const delta = ((current - previous) / previous) * 100;
  const sign = delta > 0 ? '+' : '';
  return `이전 기간 대비 ${sign}${delta.toFixed(digits)}%${suffix}`;
}

function gameTypeBadge(gameType) {
  if (gameType === 'skull_king') {
    return '<span class="badge" style="background:#ff7043;color:#fff">스컬킹</span>';
  }
  if (gameType === 'love_letter') {
    return '<span class="badge" style="background:#E91E63;color:#fff">러브레터</span>';
  }
  if (gameType === 'mighty') {
    return '<span class="badge" style="background:#1565C0;color:#fff">마이티</span>';
  }
  return '<span class="badge" style="background:#6c63ff;color:#fff">티츄</span>';
}

function mightySuitLabel(suit) {
  if (suit === 'spade') return '♠';
  if (suit === 'heart') return '♥';
  if (suit === 'diamond') return '♦';
  if (suit === 'club') return '♣';
  if (suit === 'no_trump') return 'NT';
  return suit || '-';
}

function renderAdminCardChip(cardId) {
  if (!cardId) return '<span style="color:#999">-</span>';
  let label = cardId;
  let style = 'background:#f0f0f0;color:#333;';
  if (cardId === 'mighty_joker') {
    label = 'Joker';
    style = 'background:#fff3e0;color:#e65100;font-weight:700;';
  } else if (cardId.startsWith('mighty_')) {
    const raw = cardId.replace('mighty_', '');
    const parts = raw.split('_');
    if (parts.length === 2) {
      label = `${mightySuitLabel(parts[0])}${parts[1]}`;
    }
    if (parts[0] === 'heart' || parts[0] === 'diamond') {
      style = 'background:#ffebee;color:#c62828;';
    } else {
      style = 'background:#eceff1;color:#263238;';
    }
  } else if (cardId.startsWith('special_')) {
    style = 'background:#fff3e0;color:#e65100;font-weight:700;';
  }
  return `<code style="${style}padding:2px 6px;border-radius:4px;font-size:11px;margin:1px;display:inline-block;">${escapeHtml(label)}</code>`;
}

function renderAdminRecentMatchesTable(matches) {
  if (!matches || matches.length === 0) return '<div class="empty">최근 매치 없음</div>';
  return `<div class="table-wrap"><table>
    <tr><th>ID</th><th>게임</th><th>결과</th><th>점수/플레이어</th><th>유형</th><th>종료</th><th>날짜</th></tr>
    ${matches.map(m => {
      const endReason = m.end_reason || 'normal';
      let endBadge = '<span class="badge" style="background:#e8f5e9;color:#2e7d32">정상</span>';
      if (endReason === 'leave') {
        endBadge = `<span class="badge" style="background:#fce4ec;color:#c62828">이탈</span>${m.deserter_nickname ? `<br><span style="font-size:11px;color:#c62828">${escapeHtml(m.deserter_nickname)}</span>` : ''}`;
      } else if (endReason === 'timeout') {
        endBadge = `<span class="badge" style="background:#fff8e1;color:#f57f17">시간초과</span>${m.deserter_nickname ? `<br><span style="font-size:11px;color:#f57f17">${escapeHtml(m.deserter_nickname)}</span>` : ''}`;
      }
      const rankedBadge = m.is_ranked ? '<span class="badge" style="background:#fff3e0;color:#e65100">랭크</span>' : '<span class="badge" style="background:#f5f5f5;color:#999">일반</span>';
      if (m.game_type === 'skull_king' || m.game_type === 'love_letter' || m.game_type === 'mighty') {
        return `<tr>
          <td>${m.id}</td>
          <td>${gameTypeBadge(m.game_type)}</td>
          <td><span class="badge" style="background:#fff3e0;color:#e65100">${m.player_a2 || '?'}인</span></td>
          <td style="font-size:12px">${m.player_a1 ? escapeHtml(m.player_a1) : '-'}</td>
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
        <td>${gameTypeBadge(m.game_type)}</td>
        <td>${winBadge}</td>
        <td style="font-size:12px"><span style="${aStyle}">${m.team_a_score}</span> : <span style="${bStyle}">${m.team_b_score}</span><br><span style="${aStyle}">${escapeHtml(m.player_a1)}, ${escapeHtml(m.player_a2)}</span> vs <span style="${bStyle}">${escapeHtml(m.player_b1)}, ${escapeHtml(m.player_b2)}</span></td>
        <td>${rankedBadge}</td>
        <td>${endBadge}</td>
        <td style="font-size:12px;color:#888">${formatDate(m.created_at)}</td>
      </tr>`;
    }).join('')}
  </table></div>`;
}

function dashboardActivityMeta(period = 'week', game = 'all') {
  const activityLabels = {
    today: { title: '오늘 게임량', range: '오늘 KST 기준' },
    week: { title: '주간 게임량', range: '최근 7일 KST 기준' },
    month: { title: '월간 게임량', range: '최근 30일 KST 기준' },
  };
  const activityGameLabels = {
    all: { label: '전체', title: '전체 게임량' },
    tichu: { label: '티츄', title: '티츄 게임량' },
    skull_king: { label: 'SK', title: 'SK 게임량' },
    love_letter: { label: 'LL', title: 'LL 게임량' },
    mighty: { label: '마이티', title: '마이티 게임량' },
  };
  const safePeriod = activityLabels[period] ? period : 'week';
  const safeGame = activityGameLabels[game] ? game : 'all';
  return {
    period: safePeriod,
    game: safeGame,
    periodLabel: activityLabels[safePeriod],
    gameLabel: activityGameLabels[safeGame],
  };
}

function dashboardActivityLink(period, game, label, active) {
  const href = `/tc-backstage/?activity=${encodeURIComponent(period)}&activityGame=${encodeURIComponent(game)}`;
  const apiHref = `/tc-backstage/dashboard/activity-top?activity=${encodeURIComponent(period)}&activityGame=${encodeURIComponent(game)}`;
  return `<a class="preset-link ${active ? 'active' : ''}" href="${href}" data-activity-filter="1" data-api-href="${apiHref}">${label}</a>`;
}

function renderDashboardActivityTopContent(topPlayers, period = 'week', game = 'all') {
  const meta = dashboardActivityMeta(period, game);
  const activityFilter = ['today', 'week', 'month'].map(p => {
    const label = p === 'today' ? '오늘' : p === 'week' ? '주간' : '월간';
    return dashboardActivityLink(p, meta.game, label, p === meta.period);
  }).join('');
  const gameActivityFilter = [
    ['all', '전체'],
    ['tichu', '티츄'],
    ['skull_king', 'SK'],
    ['love_letter', 'LL'],
    ['mighty', '마이티'],
  ].map(([g, label]) => dashboardActivityLink(meta.period, g, label, g === meta.game)).join('');

  const table = topPlayers && topPlayers.length > 0
    ? `<div class="table-wrap"><table>
        <tr><th>#</th><th>닉네임</th><th>${meta.gameLabel.title}</th><th>게임별</th><th>누적 게임</th><th>레이팅</th><th>Lv</th></tr>
        ${topPlayers.map((p, i) => {
          const medal = i === 0 ? '🥇' : i === 1 ? '🥈' : i === 2 ? '🥉' : `${i + 1}`;
          const tichuGames = parseInt(p.tichu_games) || 0;
          const skGames = parseInt(p.sk_games) || 0;
          const llGames = parseInt(p.ll_games) || 0;
          const mightyGames = parseInt(p.mighty_games) || 0;
          const rankGames = meta.game === 'tichu'
            ? tichuGames
            : meta.game === 'skull_king'
              ? skGames
              : meta.game === 'love_letter'
                ? llGames
                : meta.game === 'mighty'
                  ? mightyGames
                  : parseInt(p.activity_games) || 0;
          const totalGamesAll = (parseInt(p.total_games) || 0) + (parseInt(p.sk_total_games) || 0) + (parseInt(p.ll_total_games) || 0) + (parseInt(p.mighty_total_games) || 0);
          return `<tr>
            <td style="text-align:center">${medal}</td>
            <td><a href="/tc-backstage/users/${encodeURIComponent(p.nickname)}" style="color:#6c63ff;text-decoration:none;font-weight:600">${escapeHtml(p.nickname)}</a></td>
            <td style="font-weight:800">${formatNumber(rankGames)}판</td>
            <td style="font-size:12px;color:#666;line-height:1.6">
              <span style="color:#5f62d6">티츄 ${formatNumber(tichuGames)}</span> ·
              <span style="color:#ff7043">SK ${formatNumber(skGames)}</span> ·
              <span style="color:#E91E63">LL ${formatNumber(llGames)}</span> ·
              <span style="color:#1565C0">마이티 ${formatNumber(mightyGames)}</span>
            </td>
            <td>${formatNumber(totalGamesAll)}판</td>
            <td style="font-weight:700">${p.rating}</td>
            <td>${p.level}</td>
          </tr>`;
        }).join('')}
      </table></div>`
    : '<div class="empty">아직 플레이어 없음</div>';

  return `
    <div class="table-meta">
      <div>
        <h3>플레이량 Top 10</h3>
        <div class="muted" style="font-size:12px">${meta.periodLabel.range} · ${meta.gameLabel.label} 기준 참여 횟수로 정렬합니다.</div>
      </div>
      <div>
        <div class="preset-bar" style="margin-top:0">${activityFilter}</div>
        <div class="preset-bar" style="margin-top:8px">${gameActivityFilter}</div>
      </div>
    </div>
    ${table}
  `;
}

// ===== Shop form helpers =====

function formatDatetimeLocal(d) {
  if (!d) return '';
  const p = kstParts(d);
  if (!p) return '';
  return `${p.year}-${p.month}-${p.day}T${p.hour}:${p.minute}`;
}

// Material icon names exposed in the admin visual editor. Keep in sync with
// the icon set the Flutter renderer recognises (lib/widgets/shop_visual.dart
// IconData mapping). Adding a new entry here without registering it on the
// client will fall back to a default icon.
const SHOP_VISUAL_ICONS = [
  'auto_awesome', 'local_florist', 'spa', 'wb_twilight', 'emoji_events',
  'cake', 'shield', 'flash_on', 'local_fire_department', 'anchor',
  'psychology', 'star', 'theater_comedy', 'military_tech', 'workspace_premium',
  'emoji_nature', 'security', 'sentiment_very_dissatisfied', 'visibility_off',
  'whatshot', 'ac_unit', 'diamond', 'blur_on', 'bolt', 'style', 'elderly',
  'cloud', 'wb_sunny', 'coffee', 'filter_vintage', 'nights_stay', 'park',
  'waves', 'icecream', 'brightness_7', 'healing', 'local_hospital',
  'analytics', 'restart_alt', 'handyman', 'flag', 'badge', 'palette',
  'card_giftcard', 'celebration', 'verified', 'rocket_launch', 'pets',
];

// effect_type values the server actually understands. Admin can choose a
// type from this list and tweak effect_value, but cannot invent a brand new
// effect category from the form (would need server-side handling).
const SHOP_EFFECT_TYPES = [
  'leave_count_reduce', 'leave_count_reset',
  'nickname_change', 'stats_reset',
  'season_stats_reset', 'tichu_season_stats_reset',
  'sk_season_stats_reset', 'mighty_season_stats_reset',
];

function _normalizeHexColor(input, fallback) {
  if (typeof input !== 'string') return fallback;
  const m = input.trim().match(/^#?([0-9a-fA-F]{6})$/);
  return m ? `#${m[1].toUpperCase()}` : fallback;
}

// Build the visual JSON object from the form body. Returns null when the
// form opts out of visual config so the caller can leave metadata.visual
// untouched (skipping the field in the form preserves admin's previous
// edits if the route re-submits).
function buildVisualFromBody(body) {
  if (body.visual_disabled === 'on') return null;
  const icon = (body.visual_icon || '').toString().trim();
  const iconColor   = _normalizeHexColor(body.visual_iconColor,   '#666666');
  const borderColor = _normalizeHexColor(body.visual_borderColor, '#DDDDDD');
  const bgKind = body.visual_bg_kind === 'solid' ? 'solid' : 'gradient';
  const thumbnail = { icon: icon || 'flag', iconColor, borderColor };
  if (bgKind === 'solid') {
    thumbnail.background = {
      kind: 'solid',
      color: _normalizeHexColor(body.visual_bg_solid, '#FFFFFF'),
    };
  } else {
    const stop0 = _normalizeHexColor(body.visual_bg_stop0, '#FFFFFF');
    const stop1 = _normalizeHexColor(body.visual_bg_stop1, '#EEEEEE');
    const angle = parseInt(body.visual_bg_angle, 10);
    thumbnail.background = {
      kind: 'gradient',
      angle: Number.isFinite(angle) ? Math.max(0, Math.min(360, angle)) : 0,
      stops: [{ color: stop0, at: 0.0 }, { color: stop1, at: 1.0 }],
    };
  }
  const out = { version: 1, thumbnail };
  if (body.visual_preview_enabled === 'on') {
    const p0 = _normalizeHexColor(body.visual_preview_stop0, '#FFFFFF');
    const p1 = _normalizeHexColor(body.visual_preview_stop1, '#EEEEEE');
    out.preview = {
      background: {
        kind: 'gradient', angle: 0,
        stops: [{ color: p0, at: 0.0 }, { color: p1, at: 1.0 }],
      },
    };
  }
  if (body.visual_text_color) {
    out.text = { color: _normalizeHexColor(body.visual_text_color, '#FFFFFF') };
  }
  return out;
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

  // Pull existing visual (from row metadata) so the editor pre-fills
  let visual = null;
  if (values && values.metadata && typeof values.metadata === 'object') {
    visual = values.metadata.visual || null;
  } else if (typeof values?.metadata === 'string') {
    try { visual = JSON.parse(values.metadata)?.visual || null; } catch (_) { /* noop */ }
  }
  // Form fields can also override directly (re-render after validation error)
  const formVisual = (key, def) => {
    if (values[`visual_${key}`] !== undefined) return values[`visual_${key}`];
    return def;
  };
  const t = visual?.thumbnail || {};
  const bg = t.background || { kind: 'gradient', stops: [{}, {}] };
  const stop0 = bg.stops?.[0]?.color || '#FFFFFF';
  const stop1 = bg.stops?.[1]?.color || '#EEEEEE';
  const previewBg = visual?.preview?.background;
  const pStop0 = previewBg?.stops?.[0]?.color || stop0;
  const pStop1 = previewBg?.stops?.[1]?.color || stop1;

  const iconName       = formVisual('icon', t.icon || 'flag');
  const iconColor      = formVisual('iconColor',   t.iconColor   || '#666666');
  const borderColor    = formVisual('borderColor', t.borderColor || '#DDDDDD');
  const bgKind         = formVisual('bg_kind', bg.kind || 'gradient');
  const bgAngle        = formVisual('bg_angle', bg.angle ?? 0);
  const bgStop0        = formVisual('bg_stop0', stop0);
  const bgStop1        = formVisual('bg_stop1', stop1);
  const bgSolid        = formVisual('bg_solid', stop0);
  const previewEnabled = formVisual('preview_enabled', visual?.preview ? 'on' : '') === 'on';
  const previewStop0   = formVisual('preview_stop0', pStop0);
  const previewStop1   = formVisual('preview_stop1', pStop1);
  const textColor      = formVisual('text_color', visual?.text?.color || '');

  const iconOptions = SHOP_VISUAL_ICONS.map(i => `<option value="${i}">`).join('');
  const effectOptions = ['', ...SHOP_EFFECT_TYPES].map(e =>
    `<option value="${e}" ${v('effect_type', '') === e ? 'selected' : ''}>${e || '-'}</option>`
  ).join('');

  return `<form method="POST" action="${action}" id="shopItemForm">
    <div class="form-grid">
      <label>아이템 키</label>
      <input type="text" name="item_key" value="${escapeHtml(v('item_key'))}" ${isEdit ? 'readonly style="background:#f0f0f0"' : 'required'} placeholder="예: banner_new">
      <label>이름 (한국어)</label>
      <input type="text" name="name_ko" value="${escapeHtml(v('name_ko'))}" required placeholder="아이템 이름 (한국어)">
      <label>이름 (English)</label>
      <input type="text" name="name_en" value="${escapeHtml(v('name_en'))}" placeholder="Item name (English)">
      <label>이름 (Deutsch)</label>
      <input type="text" name="name_de" value="${escapeHtml(v('name_de'))}" placeholder="Artikelname (Deutsch)">
      <label>설명 (한국어)</label>
      <textarea name="description_ko" rows="2" style="padding:10px;border:1px solid #ddd;border-radius:8px;font-size:14px;font-family:inherit" placeholder="아이템 설명 (선택)">${escapeHtml(v('description_ko'))}</textarea>
      <label>설명 (English)</label>
      <textarea name="description_en" rows="2" style="padding:10px;border:1px solid #ddd;border-radius:8px;font-size:14px;font-family:inherit" placeholder="Item description (optional)">${escapeHtml(v('description_en'))}</textarea>
      <label>설명 (Deutsch)</label>
      <textarea name="description_de" rows="2" style="padding:10px;border:1px solid #ddd;border-radius:8px;font-size:14px;font-family:inherit" placeholder="Artikelbeschreibung (optional)">${escapeHtml(v('description_de'))}</textarea>
      <label>분류</label>
      <select name="category" id="shopCategory" style="padding:10px;border:1px solid #ddd;border-radius:8px;font-size:14px">${categoryOptions}</select>
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
      <select name="effect_type" style="padding:10px;border:1px solid #ddd;border-radius:8px;font-size:14px">${effectOptions}</select>
      <label>효과 수치</label>
      <input type="number" name="effect_value" value="${v('effect_value', '')}" style="padding:10px;border:1px solid #ddd;border-radius:8px;font-size:14px" placeholder="해당 효과의 수치 (예: 카운트 감소량)">
      <label>판매 시작</label>
      <input type="datetime-local" name="sale_start" value="${formatDatetimeLocal(v('sale_start'))}" style="padding:10px;border:1px solid #ddd;border-radius:8px;font-size:14px">
      <label>판매 종료</label>
      <input type="datetime-local" name="sale_end" value="${formatDatetimeLocal(v('sale_end'))}" style="padding:10px;border:1px solid #ddd;border-radius:8px;font-size:14px">
    </div>

    <h3 style="margin-top:24px;margin-bottom:8px">시각 (썸네일)</h3>
    <div class="muted" style="margin-bottom:12px">상점 카드 미리보기에 사용. 옛 앱은 무시하니 새 아이템도 안전합니다.</div>
    <div style="display:grid;grid-template-columns:1fr 220px;gap:24px;align-items:start">
      <div class="form-grid">
        <label>아이콘</label>
        <input list="visualIconList" name="visual_icon" value="${escapeHtml(iconName)}" placeholder="예: auto_awesome" style="padding:10px;border:1px solid #ddd;border-radius:8px;font-size:14px">
        <datalist id="visualIconList">${iconOptions}</datalist>
        <label>아이콘 색</label>
        <input type="color" name="visual_iconColor" value="${escapeHtml(iconColor)}" style="height:40px;width:100%">
        <label>테두리 색</label>
        <input type="color" name="visual_borderColor" value="${escapeHtml(borderColor)}" style="height:40px;width:100%">
        <label>배경 종류</label>
        <select name="visual_bg_kind" id="visualBgKind" style="padding:10px;border:1px solid #ddd;border-radius:8px;font-size:14px">
          <option value="gradient" ${bgKind === 'gradient' ? 'selected' : ''}>그라데이션</option>
          <option value="solid" ${bgKind === 'solid' ? 'selected' : ''}>단색</option>
        </select>
        <label class="visualGradientOnly">그라데이션 시작</label>
        <input type="color" name="visual_bg_stop0" value="${escapeHtml(bgStop0)}" class="visualGradientOnly" style="height:40px;width:100%">
        <label class="visualGradientOnly">그라데이션 끝</label>
        <input type="color" name="visual_bg_stop1" value="${escapeHtml(bgStop1)}" class="visualGradientOnly" style="height:40px;width:100%">
        <label class="visualGradientOnly">각도 (0~360°)</label>
        <input type="number" name="visual_bg_angle" value="${bgAngle}" min="0" max="360" class="visualGradientOnly" style="padding:10px;border:1px solid #ddd;border-radius:8px;font-size:14px">
        <label class="visualSolidOnly">단색</label>
        <input type="color" name="visual_bg_solid" value="${escapeHtml(bgSolid)}" class="visualSolidOnly" style="height:40px;width:100%">
        <label>제목/라벨 색 (선택)</label>
        <input type="color" name="visual_text_color" value="${escapeHtml(textColor || '#FFFFFF')}" style="height:40px;width:100%">
      </div>
      <div>
        <div class="muted" style="font-size:11px;margin-bottom:6px">미리보기</div>
        <div id="visualPreviewCard" style="border-radius:14px;padding:18px;text-align:center;border:2px solid #ddd;min-height:90px;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:6px">
          <span class="material-icons" id="visualPreviewIcon" style="font-size:36px">flag</span>
          <div id="visualPreviewLabel" style="font-size:12px;font-weight:600;color:#444">미리보기</div>
        </div>
      </div>
    </div>

    <h3 style="margin-top:20px;margin-bottom:8px">시각 (인게임 미리보기 — 배너 한정)</h3>
    <label style="display:flex;align-items:center;gap:8px;margin-bottom:8px">
      <input type="checkbox" name="visual_preview_enabled" ${previewEnabled ? 'checked' : ''} id="visualPreviewToggle">
      <span>인게임에서 다른 그라데이션을 사용 (체크하지 않으면 썸네일 그라데이션 사용)</span>
    </label>
    <div id="visualPreviewSection" class="form-grid" style="${previewEnabled ? '' : 'display:none'}">
      <label>인게임 시작 색</label>
      <input type="color" name="visual_preview_stop0" value="${escapeHtml(previewStop0)}" style="height:40px;width:100%">
      <label>인게임 끝 색</label>
      <input type="color" name="visual_preview_stop1" value="${escapeHtml(previewStop1)}" style="height:40px;width:100%">
    </div>

    <div style="margin-top:24px">
      <button type="submit" class="btn btn-primary">${isEdit ? '저장' : '추가'}</button>
    </div>

    <link rel="stylesheet" href="https://fonts.googleapis.com/icon?family=Material+Icons">
    <script>
      (function() {
        const previewCard  = document.getElementById('visualPreviewCard');
        const previewIcon  = document.getElementById('visualPreviewIcon');
        const previewLabel = document.getElementById('visualPreviewLabel');
        const bgKindSel    = document.getElementById('visualBgKind');
        const previewToggle = document.getElementById('visualPreviewToggle');
        const previewSection = document.getElementById('visualPreviewSection');
        const $ = (name) => document.querySelector('[name="' + name + '"]');
        const setVis = (sel, on) => document.querySelectorAll(sel).forEach(el => el.style.display = on ? '' : 'none');
        function applyKind() {
          const kind = bgKindSel.value;
          setVis('.visualGradientOnly', kind === 'gradient');
          setVis('.visualSolidOnly',    kind === 'solid');
          render();
        }
        function applyPreviewToggle() {
          previewSection.style.display = previewToggle.checked ? '' : 'none';
        }
        function render() {
          const icon   = $('visual_icon').value || 'flag';
          const iconC  = $('visual_iconColor').value;
          const border = $('visual_borderColor').value;
          const text   = $('visual_text_color').value;
          previewIcon.textContent = icon;
          previewIcon.style.color = iconC;
          previewCard.style.border = '2px solid ' + border;
          previewLabel.style.color = text;
          if (bgKindSel.value === 'solid') {
            previewCard.style.background = $('visual_bg_solid').value;
          } else {
            const a = parseInt($('visual_bg_angle').value, 10) || 0;
            previewCard.style.background =
              'linear-gradient(' + a + 'deg, ' + $('visual_bg_stop0').value + ', ' + $('visual_bg_stop1').value + ')';
          }
        }
        bgKindSel.addEventListener('change', applyKind);
        previewToggle.addEventListener('change', applyPreviewToggle);
        document.querySelectorAll('[name^="visual_"]').forEach(el => el.addEventListener('input', render));
        applyKind();
        applyPreviewToggle();
        render();
      })();
    </script>
  </form>`;
}

function parseShopFormBody(body) {
  return {
    item_key: body.item_key || '',
    name_ko: body.name_ko || '',
    name_en: body.name_en || '',
    name_de: body.name_de || '',
    description_ko: body.description_ko || '',
    description_en: body.description_en || '',
    description_de: body.description_de || '',
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
    visual: buildVisualFromBody(body),
  };
}

// ===== Route handler =====

async function handleAdminRoute(req, res, url, pathname, method, lobby, wss, maintenanceFns = {}) {
  const { getMaintenanceConfig, setMaintenanceConfig, getMaintenanceStatus, sendPushNotification, sendBroadcastPush } = maintenanceFns;
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

  if (pathname === '/tc-backstage/dashboard/activity-top' && method === 'GET') {
    const activityPeriod = ['today', 'week', 'month'].includes(url.searchParams.get('activity'))
      ? url.searchParams.get('activity')
      : 'week';
    const activityGame = ['all', 'tichu', 'skull_king', 'love_letter', 'mighty'].includes(url.searchParams.get('activityGame'))
      ? url.searchParams.get('activityGame')
      : 'all';
    const data = await getDashboardActivityTopPlayers(activityPeriod, activityGame);
    return json(res, {
      html: renderDashboardActivityTopContent(data.rows, data.period, data.game),
      url: `/tc-backstage/?activity=${encodeURIComponent(data.period)}&activityGame=${encodeURIComponent(data.game)}`,
    });
  }

  // Dashboard home
  if (pathname === '/tc-backstage/' || pathname === '/tc-backstage') {
    const activityPeriod = ['today', 'week', 'month'].includes(url.searchParams.get('activity'))
      ? url.searchParams.get('activity')
      : 'week';
    const activityGame = ['all', 'tichu', 'skull_king', 'love_letter', 'mighty'].includes(url.searchParams.get('activityGame'))
      ? url.searchParams.get('activityGame')
      : 'all';
    const stats = await getDashboardStats(activityPeriod, activityGame);
    // Get live data from lobby/wss
    const connectedUsers = wss ? wss.clients.size : 0;
    const allRooms = lobby ? lobby.getRoomList() : [];
    const activeRooms = allRooms.length;
    const gamingRooms = allRooms.filter(r => r.gameInProgress).length;
    const waitingRooms = activeRooms - gamingRooms;
    const totalSpectators = allRooms.reduce((s, r) => s + (r.spectatorCount || 0), 0);

    // Chart data — build last-7 slots anchored on KST today, so the
    // chart's 'today' slot matches the DB's KST-today grouping even when
    // server wall-clock and KST are on different calendar days.
    const nowMs = Date.now();
    const ONE_DAY_MS = 86400000;
    const last7 = [];
    for (let i = 6; i >= 0; i--) {
      last7.push(kstDateKey(new Date(nowMs - i * ONE_DAY_MS)));
    }
    const gamesByDay = {};
    const rankedByDay = {};
    const signupsByDay = {};
    const tichuByDay = {};
    const skByDay = {};
    const llByDay = {};
    const mightyByDay = {};
    for (const d of last7) { gamesByDay[d] = 0; rankedByDay[d] = 0; signupsByDay[d] = 0; tichuByDay[d] = 0; skByDay[d] = 0; llByDay[d] = 0; mightyByDay[d] = 0; }
    for (const r of stats.dailyGames) {
      const d = kstDateKey(r.day);
      gamesByDay[d] = parseInt(r.cnt) || 0;
      rankedByDay[d] = parseInt(r.ranked_cnt) || 0;
      tichuByDay[d] = parseInt(r.tichu_cnt) || 0;
      skByDay[d] = parseInt(r.sk_cnt) || 0;
      llByDay[d] = parseInt(r.ll_cnt) || 0;
      mightyByDay[d] = parseInt(r.mighty_cnt) || 0;
    }
    for (const r of stats.dailySignups) {
      const d = kstDateKey(r.day);
      signupsByDay[d] = parseInt(r.cnt) || 0;
    }
    const chartLabels = last7.map(d => d.slice(5)); // MM-DD
    const chartGames = last7.map(d => gamesByDay[d]);
    const chartTichu = last7.map(d => tichuByDay[d]);
    const chartSK = last7.map(d => skByDay[d]);
    const chartLL = last7.map(d => llByDay[d]);
    const chartMighty = last7.map(d => mightyByDay[d]);
    const chartRanked = last7.map(d => rankedByDay[d]);
    const chartSignups = last7.map(d => signupsByDay[d]);
    const adRewardsByDay = {};
    for (const d of last7) { adRewardsByDay[d] = 0; }
    for (const r of (stats.dailyAdRewards || [])) {
      const d = kstDateKey(r.day);
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
    function stackedBar(tichuVals, skVals, llVals, mightyVals, max, label) {
      return `<div style="display:flex;align-items:flex-end;gap:6px;height:80px;padding:8px 0">
        ${tichuVals.map((t, i) => {
          const s = skVals[i];
          const l = llVals[i];
          const m = mightyVals[i];
          const total = t + s + l + m;
          const ht = Math.max(t / max * 60, t > 0 ? 2 : 0);
          const hs = Math.max(s / max * 60, s > 0 ? 2 : 0);
          const hl = Math.max(l / max * 60, l > 0 ? 2 : 0);
          const hm = Math.max(m / max * 60, m > 0 ? 2 : 0);
          const hasAbove = s > 0 || l > 0 || m > 0;
          return `<div style="display:flex;flex-direction:column;align-items:center;flex:1;gap:2px">
            <span style="font-size:10px;color:#666">${total}</span>
            <div style="width:100%;max-width:28px;display:flex;flex-direction:column-reverse">
              ${t > 0 ? `<div style="height:${ht}px;background:#6c63ff;border-radius:${hasAbove ? '0' : '4px 4px'} 0 0;transition:height 0.3s" title="티츄 ${t}"></div>` : ''}
              ${s > 0 ? `<div style="height:${hs}px;background:#ff7043;border-radius:${l > 0 || m > 0 ? '0' : '4px 4px'} ${t > 0 ? '0 0' : '0 0'};transition:height 0.3s" title="SK ${s}"></div>` : ''}
              ${l > 0 ? `<div style="height:${hl}px;background:#E91E63;border-radius:${m > 0 ? '0' : '4px 4px'} ${(t > 0 || s > 0) ? '0 0' : '0 0'};transition:height 0.3s" title="LL ${l}"></div>` : ''}
              ${m > 0 ? `<div style="height:${hm}px;background:#1565C0;border-radius:4px 4px ${(t > 0 || s > 0 || l > 0) ? '0 0' : '0 0'};transition:height 0.3s" title="마이티 ${m}"></div>` : ''}
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

    const matchesTable = renderAdminRecentMatchesTable(stats.recentMatches);

    const topPlayersContent = renderDashboardActivityTopContent(
      stats.topPlayers,
      stats.topPlayersPeriod || activityPeriod,
      stats.topPlayersGame || activityGame
    );

    // Active rooms table
    let roomsTable = '';
    if (allRooms.length > 0) {
      roomsTable = `<div class="table-wrap"><table>
        <tr><th>방</th><th>방장</th><th>게임</th><th>인원</th><th>상태</th><th>유형</th><th>관전</th></tr>
        ${allRooms.map(r => `<tr>
          <td><a href="/tc-backstage/rooms/${encodeURIComponent(r.id)}" style="color:#6c63ff;text-decoration:none;font-weight:600">${escapeHtml(r.name)}</a></td>
          <td>${escapeHtml(r.hostName)}</td>
          <td>${gameTypeBadge(r.gameType)}</td>
          <td>${r.playerCount}/${r.maxPlayers}</td>
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
        <div class="stat-card"><div class="label">오늘 게임</div><div class="value green">${formatNumber(stats.todayGames)}</div><div class="kpi-note"><span style="color:#5f62d6">${formatNumber(stats.todayTichuGames)} 티츄</span> · <span style="color:#ff7043">${formatNumber(stats.todaySKGames)} SK</span> · <span style="color:#E91E63">${formatNumber(stats.todayLLGames)} LL</span> · <span style="color:#1565C0">${formatNumber(stats.todayMightyGames)} 마이티</span></div></div>
        <div class="stat-card"><div class="label">미처리 문의</div><div class="value orange">${formatNumber(stats.pendingInquiries)}</div><div class="kpi-note">사용자 응답 대기 포함</div></div>
        <div class="stat-card"><div class="label">미처리 신고</div><div class="value red">${formatNumber(stats.pendingReports)}</div><div class="kpi-note">최근 30일 ${formatNumber(reports30d)}건 누적</div></div>
      </div>

      <div class="grid-2col">
        <div class="card">
          <h3>일별 게임 (7일)</h3>
          ${stackedBar(chartTichu, chartSK, chartLL, chartMighty, maxGames, chartLabels)}
          <div style="margin-top:4px;font-size:11px;color:#888">
            <span style="display:inline-block;width:10px;height:10px;background:#6c63ff;border-radius:2px;margin-right:4px"></span>티츄
            <span style="display:inline-block;width:10px;height:10px;background:#ff7043;border-radius:2px;margin:0 4px 0 8px"></span>SK
            <span style="display:inline-block;width:10px;height:10px;background:#E91E63;border-radius:2px;margin:0 4px 0 8px"></span>LL
            <span style="display:inline-block;width:10px;height:10px;background:#1565C0;border-radius:2px;margin:0 4px 0 8px"></span>마이티
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
          <div id="activity-top-content">
            ${topPlayersContent}
          </div>
        </div>
        <div class="card">
          <div class="table-meta">
            <h3>최근 매치</h3>
            <a href="/tc-backstage/matches" class="btn btn-secondary">더보기</a>
          </div>
          ${matchesTable}
        </div>
      </div>
      <script>
        (() => {
          const root = document.getElementById('activity-top-content');
          if (!root) return;
          root.addEventListener('click', async (event) => {
            const link = event.target.closest('a[data-activity-filter]');
            if (!link) return;
            event.preventDefault();
            const apiHref = link.dataset.apiHref;
            if (!apiHref) {
              window.location.href = link.href;
              return;
            }
            root.style.opacity = '0.55';
            root.style.pointerEvents = 'none';
            try {
              const response = await fetch(apiHref, { headers: { 'Accept': 'application/json' } });
              if (!response.ok) throw new Error('Failed to load activity top players');
              const data = await response.json();
              root.innerHTML = data.html || '';
              if (data.url) window.history.replaceState(null, '', data.url);
            } catch (err) {
              window.location.href = link.href;
            } finally {
              root.style.opacity = '';
              root.style.pointerEvents = '';
            }
          });
        })();
      </script>
    `;
    return html(res, layout('대시보드', content, 'home'));
  }

  if (pathname === '/tc-backstage/matches' && method === 'GET') {
    const page = parseInt(url.searchParams.get('page') || '1', 10) || 1;
    const limit = 30;
    const data = await getAdminRecentMatches(page, limit);
    const content = `
      ${pageHeader('최근 매치', '대시보드보다 더 길게 최근 종료된 매치를 확인할 수 있습니다.')}
      <div class="card">
        <div class="table-meta">
          <div class="muted">총 ${formatNumber(data.total)}건</div>
          <a href="/tc-backstage/" class="btn btn-secondary">대시보드로</a>
        </div>
        ${renderAdminRecentMatchesTable(data.rows)}
        ${pagination(data.page, data.total, data.limit, '/tc-backstage/matches')}
      </div>
    `;
    return html(res, layout('최근 매치', content, 'home'));
  }

  if (pathname === '/tc-backstage/stats' && method === 'GET') {
    const todayKST = formatDateInput(new Date());
    const oneDayMs = 24 * 60 * 60 * 1000;
    const defaultTo = new Date(`${todayKST}T23:59:59+09:00`);
    const defaultFromValue = formatDateInput(new Date(defaultTo.getTime() - (6 * 24 * 60 * 60 * 1000)));
    const defaultFrom = new Date(`${defaultFromValue}T00:00:00+09:00`);

    const preset = ['today', 'yesterday', 'last7', 'last30'].includes(url.searchParams.get('preset'))
      ? url.searchParams.get('preset')
      : '';
    const fromParam = url.searchParams.get('from');
    const toParam = url.searchParams.get('to');
    const bucket = url.searchParams.get('bucket') === 'hour' ? 'hour' : 'day';
    const statTab = ['games', 'acquisition', 'economy', 'shop'].includes(url.searchParams.get('tab'))
      ? url.searchParams.get('tab')
      : 'games';
    const platform = ['ios', 'android'].includes((url.searchParams.get('platform') || '').toLowerCase())
      ? (url.searchParams.get('platform') || '').toLowerCase()
      : '';
    let from = fromParam ? new Date(`${fromParam}T00:00:00+09:00`) : defaultFrom;
    let to = toParam ? new Date(`${toParam}T23:59:59+09:00`) : defaultTo;
    if (preset === 'today') {
      from = new Date(`${todayKST}T00:00:00+09:00`);
      to = new Date(`${todayKST}T23:59:59+09:00`);
    } else if (preset === 'yesterday') {
      const yesterday = formatDateInput(new Date(new Date(`${todayKST}T12:00:00+09:00`).getTime() - oneDayMs));
      from = new Date(`${yesterday}T00:00:00+09:00`);
      to = new Date(`${yesterday}T23:59:59+09:00`);
    } else if (preset === 'last7') {
      const from7 = formatDateInput(new Date(defaultTo.getTime() - (6 * oneDayMs)));
      from = new Date(`${from7}T00:00:00+09:00`);
      to = defaultTo;
    } else if (preset === 'last30') {
      const from30 = formatDateInput(new Date(defaultTo.getTime() - (29 * oneDayMs)));
      from = new Date(`${from30}T00:00:00+09:00`);
      to = defaultTo;
    }

    const stats = await getDetailedAdminStats(from.toISOString(), to.toISOString(), bucket, { platform });
    const prevTo = new Date(from.getTime() - 1);
    const prevFrom = new Date(prevTo.getTime() - (to.getTime() - from.getTime()));
    const prevStats = await getDetailedAdminStats(prevFrom.toISOString(), prevTo.toISOString(), bucket, { platform });
    const summary = stats.summary || {};
    const prevSummary = prevStats.summary || {};
    const gameSeries = stats.gameSeries || [];
    const signupSeries = stats.signupSeries || [];
    const goldSeries = stats.goldSeries || [];
    const shopSalesSeries = stats.shopSalesSeries || [];
    const topShopItems = stats.topShopItems || [];
    const fromValue = formatDateInput(from);
    const toValue = formatDateInput(to);
    const platformLabel = platform === 'ios' ? 'iOS' : platform === 'android' ? 'AOS' : '전체';
    const bucketCount = Math.max(
      gameSeries.length,
      signupSeries.length,
      goldSeries.length,
      shopSalesSeries.length,
      1
    );
    const topGameEntries = [
      { key: 'tichu', label: '티츄', value: Number(summary.tichuGames || 0) },
      { key: 'skull', label: '스컬킹', value: Number(summary.skullGames || 0) },
      { key: 'love', label: '러브레터', value: Number(summary.llGames || 0) },
      { key: 'mighty', label: '마이티', value: Number(summary.mightyGames || 0) },
    ].sort((a, b) => b.value - a.value);
    const dominantGame = topGameEntries[0];
    const peakGameRow = [...gameSeries].sort((a, b) => Number(b.total_cnt || 0) - Number(a.total_cnt || 0))[0];
    const peakSignupRow = [...signupSeries].sort((a, b) => Number(b.total_cnt || 0) - Number(a.total_cnt || 0))[0];
    const peakEarnRow = [...goldSeries].sort((a, b) => Number(b.earned || 0) - Number(a.earned || 0))[0];
    const peakSpendRow = [...goldSeries].sort((a, b) => Number(b.spent || 0) - Number(a.spent || 0))[0];
    const peakShopRow = [...shopSalesSeries].sort((a, b) => Number(b.purchase_count || 0) - Number(a.purchase_count || 0))[0];
    const positiveNetBuckets = goldSeries.filter((row) => Number(row.net || 0) > 0).length;
    const iosShare = Number(summary.totalSignups || 0) > 0 ? (Number(summary.iosSignups || 0) * 100 / Number(summary.totalSignups || 0)) : 0;
    const aosShare = Number(summary.totalSignups || 0) > 0 ? (Number(summary.androidSignups || 0) * 100 / Number(summary.totalSignups || 0)) : 0;
    const avgGamesPerBucket = Number(summary.totalGames || 0) / bucketCount;
    const avgSignupsPerBucket = Number(summary.totalSignups || 0) / Math.max(signupSeries.length, 1);
    const avgNetPerBucket = Number(summary.goldNet || 0) / Math.max(goldSeries.length, 1);
    const avgPurchaseValue = Number(summary.shopPurchases || 0) > 0 ? (Number(summary.shopGoldSpent || 0) / Number(summary.shopPurchases || 0)) : 0;
    const purchasePerBuyer = Number(summary.shopBuyers || 0) > 0 ? (Number(summary.shopPurchases || 0) / Number(summary.shopBuyers || 0)) : 0;
    const signupPerGame = Number(summary.totalGames || 0) > 0 ? (Number(summary.totalSignups || 0) / Number(summary.totalGames || 0)) : 0;
    const rankedShare = Number(summary.totalGames || 0) > 0 ? (Number(summary.rankedGames || 0) * 100 / Number(summary.totalGames || 0)) : 0;
    const mightyShare = Number(summary.totalGames || 0) > 0 ? (Number(summary.mightyGames || 0) * 100 / Number(summary.totalGames || 0)) : 0;
    const shopBuyerConversion = Number(summary.totalSignups || 0) > 0 ? (Number(summary.shopBuyers || 0) * 100 / Number(summary.totalSignups || 0)) : 0;

    const statsTabParams = new URLSearchParams();
    statsTabParams.set('from', fromValue);
    statsTabParams.set('to', toValue);
    statsTabParams.set('bucket', bucket);
    if (preset) statsTabParams.set('preset', preset);
    if (platform) statsTabParams.set('platform', platform);
    const buildStatsTabLink = (tabKey) => {
      const params = new URLSearchParams(statsTabParams);
      params.set('tab', tabKey);
      return `/tc-backstage/stats?${params.toString()}`;
    };
    const buildStatsLink = (overrides = {}) => {
      const params = new URLSearchParams(statsTabParams);
      Object.entries(overrides).forEach(([key, value]) => {
        if (value === null || value === undefined || value === '') params.delete(key);
        else params.set(key, value);
      });
      return `/tc-backstage/stats?${params.toString()}`;
    };
    const statTabs = [
      { key: 'games', label: '게임 분석', desc: '볼륨, 비중, 피크 시간대' },
      { key: 'acquisition', label: '유입 분석', desc: '가입, 플랫폼 분포, 전환' },
      { key: 'economy', label: '경제 분석', desc: '획득/소모/순변동' },
      { key: 'shop', label: '상점 분석', desc: '판매, 구매자, 베스트셀러' },
    ];
    const presetLinks = [
      { key: 'today', label: '오늘' },
      { key: 'yesterday', label: '어제' },
      { key: 'last7', label: '최근 7일' },
      { key: 'last30', label: '최근 30일' },
    ];
    const comparisonMeta = {
      games: buildDeltaMeta(summary.totalGames, prevSummary.totalGames),
      signups: buildDeltaMeta(summary.totalSignups, prevSummary.totalSignups),
      goldNet: buildDeltaMeta(summary.goldNet, prevSummary.goldNet),
      shopPurchases: buildDeltaMeta(summary.shopPurchases, prevSummary.shopPurchases),
    };
    const warningCards = [];
    if (Number(prevSummary.totalGames || 0) > 0) {
      const deltaGames = ((Number(summary.totalGames || 0) - Number(prevSummary.totalGames || 0)) / Number(prevSummary.totalGames || 1)) * 100;
      if (deltaGames <= -20) warningCards.push({ tone: 'danger', title: '게임량 급감', desc: `이전 기간 대비 ${deltaGames.toFixed(1)}% 감소했습니다. 최근 매치 흐름을 바로 확인해보세요.` });
      else if (deltaGames >= 20) warningCards.push({ tone: 'good', title: '게임량 상승', desc: `이전 기간 대비 +${deltaGames.toFixed(1)}% 증가했습니다. 어떤 게임이 올렸는지 보기 좋습니다.` });
    }
    if (Number(prevSummary.totalSignups || 0) > 0) {
      const deltaSignups = ((Number(summary.totalSignups || 0) - Number(prevSummary.totalSignups || 0)) / Number(prevSummary.totalSignups || 1)) * 100;
      if (deltaSignups <= -20) warningCards.push({ tone: 'warning', title: '신규 가입 둔화', desc: `가입 수가 ${deltaSignups.toFixed(1)}% 줄었습니다. 플랫폼별 유입 변화를 함께 확인해보세요.` });
    }
    if (Number(prevSummary.goldSpent || 0) > 0) {
      const deltaGoldSpent = ((Number(summary.goldSpent || 0) - Number(prevSummary.goldSpent || 0)) / Number(prevSummary.goldSpent || 1)) * 100;
      if (deltaGoldSpent >= 25) warningCards.push({ tone: 'warning', title: '골드 소모 급증', desc: `소모 골드가 +${deltaGoldSpent.toFixed(1)}% 증가했습니다. 상점과 경제 탭을 같이 점검해보세요.` });
    }
    if (mightyShare >= 25) {
      warningCards.push({ tone: 'good', title: '마이티 비중 확대', desc: `현재 전체 게임 중 마이티가 ${mightyShare.toFixed(1)}%를 차지합니다.` });
    }
    const stickyFavorites = {
      games: [
        { label: '전체 게임', value: formatNumber(summary.totalGames || 0), meta: comparisonMeta.games },
        { label: '랭크 비중', value: formatPercent(rankedShare, 1), meta: `${formatNumber(summary.rankedGames || 0)}판` },
        { label: '마이티 비중', value: formatPercent(mightyShare, 1), meta: buildDeltaMeta(summary.mightyGames, prevSummary.mightyGames) },
        { label: '주력 게임', value: escapeHtml(dominantGame?.label || '-'), meta: dominantGame ? `${formatNumber(dominantGame.value)}판` : '데이터 없음' },
      ],
      acquisition: [
        { label: '전체 가입', value: formatNumber(summary.totalSignups || 0), meta: comparisonMeta.signups },
        { label: 'iOS 비중', value: formatPercent(iosShare, 1), meta: `${formatNumber(summary.iosSignups || 0)}명` },
        { label: 'AOS 비중', value: formatPercent(aosShare, 1), meta: `${formatNumber(summary.androidSignups || 0)}명` },
        { label: '가입/게임', value: formatPercent(signupPerGame * 100, 1), meta: '게임 100판당' },
      ],
      economy: [
        { label: '획득 골드', value: formatNumber(summary.goldEarned || 0), meta: buildDeltaMeta(summary.goldEarned, prevSummary.goldEarned) },
        { label: '소모 골드', value: formatNumber(summary.goldSpent || 0), meta: buildDeltaMeta(summary.goldSpent, prevSummary.goldSpent) },
        { label: '순변동', value: formatNumber(summary.goldNet || 0), meta: comparisonMeta.goldNet },
        { label: '흑자 구간', value: formatNumber(positiveNetBuckets), meta: `${Math.max(goldSeries.length, 1)}개 중` },
      ],
      shop: [
        { label: '상점 구매', value: formatNumber(summary.shopPurchases || 0), meta: comparisonMeta.shopPurchases },
        { label: '상점 지출', value: formatNumber(summary.shopGoldSpent || 0), meta: buildDeltaMeta(summary.shopGoldSpent, prevSummary.shopGoldSpent) },
        { label: '객단가', value: avgPurchaseValue.toFixed(1), meta: '구매 1건당 골드' },
        { label: '가입 대비 구매자', value: formatPercent(shopBuyerConversion, 1), meta: `${formatNumber(summary.shopBuyers || 0)}명` },
      ],
    };
    const statActions = {
      games: [
        { label: '최근 매치 보기', href: '/tc-backstage/matches' },
        { label: '실시간 방 보기', href: '/tc-backstage/' },
      ],
      acquisition: [
        { label: '신규 유저 보기', href: '/tc-backstage/users?sort=joined_desc' },
        { label: '전체 유저 보기', href: '/tc-backstage/users' },
      ],
      economy: [
        { label: '골드 많은 유저', href: '/tc-backstage/users?sort=gold_desc' },
        { label: '이탈 많은 유저', href: '/tc-backstage/users?sort=leaves_desc' },
      ],
      shop: [
        { label: '상점 관리', href: '/tc-backstage/shop' },
        { label: '유저 목록 보기', href: '/tc-backstage/users' },
      ],
    };

    const summaryCards = summaryStrip([
      { label: '전체 게임', value: formatNumber(summary.totalGames || 0), meta: `${fromValue} ~ ${toValue} · ${platformLabel}` },
      { label: '티츄', value: formatNumber(summary.tichuGames || 0), valueColor: '#5f62d6', meta: summary.totalGames ? formatPercent((summary.tichuGames || 0) * 100 / summary.totalGames, 1) : '0%' },
      { label: '스컬킹', value: formatNumber(summary.skullGames || 0), valueColor: '#138072', meta: summary.totalGames ? formatPercent((summary.skullGames || 0) * 100 / summary.totalGames, 1) : '0%' },
      { label: '러브레터', value: formatNumber(summary.llGames || 0), valueColor: '#E91E63', meta: summary.totalGames ? formatPercent((summary.llGames || 0) * 100 / summary.totalGames, 1) : '0%' },
      { label: '마이티', value: formatNumber(summary.mightyGames || 0), valueColor: '#7b1fa2', meta: summary.totalGames ? formatPercent((summary.mightyGames || 0) * 100 / summary.totalGames, 1) : '0%' },
      { label: '랭크전', value: formatNumber(summary.rankedGames || 0), valueColor: '#c67b2b', meta: summary.totalGames ? formatPercent((summary.rankedGames || 0) * 100 / summary.totalGames, 1) : '0%' },
      { label: '가입', value: formatNumber(summary.totalSignups || 0), meta: `iOS ${formatNumber(summary.iosSignups || 0)} · AOS ${formatNumber(summary.androidSignups || 0)}` },
      { label: '획득 골드', value: formatNumber(summary.goldEarned || 0), valueColor: '#2e8b57' },
      { label: '소모 골드', value: formatNumber(summary.goldSpent || 0), valueColor: '#c0563f' },
      { label: '순변동', value: formatNumber(summary.goldNet || 0), valueColor: (summary.goldNet || 0) >= 0 ? '#1f2328' : '#c0563f' },
      { label: '상점 구매', value: formatNumber(summary.shopPurchases || 0), meta: `구매자 ${formatNumber(summary.shopBuyers || 0)}명` },
      { label: '상점 지출', value: formatNumber(summary.shopGoldSpent || 0), valueColor: '#b35b19', meta: `판매 아이템 ${formatNumber(summary.shopUniqueItems || 0)}종` }
    ]);

    const gameTable = gameSeries.length > 0
      ? `<div class="table-wrap"><table>
          <tr><th>${bucket === 'hour' ? '시간대' : '날짜'}</th><th>전체</th><th>티추</th><th>스컬킹</th><th>러브레터</th><th>마이티</th><th>랭크전</th></tr>
          ${gameSeries.map(row => `<tr>
            <td>${formatDate(row.bucket_time)}</td>
            <td>${row.total_cnt}</td>
            <td>${row.tichu_cnt}</td>
            <td>${row.skull_cnt}</td>
            <td>${row.ll_cnt}</td>
            <td>${row.mighty_cnt}</td>
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

    const signupTable = signupSeries.length > 0
      ? `<div class="table-wrap"><table>
          <tr><th>${bucket === 'hour' ? '시간대' : '날짜'}</th><th>전체 가입</th><th>iOS</th><th>AOS</th></tr>
          ${signupSeries.map(row => `<tr>
            <td>${formatDate(row.bucket_time)}</td>
            <td style="font-weight:700">${formatNumber(row.total_cnt)}</td>
            <td>${formatNumber(row.ios_cnt)}</td>
            <td>${formatNumber(row.android_cnt)}</td>
          </tr>`).join('')}
        </table></div>`
      : '<div class="empty">가입 데이터가 없습니다</div>';

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

    // Prepare chart data as JSON. bucket_time arrives as a timestamptz at
    // the KST bucket boundary; format its components in Asia/Seoul via Intl
    // so labels stay correct regardless of the server process timezone.
    const _kstChartFmt = new Intl.DateTimeFormat('en-GB', {
      timeZone: 'Asia/Seoul',
      year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit', hour12: false,
    });
    const formatBucketLabel = (raw) => {
      const dt = new Date(raw);
      if (Number.isNaN(dt.getTime())) return '';
      const parts = Object.fromEntries(_kstChartFmt.formatToParts(dt).map((p) => [p.type, p.value]));
      const mm = parts.month;
      const dd = parts.day;
      const hh = parts.hour === '24' ? '00' : parts.hour;
      return bucket === 'hour' ? `${mm}/${dd} ${hh}시` : `${mm}/${dd}`;
    };
    const gameChartLabels = gameSeries.map((r) => formatBucketLabel(r.bucket_time));
    const gameChartTichu = gameSeries.map(r => parseInt(r.tichu_cnt) || 0);
    const gameChartSK = gameSeries.map(r => parseInt(r.skull_cnt) || 0);
    const gameChartLL = gameSeries.map(r => parseInt(r.ll_cnt) || 0);
    const gameChartMighty = gameSeries.map(r => parseInt(r.mighty_cnt) || 0);
    const gameChartRanked = gameSeries.map(r => parseInt(r.ranked_cnt) || 0);
    const gameChartTotal = gameSeries.map(r => parseInt(r.total_cnt) || 0);
    const gameBucketTimes = gameSeries.map(r => r.bucket_time);

    const signupChartLabels = signupSeries.map((r) => formatBucketLabel(r.bucket_time));
    const signupChartIOS = signupSeries.map(r => parseInt(r.ios_cnt) || 0);
    const signupChartAOS = signupSeries.map(r => parseInt(r.android_cnt) || 0);
    const signupChartTotal = signupSeries.map(r => parseInt(r.total_cnt) || 0);
    const signupBucketTimes = signupSeries.map(r => r.bucket_time);

    const goldChartLabels = goldSeries.map((r) => formatBucketLabel(r.bucket_time));
    const goldChartEarned = goldSeries.map(r => parseInt(r.earned) || 0);
    const goldChartSpent = goldSeries.map(r => parseInt(r.spent) || 0);
    const goldChartNet = goldSeries.map(r => parseInt(r.net) || 0);
    const goldBucketTimes = goldSeries.map(r => r.bucket_time);

    const shopChartLabels = shopSalesSeries.map((r) => formatBucketLabel(r.bucket_time));
    const shopChartPurchases = shopSalesSeries.map(r => parseInt(r.purchase_count) || 0);
    const shopChartBuyers = shopSalesSeries.map(r => parseInt(r.buyer_count) || 0);
    const shopChartGoldSpent = shopSalesSeries.map(r => parseInt(r.gold_spent) || 0);
    const shopBucketTimes = shopSalesSeries.map(r => r.bucket_time);

    const gamesTabContent = `
      ${summaryStrip([
        { label: '전체 게임', value: formatNumber(summary.totalGames || 0), meta: `${fromValue} ~ ${toValue} · ${platformLabel}` },
        { label: '랭크 비중', value: formatPercent(rankedShare, 1), meta: `${formatNumber(summary.rankedGames || 0)}판` },
        { label: '주력 게임', value: escapeHtml(dominantGame?.label || '-'), meta: dominantGame ? `${formatNumber(dominantGame.value)}판` : '데이터 없음' },
        { label: '평균 게임량', value: avgGamesPerBucket.toFixed(1), meta: bucket === 'hour' ? '시간대당 평균' : '일자당 평균' },
        { label: '마이티 비중', value: formatPercent(mightyShare, 1), meta: `${formatNumber(summary.mightyGames || 0)}판` },
        { label: '피크 구간', value: peakGameRow ? formatDate(peakGameRow.bucket_time) : '-', meta: peakGameRow ? `${formatNumber(peakGameRow.total_cnt)}판` : '데이터 없음' },
      ])}
      <div class="card-actions">
        ${(statActions.games || []).map((action) => `<a href="${action.href}" class="btn btn-secondary">${escapeHtml(action.label)}</a>`).join('')}
      </div>
      <div class="subtab-copy">게임 탭은 실제 플레이 볼륨과 어떤 게임이 운영을 주도하는지에 집중합니다. 차트를 클릭하면 해당 날짜로 바로 drill-down 됩니다.</div>
      <div class="grid-2col">
        <div class="card">
          <h3>게임량 추이</h3>
          <div style="position:relative;height:300px;margin-top:14px"><canvas id="gameChart"></canvas></div>
        </div>
        <div class="card">
          <h3>게임 비율</h3>
          <div style="position:relative;height:300px;display:flex;align-items:center;justify-content:center;margin-top:14px"><canvas id="gamePieChart"></canvas></div>
        </div>
      </div>
      <div class="card">
        <h3>게임량 상세</h3>
        ${gameTable}
      </div>
    `;

    const acquisitionTabContent = `
      ${summaryStrip([
        { label: '전체 가입', value: formatNumber(summary.totalSignups || 0), meta: `${fromValue} ~ ${toValue}` },
        { label: 'iOS 비중', value: formatPercent(iosShare, 1), meta: `${formatNumber(summary.iosSignups || 0)}명` },
        { label: 'AOS 비중', value: formatPercent(aosShare, 1), meta: `${formatNumber(summary.androidSignups || 0)}명` },
        { label: '평균 가입량', value: avgSignupsPerBucket.toFixed(1), meta: bucket === 'hour' ? '시간대당 평균' : '일자당 평균' },
        { label: '게임 대비 가입', value: formatPercent(signupPerGame * 100, 1), meta: `게임 100판당 ${signupPerGame.toFixed(2)}명` },
        { label: '피크 구간', value: peakSignupRow ? formatDate(peakSignupRow.bucket_time) : '-', meta: peakSignupRow ? `${formatNumber(peakSignupRow.total_cnt)}명` : '데이터 없음' },
      ])}
      <div class="card-actions">
        ${(statActions.acquisition || []).map((action) => `<a href="${action.href}" class="btn btn-secondary">${escapeHtml(action.label)}</a>`).join('')}
      </div>
      <div class="subtab-copy">유입 탭은 가입 추이와 플랫폼 분포, 그리고 게임량 대비 신규 유저 유입 강도를 같이 봅니다. 차트를 클릭하면 해당 날짜로 좁혀볼 수 있습니다.</div>
      <div class="grid-2col">
        <div class="card">
          <h3>가입 추이</h3>
          <div style="position:relative;height:300px;margin-top:14px"><canvas id="signupChart"></canvas></div>
        </div>
        <div class="card">
          <h3>가입 상세</h3>
          ${signupTable}
        </div>
      </div>
    `;

    const economyTabContent = `
      ${summaryStrip([
        { label: '획득 골드', value: formatNumber(summary.goldEarned || 0), valueColor: '#2e8b57' },
        { label: '소모 골드', value: formatNumber(summary.goldSpent || 0), valueColor: '#c0563f' },
        { label: '순변동', value: formatNumber(summary.goldNet || 0), valueColor: (summary.goldNet || 0) >= 0 ? '#1f2328' : '#c0563f' },
        { label: '평균 순변동', value: avgNetPerBucket.toFixed(1), meta: bucket === 'hour' ? '시간대당 평균' : '일자당 평균' },
        { label: '흑자 구간', value: formatNumber(positiveNetBuckets), meta: `${Math.max(goldSeries.length, 1)}개 구간 중` },
        { label: '최대 획득 시점', value: peakEarnRow ? formatDate(peakEarnRow.bucket_time) : '-', meta: peakEarnRow ? `${formatNumber(peakEarnRow.earned)} 골드` : '데이터 없음' },
      ])}
      <div class="card-actions">
        ${(statActions.economy || []).map((action) => `<a href="${action.href}" class="btn btn-secondary">${escapeHtml(action.label)}</a>`).join('')}
      </div>
      <div class="subtab-copy">경제 탭은 게임 보상, 광고, 상점 소비를 합친 전체 골드 흐름을 읽기 쉽게 보여줍니다. 차트 클릭 시 해당 날짜 기준으로 바로 좁혀집니다.</div>
      <div class="grid-2col">
        <div class="card">
          <h3>골드 획득 / 소모</h3>
          <div style="position:relative;height:300px;margin-top:14px"><canvas id="goldChart"></canvas></div>
        </div>
        <div class="card">
          <h3>보조 지표</h3>
          <div class="soft-panel">
            ${metricLine('최대 획득 구간', peakEarnRow ? `${escapeHtml(formatDate(peakEarnRow.bucket_time))} · ${formatNumber(peakEarnRow.earned)}` : '-')}
            ${metricLine('최대 소모 구간', peakSpendRow ? `${escapeHtml(formatDate(peakSpendRow.bucket_time))} · ${formatNumber(peakSpendRow.spent)}` : '-')}
            ${metricLine('구간당 평균 획득', (Number(summary.goldEarned || 0) / Math.max(goldSeries.length, 1)).toFixed(1))}
            ${metricLine('구간당 평균 소모', (Number(summary.goldSpent || 0) / Math.max(goldSeries.length, 1)).toFixed(1))}
          </div>
          <div style="height:14px"></div>
          ${goldTable}
        </div>
      </div>
    `;

    const shopTabContent = `
      ${summaryStrip([
        { label: '상점 구매', value: formatNumber(summary.shopPurchases || 0), meta: `구매자 ${formatNumber(summary.shopBuyers || 0)}명` },
        { label: '상점 지출', value: formatNumber(summary.shopGoldSpent || 0), valueColor: '#b35b19', meta: `판매 아이템 ${formatNumber(summary.shopUniqueItems || 0)}종` },
        { label: '객단가', value: avgPurchaseValue.toFixed(1), meta: '구매 1건당 골드' },
        { label: '구매자당 주문', value: purchasePerBuyer.toFixed(1), meta: '평균 구매 횟수' },
        { label: '최대 판매 구간', value: peakShopRow ? formatDate(peakShopRow.bucket_time) : '-', meta: peakShopRow ? `${formatNumber(peakShopRow.purchase_count)}건` : '데이터 없음' },
        { label: '대표 상품', value: topShopItems[0] ? escapeHtml(topShopItems[0].item_name) : '-', meta: topShopItems[0] ? `${formatNumber(topShopItems[0].purchase_count)}건` : '데이터 없음' },
      ])}
      <div class="card-actions">
        ${(statActions.shop || []).map((action) => `<a href="${action.href}" class="btn btn-secondary">${escapeHtml(action.label)}</a>`).join('')}
      </div>
      <div class="subtab-copy">상점 탭은 판매량뿐 아니라 구매자 밀도와 어떤 상품이 실제 지출을 끌고 가는지에 초점을 둡니다. 차트를 클릭하면 해당 날짜 기준으로 바로 drill-down 됩니다.</div>
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
      <div class="card">
        <h3>상점 판매 상세</h3>
        ${shopSalesTable}
      </div>
    `;

    const tabContentMap = {
      games: gamesTabContent,
      acquisition: acquisitionTabContent,
      economy: economyTabContent,
      shop: shopTabContent,
    };

    const content = `
      <script src="https://cdn.jsdelivr.net/npm/chart.js@4/dist/chart.umd.min.js"></script>
      ${pageHeader('통계', '기간별 게임량, 가입, 골드 흐름, 그리고 상점 판매 추이까지 함께 볼 수 있습니다. 플랫폼 필터로 iOS/AOS 기준도 바로 확인할 수 있습니다.')}
      <div class="filter-card">
        <div class="filter-title">조회 조건</div>
        <form method="GET" action="/tc-backstage/stats" class="search-bar" style="align-items:end;flex-wrap:wrap">
          <input type="hidden" name="tab" value="${escapeHtml(statTab)}">
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
          <div style="min-width:140px">
            <div style="font-size:12px;color:#888;margin-bottom:6px">플랫폼</div>
            <select name="platform" style="padding:10px;border:1px solid #ddd;border-radius:8px;font-size:14px">
              <option value="">전체</option>
              <option value="ios"${platform === 'ios' ? ' selected' : ''}>iOS</option>
              <option value="android"${platform === 'android' ? ' selected' : ''}>AOS</option>
            </select>
          </div>
          <button type="submit" class="btn btn-primary">조회</button>
          <a href="/tc-backstage/stats" class="btn btn-secondary">초기화</a>
        </form>
      </div>
      ${summaryCards}
      <div class="preset-bar">
        ${presetLinks.map((item) => `<a href="${buildStatsLink({ preset: item.key })}" class="preset-link ${preset === item.key ? 'active' : ''}">${item.label}</a>`).join('')}
      </div>
      <div class="subtab-bar">
        ${statTabs.map((tab) => `
          <a href="${buildStatsTabLink(tab.key)}" class="subtab-link ${statTab === tab.key ? 'active' : ''}">
            <span>${escapeHtml(tab.label)}</span>
            <span style="font-size:11px;opacity:0.8">${escapeHtml(tab.desc)}</span>
          </a>
        `).join('')}
      </div>
      <div class="sticky-kpi-rail">
        <div class="sticky-kpi-title">즐겨찾기 KPI</div>
        <div class="sticky-kpi-grid">
          ${(stickyFavorites[statTab] || []).map((item) => `
            <div class="sticky-kpi-item">
              <div class="k">${escapeHtml(item.label)}</div>
              <div class="v">${item.value}</div>
              <div class="m">${item.meta || ''}</div>
            </div>
          `).join('')}
        </div>
      </div>
      ${warningCards.length > 0 ? `
        <div class="status-strip">
          ${warningCards.map((card) => `
            <div class="status-card ${card.tone}">
              <div class="title">${escapeHtml(card.title)}</div>
              <div class="desc">${escapeHtml(card.desc)}</div>
            </div>
          `).join('')}
        </div>
      ` : ''}
      ${tabContentMap[statTab]}

      <script>
      (function() {
        const tooltipStyle = {
          backgroundColor: 'rgba(26,26,46,0.9)',
          titleFont: { size: 13 },
          bodyFont: { size: 12 },
          padding: 10,
          cornerRadius: 8,
        };
        const drilldownBase = ${JSON.stringify(buildStatsLink({ preset: null }))};
        function attachDrilldown(chart, bucketValues, targetTab) {
          if (!chart || !Array.isArray(bucketValues) || bucketValues.length === 0) return;
          chart.options.onClick = (_, elements) => {
            if (!elements || elements.length === 0) return;
            const index = elements[0].index;
            const raw = bucketValues[index];
            if (!raw) return;
            const d = new Date(raw);
            const year = d.getFullYear();
            const month = String(d.getMonth() + 1).padStart(2, '0');
            const day = String(d.getDate()).padStart(2, '0');
            const dateValue = year + '-' + month + '-' + day;
            const nextUrl = new URL(drilldownBase, window.location.origin);
            nextUrl.searchParams.set('tab', targetTab);
            nextUrl.searchParams.set('from', dateValue);
            nextUrl.searchParams.set('to', dateValue);
            nextUrl.searchParams.set('bucket', 'hour');
            window.location.href = nextUrl.pathname + nextUrl.search;
          };
          chart.update();
        }

        // Game chart - stacked bar
        const gameChartEl = document.getElementById('gameChart');
        if (gameChartEl) {
          const gameChart = new Chart(gameChartEl, {
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
                label: '러브레터',
                data: ${JSON.stringify(gameChartLL)},
                backgroundColor: 'rgba(233,30,99,0.8)',
                borderRadius: 4,
                borderSkipped: false,
              },
              {
                label: '마이티',
                data: ${JSON.stringify(gameChartMighty)},
                backgroundColor: 'rgba(123,31,162,0.8)',
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
          attachDrilldown(gameChart, ${JSON.stringify(gameBucketTimes)}, 'games');
        }

        // Game pie chart
        const totalTichu = ${JSON.stringify(gameChartTichu)}.reduce((a,b) => a+b, 0);
        const totalSK = ${JSON.stringify(gameChartSK)}.reduce((a,b) => a+b, 0);
        const totalLL = ${JSON.stringify(gameChartLL)}.reduce((a,b) => a+b, 0);
        const totalMighty = ${JSON.stringify(gameChartMighty)}.reduce((a,b) => a+b, 0);
        const gamePieChartEl = document.getElementById('gamePieChart');
        if (gamePieChartEl) new Chart(gamePieChartEl, {
          type: 'doughnut',
          data: {
            labels: ['티츄 (' + totalTichu + ')', '스컬킹 (' + totalSK + ')', '러브레터 (' + totalLL + ')', '마이티 (' + totalMighty + ')'],
            datasets: [{
              data: [totalTichu, totalSK, totalLL, totalMighty],
              backgroundColor: ['rgba(108,99,255,0.85)', 'rgba(255,112,67,0.85)', 'rgba(233,30,99,0.85)', 'rgba(123,31,162,0.85)'],
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
        const goldChartEl = document.getElementById('goldChart');
        if (goldChartEl) {
          const goldChart = new Chart(goldChartEl, {
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
          attachDrilldown(goldChart, ${JSON.stringify(goldBucketTimes)}, 'economy');
        }

        const signupChartEl = document.getElementById('signupChart');
        if (signupChartEl) {
          const signupChart = new Chart(signupChartEl, {
          type: 'bar',
          data: {
            labels: ${JSON.stringify(signupChartLabels)},
            datasets: [
              {
                label: 'iOS',
                data: ${JSON.stringify(signupChartIOS)},
                backgroundColor: 'rgba(66,165,245,0.78)',
                borderRadius: 4,
                borderSkipped: false,
              },
              {
                label: 'AOS',
                data: ${JSON.stringify(signupChartAOS)},
                backgroundColor: 'rgba(102,187,106,0.78)',
                borderRadius: 4,
                borderSkipped: false,
              },
              {
                label: '전체 가입',
                data: ${JSON.stringify(signupChartTotal)},
                type: 'line',
                borderColor: '#6d4c41',
                backgroundColor: 'rgba(109,76,65,0.1)',
                borderWidth: 2,
                pointRadius: 4,
                pointBackgroundColor: '#6d4c41',
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
          attachDrilldown(signupChart, ${JSON.stringify(signupBucketTimes)}, 'acquisition');
        }

        const shopSalesChartEl = document.getElementById('shopSalesChart');
        if (shopSalesChartEl) {
          const shopSalesChart = new Chart(shopSalesChartEl, {
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
          attachDrilldown(shopSalesChart, ${JSON.stringify(shopBucketTimes)}, 'shop');
        }
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
    const platform = ['ios', 'android'].includes((url.searchParams.get('platform') || '').toLowerCase())
      ? (url.searchParams.get('platform') || '').toLowerCase()
      : '';
    const ipQuery = url.searchParams.get('ip') || '';
    const data = await getUsers(search, page, 20, { sort, minRating, minGames, minLeaves, platform, ipQuery });
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
    if (platform) qs.set('platform', platform);
    if (ipQuery) qs.set('ip', ipQuery);
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
      <div class="filter-card">
        <div class="filter-title">유저 필터</div>
        <form method="GET" action="/tc-backstage/users" style="display:flex;flex-wrap:wrap;gap:8px;width:100%;align-items:center">
          <input type="text" name="q" placeholder="닉네임 또는 계정명 검색..." value="${escapeHtml(search)}" style="flex:1;min-width:180px">
          <input type="text" name="ip" placeholder="IP 검색" value="${escapeHtml(ipQuery)}" style="width:130px;padding:8px 10px;border-radius:8px;border:1px solid #ddd;font-size:13px">
          <select name="platform" style="padding:8px 10px;border-radius:8px;border:1px solid #ddd;font-size:13px">
            <option value="">전체 OS</option>
            <option value="ios"${platform === 'ios' ? ' selected' : ''}>iOS</option>
            <option value="android"${platform === 'android' ? ' selected' : ''}>AOS</option>
          </select>
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
        <tr><th>닉네임</th><th>권한</th><th>기기</th><th>IP</th><th>앱 버전</th><th>Lv</th><th>골드</th><th>레이팅</th><th>게임</th><th>승/패</th><th>이탈</th><th>최근 접속</th><th></th></tr>
        ${data.rows.map(u => {
          const winRate = u.total_games > 0 ? Math.round(u.wins / u.total_games * 100) : 0;
          const leaveStyle = (u.leave_count || 0) >= 3 ? 'color:#e53935;font-weight:600' : '';
          return `<tr>
          <td><a href="/tc-backstage/users/${encodeURIComponent(u.nickname)}" style="color:#6c63ff;text-decoration:none;font-weight:600">${escapeHtml(u.nickname)}</a></td>
          <td>
            ${u.is_deleted ? '<span class="badge" style="background:#ffebee;color:#c62828">탈퇴</span>' : `<span class="badge" style="background:${u.is_admin ? '#ede7f6' : '#f5f5f5'};color:${u.is_admin ? '#5e35b1' : '#888'}">${u.is_admin ? '관리자' : '일반'}</span>`}
          </td>
          <td>${deviceBadge(u.device_platform)}</td>
          <td style="font-size:12px;color:#666">${escapeHtml(u.last_ip || '-')}</td>
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
          <div class="label">티츄 전적</div><div class="value">${user.total_games}판 · ${user.wins}승 / ${user.losses}패 (${winRate}%)</div>
          <div class="label">SK 전적</div><div class="value">${user.sk_total_games || 0}판 · ${user.sk_wins || 0}승 / ${user.sk_losses || 0}패 (${user.sk_total_games > 0 ? Math.round((user.sk_wins || 0) / user.sk_total_games * 100) : 0}%)</div>
	          <div class="label">LL 전적</div><div class="value">${user.ll_total_games || 0}판 · ${user.ll_wins || 0}승 / ${user.ll_losses || 0}패 (${user.ll_total_games > 0 ? Math.round((user.ll_wins || 0) / user.ll_total_games * 100) : 0}%)</div>
	          <div class="label">마이티 레이팅</div><div class="value" style="font-weight:600">${user.mighty_rating || 1000}</div>
	          <div class="label">마이티 전적</div><div class="value">${user.mighty_total_games || 0}판 · ${user.mighty_wins || 0}승 / ${user.mighty_losses || 0}패 (${user.mighty_total_games > 0 ? Math.round((user.mighty_wins || 0) / user.mighty_total_games * 100) : 0}%)</div>
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
            if (m.gameType === 'skull_king' || m.gameType === 'love_letter' || m.gameType === 'mighty') {
              const playersText = m.players ? m.players.map(p => escapeHtml(p.nickname) + '(' + p.score + '점 #' + p.rank + ')').join(', ') : '-';
              return `<tr>
              <td>${m.id}</td>
              <td>${gameTypeBadge(m.gameType)}</td>
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
              <td>${gameTypeBadge(m.gameType)}</td>
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
          <td>${escapeHtml(item.name_ko)}</td>
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
      <h1 class="page-title">수정: ${escapeHtml(item.name_ko)}</h1>
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
    return html(res, layout(`수정: ${escapeHtml(item.name_ko)}`, content, 'shop'));
  }

  // Shop edit process
  if (shopEditMatch && method === 'POST') {
    const body = await parseBody(req);
    const data = parseShopFormBody(body);
    const result = await updateShopItem(parseInt(shopEditMatch[1]), data);
    if (!result.success) {
      const item = await getShopItemById(parseInt(shopEditMatch[1]));
      const content = `
        <h1 class="page-title">수정: ${escapeHtml(item ? item.name_ko : '')}</h1>
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

    const history = await getMaintenanceHistory(50);
    const historyRows = history.map((h, i) => {
      const badge = h.action === 'set'
        ? '<span class="badge" style="background:#e3f2fd;color:#1565c0">설정</span>'
        : '<span class="badge" style="background:#ffebee;color:#c62828">초기화</span>';
      const mStart = h.maintenance_start ? new Date(h.maintenance_start).toLocaleString('ko-KR', { timeZone: 'Asia/Seoul' }) : '-';
      const mEnd = h.maintenance_end ? new Date(h.maintenance_end).toLocaleString('ko-KR', { timeZone: 'Asia/Seoul' }) : '-';
      const msg = h.message_ko ? escapeHtml(h.message_ko.length > 30 ? h.message_ko.slice(0, 30) + '...' : h.message_ko) : '-';
      const admin = escapeHtml(h.admin_user || '-');
      const created = new Date(h.created_at).toLocaleString('ko-KR', { timeZone: 'Asia/Seoul' });
      return `<tr>
        <td>${history.length - i}</td>
        <td>${badge}</td>
        <td>${mStart} ~ ${mEnd}</td>
        <td>${msg}</td>
        <td>${admin}</td>
        <td>${created}</td>
      </tr>`;
    }).join('');

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
            <label>안내 메시지 (한국어)</label>
            <textarea name="message_ko" rows="3" placeholder="점검 안내 메시지 (한국어)">${escapeHtml(config.message_ko || '')}</textarea>
            <label>안내 메시지 (English)</label>
            <textarea name="message_en" rows="3" placeholder="Maintenance message (English)">${escapeHtml(config.message_en || '')}</textarea>
            <label>안내 메시지 (Deutsch)</label>
            <textarea name="message_de" rows="3" placeholder="Wartungsmeldung (Deutsch)">${escapeHtml(config.message_de || '')}</textarea>
          </div>
          <div style="margin-top:16px;display:flex;gap:8px">
            <button type="submit" class="btn btn-primary">저장</button>
          </div>
        </form>
        <form method="POST" action="/tc-backstage/maintenance/clear" style="margin-top:12px">
          <button type="submit" class="btn btn-danger" onclick="return confirm('점검 설정을 초기화하시겠습니까?')">전체 초기화</button>
        </form>
      </div>

      <div class="card" style="margin-top:20px">
        <h3>점검 히스토리</h3>
        <div class="table-responsive" style="margin-top:12px">
          <table>
            <thead><tr>
              <th>#</th><th>작업</th><th>점검 시간</th><th>메시지</th><th>관리자</th><th>일시</th>
            </tr></thead>
            <tbody>${historyRows || '<tr><td colspan="6" style="text-align:center;color:#999">기록 없음</td></tr>'}</tbody>
          </table>
        </div>
      </div>
    `;
    return html(res, layout('점검', content, 'maintenance'));
  }

  if (pathname === '/tc-backstage/maintenance' && method === 'POST') {
    if (setMaintenanceConfig) {
      const body = await parseBody(req);
      const config = {
        noticeStart: body.noticeStart || null,
        noticeEnd: body.noticeEnd || null,
        maintenanceStart: body.maintenanceStart || null,
        maintenanceEnd: body.maintenanceEnd || null,
        message_ko: body.message_ko || '',
        message_en: body.message_en || '',
        message_de: body.message_de || '',
      };
      setMaintenanceConfig(config);
      await insertMaintenanceHistory({ action: 'set', config, adminUser: sessionInfo.session.username });
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
        message_ko: '',
        message_en: '',
        message_de: '',
      });
      await insertMaintenanceHistory({ action: 'clear', config: {}, adminUser: sessionInfo.session.username });
    }
    return redirect(res, '/tc-backstage/maintenance');
  }

  // ===== Settings =====
  if (pathname === '/tc-backstage/settings' && method === 'GET') {
    const [eulaKo, eulaEn, eulaDe] = await Promise.all([
      getConfig('eula_content_ko'), getConfig('eula_content_en'), getConfig('eula_content_de'),
    ]);
    const [privacyKo, privacyEn, privacyDe] = await Promise.all([
      getConfig('privacy_policy_ko'), getConfig('privacy_policy_en'), getConfig('privacy_policy_de'),
    ]);
    const minVersion = await getConfig('min_version') || '';
    const latestVersion = await getConfig('latest_version') || '';
    const saved = url.searchParams.get('saved');

    const langTabs = (baseId, values) => {
      const langs = [
        { code: 'ko', label: '한국어' },
        { code: 'en', label: 'English' },
        { code: 'de', label: 'Deutsch' },
      ];
      const tabButtons = langs.map((l, i) => `
        <button type="button" class="lang-tab ${i === 0 ? 'active' : ''}" data-target="${baseId}-${l.code}"
          style="padding:6px 14px;border:1px solid #ddd;background:${i === 0 ? '#6c63ff' : '#fff'};color:${i === 0 ? '#fff' : '#333'};border-radius:6px;cursor:pointer;font-size:13px">
          ${l.label}
        </button>`).join('');
      const tabPanels = langs.map((l, i) => `
        <div id="${baseId}-${l.code}" class="lang-panel" style="display:${i === 0 ? 'block' : 'none'}">
          <textarea name="${baseId}_${l.code}" rows="20" style="font-size:13px;line-height:1.6">${escapeHtml(values[l.code] || '')}</textarea>
        </div>`).join('');
      return `
        <div style="display:flex;gap:6px;margin-bottom:10px">${tabButtons}</div>
        ${tabPanels}
      `;
    };

    const content = `
      <h1 class="page-title">설정</h1>
      ${saved ? '<div style="color:#4caf50;margin-bottom:12px;font-weight:600">저장되었습니다.</div>' : ''}
      <div class="card">
        <h3>강제 업데이트 최소 버전</h3>
        <p style="font-size:13px;color:#888;margin-bottom:8px">이 버전 미만의 앱은 강제 업데이트 팝업이 표시됩니다. (예: 2.0.1)</p>
        <form method="POST" action="/tc-backstage/settings/min-version" style="display:flex;align-items:center;gap:8px">
          <input type="text" name="min_version" value="${escapeHtml(minVersion)}" placeholder="예: 2.0.1" style="width:200px;padding:8px 12px;border:1px solid #ddd;border-radius:8px;font-size:14px">
          <button type="submit" class="btn btn-primary">저장</button>
        </form>
      </div>
      <div class="card">
        <h3>최신 버전 (소프트 업데이트)</h3>
        <p style="font-size:13px;color:#888;margin-bottom:8px">이 버전 미만의 앱은 설정 화면에 "최신 버전이 아닙니다" 안내와 스토어 이동 버튼이 표시됩니다. 강제 업데이트는 아닙니다. (예: 2.1.0)</p>
        <form method="POST" action="/tc-backstage/settings/latest-version" style="display:flex;align-items:center;gap:8px">
          <input type="text" name="latest_version" value="${escapeHtml(latestVersion)}" placeholder="예: 2.1.0" style="width:200px;padding:8px 12px;border:1px solid #ddd;border-radius:8px;font-size:14px">
          <button type="submit" class="btn btn-primary">저장</button>
        </form>
      </div>
      <div class="card">
        <h3>EULA / 이용약관</h3>
        <p style="font-size:13px;color:#888;margin-bottom:8px">ko/de 사용자는 해당 언어를 받습니다. 그 외 모든 locale은 English 버전을 받습니다.</p>
        <form method="POST" action="/tc-backstage/settings/eula" data-tabs-form>
          ${langTabs('eula_content', { ko: eulaKo, en: eulaEn, de: eulaDe })}
          <div style="margin-top:12px"><button type="submit" class="btn btn-primary">저장</button></div>
        </form>
      </div>
      <div class="card">
        <h3>개인정보처리방침</h3>
        <p style="font-size:13px;color:#888;margin-bottom:8px">ko/de 사용자는 해당 언어를 받습니다. 그 외 모든 locale은 English 버전을 받습니다.</p>
        <form method="POST" action="/tc-backstage/settings/privacy" data-tabs-form>
          ${langTabs('privacy_policy', { ko: privacyKo, en: privacyEn, de: privacyDe })}
          <div style="margin-top:12px"><button type="submit" class="btn btn-primary">저장</button></div>
        </form>
      </div>
      <script>
        document.querySelectorAll('[data-tabs-form]').forEach(form => {
          form.querySelectorAll('.lang-tab').forEach(btn => {
            btn.addEventListener('click', () => {
              const targetId = btn.dataset.target;
              form.querySelectorAll('.lang-tab').forEach(b => {
                b.classList.remove('active');
                b.style.background = '#fff';
                b.style.color = '#333';
              });
              btn.classList.add('active');
              btn.style.background = '#6c63ff';
              btn.style.color = '#fff';
              form.querySelectorAll('.lang-panel').forEach(p => {
                p.style.display = p.id === targetId ? 'block' : 'none';
              });
            });
          });
        });
      </script>
    `;
    return html(res, layout('설정', content, 'settings'));
  }

  if (pathname === '/tc-backstage/settings/min-version' && method === 'POST') {
    const body = await parseBody(req);
    await updateConfig('min_version', (body.min_version || '').trim());
    return redirect(res, '/tc-backstage/settings?saved=1');
  }

  if (pathname === '/tc-backstage/settings/latest-version' && method === 'POST') {
    const body = await parseBody(req);
    await updateConfig('latest_version', (body.latest_version || '').trim());
    return redirect(res, '/tc-backstage/settings?saved=1');
  }

  if (pathname === '/tc-backstage/settings/eula' && method === 'POST') {
    const body = await parseBody(req);
    await Promise.all([
      updateConfig('eula_content_ko', body.eula_content_ko || ''),
      updateConfig('eula_content_en', body.eula_content_en || ''),
      updateConfig('eula_content_de', body.eula_content_de || ''),
    ]);
    return redirect(res, '/tc-backstage/settings?saved=1');
  }

  if (pathname === '/tc-backstage/settings/privacy' && method === 'POST') {
    const body = await parseBody(req);
    await Promise.all([
      updateConfig('privacy_policy_ko', body.privacy_policy_ko || ''),
      updateConfig('privacy_policy_en', body.privacy_policy_en || ''),
      updateConfig('privacy_policy_de', body.privacy_policy_de || ''),
    ]);
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
    const isTichuGame = room.gameType === 'tichu';
    const isMightyGame = room.gameType === 'mighty';
    const playersHtml = roomState.players.map((p, i) => {
      if (!p) {
        const colspan = isTichuGame ? 6 : isMightyGame ? 5 : 4;
        return `<tr><td>슬롯 ${i}</td><td colspan="${colspan}" style="color:#999">비어있음</td></tr>`;
      }
      const statusBadges = [];
      if (p.isHost) statusBadges.push('<span class="badge badge-resolved">방장</span>');
      if (p.isBot) statusBadges.push('<span class="badge" style="background:#f3e5f5;color:#6a1b9a">봇</span>');
      if (!p.connected) statusBadges.push('<span class="badge badge-pending">연결 끊김</span>');
      if (p.isReady) statusBadges.push('<span class="badge" style="background:#e8f5e9;color:#2e7d32">준비</span>');

      if (isTichuGame) {
        const teamLabel = (i === 0 || i === 2) ? '<span class="badge" style="background:#e3f2fd;color:#1565c0">Team A</span>' : '<span class="badge" style="background:#fce4ec;color:#c62828">Team B</span>';
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
      }
      if (isMightyGame) {
        let cardCount = '-';
        let bidText = '-';
        let trickPointText = '-';
        if (game) {
          const hand = game.hands[p.id];
          const bid = game.bids ? game.bids[p.id] : null;
          const trickCount = Array.isArray(game.tricks) ? game.tricks.filter(t => t.winner === p.id).length : 0;
          const pointCount = Array.isArray(game.pointCards?.[p.id]) ? game.pointCards[p.id].length : 0;
          cardCount = hand ? hand.length : 0;
          if (bid === 'pass') bidText = '<span class="badge" style="background:#f5f5f5;color:#888">패스</span>';
          else if (bid && typeof bid === 'object') bidText = `<span class="badge" style="background:#e3f2fd;color:#1565c0">${bid.points} ${mightySuitLabel(bid.suit)}</span>`;
          if (game.declarer === p.id) statusBadges.push('<span class="badge" style="background:#fff3e0;color:#e65100">주공</span>');
          if (game.friendRevealed && game.partner === p.id) statusBadges.push('<span class="badge" style="background:#e8f5e9;color:#2e7d32">프렌드</span>');
          trickPointText = `${trickCount}T / ${pointCount}P`;
        }
        return `<tr>
          <td>슬롯 ${i}</td>
          <td style="font-weight:600">${escapeHtml(p.name)}</td>
          <td>${statusBadges.join(' ') || '-'}</td>
          <td style="font-weight:700;font-size:16px">${cardCount}</td>
          <td>${bidText}</td>
          <td>${trickPointText}</td>
        </tr>`;
      }
      // SK / Love Letter
      return `<tr>
        <td>슬롯 ${i}</td>
        <td style="font-weight:600">${escapeHtml(p.name)}</td>
        <td>${statusBadges.join(' ')}</td>
        <td>-</td>
        <td>-</td>
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
        'bidding': 'badge-pending',
        'kitty_exchange': 'badge-suggestion',
        'dealing_first_8': 'badge-pending',
        'large_tichu_phase': 'badge-pending',
        'dealing_remaining_6': 'badge-pending',
        'card_exchange': 'badge-suggestion',
        'playing': 'badge-resolved',
        'round_end': 'badge-reviewed',
        'game_end': 'badge-bug',
      };
      const phaseBadge = `<span class="badge ${phaseColors[phase] || 'badge-other'}">${phase}</span>`;

      if (isMightyGame) {
        let trickHtml = '';
        if (game.currentTrick.length > 0) {
          trickHtml = `<div class="table-wrap"><table>
            <tr><th>플레이어</th><th>카드</th></tr>
            ${game.currentTrick.map(t => `<tr>
              <td style="font-weight:600">${escapeHtml(game.playerNames[t.pid] || t.pid)}</td>
              <td>${renderAdminCardChip(t.cardId)}</td>
            </tr>`).join('')}
          </table></div>`;
        } else {
          trickHtml = '<div style="color:#999;font-size:13px">테이블에 카드 없음</div>';
        }

        let handsHtml = '';
        if (game.hands) {
          const handRows = game.playerIds.map(pid => {
            const hand = game.hands[pid] || [];
            const cardDisplay = hand.length > 0
              ? hand.map(renderAdminCardChip).join(' ')
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

        const scoreRows = game.playerIds.map(pid => {
          const score = game.scores?.[pid] ?? 0;
          const trickCount = Array.isArray(game.tricks) ? game.tricks.filter(t => t.winner === pid).length : 0;
          const pointCount = Array.isArray(game.pointCards?.[pid]) ? game.pointCards[pid].length : 0;
          return `<tr>
            <td style="font-weight:600">${escapeHtml(game.playerNames[pid])}</td>
            <td style="font-weight:700">${score}</td>
            <td>${trickCount}</td>
            <td>${pointCount}</td>
          </tr>`;
        }).join('');
        const scoreHtml = `<div class="table-wrap"><table>
          <tr><th>플레이어</th><th>누적 점수</th><th>트릭</th><th>포인트 카드</th></tr>
          ${scoreRows}
        </table></div>`;

        let roundResultHtml = '<div style="color:#999;font-size:13px">아직 완료된 라운드 없음</div>';
        if (game.roundResult) {
          roundResultHtml = `<div class="table-wrap"><table>
            <tr><th>플레이어</th><th>라운드 점수</th></tr>
            ${game.playerIds.map(pid => `<tr>
              <td style="font-weight:600">${escapeHtml(game.playerNames[pid])}</td>
              <td>${game.roundResult.scores?.[pid] ?? 0}</td>
            </tr>`).join('')}
          </table></div>
          <div style="margin-top:12px;font-size:13px;color:#555">
            <strong>결과:</strong>
            ${game.roundResult.success ? '주공 성공' : '주공 실패'}
            <span style="margin-left:10px"><strong>주공 팀 포인트:</strong> ${game.roundResult.declarerPoints ?? 0}</span>
          </div>`;
        }

        let specialHtml = '';
        specialHtml += `<div style="margin-bottom:8px"><strong>트럼프:</strong> ${game.trumpSuit ? `<span class="badge" style="background:#fff3e0;color:#e65100">${mightySuitLabel(game.trumpSuit)}</span>` : '<span style="color:#999">미정</span>'}</div>`;
        specialHtml += `<div style="margin-bottom:8px"><strong>현재 비드:</strong> ${game.currentBid?.bidder ? `<span class="badge" style="background:#e3f2fd;color:#1565c0">${game.currentBid.points} ${mightySuitLabel(game.currentBid.suit)}</span> <span style="font-size:12px;color:#666">${escapeHtml(game.playerNames[game.currentBid.bidder] || game.currentBid.bidder)}</span>` : '<span style="color:#999">없음</span>'}</div>`;
        specialHtml += `<div style="margin-bottom:8px"><strong>주공:</strong> ${game.declarer ? escapeHtml(game.playerNames[game.declarer] || game.declarer) : '<span style="color:#999">미정</span>'}</div>`;
        specialHtml += `<div style="margin-bottom:8px"><strong>프렌드 카드:</strong> ${game.friendCard ? renderAdminCardChip(game.friendCard) : '<span class="badge" style="background:#f5f5f5;color:#888">솔로/미선택</span>'}</div>`;
        if (game.friendRevealed) {
          specialHtml += `<div style="margin-bottom:8px"><strong>프렌드 공개:</strong> <span class="badge" style="background:#e8f5e9;color:#2e7d32">${escapeHtml(game.playerNames[game.partner] || game.partner)}</span></div>`;
        }
        if (Array.isArray(game.discarded) && game.discarded.length > 0) {
          specialHtml += `<div style="margin-bottom:8px"><strong>버린 카드:</strong> ${game.discarded.map(renderAdminCardChip).join(' ')}</div>`;
        }

        gameHtml = `
          <div class="stats-grid" style="grid-template-columns:repeat(auto-fit, minmax(130px, 1fr));margin-bottom:20px">
            <div class="stat-card" style="border-left:4px solid #1565c0"><div class="label">단계</div><div style="margin-top:4px">${phaseBadge}</div></div>
            <div class="stat-card" style="border-left:4px solid #ff9800"><div class="label">라운드</div><div class="value orange">${round}</div></div>
            <div class="stat-card" style="border-left:4px solid #4caf50"><div class="label">현재 턴</div><div style="font-weight:600;font-size:16px;margin-top:4px">${escapeHtml(currentPlayerName)}</div></div>
            <div class="stat-card" style="border-left:4px solid #7b1fa2"><div class="label">트럼프</div><div style="font-weight:700;font-size:18px;margin-top:4px">${escapeHtml(mightySuitLabel(game.trumpSuit))}</div></div>
            <div class="stat-card" style="border-left:4px solid #455a64"><div class="label">주공</div><div style="font-weight:600;font-size:16px;margin-top:4px">${escapeHtml(game.declarer ? (game.playerNames[game.declarer] || game.declarer) : '-')}</div></div>
          </div>

          <div class="card">
            <h3>활성 상태</h3>
            ${specialHtml}
          </div>

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
              <h3>점수판</h3>
              ${scoreHtml}
            </div>
            <div class="card">
              <h3>라운드 결과</h3>
              ${roundResultHtml}
            </div>
          </div>
        `;
      } else {
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
      }
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
            <span style="color:#aaa;font-size:11px;margin-left:6px">${new Date(m.timestamp).toLocaleTimeString('ko-KR', { timeZone: 'Asia/Seoul' })}</span>
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
          <div class="label">게임</div><div class="value">${gameTypeBadge(room.gameType)}</div>
          <div class="label">유형</div><div class="value">${roomState.isRanked ? '<span class="badge" style="background:#fff3e0;color:#e65100">랭크</span>' : '일반'}${roomState.isPrivate ? ' <span class="badge" style="background:#ffebee;color:#c62828">비공개</span>' : ''}</div>
          <div class="label">턴 제한</div><div class="value">${roomState.turnTimeLimit}초</div>
          <div class="label">관전자</div><div class="value">${specHtml}</div>
        </div>
      </div>

      <div class="card">
        <h3>플레이어</h3>
        <div class="table-wrap"><table>
          ${isTichuGame
            ? '<tr><th>슬롯</th><th>이름</th><th>팀</th><th>상태</th><th>카드</th><th>티츄</th><th>완료</th></tr>'
            : isMightyGame
              ? '<tr><th>슬롯</th><th>이름</th><th>상태</th><th>카드</th><th>비드</th><th>트릭/포인트</th></tr>'
            : '<tr><th>슬롯</th><th>이름</th><th>상태</th><th>카드</th><th>완료</th></tr>'}
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

  // ===== Notices =====
  function noticeCategoryBadge(cat) {
    const map = { release: '릴리즈', update: '업데이트', preview: '업데이트 예고', general: '공지' };
    const colorMap = { release: '#1565c0', update: '#2e7d32', preview: '#e65100', general: '#546e7a' };
    const bgMap = { release: '#e3f2fd', update: '#e8f5e9', preview: '#fff3e0', general: '#eceff1' };
    return `<span class="badge" style="background:${bgMap[cat] || bgMap.general};color:${colorMap[cat] || colorMap.general}">${map[cat] || cat}</span>`;
  }

  function noticeStatusBadge(status) {
    if (status === 'published') return '<span class="badge" style="background:#e8f5e9;color:#2e7d32">게시중</span>';
    return '<span class="badge" style="background:#fff8e1;color:#f57f17">임시저장</span>';
  }

  function noticeFormHtml(notice = null) {
    const cat = notice?.category || 'general';
    const title = escapeHtml(notice?.title || '');
    const content = escapeHtml(notice?.content || '');
    const isPinned = notice?.is_pinned ? 'checked' : '';
    const status = notice?.status || 'draft';
    return `
      <div class="card">
        <div style="display:grid;gap:14px">
          <div>
            <label style="font-weight:600;display:block;margin-bottom:4px">카테고리</label>
            <select name="category" style="padding:8px 12px;border:1px solid var(--line);border-radius:8px;width:100%">
              <option value="general" ${cat === 'general' ? 'selected' : ''}>공지</option>
              <option value="release" ${cat === 'release' ? 'selected' : ''}>릴리즈</option>
              <option value="update" ${cat === 'update' ? 'selected' : ''}>업데이트</option>
              <option value="preview" ${cat === 'preview' ? 'selected' : ''}>업데이트 예고</option>
            </select>
          </div>
          <div>
            <label style="font-weight:600;display:block;margin-bottom:4px">제목</label>
            <input type="text" name="title" value="${title}" placeholder="제목 입력" style="padding:8px 12px;border:1px solid var(--line);border-radius:8px;width:100%">
          </div>
          <div>
            <label style="font-weight:600;display:block;margin-bottom:4px">내용</label>
            <textarea name="content" rows="8" placeholder="내용 입력" style="padding:8px 12px;border:1px solid var(--line);border-radius:8px;width:100%">${content}</textarea>
          </div>
          <div style="display:flex;gap:16px;align-items:center">
            <label><input type="checkbox" name="is_pinned" value="1" ${isPinned}> 상단 고정</label>
            <select name="status" style="padding:8px 12px;border:1px solid var(--line);border-radius:8px">
              <option value="draft" ${status === 'draft' ? 'selected' : ''}>임시저장</option>
              <option value="published" ${status === 'published' ? 'selected' : ''}>게시</option>
            </select>
          </div>
          <div><button type="submit" class="btn btn-primary">${notice ? '수정' : '등록'}</button></div>
        </div>
      </div>`;
  }

  if (pathname === '/tc-backstage/notices' && method === 'GET') {
    const page = parseInt(url.searchParams.get('page') || '1');
    const data = await getNotices(page, 20);
    const publishedCount = data.rows.filter(r => r.status === 'published').length;
    const draftCount = data.rows.filter(r => r.status === 'draft').length;
    const pinnedCount = data.rows.filter(r => r.is_pinned).length;

    let tableContent = '';
    if (data.rows.length > 0) {
      tableContent = `<div class="table-wrap"><table>
        <tr><th>ID</th><th>카테고리</th><th>제목</th><th>상태</th><th>고정</th><th>날짜</th><th></th></tr>
        ${data.rows.map(r => `<tr>
          <td>${r.id}</td>
          <td>${noticeCategoryBadge(r.category)}</td>
          <td>${escapeHtml(r.title)}</td>
          <td>${noticeStatusBadge(r.status)}</td>
          <td>${r.is_pinned ? '📌' : ''}</td>
          <td>${formatDate(r.published_at || r.created_at)}</td>
          <td>
            <a href="/tc-backstage/notices/${r.id}/edit" class="btn btn-secondary">수정</a>
            <form method="POST" action="/tc-backstage/notices/${r.id}/delete" style="display:inline" onsubmit="return confirm('삭제하시겠습니까?')">
              <button type="submit" class="btn" style="background:#ffebee;color:#c62828">삭제</button>
            </form>
          </td>
        </tr>`).join('')}
      </table></div>
      ${pagination(data.page, data.total, data.limit, '/tc-backstage/notices')}`;
    } else {
      tableContent = '<div class="empty">공지사항 없음</div>';
    }

    const content = `
      ${pageHeader('공지사항', '앱 내 공지사항을 관리합니다. 게시 상태인 공지만 앱에 노출됩니다.', '<a href="/tc-backstage/notices/new" class="btn btn-primary">새 공지 작성</a>')}
      ${summaryStrip([
        { label: '전체', value: formatNumber(data.total) },
        { label: '게시중', value: formatNumber(publishedCount), valueColor: '#2e7d32' },
        { label: '임시저장', value: formatNumber(draftCount), valueColor: '#f57f17' },
        { label: '고정', value: formatNumber(pinnedCount) }
      ])}
      <div class="card">${tableContent}</div>
    `;
    return html(res, layout('공지사항', content, 'notices'));
  }

  // New notice form
  if (pathname === '/tc-backstage/notices/new' && method === 'GET') {
    const content = `
      ${pageHeader('새 공지 작성')}
      <form method="POST" action="/tc-backstage/notices/new">
        ${noticeFormHtml()}
      </form>
      <a href="/tc-backstage/notices" class="btn btn-secondary" style="margin-top:12px">목록으로</a>
    `;
    return html(res, layout('새 공지', content, 'notices'));
  }

  // Create notice
  if (pathname === '/tc-backstage/notices/new' && method === 'POST') {
    const body = await parseBody(req);
    await createNotice(body.category || 'general', body.title || '', body.content || '', body.is_pinned === '1', body.status || 'draft');
    return redirect(res, '/tc-backstage/notices');
  }

  // Edit notice form
  const noticeEditMatch = pathname.match(/^\/tc-backstage\/notices\/(\d+)\/edit$/);
  if (noticeEditMatch && method === 'GET') {
    const notice = await getNoticeById(parseInt(noticeEditMatch[1]));
    if (!notice) return html(res, layout('찾을 수 없음', '<div class="empty">공지를 찾을 수 없습니다</div>', 'notices'), 404);
    const content = `
      ${pageHeader('공지 수정')}
      <form method="POST" action="/tc-backstage/notices/${notice.id}/edit">
        ${noticeFormHtml(notice)}
      </form>
      <a href="/tc-backstage/notices" class="btn btn-secondary" style="margin-top:12px">목록으로</a>
    `;
    return html(res, layout('공지 수정', content, 'notices'));
  }

  // Update notice
  if (noticeEditMatch && method === 'POST') {
    const body = await parseBody(req);
    await updateNotice(parseInt(noticeEditMatch[1]), body.category || 'general', body.title || '', body.content || '', body.is_pinned === '1', body.status || 'draft');
    return redirect(res, '/tc-backstage/notices');
  }

  // Delete notice
  const noticeDeleteMatch = pathname.match(/^\/tc-backstage\/notices\/(\d+)\/delete$/);
  if (noticeDeleteMatch && method === 'POST') {
    await deleteNotice(parseInt(noticeDeleteMatch[1]));
    return redirect(res, '/tc-backstage/notices');
  }

  // ===== Push notifications =====
  if (pathname === '/tc-backstage/push' && method === 'GET') {
    const page = parseInt(url.searchParams.get('page')) || 1;
    const data = await getPushHistory(page, 20);
    const resultMsg = url.searchParams.get('result');
    const resultBanner = resultMsg ? `<div class="card" style="background:${resultMsg.startsWith('실패') ? '#ffebee' : '#e8f5e9'};border-left:4px solid ${resultMsg.startsWith('실패') ? '#c62828' : '#2e7d32'};margin-bottom:16px;font-weight:600">${escapeHtml(resultMsg)}</div>` : '';

    let tableContent;
    if (data.rows.length > 0) {
      tableContent = `<div class="table-wrap"><table>
        <tr><th>ID</th><th>관리자</th><th>제목</th><th>내용</th><th>대상</th><th>성공</th><th>실패</th><th>무효토큰</th><th>일시</th></tr>
        ${data.rows.map(r => {
          const filterBadge = r.target_filter === 'ios' ? '<span class="badge" style="background:#e3f2fd;color:#1565c0">iOS</span>'
            : r.target_filter === 'android' ? '<span class="badge" style="background:#e8f5e9;color:#2e7d32">Android</span>'
            : '<span class="badge" style="background:#f5f5f5;color:#333">전체</span>';
          const bodyTruncated = r.body.length > 40 ? r.body.substring(0, 40) + '...' : r.body;
          const date = new Date(r.created_at).toLocaleString('ko-KR', { timeZone: 'Asia/Seoul' });
          return `<tr>
            <td><a href="/tc-backstage/push/${r.id}">${r.id}</a></td>
            <td>${escapeHtml(r.admin_username)}</td>
            <td>${escapeHtml(r.title)}</td>
            <td style="color:#666;font-size:13px">${escapeHtml(bodyTruncated)}</td>
            <td>${filterBadge}</td>
            <td style="color:#2e7d32;font-weight:600">${r.success_count}</td>
            <td style="color:#c62828;font-weight:600">${r.fail_count}</td>
            <td style="color:#e65100;font-weight:600">${r.invalid_tokens}</td>
            <td style="font-size:12px;color:#888">${date}</td>
          </tr>`;
        }).join('')}
      </table></div>
      ${pagination(data.page, data.total, data.limit, '/tc-backstage/push')}`;
    } else {
      tableContent = '<div class="empty">발송 이력 없음</div>';
    }

    const content = `
      ${pageHeader('푸시알림', '전체 사용자에게 푸시 알림을 보내고 발송 이력을 관리합니다.')}
      ${resultBanner}
      <div class="card">
        <h3>푸시 발송</h3>
        <form method="POST" action="/tc-backstage/push/send" onsubmit="return confirm('정말 발송하시겠습니까? 대상 사용자 전체에게 푸시가 전송됩니다.')">
          <div style="margin-bottom:12px">
            <label style="font-weight:600;display:block;margin-bottom:4px">대상</label>
            <select name="targetFilter" style="padding:8px 12px;border-radius:8px;border:1px solid #ddd;font-size:14px;width:200px">
              <option value="all">전체</option>
              <option value="ios">iOS만</option>
              <option value="android">Android만</option>
            </select>
          </div>
          <div style="margin-bottom:12px">
            <label style="font-weight:600;display:block;margin-bottom:4px">제목</label>
            <input type="text" name="title" placeholder="푸시 제목" required style="width:100%;max-width:500px">
          </div>
          <div style="margin-bottom:12px">
            <label style="font-weight:600;display:block;margin-bottom:4px">내용</label>
            <textarea name="body" rows="3" placeholder="푸시 내용" required style="width:100%;max-width:500px"></textarea>
          </div>
          <button type="submit" class="btn btn-primary">발송</button>
        </form>
      </div>
      <div class="card" style="margin-top:16px">
        <h3>발송 이력</h3>
        ${tableContent}
      </div>
    `;
    return html(res, layout('푸시알림', content, 'push'));
  }

  // Send broadcast push
  if (pathname === '/tc-backstage/push/send' && method === 'POST') {
    const sessionData = getSessionFromCookie(req);
    const adminUsername = sessionData?.session?.username || 'unknown';
    const body = await parseBody(req);
    const title = (body.title || '').trim();
    const pushBody = (body.body || '').trim();
    const targetFilter = body.targetFilter || 'all';

    if (!title || !pushBody) {
      return redirect(res, '/tc-backstage/push?result=' + encodeURIComponent('실패: 제목과 내용을 입력해주세요'));
    }

    const tokenRows = await getBroadcastFcmTokens(targetFilter);
    if (tokenRows.length === 0) {
      return redirect(res, '/tc-backstage/push?result=' + encodeURIComponent('실패: 발송 대상이 없습니다'));
    }

    const result = await sendBroadcastPush(tokenRows, title, pushBody);

    // Clear invalid tokens
    for (const userId of result.invalidUserIds) {
      await clearInvalidFcmToken(userId);
    }

    // Build nickname map from tokenRows
    const nicknameMap = {};
    for (const row of tokenRows) {
      nicknameMap[row.id] = row.nickname;
    }

    const historyId = await insertPushHistory({
      adminUsername,
      title,
      body: pushBody,
      targetFilter,
      totalSent: tokenRows.length,
      successCount: result.successCount,
      failCount: result.failCount,
      invalidTokens: result.invalidUserIds.length,
    });

    // Build and save recipients
    const recipients = (result.results || []).map(r => ({
      userId: r.userId,
      nickname: nicknameMap[r.userId] || 'unknown',
      status: r.invalid ? 'invalid_token' : (r.success ? 'success' : 'fail'),
    }));
    if (recipients.length > 0) {
      await insertPushRecipients(historyId, recipients);
    }

    let msg;
    if (result.error) {
      msg = `실패: ${result.error} (이력 #${historyId}에 기록됨) — 전체 ${tokenRows.length}명`;
    } else {
      msg = `발송 완료 — 전체 ${tokenRows.length}명, 성공 ${result.successCount}, 실패 ${result.failCount}, 무효토큰 ${result.invalidUserIds.length}`;
    }
    return redirect(res, '/tc-backstage/push?result=' + encodeURIComponent(msg));
  }

  // Push detail page
  const pushDetailMatch = pathname.match(/^\/tc-backstage\/push\/(\d+)$/);
  if (pushDetailMatch && method === 'GET') {
    const pushId = parseInt(pushDetailMatch[1]);
    const page = parseInt(url.searchParams.get('page')) || 1;
    const data = await getPushHistoryDetail(pushId, page, 50);
    if (!data) return html(res, layout('찾을 수 없음', '<div class="empty">발송 이력을 찾을 수 없습니다</div>', 'push'), 404);

    const h = data.history;
    const filterLabel = h.target_filter === 'ios' ? 'iOS' : h.target_filter === 'android' ? 'Android' : '전체';
    const filterBadge = h.target_filter === 'ios' ? '<span class="badge" style="background:#e3f2fd;color:#1565c0">iOS</span>'
      : h.target_filter === 'android' ? '<span class="badge" style="background:#e8f5e9;color:#2e7d32">Android</span>'
      : '<span class="badge" style="background:#f5f5f5;color:#333">전체</span>';

    const statusBadgePush = (status) => {
      if (status === 'success') return '<span class="badge" style="background:#e8f5e9;color:#2e7d32">성공</span>';
      if (status === 'invalid_token') return '<span class="badge" style="background:#fff3e0;color:#e65100">무효토큰</span>';
      return '<span class="badge" style="background:#ffebee;color:#c62828">실패</span>';
    };

    let recipientTable;
    if (data.recipients.length > 0) {
      recipientTable = `<div class="table-wrap"><table>
        <tr><th>닉네임</th><th>상태</th></tr>
        ${data.recipients.map(r => `<tr>
          <td><a href="/tc-backstage/users/${encodeURIComponent(r.nickname)}">${escapeHtml(r.nickname)}</a></td>
          <td>${statusBadgePush(r.status)}</td>
        </tr>`).join('')}
      </table></div>
      ${pagination(data.page, data.total, data.limit, `/tc-backstage/push/${pushId}`)}`;
    } else {
      recipientTable = '<div class="empty">수신자 기록 없음</div>';
    }

    const content = `
      <h1 class="page-title">발송 상세 #${h.id}</h1>
      <div class="card">
        <div class="detail-grid">
          <div class="label">관리자</div><div class="value">${escapeHtml(h.admin_username)}</div>
          <div class="label">제목</div><div class="value">${escapeHtml(h.title)}</div>
          <div class="label">내용</div><div class="value" style="white-space:pre-wrap">${escapeHtml(h.body)}</div>
          <div class="label">대상</div><div class="value">${filterBadge}</div>
          <div class="label">전체 발송</div><div class="value">${h.total_sent}명</div>
          <div class="label">성공</div><div class="value" style="color:#2e7d32;font-weight:600">${h.success_count}</div>
          <div class="label">실패</div><div class="value" style="color:#c62828;font-weight:600">${h.fail_count}</div>
          <div class="label">무효토큰</div><div class="value" style="color:#e65100;font-weight:600">${h.invalid_tokens}</div>
          <div class="label">발송일시</div><div class="value">${formatDate(h.created_at)}</div>
        </div>
      </div>
      <div class="card" style="margin-top:16px">
        <h3>수신자 목록 (${formatNumber(data.total)}명)</h3>
        ${recipientTable}
      </div>
      <a href="/tc-backstage/push" class="btn btn-secondary" style="margin-top:12px">목록으로</a>
    `;
    return html(res, layout(`발송 상세 #${h.id}`, content, 'push'));
  }

  // 404
  html(res, layout('찾을 수 없음', '<div class="empty">페이지를 찾을 수 없습니다</div>'), 404);
}

module.exports = { handleAdminRoute };
