/**
 * Test bot script: 3 bots that join an existing room.
 * Usage: node test_bots.js [serverUrl]
 *
 * 1. 3 bots log in
 * 2. Bots look for existing rooms and join
 * 3. Host (real player) starts the game
 * 4. Bots auto-play through Large Tichu, Exchange, and Playing phases
 */

const WebSocket = require('ws');

const SERVER_URL = process.argv[2] || 'ws://localhost:8080';
const BOT_NAMES = ['봇_알파', '봇_베타', '봇_감마'];

class Bot {
  constructor(name, index) {
    this.name = name;
    this.index = index;
    this.ws = null;
    this.playerId = null;
    this.roomId = null;
    this.state = null;
    this.myCards = [];
  }

  connect() {
    return new Promise((resolve, reject) => {
      this.ws = new WebSocket(SERVER_URL);
      this.ws.on('open', () => {
        this.log('Connected');
        resolve();
      });
      this.ws.on('message', (raw) => {
        const data = JSON.parse(raw.toString());
        this.handleMessage(data);
      });
      this.ws.on('error', reject);
      this.ws.on('close', () => this.log('Disconnected'));
    });
  }

  send(data) {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(data));
    }
  }

  log(msg) {
    const colors = ['\x1b[36m', '\x1b[33m', '\x1b[32m', '\x1b[35m'];
    const reset = '\x1b[0m';
    console.log(`${colors[this.index]}[${this.name}]${reset} ${msg}`);
  }

  handleMessage(data) {
    switch (data.type) {
      case 'login_success':
        this.playerId = data.playerId;
        this.log(`Logged in as ${data.playerId}`);
        break;

      case 'room_list':
        // All bots look for room to join
        if (!this.roomId && data.rooms.length > 0) {
          // Find a room with space
          const room = data.rooms.find(r => r.playerCount < 4);
          if (room) {
            this.log(`Joining room: ${room.name}`);
            this.send({ type: 'join_room', roomId: room.id });
          }
        }
        break;

      case 'room_joined':
        this.roomId = data.roomId;
        this.log(`Joined room: ${data.roomName}`);
        break;

      case 'room_state':
        // If bot becomes host, leave the room
        const players = data.room.players || [];
        const me = players.find(p => p.id === this.playerId);
        if (me && me.isHost) {
          this.log('I became host, leaving room...');
          this.send({ type: 'leave_room' });
          this.roomId = null;
        }
        break;

      case 'game_state':
        this.state = data.state;
        this.myCards = data.state.myCards || [];
        this.handleGameState(data.state);
        break;

      case 'error':
        this.log(`ERROR: ${data.message}`);
        break;

      default:
        // Log game events
        if (['cards_played', 'bomb_played', 'player_passed', 'dog_played',
             'large_tichu_declared', 'large_tichu_passed', 'small_tichu_declared',
             'trick_won', 'round_end', 'call_rank', 'dragon_given'].includes(data.type)) {
          this.log(`Event: ${data.type} ${data.playerName || ''}`);
        }
    }
  }

  handleGameState(state) {
    const phase = state.phase;
    const delay = 300 + Math.random() * 700; // Random delay for realism

    this.log(`[STATE] phase=${phase}, myTurn=${state.isMyTurn}, cards=${this.myCards.length}`);

    switch (phase) {
      case 'large_tichu_phase':
        if (!state.largeTichuResponded) {
          setTimeout(() => {
            this.log('Passing Large Tichu');
            this.send({ type: 'pass_large_tichu' });
          }, delay);
        }
        break;

      case 'card_exchange':
        if (!state.exchangeDone && this.myCards.length >= 3) {
          setTimeout(() => {
            const exchangeCards = this.selectExchangeCards(this.myCards);
            this.log(`Exchanging: L=${exchangeCards.left}, P=${exchangeCards.partner}, R=${exchangeCards.right}`);
            this.send({ type: 'exchange_cards', cards: exchangeCards });
          }, delay);
        }
        break;

      case 'playing':
        this.log(`[PLAYING] dragonPending=${state.dragonPending}, isMyTurn=${state.isMyTurn}, callRank=${state.callRank}`);

        if (state.dragonPending) {
          setTimeout(() => {
            const target = Math.random() > 0.5 ? 'left' : 'right';
            this.log(`Dragon give: ${target}`);
            this.send({ type: 'dragon_give', target });
          }, delay);
          return;
        }

        if (state.isMyTurn) {
          this.log(`[MY TURN] I have ${this.myCards.length} cards, callRank=${state.callRank}`);
          this.callRank = state.callRank; // Store for autoPlay
          setTimeout(() => this.autoPlay(state), delay);
        }
        break;

      case 'round_end':
        this.log(`Round ended! Scores: Team A=${state.totalScores.teamA}, Team B=${state.totalScores.teamB}`);
        break;

      case 'game_end':
        this.log(`GAME OVER! Final: Team A=${state.totalScores.teamA}, Team B=${state.totalScores.teamB}`);
        break;
    }
  }

  autoPlay(state) {
    const trick = state.currentTrick || [];
    const cards = this.myCards;
    const callRank = state.callRank;

    if (cards.length === 0) {
      this.log('[autoPlay] No cards left');
      return;
    }

    const normalCards = cards.filter(c => !c.startsWith('special_'));
    const combos = this.findCombos(normalCards);

    // Check if we have the called rank
    const calledValue = this.rankToValue(callRank);
    const hasCalledRank = callRank && normalCards.some(c => this.getCardValue(c) === calledValue);
    if (callRank) {
      this.log(`[CALL] callRank=${callRank}, calledValue=${calledValue}, hasIt=${hasCalledRank}`);
    }

    // If starting new trick (no cards on table)
    if (trick.length === 0) {
      // Must play bird if we have it
      if (cards.includes('special_bird')) {
        this.log('Playing Bird');
        this.send({ type: 'play_cards', cards: ['special_bird'] });
        setTimeout(() => {
          const ranks = ['2','3','4','5','6','7','8','9','10','J','Q','K','A'];
          const wish = ranks[Math.floor(Math.random() * ranks.length)];
          this.log(`Calling ${wish}`);
          this.send({ type: 'call_rank', rank: wish });
        }, 200);
        return;
      }

      // Play dog if we have it
      if (cards.includes('special_dog')) {
        this.log('Playing Dog');
        this.send({ type: 'play_cards', cards: ['special_dog'] });
        return;
      }

      // Randomly choose to play a combo or single
      const rand = Math.random();

      // 30% chance to play straight if available
      if (rand < 0.3 && combos.straights.length > 0) {
        const straight = combos.straights[0];
        this.log(`Playing straight: ${straight.join(', ')}`);
        this.send({ type: 'play_cards', cards: straight });
        return;
      }

      // 30% chance to play triple if available
      if (rand < 0.6 && combos.triples.length > 0) {
        const triple = combos.triples[0];
        this.log(`Playing triple: ${triple.join(', ')}`);
        this.send({ type: 'play_cards', cards: triple });
        return;
      }

      // 30% chance to play pair if available
      if (rand < 0.9 && combos.pairs.length > 0) {
        const pair = combos.pairs[0];
        this.log(`Playing pair: ${pair.join(', ')}`);
        this.send({ type: 'play_cards', cards: pair });
        return;
      }

      // Play lowest single
      if (normalCards.length > 0) {
        this.log(`Playing: ${normalCards[0]}`);
        this.send({ type: 'play_cards', cards: [normalCards[0]] });
        return;
      }

      const playable = cards.filter(c => c !== 'special_dog');
      if (playable.length > 0) {
        this.log(`Playing: ${playable[0]}`);
        this.send({ type: 'play_cards', cards: [playable[0]] });
        return;
      }
      return;
    }

    // Cards on table: try to beat
    const lastPlay = trick[trick.length - 1];
    const lastCombo = lastPlay.combo;
    const lastCards = lastPlay.cards;

    // Check if partner played the last cards - if so, pass (don't beat teammate)
    const players = state.players || [];
    const partner = players.find(p => p.position === 'partner');

    // Debug: log team info
    if (!this._teamLogged) {
      this.log(`[TEAM] My partner: ${partner ? partner.name : 'NOT FOUND'}`);
      this.log(`[TEAM] Players: ${players.map(p => `${p.name}(${p.position})`).join(', ')}`);
      this._teamLogged = true;
    }

    if (partner && lastPlay.playerId === partner.id) {
      this.log('Partner played last, passing');
      this.send({ type: 'pass' });
      return;
    }

    // Use combo value from server (handles Phoenix correctly)
    const lastValue = lastPlay.comboValue || this.getHighestValue(lastCards.filter(c => c !== 'special_phoenix'));

    // Normalize combo type (might be object or string)
    const comboType = typeof lastCombo === 'object' ? lastCombo.type : lastCombo;
    this.log(`[Beat] combo=${comboType}, lastValue=${lastValue}, hasCalledRank=${hasCalledRank}`);

    try {
      if (comboType === 'single') {
        // If there's a call and we have it, try to play it first
        if (hasCalledRank) {
          const calledCards = normalCards.filter(c => this.getCardValue(c) === calledValue);
          for (const card of calledCards) {
            if (this.getCardValue(card) > lastValue) {
              this.log(`Playing called rank: ${card}`);
              this.send({ type: 'play_cards', cards: [card] });
              return;
            }
          }
        }

        // No call obligation or can't fulfill, play any higher card
        for (const card of normalCards) {
          if (this.getCardValue(card) > lastValue) {
            this.log(`Playing: ${card}`);
            this.send({ type: 'play_cards', cards: [card] });
            return;
          }
        }
        if (cards.includes('special_dragon') && lastValue < 15) {
          this.log('Playing Dragon');
          this.send({ type: 'play_cards', cards: ['special_dragon'] });
          return;
        }
      }

      if (comboType === 'pair') {
        // If there's a call, try to play a pair with the called rank
        if (hasCalledRank) {
          for (const pair of combos.pairs) {
            if (this.getCardValue(pair[0]) === calledValue && this.getCardValue(pair[0]) > lastValue) {
              this.log(`Playing called pair: ${pair.join(', ')}`);
              this.send({ type: 'play_cards', cards: pair });
              return;
            }
          }
        }

        for (const pair of combos.pairs) {
          const pairValue = this.getCardValue(pair[0]);
          if (pairValue > lastValue) {
            this.log(`Playing pair: ${pair.join(', ')} (value ${pairValue} > ${lastValue})`);
            this.send({ type: 'play_cards', cards: pair });
            return;
          }
        }
      }

      if (comboType === 'triple') {
        for (const triple of combos.triples) {
          const tripleValue = this.getCardValue(triple[0]);
          if (tripleValue > lastValue) {
            this.log(`Playing triple: ${triple.join(', ')}`);
            this.send({ type: 'play_cards', cards: triple });
            return;
          }
        }
      }

      if (comboType === 'straight') {
        const neededLength = lastCards.length;
        for (const straight of combos.straights) {
          if (straight.length === neededLength && this.getHighestValue(straight) > lastValue) {
            this.log(`Playing straight: ${straight.join(', ')}`);
            this.send({ type: 'play_cards', cards: straight });
            return;
          }
        }
      }

      // Full house, steps, bombs - just pass for now
      this.log(`Passing (combo: ${comboType}, value: ${lastValue})`);
      this.send({ type: 'pass' });
    } catch (err) {
      this.log(`[ERROR] ${err.message}`);
      this.send({ type: 'pass' });
    }
  }

  rankToValue(rank) {
    if (!rank) return 0;
    const map = { '2': 2, '3': 3, '4': 4, '5': 5, '6': 6, '7': 7, '8': 8, '9': 9, '10': 10, 'J': 11, 'Q': 12, 'K': 13, 'A': 14 };
    return map[rank] || parseInt(rank) || 0;
  }

  findCombos(cards) {
    const result = { pairs: [], triples: [], straights: [] };
    const byValue = {};

    for (const card of cards) {
      const v = this.getCardValue(card);
      if (!byValue[v]) byValue[v] = [];
      byValue[v].push(card);
    }

    // Find pairs and triples
    for (const v of Object.keys(byValue).sort((a, b) => a - b)) {
      const group = byValue[v];
      if (group.length >= 2) {
        result.pairs.push([group[0], group[1]]);
      }
      if (group.length >= 3) {
        result.triples.push([group[0], group[1], group[2]]);
      }
    }

    // Find straights (5+ consecutive)
    const values = Object.keys(byValue).map(Number).sort((a, b) => a - b);
    for (let start = 0; start < values.length; start++) {
      let straight = [byValue[values[start]][0]];
      for (let i = start + 1; i < values.length; i++) {
        if (values[i] === values[i - 1] + 1) {
          straight.push(byValue[values[i]][0]);
        } else {
          break;
        }
      }
      if (straight.length >= 5) {
        result.straights.push(straight);
      }
    }

    return result;
  }

  getHighestValue(cards) {
    return Math.max(...cards.map(c => this.getCardValue(c)));
  }

  getCardValue(cardId) {
    if (cardId === 'special_bird') return 1;
    if (cardId === 'special_dog') return 0;
    if (cardId === 'special_phoenix') return -1;
    if (cardId === 'special_dragon') return 15;
    const rankValues = {
      '2':2,'3':3,'4':4,'5':5,'6':6,'7':7,'8':8,'9':9,'10':10,'J':11,'Q':12,'K':13,'A':14
    };
    const rank = cardId.split('_')[1];
    return rankValues[rank] || 0;
  }

  selectExchangeCards(cards) {
    // Find cards that are part of a bomb (4 of a kind)
    const normalCards = cards.filter(c => !c.startsWith('special_'));
    const byValue = {};
    for (const card of normalCards) {
      const v = this.getCardValue(card);
      if (!byValue[v]) byValue[v] = [];
      byValue[v].push(card);
    }

    // Cards in a bomb (4 of same rank)
    const bombCards = new Set();
    for (const group of Object.values(byValue)) {
      if (group.length === 4) {
        group.forEach(c => bombCards.add(c));
      }
    }

    // For exchange sorting: Phoenix is valuable (treat as ~13)
    const exchangeValue = (c) => {
      if (c === 'special_phoenix') return 14.5; // Valuable wildcard
      if (c === 'special_dragon') return 15;
      if (c === 'special_dog') return 0;
      if (c === 'special_bird') return 1;
      return this.getCardValue(c);
    };

    // All cards sorted by value (highest first), excluding bombs
    const sortedCards = cards
      .filter(c => !bombCards.has(c))
      .sort((a, b) => exchangeValue(b) - exchangeValue(a));

    // Cards to give opponents (dog, bird, or low value cards)
    const badCards = cards.filter(c =>
      c === 'special_dog' || c === 'special_bird'
    );
    const lowCards = sortedCards.filter(c => !c.startsWith('special_')).reverse();

    const usedCards = new Set();

    // Partner gets highest non-bomb card (can be Dragon, Phoenix, or A/K)
    let partnerCard = null;
    for (const c of sortedCards) {
      if (!usedCards.has(c) && c !== 'special_dog' && c !== 'special_bird') {
        partnerCard = c;
        usedCards.add(c);
        break;
      }
    }
    // Fallback
    if (!partnerCard) {
      partnerCard = cards.find(c => !usedCards.has(c)) || cards[0];
      usedCards.add(partnerCard);
    }

    const pickForOpponent = () => {
      // Prefer giving dog or bird to opponents
      for (const sc of badCards) {
        if (!usedCards.has(sc)) {
          usedCards.add(sc);
          return sc;
        }
      }
      // Otherwise give lowest non-special card
      for (const lc of lowCards) {
        if (!usedCards.has(lc)) {
          usedCards.add(lc);
          return lc;
        }
      }
      // Fallback: any unused card
      for (const c of cards) {
        if (!usedCards.has(c)) {
          usedCards.add(c);
          return c;
        }
      }
      return cards[0];
    };

    const leftCard = pickForOpponent();
    const rightCard = pickForOpponent();

    this.log(`[Exchange] My cards: ${cards.slice(0, 5).join(', ')}...`);
    this.log(`[Exchange] Sorted top5: ${sortedCards.slice(0, 5).map(c => `${c}(${exchangeValue(c)})`).join(', ')}`);
    this.log(`[Exchange] Giving: L=${leftCard}(${exchangeValue(leftCard)}), P=${partnerCard}(${exchangeValue(partnerCard)}), R=${rightCard}(${exchangeValue(rightCard)})`);

    return {
      left: leftCard,
      partner: partnerCard,
      right: rightCard,
    };
  }

  disconnect() {
    if (this.ws) this.ws.close();
  }
}

async function main() {
  console.log(`\n🀄 Tichu Test Bots - Connecting to ${SERVER_URL}\n`);

  const bots = BOT_NAMES.map((name, i) => new Bot(name, i));

  // Connect all bots
  for (const bot of bots) {
    await bot.connect();
    await sleep(200);
  }

  // Login all bots
  for (const bot of bots) {
    bot.send({ type: 'login', nickname: bot.name });
    await sleep(200);
  }

  await sleep(500);

  // All bots poll for rooms until they join one
  const pollInterval = setInterval(() => {
    for (const bot of bots) {
      if (!bot.roomId) {
        bot.send({ type: 'room_list' });
      }
    }
    // Stop polling when all bots have joined
    if (bots.every(b => b.roomId)) {
      clearInterval(pollInterval);
      console.log('All bots joined a room!');
    }
  }, 2000);

  // Keep running
  console.log('\n✅ Bots running! Press Ctrl+C to stop.\n');

  process.on('SIGINT', () => {
    console.log('\nShutting down bots...');
    bots.forEach(b => b.disconnect());
    process.exit(0);
  });
}

function sleep(ms) {
  return new Promise(r => setTimeout(r, ms));
}

main().catch(console.error);
