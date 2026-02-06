/**
 * 4 bots auto-play test: 1 bot creates room, 3 bots join
 */

const WebSocket = require('ws');

const SERVER_URL = process.argv[2] || 'ws://localhost:8080';
const BOT_NAMES = ['봇_호스트', '봇_알파', '봇_베타', '봇_감마'];

class Bot {
  constructor(name, index, isHost = false) {
    this.name = name;
    this.index = index;
    this.isHost = isHost;
    this.ws = null;
    this.playerId = null;
    this.roomId = null;
    this.state = null;
    this.myCards = [];
    this._teamLogged = false;
    this._lastPhase = null;
    this._actedThisPhase = false;
    this._gameStarted = false;
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
    const colors = ['\x1b[35m', '\x1b[36m', '\x1b[33m', '\x1b[32m'];
    const reset = '\x1b[0m';
    console.log(`${colors[this.index]}[${this.name}]${reset} ${msg}`);
  }

  handleMessage(data) {
    switch (data.type) {
      case 'login_success':
        this.playerId = data.playerId;
        this.log(`Logged in as ${data.playerId}`);
        if (this.isHost) {
          setTimeout(() => {
            this.log('Creating room...');
            this.send({ type: 'create_room', roomName: '봇테스트방' });
          }, 500);
        }
        break;

      case 'room_list':
        if (!this.roomId && !this.isHost && data.rooms.length > 0) {
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
        const players = data.room.players || [];
        if (this.isHost && players.length === 4 && !this._gameStarted) {
          this._gameStarted = true;
          this.log('4 players ready! Starting game...');
          setTimeout(() => {
            this.send({ type: 'start_game' });
          }, 1000);
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
        if (['cards_played', 'bomb_played', 'player_passed', 'dog_played',
             'trick_won', 'round_end', 'call_rank', 'dragon_given'].includes(data.type)) {
          this.log(`Event: ${data.type} ${data.playerName || ''}`);
        }
    }
  }

  handleGameState(state) {
    const phase = state.phase;
    const delay = 300 + Math.random() * 500;

    // Reset acted flag when phase changes
    if (phase !== this._lastPhase) {
      this._lastPhase = phase;
      this._actedThisPhase = false;
    }

    switch (phase) {
      case 'large_tichu_phase':
        if (!state.largeTichuResponded && !this._actedThisPhase) {
          this._actedThisPhase = true;
          setTimeout(() => {
            this.log('Passing Large Tichu');
            this.send({ type: 'pass_large_tichu' });
          }, delay);
        }
        break;

      case 'card_exchange':
        if (!state.exchangeDone && this.myCards.length >= 3 && !this._actedThisPhase) {
          this._actedThisPhase = true;
          setTimeout(() => {
            const exchangeCards = this.selectExchangeCards(this.myCards);
            this.log(`Exchanging: L=${exchangeCards.left}, P=${exchangeCards.partner}, R=${exchangeCards.right}`);
            this.send({ type: 'exchange_cards', cards: exchangeCards });
          }, delay);
        }
        break;

      case 'playing':
        if (state.dragonPending) {
          setTimeout(() => {
            const target = Math.random() > 0.5 ? 'left' : 'right';
            this.log(`Dragon give: ${target}`);
            this.send({ type: 'dragon_give', target });
          }, delay);
          return;
        }

        if (state.isMyTurn) {
          setTimeout(() => this.autoPlay(state), delay);
        }
        break;

      case 'round_end':
        this.log(`Round ended! Scores: Team A=${state.totalScores.teamA}, Team B=${state.totalScores.teamB}`);
        this._teamLogged = false;
        if (this.isHost) {
          setTimeout(() => {
            this.log('Starting next round...');
            this.send({ type: 'next_round' });
          }, 2000);
        }
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

    if (cards.length === 0) return;

    const normalCards = cards.filter(c => !c.startsWith('special_'));
    const combos = this.findCombos(normalCards);

    // Check if we need to fulfill a call
    if (callRank) {
      const calledCards = normalCards.filter(c => {
        const rank = c.split('_')[1];
        return rank === callRank;
      });
      if (calledCards.length > 0) {
        // Must play the called card if we can beat current trick or starting new
        if (trick.length === 0) {
          this.log(`Playing called rank ${callRank}`);
          this.send({ type: 'play_cards', cards: [calledCards[0]] });
          return;
        }
        const lastPlay = trick[trick.length - 1];
        if (lastPlay.combo === 'single') {
          const lastValue = lastPlay.comboValue || 0;
          const calledValue = this.getCardValue(calledCards[0]);
          if (calledValue > lastValue) {
            this.log(`Playing called rank ${callRank} to beat`);
            this.send({ type: 'play_cards', cards: [calledCards[0]] });
            return;
          }
        }
      }
    }

    if (trick.length === 0) {
      // Starting new trick
      if (cards.includes('special_bird')) {
        this.log('Playing Bird');
        const ranks = ['2','3','4','5','6','7','8','9','10','J','Q','K','A'];
        const wish = ranks[Math.floor(Math.random() * ranks.length)]
        this.send({ type: 'play_cards', cards: ['special_bird'], callRank: wish });
        return;
      }

      if (cards.includes('special_dog')) {
        this.log('Playing Dog');
        this.send({ type: 'play_cards', cards: ['special_dog'] });
        return;
      }

      // Play combos or singles
      if (combos.pairs.length > 0 && Math.random() < 0.4) {
        this.send({ type: 'play_cards', cards: combos.pairs[0] });
        return;
      }

      if (normalCards.length > 0) {
        this.send({ type: 'play_cards', cards: [normalCards[0]] });
        return;
      }

      const playable = cards.filter(c => c !== 'special_dog');
      if (playable.length > 0) {
        this.send({ type: 'play_cards', cards: [playable[0]] });
      }
      return;
    }

    // Try to beat current trick
    const lastPlay = trick[trick.length - 1];
    const comboType = lastPlay.combo;
    const lastValue = lastPlay.comboValue || this.getHighestValue(lastPlay.cards.filter(c => c !== 'special_phoenix'));

    // Check if partner played
    const players = state.players || [];
    const partner = players.find(p => p.position === 'partner');
    if (partner && lastPlay.playerId === partner.id) {
      this.log('Partner played, passing');
      this.send({ type: 'pass' });
      return;
    }

    if (comboType === 'single') {
      for (const card of normalCards) {
        if (this.getCardValue(card) > lastValue) {
          this.send({ type: 'play_cards', cards: [card] });
          return;
        }
      }
      if (cards.includes('special_dragon') && lastValue < 15) {
        this.send({ type: 'play_cards', cards: ['special_dragon'] });
        return;
      }
    }

    if (comboType === 'pair') {
      for (const pair of combos.pairs) {
        if (this.getCardValue(pair[0]) > lastValue) {
          this.send({ type: 'play_cards', cards: pair });
          return;
        }
      }
    }

    this.log(`Passing (combo: ${comboType})`);
    this.send({ type: 'pass' });
  }

  selectExchangeCards(cards) {
    const normalCards = cards.filter(c => !c.startsWith('special_'));
    const sorted = [...normalCards].sort((a, b) => this.getCardValue(b) - this.getCardValue(a));
    const low = [...normalCards].sort((a, b) => this.getCardValue(a) - this.getCardValue(b));

    return {
      left: low[0] || cards[0],
      partner: sorted[0] || cards[1],
      right: low[1] || cards[2],
    };
  }

  findCombos(cards) {
    const result = { pairs: [], triples: [] };
    const byValue = {};
    for (const card of cards) {
      const v = this.getCardValue(card);
      if (!byValue[v]) byValue[v] = [];
      byValue[v].push(card);
    }
    for (const group of Object.values(byValue)) {
      if (group.length >= 2) result.pairs.push([group[0], group[1]]);
      if (group.length >= 3) result.triples.push([group[0], group[1], group[2]]);
    }
    return result;
  }

  getHighestValue(cards) {
    return Math.max(...cards.map(c => this.getCardValue(c)));
  }

  getCardValue(cardId) {
    if (cardId === 'special_bird') return 1;
    if (cardId === 'special_dog') return 0;
    if (cardId === 'special_phoenix') return 14.5;
    if (cardId === 'special_dragon') return 15;
    const rankValues = { '2':2,'3':3,'4':4,'5':5,'6':6,'7':7,'8':8,'9':9,'10':10,'J':11,'Q':12,'K':13,'A':14 };
    const rank = cardId.split('_')[1];
    return rankValues[rank] || 0;
  }

  disconnect() {
    if (this.ws) this.ws.close();
  }
}

async function main() {
  console.log(`\n🤖 4 Bots Auto-Test - ${SERVER_URL}\n`);

  const bots = BOT_NAMES.map((name, i) => new Bot(name, i, i === 0));

  // Connect all bots
  for (const bot of bots) {
    await bot.connect();
    await sleep(300);
  }

  // Login all bots
  for (const bot of bots) {
    bot.send({ type: 'login', nickname: bot.name });
    await sleep(300);
  }

  await sleep(1000);

  // Non-host bots poll for rooms
  const pollInterval = setInterval(() => {
    for (const bot of bots) {
      if (!bot.isHost && !bot.roomId) {
        bot.send({ type: 'room_list' });
      }
    }
    if (bots.every(b => b.roomId)) {
      clearInterval(pollInterval);
      console.log('\n✅ All bots in room!\n');
    }
  }, 1000);

  console.log('\n🎮 Bots running! Press Ctrl+C to stop.\n');

  process.on('SIGINT', () => {
    console.log('\nShutting down...');
    bots.forEach(b => b.disconnect());
    process.exit(0);
  });
}

function sleep(ms) {
  return new Promise(r => setTimeout(r, ms));
}

main().catch(console.error);
