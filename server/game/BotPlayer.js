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
    if (cards.includes('special_bird')) {
      const ranks = ['2','3','4','5','6','7','8','9','10','J','Q','K','A'];
      const wish = ranks[Math.floor(Math.random() * ranks.length)];
      return { type: 'play_cards', cards: ['special_bird'], callRank: wish };
    }
    // S28: Only play Dog if partner hasn't finished yet
    if (cards.includes('special_dog')) {
      const players = state.players || [];
      const partner = players.find(p => p.position === 'partner');
      if (partner && !partner.hasFinished) {
        return { type: 'play_cards', cards: ['special_dog'] };
      }
    }
    if (combos.pairs.length > 0 && Math.random() < 0.4) {
      return { type: 'play_cards', cards: combos.pairs[0] };
    }
    if (normalCards.length > 0) {
      return { type: 'play_cards', cards: [normalCards[0]] };
    }
    const playable = cards.filter(c => c !== 'special_dog');
    if (playable.length > 0) {
      return { type: 'play_cards', cards: [playable[0]] };
    }
    return null;
  }

  // Following a trick
  const lastPlay = trick[trick.length - 1];
  const comboType = lastPlay.combo;
  const lastValue = lastPlay.comboValue || getHighestValue(
    lastPlay.cards.filter(c => c !== 'special_phoenix')
  );

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
    // S9/S10: Phoenix can beat any single except dragon
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

  return { type: 'pass' };
}

function selectExchangeCards(cards) {
  // S8: Ensure no duplicate card selections
  const normalCards = cards.filter(c => !c.startsWith('special_'));
  const sorted = [...normalCards].sort((a, b) => getCardValue(b) - getCardValue(a));
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
  const partner = pick(sorted, cards);
  const right = pick(low.slice(1), cards);

  return { left, partner, right };
}

function findCombos(cards) {
  const result = { pairs: [], triples: [] };
  const byValue = {};
  for (const card of cards) {
    const v = getCardValue(card);
    if (!byValue[v]) byValue[v] = [];
    byValue[v].push(card);
  }
  for (const group of Object.values(byValue)) {
    if (group.length >= 2) result.pairs.push([group[0], group[1]]);
    if (group.length >= 3) result.triples.push([group[0], group[1], group[2]]);
  }
  return result;
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
