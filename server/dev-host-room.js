/**
 * Dev tool: host a Tichu room full of bots and keep playing it.
 *
 * The spectator screens can only be looked at while a game is actually running,
 * and a room whose host sits idle gets deserted after three turn timeouts — so
 * iterating on that UI meant re-creating a room every couple of minutes. This
 * logs in as a dedicated account, creates a room, fills it with bots, starts the
 * game, and then plays the host's own hand with the same rough heuristics the
 * test bots use, so the room stays alive indefinitely.
 *
 * It also declares Large/Small Tichu now and then, because those badges are part
 * of what the spectator board has to render.
 *
 * Tichu only: the auto-play below understands Tichu's protocol and nothing else.
 *
 *   node dev-host-room.js                     # ws://localhost:8080, slow bots
 *   node dev-host-room.js ws://host:8080 fast
 *
 * Leaves one account behind (dev_host_room / 자동호스트). Local databases only —
 * never point this at production.
 */

const WebSocket = require('ws');

const SERVER_URL = process.argv[2] || 'ws://localhost:8080';
const BOT_SPEED = process.argv[3] || 'slow';
const ACCOUNT = { username: 'dev_host_room', password: 'devhost1234!', nickname: '자동호스트' };
const ROOM_NAME = process.env.ROOM_NAME || '티츄관전';
const BOT_COUNT = 3;
const BOT_NAMES = [ACCOUNT.nickname];

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
      // A dev tool that swallows an auth failure just sits there connected and
      // silent, which is exactly what happened the first time this ran (an older
      // test account still held the nickname).
      case 'register_result':
        if (!data.success) this.log(`register: ${data.message}`);
        break;

      case 'login_error':
        this.log(`LOGIN FAILED: ${data.message}`);
        process.exit(1);
        break;

      case 'login_success':
        this.playerId = data.playerId;
        this.log(`Logged in as ${data.playerId}`);
        // The server may restore the previous room right after login. Give that
        // a beat to arrive: creating a room while already in one is refused, and
        // reconnecting into the running game is what we want anyway.
        setTimeout(() => {
          if (this.roomId) {
            this.log(`Reconnected into ${this.roomId} — keeping it`);
            return;
          }
          this.send({ type: 'create_room', roomName: ROOM_NAME, gameType: 'tichu' });
        }, 900);
        break;

      // Inherited from the join-a-room test bot this started as: it would see
      // the lobby list and try to join someone else's room, which the server
      // rightly refuses ("already in a room"). This tool hosts, never joins.
      case 'room_list':
        break;

      // Without this the reconnect guard above never sees a room id and tries to
      // create one anyway.
      case 'reconnected':
        this.roomId = data.roomId;
        this.log(`Reconnected: ${data.roomName || data.roomId}`);
        break;

      case 'room_joined':
        this.roomId = data.roomId;
        this.log(`Created room: ${data.roomName}`);
        let n = 0;
        const addBot = () => {
          if (n++ >= BOT_COUNT) {
            setTimeout(() => { this.log('start_game'); this.send({ type: 'start_game' }); }, 800);
            return;
          }
          this.send({ type: 'add_bot', speed: BOT_SPEED });
          setTimeout(addBot, 400);
        };
        addBot();
        break;

      case 'room_state':
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
      if (phase === 'large_tichu_phase') this._smallTried = false;
    }

    switch (phase) {
      case 'large_tichu_phase':
        if (!state.largeTichuResponded && !this._actedThisPhase) {
          this._actedThisPhase = true;
          setTimeout(() => {
            // 관전 화면의 티츄 배지를 확인하려면 실제로 선언이 있어야 한다.
            if (Math.random() < 0.4) {
              this.log('Declaring LARGE Tichu');
              this.send({ type: 'declare_large_tichu' });
            } else {
              this.log('Passing Large Tichu');
              this.send({ type: 'pass_large_tichu' });
            }
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
        if (!this._smallTried && this.myCards.length === 14) {
          this._smallTried = true;
          if (Math.random() < 0.5) {
            this.log('Declaring SMALL Tichu');
            this.send({ type: 'declare_small_tichu' });
          }
        }
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
  console.log(`\n[dev-host-room] ${SERVER_URL} — room "${ROOM_NAME}", ${BOT_COUNT} ${BOT_SPEED} bots`);
  console.log('[dev-host-room] Spectate it from the app; Ctrl-C to stop.\n');

  const bots = BOT_NAMES.map((name, i) => new Bot(name, i));

  for (const bot of bots) {
    await bot.connect();
    await sleep(300);
  }

  for (const bot of bots) {
    // Register is a no-op after the first run ("already taken"); login is what
    // matters. appVersion is sent because the server gates non-Tichu game types
    // on it and a missing value reads as an ancient client.
    bot.send({ type: 'register', ...ACCOUNT });
    await sleep(600);
    bot.send({
      type: 'login',
      username: ACCOUNT.username,
      password: ACCOUNT.password,
      deviceInfo: { appVersion: '99.0.0', locale: 'ko' },
    });
    await sleep(400);
  }

  // 방을 계속 유지한다 (관전 대상)

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
