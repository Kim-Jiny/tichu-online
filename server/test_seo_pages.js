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
  assert(html.includes(`href="/rules/${g.game}"`), `${g.slug} links to its rules page`);
  assert(seo.renderGame(g.game).includes(`/guide/${g.slug}`), `${g.game} rules link to ${g.slug}`);
  assert(seo.renderGuideIndex().includes(`/guide/${g.slug}`), `index links ${g.slug}`);
}
assert.strictEqual(seo.renderGuide('nope'), null);
console.log('seo pages ok');
