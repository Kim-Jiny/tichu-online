// node test_seo_pages.js — rule pages render, escape, and carry FAQ JSON-LD.
const assert = require('assert');
const seo = require('./seo_pages');

for (const g of seo.GAMES) {
  const html = seo.renderGame(g.slug);
  assert(html, `${g.slug} renders`);
  assert(html.includes(`<link rel="canonical" href="https://tichu.kr/rules/${g.slug}">`));
  assert(html.includes('"@type":"FAQPage"'), `${g.slug} has FAQ`);
  assert(!html.includes('**'), `${g.slug} has no raw markdown`);
  assert(!/Title:|메타 태그용/.test(html), `${g.slug} hides meta block`);
}
assert.strictEqual(seo.renderGame('nope'), null);
assert(seo.parse('# T\n\n<script>x</script> **b**\n').body.includes('&lt;script&gt;'));
assert(seo.renderIndex().includes('/rules/mighty'));

for (const g of seo.GUIDES) {
  const html = seo.renderGuide(g.slug);
  assert(html, `${g.slug} renders`);
  assert(html.includes(`<link rel="canonical" href="https://tichu.kr/guide/${g.slug}">`));
  assert(html.includes('"@type":"FAQPage"'), `${g.slug} has FAQ`);
  assert(html.includes('"@type":"BreadcrumbList"'), `${g.slug} has breadcrumbs`);
  assert(!html.includes('**'), `${g.slug} has no raw markdown`);
  assert(!/Title:|메타 태그용/.test(html), `${g.slug} hides meta block`);
  assert(html.includes(`href="/rules${g.game === 'all' ? '"' : `/${g.game}"`}`), `${g.slug} links to rules`);
  if (g.game !== 'all') {
    assert(seo.renderGame(g.game).includes(`/guide/${g.slug}`), `${g.game} rules link to ${g.slug}`);
  }
  assert(seo.renderGuideIndex().includes(`/guide/${g.slug}`), `index links ${g.slug}`);
}
assert.strictEqual(seo.renderGuide('nope'), null);

// Every picture a page points at must exist, and the image route must answer.
const fs = require('fs');
const path = require('path');
const pages = [seo.renderIndex(), seo.renderGuideIndex(),
  ...seo.GAMES.map((g) => seo.renderGame(g.slug)),
  ...seo.GUIDES.map((g) => seo.renderGuide(g.slug))];
let figures = 0;
for (const html of pages) {
  for (const m of html.matchAll(/src="\/seo-img\/([a-z0-9_]+\.webp)"/g)) {
    figures++;
    assert(fs.existsSync(path.join(__dirname, 'content', 'img', m[1])), `missing image ${m[1]}`);
  }
}
assert(figures > 20, `expected many figures, got ${figures}`);
assert(!pages.some((h) => /!\[/.test(h)), 'raw image markdown leaked');
const fake = (url) => {
  const res = { code: 0, writeHead(c) { this.code = c; }, end() {} };
  seo.serve({ method: 'GET', url }, res, url);
  return res.code;
};
assert.strictEqual(fake('/seo-img/mighty_steps.webp'), 200);
assert.strictEqual(fake('/seo-img/nope.webp'), 404);
assert.strictEqual(fake('/seo-img/..%2Fserver.js'), 404);
assert.strictEqual(fake('/seo-img/../seo_pages.js'), 404);

// English rules: own canonical, hreflang pair, FAQ markup, nothing left untranslated.
for (const g of seo.GAMES) {
  const html = seo.renderGame(g.slug, 'en');
  assert(html, `${g.slug} en renders`);
  assert(html.includes('<html lang="en">'));
  assert(html.includes(`<link rel="canonical" href="https://tichu.kr/en/rules/${g.slug}">`));
  assert(html.includes(`hreflang="ko" href="https://tichu.kr/rules/${g.slug}"`));
  assert(html.includes(`hreflang="en" href="https://tichu.kr/en/rules/${g.slug}"`));
  assert(html.includes('"@type":"FAQPage"'), `${g.slug} en has FAQ`);
  assert(!html.includes('**'), `${g.slug} en has no raw markdown`);
  assert(!/Meta tags/.test(html), `${g.slug} en hides meta block`);
  const hangul = html.replace('<a href="/rules">한국어</a>', '').match(/[가-힣]+/g);
  assert(!hangul, `${g.slug} en has untranslated text: ${hangul && hangul.slice(0, 3)}`);
  assert(seo.renderGame(g.slug).includes(`hreflang="en" href="https://tichu.kr/en/rules/${g.slug}"`), `${g.slug} ko points at en`);
}
assert(seo.renderIndex('en').includes('/en/rules/mighty'));
assert.strictEqual(seo.renderGame('nope', 'en'), null);
console.log('seo pages ok');
