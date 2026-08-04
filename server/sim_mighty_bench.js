'use strict';
/**
 * dev 봇 vs main 봇 판단 시간 비교.
 *
 * 같은 시드 딜을 각각 끝까지 치면서 결정 1건당 걸린 시간을 전부 모은다.
 * 봇은 서버 이벤트루프(또는 워커)를 붙잡고 있으므로 p95/max 가 체감에 직결된다.
 *
 *   MAIN_BOT=<main 트리 경로> node sim_mighty_bench.js [rounds] [seedBase]
 */
const MightyGame = require('./game/mighty/MightyGame');
const devBot = require('./game/mighty/MightyBot');
const { makeRng } = require('./game/mighty/MightyDeck');

const MAIN_BOT = process.env.MAIN_BOT;
const mainBot = MAIN_BOT ? require(`${MAIN_BOT}/MightyBot`) : null;

const IDS = ['p0', 'p1', 'p2', 'p3', 'p4'];
const NAMES = {}; IDS.forEach(p => (NAMES[p] = p));

function settle(g) {
  let s = 200;
  while (s-- > 0) {
    if (g.state === 'trick_end') { g.advanceAfterTrickEnd(); continue; }
    break;
  }
}

const rounds = parseInt(process.argv[2] || '300', 10);
module.exports.__rounds = rounds;
const base = parseInt(process.argv[3] || '7', 10);

function run(bot, label, roundsOverride) {
  const rounds = roundsOverride != null ? roundsOverride : module.exports.__rounds;
  const times = [];
  let errors = 0;
  const t0 = process.hrtime.bigint();
  for (let r = 0; r < rounds; r++) {
    const g = new MightyGame(IDS, NAMES, { targetScore: 50, rng: makeRng((1000003 * base + r) >>> 0) });
    g.start();
    let steps = 0;
    while (g.state !== 'round_end' && g.state !== 'game_end' && steps++ < 8000) {
      settle(g);
      if (g.state === 'round_end' || g.state === 'game_end') break;
      const actor = g.getPendingActor();
      if (!actor) break;
      const s = process.hrtime.bigint();
      const a = bot.decideMightyBotAction(g, actor, 'mixoracle');
      times.push(Number(process.hrtime.bigint() - s) / 1e6);
      if (!a) { errors++; break; }
      const res = g.handleAction(actor, a);
      if (!res || res.success === false) {
        const fb = g.getAutoTimeoutAction(actor);
        if (fb) g.handleAction(actor, fb); else { errors++; break; }
      }
    }
  }
  const wall = Number(process.hrtime.bigint() - t0) / 1e6;
  times.sort((a, b) => a - b);
  const q = (p) => times[Math.min(times.length - 1, Math.floor(times.length * p))] || 0;
  const sum = times.reduce((x, y) => x + y, 0);
  return {
    label, n: times.length, wall, errors,
    mean: sum / Math.max(1, times.length),
    p50: q(0.5), p95: q(0.95), p99: q(0.99), max: times[times.length - 1] || 0,
  };
}

// 워밍업: JIT 가 데워지기 전 구간을 측정에 넣으면 먼저 도는 쪽이 손해를 본다.
// (처음 쟀을 때 dev 를 먼저 돌려서 +24% 가 나왔는데, 상당 부분이 이 효과였다.)
const WARM = Math.max(10, Math.floor(rounds / 10));
const realRounds = rounds;
{
  const saved = realRounds;
  // eslint-disable-next-line no-global-assign
  globalThis.__benchWarm = true;
  for (const b of [devBot, mainBot].filter(Boolean)) {
    for (let i = 0; i < 1; i++) run(b, 'warm', WARM);
  }
  globalThis.__benchWarm = false;
  void saved;
}

const only = process.env.ONLY_BOT;
const results = [];
if (only !== 'main') results.push(run(devBot, 'dev'));
if (mainBot && only !== 'dev') results.push(run(mainBot, 'main'));

console.log(`\n봇 판단 시간 — ${rounds}라운드 (base ${base}), mixoracle`);
console.log('\n라벨   결정수   총시간(s)  평균(ms)   p50     p95     p99     max');
for (const r of results) {
  console.log(`${r.label.padEnd(6)} ${String(r.n).padStart(6)}   ${(r.wall / 1000).toFixed(1).padStart(7)}`
    + `   ${r.mean.toFixed(2).padStart(7)} ${r.p50.toFixed(2).padStart(7)} ${r.p95.toFixed(2).padStart(7)}`
    + ` ${r.p99.toFixed(2).padStart(7)} ${r.max.toFixed(1).padStart(7)}`);
}
if (results.length === 2) {
  const [d, m] = results;
  const pct = (a, b) => `${b > 0 ? ((a / b - 1) * 100).toFixed(1) : '-'}%`;
  console.log(`\n  dev - main:  평균 ${pct(d.mean, m.mean)} · p95 ${pct(d.p95, m.p95)} · 총시간 ${pct(d.wall, m.wall)}`);
}
