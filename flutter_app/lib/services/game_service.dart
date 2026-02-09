import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/player.dart';
import '../models/room.dart';
import '../models/game_state.dart';
import 'network_service.dart';

class GameService extends ChangeNotifier {
  final NetworkService _network;
  StreamSubscription? _subscription;
  Timer? _dogDelayTimer;
  Timer? _dogClearTimer;
  DateTime? _dogDelayUntil;
  Map<String, dynamic>? _pendingGameState;

  // Player info
  String playerId = '';
  String playerName = '';

  // Room info
  String currentRoomId = '';
  String currentRoomName = '';
  List<Player> roomPlayers = [];
  bool isHost = false;
  bool isRankedRoom = false;

  // Room list
  List<Room> roomList = [];
  List<Room> spectatableRooms = [];

  // Spectator mode
  bool isSpectator = false;
  Map<String, dynamic>? spectatorGameState;
  Set<String> pendingCardViewRequests = {}; // player IDs we've requested
  Set<String> approvedCardViews = {}; // player IDs that approved

  // Incoming card view requests (for players)
  List<Map<String, String>> incomingCardViewRequests = []; // [{spectatorId, spectatorNickname}]

  // Game state
  GameStateData? gameState;

  // Error message
  String? errorMessage;

  // Auth state
  String? loginError;
  String? registerResult;
  bool? nicknameAvailable;
  String? nicknameCheckMessage;

  // Dog play UI
  bool dogPlayActive = false;
  String dogPlayPlayerName = '';

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
        loginError = null;
        notifyListeners();
        break;

      case 'login_error':
        loginError = data['message'] ?? '로그인 실패';
        notifyListeners();
        break;

      case 'register_result':
        registerResult = data['message'] ?? '';
        notifyListeners();
        break;

      case 'nickname_check_result':
        nicknameAvailable = data['available'] ?? false;
        nicknameCheckMessage = data['message'] ?? '';
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
        isSpectator = false;
        notifyListeners();
        break;

      case 'reconnected':
        currentRoomId = data['roomId'] ?? '';
        currentRoomName = data['roomName'] ?? '';
        isSpectator = false;
        notifyListeners();
        break;

      case 'spectate_joined':
        currentRoomId = data['roomId'] ?? '';
        currentRoomName = data['roomName'] ?? '';
        isSpectator = true;
        notifyListeners();
        break;

      case 'spectatable_rooms':
        spectatableRooms = (data['rooms'] as List?)
                ?.map((r) => Room.fromJson(r))
                .toList() ??
            [];
        notifyListeners();
        break;

      case 'spectator_game_state':
        final state = data['state'] as Map<String, dynamic>?;
        if (state != null) {
          spectatorGameState = state;
        }
        notifyListeners();
        break;

      case 'card_view_requested':
        // Confirmation that our request was sent
        final reqPlayerId = data['playerId'] as String?;
        if (reqPlayerId != null) {
          pendingCardViewRequests.add(reqPlayerId);
        }
        notifyListeners();
        break;

      case 'card_view_response':
        // Player responded to our request
        final respPlayerId = data['playerId'] as String?;
        final allowed = data['allowed'] == true;
        if (respPlayerId != null) {
          pendingCardViewRequests.remove(respPlayerId);
          if (allowed) {
            approvedCardViews.add(respPlayerId);
          }
        }
        notifyListeners();
        break;

      case 'card_view_request':
        // A spectator is requesting to see our cards
        final spectatorId = data['spectatorId'] as String?;
        final spectatorNickname = data['spectatorNickname'] as String?;
        if (spectatorId != null && spectatorNickname != null) {
          // Remove duplicate if exists
          incomingCardViewRequests.removeWhere((r) => r['spectatorId'] == spectatorId);
          incomingCardViewRequests.add({
            'spectatorId': spectatorId,
            'spectatorNickname': spectatorNickname,
          });
        }
        notifyListeners();
        break;

      case 'room_left':
        currentRoomId = '';
        currentRoomName = '';
        roomPlayers = [];
        isHost = false;
        isRankedRoom = false;
        isSpectator = false;
        gameState = null;
        spectatorGameState = null;
        pendingCardViewRequests = {};
        approvedCardViews = {};
        incomingCardViewRequests = [];
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
          isRankedRoom = room['isRanked'] == true;
        }
        notifyListeners();
        break;

      case 'game_state':
        final state = data['state'] as Map<String, dynamic>?;
        if (state != null) {
          _applyGameStateWithDogDelay(state);
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
      case 'dog_played':
        _handleDogPlayed(data);
        notifyListeners();
        break;
      case 'cards_played':
      case 'bomb_played':
      case 'player_passed':
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

  void _handleDogPlayed(Map<String, dynamic> data) {
    dogPlayActive = true;
    dogPlayPlayerName = (data['playerName'] as String?) ?? '';
    _dogDelayUntil = DateTime.now().add(const Duration(seconds: 2));

    _dogClearTimer?.cancel();
    _dogClearTimer = Timer(const Duration(seconds: 2), () {
      dogPlayActive = false;
      dogPlayPlayerName = '';
      notifyListeners();
    });
  }

  void _applyGameStateWithDogDelay(Map<String, dynamic> state) {
    if (_dogDelayUntil == null) {
      gameState = GameStateData.fromJson(state);
      return;
    }

    final now = DateTime.now();
    if (now.isAfter(_dogDelayUntil!)) {
      _dogDelayUntil = null;
      gameState = GameStateData.fromJson(state);
      return;
    }

    _pendingGameState = state;
    _dogDelayTimer?.cancel();
    final remaining = _dogDelayUntil!.difference(now);
    _dogDelayTimer = Timer(remaining, () {
      if (_pendingGameState != null) {
        gameState = GameStateData.fromJson(_pendingGameState!);
        _pendingGameState = null;
        _dogDelayUntil = null;
        notifyListeners();
      }
    });
  }

  // Actions
  void login(String nickname) {
    // Guest login (development mode)
    playerName = nickname;
    loginError = null;
    _network.send({'type': 'login', 'nickname': nickname});
  }

  void loginWithCredentials(String username, String password) {
    loginError = null;
    _network.send({'type': 'login', 'username': username, 'password': password});
  }

  void register(String username, String password, String nickname) {
    registerResult = null;
    _network.send({
      'type': 'register',
      'username': username,
      'password': password,
      'nickname': nickname,
    });
  }

  void checkNickname(String nickname) {
    nicknameAvailable = null;
    nicknameCheckMessage = null;
    _network.send({'type': 'check_nickname', 'nickname': nickname});
  }

  void clearAuthState() {
    loginError = null;
    registerResult = null;
    nicknameAvailable = null;
    nicknameCheckMessage = null;
  }

  void reset() {
    playerId = '';
    playerName = '';
    currentRoomId = '';
    currentRoomName = '';
    roomPlayers = [];
    isHost = false;
    isRankedRoom = false;
    roomList = [];
    spectatableRooms = [];
    isSpectator = false;
    spectatorGameState = null;
    pendingCardViewRequests = {};
    approvedCardViews = {};
    incomingCardViewRequests = [];
    gameState = null;
    errorMessage = null;
    clearAuthState();
    notifyListeners();
  }

  void deleteAccount() {
    _network.send({'type': 'delete_account'});
  }

  void requestRoomList() {
    _network.send({'type': 'room_list'});
  }

  void requestSpectatableRooms() {
    _network.send({'type': 'spectatable_rooms'});
  }

  void spectateRoom(String roomId) {
    _network.send({'type': 'spectate_room', 'roomId': roomId});
  }

  void requestCardView(String playerId) {
    _network.send({'type': 'request_card_view', 'playerId': playerId});
  }

  void respondCardViewRequest(String spectatorId, bool allow) {
    _network.send({
      'type': 'respond_card_view',
      'spectatorId': spectatorId,
      'allow': allow,
    });
    // Remove from local list
    incomingCardViewRequests.removeWhere((r) => r['spectatorId'] == spectatorId);
    notifyListeners();
  }

  void createRoom(String roomName, {String password = '', bool isRanked = false}) {
    _network.send({
      'type': 'create_room',
      'roomName': roomName,
      'password': password,
      'isRanked': isRanked,
    });
  }

  void joinRoom(String roomId, {String password = ''}) {
    _network.send({'type': 'join_room', 'roomId': roomId, 'password': password});
  }

  void leaveRoom() {
    _network.send({'type': 'leave_room'});
  }

  void leaveGame() {
    _network.send({'type': 'leave_game'});
  }

  void startGame() {
    _network.send({'type': 'start_game'});
  }

  void playCards(List<String> cards, {String? callRank}) {
    final data = {'type': 'play_cards', 'cards': cards};
    if (callRank != null) {
      data['callRank'] = callRank;
    }
    _network.send(data);
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
    _dogDelayTimer?.cancel();
    _dogClearTimer?.cancel();
    super.dispose();
  }
}
