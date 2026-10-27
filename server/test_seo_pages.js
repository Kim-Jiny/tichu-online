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
console.log('seo pages ok');
