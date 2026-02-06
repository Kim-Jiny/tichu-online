/**
 * 3 bots that join a user's room
 */

const WebSocket = require('ws');

const SERVER_URL = process.argv[2] || 'ws://localhost:8080';
const BOT_NAMES = ['봇_1', '봇_2', '봇_3'];

class Bot {
  constructor(name, index) {
    this.name = name;
    this.index = index;
    this.ws = null;
    this.playerId = null;
    this.roomId = null;
    this.state = null;
    this.myCards = [];
    this._lastPhase = null;
    this._actedThisPhase = false;
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
    const colors = ['\x1b[36m', '\x1b[33m', '\x1b[32m'];
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
        if (!this.roomId && data.rooms.length > 0) {
          // Find a room that's not full and not the bot test room
          const room = data.rooms.find(r => r.playerCount < 4 && !r.name.includes('봇테스트'));
          if (room) {
            this.log(`Found room: ${room.name} (${room.playerCount}/4)`);
            this.send({ type: 'join_room', roomId: room.id });
          }
        }
        break;

      case 'room_joined':
        this.roomId = data.roomId;
        this.log(`Joined room: ${data.roomName}`);
        break;

      case 'room_state':
        // Check if I became the host - if so, leave the room
        if (data.room && data.room.hostId === this.playerId) {
          this.log('I became host - leaving room');
          this.send({ type: 'leave_room' });
          this.roomId = null;
          this._lastPhase = null;
          this._actedThisPhase = false;
        }
        break;

      case 'room_left':
        this.log('Left room');
        this.roomId = null;
        break;

      case 'game_state':
        this.state = data.state;
        this.myCards = data.state.myCards || [];
        this.handleGameState(data.state);
        break;

      case 'card_view_request':
        // Auto-approve spectator requests
        this.log(`Spectator ${data.spectatorNickname} requested to see cards - auto approving`);
        this.send({ type: 'respond_card_view', spectatorId: data.spectatorId, allow: true });
        break;

      case 'error':
        this.log(`ERROR: ${data.message}`);
        break;
    }
  }

  handleGameState(state) {
    const phase = state.phase;
    const delay = 300 + Math.random() * 500;

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
            this.log(`Exchanging cards`);
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
        break;

      case 'game_end':
        this.log(`GAME OVER!`);
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
      if (cards.includes('special_bird')) {
        const ranks = ['2','3','4','5','6','7','8','9','10','J','Q','K','A'];
        const wish = ranks[Math.floor(Math.random() * ranks.length)];
        this.send({ type: 'play_cards', cards: ['special_bird'], callRank: wish });
        return;
      }

      if (cards.includes('special_dog')) {
        this.send({ type: 'play_cards', cards: ['special_dog'] });
        return;
      }

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

    const lastPlay = trick[trick.length - 1];
    const comboType = lastPlay.combo;
    const lastValue = lastPlay.comboValue || this.getHighestValue(lastPlay.cards.filter(c => c !== 'special_phoenix'));

    // Check if partner played
    const players = state.players || [];
    const partner = players.find(p => p.position === 'partner');
    if (partner && lastPlay.playerId === partner.id) {
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
  console.log(`\n🤖 3 Bots waiting to join your room - ${SERVER_URL}\n`);
  console.log('Create a room in the Flutter app, and these bots will join!\n');

  const bots = BOT_NAMES.map((name, i) => new Bot(name, i));

  for (const bot of bots) {
    await bot.connect();
    await sleep(300);
  }

  for (const bot of bots) {
    bot.send({ type: 'login', nickname: bot.name });
    await sleep(300);
  }

  // Poll for rooms (continuously - bots may leave if they become host)
  setInterval(() => {
    for (const bot of bots) {
      if (!bot.roomId) {
        bot.send({ type: 'room_list' });
      }
    }
  }, 1000);

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
