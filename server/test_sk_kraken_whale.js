/**
 * 크라켄과 흰고래가 한 트릭에 함께 나왔을 때 — 공식 FAQ.
 *
 * 나중에 나온 쪽의 효과만 적용되고, 먼저 나온 쪽은 도주 카드로 취급한다.
 *   · 크라켄 → 흰고래 : 흰고래가 적용(색 무관 최고 숫자가 가져감, 숫자가
 *     없으면 무효). 크라켄은 도주.
 *   · 흰고래 → 크라켄 : 크라켄이 적용(트릭 무효). 다음 선은 "두 생물이
 *     없었다면 이겼을 사람".
 *
 * 전에는 낸 순서와 무관하게 늘 크라켄이 이겼다. 그래서
 * 검정1 → 크라켄 → 흰고래 → 노랑13 이 무효가 됐는데, 규칙대로면 노랑13 이
 * 트릭을 가져가고 승수도 올라간다 — 공약을 맞히고 못 맞히고가 갈리는 차이다.
 *
 * Run: node server/test_sk_kraken_whale.js
 */
const { resolveTrick } = require('./game/skull_king/SkullKingTrickResolver');

let failures = 0;
const check = (label, cond, detail = '') => {
  console.log(`${cond ? '  ok  ' : '  FAIL'} ${label}${!cond && detail ? ` — ${detail}` : ''}`);
  if (!cond) failures++;
};

/// 낸 순서대로 [playerId, cardId] 를 준다.
const trick = (...pairs) =>
  pairs.map(([playerId, cardId]) => ({ playerId, cardId }));
const detailTypes = (r) => (r.bonusDetail || []).map((d) => d.type).join(',');

console.log('\n[한 장만 나왔을 때 — 원래 동작 그대로]');
{
  const r = resolveTrick(trick(['a', 'sk_black_1'], ['b', 'sk_kraken'], ['c', 'sk_yellow_13']));
  check('크라켄만: 트릭 무효', r.voided === true);
  check('크라켄만: 두 생물 없었다면 이겼을 사람이 다음 선',
    r.winnerId === 'a', `winner=${r.winnerId} (검정1 이 트럼프라 a)`);
}
{
  const r = resolveTrick(trick(['a', 'sk_black_1'], ['b', 'sk_white_whale'], ['c', 'sk_yellow_13']));
  check('흰고래만: 무효가 아니다', r.voided === false);
  check('흰고래만: 색 무관 최고 숫자가 가져간다',
    r.winnerId === 'c', `winner=${r.winnerId} (노랑13 > 검정1)`);
}

console.log('\n[크라켄 → 흰고래 : 흰고래가 적용된다]');
{
  // 질문에 나온 그 트릭이다.
  const r = resolveTrick(trick(
    ['a', 'sk_black_1'], ['b', 'sk_kraken'], ['c', 'sk_white_whale'], ['d', 'sk_yellow_13'],
  ));
  check('무효가 아니다', r.voided === false, `voided=${r.voided}`);
  check('노랑13 을 낸 사람이 가져간다', r.winnerId === 'd', `winner=${r.winnerId}`);
  check('흰고래 효과로 판정했다고 알린다',
    detailTypes(r).includes('white_whale_nullify'), detailTypes(r));
  check('먼저 나온 크라켄이 밀렸다고 알린다',
    (r.bonusDetail || []).some((d) => d.supersededCreature === 'kraken'),
    JSON.stringify(r.bonusDetail));
}
{
  // 숫자가 하나도 없으면 흰고래라도 무효. 먼저 나온 크라켄은 도주라서
  // 숫자로 세어지지 않는다(애초에 숫자가 아니지만, 분기를 확인한다).
  const r = resolveTrick(trick(
    ['a', 'sk_kraken'], ['b', 'sk_white_whale'], ['c', 'sk_pirate_1'],
  ));
  check('숫자가 없으면 흰고래라도 무효', r.voided === true);
  check('그때 선은 흰고래를 낸 사람', r.winnerId === 'b', `winner=${r.winnerId}`);
}

console.log('\n[흰고래 → 크라켄 : 크라켄이 적용된다]');
{
  const r = resolveTrick(trick(
    ['a', 'sk_black_1'], ['b', 'sk_white_whale'], ['c', 'sk_kraken'], ['d', 'sk_yellow_13'],
  ));
  check('트릭이 무효가 된다', r.voided === true, `voided=${r.voided}`);
  check('크라켄 효과로 판정했다고 알린다',
    detailTypes(r).includes('kraken_void'), detailTypes(r));
  check('먼저 나온 흰고래가 밀렸다고 알린다',
    (r.bonusDetail || []).some((d) => d.supersededCreature === 'white_whale'),
    JSON.stringify(r.bonusDetail));
  // 두 생물이 없었다면 검정1(트럼프)과 노랑13 중 트럼프가 이긴다.
  check('다음 선은 두 생물이 없었다면 이겼을 사람',
    r.winnerId === 'a', `winner=${r.winnerId} (검정1 이 트럼프)`);
}
{
  // 생물을 빼면 해적이 숫자를 이긴다 — 다음 선 계산이 기본 서열을 그대로 쓴다.
  const r = resolveTrick(trick(
    ['a', 'sk_yellow_13'], ['b', 'sk_pirate_2'], ['c', 'sk_white_whale'], ['d', 'sk_kraken'],
  ));
  check('무효', r.voided === true);
  check('다음 선은 해적을 낸 사람', r.winnerId === 'b', `winner=${r.winnerId}`);
}

console.log('\n[먼저 나온 쪽은 도주다 — 숫자 판정에 끼지 않는다]');
{
  // 크라켄 → 흰고래. 숫자는 노랑2 하나뿐이므로 그게 가져간다.
  const r = resolveTrick(trick(
    ['a', 'sk_kraken'], ['b', 'sk_yellow_2'], ['c', 'sk_white_whale'],
  ));
  check('숫자가 하나면 그 사람이 가져간다', r.voided === false && r.winnerId === 'b',
    `voided=${r.voided} winner=${r.winnerId}`);
}
{
  // 흰고래가 먼저여도 마찬가지로 아무 일도 하지 않는다 — 크라켄이 무효로 만든다.
  const r = resolveTrick(trick(
    ['a', 'sk_white_whale'], ['b', 'sk_yellow_2'], ['c', 'sk_kraken'],
  ));
  check('흰고래가 먼저면 숫자 규칙이 적용되지 않는다', r.voided === true,
    `voided=${r.voided}`);
}

console.log('\n[티그리스를 도주로 낸 것과 섞여도]');
{
  const r = resolveTrick([
    { playerId: 'a', cardId: 'sk_tigress_1', tigressChoice: 'escape' },
    { playerId: 'b', cardId: 'sk_kraken' },
    { playerId: 'c', cardId: 'sk_white_whale' },
    { playerId: 'd', cardId: 'sk_green_7' },
  ]);
  check('흰고래가 적용되고 숫자가 가져간다',
    r.voided === false && r.winnerId === 'd', `voided=${r.voided} winner=${r.winnerId}`);
}

console.log(failures === 0 ? '\n전부 통과\n' : `\n${failures}건 실패\n`);
process.exit(failures === 0 ? 0 : 1);
