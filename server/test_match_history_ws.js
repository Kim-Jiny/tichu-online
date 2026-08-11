/**
 * The paged history over the wire.
 *
 * The DB test proves the pages are cut correctly; this one proves the socket
 * message reaches them, clamps what it is given, and answers with the shape the
 * client waits on (nickname / gameType / offset all echoed, or a late page for
 * another profile would be appended to this one).
 *
 * Run (server must be listening): node server/test_match_history_ws.js [nickname]
 */
const WebSocket = require('ws');

const SERVER_URL = process.env.WS_URL || 'ws://localhost:8080';
const TARGET = process.argv[2] || 'ㅋㅋㅋㅋㅋㅋ킼ㅋㅋ';
// Matches MATCH_HISTORY_PAGE_MAX on the server and _pageSize on the client.
const PAGE = 50;
const run = Date.now().toString(36).slice(-5);

let failures = 0;
const check = (label, cond, detail = '') => {
  console.log(`${cond ? '  ok  ' : '  FAIL'} ${label}${!cond && detail ? ` — ${detail}` : ''}`);
  if (!cond) failures++;
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function connect() {
  const c = { last: {} };
  c.ready = new Promise((resolve, reject) => {
    c.ws = new WebSocket(SERVER_URL);
    c.ws.on('open', resolve);
    c.ws.on('error', reject);
    c.ws.on('message', (raw) => {
      const d = JSON.parse(raw.toString());
      c.last[d.type] = d;
    });
  });
  c.send = (m) => c.ws.send(JSON.stringify(m));
  c.forget = (t) => delete c.last[t];
  c.wait = async (t, ms = 8000) => {
    const end = Date.now() + ms;
    while (Date.now() < end) {
      if (c.last[t]) return c.last[t];
      await sleep(80);
    }
    return null;
  };
  return c;
}

const idOf = (m) => `${m.gameType}:${m.id}${m.isMidGameLeave ? ':ml' : ''}`;

async function page(c, opts) {
  c.forget('match_history_page');
  c.send({ type: 'get_match_history', nickname: TARGET, ...opts });
  return c.wait('match_history_page');
}

(async () => {
  const me = connect();
  await me.ready;
  const acct = {
    username: `hist_${run}`,
    password: 'smoke1234!',
    nickname: `히스토리${run}`,
  };
  me.send({ type: 'register', ...acct });
  await sleep(900);
  me.send({ type: 'login', ...acct, deviceInfo: { appVersion: '99.0.0', locale: 'ko' } });
  if (!(await me.wait('login_success'))) throw new Error('login failed');

  console.log(`\n[${TARGET}]`);
  const first = await page(me, { gameType: 'all', offset: 0, limit: PAGE });
  check('the server answers a history request', first != null);
  if (!first) throw new Error('no answer');
  check('it echoes what was asked for',
    first.nickname === TARGET && first.gameType === 'all' && first.offset === 0,
    JSON.stringify({ n: first.nickname, g: first.gameType, o: first.offset }));
  check('a full first page comes back', first.matches.length === PAGE,
    `${first.matches.length}`);
  check('and says there is more', first.hasMore === true);

  const second = await page(me, { gameType: 'all', offset: PAGE, limit: PAGE });
  const overlap = second.matches
    .map(idOf)
    .filter((id) => first.matches.map(idOf).includes(id));
  check('the second page does not repeat the first', overlap.length === 0,
    overlap.join(','));
  check('the second page is echoed at its own offset', second.offset === PAGE);

  const tab = await page(me, { gameType: 'tichu', offset: 0, limit: 10 });
  const strays = tab.matches.filter((m) => m.gameType !== 'tichu');
  check('a single-game page holds that game only', strays.length === 0,
    strays.map((m) => m.gameType).join(','));

  // The client asks for 20; nothing stops a hand-rolled message asking for
  // everything at once.
  const greedy = await page(me, { gameType: 'all', offset: 0, limit: 5000 });
  check('an oversized page is clamped', greedy.matches.length <= PAGE,
    `${greedy.matches.length}`);

  const nobody = await page(me, {
    nickname: `없는사람${run}`,
    gameType: 'all',
    offset: 0,
    limit: PAGE,
  });
  check('an account with no history answers empty, not with an error',
    nobody != null && nobody.matches.length === 0 && nobody.hasMore === false);

  me.ws.close();
})()
  .then(() => {
    console.log(failures === 0 ? '\nPASS' : `\n${failures} FAILURE(S)`);
    process.exit(failures === 0 ? 0 : 1);
  })
  .catch((e) => {
    console.error('\nERROR', e.message);
    process.exit(1);
  });
