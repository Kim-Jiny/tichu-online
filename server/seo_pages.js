/**
 * Crawlable rule pages: /rules and /rules/<game>.
 *
 * The game itself is a Flutter canvas, so a search engine sees one page with a
 * paragraph of text on it. These are the pages that carry real prose. The text
 * lives in content/rules/*.md (copied from docs/seo/prose, which is where it
 * gets written and reviewed) and is rendered here at request time into plain
 * server HTML — no JS needed to read it, which is the whole point.
 *
 * Each file ends with a "*메타 태그용*" block holding Title / Description; that
 * block feeds <title>/<meta> and is never rendered into the body. The FAQ
 * section ("**질문?** 답") also becomes FAQPage JSON-LD.
 */

const fs = require('fs');
const path = require('path');

const BASE_URL = process.env.INVITE_BASE_URL || 'https://tichu.kr';
const DIR = path.join(__dirname, 'content', 'rules');

const GAMES = [
  { slug: 'tichu', name: '티츄', blurb: '4인 2:2 팀전. 손패를 가장 먼저 비우는 경주' },
  { slug: 'mighty', name: '마이티', blurb: '5인 트릭테이킹. 숨은 프렌드와 경매(비딩)' },
  { slug: 'skullking', name: '스컬킹', blurb: '해적 테마 예측 트릭테이킹. 약속한 만큼만 따내기' },
  { slug: 'loveletter', name: '러브레터', blurb: '카드 16장으로 하는 추리·블러핑 게임' },
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
function load(slug) {
  if (cache.has(slug)) return cache.get(slug);
  let page = null;
  try {
    page = parse(fs.readFileSync(path.join(DIR, `${slug}.md`), 'utf8'));
  } catch (_) { /* missing file → 404 */ }
  cache.set(slug, page);
  return page;
}

const CSS = `body{margin:0;background:#fdf8f3;color:#143a57;`
  + `font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Noto Sans KR','Apple SD Gothic Neo',sans-serif;line-height:1.8}`
  + `.wrap{max-width:720px;margin:0 auto;padding:32px 22px 80px}`
  + `.nav{font-size:14px;margin:0 0 28px}.nav a{color:#f28c26;text-decoration:none;margin-right:14px;font-weight:700}`
  + `h1{font-size:26px;line-height:1.4;margin:0 0 18px}h2{font-size:20px;margin:36px 0 8px;color:#143a57}h3{font-size:17px;margin:24px 0 6px}`
  + `p{margin:0 0 14px}strong{color:#143a57}a{color:#d9731a}ul{padding-left:20px}`
  + `.cta{display:inline-block;margin:28px 0 8px;padding:14px 26px;background:#f28c26;color:#fff;`
  + `border-radius:12px;text-decoration:none;font-weight:700}`
  + `.games{list-style:none;padding:0}.games li{margin:0 0 14px;padding:14px 16px;background:#fff;border:2px solid #143a57;border-radius:12px}`
  + `.games a{font-weight:700;font-size:18px}.foot{margin-top:48px;font-size:13px;opacity:.7}`;

function shell({ title, description, canonical, jsonld, inner }) {
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
    + `<style>${CSS}</style></head><body><div class="wrap">`
    + `<div class="nav"><a href="/">Tichu Online</a><a href="/rules">룰 가이드</a></div>`
    + inner
    + `<p class="foot">© Tichu Online · <a href="/support?lang=ko">고객센터</a></p>`
    + `</div></body></html>`;
}

function renderGame(slug) {
  const game = GAMES.find((g) => g.slug === slug);
  const page = game && load(slug);
  if (!page) return null;
  const canonical = `${BASE_URL}/rules/${slug}`;
  const title = page.meta.title || `${game.name} 룰 | Tichu Online`;
  const description = page.meta.description || game.blurb;
  const jsonld = [
    {
      '@context': 'https://schema.org', '@type': 'Article',
      headline: page.h1, description, inLanguage: 'ko', mainEntityOfPage: canonical,
      publisher: { '@type': 'Organization', name: 'Tichu Online', url: `${BASE_URL}/` },
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
  const inner = `<h1>${esc(page.h1)}</h1>${page.body}`
    + `<a class="cta" href="/">${esc(game.name)} 지금 플레이하기</a>`
    + `<p>설치 없이 브라우저에서 바로 시작할 수 있어요. 다른 게임 룰: ${others}</p>`;
  return shell({ title, description, canonical, jsonld, inner });
}

function renderIndex() {
  const items = GAMES.map((g) => `<li><a href="/rules/${g.slug}">${esc(g.name)} 룰 쉽게 배우기</a><br>${esc(g.blurb)}</li>`).join('');
  const title = '카드게임 룰 가이드 — 티츄 · 마이티 · 스컬킹 · 러브레터 | Tichu Online';
  const description = '티츄, 마이티, 스컬킹, 러브레터의 규칙을 이야기하듯 풀어 썼어요. 읽고 나서 바로 온라인으로 플레이해 보세요.';
  const inner = `<h1>카드게임 룰 가이드</h1>`
    + `<p>처음 보는 게임도 이야기처럼 읽다 보면 룰이 잡혀요. 네 가지 게임을 모두 Tichu Online에서 바로 해볼 수 있습니다.</p>`
    + `<ul class="games">${items}</ul><a class="cta" href="/">지금 플레이하기</a>`;
  return shell({ title, description, canonical: `${BASE_URL}/rules`, inner });
}

/// Returns true if the request was answered.
function serve(req, res, pathname) {
  if (req.method !== 'GET' && req.method !== 'HEAD') return false;
  const p = pathname.replace(/\/+$/, '');
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
  if (!html) return false;
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'public, max-age=3600' });
  res.end(req.method === 'HEAD' ? undefined : html);
  return true;
}

module.exports = { serve, parse, GAMES, renderGame, renderIndex };
