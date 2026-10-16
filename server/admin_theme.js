/**
 * 어드민 대시보드의 겉모양: 앱과 같은 카툰 테마(굵은 갈색 외곽선 + 단색 그림자 + 둥근 모서리),
 * 사이드바 구성, 아이콘, 로그인 화면.
 *
 * admin.js 의 페이지들은 `layout(title, content, activePage, pendingDeposits)` 로 이 파일의
 * renderLayout 을 부른다. 페이지 본문이 쓰는 클래스 이름(.card, .btn, .badge, table …)은 그대로
 * 두고 모양만 바꿨으므로, 페이지를 하나하나 고치지 않아도 전부 같은 옷을 입는다.
 */

// ───────────────────────────── 아이콘 ─────────────────────────────
// 24x24, 갈색 외곽선 + 앱 팔레트 채움. 이름 → <svg> 안쪽.
const ICON_BODIES = {
  home: '<path d="M3.5 11.2 12 4l8.5 7.2V20a1 1 0 0 1-1 1H15v-5.5H9V21H4.5a1 1 0 0 1-1-1z" fill="#FFD43B"/>',
  chart: '<rect x="4" y="12" width="4.2" height="8" rx="1" fill="#4DA3FF"/><rect x="9.9" y="6" width="4.2" height="14" rx="1" fill="#FF9A1F"/><rect x="15.8" y="9" width="4.2" height="11" rx="1" fill="#45C06A"/>',
  inquiry: '<path d="M4 5h16a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1h-8l-4.5 4v-4H4a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1z" fill="#9ADCFF"/><path d="M10 9.4a2 2 0 1 1 3 1.7c-.7.4-1 .8-1 1.5" fill="none"/><circle cx="12" cy="14.3" r=".6" fill="#3B2A20"/>',
  report: '<path d="M5 21V4"/><path d="M5 4.5h12l-2.2 3.5L17 11.5H5z" fill="#FF5A5F"/>',
  photo: '<rect x="3" y="5" width="18" height="14" rx="2.5" fill="#FFF4DC"/><circle cx="8.5" cy="10" r="1.8" fill="#FFD43B"/><path d="m4 17 5-4.5 3.5 3 3-2.5L20 17" fill="#45C06A"/>',
  'photo-reject': '<rect x="3" y="5" width="18" height="14" rx="2.5" fill="#FFF4DC"/><circle cx="8.5" cy="10" r="1.8" fill="#FFD43B"/><path d="m4 17 5-4.5 3.5 3 3-2.5L20 17" fill="#45C06A"/><path d="M5 20 19 4.5" stroke="#FF5A5F" stroke-width="2.6"/>',
  bot: '<rect x="5" y="8" width="14" height="11" rx="3" fill="#C9D3FF"/><path d="M12 8V4.8"/><circle cx="12" cy="4" r="1.3" fill="#FF5A5F"/><circle cx="9.3" cy="13" r="1.6" fill="#fff"/><circle cx="14.7" cy="13" r="1.6" fill="#fff"/><path d="M9.5 16.7h5"/>',
  users: '<circle cx="9" cy="8.5" r="3.2" fill="#FFD43B"/><path d="M3.5 20c0-3.3 2.4-5.5 5.5-5.5s5.5 2.2 5.5 5.5z" fill="#FF9A1F"/><circle cx="16.8" cy="9.5" r="2.4" fill="#9ADCFF"/><path d="M15.4 14.8c3 0 5 1.8 5 4.7h-4.4" fill="#4DA3FF"/>',
  online: '<circle cx="12" cy="12" r="2.8" fill="#45C06A"/><path d="M7 7a7 7 0 0 0 0 10M17 7a7 7 0 0 1 0 10" fill="none"/><path d="M4 4.5a11 11 0 0 0 0 15M20 4.5a11 11 0 0 1 0 15" fill="none"/>',
  matches: '<rect x="4" y="6" width="9" height="13" rx="1.8" fill="#FFF4DC" transform="rotate(-10 8.5 12.5)"/><rect x="11" y="5" width="9" height="13" rx="1.8" fill="#FF5A5F" transform="rotate(8 15.5 11.5)"/>',
  shop: '<path d="M5 8h14l-1 12H6z" fill="#FF9A1F"/><path d="M9 8V6.5a3 3 0 0 1 6 0V8" fill="none"/>',
  receipt: '<path d="M6 3.5h12v17l-2-1.4-2 1.4-2-1.4-2 1.4-2-1.4-2 1.4z" fill="#FFF4DC"/><path d="M9 8.5h6M9 12h6M9 15.5h3.5" fill="none"/>',
  coin: '<circle cx="12" cy="12" r="8.5" fill="#FFD43B"/><circle cx="12" cy="12" r="5.2" fill="none" stroke-width="1.4"/>',
  card: '<rect x="3" y="6" width="18" height="12" rx="2.5" fill="#45C06A"/><path d="M3 10.5h18"/><path d="M6.5 15h4"/>',
  shield: '<path d="M12 3.5 19 6v5.5c0 4.2-2.8 7.4-7 9-4.2-1.6-7-4.8-7-9V6z" fill="#9ADCFF"/><path d="m8.8 12 2.3 2.3 4.2-4.6" fill="none"/>',
  refund: '<path d="M5 12a7 7 0 1 0 2.2-5.1" fill="none"/><path d="M4 4.5v5h5z" fill="#FF9A1F"/>',
  issue: '<path d="M12 4 21.5 19.5h-19z" fill="#FFD43B"/><path d="M12 10v4.5" fill="none"/><circle cx="12" cy="17" r=".8" fill="#3B2A20"/>',
  bank: '<path d="M3 9 12 4l9 5z" fill="#FF9A1F"/><rect x="5" y="10.5" width="2.6" height="6.5" fill="#FFF4DC"/><rect x="10.7" y="10.5" width="2.6" height="6.5" fill="#FFF4DC"/><rect x="16.4" y="10.5" width="2.6" height="6.5" fill="#FFF4DC"/><path d="M3.5 19.5h17"/>',
  megaphone: '<path d="M4 10v4a1 1 0 0 0 1 1h2.5l7 4V5l-7 4H5a1 1 0 0 0-1 1z" fill="#FFD43B"/><path d="M18 9.5c1.2.8 1.2 4.2 0 5" fill="none"/>',
  ticket: '<path d="M3.5 8a1 1 0 0 1 1-1h15a1 1 0 0 1 1 1v2a2 2 0 0 0 0 4v2a1 1 0 0 1-1 1h-15a1 1 0 0 1-1-1v-2a2 2 0 0 0 0-4z" fill="#FF5A5F"/><path d="M14 8v8" stroke-dasharray="1.6 2" fill="none"/>',
  bell: '<path d="M6 17v-6a6 6 0 0 1 12 0v6l1.5 2h-15z" fill="#FFD43B"/><path d="M10 21h4" fill="none"/>',
  clock: '<circle cx="12" cy="12" r="8.5" fill="#FFF4DC"/><path d="M12 7.5V12l3 2" fill="none"/>',
  star: '<path d="m12 3.5 2.5 5.3 5.8.8-4.2 4 1 5.8L12 16.7l-5.1 2.7 1-5.8-4.2-4 5.8-.8z" fill="#FFD43B"/>',
  mail: '<rect x="3" y="6" width="18" height="13" rx="2.5" fill="#FFF4DC"/><path d="m3.5 7.5 8.5 6 8.5-6" fill="none"/>',
  log: '<rect x="3" y="5" width="18" height="14" rx="2.5" fill="#3B2A20"/><path d="m7 10 3 2.5L7 15" stroke="#45C06A" fill="none"/><path d="M12.5 15.5H17" stroke="#FFD43B" fill="none"/>',
  wrench: '<path d="M14.5 5a4.5 4.5 0 0 0-4.2 6L4.5 16.8a1.8 1.8 0 0 0 2.7 2.7L13 13.7a4.5 4.5 0 0 0 6-4.2l-2.8 2.8-2.5-.6-.6-2.5L16 6.5A4.5 4.5 0 0 0 14.5 5z" fill="#9ADCFF"/>',
  gear: '<path d="m12 3.5 1.6 2.1 2.6-.6 1 2.5 2.5 1-.6 2.6 2.1 1.6-2.1 1.6.6 2.6-2.5 1-1 2.5-2.6-.6-1.6 2.1-1.6-2.1-2.6.6-1-2.5-2.5-1 .6-2.6L2.8 11.3l2.1-1.6-.6-2.6 2.5-1 1-2.5 2.6.6z" fill="#C9D3FF"/><circle cx="12" cy="12" r="3" fill="#FFF4DC"/>',
  trophy: '<path d="M7 4h10v5a5 5 0 0 1-10 0z" fill="#FFD43B"/><path d="M7 6H4.5a2.5 2.5 0 0 0 2.6 3.6M17 6h2.5a2.5 2.5 0 0 1-2.6 3.6" fill="none"/><path d="M12 14v3.5M8.5 20h7" fill="none"/>',
  calendar: '<rect x="3.5" y="5" width="17" height="15" rx="2.5" fill="#FFF4DC"/><path d="M3.5 10h17M8 3.5v3M16 3.5v3" fill="none"/><path d="m9 15 2 2 4-4" stroke="#45C06A" fill="none"/>',
  target: '<circle cx="12" cy="12" r="8.5" fill="#FFF4DC"/><circle cx="12" cy="12" r="4.8" fill="#FF5A5F"/><circle cx="12" cy="12" r="1.5" fill="#FFF4DC"/>',
  checklist: '<rect x="5" y="4" width="14" height="17" rx="2.5" fill="#FFF4DC"/><path d="m8.5 9 1.5 1.5L13 7.8M8.5 15l1.5 1.5L13 13.8M14.5 9.5h2M14.5 15.5h2" fill="none"/>',
  gift: '<rect x="4" y="10" width="16" height="10" rx="1.8" fill="#FF5A5F"/><rect x="3" y="7" width="18" height="4" rx="1.5" fill="#FF9A1F"/><path d="M12 7v13" fill="none"/><path d="M12 7C10 3.5 6.5 4.5 8 7M12 7c2-3.5 5.5-2.5 4 0" fill="none"/>',
  token: '<circle cx="12" cy="12" r="8.5" fill="#FFD43B"/><path d="m12 7.5 1.4 3 3.2.4-2.4 2.2.7 3.2L12 14.7l-2.9 1.6.7-3.2-2.4-2.2 3.2-.4z" fill="#FF9A1F" stroke-width="1.3"/>',
  book: '<path d="M5 4.5h11a3 3 0 0 1 3 3V20H8a3 3 0 0 1-3-3z" fill="#9ADCFF"/><path d="M8 20a3 3 0 0 1-3-3" fill="none"/><path d="M9 9h6M9 12.5h6" fill="none"/>',
  logout: '<path d="M9 4.5H6A1.5 1.5 0 0 0 4.5 6v12A1.5 1.5 0 0 0 6 19.5h3" fill="none"/><path d="m13 8.5 3.8 3.5-3.8 3.5M16.8 12H9.5" fill="none"/>',
  search: '<circle cx="10.5" cy="10.5" r="6" fill="#FFF4DC"/><path d="m15 15 5 5" stroke-width="2.4" fill="none"/>',
  chevron: '<path d="m8 10 4 4 4-4" fill="none" stroke-width="2.2"/>',
  menu: '<path d="M4 7h16M4 12h16M4 17h16" fill="none" stroke-width="2.4"/>',
  top: '<path d="m6 14 6-6 6 6" fill="none" stroke-width="2.6"/>',
};

function icon(name, size = 20) {
  const body = ICON_BODIES[name] || ICON_BODIES.star;
  return `<svg class="ic" width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="#3B2A20" stroke-width="1.7" stroke-linejoin="round" stroke-linecap="round" aria-hidden="true">${body}</svg>`;
}

// ───────────────────────────── 메뉴 구성 ─────────────────────────────
// key 는 layout() 의 activePage 와 같아야 한다. badge 는 아래 renderLayout 의 badges 에서 읽는다.
const NAV_GROUPS = [
  {
    id: 'overview', label: '홈', color: '#FFD43B',
    items: [
      { key: 'home', href: '/tc-backstage/', label: '대시보드', icon: 'home' },
      { key: 'stats', href: '/tc-backstage/stats', label: '통계', icon: 'chart' },
    ],
  },
  {
    id: 'ops', label: '운영 처리', color: '#FF5A5F',
    items: [
      { key: 'inquiries', href: '/tc-backstage/inquiries', label: '문의', icon: 'inquiry', badge: 'inquiries' },
      { key: 'reports', href: '/tc-backstage/reports', label: '신고', icon: 'report', badge: 'reports' },
      { key: 'profile-photos', href: '/tc-backstage/profile-photos', label: '프로필사진', icon: 'photo' },
      { key: 'photo-rejections', href: '/tc-backstage/photo-rejections', label: '리젝 사진', icon: 'photo-reject' },
    ],
  },
  {
    id: 'people', label: '유저·게임', color: '#4DA3FF',
    items: [
      { key: 'users', href: '/tc-backstage/users', label: '유저', icon: 'users' },
      { key: 'online', href: '/tc-backstage/online', label: '접속 현황', icon: 'online' },
      { key: 'matches', href: '/tc-backstage/matches', label: '최근 매치', icon: 'matches' },
      { key: 'filler-rooms', href: '/tc-backstage/filler-rooms', label: '봇방', icon: 'bot' },
      { key: 'seasons', href: '/tc-backstage/seasons', label: '시즌', icon: 'trophy' },
      { key: 'attendance', href: '/tc-backstage/attendance', label: '출석', icon: 'calendar' },
    ],
  },
  {
    id: 'missions', label: '미션·토큰', color: '#FF9A1F',
    items: [
      { key: 'missions-overview', href: '/tc-backstage/missions', label: '미션 현황', icon: 'target' },
      { key: 'missions-manage', href: '/tc-backstage/missions/manage', label: '미션 관리', icon: 'checklist' },
      { key: 'missions-shop', href: '/tc-backstage/missions/shop', label: '토큰 상점', icon: 'gift' },
      { key: 'missions-grant', href: '/tc-backstage/missions/grant', label: '토큰 지급·회수', icon: 'token' },
      { key: 'missions-ledger', href: '/tc-backstage/missions/ledger', label: '토큰 장부', icon: 'book' },
    ],
  },
  {
    id: 'shop', label: '상점·매출', color: '#45C06A',
    items: [
      { key: 'shop', href: '/tc-backstage/shop', label: '상점', icon: 'shop' },
      { key: 'shop-history', href: '/tc-backstage/shop/history', label: '상점 구매', icon: 'receipt' },
      { key: 'gold-products', href: '/tc-backstage/gold-products', label: '골드상품', icon: 'coin' },
      { key: 'iap-receipts', href: '/tc-backstage/iap-receipts', label: '결제내역', icon: 'card' },
      { key: 'iap-attempts', href: '/tc-backstage/iap-attempts', label: '검증로그', icon: 'shield' },
      { key: 'iap-consumption', href: '/tc-backstage/iap-consumption', label: '환불요청', icon: 'refund' },
      { key: 'iap-refund-issues', href: '/tc-backstage/iap-refund-issues', label: '환불문제', icon: 'issue' },
      { key: 'deposits', href: '/tc-backstage/deposits', label: '입금확인', icon: 'bank', badge: 'deposits' },
    ],
  },
  {
    id: 'comms', label: '소통', color: '#9ADCFF',
    items: [
      { key: 'notices', href: '/tc-backstage/notices', label: '공지사항', icon: 'megaphone' },
      { key: 'coupons', href: '/tc-backstage/coupons', label: '쿠폰', icon: 'ticket' },
      { key: 'push', href: '/tc-backstage/push', label: '푸시알림', icon: 'bell' },
      { key: 'push-history', href: '/tc-backstage/push-history', label: '푸시 히스토리', icon: 'clock' },
      { key: 'campaigns', href: '/tc-backstage/campaigns', label: '마케팅 푸시', icon: 'star' },
      { key: 'mail', href: '/tc-backstage/mail', label: '운영자 우편함', icon: 'mail' },
    ],
  },
  {
    id: 'system', label: '시스템', color: '#C9D3FF',
    items: [
      { key: 'logs', href: '/tc-backstage/logs', label: '서버로그', icon: 'log' },
      { key: 'maintenance', href: '/tc-backstage/maintenance', label: '점검', icon: 'wrench' },
      { key: 'settings', href: '/tc-backstage/settings', label: '설정', icon: 'gear' },
    ],
  },
];

// activePage → 페이지 제목 옆에 붙일 아이콘
const PAGE_ICONS = {};
for (const g of NAV_GROUPS) for (const it of g.items) PAGE_ICONS[it.key] = it.icon;

function escapeAttr(s) {
  return String(s).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
}

function renderNav(activePage, badges) {
  return NAV_GROUPS.map((g) => {
    const hasActive = g.items.some((it) => it.key === activePage);
    const groupBadge = g.items.reduce((n, it) => n + (it.badge ? (badges[it.badge] || 0) : 0), 0);
    return `<details class="nav-group" data-group="${g.id}"${hasActive ? ' open data-active="1"' : ''} style="--gc:${g.color}">
      <summary><span class="ng-dot"></span><span class="ng-label">${g.label}</span>${groupBadge > 0 ? `<span class="ng-badge">${groupBadge > 99 ? '99+' : groupBadge}</span>` : ''}<span class="ng-chev">${icon('chevron', 16)}</span></summary>
      <div class="ng-items">${g.items.map((it) => {
    const n = it.badge ? (badges[it.badge] || 0) : 0;
    return `<a href="${it.href}" class="nav-link${it.key === activePage ? ' active' : ''}" data-label="${escapeAttr(it.label)}" onclick="closeSidebar()"><span class="nl-ic">${icon(it.icon, 20)}</span><span class="nl-t">${it.label}</span>${n > 0 ? `<span class="nl-badge">${n > 99 ? '99+' : n}</span>` : ''}</a>`;
  }).join('')}</div>
    </details>`;
  }).join('');
}

// ───────────────────────────── CSS ─────────────────────────────
// BASE_CSS 는 예전 어드민의 레이아웃·반응형 규칙 그대로다(페이지들이 쓰는 클래스가 전부 들어 있다).
// 아래 THEME_CSS 가 그 위에 카툰 옷을 입힌다.
const BASE_CSS = String.raw`* { margin: 0; padding: 0; box-sizing: border-box; }
html, body { width: 100%; max-width: 100%; overflow-x: hidden; }
:root {
  --bg: #f6f5f2;
  --surface: #ffffff;
  --surface-strong: #ffffff;
  --line: #e4e1da;
  --text: #1f2328;
  --muted: #6c727f;
  --brand: #0f6c5c;
  --brand-soft: #d9eee7;
  --accent: #d88c38;
  --danger: #c0563f;
  --warning: #c67b2b;
  --shadow: none;
}
body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
  background: var(--bg);
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
  background: transparent;
  border: none;
  border-left: 1px solid var(--line);
  border-radius: 0;
  padding: 2px 0 2px 16px;
}
.stats-grid > .stat-card:first-child { border-left: none; padding-left: 0; }
.stat-card .label { font-size: 12px; color: var(--muted); margin-bottom: 6px; letter-spacing: 0; text-transform: none; }
.stat-card .value { font-size: 26px; font-weight: 700; color: var(--text); letter-spacing: -0.02em; }
.stat-card .value.purple { color: #5f62d6; }
.stat-card .value.green { color: #2e8b57; }
.stat-card .value.orange { color: var(--warning); }
.stat-card .value.red { color: var(--danger); }
/* 상자를 겹치지 않는다: 카드 테두리·그림자·둥근 모서리를 걷어내고, 구획은
   여백과 얇은 구분선으로만 나눈다. 페이지마다 카드가 카드를 품고 있어서
   중요한 숫자와 배경 장식이 같은 무게로 보이던 문제. */
.card {
  background: transparent;
  border: none;
  border-top: 1px solid var(--line);
  border-radius: 0;
  padding: 20px 0 4px;
  box-shadow: none;
  margin-bottom: 8px;
  min-width: 0;
  width: 100%;
  max-width: 100%;
}
.card h3 {
  font-size: 13px;
  font-weight: 700;
  margin-bottom: 14px;
  color: var(--muted);
  letter-spacing: 0.06em;
  text-transform: uppercase;
}
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
.summary-item { background: transparent; border: none; border-left: 1px solid var(--line); border-radius: 0; padding: 2px 0 2px 16px; }
.summary-strip > .summary-item:first-child { border-left: none; padding-left: 0; }
.summary-item .k { font-size: 12px; color: var(--muted); margin-bottom: 6px; text-transform: none; letter-spacing: 0; }
.summary-item .v { font-size: 24px; font-weight: 800; letter-spacing: -0.02em; color: var(--text); }
.summary-item .meta { margin-top: 6px; font-size: 12px; color: var(--muted); line-height: 1.5; }
.section-label { font-size: 12px; color: var(--muted); margin-bottom: 10px; text-transform: none; letter-spacing: 0; font-weight: 700; }

/* ── 대시보드 ─────────────────────────────────────────────────────────
   숫자만 크게 늘어놓으면 무엇이 이상한지 알 수 없다. 모든 수치는 비교
   대상(어제, 7일 평균)을 데리고 다니고, 손댈 것이 있는 항목만 색을 쓴다. */
.dash-section { padding: 26px 0; border-top: 1px solid var(--line); }
.dash-section:first-of-type { border-top: none; padding-top: 8px; }
.dash-head { display: flex; align-items: baseline; justify-content: space-between; gap: 8px 12px; margin-bottom: 16px; flex-wrap: wrap; }
.dash-head h2 { font-size: 15px; font-weight: 700; color: var(--text); letter-spacing: -0.01em; }
.dash-head .hint { font-size: 12px; color: var(--muted); }
.dash-head a { font-size: 12px; color: var(--brand); text-decoration: none; font-weight: 600; }

.kpi-row { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 0; min-width: 0; }
.kpi { min-width: 0; }
.kpi { padding: 2px 18px; border-left: 1px solid var(--line); }
.kpi:first-child { border-left: none; padding-left: 0; }
.kpi .k { font-size: 12px; color: var(--muted); margin-bottom: 6px; }
.kpi .v { font-size: 30px; font-weight: 700; letter-spacing: -0.03em; line-height: 1.1; }
.kpi .v .unit { font-size: 14px; font-weight: 600; color: var(--muted); margin-left: 3px; }
.kpi .d { margin-top: 6px; font-size: 12px; color: var(--muted); }
.kpi .d .up { color: #2e7d54; font-weight: 700; }
.kpi .d .down { color: #b4553f; font-weight: 700; }
.kpi .d .flat { color: var(--muted); font-weight: 700; }

/* 처리 대기: 0건이면 한 줄로 조용히, 있으면 눈에 띄게. */
.todo-row { display: flex; flex-wrap: wrap; gap: 8px; }
.todo { display: inline-flex; align-items: baseline; gap: 8px; padding: 10px 14px; border: 1px solid #e7c9bf; background: #fdf3f0; border-radius: 8px; text-decoration: none; }
.todo .n { font-size: 20px; font-weight: 800; color: #b4553f; letter-spacing: -0.02em; }
.todo .t { font-size: 13px; color: #7a4436; font-weight: 600; }
.todo-clear { font-size: 13px; color: var(--muted); }

.facts { display: grid; grid-template-columns: repeat(auto-fit, minmax(210px, 1fr)); gap: 0 28px; min-width: 0; }
.facts > div { min-width: 0; }
.fact { display: flex; align-items: baseline; justify-content: space-between; gap: 12px; padding: 9px 0; border-bottom: 1px solid #f1efe9; }
.fact .k { font-size: 13px; color: var(--muted); }
.fact .v { font-size: 14px; font-weight: 700; }
.fact .v.warn { color: #b4553f; }

.cell-ellipsis { max-width: 260px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.spark { display: flex; align-items: flex-end; gap: 4px; height: 92px; min-width: 0; }
.spark .col { flex: 1; display: flex; flex-direction: column; align-items: center; gap: 4px; min-width: 0; }
.spark .stack { width: 100%; max-width: 34px; display: flex; flex-direction: column-reverse; border-radius: 3px; overflow: hidden; }
.spark .n { font-size: 11px; color: var(--muted); font-variant-numeric: tabular-nums; }
.spark .x { font-size: 10px; color: #a9a49a; }
.spark .col.today .n { color: var(--text); font-weight: 700; }
.spark .col.today .x { color: var(--text); font-weight: 700; }
.legend { display: flex; gap: 14px; flex-wrap: wrap; margin-top: 12px; }
.legend span { display: inline-flex; align-items: center; gap: 6px; font-size: 12px; color: var(--muted); }
.legend i { width: 9px; height: 9px; border-radius: 2px; display: inline-block; }
.legend .zero { opacity: 0.4; }
/* minmax(0,1fr): 그냥 1fr 이면 칸이 표의 최소 너비까지 늘어나 페이지 전체가
   가로로 넘친다(모바일에서 오른쪽이 잘리던 원인). */
.dash-cols { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: 28px; align-items: start; }
.dash-cols > * { min-width: 0; }
@media (max-width: 1100px) { .dash-cols { grid-template-columns: minmax(0, 1fr); gap: 22px; } }
.kpi-note { font-size: 12px; color: var(--muted); margin-top: 6px; line-height: 1.5; }
.metric-inline { display: flex; align-items: center; justify-content: space-between; gap: 10px; padding: 10px 0; border-bottom: 1px dashed rgba(32,28,22,0.08); }
.metric-inline:last-child { border-bottom: none; padding-bottom: 0; }
.metric-inline .name { font-size: 13px; color: var(--muted); }
.metric-inline .num { font-weight: 700; font-size: 15px; color: var(--text); }
.card-actions { display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 14px; }
/* 화면 여러 곳이 .table-responsive 를 붙여 쓰고 있었는데 CSS 에 정의가
   없어 아무 일도 하지 않았다 — 폰에서 표가 그대로 삐져나갔다. */
.table-responsive,
.table-wrap { overflow-x: auto; -webkit-overflow-scrolling: touch; border: 1px solid var(--line); border-radius: 8px; background: var(--surface); scrollbar-width: thin; max-width: 100%; width: 100%; }
table { width: 100%; max-width: 100%; border-collapse: separate; border-spacing: 0; }
th { text-align: left; padding: 10px 14px; background: #faf9f6; color: var(--muted); font-size: 12px; font-weight: 700; border-bottom: 1px solid var(--line); white-space: nowrap; text-transform: none; letter-spacing: 0; position: sticky; top: 0; z-index: 1; }
td { padding: 10px 14px; border-bottom: 1px solid #f1efe9; font-size: 14px; vertical-align: middle; }
tr:last-child td { border-bottom: none; }
tr:hover td { background: #f7f9f8; }
.badge { display: inline-block; padding: 3px 10px; border-radius: 12px; font-size: 12px; font-weight: 600; white-space: nowrap; }
.badge-pending { background: #fff3e0; color: #e65100; }
.badge-resolved { background: #e8f5e9; color: #2e7d32; }
.badge-reviewed { background: #e3f2fd; color: #1565c0; }
.badge-bug { background: #ffebee; color: #c62828; }
.badge-suggestion { background: #e8eaf6; color: #283593; }
.badge-payment { background: #fff3e0; color: #e65100; }
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
  padding: 0 0 18px;
  border-radius: 0;
  background: transparent;
  border: none;
  border-bottom: 1px solid var(--line);
  box-shadow: none;
  margin-bottom: 18px;
}
.filter-title { font-size: 12px; color: var(--muted); text-transform: none; letter-spacing: 0; margin-bottom: 10px; font-weight: 700; }
/* 필터 한 줄.
 *
 * 예전에는 폼마다 style="display:flex;..." 와 style="width:130px" 을 직접
 * 박았다. 인라인은 클래스가 못 이기므로 좁은 화면 규칙이 통하지 않았고,
 * 폰에서 칸이 줄을 넘지 못해 가로로 삐져나갔다. 폭을 클래스로 옮겨 둔다.
 *   f-grow  검색처럼 남는 자리를 먹는 칸
 *   f-mid   IP·OS·버전처럼 중간 폭
 *   f-num   최소 레이팅·게임·이탈처럼 짧은 숫자
 *   f-gap   버튼을 오른쪽으로 미는 빈칸 (폰에서는 사라진다)
 */
.filter-row { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; width: 100%; }
.filter-row .f-grow { flex: 1 1 200px; min-width: 0; }
.filter-row .f-mid { flex: 0 1 130px; min-width: 0; }
.filter-row .f-num { flex: 0 1 100px; min-width: 0; }
.filter-row .f-gap { flex: 1 1 0; }
.filter-row .f-label { font-size: 12px; color: var(--muted); }
.filter-form { display: flex; flex-direction: column; gap: 8px; width: 100%; }
.subtab-bar { display: flex; gap: 10px; flex-wrap: wrap; margin-bottom: 18px; }
.subtab-link {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 8px 13px;
  border-radius: 8px;
  text-decoration: none;
  color: var(--muted);
  background: transparent;
  border: 1px solid var(--line);
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
/* 붙박이 상자를 없앤다. 스크롤을 따라다니되 배경·그림자 없이 구분선만. */
.sticky-kpi-rail {
  position: sticky;
  top: 0;
  z-index: 20;
  margin-bottom: 18px;
  padding: 14px 0;
  border-radius: 0;
  background: var(--bg);
  border: none;
  border-bottom: 1px solid var(--line);
  box-shadow: none;
}
.sticky-kpi-title { font-size: 12px; color: var(--muted); text-transform: uppercase; letter-spacing: 0.08em; margin-bottom: 10px; }
.sticky-kpi-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 10px; }
.sticky-kpi-item { padding: 2px 0; border-radius: 0; background: transparent; border: none; }
.sticky-kpi-item .k { font-size: 12px; color: var(--muted); text-transform: none; letter-spacing: 0; margin-bottom: 6px; }
.sticky-kpi-item .v { font-size: 22px; font-weight: 800; color: var(--text); letter-spacing: -0.02em; }
.sticky-kpi-item .m { margin-top: 6px; font-size: 12px; color: var(--muted); line-height: 1.5; }
.hero-rail { padding: 14px 0; }
.hero-kpi { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 14px 4px; }
.hero-item { padding: 2px 18px; min-width: 0; border-left: 1px solid var(--line); }
.hero-item:first-child { border-left: none; padding-left: 0; }
.hk-label { font-size: 12px; color: var(--muted); letter-spacing: 0.02em; margin-bottom: 7px; white-space: nowrap; }
.hk-value { font-size: 28px; font-weight: 700; color: var(--text); letter-spacing: -0.03em; line-height: 1.05; }
.hk-delta { margin-top: 9px; }
.hk-prev { font-size: 11px; color: var(--muted); margin-top: 5px; }
.delta { display: inline-flex; align-items: center; gap: 3px; font-size: 12px; font-weight: 700; padding: 2px 9px; border-radius: 999px; line-height: 1.5; }
.delta.up { color: #1a7f4b; background: rgba(46,139,87,0.13); }
.delta.down { color: #c0563f; background: rgba(192,86,63,0.13); }
.delta.flat { color: #8a8378; background: rgba(138,131,120,0.12); font-weight: 600; }
.chart-foldout { border: 1px solid #ebe4d8; border-radius: 14px; background: #fff; margin: 12px 0; overflow: hidden; }
.chart-foldout > summary { cursor: pointer; padding: 13px 18px; font-size: 14px; font-weight: 700; color: var(--text); list-style: none; display: flex; align-items: center; justify-content: space-between; }
.chart-foldout > summary::-webkit-details-marker { display: none; }
.chart-foldout > summary::after { content: '▾ 차트 보기'; font-size: 12px; font-weight: 600; color: var(--muted); }
.chart-foldout[open] > summary::after { content: '▴ 접기'; }
.chart-foldout .card-body { padding: 2px 18px 18px; }
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
  .header-actions { width: 100%; display: flex; gap: 8px; }
  .header-actions .btn { flex: 1 1 0; min-width: 0; text-align: center; }
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
  /* 칸을 줄 단위로 눕힌다. 검색은 한 줄을 통째로, 나머지는 두세 개씩
   * 나눠 담아 세로로 끝없이 길어지지 않게 한다. */
  .filter-row { gap: 10px; }
  .filter-row .f-grow { flex: 1 1 100%; }
  .filter-row .f-mid { flex: 1 1 calc(50% - 5px); }
  .filter-row .f-num { flex: 1 1 calc(33.333% - 7px); }
  .filter-row .f-gap { display: none; }
  .filter-row .btn { flex: 1 1 auto; text-align: center; }
  /* 폰에서는 볼 자리가 없는 열을 접는다. 표가 가로로 스크롤되긴 하지만,
   * 열세 칸을 밀어 가며 보는 것과 필요한 것만 보는 것은 다르다. */
  .col-hide-sm { display: none; }
  /* 인라인 style="display:flex" 로 짠 줄들은 클래스가 없어 하나씩 잡을 수가
   * 없다. 그렇다고 전부 접으면 막대그래프(align-items:flex-end 로 세운 것)
   * 처럼 접히면 안 되는 것까지 무너진다. **입력칸이 든 줄만** 고른다 —
   * 폰에서 삐져나가는 건 그쪽이고, 차트에는 입력칸이 없다. */
  [style*="display:flex"]:has(input, select, textarea) { flex-wrap: wrap; }
  /* 그 줄 안에 인라인으로 박힌 폭이 화면보다 넓어도 화면을 넘지는 않게.
   * width 를 덮어쓰지 않고 상한만 씌우므로, 화면에 들어가는 폭은 그대로다. */
  .card input, .card select, .card textarea,
  .filter-card input, .filter-card select, .filter-card textarea {
    max-width: 100%;
  }
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
  .hero-kpi { grid-template-columns: 1fr 1fr; gap: 16px 0; }
  .hero-item { padding: 0 14px; border-left: 1px solid rgba(32,28,22,0.08); }
  .hero-item:nth-child(odd) { border-left: none; padding-left: 0; }
  .hk-value { font-size: 24px; }
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
/* 대시보드 모바일: 지표는 두 칸까지만, 구분선은 세로선 대신 가로선으로. */
@media (max-width: 768px) {
  .dash-section { padding: 20px 0; }
  .dash-head h2 { font-size: 14px; }
  .dash-head .hint { font-size: 11px; line-height: 1.5; }
  .kpi-row { grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 14px 12px; }
  .kpi { border-left: none; padding: 0; }
  .kpi .v { font-size: 24px; }
  .kpi .d { font-size: 11px; }
  .facts { grid-template-columns: minmax(0, 1fr); gap: 0; }
  .todo { padding: 9px 12px; }
  .spark { height: 84px; }
  .spark .n { font-size: 10px; }
  .spark .x { font-size: 9px; }
  .cell-ellipsis { max-width: 150px; }
}

@media (max-width: 480px) {
  .sidebar { width: 88vw; }
  .kpi-row { gap: 12px 10px; }
  .kpi .v { font-size: 21px; }
  .cell-ellipsis { max-width: 116px; }
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
`;

const THEME_CSS = String.raw`
/* ═════════════ 카툰 테마 ═════════════
   앱과 같은 규칙: 모든 테두리와 그림자는 같은 갈색(--ink), 그림자는 번지지 않는 단색. */
:root {
  --ink: #3b2a20;
  --cream: #fff4dc;
  --paper: #fffbf2;
  --sky: #cfeeff;
  --orange: #ff9a1f;
  --orange-deep: #e0720a;
  --blue: #4da3ff;
  --green: #45c06a;
  --red: #ff5a5f;
  --yellow: #ffd43b;
  --bg: #fff1d6;
  --surface: #fffbf2;
  --surface-strong: #fffbf2;
  --line: rgba(59, 42, 32, 0.2);
  --text: #3b2a20;
  --muted: #8a7565;
  --brand: #e0720a;
  --brand-soft: #ffe7c2;
  --accent: #ff9a1f;
  --danger: #e5484d;
  --warning: #e0720a;
  --font-display: 'Jua', 'Noto Sans KR', 'Apple SD Gothic Neo', sans-serif;
  --font-body: 'Noto Sans KR', 'Apple SD Gothic Neo', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
}
html { scroll-behavior: smooth; }
body {
  font-family: var(--font-body);
  color: var(--ink);
  background-color: var(--bg);
  background-image:
    linear-gradient(180deg, var(--sky) 0, rgba(207,238,255,0) 360px),
    radial-gradient(rgba(59,42,32,0.06) 1.4px, transparent 1.6px);
  background-size: 100% 100%, 22px 22px;
  background-attachment: fixed, scroll;
}
.ic { display: block; flex: none; }
::selection { background: var(--yellow); color: var(--ink); }
a { color: var(--orange-deep); }
a:hover { color: var(--ink); }
h1, h2, h3, h4, .page-title, .btn, th, .badge, .nav-link, .ng-label { font-family: var(--font-display); }

/* ── 사이드바 ── */
.sidebar {
  width: 264px;
  background: var(--paper);
  background-image: radial-gradient(rgba(59,42,32,0.05) 1.4px, transparent 1.6px);
  background-size: 20px 20px;
  color: var(--ink);
  padding: 0;
  border-right: 3px solid var(--ink);
  box-shadow: 4px 0 0 rgba(59,42,32,0.12);
  display: flex;
  flex-direction: column;
}
.sidebar { overflow: hidden; }
.sidebar a.sb-brand { display: flex; padding: 0; border: 0; background: none; }
.sidebar a.sb-brand:hover { background: none; }
.sb-head { padding: 16px 16px 10px; }
.sb-brand { display: flex; align-items: center; gap: 10px; text-decoration: none; color: var(--ink); }
.sb-brand:hover { color: var(--ink); }
.sb-logo { width: 54px; height: 54px; flex: none; border-radius: 16px; border: 2.5px solid var(--ink); background: var(--sky); box-shadow: 0 3px 0 var(--ink); display: flex; align-items: center; justify-content: center; overflow: hidden; }
.sb-logo img { width: 52px; height: auto; display: block; }
.sb-title { font-family: var(--font-display); font-size: 21px; line-height: 1.05; letter-spacing: 0.01em; color: var(--ink); }
@supports (paint-order: stroke fill) { .sb-title { color: #fff; -webkit-text-stroke: 5px var(--ink); paint-order: stroke fill; } }
.sb-sub { font-size: 11.5px; color: var(--muted); margin-top: 3px; font-weight: 500; }
.sb-search { position: relative; margin: 8px 14px 6px; }
.sb-search input { width: 100%; padding: 9px 12px 9px 34px; border-radius: 14px; border: 2px solid var(--ink); background: #fff; font-size: 13.5px; font-family: var(--font-body); color: var(--ink); outline: none; box-shadow: 0 2px 0 rgba(59,42,32,0.25); }
.sb-search input:focus { box-shadow: 0 0 0 3px rgba(255,154,31,0.35), 0 2px 0 var(--ink); }
.sb-search .ic { position: absolute; left: 10px; top: 50%; transform: translateY(-50%); }
.sb-search kbd { position: absolute; right: 9px; top: 50%; transform: translateY(-50%); font: 700 11px var(--font-body); color: var(--muted); border: 1.5px solid rgba(59,42,32,0.3); border-radius: 6px; padding: 0 5px; background: var(--cream); pointer-events: none; }
.sb-scroll { flex: 1; overflow-y: auto; padding: 4px 10px 12px; scrollbar-width: thin; }
.nav-group { margin: 6px 0; }
.nav-group > summary { list-style: none; cursor: pointer; display: flex; align-items: center; gap: 8px; padding: 8px 10px; border-radius: 12px; font-size: 13px; color: var(--muted); user-select: none; }
.nav-group > summary::-webkit-details-marker { display: none; }
.nav-group > summary:hover { background: rgba(59,42,32,0.06); color: var(--ink); }
.ng-dot { width: 11px; height: 11px; border-radius: 50%; background: var(--gc, var(--yellow)); border: 2px solid var(--ink); flex: none; }
.ng-label { flex: 1; letter-spacing: 0.04em; }
.ng-chev { transition: transform 0.18s; opacity: 0.7; }
.nav-group[open] > summary .ng-chev { transform: rotate(180deg); }
.ng-badge, .nl-badge { background: var(--red); color: #fff; border: 2px solid var(--ink); border-radius: 999px; font: 400 11px/1 var(--font-display); padding: 3px 7px 2px; min-width: 22px; text-align: center; }
.ng-items { display: flex; flex-direction: column; gap: 3px; padding: 3px 0 6px 6px; }
.sidebar a.nav-link { display: flex; align-items: center; gap: 10px; padding: 8px 10px; border-radius: 13px; border: 2px solid transparent; border-left-width: 2px; color: var(--ink); font-size: 14.5px; text-decoration: none; transition: transform 0.12s, background 0.12s; }
.sidebar a.nav-link:hover { background: var(--cream); border-color: rgba(59,42,32,0.25); color: var(--ink); transform: translateX(2px); }
.sidebar a.nav-link.active { background: var(--yellow); border-color: var(--ink); box-shadow: 0 3px 0 var(--ink); color: var(--ink); transform: none; }
.nl-ic { width: 30px; height: 30px; flex: none; display: flex; align-items: center; justify-content: center; border-radius: 10px; background: #fff; border: 2px solid rgba(59,42,32,0.55); }
.sidebar a.nav-link.active .nl-ic { border-color: var(--ink); }
.nl-t { flex: 1; min-width: 0; }
.nav-link.hidden-by-search, .nav-group.hidden-by-search { display: none; }
.sb-foot { padding: 10px 14px 14px; border-top: 2.5px dashed rgba(59,42,32,0.25); display: flex; flex-direction: column; gap: 8px; }
.sb-live { display: flex; gap: 6px; flex-wrap: wrap; }
.sb-live span { flex: 1 1 auto; text-align: center; font: 400 12px/1.2 var(--font-display); padding: 5px 8px 4px; border-radius: 10px; border: 2px solid var(--ink); background: #fff; }
.sb-live .on { background: #d6f5df; }
.sb-live .room { background: #ffe7c2; }
.sb-live .game { background: #d9ecff; }
.sidebar .logout { margin: 0; border: 0; padding: 0; }
.sidebar .logout a { display: flex; align-items: center; justify-content: center; gap: 8px; padding: 9px 12px; border-radius: 13px; border: 2px solid var(--ink); background: #fff; color: var(--ink); font: 400 14px var(--font-display); box-shadow: 0 3px 0 var(--ink); text-decoration: none; }
.sidebar a.logout-link:hover, .sidebar .logout a:hover { background: #ffe1e1; color: var(--ink); }
.menu-toggle { background: var(--yellow); color: var(--ink); border: 2.5px solid var(--ink); box-shadow: 0 3px 0 var(--ink); width: 44px; height: 44px; }
.main { margin-left: 264px; padding: 22px 28px 60px; }

/* ── 상단 바 ── */
.topbar { display: flex; align-items: center; gap: 10px; margin-bottom: 14px; flex-wrap: wrap; }
.topbar .crumb { font: 400 13px var(--font-display); color: var(--muted); display: flex; align-items: center; gap: 6px; }
.topbar .crumb b { color: var(--ink); font-weight: 400; }
.topbar .spacer { flex: 1; }
.topbar form { position: relative; }
.topbar input[type=search] { width: 240px; max-width: 60vw; padding: 9px 12px 9px 34px; border-radius: 999px; border: 2.5px solid var(--ink); background: #fff; font: 500 13.5px var(--font-body); color: var(--ink); box-shadow: 0 3px 0 var(--ink); outline: none; }
.topbar input[type=search]:focus { box-shadow: 0 3px 0 var(--ink), 0 0 0 3px rgba(255,154,31,0.4); }
.topbar form .ic { position: absolute; left: 11px; top: 50%; transform: translateY(-50%); }

/* ── 페이지 제목 ── */
.page-header { align-items: center; margin-bottom: 20px; }
.page-title { display: flex; align-items: center; gap: 12px; font-size: 32px; font-weight: 400; margin-bottom: 4px; color: var(--ink); letter-spacing: 0.01em; }
@supports (paint-order: stroke fill) { .page-title { color: #fff; -webkit-text-stroke: 7px var(--ink); paint-order: stroke fill; text-shadow: 0 4px 0 var(--ink); } }
.pt-icon { width: 46px; height: 46px; flex: none; border-radius: 15px; border: 2.5px solid var(--ink); background: #fff; box-shadow: 0 3px 0 var(--ink); display: inline-flex; align-items: center; justify-content: center; -webkit-text-stroke: 0; text-shadow: none; }
.page-subtitle { color: var(--muted); font-weight: 500; }

/* ── 패널(카드) ── */
.card, .dash-section {
  background: var(--paper);
  border: 2.5px solid var(--ink);
  border-radius: 22px;
  padding: 18px 20px 14px;
  box-shadow: 0 4px 0 var(--ink);
  margin-bottom: 18px;
}
.dash-section:first-of-type { padding-top: 18px; border-top: 2.5px solid var(--ink); }
.card .card, .dash-section .card, .card .dash-section { box-shadow: none; border-width: 2px; border-radius: 16px; background: #fff; }
.card h3 { display: inline-block; font-size: 14px; font-weight: 400; color: var(--ink); letter-spacing: 0.02em; text-transform: none; background: var(--yellow); border: 2px solid var(--ink); border-radius: 999px; padding: 3px 12px 2px; margin-bottom: 14px; }
.dash-head { margin-bottom: 14px; }
.dash-head h2 { display: inline-block; font-size: 16px; font-weight: 400; background: var(--yellow); border: 2px solid var(--ink); border-radius: 999px; padding: 3px 14px 2px; }
.dash-head .hint { color: var(--muted); font-weight: 500; }
.dash-head a { color: var(--orange-deep); font-family: var(--font-display); font-size: 13px; font-weight: 400; }
.soft-panel, .status-card { background: #fff; border: 2px solid var(--ink); border-radius: 16px; box-shadow: 0 3px 0 rgba(59,42,32,0.3); }
.status-card.warning { background: #fff0cf; border-color: var(--ink); }
.status-card.danger { background: #ffe1e1; border-color: var(--ink); }
.status-card.good { background: #dcf6e4; border-color: var(--ink); }
.chart-foldout { border: 2px solid var(--ink); border-radius: 16px; background: #fff; box-shadow: 0 3px 0 rgba(59,42,32,0.3); }
.chart-foldout > summary { font-family: var(--font-display); font-weight: 400; }
.hero-card { background: linear-gradient(135deg, #ff9a1f 0%, #ffb84d 100%); border: 3px solid var(--ink); border-radius: 26px; box-shadow: 0 5px 0 var(--ink); color: var(--ink); }
.hero-card .eyebrow, .hero-card .sub { color: rgba(59,42,32,0.75); }
.hero-meta .item { background: rgba(255,255,255,0.55); border: 2px solid var(--ink); }
.hero-meta .item .k { color: rgba(59,42,32,0.7); }
.filter-card { background: #fff; border: 2px solid var(--ink); border-radius: 18px; padding: 14px 16px 16px; box-shadow: 0 3px 0 rgba(59,42,32,0.3); }
.filter-title { font-family: var(--font-display); font-weight: 400; color: var(--ink); font-size: 13px; }
.sticky-kpi-rail { background: var(--paper); border: 2.5px solid var(--ink); border-radius: 18px; padding: 12px 16px; box-shadow: 0 4px 0 var(--ink); }

/* ── 숫자 타일 ── */
.stat-card, .summary-item, .sticky-kpi-item { background: #fff; border: 2.5px solid var(--ink); border-left: 2.5px solid var(--ink); border-radius: 18px; padding: 12px 16px; box-shadow: 0 3px 0 var(--ink); }
.stats-grid > .stat-card:first-child, .summary-strip > .summary-item:first-child { padding-left: 16px; border-left: 2.5px solid var(--ink); }
.stat-card .value, .summary-item .v, .sticky-kpi-item .v, .kpi .v, .hk-value { font-family: var(--font-display); font-weight: 400; letter-spacing: 0; }
.kpi-row { gap: 12px; }
.kpi { background: #fff; border: 2.5px solid var(--ink); border-left: 2.5px solid var(--ink); border-radius: 18px; padding: 12px 16px; box-shadow: 0 3px 0 var(--ink); }
.kpi:first-child { padding-left: 16px; }
.kpi-row > .kpi:nth-child(5n+1) { background: #fff4d0; }
.kpi-row > .kpi:nth-child(5n+2) { background: #dcf6e4; }
.kpi-row > .kpi:nth-child(5n+3) { background: #ffe7c2; }
.kpi-row > .kpi:nth-child(5n+4) { background: #d9ecff; }
.kpi-row > .kpi:nth-child(5n+5) { background: #fde0ea; }
.kpi .k { font-family: var(--font-display); color: var(--ink); opacity: 0.75; font-size: 13px; }
.hero-kpi .hero-item { background: #fff; border: 2.5px solid var(--ink); border-radius: 18px; padding: 10px 16px; box-shadow: 0 3px 0 var(--ink); }
.hero-item:first-child { padding-left: 16px; }
.hk-label { color: var(--muted); font-weight: 600; }
.delta.up, .kpi .d .up { color: #1f8a4a; }
.delta.down, .kpi .d .down { color: #d6403f; }
.delta { border: 1.5px solid var(--ink); }
.todo { background: #ffe1e1; border: 2.5px solid var(--ink); border-radius: 16px; box-shadow: 0 3px 0 var(--ink); transition: transform 0.12s; }
.todo:hover { transform: translateY(-2px); }
.todo .n { font-family: var(--font-display); font-weight: 400; color: #b3292e; font-size: 24px; }
@supports (paint-order: stroke fill) { .todo .n { color: var(--red); -webkit-text-stroke: 4px var(--ink); paint-order: stroke fill; } }
.todo .t { color: var(--ink); font-weight: 700; }
.todo-clear { display: inline-flex; align-items: center; gap: 8px; background: #dcf6e4; border: 2px solid var(--ink); border-radius: 999px; padding: 7px 14px; color: var(--ink); font-weight: 700; }
.fact { border-bottom: 2px dotted rgba(59,42,32,0.2); }
.fact .k, .metric-inline .name { color: var(--muted); font-weight: 600; }
.metric-inline { border-bottom: 2px dotted rgba(59,42,32,0.2); }
.spark .stack { border: 2px solid var(--ink); border-radius: 6px; }
.spark .n { color: var(--ink); font-weight: 700; }
.legend i { border: 1.5px solid var(--ink); border-radius: 3px; }

/* ── 표 ── */
.table-wrap, .table-responsive { border: 2.5px solid var(--ink); border-radius: 18px; box-shadow: 0 3px 0 var(--ink); background: #fff; }
th { background: var(--cream); color: var(--ink); font-weight: 400; font-size: 13px; border-bottom: 2.5px solid var(--ink); padding: 11px 14px 9px; }
th.sortable { cursor: pointer; user-select: none; }
th.sortable:hover { background: #ffe9ad; }
th.sortable::after { content: '\2195'; opacity: 0.25; margin-left: 6px; font-size: 11px; }
th.sorted-asc::after { content: '\25B2'; opacity: 0.8; }
th.sorted-desc::after { content: '\25BC'; opacity: 0.8; }
td { border-bottom: 1.5px solid rgba(59,42,32,0.12); }
tr:hover td { background: #fff6d6; }
tbody tr:nth-child(even) td { background: rgba(255,244,220,0.35); }
tbody tr:nth-child(even):hover td { background: #fff6d6; }
td a { font-weight: 700; }
.pagination a { background: #fff; color: var(--ink); border: 2px solid var(--ink); border-radius: 12px; font-family: var(--font-display); box-shadow: 0 2px 0 var(--ink); }
.pagination a:hover { background: var(--yellow); }
.pagination a.active { background: var(--orange); color: #fff; -webkit-text-stroke: 0; box-shadow: 0 2px 0 var(--ink); }

/* ── 버튼·입력 ── */
.btn { display: inline-flex; align-items: center; justify-content: center; gap: 6px; padding: 9px 18px 8px; border-radius: 999px; border: 2.5px solid var(--ink); font-size: 14px; font-weight: 400; letter-spacing: 0.01em; box-shadow: 0 3px 0 var(--ink); transition: transform 0.08s, box-shadow 0.08s, filter 0.12s; cursor: pointer; line-height: 1.2; }
.btn:hover { filter: brightness(1.06); }
.btn:active { transform: translateY(3px); box-shadow: 0 0 0 var(--ink); }
.btn-primary { background: var(--orange); color: #fff; text-shadow: 0 2px 0 rgba(59,42,32,0.55); }
.btn-primary:hover { background: var(--orange); color: #fff; }
.btn-danger { background: var(--red); color: #fff; text-shadow: 0 2px 0 rgba(59,42,32,0.55); }
.btn-danger:hover { background: var(--red); }
.btn-success { background: var(--green); color: #fff; text-shadow: 0 2px 0 rgba(59,42,32,0.55); }
.btn-success:hover { background: var(--green); }
.btn-secondary { background: #fff; color: var(--ink); }
.btn-secondary:hover { background: var(--yellow); color: var(--ink); }
button.btn[disabled], .btn.disabled { opacity: 0.5; cursor: not-allowed; box-shadow: 0 3px 0 rgba(59,42,32,0.5); }
textarea, select, input[type="date"], input[type="datetime-local"], input[type="number"], input[type="text"], input[type="password"], input[type="search"], input[type="email"], input[type="url"] {
  border: 2px solid var(--ink);
  border-radius: 14px;
  background: #fff;
  color: var(--ink);
  font-family: var(--font-body);
  font-weight: 500;
  box-shadow: 0 2px 0 rgba(59,42,32,0.25);
  outline: none;
}
textarea:focus, select:focus, input:focus { box-shadow: 0 0 0 3px rgba(255,154,31,0.4), 0 2px 0 var(--ink); border-color: var(--ink); }
input[type="checkbox"], input[type="radio"] { accent-color: var(--orange); width: 18px; height: 18px; vertical-align: middle; }
label { font-weight: 600; }
.badge { border: 2px solid var(--ink); font-weight: 400; font-size: 12px; padding: 2px 10px 1px; }
.badge-pending { background: #ffe7c2; color: var(--ink); }
.badge-resolved { background: #d6f5df; color: var(--ink); }
.badge-reviewed { background: #d9ecff; color: var(--ink); }
.badge-bug { background: #ffd9d9; color: var(--ink); }
.badge-suggestion { background: #e1e6ff; color: var(--ink); }
.badge-payment { background: #ffe7c2; color: var(--ink); }
.badge-other { background: #f1defc; color: var(--ink); }
.subtab-link, .preset-link { background: #fff; color: var(--ink); border: 2px solid var(--ink); border-radius: 999px; font-family: var(--font-display); font-weight: 400; box-shadow: 0 2px 0 var(--ink); }
.subtab-link:hover, .preset-link:hover { background: var(--cream); color: var(--ink); }
.subtab-link.active, .preset-link.active { background: var(--orange); color: #fff; border-color: var(--ink); box-shadow: 0 2px 0 var(--ink); text-shadow: 0 2px 0 rgba(59,42,32,0.5); }
.progress { background: #fff; border: 2px solid var(--ink); height: 12px; }
.progress > span { background: linear-gradient(90deg, var(--green), #7ddc8f); border-right: 2px solid var(--ink); }
.chat-log { background: #fff; border: 2px solid var(--ink); border-radius: 16px; }
.empty { color: var(--muted); font-weight: 600; }
div.empty { background: #fff; border: 2.5px dashed rgba(59,42,32,0.35); border-radius: 18px; padding: 34px 20px; }
td.empty { padding: 26px 14px; }
div.empty::before { content: ''; display: block; width: 84px; height: 84px; margin: 0 auto 10px; background: url('/tc-backstage/_a/dragon_full.webp') center/contain no-repeat; opacity: 0.9; }
details > summary { cursor: pointer; }
hr { border: none; border-top: 2.5px dashed rgba(59,42,32,0.25); margin: 16px 0; }
code, .mono { background: rgba(59,42,32,0.07); border-radius: 6px; padding: 0 5px; }
.detail-grid .label { font-family: var(--font-display); font-weight: 400; color: var(--muted); }

/* ── 대시보드 첫 화면 ── */
.dash-hero { display: grid; grid-template-columns: auto 1fr; gap: 6px 18px; align-items: center; background: linear-gradient(135deg, #ffe08a 0%, #ffb84d 100%); border: 3px solid var(--ink); border-radius: 26px; box-shadow: 0 5px 0 var(--ink); padding: 14px 20px 18px; margin-bottom: 18px; position: relative; overflow: hidden; }
.dash-hero > img { width: 112px; height: 112px; object-fit: contain; filter: drop-shadow(0 4px 0 rgba(59,42,32,0.3)); animation: dh-float 3.4s ease-in-out infinite; }
@keyframes dh-float { 0%,100% { transform: translateY(0) } 50% { transform: translateY(-6px) } }
.dh-hello { font: 400 24px var(--font-display); display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
.dh-line { margin-top: 4px; font-weight: 700; font-size: 14px; color: rgba(59,42,32,0.8); }
.state-pill { font: 400 13px var(--font-display); padding: 3px 11px 2px; border-radius: 999px; border: 2px solid var(--ink); background: #fff; }
.state-pill.ok { background: #d6f5df; } .state-pill.warn { background: #fff0cf; } .state-pill.bad { background: #ffd9d9; }
.quick-grid { grid-column: 1 / -1; display: grid; grid-template-columns: repeat(auto-fill, minmax(112px, 1fr)); gap: 10px; margin-top: 6px; }
.quick { display: flex; flex-direction: column; align-items: center; gap: 6px; padding: 10px 6px 9px; background: #fff; border: 2.5px solid var(--ink); border-radius: 18px; box-shadow: 0 3px 0 var(--ink); text-decoration: none; color: var(--ink); transition: transform 0.1s, box-shadow 0.1s; }
.quick:hover { transform: translateY(-2px); box-shadow: 0 5px 0 var(--ink); color: var(--ink); }
.quick:active { transform: translateY(3px); box-shadow: 0 0 0 var(--ink); }
.quick-t { font: 400 13.5px var(--font-display); text-align: center; }
.todo { display: inline-flex; align-items: center; gap: 10px; }
.todo-ic { display: inline-flex; }
@media (max-width: 768px) {
  .dash-hero { grid-template-columns: 1fr; text-align: center; }
  .dash-hero > img { margin: 0 auto; width: 92px; height: 92px; }
  .dh-hello { justify-content: center; font-size: 20px; }
  .quick-grid { grid-template-columns: repeat(auto-fill, minmax(92px, 1fr)); }
}

/* ── 복사 알림 ── */
code, .mono { cursor: copy; }
.copy-toast { position: fixed; left: 50%; bottom: 28px; transform: translate(-50%, 20px); opacity: 0; pointer-events: none; background: var(--ink); color: #fff; font: 400 14px var(--font-display); padding: 9px 18px 8px; border-radius: 999px; border: 2.5px solid var(--ink); box-shadow: 0 3px 0 rgba(59,42,32,0.35); transition: opacity 0.18s, transform 0.18s; z-index: 300; }
.copy-toast.show { opacity: 1; transform: translate(-50%, 0); }

/* ── 맨 위로 ── */
.to-top { position: fixed; right: 18px; bottom: 18px; width: 46px; height: 46px; border-radius: 50%; border: 2.5px solid var(--ink); background: var(--yellow); box-shadow: 0 3px 0 var(--ink); display: none; align-items: center; justify-content: center; cursor: pointer; z-index: 80; padding: 0; }
.to-top.show { display: flex; }
.to-top:active { transform: translateY(3px); box-shadow: none; }

/* ── 반응형 ── */
@media (max-width: 768px) {
  .sidebar { width: min(86vw, 330px); padding-top: 0; }
  .menu-toggle { display: flex; align-items: center; justify-content: center; padding: 0; }
  .main { padding: 14px 12px 60px; padding-top: 66px; }
  .page-title { font-size: 24px; }
  @supports (paint-order: stroke fill) { .page-title { -webkit-text-stroke: 5px var(--ink); } }
  .pt-icon { width: 38px; height: 38px; border-radius: 12px; }
  .pt-icon .ic { width: 22px; height: 22px; }
  .card, .dash-section { padding: 14px 14px 10px; border-radius: 18px; }
  .topbar input[type=search] { width: 100%; max-width: 100%; }
  .topbar form { flex: 1 1 100%; }
  .topbar .crumb { display: none; }
  .kpi { padding: 10px 12px; }
  .stat-card, .summary-item { padding: 10px 12px; }
  .hero-item { border-left: 2.5px solid var(--ink); }
  .hero-item:nth-child(odd) { border-left: 2.5px solid var(--ink); padding-left: 12px; }
  .table-wrap { border-radius: 14px; }
}
@media (prefers-reduced-motion: reduce) { * { transition: none !important; scroll-behavior: auto !important; } }
`;

// ───────────────────────────── 페이지 뼈대 ─────────────────────────────
const FONT_LINKS = `<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Jua&family=Noto+Sans+KR:wght@400;500;700&display=swap" rel="stylesheet">`;

const SHELL_JS = `
function closeSidebar(){var s=document.querySelector('.sidebar'),o=document.querySelector('.sidebar-overlay');if(s)s.classList.remove('open');if(o)o.classList.remove('open')}
function toggleSidebar(){document.querySelector('.sidebar').classList.toggle('open');document.querySelector('.sidebar-overlay').classList.toggle('open')}
(function(){
  var KEY='tcAdminNavOpen';
  var store={};try{store=JSON.parse(localStorage.getItem(KEY)||'{}')}catch(e){}
  var groups=document.querySelectorAll('.nav-group');
  groups.forEach(function(g){
    var id=g.getAttribute('data-group');
    if(!g.hasAttribute('data-active')&&store[id]===true)g.open=true;
    g.addEventListener('toggle',function(){
      if(g.getAttribute('data-searching'))return;
      store[id]=g.open;try{localStorage.setItem(KEY,JSON.stringify(store))}catch(e){}
    });
  });
  var q=document.getElementById('sb-q');
  function filter(){
    var v=(q.value||'').trim().toLowerCase();
    groups.forEach(function(g){
      var any=false;
      g.querySelectorAll('.nav-link').forEach(function(a){
        var hit=!v||a.getAttribute('data-label').toLowerCase().indexOf(v)>=0;
        a.classList.toggle('hidden-by-search',!hit);if(hit)any=true;
      });
      g.classList.toggle('hidden-by-search',!any);
      if(v){g.setAttribute('data-searching','1');g.open=any}else{g.removeAttribute('data-searching');g.open=g.hasAttribute('data-active')||store[g.getAttribute('data-group')]===true}
    });
  }
  if(q){
    q.addEventListener('input',filter);
    q.addEventListener('keydown',function(e){
      if(e.key==='Escape'){q.value='';filter();q.blur()}
      if(e.key==='Enter'){var a=document.querySelector('.nav-link:not(.hidden-by-search)');if(a&&q.value.trim())location.href=a.getAttribute('href')}
    });
    document.addEventListener('keydown',function(e){
      var t=e.target&&e.target.tagName;
      if(e.key==='/'&&t!=='INPUT'&&t!=='TEXTAREA'&&t!=='SELECT'&&!e.metaKey&&!e.ctrlKey){e.preventDefault();q.focus();q.select()}
    });
  }
  var act=document.querySelector('.nav-link.active');
  if(act&&act.scrollIntoView){try{act.scrollIntoView({block:'center'})}catch(e){}}
  // 맨 위로
  var top=document.getElementById('to-top');
  if(top){
    window.addEventListener('scroll',function(){top.classList.toggle('show',window.scrollY>600)},{passive:true});
    top.addEventListener('click',function(){window.scrollTo({top:0,behavior:'smooth'})});
  }
  // 고정폭 값(코드·ID·영수증 번호)을 누르면 복사한다
  var toast=document.getElementById('copy-toast'),toastT=null;
  document.addEventListener('click',function(e){
    var el=e.target.closest&&e.target.closest('code, .mono');
    if(!el||el.closest('a, button, input, textarea')||!navigator.clipboard)return;
    var sel=window.getSelection&&window.getSelection().toString();
    if(sel)return;
    var text=(el.textContent||'').trim();
    if(!text||text.length>300)return;
    navigator.clipboard.writeText(text).then(function(){
      if(!toast)return;
      toast.classList.add('show');clearTimeout(toastT);
      toastT=setTimeout(function(){toast.classList.remove('show')},1300);
    }).catch(function(){});
  });
  // 표 머리글을 눌러 정렬(머리글 한 줄, 병합 칸 없음, 본문 3줄 이상인 표만)
  function cellVal(td){
    var t=(td.getAttribute('data-sort')||td.textContent||'').trim();
    var n=parseFloat(t.replace(/[,₩%원판명점\\s]/g,''));
    return {t:t.toLowerCase(),n:isNaN(n)?null:n,raw:t};
  }
  document.querySelectorAll('.table-wrap table, .table-responsive table').forEach(function(tb){
    try{
      if(tb.hasAttribute('data-nosort'))return;
      var rows=[].slice.call(tb.querySelectorAll('tr'));
      var head=rows.filter(function(r){return r.querySelector('th')});
      if(head.length!==1||head[0]!==rows[0])return;
      var body=rows.slice(1);
      if(body.length<3)return;
      if(tb.querySelector('[rowspan],[colspan]'))return;
      var ths=[].slice.call(head[0].children);
      ths.forEach(function(th,ci){
        if(!th.textContent.trim()||th.classList.contains('nosort'))return;
        th.classList.add('sortable');
        th.addEventListener('click',function(){
          var asc=!th.classList.contains('sorted-asc');
          ths.forEach(function(x){x.classList.remove('sorted-asc','sorted-desc')});
          th.classList.add(asc?'sorted-asc':'sorted-desc');
          var parent=body[0].parentNode;
          var data=body.map(function(r){return {r:r,v:cellVal(r.children[ci]||r)}});
          var numeric=data.every(function(d){return d.v.n!==null||d.v.raw===''||d.v.raw==='-'});
          data.sort(function(a,b){
            var c=numeric?((a.v.n===null?-Infinity:a.v.n)-(b.v.n===null?-Infinity:b.v.n)):a.v.t.localeCompare(b.v.t,'ko');
            return asc?c:-c;
          });
          data.forEach(function(d){parent.appendChild(d.r)});
        });
      });
    }catch(e){}
  });
})();
`;

/**
 * @param {object} o
 * @param {string} o.title
 * @param {string} o.content   페이지 본문 HTML
 * @param {string} o.activePage 메뉴 key
 * @param {number} o.pendingDeposits
 * @param {object} o.badges    { inquiries, reports, deposits }
 * @param {object} o.live      { users, rooms, games } 접속 현황(없으면 숨김)
 */
function renderLayout({ title, content, activePage = '', pendingDeposits = 0, badges = {}, live = null }) {
  const b = { ...badges };
  if (pendingDeposits > 0) b.deposits = pendingDeposits;
  const activeItem = NAV_GROUPS.flatMap((g) => g.items.map((it) => ({ ...it, group: g.label }))).find((it) => it.key === activePage);
  const pageIcon = PAGE_ICONS[activePage];
  let body = content;
  if (pageIcon && body.includes('<h1 class="page-title">')) {
    body = body.replace('<h1 class="page-title">', `<h1 class="page-title"><span class="pt-icon">${icon(pageIcon, 28)}</span><span>`).replace('</h1>', '</span></h1>');
  }
  const liveHtml = live
    ? `<div class="sb-live" title="이 페이지를 연 시점의 값"><span class="on">접속 ${live.users}</span><span class="room">방 ${live.rooms}</span><span class="game">게임 ${live.games}</span></div>`
    : '';
  return `<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${title} - Tichu Admin</title>
<link rel="icon" type="image/webp" href="/tc-backstage/_a/dragon_icon.webp">
${FONT_LINKS}
<style>
${BASE_CSS}
${THEME_CSS}
</style>
</head>
<body>
<button class="menu-toggle" onclick="toggleSidebar()" aria-label="메뉴">${icon('menu', 24)}</button>
<div class="sidebar-overlay" onclick="closeSidebar()"></div>
<nav class="sidebar">
  <div class="sb-head">
    <a href="/tc-backstage/" class="sb-brand" onclick="closeSidebar()">
      <span class="sb-logo"><img src="/tc-backstage/_a/dragon_head.webp" alt=""></span>
      <span><div class="sb-title">Tichu Admin</div><div class="sb-sub">운영 대시보드</div></span>
    </a>
  </div>
  <div class="sb-search">${icon('search', 18)}<input id="sb-q" type="text" placeholder="메뉴 찾기" autocomplete="off"><kbd>/</kbd></div>
  <div class="sb-scroll">${renderNav(activePage, b)}</div>
  <div class="sb-foot">
    ${liveHtml}
    <div class="logout"><a href="/tc-backstage/logout">${icon('logout', 18)}로그아웃</a></div>
  </div>
</nav>
<main class="main">
  <div class="topbar">
    <div class="crumb">${activeItem ? `${activeItem.group} <span>›</span> <b>${activeItem.label}</b>` : ''}</div>
    <div class="spacer"></div>
    <form action="/tc-backstage/users" method="get" role="search">${icon('search', 18)}<input type="search" name="q" placeholder="유저 닉네임 검색" autocomplete="off"></form>
  </div>
  <div class="page-shell">
${body}
  </div>
</main>
<button class="to-top" id="to-top" aria-label="맨 위로">${icon('top', 22)}</button>
<div class="copy-toast" id="copy-toast">복사했어요!</div>
<script>${SHELL_JS}</script>
</body>
</html>`;
}

// ───────────────────────────── 로그인 ─────────────────────────────
function renderLoginPage(error = '') {
  return `<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Admin Login - Tichu</title>
<link rel="icon" type="image/webp" href="/tc-backstage/_a/dragon_icon.webp">
${FONT_LINKS}
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
:root { --ink: #3b2a20; --cream: #fff4dc; --paper: #fffbf2; --orange: #ff9a1f; --yellow: #ffd43b; --red: #ff5a5f; }
body { font-family: 'Noto Sans KR', 'Apple SD Gothic Neo', -apple-system, sans-serif; color: var(--ink); min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 20px;
  background-color: #fff1d6;
  background-image: linear-gradient(180deg, #9adcff 0, #cfeeff 38%, #fff1d6 100%), radial-gradient(rgba(59,42,32,0.07) 1.4px, transparent 1.6px);
  background-size: 100% 100%, 22px 22px; }
.stage { width: 380px; max-width: 100%; text-align: center; }
.mascot { width: 190px; margin: 0 auto -34px; position: relative; z-index: 2; animation: float 3.2s ease-in-out infinite; filter: drop-shadow(0 6px 0 rgba(59,42,32,0.25)); }
@keyframes float { 0%,100% { transform: translateY(0) } 50% { transform: translateY(-8px) } }
.login-box { background: var(--paper); border: 3px solid var(--ink); border-radius: 28px; padding: 46px 28px 26px; box-shadow: 0 6px 0 var(--ink); position: relative; }
h2 { font-family: 'Jua', 'Noto Sans KR', sans-serif; font-weight: 400; font-size: 30px; color: var(--ink); margin-bottom: 4px; }
@supports (paint-order: stroke fill) { h2 { color: #fff; -webkit-text-stroke: 7px var(--ink); paint-order: stroke fill; text-shadow: 0 4px 0 var(--ink); } }
.sub { color: #8a7565; font-size: 13px; font-weight: 500; margin-bottom: 20px; }
input { width: 100%; padding: 13px 16px; border: 2.5px solid var(--ink); border-radius: 16px; font-size: 15px; font-family: inherit; font-weight: 500; margin-bottom: 12px; background: #fff; color: var(--ink); box-shadow: 0 3px 0 rgba(59,42,32,0.25); outline: none; }
input:focus { box-shadow: 0 0 0 4px rgba(255,154,31,0.4), 0 3px 0 var(--ink); }
button { width: 100%; margin-top: 4px; padding: 13px; background: var(--orange); color: #fff; border: 3px solid var(--ink); border-radius: 999px; font: 400 20px 'Jua', 'Noto Sans KR', sans-serif; letter-spacing: 0.02em; text-shadow: 0 2px 0 rgba(59,42,32,0.55); cursor: pointer; box-shadow: 0 4px 0 var(--ink); transition: transform 0.08s, box-shadow 0.08s; }
button:hover { filter: brightness(1.06); }
button:active { transform: translateY(4px); box-shadow: 0 0 0 var(--ink); }
.error { color: #b3292e; background: #ffe1e1; border: 2px solid var(--ink); border-radius: 14px; font-size: 13px; font-weight: 700; padding: 9px 12px; margin-bottom: 12px; }
</style>
</head>
<body>
<div class="stage">
  <img class="mascot" src="/tc-backstage/_a/dragon_full.webp" alt="">
  <form class="login-box" method="POST" action="/tc-backstage/login">
    <h2>Tichu Admin</h2>
    <div class="sub">운영자 전용 · 로그인이 필요해요</div>
    ${error ? `<div class="error">${error}</div>` : ''}
    <input type="text" name="username" placeholder="아이디" required autofocus autocomplete="username">
    <input type="password" name="password" placeholder="비밀번호" required autocomplete="current-password">
    <button type="submit">로그인</button>
  </form>
</div>
</body>
</html>`;
}

module.exports = { renderLayout, renderLoginPage, icon, NAV_GROUPS, ICON_BODIES };
