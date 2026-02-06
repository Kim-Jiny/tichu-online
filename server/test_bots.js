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
            // Pick 3 random cards to exchange
            const shuffled = [...this.myCards].sort(() => Math.random() - 0.5);
            const cards = {
              left: shuffled[0],
              partner: shuffled[1],
              right: shuffled[2],
            };
            this.log(`Exchanging cards: ${shuffled[0]}, ${shuffled[1]}, ${shuffled[2]}`);
            this.send({ type: 'exchange_cards', cards });
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
        this.log(`GAME OVER! Final: Team A=${state.totalScores.teamA}, Team B=${state.totalScores.teamB}`);
        break;
    }
  }

  autoPlay(state) {
    const trick = state.currentTrick || [];
    const cards = this.myCards;

    if (cards.length === 0) return;

    // If starting new trick (no cards on table)
    if (trick.length === 0) {
      // Must play bird if we have it
      if (cards.includes('special_bird')) {
        this.log('Playing Bird');
        this.send({ type: 'play_cards', cards: ['special_bird'] });
        // Call a random rank
        setTimeout(() => {
          const ranks = ['2','3','4','5','6','7','8','9','10','J','Q','K','A'];
          const wish = ranks[Math.floor(Math.random() * ranks.length)];
          this.log(`Calling ${wish}`);
          this.send({ type: 'call_rank', rank: wish });
        }, 200);
        return;
      }

      // Play dog if we have it (gives turn to partner)
      if (cards.includes('special_dog')) {
        this.log('Playing Dog');
        this.send({ type: 'play_cards', cards: ['special_dog'] });
        return;
      }

      // Play lowest single card
      const playable = cards.filter(c => c !== 'special_dog');
      if (playable.length > 0) {
        this.log(`Playing: ${playable[0]}`);
        this.send({ type: 'play_cards', cards: [playable[0]] });
        return;
      }
    }

    // Cards on table: try to beat with a single higher card, or pass
    if (trick.length > 0) {
      const lastPlay = trick[trick.length - 1];
      const lastCombo = lastPlay.combo;

      if (lastCombo === 'single') {
        // Try to play a higher single card
        const lastCards = lastPlay.cards;
        const lastValue = this.getCardValue(lastCards[0]);

        for (const card of cards) {
          if (card === 'special_dog') continue;
          const val = this.getCardValue(card);
          if (val > lastValue) {
            this.log(`Playing: ${card} (beats ${lastCards[0]})`);
            this.send({ type: 'play_cards', cards: [card] });
            return;
          }
        }
      }

      // Can't beat it, pass
      this.log('Passing');
      this.send({ type: 'pass' });
    }
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
