import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/player.dart';
import '../models/room.dart';
import '../models/game_state.dart';
import 'network_service.dart';

class GameService extends ChangeNotifier {
  final NetworkService _network;
  StreamSubscription? _subscription;

  // Player info
  String playerId = '';
  String playerName = '';

  // Room info
  String currentRoomId = '';
  String currentRoomName = '';
  List<Player> roomPlayers = [];
  bool isHost = false;

  // Room list
  List<Room> roomList = [];

  // Game state
  GameStateData? gameState;

  // Error message
  String? errorMessage;

  GameService(this._network) {
    _subscription = _network.messageStream.listen(_handleMessage);
  }

  void _handleMessage(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    if (type == null) return;

    switch (type) {
      case 'login_success':
        playerId = data['playerId'] ?? '';
        playerName = data['nickname'] ?? '';
        notifyListeners();
        break;

      case 'room_list':
        roomList = (data['rooms'] as List?)
                ?.map((r) => Room.fromJson(r))
                .toList() ??
            [];
        notifyListeners();
        break;

      case 'room_joined':
        currentRoomId = data['roomId'] ?? '';
        currentRoomName = data['roomName'] ?? '';
        notifyListeners();
        break;

      case 'room_left':
        currentRoomId = '';
        currentRoomName = '';
        roomPlayers = [];
        isHost = false;
        gameState = null;
        notifyListeners();
        break;

      case 'room_state':
        final room = data['room'] as Map<String, dynamic>?;
        if (room != null) {
          roomPlayers = (room['players'] as List?)
                  ?.map((p) => Player.fromJson(p))
                  .toList() ??
              [];
          isHost = roomPlayers.any((p) => p.id == playerId && p.isHost);
        }
        notifyListeners();
        break;

      case 'game_state':
        final state = data['state'] as Map<String, dynamic>?;
        if (state != null) {
          gameState = GameStateData.fromJson(state);
        }
        notifyListeners();
        break;

      case 'error':
        errorMessage = data['message'] as String?;
        notifyListeners();
        // Clear error after a delay
        Future.delayed(const Duration(seconds: 3), () {
          errorMessage = null;
          notifyListeners();
        });
        break;

      // Game events (for potential animations/sounds)
      case 'cards_played':
      case 'bomb_played':
      case 'player_passed':
      case 'dog_played':
      case 'trick_won':
      case 'round_end':
      case 'large_tichu_declared':
      case 'large_tichu_passed':
      case 'small_tichu_declared':
      case 'call_rank':
      case 'dragon_given':
        // Handle game events if needed
        notifyListeners();
        break;
    }
  }

  // Actions
  void login(String nickname) {
    playerName = nickname;
    _network.send({'type': 'login', 'nickname': nickname});
  }

  void requestRoomList() {
    _network.send({'type': 'room_list'});
  }

  void createRoom(String roomName) {
    _network.send({'type': 'create_room', 'roomName': roomName});
  }

  void joinRoom(String roomId) {
    _network.send({'type': 'join_room', 'roomId': roomId});
  }

  void leaveRoom() {
    _network.send({'type': 'leave_room'});
  }

  void startGame() {
    _network.send({'type': 'start_game'});
  }

  void playCards(List<String> cards) {
    _network.send({'type': 'play_cards', 'cards': cards});
  }

  void passTurn() {
    _network.send({'type': 'pass'});
  }

  void declareSmallTichu() {
    _network.send({'type': 'declare_small_tichu'});
  }

  void declareLargeTichu() {
    _network.send({'type': 'declare_large_tichu'});
  }

  void passLargeTichu() {
    _network.send({'type': 'pass_large_tichu'});
  }

  void exchangeCards(String left, String partner, String right) {
    _network.send({
      'type': 'exchange_cards',
      'cards': {'left': left, 'partner': partner, 'right': right}
    });
  }

  void dragonGive(String target) {
    _network.send({'type': 'dragon_give', 'target': target});
  }

  void callRank(String rank) {
    _network.send({'type': 'call_rank', 'rank': rank});
  }

  void nextRound() {
    _network.send({'type': 'next_round'});
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
