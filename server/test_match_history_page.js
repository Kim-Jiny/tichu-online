/**
 * Does paging the match history give you every match, once?
 *
 * The profile popup's own list must not be sliced globally — the tabs would
 * starve — so paging is a second shape of the same query, and the two are easy
 * to let drift apart. This walks a real account's history a page at a time and
 * checks the walk against the unpaged answer: same matches, same order, nothing
 * repeated across a boundary and nothing dropped at one.
 *
 * Run (needs the dev database): node server/test_match_history_page.js [nickname]
 */
const db = require('./db/database.js');

let failures = 0;
const check = (label, cond, detail = '') => {
  console.log(`${cond ? '  ok  ' : '  FAIL'} ${label}${!cond && detail ? ` — ${detail}` : ''}`);
  if (!cond) failures++;
};

const idOf = (m) => `${m.gameType}:${m.id}${m.isMidGameLeave ? ':ml' : ''}`;

async function walk(nickname, gameType, pageSize) {
  const seen = [];
  let offset = 0;
  const guardLimit = Math.ceil(db.MATCH_HISTORY_MAX_DEPTH / pageSize) + 2;
  for (let guard = 0; guard < guardLimit; guard++) {
    const { matches, hasMore } = await db.getRecentMatches(nickname, pageSize, {
      gameType,
      offset,
    });
    seen.push(...matches);
    if (!hasMore || matches.length === 0) return seen;
    offset += matches.length;
  }
  throw new Error('paging did not terminate');
}

(async () => {
  const nickname = process.argv[2] || 'ㅋㅋㅋㅋㅋㅋ킼ㅋㅋ';
  console.log(`\n[${nickname}]`);

  // Paging stops at MATCH_HISTORY_MAX_DEPTH — each source is asked for
  // offset+limit rows, so an unbounded walk would end up reading whole tables.
  // Everything above compares against the history down to that depth.
  const cap = db.MATCH_HISTORY_MAX_DEPTH;
  const flat = await db.getRecentMatches(nickname, cap + 50);
  const flatSorted = [...flat]
    .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt))
    .slice(0, cap);
  console.log(`  ..  ${flat.length} matches on record, paging reaches ${cap}`);
  check('there is enough history to page through', flat.length > 5, `${flat.length}`);

  for (const size of [3, 7, 20]) {
    const walked = await walk(nickname, 'all', size);
    const ids = walked.map(idOf);
    check(`page size ${size}: no match appears twice`,
      new Set(ids).size === ids.length,
      `${ids.length} rows, ${new Set(ids).size} distinct`);
    check(`page size ${size}: nothing is skipped at a boundary`,
      ids.length === flatSorted.length,
      `walked ${ids.length}, expected ${flatSorted.length}`);
    check(`page size ${size}: the order survives paging`,
      ids.join('|') === flatSorted.map(idOf).join('|'));
  }

  // One tab at a time is what the dialog actually asks for.
  for (const gameType of ['tichu', 'skull_king', 'mighty', 'love_letter']) {
    const page = await db.getRecentMatches(nickname, 10, { gameType, offset: 0 });
    const strays = page.matches.filter((m) => m.gameType !== gameType);
    check(`${gameType}: the page holds that game only`,
      strays.length === 0,
      strays.map((m) => m.gameType).join(','));
    const expected = flatSorted.filter((m) => m.gameType === gameType);
    check(`${gameType}: the first page matches the unpaged head`,
      page.matches.map(idOf).join('|') ===
        expected.slice(0, 10).map(idOf).join('|'),
      `${page.matches.length} vs ${Math.min(10, expected.length)}`);
    check(`${gameType}: hasMore agrees with what is left`,
      page.hasMore === expected.length > 10,
      `hasMore=${page.hasMore}, total=${expected.length}`);
  }

  // Past the end is an answer, not an error.
  const beyond = await db.getRecentMatches(nickname, 10, {
    gameType: 'all',
    offset: 100000,
  });
  check('an offset past the end comes back empty',
    beyond.matches.length === 0 && beyond.hasMore === false);
})()
  .then(() => {
    console.log(failures === 0 ? '\nPASS' : `\n${failures} FAILURE(S)`);
    process.exit(failures === 0 ? 0 : 1);
  })
  .catch((e) => {
    console.error('\nERROR', e.message);
    process.exit(1);
  });
