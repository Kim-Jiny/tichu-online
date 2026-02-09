const crypto = require('crypto');
const {
  verifyAdmin, getInquiries, getInquiryById, resolveInquiry,
  getReports, getReportGroup, updateReportGroupStatus,
  getUsers, getUserDetail, deleteUser, getDashboardStats,
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
  return session;
}

function setSessionCookie(res, token) {
  const flags = `HttpOnly; SameSite=Strict; Path=/tc-backstage${isProduction ? '; Secure' : ''}`;
  res.setHeader('Set-Cookie', `tc_admin_session=${token}; ${flags}`);
}

function clearSessionCookie(res) {
  const flags = `HttpOnly; SameSite=Strict; Path=/tc-backstage; Max-Age=0${isProduction ? '; Secure' : ''}`;
  res.setHeader('Set-Cookie', `tc_admin_session=; ${flags}`);
}

function parseBody(req) {
  return new Promise((resolve) => {
    let body = '';
    req.on('data', chunk => body += chunk);
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
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #f0f2f5; color: #1a1a2e; display: flex; min-height: 100vh; }
.sidebar { width: 220px; background: #1a1a2e; color: #e0e0e0; padding: 20px 0; position: fixed; height: 100vh; overflow-y: auto; }
.sidebar h2 { padding: 0 20px 20px; font-size: 18px; color: #fff; border-bottom: 1px solid #2a2a4e; margin-bottom: 10px; }
.sidebar a { display: block; padding: 12px 20px; color: #b0b0c8; text-decoration: none; font-size: 14px; transition: all 0.2s; }
.sidebar a:hover { background: #2a2a4e; color: #fff; }
.sidebar a.active { background: #2a2a4e; color: #6c63ff; border-left: 3px solid #6c63ff; }
.sidebar .logout { margin-top: 20px; border-top: 1px solid #2a2a4e; padding-top: 10px; }
.sidebar .logout a { color: #e57373; }
.main { margin-left: 220px; flex: 1; padding: 24px; min-height: 100vh; }
.page-title { font-size: 24px; font-weight: 700; margin-bottom: 20px; color: #1a1a2e; }
.stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 16px; margin-bottom: 24px; }
.stat-card { background: #fff; border-radius: 12px; padding: 20px; box-shadow: 0 2px 8px rgba(0,0,0,0.06); }
.stat-card .label { font-size: 13px; color: #888; margin-bottom: 4px; }
.stat-card .value { font-size: 28px; font-weight: 700; color: #1a1a2e; }
.stat-card .value.purple { color: #6c63ff; }
.stat-card .value.green { color: #4caf50; }
.stat-card .value.orange { color: #ff9800; }
.stat-card .value.red { color: #e53935; }
.card { background: #fff; border-radius: 12px; padding: 20px; box-shadow: 0 2px 8px rgba(0,0,0,0.06); margin-bottom: 20px; }
.card h3 { font-size: 16px; margin-bottom: 16px; color: #1a1a2e; }
table { width: 100%; border-collapse: collapse; }
th { text-align: left; padding: 10px 12px; background: #f8f9fa; color: #666; font-size: 13px; font-weight: 600; border-bottom: 2px solid #e0e0e0; }
td { padding: 10px 12px; border-bottom: 1px solid #f0f0f0; font-size: 14px; }
tr:hover td { background: #f8f9fa; }
.badge { display: inline-block; padding: 3px 10px; border-radius: 12px; font-size: 12px; font-weight: 600; }
.badge-pending { background: #fff3e0; color: #e65100; }
.badge-resolved { background: #e8f5e9; color: #2e7d32; }
.badge-reviewed { background: #e3f2fd; color: #1565c0; }
.badge-bug { background: #ffebee; color: #c62828; }
.badge-suggestion { background: #e8eaf6; color: #283593; }
.badge-other { background: #f3e5f5; color: #6a1b9a; }
.btn { display: inline-block; padding: 8px 16px; border-radius: 8px; font-size: 14px; font-weight: 600; border: none; cursor: pointer; text-decoration: none; transition: all 0.2s; }
.btn-primary { background: #6c63ff; color: #fff; }
.btn-primary:hover { background: #5a52e0; }
.btn-danger { background: #e53935; color: #fff; }
.btn-danger:hover { background: #c62828; }
.btn-success { background: #4caf50; color: #fff; }
.btn-success:hover { background: #388e3c; }
.btn-secondary { background: #e0e0e0; color: #333; }
.btn-secondary:hover { background: #bdbdbd; }
.detail-grid { display: grid; grid-template-columns: 120px 1fr; gap: 8px 16px; margin-bottom: 16px; }
.detail-grid .label { color: #888; font-size: 13px; font-weight: 600; }
.detail-grid .value { font-size: 14px; }
textarea { width: 100%; padding: 10px; border: 1px solid #ddd; border-radius: 8px; font-size: 14px; resize: vertical; font-family: inherit; }
input[type="text"], input[type="password"] { width: 100%; padding: 10px; border: 1px solid #ddd; border-radius: 8px; font-size: 14px; font-family: inherit; }
.search-bar { display: flex; gap: 8px; margin-bottom: 16px; }
.search-bar input { flex: 1; }
.pagination { display: flex; gap: 8px; margin-top: 16px; justify-content: center; }
.pagination a { padding: 6px 12px; border-radius: 6px; background: #e0e0e0; color: #333; text-decoration: none; font-size: 13px; }
.pagination a.active { background: #6c63ff; color: #fff; }
.chat-log { max-height: 400px; overflow-y: auto; background: #f8f9fa; border-radius: 8px; padding: 12px; margin: 12px 0; }
.chat-msg { padding: 6px 0; border-bottom: 1px solid #eee; font-size: 13px; }
.chat-msg .sender { font-weight: 600; color: #1a1a2e; }
.chat-msg .text { color: #555; }
.empty { text-align: center; padding: 40px; color: #999; font-size: 15px; }
</style>
</head>
<body>
<nav class="sidebar">
  <h2>Tichu Admin</h2>
  <a href="/tc-backstage/" class="${activePage === 'home' ? 'active' : ''}">Dashboard</a>
  <a href="/tc-backstage/inquiries" class="${activePage === 'inquiries' ? 'active' : ''}">Inquiries</a>
  <a href="/tc-backstage/reports" class="${activePage === 'reports' ? 'active' : ''}">Reports</a>
  <a href="/tc-backstage/users" class="${activePage === 'users' ? 'active' : ''}">Users</a>
  <div class="logout">
    <a href="/tc-backstage/logout">Logout</a>
  </div>
</nav>
<main class="main">
${content}
</main>
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
.login-box { background: #fff; border-radius: 16px; padding: 40px; width: 360px; box-shadow: 0 8px 32px rgba(0,0,0,0.3); }
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
  <input type="text" name="username" placeholder="Username" required autofocus>
  <input type="password" name="password" placeholder="Password" required>
  <button type="submit">Login</button>
</form>
</body>
</html>`;
}

function categoryBadge(cat) {
  const map = { bug: '버그', suggestion: '건의', other: '기타' };
  return `<span class="badge badge-${cat}">${map[cat] || cat}</span>`;
}

function statusBadge(status) {
  return `<span class="badge badge-${status}">${status}</span>`;
}

function formatDate(d) {
  if (!d) return '-';
  const dt = new Date(d);
  return dt.toLocaleString('ko-KR', { timeZone: 'Asia/Seoul' });
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

// ===== Route handler =====

async function handleAdminRoute(req, res, url, pathname, method, lobby, wss) {
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
  const session = getSessionFromCookie(req);
  if (!session) {
    return redirect(res, '/tc-backstage/login');
  }

  // Dashboard home
  if (pathname === '/tc-backstage/' || pathname === '/tc-backstage') {
    const stats = await getDashboardStats();
    // Get live data from lobby/wss
    const connectedUsers = wss ? wss.clients.size : 0;
    const allRooms = lobby ? lobby.getRoomList() : [];
    const activeRooms = allRooms.length;
    const gamingRooms = allRooms.filter(r => r.gameInProgress).length;

    let matchesTable = '';
    if (stats.recentMatches.length > 0) {
      matchesTable = `<table>
        <tr><th>ID</th><th>Winner</th><th>Score</th><th>Team A</th><th>Team B</th><th>Ranked</th><th>Date</th></tr>
        ${stats.recentMatches.map(m => `<tr>
          <td>${m.id}</td>
          <td>Team ${m.winner_team}</td>
          <td>${m.team_a_score} : ${m.team_b_score}</td>
          <td>${escapeHtml(m.player_a1)}, ${escapeHtml(m.player_a2)}</td>
          <td>${escapeHtml(m.player_b1)}, ${escapeHtml(m.player_b2)}</td>
          <td>${m.is_ranked ? 'Yes' : 'No'}</td>
          <td>${formatDate(m.created_at)}</td>
        </tr>`).join('')}
      </table>`;
    } else {
      matchesTable = '<div class="empty">No recent matches</div>';
    }

    const content = `
      <h1 class="page-title">Dashboard</h1>
      <div class="stats-grid">
        <div class="stat-card"><div class="label">Connected Users</div><div class="value purple">${connectedUsers}</div></div>
        <div class="stat-card"><div class="label">Active Rooms</div><div class="value">${activeRooms}</div></div>
        <div class="stat-card"><div class="label">Games In Progress</div><div class="value green">${gamingRooms}</div></div>
        <div class="stat-card"><div class="label">Pending Inquiries</div><div class="value orange">${stats.pendingInquiries}</div></div>
        <div class="stat-card"><div class="label">Pending Reports</div><div class="value red">${stats.pendingReports}</div></div>
        <div class="stat-card"><div class="label">Total Users</div><div class="value">${stats.totalUsers}</div></div>
        <div class="stat-card"><div class="label">Today's Games</div><div class="value">${stats.todayGames}</div></div>
      </div>
      <div class="card">
        <h3>Recent Matches</h3>
        ${matchesTable}
      </div>
    `;
    return html(res, layout('Dashboard', content, 'home'));
  }

  // ===== Inquiries =====
  if (pathname === '/tc-backstage/inquiries' && method === 'GET') {
    const page = parseInt(url.searchParams.get('page') || '1');
    const data = await getInquiries(page, 20);

    let tableContent = '';
    if (data.rows.length > 0) {
      tableContent = `<table>
        <tr><th>ID</th><th>User</th><th>Category</th><th>Title</th><th>Status</th><th>Date</th><th></th></tr>
        ${data.rows.map(r => `<tr>
          <td>${r.id}</td>
          <td>${escapeHtml(r.user_nickname)}</td>
          <td>${categoryBadge(r.category)}</td>
          <td>${escapeHtml(r.title)}</td>
          <td>${statusBadge(r.status)}</td>
          <td>${formatDate(r.created_at)}</td>
          <td><a href="/tc-backstage/inquiries/${r.id}" class="btn btn-secondary">View</a></td>
        </tr>`).join('')}
      </table>
      ${pagination(data.page, data.total, data.limit, '/tc-backstage/inquiries')}`;
    } else {
      tableContent = '<div class="empty">No inquiries</div>';
    }

    const content = `
      <h1 class="page-title">Inquiries</h1>
      <div class="card">${tableContent}</div>
    `;
    return html(res, layout('Inquiries', content, 'inquiries'));
  }

  // Inquiry detail
  const inquiryMatch = pathname.match(/^\/tc-backstage\/inquiries\/(\d+)$/);
  if (inquiryMatch && method === 'GET') {
    const inquiry = await getInquiryById(parseInt(inquiryMatch[1]));
    if (!inquiry) return html(res, layout('Not Found', '<div class="empty">Inquiry not found</div>', 'inquiries'), 404);

    const content = `
      <h1 class="page-title">Inquiry #${inquiry.id}</h1>
      <div class="card">
        <div class="detail-grid">
          <div class="label">User</div><div class="value"><a href="/tc-backstage/users/${encodeURIComponent(inquiry.user_nickname)}">${escapeHtml(inquiry.user_nickname)}</a></div>
          <div class="label">Category</div><div class="value">${categoryBadge(inquiry.category)}</div>
          <div class="label">Status</div><div class="value">${statusBadge(inquiry.status)}</div>
          <div class="label">Title</div><div class="value">${escapeHtml(inquiry.title)}</div>
          <div class="label">Content</div><div class="value" style="white-space:pre-wrap">${escapeHtml(inquiry.content)}</div>
          <div class="label">Created</div><div class="value">${formatDate(inquiry.created_at)}</div>
          ${inquiry.resolved_at ? `<div class="label">Resolved</div><div class="value">${formatDate(inquiry.resolved_at)}</div>` : ''}
          ${inquiry.admin_note ? `<div class="label">Admin Note</div><div class="value" style="white-space:pre-wrap">${escapeHtml(inquiry.admin_note)}</div>` : ''}
        </div>
        ${inquiry.status === 'pending' ? `
        <form method="POST" action="/tc-backstage/inquiries/${inquiry.id}/resolve" style="margin-top:16px">
          <textarea name="admin_note" rows="3" placeholder="Admin note (optional)"></textarea>
          <div style="margin-top:8px"><button type="submit" class="btn btn-success">Mark Resolved</button></div>
        </form>` : ''}
      </div>
      <a href="/tc-backstage/inquiries" class="btn btn-secondary">Back to list</a>
    `;
    return html(res, layout(`Inquiry #${inquiry.id}`, content, 'inquiries'));
  }

  // Resolve inquiry
  const resolveMatch = pathname.match(/^\/tc-backstage\/inquiries\/(\d+)\/resolve$/);
  if (resolveMatch && method === 'POST') {
    const body = await parseBody(req);
    await resolveInquiry(parseInt(resolveMatch[1]), body.admin_note || '');
    return redirect(res, `/tc-backstage/inquiries/${resolveMatch[1]}`);
  }

  // ===== Reports (grouped by reported_nickname + room_id) =====
  if (pathname === '/tc-backstage/reports' && method === 'GET') {
    const page = parseInt(url.searchParams.get('page') || '1');
    const data = await getReports(page, 20);

    let tableContent = '';
    if (data.rows.length > 0) {
      tableContent = `<table>
        <tr><th>Reported</th><th>Room</th><th>신고자</th><th>신고수</th><th>Status</th><th>Latest</th><th></th></tr>
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
          <td><a href="${detailUrl}" class="btn btn-secondary">View</a></td>
        </tr>`;
        }).join('')}
      </table>
      ${pagination(data.page, data.total, data.limit, '/tc-backstage/reports')}`;
    } else {
      tableContent = '<div class="empty">No reports</div>';
    }

    const content = `
      <h1 class="page-title">Reports</h1>
      <div class="card">${tableContent}</div>
    `;
    return html(res, layout('Reports', content, 'reports'));
  }

  // Report group detail
  if (pathname === '/tc-backstage/reports/group' && method === 'GET') {
    const target = url.searchParams.get('target') || '';
    const roomId = url.searchParams.get('room') || '';
    if (!target) return html(res, layout('Not Found', '<div class="empty">Report not found</div>', 'reports'), 404);

    const reports = await getReportGroup(target, roomId);
    if (reports.length === 0) return html(res, layout('Not Found', '<div class="empty">Report not found</div>', 'reports'), 404);

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
          <div class="label">Reported</div><div class="value"><a href="/tc-backstage/users/${encodeURIComponent(target)}">${escapeHtml(target)}</a></div>
          <div class="label">Room ID</div><div class="value">${escapeHtml(roomId) || '-'}</div>
          <div class="label">Status</div><div class="value">${statusBadge(groupStatus)}</div>
          <div class="label">신고 수</div><div class="value"><strong>${reports.length}</strong>건</div>
        </div>
        <h3 style="margin-top:16px">신고자 목록</h3>
        ${reportsHtml}
        ${chatHtml ? `<h3 style="margin-top:16px">Chat Context</h3>${chatHtml}` : ''}
        ${groupStatus !== 'resolved' ? `
        <form method="POST" action="${formUrl}" style="margin-top:16px">
          <select name="status" style="padding:8px;border-radius:8px;border:1px solid #ddd;font-size:14px">
            <option value="reviewed" ${groupStatus === 'reviewed' ? 'selected' : ''}>Reviewed</option>
            <option value="resolved">Resolved</option>
          </select>
          <button type="submit" class="btn btn-primary" style="margin-left:8px">Update Status</button>
        </form>` : ''}
      </div>
      <a href="/tc-backstage/reports" class="btn btn-secondary">Back to list</a>
    `;
    return html(res, layout(`Reports: ${escapeHtml(target)}`, content, 'reports'));
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
    const data = await getUsers(search, page, 20);

    const searchForm = `
      <div class="search-bar">
        <form method="GET" action="/tc-backstage/users" style="display:flex;gap:8px;width:100%">
          <input type="text" name="q" placeholder="Search nickname or username..." value="${escapeHtml(search)}">
          <button type="submit" class="btn btn-primary">Search</button>
        </form>
      </div>
    `;

    let tableContent = '';
    if (data.rows.length > 0) {
      tableContent = `<table>
        <tr><th>Nickname</th><th>Username</th><th>Games</th><th>W/L</th><th>Rating</th><th>Joined</th><th></th></tr>
        ${data.rows.map(u => `<tr>
          <td>${escapeHtml(u.nickname)}</td>
          <td>${escapeHtml(u.username)}</td>
          <td>${u.total_games}</td>
          <td>${u.wins}W / ${u.losses}L</td>
          <td>${u.rating}</td>
          <td>${formatDate(u.created_at)}</td>
          <td><a href="/tc-backstage/users/${encodeURIComponent(u.nickname)}" class="btn btn-secondary">View</a></td>
        </tr>`).join('')}
      </table>
      ${pagination(data.page, data.total, data.limit, `/tc-backstage/users${search ? '?q=' + encodeURIComponent(search) : ''}`)}`;
    } else {
      tableContent = '<div class="empty">No users found</div>';
    }

    const content = `
      <h1 class="page-title">Users</h1>
      <div class="card">
        ${searchForm}
        ${tableContent}
      </div>
    `;
    return html(res, layout('Users', content, 'users'));
  }

  // User detail
  const userDetailMatch = pathname.match(/^\/tc-backstage\/users\/([^/]+)$/);
  if (userDetailMatch && method === 'GET') {
    const nickname = decodeURIComponent(userDetailMatch[1]);
    const user = await getUserDetail(nickname);
    if (!user) return html(res, layout('Not Found', '<div class="empty">User not found</div>', 'users'), 404);

    const winRate = user.total_games > 0 ? Math.round((user.wins / user.total_games) * 100) : 0;

    const content = `
      <h1 class="page-title">User: ${escapeHtml(user.nickname)}</h1>
      <div class="card">
        <div class="detail-grid">
          <div class="label">Nickname</div><div class="value">${escapeHtml(user.nickname)}</div>
          <div class="label">Username</div><div class="value">${escapeHtml(user.username)}</div>
          <div class="label">Games</div><div class="value">${user.total_games}</div>
          <div class="label">Record</div><div class="value">${user.wins}W / ${user.losses}L (${winRate}%)</div>
          <div class="label">Rating</div><div class="value">${user.rating}</div>
          <div class="label">Reports</div><div class="value">${user.report_count}</div>
          <div class="label">Inquiries</div><div class="value">${user.inquiry_count}</div>
          <div class="label">Joined</div><div class="value">${formatDate(user.created_at)}</div>
          <div class="label">Last Login</div><div class="value">${formatDate(user.last_login)}</div>
        </div>
        <form method="POST" action="/tc-backstage/users/${encodeURIComponent(user.nickname)}/ban"
              onsubmit="return confirm('Are you sure you want to ban (delete) this user? This cannot be undone.')">
          <button type="submit" class="btn btn-danger">Ban User (Delete Account)</button>
        </form>
      </div>
      <a href="/tc-backstage/users" class="btn btn-secondary">Back to list</a>
    `;
    return html(res, layout(`User: ${escapeHtml(user.nickname)}`, content, 'users'));
  }

  // Ban user
  const banMatch = pathname.match(/^\/tc-backstage\/users\/([^/]+)\/ban$/);
  if (banMatch && method === 'POST') {
    const nickname = decodeURIComponent(banMatch[1]);
    await deleteUser(nickname);
    return redirect(res, '/tc-backstage/users');
  }

  // 404
  html(res, layout('Not Found', '<div class="empty">Page not found</div>'), 404);
}

module.exports = { handleAdminRoute };
