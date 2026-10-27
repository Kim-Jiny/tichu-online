/**
 * Crawlable pages: /rules, /rules/<game>, /guide and /guide/<slug>.
 *
 * The game itself is a Flutter canvas, so a search engine sees one page with a
 * paragraph of text on it. These are the pages that carry real prose. The text
 * lives in content/rules/*.md and content/guide/*.md (the source of truth,
 * written against the game engines) and is rendered here at request time into plain server HTML — no
 * JS needed to read it, which is the whole point.
 *
 * Besides that subset, a line `![설명](이름)` becomes a captioned figure (image
 * lives in content/img/<이름>.webp, served at /seo-img/) and `> 문장` becomes a
 * highlighted tip box.
 *
 * Each file ends with a "*메타 태그용*" block holding Title / Description; that
 * block feeds <title>/<meta> and is never rendered into the body. The FAQ
 * section ("**질문?** 답") also becomes FAQPage JSON-LD.
 */

const fs = require('fs');
const path = require('path');

// Deliberately NOT INVITE_BASE_URL: that one is a deploy knob that can still
// point at the old host during a domain move (docs/DOMAIN_MIGRATION.md), and a
// canonical/og:url that follows it would tell search engines the wrong site is
// the original. The address to rank is tichu.kr.
const BASE_URL = process.env.SEO_BASE_URL || 'https://tichu.kr';
const RULES_DIR = path.join(__dirname, 'content', 'rules');
const GUIDE_DIR = path.join(__dirname, 'content', 'guide');
const IMG_DIR = path.join(__dirname, 'content', 'img');
const IMG_PATH = '/seo-img/';
// Every figure is exported at this size; width/height reserve its space so the
// page does not jump when the picture arrives.
const FIG_W = 960;
const FIG_H = 640;

const GAMES = [
  { slug: 'tichu', thumb: 'tichu_thumb', name: '티츄', blurb: '4인 2:2 팀전. 손패를 가장 먼저 비우는 경주' },
  { slug: 'mighty', thumb: 'mighty_thumb', name: '마이티', blurb: '5인 트릭테이킹. 숨은 프렌드와 경매(비딩)' },
  { slug: 'skullking', thumb: 'sk_thumb', name: '스컬킹', blurb: '해적 테마 예측 트릭테이킹. 약속한 만큼만 따내기' },
  { slug: 'loveletter', thumb: 'll_thumb', name: '러브레터', blurb: '카드 16장으로 하는 추리·블러핑 게임' },
];

// Topic pages, one search intent each. `game` ties a guide to its rules page.
const GUIDES = [
  { slug: 'mighty-friend', game: 'mighty', name: '마이티 프렌드 지명 방법', blurb: '카드 지목·조커·초구·노프렌드, 언제 무엇을 고를까' },
  { slug: 'mighty-joker', game: 'mighty', name: '마이티 조커와 조커콜', blurb: '조커가 힘을 못 쓰는 때와 조커콜을 막는 법' },
  { slug: 'mighty-score', game: 'mighty', name: '마이티 점수 계산', blurb: '공식과 계산 예시 여섯 개' },
  { slug: 'skullking-score', game: 'skullking', name: '스컬킹 점수 계산', blurb: '예측, 0 예측, 보너스 예시' },
  { slug: 'loveletter-cards', game: 'loveletter', name: '러브레터 카드 16장 정리', blurb: '숫자·장수·효과를 한눈에' },
  { slug: 'tichu-bomb', game: 'tichu', name: '티츄 특수 카드와 폭탄', blurb: '참새·개·봉황·용과 폭탄 순위' },
  { slug: 'tichu-score', game: 'tichu', name: '티츄 점수 계산', blurb: '카드 점수·꼴찌 규칙·원투·티츄 선언 예시' },
  { slug: 'skullking-expansion', game: 'skullking', name: '스컬킹 확장 카드와 해적 능력', blurb: '크라켄·흰고래·보물·해적 능력 모드' },
  { slug: 'mighty-glossary', game: 'mighty', name: '마이티 용어 사전', blurb: '주공·프렌드·기루다·백런 뜻' },
  { slug: 'tichu-glossary', game: 'tichu', name: '티츄 용어 사전', blurb: '선·폭탄·소원·그랜드 티츄·원투 뜻' },
  { slug: 'skullking-glossary', game: 'skullking', name: '스컬킹 용어 사전', blurb: '예측·리드 무늬·도주·티그리스·크라켄 뜻' },
];

function esc(s) {
  return String(s)
    .replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;').replaceAll("'", '&#39;');
}

/// Inline: **bold**, *italic*, <https://autolink>. Escapes first, so nothing in
/// the source can inject markup.
function inline(raw) {
  return esc(raw)
    .replace(/&lt;(https?:\/\/[^\s&]+)&gt;/g, '<a href="$1">$1</a>')
    .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
    .replace(/\*(.+?)\*/g, '<em>$1</em>');
}

/// The tiny markdown subset these files use: # / ## headings, paragraphs,
/// ### headings, "- " lists. Returns the rendered body and the parsed meta + FAQ.
function parse(md) {
  const parts = md.split(/\n---\n/);
  const metaBlock = parts.length > 1 ? parts[parts.length - 1] : '';
  const bodyMd = parts.length > 1 ? parts.slice(0, -1).join('\n---\n') : md;

  const meta = {};
  for (const m of metaBlock.matchAll(/^- (Title|Description|English):\s*(.+)$/gm)) {
    meta[m[1].toLowerCase()] = m[2].trim();
  }

  const out = [];
  const faq = [];
  let h1 = '';
  let list = null;
  let inFaq = false;
  const flush = () => { if (list) { out.push(`<ul>${list.join('')}</ul>`); list = null; } };

  for (const line of bodyMd.split('\n')) {
    const t = line.trim();
    if (!t) { flush(); continue; }
    if (t.startsWith('# ')) { h1 = t.slice(2); continue; }
    if (t.startsWith('### ')) {
      flush();
      out.push(`<h3>${inline(t.slice(4))}</h3>`);
      continue;
    }
    if (t.startsWith('## ')) {
      flush();
      inFaq = t.includes('자주 묻는');
      out.push(`<h2>${inline(t.slice(3))}</h2>`);
      continue;
    }
    if (t.startsWith('- ')) {
      (list ||= []).push(`<li>${inline(t.slice(2))}</li>`);
      continue;
    }
    flush();
    const img = t.match(/^!\[(.+?)\]\(([a-z0-9_]+)\)$/);
    if (img) {
      out.push(`<figure><img src="${IMG_PATH}${img[2]}.webp" alt="${esc(img[1])}" width="${FIG_W}" height="${FIG_H}" loading="lazy" decoding="async">`
        + `<figcaption>${esc(img[1])}</figcaption></figure>`);
      continue;
    }
    if (t.startsWith('> ')) {
      out.push(`<p class="tip">${inline(t.slice(2))}</p>`);
      continue;
    }
    if (inFaq) {
      const q = t.match(/^\*\*(.+?\?)\*\*\s*(.+)$/);
      if (q) faq.push({ q: q[1], a: q[2].replace(/<(https?:\/\/[^\s>]+)>/g, '$1').replace(/\*\*?/g, '') });
    }
    out.push(`<p>${inline(t)}</p>`);
  }
  flush();
  return { h1, body: out.join('\n'), meta, faq };
}

const cache = new Map();
function load(dir, slug) {
  const key = `${dir}/${slug}`;
  if (cache.has(key)) return cache.get(key);
  let page = null;
  try {
    page = parse(fs.readFileSync(path.join(dir, `${slug}.md`), 'utf8'));
  } catch (_) { /* missing file → 404 */ }
  cache.set(key, page);
  return page;
}

const THEMES = { tichu: '#e8731a', mighty: '#2f6fd6', skullking: '#1f6b8f', loveletter: '#c9306d' };

const CSS = `:root{--accent:#e8731a}`
  + `body{margin:0;background:#fdf8f3;color:#143a57;`
  + `font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Noto Sans KR','Apple SD Gothic Neo',sans-serif;line-height:1.8}`
  + `.band{height:10px;background:var(--accent)}`
  + `.wrap{max-width:720px;margin:0 auto;padding:24px 22px 80px}`
  + `.nav{font-size:14px;margin:0 0 28px}.nav a{color:var(--accent);text-decoration:none;margin-right:14px;font-weight:700}`
  + `h1{font-size:27px;line-height:1.4;margin:0 0 18px}`
  + `h2{font-size:20px;margin:40px 0 10px;color:#143a57;padding-left:12px;border-left:6px solid var(--accent)}`
  + `h3{font-size:17px;margin:24px 0 6px}`
  + `p{margin:0 0 14px}strong{color:#143a57}a{color:var(--accent)}ul{padding-left:20px}`
  + `figure{margin:22px 0}figure img{display:block;width:100%;height:auto;border:2.5px solid #143a57;border-radius:18px;`
  + `box-shadow:0 4px 0 #143a57;background:#fff}`
  + `figcaption{font-size:13px;opacity:.65;text-align:center;margin-top:10px}`
  + `.tip{background:#fff;border:2px solid #143a57;border-left:8px solid var(--accent);border-radius:12px;padding:12px 16px;font-weight:600}`
  + `.cta{display:inline-block;margin:28px 0 8px;padding:14px 26px;background:var(--accent);color:#fff;`
  + `border-radius:14px;text-decoration:none;font-weight:700;border:2.5px solid #143a57;box-shadow:0 4px 0 #143a57}`
  + `.games{list-style:none;padding:0}.games li{margin:0 0 14px;padding:12px;background:#fff;border:2px solid #143a57;`
  + `border-radius:14px;box-shadow:0 3px 0 #143a57;display:flex;gap:14px;align-items:center}`
  + `.games img{width:84px;height:84px;border-radius:12px;flex:none;border:2px solid #143a57}`
  + `.games a{font-weight:700;font-size:18px}.foot{margin-top:48px;font-size:13px;opacity:.7}`;

function shell({ title, description, canonical, jsonld, inner, theme }) {
  const accent = THEMES[theme];
  return `<!DOCTYPE html><html lang="ko"><head><meta charset="utf-8">`
    + `<meta name="viewport" content="width=device-width, initial-scale=1">`
    + `<title>${esc(title)}</title><meta name="description" content="${esc(description)}">`
    + `<link rel="canonical" href="${esc(canonical)}">`
    + `<meta property="og:type" content="article"><meta property="og:site_name" content="Tichu Online">`
    + `<meta property="og:title" content="${esc(title)}"><meta property="og:description" content="${esc(description)}">`
    + `<meta property="og:url" content="${esc(canonical)}"><meta property="og:image" content="${BASE_URL}/share-banner.jpg">`
    + `<meta property="og:image:width" content="1200"><meta property="og:image:height" content="569">`
    + `<meta property="og:locale" content="ko_KR">`
    + `<meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="${esc(title)}">`
    + `<meta name="twitter:description" content="${esc(description)}"><meta name="twitter:image" content="${BASE_URL}/share-banner.jpg">`
    + `<link rel="icon" type="image/png" href="/favicon.png">`
    + (jsonld ? `<script type="application/ld+json">${JSON.stringify(jsonld).replaceAll('<', '\\u003c')}</script>` : '')
    + `<style>${CSS}${accent ? `:root{--accent:${accent}}` : ''}</style></head><body><div class="band"></div><div class="wrap">`
    + `<div class="nav"><a href="/">Tichu Online</a><a href="/rules">룰 가이드</a><a href="/guide">공략·계산</a></div>`
    + inner
    + `<p class="foot">© Tichu Online · <a href="/support?lang=ko">고객센터</a></p>`
    + `</div></body></html>`;
}

function renderGame(slug) {
  const game = GAMES.find((g) => g.slug === slug);
  const page = game && load(RULES_DIR, slug);
  if (!page) return null;
  const canonical = `${BASE_URL}/rules/${slug}`;
  const title = page.meta.title || `${game.name} 룰 | Tichu Online`;
  const description = page.meta.description || game.blurb;
  const jsonld = [
    {
      '@context': 'https://schema.org', '@type': 'Article',
      headline: page.h1, description, inLanguage: 'ko', mainEntityOfPage: canonical,
      image: `${BASE_URL}/share-banner.jpg`,
      author: { '@type': 'Organization', name: 'Tichu Online', url: `${BASE_URL}/` },
      publisher: { '@type': 'Organization', name: 'Tichu Online', url: `${BASE_URL}/` },
    },
    {
      '@context': 'https://schema.org', '@type': 'BreadcrumbList',
      itemListElement: [
        { '@type': 'ListItem', position: 1, name: 'Tichu Online', item: `${BASE_URL}/` },
        { '@type': 'ListItem', position: 2, name: '룰 가이드', item: `${BASE_URL}/rules` },
        { '@type': 'ListItem', position: 3, name: `${game.name} 룰`, item: canonical },
      ],
    },
  ];
  if (page.faq.length) {
    jsonld.push({
      '@context': 'https://schema.org', '@type': 'FAQPage',
      mainEntity: page.faq.map((f) => ({
        '@type': 'Question', name: f.q, acceptedAnswer: { '@type': 'Answer', text: f.a },
      })),
    });
  }
  const others = GAMES.filter((g) => g.slug !== slug)
    .map((g) => `<a href="/rules/${g.slug}">${esc(g.name)} 룰</a>`).join(' · ');
  const related = GUIDES.filter((g) => g.game === slug);
  const relatedHtml = related.length
    ? `<h2>더 깊이 보기</h2><ul>${related.map((g) => `<li><a href="/guide/${g.slug}">${esc(g.name)}</a> — ${esc(g.blurb)}</li>`).join('')}</ul>`
    : '';
  const inner = `<h1>${esc(page.h1)}</h1>${page.body}${relatedHtml}`
    + `<a class="cta" href="/">🎮 ${esc(game.name)} 지금 플레이하기</a>`
    + `<p>설치 없이 브라우저에서 바로 시작할 수 있어요. 다른 게임 룰: ${others}</p>`;
  return shell({ title, description, canonical, jsonld, inner, theme: slug });
}

function renderGuide(slug) {
  const guide = GUIDES.find((g) => g.slug === slug);
  const page = guide && load(GUIDE_DIR, slug);
  if (!page) return null;
  const game = GAMES.find((g) => g.slug === guide.game);
  const canonical = `${BASE_URL}/guide/${slug}`;
  const title = page.meta.title || `${guide.name} | Tichu Online`;
  const description = page.meta.description || guide.blurb;
  const jsonld = [
    {
      '@context': 'https://schema.org', '@type': 'Article',
      headline: page.h1, description, inLanguage: 'ko', mainEntityOfPage: canonical,
      image: `${BASE_URL}/share-banner.jpg`,
      author: { '@type': 'Organization', name: 'Tichu Online', url: `${BASE_URL}/` },
      publisher: { '@type': 'Organization', name: 'Tichu Online', url: `${BASE_URL}/` },
    },
    {
      '@context': 'https://schema.org', '@type': 'BreadcrumbList',
      itemListElement: [
        { '@type': 'ListItem', position: 1, name: 'Tichu Online', item: `${BASE_URL}/` },
        { '@type': 'ListItem', position: 2, name: '공략·계산', item: `${BASE_URL}/guide` },
        { '@type': 'ListItem', position: 3, name: guide.name, item: canonical },
      ],
    },
  ];
  if (page.faq.length) {
    jsonld.push({
      '@context': 'https://schema.org', '@type': 'FAQPage',
      mainEntity: page.faq.map((f) => ({
        '@type': 'Question', name: f.q, acceptedAnswer: { '@type': 'Answer', text: f.a },
      })),
    });
  }
  const siblings = GUIDES.filter((g) => g.game === guide.game && g.slug !== slug);
  const more = siblings.length
    ? `<p>같이 보면 좋은 글: ${siblings.map((g) => `<a href="/guide/${g.slug}">${esc(g.name)}</a>`).join(' · ')}</p>`
    : '';
  const inner = `<h1>${esc(page.h1)}</h1>${page.body}`
    + `<p>${esc(game.name)} 전체 규칙은 <a href="/rules/${game.slug}">${esc(game.name)} 룰 완전 정리</a>에 있어요.</p>${more}`
    + `<a class="cta" href="/">🎮 ${esc(game.name)} 지금 플레이하기</a>`
    + `<p>설치 없이 브라우저에서 바로 시작할 수 있어요.</p>`;
  return shell({ title, description, canonical, jsonld, inner, theme: guide.game });
}

function renderGuideIndex() {
  const items = GUIDES.map((g) => {
    const game = GAMES.find((x) => x.slug === g.game);
    return `<li><img src="${IMG_PATH}${game.thumb}.webp" alt="${esc(game.name)}" width="84" height="84" loading="lazy">`
      + `<div><a href="/guide/${g.slug}">${esc(g.name)}</a><br>${esc(g.blurb)}</div></li>`;
  }).join('');
  const title = '카드게임 공략·점수 계산 가이드 — 마이티 · 스컬킹 · 러브레터 · 티츄 | Tichu Online';
  const description = '마이티 프렌드 지명, 조커콜, 점수 계산부터 스컬킹 점수, 러브레터 카드 정리, 티츄 폭탄까지 궁금한 부분만 골라 읽을 수 있는 가이드 모음이에요.';
  const inner = `<h1>공략·점수 계산 가이드</h1>`
    + `<p>규칙 전체를 읽기엔 부담스러울 때, 궁금한 부분만 골라 보세요. 전체 규칙은 <a href="/rules">룰 가이드</a>에 있어요.</p>`
    + `<ul class="games">${items}</ul><a class="cta" href="/">🎮 지금 플레이하기</a>`;
  return shell({ title, description, canonical: `${BASE_URL}/guide`, inner });
}

function renderIndex() {
  const items = GAMES.map((g) => `<li><img src="${IMG_PATH}${g.thumb}.webp" alt="${esc(g.name)} 룰" width="84" height="84" loading="lazy">`
    + `<div><a href="/rules/${g.slug}">${esc(g.name)} 룰 쉽게 배우기</a><br>${esc(g.blurb)}</div></li>`).join('');
  const title = '카드게임 룰 가이드 — 티츄 · 마이티 · 스컬킹 · 러브레터 | Tichu Online';
  const description = '티츄, 마이티, 스컬킹, 러브레터의 규칙을 이야기하듯 풀어 썼어요. 읽고 나서 바로 온라인으로 플레이해 보세요.';
  const inner = `<h1>카드게임 룰 가이드</h1>`
    + `<p>처음 보는 게임도 이야기처럼 읽다 보면 룰이 잡혀요. 네 가지 게임을 모두 Tichu Online에서 바로 해볼 수 있습니다.</p>`
    + `<figure><img src="${IMG_PATH}intro_games.webp" alt="티츄, 마이티, 스컬킹, 러브레터 — 네 가지 게임" width="${FIG_W}" height="${FIG_H}" decoding="async"></figure>`
    + `<ul class="games">${items}</ul>`
    + `<p>점수 계산이나 카드 효과처럼 궁금한 부분만 보고 싶다면 <a href="/guide">공략·점수 계산 가이드</a>를 보세요.</p>`
    + `<a class="cta" href="/">🎮 지금 플레이하기</a>`;
  return shell({ title, description, canonical: `${BASE_URL}/rules`, inner });
}

function serveImage(req, res, name) {
  const file = /^[a-z0-9_]+\.webp$/.test(name) ? path.join(IMG_DIR, name) : null;
  let data = null;
  try { if (file) data = fs.readFileSync(file); } catch (_) { /* → 404 */ }
  if (!data) {
    res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('Not found');
    return true;
  }
  res.writeHead(200, { 'Content-Type': 'image/webp', 'Content-Length': data.length, 'Cache-Control': 'public, max-age=86400' });
  res.end(req.method === 'HEAD' ? undefined : data);
  return true;
}

/// Returns true if the request was answered.
function serve(req, res, pathname) {
  if (req.method !== 'GET' && req.method !== 'HEAD') return false;
  const p = pathname.replace(/\/+$/, '');
  if (p.startsWith(IMG_PATH)) return serveImage(req, res, p.slice(IMG_PATH.length));
  let html = null;
  if (p === '/rules') html = renderIndex();
  else if (p.startsWith('/rules/')) {
    html = renderGame(p.slice('/rules/'.length));
    if (!html) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('Not found');
      return true;
    }
  }
  else if (p === '/guide') html = renderGuideIndex();
  else if (p.startsWith('/guide/')) {
    html = renderGuide(p.slice('/guide/'.length));
    if (!html) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('Not found');
      return true;
    }
  }
  if (!html) return false;
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'public, max-age=3600' });
  res.end(req.method === 'HEAD' ? undefined : html);
  return true;
}

module.exports = { serve, parse, GAMES, GUIDES, renderGame, renderIndex, renderGuide, renderGuideIndex };
