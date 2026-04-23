import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/player.dart';
import '../models/room.dart';
import '../models/game_state.dart';
import '../models/sk_game_state.dart';
import '../models/ll_game_state.dart';
import '../models/mighty_game_state.dart';
import 'network_service.dart';
import 'profile_store.dart';
import 'restore_sync_tracker.dart';
import 'sfx_service.dart';

enum AppDestination { lobby, waitingRoom, game, spectator, skGame, llGame, mightyGame }

class GameService extends ChangeNotifier {
  final NetworkService _network;
  StreamSubscription? _subscription;
  Timer? _dogDelayTimer;
  Timer? _dogClearTimer;
  Timer? _inquiryBannerTimer;
  Timer? _pushToggleTimer;
  int _pushPrefsLoadVersion = 0;
  final Map<String, DateTime> _roomInviteCooldowns = {};
  Completer<String?>? _shareInviteLinkCompleter;
  DateTime? _dogDelayUntil;
  Map<String, dynamic>? _pendingGameState;
  GameStateData? _prevGameState;
  SKGameStateData? _prevSKGameState;
  LLGameStateData? _prevLLGameState;
  MightyGameStateData? _prevMightyGameState;
  final SfxService _sfx = SfxService();
  final RestoreSyncTracker _restoreSync = RestoreSyncTracker();

  // Player info
  String playerId = '';
  String playerName = '';

  // Room info
  String currentRoomId = '';
  String currentRoomName = '';
  // Dynamic slot system: maxPlayers elements, null for empty slots
  List<Player?> roomPlayers = [null, null, null, null];
  bool isHost = false;
  bool isRankedRoom = false;
  int roomTurnTimeLimit = 30;
  int roomTargetScore = 1000;
  int roomMaxPlayers = 4;
  Set<int> roomBlockedSlots = <int>{};

  /// Effective max players after host-blocked slots are excluded.
  int get effectiveRoomMaxPlayers => roomMaxPlayers - roomBlockedSlots.length;

  // Room list
  List<Room> roomList = [];
  List<Room> spectatableRooms = [];

  // Spectator mode
  bool isSpectator = false;
  bool duplicateLoginKicked = false;
  Map<String, dynamic>? spectatorGameState;
  Set<String> pendingCardViewRequests = {}; // player IDs we've requested
  Set<String> approvedCardViews = {}; // player IDs that approved

  // Incoming card view requests (for players)
  List<Map<String, String>> incomingCardViewRequests =
      []; // [{spectatorId, spectatorNickname}]
  bool autoRejectCardView = false; // 패 보기 요청 항상 거절
  bool autoAcceptCardView = false; // 패 보기 요청 항상 승인

  // Spectators currently viewing my cards
  List<Map<String, String>> cardViewers = []; // [{id, nickname}]

  // Spectators in the room
  List<Map<String, String>> spectators = []; // [{id, nickname}]

  // Game state
  GameStateData? gameState;
  SKGameStateData? skGameState;
  LLGameStateData? llGameState;
  MightyGameStateData? mightyGameState;
  String currentGameType = 'tichu';

  // Error message
  String? errorMessage;

  // Auth state
  String? loginError;
  String? loginErrorReason;
  String? registerResult;
  bool? registerSuccess;
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
  final ProfileStore _profiles = ProfileStore();

  // Rankings
  List<Map<String, dynamic>> rankings = [];
  bool rankingsLoading = false;
  String? rankingsError;
  int? myRank;
  Map<String, dynamic>? myRankData;
  List<Map<String, dynamic>> seasons = [];

  // Shop
  int gold = 0;
  int leaveCount = 0;
  List<Map<String, dynamic>> goldHistory = [];
  List<Map<String, dynamic>> shopItems = [];
  List<Map<String, dynamic>> inventoryItems = [];
  bool shopLoading = false;
  bool goldHistoryLoading = false;
  bool inventoryLoading = false;
  String? goldHistoryError;
  String? shopError;
  String? inventoryError;
  String? lastPurchaseItemKey;
  bool? lastPurchaseSuccess;
  bool lastPurchaseExtended = false;
  String? shopActionMessage;
  bool? shopActionSuccess;

  // Equipped theme
  String? equippedTheme;

  // Equipped title
  String? equippedTitle;

  // Report result
  String? reportResultMessage;
  bool? reportResultSuccess;

  // Inquiry
  String? inquiryResultMessage;
  bool? inquiryResultSuccess;
  List<Map<String, dynamic>> inquiries = [];
  bool inquiriesLoading = false;
  String? inquiriesError;
  String? inquiryBannerMessage;

  // Notices
  List<Map<String, dynamic>> notices = [];
  bool noticesLoading = false;
  String? noticesError;
  // Set of notice IDs the user has already seen. Persisted locally —
  // there is no server-side read tracking for notices.
  final Set<int> _readNoticeIds = <int>{};
  static const String _readNoticesPrefsKey = 'read_notice_ids';
  // Set to true by requestNotices(markReadOnReceive: true) so the next
  // notices_result response automatically marks everything seen.
  bool _pendingNoticeMarkRead = false;

  /// Read-only view of notice IDs the user has already seen.
  Set<int> get readNoticeIds => _readNoticeIds;

  /// Count of notices the user hasn't opened yet.
  int get unreadNoticeCount {
    int count = 0;
    for (final n in notices) {
      final id = n['id'];
      if (id is int && !_readNoticeIds.contains(id)) count++;
    }
    return count;
  }

  // Push settings
  bool pushEnabled = true;
  bool pushFriendInviteEnabled = true;
  bool isAdminUser = false;
  bool pushAdminInquiryEnabled = true;
  bool pushAdminReportEnabled = true;
  double sfxVolume = 0.7;

  // Admin
  Map<String, dynamic>? adminDashboard;
  bool adminDashboardLoading = false;
  List<Map<String, dynamic>> adminUsers = [];
  bool adminUsersLoading = false;
  String? adminUsersError;
  Map<String, dynamic>? adminUserDetail;
  bool adminUserDetailLoading = false;
  String? adminUserDetailError;
  List<Map<String, dynamic>> adminInquiries = [];
  bool adminInquiriesLoading = false;
  String? adminInquiriesError;
  List<Map<String, dynamic>> adminReports = [];
  bool adminReportsLoading = false;
  String? adminReportsError;
  List<Map<String, dynamic>> adminReportGroup = [];
  bool adminReportGroupLoading = false;
  String? adminReportGroupError;
  String? adminActionMessage;
  bool? adminActionSuccess;

  // Nickname change
  String? nicknameChangeResult;
  bool? nicknameChangeSuccess;

  // Top card counter
  bool hasTopCardCounter = false;

  // Mighty trump counter
  bool hasMightyTrumpCounter = false;

  // Social login
  bool needNickname = false;
  String? socialProvider;
  String? socialToken;
  String? socialProviderUid;
  String? socialEmail;
  bool socialExistingUser = false;

  // Auth provider (from login_success)
  String authProvider = 'local';

  // Social link
  String? linkedSocialProvider;
  String? linkedSocialEmail;
  String? socialLinkResultMessage;
  bool? socialLinkResultSuccess;

  // Turn timeout
  String? timeoutPlayerName; // show "시간 초과!" banner
  String? desertedPlayerName; // show desertion message
  String? desertedReason; // 'leave' or 'timeout'
  int myTimeoutCount = 0; // Bug #6: own timeout count (0-2)

  // Dragon given
  String? dragonGivenMessage; // "OO이(가) OO에게 용을 줬습니다"

  // App config (EULA, Privacy Policy, Force Update)
  String? eulaContent;
  String? privacyPolicy;
  String? minVersion;
  String? latestVersion;

  // Maintenance
  bool isUnderMaintenance = false;
  bool hasMaintenanceNotice = false;
  String maintenanceMessage = '';

  // DM / Search
  List<Map<String, dynamic>> dmConversations = [];
  Map<String, List<Map<String, dynamic>>> dmMessages = {};
  int totalUnreadDmCount = 0;
  List<Map<String, dynamic>> searchResults = [];
  String? _activeDmPartner;
  String? maintenanceStart;
  String? maintenanceEnd;

  bool _disposed = false; // C2: Track disposal to prevent stale callbacks

  StreamSubscription? _fcmTokenSubscription;

  GameService(this._network) {
    _subscription = _network.messageStream.listen(_handleMessage);
    _fcmTokenSubscription = FirebaseMessaging.instance.onTokenRefresh.listen((
      newToken,
    ) {
      final preview = newToken.substring(0, newToken.length.clamp(0, 20));
      debugPrint('[FCM] onTokenRefresh: $preview...');
      if (playerId.isNotEmpty && pushEnabled) {
        _network.send({'type': 'update_fcm_token', 'fcmToken': newToken});
        debugPrint('[FCM] Refreshed token sent to server');
      }
    });
    _loadPushPrefs();
    _loadSfxPrefs();
    _loadReadNoticeIds();
    _restoreMaintenanceCache();
  }

  // Helper: count of non-null players
  int get playerCount => roomPlayers.where((p) => p != null).length;
  bool get isLoggedIn => playerId.isNotEmpty;
  bool get hasLoginError => loginError != null;
  bool get hasRoom => currentRoomId.isNotEmpty;
  bool get hasSpectatorRoom => isSpectator && hasRoom;
  bool get isInWaitingRoom => hasRoom && !isSpectator && !hasActiveGame;
  bool get hasActiveGame {
    if (mightyGameState != null &&
        mightyGameState!.phase.isNotEmpty &&
        mightyGameState!.phase != 'game_end') {
      return true;
    }
    if (skGameState != null &&
        skGameState!.phase.isNotEmpty &&
        skGameState!.phase != 'game_end') {
      return true;
    }
    if (llGameState != null &&
        llGameState!.phase.isNotEmpty &&
        llGameState!.phase != 'game_end') {
      return true;
    }
    return gameState != null &&
        gameState!.phase.isNotEmpty &&
        gameState!.phase != 'waiting' &&
        gameState!.phase != 'game_end';
  }

  bool get hasSpectatorGameState => spectatorGameState != null;
  bool get hasPendingSocialNickname => needNickname;
  Map<String, dynamic>? get profileData => _profiles.current;
  Map<String, dynamic>? profileFor(String nickname) =>
      _profiles.profileFor(nickname);
  AppDestination get currentDestination {
    if (isSpectator && hasRoom) {
      if (currentGameType == 'skull_king') return AppDestination.skGame;
      if (currentGameType == 'love_letter') return AppDestination.llGame;
      if (currentGameType == 'mighty') return AppDestination.mightyGame;
      return AppDestination.spectator;
    }
    if (!hasRoom) return AppDestination.lobby;
    if (mightyGameState != null) return AppDestination.mightyGame;
    if (llGameState != null) return AppDestination.llGame;
    if (skGameState != null) return AppDestination.skGame;
    if (gameState != null) return AppDestination.game;
    return AppDestination.waitingRoom;
  }

  bool isRoomInvitePending(String nickname) {
    final until = _roomInviteCooldowns[nickname];
    if (until == null) return false;
    if (DateTime.now().isAfter(until)) {
      _roomInviteCooldowns.remove(nickname);
      return false;
    }
    return true;
  }

  bool canInviteToRoom(String nickname) {
    if (!isInWaitingRoom) return false;
    if (nickname.isEmpty) return false;
    return !isRoomInvitePending(nickname);
  }

  // Theme gradient colors based on equipped theme
  List<Color> get themeGradient {
    switch (equippedTheme) {
      case 'theme_cotton':
        return const [Color(0xFFFFF8F0), Color(0xFFFFE8D8), Color(0xFFFFF0E8)];
      case 'theme_sky':
        return const [Color(0xFFE8F4FD), Color(0xFFD0E8F8), Color(0xFFC4E0F4)];
      case 'theme_mocha_30d':
        return const [Color(0xFFF0E8E0), Color(0xFFE0D0C4), Color(0xFFD8C8BC)];
      case 'theme_lavender':
        return const [Color(0xFFF3E8FF), Color(0xFFE8D5FF), Color(0xFFF0E0FF)];
      case 'theme_cherry':
        return const [Color(0xFFFFF0F5), Color(0xFFFFE0EC), Color(0xFFFFE8F0)];
      case 'theme_midnight':
        return const [Color(0xFFE8EAF6), Color(0xFFC5CAE9), Color(0xFFD1D5E8)];
      case 'theme_sunset':
        return const [Color(0xFFFFF3E0), Color(0xFFFFE0B2), Color(0xFFFFECCC)];
      case 'theme_forest':
        return const [Color(0xFFE8F5E9), Color(0xFFC8E6C9), Color(0xFFDCE8DC)];
      case 'theme_rose':
        return const [Color(0xFFFBE9E7), Color(0xFFFFCCBC), Color(0xFFF0E0DC)];
      case 'theme_ocean':
        return const [Color(0xFFE0F7FA), Color(0xFFB2EBF2), Color(0xFFD0F0F8)];
      case 'theme_aurora':
        return const [Color(0xFFE8F5E9), Color(0xFFE0F7FA), Color(0xFFF3E5F5)];
      case 'theme_mintchoco_30d':
        return const [Color(0xFFE8F5E9), Color(0xFFE0F2F1), Color(0xFFE8F0E8)];
      case 'theme_peach_30d':
        return const [Color(0xFFFFF8E1), Color(0xFFFFE8D0), Color(0xFFFFF0E0)];
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
      case 'theme_lavender':
        return const [Color(0xFFF0E0FF), Color(0xFFD8C0E8), Color(0xFFE0D0F0)];
      case 'theme_cherry':
        return const [Color(0xFFFFE8F0), Color(0xFFE8C8D8), Color(0xFFF0D0E0)];
      case 'theme_midnight':
        return const [Color(0xFFD0D4E8), Color(0xFFB0B8D0), Color(0xFFC0C8E0)];
      case 'theme_sunset':
        return const [Color(0xFFFFE8CC), Color(0xFFE8CCA8), Color(0xFFF0D8B8)];
      case 'theme_forest':
        return const [Color(0xFFDCE8DC), Color(0xFFB8C8B8), Color(0xFFC8D8C8)];
      case 'theme_rose':
        return const [Color(0xFFF0E0D8), Color(0xFFD8C0B8), Color(0xFFE0D0C8)];
      case 'theme_ocean':
        return const [Color(0xFFD0F0F8), Color(0xFFB0D8E8), Color(0xFFC0E0F0)];
      case 'theme_aurora':
        return const [Color(0xFFE0F0F0), Color(0xFFC0D8D8), Color(0xFFD0E0E0)];
      case 'theme_mintchoco_30d':
        return const [Color(0xFFE0F0E8), Color(0xFFC0D8C8), Color(0xFFD0E0D0)];
      case 'theme_peach_30d':
        return const [Color(0xFFFFE8D0), Color(0xFFE8D0B8), Color(0xFFF0D8C8)];
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
        equippedTitle = data['titleKey'] as String?;
        hasTopCardCounter = data['hasTopCardCounter'] == true;
        hasMightyTrumpCounter = data['hasMightyTrumpCounter'] == true;
        authProvider = data['authProvider'] as String? ?? 'local';
        isAdminUser = data['isAdmin'] == true;
        pushEnabled = data['pushEnabled'] != false;
        pushFriendInviteEnabled = data['pushFriendInvite'] != false;
        pushAdminInquiryEnabled = data['pushAdminInquiry'] != false;
        pushAdminReportEnabled = data['pushAdminReport'] != false;
        loginError = null;
        _parseMaintenanceStatus(
          data['maintenanceStatus'] as Map<String, dynamic>?,
        );
        _savePushPrefs();
        // Async FCM token update - don't block login
        _sendFcmTokenAsync();
        // Prefetch notices so the unread badge is accurate immediately.
        requestNotices();
        notifyListeners();
        break;

      case 'login_error':
        loginError = data['message'] ?? 'login_failed';
        loginErrorReason = data['reason'] as String?;
        notifyListeners();
        break;

      case 'admin_status_changed':
        isAdminUser = data['isAdmin'] == true;
        pushAdminInquiryEnabled = data['pushAdminInquiry'] != false;
        pushAdminReportEnabled = data['pushAdminReport'] != false;
        notifyListeners();
        break;

      case 'need_nickname':
        needNickname = true;
        socialProvider = data['provider'] as String?;
        socialProviderUid = data['providerUid'] as String?;
        socialEmail = data['email'] as String?;
        socialExistingUser = data['existingUser'] == true;
        notifyListeners();
        break;

      case 'register_result':
        registerResult = data['message'] ?? '';
        registerSuccess = data['success'] == true;
        notifyListeners();
        break;

      case 'nickname_check_result':
        nicknameAvailable = data['available'] ?? false;
        nicknameCheckMessage = data['message'] ?? '';
        notifyListeners();
        break;

      case 'room_list':
        roomList =
            (data['rooms'] as List?)?.map((r) => Room.fromJson(r)).toList() ??
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
        _prevGameState = null;
        skGameState = null;
        _prevSKGameState = null;
        _prevLLGameState = null;
        llGameState = null;
        mightyGameState = null;
        _prevMightyGameState = null;
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
        skGameState = null;
        _prevSKGameState = null;
        _prevLLGameState = null;
        llGameState = null;
        mightyGameState = null;
        _prevMightyGameState = null;
        pendingCardViewRequests = {};
        approvedCardViews = {};
        _prevGameState = null;
        notifyListeners();
        break;

      case 'spectatable_rooms':
        spectatableRooms =
            (data['rooms'] as List?)?.map((r) => Room.fromJson(r)).toList() ??
            [];
        notifyListeners();
        break;

      case 'spectator_game_state':
        if (currentRoomId.isEmpty) break; // Already left
        final state = data['state'] as Map<String, dynamic>?;
        if (state != null) {
          final stateGameType = state['gameType'] as String? ?? currentGameType;
          if (stateGameType == 'skull_king') {
            currentGameType = 'skull_king';
            skGameState = SKGameStateData.fromJson(state);
            spectatorGameState = null;
            gameState = null;
            llGameState = null;
            mightyGameState = null;
            _prevGameState = null;
            _prevMightyGameState = null;
          } else if (stateGameType == 'love_letter') {
            currentGameType = 'love_letter';
            llGameState = LLGameStateData.fromJson(state);
            spectatorGameState = null;
            gameState = null;
            skGameState = null;
            mightyGameState = null;
            _prevGameState = null;
            _prevSKGameState = null;
            _prevLLGameState = null;
            _prevMightyGameState = null;
          } else if (stateGameType == 'mighty') {
            currentGameType = 'mighty';
            mightyGameState = MightyGameStateData.fromJson(state);
            spectatorGameState = null;
            gameState = null;
            skGameState = null;
            llGameState = null;
            _prevGameState = null;
            _prevSKGameState = null;
            _prevLLGameState = null;
            _prevMightyGameState = null;
          } else {
            spectatorGameState = state;
            skGameState = null;
            llGameState = null;
            mightyGameState = null;
            _prevMightyGameState = null;
          }
          final spectatorList = state['spectators'] as List?;
          if (spectatorList != null) {
            spectators = spectatorList
                .map(
                  (s) => {
                    'id': (s['id'] ?? '').toString(),
                    'nickname': (s['nickname'] ?? '').toString(),
                  },
                )
                .toList();
          } else {
            spectators = [];
          }
        }
        notifyListeners();
        break;

      case 'restore_complete':
        _restoreSync.complete();
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
          if (autoRejectCardView) {
            respondCardViewRequest(spectatorId, false);
          } else if (autoAcceptCardView) {
            respondCardViewRequest(spectatorId, true);
          } else {
            // Remove duplicate if exists
            incomingCardViewRequests.removeWhere(
              (r) => r['spectatorId'] == spectatorId,
            );
            incomingCardViewRequests.add({
              'spectatorId': spectatorId,
              'spectatorNickname': spectatorNickname,
            });
          }
        }
        notifyListeners();
        break;

      case 'room_left':
        _clearRoomState(notify: false);
        notifyListeners();
        break;

      case 'kicked':
        final kickMessage = data['message'] as String? ?? 'kicked';
        final isDuplicateLogin = data['reason'] == 'duplicate_login';
        currentRoomId = '';
        currentRoomName = '';
        roomPlayers = List.filled(roomMaxPlayers, null);
        isHost = false;
        isRankedRoom = false;
        roomTurnTimeLimit = 30;
        roomTargetScore = 1000;
        isSpectator = false;
        gameState = null;
        _prevGameState = null;
        skGameState = null;
        _prevSKGameState = null;
        _prevLLGameState = null;
        llGameState = null;
        mightyGameState = null;
        _prevMightyGameState = null;
        currentGameType = 'tichu';
        roomMaxPlayers = 4;
        roomBlockedSlots = <int>{};
        chatMessages = [];
        autoRejectCardView = false;
        autoAcceptCardView = false;
        if (isDuplicateLogin) {
          playerId = '';
          playerName = '';
          duplicateLoginKicked = true;
        }
        errorMessage = kickMessage;
        notifyListeners();
        if (!isDuplicateLogin) {
          Future.delayed(const Duration(seconds: 3), () {
            if (_disposed) return; // C2: Don't notify after disposal
            errorMessage = null;
            notifyListeners();
          });
        }
        break;

      case 'room_closed':
        currentRoomId = '';
        currentRoomName = '';
        roomPlayers = List.filled(roomMaxPlayers, null);
        isHost = false;
        isRankedRoom = false;
        roomTurnTimeLimit = 30;
        roomTargetScore = 1000;
        roomMaxPlayers = 4;
        isSpectator = false;
        spectatorGameState = null;
        pendingCardViewRequests = {};
        approvedCardViews = {};
        incomingCardViewRequests = [];
        cardViewers = [];
        spectators = [];
        gameState = null;
        _prevGameState = null;
        skGameState = null;
        _prevSKGameState = null;
        _prevLLGameState = null;
        llGameState = null;
        mightyGameState = null;
        _prevMightyGameState = null;
        currentGameType = 'tichu';
        chatMessages = [];
        desertedPlayerName = null;
        desertedReason = null;
        autoRejectCardView = false;
        autoAcceptCardView = false;
        notifyListeners();
        break;

      case 'room_state':
        final room = data['room'] as Map<String, dynamic>?;
        if (room != null) {
          if (currentRoomId.isNotEmpty) {
            currentRoomName = room['name'] ?? currentRoomName;
          }
          // Reset SK state when returning from game to room
          currentGameType = room['gameType'] ?? 'tichu';
          final playersList = room['players'] as List?;
          if (playersList != null) {
            // Parse dynamic slot array with nulls
            roomPlayers = playersList.map((p) {
              if (p == null) return null;
              return Player.fromJson(p as Map<String, dynamic>);
            }).toList();
          }
          currentGameType = room['gameType'] ?? 'tichu';
          roomMaxPlayers = room['maxPlayers'] ?? 4;
          final blockedList = room['blockedSlots'] as List?;
          roomBlockedSlots = blockedList == null
              ? <int>{}
              : blockedList
                    .map((e) => e is int ? e : int.tryParse('$e') ?? -1)
                    .where((i) => i >= 0)
                    .toSet();
          final spectatorList = room['spectators'] as List?;
          if (spectatorList != null) {
            spectators = spectatorList
                .map(
                  (s) => {
                    'id': (s['id'] ?? '').toString(),
                    'nickname': (s['nickname'] ?? '').toString(),
                  },
                )
                .toList();
          } else {
            spectators = [];
          }
          isHost = roomPlayers.any(
            (p) => p != null && p.id == playerId && p.isHost,
          );
          isRankedRoom = room['isRanked'] == true;
          roomTurnTimeLimit = room['turnTimeLimit'] ?? 30;
          roomTargetScore = room['targetScore'] ?? 1000;
          if (room['gameInProgress'] != true) {
            pendingCardViewRequests = {};
            approvedCardViews = {};
            incomingCardViewRequests = [];
            cardViewers = [];
            gameState = null;
            skGameState = null;
            llGameState = null;
            mightyGameState = null;
            spectatorGameState = null;
            _prevGameState = null;
            _prevSKGameState = null;
            _prevLLGameState = null;
            _prevMightyGameState = null;
            myTimeoutCount = 0;
          }
        }
        notifyListeners();
        break;

      case 'game_state':
        if (currentRoomId.isEmpty) break; // Already left
        final state = data['state'] as Map<String, dynamic>?;
        if (state != null) {
          final stateGameType = state['gameType'] as String? ?? 'tichu';

          if (stateGameType == 'skull_king') {
            // Skull King game state
            currentGameType = 'skull_king';
            final nextSK = SKGameStateData.fromJson(state);
            _handleSKSfxTransitions(_prevSKGameState, nextSK);
            _prevSKGameState = nextSK;
            skGameState = nextSK;
            gameState = null;
            llGameState = null;
            mightyGameState = null;
            _prevGameState = null;
            _prevLLGameState = null;
            _prevMightyGameState = null;
            // Clear desertion state when SK phase is not game_end
            if (nextSK.phase != 'game_end') {
              desertedPlayerName = null;
              desertedReason = null;
            }
            final selfPlayer = nextSK.players.where(
              (p) => p.position == 'self',
            );
            myTimeoutCount = selfPlayer.isNotEmpty
                ? selfPlayer.first.timeoutCount
                : 0;
            // Parse card viewers and spectators for SK too
            final viewers = state['cardViewers'] as List?;
            if (viewers != null) {
              cardViewers = viewers
                  .map(
                    (v) => {
                      'id': (v['id'] ?? '').toString(),
                      'nickname': (v['nickname'] ?? '').toString(),
                    },
                  )
                  .toList();
            } else {
              cardViewers = [];
            }
            final skSpectatorList = state['spectators'] as List?;
            if (skSpectatorList != null) {
              spectators = skSpectatorList
                  .map(
                    (s) => {
                      'id': (s['id'] ?? '').toString(),
                      'nickname': (s['nickname'] ?? '').toString(),
                    },
                  )
                  .toList();
            } else {
              spectators = [];
            }
          } else if (stateGameType == 'mighty') {
            // Mighty game state
            currentGameType = 'mighty';
            final nextMighty = MightyGameStateData.fromJson(state);
            _handleMightySfxTransitions(_prevMightyGameState, nextMighty);
            _prevMightyGameState = mightyGameState;
            mightyGameState = nextMighty;
            gameState = null;
            skGameState = null;
            llGameState = null;
            _prevGameState = null;
            _prevSKGameState = null;
            _prevLLGameState = null;
            if (nextMighty.phase != 'game_end') {
              desertedPlayerName = null;
              desertedReason = null;
            }
            final selfPlayer = nextMighty.players.where(
              (p) => p.position == 'self',
            );
            myTimeoutCount = selfPlayer.isNotEmpty
                ? selfPlayer.first.timeoutCount
                : 0;
            final viewers = state['cardViewers'] as List?;
            if (viewers != null) {
              cardViewers = viewers
                  .map(
                    (v) => {
                      'id': (v['id'] ?? '').toString(),
                      'nickname': (v['nickname'] ?? '').toString(),
                    },
                  )
                  .toList();
            } else {
              cardViewers = [];
            }
            final mightySpectatorList = state['spectators'] as List?;
            if (mightySpectatorList != null) {
              spectators = mightySpectatorList
                  .map(
                    (s) => {
                      'id': (s['id'] ?? '').toString(),
                      'nickname': (s['nickname'] ?? '').toString(),
                    },
                  )
                  .toList();
            } else {
              spectators = [];
            }
          } else if (stateGameType == 'love_letter') {
            // Love Letter game state
            currentGameType = 'love_letter';
            final nextLL = LLGameStateData.fromJson(state);
            _handleLLSfxTransitions(_prevLLGameState, nextLL);
            _prevLLGameState = nextLL;
            llGameState = nextLL;
            gameState = null;
            skGameState = null;
            mightyGameState = null;
            _prevGameState = null;
            _prevSKGameState = null;
            _prevMightyGameState = null;
            if (nextLL.phase != 'game_end') {
              desertedPlayerName = null;
              desertedReason = null;
            }
            final selfPlayer = nextLL.players.where(
              (p) => p.position == 'self',
            );
            myTimeoutCount = selfPlayer.isNotEmpty
                ? selfPlayer.first.timeoutCount
                : 0;
            final viewers = state['cardViewers'] as List?;
            if (viewers != null) {
              cardViewers = viewers
                  .map(
                    (v) => {
                      'id': (v['id'] ?? '').toString(),
                      'nickname': (v['nickname'] ?? '').toString(),
                    },
                  )
                  .toList();
            } else {
              cardViewers = [];
            }
            final llSpectatorList = state['spectators'] as List?;
            if (llSpectatorList != null) {
              spectators = llSpectatorList
                  .map(
                    (s) => {
                      'id': (s['id'] ?? '').toString(),
                      'nickname': (s['nickname'] ?? '').toString(),
                    },
                  )
                  .toList();
            } else {
              spectators = [];
            }
          } else {
            // Tichu game state
            currentGameType = 'tichu';
            final nextState = GameStateData.fromJson(state);
            _handleSfxTransitions(_prevGameState, nextState);
            _prevGameState = nextState;
            skGameState = null;
            mightyGameState = null;
            _prevSKGameState = null;
            _prevLLGameState = null;
            _prevMightyGameState = null;

            // Clear desertion state when a new round/game starts
            final phase = state['phase'] as String? ?? '';
            if (phase != 'game_end') {
              desertedPlayerName = null;
              desertedReason = null;
            }
            // Parse card viewers
            final viewers = state['cardViewers'] as List?;
            if (viewers != null) {
              cardViewers = viewers
                  .map(
                    (v) => {
                      'id': (v['id'] ?? '').toString(),
                      'nickname': (v['nickname'] ?? '').toString(),
                    },
                  )
                  .toList();
            } else {
              cardViewers = [];
            }
            final spectatorList = state['spectators'] as List?;
            if (spectatorList != null) {
              spectators = spectatorList
                  .map(
                    (s) => {
                      'id': (s['id'] ?? '').toString(),
                      'nickname': (s['nickname'] ?? '').toString(),
                    },
                  )
                  .toList();
            } else {
              spectators = [];
            }
            _applyGameStateWithDogDelay(state);
          }
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
        _sfx.play('dog');
        notifyListeners();
        break;
      case 'cards_played':
        _sfx.play('card');
        final cards =
            (data['cards'] as List?)?.map((e) => e.toString()).toList() ?? [];
        if (cards.contains('special_dragon')) _sfx.play('dragon');
        if (cards.contains('special_dog')) _sfx.play('dog');
        // Clear dog banner when next cards are played
        if (dogPlayActive) {
          _dogClearTimer?.cancel();
          dogPlayActive = false;
          dogPlayPlayerName = '';
          notifyListeners();
        }
        break;
      case 'bomb_played':
        _sfx.play('card');
        if (dogPlayActive) {
          _dogClearTimer?.cancel();
          dogPlayActive = false;
          dogPlayPlayerName = '';
          notifyListeners();
        }
        break;
      case 'player_passed':
        break;
      case 'trick_won':
      case 'round_end':
      case 'large_tichu_declared':
        _sfx.play('large_tichu');
        break;
      case 'large_tichu_passed':
        break;
      case 'small_tichu_declared':
        _sfx.play('small_tichu');
        break;
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
          'timestamp':
              data['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
        };
        chatMessages.add(msg);
        if (chatMessages.length > 100) {
          chatMessages.removeAt(0);
        }
        if ((data['sender'] ?? '') != playerName) {
          _sfx.play('chat');
        }
        notifyListeners();
        break;

      case 'chat_banned':
        final mins = data['remainingMinutes'] ?? 0;
        chatMessages.add({
          'sender': '',
          'senderId': '',
          'message': 'chat_banned',
          'remainingMinutes': mins,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'isSystem': true,
        });
        notifyListeners();
        break;

      case 'chat_history':
        final messages = data['messages'] as List? ?? [];
        chatMessages = messages
            .map(
              (m) => {
                'sender': m['sender'] ?? '',
                'senderId': m['senderId'] ?? '',
                'message': m['message'] ?? '',
                'timestamp': m['timestamp'] ?? 0,
              },
            )
            .toList();
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
          friendsData = friendsList
              .map((f) => Map<String, dynamic>.from(f as Map))
              .toList();
          friends = friendsData
              .map((f) => f['nickname']?.toString() ?? '')
              .toList();
        } else {
          friends = friendsList.map((f) => f.toString()).toList();
          friendsData = friends
              .map((f) => <String, dynamic>{'nickname': f, 'isOnline': false})
              .toList();
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
        if (fromNickname.isNotEmpty &&
            !pendingFriendRequests.contains(fromNickname)) {
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

      case 'search_users_result':
        final users = data['users'] as List? ?? [];
        searchResults = users
            .map((u) => Map<String, dynamic>.from(u as Map))
            .toList();
        notifyListeners();
        break;

      case 'dm_message':
        final sender = data['sender'] as String? ?? '';
        final receiver = data['receiver'] as String? ?? '';
        final partner = sender == playerName ? receiver : sender;
        final msg = {
          'id': data['id'],
          'sender': sender,
          'receiver': receiver,
          'message': data['message'] as String? ?? '',
          'createdAt': data['createdAt']?.toString() ?? '',
        };
        dmMessages.putIfAbsent(partner, () => []);
        // Avoid duplicate
        final isNewMessage = !dmMessages[partner]!.any(
          (m) => m['id'] == msg['id'],
        );
        if (isNewMessage) {
          dmMessages[partner]!.add(msg);
        }
        // Update conversations
        requestDmConversations();
        if (isNewMessage && sender != playerName) {
          if (_activeDmPartner == partner) {
            markDmReadAction(partner);
            requestUnreadDmCount();
          } else {
            totalUnreadDmCount++;
          }
        }
        notifyListeners();
        break;

      case 'dm_error':
        errorMessage = data['message'] as String?;
        notifyListeners();
        Future.delayed(const Duration(seconds: 3), () {
          if (_disposed) return;
          errorMessage = null;
          notifyListeners();
        });
        break;

      case 'dm_history':
        final nickname = data['nickname'] as String? ?? '';
        final messages = data['messages'] as List? ?? [];
        final parsed = messages.map((m) {
          final raw = Map<String, dynamic>.from(m as Map);
          // Normalize DB column names to match dm_message format
          return {
            'id': raw['id'],
            'sender': raw['sender_nickname'] ?? raw['sender'] ?? '',
            'receiver': raw['receiver_nickname'] ?? raw['receiver'] ?? '',
            'message': raw['message'] ?? '',
            'createdAt': (raw['created_at'] ?? raw['createdAt'] ?? '')
                .toString(),
          };
        }).toList();
        if (nickname.isNotEmpty) {
          final existing = dmMessages[nickname] ?? [];
          final existingIds = existing.map((m) => m['id']).toSet();
          final newMsgs = parsed
              .where((m) => !existingIds.contains(m['id']))
              .toList();
          dmMessages[nickname] = [...newMsgs, ...existing];
        }
        notifyListeners();
        break;

      case 'dm_marked_read':
        final nickname = data['nickname'] as String? ?? '';
        if (nickname.isNotEmpty) {
          requestDmConversations();
          requestUnreadDmCount();
        }
        break;

      case 'dm_conversations':
        final convs = data['conversations'] as List? ?? [];
        dmConversations = convs
            .map((c) => Map<String, dynamic>.from(c as Map))
            .toList();
        notifyListeners();
        break;

      case 'unread_dm_count':
        totalUnreadDmCount = data['count'] as int? ?? 0;
        notifyListeners();
        break;

      case 'room_invite':
        final invite = Map<String, dynamic>.from(data);
        final roomId = invite['roomId'] as String? ?? '';
        final fromNickname = invite['fromNickname'] as String? ?? '';
        final exists = roomInvites.any(
          (item) =>
              (item['roomId'] as String? ?? '') == roomId &&
              (item['fromNickname'] as String? ?? '') == fromNickname,
        );
        if (!exists) {
          roomInvites.add(invite);
          notifyListeners();
        }
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

      case 'share_invite_link':
        _shareInviteLinkCompleter?.complete(data['url'] as String?);
        _shareInviteLinkCompleter = null;
        break;

      case 'share_invite_link_error':
        final message =
            data['message'] as String? ?? 'Failed to create share invite link';
        _shareInviteLinkCompleter?.completeError(StateError(message));
        _shareInviteLinkCompleter = null;
        break;

      case 'report_result':
        reportResultSuccess = data['success'] == true;
        reportResultMessage = data['message'] as String? ?? '';
        notifyListeners();
        break;

      case 'profile_result':
        _profiles.store(data);
        notifyListeners();
        break;

      case 'rankings_result':
        rankingsLoading = false;
        if (data['success'] == true) {
          final list = data['rankings'] as List? ?? [];
          rankings = list.map((e) => Map<String, dynamic>.from(e)).toList();
          rankingsError = null;
          myRank = data['myRank'] as int?;
          myRankData = data['myRankData'] != null
              ? Map<String, dynamic>.from(data['myRankData'] as Map)
              : null;
        } else {
          rankingsError = data['message'] as String? ?? 'rankings_load_failed';
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
      case 'gold_history_result':
        goldHistoryLoading = false;
        if (data['success'] == true) {
          final list = data['history'] as List? ?? [];
          goldHistory = list.map((e) => Map<String, dynamic>.from(e)).toList();
          goldHistoryError = null;
        } else {
          goldHistoryError =
              data['message'] as String? ?? 'gold_history_load_failed';
        }
        notifyListeners();
        break;
      case 'admin_dashboard_result':
        adminDashboardLoading = false;
        if (data['success'] == true) {
          adminDashboard = Map<String, dynamic>.from(
            data['dashboard'] as Map? ?? const {},
          );
        }
        notifyListeners();
        break;
      case 'admin_users_result':
        adminUsersLoading = false;
        if (data['success'] == true) {
          adminUsers = (data['rows'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          adminUsersError = null;
        } else {
          adminUsersError =
              data['message'] as String? ?? 'admin_users_load_failed';
        }
        notifyListeners();
        break;
      case 'admin_user_detail_result':
        adminUserDetailLoading = false;
        if (data['success'] == true) {
          adminUserDetail = Map<String, dynamic>.from(
            data['user'] as Map? ?? const {},
          );
          adminUserDetailError = null;
        } else {
          adminUserDetailError =
              data['message'] as String? ?? 'admin_user_detail_load_failed';
        }
        notifyListeners();
        break;
      case 'admin_inquiries_result':
        adminInquiriesLoading = false;
        if (data['success'] == true) {
          adminInquiries = (data['rows'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          adminInquiriesError = null;
        } else {
          adminInquiriesError =
              data['message'] as String? ?? 'admin_inquiries_load_failed';
        }
        notifyListeners();
        break;
      case 'admin_reports_result':
        adminReportsLoading = false;
        if (data['success'] == true) {
          adminReports = (data['rows'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          adminReportsError = null;
        } else {
          adminReportsError =
              data['message'] as String? ?? 'admin_reports_load_failed';
        }
        notifyListeners();
        break;
      case 'admin_report_group_result':
        adminReportGroupLoading = false;
        if (data['success'] == true) {
          adminReportGroup = (data['rows'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          adminReportGroupError = null;
        } else {
          adminReportGroupError =
              data['message'] as String? ?? 'admin_report_group_load_failed';
        }
        notifyListeners();
        break;
      case 'admin_set_user_result':
      case 'admin_adjust_gold_result':
      case 'admin_inquiry_resolve_result':
      case 'admin_report_status_result':
        adminActionSuccess = data['success'] == true;
        adminActionMessage =
            data['message'] as String? ??
            (adminActionSuccess == true
                ? 'admin_action_success'
                : 'admin_action_failed');
        if (type == 'admin_adjust_gold_result' &&
            adminActionSuccess == true &&
            adminUserDetail?['nickname'] == data['nickname']) {
          adminUserDetail = {
            ...?adminUserDetail,
            'gold': data['newGold'] ?? adminUserDetail?['gold'],
          };
        }
        notifyListeners();
        break;
      case 'admin_notice':
        final kind = data['kind']?.toString();
        if (kind == 'inquiry') {
          requestAdminDashboard();
          requestAdminInquiries();
        } else if (kind == 'report') {
          requestAdminDashboard();
          requestAdminReports();
        } else {
          requestAdminDashboard();
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
          shopError = data['message'] as String? ?? 'shop_load_failed';
        }
        notifyListeners();
        break;

      case 'inventory_result':
        inventoryLoading = false;
        if (data['success'] == true) {
          final list = data['items'] as List? ?? [];
          inventoryItems = list
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          inventoryError = null;
        } else {
          inventoryError =
              data['message'] as String? ?? 'inventory_load_failed';
        }
        notifyListeners();
        break;

      case 'purchase_result':
      case 'equip_result':
      case 'use_item_result':
        // Refresh wallet/inventory after actions
        requestWallet();
        requestInventory();
        shopActionSuccess = data['success'] == true;
        shopActionMessage = data['message'] as String?;
        if (type == 'purchase_result') {
          lastPurchaseItemKey = data['itemKey'] as String?;
          lastPurchaseSuccess = data['success'] == true;
          lastPurchaseExtended = data['extended'] == true;
          if (data['success'] == true &&
              data['itemKey'] == 'top_card_counter_7d') {
            hasTopCardCounter = true;
          }
          if (data['success'] == true &&
              data['itemKey'] == 'mighty_trump_counter_7d') {
            hasMightyTrumpCounter = true;
          }
        }
        if (type == 'equip_result' && data['success'] == true) {
          final themeKey = data['themeKey'] as String?;
          if (themeKey != null) {
            equippedTheme = themeKey;
          }
          final titleKey = data['titleKey'] as String?;
          if (titleKey != null) {
            equippedTitle = titleKey;
          }
        }
        notifyListeners();
        break;

      case 'inquiry_result':
        inquiryResultSuccess = data['success'] == true;
        inquiryResultMessage = data['message'] as String? ?? '';
        notifyListeners();
        break;

      case 'inquiries_result':
        inquiriesLoading = false;
        if (data['success'] == true) {
          inquiries =
              (data['inquiries'] as List?)
                  ?.map((e) => (e as Map).cast<String, dynamic>())
                  .toList() ??
              [];
          inquiriesError = null;
          _maybeShowInquiryBanner();
        } else {
          inquiriesError =
              data['message'] as String? ?? 'inquiries_load_failed';
          inquiries = [];
        }
        notifyListeners();
        break;

      case 'notices_result':
        noticesLoading = false;
        if (data['success'] == true) {
          notices =
              (data['notices'] as List?)
                  ?.map((e) => (e as Map).cast<String, dynamic>())
                  .toList() ??
              [];
          noticesError = null;
          if (_pendingNoticeMarkRead) {
            _pendingNoticeMarkRead = false;
            markCurrentNoticesAsRead();
          }
        } else {
          noticesError = data['message'] as String? ?? 'notices_load_failed';
          notices = [];
          _pendingNoticeMarkRead = false;
        }
        notifyListeners();
        break;

      case 'maintenance_status':
        _parseMaintenanceStatus(data);
        notifyListeners();
        break;

      case 'change_nickname_result':
        if (data['success'] == true) {
          final nn = data['newNickname'] as String? ?? '';
          if (nn.isNotEmpty) playerName = nn;
          nicknameChangeResult = 'nickname_changed';
          nicknameChangeSuccess = true;
        } else {
          nicknameChangeResult =
              data['message'] as String? ?? 'nickname_change_failed';
          nicknameChangeSuccess = false;
        }
        requestWallet();
        requestInventory();
        notifyListeners();
        break;

      case 'ad_reward_result':
        adRewardSuccess = data['success'] == true;
        if (adRewardSuccess!) {
          gold = (data['gold'] as num?)?.toInt() ?? gold;
          adRewardRemaining = (data['remaining'] as num?)?.toInt() ?? 0;
          adRewardResult = 'ad_reward_success';
        } else {
          adRewardResult = data['message'] as String? ?? 'reward_failed';
        }
        notifyListeners();
        break;

      case 'social_link_result':
        socialLinkResultSuccess = data['success'] == true;
        socialLinkResultMessage = data['message'] as String?;
        if (data['success'] == true && data['provider'] != null) {
          linkedSocialProvider = data['provider'] as String?;
          authProvider = data['provider'] as String;
        }
        notifyListeners();
        break;

      case 'social_unlink_result':
        socialLinkResultSuccess = data['success'] == true;
        socialLinkResultMessage = data['message'] as String?;
        if (data['success'] == true) {
          linkedSocialProvider = 'local';
          linkedSocialEmail = null;
          authProvider = 'local';
        }
        notifyListeners();
        break;

      case 'linked_social_info':
        linkedSocialProvider = data['provider'] as String?;
        linkedSocialEmail = data['email'] as String?;
        notifyListeners();
        break;

      case 'app_config':
        eulaContent = data['eulaContent'] as String? ?? '';
        privacyPolicy = data['privacyPolicy'] as String? ?? '';
        minVersion = data['minVersion'] as String? ?? '';
        latestVersion = data['latestVersion'] as String? ?? '';
        notifyListeners();
        break;
    }
  }

  void _parseMaintenanceStatus(Map<String, dynamic>? status) {
    if (status == null) return;
    hasMaintenanceNotice = status['notice'] == true;
    isUnderMaintenance = status['maintenance'] == true;
    maintenanceMessage = (status['message'] as String?) ?? '';
    maintenanceStart = status['maintenanceStart'] as String?;
    maintenanceEnd = status['maintenanceEnd'] as String?;
    _saveMaintenanceCache();
  }

  Future<void> _saveMaintenanceCache() async {
    final prefs = await SharedPreferences.getInstance();
    if (maintenanceStart != null && maintenanceEnd != null) {
      await prefs.setString('maintenance_start', maintenanceStart!);
      await prefs.setString('maintenance_end', maintenanceEnd!);
      await prefs.setString('maintenance_message', maintenanceMessage);
    } else {
      await prefs.remove('maintenance_start');
      await prefs.remove('maintenance_end');
      await prefs.remove('maintenance_message');
    }
  }

  Future<void> _restoreMaintenanceCache() async {
    final prefs = await SharedPreferences.getInstance();
    final start = prefs.getString('maintenance_start');
    final end = prefs.getString('maintenance_end');
    if (start != null && end != null) {
      maintenanceStart = start;
      maintenanceEnd = end;
      maintenanceMessage = prefs.getString('maintenance_message') ?? '';
    }
  }

  Future<void> clearMaintenanceCache() async {
    maintenanceStart = null;
    maintenanceEnd = null;
    maintenanceMessage = '';
    isUnderMaintenance = false;
    hasMaintenanceNotice = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('maintenance_start');
    await prefs.remove('maintenance_end');
    await prefs.remove('maintenance_message');
  }

  bool get isInKnownMaintenanceWindow {
    if (maintenanceStart == null || maintenanceEnd == null) return false;
    try {
      final start = DateTime.parse(maintenanceStart!);
      final end = DateTime.parse(maintenanceEnd!);
      final now = DateTime.now().toUtc();
      return now.isAfter(start) && now.isBefore(end);
    } catch (_) {
      return false;
    }
  }

  void _handleDogPlayed(Map<String, dynamic> data) {
    dogPlayActive = true;
    dogPlayPlayerName = (data['playerName'] as String?) ?? '';
    _dogDelayUntil = DateTime.now().add(const Duration(seconds: 2));

    _dogClearTimer?.cancel();
    _dogClearTimer = Timer(const Duration(seconds: 2), () {
      if (_disposed) return;
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

  void _handleSfxTransitions(GameStateData? prev, GameStateData next) {
    if (prev == null) {
      if (next.isMyTurn) {
        _sfx.play('my_turn');
      }
      return;
    }

    if (!prev.isMyTurn && next.isMyTurn) {
      _sfx.play('my_turn');
    }

    if (prev.phase != next.phase) {
      if (next.phase == 'round_end') {
        _sfx.play('round_end');
      } else if (next.phase == 'game_end') {
        final teamA = next.totalScores['teamA'] ?? 0;
        final teamB = next.totalScores['teamB'] ?? 0;
        final isWin = next.myTeam == 'A' ? teamA > teamB : teamB > teamA;
        _sfx.play(isWin ? 'victory' : 'defeat');
      }
    }
  }

  void _handleSKSfxTransitions(SKGameStateData? prev, SKGameStateData next) {
    if (prev == null) {
      if (next.isMyTurn) {
        _sfx.play('my_turn');
      }
      return;
    }

    // Card played: trick grew
    if (next.currentTrick.length > prev.currentTrick.length) {
      _sfx.play('card');
    }

    // My turn
    if (!prev.isMyTurn && next.isMyTurn) {
      _sfx.play('my_turn');
    }

    // Phase transitions
    if (prev.phase != next.phase) {
      if (next.phase == 'round_end') {
        _sfx.play('round_end');
      } else if (next.phase == 'game_end') {
        // Find self and check if rank 1
        final self = next.players.where((p) => p.position == 'self');
        if (self.isNotEmpty) {
          final myScore = self.first.totalScore;
          final maxScore = next.players
              .map((p) => p.totalScore)
              .reduce((a, b) => a > b ? a : b);
          _sfx.play(myScore >= maxScore ? 'victory' : 'defeat');
        }
      }
    }
  }

  void _handleLLSfxTransitions(LLGameStateData? prev, LLGameStateData next) {
    if (prev == null) {
      if (next.isMyTurn) {
        _sfx.play('my_turn');
      }
      return;
    }

    // Card played: discard pile grew for any player
    final prevDiscardTotal = prev.players.fold<int>(0, (s, p) => s + p.discardPile.length);
    final nextDiscardTotal = next.players.fold<int>(0, (s, p) => s + p.discardPile.length);
    if (nextDiscardTotal > prevDiscardTotal) {
      _sfx.play('card');
    }

    // My turn
    if (!prev.isMyTurn && next.isMyTurn) {
      _sfx.play('my_turn');
    }

    // Phase transitions
    if (prev.phase != next.phase) {
      if (next.phase == 'round_end') {
        _sfx.play('round_end');
      } else if (next.phase == 'game_end') {
        // Check if self won (has most tokens)
        final self = next.players.where((p) => p.position == 'self');
        if (self.isNotEmpty) {
          final myTokens = self.first.tokens;
          final maxTokens = next.players
              .map((p) => p.tokens)
              .reduce((a, b) => a > b ? a : b);
          _sfx.play(myTokens >= maxTokens ? 'victory' : 'defeat');
        }
      }
    }
  }

  void _handleMightySfxTransitions(MightyGameStateData? prev, MightyGameStateData next) {
    if (prev == null) {
      if (next.isMyTurn) {
        _sfx.play('my_turn');
      }
      return;
    }

    // Card played: trick grew
    if (next.currentTrick.length > prev.currentTrick.length) {
      _sfx.play('card');
    }

    // My turn
    if (!prev.isMyTurn && next.isMyTurn) {
      _sfx.play('my_turn');
    }

    // Phase transitions
    if (prev.phase != next.phase) {
      if (next.phase == 'round_end') {
        _sfx.play('round_end');
      } else if (next.phase == 'game_end') {
        // Check if self won (highest score)
        final self = next.players.where((p) => p.position == 'self');
        if (self.isNotEmpty) {
          final myScore = next.scores[self.first.id] ?? 0;
          final maxScore = next.scores.values.isEmpty ? 0
              : next.scores.values.reduce((a, b) => a > b ? a : b);
          _sfx.play(myScore >= maxScore ? 'victory' : 'defeat');
        }
      }
    }
  }

  Future<void> _loadSfxPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble('sfx_volume');
      if (saved != null) {
        sfxVolume = saved.clamp(0.0, 1.0);
        await _sfx.setVolume(sfxVolume);
      }
    } catch (_) {}
  }

  Future<void> setSfxVolume(double value, {bool persist = false}) async {
    sfxVolume = value.clamp(0.0, 1.0);
    await _sfx.setVolume(sfxVolume);
    if (persist) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('sfx_volume', sfxVolume);
      } catch (_) {}
    }
    notifyListeners();
  }

  void playCountdownTick() {
    _sfx.play('countdown_tick');
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
      if (_disposed) return;
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

  void loginWithCredentials(
    String username,
    String password, {
    Map<String, String?>? deviceInfo,
  }) {
    loginError = null;
    _network.send({
      'type': 'login',
      'username': username,
      'password': password,
      ...?deviceInfo == null ? null : {'deviceInfo': deviceInfo},
    });
  }

  void loginSocial(
    String provider,
    String token, {
    Map<String, String?>? deviceInfo,
  }) {
    loginError = null;
    needNickname = false;
    socialProvider = provider;
    socialToken = token;
    _network.send({
      'type': 'social_login',
      'provider': provider,
      'token': token,
      ...?deviceInfo == null ? null : {'deviceInfo': deviceInfo},
    });
  }

  void registerSocial(
    String provider,
    String token,
    String nickname, {
    bool existingUser = false,
    Map<String, String?>? deviceInfo,
  }) {
    loginError = null;
    _network.send({
      'type': 'social_register',
      'provider': provider,
      'token': token,
      'nickname': nickname,
      if (existingUser) 'existingUser': true,
      ...?deviceInfo == null ? null : {'deviceInfo': deviceInfo},
    });
  }

  void register(String username, String password, String nickname) {
    registerResult = null;
    registerSuccess = null;
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
    loginErrorReason = null;
    registerResult = null;
    registerSuccess = null;
    nicknameAvailable = null;
    nicknameCheckMessage = null;
  }

  void reset() {
    _dogDelayTimer?.cancel();
    _dogDelayTimer = null;
    _dogClearTimer?.cancel();
    _dogClearTimer = null;
    _inquiryBannerTimer?.cancel();
    _inquiryBannerTimer = null;
    _pushToggleTimer?.cancel();
    _pushToggleTimer = null;
    _dogDelayUntil = null;
    _pendingGameState = null;
    _prevGameState = null;
    _prevSKGameState = null;
    _prevLLGameState = null;
    playerId = '';
    playerName = '';
    equippedTheme = null;
    equippedTitle = null;
    currentRoomId = '';
    currentRoomName = '';
    roomPlayers = List.filled(4, null);
    isHost = false;
    isRankedRoom = false;
    roomTurnTimeLimit = 30;
    roomTargetScore = 1000;
    roomMaxPlayers = 4;
    roomBlockedSlots = <int>{};
    currentGameType = 'tichu';
    roomList = [];
    spectatableRooms = [];
    isSpectator = false;
    duplicateLoginKicked = false;
    spectatorGameState = null;
    pendingCardViewRequests = {};
    approvedCardViews = {};
    incomingCardViewRequests = [];
    cardViewers = [];
    spectators = [];
    gameState = null;
    skGameState = null;
    errorMessage = null;
    chatMessages = [];
    blockedUsers = {};
    friends = [];
    dmConversations = [];
    dmMessages = {};
    totalUnreadDmCount = 0;
    _activeDmPartner = null;
    searchResults = [];
    _profiles.clear();
    friendsData = [];
    pendingFriendRequests = [];
    pendingFriendRequestCount = 0;
    roomInvites = [];
    sentFriendRequests = {};
    _roomInviteCooldowns.clear();
    rankings = [];
    rankingsLoading = false;
    rankingsError = null;
    myRank = null;
    adRewardResult = null;
    adRewardSuccess = null;
    autoRejectCardView = false;
    autoAcceptCardView = false;
    myRankData = null;
    seasons = [];
    gold = 0;
    leaveCount = 0;
    goldHistory = [];
    shopItems = [];
    inventoryItems = [];
    shopLoading = false;
    goldHistoryLoading = false;
    inventoryLoading = false;
    goldHistoryError = null;
    shopError = null;
    inventoryError = null;
    lastPurchaseItemKey = null;
    lastPurchaseSuccess = null;
    lastPurchaseExtended = false;
    shopActionMessage = null;
    shopActionSuccess = null;
    reportResultMessage = null;
    reportResultSuccess = null;
    inquiryResultMessage = null;
    inquiryResultSuccess = null;
    inquiries = [];
    inquiriesLoading = false;
    inquiriesError = null;
    isAdminUser = false;
    pushAdminInquiryEnabled = true;
    pushAdminReportEnabled = true;
    adminDashboard = null;
    adminDashboardLoading = false;
    adminUsers = [];
    adminUsersLoading = false;
    adminUsersError = null;
    adminUserDetail = null;
    adminUserDetailLoading = false;
    adminUserDetailError = null;
    adminInquiries = [];
    adminInquiriesLoading = false;
    adminInquiriesError = null;
    adminReports = [];
    adminReportsLoading = false;
    adminReportsError = null;
    adminReportGroup = [];
    adminReportGroupLoading = false;
    adminReportGroupError = null;
    adminActionMessage = null;
    adminActionSuccess = null;
    hasTopCardCounter = false;
    hasMightyTrumpCounter = false;
    dogPlayActive = false;
    dogPlayPlayerName = '';
    inquiryBannerMessage = null;
    dragonGivenMessage = null;
    timeoutPlayerName = null;
    desertedPlayerName = null;
    desertedReason = null;
    myTimeoutCount = 0;
    nicknameChangeResult = null;
    nicknameChangeSuccess = null;
    authProvider = 'local';
    needNickname = false;
    socialProvider = null;
    socialToken = null;
    socialProviderUid = null;
    socialEmail = null;
    socialExistingUser = false;
    linkedSocialProvider = null;
    linkedSocialEmail = null;
    socialLinkResultMessage = null;
    socialLinkResultSuccess = null;
    // Note: maintenance fields are preserved across reset()
    // so MaintenanceScreen can still show after connection loss.
    // Use clearMaintenanceCache() to explicitly clear them.
    clearAuthState();
    notifyListeners();
  }

  void prepareForLoginAttempt() {
    playerId = '';
    loginError = null;
    loginErrorReason = null;
    needNickname = false;
    gameState = null;
    skGameState = null;
    spectatorGameState = null;
    _prevGameState = null;
    _prevSKGameState = null;
    _prevLLGameState = null;
    currentGameType = 'tichu';
    myTimeoutCount = 0;
  }

  bool consumeDuplicateLoginKick() {
    if (!duplicateLoginKicked) return false;
    duplicateLoginKicked = false;
    return true;
  }

  void requestMaintenanceStatus() {
    _network.send({'type': 'get_maintenance_status'});
  }

  Future<void> deleteAccount() async {
    _network.send({'type': 'delete_account'});
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }

  void setAdminAlertPush({bool? inquiry, bool? report}) {
    final payload = <String, dynamic>{'type': 'update_push_setting'};
    if (inquiry != null) {
      pushAdminInquiryEnabled = inquiry;
      payload['inquiryAlert'] = inquiry;
    }
    if (report != null) {
      pushAdminReportEnabled = report;
      payload['reportAlert'] = report;
    }
    notifyListeners();
    _network.send(payload);
  }

  void requestAdminDashboard() {
    adminDashboardLoading = true;
    notifyListeners();
    _network.send({'type': 'get_admin_dashboard'});
  }

  void requestAdminUsers({String search = '', int page = 1, int limit = 50}) {
    adminUsersLoading = true;
    adminUsersError = null;
    notifyListeners();
    _network.send({
      'type': 'get_admin_users',
      'search': search,
      'page': page,
      'limit': limit,
    });
  }

  void requestAdminUserDetail(String nickname) {
    adminUserDetailLoading = true;
    adminUserDetailError = null;
    notifyListeners();
    _network.send({'type': 'get_admin_user_detail', 'nickname': nickname});
  }

  void setAdminUser(String nickname, bool isAdmin) {
    _network.send({
      'type': 'set_admin_user',
      'nickname': nickname,
      'isAdmin': isAdmin,
    });
  }

  void adjustAdminGold(String nickname, int amount) {
    _network.send({
      'type': 'admin_adjust_gold',
      'nickname': nickname,
      'amount': amount,
    });
  }

  void requestAdminInquiries({int page = 1, int limit = 50}) {
    adminInquiriesLoading = true;
    adminInquiriesError = null;
    notifyListeners();
    _network.send({
      'type': 'get_admin_inquiries',
      'page': page,
      'limit': limit,
    });
  }

  void resolveAdminInquiry(int id, String adminNote) {
    _network.send({
      'type': 'resolve_admin_inquiry',
      'id': id,
      'adminNote': adminNote,
    });
  }

  void requestAdminReports({int page = 1, int limit = 50}) {
    adminReportsLoading = true;
    adminReportsError = null;
    notifyListeners();
    _network.send({'type': 'get_admin_reports', 'page': page, 'limit': limit});
  }

  void requestAdminReportGroup(String target, String roomId) {
    adminReportGroupLoading = true;
    adminReportGroupError = null;
    notifyListeners();
    _network.send({
      'type': 'get_admin_report_group',
      'target': target,
      'roomId': roomId,
    });
  }

  void updateAdminReportStatus(String target, String roomId, String status) {
    _network.send({
      'type': 'update_admin_report_status',
      'target': target,
      'roomId': roomId,
      'status': status,
    });
  }

  void requestRoomList() {
    _network.send({'type': 'room_list'});
  }

  void requestSpectatableRooms() {
    _network.send({'type': 'spectatable_rooms'});
  }

  void spectateRoom(String roomId, {String password = ''}) {
    _network.send({
      'type': 'spectate_room',
      'roomId': roomId,
      'password': password,
    });
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
    incomingCardViewRequests.removeWhere(
      (r) => r['spectatorId'] == spectatorId,
    );
    notifyListeners();
  }

  void rejectAllCardViewRequests() {
    for (final req in List<Map<String, String>>.from(
      incomingCardViewRequests,
    )) {
      respondCardViewRequest(req['spectatorId'] ?? '', false);
    }
    incomingCardViewRequests.clear();
    autoRejectCardView = true;
    autoAcceptCardView = false;
    notifyListeners();
  }

  void setAutoRejectCardView(bool value) {
    if (autoRejectCardView == value) return;
    autoRejectCardView = value;
    if (value) autoAcceptCardView = false;
    notifyListeners();
  }

  void setAutoAcceptCardView(bool value) {
    if (autoAcceptCardView == value) return;
    autoAcceptCardView = value;
    if (value) autoRejectCardView = false;
    notifyListeners();
  }

  bool get hasIncomingCardViewRequests => incomingCardViewRequests.isNotEmpty;
  bool get hasPendingCardViewRequest => pendingCardViewRequests.isNotEmpty;

  void expireCardViewRequest(String playerId) {
    if (pendingCardViewRequests.remove(playerId)) {
      notifyListeners();
    }
  }

  Map<String, String>? get firstIncomingCardViewRequest {
    if (incomingCardViewRequests.isEmpty) return null;
    return incomingCardViewRequests.first;
  }

  void createRoom(
    String roomName, {
    String password = '',
    bool isRanked = false,
    int turnTimeLimit = 30,
    int targetScore = 1000,
    String gameType = 'tichu',
    int maxPlayers = 4,
    List<String> skExpansions = const [],
  }) {
    final msg = <String, dynamic>{
      'type': 'create_room',
      'roomName': roomName,
      'password': password,
      'isRanked': isRanked,
      'turnTimeLimit': turnTimeLimit,
      'targetScore': targetScore,
    };
    if (gameType == 'skull_king') {
      msg['gameType'] = 'skull_king';
      msg['maxPlayers'] = maxPlayers;
      msg['skExpansions'] = skExpansions;
    } else if (gameType == 'love_letter') {
      msg['gameType'] = 'love_letter';
      msg['maxPlayers'] = maxPlayers;
    } else if (gameType == 'mighty') {
      msg['gameType'] = 'mighty';
      msg['maxPlayers'] = maxPlayers;
    }
    _network.send(msg);
  }

  void joinRoom(String roomId, {String password = ''}) {
    _network.send({
      'type': 'join_room',
      'roomId': roomId,
      'password': password,
    });
  }

  void joinRoomByInviteToken(String token) {
    _network.send({'type': 'join_room_by_invite', 'token': token});
  }

  void leaveRoom() {
    _network.send({'type': 'leave_room'});
  }

  void leaveGame() {
    _network.send({'type': 'leave_game'});
  }

  void _clearRoomState({bool notify = true}) {
    currentRoomId = '';
    currentRoomName = '';
    roomPlayers = List.filled(roomMaxPlayers, null);
    isHost = false;
    isRankedRoom = false;
    roomTurnTimeLimit = 30;
    roomTargetScore = 1000;
    roomMaxPlayers = 4;
    roomBlockedSlots = <int>{};
    currentGameType = 'tichu';
    isSpectator = false;
    gameState = null;
    _prevGameState = null;
    skGameState = null;
    _prevSKGameState = null;
    _prevLLGameState = null;
    llGameState = null;
    mightyGameState = null;
    _prevMightyGameState = null;
    spectatorGameState = null;
    pendingCardViewRequests = {};
    approvedCardViews = {};
    incomingCardViewRequests = [];
    autoRejectCardView = false;
    autoAcceptCardView = false;
    cardViewers = [];
    spectators = [];
    chatMessages = [];
    desertedPlayerName = null;
    desertedReason = null;
    dragonGivenMessage = null;
    myTimeoutCount = 0;
    if (notify) {
      notifyListeners();
    }
  }

  void addBot({int? targetSlot, String speed = 'normal'}) {
    final msg = <String, dynamic>{'type': 'add_bot', 'speed': speed};
    if (targetSlot != null) msg['targetSlot'] = targetSlot;
    _network.send(msg);
  }

  void blockSlot(int slotIndex) {
    _network.send({'type': 'block_slot', 'slotIndex': slotIndex});
  }

  void unblockSlot(int slotIndex) {
    _network.send({'type': 'unblock_slot', 'slotIndex': slotIndex});
  }

  void toggleReady() {
    _network.send({'type': 'toggle_ready'});
  }

  void startGame() {
    _network.send({'type': 'start_game'});
  }

  // SK actions
  void submitBid(int bid) {
    _network.send({'type': 'submit_bid', 'bid': bid});
  }

  void playCard(String cardId, {String? tigressChoice}) {
    final msg = <String, dynamic>{'type': 'play_card', 'cardId': cardId};
    if (tigressChoice != null) msg['tigressChoice'] = tigressChoice;
    _network.send(msg);
  }

  // LL actions
  void llPlayCard(String cardId) {
    _network.send({'type': 'play_card', 'cardId': cardId});
  }

  void llSelectTarget(String targetId) {
    _network.send({'type': 'select_target', 'targetId': targetId});
  }

  void llGuardGuess(String targetId, String guess) {
    _network.send({
      'type': 'guard_guess',
      'targetId': targetId,
      'guess': guess,
    });
  }

  void llEffectAck() {
    _network.send({'type': 'effect_ack'});
  }

  // Mighty actions
  void mightySubmitBid(int points, String suit) {
    _network.send({
      'type': 'submit_bid',
      'points': points,
      'suit': suit,
    });
  }

  void mightyPass() {
    _network.send({'type': 'submit_bid', 'pass': true});
  }

  void mightyDeclareDealMiss() {
    _network.send({'type': 'declare_deal_miss'});
  }

  void mightyDeclareKill(String cardId) {
    _network.send({'type': 'declare_kill', 'cardId': cardId});
  }

  void mightyDiscardKitty(List<String> discards, String friendCard) {
    _network.send({
      'type': 'discard_kitty',
      'discards': discards,
      'friendCard': friendCard,
    });
  }

  void mightyChangeTrump(String suit) {
    _network.send({'type': 'change_trump', 'suit': suit});
  }

  void mightyRaiseBid() {
    _network.send({'type': 'raise_bid'});
  }

  void mightyPlayCard(String cardId, {String? jokerSuit, bool jokerCall = false}) {
    final msg = <String, dynamic>{'type': 'play_card', 'cardId': cardId};
    if (jokerSuit != null) msg['jokerSuit'] = jokerSuit;
    if (jokerCall) msg['jokerCall'] = true;
    _network.send(msg);
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
      'cards': {'left': left, 'partner': partner, 'right': right},
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
  }

  void checkRoom() {
    _network.send({'type': 'check_room'});
  }

  Future<bool> checkRoomAndWait({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    return _restoreSync.begin(
      timeout: timeout,
      request: () => _network.send({'type': 'check_room'}),
    );
  }

  void nextRound() {
    _network.send({'type': 'next_round'});
  }

  void changeTeam(int targetSlot) {
    _network.send({'type': 'change_team', 'targetSlot': targetSlot});
  }

  void changeRoomName(String newName) {
    _network.send({'type': 'change_room_name', 'roomName': newName});
  }

  // Kick player (host only)
  void kickPlayer(String targetPlayerId) {
    _network.send({'type': 'kick_player', 'playerId': targetPlayerId});
  }

  // Request user profile
  void requestProfile(String nickname) {
    _profiles.beginRequest(nickname);
    _network.send({'type': 'get_profile', 'nickname': nickname});
  }

  void fallbackToLobbyAfterRestoreFailure() {
    currentRoomId = '';
    currentRoomName = '';
    roomPlayers = List.filled(4, null);
    isHost = false;
    isRankedRoom = false;
    isSpectator = false;
    spectatorGameState = null;
    pendingCardViewRequests = {};
    approvedCardViews = {};
    incomingCardViewRequests = [];
    cardViewers = [];
    gameState = null;
    _prevGameState = null;
    _prevSKGameState = null;
    _prevLLGameState = null;
    errorMessage = 'room_restore_fallback';
    notifyListeners();
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

  void requestSKRankings() {
    rankingsLoading = true;
    rankingsError = null;
    _network.send({
      'type': 'get_rankings',
      'gameType': 'skull_king',
      'seasonId': 'current',
    });
    notifyListeners();
  }

  void requestSKRankingsForSeason(int seasonId) {
    rankingsLoading = true;
    rankingsError = null;
    _network.send({
      'type': 'get_rankings',
      'gameType': 'skull_king',
      'seasonId': seasonId,
    });
    notifyListeners();
  }

  void requestMightyRankings() {
    rankingsLoading = true;
    rankingsError = null;
    _network.send({
      'type': 'get_rankings',
      'gameType': 'mighty',
      'seasonId': 'current',
    });
    notifyListeners();
  }

  void requestMightyRankingsForSeason(int seasonId) {
    rankingsLoading = true;
    rankingsError = null;
    _network.send({
      'type': 'get_rankings',
      'gameType': 'mighty',
      'seasonId': seasonId,
    });
    notifyListeners();
  }

  void requestSeasons() {
    _network.send({'type': 'get_seasons'});
  }

  // Shop
  void requestAppConfig() {
    _network.send({'type': 'get_app_config'});
  }

  void sendLocale(String languageCode) {
    _network.send({'type': 'set_locale', 'locale': languageCode});
  }

  void requestWallet() {
    _network.send({'type': 'get_wallet'});
  }

  void requestGoldHistory({int limit = 30}) {
    goldHistoryLoading = true;
    goldHistoryError = null;
    notifyListeners();
    _network.send({'type': 'get_gold_history', 'limit': limit});
  }

  // 광고 보상
  String? adRewardResult;
  bool? adRewardSuccess;
  int adRewardRemaining = 0;

  void claimAdReward() {
    _network.send({'type': 'ad_reward'});
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

  void changeNickname(String newNickname) {
    _network.send({'type': 'change_nickname', 'newNickname': newNickname});
  }

  // Social link
  void linkSocial(String provider, String token) {
    socialLinkResultSuccess = null;
    socialLinkResultMessage = null;
    _network.send({
      'type': 'social_link',
      'provider': provider,
      'token': token,
    });
  }

  void unlinkSocial() {
    socialLinkResultSuccess = null;
    socialLinkResultMessage = null;
    _network.send({'type': 'social_unlink'});
  }

  void getLinkedSocial() {
    _network.send({'type': 'get_linked_social'});
  }

  void clearSocialLinkResult() {
    socialLinkResultSuccess = null;
    socialLinkResultMessage = null;
  }

  void clearLastPurchaseResult() {
    lastPurchaseItemKey = null;
    lastPurchaseSuccess = null;
    lastPurchaseExtended = false;
  }

  void clearShopActionResult() {
    shopActionMessage = null;
    shopActionSuccess = null;
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
    _network.send({
      'type': 'report_user',
      'nickname': nickname,
      'reason': reason,
    });
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
    if (!isInWaitingRoom) {
      errorMessage = 'invite_in_game';
      notifyListeners();
      Future.delayed(const Duration(seconds: 3), () {
        if (_disposed) return;
        if (errorMessage == 'invite_in_game') {
          errorMessage = null;
          notifyListeners();
        }
      });
      return;
    }
    if (isRoomInvitePending(nickname)) {
      errorMessage = 'invite_cooldown';
      notifyListeners();
      Future.delayed(const Duration(seconds: 3), () {
        if (_disposed) return;
        if (errorMessage == 'invite_cooldown') {
          errorMessage = null;
          notifyListeners();
        }
      });
      return;
    }
    _roomInviteCooldowns[nickname] = DateTime.now().add(
      const Duration(seconds: 10),
    );
    _network.send({'type': 'invite_to_room', 'nickname': nickname});
    notifyListeners();
  }

  Future<String?> createShareInviteLink() {
    final existing = _shareInviteLinkCompleter;
    if (existing != null && !existing.isCompleted) {
      return existing.future;
    }

    final completer = Completer<String?>();
    _shareInviteLinkCompleter = completer;
    _network.send({'type': 'create_share_invite_link'});

    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        if (identical(_shareInviteLinkCompleter, completer)) {
          _shareInviteLinkCompleter = null;
        }
        throw TimeoutException('Timed out while creating share invite link');
      },
    );
  }

  // DM / Search actions
  void searchUsersAction(String query) {
    _network.send({'type': 'search_users', 'query': query});
  }

  void sendDm(String nickname, String message) {
    _network.send({
      'type': 'send_dm',
      'nickname': nickname,
      'message': message,
    });
  }

  void setActiveDmPartner(String? nickname) {
    _activeDmPartner = nickname;
  }

  void requestDmHistory(String nickname, {int? beforeId}) {
    final msg = <String, dynamic>{
      'type': 'get_dm_history',
      'nickname': nickname,
    };
    if (beforeId != null) msg['beforeId'] = beforeId;
    _network.send(msg);
  }

  void markDmReadAction(String nickname) {
    _network.send({'type': 'mark_dm_read', 'nickname': nickname});
  }

  void requestDmConversations() {
    _network.send({'type': 'get_dm_conversations'});
  }

  void requestUnreadDmCount() {
    _network.send({'type': 'get_unread_dm_count'});
  }

  void clearSearchResults() {
    searchResults = [];
    notifyListeners();
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

  bool get hasRoomInvites => roomInvites.isNotEmpty;

  Map<String, dynamic>? get firstRoomInvite {
    if (roomInvites.isEmpty) return null;
    return roomInvites.first;
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

  void requestInquiries() {
    inquiriesLoading = true;
    inquiriesError = null;
    notifyListeners();
    _network.send({'type': 'get_inquiries'});
  }

  void requestNotices({bool markReadOnReceive = false}) {
    if (markReadOnReceive) _pendingNoticeMarkRead = true;
    noticesLoading = true;
    noticesError = null;
    notifyListeners();
    _network.send({'type': 'get_notices'});
  }

  /// Load the persisted set of read notice IDs from SharedPreferences.
  Future<void> _loadReadNoticeIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_readNoticesPrefsKey) ?? const [];
      _readNoticeIds.addAll(list.map(int.tryParse).whereType<int>());
      if (_disposed) return;
      notifyListeners();
    } catch (_) {
      // Best-effort; ignore prefs errors.
    }
  }

  /// Mark every currently-known notice as read and persist the set.
  void markCurrentNoticesAsRead() {
    bool changed = false;
    for (final n in notices) {
      final id = n['id'];
      if (id is int && _readNoticeIds.add(id)) changed = true;
    }
    if (changed) {
      notifyListeners();
      _saveReadNoticeIds();
    }
  }

  Future<void> _saveReadNoticeIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _readNoticesPrefsKey,
        _readNoticeIds.map((i) => i.toString()).toList(),
      );
    } catch (_) {
      // Best-effort; ignore prefs errors.
    }
  }

  // Send FCM token to server asynchronously after login
  Future<void> _sendFcmTokenAsync() async {
    try {
      final messaging = FirebaseMessaging.instance;
      debugPrint(
        '[FCM] Starting token fetch (platform: ${Platform.operatingSystem})',
      );

      // iOS: wait for APNs token first
      if (Platform.isIOS) {
        String? apns;
        for (int i = 0; i < 30; i++) {
          if (_disposed) return;
          apns = await messaging.getAPNSToken();
          debugPrint('[FCM] APNs attempt $i: ${apns != null ? "OK" : "null"}');
          if (apns != null) break;
          await Future.delayed(const Duration(milliseconds: 1000));
        }
        if (apns == null) {
          debugPrint('[FCM] APNs token never arrived after 30 attempts');
        }
      }

      debugPrint('[FCM] Calling getToken()...');
      final token = await messaging.getToken().timeout(
        const Duration(seconds: 15),
      );
      final preview = token != null
          ? token.substring(0, token.length.clamp(0, 20))
          : 'null';
      debugPrint('[FCM] Token result: $preview...');

      if (token != null && playerId.isNotEmpty) {
        _network.send({'type': 'update_fcm_token', 'fcmToken': token});
        debugPrint('[FCM] Token sent to server');
      }
    } catch (e) {
      debugPrint('[FCM] Failed to get token: $e');
    }
  }

  Future<void> _loadPushPrefs() async {
    final loadVersion = ++_pushPrefsLoadVersion;
    final prefs = await SharedPreferences.getInstance();
    if (loadVersion != _pushPrefsLoadVersion || _disposed) return;
    pushEnabled = prefs.getBool('push_enabled') ?? true;
    pushFriendInviteEnabled = prefs.getBool('push_friend_invite') ?? true;
    notifyListeners();
  }

  Future<void> _savePushPrefs() async {
    _pushPrefsLoadVersion++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('push_enabled', pushEnabled);
    await prefs.setBool('push_friend_invite', pushFriendInviteEnabled);
  }

  Future<void> setPushEnabled(bool enabled) async {
    pushEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('push_enabled', enabled);

    _pushToggleTimer?.cancel();
    _pushToggleTimer = Timer(const Duration(milliseconds: 200), () async {
      if (_disposed) return;
      if (playerId.isNotEmpty) {
        _network.send({
          'type': 'update_push_setting',
          'enabled': enabled,
          'friendInvite': pushFriendInviteEnabled,
        });
      }
    });
    notifyListeners();
  }

  Future<void> setPushFriendInviteEnabled(bool enabled) async {
    pushFriendInviteEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('push_friend_invite', enabled);
    if (playerId.isNotEmpty) {
      _network.send({
        'type': 'update_push_setting',
        'enabled': pushEnabled,
        'friendInvite': enabled,
      });
    }
    notifyListeners();
  }

  void _maybeShowInquiryBanner() {
    for (final item in inquiries) {
      final id = (item['id'] is int)
          ? item['id'] as int
          : int.tryParse('${item['id']}') ?? -1;
      final status = item['status']?.toString() ?? '';
      final adminNote = item['admin_note']?.toString() ?? '';
      final userRead = item['user_read'] == true;
      if (id <= 0) continue;
      if (status == 'resolved' && adminNote.isNotEmpty && !userRead) {
        final title = item['title']?.toString() ?? '';
        inquiryBannerMessage = 'inquiry_reply:$title';
        _inquiryBannerTimer?.cancel();
        _inquiryBannerTimer = Timer(const Duration(seconds: 4), () {
          if (_disposed) return;
          inquiryBannerMessage = null;
          notifyListeners();
        });
        return;
      }
    }
  }

  void markInquiriesRead() {
    inquiriesLoading = true;
    inquiriesError = null;
    notifyListeners();
    _network.send({'type': 'mark_inquiries_read'});
    // Also update local state immediately so banner disappears
    for (final item in inquiries) {
      if (item['status'] == 'resolved') {
        item['user_read'] = true;
      }
    }
    inquiryBannerMessage = null;
  }

  @override
  void dispose() {
    _disposed = true; // C2: Mark as disposed
    if (_shareInviteLinkCompleter != null &&
        !_shareInviteLinkCompleter!.isCompleted) {
      _shareInviteLinkCompleter!.completeError(
        StateError('GameService disposed'),
      );
    }
    _shareInviteLinkCompleter = null;
    _subscription?.cancel();
    _fcmTokenSubscription?.cancel();
    _dogDelayTimer?.cancel();
    _dogClearTimer?.cancel();
    _inquiryBannerTimer?.cancel();
    _pushToggleTimer?.cancel();
    super.dispose();
  }
}
