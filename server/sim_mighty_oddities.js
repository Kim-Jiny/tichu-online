'use strict';
/**
 * "묘하게 이상해 보이는 수"를 여러 종류 한 번에 센다.
 *
 * 집계 점수로는 안 잡히는 행마 품질 문제를 찾는 용도. 각 항목은 사람이 봤을 때
 * 바로 이상하다고 느끼는 패턴만 담았고, 판정은 전부 봇이 실제로 쓰는 함수를
 * 그대로 쓴다(자체 구현하면 상대 손패를 못 봐서 과대보고가 난다).
 *
 *   node sim_mighty_oddities.js [rounds] [seedBase] [strategy]
 *   ONLY=overkill node ...   ← 그 항목 샘플만 출력
 */
const MightyGame = require('./game/mighty/MightyGame');
const MB = require('./game/mighty/MightyBot');
const { decideMightyBotAction } = MB;
const { getCardInfo, makeRng, RANK_ORDER } = require('./game/mighty/MightyDeck');

const IDS = ['p0', 'p1', 'p2', 'p3', 'p4'];
const NAMES = {}; IDS.forEach((p) => (NAMES[p] = p));

const rounds = parseInt(process.argv[2] || '300', 10);
const base = parseInt(process.argv[3] || '5', 10);
const strategy = process.argv[4] || 'mixoracle';

const tally = {};
const samples = [];
const bySource = {};
let lastPath = null, lastRule = null;
global.__mightyPathTrace = (p) => { lastPath = p; if (p !== 'rules') lastRule = null; };
global.__mightyRuleTrace = (n) => { lastRule = n; };

const short = (c) => String(c).replace('mighty_', '');

function flag(key, game, actor, cardId, note) {
  tally[key] = (tally[key] || 0) + 1;
  const src = lastPath === 'rules' ? `rules:${lastRule}` : String(lastPath);
  bySource[key] = bySource[key] || {};
  bySource[key][src] = (bySource[key][src] || 0) + 1;
  if (samples.length < 40 && (!process.env.ONLY || process.env.ONLY === key)) {
    samples.push({
      key,
      trick: game.tricks.length + 1,
      trump: game.trumpSuit,
      role: actor === game.declarer ? '주공' : MB.isFriend(game, actor) ? '프렌드' : '야당',
      revealed: game.friendRevealed,
      cur: game.currentTrick.map(p => `${p.pid}:${short(p.cardId)}`).join(' ') || '(리드)',
      played: short(cardId),
      hand: (game.hands[actor] || []).map(short).join(' '),
      note,
    });
  }
}

/** 봇이 믿는 트릭 소유자가 우리편인가 (야당은 프렌드 공개 전 정보 게이트를 따름). */
function believesAlly(game, botId, winner) {
  if (!winner) return false;
  const gov = MB.isGovernmentSelf(game, botId);
  return gov
    ? MB.isGovernmentSelf(game, winner)
    : (game.friendRevealed ? !MB.isGovernment(game, winner) : winner !== game.declarer);
}

let errors = 0;
for (let r = 0; r < rounds; r++) {
  // MightyGame 은 options.seed 를 안 본다 — rng 를 직접 넘겨야 재현된다.
  const game = new MightyGame(IDS, NAMES, { rng: makeRng(base + r) });
  try {
    game.start();
    let pendingLead = null;
    let guard = 0;
    while (game.state !== 'game_end' && guard++ < 4000) {
      if (game.state === 'round_end') break;
      if (game.state === 'trick_end') {
        if (pendingLead) {
          const t = game.tricks[game.tricks.length - 1];
          if (t && t.winner
              && MB.isGovernmentSelf(game, t.winner) !== MB.isGovernmentSelf(game, pendingLead.actor)) {
            flag('leadPointLost', game, pendingLead.actor, pendingLead.cardId,
              `잡패 리드 가능했음: ${pendingLead.junk}`);
          }
          pendingLead = null;
        }
        game.advanceAfterTrickEnd();
        continue;
      }
      const actor = game.currentPlayer;
      if (!actor) break;
      const action = decideMightyBotAction(game, actor, strategy);
      if (!action) break;
      const cardId = action.type === 'play_card' ? action.cardId : null;

      if (cardId) {
        const legal = game._getLegalCards(actor) || [];
        const mighty = game.getMightyCard();
        const trump = game.trumpSuit;
        const trumpActive = trump && trump !== 'no_trump';
        const seats = game.activePlayerCount || game.playerCount;
        const isLast = game.currentTrick.length === seats - 1;
        const winner = game.currentTrick.length ? MB.getCurrentTrickWinner(game) : null;
        const ally = believesAlly(game, actor, winner);
        const info = cardId === 'mighty_joker' ? null : getCardInfo(cardId);
        const jokerPower = typeof game._currentTrickJokerHasPower === 'function'
          && game._currentTrickJokerHasPower();

        // ① 아군이 이미 확보한 트릭을 비싼 카드로 가로챈다
        if (winner && ally && MB.canBeatCurrentWinner(game, cardId)) {
          const wc = MB.getWinnerCardId(game);
          const secure = wc === mighty || wc === 'mighty_joker' || MB.isEffectiveTopOfSuit(wc, game);
          const expensive = cardId === mighty || cardId === 'mighty_joker'
            || (trumpActive && info && info.suit === trump);
          // 안 덮는 선택지가 있어야 실수다. 손에 그 수밖에 없으면 강제다.
          const canDecline = legal.some((c) => !MB.canBeatCurrentWinner(game, c));
          if (secure && expensive && canDecline) {
            // 봇 믿음으론 아군인데 실제로도 아군이었나. 아니면 오라클이 전지적
            // 정보(숨은 프렌드 정체)로 친 수라 "낭비"가 아니다.
            const trulyAlly = MB.isGovernmentSelf(game, winner) === MB.isGovernmentSelf(game, actor);
            flag(trulyAlly ? 'allySteal' : 'allyStealOmni', game, actor, cardId,
              `${trulyAlly ? '진짜 아군' : '실은 적'} ${short(wc)} 확보분을 덮음`);
          }
        }

        // ② 마지막 순번인데 최소 승리 카드를 안 쓴다 (뒤에 아무도 없는데 과잉)
        if (winner && isLast && MB.canBeatCurrentWinner(game, cardId)) {
          const cheaper = legal.filter((c) => {
            if (c === cardId) return false;
            if (!MB.canBeatCurrentWinner(game, c)) return false;
            if (cardId === mighty || cardId === 'mighty_joker') {
              return c !== mighty && c !== 'mighty_joker';
            }
            if (c === mighty || c === 'mighty_joker') return false;
            const ci = getCardInfo(c);
            if (!info) return false;
            // 같은 무늬에서 더 낮은 카드로도 이겼다면 과잉이다
            return ci.suit === info.suit && RANK_ORDER[ci.rank] < RANK_ORDER[info.rank];
          });
          if (cheaper.length > 0) {
            flag('overkill', game, actor, cardId, `더 싼 승리수: ${cheaper.map(short).join(' ')}`);
          }
        }

        // ③ 힘없는 조커를 그냥 버린다 (첫/막 트릭 등에서 조커는 못 이긴다)
        if (cardId === 'mighty_joker' && !jokerPower && legal.length > 1) {
          flag('jokerWaste', game, actor, cardId, '조커가 힘없는 트릭');
        }

        // ④ 아군이 확보한 트릭에 기루다를 실어 준다 (비기루다 잡패가 있는데도)
        if (winner && ally && trumpActive && info && info.suit === trump
            && !MB.canBeatCurrentWinner(game, cardId)) {
          const junk = legal.filter((c) => {
            if (c === mighty || c === 'mighty_joker') return false;
            const ci = getCardInfo(c);
            return ci.suit !== trump && ci.point === 0;
          });
          if (junk.length > 0) {
            flag('trumpDump', game, actor, cardId, `잡패 있었음: ${junk.map(short).join(' ')}`);
          }
        }

        // ⑥ 점수 걸린 트릭을 확실히 먹을 수 있는데 흘린다
        if (winner && !ally && !MB.canBeatCurrentWinner(game, cardId)) {
          const pot = game.currentTrick.reduce(
            (sum, p) => sum + ((getCardInfo(p.cardId) || {}).point || 0), 0);
          const sure = legal.filter((x) => x !== mighty && x !== 'mighty_joker'
            && MB.canBeatCurrentWinner(game, x)
            && MB.isSafeFriendWinner(x, game, actor));
          if (pot > 0 && sure.length > 0) {
            flag('duckSureWin', game, actor, cardId,
              `확실한 승리수 있었음: ${sure.map(short).join(' ')} (판돈 ${pot}점)`);
          }
        }

        // ⑤ 점수 카드를 리드로 던지고 상대에게 뺏긴다 (잡패 리드가 가능했는데)
        if (game.currentTrick.length === 0 && info && info.point > 0
            && cardId !== mighty && legal.length > 1) {
          // 같은 무늬에 더 낮은 카드를 들고 있었는데 굳이 점수 카드를 리드한
          // 경우만 센다. 다른 무늬 잡패가 있는 건 "그 무늬를 여는" 선택일 수
          // 있어서 실수라고 단정 못 한다.
          const junk = legal.filter((c) => {
            if (c === mighty || c === 'mighty_joker') return false;
            const ci = getCardInfo(c);
            return ci.point === 0 && ci.suit === info.suit && ci.value < info.value;
          });
          if (junk.length > 0 && !MB.isEffectiveTopOfSuit(cardId, game)) {
            pendingLead = { actor, cardId, junk: junk.map(short).join(' ') };
          }
        }
      }

      const res = game.handleAction(actor, action);
      if (!res || !res.success) break;
    }
  } catch (e) {
    errors++;
    if (errors <= 2) console.error('round error:', e.message);
  }
}

const LABEL = {
  allySteal: '진짜 아군이 확보한 트릭을 비싼 카드로 덮음',
  allyStealOmni: '아군처럼 보이는 자리를 덮음 — 실은 적(오라클 전지적 정보)',
  trumpDump: '아군 확보 트릭에 기루다를 실어 줌(잡패 있었는데)',
  leadPointLost: '같은 무늬 낮은 카드 두고 점수 카드를 리드 → 상대에게 헌납',
  overkill: '마지막 순번인데 최소 승리 카드를 안 씀',
  jokerWaste: '힘없는 조커를 그냥 버림',
  mightyLeadDry: '판돈 0인데 마이티를 리드',
  duckSureWin: '점수 걸린 트릭을 확실히 먹을 수 있는데 흘림',
};

console.log(`\n이상한 수 스캔 — ${rounds}라운드, ${strategy}${errors ? ` (errors ${errors})` : ''}`);
for (const [k, v] of Object.entries(tally).sort((a, b) => b[1] - a[1])) {
  console.log(`\n  ${String(v).padStart(4)}회  ${LABEL[k] || k}`);
  const s = Object.entries(bySource[k] || {}).sort((a, b) => b[1] - a[1]);
  console.log(`         경로: ${s.map(([n, c]) => `${n} ${c}`).join(' · ')}`);
}
for (const s of samples.slice(0, 8)) {
  console.log(`\n  [${s.key}] 트릭${s.trick} ${s.role}${s.revealed ? '' : '(미공개)'} · 기루다 ${s.trump}`);
  console.log(`    ${s.cur}  → ${s.played}   ${s.note}`);
  console.log(`    손패: ${s.hand}`);
}
