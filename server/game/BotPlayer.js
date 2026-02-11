/**
 * Server-integrated Bot Player
 * AI logic based on test_3bots_join.js, but runs inside the server process.
 */

class BotPlayer {
  constructor(id, nickname) {
    this.id = id;           // 'bot_1', 'bot_2', ...
    this.nickname = nickname; // '봇 1', '봇 2', ...
    this.isBot = true;
  }
}

/**
 * Determine what action (if any) the bot should take given the current game state.
 * Accesses game internals directly for dragonPending to avoid per-player view issues.
 * Returns { type, ... } or null if no action needed.
 */
function decideBotAction(game, botId) {
  const state = game.getStateForPlayer(botId);
  const phase = state.phase;
  const myCards = state.myCards || [];

  switch (phase) {
    case 'large_tichu_phase':
      if (!state.largeTichuResponded) {
        return { type: 'pass_large_tichu' };
      }
      break;

    case 'card_exchange':
      if (!state.exchangeDone && myCards.length >= 3) {
        return { type: 'exchange_cards', cards: selectExchangeCards(myCards) };
      }
      break;

    case 'playing':
      // Bot needs to call a rank (played bird in a combo without callRank)
      if (state.needsToCallRank) {
        const ranks = ['2','3','4','5','6','7','8','9','10','J','Q','K','A'];
        const rank = ranks[Math.floor(Math.random() * ranks.length)];
        return { type: 'call_rank', rank };
      }
      // Check game-level dragonPending (blocks all play_cards)
      if (game.dragonPending) {
        if (game.dragonDecider === botId) {
          const target = Math.random() > 0.5 ? 'left' : 'right';
          return { type: 'dragon_give', target };
        }
        // Another player must decide; this bot can't act
        return null;
      }
      if (state.isMyTurn) {
        return autoPlay(state, myCards);
      }
      break;

    // round_end / game_end: bots do nothing (host handles next_round)
  }

  return null;
}

function autoPlay(state, cards) {
  const trick = state.currentTrick || [];
  const callRank = state.callRank;

  if (cards.length === 0) return null;

  const normalCards = cards.filter(c => !c.startsWith('special_'));
  const combos = findCombos(normalCards);

  // Fulfill a call if needed
  if (callRank) {
    const calledCards = normalCards.filter(c => {
      const rank = c.split('_')[1];
      return rank === callRank;
    });
    if (calledCards.length > 0) {
      if (trick.length === 0) {
        return { type: 'play_cards', cards: [calledCards[0]] };
      }
      const lastPlay = trick[trick.length - 1];
      if (lastPlay.combo === 'single') {
        const lastValue = lastPlay.comboValue || 0;
        const calledValue = getCardValue(calledCards[0]);
        if (calledValue > lastValue) {
          return { type: 'play_cards', cards: [calledCards[0]] };
        }
      }
    }
  }

  // Leading a trick
  if (trick.length === 0) {
    return leadTrick(state, cards, normalCards, combos);
  }

  // Following a trick
  return followTrick(state, cards, normalCards, combos);
}

function leadTrick(state, cards, normalCards, combos) {
  // Bird first
  if (cards.includes('special_bird')) {
    const ranks = ['2','3','4','5','6','7','8','9','10','J','Q','K','A'];
    const wish = ranks[Math.floor(Math.random() * ranks.length)];
    return { type: 'play_cards', cards: ['special_bird'], callRank: wish };
  }

  // Dog: only if partner hasn't finished
  if (cards.includes('special_dog')) {
    const players = state.players || [];
    const partner = players.find(p => p.position === 'partner');
    if (partner && !partner.hasFinished) {
      return { type: 'play_cards', cards: ['special_dog'] };
    }
  }

  // Try multi-card combos: straights > full houses > steps > triples > pairs
  // Pick randomly among available combos for variety
  const options = [];

  if (combos.straights.length > 0) {
    options.push({ weight: 3, play: combos.straights[0] });
  }
  if (combos.fullHouses.length > 0) {
    options.push({ weight: 3, play: combos.fullHouses[0] });
  }
  if (combos.steps.length > 0) {
    options.push({ weight: 2, play: combos.steps[0] });
  }
  if (combos.triples.length > 0) {
    options.push({ weight: 2, play: combos.triples[0] });
  }
  if (combos.pairs.length > 0) {
    options.push({ weight: 2, play: combos.pairs[0] });
  }

  // Play a multi-card combo ~60% of the time if available
  if (options.length > 0 && Math.random() < 0.6) {
    const totalWeight = options.reduce((s, o) => s + o.weight, 0);
    let r = Math.random() * totalWeight;
    for (const opt of options) {
      r -= opt.weight;
      if (r <= 0) {
        return { type: 'play_cards', cards: opt.play };
      }
    }
    return { type: 'play_cards', cards: options[0].play };
  }

  // Single card fallback
  if (normalCards.length > 0) {
    return { type: 'play_cards', cards: [normalCards[0]] };
  }

  // Only special cards left — play anything except dog (if partner finished)
  const playable = cards.filter(c => c !== 'special_dog');
  if (playable.length > 0) {
    return { type: 'play_cards', cards: [playable[0]] };
  }

  // Only dog remains and partner has finished — must still play it
  return { type: 'play_cards', cards: [cards[0]] };
}

function followTrick(state, cards, normalCards, combos) {
  const trick = state.currentTrick || [];
  const lastPlay = trick[trick.length - 1];
  const comboType = lastPlay.combo;
  const lastValue = lastPlay.comboValue || getHighestValue(
    lastPlay.cards.filter(c => c !== 'special_phoenix')
  );
  const lastLength = lastPlay.cards.length;

  // If partner played last, just pass
  const players = state.players || [];
  const partner = players.find(p => p.position === 'partner');
  if (partner && lastPlay.playerId === partner.id) {
    return { type: 'pass' };
  }

  if (comboType === 'single') {
    for (const card of normalCards) {
      if (getCardValue(card) > lastValue) {
        return { type: 'play_cards', cards: [card] };
      }
    }
    if (cards.includes('special_phoenix') && lastValue < 15) {
      return { type: 'play_cards', cards: ['special_phoenix'] };
    }
    if (cards.includes('special_dragon') && lastValue < 15) {
      return { type: 'play_cards', cards: ['special_dragon'] };
    }
  }

  if (comboType === 'pair') {
    for (const pair of combos.pairs) {
      if (getCardValue(pair[0]) > lastValue) {
        return { type: 'play_cards', cards: pair };
      }
    }
  }

  if (comboType === 'triple') {
    for (const triple of combos.triples) {
      if (getCardValue(triple[0]) > lastValue) {
        return { type: 'play_cards', cards: triple };
      }
    }
  }

  if (comboType === 'straight') {
    for (const straight of combos.straights) {
      if (straight.length === lastLength) {
        const highVal = getHighestValue(straight);
        if (highVal > lastValue) {
          return { type: 'play_cards', cards: straight };
        }
      }
    }
  }

  if (comboType === 'full_house') {
    for (const fh of combos.fullHouses) {
      const fhTripleVal = getFullHouseTripleValue(fh);
      if (fhTripleVal > lastValue) {
        return { type: 'play_cards', cards: fh };
      }
    }
  }

  if (comboType === 'steps') {
    for (const step of combos.steps) {
      if (step.length === lastLength) {
        const highVal = getHighestValue(step);
        if (highVal > lastValue) {
          return { type: 'play_cards', cards: step };
        }
      }
    }
  }

  // Try bombs against any combo type
  for (const bomb of combos.bombs) {
    return { type: 'play_cards', cards: bomb };
  }

  return { type: 'pass' };
}

function selectExchangeCards(cards) {
  // S8: Ensure no duplicate card selections
  const normalCards = cards.filter(c => !c.startsWith('special_'));
  // Partner gets best card — include dragon/phoenix as candidates
  const allForPartner = cards.filter(c => c !== 'special_dog' && c !== 'special_bird');
  const sortedForPartner = [...allForPartner].sort((a, b) => getCardValue(b) - getCardValue(a));
  const low = [...normalCards].sort((a, b) => getCardValue(a) - getCardValue(b));

  const used = new Set();
  function pick(candidates, fallback) {
    for (const c of candidates) {
      if (!used.has(c)) { used.add(c); return c; }
    }
    for (const c of fallback) {
      if (!used.has(c)) { used.add(c); return c; }
    }
    return fallback[0]; // should never happen with 14-card hand
  }

  const left = pick(low, cards);
  const partner = pick(sortedForPartner, cards);
  const right = pick(low.slice(1), cards);

  return { left, partner, right };
}

function findCombos(cards) {
  const result = { pairs: [], triples: [], straights: [], fullHouses: [], steps: [], bombs: [] };

  // Group cards by value
  const byValue = {};
  for (const card of cards) {
    const v = getCardValue(card);
    if (!byValue[v]) byValue[v] = [];
    byValue[v].push(card);
  }

  // Pairs, triples, four-of-a-kind bombs
  const values = Object.keys(byValue).map(Number).sort((a, b) => a - b);
  for (const v of values) {
    const group = byValue[v];
    if (group.length >= 2) result.pairs.push([group[0], group[1]]);
    if (group.length >= 3) result.triples.push([group[0], group[1], group[2]]);
    if (group.length === 4) result.bombs.push([group[0], group[1], group[2], group[3]]);
  }

  // Straights (5+ consecutive, no duplicates)
  if (values.length >= 5) {
    // Find all consecutive runs
    let runStart = 0;
    for (let i = 1; i <= values.length; i++) {
      if (i === values.length || values[i] !== values[i - 1] + 1) {
        const runLen = i - runStart;
        if (runLen >= 5) {
          // Take the shortest valid straight (5 cards) from this run
          const straightCards = [];
          for (let j = runStart; j < runStart + 5; j++) {
            straightCards.push(byValue[values[j]][0]);
          }
          result.straights.push(straightCards);
          // Also add the full run if longer
          if (runLen > 5) {
            const fullStraight = [];
            for (let j = runStart; j < i; j++) {
              fullStraight.push(byValue[values[j]][0]);
            }
            result.straights.push(fullStraight);
          }
        }
        runStart = i;
      }
    }
  }

  // Full houses (triple + pair, different values)
  for (const triple of result.triples) {
    const tripleVal = getCardValue(triple[0]);
    for (const pair of result.pairs) {
      const pairVal = getCardValue(pair[0]);
      if (pairVal !== tripleVal) {
        result.fullHouses.push([...pair, ...triple]);
        break; // one full house per triple is enough
      }
    }
  }

  // Steps (consecutive pairs, 2+ pairs)
  if (result.pairs.length >= 2) {
    const pairValues = result.pairs.map(p => getCardValue(p[0])).sort((a, b) => a - b);
    // Find consecutive pair runs
    let runStart = 0;
    for (let i = 1; i <= pairValues.length; i++) {
      if (i === pairValues.length || pairValues[i] !== pairValues[i - 1] + 1) {
        const runLen = i - runStart;
        if (runLen >= 2) {
          const stepCards = [];
          for (let j = runStart; j < i; j++) {
            const pv = pairValues[j];
            const group = byValue[pv];
            stepCards.push(group[0], group[1]);
          }
          result.steps.push(stepCards);
        }
        runStart = i;
      }
    }
  }

  // Sort combos by value (lowest first) so bot plays weakest first
  result.pairs.sort((a, b) => getCardValue(a[0]) - getCardValue(b[0]));
  result.triples.sort((a, b) => getCardValue(a[0]) - getCardValue(b[0]));
  result.straights.sort((a, b) => getHighestValue(a) - getHighestValue(b));
  result.fullHouses.sort((a, b) => getFullHouseTripleValue(a) - getFullHouseTripleValue(b));
  result.steps.sort((a, b) => getHighestValue(a) - getHighestValue(b));

  return result;
}

function getFullHouseTripleValue(cards) {
  // Full house: find the value that appears 3 times
  const counts = {};
  for (const c of cards) {
    const v = getCardValue(c);
    counts[v] = (counts[v] || 0) + 1;
  }
  for (const [v, cnt] of Object.entries(counts)) {
    if (cnt === 3) return Number(v);
  }
  // Fallback: highest value
  return getHighestValue(cards);
}

function getHighestValue(cards) {
  if (!cards || cards.length === 0) return 0;
  return Math.max(...cards.map(c => getCardValue(c)));
}

function getCardValue(cardId) {
  if (cardId === 'special_bird') return 1;
  if (cardId === 'special_dog') return 0;
  if (cardId === 'special_phoenix') return 14.5;
  if (cardId === 'special_dragon') return 15;
  const rankValues = { '2':2,'3':3,'4':4,'5':5,'6':6,'7':7,'8':8,'9':9,'10':10,'J':11,'Q':12,'K':13,'A':14 };
  const rank = cardId.split('_')[1];
  return rankValues[rank] || 0;
}

module.exports = { BotPlayer, decideBotAction };
