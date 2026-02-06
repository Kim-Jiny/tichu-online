const WebSocket = require('ws');
const ws = new WebSocket('ws://localhost:8080');
let requested = false;

ws.on('open', () => {
  ws.send(JSON.stringify({ type: 'login', nickname: 'spectator_test' }));
});

ws.on('message', (data) => {
  const msg = JSON.parse(data.toString());
  console.log('Received:', msg.type);
  
  if (msg.type === 'login_success') {
    ws.send(JSON.stringify({ type: 'spectate_room', roomId: 'room_1' }));
  }
  
  if (msg.type === 'spectator_game_state') {
    console.log('=== Spectator State ===');
    msg.state.players?.forEach(p => {
      console.log('  Player:', p.name, '| canSeeCards:', p.canSeeCards, '| cardCount:', p.cardCount, '| cards:', p.cards?.length || 0);
    });
    
    if (!requested) {
      requested = true;
      console.log('\nRequesting to see player_1 cards...');
      ws.send(JSON.stringify({ type: 'request_card_view', playerId: 'player_1' }));
    }
  }
  
  if (msg.type === 'card_view_requested') {
    console.log('Request sent for player:', msg.playerId);
    ws.close();
  }
  
  if (msg.type === 'error') {
    console.log('Error:', msg.message);
  }
});

setTimeout(() => ws.close(), 5000);
