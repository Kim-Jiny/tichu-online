import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
  // Fixed 4-slot system: always 4 elements, null for empty slots
  List<Player?> roomPlayers = [null, null, null, null];
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

  // Spectators currently viewing my cards
  List<Map<String, String>> cardViewers = []; // [{id, nickname}]

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

  // Chat
  List<Map<String, dynamic>> chatMessages = [];
  Set<String> blockedUsers = {};
  List<String> friends = [];
  List<Map<String, dynamic>> friendsData = [];
  List<String> pendingFriendRequests = [];
  int pendingFriendRequestCount = 0;
  List<Map<String, dynamic>> roomInvites = [];
  Set<String> sentFriendRequests = {};

  // Profile
  Map<String, dynamic>? profileData;

  // Rankings
  List<Map<String, dynamic>> rankings = [];
  bool rankingsLoading = false;
  String? rankingsError;
  List<Map<String, dynamic>> seasons = [];

  // Shop
  int gold = 0;
  int leaveCount = 0;
  List<Map<String, dynamic>> shopItems = [];
  List<Map<String, dynamic>> inventoryItems = [];
  bool shopLoading = false;
  bool inventoryLoading = false;
  String? shopError;
  String? inventoryError;
  String? lastPurchaseItemKey;
  bool? lastPurchaseSuccess;
  bool lastPurchaseExtended = false;

  // Equipped theme
  String? equippedTheme;

  // Report result
  String? reportResultMessage;
  bool? reportResultSuccess;

  // Inquiry
  String? inquiryResultMessage;
  bool? inquiryResultSuccess;

  // Turn timeout
  String? timeoutPlayerName; // show "시간 초과!" banner
  String? desertedPlayerName; // show desertion message
  String? desertedReason; // 'leave' or 'timeout'
  int myTimeoutCount = 0; // Bug #6: own timeout count (0-2)

  // Dragon given
  String? dragonGivenMessage; // "OO이(가) OO에게 용을 줬습니다"

  bool _disposed = false; // C2: Track disposal to prevent stale callbacks

  GameService(this._network) {
    _subscription = _network.messageStream.listen(_handleMessage);
  }

  // Helper: count of non-null players
  int get playerCount => roomPlayers.where((p) => p != null).length;

  // Theme gradient colors based on equipped theme
  List<Color> get themeGradient {
    switch (equippedTheme) {
      case 'theme_cotton':
        return const [Color(0xFFFFF8F0), Color(0xFFFFE8D8), Color(0xFFFFF0E8)];
      case 'theme_sky':
        return const [Color(0xFFE8F4FD), Color(0xFFD0E8F8), Color(0xFFC4E0F4)];
      case 'theme_mocha_30d':
        return const [Color(0xFFF0E8E0), Color(0xFFE0D0C4), Color(0xFFD8C8BC)];
      default:
        return const [Color(0xFFF8F4F6), Color(0xFFEDE6F0), Color(0xFFE0ECF6)];
    }
  }

  // Card back colors based on equipped theme: [background, border, innerBorder]
  List<Color> get cardBackColors {
    switch (equippedTheme) {
      case 'theme_cotton':
        return const [Color(0xFFFFF0E0), Color(0xFFE8D8C8), Color(0xFFF0E0D0)];
      case 'theme_sky':
        return const [Color(0xFFE0F0FF), Color(0xFFC8D8E8), Color(0xFFD0E0F0)];
      case 'theme_mocha_30d':
        return const [Color(0xFFF0E8E0), Color(0xFFD8CCC0), Color(0xFFE0D4C8)];
      default:
        return const [Color(0xFFFFF1F5), Color(0xFFE6DCE8), Color(0xFFEDE2EF)];
    }
  }

  void _handleMessage(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    if (type == null) return;

    switch (type) {
      case 'login_success':
        playerId = data['playerId'] ?? '';
        playerName = data['nickname'] ?? '';
        equippedTheme = data['themeKey'] as String?;
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

      case 'switched_to_spectator':
        isSpectator = true;
        gameState = null;
        spectatorGameState = null;
        pendingCardViewRequests = {};
        approvedCardViews = {};
        incomingCardViewRequests = [];
        cardViewers = [];
        notifyListeners();
        break;

      case 'switched_to_player':
        isSpectator = false;
        spectatorGameState = null;
        pendingCardViewRequests = {};
        approvedCardViews = {};
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
        if (currentRoomId.isEmpty) break; // Already left
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
        roomPlayers = [null, null, null, null];
        isHost = false;
        isRankedRoom = false;
        isSpectator = false;
        gameState = null;
        spectatorGameState = null;
        pendingCardViewRequests = {};
        approvedCardViews = {};
        incomingCardViewRequests = [];
        cardViewers = [];
        chatMessages = [];
        notifyListeners();
        break;

      case 'kicked':
        currentRoomId = '';
        currentRoomName = '';
        roomPlayers = [null, null, null, null];
        isHost = false;
        isRankedRoom = false;
        isSpectator = false; // C10: Clear isSpectator on kick
        gameState = null;
        chatMessages = [];
        errorMessage = data['message'] as String? ?? '강퇴되었습니다';
        notifyListeners();
        Future.delayed(const Duration(seconds: 3), () {
          if (_disposed) return; // C2: Don't notify after disposal
          errorMessage = null;
          notifyListeners();
        });
        break;

      case 'room_closed':
        currentRoomId = '';
        currentRoomName = '';
        roomPlayers = [null, null, null, null];
        isHost = false;
        isRankedRoom = false;
        isSpectator = false;
        spectatorGameState = null;
        pendingCardViewRequests = {};
        approvedCardViews = {};
        incomingCardViewRequests = [];
        cardViewers = [];
        gameState = null;
        chatMessages = [];
        desertedPlayerName = null;
        desertedReason = null;
        notifyListeners();
        break;

      case 'room_state':
        final room = data['room'] as Map<String, dynamic>?;
        if (room != null) {
          final playersList = room['players'] as List?;
          if (playersList != null && playersList.length == 4) {
            // Parse 4-slot array with nulls
            roomPlayers = playersList.map((p) {
              if (p == null) return null;
              return Player.fromJson(p as Map<String, dynamic>);
            }).toList();
          }
          isHost = roomPlayers.any((p) => p != null && p.id == playerId && p.isHost);
          isRankedRoom = room['isRanked'] == true;
        }
        notifyListeners();
        break;

      case 'game_state':
        if (currentRoomId.isEmpty) break; // Already left
        final state = data['state'] as Map<String, dynamic>?;
        if (state != null) {
          // Clear desertion state when a new round/game starts
          final phase = state['phase'] as String? ?? '';
          if (phase != 'game_end') {
            desertedPlayerName = null;
            desertedReason = null;
          }
          // Parse card viewers
          final viewers = state['cardViewers'] as List?;
          if (viewers != null) {
            cardViewers = viewers.map((v) => {
              'id': (v['id'] ?? '').toString(),
              'nickname': (v['nickname'] ?? '').toString(),
            }).toList();
          } else {
            cardViewers = [];
          }
          _applyGameStateWithDogDelay(state);
        }
        notifyListeners();
        break;

      case 'error':
        errorMessage = data['message'] as String?;
        notifyListeners();
        // Clear error after a delay
        Future.delayed(const Duration(seconds: 3), () {
          if (_disposed) return; // C2: Don't notify after disposal
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
        break;
      case 'dragon_given':
        _handleDragonGiven(data);
        break;

      case 'turn_timeout':
        _handleTurnTimeout(data);
        break;

      case 'player_deserted':
        _handlePlayerDeserted(data);
        break;

      case 'timeout_reset':
        myTimeoutCount = 0;
        notifyListeners();
        break;

      // Chat
      case 'chat_message':
        final msg = {
          'sender': data['sender'] ?? '',
          'senderId': data['senderId'] ?? '',
          'message': data['message'] ?? '',
          'timestamp': data['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
        };
        chatMessages.add(msg);
        if (chatMessages.length > 100) {
          chatMessages.removeAt(0);
        }
        notifyListeners();
        break;

      case 'chat_history':
        final messages = data['messages'] as List? ?? [];
        chatMessages = messages.map((m) => {
          'sender': m['sender'] ?? '',
          'senderId': m['senderId'] ?? '',
          'message': m['message'] ?? '',
          'timestamp': m['timestamp'] ?? 0,
        }).toList();
        notifyListeners();
        break;

      case 'blocked_users':
        final users = data['users'] as List? ?? [];
        blockedUsers = users.map((u) => u.toString()).toSet();
        notifyListeners();
        break;

      case 'block_result':
        if (data['success'] == true) {
          final nickname = data['nickname'] as String?;
          if (nickname != null) {
            if (data['blocked'] == true) {
              blockedUsers.add(nickname);
            } else {
              blockedUsers.remove(nickname);
            }
          }
        }
        notifyListeners();
        break;

      case 'friends_list':
        final friendsList = data['friends'] as List? ?? [];
        // Support both object array [{nickname, isOnline, ...}] and string array
        if (friendsList.isNotEmpty && friendsList.first is Map) {
          friendsData = friendsList.map((f) => Map<String, dynamic>.from(f as Map)).toList();
          friends = friendsData.map((f) => f['nickname']?.toString() ?? '').toList();
        } else {
          friends = friendsList.map((f) => f.toString()).toList();
          friendsData = friends.map((f) => <String, dynamic>{'nickname': f, 'isOnline': false}).toList();
        }
        notifyListeners();
        break;

      case 'friend_result':
        // Refresh friends list and pending requests after add action
        requestFriends();
        requestPendingFriendRequests();
        notifyListeners();
        break;

      case 'pending_friend_requests':
        final requests = data['requests'] as List? ?? [];
        pendingFriendRequests = requests.map((r) => r.toString()).toList();
        pendingFriendRequestCount = pendingFriendRequests.length;
        notifyListeners();
        break;

      case 'friend_request_result':
        // Refresh after accept/reject
        requestFriends();
        requestPendingFriendRequests();
        notifyListeners();
        break;

      case 'friend_request_received':
        // Someone sent us a friend request
        final fromNickname = data['fromNickname'] as String? ?? '';
        if (fromNickname.isNotEmpty && !pendingFriendRequests.contains(fromNickname)) {
          pendingFriendRequests.add(fromNickname);
          pendingFriendRequestCount = pendingFriendRequests.length;
        }
        notifyListeners();
        break;

      case 'friend_request_accepted':
        // Our request was accepted — refresh friends
        requestFriends();
        notifyListeners();
        break;

      case 'friend_removed':
        final removedNick = data['nickname'] as String? ?? '';
        if (removedNick.isNotEmpty) {
          friends.remove(removedNick);
          friendsData.removeWhere((f) => f['nickname'] == removedNick);
        }
        notifyListeners();
        break;

      case 'friend_status_changed':
        final nick = data['nickname'] as String? ?? '';
        final isOnline = data['isOnline'] == true;
        final idx = friendsData.indexWhere((f) => f['nickname'] == nick);
        if (idx != -1) {
          friendsData[idx]['isOnline'] = isOnline;
          if (!isOnline) {
            friendsData[idx]['roomId'] = null;
            friendsData[idx]['roomName'] = null;
          }
        }
        notifyListeners();
        break;

      case 'room_invite':
        roomInvites.add(Map<String, dynamic>.from(data));
        notifyListeners();
        break;

      case 'invite_result':
        // Show feedback via errorMessage for now
        if (data['success'] != true) {
          errorMessage = data['message'] as String?;
          notifyListeners();
          Future.delayed(const Duration(seconds: 3), () {
            if (_disposed) return;
            errorMessage = null;
            notifyListeners();
          });
        }
        notifyListeners();
        break;

      case 'report_result':
        reportResultSuccess = data['success'] == true;
        reportResultMessage = data['message'] as String? ?? '';
        notifyListeners();
        break;

      case 'profile_result':
        profileData = data;
        notifyListeners();
        break;

      case 'rankings_result':
        rankingsLoading = false;
        if (data['success'] == true) {
          final list = data['rankings'] as List? ?? [];
          rankings = list.map((e) => Map<String, dynamic>.from(e)).toList();
          rankingsError = null;
        } else {
          rankingsError = data['message'] as String? ?? '랭킹을 불러오지 못했습니다';
        }
        notifyListeners();
        break;

      case 'seasons_result':
        if (data['success'] == true) {
          final list = data['seasons'] as List? ?? [];
          seasons = list.map((e) => Map<String, dynamic>.from(e)).toList();
        }
        notifyListeners();
        break;
      case 'wallet_result':
        if (data['success'] == true) {
          final wallet = data['wallet'] as Map<String, dynamic>? ?? {};
          gold = wallet['gold'] ?? 0;
          leaveCount = wallet['leave_count'] ?? 0;
        }
        notifyListeners();
        break;

      case 'shop_items_result':
        shopLoading = false;
        if (data['success'] == true) {
          final list = data['items'] as List? ?? [];
          shopItems = list.map((e) => Map<String, dynamic>.from(e)).toList();
          shopError = null;
        } else {
          shopError = data['message'] as String? ?? '상점 정보를 불러오지 못했습니다';
        }
        notifyListeners();
        break;

      case 'inventory_result':
        inventoryLoading = false;
        if (data['success'] == true) {
          final list = data['items'] as List? ?? [];
          inventoryItems = list.map((e) => Map<String, dynamic>.from(e)).toList();
          inventoryError = null;
        } else {
          inventoryError = data['message'] as String? ?? '인벤토리를 불러오지 못했습니다';
        }
        notifyListeners();
        break;

      case 'purchase_result':
      case 'equip_result':
      case 'use_item_result':
        // Refresh wallet/inventory after actions
        requestWallet();
        requestInventory();
        if (type == 'purchase_result') {
          lastPurchaseItemKey = data['itemKey'] as String?;
          lastPurchaseSuccess = data['success'] == true;
          lastPurchaseExtended = data['extended'] == true;
        }
        if (type == 'equip_result' && data['success'] == true) {
          final themeKey = data['themeKey'] as String?;
          if (themeKey != null) {
            equippedTheme = themeKey;
          }
        }
        if (data['success'] != true) {
          reportResultMessage = data['message'] as String?;
          reportResultSuccess = false;
        }
        notifyListeners();
        break;

      case 'inquiry_result':
        inquiryResultSuccess = data['success'] == true;
        inquiryResultMessage = data['message'] as String? ?? '';
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

  void _handleTurnTimeout(Map<String, dynamic> data) {
    timeoutPlayerName = data['playerName'] as String? ?? '';
    // Bug #6: Track own timeout count
    final timeoutName = data['playerName'] as String? ?? '';
    if (timeoutName == playerName) {
      final count = data['count'];
      if (count is int) {
        myTimeoutCount = count;
      }
    }
    notifyListeners();
    Future.delayed(const Duration(seconds: 2), () {
      if (_disposed) return; // C2
      timeoutPlayerName = null;
      notifyListeners();
    });
  }

  void _handleDragonGiven(Map<String, dynamic> data) {
    final fromName = data['fromName'] as String? ?? '';
    final targetName = data['targetName'] as String? ?? '';
    dragonGivenMessage = '$fromName → $targetName';
    notifyListeners();
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (_disposed) return; // C2
      dragonGivenMessage = null;
      notifyListeners();
    });
  }

  void _handlePlayerDeserted(Map<String, dynamic> data) {
    desertedPlayerName = data['playerName'] as String? ?? '';
    desertedReason = data['reason'] as String? ?? 'leave';
    notifyListeners();
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
    equippedTheme = null;
    currentRoomId = '';
    currentRoomName = '';
    roomPlayers = [null, null, null, null];
    isHost = false;
    isRankedRoom = false;
    roomList = [];
    spectatableRooms = [];
    isSpectator = false;
    spectatorGameState = null;
    pendingCardViewRequests = {};
    approvedCardViews = {};
    incomingCardViewRequests = [];
    cardViewers = [];
    gameState = null;
    errorMessage = null;
    chatMessages = [];
    profileData = null;
    friendsData = [];
    pendingFriendRequests = [];
    pendingFriendRequestCount = 0;
    roomInvites = [];
    sentFriendRequests = {};
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

  void switchToSpectator() {
    _network.send({'type': 'switch_to_spectator'});
  }

  void switchToPlayer(int targetSlot) {
    _network.send({'type': 'switch_to_player', 'targetSlot': targetSlot});
  }

  void requestCardView(String playerId) {
    _network.send({'type': 'request_card_view', 'playerId': playerId});
  }

  void revokeCardView(String spectatorId) {
    _network.send({'type': 'revoke_card_view', 'spectatorId': spectatorId});
    // Optimistically remove from local list
    cardViewers.removeWhere((v) => v['id'] == spectatorId);
    notifyListeners();
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

  void createRoom(String roomName, {String password = '', bool isRanked = false, int turnTimeLimit = 30}) {
    _network.send({
      'type': 'create_room',
      'roomName': roomName,
      'password': password,
      'isRanked': isRanked,
      'turnTimeLimit': turnTimeLimit,
    });
  }

  void joinRoom(String roomId, {String password = ''}) {
    _network.send({'type': 'join_room', 'roomId': roomId, 'password': password});
  }

  void leaveRoom() {
    _network.send({'type': 'leave_room'});
    _clearRoomState();
  }

  void leaveGame() {
    _network.send({'type': 'leave_game'});
    _clearRoomState();
  }

  void _clearRoomState() {
    currentRoomId = '';
    currentRoomName = '';
    roomPlayers = [null, null, null, null];
    isHost = false;
    isRankedRoom = false;
    isSpectator = false;
    gameState = null;
    spectatorGameState = null;
    pendingCardViewRequests = {};
    approvedCardViews = {};
    incomingCardViewRequests = [];
    cardViewers = [];
    chatMessages = [];
    desertedPlayerName = null;
    desertedReason = null;
    dragonGivenMessage = null;
    myTimeoutCount = 0;
    notifyListeners();
  }

  void addBot({int? targetSlot}) {
    final msg = <String, dynamic>{'type': 'add_bot'};
    if (targetSlot != null) msg['targetSlot'] = targetSlot;
    _network.send(msg);
  }

  void toggleReady() {
    _network.send({'type': 'toggle_ready'});
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

  void resetTimeout() {
    _network.send({'type': 'reset_timeout'});
  }

  void callRank(String rank) {
    _network.send({'type': 'call_rank', 'rank': rank});
  }

  void returnToRoom() {
    _network.send({'type': 'return_to_room'});
    gameState = null;
    notifyListeners();
  }

  void checkRoom() {
    _network.send({'type': 'check_room'});
  }

  void nextRound() {
    _network.send({'type': 'next_round'});
  }

  void changeTeam(int targetSlot) {
    _network.send({'type': 'change_team', 'targetSlot': targetSlot});
  }

  // Kick player (host only)
  void kickPlayer(String targetPlayerId) {
    _network.send({'type': 'kick_player', 'playerId': targetPlayerId});
  }

  // Request user profile
  void requestProfile(String nickname) {
    profileData = null;
    _network.send({'type': 'get_profile', 'nickname': nickname});
  }

  // Rankings
  void requestRankings() {
    rankingsLoading = true;
    rankingsError = null;
    _network.send({'type': 'get_rankings'});
    notifyListeners();
  }

  void requestRankingsForSeason(int seasonId) {
    rankingsLoading = true;
    rankingsError = null;
    _network.send({'type': 'get_rankings', 'seasonId': seasonId});
    notifyListeners();
  }

  void requestSeasons() {
    _network.send({'type': 'get_seasons'});
  }

  // Shop
  void requestWallet() {
    _network.send({'type': 'get_wallet'});
  }

  void requestShopItems() {
    shopLoading = true;
    shopError = null;
    _network.send({'type': 'get_shop_items'});
    notifyListeners();
  }

  void requestInventory() {
    inventoryLoading = true;
    inventoryError = null;
    _network.send({'type': 'get_inventory'});
    notifyListeners();
  }

  void buyItem(String itemKey) {
    _network.send({'type': 'buy_item', 'itemKey': itemKey});
  }

  void equipItem(String itemKey) {
    _network.send({'type': 'equip_item', 'itemKey': itemKey});
  }

  void useItem(String itemKey) {
    _network.send({'type': 'use_item', 'itemKey': itemKey});
  }

  void clearLastPurchaseResult() {
    lastPurchaseItemKey = null;
    lastPurchaseSuccess = null;
    lastPurchaseExtended = false;
  }

  // Chat
  void sendChatMessage(String message) {
    _network.send({'type': 'chat_message', 'message': message});
  }

  void clearChatMessages() {
    chatMessages.clear();
    notifyListeners();
  }

  // Block/Unblock
  void blockUserAction(String nickname) {
    _network.send({'type': 'block_user', 'nickname': nickname});
  }

  void unblockUserAction(String nickname) {
    _network.send({'type': 'unblock_user', 'nickname': nickname});
  }

  void requestBlockedUsers() {
    _network.send({'type': 'get_blocked_users'});
  }

  bool isBlocked(String nickname) {
    return blockedUsers.contains(nickname);
  }

  // Report
  void reportUserAction(String nickname, String reason) {
    _network.send({'type': 'report_user', 'nickname': nickname, 'reason': reason});
  }

  // Friends
  void addFriendAction(String nickname) {
    _network.send({'type': 'add_friend', 'nickname': nickname});
    sentFriendRequests.add(nickname);
    notifyListeners();
  }

  void requestFriends() {
    _network.send({'type': 'get_friends'});
  }

  void requestPendingFriendRequests() {
    _network.send({'type': 'get_pending_friend_requests'});
  }

  void acceptFriendRequest(String nickname) {
    _network.send({'type': 'accept_friend_request', 'nickname': nickname});
  }

  void rejectFriendRequest(String nickname) {
    _network.send({'type': 'reject_friend_request', 'nickname': nickname});
  }

  void removeFriendAction(String nickname) {
    _network.send({'type': 'remove_friend', 'nickname': nickname});
  }

  void inviteToRoom(String nickname) {
    _network.send({'type': 'invite_to_room', 'nickname': nickname});
  }

  void acceptInvite(Map<String, dynamic> invite) {
    final roomId = invite['roomId'] as String? ?? '';
    final password = invite['password'] as String? ?? '';
    if (roomId.isNotEmpty) {
      joinRoom(roomId, password: password);
    }
    roomInvites.remove(invite);
    notifyListeners();
  }

  void dismissInvite(int index) {
    if (index >= 0 && index < roomInvites.length) {
      roomInvites.removeAt(index);
      notifyListeners();
    }
  }

  // Inquiry
  void submitInquiry(String category, String title, String content) {
    inquiryResultSuccess = null;
    inquiryResultMessage = null;
    _network.send({
      'type': 'submit_inquiry',
      'category': category,
      'title': title,
      'content': content,
    });
  }

  @override
  void dispose() {
    _disposed = true; // C2: Mark as disposed
    _subscription?.cancel();
    _dogDelayTimer?.cancel();
    _dogClearTimer?.cancel();
    super.dispose();
  }
}
